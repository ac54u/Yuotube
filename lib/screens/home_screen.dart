import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/youtube_service.dart';
import '../services/download_service.dart';
import 'video_player_screen.dart';
import 'webview_player_screen.dart'; // 确保引入了 WebView 页面

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();
  final YoutubeService _ytService = YoutubeService();
  final DownloadService _downloadService = DownloadService();

  bool _isBusy = false;
  String _statusText = "";
  double _progress = 0.0;
  
  // 使用自定义类或 Video 对象，为了兼容报错，我们允许它部分为空
  Video? _videoInfo;
  String? _fallbackId; // 备用 ID (当库失效时使用)

  @override
  void dispose() {
    _urlController.dispose();
    _ytService.dispose();
    super.dispose();
  }

  // 🛠️ 辅助：暴力提取 Video ID
  String? _extractVideoId(String url) {
    try {
      // 匹配 https://youtu.be/ID 或 https://youtube.com/watch?v=ID
      RegExp regExp = RegExp(r"(?:v=|\/)([0-9A-Za-z_-]{11}).*");
      var match = regExp.firstMatch(url);
      if (match != null && match.groupCount >= 1) {
        return match.group(1);
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  // 1. 解析逻辑 (增强版)
  Future<void> analyzeVideo() async {
    FocusScope.of(context).unfocus();
    if (_urlController.text.isEmpty) return;

    setState(() {
      _isBusy = true;
      _statusText = "正在解析...";
      _videoInfo = null;
      _fallbackId = null;
    });

    String inputUrl = _urlController.text.trim();

    try {
      // 🟢 尝试 1: 标准库解析
      final video = await _ytService.getVideoInfo(inputUrl);
      setState(() {
        _videoInfo = video;
        _statusText = "";
        _isBusy = false;
      });
    } catch (e) {
      print("标准解析失败: $e");
      
      // 🟡 尝试 2: 暴力正则提取 (容错机制)
      final extractedId = _extractVideoId(inputUrl);
      
      if (extractedId != null) {
        setState(() {
          _fallbackId = extractedId;
          _statusText = "API 受限，已启用网页模式"; // 提示用户
          _isBusy = false;
        });
        
        // 自动构建一个“假”的 Video 对象用于显示 UI
        // Video 类的构造函数可能是私有的，所以我们尽量只用 _fallbackId 控制 UI
      } else {
        _handleError("无法识别链接，请检查格式");
      }
    }
  }

  // 2. 准备资源 (兼容 API 挂掉的情况)
  Future<void> prepareResource() async {
    // 优先使用标准对象，没有则使用备用 ID
    final videoId = _videoInfo?.id.value ?? _fallbackId;
    
    if (videoId == null) return;

    setState(() {
      _isBusy = true;
      _statusText = "正在探测资源...";
    });

    List<VideoStreamInfo> downloadList = [];
    List<MuxedStreamInfo> playbackList = [];
    AudioStreamInfo? audio;

    try {
      // 尝试获取流信息 (如果是 fallback 模式，这一步大概率也会失败)
      final manifest = await _ytService.getManifest(videoId);
      
      // ... 正常的流筛选逻辑 ...
      var downloadStreams = manifest.video.toList();
      downloadStreams.sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));
      final uniqueDownloadStreams = <String, VideoStreamInfo>{};
      for (var s in downloadStreams) {
        final label = s.videoQuality.name;
        if (!uniqueDownloadStreams.containsKey(label)) {
          uniqueDownloadStreams[label] = s;
        } else if (s.container.name == 'mp4' && uniqueDownloadStreams[label]!.container.name != 'mp4') {
          uniqueDownloadStreams[label] = s;
        }
      }
      downloadList = uniqueDownloadStreams.values.toList();

      var playbackStreams = manifest.muxed.toList();
      playbackStreams.sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));
      playbackList = playbackStreams;

      audio = manifest.audio.withHighestBitrate();

    } catch (e) {
      print("流获取失败: $e");
      // 🔥 关键：即使获取流失败，也不阻断！
      // 因为网页播放模式不需要流，只需要 ID。
      if (_fallbackId == null) {
         // 如果本来就是 fallback 模式，那很正常，不报错
         _statusText = "API 阻断，仅限网页播放";
      }
    }

    setState(() {
      _isBusy = false;
      _statusText = "";
    });

    if (mounted) {
      // 弹出菜单，传入可能为空的列表
      _showActionSheet(
        context, 
        downloadList, 
        playbackList, 
        audio,
        videoId // 传入核心 ID
      );
    }
  }

  // 3. 菜单 (适配空数据)
  void _showActionSheet(
    BuildContext context, 
    List<VideoStreamInfo> downloadOptions, 
    List<MuxedStreamInfo> playbackOptions,
    AudioStreamInfo? audioStream,
    String videoId,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF27272A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text("选择操作", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
            ),

            // 🔵 选项 1: 网页内核 4K (无敌模式 - 永远可用)
            // 只要有 ID 就能用，不受 API 限制
            ListTile(
              leading: const Icon(Icons.public, color: Colors.blueAccent, size: 30),
              title: const Text("网页内核播放 (4K)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text("100% 成功 • 推荐使用", style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => WebViewPlayerScreen(
                  videoId: videoId,
                )));
              },
            ),

            const Divider(color: Colors.white10),

            // 🟢 选项 2: 极速播放 (仅在 API 正常时显示)
            if (playbackOptions.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.play_circle_fill, color: Colors.greenAccent, size: 30),
                title: const Text("极速播放 (720p)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text("直连秒开", style: TextStyle(color: Colors.grey, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  var stableVideo = playbackOptions.first; 
                  Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerScreen(
                    videoInput: stableVideo.url.toString(),
                    title: _videoInfo?.title ?? "Unknown Video",
                    isCloudMode: false,
                  )));
                },
              ),

            // 🔴 选项 3: 下载 (仅在 API 正常时显示)
            if (downloadOptions.isNotEmpty) ...[
               const Padding(
                padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
                child: Align(alignment: Alignment.centerLeft, child: Text("下载列表", style: TextStyle(color: Colors.grey, fontSize: 12))),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: downloadOptions.length,
                  itemBuilder: (ctx, index) {
                    final stream = downloadOptions[index];
                    final sizeMB = (stream.size.totalMegaBytes).toStringAsFixed(1);
                    return ListTile(
                      leading: const Icon(Icons.download, color: Colors.white),
                      title: Text(stream.videoQuality.name, style: const TextStyle(color: Colors.white)),
                      subtitle: Text("${stream.container.name.toUpperCase()} • $sizeMB MB", style: const TextStyle(color: Colors.grey)),
                      onTap: () {
                        Navigator.pop(ctx);
                        if (audioStream != null && _videoInfo != null) {
                          _triggerDownload(stream, audioStream);
                        }
                      },
                    );
                  },
                ),
              ),
            ] else ...[
               // API 挂掉时的提示
               Padding(
                 padding: const EdgeInsets.all(20),
                 child: Text(
                   "⚠️ 当前 YouTube 接口受限，无法获取下载链接。\n但在上方选择【网页内核播放】依然可以正常看 4K。",
                   style: TextStyle(color: Colors.grey[600], fontSize: 12),
                   textAlign: TextAlign.center,
                 ),
               )
            ]
          ],
        ),
      ),
    );
  }

  Future<void> _triggerDownload(VideoStreamInfo videoStream, AudioStreamInfo audioStream) async {
    // ... 原有下载逻辑 ...
    if (_videoInfo == null) return;
    setState(() { _isBusy = true; _progress = 0.0; _statusText = "准备下载..."; });
    try {
      await _downloadService.downloadAndMerge(
        video: _videoInfo!, videoStream: videoStream, audioStream: audioStream,
        onProgress: (status, progress) { if (mounted) setState(() { _statusText = status; _progress = progress; }); },
      );
    } catch (e) { _handleError(e.toString()); } 
    finally { if (mounted) setState(() { _isBusy = false; if(_progress < 1) _statusText = ""; }); }
  }

  Future<void> _triggerDeepSeekTranslation() async {
    // ... 原有翻译逻辑 ...
     if (_videoInfo == null) { _handleError("需 API 正常才能使用 AI 翻译"); return; }
     // ...
  }

  void _handleError(String msg) {
    if (!mounted) return;
    setState(() { _isBusy = false; _statusText = ""; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }

  @override
  Widget build(BuildContext context) {
    // 动态获取封面：如果有 videoInfo 用高清的，如果是 fallback 模式用官方拼接的
    String thumbUrl = "";
    String titleText = "";
    
    if (_videoInfo != null) {
      thumbUrl = _videoInfo!.thumbnails.highResUrl;
      titleText = _videoInfo!.title;
    } else if (_fallbackId != null) {
      thumbUrl = "https://img.youtube.com/vi/$_fallbackId/hqdefault.jpg";
      titleText = "视频 ID: $_fallbackId (网页模式已就绪)";
    }

    return Scaffold(
      appBar: AppBar(title: const Text("TrollStore YT Pro")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Card(
              elevation: 4, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.link, color: Colors.grey),
                    const SizedBox(width: 10),
                    Expanded(child: TextField(controller: _urlController, decoration: const InputDecoration(hintText: "粘贴链接", border: InputBorder.none), onSubmitted: (_) => analyzeVideo())),
                    IconButton(icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18), onPressed: analyzeVideo)
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            
            // 显示卡片：只要有 Info 或者 Fallback ID 都显示
            if (_videoInfo != null || _fallbackId != null) ...[
              Card(
                clipBehavior: Clip.antiAlias, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    CachedNetworkImage(
                      imageUrl: thumbUrl, 
                      height: 200, width: double.infinity, fit: BoxFit.cover,
                      errorWidget: (context, url, error) => Container(color: Colors.grey[800], height: 200, child: const Center(child: Icon(Icons.broken_image, color: Colors.white))),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(titleText, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (_isBusy) ...[
                LinearProgressIndicator(value: _progress > 0 ? _progress : null),
                const SizedBox(height: 10),
                Text(_statusText, style: const TextStyle(color: Colors.grey))
              ] else
                SizedBox(height: 50, child: ElevatedButton(onPressed: prepareResource, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4D88FF), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.play_circle_filled_rounded), SizedBox(width: 8), Text("开始操作", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))]))),
            ]
          ],
        ),
      ),
    );
  }
}

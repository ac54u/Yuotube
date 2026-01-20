import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/youtube_service.dart';
import '../services/download_service.dart';
import 'video_player_screen.dart';

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
  Video? _videoInfo;

  @override
  void dispose() {
    _urlController.dispose();
    _ytService.dispose();
    super.dispose();
  }

  Future<void> analyzeVideo() async {
    FocusScope.of(context).unfocus();
    if (_urlController.text.isEmpty) return;

    setState(() {
      _isBusy = true;
      _statusText = "正在解析元数据...";
      _videoInfo = null;
    });

    try {
      final video = await _ytService.getVideoInfo(_urlController.text);
      setState(() {
        _videoInfo = video;
        _statusText = "";
        _isBusy = false;
      });
    } catch (e) {
      _handleError("解析失败: $e");
    }
  }

  Future<void> prepareResource() async {
    if (_videoInfo == null) return;

    setState(() {
      _isBusy = true;
      _statusText = "正在获取资源...";
    });

    try {
      final manifest = await _ytService.getManifest(_videoInfo!.id.value);
      
      // 筛选下载用的流
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

      // 筛选在线播放流 (720p)
      var playbackStreams = manifest.muxed.toList();
      playbackStreams.sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));

      var audioStream = manifest.audio.withHighestBitrate();

      setState(() {
        _isBusy = false;
        _statusText = "";
      });

      if (mounted) {
        _showActionSheet(
          context, 
          uniqueDownloadStreams.values.toList(), 
          playbackStreams, 
          audioStream
        );
      }
    } catch (e) {
      _handleError("资源获取失败: $e");
    }
  }

  void _showActionSheet(
    BuildContext context, 
    List<VideoStreamInfo> downloadOptions, 
    List<MuxedStreamInfo> playbackOptions,
    AudioStreamInfo audioStream,
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

            // 🟢 选项 1: 极速播放 (直连 720p)
            ListTile(
              leading: const Icon(Icons.play_circle_fill, color: Colors.greenAccent, size: 30),
              title: const Text("极速播放 (720p)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text("直连 YouTube • 秒开", style: TextStyle(color: Colors.grey, fontSize: 12)),
              onTap: () {
                Navigator.pop(ctx);
                if (playbackOptions.isNotEmpty) {
                  var stableVideo = playbackOptions.first; 
                  Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerScreen(
                    videoInput: stableVideo.url.toString(), // 传入 URL
                    title: _videoInfo!.title,
                    isCloudMode: false, // 普通模式
                  )));
                }
              },
            ),

            // ☁️ 选项 2: 云端 4K 影院 (服务器转码)
            ListTile(
              leading: const Icon(Icons.cloud_circle, color: Colors.amber, size: 30),
              title: const Text("云端 4K 影院 (推荐)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text("私有服务器转码 • 满速 4K • 不卡顿", style: TextStyle(color: Colors.grey, fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
              onTap: () {
                Navigator.pop(ctx);
                // 🔥 关键修改：传入 Video ID，而不是 URL
                // 这样播放器就知道去请求你的服务器了
                Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerScreen(
                  videoInput: _videoInfo!.id.value, // 传入 ID (例如 dQw4w9WgXcQ)
                  title: _videoInfo!.title,
                  isCloudMode: true, // 开启云端模式
                )));
              },
            ),

            // 🔵 选项 3: DeepSeek 翻译
            ListTile(
              leading: const Icon(Icons.auto_awesome, color: Color(0xFF4D88FF), size: 24),
              title: const Text("DeepSeek 字幕翻译", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text("AI 语境翻译", style: TextStyle(color: Colors.grey, fontSize: 12)),
              onTap: () async {
                Navigator.pop(ctx);
                _triggerDeepSeekTranslation();
              },
            ),

            const Divider(color: Colors.white10),
            
            // 🔴 下载列表
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text("下载到相册", style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: downloadOptions.length,
                itemBuilder: (ctx, index) {
                  final stream = downloadOptions[index];
                  final sizeMB = (stream.size.totalMegaBytes).toStringAsFixed(1);
                  final is4K = stream.videoQuality.name.contains('2160') || stream.videoResolution.height >= 2160;

                  return ListTile(
                    leading: Icon(Icons.download, color: is4K ? Colors.purpleAccent : Colors.red),
                    title: Text(stream.videoQuality.name, style: const TextStyle(color: Colors.white)),
                    subtitle: Text("${stream.container.name.toUpperCase()} • $sizeMB MB", style: const TextStyle(color: Colors.grey)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _triggerDownload(stream, audioStream);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _triggerDownload(VideoStreamInfo videoStream, AudioStreamInfo audioStream) async {
    setState(() { _isBusy = true; _progress = 0.0; _statusText = "准备下载..."; });
    try {
      await _downloadService.downloadAndMerge(
        video: _videoInfo!,
        videoStream: videoStream,
        audioStream: audioStream,
        onProgress: (status, progress) {
          if (mounted) setState(() { _statusText = status; _progress = progress; });
        },
      );
    } catch (e) { _handleError(e.toString()); } 
    finally { if (mounted) setState(() { _isBusy = false; if(_progress < 1) _statusText = ""; }); }
  }

  Future<void> _triggerDeepSeekTranslation() async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('deepseek_key');
    if (apiKey == null || apiKey.isEmpty) { _handleError("请设置 API Key"); return; }
    setState(() { _isBusy = true; _progress = 0.0; _statusText = "准备翻译..."; });
    try {
      await _downloadService.exportDeepSeekSubtitle(
        video: _videoInfo!, apiKey: apiKey,
        onProgress: (status, progress) { if (mounted) setState(() { _statusText = status; _progress = progress; }); }
      );
    } catch (e) { _handleError(e.toString()); }
    finally { if (mounted) setState(() { _isBusy = false; if(_progress < 1) _statusText = ""; }); }
  }

  void _handleError(String msg) {
    if (!mounted) return;
    setState(() { _isBusy = false; _statusText = ""; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }

  @override
  Widget build(BuildContext context) {
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
            if (_videoInfo != null) ...[
              Card(
                clipBehavior: Clip.antiAlias, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    CachedNetworkImage(imageUrl: _videoInfo!.thumbnails.highResUrl, height: 200, width: double.infinity, fit: BoxFit.cover),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(_videoInfo!.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 2),
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

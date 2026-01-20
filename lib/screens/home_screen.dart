import 'package:flutter/material.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 引入我们拆分出去的模块
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
  
  // 实例化服务
  final YoutubeService _ytService = YoutubeService();
  final DownloadService _downloadService = DownloadService();

  // 状态变量
  bool _isBusy = false; // 是否正在忙碌 (下载/解析中)
  String _statusText = "";
  double _progress = 0.0;
  Video? _videoInfo; // 存储当前解析出的视频信息

  @override
  void dispose() {
    _urlController.dispose();
    _ytService.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 1. 解析视频逻辑
  // ---------------------------------------------------------------------------
  Future<void> analyzeVideo() async {
    FocusScope.of(context).unfocus(); // 收起键盘
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

  // ---------------------------------------------------------------------------
  // 2. 准备资源 (点击大按钮后触发)
  // ---------------------------------------------------------------------------
  Future<void> prepareResource() async {
    if (_videoInfo == null) return;

    setState(() {
      _isBusy = true;
      _statusText = "正在获取流媒体清单...";
    });

    try {
      // 🔥 核心修复点：使用 .value 获取字符串类型的 ID
      final manifest = await _ytService.getManifest(_videoInfo!.id.value);
      
      // A. 筛选下载用的流 (音画分离，画质从高到低)
      var downloadStreams = manifest.video.toList();
      downloadStreams.sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));
      
      // 去重逻辑：同分辨率下优先 MP4
      final uniqueDownloadStreams = <String, VideoStreamInfo>{};
      for (var s in downloadStreams) {
        final label = s.videoQuality.name;
        if (!uniqueDownloadStreams.containsKey(label)) {
          uniqueDownloadStreams[label] = s;
        } else if (s.container.name == 'mp4' && uniqueDownloadStreams[label]!.container.name != 'mp4') {
          uniqueDownloadStreams[label] = s;
        }
      }

      // B. 筛选在线播放用的流 (Muxed 混合流，画质从高到低)
      var playbackStreams = manifest.muxed.toList();
      playbackStreams.sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));

      // C. 获取最佳音频流 (用于 4K 合成)
      var audioStream = manifest.audio.withHighestBitrate();

      setState(() {
        _isBusy = false;
        _statusText = "";
      });

      if (mounted) {
        // 弹出底部菜单
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

  // ---------------------------------------------------------------------------
  // 3. 底部菜单 UI
  // ---------------------------------------------------------------------------
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

            // 🟢 在线播放入口
            ListTile(
              leading: const Icon(Icons.play_circle_fill, color: Colors.greenAccent, size: 30),
              title: const Text("在线播放", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text("MediaKit 内核 • 支持 4K 音画分离", style: TextStyle(color: Colors.grey, fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
              onTap: () {
                Navigator.pop(ctx);
                if (downloadOptions.isEmpty) { // 注意：MediaKit 可以播放分离流，所以我们用 downloadOptions 判断
                   _handleError("该视频无法播放");
                } else {
                  // 取最高画质的分离流进行播放
                  var bestVideo = downloadOptions.first; 
                  Navigator.push(context, MaterialPageRoute(builder: (_) => VideoPlayerScreen(
                    videoUrl: bestVideo.url.toString(),
                    audioUrl: audioStream.url.toString(), // 传入音频流，实现 4K 播放
                    title: _videoInfo!.title,
                  )));
                }
              },
            ),

            // 🔵 DeepSeek 字幕翻译入口
            ListTile(
              leading: const Icon(Icons.auto_awesome, color: Color(0xFF4D88FF), size: 24),
              title: const Text("DeepSeek 字幕翻译", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: const Text("AI 语境翻译 • 导出 SRT", style: TextStyle(color: Colors.grey, fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
              onTap: () async {
                Navigator.pop(ctx);
                _triggerDeepSeekTranslation();
              },
            ),

            const Divider(color: Colors.white10),
            
            const Padding(
              padding: EdgeInsets.only(left: 16, top: 8, bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text("下载到相册 (硬件加速)", style: TextStyle(color: Colors.grey, fontSize: 12)),
              ),
            ),

            // 🔴 下载列表
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
                    subtitle: Text("${stream.container.name.toUpperCase()} • 约 $sizeMB MB", style: const TextStyle(color: Colors.grey)),
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

  // ---------------------------------------------------------------------------
  // 4. 触发下载逻辑
  // ---------------------------------------------------------------------------
  Future<void> _triggerDownload(VideoStreamInfo videoStream, AudioStreamInfo audioStream) async {
    setState(() {
      _isBusy = true;
      _progress = 0.0;
      _statusText = "准备下载...";
    });

    try {
      // 调用 Service
      await _downloadService.downloadAndMerge(
        video: _videoInfo!,
        videoStream: videoStream,
        audioStream: audioStream,
        onProgress: (status, progress) {
          if (mounted) {
            setState(() {
              _statusText = status;
              _progress = progress;
            });
          }
        },
      );
    } catch (e) {
      _handleError(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          // 如果成功，文字会停留在 "✅ 下载完成"
          if (_progress < 1.0) _statusText = ""; 
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 5. 触发 DeepSeek 翻译逻辑
  // ---------------------------------------------------------------------------
  Future<void> _triggerDeepSeekTranslation() async {
    // 获取 Key
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('deepseek_key');
    
    if (apiKey == null || apiKey.isEmpty) {
      _handleError("请先去个人中心设置 DeepSeek API Key");
      return;
    }

    setState(() {
      _isBusy = true;
      _progress = 0.0;
      _statusText = "准备 AI 翻译...";
    });

    try {
      await _downloadService.exportDeepSeekSubtitle(
        video: _videoInfo!,
        apiKey: apiKey,
        onProgress: (status, progress) {
          if (mounted) {
            setState(() {
              _statusText = status;
              _progress = progress;
            });
          }
        },
      );
    } catch (e) {
      _handleError(e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
          if (_progress < 1.0) _statusText = "";
        });
      }
    }
  }

  // 错误处理辅助函数
  void _handleError(String msg) {
    if (!mounted) return;
    setState(() {
      _isBusy = false;
      _statusText = "";
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("TrollStore YT Pro")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 输入卡片
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.link, color: Colors.grey),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _urlController,
                        decoration: const InputDecoration(hintText: "粘贴 YouTube 链接", border: InputBorder.none),
                        onSubmitted: (_) => analyzeVideo(),
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.arrow_forward_ios_rounded, size: 18), onPressed: analyzeVideo)
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // 视频信息卡片
            if (_videoInfo != null) ...[
              Card(
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  children: [
                    CachedNetworkImage(
                      imageUrl: _videoInfo!.thumbnails.highResUrl,
                      height: 200, width: double.infinity, fit: BoxFit.cover,
                      placeholder: (_,__) => Container(color: Colors.grey[800], height: 200),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_videoInfo!.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.timer, size: 14, color: Colors.grey),
                              Text(" ${_videoInfo!.duration?.inMinutes ?? 0} 分钟", style: const TextStyle(color: Colors.grey)),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFF4D88FF), borderRadius: BorderRadius.circular(4)),
                                child: const Text("Ready", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                              )
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // 主操作按钮
              if (_isBusy) ...[
                Column(
                  children: [
                    LinearProgressIndicator(value: _progress > 0 ? _progress : null, minHeight: 8, borderRadius: BorderRadius.circular(4), color: const Color(0xFF4D88FF)),
                    const SizedBox(height: 10),
                    Text(_statusText, style: const TextStyle(color: Colors.grey))
                  ],
                )
              ] else
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: prepareResource,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4D88FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 4,
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.play_circle_filled_rounded),
                        SizedBox(width: 8),
                        Text("播放 / 下载 / 翻译", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
            ] else ...[
               Center(child: Column(children: [const SizedBox(height: 40), Icon(Icons.ondemand_video, size: 80, color: Colors.grey.withOpacity(0.3)), const SizedBox(height: 10), Text("MediaKit 4K 播放 • DeepSeek 翻译", style: TextStyle(color: Colors.grey.withOpacity(0.5)))]))
            ]
          ],
        ),
      ),
    );
  }
}

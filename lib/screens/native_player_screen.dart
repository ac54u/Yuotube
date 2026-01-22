import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// 使用别名解决命名冲突
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class NativePlayerScreen extends StatefulWidget {
  final String videoId;
  const NativePlayerScreen({super.key, required this.videoId});

  @override
  State<NativePlayerScreen> createState() => _NativePlayerScreenState();
}

class _NativePlayerScreenState extends State<NativePlayerScreen> {
  late final Player player;
  late final VideoController controller;

  bool _isLoading = true;
  String _statusText = "初始化引擎...";
  String _debugInfo = "";
  
  // 🔥 核心策略：全程伪装成 iPhone (iOS 17)
  // 必须与 YouTube 的 c=IOS 参数配合，否则 403
  final String _userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1";

  @override
  void initState() {
    super.initState();
    // 强制横屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _initPlayer();
  }

  Future<void> _initPlayer() async {
    player = Player();
    controller = VideoController(player, configuration: const VideoControllerConfiguration(enableHardwareAcceleration: true));

    try {
      await _loadVideoSource();
    } catch (e) {
      if (mounted) setState(() => _statusText = "解析中断: $e");
    }
  }

  Future<void> _loadVideoSource() async {
    setState(() => _statusText = "正在解析 4K 资源...");
    
    // 初始化解析器
    var explode = yt.YoutubeExplode();
    
    try {
      // 1. 获取视频流清单
      // 如果这里报错 VideoUnavailable，说明是库版本旧了，请务必执行 pubspec.yaml 的 git 升级
      var manifest = await explode.videos.streamsClient.getManifest(widget.videoId);
      
      // 2. 筛选 4K 视频流
      var videoStreams = manifest.video.toList();
      // 优先找高分辨率
      videoStreams.sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));
      var bestVideo = videoStreams.first;
      
      // 3. 筛选最高音质
      var audioStreams = manifest.audio.toList();
      audioStreams.sort((a, b) => b.bitrate.compareTo(a.bitrate));
      var bestAudio = audioStreams.first;

      final videoUrl = bestVideo.url.toString();
      final audioUrl = bestAudio.url.toString();
      
      final kbps = (bestAudio.bitrate.bitsPerSecond / 1000).ceil();

      if (mounted) {
        setState(() {
          _debugInfo = "画质: ${bestVideo.videoQuality} (${bestVideo.videoResolution})\n"
                       "编码: ${bestVideo.codec}\n"
                       "音质: ${kbps} kbps\n"
                       "状态: 正在建立 iOS 安全通道..."; 
          _statusText = "缓冲中...";
        });
      }

      // 🔥 4. 播放器配置：Header 注入
      await player.open(
        Media(
          videoUrl,
          extras: {
            'audio-file': audioUrl,
            
            // 告诉 MPV 我们是 iPhone
            'user-agent': _userAgent,
            
            // 这里的 Referer 也很重要
            'http-header-fields': [
              'User-Agent: $_userAgent',
              'Referer: https://www.youtube.com/',
              'Origin: https://www.youtube.com'
            ].join(','),
            
            'demuxer-max-bytes': '64MiB', 
            'network-timeout': '30',
            'hwdec': 'auto', 
          },
        ),
        play: true,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _debugInfo += "\n✅ 通道已建立";
        });
      }

    } catch (e) {
      // 捕获那个 VideoUnavailableException 错误并显示出来
      if (mounted) {
        setState(() {
          _statusText = "错误: ${e.toString().split('\n').first}"; // 只显示第一行错误
        });
      }
      print("详细错误: $e");
    } finally {
      explode.close();
    }
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        alignment: Alignment.center,
        children: [
          Video(controller: controller),
          
          if (_isLoading)
            Container(
              color: Colors.black87,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Colors.blueAccent),
                    const SizedBox(height: 20),
                    Text(
                      _statusText, 
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),

          Positioned(
            top: 20,
            left: 20,
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.white, shadows: [Shadow(blurRadius: 10, color: Colors.black)]),
                    onPressed: () => Navigator.pop(context),
                  ),
                  GestureDetector(
                    onTap: () {},
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                      child: Text(_debugInfo, style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
  
  // 🔥 关键：定义一个与之前伪装一致的 UserAgent
  final String _userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15";

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _initPlayer();
  }

  Future<void> _initPlayer() async {
    // 配置 MPV 底层参数
    // 🔥 修复：移除了不支持的 iosAudioSessionCategory 参数
    player = Player();
    
    controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true, // 开启硬解
      ),
    );

    try {
      await _loadVideoSource();
    } catch (e) {
      if (mounted) setState(() => _statusText = "解析失败: $e");
    }
  }

  Future<void> _loadVideoSource() async {
    setState(() => _statusText = "正在解析 4K 资源...");
    
    var explode = yt.YoutubeExplode();
    try {
      var manifest = await explode.videos.streamsClient.getManifest(widget.videoId);
      
      // 1. 找 4K 视频流
      var videoStreams = manifest.video.toList();
      videoStreams.sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));
      var bestVideo = videoStreams.first;
      
      // 2. 找最高音质
      var audioStreams = manifest.audio.toList();
      audioStreams.sort((a, b) => b.bitrate.compareTo(a.bitrate));
      var bestAudio = audioStreams.first;

      final videoUrl = bestVideo.url.toString();
      final audioUrl = bestAudio.url.toString();
      
      // 计算码率用于显示
      final kbps = (bestAudio.bitrate.bitsPerSecond / 1000).ceil();

      if (mounted) {
        setState(() {
          _debugInfo = "画质: ${bestVideo.videoQuality} (${bestVideo.videoResolution})\n"
                       "编码: ${bestVideo.codec}\n"
                       "音质: ${kbps} kbps\n"
                       "状态: 正在请求视频流..."; 
          _statusText = "缓冲中...";
        });
      }

      // 🔥 3. 核心修复：带 Headers 播放
      // 如果不带 UA，YouTube 会返回 403 Forbidden，导致一直转圈
      await player.open(
        Media(
          videoUrl,
          extras: {
            // 加载外部音轨
            'audio-file': audioUrl,
            
            // 伪装浏览器身份 (关键！)
            'user-agent': _userAgent,
            'http-header-fields': 'Referer: https://www.youtube.com/',
            
            // 性能优化参数
            'demuxer-max-bytes': '32MiB', // 增大缓冲区
            'network-timeout': '15', // 超时设定
            'hwdec': 'auto', // 强制尝试硬解
          },
        ),
        play: true,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _debugInfo += "\n✅ 连接成功";
        });
      }

    } catch (e) {
      if (mounted) setState(() => _statusText = "错误: $e");
      rethrow;
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
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.blueAccent),
                  const SizedBox(height: 20),
                  Text(_statusText, style: const TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 10),
                  const Text("首次加载 4K 可能需要较长时间", style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
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
                  // 点击显示/隐藏调试信息
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

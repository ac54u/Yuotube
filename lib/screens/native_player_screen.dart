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
  
  // 🔥 核心修正：使用你抓包中验证通过的 Windows Chrome UA
  // 这个身份是 YouTube 最信任的，4K 也就是它给的
  final String _userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36";

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
      
      final kbps = (bestAudio.bitrate.bitsPerSecond / 1000).ceil();

      if (mounted) {
        setState(() {
          _debugInfo = "画质: ${bestVideo.videoQuality} (${bestVideo.videoResolution})\n"
                       "编码: ${bestVideo.codec}\n"
                       "音质: ${kbps} kbps\n"
                       "状态: 正在建立加密连接..."; 
          _statusText = "缓冲中...";
        });
      }

      // 🔥 3. 绝杀：暴力修改 HTTP Headers
      // MPV 默认会用 "libmpv" 做 UA，这会被 YouTube 屏蔽。
      // 我们通过 http-header-fields 强制覆盖它。
      await player.open(
        Media(
          videoUrl,
          extras: {
            'audio-file': audioUrl,
            
            // 方法 A：标准 UA 设置
            'user-agent': _userAgent,
            
            // 方法 B：底层 Header 注入 (双重保险)
            // 这会强制替换掉所有请求头里的 User-Agent
            'http-header-fields': [
              'User-Agent: $_userAgent',
              'Referer: https://www.youtube.com/',
              'Origin: https://www.youtube.com'
            ].join(','),
            
            // 缓冲优化
            'demuxer-max-bytes': '50MiB', // 加大缓冲区到 50M
            'network-timeout': '30',
            'hwdec': 'auto',
          },
        ),
        play: true,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _debugInfo += "\n✅ 数据流已接通";
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

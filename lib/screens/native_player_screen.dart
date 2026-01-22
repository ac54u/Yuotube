import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// 🔥 1. 使用 'as yt' 解决 Video 类的命名冲突
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

  @override
  void initState() {
    super.initState();
    // 强制横屏体验
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _initPlayer();
  }

  Future<void> _initPlayer() async {
    // 创建播放器实例
    player = Player();
    controller = VideoController(player);

    try {
      await _loadVideoSource();
    } catch (e) {
      if (mounted) setState(() => _statusText = "解析失败: $e");
    }
  }

  Future<void> _loadVideoSource() async {
    setState(() => _statusText = "正在解析 4K 资源...");
    
    // 使用别名 yt 调用
    var explode = yt.YoutubeExplode();
    try {
      var manifest = await explode.videos.streamsClient.getManifest(widget.videoId);
      
      // 1. 获取视频流 (2160p/4K)
      var videoStreams = manifest.video.toList();
      videoStreams.sort((a, b) => b.videoResolution.height.compareTo(a.videoResolution.height));
      var bestVideo = videoStreams.first;
      
      // 2. 获取音频流 (最高音质)
      var audioStreams = manifest.audio.toList();
      audioStreams.sort((a, b) => b.bitrate.compareTo(a.bitrate));
      var bestAudio = audioStreams.first;

      final videoUrl = bestVideo.url.toString();
      final audioUrl = bestAudio.url.toString();

      if (mounted) {
        // 🔥 2. 修复 kbit 报错：手动计算 kbps
        final kbps = (bestAudio.bitrate.bitsPerSecond / 1000).ceil();
        
        setState(() {
          _debugInfo = "画质: ${bestVideo.videoQuality} (${bestVideo.videoResolution})\n"
                       "编码: ${bestVideo.codec}\n"
                       "音质: ${kbps} kbps (MPV合成)";
          _statusText = "缓冲中...";
        });
      }

      // 🔥 3. 修复 audios 参数报错
      // MediaKit 使用 extras 参数传递底层 MPV 指令
      // 'audio-file' 是 MPV 用来加载外部音轨的参数
      await player.open(
        Media(
          videoUrl,
          extras: {
            'audio-file': audioUrl, // 关键：告诉内核去哪里加载声音
          },
        ),
        play: true,
      );

      if (mounted) {
        setState(() => _isLoading = false);
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
    // 恢复竖屏
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
          // 4. 这里的 Video 指的是 media_kit_video 的组件，不再冲突
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
                  if (!_isLoading)
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(top: 8),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                      child: Text(_debugInfo, style: const TextStyle(color: Colors.greenAccent, fontSize: 12)),
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

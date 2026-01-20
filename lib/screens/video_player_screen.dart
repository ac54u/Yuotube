import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String? audioUrl;
  final String title;

  const VideoPlayerScreen({
    super.key,
    required this.videoUrl,
    this.audioUrl,
    required this.title,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player player;
  late final VideoController controller;

  // 🔥 1. 核心伪装头：模拟 Chrome 浏览器，防止 403 Forbidden
  // 如果没有这个，YouTube 会拒绝连接，导致一直转圈
  final Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Referer': 'https://www.youtube.com/',
    'Origin': 'https://www.youtube.com',
  };

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    
    // 初始化播放器
    player = Player();
    controller = VideoController(player);

    _initPlayerConfig();
    _playVideo();
  }

  Future<void> _initPlayerConfig() async {
    // 🔥 2. 强制播放器走代理 (解决部分 VPN 不生效的问题)
    // 只有当你的 VPN 开了 "TUN 模式" 或 "全局模式" 时，这步才不需要
    // 如果你发现还是连不上，可以尝试解开下面这行的注释，并填入你代理软件的端口 (比如 Clsh 通常是 7890)
    // await (player.platform as NativePlayer).setProperty('http-proxy', 'http://127.0.0.1:7890');
    
    // 优化缓冲设置，减少转圈
    await (player.platform as NativePlayer).setProperty('cache', 'yes');
    await (player.platform as NativePlayer).setProperty('demuxer-max-bytes', '50000000'); // 50MB 缓存
  }

  Future<void> _playVideo() async {
    // 4K 音画分离模式
    if (widget.audioUrl != null) {
      await player.open(
        Media(
          widget.videoUrl,
          httpHeaders: _headers, // 注入 Header
        ),
        play: false, 
      );
      
      // 加载音轨也需要 Header
      // 注意：MediaKit 目前对 AudioTrack 的 headers 支持可能有限，但在新版中已改善
      await player.setAudioTrack(AudioTrack.uri(widget.audioUrl!));
      
      await player.play();
    } 
    // 720p 混合流模式 (最稳)
    else {
      await player.open(
        Media(
          widget.videoUrl,
          httpHeaders: _headers, // 注入 Header
        ),
      );
    }
  }

  @override
  void dispose() {
    player.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 14, color: Colors.white)),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: const BackButton(),
      ),
      body: Center(
        child: Video(
          controller: controller,
          controls: MaterialVideoControls,
        ),
      ),
    );
  }
}

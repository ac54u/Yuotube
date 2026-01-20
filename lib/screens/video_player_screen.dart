import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String? audioUrl; // 允许传入分离的音频流
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

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();

    // 1. 初始化 Player
    player = Player();
    controller = VideoController(player);

    _initPlayback();
  }

  Future<void> _initPlayback() async {
    // 🔥 核心黑科技：MediaKit 支持多轨道
    // 如果有独立的音频流（比如 4K 模式），我们需要同时加载
    
    if (widget.audioUrl != null) {
      // 方式 A: 打开视频，然后旁路加载音频 (Side-loading)
      await player.open(Media(widget.videoUrl));
      // 注意：MediaKit 的 AudioTrack.uri 目前还在完善中，
      // 对于 m3u8/dash 它是自动处理的。
      // 对于 YouTube 这种 raw stream，最稳妥的方式其实是依赖 MPV 的内部合并
      // 但为了演示，我们先尝试直接播放视频流（MediaKit 基于 MPV，MPV 对网络流兼容性极强）
      
      // ⚠️ 进阶技巧：如果是纯分离流，MediaKit 可以通过 extras 传递参数给 mpv
      // 但最简单的方案：让它直接播放 videoUrl。
      // 如果发现没有声音（因为是 4K 分离流），我们需要在 UI 上做处理或使用 ffmpeg 合并流播放（太慢）。
      
      // ✅ 修正方案：
      // 实际上，MediaKit 的 open 函数可以直接接受 audio 参数
      // 但为了保证 100% 成功，我们这里先演示播放 VideoUrl。
      // 如果是 DASH Manifest (mpd) URL，它会自动合并。
      // 但既然我们只有 raw url，我们尝试使用 AudioTrack.uri 加载音轨
      
      await player.setAudioTrack(AudioTrack.uri(widget.audioUrl!));
    } else {
      // 普通 720p 混合流
      await player.open(Media(widget.videoUrl));
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
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.title, style: const TextStyle(fontSize: 14)),
      ),
      body: Center(
        child: Video(
          controller: controller,
          controls: MaterialVideoControls, // 使用默认的精美 UI
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoInput; // 可能是 URL，也可能是 Video ID
  final String title;
  final bool isCloudMode; // 是否使用私有服务器

  const VideoPlayerScreen({
    super.key,
    required this.videoInput,
    required this.title,
    required this.isCloudMode,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final Player player;
  late final VideoController controller;

  // 🔥 你的私有服务器地址 (已填入你的 IP)
  final String _serverBase = "http://69.63.217.175:8000";

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    
    // 初始化播放器
    player = Player();
    controller = VideoController(player);

    _playVideo();
  }

  Future<void> _playVideo() async {
    String playUrl = "";

    if (widget.isCloudMode) {
      // ☁️ 云端模式：拼接服务器地址
      // 格式: http://IP:8000/play?id=VIDEO_ID
      playUrl = "$_serverBase/play?id=${widget.videoInput}";
      print("正在请求云端 4K: $playUrl");
    } else {
      // 🟢 普通模式：直接播放 URL (720p)
      playUrl = widget.videoInput;
    }

    // 播放配置
    // 云端推流是 MKV 格式，不需要伪装 Header，不需要复杂 Cache
    // 因为服务器到你的手机通常是满速的
    await player.open(
      Media(playUrl),
      play: true,
    );
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

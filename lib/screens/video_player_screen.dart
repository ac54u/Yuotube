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
  final Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Referer': 'https://www.youtube.com/',
    'Origin': 'https://www.youtube.com',
  };

  @override
  void initState() {
    super.initState();
    // 保持屏幕常亮
    WakelockPlus.enable();
    
    // 初始化播放器
    player = Player();
    controller = VideoController(player);

    _initPlayerConfig();
    _playVideo();
  }

  // ---------------------------------------------------------------------------
  // 🚀 核心修复：针对 4K 播放的大缓存配置
  // ---------------------------------------------------------------------------
  Future<void> _initPlayerConfig() async {
    // 如果你的 VPN 需要强制指定代理，请解开下面这行并修改端口
    // await (player.platform as NativePlayer).setProperty('http-proxy', 'http://127.0.0.1:7890');
    
    // 🔥 开启缓存 (MPV 默认策略很保守，这里我们强制开启)
    await (player.platform as NativePlayer).setProperty('cache', 'yes');
    
    // 🔥 设置 128MB 超大缓存 (单位是字节)
    // 默认只有几 MB，看 4K 根本不够，128MB 足够缓冲几十秒的高码率视频
    await (player.platform as NativePlayer).setProperty('demuxer-max-bytes', '${128 * 1024 * 1024}'); 
    
    // 🔥 增加预读取时间到 30秒
    // 让播放器像推土机一样尽可能多地把后面的数据拉下来
    await (player.platform as NativePlayer).setProperty('demuxer-readahead-secs', '30');
  }

  Future<void> _playVideo() async {
    // 🟢 4K 音画分离模式 (双流)
    if (widget.audioUrl != null) {
      await player.open(
        Media(
          widget.videoUrl,
          httpHeaders: _headers, // 注入伪装头
        ),
        play: false, // 先暂停，等音频轨挂载
      );
      
      // 挂载音频流
      await player.setAudioTrack(AudioTrack.uri(widget.audioUrl!));
      
      await player.play();
    } 
    // 🟢 720p/1080p 混合流模式 (单流)
    else {
      await player.open(
        Media(
          widget.videoUrl,
          httpHeaders: _headers,
        ),
      );
    }
  }

  @override
  void dispose() {
    player.dispose();
    WakelockPlus.disable(); // 恢复屏幕休眠
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

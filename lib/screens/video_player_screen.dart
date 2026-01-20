import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoInput; // 视频 ID 或 URL
  final String title;
  final bool isCloudMode;  // 是否开启云端服务器模式

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

  // 🔥 请填入你服务器的真实 IP (不要带 trailing slash)
  final String _serverBase = "http://69.63.217.175:8000";

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // 保持屏幕常亮
    
    // 初始化播放器
    player = Player(
      configuration: const PlayerConfiguration(
        // 允许所有协议，防止被安全策略拦截
        protocolWhitelist: ['http', 'https', 'tcp', 'tls', 'crypto'],
      ),
    );
    
    controller = VideoController(player);

    _initPlayerConfig();
    _playVideo();
  }

  // ---------------------------------------------------------------------------
  // 🚀 性能调优：让播放器像“吸尘器”一样疯狂吸入数据
  // ---------------------------------------------------------------------------
  Future<void> _initPlayerConfig() async {
    final mpv = player.platform as NativePlayer;

    // 1. 强制开启缓存 (对应服务器的高带宽)
    await mpv.setProperty('cache', 'yes');
    
    // 2. 设置 512MB 内存缓冲区
    // 4K 视频码率极大，必须给足空间，否则稍微网络波动就卡
    await mpv.setProperty('demuxer-max-bytes', '${512 * 1024 * 1024}'); 
    
    // 3. 激进的预读取策略
    // 告诉播放器：尽量往下下载 120秒 的内容，不要停！
    await mpv.setProperty('demuxer-readahead-secs', '120');

    // 4. 网络超时优化 (配合服务器的 ffmpeg 启动时间)
    // 如果服务器 5秒没反应，别急着断开，再等等，哪怕等 60秒
    await mpv.setProperty('network-timeout', '60');

    // 5. 强制硬件解码 (必开)
    // 软解 4K 会让手机瞬间发烫降频，导致卡顿
    await mpv.setProperty('hwdec', 'auto');

    // 6. (可选) 如果你在国内直连较慢，可能需要解开下面的代理
    // await mpv.setProperty('http-proxy', 'http://127.0.0.1:7890');
  }

  Future<void> _playVideo() async {
    String playUrl = "";
    Map<String, String> headers = {};

    if (widget.isCloudMode) {
      // ☁️ 云端模式：极简连接
      // 直接连你的服务器，不需要任何伪装 Header，越快越好
      playUrl = "$_serverBase/play?id=${widget.videoInput}";
      print("🚀 正在连接私有云服务器: $playUrl");
    } else {
      // 🟢 直连模式：需要伪装 (备用方案)
      playUrl = widget.videoInput;
      headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
        'Referer': 'https://www.youtube.com/',
      };
    }

    // 打开视频
    await player.open(
      Media(
        playUrl,
        httpHeaders: headers, // 云端模式下为空，直连模式下有伪装
      ),
      play: true, // 自动播放
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
      backgroundColor: Colors.black, // 纯黑沉浸背景
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 14, color: Colors.white)),
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: const BackButton(),
        elevation: 0,
      ),
      body: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            Video(
              controller: controller,
              controls: MaterialVideoControls,
              // 关键：切后台不暂停，防止缓冲中断
              pauseUponEnteringBackgroundMode: false, 
              resumeUponEnteringForegroundMode: true,
            ),
            // 这里可以加一个简单的缓冲提示，如果 buffer 太低可以显示
          ],
        ),
      ),
    );
  }
}

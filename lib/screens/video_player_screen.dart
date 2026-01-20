import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';       // 播放器核心
import 'package:media_kit_video/media_kit_video.dart'; // 播放器 UI
import 'package:wakelock_plus/wakelock_plus.dart';   // 屏幕常亮工具

class VideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String? audioUrl; // 4K 模式需要这个
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

  // 🔥 核心伪装 UA：必须和电脑端的 Chrome 保持一致，骗过 YouTube 的风控
  final String _userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  @override
  void initState() {
    super.initState();
    // 1. 保持屏幕常亮 (看电影时不能黑屏)
    WakelockPlus.enable();
    
    // 2. 初始化播放器实例
    // protocolWhitelist: 允许 HTTP/HTTPS/TCP/TLS 等所有协议，防止部分梯子被拦截
    player = Player(
      configuration: const PlayerConfiguration(
        protocolWhitelist: ['http', 'https', 'tcp', 'tls', 'crypto'],
      ),
    );
    
    // 3. 绑定控制器
    controller = VideoController(player);

    // 4. 执行核心配置 (这是能否播 4K 的关键)
    _initPlayerConfig();
    
    // 5. 开始加载视频
    _playVideo();
  }

  // ---------------------------------------------------------------------------
  // 🚀 4K 播放核心调优 (MPV 内核层)
  // ---------------------------------------------------------------------------
  Future<void> _initPlayerConfig() async {
    final mpv = player.platform as NativePlayer;

    // 🔥 A. 身份伪装 (解决 403 Forbidden)
    // 告诉 YouTube 服务器："我不是爬虫脚本，我是正经的 Chrome 浏览器"
    await mpv.setProperty('user-agent', _userAgent);
    await mpv.setProperty('referer', 'https://www.youtube.com/');
    
    // 🔥 B. 暴力缓存 (解决 4K 转圈卡顿)
    // 开启缓存
    await mpv.setProperty('cache', 'yes');
    // 分配 512MB 内存作为缓冲区 (4K 码率极高，默认缓存几秒就没了，必须加大)
    await mpv.setProperty('demuxer-max-bytes', '${512 * 1024 * 1024}'); 
    // 让播放器尽可能多地预加载 (提前下载未来 60秒 的内容)
    await mpv.setProperty('demuxer-readahead-secs', '60');

    // 🔥 C. 网络握手优化 (解决 VPN 环境下的连接失败)
    // 忽略 SSL 证书验证 (很多代理软件会劫持证书，导致握手失败)
    await mpv.setProperty('tls-verify', 'no');
    // 增加超时容忍度 (给梯子一点反应时间)
    await mpv.setProperty('network-timeout', '30');

    // 🔥 D. 强制硬件解码 (解决手机发热、掉帧)
    // iOS 使用 videotoolbox，Android 使用 mediacodec
    await mpv.setProperty('hwdec', 'auto'); 
    
    // (备选方案) 强制代理：如果你还卡，解开下面这行，填入你梯子的 HTTP 端口
    // await mpv.setProperty('http-proxy', 'http://127.0.0.1:7890');
  }

  Future<void> _playVideo() async {
    // 构造请求头 (应用层也要带上，双重保险)
    final headers = {
      'User-Agent': _userAgent,
      'Referer': 'https://www.youtube.com/',
    };

    if (widget.audioUrl != null) {
      // 🟡 4K 音画分离模式 (双流拼接)
      // 这是唯一能在线看 4K 的方式 (除了 DASH)
      
      // 打开视频流，但先 play: false (暂停状态)
      await player.open(
        Media(
          widget.videoUrl,
          httpHeaders: headers,
        ),
        play: false, 
      );
      
      // 挂载音频流 (注意：音频流通常不需要太复杂的 header，但带上无妨)
      await player.setAudioTrack(
        AudioTrack.uri(
          widget.audioUrl!,
        )
      );
      
      // 💡 小技巧：稍微延迟 500ms 再播放，让缓冲区先吃一点数据，防止起步卡顿
      await Future.delayed(const Duration(milliseconds: 500));
      await player.play();
      
    } else {
      // 🟢 普通单流模式 (720p/1080p 混合流)
      // 如果你点的不是 4K，走这里
      await player.open(
        Media(
          widget.videoUrl,
          httpHeaders: headers,
        ),
      );
    }
  }

  @override
  void dispose() {
    // ⚠️ 退出页面时必须清理，否则后台会继续下载耗电
    player.dispose();
    WakelockPlus.disable(); // 恢复屏幕休眠
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // 纯黑背景，沉浸式体验
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontSize: 14, color: Colors.white)),
        backgroundColor: Colors.transparent, // 透明导航栏
        iconTheme: const IconThemeData(color: Colors.white), // 白色返回箭头
        leading: const BackButton(),
        elevation: 0,
      ),
      // 使用 Center + AspectRatio 确保视频居中且不被拉伸
      body: Center(
        child: Video(
          controller: controller,
          controls: MaterialVideoControls, // 使用 MediaKit 自带的 Material 风格控制条
          pauseUponEnteringBackgroundMode: true, // 切后台自动暂停
          resumeUponEnteringForegroundMode: true, // 回前台自动播放
        ),
      ),
    );
  }
}

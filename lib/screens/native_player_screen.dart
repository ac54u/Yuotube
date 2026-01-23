import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
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
  String _statusText = "启动全协议解析...";
  String _debugInfo = "";

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
    controller = VideoController(player, configuration: const VideoControllerConfiguration(enableHardwareAcceleration: true));

    try {
      await _startBruteForceParsing();
    } catch (e) {
      if (mounted) setState(() => _statusText = "解析耗尽: $e");
    }
  }

  // 🔥 核心：无视 Surge 证书拦截的客户端
  http.Client _getUnsafeClient() {
    final ioClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) => true; // 统统放行
    return IOClient(ioClient);
  }

  // 🚀 策略总控：先试 Cobalt，再试 Invidious，最后试 Piped
  Future<void> _startBruteForceParsing() async {
    try {
      await _tryCobaltApi(); // 第一顺位：最强解析
    } catch (e1) {
      print("Cobalt 失败: $e1");
      try {
        await _tryInvidiousApi(); // 第二顺位：老牌镜像
      } catch (e2) {
        print("Invidious 失败: $e2");
        throw Exception("所有协议均失效，建议切换 IP");
      }
    }
  }

  // ----------------------------------------------------------------
  // 🟢 方案 A: Cobalt API (推荐，画质最好)
  // ----------------------------------------------------------------
  Future<void> _tryCobaltApi() async {
    if (mounted) setState(() => _statusText = "正在请求 Cobalt 高速接口...");
    
    // Cobalt 公共实例列表
    final instances = [
      "https://api.cobalt.tools",
      "https://cobalt.api.kwiatekmiki.pl",
      "https://api.cobalt.rogery.dev",
    ];

    for (final host in instances) {
      try {
        final client = _getUnsafeClient();
        final response = await client.post(
          Uri.parse("$host/api/json"),
          headers: {
            "Accept": "application/json",
            "Content-Type": "application/json"
          },
          body: jsonEncode({
            "url": "https://www.youtube.com/watch?v=${widget.videoId}",
            "vQuality": "max", // 强制最高画质
            "filenamePattern": "basic"
          })
        ).timeout(const Duration(seconds: 8));
        
        client.close();

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final url = data['url'];
          if (url != null) {
            await _playMedia(url, "Cobalt API (${Uri.parse(host).host})");
            return; // 成功则退出
          }
        }
      } catch (e) {
        print("Cobalt 节点 $host 异常: $e");
        continue; // 试下一个
      }
    }
    throw Exception("Cobalt 全灭");
  }

  // ----------------------------------------------------------------
  // 🟡 方案 B: Invidious API (备用)
  // ----------------------------------------------------------------
  Future<void> _tryInvidiousApi() async {
    if (mounted) setState(() => _statusText = "切换至 Invidious 协议...");

    final instances = [
      "https://inv.tux.pizza",
      "https://invidious.drgns.space",
      "https://invidious.privacydev.net",
      "https://vid.puffyan.us",
    ];

    for (final host in instances) {
      try {
        final client = _getUnsafeClient();
        final apiUrl = "$host/api/v1/videos/${widget.videoId}";
        final response = await client.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 6));
        client.close();

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final List<dynamic> formatStreams = data['formatStreams'];
          
          // 找最高画质
          formatStreams.sort((a, b) => (b['height'] ?? 0).compareTo(a['height'] ?? 0));
          
          if (formatStreams.isNotEmpty) {
            final targetUrl = formatStreams.first['url'];
            await _playMedia(targetUrl, "Invidious (${Uri.parse(host).host})");
            return;
          }
        }
      } catch (e) {
        continue;
      }
    }
    throw Exception("Invidious 全灭");
  }

  // ▶️ 统一播放入口
  Future<void> _playMedia(String url, String sourceName) async {
    if (mounted) {
      setState(() {
        _debugInfo = "来源: $sourceName\n状态: 已获取直链，缓冲中...";
        _statusText = "资源获取成功，准备播放...";
      });
    }

    await player.open(
      Media(
        url,
        extras: {
          'tls-verify': 'no', // 忽略播放器 SSL 报错
          'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'demuxer-max-bytes': '64MiB', // 大缓存
        },
      ),
      play: true,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        _debugInfo += "\n✅ 播放开始";
      });
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
                  Text(
                    _statusText, 
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text("正在尝试穿透网络封锁...", style: TextStyle(color: Colors.grey, fontSize: 12)),
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

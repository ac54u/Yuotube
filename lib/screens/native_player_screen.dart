import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
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
  String _statusText = "正在连接 Cobalt 高速通道...";
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
      await _startCobaltSequence();
    } catch (e) {
      if (mounted) setState(() => _statusText = "解析失败: $e\n请尝试切换 VPN 节点");
    }
  }

  // 🔥 专注 Cobalt 协议 (目前最稳的 4K 方案)
  Future<void> _startCobaltSequence() async {
    // 两个最强的 Cobalt 实例
    final instances = [
      "https://api.cobalt.tools",          // 官方主节点
      "https://cobalt.api.kwiatekmiki.pl", // 欧洲备用
    ];

    for (final host in instances) {
      if (!mounted) return;
      setState(() => _statusText = "正在请求服务器: ${Uri.parse(host).host}...");

      try {
        final response = await http.post(
          Uri.parse("$host/api/json"),
          headers: {
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0"
          },
          body: jsonEncode({
            "url": "https://www.youtube.com/watch?v=${widget.videoId}",
            "vQuality": "max", // 🔥 强制请求最高画质 (4K/8K)
            "filenamePattern": "basic"
          })
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          if (data['status'] == 'error' || data['url'] == null) {
            print("节点 $host 返回错误: ${data['text']}");
            continue; // 换下一个
          }

          final url = data['url'];
          await _playMedia(url, "Cobalt (${Uri.parse(host).host})");
          return; // 成功！
        } else {
          print("节点 $host 状态码: ${response.statusCode}");
        }
      } catch (e) {
        print("节点 $host 连接超时: $e");
        continue;
      }
    }
    
    throw Exception("所有 Cobalt 节点均繁忙或被墙");
  }

  Future<void> _playMedia(String url, String sourceName) async {
    if (mounted) {
      setState(() {
        _debugInfo = "来源: $sourceName\n协议: 4K 直链 (无风控)\n状态: 缓冲中...";
        _statusText = "获取成功，即将播放...";
      });
    }

    await player.open(
      Media(
        url,
        extras: {
          'tls-verify': 'no', // MPV 也忽略证书
          'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'demuxer-max-bytes': '100MiB', // 加大缓存到 100M
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
                  Text(_statusText, style: const TextStyle(color: Colors.white, fontSize: 14), textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  const Text("SSL 全局穿透已激活", style: TextStyle(color: Colors.green, fontSize: 12)),
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

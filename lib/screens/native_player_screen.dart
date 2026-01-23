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
  String _statusText = "启动全网节点扫描...";
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
      await _startUniversalParsing();
    } catch (e) {
      if (mounted) setState(() => _statusText = "全网节点均不可用\n建议更换 VPN 地区");
    }
  }

  // 🚀 核心总控：全协议轮询
  Future<void> _startUniversalParsing() async {
    // 1. 优先尝试 Cobalt (画质最佳)
    if (await _tryCobaltSequence()) return;

    // 2. 失败则尝试 Piped (节点最多)
    if (await _tryPipedSequence()) return;

    // 3. 最后尝试 Invidious (兜底)
    if (await _tryInvidiousSequence()) return;

    throw Exception("所有协议节点均失效");
  }

  // ----------------------------------------------------------------
  // 🟢 协议 A: Cobalt (4K 直链)
  // ----------------------------------------------------------------
  Future<bool> _tryCobaltSequence() async {
    final instances = [
      "https://api.cobalt.tools",
      "https://cobalt.api.kwiatekmiki.pl",
      "https://api.cobalt.rogery.dev",
      "https://cobalt.tools", 
    ];

    for (var i = 0; i < instances.length; i++) {
      final host = instances[i];
      if (!mounted) return false;
      setState(() => _statusText = "正在尝试 Cobalt 节点 (${i + 1}/${instances.length})...");

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
            "vQuality": "max",
            "filenamePattern": "basic"
          })
        ).timeout(const Duration(seconds: 5)); // 快速跳过

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['url'] != null) {
            await _playMedia(data['url'], "Cobalt (${Uri.parse(host).host})");
            return true;
          }
        }
      } catch (e) {
        print("Cobalt $host 失败: $e");
        continue;
      }
    }
    return false;
  }

  // ----------------------------------------------------------------
  // 🟡 协议 B: Piped (最稳健)
  // ----------------------------------------------------------------
  Future<bool> _tryPipedSequence() async {
    final instances = [
      "https://pipedapi.kavin.rocks",
      "https://api.piped.privacy.com.de",
      "https://pipedapi.drgns.space",
      "https://pa.il.ax",
      "https://piped-api.lunar.icu",
      "https://pipedapi.smnz.de",
      "https://api.piped.yt",
    ];

    for (var i = 0; i < instances.length; i++) {
      final host = instances[i];
      if (!mounted) return false;
      setState(() => _statusText = "正在尝试 Piped 节点 (${i + 1}/${instances.length})...");

      try {
        final response = await http.get(
          Uri.parse("$host/streams/${widget.videoId}")
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final List<dynamic> videoStreams = data['videoStreams'];
          
          // 找最高画质 videoOnly
          var bestVideo = videoStreams.where((e) => e['videoOnly'] == true).toList();
          if (bestVideo.isEmpty) bestVideo = videoStreams;
          bestVideo.sort((a, b) => (b['height'] ?? 0).compareTo(a['height'] ?? 0));

          if (bestVideo.isNotEmpty) {
            final targetVideo = bestVideo.first;
            
            // 找音频
            final List<dynamic> audioStreams = data['audioStreams'];
            audioStreams.sort((a, b) => (b['bitrate'] ?? 0).compareTo(a['bitrate'] ?? 0));
            final targetAudio = audioStreams.isNotEmpty ? audioStreams.first : null;

            await _playMedia(
              targetVideo['url'], 
              "Piped (${Uri.parse(host).host})", 
              audioUrl: targetAudio?['url']
            );
            return true;
          }
        }
      } catch (e) {
        continue;
      }
    }
    return false;
  }

  // ----------------------------------------------------------------
  // 🟠 协议 C: Invidious (最后的防线)
  // ----------------------------------------------------------------
  Future<bool> _tryInvidiousSequence() async {
    final instances = [
      "https://inv.tux.pizza",
      "https://invidious.drgns.space",
      "https://vid.puffyan.us",
      "https://invidious.privacydev.net",
    ];

    for (var i = 0; i < instances.length; i++) {
      final host = instances[i];
      if (!mounted) return false;
      setState(() => _statusText = "正在尝试 Invidious 节点 (${i + 1}/${instances.length})...");

      try {
        final response = await http.get(
          Uri.parse("$host/api/v1/videos/${widget.videoId}")
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final List<dynamic> formatStreams = data['formatStreams'];
          formatStreams.sort((a, b) => (b['height'] ?? 0).compareTo(a['height'] ?? 0));

          if (formatStreams.isNotEmpty) {
            await _playMedia(formatStreams.first['url'], "Invidious (${Uri.parse(host).host})");
            return true;
          }
        }
      } catch (e) {
        continue;
      }
    }
    return false;
  }

  Future<void> _playMedia(String url, String sourceName, {String? audioUrl}) async {
    if (mounted) {
      setState(() {
        _debugInfo = "✅ 解析成功\n节点: $sourceName\n状态: 缓冲中...";
        _statusText = "资源获取成功，准备播放...";
      });
    }

    await player.open(
      Media(
        url,
        extras: {
          if (audioUrl != null) 'audio-file': audioUrl,
          'tls-verify': 'no', // 忽略证书
          'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'demuxer-max-bytes': '64MiB',
        },
      ),
      play: true,
    );

    if (mounted) {
      setState(() {
        _isLoading = false;
        _debugInfo += "\n▶️ 播放开始";
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

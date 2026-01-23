import 'dart:async';
import 'dart:convert';
import 'dart:io'; // 🔥 需要这个来处理证书
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart'; // 🔥 需要这个来创建自定义 Client
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
  String _statusText = "正在连接中转节点...";
  String _debugInfo = "";
  
  // Piped 实例列表
  final List<String> _apiInstances = [
    "https://pipedapi.kavin.rocks",
    "https://api.piped.privacy.com.de",
    "https://pipedapi.drgns.space",
    "https://pa.il.ax",
    "https://piped-api.lunar.icu",
  ];
  int _currentApiIndex = 0;

  @override
  void initState() {
    super.initState();
    // 强制横屏
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
      await _fetchStreamFromPiped();
    } catch (e) {
      if (mounted) setState(() => _statusText = "全线崩溃: $e");
    }
  }

  // 🔥 核心：创建一个“不安全”的客户端，忽略 Surge 的证书错误
  http.Client _getUnsafeClient() {
    final ioClient = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true; // 👈 无论证书啥样，统统放行
    return IOClient(ioClient);
  }

  Future<void> _fetchStreamFromPiped() async {
    setState(() => _statusText = "正在请求无污染资源 (SSL Bypass)...");

    try {
      final apiUrl = "${_apiInstances[_currentApiIndex]}/streams/${widget.videoId}";
      print("正在请求 API: $apiUrl");

      // 🔥 使用自定义的 client 发送请求
      final client = _getUnsafeClient();
      final response = await client.get(Uri.parse(apiUrl));
      client.close(); // 用完记得关闭
      
      if (response.statusCode != 200) {
        throw Exception("API 拒绝服务: ${response.statusCode}");
      }

      final data = jsonDecode(response.body);
      
      // 1. 提取视频流
      final List<dynamic> videoStreams = data['videoStreams'];
      // 过滤出只有视频的流 (videoOnly)，通常 4K 都在这里
      var bestVideo = videoStreams.where((e) => e['videoOnly'] == true).toList();
      
      if (bestVideo.isEmpty) bestVideo = videoStreams;

      // 降序排列 (分辨率高在前)
      bestVideo.sort((a, b) => (b['height'] ?? 0).compareTo(a['height'] ?? 0)); 

      if (bestVideo.isEmpty) throw Exception("没有找到视频流");
      final targetVideo = bestVideo.first; 

      // 2. 提取音频流
      final List<dynamic> audioStreams = data['audioStreams'];
      audioStreams.sort((a, b) => (b['bitrate'] ?? 0).compareTo(a['bitrate'] ?? 0));
      final targetAudio = audioStreams.isNotEmpty ? audioStreams.first : null;

      final videoUrl = targetVideo['url'];
      final audioUrl = targetAudio?['url'];

      if (mounted) {
        setState(() {
          _debugInfo = "来源: Piped API (已绕过证书验证)\n"
                       "画质: ${targetVideo['quality']}\n"
                       "格式: ${targetVideo['format']}\n"
                       "状态: 准备播放..."; 
        });
      }

      // 3. 喂给 MPV 播放器
      await player.open(
        Media(
          videoUrl,
          extras: {
            if (audioUrl != null) 'audio-file': audioUrl,
            
            // 🔥 关键：告诉 MPV 内核也忽略 SSL 证书错误
            // 否则虽然 API 通了，但视频流可能会被 Surge 拦住
            'tls-verify': 'no', 
            
            'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36',
            'demuxer-max-bytes': '64MiB',
          },
        ),
        play: true,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _debugInfo += "\n✅ 播放成功";
        });
      }

    } catch (e) {
      print("API 请求失败: $e");
      // 自动切换下一个 API 节点
      if (_currentApiIndex < _apiInstances.length - 1) {
        _currentApiIndex++;
        if (mounted) setState(() => _statusText = "节点繁忙，切换线路 ${_currentApiIndex + 1}...");
        await _fetchStreamFromPiped(); 
      } else {
        if (mounted) setState(() => _statusText = "解析失败: $e");
      }
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
                  Text(_statusText, style: const TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 10),
                  const Text("正在穿透 SSL 验证...", style: TextStyle(color: Colors.grey, fontSize: 12)),
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

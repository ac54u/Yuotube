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
  String _statusText = "正在优选线路...";
  String _debugInfo = "";
  
  // 🔥 超级节点列表 (包含欧洲、美国、亚洲等地的 Piped 实例)
  // 只要这里面有一个活的，你就能看！
  final List<String> _apiInstances = [
    "https://pipedapi.kavin.rocks",          // 官方主节点 (常拥堵)
    "https://api.piped.privacy.com.de",      // 德国 (稳)
    "https://pipedapi.drgns.space",          // 美国
    "https://pa.il.ax",                      // 以色列
    "https://piped-api.lunar.icu",           // 德国
    "https://pipedapi.ducks.party",          // 欧洲
    "https://api.piped.projectsegfau.lt",    // 法国
    "https://pipedapi.smnz.de",              // 德国
    "https://api.piped.yt",                  // 备用
    "https://pipedapi.moomoo.me",            // 备用
    "https://pipedapi.leptons.xyz",          // 备用
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
      if (mounted) setState(() => _statusText = "所有线路均繁忙，请稍后再试");
    }
  }

  // 忽略 SSL 证书 (穿透 Surge)
  http.Client _getUnsafeClient() {
    final ioClient = HttpClient()
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
    return IOClient(ioClient);
  }

  Future<void> _fetchStreamFromPiped() async {
    if (_currentApiIndex >= _apiInstances.length) {
      throw Exception("所有节点已尝试完毕");
    }

    final currentApi = _apiInstances[_currentApiIndex];
    if (mounted) setState(() => _statusText = "正在尝试线路 ${_currentApiIndex + 1}/${_apiInstances.length}...\n(${Uri.parse(currentApi).host})");

    try {
      final apiUrl = "$currentApi/streams/${widget.videoId}";
      print("Testing API: $apiUrl");

      final client = _getUnsafeClient();
      // 设置 5 秒超时，快速跳过坏节点
      final response = await client.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 5));
      client.close();
      
      if (response.statusCode != 200) {
        throw Exception("HTTP ${response.statusCode}");
      }

      final data = jsonDecode(response.body);
      
      // 1. 提取视频流
      final List<dynamic> videoStreams = data['videoStreams'];
      // 优先找 videoOnly (通常是 1080p/4K)
      var bestVideo = videoStreams.where((e) => e['videoOnly'] == true).toList();
      if (bestVideo.isEmpty) bestVideo = videoStreams;

      // 排序：分辨率降序
      bestVideo.sort((a, b) => (b['height'] ?? 0).compareTo(a['height'] ?? 0)); 

      if (bestVideo.isEmpty) throw Exception("无视频流");
      final targetVideo = bestVideo.first; 

      // 2. 提取音频流
      final List<dynamic> audioStreams = data['audioStreams'];
      audioStreams.sort((a, b) => (b['bitrate'] ?? 0).compareTo(a['bitrate'] ?? 0));
      final targetAudio = audioStreams.isNotEmpty ? audioStreams.first : null;

      final videoUrl = targetVideo['url'];
      final audioUrl = targetAudio?['url'];

      if (mounted) {
        setState(() {
          _debugInfo = "节点: ${Uri.parse(currentApi).host}\n"
                       "画质: ${targetVideo['quality'] ?? 'Unknown'}\n"
                       "格式: ${targetVideo['format']}\n"
                       "状态: 缓冲中..."; 
        });
      }

      // 3. 播放
      await player.open(
        Media(
          videoUrl,
          extras: {
            if (audioUrl != null) 'audio-file': audioUrl,
            'tls-verify': 'no', // 忽略播放器的 SSL 报错
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
      print("节点 $currentApi 失败: $e");
      // 🔥 自动切换下一个节点
      _currentApiIndex++;
      if (mounted) {
        // 递归重试
        await _fetchStreamFromPiped(); 
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
                  Text(
                    _statusText, 
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 10),
                  const Text("正在全球节点中寻找可用服务器...", style: TextStyle(color: Colors.grey, fontSize: 12)),
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

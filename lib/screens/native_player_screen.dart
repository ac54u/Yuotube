import 'dart:async';
import 'dart:convert'; // 用于解析 JSON
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http; // 🔥 引入 http 请求库
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
  
  // 🔥 Piped 实例列表 (如果一个挂了，可以换其他的)
  // 这些服务器专门负责替我们向 YouTube 要链接
  final List<String> _apiInstances = [
    "https://pipedapi.kavin.rocks",
    "https://api.piped.privacy.com.de",
    "https://pipedapi.drgns.space",
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

  // 🔥 核心逻辑：不再用 youtube_explode，改用 Piped API
  Future<void> _fetchStreamFromPiped() async {
    setState(() => _statusText = "正在请求无污染资源...");

    try {
      final apiUrl = "${_apiInstances[_currentApiIndex]}/streams/${widget.videoId}";
      print("正在请求 API: $apiUrl");

      final response = await http.get(Uri.parse(apiUrl));
      
      if (response.statusCode != 200) {
        throw Exception("API 拒绝服务: ${response.statusCode}");
      }

      final data = jsonDecode(response.body);
      
      // 1. 提取视频流
      final List<dynamic> videoStreams = data['videoStreams'];
      // 过滤出只有视频的流 (videoOnly)，通常 4K 都在这里
      var bestVideo = videoStreams.where((e) => e['videoOnly'] == true).toList();
      
      // 如果没有 videoOnly，就找普通的
      if (bestVideo.isEmpty) bestVideo = videoStreams;

      // 按照分辨率排序 (height 越大越好)
      bestVideo.sort((a, b) => (b['height'] ?? 0).compareTo(a['height'] ?? 0)); // 降序

      if (bestVideo.isEmpty) throw Exception("没有找到视频流");
      final targetVideo = bestVideo.first; // 拿到最高画质 (4K)

      // 2. 提取音频流
      final List<dynamic> audioStreams = data['audioStreams'];
      // 按照码率排序
      audioStreams.sort((a, b) => (b['bitrate'] ?? 0).compareTo(a['bitrate'] ?? 0));
      final targetAudio = audioStreams.isNotEmpty ? audioStreams.first : null;

      final videoUrl = targetVideo['url'];
      final audioUrl = targetAudio?['url'];

      if (mounted) {
        setState(() {
          _debugInfo = "来源: Piped API (绕过本地风控)\n"
                       "画质: ${targetVideo['quality']} (${targetVideo['format']})\n"
                       "编码: ${targetVideo['videoCodec'] ?? 'Unknown'}\n"
                       "音质: ${targetAudio != null ? (targetAudio['bitrate'] / 1024).round() : 0} kbps\n"
                       "状态: 缓冲中..."; 
        });
      }

      // 3. 喂给 MPV 播放器
      // Piped 返回的链接通常不需要复杂的 UA 伪装，但带上也没坏处
      await player.open(
        Media(
          videoUrl,
          extras: audioUrl != null ? {
            'audio-file': audioUrl,
            // 这里的 UA 可以用标准的，因为 Piped 已经处理过签名了
            'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.18 Safari/537.36',
          } : null,
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
      // 自动切换下一个 API 节点重试
      if (_currentApiIndex < _apiInstances.length - 1) {
        _currentApiIndex++;
        if (mounted) setState(() => _statusText = "节点繁忙，切换线路 ${_currentApiIndex + 1}...");
        await _fetchStreamFromPiped(); // 递归重试
      } else {
        if (mounted) setState(() => _statusText = "解析失败: 无法获取流地址");
        rethrow;
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
                  const Text("正在使用云端 API 解析...", style: TextStyle(color: Colors.grey, fontSize: 12)),
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

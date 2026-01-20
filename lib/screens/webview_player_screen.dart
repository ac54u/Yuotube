import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WebViewPlayerScreen extends StatefulWidget {
  final String videoId;
  const WebViewPlayerScreen({super.key, required this.videoId});

  @override
  State<WebViewPlayerScreen> createState() => _WebViewPlayerScreenState();
}

class _WebViewPlayerScreenState extends State<WebViewPlayerScreen> {
  InAppWebViewController? webViewController;
  
  // 注入脚本：去广告 + 自动播放
  final String _injectScript = """
    // 屏蔽广告容器
    var style = document.createElement('style');
    style.innerHTML = '.ad-container, .ytp-ad-module, .ytp-ad-overlay-container, .ytp-ad-player-overlay { display: none !important; }';
    document.head.appendChild(style);

    // 尝试自动播放
    setTimeout(function() {
        var video = document.querySelector('video');
        if (video) { video.play(); }
    }, 2000);
  """;

  @override
  void initState() {
    super.initState();
    // 强制横屏，沉浸式体验
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // 恢复竖屏
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              // 强制桌面版参数 + 自动播放参数
              url: WebUri("https://www.youtube.com/embed/${widget.videoId}?autoplay=1&controls=1&rel=0&playsinline=0&modestbranding=1"),
            ),
            initialSettings: InAppWebViewSettings(
              mediaPlaybackRequiresUserGesture: false, // 允许自动播放
              allowsInlineMediaPlayback: true,
              // 🔥 核心伪装：伪装成 Mac 上的 Chrome，强开 4K 选项
              userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
              iframeAllow: "camera; microphone; fullscreen; accelerometer; gyroscope; encrypted-media; picture-in-picture",
              isInspectable: true,
              useHybridComposition: true, // Android 性能优化
            ),
            onWebViewCreated: (controller) {
              webViewController = controller;
            },
            onLoadStop: (controller, url) async {
              await controller.evaluateJavascript(source: _injectScript);
            },
          ),
          // 返回按钮
          Positioned(
            top: 20,
            left: 20,
            child: SafeArea(
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
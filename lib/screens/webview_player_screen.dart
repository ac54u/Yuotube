import 'dart:async';
import 'dart:collection';
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
  bool _isLoading = true;
  bool _showControls = false;
  Timer? _hideTimer;

  // 🔥 最佳伪装身份：iPad Pro (支持 4K，支持触屏，Google 认为是移动设备所以允许登录)
  final String _ipadUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15";

  // 🔥 4K 解锁脚本
  final String _unlock4KScript = """
    // 1. 视口欺骗 (让 YouTube 以为屏幕很大)
    var meta = document.querySelector('meta[name="viewport"]');
    if (!meta) {
        meta = document.createElement('meta');
        meta.name = 'viewport';
        document.head.appendChild(meta);
    }
    meta.content = 'width=1920, initial-scale=1.0';

    // 2. 屏幕分辨率欺骗
    try {
        Object.defineProperty(window.screen, 'width', { get: () => 3840 });
        Object.defineProperty(window.screen, 'height', { get: () => 2160 });
        Object.defineProperty(window, 'devicePixelRatio', { get: () => 2.0 });
    } catch(e) {}
    
    // 3. 自动画质尝试
    setInterval(() => {
        var player = document.getElementById('movie_player');
        if (player && player.setPlaybackQualityRange) {
             // 只有在没被用户手动设置过的情况下才尝试自动切
             if(player.getPlaybackQuality() === 'small' || player.getPlaybackQuality() === 'medium') {
                 player.setPlaybackQualityRange('highres', 'highres');
             }
        }
    }, 3000);
  """;

  // 🧹 温和的 UI 净化 (只隐藏广告和无关推荐，绝对不碰播放器控件)
  final String _uiCleanupScript = """
    var style = document.createElement('style');
    style.innerHTML = `
      /* 背景黑化 */
      body, html, ytd-app { background: #000 !important; }
      
      /* 隐藏外部框架 */
      #masthead-container { opacity: 0 !important; pointer-events: none !important; height: 0 !important; }
      #secondary, #comments, #related, ytd-merch-shelf-renderer { display: none !important; }
      
      /* 铺满全屏 */
      #page-manager { margin: 0 !important; margin-top: 0 !important; }
      #primary { padding: 0 !important; margin: 0 !important; max-width: 100% !important; }
      #player-container-outer { max-width: 100% !important; }
      
      /* 🔥 关键：确保播放器位于最上层，但不要遮挡它自己的控制栏 */
      #player { position: relative !important; z-index: 1 !important; width: 100vw !important; height: 100vh !important; }
      
      /* 隐藏顶部横幅广告，但保留底部的控制条 (.ytp-chrome-bottom) */
      .ytp-ad-module, .ytp-ad-overlay-container { display: none !important; }
    `;
    document.head.appendChild(style);
  """;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeRight, DeviceOrientation.landscapeLeft]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // ❌ 以前这里有一行 deleteAllCookies，已经被我删了！现在的登录状态会永久保存！
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _showControls = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri("https://www.youtube.com/watch?v=${widget.videoId}"),
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(source: _unlock4KScript, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END, forMainFrameOnly: true),
            ]),
            initialSettings: InAppWebViewSettings(
              // 🔥 使用 iPad Pro 身份：这是完美的平衡点
              // 它既能骗过 Google 安全检查允许登录，又能请求到 1080p/4K 视频流
              userAgent: _ipadUA,
              preferredContentMode: UserPreferredContentMode.RECOMMENDED, // 让 Webview 自己决定，避免强制 Desktop 导致的触控失效
              
              allowsInlineMediaPlayback: true, // 必须开启，防止 iOS 原生播放器劫持
              mediaPlaybackRequiresUserGesture: false,
              
              useWideViewPort: true,
              loadWithOverviewMode: true,
              isInspectable: true,
              supportZoom: true,
            ),
            
            onWebViewCreated: (controller) => webViewController = controller,

            onLoadStop: (controller, url) async {
              await controller.evaluateJavascript(source: _uiCleanupScript);
              if (mounted) setState(() => _isLoading = false);
            },
          ),

          if (_isLoading)
            Container(color: Colors.black, child: const Center(child: CircularProgressIndicator(color: Colors.redAccent))),

          // UI 控制层
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Container(
                height: 100,
                decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.black.withOpacity(0.8), Colors.transparent], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.arrow_back, color: Colors.white, size: 24)),
                        ),
                        const SizedBox(width: 16),
                        const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                                Text("iPad Pro Mode", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                Text("Login Supported • 4K Ready", style: TextStyle(color: Colors.amber, fontSize: 10))
                            ]
                        ),
                        const Spacer(),
                        
                        // 登录按钮
                        TextButton.icon(
                            icon: const Icon(Icons.login, size: 16, color: Colors.white),
                            label: const Text("去登录(只需一次)", style: TextStyle(color: Colors.white)),
                            style: TextButton.styleFrom(backgroundColor: Colors.blueAccent.withOpacity(0.4)),
                            onPressed: () {
                                webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri("https://accounts.google.com/ServiceLogin?service=youtube")));
                            },
                        ),

                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white70),
                          onPressed: () {
                            webViewController?.reload();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          
          if (!_showControls)
            Positioned(top: 0, left: 0, right: 0, height: 80, child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _toggleControls, child: Container(color: Colors.transparent))),
        ],
      ),
    );
  }
}

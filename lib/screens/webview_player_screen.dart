import 'dart:collection';
import 'dart:async';
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
  bool _showControls = true;
  Timer? _hideTimer;

  // 🔥 4K 分辨率欺骗脚本 (针对 macOS 优化)
  final String _screenSpoofScript = """
    try {
        // 伪装成 5K iMac 的分辨率
        Object.defineProperty(window.screen, 'width', { get: function() { return 5120; } });
        Object.defineProperty(window.screen, 'height', { get: function() { return 2880; } });
        Object.defineProperty(window.screen, 'availWidth', { get: function() { return 5120; } });
        Object.defineProperty(window.screen, 'availHeight', { get: function() { return 2880; } });
        Object.defineProperty(window, 'innerWidth', { get: function() { return 2560; } });
        Object.defineProperty(window, 'innerHeight', { get: function() { return 1440; } });
        Object.defineProperty(window, 'devicePixelRatio', { get: function() { return 2.0; } });
    } catch(e) {}
  """;

  // 🔥 UI 净化脚本 (增强版：处理弹窗)
  final String _uiCleanupScript = """
    var style = document.createElement('style');
    style.innerHTML = `
      #masthead-container, #secondary, #below, #comments, #related, ytd-merch-shelf-renderer { display: none !important; }
      ytd-app { background: #000 !important; }
      #page-manager { margin: 0 !important; }
      #primary { padding: 0 !important; margin: 0 !important; max-width: 100% !important; }
      #player { position: fixed !important; top: 0 !important; left: 0 !important; width: 100vw !important; height: 100vh !important; z-index: 1 !important; }
      .ytp-ad-module, .ytp-ad-overlay-container, .ytp-chrome-top { display: none !important; }
      
      /* 隐藏登录提示弹窗 */
      ytd-popup-container, paper-dialog, yt-upsell-dialog-renderer { display: none !important; }
      .yt-spec-button-shape-next--call-to-action { display: none !important; }
    `;
    document.head.appendChild(style);

    setTimeout(function() {
        var video = document.querySelector('video');
        if (video && video.paused) video.play();
        
        // 自动点击“不用了”/“拒绝”
        var buttons = document.querySelectorAll('button');
        buttons.forEach(btn => {
            if(btn.innerText.includes('No thanks') || btn.innerText.includes('Reject') || btn.innerText.includes('Not now')) {
                btn.click();
            }
        });
    }, 1000);
  """;

  @override
  void initState() {
    super.initState();
    // 强制横屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight, DeviceOrientation.landscapeLeft,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    
    // 🔥 关键步骤：启动前清除 Cookie，防止被 Google 标记
    _clearCookies();
    
    _startHideTimer();
  }

  Future<void> _clearCookies() async {
    try {
      await CookieManager.instance().deleteAllCookies();
      print("Cookies cleaned for stealth mode");
    } catch(e) {
      print("Cookie clean error: $e");
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
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
              url: WebUri("https://www.youtube.com/watch?v=${widget.videoId}"),
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(
                source: _screenSpoofScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                forMainFrameOnly: true,
              ),
            ]),
            initialSettings: InAppWebViewSettings(
              // 🔥 核心修改：使用无痕模式 (Incognito)
              incognito: true, 
              
              preferredContentMode: UserPreferredContentMode.DESKTOP,
              allowsInlineMediaPlayback: true,
              mediaPlaybackRequiresUserGesture: false,
              useWideViewPort: true,
              loadWithOverviewMode: true,
              
              // 🔥 核心修改：伪装成 macOS Safari (更适合 iPhone，降低风控概率)
              userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Safari/605.1.15",
              
              isInspectable: true,
              supportZoom: true,
              layoutAlgorithm: LayoutAlgorithm.NORMAL, 
            ),
            onWebViewCreated: (controller) => webViewController = controller,
            onLoadStop: (controller, url) async {
              await controller.evaluateJavascript(source: _uiCleanupScript);
              if (mounted) setState(() => _isLoading = false);
            },
          ),

          // Loading 层
          if (_isLoading)
            Container(color: Colors.black, child: const Center(child: CircularProgressIndicator(color: Colors.redAccent))),

          // UI 控制层 (保持之前的 Netflix 风格)
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: !_showControls,
              child: Container(
                height: 100,
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withOpacity(0.8), Colors.transparent])),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        // 返回按钮
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // 标题
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                             const Text("Stealth Cinema", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                             Row(children: [
                               Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(4)), child: const Text("4K", style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold))),
                               const SizedBox(width: 6),
                               Text("MacOS Mode • Incognito", style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10)),
                             ])
                          ]),
                        ),
                        // 刷新按钮 (遇到机器人验证时点这个重试)
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white70),
                          onPressed: () {
                            setState(() => _isLoading = true);
                            _clearCookies().then((_) => webViewController?.reload());
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
            Positioned(top: 0, left: 0, right: 0, height: 60, child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: _toggleControls, child: Container(color: Colors.transparent))),
        ],
      ),
    );
  }
}

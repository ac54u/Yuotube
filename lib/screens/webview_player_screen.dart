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
  bool _showControls = true;
  Timer? _hideTimer;

  // 🔥 终极反爬虫脚本：全方位伪装成 Mac Safari
  final String _antiBotScript = """
    // 1. 消除自动化特征
    Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
    
    // 2. 伪装硬件并发数 (让我也像个真电脑)
    Object.defineProperty(navigator, 'hardwareConcurrency', { get: () => 4 });
    
    // 3. 伪装平台 (这是关键，不能让它发现是 iPhone)
    Object.defineProperty(navigator, 'platform', { get: () => 'MacIntel' });
    Object.defineProperty(navigator, 'maxTouchPoints', { get: () => 0 }); // 电脑通常没有触摸屏

    // 4. 屏幕分辨率伪装 (4K iMac)
    Object.defineProperty(window.screen, 'width', { get: () => 5120 });
    Object.defineProperty(window.screen, 'height', { get: () => 2880 });
    Object.defineProperty(window, 'devicePixelRatio', { get: () => 2.0 });

    console.log("Stealth mode active: Bot traces removed.");
  """;

  // 🔥 UI 净化脚本
  final String _uiCleanupScript = """
    var style = document.createElement('style');
    style.innerHTML = `
      #masthead-container, #secondary, #below, #comments, #related, ytd-merch-shelf-renderer { display: none !important; }
      ytd-app { background: #000 !important; }
      #page-manager { margin: 0 !important; }
      #primary { padding: 0 !important; margin: 0 !important; max-width: 100% !important; }
      #player { position: fixed !important; top: 0 !important; left: 0 !important; width: 100vw !important; height: 100vh !important; z-index: 1 !important; }
      .ytp-ad-module, .ytp-ad-overlay-container, .ytp-chrome-top { display: none !important; }
      /* 暴力隐藏登录弹窗 */
      ytd-popup-container, paper-dialog, .yt-spec-button-shape-next--call-to-action { display: none !important; }
    `;
    document.head.appendChild(style);

    setTimeout(function() {
        var video = document.querySelector('video');
        if (video && video.paused) video.play();
        
        // 自动点击"拒绝/不用了"
        document.querySelectorAll('button').forEach(btn => {
            if(btn.innerText.match(/No thanks|Reject|Not now|不用了|拒绝/i)) btn.click();
        });
    }, 1500);
  """;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight, DeviceOrientation.landscapeLeft,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    
    // 🔥 启动前准备：先注入 Cookie 再加载
    _prepareEnvironment();
    _startHideTimer();
  }

  Future<void> _prepareEnvironment() async {
    // 1. 清理旧数据 (防止之前的失败记录影响)
    await CookieManager.instance().deleteAllCookies();
    
    // 2. 注入“免死金牌” Cookie (绕过同意弹窗)
    // SOCS=CAI... 表示“我已同意所有条款”
    await CookieManager.instance().setCookie(
      url: WebUri("https://www.youtube.com"),
      name: "SOCS",
      value: "CAISNQgDEitib3FfaWRlbnRpdHlmcm9udGVuZHVpXzIwMjMwMTEwLjA3X3AwX1JDXzAaAmVuIAEaBgiAoLmYBw",
    );
    await CookieManager.instance().setCookie(
      url: WebUri("https://www.youtube.com"),
      name: "CONSENT",
      value: "YES+cb.20210328-17-p0.en+FX+419",
    );
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
                source: _antiBotScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                forMainFrameOnly: true,
              ),
            ]),
            initialSettings: InAppWebViewSettings(
              preferredContentMode: UserPreferredContentMode.DESKTOP,
              allowsInlineMediaPlayback: true,
              mediaPlaybackRequiresUserGesture: false,
              useWideViewPort: true,
              loadWithOverviewMode: true,
              // 🔥 伪装成 Mac Safari (比 Chrome 更可信，因为宿主就是 iPhone)
              userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Safari/605.1.15",
              isInspectable: true,
              supportZoom: true,
            ),
            
            onWebViewCreated: (controller) => webViewController = controller,
            
            // 🔥 路由锁死：严禁跳转到登录页或 APP
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              var uri = navigationAction.request.url!;
              var urlString = uri.toString();
              
              // 1. 拦截 Google 登录页
              if (urlString.contains("accounts.google.com") || urlString.contains("google.com/signin")) {
                print("🛑 拦截登录跳转: $urlString");
                return NavigationActionPolicy.CANCEL; // 禁止跳转
              }
              
              // 2. 拦截唤起外部 App (YouTube App)
              if (["youtube", "intent"].contains(uri.scheme)) {
                 print("🛑 拦截外部唤起: $urlString");
                 return NavigationActionPolicy.CANCEL;
              }
              
              return NavigationActionPolicy.ALLOW;
            },

            onLoadStop: (controller, url) async {
              await controller.evaluateJavascript(source: _uiCleanupScript);
              if (mounted) setState(() => _isLoading = false);
            },
          ),

          // Loading
          if (_isLoading)
            Container(color: Colors.black, child: const Center(child: CircularProgressIndicator(color: Colors.redAccent))),

          // UI (Controls)
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
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.arrow_back, color: Colors.white, size: 24)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                             const Text("Anti-Bot Cinema", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                             Row(children: [
                               Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(4)), child: const Text("4K", style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold))),
                               const SizedBox(width: 6),
                               Text("Route Blocked • Cookies Injected", style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10)),
                             ])
                          ]),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white70),
                          onPressed: () {
                            setState(() => _isLoading = true);
                            _prepareEnvironment().then((_) => webViewController?.reload());
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

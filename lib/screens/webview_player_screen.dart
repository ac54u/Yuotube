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
  
  bool _isLoginMode = false;

  // 🖥️ 身份：使用最新的 macOS Safari UA (为了兼容性和 VP9)
  final String _desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15";
  final String _mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1";

  // ☢️ 核弹脚本：Codec 欺骗 + 5K 分辨率
  final String _godModeScript = """
    console.log("☢️ God Mode Loaded");

    // 1. 【核心突破】篡改 MSE 能力检测
    // 强制告诉 YouTube：我们支持 VP9 (4K 编码)，即使 iOS 说不支持
    try {
        if (window.MediaSource) {
            var originalIsTypeSupported = window.MediaSource.isTypeSupported;
            window.MediaSource.isTypeSupported = function(mime) {
                // 只要问到 vp9 或 av01，统统回答 true
                if (mime && (mime.includes('vp9') || mime.includes('vp09') || mime.includes('av01'))) {
                    console.log("😈 Lying about codec support: " + mime);
                    return true;
                }
                return originalIsTypeSupported.call(this, mime);
            };
        }
    } catch(e) { console.log(e); }

    // 2. 【5K 屏幕伪装】
    // 既然要骗，就骗大点。伪装成 5K iMac。
    try {
        Object.defineProperty(window.screen, 'width', { get: () => 5120 });
        Object.defineProperty(window.screen, 'height', { get: () => 2880 });
        Object.defineProperty(window, 'availWidth', { get: () => 5120 });
        Object.defineProperty(window, 'availHeight', { get: () => 2880 });
        Object.defineProperty(window, 'devicePixelRatio', { get: () => 2.0 });
        Object.defineProperty(window, 'innerWidth', { get: () => 2560 });
        Object.defineProperty(window, 'innerHeight', { get: () => 1440 });
    } catch(e) {}

    // 3. 【防黑屏 & 强制内联】
    var observer = new MutationObserver(function(mutations) {
        var videos = document.querySelectorAll('video');
        videos.forEach(function(video) {
            if (!video.hasAttribute('playsinline')) {
                video.setAttribute('playsinline', 'true');
                video.setAttribute('webkit-playsinline', 'true');
            }
            video.style.visibility = 'visible';
            video.style.display = 'block';
        });
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });

    // 4. 【视口锁定】
    var meta = document.querySelector('meta[name="viewport"]');
    if (!meta) { meta = document.createElement('meta'); document.head.appendChild(meta); }
    meta.name = 'viewport';
    meta.content = 'width=1920, initial-scale=1.0, maximum-scale=1.0, user-scalable=yes';

    // 5. 【UI 净化】
    var style = document.createElement('style');
    style.innerHTML = `
      body, html, ytd-app { background: #000 !important; width: 100vw !important; height: 100vh !important; overflow: hidden !important; }
      #masthead-container, #secondary, #comments, #related, .ytp-chrome-top { display: none !important; }
      .ytp-fullscreen-button { display: none !important; }
      #player { position: fixed !important; top: 0 !important; left: 0 !important; width: 100vw !important; height: 100vh !important; z-index: 1 !important; }
      video { object-fit: contain !important; }
    `;
    document.head.appendChild(style);

    // 6. 【外挂接口】
    window.forceQuality = function(quality) {
        var player = document.getElementById('movie_player');
        if (player && player.setPlaybackQualityRange) {
            console.log("🚀 Force command: " + quality);
            player.setPlaybackQualityRange(quality, quality);
            player.setPlaybackQuality(quality);
        }
    }
  """;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeRight, DeviceOrientation.landscapeLeft]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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

  Future<void> _switchMode(bool loginMode) async {
    setState(() { _isLoading = true; _isLoginMode = loginMode; });
    await webViewController?.setSettings(settings: InAppWebViewSettings(
      userAgent: loginMode ? _mobileUA : _desktopUA,
      preferredContentMode: loginMode ? UserPreferredContentMode.MOBILE : UserPreferredContentMode.DESKTOP,
      useWideViewPort: !loginMode,
      loadWithOverviewMode: !loginMode,
      allowsInlineMediaPlayback: true,
    ));
    webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri(loginMode ? "https://accounts.google.com/ServiceLogin?service=youtube" : "https://www.youtube.com/watch?v=${widget.videoId}")));
  }

  void _showQualitySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF222222),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("强制 VP9 解码 (实验性)", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("尝试强制请求 4K 流。如果黑屏，说明手机硬件不支持硬解。", style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            const Divider(color: Colors.white10),
            _buildQualityOption("🚀 4K (2160p)", "highres"),
            _buildQualityOption("📺 2K (1440p)", "hd1440"),
            _buildQualityOption("💿 1080p", "hd1080"),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityOption(String label, String code) {
    return ListTile(
      leading: const Icon(Icons.high_quality, color: Colors.purpleAccent),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: () {
        Navigator.pop(context);
        webViewController?.evaluateJavascript(source: "window.forceQuality('$code');");
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri("https://www.youtube.com/watch?v=${widget.videoId}")),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(source: _godModeScript, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: true),
            ]),
            initialSettings: InAppWebViewSettings(
              userAgent: _desktopUA,
              preferredContentMode: UserPreferredContentMode.DESKTOP,
              allowsInlineMediaPlayback: true,
              mediaPlaybackRequiresUserGesture: false,
              useWideViewPort: true,
              loadWithOverviewMode: true,
              isInspectable: true,
              supportZoom: true,
              // 🔥 尝试开启混合合成，提升渲染兼容性
              useHybridComposition: true,
            ),
            onWebViewCreated: (controller) => webViewController = controller,
            onLoadStop: (controller, url) async {
              await controller.evaluateJavascript(source: _godModeScript);
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
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                                Text(_isLoginMode ? "Login Mode" : "VP9 Injector", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(_isLoginMode ? "登录完成后切回" : "伪装 5K iMac • 强开 Codec", style: TextStyle(color: _isLoginMode ? Colors.amber : Colors.purpleAccent, fontSize: 10))
                            ]
                        ),
                        const Spacer(),
                        
                        if (!_isLoginMode)
                          ElevatedButton.icon(
                            icon: const Icon(Icons.bolt, size: 14),
                            label: const Text("强开4K"),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: Colors.white),
                            onPressed: _showQualitySheet,
                          ),
                        
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(_isLoginMode ? Icons.movie : Icons.login, color: Colors.white70),
                          onPressed: () => _switchMode(!_isLoginMode),
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

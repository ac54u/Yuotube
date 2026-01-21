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

  // 🖥️ Windows Chrome UA：这是 YouTube 4K 的亲爹
  // 只有用这个身份，YouTube 才会愿意下发 VP9 编码
  final String _windowsUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";
  
  final String _mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1";

  // ☢️ 核弹脚本：欺骗 MSE 能力
  final String _vp9EnforcerScript = """
    console.log("☢️ VP9 Enforcer Loaded");

    // 1. 【核心】篡改 MediaSource 能力检测
    // 这是最关键的一步！不管 iOS 说支不支持，我们统统返回 True！
    try {
        if (window.MediaSource) {
            var realSupport = window.MediaSource.isTypeSupported;
            window.MediaSource.isTypeSupported = function(mime) {
                // 只要问到 vp9 或 av1，就撒谎说支持
                if (mime && (mime.includes('vp9') || mime.includes('vp09') || mime.includes('av01'))) {
                    console.log("😈 Lying about VP9 support for: " + mime);
                    return true;
                }
                // 正常的 mp4/h264 还是走系统检测
                return realSupport.call(this, mime);
            };
        }
    } catch(e) {}

    // 2. 【身份伪装】彻底伪装成 Windows PC
    try {
        Object.defineProperty(navigator, 'platform', { get: () => 'Win32' });
        Object.defineProperty(navigator, 'maxTouchPoints', { get: () => 0 }); // 假装是鼠标
        Object.defineProperty(window.screen, 'width', { get: () => 3840 });
        Object.defineProperty(window.screen, 'height', { get: () => 2160 });
        Object.defineProperty(window, 'devicePixelRatio', { get: () => 1.5 }); // Windows 常见的 DPI
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
    meta.content = 'width=1920, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';

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
            // 暴力清空 buffer，强制重载流
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
      userAgent: loginMode ? _mobileUA : _windowsUA,
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
            const Text("VP9 强开模式", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("只有 VP9 编码才有 4K。已强制注入解码支持。", style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            const Divider(color: Colors.white10),
            _buildQualityOption("🚀 4K (2160p)", "highres"), // highres 是 4K+ 的代号
            _buildQualityOption("📺 2K (1440p)", "hd1440"),
            _buildQualityOption("💿 1080p", "hd1080"),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityOption(String label, String code) {
    return ListTile(
      leading: const Icon(Icons.bolt, color: Colors.orangeAccent),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: () {
        Navigator.pop(context);
        webViewController?.evaluateJavascript(source: "window.forceQuality('$code');");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("正在暴力请求 $label...")));
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
              UserScript(source: _vp9EnforcerScript, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: true),
            ]),
            initialSettings: InAppWebViewSettings(
              // 🔥 关键：使用 Windows UA 才能骗到 VP9
              userAgent: _windowsUA,
              preferredContentMode: UserPreferredContentMode.DESKTOP,
              allowsInlineMediaPlayback: true, 
              mediaPlaybackRequiresUserGesture: false,
              useWideViewPort: true,
              loadWithOverviewMode: true,
              isInspectable: true,
              supportZoom: true,
              useHybridComposition: true, // 增强兼容性
            ),
            onWebViewCreated: (controller) => webViewController = controller,
            onLoadStop: (controller, url) async {
              await controller.evaluateJavascript(source: _vp9EnforcerScript);
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
                                Text(_isLoginMode ? "Login Mode" : "Windows 10 Chrome", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(_isLoginMode ? "完成登录后切回" : "VP9 解码已注入", style: TextStyle(color: _isLoginMode ? Colors.amber : Colors.orangeAccent, fontSize: 10))
                            ]
                        ),
                        const Spacer(),
                        
                        if (!_isLoginMode)
                          ElevatedButton.icon(
                            icon: const Icon(Icons.high_quality, size: 14),
                            label: const Text("强开4K"),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white),
                            onPressed: _showQualitySheet,
                          ),
                        
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(_isLoginMode ? Icons.movie : Icons.login, color: Colors.white70),
                          tooltip: _isLoginMode ? "切回看片" : "去登录",
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

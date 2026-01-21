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
  
  // 状态：是否为登录模式
  bool _isLoginMode = false;

  // 🖥️ Windows Chrome (这是拥有最全画质菜单的身份)
  final String _desktopUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";
  
  // 📱 手机身份 (仅用于登录)
  final String _mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Mobile/15E148 Safari/604.1";

  // ☢️ 核心脚本：解锁菜单 + 强制 4K
  final String _unlockMenuScript = """
    console.log("☢️ Menu Unlock Loaded");

    // 1. 【伪装鼠标设备】
    // 关键！告诉 YouTube 我没有触摸屏， forcing it to render the Desktop Menu (small popup)
    try {
        Object.defineProperty(navigator, 'maxTouchPoints', { get: () => 0 });
        Object.defineProperty(navigator, 'platform', { get: () => 'Win32' });
    } catch(e) {}

    // 2. 【防黑屏 & 强制内联】
    var observer = new MutationObserver(function(mutations) {
        var videos = document.querySelectorAll('video');
        videos.forEach(function(video) {
            if (!video.hasAttribute('playsinline')) {
                video.setAttribute('playsinline', 'true');
                video.setAttribute('webkit-playsinline', 'true');
            }
        });
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });

    // 3. 【视口欺骗】(让菜单以为屏幕很大)
    var meta = document.querySelector('meta[name="viewport"]');
    if (!meta) { meta = document.createElement('meta'); document.head.appendChild(meta); }
    meta.name = 'viewport';
    meta.content = 'width=1920, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';

    // 4. 【画质菜单解锁】
    // 强制开启 MSE (Media Source Extensions) 支持，这是 4K 的基础
    if (!window.MediaSource) { console.log("⚠️ MSE not supported by iOS WebKit, relying on native HLS"); }

    // 5. 【后台暴力提画质】
    // 既然菜单可能显示不全，我们在后台帮你选
    setInterval(() => {
        var player = document.getElementById('movie_player');
        if (player && player.setPlaybackQualityRange) {
             // 强制设置最高画质，不管菜单显示什么
             player.setPlaybackQualityRange('highres', 'highres');
             player.setPlaybackQuality('hd2160');
             player.setPlaybackQuality('hd1440');
             player.setPlaybackQuality('hd1080');
        }
    }, 2000);

    // 6. 【UI 净化】
    var style = document.createElement('style');
    style.innerHTML = `
      body, html, ytd-app { background: #000 !important; width: 100vw !important; height: 100vh !important; overflow: hidden !important; }
      #masthead-container, #secondary, #comments, #related, .ytp-chrome-top { display: none !important; }
      
      /* 隐藏全屏按钮 */
      .ytp-fullscreen-button { display: none !important; }
      
      #player { position: fixed !important; top: 0 !important; left: 0 !important; width: 100vw !important; height: 100vh !important; z-index: 1 !important; }
      video { object-fit: contain !important; }
    `;
    document.head.appendChild(style);
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

    if (loginMode) {
      webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri("https://accounts.google.com/ServiceLogin?service=youtube")));
    } else {
      webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri("https://www.youtube.com/watch?v=${widget.videoId}")));
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
              UserScript(
                source: _unlockMenuScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                forMainFrameOnly: true,
              ),
            ]),
            initialSettings: InAppWebViewSettings(
              // 🔥 这里的关键是 Windows UA + DESKTOP 模式
              userAgent: _desktopUA,
              preferredContentMode: UserPreferredContentMode.DESKTOP,
              
              allowsInlineMediaPlayback: true,
              allowsAirPlayForMediaPlayback: false,
              allowsPictureInPictureMediaPlayback: false,
              
              mediaPlaybackRequiresUserGesture: false,
              useWideViewPort: true,
              loadWithOverviewMode: true,
              isInspectable: true,
              supportZoom: true,
            ),
            onWebViewCreated: (controller) => webViewController = controller,
            onLoadStop: (controller, url) async {
              await controller.evaluateJavascript(source: _unlockMenuScript);
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
                                Text(_isLoginMode ? "Login Mode" : "Windows 4K", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(_isLoginMode ? "完成登录后切回" : "强制解锁菜单", style: TextStyle(color: _isLoginMode ? Colors.amber : Colors.greenAccent, fontSize: 10))
                            ]
                        ),
                        const Spacer(),
                        
                        // 模式切换
                        ElevatedButton.icon(
                            icon: Icon(_isLoginMode ? Icons.movie : Icons.login, size: 14),
                            label: Text(_isLoginMode ? "切回看片" : "去登录"),
                            style: ElevatedButton.styleFrom(backgroundColor: _isLoginMode ? Colors.green : Colors.blueAccent, foregroundColor: Colors.white),
                            onPressed: () => _switchMode(!_isLoginMode),
                        ),

                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white70),
                          onPressed: () { webViewController?.reload(); },
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

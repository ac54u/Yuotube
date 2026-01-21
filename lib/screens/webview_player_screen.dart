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

  // 🖥️ 最佳身份：Mac Safari (兼容性最好，不易黑屏)
  final String _desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Safari/605.1.15";
  final String _mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Mobile/15E148 Safari/604.1";

  // ☢️ 核心脚本：防黑屏 + 接收画质指令
  final String _coreScript = """
    console.log("☢️ Core Script Loaded");

    // 1. 【防黑屏】暴力禁止系统播放器
    var observer = new MutationObserver(function(mutations) {
        var videos = document.querySelectorAll('video');
        videos.forEach(function(video) {
            if (!video.hasAttribute('playsinline')) {
                video.setAttribute('playsinline', 'true');
                video.setAttribute('webkit-playsinline', 'true');
            }
            // 强制显示视频层
            video.style.visibility = 'visible';
            video.style.display = 'block';
        });
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });

    // 2. 【视口欺骗】
    var meta = document.querySelector('meta[name="viewport"]');
    if (!meta) { meta = document.createElement('meta'); document.head.appendChild(meta); }
    meta.name = 'viewport';
    meta.content = 'width=1920, initial-scale=1.0, maximum-scale=1.0, user-scalable=yes';

    // 3. 【UI 净化】
    var style = document.createElement('style');
    style.innerHTML = `
      body, html, ytd-app { background: #000 !important; width: 100vw !important; height: 100vh !important; overflow: hidden !important; }
      #masthead-container, #secondary, #comments, #related, .ytp-chrome-top { display: none !important; }
      .ytp-fullscreen-button { display: none !important; } /* 删掉全屏按钮 */
      #player { position: fixed !important; top: 0 !important; left: 0 !important; width: 100vw !important; height: 100vh !important; z-index: 1 !important; }
      video { object-fit: contain !important; }
    `;
    document.head.appendChild(style);

    // 4. 【外挂接口】供 Flutter 调用
    window.forceQuality = function(quality) {
        console.log("🚀 Forcing quality: " + quality);
        var player = document.getElementById('movie_player');
        if (player && player.setPlaybackQualityRange) {
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

  // 🔥 核心：显示我们自己的画质菜单
  void _showQualitySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF222222),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("强制画质选择 (Bypass)", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text("YouTube 菜单已隐藏，请直接在此选择：", style: TextStyle(color: Colors.grey[400], fontSize: 12)),
            const Divider(color: Colors.white10),
            _buildQualityOption("🚀 4K / 2160p", "highres"),
            _buildQualityOption("📺 2K / 1440p", "hd1440"),
            _buildQualityOption("💿 1080p HD", "hd1080"),
            _buildQualityOption("📱 720p", "hd720"),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityOption(String label, String code) {
    return ListTile(
      leading: const Icon(Icons.high_quality, color: Colors.blueAccent),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: () {
        Navigator.pop(context);
        // 调用 JS 强制切换
        webViewController?.evaluateJavascript(source: "window.forceQuality('$code');");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("已请求: $label"), duration: const Duration(seconds: 1)));
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
              UserScript(source: _coreScript, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: true),
            ]),
            initialSettings: InAppWebViewSettings(
              userAgent: _desktopUA,
              preferredContentMode: UserPreferredContentMode.DESKTOP,
              allowsInlineMediaPlayback: true, // 必开
              mediaPlaybackRequiresUserGesture: false,
              useWideViewPort: true,
              loadWithOverviewMode: true,
              isInspectable: true,
              supportZoom: true,
            ),
            onWebViewCreated: (controller) => webViewController = controller,
            onLoadStop: (controller, url) async {
              await controller.evaluateJavascript(source: _coreScript);
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
                                Text(_isLoginMode ? "Login Mode" : "God Mode 4K", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(_isLoginMode ? "完成登录后切回" : "使用右上角按钮切画质", style: TextStyle(color: _isLoginMode ? Colors.amber : Colors.greenAccent, fontSize: 10))
                            ]
                        ),
                        const Spacer(),
                        
                        if (!_isLoginMode)
                          ElevatedButton.icon(
                            icon: const Icon(Icons.settings, size: 14),
                            label: const Text("强制画质"),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent, foregroundColor: Colors.white),
                            onPressed: _showQualitySheet,
                          ),
                        
                        const SizedBox(width: 8),
                        
                        // 模式切换
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

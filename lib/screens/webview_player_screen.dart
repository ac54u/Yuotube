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

  // 🖥️ 桌面身份 (Mac Safari - 这是解锁 4K 且不黑屏的最佳选择)
  // Windows Chrome 有时会触发 Google 的安全警报，Mac Safari 在 iPhone 上更“原生”
  final String _desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Safari/605.1.15";
  
  // 📱 手机身份 (仅用于登录)
  final String _mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_3 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Mobile/15E148 Safari/604.1";

  // ☢️ 核弹级修复脚本
  final String _nuclearFixScript = """
    console.log("☢️ Nuclear Fix Loaded");

    // 1. 【防黑屏绝杀】MutationObserver 实时监控
    // 只要视频标签出现，立刻打上“禁止全屏”的钢印
    var observer = new MutationObserver(function(mutations) {
        var videos = document.querySelectorAll('video');
        videos.forEach(function(video) {
            // 强制内联
            if (!video.hasAttribute('playsinline')) {
                video.setAttribute('playsinline', 'true');
                video.setAttribute('webkit-playsinline', 'true');
                console.log("🔒 Video locked to inline");
            }
            // 修复黑屏：强制可见性
            video.style.visibility = 'visible';
            video.style.opacity = '1';
            video.style.display = 'block';
        });
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });

    // 2. 【4K 视口欺骗】
    // 告诉 YouTube 这是一个 1920x1080 的显示器
    var meta = document.querySelector('meta[name="viewport"]');
    if (!meta) { meta = document.createElement('meta'); document.head.appendChild(meta); }
    meta.name = 'viewport';
    meta.content = 'width=1920, initial-scale=1.0, maximum-scale=1.0, user-scalable=yes';

    // 3. 【画质暴力轮询】
    setInterval(() => {
        var player = document.getElementById('movie_player');
        if (player && player.setPlaybackQualityRange) {
             // 只有当画质极低（360p/240p）时才干预，防止打断用户
             var q = player.getPlaybackQuality();
             if(q === 'small' || q === 'medium' || q === 'tiny') {
                 player.setPlaybackQualityRange('highres', 'highres');
                 console.log("⚡ Upgrading quality from " + q);
             }
        }
    }, 3000);

    // 4. 【UI 深度净化】
    var style = document.createElement('style');
    style.innerHTML = `
      /* 背景纯黑 */
      body, html, ytd-app { background: #000 !important; width: 100vw !important; height: 100vh !important; overflow: hidden !important; }
      
      /* 隐藏所有干扰 */
      #masthead-container, #secondary, #comments, #related, ytd-merch-shelf-renderer { display: none !important; }
      .ytp-chrome-top { display: none !important; }
      
      /* 🔥 彻底干掉全屏按钮 - 防止误触触发系统黑屏 */
      .ytp-fullscreen-button { display: none !important; }
      
      /* 播放器强制铺满 */
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

  // 切换模式 (登录 vs 看片)
  Future<void> _switchMode(bool loginMode) async {
    setState(() {
      _isLoading = true;
      _isLoginMode = loginMode;
    });

    // 切换 UA 和 视口模式
    await webViewController?.setSettings(settings: InAppWebViewSettings(
      userAgent: loginMode ? _mobileUA : _desktopUA,
      preferredContentMode: loginMode ? UserPreferredContentMode.MOBILE : UserPreferredContentMode.DESKTOP,
      useWideViewPort: !loginMode, // 桌面模式开启宽视口
      loadWithOverviewMode: !loginMode,
      allowsInlineMediaPlayback: true, // 始终开启防劫持
    ));

    // 登录模式跳转登录页，看片模式跳转视频页
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
                source: _nuclearFixScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                forMainFrameOnly: true,
              ),
            ]),
            initialSettings: InAppWebViewSettings(
              // 🔥 默认为桌面模式 (这是 4K 的前提)
              userAgent: _desktopUA,
              preferredContentMode: UserPreferredContentMode.DESKTOP,
              
              // 🔥 核心防黑屏配置
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
              // 二次注入确保生效
              await controller.evaluateJavascript(source: _nuclearFixScript);
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
                                Text(_isLoginMode ? "Login Mode" : "Mac Desktop 4K", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(_isLoginMode ? "请登录，完成后切回 4K" : "已伪装 Mac • 防黑屏", style: TextStyle(color: _isLoginMode ? Colors.amber : Colors.greenAccent, fontSize: 10))
                            ]
                        ),
                        const Spacer(),
                        
                        // 🔥 模式切换 (解决一切问题的钥匙)
                        ElevatedButton.icon(
                            icon: Icon(_isLoginMode ? Icons.movie : Icons.login, size: 14),
                            label: Text(_isLoginMode ? "切回看片" : "去登录"),
                            style: ElevatedButton.styleFrom(
                                backgroundColor: _isLoginMode ? Colors.green : Colors.blueAccent, 
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            onPressed: () => _switchMode(!_isLoginMode),
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

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
  
  // 默认为桌面模式 (为了画质)
  bool _isDesktopMode = true; 

  // 🖥️ 桌面身份 (Windows Chrome - 解锁 4K 的关键)
  final String _desktopUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";
  // 📱 手机身份 (仅用于登录)
  final String _mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1";

  // 🔥 核心修复脚本：
  // 1. 欺骗分辨率
  // 2. 移除原生全屏干扰
  // 3. 暴力设置画质
  final String _fixScript = """
    // A. 视口欺骗 (让 YouTube 以为是 1080p 显示器)
    var meta = document.querySelector('meta[name="viewport"]');
    if (!meta) {
        meta = document.createElement('meta');
        meta.name = 'viewport';
        document.head.appendChild(meta);
    }
    meta.content = 'width=1920, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';

    // B. 屏幕参数欺骗
    try {
        Object.defineProperty(window.screen, 'width', { get: () => 1920 });
        Object.defineProperty(window.screen, 'height', { get: () => 1080 });
        Object.defineProperty(window, 'availWidth', { get: () => 1920 });
        Object.defineProperty(window, 'availHeight', { get: () => 1080 });
        Object.defineProperty(window, 'devicePixelRatio', { get: () => 2.0 });
    } catch(e) {}

    // C. 样式修正 (修复黑屏/白边)
    var style = document.createElement('style');
    style.innerHTML = `
      /* 强制背景纯黑 */
      body, html, ytd-app { background-color: #000 !important; width: 100vw !important; height: 100vh !important; overflow: hidden !important; }
      
      /* 隐藏干扰元素 */
      #masthead-container, #secondary, #below, #comments, #related, .ytp-chrome-top { display: none !important; }
      
      /* 强制播放器铺满，禁止原生全屏接管 */
      #player { position: fixed !important; top: 0 !important; left: 0 !important; width: 100vw !important; height: 100vh !important; z-index: 1 !important; }
      video { object-fit: contain !important; width: 100% !important; height: 100% !important; }
      
      /* 隐藏全屏按钮 (防止误触导致系统黑屏) */
      .ytp-fullscreen-button { display: none !important; }
    `;
    document.head.appendChild(style);

    // D. 画质轮询 (每2秒敲打一次)
    setInterval(() => {
        var player = document.getElementById('movie_player');
        if (player && player.setPlaybackQualityRange) {
            // 优先 4K, 其次 1080p
            player.setPlaybackQualityRange('highres', 'highres');
            var q = player.getPlaybackQuality();
            if(q == 'small' || q == 'medium' || q == 'large') {
                player.setPlaybackQuality('hd1080');
            }
        }
        // 尝试自动播放
        var video = document.querySelector('video');
        if(video && video.paused) video.play();
    }, 2000);
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

  // 切换模式 (核心防黑屏逻辑)
  Future<void> _switchMode(bool toDesktop) async {
    setState(() => _isLoading = true);
    _isDesktopMode = toDesktop;
    
    // 强制清理缓存，防止旧的移动版页面残留导致黑屏
    if (toDesktop) {
      await webViewController?.clearCache();
    }

    await webViewController?.setSettings(settings: InAppWebViewSettings(
      userAgent: toDesktop ? _desktopUA : _mobileUA,
      preferredContentMode: toDesktop ? UserPreferredContentMode.DESKTOP : UserPreferredContentMode.MOBILE,
      useWideViewPort: toDesktop,
      loadWithOverviewMode: toDesktop,
      allowsInlineMediaPlayback: true, // 🔥 关键：禁止原生全屏
    ));
    
    // 重新加载 URL 而不是 reload，确保 Headers 生效
    webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri("https://www.youtube.com/watch?v=${widget.videoId}")));
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
              UserScript(source: _fixScript, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END, forMainFrameOnly: true),
            ]),
            initialSettings: InAppWebViewSettings(
              // 🔥 默认桌面模式
              preferredContentMode: UserPreferredContentMode.DESKTOP,
              userAgent: _desktopUA,
              
              // 🔥 iOS 防黑屏关键设置
              allowsInlineMediaPlayback: true, // 必须为 true
              allowsAirPlayForMediaPlayback: false,
              allowsPictureInPictureMediaPlayback: false, // 关闭画中画防止冲突
              
              mediaPlaybackRequiresUserGesture: false,
              useWideViewPort: true,
              loadWithOverviewMode: true,
              isInspectable: true,
              supportZoom: true,
            ),
            
            onWebViewCreated: (controller) => webViewController = controller,

            // 自动检测登录页
            onLoadStart: (controller, url) async {
              String urlStr = url.toString();
              if (urlStr.contains("accounts.google.com") && _isDesktopMode) {
                 _switchMode(false); // 自动切手机模式登录
              }
            },

            onLoadStop: (controller, url) async {
              await controller.evaluateJavascript(source: _fixScript);
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
                                Text(_isDesktopMode ? "4K Desktop" : "Login Mode", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(_isDesktopMode ? "防黑屏增强版" : "请登录", style: TextStyle(color: _isDesktopMode ? Colors.greenAccent : Colors.amber, fontSize: 10))
                            ]
                        ),
                        const Spacer(),
                        
                        // 登录切换
                        if (!_isDesktopMode)
                        ElevatedButton(
                            child: const Text("切回4K模式"),
                            onPressed: () => _switchMode(true),
                        ),

                        const SizedBox(width: 8),
                        
                        // 🔥 救砖按钮：重置内核 (黑屏点这个)
                        IconButton(
                          icon: const Icon(Icons.cleaning_services, color: Colors.redAccent),
                          tooltip: "黑屏修复",
                          onPressed: () {
                            setState(() => _isLoading = true);
                            // 强制清除所有缓存并重载
                            webViewController?.clearCache();
                            webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri("https://www.youtube.com/watch?v=${widget.videoId}")));
                          },
                        ),
                        
                        // 普通刷新
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

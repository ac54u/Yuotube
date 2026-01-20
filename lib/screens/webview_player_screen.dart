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

  // 🖥️ 桌面身份 (4K)
  final String _desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";
  // 📱 登录身份 (Android)
  final String _mobileUA = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36";

  // 🔥 核心脚本：伪造宽屏 + 强制 4K
  final String _resolutionHackScript = """
    // 1. 强制修改 Viewport (把手机窄屏伪装成 1920 宽屏)
    // 这是解锁 4K 选项的最关键一步！
    var meta = document.querySelector('meta[name="viewport"]');
    if (meta) {
        meta.setAttribute('content', 'width=1920, initial-scale=1.0');
    } else {
        var newMeta = document.createElement('meta');
        newMeta.name = 'viewport';
        newMeta.content = 'width=1920, initial-scale=1.0';
        document.getElementsByTagName('head')[0].appendChild(newMeta);
    }

    // 2. 欺骗 JS 层面的屏幕宽度
    Object.defineProperty(window.screen, 'width', { get: () => 3840 });
    Object.defineProperty(window.screen, 'height', { get: () => 2160 });
    Object.defineProperty(window, 'innerWidth', { get: () => 1920 });
    Object.defineProperty(window, 'innerHeight', { get: () => 1080 });
    Object.defineProperty(window, 'devicePixelRatio', { get: () => 2.0 });

    // 3. 暴力轮询设置画质
    setInterval(() => {
        var player = document.getElementById('movie_player');
        if (player && player.setPlaybackQualityRange) {
            // 尝试设定最高画质
            player.setPlaybackQualityRange('highres', 'highres');
            // 如果卡在 360p，尝试强制切 1080p+
            if(player.getPlaybackQuality() === 'medium' || player.getPlaybackQuality() === 'small') {
                 player.setPlaybackQuality('hd1080'); 
                 player.setPlaybackQuality('hd2160');
            }
        }
    }, 3000);
  """;

  // 🧹 UI 修复脚本 (解决白边和居中问题)
  final String _cssFixScript = """
    var style = document.createElement('style');
    style.innerHTML = `
      /* 隐藏干扰元素 */
      #masthead-container, #secondary, #below, #comments, #related, ytd-merch-shelf-renderer { display: none !important; }
      .ytp-chrome-top, .ytp-show-cards-title { display: none !important; }
      ytd-popup-container { display: none !important; } /* 隐藏弹窗 */
      
      /* 🔥 强制全屏铺满，不留白边 */
      body, html, ytd-app { 
          background: #000 !important; 
          width: 100vw !important; 
          height: 100vh !important; 
          overflow: hidden !important; 
          margin: 0 !important;
          padding: 0 !important;
      }
      
      #page-manager { margin: 0 !important; width: 100% !important; height: 100% !important; }
      #primary { padding: 0 !important; margin: 0 !important; max-width: 100% !important; width: 100% !important; }
      
      /* 播放器强制居中放大 */
      #player { 
          position: fixed !important; 
          top: 0 !important; 
          left: 0 !important; 
          width: 100vw !important; 
          height: 100vh !important; 
          z-index: 1 !important; 
      }
      #player-container-outer, #player-container-inner, .html5-video-container, video {
          width: 100% !important;
          height: 100% !important;
      }
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
                source: _resolutionHackScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END, // 改为 End 确保覆盖原有的 meta 标签
                forMainFrameOnly: true,
              ),
            ]),
            initialSettings: InAppWebViewSettings(
              preferredContentMode: UserPreferredContentMode.DESKTOP,
              userAgent: _desktopUA, // 默认桌面身份
              
              allowsInlineMediaPlayback: true,
              mediaPlaybackRequiresUserGesture: false,
              
              // 🔥 关键设置：允许缩放，开启宽屏概览
              useWideViewPort: true,
              loadWithOverviewMode: true,
              
              isInspectable: true,
              supportZoom: true,
              
              // 混合渲染模式 (Android)
              useHybridComposition: true,
            ),
            
            onWebViewCreated: (controller) => webViewController = controller,

            // 🔥 身份切换逻辑 (变色龙)
            onLoadStart: (controller, url) async {
              String urlStr = url.toString();
              if (urlStr.contains("accounts.google.com")) {
                // 切 Android 登录
                await controller.setSettings(settings: InAppWebViewSettings(
                  userAgent: _mobileUA,
                  preferredContentMode: UserPreferredContentMode.MOBILE,
                ));
              } else if (urlStr.contains("youtube.com") && !urlStr.contains("accounts")) {
                // 切 Desktop 看片
                var currentUA = await controller.getSettings().then((s) => s?.userAgent);
                if (currentUA != _desktopUA) {
                   await controller.setSettings(settings: InAppWebViewSettings(
                    userAgent: _desktopUA,
                    preferredContentMode: UserPreferredContentMode.DESKTOP,
                    useWideViewPort: true, // 确保宽屏
                  ));
                  controller.reload(); // 必须刷新才能生效
                }
              }
            },

            shouldOverrideUrlLoading: (controller, navigationAction) async {
              var uri = navigationAction.request.url!;
              if (!["http", "https"].contains(uri.scheme)) return NavigationActionPolicy.CANCEL;
              return NavigationActionPolicy.ALLOW;
            },

            onLoadStop: (controller, url) async {
              await controller.evaluateJavascript(source: _cssFixScript);
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
                        const Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                    Text("Logged In • Cinema Mode", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                    Text("Force 1920px Viewport", style: TextStyle(color: Colors.amber, fontSize: 10))
                                ]
                            )
                        ),
                        // 登录按钮
                        TextButton.icon(
                            icon: const Icon(Icons.login, size: 16, color: Colors.white),
                            label: const Text("登录修复", style: TextStyle(color: Colors.white)),
                            style: TextButton.styleFrom(backgroundColor: Colors.blueAccent.withOpacity(0.3)),
                            onPressed: () {
                                webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri("https://accounts.google.com/ServiceLogin?service=youtube")));
                            },
                        ),
                        const SizedBox(width: 8),
                        // 刷新按钮 (关键)
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white70),
                          tooltip: "画质不行点这里",
                          onPressed: () {
                            setState(() => _isLoading = true);
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

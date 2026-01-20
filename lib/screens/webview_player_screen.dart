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
  bool _showControls = false; // 默认隐藏
  Timer? _hideTimer;

  // 🖥️ 4K 伪装身份 (Windows Chrome)
  final String _desktopUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";
  
  // 📱 登录专用身份 (Android Chrome) - 这个身份可以通过 Google 安全检查
  final String _mobileUA = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36";

  // 🔥 4K 暴力脚本
  final String _enforce4KScript = """
    try {
        Object.defineProperty(window.screen, 'width', { get: () => 3840 });
        Object.defineProperty(window.screen, 'height', { get: () => 2160 });
        Object.defineProperty(window, 'devicePixelRatio', { get: () => 2.0 });
        
        setInterval(() => {
            var player = document.getElementById('movie_player');
            if (player && player.setPlaybackQualityRange) {
                player.setPlaybackQualityRange('highres', 'highres'); 
                if(player.getPlaybackQuality() !== 'hd2160') player.setPlaybackQuality('hd2160');
            }
        }, 2000);
    } catch(e) {}
  """;

  // 🧹 UI 净化脚本
  final String _uiCleanupScript = """
    var style = document.createElement('style');
    style.innerHTML = `
      #masthead-container, #secondary, #below, #comments, #related, ytd-merch-shelf-renderer { display: none !important; }
      ytd-app { background: #000 !important; }
      #page-manager { margin: 0 !important; }
      #primary { padding: 0 !important; margin: 0 !important; max-width: 100% !important; }
      #player { position: fixed !important; top: 0 !important; left: 0 !important; width: 100vw !important; height: 100vh !important; z-index: 1 !important; }
      .ytp-chrome-top, .ytp-show-cards-title, .ytp-watermark { display: none !important; }
      /* 隐藏登录弹窗 (如果已经登录了就不需要显示) */
      ytd-popup-container { display: none !important; }
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
              // 回归官网 Watch 模式 (只有这模式能看 4K + 登录)
              url: WebUri("https://www.youtube.com/watch?v=${widget.videoId}"),
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(
                source: _enforce4KScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                forMainFrameOnly: true,
              ),
            ]),
            initialSettings: InAppWebViewSettings(
              // 默认先用桌面模式 (为了 4K)
              preferredContentMode: UserPreferredContentMode.DESKTOP,
              userAgent: _desktopUA,
              
              allowsInlineMediaPlayback: true,
              mediaPlaybackRequiresUserGesture: false,
              useWideViewPort: true,
              loadWithOverviewMode: true,
              isInspectable: true,
              supportZoom: true,
            ),
            
            onWebViewCreated: (controller) => webViewController = controller,

            // 🔥🔥🔥 核心魔法：智能变身逻辑
            onLoadStart: (controller, url) async {
              String urlStr = url.toString();
              
              // 1. 如果检测到是 Google 登录页 -> 变身安卓手机 (允许登录)
              if (urlStr.contains("accounts.google.com") || urlStr.contains("google.com/signin")) {
                print("🛑 检测到登录页，切换为移动端身份以绕过安全检查...");
                await controller.setSettings(settings: InAppWebViewSettings(
                  userAgent: _mobileUA, // 切换 UA
                  preferredContentMode: UserPreferredContentMode.MOBILE,
                ));
              }
              
              // 2. 如果登录完成回到了 YouTube -> 变身回 Windows 电脑 (为了 4K)
              else if (urlStr.contains("youtube.com") && !urlStr.contains("accounts.google.com")) {
                // 获取当前 UA 检查是否需要切换
                String? currentUA = await controller.getSettings().then((s) => s?.userAgent);
                if (currentUA != _desktopUA) {
                  print("✅ 检测到回到 YouTube，切回桌面 4K 身份...");
                  await controller.setSettings(settings: InAppWebViewSettings(
                    userAgent: _desktopUA,
                    preferredContentMode: UserPreferredContentMode.DESKTOP,
                  ));
                  // 强制刷新以生效桌面版界面
                  controller.reload(); 
                }
              }
            },

            // 🔥 路由锁死：防止白屏跳转 App
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              var uri = navigationAction.request.url!;
              
              // 禁止唤起外部 App (YouTube / Google)
              if (!["http", "https", "about", "data"].contains(uri.scheme)) {
                 print("🛑 拦截外部 App 跳转: ${uri.scheme}");
                 return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },

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
                        const Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                    Text("Chameleon Mode", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                    Text("Login Support • 4K Auto", style: TextStyle(color: Colors.greenAccent, fontSize: 10))
                                ]
                            )
                        ),
                        // 强制登录按钮
                        TextButton.icon(
                            icon: const Icon(Icons.login, size: 16, color: Colors.white),
                            label: const Text("去登录", style: TextStyle(color: Colors.white)),
                            style: TextButton.styleFrom(backgroundColor: Colors.blueAccent.withOpacity(0.3)),
                            onPressed: () {
                                // 手动强制跳转登录页
                                webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri("https://accounts.google.com/ServiceLogin?service=youtube")));
                            },
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white70),
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

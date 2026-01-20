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
  
  // 当前模式标记
  bool _isDesktopMode = true; 

  // 🖥️ 桌面身份 (解锁 4K)
  final String _desktopUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";
  // 📱 手机身份 (用于登录)
  final String _mobileUA = "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Mobile Safari/537.36";

  // 🔥 画面适配 + 4K 解锁脚本
  final String _fixScript = """
    // 1. 强制铺满全屏，修复黑边/白边
    var style = document.createElement('style');
    style.innerHTML = `
      body, html, ytd-app { background: #000 !important; width: 100vw !important; height: 100vh !important; overflow: hidden !important; margin: 0 !important; }
      #masthead-container, #secondary, #below, #comments, #related { display: none !important; }
      .ytp-chrome-top, .ytp-show-cards-title { display: none !important; }
      
      /* 强制播放器居中且覆盖全屏 */
      #player { position: fixed !important; top: 0 !important; left: 0 !important; width: 100vw !important; height: 100vh !important; z-index: 1 !important; }
      video { object-fit: contain !important; width: 100% !important; height: 100% !important; }
    `;
    document.head.appendChild(style);

    // 2. 欺骗 YouTube 我是大屏幕 (解锁 4K 选项的关键)
    try {
        Object.defineProperty(window.screen, 'width', { get: () => 3840 });
        Object.defineProperty(window.screen, 'height', { get: () => 2160 });
        Object.defineProperty(window, 'devicePixelRatio', { get: () => 2.0 });
    } catch(e) {}

    // 3. 自动切画质
    setInterval(() => {
        var player = document.getElementById('movie_player');
        if (player && player.setPlaybackQualityRange) {
            player.setPlaybackQualityRange('highres', 'highres'); 
            if(player.getPlaybackQuality() == 'small' || player.getPlaybackQuality() == 'medium') {
                player.setPlaybackQuality('hd1080');
            }
        }
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

  // 🔥 核心功能：手动切换 电脑/手机 模式
  Future<void> _switchMode(bool toDesktop) async {
    setState(() => _isLoading = true);
    _isDesktopMode = toDesktop;
    
    await webViewController?.setSettings(settings: InAppWebViewSettings(
      userAgent: toDesktop ? _desktopUA : _mobileUA,
      preferredContentMode: toDesktop ? UserPreferredContentMode.DESKTOP : UserPreferredContentMode.MOBILE,
      useWideViewPort: toDesktop, // 电脑模式开启宽屏
      loadWithOverviewMode: toDesktop,
    ));
    
    webViewController?.reload();
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
              preferredContentMode: UserPreferredContentMode.DESKTOP, // 默认尝试桌面
              userAgent: _desktopUA,
              allowsInlineMediaPlayback: true,
              mediaPlaybackRequiresUserGesture: false,
              useWideViewPort: true,
              loadWithOverviewMode: true,
              isInspectable: true,
              supportZoom: true, // 允许手势缩放以适应屏幕
            ),
            
            onWebViewCreated: (controller) => webViewController = controller,

            // 智能检测：如果掉到了登录页，自动切手机模式方便输入
            onLoadStart: (controller, url) async {
              String urlStr = url.toString();
              if (urlStr.contains("accounts.google.com") && _isDesktopMode) {
                print("自动切换到手机模式以允许登录...");
                // 不要自动 setState 刷新 UI，只改内核
                 _switchMode(false); 
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
                                Text(_isDesktopMode ? "4K Desktop Mode" : "Login/Mobile Mode", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(_isDesktopMode ? "已伪装成电脑 • 画质解锁" : "已伪装成手机 • 仅限登录", style: TextStyle(color: _isDesktopMode ? Colors.greenAccent : Colors.amber, fontSize: 10))
                            ]
                        ),
                        const Spacer(),
                        
                        // 🔥 模式切换按钮
                        TextButton.icon(
                            icon: Icon(_isDesktopMode ? Icons.phone_android : Icons.desktop_windows, size: 16, color: Colors.white),
                            label: Text(_isDesktopMode ? "切手机(登录用)" : "切电脑(看4K)", style: const TextStyle(color: Colors.white)),
                            style: TextButton.styleFrom(backgroundColor: Colors.blueAccent.withOpacity(0.4)),
                            onPressed: () => _switchMode(!_isDesktopMode),
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

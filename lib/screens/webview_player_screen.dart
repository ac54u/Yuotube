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

  // 🖥️ 桌面身份 (Windows Chrome - 解锁 4K 的唯一真神)
  final String _desktopUA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36";
  // 📱 手机身份 (仅用于登录)
  final String _mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1";

  // 🔥 核心脚本：防跳转 + 解锁 4K
  final String _coreScript = """
    // 1. 暴力禁止 iOS 原生播放器接管 (关键修复!)
    // 每 500ms 检查一次视频标签，强行加上 playsinline
    setInterval(() => {
        var videos = document.querySelectorAll('video');
        videos.forEach(video => {
            if (!video.hasAttribute('playsinline')) {
                video.setAttribute('playsinline', 'true');
                video.setAttribute('webkit-playsinline', 'true');
                // 如果视频暂停了，尝试静音播放一帧来激活
                if(video.paused) { video.muted = true; video.play(); }
            }
        });
    }, 500);

    // 2. 视口欺骗 (让 YouTube 以为是 1080p 显示器)
    var meta = document.querySelector('meta[name="viewport"]');
    if (!meta) {
        meta = document.createElement('meta');
        meta.name = 'viewport';
        document.head.appendChild(meta);
    }
    meta.content = 'width=1920, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';

    // 3. 屏幕参数欺骗
    try {
        Object.defineProperty(window.screen, 'width', { get: () => 3840 });
        Object.defineProperty(window.screen, 'height', { get: () => 2160 });
        Object.defineProperty(window, 'devicePixelRatio', { get: () => 2.0 });
    } catch(e) {}

    // 4. 样式修正 (修复黑屏/白边)
    var style = document.createElement('style');
    style.innerHTML = `
      body, html, ytd-app { background-color: #000 !important; width: 100vw !important; height: 100vh !important; overflow: hidden !important; }
      #masthead-container, #secondary, #below, #comments, #related, .ytp-chrome-top { display: none !important; }
      
      /* 强制播放器铺满 */
      #player { position: fixed !important; top: 0 !important; left: 0 !important; width: 100vw !important; height: 100vh !important; z-index: 1 !important; }
      video { object-fit: contain !important; width: 100% !important; height: 100% !important; }
    `;
    document.head.appendChild(style);

    // 5. 画质轮询
    setInterval(() => {
        var player = document.getElementById('movie_player');
        if (player && player.setPlaybackQualityRange) {
            player.setPlaybackQualityRange('highres', 'highres');
            var q = player.getPlaybackQuality();
            if(q == 'small' || q == 'medium' || q == 'large') {
                player.setPlaybackQuality('hd1080');
            }
        }
    }, 3000);
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
    
    // 切换模式时清理缓存，防止页面结构错乱
    await webViewController?.clearCache();

    await webViewController?.setSettings(settings: InAppWebViewSettings(
      userAgent: toDesktop ? _desktopUA : _mobileUA,
      preferredContentMode: toDesktop ? UserPreferredContentMode.DESKTOP : UserPreferredContentMode.MOBILE,
      useWideViewPort: toDesktop,
      loadWithOverviewMode: toDesktop,
      allowsInlineMediaPlayback: true, // 始终保持开启
    ));
    
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
              UserScript(source: _coreScript, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END, forMainFrameOnly: true),
            ]),
            initialSettings: InAppWebViewSettings(
              // 🔥 默认桌面模式 (这是 4K 的关键)
              preferredContentMode: UserPreferredContentMode.DESKTOP,
              userAgent: _desktopUA,
              
              // 🔥 iOS 必须开启这两个才能防止原生播放器接管
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
                                Text(_isDesktopMode ? "4K Cinema Mode" : "Login Mode (Low Res)", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                Text(_isDesktopMode ? "已注入防跳转脚本" : "请在此模式登录，然后切回电脑", style: TextStyle(color: _isDesktopMode ? Colors.greenAccent : Colors.amber, fontSize: 10))
                            ]
                        ),
                        const Spacer(),
                        
                        // 🔥 模式切换按钮 (这是解决一切问题的钥匙)
                        ElevatedButton.icon(
                            icon: Icon(_isDesktopMode ? Icons.phone_android : Icons.desktop_mac, size: 14),
                            label: Text(_isDesktopMode ? "切手机(登录)" : "切电脑(4K)"),
                            style: ElevatedButton.styleFrom(backgroundColor: _isDesktopMode ? Colors.grey[800] : Colors.blueAccent, foregroundColor: Colors.white),
                            onPressed: () => _switchMode(!_isDesktopMode),
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

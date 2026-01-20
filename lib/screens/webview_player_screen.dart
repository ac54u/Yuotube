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

  // 🔥 4K 智能锁画质脚本 (带 Debug 回显)
  final String _smartQualityScript = """
    // 1. 创建一个悬浮 Debug 窗口，让你亲眼看到 Youtube 到底给了什么画质
    var debugDiv = document.createElement('div');
    debugDiv.style.cssText = 'position:fixed; top:10px; left:10px; z-index:99999; color:#0f0; background:rgba(0,0,0,0.7); padding:5px; font-size:10px; pointer-events:none; max-width:300px; word-wrap:break-word;';
    debugDiv.id = 'yt-debug-overlay';
    document.body.appendChild(debugDiv);
    
    function log(msg) {
        var d = document.getElementById('yt-debug-overlay');
        if(d) d.innerText = msg;
    }

    try {
        // 2. 屏幕欺骗 (Screen Spoofing) - 必须非常激进
        Object.defineProperty(window.screen, 'width', { get: () => 3840 });
        Object.defineProperty(window.screen, 'height', { get: () => 2160 });
        Object.defineProperty(window, 'devicePixelRatio', { get: () => 3.0 }); // 提升 DPI 权重
        Object.defineProperty(window, 'innerWidth', { get: () => 3840 }); // 告诉 Embed 容器我有这么宽

        // 3. 循环检测逻辑
        setInterval(() => {
            var player = document.getElementById('movie_player');
            if (player && player.getAvailableQualityLevels) {
                
                // A. 获取真实可用列表
                var levels = player.getAvailableQualityLevels();
                var current = player.getPlaybackQuality();
                
                // B. 回显给用户看 (关键一步)
                log('Available: ' + JSON.stringify(levels) + '\\nCurrent: ' + current);
                
                // C. 智能选择策略
                if (levels && levels.length > 0) {
                    // 优先找 4K/8K
                    var target = 'hd1080'; // 保底
                    if (levels.includes('highres')) target = 'highres';
                    else if (levels.includes('hd2160')) target = 'hd2160';
                    else if (levels.includes('hd1440')) target = 'hd1440';
                    
                    // 只有当当前画质不达标时，才发送请求，避免死循环
                    if (current !== target && current !== 'highres') {
                        player.setPlaybackQualityRange(target, target);
                        player.setPlaybackQuality(target);
                        console.log('Attempting upgrade to: ' + target);
                    }
                }
            } else {
                log('Waiting for player API...');
            }
        }, 1000);
    } catch(e) {
        log('Error: ' + e);
    }
  """;

  final String _uiCleanupScript = """
    var style = document.createElement('style');
    style.innerHTML = `
      .ytp-chrome-top, .ytp-show-cards-title, .ytp-pause-overlay, .ytp-watermark, .ytp-upnext { display: none !important; }
      body, html { margin: 0; padding: 0; background: #000; overflow: hidden; }
      #movie_player { width: 100vw !important; height: 100vh !important; }
    `;
    document.head.appendChild(style);
  """;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeRight, DeviceOrientation.landscapeLeft]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    CookieManager.instance().deleteAllCookies();
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
              // Embed 模式 + 这里的 Referer 是绕过 153 和 登录墙 的关键
              url: WebUri("https://www.youtube.com/embed/${widget.videoId}?autoplay=1&controls=1&rel=0&playsinline=1&modestbranding=1&enablejsapi=1"),
              headers: {"Referer": "https://www.youtube.com/watch?v=${widget.videoId}"},
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(
                source: _smartQualityScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                forMainFrameOnly: true,
              ),
            ]),
            initialSettings: InAppWebViewSettings(
              preferredContentMode: UserPreferredContentMode.DESKTOP,
              allowsInlineMediaPlayback: true,
              mediaPlaybackRequiresUserGesture: false,
              useWideViewPort: true,
              loadWithOverviewMode: true,
              // 使用 Chrome 桌面 UA，配合上面的 Screen Spoof
              userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
              isInspectable: true,
              supportZoom: false,
            ),
            onWebViewCreated: (controller) => webViewController = controller,
            onLoadStop: (controller, url) async {
              await controller.evaluateJavascript(source: _uiCleanupScript);
              if (mounted) setState(() => _isLoading = false);
            },
          ),

          if (_isLoading)
            Container(color: Colors.black, child: const Center(child: CircularProgressIndicator(color: Colors.redAccent))),

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
                        InkWell(onTap: () => Navigator.pop(context), child: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.arrow_back, color: Colors.white, size: 24))),
                        const SizedBox(width: 16),
                        const Text("Debug Mode • Checking Levels...", style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                        const Spacer(),
                        IconButton(icon: const Icon(Icons.refresh, color: Colors.white70), onPressed: () { setState(() => _isLoading = true); webViewController?.reload(); }),
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

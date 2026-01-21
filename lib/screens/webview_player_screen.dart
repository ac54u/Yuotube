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

  // 🔥 终极身份：iPad Pro (iPadOS 16)
  // 它的权重极高，Google 认为它是移动设备(允许登录)，但又认为它是高性能设备(给 4K)
  final String _ipadUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Safari/605.1.15";

  // ☢️ 核弹脚本：包含 防劫持 + 4K 解锁 + UI 修复
  // 必须在 AT_DOCUMENT_START (网页刚开始加载时) 注入，抢在 YouTube JS 执行前生效
  final String _nuclearScript = """
    console.log("☢️ Nuclear Script Loaded");

    // 1. 【防劫持核心】暴力给 video 标签加锁
    // 监听 DOM 变化，只要出现 video 标签，立刻加上 playsinline 属性
    // 这能 100% 阻止 iOS 系统播放器弹出
    var observer = new MutationObserver(function(mutations) {
        var videos = document.querySelectorAll('video');
        videos.forEach(function(video) {
            if (!video.hasAttribute('playsinline')) {
                video.setAttribute('playsinline', 'true');
                video.setAttribute('webkit-playsinline', 'true');
                console.log("🔒 Video locked to inline mode");
            }
        });
    });
    observer.observe(document.documentElement, { childList: true, subtree: true });

    // 2. 【4K 解锁】视口欺骗
    // 强制把 Viewport 改成 1920 宽，骗 YouTube 开启桌面级画质
    var meta = document.querySelector('meta[name="viewport"]');
    if (!meta) {
        meta = document.createElement('meta');
        meta.name = 'viewport';
        document.head.appendChild(meta);
    }
    // 注意：iPad 模式下，这个 viewport 设置非常关键
    meta.content = 'width=1920, initial-scale=1.0, maximum-scale=1.0, user-scalable=yes';

    // 3. 【屏幕参数伪造】
    try {
        Object.defineProperty(window.screen, 'width', { get: () => 2732 }); // iPad Pro 12.9 宽度
        Object.defineProperty(window.screen, 'height', { get: () => 2048 });
        Object.defineProperty(window, 'devicePixelRatio', { get: () => 2.0 });
    } catch(e) {}

    // 4. 【画质保底】每 3 秒检查一次
    setInterval(() => {
        var player = document.getElementById('movie_player');
        if (player && player.setPlaybackQualityRange) {
             // 只有当画质极低时才干预，避免打断用户手动选择
             var q = player.getPlaybackQuality();
             if(q === 'small' || q === 'medium' || q === 'tiny') {
                 player.setPlaybackQualityRange('highres', 'highres');
                 console.log("⚡ Upgrading quality...");
             }
        }
    }, 3000);

    // 5. 【UI 净化】
    // 只隐藏广告和推荐，绝不碰播放器控件 (.ytp-chrome-bottom)
    var style = document.createElement('style');
    style.innerHTML = `
      /* 背景黑化 */
      body, html, ytd-app { background: #000 !important; }
      
      /* 隐藏外部框架，只留视频 */
      #masthead-container, #secondary, #comments, #related, ytd-merch-shelf-renderer { display: none !important; }
      
      /* 确保播放器不被遮挡 */
      #player { position: fixed !important; top: 0 !important; left: 0 !important; width: 100vw !important; height: 100vh !important; z-index: 99999 !important; }
      
      /* 修复视频尺寸 */
      video { object-fit: contain !important; width: 100% !important; height: 100% !important; }
      
      /* 隐藏顶部 App 推广横幅 */
      .ytp-app-banner { display: none !important; }
    `;
    document.head.appendChild(style);
  """;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeRight, DeviceOrientation.landscapeLeft]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // ❌ 绝对不要在这里清除 Cookie！否则每次重启都要重新登录！
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
            // 🔥 注入核弹脚本：这是解决 Native Player 劫持的关键
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(
                source: _nuclearScript,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, // 必须在网页还没加载出来前就注入
                forMainFrameOnly: true,
              ),
            ]),
            initialSettings: InAppWebViewSettings(
              // 🔥 身份：iPad Pro (最稳的方案)
              userAgent: _ipadUA,
              
              // 🔥 iOS 核心设置：必须全部允许内联
              allowsInlineMediaPlayback: true,
              allowsAirPlayForMediaPlayback: false,
              allowsPictureInPictureMediaPlayback: false,
              
              // 推荐使用 Recommended 模式，让 Webview 自己处理 iPad 的视口逻辑
              preferredContentMode: UserPreferredContentMode.RECOMMENDED,
              
              mediaPlaybackRequiresUserGesture: false,
              useWideViewPort: true,
              loadWithOverviewMode: true,
              isInspectable: true,
              supportZoom: true, // 允许缩放，防止界面卡死
            ),
            
            onWebViewCreated: (controller) => webViewController = controller,

            onLoadStop: (controller, url) async {
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
                        const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                                Text("iPad Pro Core", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                Text("Anti-Hijack • Persistent Login", style: TextStyle(color: Colors.greenAccent, fontSize: 10))
                            ]
                        ),
                        const Spacer(),
                        
                        // 登录按钮
                        TextButton.icon(
                            icon: const Icon(Icons.login, size: 16, color: Colors.white),
                            label: const Text("登录(只需一次)", style: TextStyle(color: Colors.white)),
                            style: TextButton.styleFrom(backgroundColor: Colors.blueAccent.withOpacity(0.4)),
                            onPressed: () {
                                // 跳转 iPad 版登录页
                                webViewController?.loadUrl(urlRequest: URLRequest(url: WebUri("https://accounts.google.com/ServiceLogin?service=youtube&continue=https://m.youtube.com")));
                            },
                        ),

                        const SizedBox(width: 8),
                        // 强制重载 (救砖用)
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

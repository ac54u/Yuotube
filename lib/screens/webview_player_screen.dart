import 'dart:collection';
import 'dart:async'; // 引入 Timer
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WebViewPlayerScreen extends StatefulWidget {
  final String videoId;
  const WebViewPlayerScreen({super.key, required this.videoId});

  @override
  State<WebViewPlayerScreen> createState() => _WebViewPlayerScreenState();
}

class _WebViewPlayerScreenState extends State<WebViewPlayerScreen> with SingleTickerProviderStateMixin {
  InAppWebViewController? webViewController;
  
  // 状态变量
  bool _isLoading = true; // 是否正在加载
  bool _showControls = true; // 是否显示控制层
  Timer? _hideTimer; // 自动隐藏计时器

  // 🔥 4K 分辨率欺骗脚本 (核心黑科技)
  final String _screenSpoofScript = """
    try {
        Object.defineProperty(window.screen, 'width', { get: function() { return 3840; } });
        Object.defineProperty(window.screen, 'height', { get: function() { return 2160; } });
        Object.defineProperty(window.screen, 'availWidth', { get: function() { return 3840; } });
        Object.defineProperty(window.screen, 'availHeight', { get: function() { return 2160; } });
        Object.defineProperty(window, 'innerWidth', { get: function() { return 1920; } });
        Object.defineProperty(window, 'innerHeight', { get: function() { return 1080; } });
        Object.defineProperty(window, 'devicePixelRatio', { get: function() { return 2.0; } });
    } catch(e) {}
  """;

  // 🔥 UI 净化脚本
  final String _uiCleanupScript = """
    var style = document.createElement('style');
    style.innerHTML = `
      #masthead-container, #secondary, #below, #comments, #related, ytd-merch-shelf-renderer { display: none !important; }
      ytd-app { background: #000 !important; }
      #page-manager { margin: 0 !important; }
      #primary { padding: 0 !important; margin: 0 !important; max-width: 100% !important; }
      #player { position: fixed !important; top: 0 !important; left: 0 !important; width: 100vw !important; height: 100vh !important; z-index: 1 !important; }
      .ytp-ad-module, .ytp-ad-overlay-container { display: none !important; }
      /* 隐藏顶部标题栏，使用我们自己的 Flutter UI */
      .ytp-chrome-top { display: none !important; } 
    `;
    document.head.appendChild(style);

    setTimeout(function() {
        var video = document.querySelector('video');
        if (video && video.paused) video.play();
        var dismissBtn = document.querySelector('yt-button-renderer#dismiss-button');
        if(dismissBtn) dismissBtn.click();
    }, 1500);
  """;

  @override
  void initState() {
    super.initState();
    // 沉浸式横屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    
    // 3秒后自动隐藏 UI
    _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // 纯黑底色
      body: Stack(
        children: [
          // 1. 底层：WebView 视频
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri("https://www.youtube.com/watch?v=${widget.videoId}"),
            ),
            initialUserScripts: UnmodifiableListView<UserScript>([
              UserScript(
                source: _screenSpoofScript,
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
              userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
              isInspectable: true,
              supportZoom: true,
              layoutAlgorithm: LayoutAlgorithm.NORMAL, 
            ),
            onWebViewCreated: (controller) => webViewController = controller,
            onLoadStop: (controller, url) async {
              // 页面加载完毕，注入去广告 + 隐藏 Loading
              await controller.evaluateJavascript(source: _uiCleanupScript);
              if (mounted) setState(() => _isLoading = false);
            },
          ),

          // 2. 交互层：透明遮罩 (用于点击显示/隐藏 UI)
          // 注意：这里使用 IgnorePointer 配合逻辑，让点击穿透到 WebView
          // 但为了能唤起 Flutter UI，我们做一个边缘检测或者仅仅依靠 WebView 自身的点击反馈不太够
          // 💡 策略：我们做一个透明层，但是 behavior: HitTestBehavior.translucent
          // 实际上，为了能操作 YouTube 网页里的按钮，我们不能完全覆盖它。
          // 所以：我们只提供顶部的 UI，不拦截中间的点击。
          // 用户点视频中间会触发 YouTube 自己的暂停，同时我们监听不到...
          // ⚡️ 妥协方案：提供一个明显的"展开菜单"浮动按钮，或者点击顶部区域唤出。
          
          // 3. 中间层：Loading 动画 (居中)
          if (_isLoading)
            Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.redAccent),
                    const SizedBox(height: 16),
                    Text(
                      "正在启动 4K 引擎...", 
                      style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)
                    ),
                  ],
                ),
              ),
            ),

          // 4. 顶层 UI：电影感渐变控制栏
          AnimatedOpacity(
            opacity: _showControls ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: !_showControls, // 隐藏时让点击穿透
              child: Container(
                height: 100, // 顶部渐变区域高度
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(0.8), // 顶部深黑
                      Colors.transparent, // 底部透明
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 返回按钮 (玻璃拟态风格)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(50),
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.1),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white.withOpacity(0.2)),
                              ),
                              child: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        
                        // 标题信息
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 6),
                              const Text(
                                "TrollStore Cinema", 
                                style: TextStyle(
                                  color: Colors.white, 
                                  fontWeight: FontWeight.bold, 
                                  fontSize: 16,
                                  shadows: [Shadow(blurRadius: 10, color: Colors.black)],
                                ),
                              ),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amber,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text("4K HDR", style: TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900)),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    "Web Core • Desktop Mode", 
                                    style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),

                        // 右侧：刷新按钮 (防止卡死)
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white70),
                          tooltip: "重新加载",
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
          
          // 5. 触发层：点击屏幕任意位置唤醒 UI
          // 我们放在最底下还是最上面？
          // 为了不阻挡 YouTube 网页操作，我们只在 UI 隐藏时，在顶部放置一个透明感应区
          if (!_showControls)
            Positioned(
              top: 0, left: 0, right: 0, height: 60,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _toggleControls,
                child: Container(color: Colors.transparent),
              ),
            ),
        ],
      ),
    );
  }
}

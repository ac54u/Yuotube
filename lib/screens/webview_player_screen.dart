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

  // 💉 桌面版专用去广告脚本
  // 这里的 CSS 选择器专门针对 YouTube PC 网页版
  final String _injectScript = """
    // 1. 暴力隐藏所有干扰元素 (顶栏、侧边栏、评论、推荐视频)
    var style = document.createElement('style');
    style.innerHTML = `
      #masthead-container, #secondary, #below, #comments, #related, ytd-merch-shelf-renderer { display: none !important; }
      ytd-app { background: #000 !important; }
      #page-manager { margin: 0 !important; }
      #primary { padding: 0 !important; margin: 0 !important; max-width: 100% !important; }
      
      /* 强制播放器铺满全屏 */
      #player { position: fixed !important; top: 0 !important; left: 0 !important; width: 100vw !important; height: 100vh !important; z-index: 99999 !important; }
      #player-container-outer { max-width: 100% !important; }
      #player-container-inner { padding: 0 !important; }
      
      /* 隐藏广告容器 */
      .ytp-ad-module, .ytp-ad-overlay-container, .ytp-ad-player-overlay { display: none !important; }
      
      /* 隐藏不需要的按钮 (比如"在App中打开") */
      .ytp-button[aria-label="在 App 中打开"] { display: none !important; }
    `;
    document.head.appendChild(style);

    // 2. 自动播放与点击
    setTimeout(function() {
        var video = document.querySelector('video');
        if (video) { 
          video.play(); 
        }
        // 关闭可能的弹窗
        var dismissBtn = document.querySelector('yt-button-renderer#dismiss-button');
        if(dismissBtn) dismissBtn.click();
        
        // 尝试自动点击"设置" -> 选最高画质 (可选，因网络原因可能不稳，主要靠手动选)
    }, 1000);
  """;

  @override
  void initState() {
    super.initState();
    // 强制横屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
    // 隐藏状态栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              // 直接访问 Desktop 版 Watch 页面
              url: WebUri("https://www.youtube.com/watch?v=${widget.videoId}"),
            ),
            initialSettings: InAppWebViewSettings(
              // 🔥 核心修改 1: iOS 强制请求桌面站点 (解决 360p 和 广告问题)
              preferredContentMode: UserPreferredContentMode.DESKTOP,
              
              // 🔥 核心修改 2: 允许内联播放 (解决 iOS 自动弹系统播放器问题)
              allowsInlineMediaPlayback: true,
              mediaPlaybackRequiresUserGesture: false,
              
              // 伪装 UserAgent (双重保险)
              userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
              
              // 其他配置
              isInspectable: true,
              useHybridComposition: true,
              supportZoom: false, // 禁止缩放，防止布局乱掉
            ),
            onWebViewCreated: (controller) {
              webViewController = controller;
            },
            onLoadStop: (controller, url) async {
              // 注入去广告 CSS
              await controller.evaluateJavascript(source: _injectScript);
            },
          ),
          
          // 返回按钮 (半透明悬浮)
          Positioned(
            top: 20,
            left: 20,
            child: SafeArea(
              child: CircleAvatar(
                radius: 20,
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
  
  // 注入脚本：
  // 1. 强制视频播放器全屏覆盖
  // 2. 移除所有广告、评论、侧边栏
  // 3. 自动播放
  final String _injectScript = """
    // 隐藏滚动条
    document.body.style.overflow = 'hidden';
    
    // 创建一个超强 CSS 来隐藏无关元素，只留播放器
    var style = document.createElement('style');
    style.innerHTML = `
      /* 隐藏头部、侧边栏、评论、推荐 */
      #masthead-container, #secondary, #below, #comments, #related, ytd-merch-shelf-renderer { display: none !important; }
      
      /* 强制播放器铺满全屏 */
      ytd-app { background: #000 !important; }
      #page-manager { margin: 0 !important; }
      #primary { padding: 0 !important; margin: 0 !important; max-width: 100% !important; }
      #player { position: fixed !important; top: 0 !important; left: 0 !important; width: 100vw !important; height: 100vh !important; z-index: 99999 !important; }
      #player-container-outer { max-width: 100% !important; }
      #player-container-inner { padding: 0 !important; }
      
      /* 隐藏广告层 */
      .ytp-ad-module, .ytp-ad-overlay-container { display: none !important; }
    `;
    document.head.appendChild(style);

    // 尝试自动播放
    setTimeout(function() {
        var video = document.querySelector('video');
        if (video) { 
          video.play(); 
        }
        // 尝试点击"不用了" (针对登录弹窗)
        var dismissBtn = document.querySelector('yt-button-renderer#dismiss-button');
        if(dismissBtn) dismissBtn.click();
    }, 1500);
  """;

  @override
  void initState() {
    super.initState();
    // 强制横屏
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeRight,
      DeviceOrientation.landscapeLeft,
    ]);
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
              // 🔥 核心修改：不再使用 /embed/，而是使用桌面版官网 /watch?v=
              // 这能完美绕过 Error 153，因为 YouTube 认为你在用电脑浏览器访问官网
              url: WebUri("https://www.youtube.com/watch?v=${widget.videoId}&autoplay=1"),
            ),
            initialSettings: InAppWebViewSettings(
              mediaPlaybackRequiresUserGesture: false,
              allowsInlineMediaPlayback: true,
              // 🔥 必须伪装成 Desktop Chrome，否则会跳转到 m.youtube.com (只有720p)
              userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
              useHybridComposition: true, 
              javaScriptEnabled: true,
              domStorageEnabled: true,
              // 允许缩放，防止某些机型显示异常
              supportZoom: false,
            ),
            onWebViewCreated: (controller) {
              webViewController = controller;
            },
            onLoadStop: (controller, url) async {
              // 页面加载完，执行"截肢手术"，把多余UI砍掉
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

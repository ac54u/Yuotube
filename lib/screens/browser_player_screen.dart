import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class BrowserPlayerScreen extends StatefulWidget {
  final String videoId;
  const BrowserPlayerScreen({super.key, required this.videoId});

  @override
  State<BrowserPlayerScreen> createState() => _BrowserPlayerScreenState();
}

class _BrowserPlayerScreenState extends State<BrowserPlayerScreen> {
  InAppWebViewController? webViewController;
  String _currentUrl = "";
  double _progress = 0;
  
  // 默认为桌面模式
  bool _isDesktopMode = true;

  // 🖥️ 纯净的 Mac Safari UA (这是 iOS 上兼容性最好的桌面身份)
  final String _desktopUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15";
  
  // 📱 iPhone UA
  final String _mobileUA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1";

  @override
  void initState() {
    super.initState();
  }

  // 切换 桌面/手机 模式
  Future<void> _toggleMode() async {
    setState(() {
      _isDesktopMode = !_isDesktopMode;
    });

    await webViewController?.setSettings(settings: InAppWebViewSettings(
      // 🔥 核心：调用系统原生的 contentMode 切换
      preferredContentMode: _isDesktopMode 
          ? UserPreferredContentMode.DESKTOP 
          : UserPreferredContentMode.MOBILE,
      userAgent: _isDesktopMode ? _desktopUA : _mobileUA,
      
      // 允许内联播放 (防止全屏黑屏)
      allowsInlineMediaPlayback: true,
      
      // 允许缩放 (电脑网页在手机上看需要缩放)
      supportZoom: true,
      builtInZoomControls: true,
      displayZoomControls: false,
    ));

    webViewController?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // 顶部：像浏览器一样的地址栏
      appBar: AppBar(
        backgroundColor: const Color(0xFF222222),
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.centerLeft,
          child: Text(
            _currentUrl.isEmpty ? "Loading..." : _currentUrl,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => webViewController?.reload(),
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(
              url: WebUri("https://www.youtube.com/watch?v=${widget.videoId}"),
            ),
            initialSettings: InAppWebViewSettings(
              // 默认桌面模式
              preferredContentMode: UserPreferredContentMode.DESKTOP,
              userAgent: _desktopUA,
              
              // 基础配置
              allowsInlineMediaPlayback: true,
              mediaPlaybackRequiresUserGesture: false,
              useWideViewPort: true,
              loadWithOverviewMode: true,
              isInspectable: true,
              supportZoom: true,
              
              // 开启混合合成 (Android增强，iOS上无害)
              useHybridComposition: true,
            ),
            
            onWebViewCreated: (controller) {
              webViewController = controller;
            },
            
            onLoadStart: (controller, url) {
              setState(() {
                _currentUrl = url.toString();
              });
            },
            
            onLoadStop: (controller, url) {
              setState(() {
                _currentUrl = url.toString();
              });
            },

            onProgressChanged: (controller, progress) {
              setState(() {
                _progress = progress / 100;
              });
            },
          ),
          
          // 进度条
          if (_progress < 1.0)
            LinearProgressIndicator(value: _progress, color: Colors.blueAccent, backgroundColor: Colors.transparent),
        ],
      ),
      
      // 底部：浏览器工具栏
      bottomNavigationBar: Container(
        color: const Color(0xFF222222),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 后退
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                onPressed: () => webViewController?.goBack(),
              ),
              
              // 核心：桌面模式开关
              ElevatedButton.icon(
                icon: Icon(_isDesktopMode ? Icons.desktop_mac : Icons.phone_iphone, size: 16),
                label: Text(_isDesktopMode ? "电脑模式 (4K)" : "手机模式 (登录)"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isDesktopMode ? Colors.blueAccent : Colors.grey[700],
                  foregroundColor: Colors.white,
                ),
                onPressed: _toggleMode,
              ),

              // 前进
              IconButton(
                icon: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 20),
                onPressed: () => webViewController?.goForward(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

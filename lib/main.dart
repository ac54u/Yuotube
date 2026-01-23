import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';

// 🔥 核弹级补丁：全局忽略 SSL 证书错误
// 这能让 App 彻底无视 Surge/Clash 的 MitM 拦截
class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 🔥 激活全局 SSL 绕过 (针对 Surge 用户)
  HttpOverrides.global = MyHttpOverrides();
  
  // 初始化播放器内核
  MediaKit.ensureInitialized();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // 去掉右上角 DEBUG 标签
      title: 'TrollStore YT Pro',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF18181B),
        cardColor: const Color(0xFF27272A),
        primaryColor: const Color(0xFF4D88FF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4D88FF),
          brightness: Brightness.dark,
          surface: const Color(0xFF27272A),
        ),
        useMaterial3: true,
      ),
      home: const MainLayout(),
    );
  }
}

class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;
  final List<Widget> _pages = [
    const HomeScreen(), 
    const ProfileScreen()
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF27272A),
        indicatorColor: Theme.of(context).primaryColor.withOpacity(0.2),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.download_rounded), label: '首页'),
          NavigationDestination(icon: Icon(Icons.person_rounded), label: '我的'),
        ],
      ),
    );
  }
}

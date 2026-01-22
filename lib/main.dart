    import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart'; // 🔥 核心：初始化播放器引擎
import 'screens/home_screen.dart'; // 引入首页
import 'screens/profile_screen.dart'; // 引入个人中心

void main() {
  // 1. 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. 🔥 核心：初始化 MediaKit (否则播放器会报错)
  MediaKit.ensureInitialized();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TrollStore YT Pro',
      // 全局暗黑主题配置
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
        // 全局 AppBar 样式
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ),
      // 指向带有底部导航的主布局
      home: const MainLayout(),
    );
  }
}

// 主布局：负责底部导航栏切换
class MainLayout extends StatefulWidget {
  const MainLayout({super.key});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  int _currentIndex = 0;
  
  // 页面列表：首页 & 个人中心
  final List<Widget> _pages = [
    const HomeScreen(), 
    const ProfileScreen()
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex], // 显示当前选中的页面
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: const Color(0xFF27272A),
        indicatorColor: Theme.of(context).primaryColor.withOpacity(0.2),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.download_rounded), 
            label: '首页'
          ),
          NavigationDestination(
            icon: Icon(Icons.person_rounded), 
            label: '我的'
          ),
        ],
      ),
    );
  }
}

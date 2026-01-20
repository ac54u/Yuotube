import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:io';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _avatarPath;
  String _ipAddress = "获取中...";
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _fetchIp();
  }

  // 加载本地存储的数据 (头像路径 + API Key)
  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _avatarPath = prefs.getString('user_avatar');
      _apiKeyController.text = prefs.getString('deepseek_key') ?? "";
    });
  }

  // 保存 DeepSeek API Key
  Future<void> _saveApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('deepseek_key', _apiKeyController.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("DeepSeek Key 已保存！"), backgroundColor: Colors.green),
      );
      FocusScope.of(context).unfocus(); // 收起键盘
    }
  }

  // 获取公网 IP
  Future<void> _fetchIp() async {
    try {
      final response = await http.get(Uri.parse('https://api.ipify.org'));
      if (response.statusCode == 200) {
        if (mounted) setState(() => _ipAddress = response.body);
      }
    } catch (e) {
      if (mounted) setState(() => _ipAddress = "获取失败");
    }
  }

  // 选择并保存头像
  Future<void> _pickAvatar() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_avatar', image.path);
        setState(() => _avatarPath = image.path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("无法读取相册: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("个人中心"),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 1. 顶部头像与信息区域
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 50,
                        backgroundColor: Colors.grey[800],
                        backgroundImage: _avatarPath != null 
                            ? FileImage(File(_avatarPath!)) 
                            : null,
                        child: _avatarPath == null 
                            ? const Icon(Icons.person, size: 50, color: Colors.white54) 
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.edit, size: 14, color: Colors.white),
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "TrollStore 用户",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "IP: $_ipAddress",
                    style: const TextStyle(fontSize: 12, fontFamily: "monospace", color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 30),

          // 2. DeepSeek Key 设置卡片
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: Theme.of(context).cardColor,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.key, color: Theme.of(context).primaryColor),
                      const SizedBox(width: 10),
                      const Text(
                        "DeepSeek API Key",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _apiKeyController,
                    decoration: const InputDecoration(
                      hintText: "sk-xxxxxxxx...",
                      hintStyle: TextStyle(color: Colors.white24),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      isDense: true,
                    ),
                    obscureText: true, // 隐藏 Key，保护隐私
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveApiKey,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white10,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text("保存 Key"),
                    ),
                  )
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),

          // 3. 功能菜单
          _buildMenuItem(
            icon: Icons.delete_outline,
            title: "清理缓存",
            subtitle: "释放临时文件空间",
            onTap: () async {
              final tempDir = Directory.systemTemp;
              try {
                if (await tempDir.exists()) {
                  // 递归删除临时目录内容
                  tempDir.listSync().forEach((FileSystemEntity entity) {
                     try { entity.deleteSync(recursive: true); } catch(e) {}
                  });
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("缓存已清理")),
                  );
                }
              } catch (e) {
                // 忽略权限错误
              }
            },
          ),
          
          _buildMenuItem(
            icon: Icons.info_outline,
            title: "关于版本",
            subtitle: "v2.0.0 (MediaKit 4K Edition)",
          ),
          
          const SizedBox(height: 20),

          // 4. 底部状态指示条
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor.withOpacity(0.2),
                  Colors.purple.withOpacity(0.2)
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(
              children: [
                Icon(Icons.auto_awesome, color: Theme.of(context).primaryColor),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "DeepSeek 翻译引擎 & MediaKit 播放内核已就绪。",
                    style: TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  // 通用菜单项构建器
  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Theme.of(context).cardColor,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.white70),
        ),
        title: Text(title),
        subtitle: subtitle != null
            ? Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey))
            : null,
        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}

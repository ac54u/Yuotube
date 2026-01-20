import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
// import 'package:permission_handler/permission_handler.dart'; // Gal 内部会自动处理权限，通常不需要单独引用，如果报错可解开
// import 'package:path_provider/path_provider.dart'; // 若 Directory.systemTemp 报错，需解开此行并改用 getTemporaryDirectory

/// 进度回调定义: (状态描述, 进度0.0-1.0)
typedef ProgressCallback = void Function(String status, double progress);

class DownloadService {
  final YoutubeExplode _yt = YoutubeExplode();

  // ---------------------------------------------------------------------------
  // 🎬 核心功能 1: 极速下载 + 硬件转码
  // ---------------------------------------------------------------------------
  Future<void> downloadAndMerge({
    required Video video,
    required VideoStreamInfo videoStream,
    required AudioStreamInfo audioStream,
    required ProgressCallback onProgress,
  }) async {
    try {
      // 1. 检查权限
      if (!await Gal.hasAccess()) await Gal.requestAccess();

      final tempDir = Directory.systemTemp;
      final videoPath = '${tempDir.path}/temp_video.${videoStream.container.name}';
      final audioPath = '${tempDir.path}/temp_audio.${audioStream.container.name}';
      
      // 清理文件名中的非法字符
      final safeTitle = video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final finalPath = '${tempDir.path}/${safeTitle}_${videoStream.videoResolution.height}p.mp4';

      // 清理旧文件
      if (await File(finalPath).exists()) await File(finalPath).delete();

      // 2. 并行下载
      onProgress("🚀 极速并行下载中...", 0.0);
      
      final totalSize = videoStream.size.totalBytes + audioStream.size.totalBytes;
      int receivedV = 0;
      int receivedA = 0;

      void updateDownloadProgress() {
        final p = (receivedV + receivedA) / totalSize;
        // 下载占总进度的 80%
        onProgress("正在下载: ${(p * 100).toInt()}%", p * 0.8);
      }

      final taskVideo = _downloadStream(videoStream, videoPath, (bytes) {
        receivedV += bytes;
        updateDownloadProgress();
      });

      final taskAudio = _downloadStream(audioStream, audioPath, (bytes) {
        receivedA += bytes;
        updateDownloadProgress();
      });

      await Future.wait([taskVideo, taskAudio]);

      // 3. 硬件加速合成
      onProgress("⚡️ GPU 硬件加速合成中...", 0.85);

      // iOS 专用命令: h264_videotoolbox
      // -allow_sw 1: 允许软件编码兜底
      // -b:v 15M: 保证 4K 画质
      // 使用 Dart 字符串插值 "$var" 代替 .format()
      final runCmd = '-i "$videoPath" -i "$audioPath" -c:v h264_videotoolbox -b:v 15M -allow_sw 1 -c:a aac -b:a 192k -y "$finalPath"';

      await FFmpegKit.execute(runCmd).then((session) async {
        final returnCode = await session.getReturnCode();
        
        if (ReturnCode.isSuccess(returnCode)) {
          onProgress("正在保存到相册...", 0.95);
          await Gal.putVideo(finalPath);
          onProgress("✅ 下载完成", 1.0);
        } else {
          // 硬件失败，尝试软件兜底 (libx264 ultrafast)
          onProgress("硬件加速失败，尝试软解...", 0.85);
          final fallbackCmd = '-i "$videoPath" -i "$audioPath" -c:v libx264 -preset ultrafast -crf 23 -c:a aac -b:a 192k -y "$finalPath"';
          
          final session2 = await FFmpegKit.execute(fallbackCmd);
          if (ReturnCode.isSuccess(await session2.getReturnCode())) {
             onProgress("正在保存到相册...", 0.95);
             await Gal.putVideo(finalPath);
             onProgress("✅ 下载完成", 1.0);
          } else {
             final logs = await session2.getAllLogsAsString();
             throw Exception("转码彻底失败: $logs");
          }
        }
      });

      // 4. 清理临时文件 (保留 finalPath 一会儿防止写入未完成，但 Gal 其实已经拷贝了)
      try {
        if (await File(videoPath).exists()) await File(videoPath).delete();
        if (await File(audioPath).exists()) await File(audioPath).delete();
        if (await File(finalPath).exists()) await File(finalPath).delete();
      } catch (e) {
        print("清理临时文件失败: $e");
      }

    } catch (e) {
      throw Exception("下载流程出错: $e");
    }
  }

  // 辅助流下载方法
  Future<void> _downloadStream(StreamInfo info, String path, Function(int) onBytes) async {
    final stream = _yt.videos.streamsClient.get(info);
    final file = File(path);
    final sink = file.openWrite();
    
    await stream.listen((data) {
      sink.add(data);
      onBytes(data.length);
    }).asFuture();
    
    await sink.flush();
    await sink.close();
  }

  // ---------------------------------------------------------------------------
  // 🧠 核心功能 2: DeepSeek 字幕翻译
  // ---------------------------------------------------------------------------
  Future<void> exportDeepSeekSubtitle({
    required Video video,
    required String apiKey,
    required ProgressCallback onProgress,
  }) async {
    if (apiKey.isEmpty) throw Exception("DeepSeek API Key 为空");

    try {
      onProgress("正在获取字幕轨道...", 0.1);
      final manifest = await _yt.videos.closedCaptions.getManifest(video.id);
      
      // 智能选轨策略
      ClosedCaptionTrackInfo? trackInfo;
      bool needTranslation = false;

      try {
        // 1. 找人工中文
        trackInfo = manifest.tracks.firstWhere((t) => t.language.code.startsWith('zh') && !t.isAutoGenerated);
      } catch (_) {
        try {
          // 2. 找人工英文
          trackInfo = manifest.tracks.firstWhere((t) => t.language.code == 'en' && !t.isAutoGenerated);
          needTranslation = true;
        } catch (_) {
          // 3. 找自动生成英文或其他
          if (manifest.tracks.isNotEmpty) {
            trackInfo = manifest.tracks.first;
            needTranslation = true;
          } else {
             throw Exception("该视频没有可用字幕");
          }
        }
      }

      onProgress("正在下载字幕内容...", 0.2);
      ClosedCaptionTrack track;
      try {
        track = await _yt.videos.closedCaptions.get(trackInfo!);
      } catch (e) {
        // 如果特定轨道失败，尝试找一个非自动生成的轨道重试
        var fallbackTrack = manifest.tracks.firstWhere((t) => !t.isAutoGenerated, orElse: () => manifest.tracks.first);
        track = await _yt.videos.closedCaptions.get(fallbackTrack);
      }

      final originalLines = track.captions.map((e) => e.text).toList();
      final translatedLines = <String>[];

      // 执行翻译
      if (needTranslation) {
        const batchSize = 20;
        final totalLines = originalLines.length;

        for (int i = 0; i < totalLines; i += batchSize) {
          final end = (i + batchSize < totalLines) ? i + batchSize : totalLines;
          final batch = originalLines.sublist(i, end);
          
          final percent = (i / totalLines * 100).toInt();
          final p = 0.2 + (i / totalLines * 0.7); // 进度 20% -> 90%
          onProgress("AI 思考中: $percent% ($i/$totalLines行)", p);

          final result = await _callDeepSeekApi(batch, apiKey);
          translatedLines.addAll(result);
          
          // 避免 QPS 限制
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } else {
        translatedLines.addAll(originalLines);
      }

      // 生成 SRT
      onProgress("正在生成 SRT 文件...", 0.95);
      final srtContent = _generateSrt(track.captions, translatedLines);

      // 导出文件
      final tempDir = Directory.systemTemp;
      final safeTitle = video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fileName = "${safeTitle}_DeepSeek_CN.srt";
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(srtContent);

      onProgress("✅ 导出成功", 1.0);
      await Share.shareXFiles([XFile(file.path)], text: "DeepSeek 翻译字幕");

    } catch (e) {
      throw Exception("字幕导出失败: $e");
    }
  }

  // DeepSeek API 调用
  Future<List<String>> _callDeepSeekApi(List<String> lines, String apiKey) async {
    const url = 'https://api.deepseek.com/chat/completions';
    final content = lines.join('\n');
    const systemPrompt = "你是一个专业的字幕翻译专家。将以下英文SRT字幕翻译成地道的简体中文。请严格保持行数对应，每一行原文对应一行译文。不要输出任何解释性文字，只输出翻译结果。";

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          "model": "deepseek-chat",
          "messages": [
            {"role": "system", "content": systemPrompt},
            {"role": "user", "content": content}
          ],
          "temperature": 1.3,
          "stream": false
        }),
      );

      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        final json = jsonDecode(body);
        final text = json['choices'][0]['message']['content'].toString().trim();
        return text.split('\n');
      } else {
        // 如果 API 报错，返回原文，防止流程中断
        print("API Error: ${response.body}");
        return lines;
      }
    } catch (e) {
      print("Network Error: $e");
      return lines;
    }
  }

  // 生成 SRT 格式字符串
  String _generateSrt(List<ClosedCaption> captions, List<String> translatedTexts) {
    final buffer = StringBuffer();
    for (int i = 0; i < captions.length; i++) {
      final caption = captions[i];
      final text = (i < translatedTexts.length) ? translatedTexts[i] : caption.text;

      buffer.writeln("${i + 1}");
      buffer.writeln("${_formatDuration(caption.offset)} --> ${_formatDuration(caption.offset + caption.duration)}");
      buffer.writeln(text);
      buffer.writeln();
    }
    return buffer.toString();
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String threeDigits(int n) => n.toString().padLeft(3, "0");
    return "${twoDigits(d.inHours)}:${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))},$threeDigits";
  }
}

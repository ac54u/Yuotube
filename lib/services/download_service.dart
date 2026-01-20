import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart'; // 🔥 新增：防止锁屏

/// 进度回调定义
typedef ProgressCallback = void Function(String status, double progress);

class DownloadService {
  // 每次调用重新实例化，确保网络 Session 干净
  YoutubeExplode get _yt => YoutubeExplode();

  // ---------------------------------------------------------------------------
  // 🎬 核心功能: 极速下载 + 硬件转码 (防中断版)
  // ---------------------------------------------------------------------------
  Future<void> downloadAndMerge({
    required Video video,
    required VideoStreamInfo videoStream,
    required AudioStreamInfo audioStream,
    required ProgressCallback onProgress,
  }) async {
    final yt = _yt;
    
    // 🔥 1. 开始下载时，强制屏幕常亮，防止 iOS 杀后台
    await WakelockPlus.enable();

    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();

      final tempDir = Directory.systemTemp;
      final videoPath = '${tempDir.path}/temp_video.${videoStream.container.name}';
      final audioPath = '${tempDir.path}/temp_audio.${audioStream.container.name}';
      final safeTitle = video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final finalPath = '${tempDir.path}/${safeTitle}_${videoStream.videoResolution.height}p.mp4';

      // 清理旧文件
      if (await File(finalPath).exists()) await File(finalPath).delete();

      onProgress("🚀 保持屏幕常亮，开始下载...", 0.0);
      
      final totalSize = videoStream.size.totalBytes + audioStream.size.totalBytes;
      int receivedV = 0;
      int receivedA = 0;

      void updateDownloadProgress() {
        final p = (receivedV + receivedA) / totalSize;
        onProgress("正在下载: ${(p * 100).toInt()}%", p * 0.8);
      }

      // 🔥 2. 并行下载 (带超时检测)
      final taskVideo = _downloadStream(yt, videoStream, videoPath, (bytes) {
        receivedV += bytes;
        updateDownloadProgress();
      });

      final taskAudio = _downloadStream(yt, audioStream, audioPath, (bytes) {
        receivedA += bytes;
        updateDownloadProgress();
      });

      // 等待下载完成
      await Future.wait([taskVideo, taskAudio]);

      onProgress("⚡️ 下载完成，GPU 合成中...", 0.85);

      // FFmpeg 合成命令 (硬件加速)
      final runCmd = '-i "$videoPath" -i "$audioPath" -c:v h264_videotoolbox -b:v 15M -allow_sw 1 -c:a aac -b:a 192k -y "$finalPath"';

      await FFmpegKit.execute(runCmd).then((session) async {
        final returnCode = await session.getReturnCode();
        
        if (ReturnCode.isSuccess(returnCode)) {
          onProgress("正在保存到相册...", 0.95);
          await Gal.putVideo(finalPath);
          onProgress("✅ 下载完成", 1.0);
        } else {
          onProgress("硬件加速失败，尝试软解...", 0.85);
          final fallbackCmd = '-i "$videoPath" -i "$audioPath" -c:v libx264 -preset ultrafast -crf 23 -c:a aac -b:a 192k -y "$finalPath"';
          
          final session2 = await FFmpegKit.execute(fallbackCmd);
          if (ReturnCode.isSuccess(await session2.getReturnCode())) {
             onProgress("正在保存到相册...", 0.95);
             await Gal.putVideo(finalPath);
             onProgress("✅ 下载完成", 1.0);
          } else {
             final logs = await session2.getAllLogsAsString();
             throw Exception("转码失败: $logs");
          }
        }
      });

      // 清理缓存
      try {
        if (await File(videoPath).exists()) await File(videoPath).delete();
        if (await File(audioPath).exists()) await File(audioPath).delete();
        if (await File(finalPath).exists()) await File(finalPath).delete();
      } catch (e) {}

    } catch (e) {
      throw Exception("下载中断: $e");
    } finally {
      yt.close();
      // 🔥 3. 无论成功失败，恢复屏幕休眠设置
      await WakelockPlus.disable();
    }
  }

  // 辅助流下载方法 (带超时)
  Future<void> _downloadStream(YoutubeExplode yt, StreamInfo info, String path, Function(int) onBytes) async {
    final stream = yt.videos.streamsClient.get(info);
    final file = File(path);
    final sink = file.openWrite();
    
    // 🔥 4. 增加 45秒超时检测
    // 如果网络卡住超过 45秒没数据，直接报错，避免无限转圈
    await stream
      .timeout(
        const Duration(seconds: 45), 
        onTimeout: (EventSink<List<int>> sink) {
          throw TimeoutException("网络连接超时 (45s 无数据)，请检查 VPN");
        }
      )
      .listen((data) {
        sink.add(data);
        onBytes(data.length);
      }).asFuture();
    
    await sink.flush();
    await sink.close();
  }

  // ---------------------------------------------------------------------------
  // 🧠 DeepSeek 字幕翻译 (保持之前的修复版)
  // ---------------------------------------------------------------------------
  Future<void> exportDeepSeekSubtitle({
    required Video video,
    required String apiKey,
    required ProgressCallback onProgress,
  }) async {
    final yt = _yt;
    if (apiKey.isEmpty) throw Exception("DeepSeek API Key 为空");

    try {
      onProgress("正在获取字幕轨道...", 0.1);
      final manifest = await yt.videos.closedCaptions.getManifest(video.id);
      
      if (manifest.tracks.isEmpty) throw Exception("该视频没有任何字幕轨道");

      ClosedCaptionTrackInfo? trackInfo;
      bool needTranslation = false;

      try {
        trackInfo = manifest.tracks.firstWhere((t) => t.language.code.startsWith('zh') && !t.isAutoGenerated);
      } catch (_) {
        try {
          trackInfo = manifest.tracks.firstWhere((t) => t.language.code == 'en' && !t.isAutoGenerated);
          needTranslation = true;
        } catch (_) {
          trackInfo = manifest.tracks.first;
          needTranslation = true;
        }
      }

      onProgress("正在下载字幕内容...", 0.2);
      ClosedCaptionTrack? track;
      try {
        track = await yt.videos.closedCaptions.get(trackInfo!);
      } catch (e) {
        try {
          var fallback = manifest.tracks.firstWhere((t) => t.isAutoGenerated, orElse: () => manifest.tracks.last);
          track = await yt.videos.closedCaptions.get(fallback);
          needTranslation = true;
        } catch (e2) {
          throw Exception("字幕解析彻底失败: $e2");
        }
      }

      final originalLines = track.captions.map((e) => e.text).toList();
      final translatedLines = <String>[];

      if (needTranslation || trackInfo.language.code != 'zh') {
        const batchSize = 20;
        final totalLines = originalLines.length;
        for (int i = 0; i < totalLines; i += batchSize) {
          final end = (i + batchSize < totalLines) ? i + batchSize : totalLines;
          final batch = originalLines.sublist(i, end);
          final percent = (i / totalLines * 100).toInt();
          onProgress("AI 思考中: $percent%", 0.2 + (i / totalLines * 0.7));
          final result = await _callDeepSeekApi(batch, apiKey);
          translatedLines.addAll(result);
          await Future.delayed(const Duration(milliseconds: 100));
        }
      } else {
        translatedLines.addAll(originalLines);
      }

      onProgress("正在生成 SRT...", 0.95);
      final srtContent = _generateSrt(track.captions, translatedLines);
      final tempDir = Directory.systemTemp;
      final safeTitle = video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${tempDir.path}/${safeTitle}_DeepSeek_CN.srt');
      await file.writeAsString(srtContent);

      onProgress("✅ 导出成功", 1.0);
      await Share.shareXFiles([XFile(file.path)], text: "字幕导出");

    } catch (e) {
      throw Exception("字幕失败: $e");
    } finally {
      yt.close();
    }
  }

  Future<List<String>> _callDeepSeekApi(List<String> lines, String apiKey) async {
    // ... (保持 API 调用代码不变，省略以节省篇幅，请保留原有的 _callDeepSeekApi 代码)
    // 如果你没有备份，请告诉我，我再发一遍完整的 API 调用部分
    const url = 'https://api.deepseek.com/chat/completions';
    final content = lines.join('\n');
    const systemPrompt = "你是一个专业的字幕翻译专家。将以下英文SRT字幕翻译成地道的简体中文。请严格保持行数对应，每一行原文对应一行译文。不要输出任何解释性文字，只输出翻译结果。";
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
        body: jsonEncode({"model": "deepseek-chat", "messages": [{"role": "system", "content": systemPrompt}, {"role": "user", "content": content}], "temperature": 1.3, "stream": false}),
      );
      if (response.statusCode == 200) {
        final body = utf8.decode(response.bodyBytes);
        final json = jsonDecode(body);
        return json['choices'][0]['message']['content'].toString().trim().split('\n');
      }
      return lines;
    } catch (e) { return lines; }
  }

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

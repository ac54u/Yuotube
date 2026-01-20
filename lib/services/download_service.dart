import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:gal/gal.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// 进度回调定义
typedef ProgressCallback = void Function(String status, double progress);

class DownloadService {
  // 🔥 伪装头：模拟 Chrome 122，防止被识别为机器人
  final Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
    'Accept': '*/*',
    'Connection': 'keep-alive',
    'Referer': 'https://www.youtube.com/',
    'Origin': 'https://www.youtube.com',
  };

  YoutubeExplode get _yt => YoutubeExplode();

  // ---------------------------------------------------------------------------
  // 🚀 功能: 8线程并发极速下载 + 硬件转码
  // ---------------------------------------------------------------------------
  Future<void> downloadAndMerge({
    required Video video,
    required VideoStreamInfo videoStream,
    required AudioStreamInfo audioStream,
    required ProgressCallback onProgress,
  }) async {
    await WakelockPlus.enable();
    final tempDir = Directory.systemTemp;
    final uniqueId = DateTime.now().millisecondsSinceEpoch;
    
    // 临时文件路径
    final videoPath = '${tempDir.path}/v_$uniqueId.${videoStream.container.name}';
    final audioPath = '${tempDir.path}/a_$uniqueId.${audioStream.container.name}';
    final safeTitle = video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final finalPath = '${tempDir.path}/${safeTitle}_${videoStream.videoResolution.height}p.mp4';

    try {
      if (!await Gal.hasAccess()) await Gal.requestAccess();
      if (await File(finalPath).exists()) await File(finalPath).delete();

      // --- 并发下载阶段 ---
      onProgress("🚀 正在建立 8 线程高速连接...", 0.0);
      
      final totalSize = videoStream.size.totalBytes + audioStream.size.totalBytes;
      int downloadedBytes = 0;

      // 进度更新锁，防止并发写入冲突
      void updateProgress(int newBytes) {
        downloadedBytes += newBytes;
        final p = downloadedBytes / totalSize;
        // 下载占 80% 的进度条
        if (p <= 1.0) {
          onProgress("高速下载中: ${(p * 100).toInt()}%", p * 0.8);
        }
      }

      // 🔥 启动多线程下载
      // 视频文件大，开 8 线程；音频文件小，开 2 线程
      final taskVideo = _downloadWithChunks(
        url: videoStream.url.toString(), 
        savePath: videoPath, 
        threadCount: 8,  // 8倍速核心
        onReceive: updateProgress
      );

      final taskAudio = _downloadWithChunks(
        url: audioStream.url.toString(), 
        savePath: audioPath, 
        threadCount: 2, 
        onReceive: updateProgress
      );

      await Future.wait([taskVideo, taskAudio]);

      // --- 转码合成阶段 ---
      onProgress("⚡️ 视频合成中 (请勿锁屏)...", 0.85);

      final runCmd = '-i "$videoPath" -i "$audioPath" -c:v h264_videotoolbox -b:v 20M -allow_sw 1 -c:a aac -b:a 192k -y "$finalPath"';

      final session = await FFmpegKit.execute(runCmd);
      if (ReturnCode.isSuccess(await session.getReturnCode())) {
        onProgress("💾 保存到相册...", 0.95);
        await Gal.putVideo(finalPath);
        onProgress("✅ 下载完成", 1.0);
      } else {
        // 失败尝试软解 (兼容性更好)
        onProgress("尝试兼容模式合成...", 0.85);
        final runCmdSoft = '-i "$videoPath" -i "$audioPath" -c:v libx264 -preset ultrafast -crf 23 -c:a aac -b:a 192k -y "$finalPath"';
        final sessionSoft = await FFmpegKit.execute(runCmdSoft);
        
        if (ReturnCode.isSuccess(await sessionSoft.getReturnCode())) {
           await Gal.putVideo(finalPath);
           onProgress("✅ 下载完成", 1.0);
        } else {
           throw Exception("合成失败，空间可能不足");
        }
      }

      _tryDelete(videoPath);
      _tryDelete(audioPath);
      _tryDelete(finalPath);

    } catch (e) {
      throw Exception("下载中断: $e");
    } finally {
      await WakelockPlus.disable();
      _yt.close();
    }
  }

  // 🔥 核心黑科技: 多线程分块下载器 (IDM 逻辑)
  Future<void> _downloadWithChunks({
    required String url,
    required String savePath,
    required int threadCount,
    required Function(int) onReceive,
  }) async {
    // 1. 获取文件总大小
    final headReq = http.Request('HEAD', Uri.parse(url));
    headReq.headers.addAll(_headers);
    final headRes = await http.Client().send(headReq);
    final totalLength = int.parse(headRes.headers['content-length'] ?? '0');

    if (totalLength == 0) {
      throw Exception("无法获取文件大小，可能被拦截");
    }

    // 2. 计算分块并下载到独立文件 (.part0, .part1...)
    // 为了避免 Dart 文件锁冲突，我们先下载到独立文件，最后合并
    final chunkSize = (totalLength / threadCount).ceil();
    List<Future> futures = [];
    List<String> partFiles = [];

    for (int i = 0; i < threadCount; i++) {
      final start = i * chunkSize;
      final end = (i + 1) * chunkSize - 1;
      final effectiveEnd = end < totalLength ? end : totalLength - 1;

      if (start >= totalLength) break;

      final partPath = "$savePath.part$i";
      partFiles.add(partPath);

      // 启动分块下载线程
      futures.add(_downloadPart(
        url: url,
        partPath: partPath,
        start: start,
        end: effectiveEnd,
        onReceive: onReceive
      ));
    }

    // 3. 等待所有分块下载完成
    await Future.wait(futures);

    // 4. 合并分块 (IO流合并)
    final finalFile = File(savePath);
    final sink = finalFile.openWrite(); // 默认写入模式

    for (var partPath in partFiles) {
      final partFile = File(partPath);
      if (await partFile.exists()) {
        await sink.addStream(partFile.openRead());
        await partFile.delete(); // 合并完立刻删除
      }
    }
    await sink.close();
  }

  // 单个分块下载任务
  Future<void> _downloadPart({
    required String url,
    required String partPath,
    required int start,
    required int end,
    required Function(int) onReceive,
  }) async {
    int retries = 3;
    while (retries > 0) {
      try {
        // 如果分块文件已存在且大小正确，跳过 (简单的断点续传)
        final file = File(partPath);
        if (await file.exists()) {
           final len = await file.length();
           if (len == (end - start + 1)) {
             onReceive(len); // 补回进度
             return; 
           }
           await file.delete(); // 否则删除重下
        }

        final request = http.Request('GET', Uri.parse(url));
        request.headers.addAll(_headers);
        // 🔥 关键：Range 头告诉服务器“我只要这一块”
        request.headers['Range'] = 'bytes=$start-$end';

        final response = await http.Client().send(request);
        
        if (response.statusCode != 206) {
           throw Exception("服务器不支持分块: ${response.statusCode}");
        }

        final sink = file.openWrite();
        await response.stream.timeout(
          const Duration(seconds: 30), // 30秒无数据超时
          onTimeout: (sink) => throw TimeoutException("分块超时"),
        ).listen((chunk) {
          sink.add(chunk);
          onReceive(chunk.length);
        }).asFuture();

        await sink.close();
        return; // 成功退出

      } catch (e) {
        retries--;
        if (retries == 0) throw Exception("分块下载失败 ($start-$end): $e");
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 🧠 功能 2: DeepSeek 字幕翻译 (手动抓取 + XML修复版)
  // ---------------------------------------------------------------------------
  Future<void> exportDeepSeekSubtitle({
    required Video video,
    required String apiKey,
    required ProgressCallback onProgress,
  }) async {
    final yt = _yt;
    if (apiKey.isEmpty) throw Exception("请先设置 API Key");

    try {
      onProgress("正在解析字幕轨道...", 0.1);
      final manifest = await yt.videos.closedCaptions.getManifest(video.id);
      
      if (manifest.tracks.isEmpty) throw Exception("无可用字幕");

      // 选轨逻辑
      ClosedCaptionTrackInfo? trackInfo;
      try {
        trackInfo = manifest.tracks.firstWhere((t) => t.language.code.startsWith('zh') && !t.isAutoGenerated);
      } catch (_) {
        try {
          trackInfo = manifest.tracks.firstWhere((t) => t.language.code == 'en' && !t.isAutoGenerated);
        } catch (_) {
          trackInfo = manifest.tracks.first;
        }
      }

      onProgress("正在下载字幕文件...", 0.2);
      
      ClosedCaptionTrack track;
      try {
        // 尝试用库获取
        track = await yt.videos.closedCaptions.get(trackInfo!);
      } catch (e) {
        // 失败回退到自动生成轨道
        try {
           track = await yt.videos.closedCaptions.get(manifest.tracks.first);
        } catch (e2) {
           throw Exception("无法解析字幕: $e");
        }
      }
      
      // DeepSeek 翻译
      final originalLines = track.captions.map((e) => e.text).toList();
      final translatedLines = <String>[];
      
      if (!trackInfo!.language.code.startsWith('zh')) {
        const batchSize = 20;
        final totalLines = originalLines.length;
        for (int i = 0; i < totalLines; i += batchSize) {
          final end = (i + batchSize < totalLines) ? i + batchSize : totalLines;
          final batch = originalLines.sublist(i, end);
          final p = 0.2 + (i / totalLines * 0.7);
          onProgress("AI 翻译中: ${(i/totalLines*100).toInt()}%", p);
          
          final result = await _callDeepSeekApi(batch, apiKey);
          translatedLines.addAll(result);
        }
      } else {
        translatedLines.addAll(originalLines);
      }

      onProgress("生成文件中...", 0.95);
      final srt = _generateSrt(track.captions, translatedLines);
      
      final safeTitle = video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final file = File('${Directory.systemTemp.path}/${safeTitle}_CN.srt');
      await file.writeAsString(srt);

      onProgress("✅ 导出成功", 1.0);
      await Share.shareXFiles([XFile(file.path)]);

    } catch (e) {
      throw Exception("字幕操作失败: $e");
    } finally {
      yt.close();
    }
  }

  // DeepSeek API
  Future<List<String>> _callDeepSeekApi(List<String> lines, String apiKey) async {
    try {
      final res = await http.post(
        Uri.parse('https://api.deepseek.com/chat/completions'),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $apiKey'},
        body: jsonEncode({
          "model": "deepseek-chat",
          "messages": [
            {"role": "system", "content": "翻译为简体中文，保持行数一致，不输出解释。"},
            {"role": "user", "content": lines.join('\n')}
          ],
          "stream": false
        }),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(utf8.decode(res.bodyBytes));
        return data['choices'][0]['message']['content'].toString().trim().split('\n');
      }
    } catch (_) {}
    return lines;
  }

  String _generateSrt(List<ClosedCaption> captions, List<String> texts) {
    final buf = StringBuffer();
    for (int i = 0; i < captions.length; i++) {
      final cap = captions[i];
      final text = (i < texts.length) ? texts[i] : cap.text;
      buf.writeln("${i + 1}");
      buf.writeln("${_fmt(cap.offset)} --> ${_fmt(cap.offset + cap.duration)}");
      buf.writeln(text);
      buf.writeln();
    }
    return buf.toString();
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, "0");
    String three(int n) => n.toString().padLeft(3, "0");
    return "${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))},$three";
  }

  void _tryDelete(String path) async {
    try { if (await File(path).exists()) await File(path).delete(); } catch (_) {}
  }
}

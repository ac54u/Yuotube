import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YoutubeService {
  // 单例模式 (可选，这里使用简单实例即可)
  final YoutubeExplode _yt = YoutubeExplode();

  /// 获取视频详情 (标题、封面、时长等)
  Future<Video> getVideoInfo(String url) async {
    try {
      // 自动处理短链接 (youtu.be) 和长链接
      return await _yt.videos.get(url);
    } catch (e) {
      throw Exception("无法解析视频链接: $e");
    }
  }

  /// 获取流媒体清单 (包含了所有的音视频流选项)
  Future<StreamManifest> getManifest(String videoId) async {
    try {
      return await _yt.videos.streamsClient.getManifest(videoId);
    } catch (e) {
      throw Exception("无法获取视频流: $e");
    }
  }

  /// 获取字幕轨道清单
  Future<ClosedCaptionManifest> getCaptionManifest(String videoId) async {
    try {
      return await _yt.videos.closedCaptions.getManifest(videoId);
    } catch (e) {
      throw Exception("无法获取字幕清单: $e");
    }
  }

  /// 获取具体的字幕内容
  Future<ClosedCaptionTrack> getCaptionTrack(ClosedCaptionTrackInfo info) async {
    try {
      return await _yt.videos.closedCaptions.get(info);
    } catch (e) {
      throw Exception("字幕内容获取失败: $e");
    }
  }

  /// 释放资源
  void dispose() {
    _yt.close();
  }
}

import 'dart:typed_data';
import '../../../../core/database/app_database.dart';
import 'pose_landmarks_model.dart';

/// 标准试穿帧输入：阶段一传入静态全身照，阶段二直接传入摄像头视频帧字节流
class TryOnFrame {
  final String? filePath;
  final Uint8List? bytes;
  final int width;
  final int height;
  final bool isVideoStreamFrame;
  final int rotationDegrees;
  final int bytesPerRow;
  final String pixelFormat;
  final bool isFrontCamera;

  const TryOnFrame({
    this.filePath,
    this.bytes,
    required this.width,
    required this.height,
    this.isVideoStreamFrame = false,
    this.rotationDegrees = 0,
    this.bytesPerRow = 0,
    this.pixelFormat = 'nv21',
    this.isFrontCamera = false,
  });
}

/// 试穿模块核心解耦接口层
/// 阶段一由 StaticTryOnEngine 实现；阶段二由 NeonStreamTryOnEngine 实现实时视频流试穿
abstract class TryOnEngineInterface {
  /// 从输入帧提取人体关键点坐标（肩、肘、腰、胯/臀、膝）
  Future<PoseLandmarks?> detectPose(TryOnFrame frame);

  /// 将选中的白底/透明底衣物按骨骼关键点变形贴合到目标帧，并做边缘羽化
  Future<Uint8List> renderTryOn({
    required TryOnFrame bodyFrame,
    required List<ClothingItem> garments,
    required PoseLandmarks landmarks,
  });

  Future<void> dispose();
}

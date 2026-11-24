import 'dart:math';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Pose 33 点 + EMA 平滑防抖 + 躯干四边形计算
/// 帧丢弃锁由调用方(tryon_mirror_screen)保证:同一时间只处理一帧。
class PoseService {
  final _detector = PoseDetector(
      options: PoseDetectorOptions(mode: PoseDetectionMode.stream, model: PoseDetectionModel.base));
  final Map<PoseLandmarkType, Offset> _ema = {};
  static const double _alpha = 0.35; // EMA 系数:越大跟手越快、越抖;0.35 为平衡值

  Future<Map<PoseLandmarkType, Offset>?> process(CameraImage image, int rotation) async {
    final input = InputImage.fromBytes(
      bytes: image.planes.fold<List<int>>([], (p, e) => p..addAll(e.bytes)),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.values[rotation],
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
    final poses = await _detector.processImage(input);
    if (poses.isEmpty) return null;
    final pose = poses.first;
    final out = <PoseLandmarkType, Offset>{};
    for (final e in pose.landmarks.entries) {
      final raw = Offset(e.value.x, e.value.y);
      final prev = _ema[e.key];
      final smooth = prev == null ? raw : Offset(
        prev.dx + _alpha * (raw.dx - prev.dx),
        prev.dy + _alpha * (raw.dy - prev.dy));
      _ema[e.key] = smooth;
      out[e.key] = smooth;
    }
    return out;
  }

  /// 躯干四边形:左肩/右肩/左胯/右胯,按 1.25 倍外扩留出衣物余量
  static List<Offset> torsoQuad(Map<PoseLandmarkType, Offset> lm) {
    Offset at(PoseLandmarkType t) => lm[t] ?? Offset.zero;
    final ls = at(PoseLandmarkType.leftShoulder), rs = at(PoseLandmarkType.rightShoulder);
    final lh = at(PoseLandmarkType.leftHip), rh = at(PoseLandmarkType.rightHip);
    final cx = (ls.dx + rs.dx + lh.dx + rh.dx) / 4, cy = (ls.dy + rs.dy + lh.dy + rh.dy) / 4;
    Offset expand(Offset p) => Offset(cx + (p.dx - cx) * 1.25, cy + (p.dy - cy) * 1.25);
    return [expand(ls), expand(rs), expand(rh), expand(lh)];
  }

  /// 关键点缺失/置信度低时返回 false,调用方保持上一帧、不闪烁
  static bool isTorsoValid(Map<PoseLandmarkType, Offset> lm) {
    for (final t in [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftHip, PoseLandmarkType.rightHip]) {
      final p = lm[t];
      if (p == null || p == Offset.zero) return false;
    }
    return true;
  }

  void dispose() => _detector.close();
}

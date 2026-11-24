import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;
import 'package:flutter/material.dart' show Matrix4;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../../../../core/database/app_database.dart';
import '../domain/pose_landmarks_model.dart';
import '../domain/try_on_engine_interface.dart';

/// 向后兼容别名
typedef NeonStreamTryOnStub = NeonStreamTryOnEngine;

/// 实时视频流衣物贴合矩阵计算结果（供 Flutter GPU 加速渲染）
class GarmentOverlayTransform {
  final Matrix4 matrix;
  final double width;
  final double height;
  final Offset center;
  final double rotationRad;
  final double skewX;

  const GarmentOverlayTransform({
    required this.matrix,
    required this.width,
    required this.height,
    required this.center,
    required this.rotationRad,
    required this.skewX,
  });
}

/// 阶段二实时视频流 AR 试穿引擎（NeonStreamTryOnEngine）
/// - Google ML Kit Pose Detection (Stream 模式) 实时追踪肩、肘、胯、膝关键点
/// - 内置指数移动平均（EMA）平滑滤波，消除摄像头抖动
/// - 实时计算 2D 仿射/透视变形矩阵，支持 Flutter 实时叠加与 OpenCV 离线合成
class NeonStreamTryOnEngine implements TryOnEngineInterface {
  final PoseDetector _poseDetector;
  final double smoothingAlpha;

  PoseLandmarks? _smoothedLandmarks;
  DateTime? _lastValidPoseAt;

  NeonStreamTryOnEngine({this.smoothingAlpha = 0.35})
      : _poseDetector = PoseDetector(
          options: PoseDetectorOptions(
            mode: PoseDetectionMode.stream,
            model: PoseDetectionModel.base,
          ),
        );

  /// 切换摄像头或重置会话时清空 EMA 历史状态
  void resetSmoothing() {
    _smoothedLandmarks = null;
    _lastValidPoseAt = null;
  }

  @override
  Future<PoseLandmarks?> detectPose(TryOnFrame frame) async {
    final InputImage? inputImage = _buildInputImage(frame);
    if (inputImage == null) return _smoothedLandmarks;

    final poses = await _poseDetector.processImage(inputImage);
    if (poses.isEmpty) {
      // 若超过 800ms 未检测到人体，则清空平滑缓存
      if (_lastValidPoseAt != null &&
          DateTime.now().difference(_lastValidPoseAt!).inMilliseconds > 800) {
        _smoothedLandmarks = null;
      }
      return _smoothedLandmarks;
    }

    final pose = poses.first;
    final lsRaw = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rsRaw = pose.landmarks[PoseLandmarkType.rightShoulder];
    if (lsRaw == null || rsRaw == null) return _smoothedLandmarks;

    // 当图像旋转 90° 或 270° 时，ML Kit 输出坐标基于旋转后的逻辑宽高
    final bool isRotated =
        frame.rotationDegrees == 90 || frame.rotationDegrees == 270;
    final int logicalW = isRotated ? frame.height : frame.width;
    final int logicalH = isRotated ? frame.width : frame.height;

    BodyPoint pt(PoseLandmarkType type, double fallbackX, double fallbackY) {
      final l = pose.landmarks[type];
      if (l == null) {
        return BodyPoint(x: fallbackX, y: fallbackY, confidence: 0.3);
      }
      return BodyPoint(x: l.x, y: l.y, confidence: l.likelihood);
    }

    final ls = pt(PoseLandmarkType.leftShoulder, logicalW * 0.6, logicalH * 0.25);
    final rs = pt(PoseLandmarkType.rightShoulder, logicalW * 0.4, logicalH * 0.25);
    final shoulderW = max(24.0, (ls.x - rs.x).abs());

    final rawLandmarks = PoseLandmarks(
      leftShoulder: ls,
      rightShoulder: rs,
      leftElbow: pt(
        PoseLandmarkType.leftElbow,
        ls.x + shoulderW * 0.18,
        ls.y + shoulderW * 0.65,
      ),
      rightElbow: pt(
        PoseLandmarkType.rightElbow,
        rs.x - shoulderW * 0.18,
        rs.y + shoulderW * 0.65,
      ),
      leftHip: pt(
        PoseLandmarkType.leftHip,
        ls.x - shoulderW * 0.08,
        ls.y + shoulderW * 1.45,
      ),
      rightHip: pt(
        PoseLandmarkType.rightHip,
        rs.x + shoulderW * 0.08,
        rs.y + shoulderW * 1.45,
      ),
      leftKnee: pt(
        PoseLandmarkType.leftKnee,
        ls.x - shoulderW * 0.08,
        ls.y + shoulderW * 2.55,
      ),
      rightKnee: pt(
        PoseLandmarkType.rightKnee,
        rs.x + shoulderW * 0.08,
        rs.y + shoulderW * 2.55,
      ),
      imageWidth: logicalW,
      imageHeight: logicalH,
    );

    _lastValidPoseAt = DateTime.now();
    if (_smoothedLandmarks == null) {
      _smoothedLandmarks = rawLandmarks;
    } else {
      _smoothedLandmarks =
          _smoothedLandmarks!.smoothWith(rawLandmarks, smoothingAlpha);
    }
    return _smoothedLandmarks;
  }

  InputImage? _buildInputImage(TryOnFrame frame) {
    if (frame.bytes != null && frame.isVideoStreamFrame) {
      final rotation =
          InputImageRotationValue.fromRawValue(frame.rotationDegrees) ??
              InputImageRotation.rotation0deg;
      final format = frame.pixelFormat == 'bgra8888'
          ? InputImageFormat.bgra8888
          : InputImageFormat.nv21;
      return InputImage.fromBytes(
        bytes: frame.bytes!,
        metadata: InputImageMetadata(
          size: Size(frame.width.toDouble(), frame.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow:
              frame.bytesPerRow > 0 ? frame.bytesPerRow : frame.width,
        ),
      );
    }
    if (frame.filePath != null) {
      return InputImage.fromFilePath(frame.filePath!);
    }
    return null;
  }

  /// 根据平滑后的骨骼点，实时计算映射到屏幕预览区的衣物仿射/透视变形矩阵
  GarmentOverlayTransform computeOverlayTransform({
    required String category,
    required PoseLandmarks landmarks,
    required Size previewSize,
    required bool mirrorX,
  }) {
    final scaleX = previewSize.width / max(1, landmarks.imageWidth);
    final scaleY = previewSize.height / max(1, landmarks.imageHeight);

    Offset mapPt(BodyPoint p) {
      final x = p.x * scaleX;
      final y = p.y * scaleY;
      return Offset(mirrorX ? (previewSize.width - x) : x, y);
    }

    final ls = mapPt(landmarks.leftShoulder);
    final rs = mapPt(landmarks.rightShoulder);
    final le = mapPt(landmarks.leftElbow);
    final re = mapPt(landmarks.rightElbow);
    final lh = mapPt(landmarks.leftHip);
    final rh = mapPt(landmarks.rightHip);
    final lk = mapPt(landmarks.leftKnee);
    final rk = mapPt(landmarks.rightKnee);

    // 统一左右端点（屏幕左 -> 屏幕右）
    final topL = ls.dx <= rs.dx ? ls : rs;
    final topR = ls.dx <= rs.dx ? rs : ls;
    final hipL = lh.dx <= rh.dx ? lh : rh;
    final hipR = lh.dx <= rh.dx ? rh : lh;
    final kneeL = lk.dx <= rk.dx ? lk : rk;
    final kneeR = lk.dx <= rk.dx ? rk : lk;

    late Offset center;
    late double targetWidth;
    late double targetHeight;
    late double angle;
    late double skewX;

    if (category == 'bottom') {
      final hipSpan = (hipR - hipL).distance;
      final legLength = max(
        hipSpan * 1.45,
        ((kneeL - hipL).distance + (kneeR - hipR).distance) * 0.78,
      );
      final hipMid = Offset((hipL.dx + hipR.dx) / 2, (hipL.dy + hipR.dy) / 2);
      final kneeMid =
          Offset((kneeL.dx + kneeR.dx) / 2, (kneeL.dy + kneeR.dy) / 2);
      center = Offset(
        (hipMid.dx + kneeMid.dx) / 2,
        hipMid.dy + legLength * 0.44,
      );
      targetWidth = max(60.0, hipSpan * 1.65);
      targetHeight = max(80.0, legLength * 1.35);
      angle = atan2(hipR.dy - hipL.dy, hipR.dx - hipL.dx);
      skewX = ((kneeMid.dx - hipMid.dx) / max(1.0, legLength)).clamp(-0.28, 0.28);
    } else {
      final shoulderSpan = (topR - topL).distance;
      final elbowSpan = (le - re).distance;
      final torsoLen = max(
        shoulderSpan * 1.15,
        ((hipL - topL).distance + (hipR - topR).distance) / 2,
      );
      final shoulderMid =
          Offset((topL.dx + topR.dx) / 2, (topL.dy + topR.dy) / 2);
      final hipMid = Offset((hipL.dx + hipR.dx) / 2, (hipL.dy + hipR.dy) / 2);

      final bool isDress = category == 'dress';
      final bool isOuter = category == 'outerwear';
      final widthFactor = isOuter ? 1.85 : 1.68;
      final heightFactor = isDress ? 2.05 : (isOuter ? 1.38 : 1.28);

      // 结合肘部宽度微调袖口/肩宽贴合度
      final adaptiveWidth =
          max(shoulderSpan * widthFactor, elbowSpan * 0.92);
      targetWidth = max(72.0, adaptiveWidth);
      targetHeight = max(84.0, torsoLen * heightFactor);

      center = Offset(
        (shoulderMid.dx * 0.55 + hipMid.dx * 0.45),
        shoulderMid.dy + targetHeight * 0.42,
      );
      angle = atan2(topR.dy - topL.dy, topR.dx - topL.dx);
      skewX = ((hipMid.dx - shoulderMid.dx) / max(1.0, torsoLen))
          .clamp(-0.25, 0.25);
    }

    // 构建包含平移、旋转、倾斜与轻微透视的 4x4 变形矩阵
    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.0012)
      ..rotateZ(angle)
      ..setEntry(0, 1, skewX * 0.35);

    return GarmentOverlayTransform(
      matrix: matrix,
      width: targetWidth,
      height: targetHeight,
      center: center,
      rotationRad: angle,
      skewX: skewX,
    );
  }

  /// 离线单帧合成实现（用于直接从视频帧字节流导出静态合成图）
  @override
  Future<Uint8List> renderTryOn({
    required TryOnFrame bodyFrame,
    required List<ClothingItem> garments,
    required PoseLandmarks landmarks,
  }) async {
    final Uint8List bodyBytes = bodyFrame.bytes ??
        await File(bodyFrame.filePath!).readAsBytes();
    final decodedBody = img.decodeImage(bodyBytes);
    if (decodedBody == null) return bodyBytes;

    cv.Mat canvasMat = cv.imdecode(bodyBytes, cv.IMREAD_COLOR);
    final ordered = List<ClothingItem>.from(garments)
      ..sort((a, b) => _layerOrder(a.category).compareTo(_layerOrder(b.category)));

    for (final garment in ordered) {
      final alphaPath =
          garment.cutoutImgPath.replaceAll('cutout_white', 'cutout_alpha');
      final file = File(alphaPath).existsSync()
          ? File(alphaPath)
          : File(garment.cutoutImgPath);
      if (!await file.exists()) continue;

      final gBytes = await file.readAsBytes();
      final gDecoded = img.decodeImage(gBytes);
      if (gDecoded == null) continue;

      final t = computeOverlayTransform(
        category: garment.category,
        landmarks: landmarks,
        previewSize: Size(canvasMat.cols.toDouble(), canvasMat.rows.toDouble()),
        mirrorX: false,
      );

      final halfW = t.width / 2;
      final halfH = t.height / 2;
      final cosA = cos(t.rotationRad);
      final sinA = sin(t.rotationRad);

      cv.Point2f rotPt(double dx, double dy) {
        return cv.Point2f(
          t.center.dx + dx * cosA - dy * sinA,
          t.center.dy + dx * sinA + dy * cosA,
        );
      }

      final srcPts = cv.VecPoint2f.fromList([
        cv.Point2f(0, 0),
        cv.Point2f(gDecoded.width.toDouble(), 0),
        cv.Point2f(0, gDecoded.height.toDouble()),
      ]);
      final dstPts = cv.VecPoint2f.fromList([
        rotPt(-halfW, -halfH),
        rotPt(halfW, -halfH),
        rotPt(-halfW, halfH),
      ]);

      final affine = cv.getAffineTransform2f(srcPts, dstPts);
      final pngBytes = Uint8List.fromList(img.encodePng(gDecoded));
      final gBgra = cv.imdecode(pngBytes, cv.IMREAD_UNCHANGED);
      final warped = cv.warpAffine(
        gBgra,
        affine,
        (canvasMat.cols, canvasMat.rows),
      );

      final channels = cv.split(warped);
      cv.Mat alphaMask;
      if (channels.length == 4) {
        alphaMask = cv.gaussianBlur(channels[3], (5, 5), 0);
      } else {
        final gray = cv.cvtColor(warped, cv.COLOR_BGR2GRAY);
        final (_, mask) = cv.threshold(gray, 245, 255, cv.THRESH_BINARY_INV);
        alphaMask = cv.gaussianBlur(mask, (5, 5), 0);
        gray.dispose();
        mask.dispose();
      }

      final warpedBgr = channels.length >= 3
          ? cv.merge(cv.VecMat.fromList([channels[0], channels[1], channels[2]]))
          : warped;

      final fgData = warpedBgr.data;
      final alphaData = alphaMask.data;
      final bgData = canvasMat.data;

      for (int i = 0; i < alphaData.length; i++) {
        final a = alphaData[i] / 255.0;
        if (a <= 0.01) continue;
        final idx = i * 3;
        if (idx + 2 >= bgData.length || idx + 2 >= fgData.length) break;
        bgData[idx] = (fgData[idx] * a + bgData[idx] * (1.0 - a)).round();
        bgData[idx + 1] =
            (fgData[idx + 1] * a + bgData[idx + 1] * (1.0 - a)).round();
        bgData[idx + 2] =
            (fgData[idx + 2] * a + bgData[idx + 2] * (1.0 - a)).round();
      }

      final nextMat = cv.Mat.fromList(
        canvasMat.rows,
        canvasMat.cols,
        cv.MatType.CV_8UC3,
        bgData,
      );

      srcPts.dispose();
      dstPts.dispose();
      affine.dispose();
      gBgra.dispose();
      warped.dispose();
      alphaMask.dispose();
      if (channels.length >= 3) warpedBgr.dispose();
      for (final c in channels) {
        c.dispose();
      }
      canvasMat.dispose();
      canvasMat = nextMat;
    }

    final (_, encoded) = cv.imencode('.png', canvasMat);
    canvasMat.dispose();
    return encoded;
  }

  int _layerOrder(String category) {
    return switch (category) {
      'bottom' => 1,
      'dress' => 2,
      'top' => 3,
      'outerwear' => 4,
      _ => 5,
    };
  }

  @override
  Future<void> dispose() async {
    await _poseDetector.close();
  }
}

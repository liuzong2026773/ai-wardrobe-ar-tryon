import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv;
import '../../../core/database/app_database.dart';
import '../domain/pose_landmarks_model.dart';
import '../domain/try_on_engine_interface.dart';

/// 阶段一静态试穿实现：Google MediaPipe Pose 骨骼检测 + OpenCV 仿射变换与边缘羽化
class StaticTryOnEngine implements TryOnEngineInterface {
  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.single,
      model: PoseDetectionModel.accurate,
    ),
  );

  @override
  Future<PoseLandmarks?> detectPose(TryOnFrame frame) async {
    if (frame.filePath == null) return null;
    final inputImage = InputImage.fromFilePath(frame.filePath!);
    final poses = await _poseDetector.processImage(inputImage);
    if (poses.isEmpty) {
      return _fallbackLandmarks(frame.width, frame.height);
    }

    final pose = poses.first;
    BodyPoint pt(PoseLandmarkType type, double fx, double fy) {
      final l = pose.landmarks[type];
      if (l == null) {
        return BodyPoint(
          x: frame.width * fx,
          y: frame.height * fy,
          confidence: 0.4,
        );
      }
      return BodyPoint(x: l.x, y: l.y, confidence: l.likelihood);
    }

    return PoseLandmarks(
      leftShoulder: pt(PoseLandmarkType.leftShoulder, 0.60, 0.24),
      rightShoulder: pt(PoseLandmarkType.rightShoulder, 0.40, 0.24),
      leftElbow: pt(PoseLandmarkType.leftElbow, 0.66, 0.38),
      rightElbow: pt(PoseLandmarkType.rightElbow, 0.34, 0.38),
      leftHip: pt(PoseLandmarkType.leftHip, 0.57, 0.50),
      rightHip: pt(PoseLandmarkType.rightHip, 0.43, 0.50),
      leftKnee: pt(PoseLandmarkType.leftKnee, 0.56, 0.72),
      rightKnee: pt(PoseLandmarkType.rightKnee, 0.44, 0.72),
      imageWidth: frame.width,
      imageHeight: frame.height,
    );
  }

  PoseLandmarks _fallbackLandmarks(int w, int h) {
    return PoseLandmarks(
      leftShoulder: BodyPoint(x: w * 0.60, y: h * 0.24, confidence: 0.5),
      rightShoulder: BodyPoint(x: w * 0.40, y: h * 0.24, confidence: 0.5),
      leftElbow: BodyPoint(x: w * 0.66, y: h * 0.38, confidence: 0.5),
      rightElbow: BodyPoint(x: w * 0.34, y: h * 0.38, confidence: 0.5),
      leftHip: BodyPoint(x: w * 0.57, y: h * 0.50, confidence: 0.5),
      rightHip: BodyPoint(x: w * 0.43, y: h * 0.50, confidence: 0.5),
      leftKnee: BodyPoint(x: w * 0.56, y: h * 0.72, confidence: 0.5),
      rightKnee: BodyPoint(x: w * 0.44, y: h * 0.72, confidence: 0.5),
      imageWidth: w,
      imageHeight: h,
    );
  }

  @override
  Future<Uint8List> renderTryOn({
    required TryOnFrame bodyFrame,
    required List<ClothingItem> garments,
    required PoseLandmarks landmarks,
  }) async {
    final Uint8List bodyBytes = bodyFrame.bytes ??
        await File(bodyFrame.filePath!).readAsBytes();
    final bodyImg = img.decodeImage(bodyBytes);
    if (bodyImg == null) return bodyBytes;

    final ordered = List<ClothingItem>.from(garments)
      ..sort((a, b) => _layerOrder(a.category).compareTo(_layerOrder(b.category)));

    cv.Mat canvasMat = cv.imdecode(bodyBytes, cv.IMREAD_COLOR);

    for (final garment in ordered) {
      final alphaPath =
          garment.cutoutImgPath.replaceAll('cutout_white', 'cutout_alpha');
      final file = File(alphaPath).existsSync()
          ? File(alphaPath)
          : File(garment.cutoutImgPath);
      if (!await file.exists()) continue;

      final garmentBytes = await file.readAsBytes();
      final garmentDecoded = img.decodeImage(garmentBytes);
      if (garmentDecoded == null) continue;

      final anchor = _computeTargetQuad(garment.category, landmarks);
      canvasMat = _warpAndFeatherComposite(
        canvasMat: canvasMat,
        garmentDecoded: garmentDecoded,
        dstTopLeft: anchor.$1,
        dstTopRight: anchor.$2,
        dstBottomLeft: anchor.$3,
      );
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

  (cv.Point2f, cv.Point2f, cv.Point2f) _computeTargetQuad(
    String category,
    PoseLandmarks lm,
  ) {
    final shoulderSpan = (lm.leftShoulder.x - lm.rightShoulder.x).abs();
    final padX = max(20.0, shoulderSpan * 0.25);

    if (category == 'bottom') {
      final topY = min(lm.leftHip.y, lm.rightHip.y) - 10;
      final botY = max(lm.leftKnee.y, lm.rightKnee.y) + shoulderSpan * 0.45;
      final minX = min(lm.rightHip.x, lm.leftHip.x) - padX * 0.8;
      final maxX = max(lm.rightHip.x, lm.leftHip.x) + padX * 0.8;
      return (
        cv.Point2f(minX, topY),
        cv.Point2f(maxX, topY),
        cv.Point2f(minX, botY),
      );
    }

    final topY = min(lm.leftShoulder.y, lm.rightShoulder.y) - 18;
    final botY = category == 'dress'
        ? max(lm.leftKnee.y, lm.rightKnee.y) + 24
        : max(lm.leftHip.y, lm.rightHip.y) + 20;
    final minX = min(lm.rightShoulder.x, lm.leftShoulder.x) - padX;
    final maxX = max(lm.rightShoulder.x, lm.leftShoulder.x) + padX;
    return (
      cv.Point2f(minX, topY),
      cv.Point2f(maxX, topY),
      cv.Point2f(minX, botY),
    );
  }

  cv.Mat _warpAndFeatherComposite({
    required cv.Mat canvasMat,
    required img.Image garmentDecoded,
    required cv.Point2f dstTopLeft,
    required cv.Point2f dstTopRight,
    required cv.Point2f dstBottomLeft,
  }) {
    final gw = garmentDecoded.width.toDouble();
    final gh = garmentDecoded.height.toDouble();

    final srcPts = cv.VecPoint2f.fromList([
      cv.Point2f(0, 0),
      cv.Point2f(gw, 0),
      cv.Point2f(0, gh),
    ]);
    final dstPts = cv.VecPoint2f.fromList([
      dstTopLeft,
      dstTopRight,
      dstBottomLeft,
    ]);

    final affine = cv.getAffineTransform2f(srcPts, dstPts);

    final pngBytes = Uint8List.fromList(img.encodePng(garmentDecoded));
    final garmentBgra = cv.imdecode(pngBytes, cv.IMREAD_UNCHANGED);
    final warped = cv.warpAffine(
      garmentBgra,
      affine,
      (canvasMat.cols, canvasMat.rows),
    );

    final channels = cv.split(warped);
    cv.Mat alphaMask;
    if (channels.length == 4) {
      alphaMask = cv.gaussianBlur(channels[3], (7, 7), 0);
    } else {
      final gray = cv.cvtColor(warped, cv.COLOR_BGR2GRAY);
      final (_, mask) = cv.threshold(gray, 245, 255, cv.THRESH_BINARY_INV);
      alphaMask = cv.gaussianBlur(mask, (7, 7), 0);
      gray.dispose();
      mask.dispose();
    }

    final warpedBgr = channels.length >= 3
        ? cv.merge(cv.VecMat.fromList([channels[0], channels[1], channels[2]]))
        : warped;

    final outImg = img.Image.fromBytes(
      width: canvasMat.cols,
      height: canvasMat.rows,
      bytes: canvasMat.data.buffer,
      order: img.ChannelOrder.bgr,
    );
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

    final resultMat = cv.Mat.fromList(
      outImg.height,
      outImg.width,
      cv.MatType.CV_8UC3,
      bgData,
    );

    srcPts.dispose();
    dstPts.dispose();
    affine.dispose();
    garmentBgra.dispose();
    warped.dispose();
    alphaMask.dispose();
    if (channels.length >= 3) warpedBgr.dispose();
    for (final c in channels) {
      c.dispose();
    }
    canvasMat.dispose();

    return resultMat;
  }

  @override
  Future<void> dispose() async {
    await _poseDetector.close();
  }
}

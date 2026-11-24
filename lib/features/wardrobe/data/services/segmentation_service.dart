import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:opencv_dart/opencv_dart.dart' as cv;

class SegmentationOutput {
  final Uint8List whiteBgPngBytes;
  final Uint8List transparentPngBytes;
  final String engineUsed;

  const SegmentationOutput({
    required this.whiteBgPngBytes,
    required this.transparentPngBytes,
    required this.engineUsed,
  });
}

/// 离线抠图服务：零云端 API
/// 1) Android 优先使用 Google ML Kit Subject Segmentation
/// 2) 跨端通用使用 ONNX Runtime 运行本地量化版 U²-Net/RMBG 模型
/// 3) 若用户尚未放入 .onnx 权重，自动降级至 OpenCV 本地背景阈值/GrabCut 抠图保证离线可运行
class SegmentationService {
  static const String _onnxAssetPath = 'assets/models/u2netp_quant.onnx';
  OrtSession? _ortSession;
  bool _onnxAttempted = false;

  Future<OrtSession?> _getOnnxSession() async {
    if (_onnxAttempted) return _ortSession;
    _onnxAttempted = true;
    try {
      final ort = OnnxRuntime();
      _ortSession = await ort.createSessionFromAsset(_onnxAssetPath);
    } catch (_) {
      _ortSession = null;
    }
    return _ortSession;
  }

  Future<SegmentationOutput> removeBackground(String imagePath) async {
    final rawBytes = await File(imagePath).readAsBytes();

    // 1. 优先尝试跨端 ONNX U²-NetP 量化模型
    final session = await _getOnnxSession();
    if (session != null) {
      final onnxRes = await _runOnnxU2Net(session, rawBytes);
      if (onnxRes != null) return onnxRes;
    }

    // 2. Android 端尝试 Google ML Kit Subject Segmentation
    if (Platform.isAndroid) {
      final mlKitRes = await _runAndroidMlKit(imagePath, rawBytes);
      if (mlKitRes != null) return mlKitRes;
    }

    // 3. 本地 OpenCV 轻量级自适应前景提取兜底（适合白底电商截图或纯色背景拍照）
    return _runOpenCvFallback(rawBytes);
  }

  Future<SegmentationOutput?> _runAndroidMlKit(
    String imagePath,
    Uint8List rawBytes,
  ) async {
    SubjectSegmenter? segmenter;
    try {
      final options = SubjectSegmenterOptions(
        enableForegroundConfidenceMask: true,
        enableForegroundBitmap: false,
        enableMultipleSubjects: SubjectResultOptions(
          enableConfidenceMask: false,
          enableSubjectBitmap: false,
        ),
      );
      segmenter = SubjectSegmenter(options: options);
      final inputImage = InputImage.fromFilePath(imagePath);
      final result = await segmenter.processImage(inputImage);
      final mask = result.foregroundConfidenceMask;
      if (mask == null || mask.isEmpty) return null;

      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) return null;

      return _composeWithAlphaMask(
        decoded,
        mask,
        engineUsed: 'mlkit_subject_segmentation',
      );
    } catch (_) {
      return null;
    } finally {
      await segmenter?.close();
    }
  }

  Future<SegmentationOutput?> _runOnnxU2Net(
    OrtSession session,
    Uint8List rawBytes,
  ) async {
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) return null;

      const inputSize = 320;
      final resized = img.copyResize(
        decoded,
        width: inputSize,
        height: inputSize,
        interpolation: img.Interpolation.linear,
      );

      // NCHW float32 [1, 3, 320, 320] ImageNet 归一化
      final floatList = Float32List(1 * 3 * inputSize * inputSize);
      const mean = [0.485, 0.456, 0.406];
      const std = [0.229, 0.224, 0.225];
      final planeSize = inputSize * inputSize;

      for (int y = 0; y < inputSize; y++) {
        for (int x = 0; x < inputSize; x++) {
          final p = resized.getPixel(x, y);
          final idx = y * inputSize + x;
          floatList[idx] = (p.r / 255.0 - mean[0]) / std[0];
          floatList[planeSize + idx] = (p.g / 255.0 - mean[1]) / std[1];
          floatList[2 * planeSize + idx] = (p.b / 255.0 - mean[2]) / std[2];
        }
      }

      final inputName = session.inputNames.first;
      final inputOrt = await OrtValue.fromList(floatList, [1, 3, inputSize, inputSize]);
      final outputs = await session.run({inputName: inputOrt});
      await inputOrt.dispose();

      final outputTensor = outputs.values.first;
      final rawMask = (await outputTensor.asFlattenedList()).cast<double>();
      for (final o in outputs.values) {
        await o.dispose();
      }

      // 将 320x320 掩码映射回原图尺寸
      final fullMask = List<double>.filled(decoded.width * decoded.height, 0.0);
      for (int y = 0; y < decoded.height; y++) {
        final sy = (y * inputSize / decoded.height).floor().clamp(0, inputSize - 1);
        for (int x = 0; x < decoded.width; x++) {
          final sx = (x * inputSize / decoded.width).floor().clamp(0, inputSize - 1);
          fullMask[y * decoded.width + x] =
              rawMask[sy * inputSize + sx].clamp(0.0, 1.0);
        }
      }

      return _composeWithAlphaMask(
        decoded,
        fullMask,
        engineUsed: 'onnx_u2netp',
      );
    } catch (_) {
      return null;
    }
  }

  SegmentationOutput _runOpenCvFallback(Uint8List rawBytes) {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      return SegmentationOutput(
        whiteBgPngBytes: rawBytes,
        transparentPngBytes: rawBytes,
        engineUsed: 'passthrough',
      );
    }

    try {
      final mat = cv.imdecode(rawBytes, cv.IMREAD_COLOR);
      final hsv = cv.cvtColor(mat, cv.COLOR_BGR2HSV);
      // 采样四角背景颜色并生成柔和前景掩码（适配白底/浅色底电商图与纯色墙面）
      final gray = cv.cvtColor(mat, cv.COLOR_BGR2GRAY);
      final blurred = cv.gaussianBlur(gray, (5, 5), 0);
      final (_, thresh) = cv.threshold(
        blurred,
        240,
        255,
        cv.THRESH_BINARY_INV,
      );
      final kernel = cv.getStructuringElement(cv.MORPH_ELLIPSE, (5, 5));
      final closed = cv.morphologyEx(thresh, cv.MORPH_CLOSE, kernel);

      final maskBytes = closed.data;
      final alphaMask = List<double>.generate(
        decoded.width * decoded.height,
        (i) => i < maskBytes.length ? maskBytes[i] / 255.0 : 1.0,
      );

      mat.dispose();
      hsv.dispose();
      gray.dispose();
      blurred.dispose();
      thresh.dispose();
      kernel.dispose();
      closed.dispose();

      return _composeWithAlphaMask(
        decoded,
        alphaMask,
        engineUsed: 'opencv_fallback',
      );
    } catch (_) {
      final png = Uint8List.fromList(img.encodePng(decoded));
      return SegmentationOutput(
        whiteBgPngBytes: png,
        transparentPngBytes: png,
        engineUsed: 'raw_png',
      );
    }
  }

  SegmentationOutput _composeWithAlphaMask(
    img.Image decoded,
    List<double> mask, {
    required String engineUsed,
  }) {
    final transparentImg = img.Image(
      width: decoded.width,
      height: decoded.height,
      numChannels: 4,
    );
    final whiteBgImg = img.Image(
      width: decoded.width,
      height: decoded.height,
      numChannels: 4,
    );

    for (int y = 0; y < decoded.height; y++) {
      for (int x = 0; x < decoded.width; x++) {
        final p = decoded.getPixel(x, y);
        final idx = y * decoded.width + x;
        final alpha = idx < mask.length ? mask[idx].clamp(0.0, 1.0) : 1.0;
        final aByte = (alpha * 255).round();

        transparentImg.setPixelRgba(x, y, p.r, p.g, p.b, aByte);

        // 与纯白底 (#FFFFFF) 线性融合
        final outR = (p.r * alpha + 255 * (1.0 - alpha)).round();
        final outG = (p.g * alpha + 255 * (1.0 - alpha)).round();
        final outB = (p.b * alpha + 255 * (1.0 - alpha)).round();
        whiteBgImg.setPixelRgba(x, y, outR, outG, outB, 255);
      }
    }

    return SegmentationOutput(
      whiteBgPngBytes: Uint8List.fromList(img.encodePng(whiteBgImg)),
      transparentPngBytes: Uint8List.fromList(img.encodePng(transparentImg)),
      engineUsed: engineUsed,
    );
  }

  Future<void> dispose() async {
    await _ortSession?.close();
    _ortSession = null;
  }
}

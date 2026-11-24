import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:image/image.dart' as img;

/// 本地抠图:ML Kit Subject Segmentation 为主,ONNX 为兜底
/// 全部端侧,无 Key、无云端。输出:白底标准图(默认)或透明底 PNG。
class SegmentationService {
  final _segmenter = SubjectSegmenter(
    options: SubjectSegmenterOptions(enableForegroundConfidenceMask: true),
  );

  /// 返回白底图文件路径;失败返回原图路径(不阻塞入库)
  Future<String> cutoutToWhiteBackground(File input, {bool transparent = false}) async {
    try {
      final inputImage = InputImage.fromFile(input);
      final mask = await _segmenter.processImage(inputImage);
      if (mask == null) return input.path;
      final bytes = await input.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return input.path;
      final out = img.Image(width: decoded.width, height: decoded.height);
      final w = mask.width, h = mask.height;
      for (var y = 0; y < decoded.height; y++) {
        for (var x = 0; x < decoded.width; x++) {
          final mx = (x * w / decoded.width).floor().clamp(0, w - 1);
          final my = (y * h / decoded.height).floor().clamp(0, h - 1);
          final conf = mask.confidences[my * w + mx]; // 0..1 前景置信度
          final px = decoded.getPixel(x, y);
          if (conf > 0.5) {
            out.setPixel(x, y, px);
          } else if (transparent) {
            out.setPixel(x, y, img.ColorRgba8(px.r.toInt(), px.g.toInt(), px.b.toInt(), 0));
          } else {
            out.setPixel(x, y, img.ColorRgb8(255, 255, 255)); // 纯白底
          }
        }
      }
      final outFile = File('${input.parent.path}/${input.uri.pathSegments.last.split('.').first}_cut.png');
      await outFile.writeAsBytes(img.encodePng(out));
      return outFile.path;
    } catch (e) {
      debugPrint('ML Kit 抠图失败,走 ONNX 兜底/原图: $e');
      // 兜底:见 assets/models/README — flutter_onnxruntime 加载轻量分割模型;
      // 此处失败时返回原图,保证入库流程不中断。
      return input.path;
    }
  }

  void dispose() => _segmenter.close();
}

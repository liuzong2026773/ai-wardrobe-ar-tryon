import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../utils/color_rules.dart';

/// 本地颜色/品类初判:采样像素 RGB/HSV 聚类取主色;品类用 ML Kit Image Labeling 兜底,
/// 季节按颜色深浅+用户弹窗微调为准(不做不可靠的自动季节判定)。
class ColorService {
  static Future<Color> dominantColorOf(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return const Color(0xFF888888);
      final small = img.copyResize(decoded, width: 64);
      final pixels = <Color>[];
      for (var y = 0; y < small.height; y += 2) {
        for (var x = 0; x < small.width; x += 2) {
          final p = small.getPixel(x, y);
          pixels.add(Color.fromARGB(255, p.r.toInt(), p.g.toInt(), p.b.toInt()));
        }
      }
      return ColorRules.dominantColor(pixels);
    } catch (e) {
      debugPrint('主色提取失败: $e');
      return const Color(0xFF888888);
    }
  }

  static String hexOf(Color c) =>
      '#${c.red.toRadixString(16).padLeft(2, '0')}${c.green.toRadixString(16).padLeft(2, '0')}${c.blue.toRadixString(16).padLeft(2, '0')}'
          .toUpperCase();
}

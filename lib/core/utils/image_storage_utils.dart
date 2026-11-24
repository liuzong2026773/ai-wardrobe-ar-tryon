import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../constants/wardrobe_constants.dart';

class ColorExtractionResult {
  final String colorName;
  final String colorHex;
  const ColorExtractionResult({required this.colorName, required this.colorHex});
}

class ImageStorageUtils {
  static Future<Directory> _ensureSubDir(String subDir) async {
    final baseDir = await getApplicationDocumentsDirectory();
    final target = Directory(p.join(baseDir.path, 'wardrobe_assets', subDir));
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target;
  }

  /// 将图像字节保存到本地沙盒并返回绝对路径
  static Future<String> saveImageBytes(
    Uint8List bytes, {
    required String subDir,
    String extension = 'png',
  }) async {
    final dir = await _ensureSubDir(subDir);
    final filename =
        '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}.$extension';
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// 从中心前景区域采样像素，映射到最近的标准色系（忽略透明和纯白背景像素）
  static ColorExtractionResult extractDominantColor(Uint8List pngBytes) {
    final decoded = img.decodeImage(pngBytes);
    if (decoded == null) {
      return const ColorExtractionResult(colorName: '米白', colorHex: '#F5F2EB');
    }

    int sumR = 0, sumG = 0, sumB = 0, count = 0;
    final stepX = max(1, decoded.width ~/ 40);
    final stepY = max(1, decoded.height ~/ 40);

    for (int y = decoded.height ~/ 6; y < decoded.height * 5 ~/ 6; y += stepY) {
      for (int x = decoded.width ~/ 6; x < decoded.width * 5 ~/ 6; x += stepX) {
        final pixel = decoded.getPixel(x, y);
        final a = pixel.a.toInt();
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();

        // 跳过透明像素以及近乎纯白的背景像素
        final isWhiteBg = r > 248 && g > 248 && b > 248;
        if (a > 180 && !isWhiteBg) {
          sumR += r;
          sumG += g;
          sumB += b;
          count++;
        }
      }
    }

    if (count == 0) {
      return const ColorExtractionResult(colorName: '纯白', colorHex: '#FFFFFF');
    }

    final avgR = sumR ~/ count;
    final avgG = sumG ~/ count;
    final avgB = sumB ~/ count;

    ColorPreset closest = ColorPreset.presets.first;
    double minDist = double.infinity;
    for (final preset in ColorPreset.presets) {
      final dr = avgR - preset.r;
      final dg = avgG - preset.g;
      final db = avgB - preset.b;
      final dist = sqrt(dr * dr + dg * dg + db * db);
      if (dist < minDist) {
        minDist = dist;
        closest = preset;
      }
    }

    return ColorExtractionResult(
      colorName: closest.name,
      colorHex: closest.hex,
    );
  }
}

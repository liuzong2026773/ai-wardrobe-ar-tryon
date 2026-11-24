import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:image/image.dart' as img;
import '../../../../core/utils/image_storage_utils.dart';

class AutoTagResult {
  final String suggestedName;
  final String category;
  final String primaryColor;
  final String colorHex;
  final List<String> seasons;
  final String fitStyle;
  final int tempMin;
  final int tempMax;

  const AutoTagResult({
    required this.suggestedName,
    required this.category,
    required this.primaryColor,
    required this.colorHex,
    required this.seasons,
    required this.fitStyle,
    required this.tempMin,
    required this.tempMax,
  });
}

/// 端侧自动打标服务：MobileNetV3 ONNX 分类 + 主色提取
class AutoTaggerService {
  static const String _classifierModelPath =
      'assets/models/mobilenetv3_fashion.onnx';
  static const List<String> _categories = [
    'top',
    'bottom',
    'dress',
    'outerwear',
    'shoes',
    'accessory',
  ];

  OrtSession? _classifierSession;
  bool _attemptedLoad = false;

  Future<OrtSession?> _getSession() async {
    if (_attemptedLoad) return _classifierSession;
    _attemptedLoad = true;
    try {
      final ort = OnnxRuntime();
      _classifierSession = await ort.createSessionFromAsset(_classifierModelPath);
    } catch (_) {
      _classifierSession = null;
    }
    return _classifierSession;
  }

  Future<AutoTagResult> analyzeClothing(Uint8List transparentPngBytes) async {
    final colorRes = ImageStorageUtils.extractDominantColor(transparentPngBytes);
    final category = await _predictCategory(transparentPngBytes);
    final seasons = _inferSeasons(category, colorRes.colorName);
    final tempRange = _inferTempRange(category, seasons);

    final categoryZh = switch (category) {
      'top' => '上装',
      'bottom' => '下装',
      'dress' => '连衣裙',
      'outerwear' => '外套',
      'shoes' => '鞋子',
      'accessory' => '配饰',
      _ => '单品',
    };

    return AutoTagResult(
      suggestedName: '${colorRes.colorName}$categoryZh',
      category: category,
      primaryColor: colorRes.colorName,
      colorHex: colorRes.colorHex,
      seasons: seasons,
      fitStyle: 'regular',
      tempMin: tempRange.$1,
      tempMax: tempRange.$2,
    );
  }

  Future<String> _predictCategory(Uint8List pngBytes) async {
    final decoded = img.decodeImage(pngBytes);
    if (decoded == null) return 'top';

    final session = await _getSession();
    if (session != null) {
      try {
        const size = 224;
        final resized = img.copyResize(decoded, width: size, height: size);
        final inputData = Float32List(1 * 3 * size * size);
        final plane = size * size;
        for (int y = 0; y < size; y++) {
          for (int x = 0; x < size; x++) {
            final p = resized.getPixel(x, y);
            final idx = y * size + x;
            inputData[idx] = (p.r / 255.0 - 0.485) / 0.229;
            inputData[plane + idx] = (p.g / 255.0 - 0.456) / 0.224;
            inputData[2 * plane + idx] = (p.b / 255.0 - 0.406) / 0.225;
          }
        }
        final inputOrt = await OrtValue.fromList(inputData, [1, 3, size, size]);
        final outputs = await session.run({session.inputNames.first: inputOrt});
        await inputOrt.dispose();

        final logits = (await outputs.values.first.asFlattenedList()).cast<double>();
        for (final o in outputs.values) {
          await o.dispose();
        }

        int bestIdx = 0;
        double maxVal = -double.infinity;
        for (int i = 0; i < min(logits.length, _categories.length); i++) {
          if (logits[i] > maxVal) {
            maxVal = logits[i];
            bestIdx = i;
          }
        }
        return _categories[bestIdx];
      } catch (_) {
        // ONNX 推理异常时回退到启发式宽高比判定
      }
    }

    // 启发式前景轮廓宽高比判定（离线无模型权重时兜底）
    int minX = decoded.width, maxX = 0, minY = decoded.height, maxY = 0;
    for (int y = 0; y < decoded.height; y += 2) {
      for (int x = 0; x < decoded.width; x += 2) {
        final p = decoded.getPixel(x, y);
        if (p.a > 128 && !(p.r > 245 && p.g > 245 && p.b > 245)) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    final fgW = max(1, maxX - minX);
    final fgH = max(1, maxY - minY);
    final ratio = fgH / fgW;

    if (ratio > 1.65) return 'dress';
    if (ratio > 1.25) return 'bottom';
    if (ratio < 0.72) return 'shoes';
    return 'top';
  }

  List<String> _inferSeasons(String category, String colorName) {
    if (category == 'outerwear') return ['autumn', 'winter'];
    if (category == 'dress') return ['spring', 'summer'];
    if (colorName == '粉色' || colorName == '浅蓝' || colorName == '纯白') {
      return ['spring', 'summer'];
    }
    if (colorName == '焦糖' || colorName == '酒红' || colorName == '深灰') {
      return ['autumn', 'winter'];
    }
    return ['spring', 'autumn'];
  }

  (int, int) _inferTempRange(String category, List<String> seasons) {
    if (category == 'outerwear' || seasons.contains('winter')) return (0, 18);
    if (seasons.contains('summer') && !seasons.contains('autumn')) {
      return (22, 38);
    }
    return (14, 26);
  }

  Future<void> dispose() async {
    await _classifierSession?.close();
    _classifierSession = null;
  }
}

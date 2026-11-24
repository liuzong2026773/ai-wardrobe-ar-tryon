import 'dart:math';
import 'dart:ui';

/// 色彩搭配规则库:同色系 / 莫兰迪 / 互补色 — 纯本地规则,无云端
class ColorRules {
  /// HSV 距离:色相环距离 + 饱和/明度差
  static double harmonyScore(Color a, Color b, String rule) {
    final ha = HSVColor.fromColor(a), hb = HSVColor.fromColor(b);
    double dh = (ha.hue - hb.hue).abs();
    if (dh > 180) dh = 360 - dh;
    final ds = (ha.saturation - hb.saturation).abs();
    final dv = (ha.value - hb.value).abs();
    switch (rule) {
      case '同色系': return dh < 30 && ds < 0.35 ? 1.0 - dh / 60 : 0.0;
      case '莫兰迪': // 低饱和 + 明度接近 = 莫兰迪
        return (ha.saturation < 0.45 && hb.saturation < 0.45 && dv < 0.25)
            ? 0.9 : 0.2;
      case '互补色': return (dh > 150 && dh < 210) ? 1.0 - (dh - 180).abs() / 60 : 0.0;
      default: return 1.0 - (dh / 360 + ds + dv) / 3;
    }
  }

  /// 温度区间过滤:返回该气温适合的季节
  static List<String> seasonsForTemp(double tempC) {
    if (tempC >= 26) return ['夏'];
    if (tempC >= 18) return ['春', '夏', '秋'];
    if (tempC >= 10) return ['春', '秋'];
    if (tempC >= 0) return ['秋', '冬'];
    return ['冬'];
  }

  /// 主色命名(粗聚类):用于标签
  static String familyOf(Color c) {
    final hsv = HSVColor.fromColor(c);
    if (hsv.saturation < 0.12) {
      if (hsv.value > 0.85) return '白色系';
      if (hsv.value < 0.2) return '黑色系';
      return '灰色系';
    }
    if (hsv.saturation < 0.45 && hsv.value < 0.75) return '莫兰迪色系';
    final h = hsv.hue;
    if (h < 15 || h >= 345) return '红色系';
    if (h < 45) return '橙色系';
    if (h < 70) return '黄色系';
    if (h < 170) return '绿色系';
    if (h < 250) return '蓝色系';
    if (h < 290) return '紫色系';
    return '粉色系';
  }

  /// RGB/HSV 聚类主色:采样像素取出现最多的量化色
  static Color dominantColor(List<Color> pixels) {
    final counts = <int, int>{};
    for (final c in pixels) {
      final q = ((c.red ~/ 32) << 10) | ((c.green ~/ 32) << 5) | (c.blue ~/ 32);
      counts[q] = (counts[q] ?? 0) + 1;
    }
    final top = counts.entries.reduce((a, b) => a.value > b.value ? a : b).key;
    final r = ((top >> 10) & 31) * 32 + 16, g = ((top >> 5) & 31) * 32 + 16, b = (top & 31) * 32 + 16;
    return Color.fromARGB(255, min(r, 255), min(g, 255), min(b, 255));
  }
}

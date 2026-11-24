import 'package:flutter_test/flutter_test.dart';
import 'package:ai_wardrobe_ar_tryon/utils/color_rules.dart';
import 'package:flutter/material.dart';

void main() {
  test('温度过滤:30°C 只推夏季', () {
    expect(ColorRules.seasonsForTemp(30), ['夏']);
  });
  test('温度过滤:5°C 推秋冬', () {
    expect(ColorRules.seasonsForTemp(5), ['秋', '冬']);
  });
  test('莫兰迪色识别:低饱和灰蓝', () {
    expect(ColorRules.familyOf(const Color(0xFF8A9BA8)), '莫兰迪色系');
  });
  test('同色系和谐度:色相接近得分高', () {
    final s = ColorRules.harmonyScore(
        const Color(0xFF3A5A7A), const Color(0xFF4A6A8A), '同色系');
    expect(s, greaterThan(0.5));
  });
}

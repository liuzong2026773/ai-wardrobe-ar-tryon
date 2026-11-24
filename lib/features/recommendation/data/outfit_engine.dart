import 'dart:convert';
import 'package:flutter/services.dart';
import '../../../core/database/app_database.dart';

class RecommendedOutfit {
  final String title;
  final String styleTag;
  final int score;
  final List<ClothingItem> items;

  const RecommendedOutfit({
    required this.title,
    required this.styleTag,
    required this.score,
    required this.items,
  });
}

/// 本地智能穿搭推荐引擎（零云端 API）
/// 结合：温度区间过滤 + 色彩搭配规则库（同色系/莫兰迪/互补色）+ 上下装版型匹配
class OutfitEngine {
  Map<String, dynamic>? _rulesCache;

  Future<Map<String, dynamic>> _loadRules() async {
    if (_rulesCache != null) return _rulesCache!;
    final raw =
        await rootBundle.loadString('assets/rules/color_harmony_rules.json');
    _rulesCache = jsonDecode(raw) as Map<String, dynamic>;
    return _rulesCache!;
  }

  Future<List<RecommendedOutfit>> generateDailyTop3({
    required List<ClothingItem> allItems,
    required double tempCelsius,
  }) async {
    if (allItems.isEmpty) return [];

    final rules = await _loadRules();
    final tempInt = tempCelsius.round();

    // 1. 温度区间过滤（若严格过滤不足，则放宽至全部单品兜底）
    var candidates = allItems
        .where((i) => i.tempMin <= tempInt && i.tempMax >= tempInt)
        .toList();
    if (candidates.length < 3) {
      candidates = List<ClothingItem>.from(allItems);
    }

    final tops = candidates.where((e) => e.category == 'top').toList();
    final bottoms = candidates.where((e) => e.category == 'bottom').toList();
    final dresses = candidates.where((e) => e.category == 'dress').toList();
    final outerwears =
        candidates.where((e) => e.category == 'outerwear').toList();
    final shoesList = candidates.where((e) => e.category == 'shoes').toList();

    final needOuterwear = tempInt <= 18;
    final List<RecommendedOutfit> scored = [];

    // 2. 生成“上装 + 下装 (+ 外套 + 鞋子)”组合并打分
    for (final top in tops) {
      for (final bottom in bottoms) {
        final colorMatch = _evaluateColorHarmony(
          top.primaryColor,
          bottom.primaryColor,
          rules,
        );
        final fitMatch = _evaluateFitPairing(
          top.fitStyle,
          bottom.fitStyle,
          rules,
        );

        final combo = <ClothingItem>[top, bottom];
        int totalScore = 50 + colorMatch.$2 + fitMatch.$2;

        if (needOuterwear && outerwears.isNotEmpty) {
          final bestOuter = _pickBestOuterwear(top, outerwears, rules);
          combo.add(bestOuter);
          totalScore += 10;
        }
        if (shoesList.isNotEmpty) {
          combo.add(shoesList.first);
        }

        // 优先推荐平时穿着次数较少的单品，提高衣橱利用率
        totalScore -= (top.wearCount + bottom.wearCount).clamp(0, 15);

        final tag = '${colorMatch.$1} · ${fitMatch.$1}';
        scored.add(
          RecommendedOutfit(
            title: '${top.primaryColor}${top.name} × ${bottom.name}',
            styleTag: tag,
            score: totalScore,
            items: combo,
          ),
        );
      }
    }

    // 3. 支持连衣裙组合
    for (final dress in dresses) {
      final combo = <ClothingItem>[dress];
      int totalScore = 65 - dress.wearCount.clamp(0, 10);
      if (needOuterwear && outerwears.isNotEmpty) {
        combo.add(_pickBestOuterwear(dress, outerwears, rules));
        totalScore += 10;
      }
      if (shoesList.isNotEmpty) {
        combo.add(shoesList.first);
      }
      scored.add(
        RecommendedOutfit(
          title: '${dress.name} 优雅套装',
          styleTag: '连衣裙 · 极简',
          score: totalScore,
          items: combo,
        ),
      );
    }

    scored.sort((a, b) => b.score.compareTo(a.score));

    // 去重选取 Top 3，避免连续重复同一件上衣
    final List<RecommendedOutfit> top3 = [];
    final Set<int> usedPrimaryIds = {};
    for (final candidate in scored) {
      if (top3.length >= 3) break;
      final primaryId = candidate.items.first.id;
      if (!usedPrimaryIds.contains(primaryId) || scored.length <= 3) {
        top3.add(candidate);
        usedPrimaryIds.add(primaryId);
      }
    }
    return top3;
  }

  (String, int) _evaluateColorHarmony(
    String c1,
    String c2,
    Map<String, dynamic> rules,
  ) {
    final harmonyList = (rules['harmony_rules'] as List<dynamic>?) ?? [];
    for (final rule in harmonyList) {
      final map = rule as Map<String, dynamic>;
      final styleTag = map['style_tag'] as String;
      final bonus = (map['score_bonus'] as num).toInt();

      final pairs = map['pairs'] as List<dynamic>?;
      if (pairs != null) {
        for (final pair in pairs) {
          final p = (pair as List).cast<String>();
          if ((p[0] == c1 && p[1] == c2) || (p[0] == c2 && p[1] == c1)) {
            return (styleTag, bonus);
          }
        }
      }

      final neutrals = (map['neutral_colors'] as List<dynamic>?)?.cast<String>();
      if (neutrals != null && (neutrals.contains(c1) || neutrals.contains(c2))) {
        return (styleTag, bonus);
      }
    }
    return ('日常随心', 5);
  }

  (String, int) _evaluateFitPairing(
    String topFit,
    String bottomFit,
    Map<String, dynamic> rules,
  ) {
    final fitList = (rules['fit_pairing_rules'] as List<dynamic>?) ?? [];
    for (final rule in fitList) {
      final map = rule as Map<String, dynamic>;
      if (map['top'] == topFit && map['bottom'] == bottomFit) {
        return (map['label'] as String, (map['score_bonus'] as num).toInt());
      }
    }
    return ('均衡版型', 6);
  }

  ClothingItem _pickBestOuterwear(
    ClothingItem baseItem,
    List<ClothingItem> outerwears,
    Map<String, dynamic> rules,
  ) {
    ClothingItem best = outerwears.first;
    int bestBonus = -1;
    for (final outer in outerwears) {
      final (_, bonus) =
          _evaluateColorHarmony(baseItem.primaryColor, outer.primaryColor, rules);
      if (bonus > bestBonus) {
        bestBonus = bonus;
        best = outer;
      }
    }
    return best;
  }
}

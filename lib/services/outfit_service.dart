import 'dart:math';
import 'dart:ui';
import '../data/app_database.dart';
import '../utils/color_rules.dart';

/// 本地穿搭算法:温度过滤 + 色彩规则 + 版型匹配,每天 3 套,无云端
class OutfitService {
  final AppDatabase db;
  OutfitService(this.db);

  Future<List<List<ClothingItem>>> dailyRecommendations(double tempC) async {
    final all = await db.allItems;
    if (all.isEmpty) return [];
    final okSeasons = ColorRules.seasonsForTemp(tempC);
    final filtered = all.where((i) {
      final seasons = seasonsFromJson(i.seasons);
      return seasons.any(okSeasons.contains);
    }).toList();
    final pool = filtered.isEmpty ? all : filtered;

    ClothingItem? pick(String category, List<ClothingItem> exclude) {
      final c = pool.where((i) => i.category == category && !exclude.contains(i)).toList();
      if (c.isEmpty) return null;
      c.shuffle(Random(DateTime.now().day)); // 每天换一套组合
      return c.first;
    }

    final outfits = <List<ClothingItem>>[];
    final rules = ['同色系', '莫兰迪', '互补色'];
    for (var k = 0; k < 3; k++) {
      final top = pick('上装', []) ?? pick('连衣裙', []);
      if (top == null) continue;
      final items = <ClothingItem>[top];
      // 下装:优先色彩和谐,其次版型(连衣裙不再配下装)
      if (top.category != '连衣裙') {
        final bottoms = pool.where((i) => i.category == '下装').toList();
        // 按与上装的和谐度降序
        bottoms.sort((a, b) => ColorRules.harmonyScore(_hex(b.mainColorHex), _hex(top.mainColorHex), rules[k])
            .compareTo(ColorRules.harmonyScore(_hex(a.mainColorHex), _hex(top.mainColorHex), rules[k])));
        if (bottoms.isNotEmpty) items.add(bottoms.first);
      }
      final outer = pick('外套', items);
      if (outer != null && tempC < 20) items.add(outer);
      final shoes = pick('鞋子', items);
      if (shoes != null) items.add(shoes);
      outfits.add(items);
    }
    return outfits;
  }

  static Color _hex(String hex) {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }
}

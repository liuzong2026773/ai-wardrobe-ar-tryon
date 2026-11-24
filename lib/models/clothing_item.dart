import 'dart:ui';

enum ClothingCategory { top, bottom, dress, outerwear, shoes, accessory }

extension ClothingCategoryLabel on ClothingCategory {
  String get label => switch (this) {
    ClothingCategory.top => '上装',
    ClothingCategory.bottom => '下装',
    ClothingCategory.dress => '连衣裙',
    ClothingCategory.outerwear => '外套',
    ClothingCategory.shoes => '鞋子',
    ClothingCategory.accessory => '配饰',
  };
  static ClothingCategory fromLabel(String s) => ClothingCategory.values.firstWhere(
      (e) => e.label == s, orElse: () => ClothingCategory.top);
}

enum Season { spring, summer, autumn, winter }

extension SeasonLabel on Season {
  String get label => switch (this) {
    Season.spring => '春',
    Season.summer => '夏',
    Season.autumn => '秋',
    Season.winter => '冬',
  };
}

class WardrobeItem {
  final String id;
  final String name;
  final ClothingCategory category;
  final List<Season> seasons;
  final Color mainColor;
  final String colorFamily; // 如 莫兰迪蓝 / 暖白 / 黑
  final String imagePath; // 白底/透明底标准图(本地)
  final String originalPath;
  final bool isFavorite;
  final int wearCount;
  final DateTime createdAt;

  const WardrobeItem({
    required this.id,
    required this.name,
    required this.category,
    required this.seasons,
    required this.mainColor,
    required this.colorFamily,
    required this.imagePath,
    required this.originalPath,
    this.isFavorite = false,
    this.wearCount = 0,
    required this.createdAt,
  });

  WardrobeItem copyWith({bool? isFavorite, int? wearCount, String? name,
    ClothingCategory? category, List<Season>? seasons, Color? mainColor, String? colorFamily}) =>
    WardrobeItem(id: id, name: name ?? this.name, category: category ?? this.category,
      seasons: seasons ?? this.seasons, mainColor: mainColor ?? this.mainColor,
      colorFamily: colorFamily ?? this.colorFamily, imagePath: imagePath,
      originalPath: originalPath, isFavorite: isFavorite ?? this.isFavorite,
      wearCount: wearCount ?? this.wearCount, createdAt: createdAt);
}

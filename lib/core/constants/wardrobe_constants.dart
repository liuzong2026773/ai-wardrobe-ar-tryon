import 'package:flutter/material.dart';

class ClothingCategory {
  final String key;
  final String label;
  final IconData icon;

  const ClothingCategory({
    required this.key,
    required this.label,
    required this.icon,
  });

  static const all = ClothingCategory(
    key: 'all',
    label: '全部',
    icon: Icons.grid_view_rounded,
  );
  static const top = ClothingCategory(
    key: 'top',
    label: '上装',
    icon: Icons.checkroom_rounded,
  );
  static const bottom = ClothingCategory(
    key: 'bottom',
    label: '下装',
    icon: Icons.straighten_rounded,
  );
  static const dress = ClothingCategory(
    key: 'dress',
    label: '连衣裙',
    icon: Icons.dry_cleaning_rounded,
  );
  static const outerwear = ClothingCategory(
    key: 'outerwear',
    label: '外套',
    icon: Icons.layers_rounded,
  );
  static const shoes = ClothingCategory(
    key: 'shoes',
    label: '鞋子',
    icon: Icons.ice_skating_rounded,
  );
  static const accessory = ClothingCategory(
    key: 'accessory',
    label: '配饰',
    icon: Icons.watch_rounded,
  );

  static const List<ClothingCategory> sidebarItems = [
    all,
    top,
    bottom,
    dress,
    outerwear,
    shoes,
    accessory,
  ];

  static const List<ClothingCategory> editableItems = [
    top,
    bottom,
    dress,
    outerwear,
    shoes,
    accessory,
  ];

  static String labelOf(String key) {
    return sidebarItems
        .firstWhere((e) => e.key == key, orElse: () => top)
        .label;
  }
}

class ClothingSeason {
  final String key;
  final String label;

  const ClothingSeason({required this.key, required this.label});

  static const all = ClothingSeason(key: 'all', label: '四季');
  static const spring = ClothingSeason(key: 'spring', label: '春');
  static const summer = ClothingSeason(key: 'summer', label: '夏');
  static const autumn = ClothingSeason(key: 'autumn', label: '秋');
  static const winter = ClothingSeason(key: 'winter', label: '冬');

  static const List<ClothingSeason> filterItems = [
    all,
    spring,
    summer,
    autumn,
    winter,
  ];

  static const List<ClothingSeason> editableItems = [
    spring,
    summer,
    autumn,
    winter,
  ];

  static String labelOf(String key) {
    return filterItems
        .firstWhere((e) => e.key == key, orElse: () => spring)
        .label;
  }
}

class FitStyleOption {
  final String key;
  final String label;

  const FitStyleOption({required this.key, required this.label});

  static const slim = FitStyleOption(key: 'slim', label: '修身');
  static const regular = FitStyleOption(key: 'regular', label: '标准');
  static const loose = FitStyleOption(key: 'loose', label: '宽松');
  static const cropped = FitStyleOption(key: 'cropped', label: '短款');

  static const List<FitStyleOption> values = [slim, regular, loose, cropped];

  static String labelOf(String key) {
    return values.firstWhere((e) => e.key == key, orElse: () => regular).label;
  }
}

class ColorPreset {
  final String name;
  final String hex;
  final int r;
  final int g;
  final int b;

  const ColorPreset({
    required this.name,
    required this.hex,
    required this.r,
    required this.g,
    required this.b,
  });

  Color get color => Color.fromARGB(255, r, g, b);

  static const List<ColorPreset> presets = [
    ColorPreset(name: '米白', hex: '#F5F2EB', r: 245, g: 242, b: 235),
    ColorPreset(name: '纯白', hex: '#FFFFFF', r: 255, g: 255, b: 255),
    ColorPreset(name: '燕麦', hex: '#E6DEC8', r: 230, g: 222, b: 200),
    ColorPreset(name: '浅灰', hex: '#D3D5D4', r: 211, g: 213, b: 212),
    ColorPreset(name: '深灰', hex: '#5C5F62', r: 92, g: 95, b: 98),
    ColorPreset(name: '黑色', hex: '#1E1E1E', r: 30, g: 30, b: 30),
    ColorPreset(name: '卡其', hex: '#C3B091', r: 195, g: 176, b: 145),
    ColorPreset(name: '焦糖', hex: '#A66A3E', r: 166, g: 106, b: 62),
    ColorPreset(name: '粉色', hex: '#E8B4B8', r: 232, g: 180, b: 184),
    ColorPreset(name: '浅蓝', hex: '#A7C7E7', r: 167, g: 199, b: 231),
    ColorPreset(name: '藏青', hex: '#1F305E', r: 31, g: 48, b: 94),
    ColorPreset(name: '鼠尾草绿', hex: '#9CAF88', r: 156, g: 175, b: 136),
    ColorPreset(name: '酒红', hex: '#722F37', r: 114, g: 47, b: 55),
  ];
}

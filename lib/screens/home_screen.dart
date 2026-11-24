import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../data/app_database.dart';
import '../widgets/clothing_card.dart';

/// 首页:总数统计 + 搜索 + 品类/季节双筛 + 双列瀑布流白底卡片 + 收藏 + 穿搭次数
class HomeScreen extends StatefulWidget {
  final AppDatabase db;
  const HomeScreen({super.key, required this.db});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _query = '';
  String? _category;
  String? _season;
  bool _favOnly = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的衣橱')),
      body: StreamBuilder<List<ClothingItem>>(
        stream: widget.db.watchItems(),
        builder: (_, snap) {
          final all = snap.data ?? [];
          var list = all.where((i) {
            if (_query.isNotEmpty && !i.name.contains(_query) && !i.colorFamily.contains(_query)) return false;
            if (_category != null && i.category != _category) return false;
            if (_season != null && !seasonsFromJson(i.seasons).contains(_season)) return false;
            if (_favOnly && !i.isFavorite) return false;
            return true;
          }).toList();
          return Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(children: [
                Text('共 ${all.length} 件', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                FilterChip(label: const Text('只看收藏'), selected: _favOnly,
                  onSelected: (v) => setState(() => _favOnly = v)),
              ])),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(decoration: const InputDecoration(
                hintText: '搜索衣物 / 颜色…', prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(24)))),
                onChanged: (v) => setState(() => _query = v))),
            const SizedBox(height: 8),
            SingleChildScrollView(scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [
                for (final c in ['上装', '下装', '连衣裙', '外套', '鞋子', '配饰'])
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(label: Text(c), selected: _category == c,
                      onSelected: (v) => setState(() => _category = v ? c : null))),
                const SizedBox(width: 8),
                for (final s in ['春', '夏', '秋', '冬'])
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(label: Text('$s季'), selected: _season == s,
                      onSelected: (v) => setState(() => _season = v ? s : null))),
              ])),
            const SizedBox(height: 8),
            Expanded(child: list.isEmpty
                ? const Center(child: Text('衣橱还是空的,点右下角 + 拍照入库吧'))
                : MasonryGridView.count(crossAxisCount: 2, mainAxisSpacing: 8, crossAxisSpacing: 8,
                    padding: const EdgeInsets.all(12), itemCount: list.length,
                    itemBuilder: (_, i) => AspectRatio(aspectRatio: 0.78,
                      child: ClothingCard(item: list[i],
                        onFavorite: () => widget.db.toggleFavorite(list[i].id, !list[i].isFavorite))))),
          ]);
        },
      ),
    );
  }
}

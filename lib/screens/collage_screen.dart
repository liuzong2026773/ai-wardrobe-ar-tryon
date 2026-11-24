import 'dart:io';
import 'package:flutter/material.dart';
import '../data/app_database.dart';

/// 自由拼贴画布:单品缩放/旋转/图层顺序调整(拖动、双指缩放、长按置顶/置底)
class CollageScreen extends StatefulWidget {
  final AppDatabase db;
  const CollageScreen({super.key, required this.db});
  @override State<CollageScreen> createState() => _CollageScreenState();
}

class _Placed {
  ClothingItem item;
  Offset pos; // 相对画布 0..1
  double scale, rotation;
  _Placed(this.item, this.pos, this.scale, this.rotation);
}

class _CollageScreenState extends State<CollageScreen> {
  final List<_Placed> _placed = [];

  Future<void> _add() async {
    final items = await widget.db.allItems;
    if (!mounted || items.isEmpty) return;
    final picked = await showModalBottomSheet<ClothingItem>(context: context,
      builder: (_) => ListView(children: items.map((i) => ListTile(
        leading: Image.file(File(i.imagePath), width: 48, height: 48, fit: BoxFit.contain),
        title: Text(i.name), onTap: () => Navigator.pop(context, i))).toList()));
    if (picked != null) setState(() => _placed.add(_Placed(picked, const Offset(0.5, 0.5), 1.0, 0.0)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('自由拼贴'), actions: [
      IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(_placed.clear)),
    ]),
    body: Container(color: Colors.grey.shade100, child: Stack(children: [
      for (var k = 0; k < _placed.length; k++)
        Positioned(
          left: _placed[k].pos.dx * MediaQuery.of(context).size.width - 70 * _placed[k].scale,
          top: _placed[k].pos.dy * 400 - 90 * _placed[k].scale,
          child: GestureDetector(
            onPanUpdate: (d) => setState(() => _placed[k].pos += Offset(
                d.delta.dx / MediaQuery.of(context).size.width, d.delta.dy / 400)),
            onScaleUpdate: (d) => setState(() {
              _placed[k].scale = (_placed[k].scale * d.scale).clamp(0.3, 2.5);
              _placed[k].rotation += d.rotation;
            }),
            onLongPress: () => setState(() {
              final p = _placed.removeAt(k);
              _placed.add(p); // 置顶
            }),
            child: Transform.rotate(angle: _placed[k].rotation,
              child: Image.file(File(_placed[k].item.imagePath),
                width: 140 * _placed[k].scale, height: 180 * _placed[k].scale, fit: BoxFit.contain)),
          ),
        ),
      if (_placed.isEmpty) const Center(child: Text('点右下角 + 添加单品\n拖动移动,双指缩放旋转,长按置顶')),
    ])),
    floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add)),
  );
}

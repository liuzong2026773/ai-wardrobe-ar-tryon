import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../data/app_database.dart';

/// 静态全身照试穿:上传 1-2 张正面全身照(本地保存),一键把衣橱单品贴合到照片上预览。
/// 贴合方式:按照片比例把衣物图缩放到躯干区域(默认上半身居中),支持拖动/缩放微调。
class StaticTryonScreen extends StatefulWidget {
  final AppDatabase db;
  const StaticTryonScreen({super.key, required this.db});
  @override State<StaticTryonScreen> createState() => _StaticTryonScreenState();
}

class _StaticTryonScreenState extends State<StaticTryonScreen> {
  File? _body;
  File? _garment;
  Offset _pos = const Offset(0.5, 0.35);
  double _scale = 0.45;

  Future<void> _pickBody() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (x == null) return;
    setState(() => _body = File(x.path));
    // 本地保存全身照(最多 2 张,由数据库表 body_photos 管理,此处简化保存 1 张主图)
    await widget.db.insertBodyPhoto(BodyPhotosCompanion.insert(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      imagePath: x.path, isPrimary: const Value(true)));
  }

  Future<void> _pickGarment() async {
    final items = await widget.db.allItems;
    if (!mounted || items.isEmpty) return;
    final picked = await showModalBottomSheet<ClothingItem>(context: context,
      builder: (_) => ListView(children: items.map((i) => ListTile(
        leading: Image.file(File(i.imagePath), width: 48, height: 48, fit: BoxFit.contain),
        title: Text(i.name), subtitle: Text('${i.category} · ${i.colorFamily}'),
        onTap: () => Navigator.pop(context, i))).toList()));
    if (picked != null) setState(() => _garment = File(picked.imagePath));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('静态全身照试穿')),
      body: Column(children: [
        Expanded(
          child: _body == null
              ? const Center(child: Text('先上传 1 张正面全身照'))
              : LayoutBuilder(builder: (_, c) => GestureDetector(
                  onPanUpdate: (d) => setState(() => _pos += Offset(
                      d.delta.dx / c.maxWidth, d.delta.dy / c.maxHeight)),
                  onScaleUpdate: (d) => setState(() => _scale = (_scale * d.scale).clamp(0.2, 1.0)),
                  child: Stack(children: [
                    Positioned.fill(child: Image.file(_body!, fit: BoxFit.contain)),
                    if (_garment != null)
                      Positioned(
                        left: _pos.dx * c.maxWidth - 90 * _scale,
                        top: _pos.dy * c.maxHeight - 110 * _scale,
                        width: 180 * _scale, height: 220 * _scale,
                        child: Image.file(_garment!, fit: BoxFit.contain),
                      ),
                  ]),
                )),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            FilledButton.icon(onPressed: _pickBody, icon: const Icon(Icons.person),
                label: const Text('上传全身照')),
            FilledButton.icon(onPressed: _pickGarment, icon: const Icon(Icons.checkroom),
                label: const Text('选一件衣服')),
          ]),
        ),
        const Padding(padding: EdgeInsets.only(bottom: 16),
          child: Text('拖动可移动衣物,双指缩放调整大小', style: TextStyle(color: Colors.grey))),
      ]),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../data/app_database.dart';
import '../services/color_service.dart';
import '../services/segmentation_service.dart';
import '../utils/color_rules.dart';

/// 入库:相机拍照 / 相册多选(兼容电商截图) → 本地抠图 → 主色/品类初判 → 弹窗微调 → Drift 入库
class AddItemScreen extends StatefulWidget {
  final AppDatabase db;
  const AddItemScreen({super.key, required this.db});
  @override State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final _seg = SegmentationService();
  bool _busy = false;

  Future<void> _import(ImageSource src, {bool multi = false}) async {
    setState(() => _busy = true);
    try {
      final picker = ImagePicker();
      final files = multi
          ? await picker.pickMultiImage()
          : [await picker.pickImage(source: src)].whereType<XFile>().toList();
      for (final x in files) {
        final orig = File(x.path);
        final cutPath = await _seg.cutoutToWhiteBackground(orig);
        final color = await ColorService.dominantColorOf(File(cutPath));
        if (!mounted) return;
        final tuned = await _showTuneDialog(color);
        if (tuned == null) continue;
        await widget.db.insertItem(ClothingItemsCompanion.insert(
          id: const Uuid().v4(),
          name: tuned['name'] as String,
          category: tuned['category'] as String,
          seasons: seasonsToJson((tuned['seasons'] as List<String>)),
          mainColorHex: ColorService.hexOf(color),
          colorFamily: ColorRules.familyOf(color),
          imagePath: cutPath, originalPath: orig.path,
          createdAt: DateTime.now(),
        ));
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已入库')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, Object>?> _showTuneDialog(Color color) async {
    String category = '上装';
    final seasons = <String>{'春', '秋'};
    final nameCtrl = TextEditingController(text: ColorRules.familyOf(color));
    return showDialog<Map<String, Object>>(context: context, builder: (_) => AlertDialog(
      title: const Text('确认标签(可手动微调)'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [Container(width: 28, height: 28, color: color),
          const SizedBox(width: 8), Text('主色 ${ColorService.hexOf(color)} · ${ColorRules.familyOf(color)}')]),
        TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '名称')),
        DropdownButton<String>(value: category, isExpanded: true,
          items: ['上装', '下装', '连衣裙', '外套', '鞋子', '配饰']
              .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) => category = v ?? category),
        Wrap(children: ['春', '夏', '秋', '冬'].map((s) => FilterChip(
          label: Text(s), selected: seasons.contains(s),
          onSelected: (v) => setState(() => v ? seasons.add(s) : seasons.remove(s)))).toList()),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(context, {
          'name': nameCtrl.text, 'category': category, 'seasons': seasons.toList(),
        }), child: const Text('存入衣橱')),
      ],
    ));
  }

  @override void dispose() { _seg.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('添加衣物')),
    body: Center(child: _busy
        ? const Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(), SizedBox(height: 12), Text('正在本地抠图…')])
        : Column(mainAxisSize: MainAxisSize.min, children: [
            FilledButton.icon(onPressed: () => _import(ImageSource.camera),
              icon: const Icon(Icons.camera_alt), label: const Text('相机拍照')),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: () => _import(ImageSource.gallery, multi: true),
              icon: const Icon(Icons.photo_library), label: const Text('相册多选导入(支持电商截图)')),
            const SizedBox(height: 16),
            const Text('抠图、识别全部在手机本地完成,不上传', style: TextStyle(color: Colors.grey)),
          ])),
  );
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/constants/wardrobe_constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/repositories/wardrobe_repository.dart';
import '../../data/services/auto_tagger_service.dart';
import '../widgets/tag_editor_sheet.dart';

class ItemImportPage extends ConsumerStatefulWidget {
  const ItemImportPage({super.key});

  @override
  ConsumerState<ItemImportPage> createState() => _ItemImportPageState();
}

class _ItemImportPageState extends ConsumerState<ItemImportPage> {
  final ImagePicker _picker = ImagePicker();
  final List<_EditableDraft> _drafts = [];
  bool _processing = false;
  String _statusText = '';

  Future<void> _pickFromCamera() async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    if (picked == null) return;
    await _processPaths([picked.path]);
  }

  Future<void> _pickFromGallery() async {
    final pickedList = await _picker.pickMultiImage(imageQuality: 90);
    if (pickedList.isEmpty) return;
    await _processPaths(pickedList.map((e) => e.path).toList());
  }

  Future<void> _processPaths(List<String> paths) async {
    setState(() {
      _processing = true;
      _statusText = '正在本地离线抠图与识别属性 (0/${paths.length})...';
    });

    final repo = ref.read(wardrobeRepositoryProvider);
    for (int i = 0; i < paths.length; i++) {
      setState(() {
        _statusText = '正在本地离线抠图与识别属性 (${i + 1}/${paths.length})...';
      });
      final draft = await repo.processImageForImport(paths[i]);
      _drafts.add(_EditableDraft.fromProcessed(draft));
    }

    if (mounted) {
      setState(() {
        _processing = false;
        _statusText = '';
      });
    }
  }

  Future<void> _saveAll() async {
    if (_drafts.isEmpty) return;
    final repo = ref.read(wardrobeRepositoryProvider);
    for (final d in _drafts) {
      await repo.saveClothingItem(
        name: d.name,
        category: d.category,
        primaryColor: d.primaryColor,
        colorHex: d.colorHex,
        seasons: d.seasons,
        fitStyle: d.fitStyle,
        tempMin: d.tempMin,
        tempMax: d.tempMax,
        cutoutImgPath: d.cutoutWhitePath,
        originImgPath: d.originPath,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已成功入库 ${_drafts.length} 件单品')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('衣物入库与本地抠图'),
        actions: [
          if (_drafts.isNotEmpty && !_processing)
            TextButton(
              onPressed: _saveAll,
              child: Text(
                '全部入库 (${_drafts.length})',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _processing ? null : _pickFromCamera,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('拍照入库'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accentCharcoal,
                    ),
                    onPressed: _processing ? null : _pickFromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('相册多选'),
                  ),
                ),
              ],
            ),
          ),
          if (_processing)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(
                    _statusText,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: _drafts.isEmpty
                ? const Center(
                    child: Text(
                      '支持相机拍照或相册多选电商截图\n全程离线完成自动抠图、主色提取与品类打标',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _drafts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final d = _drafts[index];
                      return Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(10),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              File(d.cutoutWhitePath),
                              width: 64,
                              height: 64,
                              fit: BoxFit.contain,
                            ),
                          ),
                          title: Text(
                            d.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '${ClothingCategory.labelOf(d.category)} · ${d.primaryColor} · ${FitStyleOption.labelOf(d.fitStyle)} · 引擎: ${d.engine}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () async {
                              final edited =
                                  await showModalBottomSheet<TagEditResult>(
                                context: context,
                                isScrollControlled: true,
                                builder: (_) => TagEditorSheet(
                                  initialName: d.name,
                                  initialCategory: d.category,
                                  initialColor: d.primaryColor,
                                  initialColorHex: d.colorHex,
                                  initialSeasons: d.seasons,
                                  initialFitStyle: d.fitStyle,
                                  initialTempMin: d.tempMin,
                                  initialTempMax: d.tempMax,
                                ),
                              );
                              if (edited != null) {
                                setState(() {
                                  _drafts[index] = d.copyWith(edited);
                                });
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _EditableDraft {
  final String originPath;
  final String cutoutWhitePath;
  final String engine;
  final String name;
  final String category;
  final String primaryColor;
  final String colorHex;
  final List<String> seasons;
  final String fitStyle;
  final int tempMin;
  final int tempMax;

  const _EditableDraft({
    required this.originPath,
    required this.cutoutWhitePath,
    required this.engine,
    required this.name,
    required this.category,
    required this.primaryColor,
    required this.colorHex,
    required this.seasons,
    required this.fitStyle,
    required this.tempMin,
    required this.tempMax,
  });

  factory _EditableDraft.fromProcessed(ProcessedClothingDraft p) {
    final AutoTagResult t = p.autoTags;
    return _EditableDraft(
      originPath: p.originPath,
      cutoutWhitePath: p.cutoutWhitePath,
      engine: p.segmentationEngine,
      name: t.suggestedName,
      category: t.category,
      primaryColor: t.primaryColor,
      colorHex: t.colorHex,
      seasons: t.seasons,
      fitStyle: t.fitStyle,
      tempMin: t.tempMin,
      tempMax: t.tempMax,
    );
  }

  _EditableDraft copyWith(TagEditResult r) {
    return _EditableDraft(
      originPath: originPath,
      cutoutWhitePath: cutoutWhitePath,
      engine: engine,
      name: r.name,
      category: r.category,
      primaryColor: r.primaryColor,
      colorHex: r.colorHex,
      seasons: r.seasons,
      fitStyle: r.fitStyle,
      tempMin: r.tempMin,
      tempMax: r.tempMax,
    );
  }
}

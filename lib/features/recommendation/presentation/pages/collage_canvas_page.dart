import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../wardrobe/presentation/providers/wardrobe_provider.dart';

class _CanvasPiece {
  final ClothingItem item;
  Offset position;
  double scale;

  _CanvasPiece({
    required this.item,
    required this.position,
    this.scale = 1.0,
  });
}

class CollageCanvasPage extends ConsumerStatefulWidget {
  const CollageCanvasPage({super.key});

  @override
  ConsumerState<CollageCanvasPage> createState() => _CollageCanvasPageState();
}

class _CollageCanvasPageState extends ConsumerState<CollageCanvasPage> {
  final List<_CanvasPiece> _pieces = [];
  final TextEditingController _titleController =
      TextEditingController(text: '我的自定义穿搭');

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _saveToCalendar() async {
    if (_pieces.isEmpty) return;
    final now = DateTime.now();
    final dateStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final outfitDao = ref.read(outfitDaoProvider);

    final outfitId = await outfitDao.createOutfitWithItems(
      outfit: OutfitsCompanion.insert(
        title: _titleController.text.trim().isEmpty
            ? '自定义拼贴'
            : _titleController.text.trim(),
        sourceType: 'manual_collage',
        createdAt: now.millisecondsSinceEpoch,
      ),
      items: _pieces.asMap().entries.map((entry) {
        final p = entry.value;
        return OutfitItemsCompanion.insert(
          outfitId: 0,
          itemId: p.item.id,
          posX: Value((p.position.dx / 360.0).clamp(0.0, 1.0)),
          posY: Value((p.position.dy / 460.0).clamp(0.0, 1.0)),
          scale: Value(p.scale),
          zIndex: Value(entry.key),
        );
      }).toList(),
    );

    await outfitDao.logOutfitToCalendar(
      wearDate: dateStr,
      outfitId: outfitId,
      note: '画布自由拼贴方案',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('拼贴方案已保存至穿搭日历')),
      );
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final allItemsAsync = ref.watch(filteredWardrobeItemsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('自由拖拽拼贴画布'),
        actions: [
          TextButton(
            onPressed: _pieces.isEmpty ? null : _saveToCalendar,
            child: const Text('保存至日历', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: '输入穿搭方案名称...',
                filled: true,
                fillColor: AppTheme.cardWhite,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.dividerColor),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.dividerColor),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  children: [
                    if (_pieces.isEmpty)
                      const Center(
                        child: Text(
                          '点击下方单品添加到画布，支持自由拖拽调整位置',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                    ..._pieces.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final piece = entry.value;
                      return Positioned(
                        left: piece.position.dx,
                        top: piece.position.dy,
                        child: GestureDetector(
                          onPanUpdate: (details) {
                            setState(() {
                              piece.position += details.delta;
                            });
                          },
                          onLongPress: () {
                            setState(() => _pieces.removeAt(idx));
                          },
                          child: SizedBox(
                            width: 120 * piece.scale,
                            height: 120 * piece.scale,
                            child: Image.file(
                              File(piece.item.cutoutImgPath),
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '选择单品加入画布（长按画布单品可移除）',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
          ),
          SizedBox(
            height: 110,
            child: allItemsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (items) => ListView.separated(
                padding: const EdgeInsets.all(12),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final item = items[i];
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _pieces.add(
                          _CanvasPiece(
                            item: item,
                            position: Offset(
                              40.0 + (_pieces.length % 3) * 45.0,
                              30.0 + (_pieces.length % 3) * 55.0,
                            ),
                          ),
                        );
                      });
                    },
                    child: Container(
                      width: 78,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.dividerColor),
                      ),
                      child: Image.file(
                        File(item.cutoutImgPath),
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

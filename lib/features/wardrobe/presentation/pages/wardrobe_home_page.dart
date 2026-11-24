import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../../../../core/constants/wardrobe_constants.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../providers/wardrobe_provider.dart';
import '../widgets/clothing_card.dart';
import '../widgets/tag_editor_sheet.dart';
import 'item_import_page.dart';

class WardrobeHomePage extends ConsumerWidget {
  const WardrobeHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalCountAsync = ref.watch(wardrobeTotalCountProvider);
    final itemsAsync = ref.watch(filteredWardrobeItemsProvider);
    final filter = ref.watch(wardrobeFilterProvider);
    final filterNotifier = ref.read(wardrobeFilterProvider.notifier);

    final totalCount = totalCountAsync.valueOrNull ?? 0;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 顶部：衣橱总件数 + 关键词搜索 + 收藏筛选 + 入库按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        '衣橱 ($totalCount件)',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '仅看收藏',
                        onPressed: filterNotifier.toggleFavoritesOnly,
                        icon: Icon(
                          filter.favoritesOnly
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: filter.favoritesOnly
                              ? AppTheme.heartRed
                              : AppTheme.textSecondary,
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.accentCharcoal,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                        ),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const ItemImportPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.add_a_photo_outlined, size: 16),
                        label: const Text('入库', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    onChanged: filterNotifier.setKeyword,
                    decoration: InputDecoration(
                      hintText: '搜索单品名称、颜色或版型...',
                      hintStyle: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: AppTheme.textSecondary,
                      ),
                      filled: true,
                      fillColor: AppTheme.cardWhite,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppTheme.dividerColor),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppTheme.dividerColor),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 主体：左侧品类/季节双维度导航栏 + 右侧双列瀑布流
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DualDimensionSidebar(
                    selectedCategory: filter.category,
                    selectedSeason: filter.season,
                    onCategoryChanged: filterNotifier.setCategory,
                    onSeasonChanged: filterNotifier.setSeason,
                  ),
                  Expanded(
                    child: itemsAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (err, _) => Center(child: Text('加载失败: $err')),
                      data: (items) {
                        if (items.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.checkroom_outlined,
                                  size: 54,
                                  color: AppTheme.textSecondary
                                      .withValues(alpha: 0.5),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  '暂无符合条件的单品，点击右上角「入库」添加',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        return MasonryGridView.count(
                          padding: const EdgeInsets.fromLTRB(8, 4, 14, 24),
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          itemCount: items.length,
                          itemBuilder: (context, index) {
                            final item = items[index];
                            return ClothingCard(
                              item: item,
                              onToggleFavorite: () {
                                ref
                                    .read(wardrobeDaoProvider)
                                    .toggleFavorite(item.id, !item.isFavorite);
                              },
                              onTap: () => _openEditSheet(context, ref, item),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditSheet(
    BuildContext context,
    WidgetRef ref,
    ClothingItem item,
  ) async {
    List<String> seasons = ['spring'];
    try {
      seasons = (jsonDecode(item.seasons) as List).cast<String>();
    } catch (_) {}

    final result = await showModalBottomSheet<TagEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cardWhite,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => TagEditorSheet(
        initialName: item.name,
        initialCategory: item.category,
        initialColor: item.primaryColor,
        initialColorHex: item.colorHex,
        initialSeasons: seasons,
        initialFitStyle: item.fitStyle,
        initialTempMin: item.tempMin,
        initialTempMax: item.tempMax,
      ),
    );

    if (result != null) {
      await ref.read(wardrobeDaoProvider).updateItemTags(
            id: item.id,
            name: result.name,
            category: result.category,
            primaryColor: result.primaryColor,
            colorHex: result.colorHex,
            seasonsJson: jsonEncode(result.seasons),
            fitStyle: result.fitStyle,
            tempMin: result.tempMin,
            tempMax: result.tempMax,
          );
    }
  }
}

class _DualDimensionSidebar extends StatelessWidget {
  final String selectedCategory;
  final String selectedSeason;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onSeasonChanged;

  const _DualDimensionSidebar({
    required this.selectedCategory,
    required this.selectedSeason,
    required this.onCategoryChanged,
    required this.onSeasonChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: AppTheme.dividerColor, width: 1),
        ),
      ),
      child: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              '品类',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          ...ClothingCategory.sidebarItems.map((cat) {
            final active = selectedCategory == cat.key;
            return InkWell(
              onTap: () => onCategoryChanged(cat.key),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active ? AppTheme.accentCharcoal : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      cat.icon,
                      size: 18,
                      color: active ? Colors.white : AppTheme.textSecondary,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      cat.label,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                        color: active ? Colors.white : AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              '季节',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          ...ClothingSeason.filterItems.map((season) {
            final active = selectedSeason == season.key;
            return InkWell(
              onTap: () => onSeasonChanged(season.key),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                padding: const EdgeInsets.symmetric(vertical: 7),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? AppTheme.tagBg : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: active
                      ? Border.all(color: AppTheme.accentCharcoal, width: 1)
                      : null,
                ),
                child: Text(
                  season.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

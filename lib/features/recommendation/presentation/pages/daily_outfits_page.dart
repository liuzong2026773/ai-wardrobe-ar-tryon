import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../try_on/presentation/pages/static_try_on_page.dart';
import '../../data/outfit_engine.dart';
import '../providers/recommendation_provider.dart';
import 'collage_canvas_page.dart';
import 'outfit_calendar_page.dart';

class DailyOutfitsPage extends ConsumerWidget {
  const DailyOutfitsPage({super.key});

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weatherAsync = ref.watch(currentWeatherProvider);
    final recsAsync = ref.watch(dailyRecommendationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('今日穿搭推荐'),
        actions: [
          IconButton(
            tooltip: '穿搭日历',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OutfitCalendarPage()),
              );
            },
          ),
          IconButton(
            tooltip: '自由拼贴画布',
            icon: const Icon(Icons.dashboard_customize_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CollageCanvasPage()),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(currentWeatherProvider);
          ref.invalidate(dailyRecommendationsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 顶部天气感知卡片
            weatherAsync.when(
              loading: () => const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('正在获取本地实时天气...'),
                ),
              ),
              error: (_, __) => const SizedBox.shrink(),
              data: (w) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.wb_sunny_outlined, size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '当前天气：${w.displayLabel}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              w.isFallback
                                  ? '离线默认温度（下拉可重试定位）'
                                  : 'Open-Meteo 实时感知 · 已自动过滤适穿单品',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              '为你生成 3 套今日灵感',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            recsAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) => Text('生成失败: $err'),
              data: (list) {
                if (list.isEmpty) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        '衣橱单品不足，请先入库至少 1 件上装和 1 件下装（或连衣裙）。',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ),
                  );
                }
                return Column(
                  children: list.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final outfit = entry.value;
                    return _RecommendedOutfitCard(
                      index: idx + 1,
                      outfit: outfit,
                      onWearToday: () async {
                        final weather = weatherAsync.valueOrNull;
                        await _saveAndLogToday(
                          context,
                          ref,
                          outfit,
                          weather?.displayLabel,
                          weather?.temperatureCelsius,
                        );
                      },
                      onTryOn: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => StaticTryOnPage(
                              initialItems: outfit.items,
                            ),
                          ),
                        );
                      },
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveAndLogToday(
    BuildContext context,
    WidgetRef ref,
    RecommendedOutfit rec,
    String? weatherTag,
    double? tempCelsius,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final outfitDao = ref.read(outfitDaoProvider);

    final outfitId = await outfitDao.createOutfitWithItems(
      outfit: OutfitsCompanion.insert(
        title: rec.title,
        sourceType: 'auto_recommend',
        weatherTag: Value(weatherTag),
        createdAt: now,
      ),
      items: rec.items.asMap().entries.map((e) {
        return OutfitItemsCompanion.insert(
          outfitId: 0,
          itemId: e.value.id,
          posX: Value(0.5),
          posY: Value(0.25 + e.key * 0.25),
          zIndex: Value(e.key),
        );
      }).toList(),
    );

    await outfitDao.logOutfitToCalendar(
      wearDate: _todayString(),
      outfitId: outfitId,
      weatherSnapshot: weatherTag,
      tempCelsius: tempCelsius,
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已打卡今日穿搭，单品穿着次数 +1')),
      );
    }
  }
}

class _RecommendedOutfitCard extends StatelessWidget {
  final int index;
  final RecommendedOutfit outfit;
  final VoidCallback onWearToday;
  final VoidCallback onTryOn;

  const _RecommendedOutfitCard({
    required this.index,
    required this.outfit,
    required this.onWearToday,
    required this.onTryOn,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.accentCharcoal,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'LOOK 0$index',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    outfit.styleTag,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                Text(
                  '匹配度 ${outfit.score}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: outfit.items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final item = outfit.items[i];
                  return Container(
                    width: 90,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.dividerColor),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: Image.file(
                            File(item.cutoutImgPath),
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: onTryOn,
                  child: const Text('静态试穿'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accentCharcoal,
                  ),
                  onPressed: onWearToday,
                  child: const Text('穿这套打卡'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

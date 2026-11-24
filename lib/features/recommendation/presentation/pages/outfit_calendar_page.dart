import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/theme/app_theme.dart';

class OutfitCalendarPage extends ConsumerStatefulWidget {
  const OutfitCalendarPage({super.key});

  @override
  ConsumerState<OutfitCalendarPage> createState() => _OutfitCalendarPageState();
}

class _OutfitCalendarPageState extends ConsumerState<OutfitCalendarPage> {
  late DateTime _focusedMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month);
  }

  String get _yearMonth =>
      '${_focusedMonth.year}-${_focusedMonth.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final calendarStream =
        ref.watch(outfitDaoProvider).watchMonthCalendar(_yearMonth);

    return Scaffold(
      appBar: AppBar(title: Text('穿搭日历 ($_yearMonth)')),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() {
                    _focusedMonth =
                        DateTime(_focusedMonth.year, _focusedMonth.month - 1);
                  });
                },
              ),
              Text(
                '${_focusedMonth.year} 年 ${_focusedMonth.month} 月',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() {
                    _focusedMonth =
                        DateTime(_focusedMonth.year, _focusedMonth.month + 1);
                  });
                },
              ),
            ],
          ),
          Expanded(
            child: StreamBuilder<List<OutfitCalendarData>>(
              stream: calendarStream,
              builder: (context, snapshot) {
                final entries = snapshot.data ?? [];
                if (entries.isEmpty) {
                  return const Center(
                    child: Text(
                      '本月暂无穿搭打卡记录',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                    final entry = entries[index];
                    return FutureBuilder<OutfitWithItems?>(
                      future: ref
                          .read(outfitDaoProvider)
                          .getOutfitWithItems(entry.outfitId),
                      builder: (context, outfitSnap) {
                        final details = outfitSnap.data;
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      entry.wearDate,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                    if (entry.weatherSnapshot != null)
                                      Text(
                                        entry.weatherSnapshot!,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.textSecondary,
                                        ),
                                      ),
                                  ],
                                ),
                                if (details != null) ...[
                                  const SizedBox(height: 6),
                                  Text(details.outfit.title),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    height: 64,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: details.items.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(width: 8),
                                      itemBuilder: (_, i) => Image.file(
                                        File(details.items[i].clothing.cutoutImgPath),
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import '../data/app_database.dart';
import '../services/outfit_service.dart';
import '../services/weather_service.dart';

/// 每日推荐:Open-Meteo 气温 + 温度过滤 + 色彩规则,每天 3 套
class RecommendScreen extends StatefulWidget {
  final AppDatabase db;
  const RecommendScreen({super.key, required this.db});
  @override State<RecommendScreen> createState() => _RecommendScreenState();
}

class _RecommendScreenState extends State<RecommendScreen> {
  List<List<ClothingItem>> _outfits = [];
  double _temp = 20;
  bool _loading = true;

  @override void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final temp = await WeatherService().currentTempC();
    final outfits = await OutfitService(widget.db).dailyRecommendations(temp);
    if (mounted) setState(() { _temp = temp; _outfits = outfits; _loading = false; });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('今日穿搭')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _outfits.isEmpty
            ? const Center(child: Text('衣橱还是空的,先拍照入库几件吧'))
            : ListView.builder(padding: const EdgeInsets.all(16), itemCount: _outfits.length,
                itemBuilder: (_, i) {
                  final items = _outfits[i];
                  final rule = ['同色系', '莫兰迪', '互补色'][i % 3];
                  return Card(margin: const EdgeInsets.only(bottom: 16), child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('推荐 ${i + 1} · $rule · 今日 ${_temp.toStringAsFixed(1)}°C',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 10),
                      SizedBox(height: 110, child: ListView.builder(scrollDirection: Axis.horizontal,
                        itemCount: items.length,
                        itemBuilder: (_, j) => Padding(padding: const EdgeInsets.only(right: 8),
                          child: Column(children: [
                            Container(width: 84, height: 84, color: Colors.white,
                              child: Image.file(File(items[j].imagePath), fit: BoxFit.contain)),
                            const SizedBox(height: 4),
                            Text(items[j].name, style: const TextStyle(fontSize: 12)),
                          ])))),
                      Align(alignment: Alignment.centerRight, child: FilledButton(
                        onPressed: () async {
                          await widget.db.insertOutfit(OutfitsCompanion.insert(
                            id: DateTime.now().millisecondsSinceEpoch.toString(),
                            name: '推荐 ${i + 1} · $rule',
                            itemIds: '[${items.map((e) => '"${e.id}"').join(',')}]',
                            date: DateTime.now(), isDailyRecommendation: const Value(true)));
                          for (final it in items) { await widget.db.bumpWearCount(it.id); }
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已记录为今天的穿搭,穿搭次数 +1')));
                        },
                        child: const Text('就穿这套'))),
                    ]),
                  ));
                }),
  );
}

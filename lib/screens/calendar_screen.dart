import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../data/app_database.dart';

/// 穿搭日历打卡:点某天查看当天的穿搭记录;在“今日穿搭”页点“就穿这套”即打卡
class CalendarScreen extends StatefulWidget {
  final AppDatabase db;
  const CalendarScreen({super.key, required this.db});
  @override State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();
  List<WearLog> _logs = [];

  @override void initState() { super.initState(); _load(_selected); }

  Future<void> _load(DateTime day) async {
    final logs = await widget.db.logsOn(day);
    if (mounted) setState(() => _logs = logs);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('穿搭日历')),
    body: Column(children: [
      TableCalendar(firstDay: DateTime(2024, 1, 1), lastDay: DateTime(2030, 12, 31),
        focusedDay: _focused, selectedDayPredicate: (d) => isSameDay(d, _selected),
        onDaySelected: (s, f) { setState(() { _selected = s; _focused = f; }); _load(s); },
        calendarFormat: CalendarFormat.month),
      const Divider(),
      Expanded(child: _logs.isEmpty
          ? Center(child: Text('${_selected.month}月${_selected.day}日还没有穿搭打卡'))
          : ListView(children: _logs.map((l) => ListTile(
              leading: const Icon(Icons.checkroom),
              title: Text('穿搭 ${l.outfitId}'),
              subtitle: Text(l.note.isEmpty ? '已打卡' : l.note))).toList())),
    ]),
  );
}

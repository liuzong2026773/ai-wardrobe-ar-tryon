import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'data/app_database.dart';
import 'screens/home_screen.dart';
import 'screens/add_item_screen.dart';
import 'screens/recommend_screen.dart';
import 'screens/tryon_mirror_screen.dart';
import 'screens/static_tryon_screen.dart';
import 'screens/collage_screen.dart';
import 'screens/calendar_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = AppDatabase();
  runApp(AIWardrobeApp(db: db));
}

class AIWardrobeApp extends StatelessWidget {
  final AppDatabase db;
  const AIWardrobeApp({super.key, required this.db});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AI电子衣橱',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.pink),
    home: MainShell(db: db),
  );
}

class MainShell extends StatefulWidget {
  final AppDatabase db;
  const MainShell({super.key, required this.db});
  @override State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // 首次启动请求权限;定位可拒绝(天气会用默认值)
    Permission.camera.request();
    Permission.photos.request();
    Permission.locationWhenInUse.request();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(db: widget.db),
      RecommendScreen(db: widget.db),
      TryonMirrorScreen(db: widget.db),
      StaticTryonScreen(db: widget.db),
      CollageScreen(db: widget.db),
      CalendarScreen(db: widget.db),
    ];
    return Scaffold(
      // 不用 IndexedStack:试衣镜页一创建就会开摄像头,用 pages[_index] 保证
      // 只有切到试衣镜时才初始化相机,切走即 dispose。
      body: pages[_index],
      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => AddItemScreen(db: widget.db))),
        child: const Icon(Icons.add_a_photo)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.checkroom), label: '衣橱'),
          NavigationDestination(icon: Icon(Icons.auto_awesome), label: '今日穿搭'),
          NavigationDestination(icon: Icon(Icons.camera_front), label: '试衣镜'),
          NavigationDestination(icon: Icon(Icons.person), label: '全身试穿'),
          NavigationDestination(icon: Icon(Icons.dashboard_customize), label: '拼贴'),
          NavigationDestination(icon: Icon(Icons.calendar_month), label: '日历'),
        ],
      ),
    );
  }
}

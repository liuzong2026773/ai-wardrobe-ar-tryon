import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/recommendation/presentation/pages/daily_outfits_page.dart';
import 'features/try_on/presentation/pages/live_try_on_camera_page.dart';
import 'features/try_on/presentation/pages/static_try_on_page.dart';
import 'features/wardrobe/presentation/pages/wardrobe_home_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  static const List<Widget> _cachedPages = [
    WardrobeHomePage(),
    DailyOutfitsPage(),
    StaticTryOnPage(),
  ];

  @override
  Widget build(BuildContext context) {
    // AR 试衣镜按需挂载/卸载，切离该 Tab 时自动释放 Android 摄像头硬件资源
    return Scaffold(
      body: _currentIndex == 3
          ? const LiveTryOnCameraPage()
          : IndexedStack(
              index: _currentIndex,
              children: _cachedPages,
            ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: AppTheme.cardWhite,
        selectedIndex: _currentIndex,
        onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.checkroom_outlined),
            selectedIcon: Icon(Icons.checkroom_rounded),
            label: '衣橱',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome_rounded),
            label: '穿搭',
          ),
          NavigationDestination(
            icon: Icon(Icons.accessibility_new_outlined),
            selectedIcon: Icon(Icons.accessibility_new_rounded),
            label: '静态试穿',
          ),
          NavigationDestination(
            icon: Icon(Icons.videocam_outlined),
            selectedIcon: Icon(Icons.videocam_rounded),
            label: 'AR试衣',
          ),
        ],
      ),
    );
  }
}

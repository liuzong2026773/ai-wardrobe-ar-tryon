import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_router.dart';
import 'core/theme/app_theme.dart';

// 诊断版：启动闪退时把错误原话显示在屏幕上，而不是直接闪退消失。
final ValueNotifier<String?> fatalError = ValueNotifier<String?>(null);

void _reportFatal(Object e, [StackTrace? s]) {
  final msg = '$e${s == null ? '' : '\n$s'}';
  if (fatalError.value == null) fatalError.value = msg;
  debugPrint('FATAL: $msg');
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    _reportFatal(details.exception, details.stack);
  };
  ui.PlatformDispatcher.instance.onError = (e, s) {
    _reportFatal(e, s);
    return true;
  };
  runApp(const ProviderScope(child: AiWardrobeApp()));
}

class AiWardrobeApp extends StatelessWidget {
  const AiWardrobeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: fatalError,
      builder: (context, err, _) {
        if (err != null) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('启动出错了（请把这页截图发给开发者）',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        SelectableText(err, style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }
        return MaterialApp(
          title: 'AI 电子衣橱',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: const AppShell(),
        );
      },
    );
  }
}

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../wardrobe/presentation/providers/wardrobe_provider.dart';
import '../../domain/pose_landmarks_model.dart';
import '../../domain/try_on_engine_interface.dart';
import 'body_photo_manage_page.dart';
import 'live_try_on_camera_page.dart';

class StaticTryOnPage extends ConsumerStatefulWidget {
  final List<ClothingItem> initialItems;
  const StaticTryOnPage({super.key, this.initialItems = const []});

  @override
  ConsumerState<StaticTryOnPage> createState() => _StaticTryOnPageState();
}

class _StaticTryOnPageState extends ConsumerState<StaticTryOnPage> {
  final List<ClothingItem> _selectedGarments = [];
  Uint8List? _renderedBytes;
  bool _rendering = false;

  @override
  void initState() {
    super.initState();
    _selectedGarments.addAll(widget.initialItems);
    if (_selectedGarments.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runTryOn());
    }
  }

  Future<void> _runTryOn() async {
    final defaultPhoto =
        await ref.read(bodyPhotoDaoProvider).getDefaultBodyPhoto();
    if (defaultPhoto == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先上传 1 张正面全身照底图')),
        );
      }
      return;
    }

    setState(() => _rendering = true);
    try {
      final landmarks =
          PoseLandmarks.fromJsonString(defaultPhoto.landmarksJson);
      final engine = ref.read(tryOnEngineProvider);
      final result = await engine.renderTryOn(
        bodyFrame: TryOnFrame(
          filePath: defaultPhoto.imagePath,
          width: defaultPhoto.imageWidth,
          height: defaultPhoto.imageHeight,
        ),
        garments: _selectedGarments,
        landmarks: landmarks,
      );
      if (mounted) {
        setState(() => _renderedBytes = result);
      }
    } finally {
      if (mounted) setState(() => _rendering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bodyPhotosStream =
        ref.watch(bodyPhotoDaoProvider).watchAllBodyPhotos();
    final wardrobeAsync = ref.watch(filteredWardrobeItemsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('静态虚拟试穿'),
        actions: [
          IconButton(
            tooltip: '进入 AR 实时试衣镜',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => LiveTryOnCameraPage(
                    initialItems: _selectedGarments,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.videocam_outlined),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const BodyPhotoManagePage()),
              );
            },
            icon: const Icon(Icons.accessibility_new_outlined, size: 18),
            label: const Text('底图管理'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: StreamBuilder<List<BodyPhoto>>(
              stream: bodyPhotosStream,
              builder: (context, snapshot) {
                final photos = snapshot.data ?? [];
                final defaultPhoto = photos.where((e) => e.isDefault).firstOrNull ??
                    photos.firstOrNull;

                if (defaultPhoto == null) {
                  return Center(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const BodyPhotoManagePage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('上传正面站立全身照开始试穿'),
                    ),
                  );
                }

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.dividerColor),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _renderedBytes != null
                          ? Image.memory(_renderedBytes!, fit: BoxFit.contain)
                          : Image.file(
                              File(defaultPhoto.imagePath),
                              fit: BoxFit.contain,
                            ),
                    ),
                    if (_rendering)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'OpenCV 仿射贴合与边缘羽化中...',
                          style: TextStyle(color: Colors.white, fontSize: 13),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '已选试穿单品 (${_selectedGarments.length})',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accentCharcoal,
                  ),
                  onPressed: _selectedGarments.isEmpty || _rendering
                      ? null
                      : _runTryOn,
                  child: const Text('一键合成试穿'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 110,
            child: wardrobeAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
              data: (items) => ListView.separated(
                padding: const EdgeInsets.all(12),
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final item = items[i];
                  final selected =
                      _selectedGarments.any((e) => e.id == item.id);
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (selected) {
                          _selectedGarments.removeWhere((e) => e.id == item.id);
                        } else {
                          _selectedGarments.add(item);
                        }
                      });
                    },
                    child: Container(
                      width: 80,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected
                              ? AppTheme.accentCharcoal
                              : AppTheme.dividerColor,
                          width: selected ? 2 : 1,
                        ),
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

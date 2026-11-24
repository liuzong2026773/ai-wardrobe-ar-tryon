import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/image_storage_utils.dart';
import '../../data/static_try_on_engine.dart';
import '../../domain/try_on_engine_interface.dart';

final tryOnEngineProvider = Provider<TryOnEngineInterface>((ref) {
  final engine = StaticTryOnEngine();
  ref.onDispose(() => engine.dispose());
  return engine;
});

class BodyPhotoManagePage extends ConsumerStatefulWidget {
  const BodyPhotoManagePage({super.key});

  @override
  ConsumerState<BodyPhotoManagePage> createState() =>
      _BodyPhotoManagePageState();
}

class _BodyPhotoManagePageState extends ConsumerState<BodyPhotoManagePage> {
  final ImagePicker _picker = ImagePicker();
  bool _analyzing = false;

  Future<void> _addBodyPhoto(int currentCount) async {
    if (currentCount >= 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('最多保存 2 张全身照底图，请先删除旧图后再上传')),
      );
      return;
    }
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
    if (picked == null) return;

    setState(() => _analyzing = true);
    try {
      final bytes = await File(picked.path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      final w = decoded?.width ?? 720;
      final h = decoded?.height ?? 1280;

      final savedPath = await ImageStorageUtils.saveImageBytes(
        bytes,
        subDir: 'body_photos',
        extension: 'jpg',
      );

      final engine = ref.read(tryOnEngineProvider);
      final landmarks = await engine.detectPose(
        TryOnFrame(filePath: savedPath, width: w, height: h),
      );

      if (landmarks == null) {
        throw Exception('未识别到人体姿态');
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      await ref.read(bodyPhotoDaoProvider).insertBodyPhoto(
            BodyPhotosCompanion.insert(
              label: Value('正面全身照 ${currentCount + 1}'),
              imagePath: savedPath,
              imageWidth: w,
              imageHeight: h,
              landmarksJson: landmarks.toJsonString(),
              createdAt: now,
              updatedAt: now,
            ),
          );
    } finally {
      if (mounted) setState(() => _analyzing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final photosStream = ref.watch(bodyPhotoDaoProvider).watchAllBodyPhotos();

    return Scaffold(
      appBar: AppBar(title: const Text('全身照底图管理 (1~2张)')),
      body: StreamBuilder<List<BodyPhoto>>(
        stream: photosStream,
        builder: (context, snapshot) {
          final photos = snapshot.data ?? [];
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accentCharcoal,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  onPressed:
                      _analyzing ? null : () => _addBodyPhoto(photos.length),
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: Text(
                    _analyzing ? '正在本地识别肩/腰/臀/膝关键点...' : '上传正面站立全身照',
                  ),
                ),
              ),
              Expanded(
                child: photos.isEmpty
                    ? const Center(
                        child: Text(
                          '请上传 1~2 张光线充足的正面站立全身照\n将使用 MediaPipe Pose 离线提取骨骼关键点',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: photos.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (_, i) {
                          final photo = photos[i];
                          return Card(
                            child: ListTile(
                              contentPadding: const EdgeInsets.all(10),
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(
                                  File(photo.imagePath),
                                  width: 56,
                                  height: 80,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              title: Text(photo.label),
                              subtitle: Text(
                                photo.isDefault ? '当前默认试穿底图' : '点击设为默认',
                                style: TextStyle(
                                  color: photo.isDefault
                                      ? AppTheme.heartRed
                                      : AppTheme.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                              onTap: () => ref
                                  .read(bodyPhotoDaoProvider)
                                  .setDefaultBodyPhoto(photo.id),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () => ref
                                    .read(bodyPhotoDaoProvider)
                                    .deleteBodyPhoto(photo.id),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../../../core/utils/image_storage_utils.dart';
import 'auto_tagger_service.dart';
import 'segmentation_service.dart';

class ProcessedClothingDraft {
  final String originPath;
  final String cutoutWhitePath;
  final String cutoutTransparentPath;
  final AutoTagResult autoTags;
  final String segmentationEngine;

  const ProcessedClothingDraft({
    required this.originPath,
    required this.cutoutWhitePath,
    required this.cutoutTransparentPath,
    required this.autoTags,
    required this.segmentationEngine,
  });
}

final segmentationServiceProvider = Provider<SegmentationService>((ref) {
  final service = SegmentationService();
  ref.onDispose(() => service.dispose());
  return service;
});

final autoTaggerServiceProvider = Provider<AutoTaggerService>((ref) {
  final service = AutoTaggerService();
  ref.onDispose(() => service.dispose());
  return service;
});

final wardrobeRepositoryProvider = Provider<WardrobeRepository>((ref) {
  return WardrobeRepository(
    dao: ref.watch(wardrobeDaoProvider),
    segmentationService: ref.watch(segmentationServiceProvider),
    autoTaggerService: ref.watch(autoTaggerServiceProvider),
  );
});

class WardrobeRepository {
  final WardrobeDao dao;
  final SegmentationService segmentationService;
  final AutoTaggerService autoTaggerService;

  WardrobeRepository({
    required this.dao,
    required this.segmentationService,
    required this.autoTaggerService,
  });

  Future<ProcessedClothingDraft> processImageForImport(String sourcePath) async {
    final seg = await segmentationService.removeBackground(sourcePath);
    final tags = await autoTaggerService.analyzeClothing(seg.transparentPngBytes);

    final rawBytes = await File(sourcePath).readAsBytes();
    final savedOrigin = await ImageStorageUtils.saveImageBytes(
      rawBytes,
      subDir: 'origin',
      extension: 'jpg',
    );
    final savedWhite = await ImageStorageUtils.saveImageBytes(
      seg.whiteBgPngBytes,
      subDir: 'cutout_white',
      extension: 'png',
    );
    final savedAlpha = await ImageStorageUtils.saveImageBytes(
      seg.transparentPngBytes,
      subDir: 'cutout_alpha',
      extension: 'png',
    );

    return ProcessedClothingDraft(
      originPath: savedOrigin,
      cutoutWhitePath: savedWhite,
      cutoutTransparentPath: savedAlpha,
      autoTags: tags,
      segmentationEngine: seg.engineUsed,
    );
  }

  Future<int> saveClothingItem({
    required String name,
    required String category,
    required String primaryColor,
    required String colorHex,
    required List<String> seasons,
    required String fitStyle,
    required int tempMin,
    required int tempMax,
    required String cutoutImgPath,
    required String originImgPath,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    return dao.insertItem(
      ClothingItemsCompanion.insert(
        name: name,
        category: category,
        primaryColor: primaryColor,
        colorHex: colorHex,
        seasons: jsonEncode(seasons),
        fitStyle: Value(fitStyle),
        tempMin: Value(tempMin),
        tempMax: Value(tempMax),
        cutoutImgPath: cutoutImgPath,
        originImgPath: Value(originImgPath),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }
}

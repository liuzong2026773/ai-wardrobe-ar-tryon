import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_database.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final wardrobeDaoProvider = Provider<WardrobeDao>((ref) {
  return ref.watch(appDatabaseProvider).wardrobeDao;
});

final outfitDaoProvider = Provider<OutfitDao>((ref) {
  return ref.watch(appDatabaseProvider).outfitDao;
});

final bodyPhotoDaoProvider = Provider<BodyPhotoDao>((ref) {
  return ref.watch(appDatabaseProvider).bodyPhotoDao;
});

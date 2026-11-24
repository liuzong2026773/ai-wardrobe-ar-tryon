import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart'; // dart run build_runner build --delete-conflicting-outputs 生成

/// 表1:衣物 — 任务要求的 SQLite 结构
class ClothingItems extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get category => text()(); // 上装/下装/连衣裙/外套/鞋子/配饰
  TextColumn get seasons => text()(); // JSON: ["春","夏"]
  TextColumn get mainColorHex => text()(); // 如 #3A5A7A
  TextColumn get colorFamily => text()();
  TextColumn get imagePath => text()(); // 白底标准图本地路径
  TextColumn get originalPath => text()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  IntColumn get wearCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  @override Set<Column> get primaryKey => {id};
}

/// 表2:穿搭组合
class Outfits extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get itemIds => text()(); // JSON: ["id1","id2"]
  DateTimeColumn get date => dateTime()();
  BoolColumn get isDailyRecommendation => boolean().withDefault(const Constant(false))();
  @override Set<Column> get primaryKey => {id};
}

/// 表3:穿搭日历打卡
class WearLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get outfitId => text()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().withDefault(const Constant(''))();
}

/// 表4:静态试穿全身照(最多 2 张,本地保存)
class BodyPhotos extends Table {
  TextColumn get id => text()();
  TextColumn get imagePath => text()();
  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  @override Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [ClothingItems, Outfits, WearLogs, BodyPhotos])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  @override int get schemaVersion => 1;

  static LazyDatabase _openConnection() => LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    return NativeDatabase(File(p.join(dir.path, 'app.db')));
  });

  // --- ClothingItems DAO ---
  Future<List<ClothingItem>> get allItems =>
      select(clothingItems).get();
  Future<void> insertItem(ClothingItem item) => into(clothingItems).insert(item);
  Future<void> updateItem(ClothingItem item) =>
      (update(clothingItems)..where((t) => t.id.equals(item.id))).write(item);
  Future<void> deleteItem(String id) =>
      (delete(clothingItems)..where((t) => t.id.equals(id))).go();
  Future<void> toggleFavorite(String id, bool fav) async {
    await (update(clothingItems)..where((t) => t.id.equals(id)))
        .write(ClothingItemsCompanion(isFavorite: Value(fav)));
  }
  Future<void> bumpWearCount(String id) async {
    final row = await (select(clothingItems)..where((t) => t.id.equals(id))).getSingle();
    await (update(clothingItems)..where((t) => t.id.equals(id)))
        .write(ClothingItemsCompanion(wearCount: Value(row.wearCount + 1)));
  }
  Stream<List<ClothingItem>> watchItems() => select(clothingItems).watch();

  Future<void> insertOutfit(Outfit outfit) => into(outfits).insert(outfit);
  Future<void> logWear(String outfitId, DateTime date, {String note = ''}) =>
      into(wearLogs).insert(WearLogsCompanion(
        outfitId: Value(outfitId), date: Value(date), note: Value(note)));
  Future<List<WearLog>> logsOn(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return (select(wearLogs)
      ..where((t) => t.date.isBiggerOrEqualValue(start) & t.date.isSmallerThanValue(end))).get();
  }
  Future<void> insertBodyPhoto(BodyPhoto photo) => into(bodyPhotos).insert(photo);
  Future<List<BodyPhoto>> get bodyPhotos => select(bodyPhotos).get();
  Future<void> clearBodyPhotos() => delete(bodyPhotos).go();
}

String seasonsToJson(List<String> s) => jsonEncode(s);
List<String> seasonsFromJson(String s) =>
    (jsonDecode(s) as List).map((e) => e.toString()).toList();

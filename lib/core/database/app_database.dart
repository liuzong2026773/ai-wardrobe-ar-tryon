import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class ClothingItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get category => text()();
  TextColumn get primaryColor => text()();
  TextColumn get colorHex => text()();
  TextColumn get seasons => text()();
  TextColumn get fitStyle => text().withDefault(const Constant('regular'))();
  IntColumn get tempMin => integer().withDefault(const Constant(15))();
  IntColumn get tempMax => integer().withDefault(const Constant(25))();
  TextColumn get cutoutImgPath => text()();
  TextColumn get originImgPath => text().nullable()();
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();
  IntColumn get wearCount => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
}

class Outfits extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get sourceType => text()();
  TextColumn get weatherTag => text().nullable()();
  TextColumn get previewPath => text().nullable()();
  IntColumn get createdAt => integer()();
}

class OutfitItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get outfitId =>
      integer().references(Outfits, #id, onDelete: KeyAction.cascade)();
  IntColumn get itemId =>
      integer().references(ClothingItems, #id, onDelete: KeyAction.cascade)();
  RealColumn get posX => real().withDefault(const Constant(0.0))();
  RealColumn get posY => real().withDefault(const Constant(0.0))();
  RealColumn get scale => real().withDefault(const Constant(1.0))();
  RealColumn get rotation => real().withDefault(const Constant(0.0))();
  IntColumn get zIndex => integer().withDefault(const Constant(0))();
}

class OutfitCalendar extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get wearDate => text().unique()();
  IntColumn get outfitId =>
      integer().references(Outfits, #id, onDelete: KeyAction.cascade)();
  TextColumn get note => text().nullable()();
  TextColumn get weatherSnapshot => text().nullable()();
  RealColumn get tempCelsius => real().nullable()();
  TextColumn get occasionTag => text().withDefault(const Constant('daily'))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
}

class BodyPhotos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get label => text().withDefault(const Constant('正面全身照'))();
  TextColumn get imagePath => text()();
  IntColumn get imageWidth => integer()();
  IntColumn get imageHeight => integer()();
  TextColumn get landmarksJson => text()();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
}

class OutfitItemWithClothing {
  final OutfitItem layout;
  final ClothingItem clothing;
  OutfitItemWithClothing({required this.layout, required this.clothing});
}

class OutfitWithItems {
  final Outfit outfit;
  final List<OutfitItemWithClothing> items;
  OutfitWithItems({required this.outfit, required this.items});
}

@DriftDatabase(
  tables: [ClothingItems, Outfits, OutfitItems, OutfitCalendar, BodyPhotos],
  daos: [WardrobeDao, OutfitDao, BodyPhotoDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'ai_wardrobe_db'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

@DriftAccessor(tables: [ClothingItems])
class WardrobeDao extends DatabaseAccessor<AppDatabase>
    with _$WardrobeDaoMixin {
  WardrobeDao(super.db);

  Stream<int> watchTotalCount() {
    final countExp = clothingItems.id.count();
    final query = selectOnly(clothingItems)..addColumns([countExp]);
    return query.map((row) => row.read(countExp) ?? 0).watchSingle();
  }

  Stream<List<ClothingItem>> watchFilteredItems({
    String? category,
    String? season,
    String? keyword,
    bool favoritesOnly = false,
  }) {
    final query = select(clothingItems)
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ]);

    query.where((t) {
      Expression<bool> predicate = const Constant(true);

      if (category != null && category != 'all') {
        predicate = predicate & t.category.equals(category);
      }
      if (season != null && season != 'all') {
        predicate = predicate & t.seasons.like('%"$season"%');
      }
      if (favoritesOnly) {
        predicate = predicate & t.isFavorite.equals(true);
      }
      if (keyword != null && keyword.trim().isNotEmpty) {
        final kw = '%${keyword.trim()}%';
        predicate = predicate &
            (t.name.like(kw) |
                t.primaryColor.like(kw) |
                t.fitStyle.like(kw));
      }
      return predicate;
    });

    return query.watch();
  }

  Future<ClothingItem?> getItemById(int id) {
    return (select(clothingItems)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  Future<List<ClothingItem>> getAllItems() {
    return select(clothingItems).get();
  }

  Future<List<ClothingItem>> getItemsByTemperature(int tempCelsius) {
    return (select(clothingItems)
          ..where((t) =>
              t.tempMin.isSmallerOrEqualValue(tempCelsius) &
              t.tempMax.isBiggerOrEqualValue(tempCelsius)))
        .get();
  }

  Future<int> insertItem(ClothingItemsCompanion entry) {
    return into(clothingItems).insert(entry);
  }

  Future<bool> updateItemTags({
    required int id,
    required String name,
    required String category,
    required String primaryColor,
    required String colorHex,
    required String seasonsJson,
    required String fitStyle,
    required int tempMin,
    required int tempMax,
  }) async {
    final rows = await (update(clothingItems)..where((t) => t.id.equals(id)))
        .write(ClothingItemsCompanion(
      name: Value(name),
      category: Value(category),
      primaryColor: Value(primaryColor),
      colorHex: Value(colorHex),
      seasons: Value(seasonsJson),
      fitStyle: Value(fitStyle),
      tempMin: Value(tempMin),
      tempMax: Value(tempMax),
      updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
    ));
    return rows > 0;
  }

  Future<void> toggleFavorite(int id, bool isFavorite) async {
    await (update(clothingItems)..where((t) => t.id.equals(id))).write(
      ClothingItemsCompanion(
        isFavorite: Value(isFavorite),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> incrementWearCount(List<int> itemIds) async {
    if (itemIds.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await transaction(() async {
      for (final itemId in itemIds) {
        await customUpdate(
          'UPDATE clothing_items SET wear_count = wear_count + 1, updated_at = ? WHERE id = ?',
          variables: [Variable.withInt(now), Variable.withInt(itemId)],
          updates: {clothingItems},
        );
      }
    });
  }

  Future<int> deleteItem(int id) {
    return (delete(clothingItems)..where((t) => t.id.equals(id))).go();
  }
}

@DriftAccessor(tables: [Outfits, OutfitItems, OutfitCalendar, ClothingItems])
class OutfitDao extends DatabaseAccessor<AppDatabase> with _$OutfitDaoMixin {
  OutfitDao(super.db);

  Stream<List<Outfit>> watchOutfits({String? sourceType}) {
    final query = select(outfits)
      ..orderBy([
        (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
      ]);
    if (sourceType != null) {
      query.where((t) => t.sourceType.equals(sourceType));
    }
    return query.watch();
  }

  Future<int> createOutfitWithItems({
    required OutfitsCompanion outfit,
    required List<OutfitItemsCompanion> items,
  }) async {
    return transaction(() async {
      final outfitId = await into(outfits).insert(outfit);
      for (final item in items) {
        await into(outfitItems).insert(
          item.copyWith(outfitId: Value(outfitId)),
        );
      }
      return outfitId;
    });
  }

  Future<OutfitWithItems?> getOutfitWithItems(int outfitId) async {
    final outfit = await (select(outfits)..where((t) => t.id.equals(outfitId)))
        .getSingleOrNull();
    if (outfit == null) return null;

    final rows = await (select(outfitItems)
          ..where((t) => t.outfitId.equals(outfitId))
          ..orderBy([(t) => OrderingTerm(expression: t.zIndex)]))
        .join([
      innerJoin(clothingItems, clothingItems.id.equalsExp(outfitItems.itemId)),
    ]).get();

    final joined = rows.map((row) {
      return OutfitItemWithClothing(
        layout: row.readTable(outfitItems),
        clothing: row.readTable(clothingItems),
      );
    }).toList();

    return OutfitWithItems(outfit: outfit, items: joined);
  }

  Future<int> deleteOutfit(int id) {
    return (delete(outfits)..where((t) => t.id.equals(id))).go();
  }

  Future<void> logOutfitToCalendar({
    required String wearDate,
    required int outfitId,
    String? note,
    String? weatherSnapshot,
    double? tempCelsius,
    String occasionTag = 'daily',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await transaction(() async {
      final existing = await (select(outfitCalendar)
            ..where((t) => t.wearDate.equals(wearDate)))
          .getSingleOrNull();

      await into(outfitCalendar).insertOnConflictUpdate(
        OutfitCalendarCompanion(
          wearDate: Value(wearDate),
          outfitId: Value(outfitId),
          note: Value(note),
          weatherSnapshot: Value(weatherSnapshot),
          tempCelsius: Value(tempCelsius),
          occasionTag: Value(occasionTag),
          createdAt: Value(existing?.createdAt ?? now),
          updatedAt: Value(now),
        ),
      );

      if (existing == null || existing.outfitId != outfitId) {
        final links = await (select(outfitItems)
              ..where((t) => t.outfitId.equals(outfitId)))
            .get();
        final itemIds = links.map((e) => e.itemId).toList();
        await db.wardrobeDao.incrementWearCount(itemIds);
      }
    });
  }

  Stream<List<OutfitCalendarData>> watchMonthCalendar(String yearMonth) {
    return (select(outfitCalendar)
          ..where((t) => t.wearDate.like('$yearMonth%'))
          ..orderBy([(t) => OrderingTerm(expression: t.wearDate)]))
        .watch();
  }

  Future<int> deleteCalendarEntry(String wearDate) {
    return (delete(outfitCalendar)..where((t) => t.wearDate.equals(wearDate)))
        .go();
  }
}

@DriftAccessor(tables: [BodyPhotos])
class BodyPhotoDao extends DatabaseAccessor<AppDatabase>
    with _$BodyPhotoDaoMixin {
  BodyPhotoDao(super.db);

  Stream<List<BodyPhoto>> watchAllBodyPhotos() {
    return (select(bodyPhotos)
          ..orderBy([
            (t) => OrderingTerm(expression: t.isDefault, mode: OrderingMode.desc),
            (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
          ]))
        .watch();
  }

  Future<BodyPhoto?> getDefaultBodyPhoto() {
    return (select(bodyPhotos)
          ..where((t) => t.isDefault.equals(true))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<int> insertBodyPhoto(BodyPhotosCompanion entry) async {
    return transaction(() async {
      final countExp = bodyPhotos.id.count();
      final countRow = await (selectOnly(bodyPhotos)..addColumns([countExp]))
          .getSingle();
      final existingCount = countRow.read(countExp) ?? 0;

      final shouldDefault = existingCount == 0 ? true : entry.isDefault.value;
      if (shouldDefault && existingCount > 0) {
        await update(bodyPhotos)
            .write(const BodyPhotosCompanion(isDefault: Value(false)));
      }
      return into(bodyPhotos)
          .insert(entry.copyWith(isDefault: Value(shouldDefault)));
    });
  }

  Future<void> setDefaultBodyPhoto(int id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await transaction(() async {
      await update(bodyPhotos).write(
        BodyPhotosCompanion(
          isDefault: const Value(false),
          updatedAt: Value(now),
        ),
      );
      await (update(bodyPhotos)..where((t) => t.id.equals(id))).write(
        BodyPhotosCompanion(
          isDefault: const Value(true),
          updatedAt: Value(now),
        ),
      );
    });
  }

  Future<int> deleteBodyPhoto(int id) {
    return (delete(bodyPhotos)..where((t) => t.id.equals(id))).go();
  }
}

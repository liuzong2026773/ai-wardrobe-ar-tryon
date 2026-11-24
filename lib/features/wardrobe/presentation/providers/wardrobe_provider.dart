import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';

class WardrobeFilterState {
  final String category;
  final String season;
  final String keyword;
  final bool favoritesOnly;

  const WardrobeFilterState({
    this.category = 'all',
    this.season = 'all',
    this.keyword = '',
    this.favoritesOnly = false,
  });

  WardrobeFilterState copyWith({
    String? category,
    String? season,
    String? keyword,
    bool? favoritesOnly,
  }) {
    return WardrobeFilterState(
      category: category ?? this.category,
      season: season ?? this.season,
      keyword: keyword ?? this.keyword,
      favoritesOnly: favoritesOnly ?? this.favoritesOnly,
    );
  }
}

class WardrobeFilterNotifier extends Notifier<WardrobeFilterState> {
  @override
  WardrobeFilterState build() => const WardrobeFilterState();

  void setCategory(String category) =>
      state = state.copyWith(category: category);

  void setSeason(String season) => state = state.copyWith(season: season);

  void setKeyword(String keyword) => state = state.copyWith(keyword: keyword);

  void toggleFavoritesOnly() =>
      state = state.copyWith(favoritesOnly: !state.favoritesOnly);
}

final wardrobeFilterProvider =
    NotifierProvider<WardrobeFilterNotifier, WardrobeFilterState>(
  WardrobeFilterNotifier.new,
);

final wardrobeTotalCountProvider = StreamProvider<int>((ref) {
  return ref.watch(wardrobeDaoProvider).watchTotalCount();
});

final filteredWardrobeItemsProvider = StreamProvider<List<ClothingItem>>((ref) {
  final filter = ref.watch(wardrobeFilterProvider);
  return ref.watch(wardrobeDaoProvider).watchFilteredItems(
        category: filter.category,
        season: filter.season,
        keyword: filter.keyword,
        favoritesOnly: filter.favoritesOnly,
      );
});

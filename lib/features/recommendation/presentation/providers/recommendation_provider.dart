import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/database_provider.dart';
import '../../data/outfit_engine.dart';
import '../../data/weather_service.dart';

final weatherServiceProvider = Provider<WeatherService>((ref) => WeatherService());
final outfitEngineProvider = Provider<OutfitEngine>((ref) => OutfitEngine());

final currentWeatherProvider = FutureProvider<WeatherInfo>((ref) async {
  return ref.watch(weatherServiceProvider).fetchCurrentWeather();
});

final dailyRecommendationsProvider =
    FutureProvider<List<RecommendedOutfit>>((ref) async {
  final weather = await ref.watch(currentWeatherProvider.future);
  final allItems = await ref.watch(wardrobeDaoProvider).getAllItems();
  return ref.watch(outfitEngineProvider).generateDailyTop3(
        allItems: allItems,
        tempCelsius: weather.temperatureCelsius,
      );
});

final savedOutfitsProvider = StreamProvider<List<Outfit>>((ref) {
  return ref.watch(outfitDaoProvider).watchOutfits();
});

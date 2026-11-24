import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';

class WeatherInfo {
  final double temperatureCelsius;
  final int weatherCode;
  final String description;
  final bool isFallback;

  const WeatherInfo({
    required this.temperatureCelsius,
    required this.weatherCode,
    required this.description,
    this.isFallback = false,
  });

  String get displayLabel => '${description} ${temperatureCelsius.round()}°C';
}

/// 接入免费开源 Open-Meteo 天气接口（非商用免费、无需 API Key）
class WeatherService {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
    ),
  );

  Future<WeatherInfo> fetchCurrentWeather() async {
    try {
      final position = await _determinePosition();
      final response = await _dio.get<Map<String, dynamic>>(
        'https://api.open-meteo.com/v1/forecast',
        queryParameters: {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'current': 'temperature_2m,weather_code',
          'timezone': 'auto',
        },
      );

      final current = response.data?['current'] as Map<String, dynamic>?;
      if (current != null) {
        final temp = (current['temperature_2m'] as num).toDouble();
        final code = (current['weather_code'] as num).toInt();
        return WeatherInfo(
          temperatureCelsius: temp,
          weatherCode: code,
          description: _mapWmoCode(code),
        );
      }
    } catch (_) {
      // 离线或定位未授权时返回默认温和天气，确保推荐引擎可用
    }
    return const WeatherInfo(
      temperatureCelsius: 20.0,
      weatherCode: 2,
      description: '多云',
      isFallback: true,
    );
  }

  Future<Position> _determinePosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services disabled');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Location permission denied');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
      ),
    );
  }

  String _mapWmoCode(int code) {
    if (code == 0) return '晴';
    if (code <= 3) return '多云';
    if (code <= 48) return '雾';
    if (code <= 67) return '小雨';
    if (code <= 77) return '雪';
    if (code <= 82) return '阵雨';
    return '雷阵雨';
  }
}

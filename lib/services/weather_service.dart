import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

/// Open-Meteo:免费、免 Key、无需注册。失败/无网 → 默认 20°C,不阻塞推荐。
class WeatherService {
  Future<double> currentTempC() async {
    try {
      final perm = await Geolocator.checkPermission();
      Position? pos;
      if (perm == LocationPermission.whileInUse || perm == LocationPermission.always) {
        pos = await Geolocator.getCurrentPosition(timeLimit: const Duration(seconds: 5));
      }
      final lat = pos?.latitude ?? 31.0; // 默认成都附近,用户可在设置里改城市
      final lon = pos?.longitude ?? 104.0;
      final uri = Uri.parse(
          'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current=temperature_2m&timezone=auto');
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        return (j['current']['temperature_2m'] as num).toDouble();
      }
    } catch (_) {}
    return 20.0; // 离线默认值
  }
}

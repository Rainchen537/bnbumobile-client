import 'package:geolocator/geolocator.dart';

import '../models/assistant_models.dart';

abstract interface class AssistantLocationService {
  Future<AssistantCurrentLocationContext> currentLocation();
}

class GeolocatorAssistantLocationService implements AssistantLocationService {
  const GeolocatorAssistantLocationService();

  @override
  Future<AssistantCurrentLocationContext> currentLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const AssistantLocationException('请先在系统设置中开启定位服务。');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const AssistantLocationException('未获得定位权限，无法查看当前位置。');
    }
    if (permission == LocationPermission.deniedForever) {
      throw const AssistantLocationException('定位权限已被永久拒绝，请在系统设置中开启。');
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return AssistantCurrentLocationContext(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy < 0 ? 0 : position.accuracy,
        observedAt: position.timestamp,
      );
    } on AssistantLocationException {
      rethrow;
    } catch (_) {
      throw const AssistantLocationException('暂时无法读取当前位置，请稍后重试。');
    }
  }
}

class AssistantLocationException implements Exception {
  const AssistantLocationException(this.message);

  final String message;

  @override
  String toString() => message;
}

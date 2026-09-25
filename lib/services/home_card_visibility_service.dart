import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'network_retry.dart';

enum HomeServiceCard {
  campusDirectory('campus_directory'),
  portal('portal'),
  ispace('ispace'),
  campusLandmarks('campus_landmarks'),
  campusNavigation('campus_navigation'),
  officialMap('official_map'),
  mis('mis'),
  publicDirectory('public_directory'),
  academicCalendar('academic_calendar'),
  gradeReport('grade_report'),
  leaveApplication('leave_application'),
  checkIn('check_in'),
  ecard('ecard'),
  duoduo('duoduo');

  const HomeServiceCard(this.wireKey);

  final String wireKey;
}

class HomeCardVisibility {
  const HomeCardVisibility({required this.version, required this.cards});

  static const defaults = HomeCardVisibility(version: 0, cards: {});

  final int version;
  final Map<HomeServiceCard, bool> cards;

  bool isVisible(HomeServiceCard card) => cards[card] ?? true;

  Map<String, Object> toJson() => {
    'schema_version': 1,
    'version': version,
    'cards': {
      for (final card in HomeServiceCard.values) card.wireKey: isVisible(card),
    },
  };

  factory HomeCardVisibility.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != 1) {
      throw const FormatException('首页卡片配置版本无效。');
    }
    final version = json['version'];
    final rawCards = json['cards'];
    if (version is! int || version < 0 || rawCards is! Map) {
      throw const FormatException('首页卡片配置格式无效。');
    }
    final parsed = <HomeServiceCard, bool>{};
    for (final card in HomeServiceCard.values) {
      final value = rawCards[card.wireKey];
      if (value != null && value is! bool) {
        throw const FormatException('首页卡片可见值无效。');
      }
      parsed[card] = value is bool ? value : true;
    }
    return HomeCardVisibility(
      version: version,
      cards: Map.unmodifiable(parsed),
    );
  }
}

abstract interface class HomeCardVisibilityService {
  Future<HomeCardVisibility> load();

  void dispose();
}

/// Optional fast path for services with a trusted local snapshot. It lets the
/// home grid honor a cached disabled entry before starting a network refresh.
abstract interface class CachedHomeCardVisibilityService {
  Future<HomeCardVisibility?> loadCached();
}

class DefaultHomeCardVisibilityService implements HomeCardVisibilityService {
  const DefaultHomeCardVisibilityService();

  @override
  Future<HomeCardVisibility> load() async => HomeCardVisibility.defaults;

  @override
  void dispose() {}
}

class RemoteHomeCardVisibilityService
    implements HomeCardVisibilityService, CachedHomeCardVisibilityService {
  RemoteHomeCardVisibilityService({
    http.Client? client,
    Future<SharedPreferences> Function()? preferencesLoader,
    String? baseUrl,
  }) : _client = client ?? createAppHttpClient(),
       _ownsClient = client == null,
       _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance,
       _baseUrl = AppConfig.normalizedHttpsBaseUrl(
         baseUrl ?? AppConfig.syncServiceBaseUrl,
         settingName: 'SYNC_SERVICE_BASE_URL',
       );

  static const _cacheKey = 'home.card_visibility.v1';
  static const _maxResponseBytes = 32 * 1024;

  final http.Client _client;
  final bool _ownsClient;
  final Future<SharedPreferences> Function() _preferencesLoader;
  final String _baseUrl;
  Future<void> _cacheWriteQueue = Future<void>.value();
  int _highestTrustedVersion = -1;

  @override
  Future<HomeCardVisibility> load() async {
    late final HomeCardVisibility visibility;
    try {
      final request =
          http.Request('GET', Uri.parse('$_baseUrl/v1/public/home-cards'))
            ..followRedirects = false
            ..maxRedirects = 0
            ..headers['Accept'] = 'application/json';
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200 || response.isRedirect) {
        throw const FormatException('首页卡片配置暂不可用。');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 8),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > _maxResponseBytes) {
          throw const FormatException('首页卡片配置超过大小限制。');
        }
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('首页卡片配置格式无效。');
      }
      visibility = HomeCardVisibility.fromJson(decoded);
    } catch (_) {
      return await loadCached() ?? HomeCardVisibility.defaults;
    }
    try {
      final accepted = await _cacheVisibility(visibility);
      if (!accepted) return await loadCached() ?? HomeCardVisibility.defaults;
    } catch (_) {
      // A valid live response remains usable when local persistence fails.
    }
    return visibility;
  }

  Future<bool> _cacheVisibility(HomeCardVisibility visibility) {
    final operation = _cacheWriteQueue.then<bool>((_) async {
      final preferences = await _preferencesLoader();
      var trustedVersion = _highestTrustedVersion;
      final encoded = preferences.getString(_cacheKey);
      if (encoded != null && encoded.isNotEmpty) {
        try {
          final decoded = jsonDecode(encoded);
          if (decoded is Map<String, dynamic>) {
            final cached = HomeCardVisibility.fromJson(decoded);
            if (cached.version > trustedVersion) {
              trustedVersion = cached.version;
            }
          }
        } catch (_) {
          // A malformed old cache is replaced only by this valid response.
        }
      }
      if (visibility.version < trustedVersion) return false;
      final saved = await preferences.setString(
        _cacheKey,
        jsonEncode(visibility.toJson()),
      );
      if (!saved) throw const FormatException('首页卡片配置缓存写入失败。');
      _highestTrustedVersion = visibility.version;
      return true;
    });
    _cacheWriteQueue = operation.then<void>((_) {}, onError: (_) {});
    return operation;
  }

  @override
  Future<HomeCardVisibility?> loadCached() async {
    try {
      final preferences = await _preferencesLoader();
      final encoded = preferences.getString(_cacheKey);
      if (encoded == null || encoded.isEmpty) return null;
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return null;
      final visibility = HomeCardVisibility.fromJson(decoded);
      if (visibility.version > _highestTrustedVersion) {
        _highestTrustedVersion = visibility.version;
      }
      return visibility;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    if (_ownsClient) _client.close();
  }
}

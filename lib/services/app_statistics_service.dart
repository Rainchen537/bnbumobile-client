import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'apple_statistics_bridge.dart';
import 'network_retry.dart';
import 'usage_sync_service.dart';

const statisticsConsentVersion = 'statistics.v1';

abstract interface class StatisticsTransport {
  Future<Map<String, dynamic>> status(String username);
  Future<int> send(
    String username,
    String endpoint,
    Map<String, dynamic> batch,
  );
  void dispose();
}

class RemoteStatisticsTransport implements StatisticsTransport {
  RemoteStatisticsTransport({
    http.Client? client,
    UsageSyncStore? store,
    String? baseUrl,
  }) : _client = client ?? createAppHttpClient(),
       _store = store ?? SecureUsageSyncStore(),
       _base = AppConfig.normalizedHttpsBaseUrl(
         baseUrl ?? AppConfig.syncServiceBaseUrl,
         settingName: 'SYNC_SERVICE_BASE_URL',
       );
  final http.Client _client;
  final UsageSyncStore _store;
  final String _base;

  Future<Map<String, String>> _headers(String username) async {
    final record = await _store.loadDevice(schoolEmailForUsername(username));
    final token = record?.deviceToken;
    if (token == null) throw StateError('Device enrollment required');
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  @override
  Future<Map<String, dynamic>> status(String username) async {
    final response = await _client
        .get(
          Uri.parse('$_base/v1/devices/current/statistics'),
          headers: await _headers(username),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode != 200 || response.bodyBytes.length > 4096) {
      throw StateError('Statistics status unavailable');
    }
    final value = jsonDecode(response.body);
    if (value is! Map<String, dynamic> ||
        value['consent_version'] != statisticsConsentVersion ||
        value['app_usage_enabled'] is! bool ||
        value['notification_stats_enabled'] is! bool) {
      throw StateError('Unsupported statistics contract');
    }
    return value;
  }

  @override
  Future<int> send(
    String username,
    String endpoint,
    Map<String, dynamic> batch,
  ) async {
    if (!{'app-usage', 'notification-events'}.contains(endpoint)) {
      throw ArgumentError('endpoint');
    }
    final body = jsonEncode(batch);
    if (utf8.encode(body).length > 65536) {
      throw ArgumentError('batch too large');
    }
    final response = await _client
        .post(
          Uri.parse('$_base/v1/devices/current/$endpoint'),
          headers: await _headers(username),
          body: body,
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == 200) {
      if (response.bodyBytes.length > 4096) throw StateError('Invalid receipt');
      final result = jsonDecode(response.body);
      if (result is! Map ||
          result['accepted'] is! int ||
          result['duplicates'] is! int ||
          result['accepted'] + result['duplicates'] !=
              (batch['events'] as List).length) {
        throw StateError('Invalid statistics receipt');
      }
    }
    return response.statusCode;
  }

  @override
  void dispose() => _client.close();
}

abstract interface class StatisticsStore {
  Future<Map<String, dynamic>?> load(String owner);
  Future<void> save(String owner, Map<String, dynamic> value);
}

class PreferencesStatisticsStore implements StatisticsStore {
  @override
  Future<Map<String, dynamic>?> load(String owner) async {
    final raw = (await SharedPreferences.getInstance()).getString(
      'statistics.v1.$owner',
    );
    if (raw == null || raw.length > 4 * 1024 * 1024) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(String owner, Map<String, dynamic> value) async {
    final ok = await (await SharedPreferences.getInstance()).setString(
      'statistics.v1.$owner',
      jsonEncode(value),
    );
    if (!ok) throw StateError('Statistics persistence failed');
  }
}

/// A per-account opt-in outbox. No school credentials or notification text enters it.
class AppStatisticsService extends ChangeNotifier {
  AppStatisticsService({
    StatisticsTransport? transport,
    StatisticsStore? store,
    AppleStatisticsBridge? bridge,
    TargetPlatform? platform,
    DateTime Function()? clock,
    Future<String> Function()? versionLoader,
    String? environment,
  }) : _transport = transport ?? RemoteStatisticsTransport(),
       _store = store ?? PreferencesStatisticsStore(),
       _bridge = bridge ?? AppleStatisticsBridge(),
       platform = platform ?? defaultTargetPlatform,
       _clock = clock ?? DateTime.now,
       _versionLoader =
           versionLoader ??
           (() async {
             final p = await PackageInfo.fromPlatform();
             return '${p.version}+${p.buildNumber}';
           }),
       environment =
           environment ??
           const String.fromEnvironment(
             'STATISTICS_ENVIRONMENT',
             defaultValue: 'development',
           );

  final StatisticsTransport _transport;
  final StatisticsStore _store;
  final AppleStatisticsBridge _bridge;
  final TargetPlatform platform;
  final DateTime Function() _clock;
  final Future<String> Function() _versionLoader;
  final String environment;
  String? _username, _owner;
  Map<String, dynamic>? _state;
  int _generation = 0;
  Future<void> _mutation = Future.value();
  bool _disposed = false, _polling = false;
  bool _consentChanging = false;
  DateTime? _retryAt;
  int _failures = 0;
  String? _version;
  bool get supported =>
      !kIsWeb &&
      {TargetPlatform.iOS, TargetPlatform.macOS}.contains(platform) &&
      {'production', 'development', 'automation'}.contains(environment);
  bool get hasAccount => _state != null;
  bool get hasConsentChoice => consented || _state?['consent_choice'] is bool;
  int get consentEpoch => _generation;
  bool get consented =>
      !_consentChanging &&
      _state?['consent_version'] == statisticsConsentVersion &&
      consentAt != null;
  DateTime? get consentAt =>
      DateTime.tryParse(_state?['consented_at'] as String? ?? '');
  bool get appUsageEnabled => consented && _state?['app_usage_enabled'] == true;
  bool get remindersEnabled =>
      consented && _state?['notification_stats_enabled'] == true;
  int get pendingCount => (_state?['events'] as List?)?.length ?? 0;
  bool get needsProtocolUpdate =>
      (_state?['protocol_errors'] as List?)?.isNotEmpty ?? false;
  String? get owner => _owner;
  bool _current(int generation) =>
      !_disposed && generation == _generation && _state != null;

  Future<T> _mutate<T>(Future<T> Function() action) {
    final result = _mutation.then((_) => action());
    _mutation = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<void> setAccount(String? username) async {
    if (!supported) return;
    final normalized = username == null
        ? null
        : schoolEmailForUsername(username);
    if (normalized == _username) return;
    _username = normalized;
    _owner = normalized == null
        ? null
        : sha256.convert(utf8.encode(normalized)).toString();
    final generation = ++_generation;
    _state = null;
    _consentChanging = false;
    _retryAt = null;
    _failures = 0;
    notifyListeners();
    if (_owner == null) return;
    final key = _owner!;
    final saved = await _mutate(() => _store.load(key));
    if (_disposed || generation != _generation) return;
    _version ??= await _versionLoader();
    if (!RegExp(r'^[0-9A-Za-z.+_-]{1,32}$').hasMatch(_version!)) {
      throw StateError('Invalid statistics app version');
    }
    if (_disposed || generation != _generation) return;
    _state = _validatedState(saved);
    if (!_current(generation)) return;
    notifyListeners();
    await poll();
  }

  Future<void> setConsent(bool enabled) async {
    if (!hasAccount ||
        enabled == consented && hasConsentChoice && !_consentChanging) {
      return;
    }
    final generation = ++_generation;
    // Invalidate in-flight work synchronously, before waiting for disk I/O.
    _consentChanging = true;
    _retryAt = null;
    notifyListeners();
    try {
      await _mutate(() async {
        if (!_current(generation)) return;
        // Withdraw/re-consent starts a fresh epoch: no pre-consent events or bindings.
        final next = <String, dynamic>{
          'consent_choice': enabled,
          if (enabled) 'consent_version': statisticsConsentVersion,
          if (enabled)
            'consented_at': DateTime.fromMillisecondsSinceEpoch(
              _clock().millisecondsSinceEpoch,
              isUtc: true,
            ).toIso8601String(),
          'events': <dynamic>[],
          'seen': <String, dynamic>{},
          'bindings': <String, dynamic>{},
        };
        await _store.save(_owner!, next);
        if (!_current(generation)) return;
        _state = next;
        _consentChanging = false;
        notifyListeners();
      });
    } catch (_) {
      // Keep collection disabled on a failed withdrawal. Do not silently restore it.
      if (_current(generation)) notifyListeners();
      rethrow;
    }
    if (enabled && _current(generation)) await poll();
  }

  Map<String, dynamic> _validatedState(Map<String, dynamic>? saved) {
    if (_wasDeclined(saved)) return {'consent_choice': false};
    if (saved == null ||
        saved['consent_version'] != statisticsConsentVersion ||
        saved['consented_at'] is! String ||
        DateTime.tryParse(saved['consented_at']) == null ||
        DateTime.parse(saved['consented_at']).isAfter(_clock()) ||
        saved['events'] is! List ||
        saved['seen'] is! Map<String, dynamic> ||
        saved['bindings'] is! Map<String, dynamic>) {
      return {};
    }
    final consent = DateTime.parse(saved['consented_at']);
    final events = <Map<String, dynamic>>[];
    for (final raw in (saved['events'] as List).take(6000)) {
      if (raw is! Map ||
          raw['event_id'] is! String ||
          !_uuidPattern.hasMatch(raw['event_id']) ||
          raw['occurred_at'] is! String ||
          raw['app_version'] is! String ||
          !RegExp(r'^[0-9A-Za-z.+_-]{1,32}$').hasMatch(raw['app_version']) ||
          raw['platform'] !=
              (platform == TargetPlatform.iOS ? 'ios' : 'macos') ||
          raw['environment'] != environment) {
        continue;
      }
      final occurred = DateTime.tryParse(raw['occurred_at']);
      if (occurred == null ||
          occurred.isBefore(consent) ||
          occurred.isAfter(_clock())) {
        continue;
      }
      final reminder = raw.containsKey('notification_id');
      if (reminder &&
          (raw['notification_id'] != raw['event_id'] ||
              !{'ddl', 'schedule'}.contains(raw['kind']) ||
              raw['stage'] != 'displayed' ||
              raw['evidence'] != 'observed_notification_center')) {
        continue;
      }
      events.add({
        for (final k in [
          'event_id',
          'occurred_at',
          'platform',
          'app_version',
          'environment',
          if (reminder) ...['notification_id', 'kind', 'stage', 'evidence'],
        ])
          k: raw[k],
      });
    }
    final seen = <String, dynamic>{};
    for (final entry in (saved['seen'] as Map<String, dynamic>).entries.take(
      6000,
    )) {
      if (_uuidPattern.hasMatch(entry.key) &&
          entry.value is String &&
          DateTime.tryParse(entry.value) != null) {
        seen[entry.key] = entry.value;
      }
    }
    final bindings = <String, dynamic>{};
    for (final entry
        in (saved['bindings'] as Map<String, dynamic>).entries.take(6000)) {
      final v = entry.value;
      if (v is! Map ||
          v['notification_id'] is! String ||
          !_uuidPattern.hasMatch(v['notification_id']) ||
          v['owner'] != _owner ||
          v['environment'] != environment ||
          v['app_version'] is! String ||
          !{'ddl', 'schedule'}.contains(v['kind']) ||
          v['created_at_ms'] is! int ||
          v['trigger_at'] is! String ||
          DateTime.tryParse(v['trigger_at']) == null) {
        continue;
      }
      bindings[entry.key] = {
        for (final k in [
          'notification_id',
          'owner',
          'kind',
          'created_at_ms',
          'trigger_at',
          'environment',
          'app_version',
        ])
          k: v[k],
      };
    }
    return {
      'consent_choice': true,
      'consent_version': statisticsConsentVersion,
      'consented_at': saved['consented_at'],
      'app_usage_enabled': saved['app_usage_enabled'] == true,
      'notification_stats_enabled': saved['notification_stats_enabled'] == true,
      'events': events,
      'seen': seen,
      'bindings': bindings,
      if (saved['protocol_error_version'] == _version &&
          saved['protocol_errors'] is List)
        'protocol_errors': (saved['protocol_errors'] as List)
            .where((e) => {'app-usage', 'notification-events'}.contains(e))
            .toSet()
            .toList(),
      if (saved['protocol_error_version'] == _version)
        'protocol_error_version': _version,
    };
  }

  // Legacy withdrawal records had only empty queues; never opt them back in.
  bool _wasDeclined(Map<String, dynamic>? saved) =>
      saved?['consent_choice'] == false ||
      (saved != null &&
          saved.length == 3 &&
          saved['events'] is List &&
          (saved['events'] as List).isEmpty &&
          saved['seen'] is Map &&
          (saved['seen'] as Map).isEmpty &&
          saved['bindings'] is Map &&
          (saved['bindings'] as Map).isEmpty);

  /// Called only after the login page's current privacy notice is accepted.
  /// Stores the choice locally; no device enrollment, observation or HTTP here.
  Future<void> acceptLoginPrivacy(String username) async {
    if (!supported || _disposed || _username != null) return;
    final normalized = schoolEmailForUsername(username);
    final key = sha256.convert(utf8.encode(normalized)).toString();
    final generation = _generation;
    await _mutate(() async {
      final saved = await _store.load(key);
      if (_disposed || generation != _generation || _username != null) return;
      if (_wasDeclined(saved)) return;
      final previous = DateTime.tryParse(
        saved?['consented_at'] as String? ?? '',
      );
      if (saved?['consent_version'] == statisticsConsentVersion &&
          previous != null &&
          !previous.isAfter(_clock())) {
        return;
      }
      await _store.save(key, {
        'consent_choice': true,
        'consent_version': statisticsConsentVersion,
        'consented_at': DateTime.fromMillisecondsSinceEpoch(
          _clock().millisecondsSinceEpoch,
          isUtc: true,
        ).toIso8601String(),
        'events': <dynamic>[],
        'seen': <String, dynamic>{},
        'bindings': <String, dynamic>{},
      });
    });
  }

  Future<void> _save() async {
    if (_owner != null && _state != null) await _store.save(_owner!, _state!);
  }

  List<dynamic> get _events =>
      _state!.putIfAbsent('events', () => <dynamic>[]) as List<dynamic>;
  Map<String, dynamic> get _seen =>
      _state!.putIfAbsent('seen', () => <String, dynamic>{})
          as Map<String, dynamic>;
  Map<String, dynamic> get _bindings =>
      _state!.putIfAbsent('bindings', () => <String, dynamic>{})
          as Map<String, dynamic>;

  void _prune() {
    final cutoff = _clock().toUtc().subtract(const Duration(days: 31));
    bool expired(dynamic value) =>
        DateTime.tryParse(value is String ? value : '')?.isBefore(cutoff) ??
        true;
    _events.removeWhere((dynamic e) => e is! Map || expired(e['occurred_at']));
    _seen.removeWhere((_, value) => expired(value));
    _bindings.removeWhere(
      (_, value) => value is! Map || expired(value['trigger_at']),
    );
  }

  Map<String, dynamic> _metadata() => {
    'platform': platform == TargetPlatform.iOS ? 'ios' : 'macos',
    'app_version': _version,
    'environment': environment,
  };

  Future<void> recordEntry() {
    final generation = _generation, occurred = _clock().toUtc();
    if (!appUsageEnabled || _version == null) return Future.value();
    return _mutate(() async {
      if (!_current(generation) || !appUsageEnabled) return;
      _prune();
      if (_events.length >= 6000) {
        return; // bounded; never evict unsent records to inflate counts
      }
      _events.add({
        ..._metadata(),
        'event_id': _uuid(),
        'occurred_at': occurred.toIso8601String(),
      });
      await _save();
      if (_current(generation)) notifyListeners();
    });
  }

  /// Enrich only schedules made after explicit consent; original navigation stays local.
  Future<String?> notificationPayload({
    required String kind,
    required int id,
    required DateTime triggerAt,
    required String? payload,
  }) {
    final generation = _generation;
    if (!remindersEnabled) return Future.value(payload);
    return _mutate(() async {
      if (!_current(generation) ||
          !remindersEnabled ||
          !{'ddl', 'schedule'}.contains(kind)) {
        return payload;
      }
      _prune();
      final key = sha256
          .convert(
            utf8.encode('$kind|$id|${triggerAt.toUtc().toIso8601String()}'),
          )
          .toString();
      if (!_bindings.containsKey(key) && _bindings.length >= 6000) {
        return payload;
      }
      final binding =
          _bindings.putIfAbsent(
                key,
                () => {
                  'notification_id': _uuid(),
                  'kind': kind,
                  'owner': _owner,
                  'environment': environment,
                  'app_version': _version,
                  'created_at_ms': _clock().millisecondsSinceEpoch,
                  'trigger_at': triggerAt.toUtc().toIso8601String(),
                },
              )
              as Map;
      await _save(); // UUID must survive a crash before submitting to the OS
      if (!_current(generation) || !remindersEnabled) return payload;
      return jsonEncode({'payload': payload, 'bnbu_statistics': binding});
    });
  }

  Future<void> observeReminders() async {
    if (!remindersEnabled || _version == null) return;
    final generation = _generation, consent = consentAt!, key = _owner!;
    final observations = await _bridge.readDelivered(
      owner: key,
      consentAt: consent,
    );
    await _mutate(() async {
      if (!_current(generation) || !remindersEnabled || consentAt != consent) {
        return;
      }
      _prune();
      for (final e in observations) {
        final id = e['notification_id'];
        final occurred = DateTime.tryParse(
          e['occurred_at'] is String ? e['occurred_at'] : '',
        );
        if (id is! String ||
            !_uuidPattern.hasMatch(id) ||
            occurred == null ||
            occurred.isBefore(consent) ||
            occurred.isAfter(_clock()) ||
            occurred.isBefore(_clock().subtract(const Duration(days: 31))) ||
            !{'ddl', 'schedule'}.contains(e['kind']) ||
            e['stage'] != 'displayed' ||
            e['evidence'] != 'observed_notification_center' ||
            e['environment'] != environment ||
            e['app_version'] is! String ||
            !RegExp(r'^[0-9A-Za-z.+_-]{1,32}$').hasMatch(e['app_version']) ||
            _seen.containsKey(id) ||
            _events.length >= 6000 ||
            _seen.length >= 6000) {
          continue;
        }
        // Whitelist fields again at the Dart boundary. Never spread arbitrary native data.
        _events.add({
          ..._metadata(),
          'app_version': e['app_version'],
          'event_id': id,
          'notification_id': id,
          'kind': e['kind'],
          'stage': 'displayed',
          'evidence': 'observed_notification_center',
          'occurred_at': occurred.toUtc().toIso8601String(),
        });
        _seen[id] = occurred.toUtc().toIso8601String();
      }
      await _save();
      if (_current(generation)) notifyListeners();
    });
  }

  Future<void> poll() async {
    if (!supported ||
        !consented ||
        _polling ||
        (_retryAt?.isAfter(_clock()) ?? false)) {
      return;
    }
    _polling = true;
    final generation = _generation, username = _username!, consent = consentAt;
    try {
      try {
        final status = await _transport.status(username);
        await _mutate(() async {
          if (!_current(generation) || consentAt != consent || !consented) {
            return;
          }
          _state!['app_usage_enabled'] = status['app_usage_enabled'] == true;
          _state!['notification_stats_enabled'] =
              status['notification_stats_enabled'] == true;
          await _save();
          if (_current(generation)) notifyListeners();
        });
      } catch (_) {
        /* Offline: retain the last confirmed gates, never invent enabled. */
      }
      if (!_current(generation) || consentAt != consent || !consented) return;
      try {
        await observeReminders();
      } catch (_) {
        /* unavailable is not zero */
      }
      for (final endpoint in ['app-usage', 'notification-events']) {
        if (!_current(generation) || consentAt != consent || !consented) return;
        if (endpoint == 'app-usage' ? !appUsageEnabled : !remindersEnabled) {
          continue;
        }
        if ((_state?['protocol_errors'] as List?)?.contains(endpoint) ??
            false) {
          continue;
        }
        final batch = await _mutate(() async {
          if (!_current(generation) || consentAt != consent || !consented) {
            return <Map<String, dynamic>>[];
          }
          _prune();
          return _events
              .where(
                (e) =>
                    (e['notification_id'] != null) ==
                    (endpoint == 'notification-events'),
              )
              .take(100)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        });
        if (batch.isEmpty) continue;
        if (!_current(generation) || consentAt != consent || !consented) return;
        final status = await _transport.send(username, endpoint, {
          'consent_version': statisticsConsentVersion,
          'consented_at': consent!.toUtc().toIso8601String(),
          'events': batch,
        });
        if (!_current(generation)) return;
        if (status != 200) {
          if (status == 409 || status == 422) {
            await _mutate(() async {
              if (!_current(generation)) return;
              (_state!.putIfAbsent('protocol_errors', () => <dynamic>[])
                      as List)
                  .add(endpoint);
              _state!['protocol_error_version'] = _version;
              await _save(); // retain unacknowledged data; stop automatic poison-batch retries
              if (_current(generation)) notifyListeners();
            });
          }
          _backoff(status == 429);
          break;
        }
        _failures = 0;
        _retryAt = null;
        await _mutate(() async {
          if (!_current(generation) || consentAt != consent) return;
          final ids = batch.map((e) => e['event_id']).toSet();
          _events.removeWhere((e) => ids.contains(e['event_id']));
          await _save();
          if (_current(generation)) notifyListeners();
        });
      }
    } catch (_) {
      if (_current(generation)) _backoff(false);
      /* Do not expose tokens, payloads or remote error bodies. */
    } finally {
      _polling = false;
    }
  }

  void _backoff(bool rateLimited) {
    _failures = min(_failures + 1, 6);
    _retryAt = _clock().add(
      Duration(minutes: rateLimited ? 60 : min(60, 1 << _failures)),
    );
  }

  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  static String _uuid() {
    final r = Random.secure(), bytes = List<int>.filled(16, 0);
    for (var i = 0; i < 16; i++) {
      bytes[i] = r.nextInt(256);
    }
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final s = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _transport.dispose();
    _bridge.dispose();
    super.dispose();
  }
}

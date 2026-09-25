import 'sync/account_sync_storage.dart';
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mail_radar_models.dart';
import '../models/mail_models.dart';

const mailRadarConsentVersion = '2026-08-14-mail-radar-v2';
const mailRadarDefaultLookbackDays = 30;
const mailRadarAllowedLookbackDays = <int>{7, 30, 60};

String createStableMailRadarClientRequestId({
  required String username,
  required int mailboxUidValidity,
  required int uid,
  MailFolder folder = MailFolder.inbox,
  String targetLanguageTag = mailRadarDefaultTargetLanguageTag,
}) {
  final normalizedLanguage = normalizeMailRadarTargetLanguageTag(
    targetLanguageTag,
  );
  final digest = sha256.convert(
    utf8.encode(
      '${_mailRadarAccountId(username)}\u0000${folder == MailFolder.inbox ? '' : '${folder.name}\u0000'}$mailboxUidValidity\u0000$uid\u0000$normalizedLanguage\u0000$mailRadarAnalysisContractVersion',
    ),
  );
  final bytes = digest.bytes.take(16).toList(growable: false);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

String _mailRadarAccountId(String username) {
  final normalized = username.trim().toLowerCase();
  final separator = normalized.indexOf('@');
  return separator > 0 ? normalized.substring(0, separator) : normalized;
}

class MailRadarPreferences {
  const MailRadarPreferences({
    required this.hasConsent,
    required this.enabled,
    required this.lookbackDays,
  });

  const MailRadarPreferences.initial()
    : hasConsent = false,
      enabled = false,
      lookbackDays = mailRadarDefaultLookbackDays;

  final bool hasConsent;
  final bool enabled;
  final int lookbackDays;
}

abstract interface class MailRadarStore {
  Future<MailRadarPreferences> loadPreferences(String username);
  Future<bool> hasConsent(String username);
  Future<void> grantConsent(String username);
  Future<void> setEnabled(String username, bool enabled);
  Future<void> setLookbackDays(String username, int days);
  Future<void> revokeConsent(String username);
  Future<List<MailRadarItem>> load(String username);
  Future<void> save(String username, List<MailRadarItem> items);
}

class SharedPreferencesMailRadarStore implements MailRadarStore {
  const SharedPreferencesMailRadarStore();

  String _owner(String username) => sha256
      .convert(utf8.encode(username.trim().toLowerCase()))
      .toString()
      .substring(0, 24);

  String _consentKey(String username) =>
      'mail_radar_consent_${_owner(username)}';
  String _itemsKey(String username) => 'mail_radar_items_${_owner(username)}';
  String _enabledKey(String username) =>
      'mail_radar_enabled_${_owner(username)}';
  String _lookbackKey(String username) =>
      'mail_radar_lookback_days_${_owner(username)}';

  @override
  Future<MailRadarPreferences> loadPreferences(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final hasConsent =
        prefs.getString(_consentKey(username)) == mailRadarConsentVersion;
    final storedDays = prefs.getInt(_lookbackKey(username));
    final lookbackDays = mailRadarAllowedLookbackDays.contains(storedDays)
        ? storedDays!
        : storedDays != null && storedDays > 60
        ? 60
        : mailRadarDefaultLookbackDays;
    if (storedDays != null && storedDays != lookbackDays) {
      await prefs.setInt(_lookbackKey(username), lookbackDays);
    }
    return MailRadarPreferences(
      hasConsent: hasConsent,
      enabled: hasConsent && (prefs.getBool(_enabledKey(username)) ?? true),
      lookbackDays: lookbackDays,
    );
  }

  @override
  Future<bool> hasConsent(String username) async {
    return (await loadPreferences(username)).hasConsent;
  }

  @override
  Future<void> grantConsent(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_consentKey(username), mailRadarConsentVersion);
    await prefs.setBool(_enabledKey(username), true);
    if (!mailRadarAllowedLookbackDays.contains(
      prefs.getInt(_lookbackKey(username)),
    )) {
      await prefs.setInt(_lookbackKey(username), mailRadarDefaultLookbackDays);
    }
  }

  @override
  Future<void> setEnabled(String username, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_consentKey(username)) != mailRadarConsentVersion) {
      throw StateError('邮件雷达尚未取得当前版本同意。');
    }
    await prefs.setBool(_enabledKey(username), enabled);
  }

  @override
  Future<void> setLookbackDays(String username, int days) async {
    if (!mailRadarAllowedLookbackDays.contains(days)) {
      throw ArgumentError.value(days, 'days', '不支持的邮件雷达时间范围');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lookbackKey(username), days);
  }

  @override
  Future<void> revokeConsent(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_consentKey(username));
    await prefs.setBool(_enabledKey(username), false);
  }

  @override
  Future<List<MailRadarItem>> load(String username) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_itemsKey(username));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(MailRadarItem.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> save(String username, List<MailRadarItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _itemsKey(username),
      jsonEncode(items.map((item) => item.toJson()).toList(growable: false)),
    );
    if (!saved) throw StateError('邮件事项保存失败。');
  }
}

class MailRadarPreferenceSnapshot {
  const MailRadarPreferenceSnapshot(this.version, this.preferences);
  final int version;
  final MailRadarPreferences preferences;
}

abstract interface class MailRadarPreferenceSyncService {
  Future<MailRadarPreferenceSnapshot?> loadRadarPreferences(String username);
  Future<MailRadarPreferenceSnapshot> saveRadarPreferences(
    String username,
    int expectedVersion,
    MailRadarPreferences preferences,
  );
}

class MailRadarPreferenceConflict implements Exception {}

/// Account settings are authoritative remotely; local preferences are a cache.
/// Reads never upload an untouched default over another device's selection.
class SyncedMailRadarStore implements MailRadarStore {
  SyncedMailRadarStore({
    required this.local,
    required this.remote,
    AccountSyncStorage? journal,
  }) : _journal =
           journal ??
           (local is SharedPreferencesMailRadarStore
               ? AccountSyncStorage.shared
               : null);
  final AccountSyncStorage? _journal;
  final _records = <String, Map<String, dynamic>>{};
  String? syncError;
  bool remoteConfirmed = false;
  Future<Map<String, dynamic>?> _record(String owner) async =>
      _records[owner] ??=
          await _journal?.read(owner, 'radar-preferences') ?? {};
  Future<void> _saveRecord(String owner, Map<String, dynamic> record) async {
    await _journal?.write(owner, 'radar-preferences', record);
    _records[owner] = record;
  }

  Map<String, dynamic> _encode(MailRadarPreferences p) => {
    'consent': p.hasConsent,
    'enabled': p.enabled,
    'days': p.lookbackDays,
  };
  MailRadarPreferences _decode(Map p) => MailRadarPreferences(
    hasConsent: p['consent'] == true,
    enabled: p['consent'] == true && p['enabled'] == true,
    lookbackDays: p['days'] as int,
  );
  Future<MailRadarPreferences> _cached(String owner) async {
    final r = await _record(owner);
    return r?['value'] is Map
        ? _decode(r!['value'] as Map)
        : local.loadPreferences(owner);
  }

  Future<bool> _flushStop(String owner) async {
    final record = await _record(owner);
    if (record?['pendingOff'] != true) return true;
    try {
      final remoteValue = await remote.loadRadarPreferences(owner);
      if (remoteValue != null &&
          remoteValue.preferences.enabled &&
          remoteValue.version != record!['version']) {
        syncError = '本机已停止，其他设备更新过雷达设置，请再次选择不使用以确认账号停用。';
        return false;
      }
      final p = _decode(record!['value'] as Map);
      final saved = await remote.saveRadarPreferences(
        owner,
        remoteValue?.version ?? 0,
        p,
      );
      await _cache(owner, saved.preferences, version: saved.version);
      syncError = null;
      return true;
    } catch (_) {
      syncError = '本机已停止，账号停用等待联网同步。';
      return false;
    }
  }

  Future<void> _stop(String owner, {bool revoke = false}) => _serial(() async {
    final p = await _cached(owner);
    var version = (await _record(owner))?['version'] ?? 0;
    await _saveRecord(owner, {
      'version': version,
      'pendingOff': true,
      'value': _encode(
        MailRadarPreferences(
          hasConsent: revoke ? false : p.hasConsent,
          enabled: false,
          lookbackDays: p.lookbackDays,
        ),
      ),
    });
    // The stop intent is durable before the first network request.
    try {
      version = (await remote.loadRadarPreferences(owner))?.version ?? 0;
      final pending = Map<String, dynamic>.from((await _record(owner))!);
      pending['version'] = version;
      await _saveRecord(owner, pending);
    } catch (_) {}
    await _flushStop(owner);
  });
  final MailRadarStore local;
  final MailRadarPreferenceSyncService remote;
  Future<void> _queue = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _cache(
    String username,
    MailRadarPreferences value, {
    int? version,
  }) async {
    await _saveRecord(username, {
      'version': version ?? (await _record(username))?['version'] ?? 0,
      'pendingOff': false,
      'value': _encode(value),
    });
    if (_journal != null) return;
    if (value.hasConsent) {
      await local.grantConsent(username);
      await local.setEnabled(username, value.enabled);
    } else {
      await local.revokeConsent(username);
    }
    await local.setLookbackDays(username, value.lookbackDays);
  }

  @override
  Future<MailRadarPreferences> loadPreferences(String username) => _serial(
    () async {
      remoteConfirmed = false;
      if (!await _flushStop(username)) return _cached(username);
      try {
        var snapshot = await remote.loadRadarPreferences(username);
        if (snapshot == null) {
          final previous = await _cached(username);
          // Migrate only an explicit prior consent, using create-if-absent.
          if (!previous.hasConsent) return previous;
          try {
            snapshot = await remote.saveRadarPreferences(username, 0, previous);
          } on MailRadarPreferenceConflict {
            snapshot = await remote.loadRadarPreferences(username);
            if (snapshot == null) rethrow;
          }
        }
        await _cache(username, snapshot.preferences, version: snapshot.version);
        syncError = null;
        remoteConfirmed = true;
        return snapshot.preferences;
      } catch (_) {
        return _cached(username);
      }
    },
  );

  /// Adopt a server receipt from an explicit source-consent operation. This
  /// clears an older offline stop only after a new, affirmative user choice.
  Future<void> acceptConsentReceipt(
    String username,
    MailRadarPreferenceSnapshot snapshot,
  ) => _serial(
    () => _cache(username, snapshot.preferences, version: snapshot.version),
  );

  Future<void> _update(
    String username,
    MailRadarPreferences Function(MailRadarPreferences) change,
  ) => _serial(() async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final current = await remote.loadRadarPreferences(username);
      final value = change(
        current?.preferences ?? await local.loadPreferences(username),
      );
      try {
        final saved = await remote.saveRadarPreferences(
          username,
          current?.version ?? 0,
          value,
        );
        await _cache(username, saved.preferences, version: saved.version);
        syncError = null;
        return;
      } on MailRadarPreferenceConflict {
        if (attempt == 1) {
          throw const FormatException('邮件雷达设置已在其他设备修改，请重试。');
        }
      }
    }
  });

  @override
  Future<bool> hasConsent(String username) async =>
      (await loadPreferences(username)).hasConsent;
  @override
  Future<void> grantConsent(String username) => _update(
    username,
    (p) => MailRadarPreferences(
      hasConsent: true,
      enabled: true,
      lookbackDays: p.lookbackDays,
    ),
  );
  @override
  Future<void> setEnabled(String username, bool enabled) => !enabled
      ? _stop(username)
      : _update(username, (p) {
          if (enabled && !p.hasConsent) {
            throw const FormatException('请先同意使用邮件雷达。');
          }
          return MailRadarPreferences(
            hasConsent: p.hasConsent,
            enabled: enabled,
            lookbackDays: p.lookbackDays,
          );
        });
  @override
  Future<void> setLookbackDays(String username, int days) =>
      _update(username, (p) {
        if (!mailRadarAllowedLookbackDays.contains(days)) {
          throw const FormatException('不支持的雷达范围。');
        }
        return MailRadarPreferences(
          hasConsent: p.hasConsent,
          enabled: p.enabled,
          lookbackDays: days,
        );
      });
  Future<void> setRangeChoice(String username, int days) => days == 0
      ? _stop(username)
      : _update(username, (p) {
          if (days != 0 && !mailRadarAllowedLookbackDays.contains(days)) {
            throw const FormatException('不支持的雷达范围。');
          }
          return MailRadarPreferences(
            hasConsent: days > 0 || p.hasConsent,
            enabled: days > 0,
            lookbackDays: days > 0 ? days : p.lookbackDays,
          );
        });
  @override
  Future<void> revokeConsent(String username) => _stop(username, revoke: true);
  @override
  Future<List<MailRadarItem>> load(String username) => local.load(username);
  @override
  Future<void> save(String username, List<MailRadarItem> items) =>
      local.save(username, items);
}

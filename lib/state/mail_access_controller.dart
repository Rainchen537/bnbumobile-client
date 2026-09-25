import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/mail_login_settings.dart';
import '../models/mail_models.dart';
import '../services/mail_service.dart';

enum MailAccessStatus {
  signedOut,
  pending,
  checking,
  connected,
  needsPassword,
  skipped,
  unavailable,
}

/// Owned by the central school session. No second iSpace/SSO login or storage.
class MailAccessController extends ChangeNotifier {
  MailAccessController({required this.verify});

  final Future<void> Function(MailAccessCredentials) verify;
  Future<void> Function(MailLoginSettings)? _persist;
  String? _owner, _schoolPassword;
  MailLoginSettings _settings = const MailLoginSettings();
  MailAccessCredentials? _credentials;
  MailAccessStatus _status = MailAccessStatus.signedOut;
  Future<void>? _pending;
  DateTime? _retryAfter;
  int _generation = 0, _revision = 0;
  bool _disposed = false, _prompt = false;
  String? _error;

  MailAccessStatus get status => _status;
  MailLoginSettings get settings => _settings;
  MailAccessCredentials? get credentials => _credentials;
  int get revision => _revision;
  String? get owner => _owner;
  String? get error => _error;
  bool get shouldPrompt => _prompt;
  bool get busy => _status == MailAccessStatus.checking;

  void bind({
    required String owner,
    required String schoolPassword,
    required MailLoginSettings settings,
    required Future<void> Function(MailLoginSettings) persist,
  }) {
    reset();
    _owner = owner;
    _schoolPassword = schoolPassword;
    _settings = settings;
    _persist = persist;
    _status = settings.skipped
        ? MailAccessStatus.skipped
        : settings.needsPassword
        ? MailAccessStatus.needsPassword
        : MailAccessStatus.pending;
    _prompt = settings.needsPassword && !settings.skipped;
    _changed();
  }

  Future<void> ensureVerified({bool retry = false}) {
    if (_disposed ||
        _owner == null ||
        _status == MailAccessStatus.connected ||
        _status == MailAccessStatus.skipped ||
        _status == MailAccessStatus.needsPassword) {
      return Future.value();
    }
    if (!retry && _retryAfter?.isAfter(DateTime.now()) == true) {
      return Future.value();
    }
    return _pending ??
        _start(_settings.password ?? _schoolPassword!, automatic: true);
  }

  Future<void> connect(String password) {
    if (_disposed || _owner == null || password.isEmpty) return Future.value();
    return _pending ?? _start(password, automatic: false);
  }

  Future<void> _start(String password, {required bool automatic}) {
    final generation = _generation;
    // Publish the in-flight guard before notifying synchronous listeners.
    final completed = Completer<void>();
    _pending = completed.future;
    _status = MailAccessStatus.checking;
    _error = null;
    _changed();
    unawaited(
      _verify(password, generation, automatic: automatic).whenComplete(() {
        if (generation == _generation) _pending = null;
        completed.complete();
      }),
    );
    return completed.future;
  }

  bool _current(int generation) => !_disposed && generation == _generation;

  Future<void> _verify(
    String password,
    int generation, {
    required bool automatic,
  }) async {
    if (!_current(generation) || _owner == null) return;
    final candidate = MailAccessCredentials.fromUserId(
      userId: _owner!,
      password: password,
    );
    try {
      await verify(candidate);
      if (!_current(generation)) return;
      _settings = MailLoginSettings(password: password);
      await _save(generation);
      if (!_current(generation)) return;
      _credentials = candidate;
      _status = MailAccessStatus.connected;
      _prompt = false;
      _retryAfter = null;
    } on MailAuthenticationException {
      if (!_current(generation)) return;
      _credentials = null;
      _settings = MailLoginSettings(
        password: _settings.password,
        needsPassword: true,
      );
      _status = MailAccessStatus.needsPassword;
      _prompt = _prompt || automatic;
      _error = '邮箱验证失败，请输入邮箱密码；也请确认学校邮箱已开通。';
      await _save(generation);
    } catch (_) {
      if (!_current(generation)) return;
      // A prior successful connection may still open account-isolated caches.
      // Never promote an unverified fallback (or a rejected/skipped password).
      if (_settings.password != null &&
          !_settings.needsPassword &&
          !_settings.skipped) {
        _credentials = MailAccessCredentials.fromUserId(
          userId: _owner!,
          password: _settings.password!,
        );
      }
      _status = MailAccessStatus.unavailable;
      _retryAfter = DateTime.now().add(const Duration(minutes: 2));
      _error = '暂时无法连接邮箱，请检查网络后重试。iSpace 登录不受影响。';
    }
    if (_current(generation)) _changed();
  }

  Future<void> _save(int generation) async {
    try {
      if (_current(generation)) await _persist?.call(_settings);
    } catch (_) {
      if (_current(generation)) {
        _error = '邮箱设置仅在本次会话生效，安全存储失败，请稍后重试。';
      }
    }
  }

  Future<void> skip() async {
    if (_owner == null || _credentials != null) return;
    final generation = ++_generation;
    _pending = null;
    _credentials = null;
    _settings = MailLoginSettings(
      password: _settings.password,
      skipped: true,
      needsPassword: _settings.needsPassword,
    );
    _status = MailAccessStatus.skipped;
    _prompt = false;
    _error = null;
    await _save(generation);
    if (_current(generation)) _changed();
  }

  Future<void> reportAuthenticationFailure(MailAccessCredentials failed) async {
    final current = _credentials;
    if (current == null ||
        current.emailAddress != failed.emailAddress ||
        current.password != failed.password) {
      return;
    }
    final generation = ++_generation;
    _pending = null;
    _credentials = null;
    _settings = MailLoginSettings(
      password: _settings.password,
      needsPassword: true,
    );
    _status = MailAccessStatus.needsPassword;
    // Expiry is repaired on the mailbox page, without interrupting other pages.
    _prompt = false;
    _changed();
    await _save(generation);
  }

  void reset() {
    _generation++;
    _pending = null;
    _owner = _schoolPassword = null;
    _credentials = null;
    _persist = null;
    _settings = const MailLoginSettings();
    _status = MailAccessStatus.signedOut;
    _prompt = false;
    _error = null;
    _retryAfter = null;
    _changed();
  }

  void _changed() {
    _revision++;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    reset();
    super.dispose();
  }
}

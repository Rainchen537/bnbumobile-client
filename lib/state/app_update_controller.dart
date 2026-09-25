import 'dart:io';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_update.dart';
import '../models/app_update_policy.dart';
import '../services/app_update_policy_service.dart';
import '../services/app_update_events.dart';
import '../services/app_version_service.dart';
import '../services/android_app_update_service.dart';

typedef AppUpdateDriverFactory = Future<AppUpdateDriver> Function();

abstract class AppUpdateDriver extends ChangeNotifier {
  AppUpdateState get state;

  Future<void> initialize();

  Future<AppUpdateCheckOutcome> check();

  Future<void> openDownloadPage();

  UpdateCheckOptions get options => const UpdateCheckOptions();
  int get policyRevision => 0;
  bool get supportsEvents => false;
  Future<void> refreshCachedPolicy() async {}
  Future<void> refreshPendingPolicy() async {}
  bool get supportsInAppUpdate => false;
  bool get hasPendingUpdate => false;
  Future<void> downloadAndInstall() async {}
  Future<void> installUpdate({bool requestPermission = false}) async {}
  void cancelDownload() {}
}

class AppUpdateController extends ChangeNotifier {
  AppUpdateController({
    AppUpdateDriverFactory? driverFactory,
    DateTime Function()? now,
  }) : _driverFactory = driverFactory ?? _createDefaultDriver,
       _now = now ?? DateTime.now;

  static const automaticCheckInterval = Duration(hours: 6);

  final AppUpdateDriverFactory _driverFactory;
  final DateTime Function() _now;
  Future<AppUpdateCheckOutcome>? _checkInFlight;
  DateTime? _lastFailedCheckAt;
  String? _deferredVersion;
  DateTime? _deferredUntil;
  bool _disposed = false;
  bool _manualInitializationRequested = false;
  bool _initializationPerformedCheck = false;
  Timer? _periodicTimer;
  Timer? _eventTimer;
  int _pendingEventRevision = 0;
  bool _foreground = true;
  bool updateModalOpen = false;
  AppUpdateRelease? _requiredRelease;
  late final AppUpdateEvents _events = AppUpdateEvents((revision) {
    if (revision > (_driver?.policyRevision ?? 0)) {
      if (revision > _pendingEventRevision) _pendingEventRevision = revision;
      _eventTimer ??= Timer(
        Duration(seconds: options.eventDebounceSeconds),
        () {
          _eventTimer = null;
          unawaited(trigger(UpdateTrigger.remoteEvent));
        },
      );
    }
  });
  UpdateCheckOptions get options =>
      _driver?.options ?? const UpdateCheckOptions();
  bool get requiresUpdate =>
      _requiredRelease != null &&
      (_requiredRelease!.validUntil == null ||
          _now().isBefore(_requiredRelease!.validUntil!));
  AppUpdateRelease? get requiredRelease =>
      requiresUpdate ? _requiredRelease : null;
  bool get usesStore =>
      (state.release ?? requiredRelease)?.platform == AppUpdatePlatform.ios;

  void setForeground(bool value) {
    _foreground = value;
    _events.setEnabled(
      value &&
          (_driver?.supportsEvents ?? false) &&
          options.allows(UpdateTrigger.remoteEvent),
    );
    if (!value) {
      _eventTimer?.cancel();
      _eventTimer = null;
    }
  }

  Future<void> trigger(UpdateTrigger reason) async {
    await initialize();
    if (_disposed || !_foreground || !options.allows(reason)) return;
    if (reason == UpdateTrigger.remoteEvent) {
      if (_driver?.hasPendingUpdate ?? false) {
        await _driver?.refreshPendingPolicy();
      } else if (!isBusy) {
        await checkForUpdates(manual: false);
      }
    } else {
      await checkAutomaticallyIfDue();
    }
  }

  Future<void> _tick() async {
    if (_disposed || !_foreground) return;
    if (!isBusy && !(_driver?.hasPendingUpdate ?? false)) {
      await _driver?.refreshCachedPolicy();
    }
    if (_disposed) return;
    notifyListeners();
    if (_pendingEventRevision > (_driver?.policyRevision ?? 0) &&
        (_lastFailedCheckAt == null ||
            _now().difference(_lastFailedCheckAt!).inSeconds >=
                options.retrySeconds)) {
      await trigger(UpdateTrigger.remoteEvent);
    }
    await trigger(UpdateTrigger.periodic);
  }

  bool shouldPromptAutomatically(AppUpdateRelease release) =>
      release.mandatory ||
      _deferredVersion != release.versionLabel ||
      _deferredUntil == null ||
      !_now().isBefore(_deferredUntil!);

  Future<void> deferAutomaticPrompt(AppUpdateRelease release) async {
    if (release.mandatory) return;
    _deferredVersion = release.versionLabel;
    _deferredUntil = _now().add(
      Duration(
        seconds: options.deferSeconds > options.repeatSeconds
            ? options.deferSeconds
            : options.repeatSeconds,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_update.deferred_version', _deferredVersion!);
    await prefs.setInt(
      'app_update.deferred_until',
      _deferredUntil!.millisecondsSinceEpoch,
    );
  }

  AppUpdateDriver? _driver;
  AppUpdateState _state = const AppUpdateIdle();
  DateTime? _lastAutomaticCheckAt;
  Future<void>? _initialization;
  bool _lastCheckWasManual = false;

  AppUpdateState get state => _state;
  bool get lastCheckWasManual => _lastCheckWasManual;
  bool get isBusy =>
      state is AppUpdateChecking ||
      state is AppUpdateDownloading ||
      state is AppUpdateVerifying ||
      state is AppUpdateInstalling;
  bool get canDownloadInApp =>
      (_driver?.supportsInAppUpdate ?? false) &&
      (state.release?.canInstallInApp ?? false);

  String get statusLabel => switch (state) {
    AppUpdateChecking() => '检查中',
    AppUpdateAvailable() => '有新版本',
    AppUpdateUpToDate() => '已是最新',
    AppUpdateDownloading() => '正在下载更新',
    AppUpdateVerifying() => '正在校验安装包',
    AppUpdateInstalling() => '正在准备安装',
    AppUpdateAwaitingInstall() => '等待安装',
    AppUpdateFailed(:final retryAction) => switch (retryAction) {
      AppUpdateRetryAction.openWebsite => '打开官网失败',
      AppUpdateRetryAction.download => '更新下载失败',
      AppUpdateRetryAction.install => '安装未完成',
      AppUpdateRetryAction.check => '检查失败',
    },
    AppUpdateUnsupported() => '当前平台不支持',
    AppUpdateIdle() => '自动检查',
  };

  Future<void> initialize() {
    return _initialization ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt('app_update.last_automatic_check');
      _lastAutomaticCheckAt = last == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(last);
      _deferredVersion = prefs.getString('app_update.deferred_version');
      final deferred = prefs.getInt('app_update.deferred_until');
      _deferredUntil = deferred == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(deferred);
      final driver = await _driverFactory();
      if (_disposed) {
        driver.dispose();
        return;
      }
      _driver = driver;
      driver.addListener(_syncDriverState);
      await driver.initialize();
      _syncDriverState();
      if (driver.supportsEvents) {
        _periodicTimer = Timer.periodic(
          const Duration(seconds: 30),
          (_) => unawaited(_tick()),
        );
      }
      setForeground(_foreground);
      if (options.allows(UpdateTrigger.startup) &&
          (_lastAutomaticCheckAt == null ||
              _now().isBefore(_lastAutomaticCheckAt!) ||
              _now().difference(_lastAutomaticCheckAt!) >=
                  Duration(seconds: options.cacheSeconds))) {
        _initializationPerformedCheck = true;
        await checkForUpdates(manual: _manualInitializationRequested);
      }
    } catch (error) {
      _setState(
        AppUpdateFailed(error, retryAction: AppUpdateRetryAction.check),
      );
    }
  }

  Future<AppUpdateCheckOutcome> checkForUpdates({bool manual = true}) async {
    final initializedHere = _driver == null;
    if (initializedHere && manual) _manualInitializationRequested = true;
    if (_driver == null) {
      if (_initialization == null) {
        await initialize();
      } else {
        await _initialization;
      }
    }
    final driver = _driver;
    if (driver == null) return AppUpdateCheckOutcome.failed;
    if (driver.hasPendingUpdate) return AppUpdateCheckOutcome.available;
    if (initializedHere &&
        _initializationPerformedCheck &&
        state is! AppUpdateIdle &&
        state is! AppUpdateChecking) {
      _lastCheckWasManual = manual;
      return switch (state) {
        AppUpdateAvailable() => AppUpdateCheckOutcome.available,
        AppUpdateUpToDate() => AppUpdateCheckOutcome.upToDate,
        AppUpdateUnsupported() => AppUpdateCheckOutcome.unsupported,
        _ => AppUpdateCheckOutcome.failed,
      };
    }
    if (_checkInFlight != null) {
      _lastCheckWasManual = _lastCheckWasManual || manual;
      return _checkInFlight!;
    }
    _lastCheckWasManual = manual;
    final future = _runCheck(driver, manual);
    _checkInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_checkInFlight, future)) _checkInFlight = null;
    }
  }

  Future<AppUpdateCheckOutcome> _runCheck(
    AppUpdateDriver driver,
    bool manual,
  ) async {
    final result = await driver.check();
    if (result == AppUpdateCheckOutcome.failed) {
      _lastFailedCheckAt = _now();
    } else if (result != AppUpdateCheckOutcome.unsupported) {
      _lastFailedCheckAt = null;
      _lastAutomaticCheckAt = _now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'app_update.last_automatic_check',
        _lastAutomaticCheckAt!.millisecondsSinceEpoch,
      );
    }
    if (!_disposed) {
      _syncDriverState();
      setForeground(_foreground);
    }
    return result;
  }

  Future<void> checkAutomaticallyIfDue() async {
    await initialize();
    if (_driver?.hasPendingUpdate ?? false) return;
    if (_lastFailedCheckAt != null &&
        !_now().isBefore(_lastFailedCheckAt!) &&
        _now().difference(_lastFailedCheckAt!) <
            Duration(seconds: options.retrySeconds)) {
      return;
    }
    final lastCheck = _lastAutomaticCheckAt;
    if (lastCheck != null &&
        !_now().isBefore(lastCheck) &&
        _now().difference(lastCheck) <
            Duration(seconds: options.cacheSeconds)) {
      return;
    }
    if (isBusy) return;
    await checkForUpdates(manual: false);
  }

  Future<bool> openDownloadPage() async {
    final driver = _driver;
    if (driver == null) return false;
    await driver.openDownloadPage();
    _syncDriverState();
    return state is! AppUpdateFailed;
  }

  Future<void> downloadAndInstall() async {
    await _driver?.downloadAndInstall();
  }

  Future<void> installUpdate({bool requestPermission = false}) async {
    await _driver?.installUpdate(requestPermission: requestPermission);
  }

  void cancelDownload() => _driver?.cancelDownload();

  void _syncDriverState() {
    final driver = _driver;
    if (driver != null) _setState(driver.state);
  }

  void _setState(AppUpdateState value) {
    if (identical(_state, value)) return;
    _state = value;
    final release = value.release;
    if (release != null && release.mandatory) {
      _requiredRelease = release;
    } else if (release != null ||
        value is AppUpdateUpToDate ||
        value is AppUpdateAvailable ||
        value is AppUpdateUnsupported) {
      _requiredRelease = null;
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _periodicTimer?.cancel();
    _eventTimer?.cancel();
    _events.dispose();
    final driver = _driver;
    if (driver != null) {
      driver.removeListener(_syncDriverState);
      driver.dispose();
    }
    super.dispose();
  }
}

Future<AppUpdateDriver> _createDefaultDriver() async {
  if (kIsWeb || !kReleaseMode) return UnsupportedAppUpdateDriver();
  final platform = switch (Platform.operatingSystem) {
    'android' => AppUpdatePlatform.android,
    'ios' => AppUpdatePlatform.ios,
    'macos' => AppUpdatePlatform.macos,
    'windows' => AppUpdatePlatform.windows,
    _ => AppUpdatePlatform.unsupported,
  };
  if (platform == AppUpdatePlatform.unsupported) {
    return UnsupportedAppUpdateDriver();
  }
  if (platform == AppUpdatePlatform.android) {
    return AndroidAppUpdateDriver(service: AppUpdatePolicyService());
  }
  return WebsiteAppUpdateDriver(
    platform: platform,
    service: AppUpdatePolicyService(),
  );
}

class UnsupportedAppUpdateDriver extends AppUpdateDriver {
  @override
  AppUpdateState get state => const AppUpdateUnsupported();

  @override
  Future<AppUpdateCheckOutcome> check() async =>
      AppUpdateCheckOutcome.unsupported;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> openDownloadPage() async {}
}

class WebsiteAppUpdateDriver extends AppUpdateDriver {
  WebsiteAppUpdateDriver({
    required this.platform,
    AppVersionService? service,
    Future<PackageInfo> Function()? packageInfoLoader,
    Future<bool> Function(Uri uri)? externalLauncher,
  }) : _service = service ?? AppVersionService(),
       _ownsService = service == null,
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _externalLauncher =
           externalLauncher ??
           ((uri) => launchUrl(uri, mode: LaunchMode.externalApplication));

  final AppUpdatePlatform platform;
  final AppVersionService _service;
  final bool _ownsService;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final Future<bool> Function(Uri uri) _externalLauncher;
  AppUpdateState _state = const AppUpdateIdle();
  AppUpdateRelease? _release;
  bool _disposed = false;

  @override
  AppUpdateState get state => _state;

  @override
  UpdateCheckOptions get options => _service is AppUpdatePolicyService
      ? _service.options
      : const UpdateCheckOptions();
  @override
  int get policyRevision =>
      _service is AppUpdatePolicyService ? _service.revision : 0;
  @override
  bool get supportsEvents => _service is AppUpdatePolicyService;
  @override
  Future<void> initialize() async {
    await refreshCachedPolicy();
  }

  @override
  Future<void> refreshCachedPolicy() async {
    if (_service is! AppUpdatePolicyService) return;
    final info = await _packageInfoLoader();
    final build = installedUpdateBuild(info.buildNumber);
    if (build == null) return;
    final restored = await _service.restore(platform, build);
    if (restored != null) {
      _release = restored;
      _setState(AppUpdateAvailable(restored));
    } else if (_release?.validUntil != null) {
      _release = null;
      _setState(const AppUpdateUpToDate());
    }
  }

  @override
  Future<AppUpdateCheckOutcome> check() async {
    final previous = _release;
    _setState(const AppUpdateChecking());
    try {
      final packageInfo = await _packageInfoLoader();
      final installedBuildNumber = installedUpdateBuild(
        packageInfo.buildNumber,
      );
      if (installedBuildNumber == null) {
        _setState(const AppUpdateUnsupported());
        return AppUpdateCheckOutcome.unsupported;
      }
      final release = await _service.check(
        platform: platform,
        installedBuildNumber: installedBuildNumber,
      );
      if (release == null) {
        _release = null;
        _setState(const AppUpdateUpToDate());
        return AppUpdateCheckOutcome.upToDate;
      }
      _release = release;
      _setState(AppUpdateAvailable(release));
      return AppUpdateCheckOutcome.available;
    } catch (error) {
      _setState(
        AppUpdateFailed(
          error,
          value: previous,
          retryAction: AppUpdateRetryAction.check,
        ),
      );
      return AppUpdateCheckOutcome.failed;
    }
  }

  @override
  Future<void> openDownloadPage() async {
    final release = _release;
    if (release == null) return;
    try {
      if (!await _externalLauncher(release.downloadUri)) {
        throw StateError('系统浏览器无法打开官网下载地址。');
      }
      _setState(AppUpdateAvailable(release));
    } catch (error) {
      _setState(
        AppUpdateFailed(
          error,
          value: release,
          retryAction: AppUpdateRetryAction.openWebsite,
        ),
      );
    }
  }

  void _setState(AppUpdateState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsService || _service is AppUpdatePolicyService) _service.dispose();
    super.dispose();
  }
}

class AndroidAppUpdateDriver extends WebsiteAppUpdateDriver {
  AndroidAppUpdateDriver({
    super.service,
    super.packageInfoLoader,
    super.externalLauncher,
    AndroidAppUpdateService? updateService,
  }) : _updateService = updateService ?? AndroidAppUpdateService(),
       super(platform: AppUpdatePlatform.android);

  final AndroidAppUpdateService _updateService;
  File? _downloadedFile;
  bool _operationInProgress = false;

  @override
  bool get supportsInAppUpdate => true;

  @override
  bool get hasPendingUpdate => _operationInProgress || _downloadedFile != null;

  @override
  Future<AppUpdateCheckOutcome> check() async =>
      hasPendingUpdate ? AppUpdateCheckOutcome.available : super.check();

  @override
  Future<void> refreshPendingPolicy() async {
    if (_service is! AppUpdatePolicyService) return;
    final old = _release;
    if (old == null) return;
    try {
      final info = await _packageInfoLoader();
      final build = installedUpdateBuild(info.buildNumber);
      if (build == null) return;
      final next = await _service.check(
        platform: platform,
        installedBuildNumber: build,
      );
      if (_disposed || !identical(old, _release)) return;
      final sameArtifact =
          next != null &&
          next.buildNumber == old.buildNumber &&
          next.artifactSha256 == old.artifactSha256;
      _release = next;
      if (!sameArtifact) {
        _updateService.cancelDownload();
        _downloadedFile = null;
        _setState(
          next == null ? const AppUpdateUpToDate() : AppUpdateAvailable(next),
        );
      } else {
        _setState(switch (_state) {
          AppUpdateDownloading(:final receivedBytes) => AppUpdateDownloading(
            next,
            receivedBytes,
          ),
          AppUpdateVerifying() => AppUpdateVerifying(next),
          AppUpdateInstalling() => AppUpdateInstalling(next),
          AppUpdateAwaitingInstall(:final permissionRequired) =>
            AppUpdateAwaitingInstall(
              next,
              permissionRequired: permissionRequired,
            ),
          _ => AppUpdateAvailable(next),
        });
      }
    } catch (_) {
      /* Keep the verified pending artifact and last valid gate. */
    }
  }

  @override
  Future<void> downloadAndInstall() async {
    final release = _release;
    if (_operationInProgress || release == null || !release.canInstallInApp) {
      return;
    }
    _operationInProgress = true;
    _setState(AppUpdateDownloading(release, 0));
    var lastProgress = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      final downloaded = await _updateService.download(
        release,
        onProgress: (received) {
          final now = DateTime.now();
          if (received == 0 ||
              received == release.artifactSize ||
              now.difference(lastProgress).inMilliseconds >= 150) {
            lastProgress = now;
            if (_release?.buildNumber == release.buildNumber &&
                _release?.artifactSha256 == release.artifactSha256) {
              _setState(AppUpdateDownloading(_release!, received));
            }
          }
        },
        onVerifying: () {
          if (_release?.buildNumber == release.buildNumber &&
              _release?.artifactSha256 == release.artifactSha256) {
            _setState(AppUpdateVerifying(_release!));
          }
        },
      );
      if (!_sameArtifact(release)) return;
      _downloadedFile = downloaded;
    } on AndroidUpdateCancelled {
      if (_release?.buildNumber != release.buildNumber ||
          _release?.artifactSha256 != release.artifactSha256) {
        return;
      }
      _setState(AppUpdateAvailable(_release!));
      return;
    } catch (error) {
      if (!_sameArtifact(release)) return;
      _setState(
        AppUpdateFailed(
          error,
          value: _release!,
          retryAction: AppUpdateRetryAction.download,
        ),
      );
      return;
    } finally {
      _operationInProgress = false;
    }
    if (!_disposed &&
        _release?.buildNumber == release.buildNumber &&
        _release?.artifactSha256 == release.artifactSha256) {
      await installUpdate();
    }
  }

  @override
  Future<void> installUpdate({bool requestPermission = false}) async {
    final release = _release;
    final file = _downloadedFile;
    if (_operationInProgress || release == null || file == null || _disposed) {
      return;
    }
    _operationInProgress = true;
    _setState(AppUpdateInstalling(release));
    try {
      if (requestPermission &&
          !await _updateService.requestInstallPermission()) {
        if (_sameArtifact(release)) {
          _setState(
            AppUpdateAwaitingInstall(_release!, permissionRequired: true),
          );
        }
        return;
      }
      if (_disposed || !_sameArtifact(release)) return;
      final outcome = await _updateService.install(file, release);
      if (!_sameArtifact(release)) return;
      // Opening the system installer is not evidence of a completed update.
      _setState(
        AppUpdateAwaitingInstall(
          _release!,
          permissionRequired:
              outcome == AndroidInstallResult.permissionRequired,
        ),
      );
    } catch (error) {
      if (!_sameArtifact(release)) return;
      final invalid =
          error is PlatformException && error.code == 'invalid_update';
      if (invalid) {
        _downloadedFile = null;
        try {
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
      _setState(
        AppUpdateFailed(
          error,
          value: _release!,
          retryAction: invalid
              ? AppUpdateRetryAction.download
              : AppUpdateRetryAction.install,
        ),
      );
    } finally {
      _operationInProgress = false;
    }
  }

  bool _sameArtifact(AppUpdateRelease release) =>
      _release?.buildNumber == release.buildNumber &&
      _release?.artifactSha256 == release.artifactSha256;

  @override
  void cancelDownload() => _updateService.cancelDownload();

  @override
  void dispose() {
    _updateService.dispose();
    super.dispose();
  }
}

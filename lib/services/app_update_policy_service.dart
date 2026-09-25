import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_update.dart';
import '../models/app_update_policy.dart';
import 'app_version_service.dart';

const updateBuildOverride = String.fromEnvironment('BNBU_BUILD_NUMBER');
int? installedUpdateBuild(String nativeBuild) => int.tryParse(
  updateBuildOverride.isEmpty ? nativeBuild : updateBuildOverride,
);
const productVersionOverride = String.fromEnvironment('BNBU_PRODUCT_VERSION');
const distributionChannelOverride = String.fromEnvironment(
  'BNBU_UPDATE_CHANNEL',
);
String displayedProductVersion(String nativeVersion) =>
    productVersionOverride.isEmpty ? nativeVersion : productVersionOverride;

class AppUpdatePolicyService extends AppVersionService {
  AppUpdatePolicyService({
    http.Client? client,
    Future<PackageInfo> Function()? packageInfoLoader,
    DateTime Function()? now,
    String? systemVersion,
  }) : _http = client ?? http.Client(),
       _infoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _now = now ?? DateTime.now,
       _systemVersion = systemVersion;
  static final policyUri = Uri.parse(
    'https://api.bnbu.yunwai.cloud/v1/public/app-updates',
  );
  final http.Client _http;
  final Future<PackageInfo> Function() _infoLoader;
  final DateTime Function() _now;
  final String? _systemVersion;
  UpdateCheckOptions options = const UpdateCheckOptions();
  int revision = 0;
  bool get hasV2 => revision > 0;
  String get _cacheKey => 'app_update.policy.v2';

  Future<Map<String, dynamic>> _read(http.StreamedResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      if (bytes.length + chunk.length > 256 * 1024) {
        throw const FormatException('Policy too large');
      }
      bytes.addAll(chunk);
    }
    return jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
  }

  Future<AppUpdateRelease?> restore(
    AppUpdatePlatform platform,
    int build,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null) return null;
    try {
      final stored = jsonDecode(raw) as Map<String, dynamic>;
      final received = DateTime.parse(stored['received'] as String);
      if (_now().isBefore(received)) return null;
      final decision = await _evaluate(
        stored['policy'] as Map<String, dynamic>,
        platform,
        build,
        received,
        prefs,
      );
      if (_now().difference(received).inSeconds >=
          decision.options.validSeconds) {
        return null;
      }
      options = decision.options;
      revision = decision.revision;
      return decision.release;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AppUpdateRelease?> check({
    required AppUpdatePlatform platform,
    required int installedBuildNumber,
  }) async {
    final request = http.Request('GET', policyUri)..followRedirects = false;
    final response = await _http
        .send(request)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode == 404) {
      await response.stream.drain<void>();
      // An unavailable v2 endpoint cannot erase an already active v2 requirement.
      if (hasV2) throw StateError('Update policy unavailable');
      if (platform == AppUpdatePlatform.ios) return null;
      return super.check(
        platform: platform,
        installedBuildNumber: installedBuildNumber,
      );
    }
    if (response.statusCode != 200 ||
        (response.request?.url ?? policyUri) != policyUri) {
      await response.stream.listen(null).cancel();
      throw StateError('Update policy unavailable');
    }
    final json = await _read(response);
    final prefs = await SharedPreferences.getInstance();
    final received = _now();
    final decision = await _evaluate(
      json,
      platform,
      installedBuildNumber,
      received,
      prefs,
    );
    if (decision.revision < revision) {
      throw const FormatException('Stale update policy');
    }
    options = decision.options;
    revision = decision.revision;
    await prefs.setString(
      _cacheKey,
      jsonEncode({'received': received.toIso8601String(), 'policy': json}),
    );
    // Before a platform has been configured, retain its existing v1 discovery.
    final hasLane = (json['policies'] as List).any(
      (p) => p['platform'] == platform.name,
    );
    if (!hasLane && revision == 0 && platform != AppUpdatePlatform.ios) {
      return super.check(
        platform: platform,
        installedBuildNumber: installedBuildNumber,
      );
    }
    return decision.release;
  }

  Future<UpdateDecision> _evaluate(
    Map<String, dynamic> json,
    AppUpdatePlatform platform,
    int build,
    DateTime received,
    SharedPreferences prefs,
  ) async {
    if (json['schema_version'] != 2 ||
        json['revision'] is! int ||
        (json['revision'] as int) < 0) {
      throw const FormatException('Unknown update protocol');
    }
    final info = await _infoLoader();
    var channel = distributionChannelOverride.isNotEmpty
        ? distributionChannelOverride
        : platform == AppUpdatePlatform.ios
        ? 'app_store'
        : 'website';
    if (platform == AppUpdatePlatform.ios &&
        Platform.isIOS &&
        distributionChannelOverride.isEmpty) {
      try {
        channel =
            await const MethodChannel(
              'bnbu/update_environment',
            ).invokeMethod<String>('distributionChannel') ??
            'local';
      } catch (_) {
        channel = 'local';
      }
    }
    final policies = (json['policies'] as List)
        .where((p) => p['platform'] == platform.name && p['channel'] == channel)
        .toList();
    if (policies.isEmpty) {
      return UpdateDecision(revision: json['revision'] as int);
    }
    if (policies.length != 1) throw const FormatException('Duplicate policy');
    final policy = policies.single as Map<String, dynamic>;
    final settings = UpdateCheckOptions.fromJson(policy);
    final revision = json['revision'] as int;
    final empty = UpdateDecision(options: settings, revision: revision);
    final releases = (json['releases'] as List)
        .where((r) => r['id'] == policy['target_id'])
        .toList();
    if (releases.length != 1) {
      throw const FormatException('Missing update target');
    }
    final r = releases.single as Map<String, dynamic>;
    if (r['platform'] != platform.name ||
        r['channel'] != channel ||
        r['bundle_id'] != info.packageName) {
      return empty;
    }
    final version = ProductVersion.parse(r['version'] as String);
    final current = ProductVersion.parse(displayedProductVersion(info.version));
    final native = ProductVersion.parse(r['native_version'] as String);
    final targetBuild = r['build_number'] as int;
    if (targetBuild <= 0 || targetBuild > 2100000000) {
      throw const FormatException('Invalid build');
    }
    // App Store only exposes the public native version, not a selectable build.
    final newer = platform == AppUpdatePlatform.ios && channel == 'app_store'
        ? native.compareTo(ProductVersion.parse(info.version)) > 0
        : platform == AppUpdatePlatform.android
        ? targetBuild > build
        : version.compareTo(current) > 0 ||
              (version.compareTo(current) == 0 && targetBuild > build);
    if (!newer) return empty;
    final minOs = r['minimum_os'] as String? ?? '';
    if (minOs.isNotEmpty) {
      final actual = _systemVersion ?? await _readSystemVersion();
      if (actual == null || _compareOs(actual, minOs) < 0) return empty;
    }
    final minimumVersion = policy['minimum_supported_version'] as String;
    final minimumBuild = policy['minimum_supported_build'] as int;
    final required =
        (minimumVersion.isNotEmpty &&
            current.compareTo(ProductVersion.parse(minimumVersion)) < 0) ||
        build < minimumBuild;
    final generated = DateTime.parse(json['generated_at'] as String);
    if (!generated.isUtc) {
      throw const FormatException('Policy time must be UTC');
    }
    final effectiveNow = generated.add(_now().difference(received));
    final after = policy['mandatory_after'] as String;
    final mandatory =
        required &&
        (after.isEmpty || !effectiveNow.isBefore(DateTime.parse(after)));
    var bucket = prefs.getInt('app_update.rollout_bucket');
    bucket ??= Random.secure().nextInt(100);
    await prefs.setInt('app_update.rollout_bucket', bucket);
    // Required versions bypass optional rollout even before the deadline.
    if (!required && bucket >= (policy['rollout_percent'] as int)) return empty;
    final uri = Uri.parse(r['download_url'] as String);
    final trusted = platform == AppUpdatePlatform.ios
        ? uri.scheme == 'https' &&
              !uri.hasPort &&
              uri.userInfo.isEmpty &&
              !uri.hasQuery &&
              !uri.hasFragment &&
              (channel == 'app_store'
                  ? uri.host == 'apps.apple.com' &&
                        RegExp(
                          r'^/(?:[a-z]{2}/)?app/(?:[^/]+/)?id\d+$',
                        ).hasMatch(uri.path)
                  : channel == 'testflight' &&
                        uri.host == 'testflight.apple.com' &&
                        RegExp(r'^/join/[A-Za-z0-9]+$').hasMatch(uri.path))
        : isTrustedUpdateDownloadUri(uri, platform);
    if (!trusted) throw const FormatException('Untrusted update URL');
    final notes = List<String>.from(r['release_notes'] as List);
    final english = List<String>.from(r['release_notes_en'] as List);
    if ([...notes, ...english].any((n) => n.length > 200) ||
        notes.length > 8 ||
        english.length > 8) {
      throw const FormatException('Invalid release notes');
    }
    final release = AppUpdateRelease(
      platform: platform,
      version: version.toString(),
      nativeVersion: r['native_version'] as String,
      buildNumber: targetBuild,
      downloadUri: uri,
      releaseNotes: notes,
      releaseNotesEn: english,
      artifactSha256: platform == AppUpdatePlatform.android
          ? r['sha256'] as String
          : null,
      artifactSize: platform == AppUpdatePlatform.android
          ? r['size_bytes'] as int
          : null,
      mandatory: mandatory,
      policyRevision: revision,
      mandatoryReason: policy['mandatory_reason'] as String,
      mandatoryReasonEn: policy['mandatory_reason_en'] as String,
      mandatoryAfter: required && after.isNotEmpty
          ? received.add(DateTime.parse(after).difference(generated))
          : null,
      validUntil: received.add(Duration(seconds: settings.validSeconds)),
    );
    if (platform == AppUpdatePlatform.android && !release.canInstallInApp) {
      throw const FormatException('Invalid APK integrity metadata');
    }
    return UpdateDecision(
      release: release,
      options: settings,
      revision: revision,
    );
  }

  static Future<String?> _readSystemVersion() async {
    // Android's Dart OS value is a Linux kernel; never treat that as Android OS.
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        return await const MethodChannel(
          'bnbu/update_environment',
        ).invokeMethod<String>('systemVersion');
      } catch (_) {
        return null;
      }
    }
    return RegExp(
      r'(\d+\.\d+(?:\.\d+)?)',
    ).firstMatch(Platform.operatingSystemVersion)?.group(1);
  }

  static int _compareOs(String a, String b) {
    final x = a.split('.').map(int.parse).toList(),
        y = b.split('.').map(int.parse).toList();
    for (var i = 0; i < max(x.length, y.length); i++) {
      final c = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
      if (c != 0) return c;
    }
    return 0;
  }

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }
}

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'network_retry.dart';

class DeveloperContact {
  const DeveloperContact({
    required this.label,
    required this.kind,
    required this.value,
  });
  final String label;
  final String kind;
  final String value;

  Uri? get target => switch (kind) {
    'website' => Uri.parse(value),
    'email' => Uri(scheme: 'mailto', path: value),
    _ => null,
  };

  factory DeveloperContact.fromJson(Map<String, dynamic> json) {
    final label = json['label'];
    final kind = json['kind'];
    final value = json['value'];
    if (label is! String ||
        label.trim().isEmpty ||
        label.length > 80 ||
        value is! String ||
        value.trim().isEmpty ||
        value.length > 500 ||
        !['website', 'email', 'text'].contains(kind) ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(label + value)) {
      throw const FormatException('Invalid developer contact');
    }
    if (kind == 'website') {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.port != 443) {
        throw const FormatException('Invalid contact website');
      }
    }
    if (kind == 'email' &&
        !RegExp(
          r'^[A-Za-z0-9.!#$%&\x27*+/=^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\.[A-Za-z]{2,}$',
        ).hasMatch(value)) {
      throw const FormatException('Invalid contact email');
    }
    return DeveloperContact(label: label, kind: kind as String, value: value);
  }
  Map<String, dynamic> toJson() => {
    'label': label,
    'kind': kind,
    'value': value,
  };
}

class AppAboutConfiguration {
  const AppAboutConfiguration({this.version = 0, this.contacts = const []});
  final int version;
  final List<DeveloperContact> contacts;

  factory AppAboutConfiguration.fromJson(Map<String, dynamic> json) {
    final version = json['version'];
    final contacts = json['contacts'];
    if (json['schema_version'] != 1 ||
        version is! int ||
        version < 0 ||
        contacts is! List ||
        contacts.length > 12) {
      throw const FormatException('Invalid about configuration');
    }
    return AppAboutConfiguration(
      version: version,
      contacts: List.unmodifiable(
        contacts.map(
          (item) =>
              DeveloperContact.fromJson(Map<String, dynamic>.from(item as Map)),
        ),
      ),
    );
  }
  Map<String, dynamic> toJson() => {
    'schema_version': 1,
    'version': version,
    'contacts': contacts.map((item) => item.toJson()).toList(),
  };
}

/// Public, source-scoped configuration. No school or device credentials.
class AppAboutService {
  AppAboutService({
    http.Client? client,
    String? baseUrl,
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _client = client ?? createAppHttpClient(),
       _ownsClient = client == null,
       _preferences = preferencesLoader ?? SharedPreferences.getInstance,
       _base = AppConfig.normalizedHttpsBaseUrl(
         baseUrl ?? AppConfig.syncServiceBaseUrl,
         settingName: 'SYNC_SERVICE_BASE_URL',
       );
  final http.Client _client;
  final bool _ownsClient;
  final String _base;
  final Future<SharedPreferences> Function() _preferences;
  String get _key => 'app.about.v1.$_base';
  static const _limit = 32 * 1024;

  Future<AppAboutConfiguration> loadCached() async {
    try {
      final raw = (await _preferences()).getString(_key);
      if (raw == null || utf8.encode(raw).length > _limit) {
        return const AppAboutConfiguration();
      }
      return AppAboutConfiguration.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return const AppAboutConfiguration();
    }
  }

  Future<AppAboutConfiguration> refresh(AppAboutConfiguration current) async {
    try {
      final next = await _fetch().timeout(const Duration(seconds: 8));
      if (next.version < current.version) return current;
      await (await _preferences()).setString(_key, jsonEncode(next.toJson()));
      return next;
    } catch (_) {
      return current;
    }
  }

  Future<AppAboutConfiguration> _fetch() async {
    final request = http.Request('GET', Uri.parse('$_base/v1/public/app-about'))
      ..followRedirects = false
      ..headers['Accept'] = 'application/json';
    final response = await _client.send(request);
    if (response.statusCode != 200 ||
        response.isRedirect ||
        (response.contentLength ?? 0) > _limit) {
      throw const FormatException('About configuration unavailable');
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 8),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > _limit) {
        throw const FormatException('About configuration too large');
      }
    }
    return AppAboutConfiguration.fromJson(
      jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
    );
  }

  void dispose() {
    if (_ownsClient) _client.close();
  }
}

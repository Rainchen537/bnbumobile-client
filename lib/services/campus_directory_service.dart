import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../models/campus_directory.dart';
import 'network_retry.dart';
import 'public_directory_cache.dart';

abstract interface class CampusDirectoryService {
  Future<List<CampusDirectoryOrganization>> loadOrganizations();

  Future<OfficialTeacherPage> loadTeachers({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
  });

  void dispose();
}

abstract interface class VersionedCampusDirectoryService {
  Future<OfficialTeacherPage> loadTeacherSnapshot({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
    String snapshotVersion = '',
    bool refresh = false,
  });
}

class RemoteCampusDirectoryService
    implements CampusDirectoryService, VersionedCampusDirectoryService {
  RemoteCampusDirectoryService({
    http.Client? client,
    AssetBundle? assetBundle,
    String? baseUrl,
    Future<void> Function(Duration delay)? retryDelay,
  }) : _client = client ?? PublicDirectoryCache.shared,
       _ownsClient = client == null,
       _assetBundle = assetBundle ?? rootBundle,
       _baseUrl = AppConfig.normalizedHttpsBaseUrl(
         baseUrl ?? AppConfig.syncServiceBaseUrl,
         settingName: 'SYNC_SERVICE_BASE_URL',
       ),
       _retryDelay = retryDelay ?? Future<void>.delayed;

  final http.Client _client;
  final bool _ownsClient;
  final AssetBundle _assetBundle;
  final String _baseUrl;
  final Future<void> Function(Duration delay) _retryDelay;

  Future<List<OfficialTeacherProfile>> loadContactIndex() async {
    final response = await _client
        .get(
          Uri.parse('$_baseUrl/v1/directory/public/contacts'),
          headers: const {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 ||
        response.bodyBytes.length > 4 * 1024 * 1024) {
      throw const CampusDirectoryException('联系人目录暂时不可用。');
    }
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return (decoded['items'] as List)
        .map(
          (item) => OfficialTeacherProfile.fromJson(
            (item as Map).cast<String, dynamic>(),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<CampusDirectoryOrganization>> loadOrganizations() {
    return _loadOrganizationsOnce();
  }

  Future<List<CampusDirectoryOrganization>> _loadOrganizationsOnce() async {
    http.Response? response;
    try {
      response = await retryNetworkOperation<http.Response>(
        () => _client
            .get(
              Uri.parse('$_baseUrl/v1/directory/public/organizations'),
              headers: const {'Accept': 'application/json'},
            )
            .timeout(const Duration(seconds: 12)),
        shouldRetryResult: (response) =>
            isTransientHttpStatus(response.statusCode),
        delay: _retryDelay,
      );
    } on Object {
      // The packaged snapshot keeps the directory available offline.
    }
    if (response?.statusCode == 200) {
      try {
        final remote = jsonDecode(response!.body);
        if (remote is Map<String, dynamic> &&
            remote['organizations'] is List &&
            (remote['organizations'] as List).whereType<Map>().any(
              (o) => !o.containsKey('sources'),
            )) {
          // Older servers do not know the explicitly sourced supplemental
          // records bundled with this client. Preserve their existing fields.
          final bundled =
              jsonDecode(
                    await _assetBundle.loadString(
                      'assets/catalog/bnbu_directory.json',
                    ),
                  )
                  as Map;
          final byId = {
            for (final o in (bundled['organizations'] as List).whereType<Map>())
              o['id']: o,
          };
          for (final org
              in (remote['organizations'] as List).whereType<Map>()) {
            final extra = byId[org['id']];
            if (org.containsKey('sources') || extra == null) continue;
            final existing = (org['staff'] as List? ?? const [])
                .whereType<Map>();
            final ownsRoster = const {
              'college-gs',
              'research-ias',
            }.contains(org['id']);
            final supplements = (extra['staff'] as List? ?? const [])
                .whereType<Map>()
                .where(
                  (p) =>
                      !ownsRoster &&
                      (p['source_urls'] as List? ?? const []).isNotEmpty &&
                      !existing.any(
                        (old) =>
                            old['name'] == p['name'] &&
                            old['email'] == p['email'],
                      ),
                );
            org['staff'] = [
              ...(org['staff'] as List? ?? const []),
              ...supplements,
            ];
            org['services'] = extra['services'] ?? const [];
            org['sources'] = extra['sources'] ?? const [];
          }
          return _parseOrganizations(jsonEncode(remote));
        }
        return _parseOrganizations(response.body);
      } on FormatException {
        // A malformed remote snapshot must not make the native directory blank.
      } on CampusDirectoryException {
        // The packaged snapshot remains the source of last resort.
      }
    }
    final raw = await _assetBundle.loadString(
      'assets/catalog/bnbu_directory.json',
    );
    return _parseOrganizations(raw);
  }

  List<CampusDirectoryOrganization> _parseOrganizations(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const CampusDirectoryException('政教目录格式无效。');
    }
    final organizations = decoded['organizations'];
    if (organizations is! List) {
      throw const CampusDirectoryException('政教目录缺少机构列表。');
    }
    return organizations
        .whereType<Map>()
        .map(
          (item) => CampusDirectoryOrganization.fromJson(
            item.cast<String, dynamic>(),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<OfficialTeacherPage> loadTeachers({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
  }) => loadTeacherSnapshot(
    query: query,
    unit: unit,
    offset: offset,
    limit: limit,
  );

  @override
  Future<OfficialTeacherPage> loadTeacherSnapshot({
    String query = '',
    String unit = '',
    int offset = 0,
    int limit = 60,
    String snapshotVersion = '',
    bool refresh = false,
  }) async {
    final normalizedQuery = query.trim();
    final normalizedUnit = unit.trim();
    if (normalizedQuery.length > 80 ||
        normalizedUnit.length > 160 ||
        offset < 0 ||
        limit < 1 ||
        limit > 100) {
      throw const CampusDirectoryException('师资目录请求参数无效。');
    }
    final uri = Uri.parse('$_baseUrl/v1/directory/public/teachers').replace(
      queryParameters: {
        if (normalizedQuery.isNotEmpty) 'q': normalizedQuery,
        if (normalizedUnit.isNotEmpty) 'unit': normalizedUnit,
        if (snapshotVersion.isNotEmpty) 'snapshot_version': snapshotVersion,
        'offset': '$offset',
        'limit': '$limit',
      },
    );
    final http.Response response;
    try {
      response = await retryNetworkOperation(
        () =>
            (refresh && _client is PublicDirectoryCache
                    ? _client.refreshPublic(uri)
                    : _client.get(
                        uri,
                        headers: const {'Accept': 'application/json'},
                      ))
                .timeout(const Duration(seconds: 15)),
        shouldRetryResult: (response) =>
            isTransientHttpStatus(response.statusCode),
        delay: _retryDelay,
      );
    } on Object catch (error) {
      if (isTransientNetworkError(error)) {
        throw const CampusDirectoryException('师资目录网络连接不稳定，请稍后重试。');
      }
      rethrow;
    }
    if (response.statusCode == 409) {
      throw const CampusDirectoryException(
        '师资目录已更新，请重新加载',
        snapshotChanged: true,
      );
    }
    if (response.statusCode != 200) {
      throw CampusDirectoryException('师资目录暂时不可用（HTTP ${response.statusCode}）。');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const CampusDirectoryException('师资目录响应格式无效。');
    }
    return OfficialTeacherPage.fromJson(decoded);
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }
}

class CampusDirectoryException implements Exception {
  const CampusDirectoryException(this.message, {this.snapshotChanged = false});

  final bool snapshotChanged;

  final String message;

  @override
  String toString() => message;
}

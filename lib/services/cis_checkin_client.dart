import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import '../config/app_config.dart';
import '../config/ispace_tls_trust.dart';
import '../models/cis_checkin.dart';

enum CisCheckinFailure {
  authentication,
  permission,
  network,
  invalidData,
  sessionChanged,
}

class CisCheckinException implements Exception {
  const CisCheckinException(this.failure);
  final CisCheckinFailure failure;
  String get message => switch (failure) {
    CisCheckinFailure.authentication => '打卡系统认证未通过，请在学校系统核对账号或额外验证要求。',
    CisCheckinFailure.permission => '当前账号暂无打卡系统访问权限。',
    CisCheckinFailure.network => '暂时无法连接学校打卡系统，请稍后重试。',
    CisCheckinFailure.invalidData => '学校打卡数据格式暂不支持，请稍后重试。',
    CisCheckinFailure.sessionChanged => '登录状态已变化，请重新打开打卡查看。',
  };
  @override
  String toString() => 'CisCheckinException(${failure.name})';
}

/// Owned only by AppSessionController. No disk storage, cookie export,
/// administrative endpoints, check-in mutations or cross-origin redirects.
class CisCheckinClient {
  CisCheckinClient({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    DateTime Function()? clock,
    Future<void> Function(Duration)? retryDelay,
  }) : _clock = clock ?? DateTime.now,
       _retryDelay = retryDelay ?? Future<void>.delayed,
       _client =
           client ??
           IOClient(
             HttpClient(
               context: createBnbuSchoolSecurityContext([
                 AppConfig.bnbuCheckinBaseUrl,
               ]),
             )..connectionTimeout = timeout,
           );

  final http.Client _client;
  final Duration timeout;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _retryDelay;
  final _projects = _CisReadCache<CisCheckinProject>();
  final _records = _CisReadCache<CisCheckinRecord>();

  CisCheckinPageData<CisCheckinProject>? cachedProjects({int page = 1}) =>
      _projects.peek('$page', _clock());
  CisCheckinPageData<CisCheckinRecord>? cachedRecords({
    String? projectId,
    int page = 1,
  }) => _records.peek('${projectId ?? ''}:$page', _clock());
  Future<void> _queue = Future.value();
  int _generation = 0;
  bool _disposed = false;
  String? _owner;
  String? _token;
  static const pageSize = 30;
  static const _maxBytes = 2 * 1024 * 1024;

  void clearSession() {
    _generation++;
    _projects.clear();
    _records.clear();
    _queue = Future.value();
    _owner = null;
    _token = null;
  }

  void dispose() {
    _disposed = true;
    clearSession();
    _client.close();
  }

  void _check(int generation) {
    if (_disposed || generation != _generation) {
      throw const CisCheckinException(CisCheckinFailure.sessionChanged);
    }
  }

  Future<CisCheckinPageData<CisCheckinProject>> fetchProjects({
    required String username,
    required String password,
    int page = 1,
    bool forceRefresh = false,
  }) => _cachedRead(
    _projects,
    '$page',
    username,
    forceRefresh,
    () => _read(
      username,
      password,
      '/api/user/authorityUser/list',
      page,
      const {},
      CisCheckinProject.fromJson,
    ),
  );

  Future<CisCheckinPageData<CisCheckinRecord>> fetchRecords({
    required String username,
    required String password,
    String? projectId,
    int page = 1,
    bool forceRefresh = false,
  }) => _cachedRead(
    _records,
    '${projectId ?? ''}:$page',
    username,
    forceRefresh,
    () => _read(
      username,
      password,
      '/api/user/checkin/log/list',
      page,
      {
        if (projectId != null) 'projectId': cisId(projectId),
        'sortField': 'createTime',
        'sortOrder': 'descend',
      },
      CisCheckinRecord.fromJson,
      include: CisCheckinRecord.isSettled,
    ),
  );

  Future<CisCheckinPageData<T>> _cachedRead<T>(
    _CisReadCache<T> cache,
    String key,
    String owner,
    bool forceRefresh,
    Future<CisCheckinPageData<T>> Function() read,
  ) {
    _check(_generation);
    if (_owner != owner) {
      clearSession();
      _owner = owner;
    }
    // A foreground open and preloading share the same live request.
    final pending = cache.pending[key];
    if (pending != null) return pending;
    final cached = cache.peek(key, _clock(), fresh: true);
    if (!forceRefresh && cached != null) return Future.value(cached);
    final generation = _generation;
    late final Future<CisCheckinPageData<T>> future;
    future = (() async {
      try {
        final result = await Future.sync(read);
        _check(generation);
        cache.store(key, result, _clock());
        return result;
      } finally {
        if (identical(cache.pending[key], future)) cache.pending.remove(key);
      }
    })();
    cache.pending[key] = future;
    return future;
  }

  Future<CisCheckinPageData<T>> _read<T>(
    String username,
    String password,
    String path,
    int page,
    Map<String, String> query,
    T Function(Map<String, dynamic>) parse, {
    bool Function(Map<String, dynamic>)? include,
  }) {
    if (page < 1 || page > 10000) throw ArgumentError.value(page, 'page');
    final generation = _generation;
    final result = _queue.then((_) async {
      _check(generation);
      try {
        if (_owner != username) {
          _owner = username;
          _token = null;
        }
        for (var attempt = 0; attempt < 2; attempt++) {
          _check(generation);
          if (_token == null) {
            final login = await _request(
              '/api/auth/login',
              generation,
              body: {
                username.contains('@') ? 'email' : 'username': username,
                'password': password,
              },
            );
            final token = cisObject(login['result'])['token'];
            if (token is! String ||
                token.isEmpty ||
                token.length > 16384 ||
                RegExp(r'[\r\n]').hasMatch(token)) {
              throw const CisCheckinException(CisCheckinFailure.authentication);
            }
            _check(generation);
            _token = token;
          }
          try {
            final response = await _readRequest(
              path,
              generation,
              query: {...query, 'pageNo': '$page', 'pageSize': '$pageSize'},
            );
            _check(generation);
            final data = cisObject(response['result']);
            final rows = data['data'];
            final total = cisCount(data['totalCount']);
            if (data['pageNo'] != page ||
                rows is! List ||
                rows.length > pageSize) {
              throw const FormatException('Invalid CIS page');
            }
            final parsed = <T>[];
            var hasUnknownStatistics = false;
            for (final row in rows) {
              final object = cisObject(row);
              if (include != null &&
                  !CisCheckinRecord.hasKnownStatistics(object)) {
                hasUnknownStatistics = true;
              }
              if (include == null || include(object)) parsed.add(parse(object));
            }
            return CisCheckinPageData<T>(
              items: List.unmodifiable(parsed),
              page: page,
              hasMore: page * pageSize < total,
              hasUnknownStatistics: hasUnknownStatistics,
            );
          } on CisCheckinException catch (error) {
            _check(generation);
            if (error.failure != CisCheckinFailure.authentication ||
                attempt > 0) {
              rethrow;
            }
            _token = null;
          }
        }
        throw const CisCheckinException(CisCheckinFailure.authentication);
      } on CisCheckinException {
        rethrow;
      } on FormatException {
        throw const CisCheckinException(CisCheckinFailure.invalidData);
      } catch (_) {
        _check(generation);
        throw const CisCheckinException(CisCheckinFailure.network);
      }
    });
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<Map<String, dynamic>> _readRequest(
    String path,
    int generation, {
    required Map<String, String> query,
  }) async {
    for (var attempt = 0; ; attempt++) {
      _check(generation);
      try {
        return await _request(path, generation, query: query);
      } catch (error) {
        _check(generation);
        final transient =
            error is _CisTransientFailure ||
            error is TimeoutException ||
            error is SocketException ||
            error is http.ClientException;
        if (!transient || attempt >= 1) rethrow;
        await _retryDelay(const Duration(milliseconds: 350));
      }
    }
  }

  Future<Map<String, dynamic>> _request(
    String path,
    int generation, {
    Map<String, String> query = const {},
    Map<String, String>? body,
  }) async {
    _check(generation);
    final uri = Uri.parse(
      AppConfig.bnbuCheckinBaseUrl,
    ).replace(path: path, queryParameters: query.isEmpty ? null : query);
    final abort = Completer<void>();
    final deadline = Timer(timeout, () => abort.complete());
    try {
      final request =
          http.AbortableRequest(
              body == null ? 'GET' : 'POST',
              uri,
              abortTrigger: abort.future,
            )
            ..followRedirects = false
            ..headers['Accept'] = 'application/json';
      if (body != null) {
        request.headers['Content-Type'] = 'application/json;charset=UTF-8';
        request.body = jsonEncode(body);
      } else {
        request.headers['Authorization'] = _token!;
      }
      final response = await _client.send(request).timeout(timeout);
      if (_disposed || generation != _generation) {
        await response.stream.listen(null).cancel();
        _check(generation);
      }
      if (response.statusCode == 401) {
        await response.stream.listen(null).cancel();
        throw const CisCheckinException(CisCheckinFailure.authentication);
      }
      if (response.statusCode == 403) {
        await response.stream.listen(null).cancel();
        throw const CisCheckinException(CisCheckinFailure.permission);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        await response.stream.listen(null).cancel();
        if (const [408, 500, 502, 503, 504].contains(response.statusCode)) {
          throw const _CisTransientFailure();
        }
        throw const CisCheckinException(CisCheckinFailure.network);
      }
      if ((response.contentLength ?? 0) > _maxBytes) {
        await response.stream.listen(null).cancel();
        throw const FormatException('Oversized CIS response');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(timeout)) {
        if (bytes.length + chunk.length > _maxBytes) {
          throw const FormatException('Oversized CIS response');
        }
        bytes.addAll(chunk);
      }
      _check(generation);
      final result = cisObject(jsonDecode(utf8.decode(bytes)));
      if (result['success'] == false ||
          (result['code'] != null && result['code'] != 200)) {
        throw CisCheckinException(
          body != null || result['code'] == 401
              ? CisCheckinFailure.authentication
              : result['code'] == 403
              ? CisCheckinFailure.permission
              : CisCheckinFailure.invalidData,
        );
      }
      return result;
    } finally {
      deadline.cancel();
      if (!abort.isCompleted) abort.complete();
    }
  }
}

class _CisTransientFailure implements Exception {
  const _CisTransientFailure();
}

/// Bounded, account-session-only cache; never persisted or sent to sync/AI.
class _CisReadCache<T> {
  final entries = <String, (DateTime, CisCheckinPageData<T>)>{};
  final pending = <String, Future<CisCheckinPageData<T>>>{};
  CisCheckinPageData<T>? peek(String key, DateTime now, {bool fresh = false}) {
    final entry = entries[key];
    if (entry == null) return null;
    final age = now.difference(entry.$1);
    if (age >= const Duration(minutes: 30)) {
      entries.remove(key);
      return null;
    }
    if (fresh && age >= const Duration(minutes: 2)) return null;
    return entry.$2;
  }

  void store(String key, CisCheckinPageData<T> value, DateTime now) {
    entries.remove(key);
    entries[key] = (now, value);
    while (entries.length > 24) {
      entries.remove(entries.keys.first);
    }
  }

  void clear() {
    entries.clear();
    pending.clear();
  }
}

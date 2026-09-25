import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../config/app_config.dart';
import '../models/academic_calendar.dart';
import 'network_retry.dart';

/// Public configuration only. HTTP is independent from school sessions.
class AcademicCalendarStore {
  AcademicCalendarStore({
    http.Client? client,
    Future<Directory> Function()? directory,
    String? baseUrl,
    void Function(BnbuCalendarCatalog)? onUpdate,
  }) : _client = client ?? createAppHttpClient(),
       _directory = directory ?? getApplicationSupportDirectory,
       baseUrl = AppConfig.normalizedHttpsBaseUrl(
         baseUrl ?? AppConfig.syncServiceBaseUrl,
         settingName: 'SYNC_SERVICE_BASE_URL',
       ),
       _onUpdate = onUpdate ?? BnbuAcademicCalendar.install;
  static final shared = AcademicCalendarStore();
  final http.Client _client;
  final Future<Directory> Function() _directory;
  final String baseUrl;
  final void Function(BnbuCalendarCatalog) _onUpdate;
  BnbuCalendarCatalog? catalog;
  Future<void>? _local, _refresh;
  DateTime? _lastCheck;
  bool failed = false, _disposed = false;
  Future<File> _file() async => File(
    '${(await _directory()).path}/academic-calendar-v1-${sha256.convert(utf8.encode(baseUrl)).toString().substring(0, 16)}.json',
  );
  Future<void> loadLocal() => _local ??= _loadLocal();
  Future<void> _loadLocal() async {
    try {
      final file = await _file();
      if (await file.length() > 2 * 1024 * 1024) return;
      final next = BnbuCalendarCatalog.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
      if (!_disposed) {
        catalog = next;
        _onUpdate(next);
      }
    } on Object {
      /* Invalid cache leaves the built-in semester intact. */
    }
  }

  Future<void> refresh({bool force = false}) async {
    await loadLocal();
    if (_disposed) return;
    if (!force &&
        _lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < const Duration(minutes: 5)) {
      return;
    }
    return _refresh ??= _fetch().whenComplete(() => _refresh = null);
  }

  Future<void> _fetch() async {
    _lastCheck = DateTime.now();
    failed = false;
    try {
      final request = http.Request(
        'GET',
        Uri.parse('$baseUrl/v1/public/academic-calendar'),
      )..followRedirects = false;
      if (catalog != null) {
        request.headers['If-None-Match'] =
            '"academic-calendar-${catalog!.version}"';
      }
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 304 && catalog != null) {
        await response.stream.drain<void>().timeout(
          const Duration(seconds: 12),
        );
        return;
      }
      if (response.statusCode != 200 || response.isRedirect) {
        await response.stream
            .take(1)
            .drain<void>()
            .timeout(const Duration(seconds: 12));
        throw const FormatException('Calendar HTTP');
      }
      final bytes = await (() async {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (builder.length + chunk.length > 2 * 1024 * 1024) {
            throw const FormatException('Calendar size');
          }
          builder.add(chunk);
        }
        return builder.takeBytes();
      })().timeout(const Duration(seconds: 15));
      final next = BnbuCalendarCatalog.fromJson(
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
      );
      if (_disposed || (catalog != null && next.version <= catalog!.version)) {
        return;
      }
      try {
        final file = await _file();
        await file.parent.create(recursive: true);
        final temp = File('${file.path}.tmp');
        await temp.writeAsBytes(bytes, flush: true);
        await temp.rename(file.path);
      } on Object {
        /* Valid in-memory updates remain usable on a full disk. */
      }
      if (!_disposed) {
        catalog = next;
        _onUpdate(next);
      }
    } on Object {
      failed = true;
    }
  }

  void dispose() {
    _disposed = true;
    _client.close();
  }
}

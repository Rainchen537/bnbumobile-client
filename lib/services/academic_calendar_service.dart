import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../config/ispace_tls_trust.dart';
import '../models/academic_calendar.dart';
import 'network_retry.dart';

enum AcademicCalendarDocumentKind { academicCalendar, classSchedule }

class AcademicCalendarDocument {
  const AcademicCalendarDocument({
    required this.kind,
    required this.title,
    required this.uri,
  });

  final AcademicCalendarDocumentKind kind;
  final String title;
  final Uri uri;
}

class AcademicCalendarBundle {
  const AcademicCalendarBundle({
    required this.semesterTitle,
    required this.academicCalendar,
    required this.classSchedule,
  });

  final String semesterTitle;
  final AcademicCalendarDocument academicCalendar;
  final AcademicCalendarDocument classSchedule;
}

class AcademicCalendarSnapshot {
  const AcademicCalendarSnapshot({
    required this.bundle,
    required this.academicCalendarBytes,
    required this.classScheduleBytes,
  });

  final AcademicCalendarBundle bundle;
  final Uint8List academicCalendarBytes;
  final Uint8List classScheduleBytes;

  Uint8List bytesFor(AcademicCalendarDocumentKind kind) => switch (kind) {
    AcademicCalendarDocumentKind.academicCalendar => academicCalendarBytes,
    AcademicCalendarDocumentKind.classSchedule => classScheduleBytes,
  };
}

abstract interface class AcademicCalendarRepository {
  Future<AcademicCalendarSnapshot> load();
}

/// Lightweight official metadata loader.  It intentionally never downloads
/// either PDF, which keeps Small U context requests bounded.
abstract interface class AcademicCalendarBundleLoader {
  Future<AcademicCalendarBundle> loadBundle();
}

class OfficialAcademicCalendarRepository
    implements AcademicCalendarRepository, AcademicCalendarBundleLoader {
  OfficialAcademicCalendarRepository({
    http.Client? client,
    this.semester,
    this.cacheTtl = Duration.zero,
    DateTime Function()? now,
  }) : _client = client,
       _now = now ?? DateTime.now;

  final BnbuCalendarSemester? Function()? semester;
  final Duration cacheTtl;
  final DateTime Function() _now;
  AcademicCalendarBundle? _bundle;
  DateTime? _bundleLoadedAt;
  Future<AcademicCalendarBundle>? _bundleLoading;
  final _documents = <Uri, ({DateTime at, Uint8List bytes})>{};
  final _documentLoading = <String, Future<Uint8List>>{};
  int _calendarRevision = -1;

  static final Uri indexUri = Uri.parse(
    'https://ar.bnbu.edu.cn/current_students/student_handbook/Academic_Calendar.htm',
  );
  static final Uri fallbackAcademicCalendarUri = Uri.parse(
    'https://ar.bnbu.edu.cn/attachment/file/Academic_Calendar_for_S1_AY202627.pdf',
  );
  static final Uri fallbackClassScheduleUri = Uri.parse(
    'https://ar.bnbu.edu.cn/attachment/file/Class_schedule_for_S1_AY202627.pdf',
  );

  static const int _maxIndexBytes = 2 * 1024 * 1024;
  static const int _maxPdfBytes = 24 * 1024 * 1024;
  static const int _maxRedirects = 3;

  final http.Client? _client;

  @override
  Future<AcademicCalendarSnapshot> load() async {
    final bundle = await loadBundle();
    final bytes = await Future.wait([
      _loadDocument(bundle.academicCalendar),
      _loadDocument(bundle.classSchedule),
    ]);
    return AcademicCalendarSnapshot(
      bundle: bundle,
      academicCalendarBytes: bytes[0],
      classScheduleBytes: bytes[1],
    );
  }

  /// Fetch only the requested public document; coalesce simultaneous readers.
  Future<Uint8List> loadDocument(AcademicCalendarDocumentKind kind) async {
    final bundle = await loadBundle();
    return _loadDocument(
      kind == AcademicCalendarDocumentKind.academicCalendar
          ? bundle.academicCalendar
          : bundle.classSchedule,
    );
  }

  Future<T> _withClient<T>(Future<T> Function(http.Client) operation) async {
    final client =
        _client ??
        createAppHttpClient(
          securityContext: createBnbuSchoolSecurityContext([
            indexUri.toString(),
            fallbackAcademicCalendarUri.toString(),
            fallbackClassScheduleUri.toString(),
          ]),
        );
    try {
      return await operation(client);
    } finally {
      if (_client == null) client.close();
    }
  }

  bool _fresh(DateTime? at) =>
      at != null && _now().difference(at) < cacheTtl && !_now().isBefore(at);

  @override
  Future<AcademicCalendarBundle> loadBundle() {
    if (_calendarRevision != BnbuAcademicCalendar.revision.value) {
      _calendarRevision = BnbuAcademicCalendar.revision.value;
      _bundle = null;
      _bundleLoadedAt = null;
      _documents.clear();
    }
    final configured = semester?.call() ?? BnbuAcademicCalendar.current;
    if (configured.documents.isNotEmpty) {
      return Future.value(bundleForSemester(configured));
    }
    if (_bundle != null && _fresh(_bundleLoadedAt)) {
      return Future.value(_bundle!);
    }
    return _bundleLoading ??= _withClient(_loadBundle)
        .then((value) {
          _bundle = value;
          _bundleLoadedAt = _now();
          return value;
        })
        .whenComplete(() => _bundleLoading = null);
  }

  Future<Uint8List> _loadDocument(AcademicCalendarDocument document) {
    final revision = _calendarRevision;
    final loadingKey = '$revision:${document.uri}';
    final cached = _documents[document.uri];
    if (cached != null && _fresh(cached.at)) return Future.value(cached.bytes);
    return _documentLoading[loadingKey] ??=
        _withClient(
              (client) => _downloadWithFallback(
                client,
                document.uri,
                BnbuAcademicCalendar.catalog == null
                    ? (document.kind ==
                              AcademicCalendarDocumentKind.academicCalendar
                          ? fallbackAcademicCalendarUri
                          : fallbackClassScheduleUri)
                    : document.uri,
              ),
            )
            .then((value) {
              // There are only two current documents; replaced URLs do not accumulate.
              _documents.removeWhere((uri, entry) => !_fresh(entry.at));
              if (_documents.length >= 2) {
                _documents.remove(_documents.keys.first);
              }
              final bytes = value.asUnmodifiableView();
              if (revision == _calendarRevision) {
                _documents[document.uri] = (at: _now(), bytes: bytes);
              }
              return bytes;
            })
            .whenComplete(() {
              _documentLoading.remove(loadingKey);
            });
  }

  Future<AcademicCalendarBundle> _loadBundle(http.Client client) async {
    try {
      final indexBytes = await _download(
        client,
        indexUri,
        maxBytes: _maxIndexBytes,
        requirePdf: false,
      );
      return parseAcademicCalendarIndex(
        utf8.decode(indexBytes, allowMalformed: true),
        indexUri: indexUri,
      );
    } catch (_) {
      // Pinned official links keep metadata available when the registry index
      // is temporarily unavailable.
      return fallbackAcademicCalendarBundle;
    }
  }

  Future<Uint8List> _downloadWithFallback(
    http.Client client,
    Uri primary,
    Uri fallback,
  ) async {
    try {
      return await _download(
        client,
        primary,
        maxBytes: _maxPdfBytes,
        requirePdf: true,
      );
    } catch (_) {
      if (primary == fallback) rethrow;
      return _download(
        client,
        fallback,
        maxBytes: _maxPdfBytes,
        requirePdf: true,
      );
    }
  }

  Future<Uint8List> _download(
    http.Client client,
    Uri initialUri, {
    required int maxBytes,
    required bool requirePdf,
  }) async {
    var current = _requireOfficialUri(initialUri, requirePdf: requirePdf);
    for (var redirect = 0; redirect <= _maxRedirects; redirect++) {
      final request = http.Request('GET', current)
        ..followRedirects = false
        ..headers['Accept'] = requirePdf
            ? 'application/pdf'
            : 'text/html,application/xhtml+xml';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (_isRedirect(response.statusCode)) {
        final location = response.headers['location'];
        await response.stream.drain<void>();
        if (location == null || redirect == _maxRedirects) {
          throw const AcademicCalendarException('学校文件重定向无效。');
        }
        current = _requireOfficialUri(
          current.resolve(location),
          requirePdf: requirePdf,
        );
        continue;
      }
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        throw AcademicCalendarException('学校文件返回 HTTP ${response.statusCode}。');
      }
      final contentLength = response.contentLength;
      if (contentLength != null && contentLength > maxBytes) {
        await response.stream.drain<void>();
        throw const AcademicCalendarException('学校文件超过允许大小。');
      }
      final builder = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        received += chunk.length;
        if (received > maxBytes) {
          throw const AcademicCalendarException('学校文件超过允许大小。');
        }
        builder.add(chunk);
      }
      final bytes = builder.takeBytes();
      if (bytes.isEmpty) {
        throw const AcademicCalendarException('学校文件内容为空。');
      }
      if (requirePdf && !_hasPdfMagic(bytes)) {
        throw const AcademicCalendarException('学校返回的内容不是 PDF。');
      }
      return bytes;
    }
    throw const AcademicCalendarException('学校文件重定向次数过多。');
  }
}

AcademicCalendarBundle parseAcademicCalendarIndex(
  String source, {
  Uri? indexUri,
}) {
  final baseUri = indexUri ?? OfficialAcademicCalendarRepository.indexUri;
  final document = html_parser.parse(source);
  Uri? academicCalendarUri;
  Uri? classScheduleUri;
  for (final anchor in document.querySelectorAll('a[href]')) {
    final text = _normalizedLinkText(anchor.text);
    final href = anchor.attributes['href']?.trim();
    if (href == null || href.isEmpty) continue;
    if (text.contains('academiccalendarfors1ofay202627pdf')) {
      academicCalendarUri = _requireOfficialUri(
        baseUri.resolve(href),
        requirePdf: true,
      );
    } else if (text.contains('classschedulefors1ofay202627pdf')) {
      classScheduleUri = _requireOfficialUri(
        baseUri.resolve(href),
        requirePdf: true,
      );
    }
  }
  if (academicCalendarUri == null || classScheduleUri == null) {
    throw const AcademicCalendarException('官网未找到本学期校历文件。');
  }
  return AcademicCalendarBundle(
    semesterTitle: bnbuAy202627Semester1Title,
    academicCalendar: AcademicCalendarDocument(
      kind: AcademicCalendarDocumentKind.academicCalendar,
      title: 'Academic Calendar for S1 of AY2026-27.pdf',
      uri: academicCalendarUri,
    ),
    classSchedule: AcademicCalendarDocument(
      kind: AcademicCalendarDocumentKind.classSchedule,
      title: 'Class Schedule for S1 of AY2026-27.pdf',
      uri: classScheduleUri,
    ),
  );
}

final AcademicCalendarBundle fallbackAcademicCalendarBundle =
    AcademicCalendarBundle(
      semesterTitle: bnbuAy202627Semester1Title,
      academicCalendar: AcademicCalendarDocument(
        kind: AcademicCalendarDocumentKind.academicCalendar,
        title: 'Academic Calendar for S1 of AY2026-27.pdf',
        uri: OfficialAcademicCalendarRepository.fallbackAcademicCalendarUri,
      ),
      classSchedule: AcademicCalendarDocument(
        kind: AcademicCalendarDocumentKind.classSchedule,
        title: 'Class Schedule for S1 of AY2026-27.pdf',
        uri: OfficialAcademicCalendarRepository.fallbackClassScheduleUri,
      ),
    );

Uri _requireOfficialUri(Uri uri, {required bool requirePdf}) {
  final valid =
      uri.scheme == 'https' &&
      uri.host.toLowerCase() == 'ar.bnbu.edu.cn' &&
      (!uri.hasPort || uri.port == 443) &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      (!requirePdf || uri.path.toLowerCase().endsWith('.pdf'));
  if (!valid) {
    throw const AcademicCalendarException('学校文件地址不受信任。');
  }
  return uri;
}

bool _isRedirect(int statusCode) =>
    statusCode == 301 ||
    statusCode == 302 ||
    statusCode == 303 ||
    statusCode == 307 ||
    statusCode == 308;

bool _hasPdfMagic(Uint8List bytes) =>
    bytes.length >= 5 &&
    bytes[0] == 0x25 &&
    bytes[1] == 0x50 &&
    bytes[2] == 0x44 &&
    bytes[3] == 0x46 &&
    bytes[4] == 0x2d;

String _normalizedLinkText(String value) =>
    value.toLowerCase().replaceAll(RegExp('[^a-z0-9]'), '');

class AcademicCalendarException implements Exception {
  const AcademicCalendarException(this.message);

  final String message;

  @override
  String toString() => message;
}

AcademicCalendarBundle bundleForSemester(BnbuCalendarSemester term) =>
    AcademicCalendarBundle(
      semesterTitle: term.semesterTitle,
      academicCalendar: AcademicCalendarDocument(
        kind: AcademicCalendarDocumentKind.academicCalendar,
        title: term.documents['academic_calendar']!.title,
        uri: term.documents['academic_calendar']!.uri,
      ),
      classSchedule: AcademicCalendarDocument(
        kind: AcademicCalendarDocumentKind.classSchedule,
        title: term.documents['class_schedule']!.title,
        uri: term.documents['class_schedule']!.uri,
      ),
    );

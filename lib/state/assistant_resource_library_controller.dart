import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/assistant_models.dart';
import '../models/assistant_resource.dart';
import '../services/assistant_resource_library_store.dart';
import 'app_session_controller.dart';

class AssistantResourceLibraryController extends ChangeNotifier {
  AssistantResourceLibraryController({
    required AppSessionController sessionController,
    AssistantResourceLibraryStore? store,
  }) : _sessionController = sessionController,
       _store = store ?? FileSystemAssistantResourceLibraryStore() {
    _sessionController.addListener(_handleSessionChanged);
    _owner = _normalizedOwner;
  }

  final AppSessionController _sessionController;
  final AssistantResourceLibraryStore _store;

  String? _owner;
  int _generation = 0;
  List<AssistantResourceItem> _resources = const [];
  bool _loading = false;
  String? _error;
  Future<void>? _initialization;
  Future<void> _mutation = Future<void>.value();
  bool _disposed = false;

  List<AssistantResourceItem> get resources => List.unmodifiable(_resources);
  bool get loading => _loading;
  String? get error => _error;

  String? get _normalizedOwner {
    if (!_sessionController.isLoggedIn) {
      return null;
    }
    final value = _sessionController.username?.trim().toLowerCase() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<void> initialize() {
    final owner = _normalizedOwner;
    if (owner != _owner) {
      _switchOwner(owner);
    }
    if (owner == null) {
      return Future<void>.value();
    }
    final active = _initialization;
    if (active != null) {
      return active;
    }
    final generation = _generation;
    final future = _load(owner, generation);
    _initialization = future;
    return future.whenComplete(() {
      if (identical(_initialization, future)) {
        _initialization = null;
      }
    });
  }

  Future<AssistantResourceItem> importCourseArchive({
    required String sourcePath,
    required String fileName,
    required String courseTitle,
    required int fileCount,
    required int totalBytes,
    required List<String> selectedFileNames,
  }) {
    final owner = _owner;
    final generation = _generation;
    if (owner == null) {
      return Future.error(
        const AssistantResourceLibraryException('当前登录账号不可用。'),
      );
    }
    return _enqueue(() async {
      final item = await _store.importFile(
        owner,
        sourcePath: sourcePath,
        fileName: fileName,
        mimeType: 'application/zip',
        kind: AssistantResourceKind.courseArchive,
        sourceTitle: courseTitle,
        summary: _courseArchiveSummary(
          fileCount: fileCount,
          totalBytes: totalBytes,
          selectedFileNames: selectedFileNames,
        ),
      );
      if (_isCurrent(owner, generation)) {
        _resources = [
          item,
          ..._resources.where((candidate) => candidate.id != item.id),
        ];
        _error = null;
        _notify();
      }
      return item;
    });
  }

  AssistantInputAttachment createReferenceAttachment(
    AssistantResourceItem item,
  ) {
    final live = _resources.where((candidate) => candidate.id == item.id);
    if (live.length != 1) {
      throw const AssistantResourceLibraryException('这个资源已不存在。');
    }
    return live.single.toReferenceAttachment();
  }

  Future<void> delete(AssistantResourceItem item) {
    final owner = _owner;
    final generation = _generation;
    if (owner == null) {
      return Future<void>.value();
    }
    return _enqueue(() async {
      await _store.delete(owner, item);
      if (_isCurrent(owner, generation)) {
        _resources = _resources
            .where((candidate) => candidate.id != item.id)
            .toList(growable: false);
        _error = null;
        _notify();
      }
    });
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    _notify();
  }

  Future<void> _load(String owner, int generation) async {
    _loading = true;
    _error = null;
    _notify();
    try {
      final loaded = await _store.load(owner);
      if (!_isCurrent(owner, generation)) return;
      _resources = loaded;
    } catch (error) {
      if (!_isCurrent(owner, generation)) return;
      _resources = const [];
      _error = error.toString();
    } finally {
      if (_isCurrent(owner, generation)) {
        _loading = false;
        _notify();
      }
    }
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _mutation = _mutation.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _handleSessionChanged() {
    final owner = _normalizedOwner;
    if (owner == _owner) return;
    _switchOwner(owner);
    if (owner != null) {
      unawaited(initialize());
    }
  }

  void _switchOwner(String? owner) {
    _generation++;
    _owner = owner;
    _resources = const [];
    _loading = false;
    _error = null;
    _initialization = null;
    _notify();
  }

  bool _isCurrent(String owner, int generation) {
    return !_disposed && _owner == owner && _generation == generation;
  }

  String _courseArchiveSummary({
    required int fileCount,
    required int totalBytes,
    required List<String> selectedFileNames,
  }) {
    final names = selectedFileNames
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty)
        .take(24)
        .join('、');
    return [
      '设备端生成的课程 ZIP，包含 $fileCount 个文件，共 $totalBytes 字节。',
      if (names.isNotEmpty) '文件：$names',
      if (selectedFileNames.length > 24)
        '另有 ${selectedFileNames.length - 24} 个文件未在摘要中列出。',
    ].join(' ');
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionController.removeListener(_handleSessionChanged);
    super.dispose();
  }
}

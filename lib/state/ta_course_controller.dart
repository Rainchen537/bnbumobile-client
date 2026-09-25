import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/ta_course_entry.dart';
import '../models/personal_sync_data.dart';
import '../models/timetable_data.dart';
import '../services/ta_course_repository.dart';
import 'app_session_controller.dart';

class TaCourseController extends ChangeNotifier {
  TaCourseController({
    required AppSessionController sessionController,
    TaCourseRepository? repository,
  }) : _sessionController = sessionController,
       _repository = repository ?? TaCourseRepository() {
    _sessionController.addListener(_handleSessionChanged);
    _syncOwnerWithSession();
  }

  final AppSessionController _sessionController;
  final TaCourseRepository _repository;

  String? _owner;
  String? _ownerHash;
  int _ownerGeneration = 0;
  String? _loadedOwner;
  int? _loadedOwnerGeneration;
  Future<TaCourseMutationResult>? _loadInFlight;
  String? _loadInFlightOwner;
  int? _loadInFlightOwnerGeneration;
  int _revision = 0;
  List<TaCourseEntry> _entries = const [];
  bool _isLoading = false;
  bool _isSaving = false;
  Object? _lastSaveError;
  TaCourseConflictException? _lastConflict;
  bool _disposed = false;

  TimetableData? get timetable => _sessionController.timetable;

  TaCourseEntry _validatedEntry(TaCourseEntry entry) {
    entry.validate();
    if (!entry.isTa) return entry;
    final course = entry.resolveCourse(timetable);
    if (course == null) {
      throw const TaCourseStorageException('所属课程已变化，请重新选择课程。');
    }
    return entry.copyWith(title: course.name, courseCode: course.code);
  }

  bool get canManage => _owner != null;
  List<TaCourseEntry> get entries => _entries;
  int get revision => _revision;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  Object? get lastSaveError => _lastSaveError;
  TaCourseConflictException? get lastConflict => _lastConflict;
  String? get ownerHash => _ownerHash;

  String? get errorMessage {
    final conflict = _lastConflict;
    if (conflict != null) {
      return _messageForConflict(conflict);
    }
    final saveError = _lastSaveError;
    if (saveError is TaCourseStorageException) {
      return saveError.message;
    }
    if (saveError != null) {
      return '固定日程配置保存失败，请稍后重试。';
    }
    return null;
  }

  TaCourseImportDiff previewImport(List<TaCourseEntry> importedEntries) {
    return _repository.previewImport(
      TaCourseState(
        ownerHash: _ownerHash ?? '',
        revision: _revision,
        entries: _entries,
      ),
      importedEntries,
    );
  }

  Future<TaCourseMutationResult> reload() async {
    final owner = _owner;
    if (owner == null) {
      _clearForSignedOut();
      return TaCourseMutationResult.success();
    }
    return _requestLoad(owner, _ownerGeneration, force: true);
  }

  Future<void> applySynchronized(
    String owner,
    PersonalSyncData before,
    PersonalSyncData target,
    bool Function() isCurrent,
  ) async {
    final generation = _ownerGeneration;
    bool current() =>
        !_disposed &&
        owner == _owner &&
        generation == _ownerGeneration &&
        isCurrent();
    if (!current()) throw StateError('Sync account changed');
    final state = await _repository.applySynchronized(
      owner,
      before,
      target,
      current,
    );
    if (!current()) return;
    if (state.revision == _revision) return;
    _applyState(state);
    _notifyListeners();
  }

  Future<TaCourseMutationResult> ensureLoaded() async {
    final owner = _owner;
    if (owner == null) {
      _clearForSignedOut();
      return TaCourseMutationResult.success();
    }
    return _requestLoad(owner, _ownerGeneration, force: false);
  }

  Future<TaCourseMutationResult> addEntry(
    TaCourseEntry entry, {
    required int expectedRevision,
  }) {
    return _mutate(
      (owner) => _repository.addEntry(
        owner,
        _validatedEntry(entry),
        expectedRevision: expectedRevision,
      ),
    );
  }

  Future<TaCourseMutationResult> updateEntry(
    TaCourseEntry entry, {
    required int expectedRevision,
  }) {
    return _mutate(
      (owner) => _repository.updateEntry(
        owner,
        _validatedEntry(entry),
        expectedRevision: expectedRevision,
      ),
    );
  }

  Future<TaCourseMutationResult> deleteEntry(
    String entryId, {
    required int expectedRevision,
  }) {
    return _mutate(
      (owner) => _repository.deleteEntry(
        owner,
        entryId,
        expectedRevision: expectedRevision,
      ),
    );
  }

  Future<TaCourseMutationResult> applyImportDiff(TaCourseImportDiff diff) {
    return _mutate((owner) {
      for (final entry in [
        ...diff.additions,
        ...diff.updates.map((update) => update.imported),
      ]) {
        final canonical = _validatedEntry(entry);
        if (!canonical.hasSameCourseFields(entry)) {
          throw const TaCourseStorageException('导入的 TA 与所属课程不一致。');
        }
      }
      return _repository.applyImportDiff(owner, diff);
    });
  }

  void clearErrors() {
    if (_lastSaveError == null && _lastConflict == null) {
      return;
    }
    _lastSaveError = null;
    _lastConflict = null;
    _notifyListeners();
  }

  void _handleSessionChanged() {
    _syncOwnerWithSession();
  }

  void _syncOwnerWithSession() {
    final nextOwner = _currentSessionOwner;
    if (nextOwner == _owner) {
      return;
    }
    _owner = nextOwner;
    _ownerHash = nextOwner == null
        ? null
        : TaCourseRepository.ownerHashForUsername(nextOwner);
    _ownerGeneration += 1;
    _loadedOwner = null;
    _loadedOwnerGeneration = null;
    _loadInFlight = null;
    _loadInFlightOwner = null;
    _loadInFlightOwnerGeneration = null;
    _lastSaveError = null;
    _lastConflict = null;
    if (nextOwner == null) {
      _clearForSignedOut();
      return;
    }
    _entries = const [];
    _revision = 0;
    _isLoading = true;
    _notifyListeners();
    unawaited(ensureLoaded());
  }

  String? get _currentSessionOwner {
    if (!_sessionController.isLoggedIn) {
      return null;
    }
    final username = _sessionController.username?.trim().toLowerCase() ?? '';
    return username.isEmpty ? null : username;
  }

  void _clearForSignedOut() {
    _entries = const [];
    _revision = 0;
    _ownerHash = null;
    _loadedOwner = null;
    _loadedOwnerGeneration = null;
    _loadInFlight = null;
    _loadInFlightOwner = null;
    _loadInFlightOwnerGeneration = null;
    _isLoading = false;
    _isSaving = false;
    _lastSaveError = null;
    _lastConflict = null;
    _notifyListeners();
  }

  Future<TaCourseMutationResult> _requestLoad(
    String owner,
    int ownerGeneration, {
    required bool force,
  }) {
    final inFlight = _loadInFlight;
    if (inFlight != null &&
        _loadInFlightOwner == owner &&
        _loadInFlightOwnerGeneration == ownerGeneration) {
      return inFlight;
    }
    if (!force &&
        _loadedOwner == owner &&
        _loadedOwnerGeneration == ownerGeneration) {
      return Future.value(TaCourseMutationResult.success());
    }

    if (!_isLoading) {
      _isLoading = true;
      _notifyListeners();
    }
    final load = _loadOwner(owner, ownerGeneration);
    _loadInFlight = load;
    _loadInFlightOwner = owner;
    _loadInFlightOwnerGeneration = ownerGeneration;
    unawaited(
      load.whenComplete(() {
        if (identical(_loadInFlight, load)) {
          _loadInFlight = null;
          _loadInFlightOwner = null;
          _loadInFlightOwnerGeneration = null;
        }
      }),
    );
    return load;
  }

  Future<TaCourseMutationResult> _loadOwner(
    String owner,
    int ownerGeneration,
  ) async {
    try {
      final state = await _repository.load(owner);
      if (_disposed || _owner != owner || _ownerGeneration != ownerGeneration) {
        return TaCourseMutationResult.failure(StateError('登录状态已变化，请重新操作。'));
      }
      _applyState(state);
      _loadedOwner = owner;
      _loadedOwnerGeneration = ownerGeneration;
      _isLoading = false;
      _lastSaveError = null;
      _lastConflict = null;
      _notifyListeners();
      return TaCourseMutationResult.success(state: state);
    } on TaCourseConflictException catch (error) {
      if (!_disposed &&
          _owner == owner &&
          _ownerGeneration == ownerGeneration) {
        _isLoading = false;
        _lastConflict = error;
        _notifyListeners();
      }
      return TaCourseMutationResult.conflict(error);
    } catch (error) {
      if (!_disposed &&
          _owner == owner &&
          _ownerGeneration == ownerGeneration) {
        _isLoading = false;
        _lastSaveError = error;
        _notifyListeners();
      }
      return TaCourseMutationResult.failure(error);
    }
  }

  Future<TaCourseMutationResult> _mutate(
    Future<TaCourseState> Function(String owner) operation,
  ) async {
    final owner = _owner;
    if (owner == null) {
      final error = StateError('请先登录后管理固定日程。');
      _lastSaveError = error;
      _notifyListeners();
      return TaCourseMutationResult.failure(error);
    }
    final ownerGeneration = _ownerGeneration;
    final loadResult = await ensureLoaded();
    if (!loadResult.isSuccess) {
      return loadResult;
    }
    if (_disposed || _owner != owner || _ownerGeneration != ownerGeneration) {
      return TaCourseMutationResult.failure(StateError('登录状态已变化，请重新操作。'));
    }
    _isSaving = true;
    _lastSaveError = null;
    _lastConflict = null;
    _notifyListeners();
    try {
      final state = await operation(owner);
      if (_disposed || _owner != owner || _ownerGeneration != ownerGeneration) {
        return TaCourseMutationResult.failure(StateError('登录状态已变化，请重新操作。'));
      }
      _applyState(state);
      _loadedOwner = owner;
      _loadedOwnerGeneration = ownerGeneration;
      _lastSaveError = null;
      _lastConflict = null;
      _notifyListeners();
      return TaCourseMutationResult.success(state: state);
    } on TaCourseConflictException catch (error) {
      if (!_disposed &&
          _owner == owner &&
          _ownerGeneration == ownerGeneration) {
        _lastConflict = error;
        _notifyListeners();
      }
      return TaCourseMutationResult.conflict(error);
    } catch (error) {
      if (!_disposed &&
          _owner == owner &&
          _ownerGeneration == ownerGeneration) {
        _lastSaveError = error;
        _notifyListeners();
      }
      return TaCourseMutationResult.failure(error);
    } finally {
      if (!_disposed &&
          _owner == owner &&
          _ownerGeneration == ownerGeneration) {
        _isSaving = false;
        _notifyListeners();
      }
    }
  }

  void _applyState(TaCourseState state) {
    _ownerHash = state.ownerHash;
    _revision = state.revision;
    _entries = state.entries;
    final owner = _owner;
    if (owner != null) {
      _sessionController.updateFixedScheduleReminders(entries, owner: owner);
    }
  }

  String _messageForConflict(TaCourseConflictException conflict) {
    return switch (conflict.type) {
      TaCourseConflictType.collectionRevisionMismatch => '固定日程配置已变化，请重新打开后再操作。',
      TaCourseConflictType.entryRevisionMismatch => '这条日程已被更新，请重新打开后再保存。',
      TaCourseConflictType.missingEntry => '这条日程已不存在，请刷新后再操作。',
      TaCourseConflictType.duplicateEntry => '导入内容包含重复日程，请检查文件后重试。',
      TaCourseConflictType.importHasConflicts => '导入内容与当前固定日程配置冲突，请先处理冲突。',
    };
  }

  void _notifyListeners() {
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

class TaCourseMutationResult {
  const TaCourseMutationResult._({this.state, this.conflict, this.error});

  factory TaCourseMutationResult.success({TaCourseState? state}) {
    return TaCourseMutationResult._(state: state);
  }

  factory TaCourseMutationResult.conflict(TaCourseConflictException conflict) {
    return TaCourseMutationResult._(conflict: conflict, error: conflict);
  }

  factory TaCourseMutationResult.failure(Object error) {
    return TaCourseMutationResult._(error: error);
  }

  final TaCourseState? state;
  final TaCourseConflictException? conflict;
  final Object? error;

  bool get isSuccess => conflict == null && error == null;
}

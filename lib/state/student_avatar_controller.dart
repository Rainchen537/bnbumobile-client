import 'package:flutter/foundation.dart';

import '../models/student_avatar_profile.dart';
import '../services/student_avatar_store.dart';

class StudentAvatarController extends ChangeNotifier {
  StudentAvatarController({StudentAvatarStore? store})
    : _store = store ?? SharedPreferencesStudentAvatarStore();

  final StudentAvatarStore _store;

  String? _owner;
  StudentAvatarProfile _profile = const StudentAvatarProfile();
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isRevealed = true;
  Object? _error;
  int _ownerGeneration = 0;
  int _saveGeneration = 0;

  String? get owner => _owner;
  StudentAvatarProfile get profile => _profile;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isRevealed => _isRevealed;
  Object? get error => _error;

  Future<void> switchOwner(String? owner) async {
    final normalized = owner?.trim().toLowerCase();
    final nextOwner = normalized == null || normalized.isEmpty
        ? null
        : normalized;
    if (nextOwner == _owner) {
      return;
    }

    final generation = ++_ownerGeneration;
    _owner = nextOwner;
    _profile = const StudentAvatarProfile();
    _error = null;
    _isLoading = nextOwner != null;
    _isSaving = false;
    _isRevealed = true;
    notifyListeners();

    if (nextOwner == null) {
      return;
    }

    try {
      final stored = await _store.load(nextOwner);
      if (generation != _ownerGeneration) {
        return;
      }
      _profile = stored ?? const StudentAvatarProfile();
    } catch (error) {
      if (generation != _ownerGeneration) {
        return;
      }
      _error = error;
    } finally {
      if (generation == _ownerGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  void reveal() {
    if (_isRevealed) {
      return;
    }
    _isRevealed = true;
    notifyListeners();
  }

  void toggleReveal() {
    _isRevealed = !_isRevealed;
    notifyListeners();
  }

  Future<void> update(StudentAvatarProfile profile) async {
    final owner = _owner;
    _profile = profile;
    _error = null;
    notifyListeners();
    if (owner == null) {
      return;
    }

    final ownerGeneration = _ownerGeneration;
    final saveGeneration = ++_saveGeneration;
    _isSaving = true;
    notifyListeners();
    try {
      await _store.save(owner, profile);
    } catch (error) {
      if (ownerGeneration == _ownerGeneration &&
          saveGeneration == _saveGeneration) {
        _error = error;
      }
    } finally {
      if (ownerGeneration == _ownerGeneration &&
          saveGeneration == _saveGeneration) {
        _isSaving = false;
        notifyListeners();
      }
    }
  }

  Future<void> reset() => update(const StudentAvatarProfile());

  Future<void> applyAgentPatch(
    StudentAvatarPatch patch, {
    required bool confirmed,
  }) async {
    if (!confirmed) {
      throw StateError('Student avatar changes require user confirmation');
    }
    if (patch.isEmpty) {
      return;
    }
    await update(patch.applyTo(_profile));
  }
}

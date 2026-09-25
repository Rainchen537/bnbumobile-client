import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/student_avatar_profile.dart';

abstract interface class StudentAvatarStore {
  Future<StudentAvatarProfile?> load(String owner);

  Future<void> save(String owner, StudentAvatarProfile profile);

  Future<void> remove(String owner);
}

class SharedPreferencesStudentAvatarStore implements StudentAvatarStore {
  SharedPreferencesStudentAvatarStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const String _keyPrefix = 'bnbu.student_avatar.v1.';

  final Future<SharedPreferences> Function() _preferencesLoader;
  Future<void> _mutationTail = Future<void>.value();

  @override
  Future<StudentAvatarProfile?> load(String owner) async {
    final normalizedOwner = _normalizedOwner(owner);
    await _mutationTail;
    final preferences = await _preferencesLoader();
    final encoded = preferences.getString(_keyFor(normalizedOwner));
    if (encoded == null || encoded.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, Object?>) {
        return null;
      }
      return StudentAvatarProfile.fromJson(decoded);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(String owner, StudentAvatarProfile profile) {
    final normalizedOwner = _normalizedOwner(owner);
    return _enqueueMutation(() async {
      final preferences = await _preferencesLoader();
      final didWrite = await preferences.setString(
        _keyFor(normalizedOwner),
        jsonEncode(profile.toJson()),
      );
      if (!didWrite) {
        throw StateError('Unable to persist student avatar');
      }
    });
  }

  @override
  Future<void> remove(String owner) {
    final normalizedOwner = _normalizedOwner(owner);
    return _enqueueMutation(() async {
      final preferences = await _preferencesLoader();
      final didRemove = await preferences.remove(_keyFor(normalizedOwner));
      if (!didRemove && preferences.containsKey(_keyFor(normalizedOwner))) {
        throw StateError('Unable to remove student avatar');
      }
    });
  }

  Future<void> _enqueueMutation(Future<void> Function() mutation) {
    final operation = _mutationTail.then((_) => mutation());
    _mutationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  String _keyFor(String normalizedOwner) {
    final digest = sha256.convert(utf8.encode(normalizedOwner));
    return '$_keyPrefix$digest';
  }

  String _normalizedOwner(String owner) {
    final normalized = owner.trim().toLowerCase();
    if (normalized.isEmpty || normalized.length > 320) {
      throw ArgumentError.value(owner, 'owner', 'Invalid avatar owner');
    }
    return normalized;
  }
}

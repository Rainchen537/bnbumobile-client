import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/campus_user_place.dart';

abstract interface class CampusUserPlaceStore {
  Future<List<CampusUserPlace>> load(String owner);

  Future<void> save(String owner, List<CampusUserPlace> places);
}

class SharedPreferencesCampusUserPlaceStore implements CampusUserPlaceStore {
  SharedPreferencesCampusUserPlaceStore({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const String _keyPrefix = 'bnbu.campus_user_places.v1.';
  static const int maxPlaces = 50;

  final Future<SharedPreferences> Function() _preferencesLoader;
  Future<void> _mutationTail = Future<void>.value();

  @override
  Future<List<CampusUserPlace>> load(String owner) async {
    final key = _keyFor(owner);
    await _mutationTail;
    final encoded = (await _preferencesLoader()).getString(key);
    if (encoded == null || encoded.isEmpty) return const <CampusUserPlace>[];
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return const <CampusUserPlace>[];
      final places = <CampusUserPlace>[];
      for (final raw in decoded) {
        if (raw is! Map) continue;
        try {
          places.add(
            CampusUserPlace.fromJson(
              raw.map((key, value) => MapEntry(key.toString(), value)),
            ),
          );
        } on FormatException {
          continue;
        }
        if (places.length == maxPlaces) break;
      }
      places.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      return List<CampusUserPlace>.unmodifiable(places);
    } on FormatException {
      return const <CampusUserPlace>[];
    }
  }

  @override
  Future<void> save(String owner, List<CampusUserPlace> places) {
    if (places.length > maxPlaces) {
      throw ArgumentError.value(places.length, 'places', 'Too many places');
    }
    final key = _keyFor(owner);
    final encoded = jsonEncode(
      places.map((place) => place.toJson()).toList(growable: false),
    );
    final operation = _mutationTail.then((_) async {
      final didWrite = await (await _preferencesLoader()).setString(
        key,
        encoded,
      );
      if (!didWrite) throw StateError('Unable to persist campus places');
    });
    _mutationTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  String _keyFor(String owner) {
    final normalized = owner.trim().toLowerCase();
    if (normalized.isEmpty || normalized.length > 320) {
      throw ArgumentError.value(owner, 'owner', 'Invalid campus place owner');
    }
    return '$_keyPrefix${sha256.convert(utf8.encode(normalized))}';
  }
}

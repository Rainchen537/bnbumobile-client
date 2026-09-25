import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/campus_user_place.dart';
import 'package:bnbu_me/services/campus_user_place_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('campus places persist independently for each account', () async {
    final store = SharedPreferencesCampusUserPlaceStore();
    final now = DateTime.utc(2026, 8, 4, 8);
    final place = CampusUserPlace(
      id: 'place-1',
      name: '社团集合点',
      note: '每周三',
      mapX: 0.42,
      mapY: 0.61,
      createdAt: now,
      updatedAt: now,
    );

    await store.save('first@bnbu.edu.cn', <CampusUserPlace>[place]);

    expect(await store.load('first@bnbu.edu.cn'), <CampusUserPlace>[place]);
    expect(await store.load('second@bnbu.edu.cn'), isEmpty);
  });

  test('invalid map coordinates are rejected', () {
    expect(
      () => CampusUserPlace.fromJson(<String, Object?>{
        'id': 'place-1',
        'name': '越界地点',
        'note': '',
        'map_x': 1.2,
        'map_y': 0.5,
        'created_at': '2026-08-04T08:00:00Z',
        'updated_at': '2026-08-04T08:00:00Z',
      }),
      throwsFormatException,
    );
  });

  test(
    'amap longitude and latitude persist without legacy image coordinates',
    () async {
      final store = SharedPreferencesCampusUserPlaceStore();
      final now = DateTime.utc(2026, 8, 4, 8);
      final place = CampusUserPlace(
        id: 'amap-place',
        name: '排练集合点',
        note: '',
        longitude: 113.5428,
        latitude: 22.3635,
        createdAt: now,
        updatedAt: now,
      );

      await store.save('owner', <CampusUserPlace>[place]);

      expect(await store.load('owner'), <CampusUserPlace>[place]);
      expect(place.toJson(), isNot(contains('map_x')));
    },
  );

  test('invalid local records are skipped while valid places remain', () async {
    final store = SharedPreferencesCampusUserPlaceStore();
    final now = DateTime.utc(2026, 8, 4, 8);
    final validPlace = CampusUserPlace(
      id: 'valid-place',
      name: '有效地点',
      note: '',
      mapX: 0.4,
      mapY: 0.6,
      createdAt: now,
      updatedAt: now,
    );
    const owner = 'student@bnbu.edu.cn';
    await store.save(owner, <CampusUserPlace>[validPlace]);

    final preferences = await SharedPreferences.getInstance();
    final storageKey = preferences.getKeys().single;
    await preferences.setString(
      storageKey,
      jsonEncode(<Object?>[
        validPlace.toJson(),
        <String, Object?>{
          ...validPlace.toJson(),
          'id': 'invalid-place',
          'map_x': -0.1,
        },
      ]),
    );

    expect(await store.load(owner), <CampusUserPlace>[validPlace]);
  });

  test('store rejects more than the local place limit', () {
    final store = SharedPreferencesCampusUserPlaceStore();
    final now = DateTime.utc(2026, 8, 4, 8);
    final places = List<CampusUserPlace>.generate(
      SharedPreferencesCampusUserPlaceStore.maxPlaces + 1,
      (index) => CampusUserPlace(
        id: 'place-$index',
        name: '地点 $index',
        note: '',
        mapX: 0.5,
        mapY: 0.5,
        createdAt: now,
        updatedAt: now,
      ),
    );

    expect(() => store.save('owner', places), throwsArgumentError);
  });
}

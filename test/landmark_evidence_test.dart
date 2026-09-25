import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/campus_landmark.dart';
import 'campus_landmarks_test.dart' show fixture;

void main() {
  test('evidence remains structured without photos or community scores', () {
    final json = fixture();
    final item = json['catalog']['landmarks'][0] as Map<String, dynamic>;
    item['aliases'] = ['Library', '图书馆'];
    item['sources'] = [
      {
        'id': 'official',
        'title': {'zh-Hans': '校方'},
        'url': 'https://example.edu/source',
        'record_id': 'BNBU-IC-001',
        'checked_on': '2026-09-16',
        'note': {'zh-Hans': '历史年度'},
      },
    ];
    item['facts'] = [
      {
        'id': 'award',
        'label': {'zh-Hans': '校方评级'},
        'value': {'zh-Hans': '四星级'},
        'period': '2025—2026学年',
        'source_ids': ['official'],
      },
    ];
    final catalog = LandmarkCatalog.fromJson(json);
    final parsed = catalog.landmarks.first;
    expect(parsed.aliases, contains('图书馆'));
    expect(parsed.sources.single.recordId, 'BNBU-IC-001');
    expect(parsed.facts.single.period, '2025—2026学年');
    expect(parsed.photos, isEmpty);
    expect(catalog.json['catalog']['landmarks'][0]['sources'], item['sources']);
    item['facts'][0]['source_ids'] = ['absent'];
    expect(() => LandmarkCatalog.fromJson(json), throwsFormatException);
  });
  test('legacy evidence defaults to empty', () {
    final parsed = LandmarkCatalog.fromJson(fixture()).landmarks.first;
    expect(parsed.aliases, isEmpty);
    expect(parsed.sources, isEmpty);
    expect(parsed.facts, isEmpty);
  });
}

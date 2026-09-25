import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/widget_snapshot.dart';

void main() {
  test(
    'production Swift codec decodes the actual Dart snapshot timestamps',
    () {
      final directory = Directory.systemTemp.createTempSync('bnbu-codec-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final start = DateTime.utc(2026, 9, 21, 2, 0, 0, 123, 456);
      final snapshot = BnbuWidgetSnapshot(
        generatedAt: start,
        interfaceLanguage: 'en',
        courses: [
          BnbuWidgetCourseOccurrence(
            title: 'Synthetic Course',
            code: 'TEST',
            room: 'T2-301',
            teacher: '',
            startsAt: start,
            endsAt: start.add(const Duration(hours: 1)),
            isTaCourse: false,
          ),
        ],
        deadlines: [
          BnbuWidgetDeadline(
            title: 'Synthetic DDL',
            courseName: 'TEST',
            dueAt: start.add(const Duration(hours: 2)),
          ),
        ],
      );
      final payload = File('${directory.path}/snapshot.json')
        ..writeAsStringSync(jsonEncode(snapshot.toJson()));
      final source = File('${directory.path}/main.swift')
        ..writeAsStringSync(r'''
import Foundation
struct Snapshot: Decodable {
  struct Course: Decodable { let startsAt: Date; let endsAt: Date }
  struct Deadline: Decodable { let dueAt: Date }
  let generatedAt: Date
  let courses: [Course]
  let deadlines: [Deadline]
}
let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
// This must fail with the old decoder, proving the regression is reproduced.
let old = JSONDecoder()
old.dateDecodingStrategy = .iso8601
precondition((try? old.decode(Snapshot.self, from: data)) == nil)
let snapshot = try BnbuSnapshotCodec.makeDecoder().decode(Snapshot.self, from: data)
precondition(snapshot.courses[0].startsAt == snapshot.generatedAt)
precondition(abs(snapshot.courses[0].endsAt.timeIntervalSince(snapshot.generatedAt) - 3600) < 0.001)
precondition(abs(snapshot.deadlines[0].dueAt.timeIntervalSince(snapshot.generatedAt) - 7200) < 0.001)
print("PASS")
''');
      final binary = '${directory.path}/check';
      final compile = Process.runSync('xcrun', [
        'swiftc',
        'apple/BnbuSnapshotCodec.swift',
        source.path,
        '-o',
        binary,
      ]);
      expect(compile.exitCode, 0, reason: '${compile.stderr}');
      final run = Process.runSync(binary, [payload.path]);
      expect(run.exitCode, 0, reason: '${run.stderr}');
      expect(run.stdout, contains('PASS'));
    },
    skip: !Platform.isMacOS,
  );
}

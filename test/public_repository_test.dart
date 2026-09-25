import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repository contains only a server scope notice', () {
    expect(
      Directory('server')
          .listSync(recursive: true)
          .whereType<File>()
          .map((file) => file.path.replaceAll('\\', '/')),
      ['server/README.md'],
    );
    final result = Process.runSync('git', ['ls-files', '-z']);
    expect(result.exitCode, 0);
    final tracked = (result.stdout as String).split('\u0000');
    expect(tracked.any((p) => p.startsWith('.local/')), isFalse);
    expect(tracked.any((p) => p.startsWith('docs/history-session/')), isFalse);
  });

  test('public resource bundles contain no operational records', () {
    final directory = jsonDecode(
      File('assets/catalog/bnbu_directory.json').readAsStringSync(),
    );
    final reviews = jsonDecode(
      File('assets/catalog/teacher_review_references.json').readAsStringSync(),
    );
    expect(directory['organizations'], isEmpty);
    expect(reviews['references'], isEmpty);
    expect(File('assets/campus/official-map.jpg').existsSync(), isFalse);
  });
}

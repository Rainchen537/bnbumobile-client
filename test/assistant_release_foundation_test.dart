import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/services/academic_calendar_service.dart';
import 'package:bnbu_me/services/assistant/assistant_document_cache.dart';
import 'package:bnbu_me/services/assistant/assistant_local_navigation.dart';

void main() {
  final actions = AssistantActionType.values.toSet();
  test('fixed bilingual navigation has no ambiguous or compound matches', () {
    expect(
      AssistantLocalNavigation.parse('打开官方校历 PDF。', actions)?.targetId,
      'academic_calendar',
    );
    expect(
      AssistantLocalNavigation.parse(
        'Open the official Class Schedule PDF.',
        actions,
      )?.targetId,
      'class_schedule',
    );
    for (final input in [
      '不要打开校历',
      '打开校历并总结九月安排',
      '打开我刚才提到的页面',
      'Open the calendar and email',
      '请问校历在哪里',
      '打开 https://evil.example',
    ]) {
      expect(
        AssistantLocalNavigation.parse(input, actions),
        isNull,
        reason: input,
      );
    }
    expect(AssistantLocalNavigation.parse('打开官方校历 PDF', {}), isNull);
  });
  test(
    'protocol negotiation selects an intersection instead of assuming future SSE compatibility',
    () {
      final json = <String, dynamic>{
        'available': true,
        'model': 'fixture',
        'context_version': '6',
        'supported_context_versions': ['5', '6'],
        'context_sources': <String>[],
        'actions': <String>[],
        'stores_conversation_content': true,
        'purchase_api_available': false,
        'agent_protocol_version': 4,
        'supported_agent_protocol_versions': [3, 4],
      };
      final value = AssistantCapabilities.fromJson(json);
      expect(value.agentProtocolVersion, 3);
      expect(value.negotiatedContextVersion, '5');
      json['supported_agent_protocol_versions'] = [4];
      expect(() => AssistantCapabilities.fromJson(json), throwsFormatException);
    },
  );
  test(
    'requested PDF downloads once for concurrent readers and refreshes after TTL',
    () async {
      var now = DateTime.utc(2026, 9, 6);
      final paths = <String>[];
      final repo = OfficialAcademicCalendarRepository(
        cacheTtl: const Duration(minutes: 10),
        now: () => now,
        client: MockClient((r) async {
          paths.add(r.url.path);
          await Future<void>.delayed(const Duration(milliseconds: 5));
          if (r.url.path.endsWith('.htm')) {
            return http.Response(
              '''<a href="/attachment/file/a.pdf">Academic Calendar for S1 of AY2026-27.pdf</a><a href="/attachment/file/b.pdf">Class Schedule for S1 of AY2026-27.pdf</a>''',
              200,
            );
          }
          return http.Response.bytes(utf8.encode('%PDF-1.7 fixture'), 200);
        }),
      );
      await Future.wait(
        List.generate(
          8,
          (_) =>
              repo.loadDocument(AcademicCalendarDocumentKind.academicCalendar),
        ),
      );
      expect(paths.where((p) => p.endsWith('.pdf')), [
        '/attachment/file/a.pdf',
      ]);
      await repo.loadDocument(AcademicCalendarDocumentKind.academicCalendar);
      expect(paths.length, 2);
      now = now.add(const Duration(minutes: 11));
      await repo.loadDocument(AcademicCalendarDocumentKind.academicCalendar);
      expect(paths.length, 4);
    },
  );
  test(
    'text cache reuses content across pagination and never poisons a failed extraction',
    () async {
      var calls = 0;
      final gate = Completer<String>();
      final cache = AssistantDocumentTextCache(
        extract: (name, bytes) {
          calls++;
          return gate.future;
        },
      );
      final bytes = Uint8List.fromList([1, 2, 3]);
      final first = cache.read('calendar.pdf', bytes),
          second = cache.read('renamed.pdf', bytes);
      gate.complete('first page\nlast page');
      expect(await first, await second);
      expect(calls, 1);
      await cache.read('again.pdf', bytes);
      expect(calls, 1);
      var failures = 0;
      final retry = AssistantDocumentTextCache(
        extract: (name, bytes) async {
          if (failures++ == 0) throw StateError('parse');
          return 'ok';
        },
      );
      await expectLater(retry.read('x.pdf', bytes), throwsStateError);
      expect(await retry.read('x.pdf', bytes), 'ok');
    },
  );
}

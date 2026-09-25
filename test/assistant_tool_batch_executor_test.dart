import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/services/assistant/assistant_tool_batch_executor.dart';

void main() {
  test(
    'starts independent tool calls before waiting for either result',
    () async {
      const executor = AssistantToolBatchExecutor();
      final first = Completer<AssistantAgentToolResult>();
      final second = Completer<AssistantAgentToolResult>();
      final started = <String>[];
      const calls = [
        AssistantAgentToolCall(
          callId: 'first',
          name: 'get_courses',
          arguments: {},
        ),
        AssistantAgentToolCall(
          callId: 'second',
          name: 'get_schedule',
          arguments: {},
        ),
      ];

      final pending = executor.execute(
        calls: calls,
        executeOne: (call) {
          started.add(call.callId);
          return call.callId == 'first' ? first.future : second.future;
        },
      );

      expect(started, ['first', 'second']);
      second.complete(
        const AssistantAgentToolResult(
          callId: 'second',
          context: AssistantContextPayload(sources: {}),
        ),
      );
      first.complete(
        const AssistantAgentToolResult(
          callId: 'first',
          context: AssistantContextPayload(sources: {}),
        ),
      );

      final results = await pending;
      expect(results.map((result) => result.callId), ['first', 'second']);
    },
  );

  test('rejects duplicate call ids before starting any tool', () {
    const executor = AssistantToolBatchExecutor();
    var started = false;

    expect(
      () => executor.execute(
        calls: const [
          AssistantAgentToolCall(
            callId: 'same',
            name: 'get_courses',
            arguments: {},
          ),
          AssistantAgentToolCall(
            callId: 'same',
            name: 'get_schedule',
            arguments: {},
          ),
        ],
        executeOne: (_) {
          started = true;
          throw StateError('must not run');
        },
      ),
      throwsA(isA<AssistantToolBatchException>()),
    );
    expect(started, isFalse);
  });
}

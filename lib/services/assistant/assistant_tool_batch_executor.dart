import '../../models/assistant_models.dart';

class AssistantToolBatchExecutor {
  const AssistantToolBatchExecutor({this.maxCalls = 4});

  final int maxCalls;

  Future<List<AssistantAgentToolResult>> execute({
    required List<AssistantAgentToolCall> calls,
    required Future<AssistantAgentToolResult> Function(
      AssistantAgentToolCall call,
    )
    executeOne,
  }) {
    if (calls.isEmpty || calls.length > maxCalls) {
      throw const AssistantToolBatchException('小U客户端工具批次大小无效。');
    }
    final callIds = calls.map((call) => call.callId).toSet();
    if (callIds.length != calls.length) {
      throw const AssistantToolBatchException('小U客户端工具批次包含重复调用。');
    }
    return Future.wait(calls.map(executeOne));
  }
}

class AssistantToolBatchException implements Exception {
  const AssistantToolBatchException(this.message);

  final String message;

  @override
  String toString() => message;
}

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/assistant_models.dart';

/// An in-memory reference to the one module actually read in the preceding turn.
/// It carries names only; neither content, permission nor a write authorization
/// is reused. The controller owns one reference per conversation and account.
class AssistantIspaceFollowupReference {
  const AssistantIspaceFollowupReference({
    required this.courseName,
    required this.moduleName,
    required this.answerAt,
    required this.answerDigest,
  });

  final String courseName;
  final String moduleName;
  final DateTime answerAt;
  final String answerDigest;

  static AssistantIspaceFollowupReference? fromContext(
    AssistantContextPayload context, {
    required String answer,
    required DateTime answerAt,
  }) {
    final targets = {
      for (final result in context.ispaceToolResults)
        if (result.kind == 'module' &&
            result.userVisible &&
            result.moduleRef.isNotEmpty &&
            result.name.isNotEmpty &&
            result.courseName.isNotEmpty)
          result.moduleRef: result,
    };
    if (targets.length != 1) return null;
    final target = targets.values.single;
    return AssistantIspaceFollowupReference(
      courseName: target.courseName,
      moduleName: target.name,
      answerAt: answerAt,
      answerDigest: _digest(answer),
    );
  }

  AssistantIspaceFollowupReference afterAnswer(String answer, DateTime at) =>
      AssistantIspaceFollowupReference(
        courseName: courseName,
        moduleName: moduleName,
        answerAt: at,
        answerDigest: _digest(answer),
      );

  String? resolve(
    String message, {
    required String previousAnswer,
    required DateTime previousAnswerAt,
  }) {
    if (previousAnswerAt != answerAt ||
        _digest(previousAnswer) != answerDigest) {
      return null;
    }
    final normalized = message.toLowerCase();
    if (RegExp(
      r'\b(?:instead|switch)\b|'
      r'\b(?:another|different|other)\s+(?:form|quiz|questionnaire|module|activity|course)s?\b|'
      r'另一|另外|改为|换成',
    ).hasMatch(normalized)) {
      return null;
    }
    final followup =
        RegExp(
          r'\bcontinue\b|继续|接着|第\s*[0-9一二三四五六七八九十]+\s*题|'
          r'\bquestion\s*\d+\b|全部题目|所有题目',
        ).hasMatch(normalized) ||
        (RegExp(
              r'\b(?:it|its|that|this|these|those|same)\b|这份|这个|那个|刚才|前面',
            ).hasMatch(normalized) &&
            RegExp(
              r'\b(?:form|quiz|questionnaire|questions?|options?|answers?|module)\b|题目|选项|作答|问卷|回答',
            ).hasMatch(normalized));
    if (!followup) return null;
    final course = jsonEncode(courseName);
    final module = jsonEncode(moduleName);
    final hasChinese = RegExp(r'[\u3400-\u9fff]').hasMatch(message);
    final reference = hasChinese
        ? '本机前文指代：课程$course，活动$module。请重新核对内容和权限。'
        : 'App reference: course $course; activity $module. Recheck content and access.';
    final resolved = '$message\n\n$reference';
    return resolved.length <= 4000 ? resolved : null;
  }

  static String _digest(String value) =>
      sha256.convert(utf8.encode(value)).toString();
}

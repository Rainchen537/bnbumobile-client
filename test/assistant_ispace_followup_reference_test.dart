import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/services/assistant/assistant_ispace_followup_reference.dart';

void main() {
  final at = DateTime.utc(2026, 10, 1);
  const answer = 'There are two questions in this form.';
  AssistantIspaceToolResultContext result(String id) =>
      AssistantIspaceToolResultContext(
        resultKey: 'module:$id',
        kind: 'module',
        observedAt: at,
        courseId: '42',
        moduleRef: 'm1:42:$id:7:feedback',
        moduleId: id,
        instanceId: '7',
        moduleType: 'feedback',
        name: 'Workshop Reflection',
        courseName: 'Practice Hub',
        capabilities: const ['module_read'],
      );
  AssistantIspaceFollowupReference reference() =>
      AssistantIspaceFollowupReference.fromContext(
        AssistantContextPayload(
          sources: const {AssistantContextSource.ispaceToolResults},
          ispaceToolResults: [result('101')],
        ),
        answer: answer,
        answerAt: at,
      )!;

  for (final prompt in [
    '继续列出全部题目和选项',
    'Please continue beyond the module summary and read the actual form content.',
    'Help me answer question 2.',
    'Continue with my answers. For other comments, write: No other comments.',
  ]) {
    test('follow-up keeps the verified target: $prompt', () {
      final resolved = reference().resolve(
        prompt,
        previousAnswer: answer,
        previousAnswerAt: at,
      );
      expect(resolved, startsWith(prompt));
      expect(resolved, contains('"Workshop Reflection"'));
      expect(resolved, contains('"Practice Hub"'));
      expect(resolved, isNot(contains('m1:')));
      expect(resolved, isNot(contains('feedback_write')));
    });
  }

  test(
    'another topic or an explicitly different form receives no old target',
    () {
      for (final prompt in [
        'What is tomorrow weather?',
        'Read another form instead.',
        '换成另一份问卷继续回答',
        'Read the questions in Course Evaluation 2027.',
      ]) {
        expect(
          reference().resolve(
            prompt,
            previousAnswer: answer,
            previousAnswerAt: at,
          ),
          isNull,
        );
      }
    },
  );

  test('edited or replaced history invalidates the reference', () {
    expect(
      reference().resolve(
        '继续',
        previousAnswer: 'Changed answer',
        previousAnswerAt: at,
      ),
      isNull,
    );
    expect(
      reference().resolve(
        '继续',
        previousAnswer: answer,
        previousAnswerAt: at.add(const Duration(seconds: 1)),
      ),
      isNull,
    );
  });

  test(
    'comparison of multiple actual modules creates no implicit single target',
    () {
      final reference = AssistantIspaceFollowupReference.fromContext(
        AssistantContextPayload(
          sources: const {AssistantContextSource.ispaceToolResults},
          ispaceToolResults: [result('101'), result('102')],
        ),
        answer: answer,
        answerAt: at,
      );
      expect(reference, isNull);
    },
  );
}

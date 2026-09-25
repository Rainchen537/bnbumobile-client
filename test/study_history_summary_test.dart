import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/services/assistant_history_store.dart';
import 'package:bnbu_me/services/study_history_summary.dart';

void main() {
  const document = AssistantStudyDocument(
    key: 'quiz',
    title: 'Quiz.pdf',
    sourceUrl: 'https://ispace.example/quiz.pdf',
  );

  AssistantConversation conversation({
    required String id,
    required DateTime updatedAt,
    required String question,
    AssistantStudyDocument studyDocument = document,
  }) {
    return AssistantConversation(
      id: id,
      title: studyDocument.title,
      createdAt: updatedAt.subtract(const Duration(minutes: 1)),
      updatedAt: updatedAt,
      kind: AssistantConversationKind.study,
      studyDocument: studyDocument,
      messages: [
        AssistantStoredMessage(
          role: 'user',
          content: question,
          createdAt: updatedAt,
          studyContext: const AssistantStudyMessageContext(
            type: AssistantStudyEntryType.question,
            pages: [1],
            scope: 'current_page',
          ),
        ),
      ],
    );
  }

  test('study history uses the first question as its compact title', () {
    final item = conversation(
      id: 'one',
      updatedAt: DateTime.utc(2026, 8, 3, 12),
      question: '请逐项解释这道题目的每一个选项为什么成立',
    );

    expect(studyConversationDisplayTitle(item), '请逐项解释这道题目的每一个选项为什么成立');
  });

  test('study history keeps sessions ordered and documents deduplicated', () {
    final now = DateTime.utc(2026, 8, 3, 12);
    const secondDocument = AssistantStudyDocument(
      key: 'lecture',
      title: 'Lecture.pdf',
      sourceUrl: 'https://ispace.example/lecture.pdf',
    );
    final older = conversation(
      id: 'older',
      updatedAt: now.subtract(const Duration(hours: 2)),
      question: '旧问题',
    );
    final latest = conversation(
      id: 'latest',
      updatedAt: now.subtract(const Duration(minutes: 8)),
      question: '新问题',
    );
    final other = conversation(
      id: 'other',
      updatedAt: now.subtract(const Duration(minutes: 20)),
      question: '课件问题',
      studyDocument: secondDocument,
    );

    expect(
      studyQuestionConversationsForDocument([
        older,
        other,
        latest,
      ], document.key).map((item) => item.id),
      ['latest', 'older'],
    );
    expect(
      recentStudyDocuments([older, other, latest]).map((item) => item.id),
      ['latest', 'other'],
    );
    expect(studyRelativeTime(latest.updatedAt, now: now), '8 分钟前');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/pages/study_window_app.dart';
import 'package:bnbu_me/pages/study_workspace_page.dart';
import 'package:bnbu_me/services/assistant_history_store.dart';
import 'package:bnbu_me/services/study_window_manager.dart';

void main() {
  test('study workspace keeps one active browser-style document tab', () {
    const first = AssistantStudyDocument(
      key: 'first',
      title: 'Lecture 01.pdf',
      sourceUrl: 'https://ispace.example/lecture-01.pdf',
    );
    const second = AssistantStudyDocument(
      key: 'second',
      title: 'Lecture 02.pdf',
      sourceUrl: 'https://ispace.example/lecture-02.pdf',
    );
    final controller = StudyWorkspaceTabController([first]);
    addTearDown(controller.dispose);

    expect(controller.activeKey, first.key);
    controller.add(second);
    controller.add(second);
    expect(controller.documents, [first, second]);
    expect(controller.activeKey, second.key);

    controller.moveBefore(second.key, first.key);
    expect(controller.documents, [second, first]);
    expect(controller.activeKey, second.key);

    controller.activate(first.key);
    expect(controller.activeKey, first.key);

    controller.remove(first.key);
    expect(controller.documents, [second]);
    expect(controller.activeKey, second.key);
  });

  test('study window title follows the merged tab group on every desktop', () {
    const first = AssistantStudyDocument(
      key: 'first',
      title: 'Quiz 1.pdf',
      sourceUrl: 'https://ispace.example/quiz-1.pdf',
    );
    const second = AssistantStudyDocument(
      key: 'second',
      title: 'Quiz 2.pdf',
      sourceUrl: 'https://ispace.example/quiz-2.pdf',
    );
    const third = AssistantStudyDocument(
      key: 'third',
      title: 'Quiz 3.pdf',
      sourceUrl: 'https://ispace.example/quiz-3.pdf',
    );

    expect(studyWindowTitle(const []), '学业整理');
    expect(studyWindowTitle(const [first]), 'Quiz 1.pdf');
    expect(studyWindowTitle(const [first, second]), 'Quiz 1.pdf和Quiz 2.pdf');
    expect(
      studyWindowTitle(const [first, second, third]),
      'Quiz 1.pdf和Quiz 2.pdf和其他共3个页面',
    );
  });

  test('study window arguments restore only bounded document metadata', () {
    final documents = StudyWindowManager.decodeDocuments(
      '{"kind":"study","documents":[{"key":"abc","title":"Lecture 01.pdf","source_url":"https://ispace.example/lecture-01.pdf"}]}',
    );

    expect(documents, hasLength(1));
    expect(documents?.single.title, 'Lecture 01.pdf');
    expect(StudyWindowManager.decodeDocuments('{"kind":"main"}'), isNull);
  });

  test('organization progress does not appear as a pending question', () {
    final now = DateTime.utc(2026, 8, 3);
    final conversation = AssistantConversation(
      id: 'study-1',
      title: 'Quiz Answer',
      createdAt: now,
      updatedAt: now,
      kind: AssistantConversationKind.study,
      studyDocument: const AssistantStudyDocument(
        key: 'quiz',
        title: 'Quiz Answer',
        sourceUrl: 'https://ispace.example/quiz',
      ),
      messages: [
        AssistantStoredMessage(
          role: 'user',
          content: '上一条问题',
          createdAt: now,
          studyContext: const AssistantStudyMessageContext(
            type: AssistantStudyEntryType.question,
            pages: [1],
            scope: 'current_page',
          ),
        ),
        AssistantStoredMessage(
          role: 'user',
          content: '整理第 1 页',
          createdAt: now.add(const Duration(seconds: 1)),
          studyContext: const AssistantStudyMessageContext(
            type: AssistantStudyEntryType.organization,
            pages: [1],
            scope: 'current_page',
          ),
        ),
      ],
    );

    expect(
      isStudyQuestionPending(conversation, isConversationSending: true),
      isFalse,
    );
    expect(
      isStudyQuestionPending(
        conversation.copyWith(messages: [conversation.messages.first]),
        isConversationSending: true,
      ),
      isTrue,
    );
    expect(
      isStudyQuestionPending(
        conversation.copyWith(messages: [conversation.messages.first]),
        isConversationSending: false,
      ),
      isFalse,
    );
  });
}

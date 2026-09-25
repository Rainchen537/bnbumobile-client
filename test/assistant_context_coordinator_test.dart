import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/assistant_models.dart';
import 'package:bnbu_me/services/assistant_context_coordinator.dart';

void main() {
  test('latest route context wins and is removed on dispose', () {
    final coordinator = AssistantContextCoordinator();
    addTearDown(coordinator.dispose);
    final root = coordinator.register(
      AssistantContextContribution(
        currentPage: () =>
            const AssistantCurrentPageContext(pageType: 'mail', title: '邮箱'),
      ),
    );
    final detail = coordinator.register(
      AssistantContextContribution(
        currentPage: () => const AssistantCurrentPageContext(
          pageType: 'mail_detail',
          title: '邮件详情',
        ),
        selectedMail: () => AssistantSelectedMailContext(
          senderName: 'Teacher',
          senderEmail: 'teacher@bnbu.edu.cn',
          subject: 'Course',
          receivedAt: DateTime.utc(2026, 7, 21),
          bodyExcerpt: 'Body excerpt',
        ),
      ),
    );

    expect(coordinator.snapshot().currentPage?.pageType, 'mail_detail');
    expect(coordinator.snapshot().selectedMail?.bodyExcerpt, 'Body excerpt');

    detail.dispose();

    expect(coordinator.snapshot().currentPage?.pageType, 'mail');
    expect(coordinator.snapshot().selectedMail, isNull);
    root.dispose();
  });

  test('mail summaries are limited and provider failures are isolated', () {
    final coordinator = AssistantContextCoordinator();
    addTearDown(coordinator.dispose);
    coordinator.register(
      AssistantContextContribution(
        mailSummaries: () => List.generate(
          30,
          (index) => AssistantMailSummaryContext(
            senderName: 'Sender $index',
            senderEmail: 'sender$index@bnbu.edu.cn',
            subject: 'Subject $index',
            receivedAt: DateTime.utc(2026, 7, 21),
            preview: 'Preview',
          ),
        ),
      ),
    );
    coordinator.register(
      AssistantContextContribution(
        currentPage: () => throw StateError('route disposed'),
      ),
    );

    final snapshot = coordinator.snapshot();

    expect(snapshot.mailSummaries, hasLength(24));
    expect(snapshot.currentPage, isNull);
  });

  test(
    'mail summary loader can refresh and include draft mailbox items',
    () async {
      final coordinator = AssistantContextCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.register(
        AssistantContextContribution(
          mailSummaries: () => const [],
          loadMailSummaries: () async => [
            AssistantMailSummaryContext(
              uid: 19,
              folder: 'drafts',
              mailboxUidValidity: 812,
              senderName: 'Student',
              senderEmail: 'student@mail.bnbu.edu.cn',
              subject: 'Saved draft',
              receivedAt: DateTime.utc(2026, 8, 4),
              preview: 'Draft body',
            ),
          ],
        ),
      );

      expect(coordinator.canLoadMailSummaries, isTrue);
      final summaries = await coordinator.loadMailSummaries();

      expect(summaries, hasLength(1));
      expect(summaries.single.folder, 'drafts');
      expect(summaries.single.uid, 19);
    },
  );
}

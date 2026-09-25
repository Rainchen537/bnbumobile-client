import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/pages/mail_page.dart';
import 'package:bnbu_me/services/mail_attachment_store.dart';
import 'package:bnbu_me/widgets/native_html_mail_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import '../tool/mobile_mail_preview.dart';

void main() {
  testWidgets('Android HTML mail can return while its header is animating', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async {
        if (call.method == 'create') return 1;
        if (call.method == 'resize') {
          final arguments = call.arguments as Map;
          return {'width': arguments['width'], 'height': arguments['height']};
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      );
    });
    final fixture = MailReferenceFixture();
    addTearDown(fixture.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Inbox')),
      ),
    );
    navigator.currentState!.push<void>(
      MaterialPageRoute<void>(builder: (_) => fixture.detailPage()),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 8; i++) {
      tester
          .widget<NativeHtmlMailView>(find.byType(NativeHtmlMailView))
          .onCollapsedChanged!(i.isEven);
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.tap(find.byTooltip('返回邮箱'));
    await tester.pumpAndSettle();
    expect(find.text('Inbox'), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('short mail scroll settles and can return to the inbox', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final fixture = MailReferenceFixture();
    addTearDown(fixture.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Inbox')),
      ),
    );
    navigator.currentState!.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MailDetailPage(
          detail: MailMessageDetail(
            uid: 1,
            subject: 'Short scrollable message',
            sender: 'Office <office@example.test>',
            recipients: 'preview@example.test',
            cc: null,
            date: null,
            body: List.generate(29, (i) => 'Message line $i.').join('\n'),
            htmlBody: null,
            isSeen: true,
            folder: MailFolder.inbox,
            mailboxUidValidity: 100,
          ),
          timeFormat: DateFormat('yyyy-MM-dd HH:mm'),
          mailService: fixture.service,
          credentials: MailReferenceFixture.credentials,
          attachmentStore: const IoMailAttachmentStore(),
          senderAvatarService: fixture.avatar,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final body = find.byKey(const ValueKey('mail-detail-plain-scroll'));
    final controller = tester.widget<SingleChildScrollView>(body).controller!;
    // This message only just overflows while its sender header is visible.
    expect(controller.position.maxScrollExtent, greaterThan(18));
    expect(controller.position.maxScrollExtent, lessThan(100));
    await tester.drag(body, const Offset(0, -60));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('返回邮箱'));
    await tester.pumpAndSettle();
    expect(find.text('Inbox'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

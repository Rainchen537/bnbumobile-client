import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/mail_models.dart';
import 'package:bnbu_me/models/mail_radar_models.dart';
import 'package:bnbu_me/l10n/bnbu_localizations.dart';
import 'package:bnbu_me/services/mail_service.dart';
import 'package:bnbu_me/widgets/mail_message_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tool/mobile_mail_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Use the host's system face only for local visual QA, never bundle it.
    final faces = [
      File('/System/Library/Fonts/SFNS.ttf'),
      File(
        '/System/Library/AssetsV2/com_apple_MobileAsset_Font7/3419f2a427639ad8c8e139149a287865a90fa17e.asset/AssetData/PingFang.ttc',
      ),
    ];
    for (final face in faces) {
      if (await face.exists()) {
        final loader = FontLoader('Roboto')
          ..addFont(
            Future.value(ByteData.sublistView(await face.readAsBytes())),
          );
        await loader.load();
      }
    }
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    for (final family in manifest.whereType<Map>()) {
      if (!(family['family'] as String).contains('lucide') &&
          family['family'] != 'MaterialIcons' &&
          !(family['family'] as String).contains('simple_icons')) {
        continue;
      }
      final loader = FontLoader(family['family'] as String);
      for (final font in family['fonts'] as List) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  Future<MailReferenceFixture> launch(
    WidgetTester tester, {
    bool detail = false,
    bool compose = false,
    bool light = false,
    Size size = const Size(402, 874),
    Locale locale = const Locale('zh', 'CN'),
    double textScale = 1,
    ReferenceMailService? mailService,
  }) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 62, bottom: 34);
    addTearDown(tester.view.reset);
    final fixture = MailReferenceFixture(
      now: DateTime.now(),
      mailService: mailService,
    );
    await fixture.initialize();
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('mail-reference-boundary'),
        child: MailReferencePreviewApp(
          fixture: fixture,
          detail: detail,
          compose: compose,
          light: light,
          locale: locale,
          textScale: textScale,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fixture;
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('mail-reference-boundary')),
      );
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('build/mail-reference');
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'compose follows the reference canvas and keyboard toolbar in both themes',
    (tester) async {
      for (final light in [true, false]) {
        await launch(tester, compose: true, light: light);
        tester.view.viewInsets = const FakeViewPadding(bottom: 336);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final toolbar = tester.getRect(
          find.byKey(const ValueKey('compose-editor-toolbar')),
        );
        expect(toolbar.bottom, closeTo(874 - 336, 1));
        expect(find.text('0 个附件'), findsNothing);
        expect(tester.getCenter(find.text('新建邮件')).dx, closeTo(201, .1));
        await capture(
          tester,
          light ? 'compose-next-light' : 'compose-next-dark',
        );
        await tester.pumpWidget(const SizedBox());
        tester.view.viewInsets = const FakeViewPadding();
      }
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'continuous rows retain previews, and selection retains avatars while replacing root navigation',
    (tester) async {
      await launch(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(MailMessageRow), findsWidgets);
      expect(find.textContaining('Dear students'), findsWidgets);
      await capture(tester, 'inbox-dark');
      await tester.tap(find.text('多选'));
      await tester.pumpAndSettle();
      expect(find.text('选择邮件'), findsOneWidget);
      expect(find.text('全选'), findsOneWidget);
      final row = tester.widget<MailMessageRow>(
        find.byType(MailMessageRow).first,
      );
      expect(row.selectionMode, isTrue);
      expect(find.byKey(const ValueKey('mail-compose-action')), findsNothing);
      expect(find.text('拒收'), findsNothing);
      await capture(tester, 'selection-dark');
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mail-compose-action')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  for (final width in [390.0, 1440.0]) {
    testWidgets('legacy in-memory preview is readable at $width', (
      tester,
    ) async {
      final service = ReferenceMailService(DateTime.now());
      service.messages[0] = service.messages[0].copyWith(
        preview: '各位同学： &nbsp; A&amp;B &#x1F600;',
      );
      await launch(tester, size: Size(width, 900), mailService: service);
      await tester.pumpAndSettle();
      expect(find.text('各位同学： A&B 😀'), findsOneWidget);
      expect(find.textContaining('&nbsp;'), findsNothing);
      expect(find.textContaining('&amp;'), findsNothing);
      expect(service.mutations, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets(
    'left swipe marks the actual message and opening another row closes the first actions',
    (tester) async {
      final fixture = await launch(tester);
      await tester.drag(
        find.byType(MailMessageRow).first,
        const Offset(-220, 0),
      );
      await tester.pumpAndSettle();
      expect(find.text('标为已读'), findsOneWidget);
      await capture(tester, 'swipe-dark');
      await tester.tap(find.text('标为已读'));
      await tester.pumpAndSettle();
      expect(
        fixture.service.messages
            .firstWhere(
              (message) =>
                  message.uid == 1 && message.folder == MailFolder.inbox,
            )
            .isSeen,
        isTrue,
      );
      expect(fixture.service.mutations, contains('seen:true'));
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'folder menu omits retired topics and sent has disabled unread filter',
    (tester) async {
      await launch(tester);
      await tester.tap(find.byKey(const ValueKey('mail-folder-selector')));
      await tester.pumpAndSettle();
      for (final label in ['星标邮件', '垃圾邮件']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('话题'), findsNothing);
      await capture(tester, 'folder-menu-dark');
      await tester.tap(find.text('已发送'));
      await tester.pumpAndSettle();
      final unreadButton = tester.widget<TextButton>(
        find.ancestor(of: find.text('未读'), matching: find.byType(TextButton)),
      );
      expect(unreadButton.onPressed, isNull);
      await capture(tester, 'sent-dark');
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'selection waits for all pages even when the first page is checked',
    (tester) async {
      final service = _DelayedPagedMailService();
      addTearDown(service.releasePage);
      await launch(tester, mailService: service);
      await tester.tap(find.text('多选'));
      await tester.pumpAndSettle();
      for (var index = 0; index < 2; index++) {
        await tester.tap(find.byType(MailMessageRow).at(index));
        await tester.pump();
      }
      expect(find.text('全选'), findsOneWidget);
      expect(find.text('取消全选'), findsNothing);
      await tester.tap(find.text('全选'));
      await tester.pump();
      final selectAll = tester.widget<TextButton>(
        find.ancestor(of: find.text('全选'), matching: find.byType(TextButton)),
      );
      final delete = tester.widget<TextButton>(
        find.ancestor(of: find.text('删除'), matching: find.byType(TextButton)),
      );
      expect(selectAll.onPressed, isNull);
      expect(delete.onPressed, isNull);
      service.releasePage();
      await tester.pumpAndSettle();
      final rows = tester.widgetList<MailMessageRow>(
        find.byType(MailMessageRow),
      );
      expect(rows.length, 3);
      expect(rows.every((row) => row.selected), isTrue);
      expect(find.text('取消全选'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('cancelling select all ignores a late mailbox page', (
    tester,
  ) async {
    final service = _DelayedPagedMailService();
    addTearDown(service.releasePage);
    await launch(tester, mailService: service);
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全选'));
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pump();
    service.releasePage();
    await tester.pumpAndSettle();
    expect(find.text('选择邮件'), findsNothing);
    await tester.tap(find.text('多选'));
    await tester.pumpAndSettle();
    final rows = tester.widgetList<MailMessageRow>(find.byType(MailMessageRow));
    expect(rows.every((row) => !row.selected), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('radar uses mail rows only after a range is enabled', (
    tester,
  ) async {
    final fixture = await launch(tester);
    expect(find.byKey(const ValueKey('mail-radar-mobile-tile')), findsNothing);
    await fixture.radar.setRangeChoice(30);
    await tester.pumpAndSettle();
    await tester.tap(find.text('邮件雷达'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final first = tester.widget<MailMessageRow>(
      find.byType(MailMessageRow).first,
    );
    expect(first.tags.map((tag) => tag.label), contains('截止事项'));
    expect(find.byType(Switch), findsNothing);
    await capture(tester, 'radar-dark');
    expect(find.text('不使用'), findsNothing);
    expect(find.text('7 天'), findsNothing);
    await fixture.radar.setRangeChoice(0);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mail-radar-mobile-tile')), findsNothing);
    expect(find.byKey(const ValueKey('mail-radar-scroll')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('radar rows open the original reader without an analysis panel', (
    tester,
  ) async {
    final fixture = await launch(tester);
    await fixture.radar.setRangeChoice(30);
    await tester.pumpAndSettle();
    await tester.tap(find.text('邮件雷达'));
    await tester.pumpAndSettle();
    final row = tester.widget<MailMessageRow>(
      find.byType(MailMessageRow).first,
    );
    await tester.tap(find.byKey(ValueKey(row.message.identityKey)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mail-detail-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('mail-radar-detail-modal')), findsNothing);
    expect(find.text('小U摘要'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'radar mark complete retains exclusion semantics and read state',
    (tester) async {
      final fixture = await launch(tester);
      await fixture.radar.setRangeChoice(30);
      await tester.pumpAndSettle();
      await tester.tap(find.text('邮件雷达'));
      await tester.pumpAndSettle();
      final row = tester.widget<MailMessageRow>(
        find.byType(MailMessageRow).first,
      );
      final before = fixture.radar.items.firstWhere(
        (item) => item.toSummary().identityKey == row.message.identityKey,
      );
      expect(row.swipeActions.map((action) => action.label), contains('标记完成'));
      expect(
        row.swipeActions.map((action) => action.label),
        isNot(contains('无需雷达')),
      );
      row.swipeActions
          .singleWhere((action) => action.label == '标记完成')
          .onPressed!();
      await tester.pumpAndSettle();
      final after = fixture.radar.items.firstWhere(
        (item) => item.key == before.key,
      );
      expect(after.membership, MailRadarMembership.excluded);
      expect(after.originalIsSeen, before.originalIsSeen);
      expect(
        fixture.radar.visibleItems.any((item) => item.key == before.key),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('reader disclosure reorganizes sender address and recipients', (
    tester,
  ) async {
    await launch(tester, detail: true);
    expect(find.text('外部'), findsNothing);
    await capture(tester, 'reader-dark-fallback');
    await tester.tap(find.byKey(const ValueKey('mail-recipient-expand')));
    await tester.pumpAndSettle();
    expect(find.text('student.services@example.test'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mail-recipient-collapse')),
      findsOneWidget,
    );
    await capture(tester, 'reader-expanded-dark-fallback');
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('light layout preserves the same row structure', (tester) async {
    await launch(tester, light: true);
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<MailMessageRow>(find.byType(MailMessageRow).first)
          .selectionMode,
      isFalse,
    );
    await capture(tester, 'inbox-light');
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets(
    'wide compose stays in reading pane and preserves mailbox across resize',
    (tester) async {
      await launch(tester, size: const Size(1440, 1000), light: true);
      await tester.tap(find.text('新建邮件'));
      await tester.pumpAndSettle();
      final list = find.byKey(const ValueKey('mail-desktop-message-list'));
      final editor = find.byKey(const ValueKey('compose-desktop-workspace'));
      expect(list, findsOneWidget);
      expect(
        find.byKey(const ValueKey('root-side-navigation-panel')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mail-desktop-folder-pane')),
        findsOneWidget,
      );
      expect(
        tester.getRect(editor).left,
        greaterThanOrEqualTo(tester.getRect(list).right),
      );
      await capture(tester, 'desktop-compose-right-pane-20260914');
      await tester.enterText(
        find.byKey(const ValueKey('compose-subject-field')),
        'Preserved draft',
      );
      await tester.pump();
      tester.view.physicalSize = const Size(390, 1000);
      await tester.pumpAndSettle();
      expect(find.text('Preserved draft'), findsOneWidget);
      tester.view.physicalSize = const Size(1440, 1000);
      await tester.pumpAndSettle();
      expect(find.text('Preserved draft'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('compose-close')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('compose-exit-discard')));
      await tester.pumpAndSettle();
      expect(editor, findsNothing);
      expect(list, findsOneWidget);
      expect(
        find.byKey(const ValueKey('root-side-navigation-panel')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('navigation and mailbox columns reflow at 390, 900 and 1440', (
    tester,
  ) async {
    for (final width in [390.0, 900.0, 1440.0]) {
      await launch(tester, size: Size(width, 900));
      expect(
        find.byKey(const ValueKey('root-bottom-navigation')),
        width < 700 ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('root-side-navigation-panel')),
        width >= 700 ? findsOneWidget : findsNothing,
      );
      expect(
        find.byKey(const ValueKey('mail-desktop-workspace')),
        width >= 1440 ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'desktop keeps list and reading panes for folders, stars and radar',
    (tester) async {
      final fixture = await launch(tester, size: const Size(1440, 900));
      expect(
        tester
            .getSize(find.byKey(const ValueKey('mail-desktop-folder-pane')))
            .width,
        closeTo(171.6, .01),
      );
      expect(
        find.byKey(const ValueKey('mail-desktop-message-list')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mail-desktop-account')),
        findsOneWidget,
      );
      expect(find.text('仅看未读'), findsNothing);
      expect(
        tester
            .getSize(find.byKey(const ValueKey('mail-desktop-status')))
            .height,
        34,
      );

      await tester.tap(find.byKey(const ValueKey('mail-desktop-row-1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mail-desktop-reading-pane')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mail-desktop-reading-title')),
        findsOneWidget,
      );
      await capture(tester, 'desktop-workspace-v4');
      final selectedTitle = tester
          .widget<Text>(
            find.byKey(const ValueKey('mail-desktop-reading-title')),
          )
          .data;

      await tester.tap(find.byKey(const ValueKey('mail-desktop-result-menu')));
      await tester.pumpAndSettle();
      for (final label in ['全部', '未读', '由新到旧', '由旧到新']) {
        expect(find.text(label), findsWidgets);
      }
      await capture(tester, 'desktop-result-menu-unified');
      await tester.tap(find.text('由旧到新').last);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('mail-desktop-reading-title')),
            )
            .data,
        selectedTitle,
      );

      await fixture.radar.setRangeChoice(30);
      await tester.pumpAndSettle();
      await tester.tap(find.text('邮件雷达').last);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mail-desktop-message-list')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('mail-desktop-row-1')), findsOneWidget);
      expect(find.text('紧急'), findsOneWidget);
      expect(find.text('截止事项'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('mail-desktop-row-1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mail-desktop-reading-pane')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mail-desktop-reading-title')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('mail-detail-page')), findsNothing);
      await capture(tester, 'desktop-radar-workspace-v4');
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'desktop detail disclosure keeps metadata separate from actions',
    (tester) async {
      await launch(tester, size: const Size(1440, 900));
      await tester.tap(find.byKey(const ValueKey('mail-desktop-row-1')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mail-desktop-show-details')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('mail-desktop-show-details')));
      await tester.pumpAndSettle();
      expect(find.text('发件人'), findsOneWidget);
      expect(find.text('收件人'), findsOneWidget);
      expect(find.text('时间'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mail-desktop-hide-details')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'compact newest inbox stays bounded while a wide workspace requests the complete date index',
    (tester) async {
      final compactService = _SortedDispatchMailService();
      await launch(
        tester,
        size: const Size(390, 844),
        mailService: compactService,
      );
      expect(compactService.filteredFetches, greaterThan(0));
      expect(compactService.sortedFetches, 0);
      await tester.pumpWidget(const SizedBox.shrink());

      final wideService = _SortedDispatchMailService();
      await launch(
        tester,
        size: const Size(1440, 900),
        mailService: wideService,
      );
      expect(wideService.sortedFetches, greaterThan(0));
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    '320px large text and English or Traditional Chinese keep mail actions reachable',
    (tester) async {
      for (final locale in [
        const Locale('en'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      ]) {
        await launch(
          tester,
          size: const Size(320, 874),
          locale: locale,
          textScale: 1.6,
        );
        final l10n = BnbuLocalizations.of(
          tester.element(find.byType(MailMessageRow).first),
        );
        await tester.tap(find.text(l10n.text('多选')));
        await tester.pumpAndSettle();
        expect(find.text(l10n.text('移动')).hitTestable(), findsOneWidget);
        await tester.tap(find.text(l10n.text('全选')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(l10n.text('完成')));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('mail-radar-mobile-tile')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
      debugDefaultTargetPlatformOverride = null;
    },
  );
}

class _SortedDispatchMailService extends ReferenceMailService
    implements MailSortedFolderReader {
  _SortedDispatchMailService() : super(DateTime.now());

  int filteredFetches = 0;
  int sortedFetches = 0;

  @override
  Future<MailFolderSnapshot> fetchFilteredFolder({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    bool unreadOnly = false,
    bool flaggedOnly = false,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) {
    filteredFetches += 1;
    return super.fetchFilteredFolder(
      credentials: credentials,
      folder: folder,
      unreadOnly: unreadOnly,
      flaggedOnly: flaggedOnly,
      page: page,
      pageSize: pageSize,
      expectedMailboxUidValidity: expectedMailboxUidValidity,
    );
  }

  @override
  Future<MailFolderSnapshot> fetchSortedFolder({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required MailSortOrder sortOrder,
    bool unreadOnly = false,
    bool flaggedOnly = false,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) {
    sortedFetches += 1;
    return super.fetchFilteredFolder(
      credentials: credentials,
      folder: folder,
      unreadOnly: unreadOnly,
      flaggedOnly: flaggedOnly,
      page: page,
      pageSize: pageSize,
      expectedMailboxUidValidity: expectedMailboxUidValidity,
    );
  }

  @override
  Future<MailFolderSnapshot?> readCachedSortedFolder({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    required MailSortOrder sortOrder,
    bool unreadOnly = false,
    bool flaggedOnly = false,
    int page = 1,
    int pageSize = 25,
  }) async => null;
}

class _DelayedPagedMailService extends ReferenceMailService {
  _DelayedPagedMailService() : super(DateTime.now()) {
    messages.removeWhere(
      (message) =>
          message.uid > 3 ||
          (message.folder != MailFolder.inbox &&
              message.folder != MailFolder.sent),
    );
  }
  final _secondPage = Completer<void>();
  bool failSecondPage = false;
  void releasePage() {
    if (!_secondPage.isCompleted) _secondPage.complete();
  }

  @override
  Future<MailFolderSnapshot> fetchFilteredFolder({
    required MailAccessCredentials credentials,
    required MailFolder folder,
    bool unreadOnly = false,
    bool flaggedOnly = false,
    int page = 1,
    int pageSize = 25,
    int? expectedMailboxUidValidity,
  }) async {
    if (page == 2 && folder == MailFolder.inbox) {
      await _secondPage.future;
      if (failSecondPage) throw StateError('Synthetic page unavailable');
    }
    return super.fetchFilteredFolder(
      credentials: credentials,
      folder: folder,
      unreadOnly: unreadOnly,
      flaggedOnly: flaggedOnly,
      page: page,
      pageSize: 2,
      expectedMailboxUidValidity: expectedMailboxUidValidity,
    );
  }
}

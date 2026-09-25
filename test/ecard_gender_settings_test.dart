import 'dart:async';
import 'package:bnbu_me/models/ecard_gender_preferences.dart';
import 'package:bnbu_me/models/portal_account_profile.dart';
import 'package:bnbu_me/pages/student_ecard_page.dart';
import 'package:bnbu_me/pages/user_page.dart';
import 'package:bnbu_me/widgets/ecard_gender_settings_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bnbu_me/services/ecard_gender_store.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/ecard_gender_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Lease implements AppSessionLease {
  _Lease(this.owner);
  @override
  final String owner;
  @override
  bool isActive = true;
}

class _Session extends AppSessionController {
  var lease = _Lease('2099000001');
  @override
  bool get isLoggedIn => lease.isActive;
  @override
  String? get username => lease.owner;
  @override
  AppSessionLease? captureSessionLease() => lease.isActive ? lease : null;
  @override
  PortalAccountProfile get portalProfile => const PortalAccountProfile(
    fullName: '测试同学 TEST STUDENT',
    chineseName: '测试同学',
    englishName: 'TEST STUDENT',
    identity: 'Student',
    organization: 'Student',
    department: '',
    college: 'FST',
    avatarPath: '',
    gender: 'male',
  );
  void switchTo(String owner) {
    lease.isActive = false;
    lease = _Lease(owner);
    notifyListeners();
  }
}

class _Store extends EcardGenderStore {
  final values = <String, EcardGenderPreferences>{};
  Completer<EcardGenderPreferences>? pendingRead;
  Completer<void>? pendingWrite;
  bool failRead = false;
  bool failWrite = false;
  int writes = 0;
  @override
  Future<EcardGenderPreferences> read(String owner) async {
    if (failRead) throw StateError('Synthetic read failure');
    if (pendingRead != null) return pendingRead!.future;
    return values[owner] ?? const EcardGenderPreferences();
  }

  @override
  Future<void> save(
    String owner,
    EcardGenderPreferences value, {
    required bool Function() isCurrent,
  }) async {
    writes++;
    await pendingWrite?.future;
    if (!isCurrent()) throw StateError('Expired fixture lease');
    if (failWrite) throw StateError('Synthetic write failure');
    values[owner] = value;
    notifyListeners();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<(_Session, _Store)> mount(
    WidgetTester tester, {
    double width = 390,
    double scale = 1,
    Locale locale = const Locale('zh'),
    bool dark = false,
    _Store? store,
    bool userSettings = false,
    TargetPlatform platform = TargetPlatform.iOS,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = _Session();
    final actual = store ?? _Store();
    addTearDown(session.dispose);
    addTearDown(actual.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: (dark ? AppTheme.dark : AppTheme.light).copyWith(
          platform: platform,
        ),
        locale: locale,
        supportedLocales: BnbuLocalizations.supportedLocales,
        localizationsDelegates: const [
          BnbuLocalizations.delegate,
          ...GlobalMaterialLocalizations.delegates,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: userSettings
            ? UserPage(controller: session, ecardGenderStore: actual)
            : Column(
                children: [
                  Expanded(
                    child: StudentEcardPage(
                      controller: session,
                      onGoToUser: () {},
                      genderStore: actual,
                    ),
                  ),
                  Material(
                    child: EcardGenderSettingsEntry(
                      controller: session,
                      store: actual,
                    ),
                  ),
                ],
              ),
      ),
    );
    await tester.pumpAndSettle();
    return (session, actual);
  }

  Future<void> open(WidgetTester tester, {bool english = false}) async {
    await tester.tap(find.byKey(const ValueKey('ecard-gender-settings-entry')));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String key) async {
    if (key == 'hidden') {
      final toggle = find.byKey(const ValueKey('ecard-gender-visible-switch'));
      await tester.ensureVisible(toggle);
      if (tester.widget<SwitchListTile>(toggle).value) {
        await tester.tap(toggle);
        await tester.pumpAndSettle();
      }
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      return;
    }
    final target = find.byKey(ValueKey('ecard-gender-$key'));
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> closeEditor(WidgetTester tester) async {
    // Closing is navigation only: choices already save, text is flushed on exit.
    expect(find.byKey(const ValueKey('ecard-gender-save')), findsNothing);
    await tester.tap(
      find
          .descendant(
            of: find.byType(EcardGenderSettings),
            matching: find.byType(IconButton),
          )
          .first,
    );
    await tester.pumpAndSettle();
  }

  String? selectedGender(WidgetTester tester) => tester
      .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
      .groupValue;

  bool displaysGender(WidgetTester tester) => tester
      .widget<SwitchListTile>(
        find.byKey(const ValueKey('ecard-gender-visible-switch')),
      )
      .value;

  testWidgets('ecard menu no longer exposes gender settings', (tester) async {
    await mount(tester);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('student-ecard-gender-settings-menu')),
      findsNothing,
    );
    expect(find.text('性别显示').hitTestable(), findsNothing);
    expect(find.text('刷新'), findsOneWidget);
  });

  for (final width in [390.0, 900.0, 1440.0]) {
    testWidgets('private settings route is nested and defaults on at $width', (
      tester,
    ) async {
      final (_, store) = await mount(tester, width: width, userSettings: true);
      expect(
        find.byKey(const ValueKey('ecard-gender-settings-entry')),
        findsNothing,
      );
      final account = find.text('账户与安全');
      await tester.ensureVisible(account);
      await tester.tap(account);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('ecard-gender-settings-entry')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('personal-profile-display-setting')),
      );
      await tester.pumpAndSettle();
      await open(tester);
      expect(displaysGender(tester), isTrue);
      expect(selectedGender(tester), 'man');
      expect(store.writes, 0);
      await choose(tester, 'hidden');
      await closeEditor(tester);
      expect(store.values.values.single.visible, isFalse);
      await open(tester);
      expect(displaysGender(tester), isFalse);
      await closeEditor(tester);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'desktop account settings do not expose a mobile eCard preference',
    (tester) async {
      await mount(
        tester,
        width: 1200,
        userSettings: true,
        platform: TargetPlatform.macOS,
      );
      await tester.tap(find.text('账户与安全'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('personal-profile-display-setting')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('ecard-gender-settings-entry')),
        findsNothing,
      );
    },
  );

  testWidgets('hidden preference keeps the selection and edits stay hidden', (
    tester,
  ) async {
    final store = _Store();
    store.values['2099000001'] = const EcardGenderPreferences(
      visible: false,
      choice: EcardGenderChoice.transMan,
    );
    await mount(tester, store: store);
    await open(tester);
    expect(selectedGender(tester), 'transMan');
    expect(displaysGender(tester), isFalse);
    await choose(tester, 'nonBinary');
    expect(selectedGender(tester), 'nonBinary');
    expect(displaysGender(tester), isFalse);
    await closeEditor(tester);
    expect(store.values.values.single.choice, EcardGenderChoice.nonBinary);
    expect(store.values.values.single.visible, isFalse);
    expect(find.byKey(const ValueKey('student-ecard-gender')), findsNothing);
    final data = tester
        .widget<StudentEcardView>(find.byType(StudentEcardView))
        .data;
    expect(data.walletCard().toWire(null).containsKey('gender'), isFalse);
    await open(tester);
    expect(selectedGender(tester), 'nonBinary');
    expect(displaysGender(tester), isFalse);
    await tester.tap(find.byKey(const ValueKey('ecard-gender-visible-switch')));
    await closeEditor(tester);
    expect(find.text('非二元性别／性别流动 / Non-binary / Genderfluid'), findsOneWidget);
  });

  testWidgets(
    'hidden preference exposes custom text without revealing the card',
    (tester) async {
      final store = _Store();
      store.values['2099000001'] = const EcardGenderPreferences(
        visible: false,
        choice: EcardGenderChoice.selfDescribe,
        custom: 'Synthetic original',
      );
      await mount(tester, store: store);
      await open(tester);
      expect(selectedGender(tester), 'selfDescribe');
      final input = find.byKey(const ValueKey('ecard-gender-custom'));
      expect(input, findsOneWidget);
      await tester.ensureVisible(input);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Synthetic original',
      );
      await tester.enterText(input, 'Synthetic cancelled');
      await tester.tap(
        find.descendant(
          of: find.byType(EcardGenderSettings),
          matching: find.byTooltip('关闭'),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.values.values.single.custom, 'Synthetic cancelled');
      await open(tester);
      await tester.ensureVisible(input);
      await tester.enterText(input, 'Synthetic updated');
      expect(displaysGender(tester), isFalse);
      await closeEditor(tester);
      expect(store.values.values.single.custom, 'Synthetic updated');
      expect(store.values.values.single.visible, isFalse);
      expect(find.byKey(const ValueKey('student-ecard-gender')), findsNothing);
      await open(tester);
      expect(
        tester.widget<TextField>(input).controller!.text,
        'Synthetic updated',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('ecard-gender-visible-switch')),
      );
      await tester.tap(
        find.byKey(const ValueKey('ecard-gender-visible-switch')),
      );
      await closeEditor(tester);
      expect(find.text('Synthetic updated'), findsOneWidget);
    },
  );

  testWidgets(
    'hidden preference still shows the known school choice in settings',
    (tester) async {
      final store = _Store();
      store.values['2099000001'] = const EcardGenderPreferences(visible: false);
      await mount(tester, store: store);
      await open(tester);
      expect(selectedGender(tester), 'man');
      expect(displaysGender(tester), isFalse);
      await closeEditor(tester);
      expect(store.values.values.single.choice, isNull);
      expect(store.values.values.single.visible, isFalse);
    },
  );

  testWidgets('only ellipsis opens editor; choices save without confirmation', (
    tester,
  ) async {
    final (_, store) = await mount(tester);
    expect(find.byType(SwitchListTile), findsNothing);
    await tester.tap(find.byKey(const ValueKey('student-ecard-gender')));
    await tester.pumpAndSettle();
    expect(find.byType(EcardGenderSettings), findsNothing);
    await open(tester);
    expect(find.byType(RadioListTile<String>), findsNWidgets(6));
    expect(find.byType(SwitchListTile), findsOneWidget);
    await choose(tester, 'transWoman');
    expect(store.writes, 1);
    expect(store.values.values.single.choice, EcardGenderChoice.transWoman);
    expect(find.byKey(const ValueKey('ecard-gender-save')), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(EcardGenderSettings),
        matching: find.byTooltip('关闭'),
      ),
    );
    await tester.pumpAndSettle();
    expect(store.writes, 1);
    expect(find.text('跨性别女性 / Trans woman'), findsOneWidget);
  });

  testWidgets(
    'selected display and hidden state persist without modifying school source',
    (tester) async {
      final (session, store) = await mount(tester);
      await open(tester);
      await choose(tester, 'nonBinary');
      await closeEditor(tester);
      expect(
        find.text('非二元性别／性别流动 / Non-binary / Genderfluid'),
        findsOneWidget,
      );
      expect(session.portalProfile.gender, 'male');
      await open(tester);
      await choose(tester, 'hidden');
      await closeEditor(tester);
      expect(find.byKey(const ValueKey('student-ecard-gender')), findsNothing);
      final data = tester
          .widget<StudentEcardView>(find.byType(StudentEcardView))
          .data;
      expect(data.walletCard().toWire(null).containsKey('gender'), isFalse);
      expect(
        find.byKey(const ValueKey('student-ecard-student-id')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('student-ecard-barcode')),
        findsOneWidget,
      );
      expect(store.values[session.lease.owner]!.visible, isFalse);
      await open(tester);
      expect(selectedGender(tester), 'nonBinary');
      expect(displaysGender(tester), isFalse);
      await tester.tap(
        find.byKey(const ValueKey('ecard-gender-visible-switch')),
      );
      await tester.pumpAndSettle();
      await closeEditor(tester);
      expect(
        find.text('非二元性别／性别流动 / Non-binary / Genderfluid'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'custom text autosaves after debounce and failed save can retry',
    (tester) async {
      final (_, store) = await mount(tester);
      await open(tester);
      await choose(tester, 'selfDescribe');
      expect(find.byKey(const ValueKey('ecard-gender-error')), findsOneWidget);
      final input = find.byKey(const ValueKey('ecard-gender-custom'));
      await tester.ensureVisible(input);
      await tester.enterText(input, 'Synthetic identity');
      store.failWrite = true;
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(find.text('本机保存失败，请重试'), findsOneWidget);
      expect(find.byType(EcardGenderSettings), findsOneWidget);
      expect(store.values, isEmpty);
      store.failWrite = false;
      await tester.tap(find.byKey(const ValueKey('ecard-gender-retry')));
      await tester.pumpAndSettle();
      expect(store.values.values.single.custom, 'Synthetic identity');
      await closeEditor(tester);
      expect(find.text('Synthetic identity'), findsOneWidget);
    },
  );

  testWidgets('hide remains possible with unfinished invalid custom draft', (
    tester,
  ) async {
    final (_, store) = await mount(tester);
    await open(tester);
    await choose(tester, 'selfDescribe');
    final input = find.byKey(const ValueKey('ecard-gender-custom'));
    await tester.ensureVisible(input);
    await tester.enterText(input, 'x' * 41);
    await choose(tester, 'hidden');
    await closeEditor(tester);
    expect(store.values.values.single.visible, isFalse);
    expect(find.byKey(const ValueKey('student-ecard-gender')), findsNothing);
  });

  testWidgets(
    'loading, read failure and late old-account result never reveal old gender',
    (tester) async {
      final store = _Store()..pendingRead = Completer<EcardGenderPreferences>();
      final (session, _) = await mount(tester, store: store);
      expect(find.byKey(const ValueKey('student-ecard-gender')), findsNothing);
      final oldRead = store.pendingRead!;
      store.pendingRead = null;
      store.values['2099000002'] = const EcardGenderPreferences(visible: false);
      session.switchTo('2099000002');
      await tester.pumpAndSettle();
      oldRead.complete(
        const EcardGenderPreferences(choice: EcardGenderChoice.transMan),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('student-ecard-gender')), findsNothing);
      store.failRead = true;
      session.switchTo('2099000003');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('student-ecard-gender')), findsNothing);
      await open(tester);
      expect(find.byType(EcardGenderSettings), findsNothing);
      expect(find.text('性别显示设置暂不可用，请重试'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets('account switch closes editor and rejects a late write', (
    tester,
  ) async {
    final (session, store) = await mount(tester);
    await open(tester);
    store.pendingWrite = Completer<void>();
    await choose(tester, 'transWoman');
    session.switchTo('2099000002');
    await tester.pumpAndSettle();
    store.pendingWrite!.complete();
    await tester.pumpAndSettle();
    expect(store.values, isEmpty);
    expect(find.byType(EcardGenderSettings), findsNothing);
    expect(find.text('跨性别女性 / Trans woman'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom self-description is not translated as interface text', (
    tester,
  ) async {
    final store = _Store();
    store.values['2099000001'] = const EcardGenderPreferences(
      choice: EcardGenderChoice.selfDescribe,
      custom: '保存',
    );
    await mount(tester, store: store, locale: const Locale('en'));
    expect(find.text('保存'), findsOneWidget);
    final data = tester
        .widget<StudentEcardView>(find.byType(StudentEcardView))
        .data;
    expect(data.gender, '保存');
    expect(data.walletCard().toWire(null).containsKey('gender'), isFalse);
  });

  testWidgets(
    'external preference change cancels pending automatic text save',
    (tester) async {
      final (session, store) = await mount(tester);
      await open(tester);
      await choose(tester, 'selfDescribe');
      final input = find.byKey(const ValueKey('ecard-gender-custom'));
      await tester.ensureVisible(input);
      await tester.enterText(input, 'Synthetic pending');
      await store.save(
        session.lease.owner,
        const EcardGenderPreferences(
          visible: false,
          choice: EcardGenderChoice.woman,
        ),
        isCurrent: () => true,
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(EcardGenderSettings), findsNothing);
      expect(store.values.values.single.visible, isFalse);
      expect(store.values.values.single.choice, EcardGenderChoice.woman);
      expect(store.values.values.single.custom, isEmpty);
    },
  );

  testWidgets(
    'closing after a failed autosave reports failure without retrying',
    (tester) async {
      final (_, store) = await mount(tester);
      await open(tester);
      store.failWrite = true;
      await choose(tester, 'woman');
      expect(store.writes, 1);
      expect(find.text('本机保存失败，请重试'), findsOneWidget);
      await closeEditor(tester);
      expect(store.writes, 1);
      expect(store.values, isEmpty);
      expect(find.text('本机保存失败，请重试'), findsOneWidget);
      expect(find.text('男'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets(
    'another route changing the local preference refreshes the card',
    (tester) async {
      final (session, store) = await mount(tester);
      await open(tester);
      await choose(tester, 'transMan');
      await store.save(
        session.lease.owner,
        const EcardGenderPreferences(visible: false),
        isCurrent: () => true,
      );
      await tester.pumpAndSettle();
      expect(find.byType(EcardGenderSettings), findsNothing);
      expect(find.byKey(const ValueKey('student-ecard-gender')), findsNothing);
      expect(store.values.values.single.visible, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('custom editor keeps close reachable and flushes with keyboard', (
    tester,
  ) async {
    await mount(tester, width: 320, locale: const Locale('en'));
    await open(tester, english: true);
    await choose(tester, 'selfDescribe');
    tester.view.viewInsets = const FakeViewPadding(bottom: 310);
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('ecard-gender-custom'));
    await tester.ensureVisible(input);
    await tester.enterText(input, 'Synthetic identity');
    final button = find
        .descendant(
          of: find.byType(EcardGenderSettings),
          matching: find.byType(IconButton),
        )
        .first;
    expect(tester.getRect(button).bottom, lessThan(844 - 310));
    await closeEditor(tester);
    expect(find.text('Synthetic identity'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final locale in [
    const Locale('zh'),
    const Locale('zh', 'TW'),
    const Locale('en'),
  ]) {
    testWidgets(
      'short Chinese presets keep English and stored choices: $locale',
      (tester) async {
        final (_, store) = await mount(tester, locale: locale);
        final english = locale.languageCode == 'en';
        await open(tester, english: english);
        expect(
          find.descendant(
            of: find.byType(EcardGenderSettings),
            matching: find.text(english ? 'Man' : '男'),
          ),
          findsOneWidget,
        );
        expect(find.text(english ? 'Woman' : '女'), findsOneWidget);
        expect(find.text('男性'), findsNothing);
        expect(find.text('女性'), findsNothing);
        for (final entry in {'woman': '女 / Woman', 'man': '男 / Man'}.entries) {
          await choose(tester, entry.key);
          await closeEditor(tester);
          expect(find.text(entry.value), findsOneWidget);
          final data = tester
              .widget<StudentEcardView>(find.byType(StudentEcardView))
              .data;
          expect(data.gender, entry.value);
          expect(data.walletCard().toWire(null).containsKey('gender'), isFalse);
          expect(store.values.values.single.toJson()['choice'], entry.key);
          await open(tester, english: english);
        }
        await closeEditor(tester);
      },
    );
    for (final width in [320.0, 390.0, 768.0]) {
      testWidgets('editor stays bounded and usable at $locale / $width', (
        tester,
      ) async {
        await mount(
          tester,
          width: width,
          scale: 1.6,
          locale: locale,
          dark: true,
        );
        await open(tester, english: locale.languageCode == 'en');
        await choose(tester, 'hidden');
        await closeEditor(tester);
        expect(
          find.byKey(const ValueKey('student-ecard-gender')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}

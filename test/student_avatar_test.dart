import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnbu_me/models/student_avatar_profile.dart';
import 'package:bnbu_me/pages/user_page.dart';
import 'package:bnbu_me/services/student_avatar_store.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/state/app_theme_mode_controller.dart';
import 'package:bnbu_me/state/student_avatar_controller.dart';
import 'package:bnbu_me/theme/app_theme.dart';
import 'package:bnbu_me/widgets/student_avatar_editor.dart';
import 'package:bnbu_me/widgets/student_avatar_rive.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('student avatar profile round-trips every customization slot', () {
    const profile = StudentAvatarProfile(
      body: StudentAvatarBody.athletic,
      skinTone: StudentAvatarSkinTone.deep,
      hairStyle: StudentAvatarHairStyle.bun,
      hairColor: StudentAvatarHairColor.blueBlack,
      top: StudentAvatarTop.winterCoat,
      bottom: StudentAvatarBottom.blueDenim,
      shoes: StudentAvatarShoes.highTops,
      accessory: StudentAvatarAccessory.scarf,
      mood: StudentAvatarMood.thinking,
    );

    expect(StudentAvatarProfile.fromJson(profile.toJson()), profile);
    expect(
      () => StudentAvatarProfile.fromJson({
        ...profile.toJson(),
        'schema_version': 99,
      }),
      throwsFormatException,
    );
  });

  test('student avatar storage is isolated by a hashed account key', () async {
    final store = SharedPreferencesStudentAvatarStore();
    const first = StudentAvatarProfile(top: StudentAvatarTop.varsityJacket);
    const second = StudentAvatarProfile(top: StudentAvatarTop.smartShirt);

    await store.save('student.one@mail.bnbu.edu.cn', first);
    await store.save('student.two@mail.bnbu.edu.cn', second);

    expect(await store.load('STUDENT.ONE@mail.bnbu.edu.cn'), first);
    expect(await store.load('student.two@mail.bnbu.edu.cn'), second);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getKeys(), hasLength(2));
    expect(
      preferences.getKeys().any((key) => key.contains('student.one')),
      isFalse,
    );
  });

  test(
    'agent avatar patch requires confirmation and stays allowlisted',
    () async {
      final store = _MemoryStudentAvatarStore();
      final controller = StudentAvatarController(store: store);
      addTearDown(controller.dispose);
      await controller.switchOwner('student');
      final patch = StudentAvatarPatch.fromJson({
        'hair_style': 'crop',
        'top': 'campusHoodie',
        'mood': 'focused',
      });

      await expectLater(
        controller.applyAgentPatch(patch, confirmed: false),
        throwsStateError,
      );
      expect(controller.profile.hairStyle, StudentAvatarHairStyle.wave);

      await controller.applyAgentPatch(patch, confirmed: true);
      expect(controller.profile.hairStyle, StudentAvatarHairStyle.crop);
      expect(controller.profile.mood, StudentAvatarMood.focused);
      expect(store.values['student'], controller.profile);

      expect(
        () => StudentAvatarPatch.fromJson({'unknown_slot': 'value'}),
        throwsFormatException,
      );
    },
  );

  test(
    'owner switch ignores a late profile from the previous account',
    () async {
      final store = _DeferredStudentAvatarStore();
      final controller = StudentAvatarController(store: store);
      addTearDown(controller.dispose);

      final firstLoad = controller.switchOwner('first');
      final secondLoad = controller.switchOwner('second');
      store.loads['second']!.complete(
        const StudentAvatarProfile(top: StudentAvatarTop.smartShirt),
      );
      await secondLoad;
      store.loads['first']!.complete(
        const StudentAvatarProfile(top: StudentAvatarTop.winterCoat),
      );
      await firstLoad;

      expect(controller.owner, 'second');
      expect(controller.profile.top, StudentAvatarTop.smartShirt);
    },
  );

  testWidgets('avatar stage has an animated local fallback before riv export', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: SizedBox(
            width: 320,
            height: 520,
            child: StudentAvatarStage(profile: StudentAvatarProfile()),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    expect(find.byKey(const ValueKey('student-avatar-stage')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('student-avatar-vector-fallback')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('macOS profile keeps the avatar stage hidden', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final sessionController = AppSessionController();
    final themeController = AppThemeModeController();
    addTearDown(sessionController.dispose);
    addTearDown(themeController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light.copyWith(platform: TargetPlatform.macOS),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(1200, 800),
            disableAnimations: true,
          ),
          child: UserPage(
            controller: sessionController,
            themeModeController: themeController,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final card = find.byKey(const ValueKey('user-profile-card'));
    final logo = find.byKey(const ValueKey('user-hero-brand-mark'));
    final cardRect = tester.getRect(card);
    final logoRect = tester.getRect(logo);
    expect(cardRect.height, lessThan(170));
    expect(cardRect.right - logoRect.right, lessThanOrEqualTo(18));
    expect(logoRect.top - cardRect.top, lessThanOrEqualTo(18));
    expect(
      find.byKey(const ValueKey('user-profile-bubble-arcs')),
      findsNothing,
    );

    expect(
      find.byKey(const ValueKey('user-desktop-avatar-stage')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('student-avatar-vector-fallback')),
      findsNothing,
    );
    await tester.tap(card);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('user-desktop-avatar-stage')),
      findsNothing,
    );
    await tester.tap(card);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('user-desktop-avatar-stage')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile profile scrolls as one surface and keeps avatar hidden', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sessionController = AppSessionController();
    addTearDown(sessionController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: UserPage(controller: sessionController),
      ),
    );
    await tester.pump();
    final card = find.byKey(const ValueKey('user-profile-card'));
    final background = find.byKey(const ValueKey('user-mobile-background'));
    final settings = find.byKey(const ValueKey('user-mobile-settings-surface'));
    final initialCardTop = tester.getTopLeft(card).dy;
    final initialBackgroundTop = tester.getTopLeft(background).dy;
    final initialSettingsTop = tester.getTopLeft(settings).dy;
    final gesture = await tester.startGesture(const Offset(195, 400));
    await gesture.moveBy(const Offset(0, 20));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 180));
    await tester.pump();
    final delta = tester.getTopLeft(settings).dy - initialSettingsTop;
    expect(delta, 0);
    expect(tester.getTopLeft(card).dy - initialCardTop, closeTo(delta, 1));
    expect(
      tester.getTopLeft(background).dy - initialBackgroundTop,
      closeTo(delta, 1),
    );
    expect(
      find.byKey(const ValueKey('user-mobile-avatar-stage')),
      findsNothing,
    );
    await gesture.up();
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.getTopLeft(card).dy, closeTo(initialCardTop, 1));
    expect(find.byKey(const ValueKey('user-profile-card')), findsOneWidget);
    for (final label in ['账户与安全', '通知与同步', '外观与语言', '关于应用']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile avatar stays hidden with large text', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final sessionController = AppSessionController();
    addTearDown(sessionController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            textScaler: TextScaler.linear(2),
          ),
          child: UserPage(controller: sessionController),
        ),
      ),
    );
    await tester.pump();

    final card = find.byKey(const ValueKey('user-profile-card'));
    await tester.tap(card);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('user-profile-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('user-mobile-avatar-stage')),
      findsNothing,
    );
    expect(find.text('通知与同步'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile profile keeps avatar hidden for reduced motion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final sessionController = AppSessionController();
    addTearDown(sessionController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 844),
            disableAnimations: true,
          ),
          child: UserPage(controller: sessionController),
        ),
      ),
    );
    await tester.pump();

    final card = find.byKey(const ValueKey('user-profile-card'));
    await tester.tap(card);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('user-mobile-avatar-stage')),
      findsNothing,
    );
    expect(find.text('通知与同步'), findsOneWidget);

    await tester.tap(card);
    await tester.pump();

    expect(
      find.byKey(const ValueKey('user-mobile-avatar-stage')),
      findsNothing,
    );
    expect(find.text('通知与同步'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('avatar editor uses the shared 700 px modal breakpoint', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = StudentAvatarController(
      store: _MemoryStudentAvatarStore(),
    );
    addTearDown(controller.dispose);

    Future<void> pumpAt(Size size) async {
      tester.view.physicalSize = size;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: MediaQueryData(size: size, disableAnimations: true),
            child: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    key: const ValueKey('open-avatar-editor'),
                    onPressed: () =>
                        showStudentAvatarEditor(context, controller),
                    child: const Text('编辑'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpAt(const Size(699, 900));
    await tester.tap(find.byKey(const ValueKey('open-avatar-editor')));
    await tester.pump();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.byKey(const ValueKey('student-avatar-editor-modal')),
      findsOneWidget,
    );
    Navigator.of(
      tester.element(find.byKey(const ValueKey('student-avatar-editor-modal'))),
    ).pop();
    await tester.pump(const Duration(milliseconds: 250));

    await pumpAt(const Size(700, 900));
    await tester.tap(find.byKey(const ValueKey('open-avatar-editor')));
    await tester.pump();
    expect(find.byType(BottomSheet), findsNothing);
    expect(
      find.byKey(const ValueKey('student-avatar-editor-modal')),
      findsOneWidget,
    );
    final dialogRect = tester.getRect(
      find.byKey(const ValueKey('bnbu-adaptive-modal-dialog')),
    );
    expect(dialogRect.center.dx, closeTo(350, 0.1));
    expect(dialogRect.center.dy, closeTo(450, 0.1));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.byKey(const ValueKey('student-avatar-editor-modal')),
      findsNothing,
    );
  });
}

class _MemoryStudentAvatarStore implements StudentAvatarStore {
  final values = <String, StudentAvatarProfile>{};

  @override
  Future<StudentAvatarProfile?> load(String owner) async => values[owner];

  @override
  Future<void> remove(String owner) async {
    values.remove(owner);
  }

  @override
  Future<void> save(String owner, StudentAvatarProfile profile) async {
    values[owner] = profile;
  }
}

class _DeferredStudentAvatarStore implements StudentAvatarStore {
  final loads = <String, Completer<StudentAvatarProfile?>>{};

  @override
  Future<StudentAvatarProfile?> load(String owner) {
    return (loads[owner] ??= Completer<StudentAvatarProfile?>()).future;
  }

  @override
  Future<void> remove(String owner) async {}

  @override
  Future<void> save(String owner, StudentAvatarProfile profile) async {}
}

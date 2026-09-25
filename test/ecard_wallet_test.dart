import 'dart:async';
import 'package:bnbu_me/widgets/ecard_gender_settings_entry.dart';
import 'dart:convert';

import 'package:bnbu_me/l10n/bnbu_localizations.dart';
import 'package:bnbu_me/models/portal_account_profile.dart';
import 'package:bnbu_me/pages/student_ecard_page.dart';
import 'package:bnbu_me/services/ecard_wallet_service.dart';
import 'package:bnbu_me/services/ecard_gender_store.dart';
import 'package:bnbu_me/models/ecard_gender_preferences.dart';
import 'package:bnbu_me/services/sync/device_session_provider.dart';
import 'package:bnbu_me/services/usage_sync_service.dart';
import 'package:bnbu_me/state/app_session_controller.dart';
import 'package:bnbu_me/widgets/ecard_wallet_consent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _card = EcardWalletCard(
  fullName: '测试同学 TEST STUDENT',
  chineseName: '测试同学',
  englishName: 'TEST STUDENT',
  studentId: '2099000001',
  department: 'FST',
  identity: 'BNBU Student UG/STUDENT',
);
const _passType = 'pass.test.bnbu';
final _serial = 'a' * 64;
EcardWalletPass _pass() =>
    EcardWalletPass(Uint8List.fromList([80, 75, 3, 4]), _passType, _serial);

Matcher walletError(EcardWalletError reason) => throwsA(
  isA<EcardWalletException>().having((e) => e.reason, 'reason', reason),
);

class _Platform implements EcardWalletPlatform {
  bool available = true;
  int presents = 0;
  int portraits = 0;
  int dismissals = 0;
  EcardWalletResult result = EcardWalletResult.added;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<Uint8List> preparePortrait(Uint8List photo) async {
    portraits++;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<EcardWalletResult> present(EcardWalletPass pass) async {
    presents++;
    return result;
  }

  @override
  Future<void> dismiss() async {
    dismissals++;
  }
}

class _Issuer implements EcardWalletIssuer {
  int reads = 0;
  int writes = 0;
  Map<String, Object?>? sentCard;
  bool ready = true;
  bool supportsGenderOmission = true;
  Completer<EcardWalletPass>? pending;
  Completer<String>? availabilityPending;
  @override
  Future<String> availability(String owner, bool Function() isCurrent) async {
    reads++;
    if (!ready) throw const EcardWalletException(EcardWalletError.unavailable);
    if (!supportsGenderOmission) {
      throw const EcardWalletException(EcardWalletError.layoutUnavailable);
    }
    return availabilityPending?.future ?? _passType;
  }

  @override
  Future<EcardWalletPass> issue({
    required String owner,
    required Map<String, Object?> card,
    required DateTime acceptedAt,
    required String expectedPassType,
    required bool Function() isCurrent,
  }) async {
    writes++;
    sentCard = card;
    expect(owner, 'fixture');
    expect(expectedPassType, _passType);
    expect(acceptedAt.isUtc, isTrue);
    expect(isCurrent(), isTrue);
    return pending?.future ?? _pass();
  }

  @override
  void cancel() {}
}

class _Devices implements UsageSyncStore {
  bool registered = true;
  Completer<void>? wait;
  UsageSyncDeviceRecord record = const UsageSyncDeviceRecord(
    installationId: 'fixture',
    deviceToken: 'synthetic-token',
  );
  @override
  Future<UsageSyncDeviceRecord?> loadDevice(String email) async {
    await wait?.future;
    return registered ? record : null;
  }

  @override
  Future<void> saveDevice(String email, UsageSyncDeviceRecord value) async {
    record = value;
  }
}

class _Lease implements AppSessionLease {
  @override
  String get owner => 'fixture';
  @override
  bool isActive = true;
}

class _GenderStore extends EcardGenderStore {
  EcardGenderPreferences value = const EcardGenderPreferences();
  bool failRead = false;
  @override
  Future<EcardGenderPreferences> read(String owner) async {
    if (failRead) throw StateError('Synthetic preference read failure');
    return value;
  }

  @override
  Future<void> save(
    String owner,
    EcardGenderPreferences next, {
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) throw StateError('Expired fixture lease');
    value = next;
    notifyListeners();
  }
}

class _Session extends AppSessionController {
  final lease = _Lease();
  int refreshes = 0;
  @override
  bool get isLoggedIn => lease.isActive;
  @override
  String? get username => '2099000001';
  @override
  PortalAccountProfile? get portalProfile => const PortalAccountProfile(
    fullName: '测试同学 TEST STUDENT',
    chineseName: '测试同学',
    englishName: 'TEST STUDENT',
    identity: 'Student',
    organization: 'Student',
    department: '',
    college: 'FST',
    avatarPath: '',
  );
  @override
  AppSessionLease? captureSessionLease() => lease.isActive ? lease : null;
  @override
  Future<void> refreshPortalProfile() async {
    refreshes++;
  }

  void invalidate() {
    lease.isActive = false;
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Wallet is independent of an unreadable eCard gender preference',
    (tester) async {
      final session = _Session();
      final store = _GenderStore()..failRead = true;
      final issuer = _Issuer()..ready = false;
      await tester.pumpWidget(
        MaterialApp(
          home: StudentEcardPage(
            controller: session,
            onGoToUser: () {},
            genderStore: store,
            walletFlow: EcardWalletFlow(platform: _Platform(), issuer: issuer),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加到 Apple 钱包'));
      await tester.pumpAndSettle();
      expect(issuer.reads, 1);
      expect(issuer.writes, 0);
      expect(find.text('钱包签发服务尚未就绪，暂时无法添加'), findsOneWidget);
      expect(find.text('性别显示设置暂不可用，请重试'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
      store.dispose();
    },
  );

  test(
    'visible, hidden and custom gender all stay out of Wallet wire data',
    () {
      const source = StudentEcardData(
        fullName: 'Fixture',
        studentId: '00012345',
        department: 'FST',
        identity: 'Student',
        gender: 'SYNTHETIC-GENDER',
      );
      final expected = source.walletCard().toWire(null);
      expect(expected.containsKey('gender'), isFalse);
      for (final value in [null, '男 / Man', '女 / Woman', 'Synthetic custom']) {
        expect(
          source.withGenderDisplay(value).walletCard().toWire(null),
          expected,
        );
      }
      expect(source.gender, 'SYNTHETIC-GENDER');
    },
  );

  testWidgets('editing and hiding gender never automatically contact Wallet', (
    tester,
  ) async {
    final session = _Session();
    final store = _GenderStore();
    final issuer = _Issuer();
    final native = _Platform();
    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Expanded(
              child: StudentEcardPage(
                controller: session,
                onGoToUser: () {},
                walletFlow: EcardWalletFlow(platform: native, issuer: issuer),
                genderStore: store,
              ),
            ),
            Material(
              child: EcardGenderSettingsEntry(
                controller: session,
                store: store,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final choice in ['transMan', 'hidden', 'nonBinary']) {
      await tester.tap(
        find.byKey(const ValueKey('ecard-gender-settings-entry')),
      );
      await tester.pumpAndSettle();
      final target = find.byKey(
        ValueKey(
          choice == 'hidden'
              ? 'ecard-gender-visible-switch'
              : 'ecard-gender-$choice',
        ),
      );
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ecard-gender-save')), findsNothing);
      await tester.tap(find.byTooltip('关闭').last);
      await tester.pumpAndSettle();
      expect(issuer.reads, 0);
      expect(issuer.writes, 0);
      expect(native.portraits, 0);
      expect(native.presents, 0);
      if (choice != 'transMan') {
        expect(store.value.visible, isFalse);
        expect(
          find.byKey(const ValueKey('student-ecard-gender')),
          findsNothing,
        );
      }
    }
    expect(store.value.visible, isFalse);
    expect(store.value.choice, EcardGenderChoice.nonBinary);
    expect(find.byKey(const ValueKey('student-ecard-gender')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    session.dispose();
    store.dispose();
  });

  testWidgets(
    'real eCard menu preserves refresh and disables unready issuance without upload',
    (tester) async {
      final session = _Session();
      final issuer = _Issuer()..ready = false;
      final flow = EcardWalletFlow(platform: _Platform(), issuer: issuer);
      await tester.pumpWidget(
        MaterialApp(
          home: StudentEcardPage(
            controller: session,
            onGoToUser: () {},
            walletFlow: flow,
            genderStore: _GenderStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      expect(find.text('添加到 Apple 钱包'), findsOneWidget);
      await tester.tap(find.text('刷新'));
      await tester.pumpAndSettle();
      expect(session.refreshes, 1);
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加到 Apple 钱包'));
      await tester.pumpAndSettle();
      expect(find.text('钱包签发服务尚未就绪，暂时无法添加'), findsOneWidget);
      expect(find.byType(EcardWalletConsentDialog), findsNothing);
      expect(issuer.writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
  );

  testWidgets(
    'logout on real page drops late availability and never opens consent',
    (tester) async {
      final session = _Session();
      final issuer = _Issuer()..availabilityPending = Completer<String>();
      final flow = EcardWalletFlow(platform: _Platform(), issuer: issuer);
      await tester.pumpWidget(
        MaterialApp(
          home: StudentEcardPage(
            controller: session,
            onGoToUser: () {},
            walletFlow: flow,
            genderStore: _GenderStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加到 Apple 钱包'));
      await tester.pump(const Duration(milliseconds: 500));
      session.invalidate();
      issuer.availabilityPending!.complete(_passType);
      await tester.pumpAndSettle();
      expect(find.byType(EcardWalletConsentDialog), findsNothing);
      expect(issuer.writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
  );

  testWidgets(
    'unsupported eCard devices retain refresh without a Wallet entry',
    (tester) async {
      final session = _Session();
      final issuer = _Issuer();
      final flow = EcardWalletFlow(
        platform: _Platform()..available = false,
        issuer: issuer,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StudentEcardPage(
            controller: session,
            onGoToUser: () {},
            walletFlow: flow,
            genderStore: _GenderStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      expect(find.text('刷新'), findsOneWidget);
      expect(find.text('添加到 Apple 钱包'), findsNothing);
      expect(issuer.reads, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      session.dispose();
    },
  );

  test(
    'snapshot exports only resolved visible fields, same photo and exact QR ID',
    () {
      final photo = Uint8List.fromList([4, 5, 6]);
      final card = const StudentEcardData(
        fullName: 'Source Full Name',
        chineseName: '测试',
        englishName: 'SOURCE NAME',
        studentId: '001234567',
        department: 'SCC',
        identity: 'BNBU Student TPG/STUDENT',
        gender: '--',
        residence: 'DO NOT EXPORT',
      ).walletCard(photo: photo);
      expect(card.photo, same(photo));
      expect(card.toWire(photo), {
        'full_name': 'Source Full Name',
        'chinese_name': '测试',
        'english_name': 'SOURCE NAME',
        'student_id': '001234567',
        'department': 'SCC',
        'identity': 'BNBU Student TPG/STUDENT',
        'photo_base64': base64Encode(photo),
      });
    },
  );

  test('cancel never prepares photo or uploads card', () async {
    final issuer = _Issuer();
    final native = _Platform();
    final flow = EcardWalletFlow(platform: native, issuer: issuer);
    expect(
      await flow.add(
        owner: 'fixture',
        card: _card,
        isCurrent: () => true,
        confirm: () async => false,
      ),
      EcardWalletResult.closed,
    );
    expect(issuer.reads, 1);
    expect(issuer.writes, 0);
    expect(native.portraits, 0);
    expect(native.presents, 0);
  });

  test(
    'hidden gender never enters payload or a silent school fallback',
    () async {
      final issuer = _Issuer();
      final hidden = const StudentEcardData(
        fullName: 'Fixture',
        studentId: '00012345',
        department: 'FST',
        identity: 'Student',
        gender: 'PRIVATE-SYNTHETIC',
      ).withGenderDisplay(null).walletCard();
      final flow = EcardWalletFlow(platform: _Platform(), issuer: issuer);
      await flow.add(
        owner: 'fixture',
        card: hidden,
        isCurrent: () => true,
        confirm: () async => true,
      );
      expect(issuer.sentCard!.containsKey('gender'), isFalse);
      expect(jsonEncode(issuer.sentCard), isNot(contains('PRIVATE-SYNTHETIC')));
      final old = _Issuer()..supportsGenderOmission = false;
      await expectLater(
        EcardWalletFlow(platform: _Platform(), issuer: old).add(
          owner: 'fixture',
          card: hidden,
          isCurrent: () => true,
          confirm: () async {
            fail('old issuer must stop before consent or upload');
          },
        ),
        walletError(EcardWalletError.layoutUnavailable),
      );
      expect(old.writes, 0);
    },
  );

  test(
    'remote must declare the gender-free two-row layout explicitly',
    () async {
      for (final (capability, layout) in [
        for (final value in [null, false, 'true', 1, true]) (value, 2),
        for (final value in [null, 1, 3, '2', 2.0]) (true, value),
      ]) {
        final issuer = RemoteEcardWalletIssuer(
          baseUrl: 'https://fixture.invalid',
          devices: DeviceSessionProvider(store: _Devices()),
          clientFactory: () => MockClient((request) async {
            expect(request.method, 'GET');
            return http.Response(
              jsonEncode({
                'available': true,
                'consent_version': ecardWalletConsentVersion,
                'pass_type_identifier': _passType,
                if (capability != null) 'supports_gender_omission': capability,
                if (layout != null) 'layout_version': layout,
                'barcode_version': 2,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        if (capability == true && layout is int && layout == 2) {
          expect(await issuer.availability('fixture', () => true), _passType);
        } else {
          await expectLater(
            issuer.availability('fixture', () => true),
            walletError(EcardWalletError.layoutUnavailable),
          );
        }
      }
    },
  );

  test('remote requires the linear barcode template before consent', () async {
    for (final version in [null, 1, '2', 2.0, 2]) {
      final issuer = RemoteEcardWalletIssuer(
        baseUrl: 'https://fixture.invalid',
        devices: DeviceSessionProvider(store: _Devices()),
        clientFactory: () => MockClient((request) async {
          expect(request.method, 'GET');
          return http.Response(
            jsonEncode({
              'available': true,
              'consent_version': ecardWalletConsentVersion,
              'pass_type_identifier': _passType,
              'supports_gender_omission': true,
              'layout_version': 2,
              if (version != null) 'barcode_version': version,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      if (version is int && version == 2) {
        expect(await issuer.availability('fixture', () => true), _passType);
      } else {
        await expectLater(
          issuer.availability('fixture', () => true),
          walletError(EcardWalletError.layoutUnavailable),
        );
      }
    }
  });

  test(
    'unconfigured signer sends no card and does not request consent',
    () async {
      final issuer = _Issuer()..ready = false;
      final flow = EcardWalletFlow(platform: _Platform(), issuer: issuer);
      await expectLater(
        flow.add(
          owner: 'fixture',
          card: _card,
          isCurrent: () => true,
          confirm: () async {
            fail('unconfigured service cannot ask to upload');
          },
        ),
        walletError(EcardWalletError.unavailable),
      );
      expect(issuer.writes, 0);
    },
  );

  test('unsupported platform has no remote requests or consent', () async {
    final issuer = _Issuer();
    final native = _Platform()..available = false;
    final flow = EcardWalletFlow(platform: native, issuer: issuer);
    await expectLater(
      flow.add(
        owner: 'fixture',
        card: _card,
        isCurrent: () => true,
        confirm: () async {
          fail('unsupported');
        },
      ),
      walletError(EcardWalletError.unavailable),
    );
    expect(issuer.reads, 0);
  });

  for (final result in EcardWalletResult.values) {
    test(
      'native $result is reported without assuming sheet close means success',
      () async {
        final issuer = _Issuer();
        final native = _Platform()..result = result;
        final flow = EcardWalletFlow(platform: native, issuer: issuer);
        expect(
          await flow.add(
            owner: 'fixture',
            card: _card,
            isCurrent: () => true,
            confirm: () async => true,
          ),
          result,
        );
        expect(issuer.writes, 1);
        expect(native.presents, 1);
        expect(issuer.sentCard, _card.toWire(null));
      },
    );
  }

  test('logout while consent is open does not upload', () async {
    var current = true;
    final issuer = _Issuer();
    final flow = EcardWalletFlow(platform: _Platform(), issuer: issuer);
    await expectLater(
      flow.add(
        owner: 'fixture',
        card: _card,
        isCurrent: () => current,
        confirm: () async {
          current = false;
          return true;
        },
      ),
      walletError(EcardWalletError.sessionChanged),
    );
    expect(issuer.writes, 0);
  });

  test(
    'cancelled generation rejects late pass even after same-account relogin',
    () async {
      final issuer = _Issuer()..pending = Completer<EcardWalletPass>();
      final native = _Platform();
      final flow = EcardWalletFlow(platform: native, issuer: issuer);
      final future = flow.add(
        owner: 'fixture',
        card: _card,
        isCurrent: () => true,
        confirm: () async => true,
      );
      final assertion = expectLater(
        future,
        walletError(EcardWalletError.sessionChanged),
      );
      await Future<void>.delayed(Duration.zero);
      expect(issuer.writes, 1);
      flow.cancel();
      issuer.pending!.complete(_pass());
      await assertion;
      expect(native.presents, 0);
      expect(native.dismissals, 1);
    },
  );

  test(
    'late availability after logout never opens consent; double click is gated',
    () async {
      final issuer = _Issuer()..availabilityPending = Completer<String>();
      final flow = EcardWalletFlow(platform: _Platform(), issuer: issuer);
      var current = true;
      final future = flow.add(
        owner: 'fixture',
        card: _card,
        isCurrent: () => current,
        confirm: () async {
          fail('late consent');
        },
      );
      final assertion = expectLater(
        future,
        walletError(EcardWalletError.sessionChanged),
      );
      await expectLater(
        flow.add(
          owner: 'fixture',
          card: _card,
          isCurrent: () => true,
          confirm: () async => true,
        ),
        walletError(EcardWalletError.busy),
      );
      current = false;
      issuer.availabilityPending!.complete(_passType);
      await assertion;
      expect(issuer.writes, 0);
    },
  );

  test(
    'remote uses device bearer, no redirects, bounded wire and no school credentials',
    () async {
      final requests = <http.Request>[];
      final issuer = RemoteEcardWalletIssuer(
        baseUrl: 'https://fixture.invalid',
        devices: DeviceSessionProvider(store: _Devices()),
        clientFactory: () => MockClient((request) async {
          requests.add(request);
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode({
                'available': true,
                'consent_version': ecardWalletConsentVersion,
                'pass_type_identifier': _passType,
                'supports_gender_omission': true,
                'layout_version': 2,
                'barcode_version': 2,
              }),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response.bytes(
            _pass().bytes,
            200,
            headers: {
              'content-type': 'application/vnd.apple.pkpass',
              'x-wallet-pass-type': _passType,
              'x-wallet-serial': _serial,
            },
          );
        }),
      );
      expect(await issuer.availability('fixture', () => true), _passType);
      final now = DateTime.utc(2026, 9, 17);
      final result = await issuer.issue(
        owner: 'fixture',
        card: _card.toWire(null),
        acceptedAt: now,
        expectedPassType: _passType,
        isCurrent: () => true,
      );
      expect(result.serial, _serial);
      expect(requests.first.body, isEmpty);
      expect(
        requests.every(
          (r) =>
              !r.followRedirects &&
              r.headers['Authorization'] == 'Bearer synthetic-token',
        ),
        isTrue,
      );
      expect(jsonDecode(requests.last.body), {
        'consent_version': ecardWalletConsentVersion,
        'consent': true,
        'accepted_at': now.toIso8601String(),
        'card': _card.toWire(null),
      });
      expect(requests.last.headers.containsKey('Cookie'), isFalse);
    },
  );

  for (final status in [302, 401, 413, 422, 429, 503]) {
    test(
      'HTTP $status is not retried and private error is not forwarded',
      () async {
        var calls = 0;
        final devices = _Devices();
        final issuer = RemoteEcardWalletIssuer(
          baseUrl: 'https://fixture.invalid',
          devices: DeviceSessionProvider(store: devices),
          clientFactory: () => MockClient((r) async {
            calls++;
            return http.Response('PRIVATE-ERROR', status);
          }),
        );
        await expectLater(
          issuer.availability('fixture', () => true),
          throwsA(isA<EcardWalletException>()),
        );
        expect(calls, 1);
        if (status == 401) expect(devices.record.deviceToken, isNull);
      },
    );
  }

  test('expired owner during secure-store read sends no request', () async {
    var current = true;
    var calls = 0;
    final devices = _Devices()..wait = Completer<void>();
    final issuer = RemoteEcardWalletIssuer(
      baseUrl: 'https://fixture.invalid',
      devices: DeviceSessionProvider(store: devices),
      clientFactory: () => MockClient((r) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    final future = issuer.availability('fixture', () => current);
    final assertion = expectLater(
      future,
      walletError(EcardWalletError.sessionChanged),
    );
    current = false;
    devices.wait!.complete();
    await assertion;
    expect(calls, 0);
  });

  test(
    'oversized response and mismatched pass identity are rejected',
    () async {
      for (final oversize in [true, false]) {
        final issuer = RemoteEcardWalletIssuer(
          baseUrl: 'https://fixture.invalid',
          devices: DeviceSessionProvider(store: _Devices()),
          clientFactory: () => MockClient(
            (r) async => http.Response.bytes(
              oversize ? Uint8List(ecardWalletMaxPassBytes + 1) : _pass().bytes,
              200,
              headers: {
                'content-type': 'application/vnd.apple.pkpass',
                'x-wallet-pass-type': 'pass.other',
                'x-wallet-serial': _serial,
              },
            ),
          ),
        );
        await expectLater(
          issuer.issue(
            owner: 'fixture',
            card: _card.toWire(null),
            acceptedAt: DateTime.now(),
            expectedPassType: _passType,
            isCurrent: () => true,
          ),
          walletError(EcardWalletError.invalidCard),
        );
      }
    },
  );

  test('native channel accepts only explicit checked result', () async {
    const channel = MethodChannel('bnbu/ecard_wallet');
    final binding =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() => binding.setMockMethodCallHandler(channel, null));
    var value = 'closed';
    binding.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'isAvailable' ? true : value,
    );
    final native = NativeEcardWalletPlatform(channel: channel, supported: true);
    expect(await native.isAvailable(), isTrue);
    expect(await native.present(_pass()), EcardWalletResult.closed);
    value = 'added';
    expect(await native.present(_pass()), EcardWalletResult.added);
    value = 'unknown';
    await expectLater(
      native.present(_pass()),
      walletError(EcardWalletError.invalidCard),
    );
    expect(
      await NativeEcardWalletPlatform(supported: false).isAvailable(),
      isFalse,
    );
  });

  for (final dark in [true, false]) {
    for (final locale in [
      const Locale('zh'),
      const Locale('zh', 'TW'),
      const Locale('en'),
    ]) {
      for (final width in [320.0, 390.0, 768.0]) {
        testWidgets(
          'gender-free consent stays bounded with reachable cancel: $dark/$locale/$width',
          (tester) async {
            await tester.binding.setSurfaceSize(Size(width, 740));
            addTearDown(() => tester.binding.setSurfaceSize(null));
            bool? accepted;
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData(
                  brightness: dark ? Brightness.dark : Brightness.light,
                ),
                locale: locale,
                supportedLocales: BnbuLocalizations.supportedLocales,
                localizationsDelegates: const [
                  BnbuLocalizations.delegate,
                  ...GlobalMaterialLocalizations.delegates,
                ],
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      child: const Text('open'),
                      onPressed: () async {
                        accepted = await showDialog<bool>(
                          context: context,
                          builder: (_) => MediaQuery(
                            data: MediaQuery.of(
                              context,
                            ).copyWith(textScaler: TextScaler.linear(1.6)),
                            child: EcardWalletConsentDialog(
                              buttonBuilder: (press) => ElevatedButton(
                                onPressed: press,
                                child: const Text('TEST BUTTON'),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('open'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(find.byType(SingleChildScrollView), findsOneWidget);
            final rendered = tester
                .widget<Text>(
                  find.descendant(
                    of: find.byType(SingleChildScrollView),
                    matching: find.byType(Text),
                  ),
                )
                .data!;
            expect(
              rendered,
              contains(
                locale.languageCode == 'en'
                    ? 'Wallet passes do not include gender, and gender will not be uploaded'
                    : (locale.countryCode == 'TW' ? '錢包不包含性別' : '钱包不包含性别'),
              ),
            );
            final cancel = locale.languageCode == 'en' ? 'Cancel' : '取消';
            await tester.tap(find.text(cancel));
            await tester.pumpAndSettle();
            expect(accepted, isFalse);
          },
        );
      }
    }
  }
}

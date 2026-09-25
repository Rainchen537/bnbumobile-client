import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bnbu_me/models/ecard_gender_preferences.dart';
import 'package:bnbu_me/pages/student_ecard_page.dart';
import 'package:bnbu_me/services/ecard_gender_store.dart';
import 'package:bnbu_me/services/sync/account_sync_storage.dart';
import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  final key = SecretKey(List.filled(32, 7));
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('bnbu-ecard-gender-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });
  AccountSyncStorage storage() => AccountSyncStorage(
    directory: () async => directory,
    key: () async => key,
  );

  test(
    'defaults preserve source and all six display choices match approved labels',
    () {
      expect(const EcardGenderPreferences().visible, isTrue);
      expect(const EcardGenderPreferences().displayValue('男/MALE'), '男');
      expect(const EcardGenderPreferences().displayValue('女/FEMALE'), '女');
      expect(const EcardGenderPreferences().displayValue('--'), '--');
      expect(EcardGenderChoice.man.label, '男');
      expect(EcardGenderChoice.woman.label, '女');
      expect(
        const EcardGenderPreferences(
          choice: EcardGenderChoice.man,
        ).displayValue('school'),
        '男 / Man',
      );
      expect(
        const EcardGenderPreferences(
          choice: EcardGenderChoice.woman,
        ).displayValue('school'),
        '女 / Woman',
      );
      expect(
        const EcardGenderPreferences(
          choice: EcardGenderChoice.selfDescribe,
          custom: '女性',
        ).displayValue('school'),
        '女性',
      );
      expect(EcardGenderChoice.values.map((v) => v.english), [
        'Man',
        'Woman',
        'Non-binary / Genderfluid',
        'Trans woman',
        'Trans man',
        'Self-describe',
      ]);
      for (final choice in EcardGenderChoice.values) {
        final value = EcardGenderPreferences(
          choice: choice,
          custom: 'Synthetic description',
        );
        expect(value.displayValue('school'), isNot('school'));
        expect(
          value.displayValue('school')!.runes.length,
          lessThanOrEqualTo(40),
        );
        expect(
          EcardGenderPreferences.fromJson(
            value.toJson(),
          ).displayValue('school'),
          value.displayValue('school'),
        );
      }
    },
  );

  test(
    'hidden projection removes gender from eCard and wire without mutating school data',
    () {
      const source = StudentEcardData(
        fullName: 'Fixture',
        studentId: '00012345',
        department: 'FST',
        identity: 'Student',
        gender: 'SYNTHETIC-PRIVATE',
      );
      final hidden = source.withGenderDisplay(
        const EcardGenderPreferences(
          visible: false,
        ).displayValue(source.gender),
      );
      expect(source.gender, 'SYNTHETIC-PRIVATE');
      expect(hidden.showGender, isFalse);
      expect(hidden.gender, isEmpty);
      expect(hidden.walletCard().toWire(null).containsKey('gender'), isFalse);
      expect(
        jsonEncode(hidden.walletCard().toWire(null)),
        isNot(contains('SYNTHETIC-PRIVATE')),
      );
      expect(hidden.barcodePayload, source.barcodePayload);
    },
  );

  test('custom value length and control validation match bounded export', () {
    expect(EcardGenderPreferences.validCustom('🌈' * 40), isTrue);
    expect(EcardGenderPreferences.validCustom('x' * 41), isFalse);
    for (final value in [
      '',
      '  ',
      'x\ny',
      'x\u0000y',
      'x\u202ey',
      'x\u00ady',
      'x\u061cy',
    ]) {
      expect(EcardGenderPreferences.validCustom(value), isFalse);
    }
    expect(
      () => EcardGenderPreferences.fromJson({
        'schema': 1,
        'visible': true,
        'choice': 'unknown',
        'custom': '',
      }),
      throwsFormatException,
    );
  });

  test(
    'preferences survive restart encrypted, normalize owner and never enter habits domain',
    () async {
      final store = EcardGenderStore(storage: storage());
      const value = EcardGenderPreferences(
        visible: false,
        choice: EcardGenderChoice.selfDescribe,
        custom: 'private synthetic display',
      );
      await store.save(
        'Fixture@mail.bnbu.edu.cn',
        value,
        isCurrent: () => true,
      );
      final restarted = EcardGenderStore(storage: storage());
      expect((await restarted.read('fixture')).visible, isFalse);
      expect((await restarted.read('fixture')).custom, value.custom);
      expect((await restarted.read('other')).visible, isTrue);
      expect(await storage().read('fixture', 'habits'), isNull);
      for (final file
          in directory.listSync(recursive: true).whereType<File>()) {
        expect(
          utf8.decode(file.readAsBytesSync(), allowMalformed: true),
          isNot(contains(value.custom)),
        );
        expect(file.path, isNot(contains('fixture')));
      }
      store.dispose();
      restarted.dispose();
    },
  );

  test(
    'corrupt record fails instead of reverting to visible school gender',
    () async {
      final store = EcardGenderStore(storage: storage());
      await store.save(
        'fixture',
        const EcardGenderPreferences(visible: false),
        isCurrent: () => true,
      );
      final file = directory.listSync(recursive: true).whereType<File>().single;
      final bytes = await file.readAsBytes();
      bytes[bytes.length - 1] ^= 1;
      await file.writeAsBytes(bytes);
      await expectLater(store.read('fixture'), throwsA(anything));
      store.dispose();
    },
  );

  test(
    'session revoked during encryption cannot replace existing hidden record',
    () async {
      final base = EcardGenderStore(storage: storage());
      await base.save(
        'fixture',
        const EcardGenderPreferences(visible: false),
        isCurrent: () => true,
      );
      final pendingKey = Completer<SecretKey>();
      final started = Completer<void>();
      final delayed = EcardGenderStore(
        storage: AccountSyncStorage(
          directory: () async => directory,
          key: () {
            started.complete();
            return pendingKey.future;
          },
        ),
      );
      var active = true;
      final write = delayed.save(
        'fixture',
        const EcardGenderPreferences(choice: EcardGenderChoice.woman),
        isCurrent: () => active,
      );
      final checked = expectLater(write, throwsStateError);
      await started.future;
      active = false;
      pendingKey.complete(key);
      await checked;
      expect((await base.read('fixture')).visible, isFalse);
      expect(directory.listSync(recursive: true).whereType<File>().length, 1);
      base.dispose();
      delayed.dispose();
    },
  );
}

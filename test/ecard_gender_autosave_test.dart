import 'dart:async';
import 'package:bnbu_me/models/ecard_gender_preferences.dart';
import 'package:bnbu_me/state/ecard_gender_autosave.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'hiding an unfinished draft keeps the last valid in-flight choice',
    (tester) async {
      final gate = Completer<void>();
      final values = <EcardGenderPreferences>[];
      final editor = EcardGenderAutosave(
        initial: const EcardGenderPreferences(),
        isCurrent: () => true,
        onSave: (value) async {
          values.add(value);
          if (values.length == 1) await gate.future;
        },
      );
      addTearDown(editor.dispose);
      editor.setChoice(EcardGenderChoice.woman);
      editor.setChoice(EcardGenderChoice.selfDescribe);
      editor.setVisible(false);
      gate.complete();
      await editor.flush();
      expect(values.last.visible, isFalse);
      expect(values.last.choice, EcardGenderChoice.woman);
    },
  );
  testWidgets('rapid edits serialize and keep only the latest queued choice', (
    tester,
  ) async {
    final gate = Completer<void>();
    final values = <EcardGenderPreferences>[];
    final editor = EcardGenderAutosave(
      initial: const EcardGenderPreferences(visible: false),
      isCurrent: () => true,
      onSave: (value) async {
        values.add(value);
        if (values.length == 1) await gate.future;
      },
    );
    addTearDown(editor.dispose);
    editor.setChoice(EcardGenderChoice.woman);
    editor.setChoice(EcardGenderChoice.nonBinary);
    editor.setChoice(EcardGenderChoice.transMan);
    expect(values.length, 1);
    gate.complete();
    await editor.flush();
    expect(values.map((v) => v.choice), [
      EcardGenderChoice.woman,
      EcardGenderChoice.transMan,
    ]);
    expect(values.every((v) => !v.visible), isTrue);
    expect(editor.saving, isFalse);
  });

  testWidgets('custom input debounces and does not save IME composing text', (
    tester,
  ) async {
    final values = <EcardGenderPreferences>[];
    final editor = EcardGenderAutosave(
      initial: const EcardGenderPreferences(
        choice: EcardGenderChoice.selfDescribe,
        custom: 'original',
      ),
      isCurrent: () => true,
      onSave: (v) async => values.add(v),
    );
    addTearDown(editor.dispose);
    editor.setCustom('draft', composing: false);
    await tester.pump(const Duration(milliseconds: 200));
    editor.setCustom('合成内容', composing: true);
    await tester.pump(const Duration(seconds: 1));
    expect(values, isEmpty);
    editor.setCustom('合成内容', composing: false);
    await tester.pump(const Duration(milliseconds: 399));
    expect(values, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(values.single.custom, '合成内容');
    expect(await editor.flush(), isTrue);
    expect(values.length, 1);
  });

  testWidgets(
    'dismiss flushes valid text before its debounce without duplicates',
    (tester) async {
      final values = <EcardGenderPreferences>[];
      final editor = EcardGenderAutosave(
        initial: const EcardGenderPreferences(
          visible: false,
          choice: EcardGenderChoice.selfDescribe,
          custom: 'old',
        ),
        isCurrent: () => true,
        onSave: (v) async => values.add(v),
      );
      addTearDown(editor.dispose);
      editor.setCustom('new', composing: false);
      expect(await editor.flush(), isTrue);
      expect(values.single.custom, 'new');
      expect(values.single.visible, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(values.length, 1);
    },
  );

  testWidgets(
    'invalid draft never replaces safe custom value or prevents hiding',
    (tester) async {
      final values = <EcardGenderPreferences>[];
      final editor = EcardGenderAutosave(
        initial: const EcardGenderPreferences(
          choice: EcardGenderChoice.selfDescribe,
          custom: 'safe',
        ),
        isCurrent: () => true,
        onSave: (v) async => values.add(v),
      );
      addTearDown(editor.dispose);
      editor.setCustom('x' * 40, composing: false);
      await tester.pump(const Duration(milliseconds: 100));
      editor.setCustom('x' * 41, composing: false);
      await tester.pump(const Duration(seconds: 1));
      expect(values, isEmpty);
      editor.setVisible(false);
      await editor.flush();
      expect(values.single.visible, isFalse);
      expect(values.single.custom, 'safe');
      expect(editor.error, isNotNull);
      expect(editor.draft.custom.length, 41);
    },
  );

  testWidgets(
    'failure is visible, does not retry on close, and can be retried',
    (tester) async {
      var failing = true;
      var attempts = 0;
      final values = <EcardGenderPreferences>[];
      final editor = EcardGenderAutosave(
        initial: const EcardGenderPreferences(),
        isCurrent: () => true,
        onSave: (v) async {
          attempts++;
          if (failing) throw StateError('synthetic failure');
          values.add(v);
        },
      );
      addTearDown(editor.dispose);
      editor.setChoice(EcardGenderChoice.woman);
      await tester.pump();
      expect(editor.failed, isTrue);
      expect(await editor.flush(), isFalse);
      expect(attempts, 1);
      failing = false;
      editor.retry();
      expect(await editor.flush(), isTrue);
      expect(editor.error, isNull);
      expect(values.single.choice, EcardGenderChoice.woman);
    },
  );

  testWidgets('account revocation discards debounced and queued writes', (
    tester,
  ) async {
    var active = true;
    final values = <EcardGenderPreferences>[];
    final editor = EcardGenderAutosave(
      initial: const EcardGenderPreferences(
        choice: EcardGenderChoice.selfDescribe,
        custom: 'old',
      ),
      isCurrent: () => active,
      onSave: (v) async => values.add(v),
    );
    addTearDown(editor.dispose);
    editor.setCustom('new', composing: false);
    active = false;
    await tester.pump(const Duration(seconds: 1));
    await editor.flush();
    expect(values, isEmpty);
  });
}

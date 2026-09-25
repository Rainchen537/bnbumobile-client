import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/ecard_gender_preferences.dart';

/// One editor's local-only, latest-choice-wins write queue.
class EcardGenderAutosave extends ChangeNotifier {
  EcardGenderAutosave({
    required EcardGenderPreferences initial,
    required this.onSave,
    required this.isCurrent,
  }) : draft = initial,
       _lastValid = initial,
       _saved = initial;

  final Future<void> Function(EcardGenderPreferences) onSave;
  final bool Function() isCurrent;
  EcardGenderPreferences draft;
  EcardGenderPreferences _saved;
  EcardGenderPreferences _lastValid;
  EcardGenderPreferences? _pending;
  Timer? _timer;
  Future<void>? _worker;
  bool _composing = false;
  bool _disposed = false;
  bool failed = false;
  String? error;
  bool get saving => _worker != null;

  void setVisible(bool value) {
    draft = EcardGenderPreferences(
      visible: value,
      choice: draft.choice,
      custom: draft.custom,
    );
    _schedule();
  }

  void setChoice(EcardGenderChoice value) {
    draft = EcardGenderPreferences(
      visible: draft.visible,
      choice: value,
      custom: draft.custom,
    );
    _schedule();
  }

  void setCustom(String text, {required bool composing}) {
    draft = EcardGenderPreferences(
      visible: draft.visible,
      choice: draft.choice,
      custom: text,
    );
    _composing = composing;
    _schedule(debounce: true);
  }

  bool _same(EcardGenderPreferences a, EcardGenderPreferences b) =>
      a.visible == b.visible && a.choice == b.choice && a.custom == b.custom;

  EcardGenderPreferences? _candidate() {
    final custom = draft.custom.trim();
    final validText =
        !_composing && EcardGenderPreferences.validCustom(draft.custom);
    final invalid =
        draft.choice == EcardGenderChoice.selfDescribe && !validText;
    error = invalid && !_composing ? '请输入1–40个字符，不含换行或控制字符' : null;
    if (invalid) {
      // An unfinished text draft must not prevent hiding the last safe value.
      return draft.visible
          ? null
          : EcardGenderPreferences(
              visible: false,
              choice: _lastValid.choice,
              custom: _lastValid.custom,
            );
    }
    return EcardGenderPreferences(
      visible: draft.visible,
      choice: draft.choice,
      custom:
          !_composing &&
              EcardGenderPreferences(
                visible: false,
                custom: draft.custom,
              ).isValid
          ? custom
          : _lastValid.custom,
    );
  }

  void _schedule({bool debounce = false}) {
    _timer?.cancel();
    _pending = null;
    failed = false;
    final value = _candidate();
    if (!_disposed && isCurrent() && value != null) {
      if (debounce && !_composing) {
        _timer = Timer(const Duration(milliseconds: 400), () => _queue(value));
      } else if (!debounce || !_composing) {
        _queue(value);
      }
    }
    _notify();
  }

  void _queue(EcardGenderPreferences value) {
    if (_disposed || !isCurrent()) return;
    // Only a value actually submitted for saving is a safe fallback. A valid
    // prefix of a later invalid draft must not be silently saved when hiding.
    _lastValid = value;
    _pending = value;
    if (_worker != null) return;
    final completion = Completer<void>();
    _worker = completion.future;
    unawaited(() async {
      try {
        while (_pending != null && !_disposed && isCurrent()) {
          final next = _pending!;
          _pending = null;
          if (_same(next, _saved)) continue;
          try {
            await onSave(next);
            _saved = next;
            failed = false;
            _candidate();
          } catch (_) {
            if (isCurrent()) {
              failed = true;
              error = '本机保存失败，请重试';
            }
          }
        }
      } finally {
        _pending = null;
        _worker = null;
        completion.complete();
        _notify();
      }
    }());
  }

  void retry() => _schedule();

  /// The owning page calls this on every modal dismissal, before disposal.
  Future<bool> flush() async {
    _timer?.cancel();
    _timer = null;
    if (!isCurrent()) {
      _pending = null;
      return true;
    }
    // Do not silently retry a reported disk failure just because the UI closed.
    if (!failed) {
      final value = _candidate();
      if (value != null) _queue(value);
    }
    while (_worker != null) {
      await _worker;
    }
    return !isCurrent() || (!failed && error == null);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _pending = null;
    super.dispose();
  }
}

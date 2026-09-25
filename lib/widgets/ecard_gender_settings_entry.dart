import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/ecard_gender_preferences.dart';
import '../services/ecard_gender_store.dart';
import '../state/app_session_controller.dart';
import '../state/ecard_gender_autosave.dart';
import '../theme/app_theme.dart';
import 'bnbu_adaptive_modal.dart';
import 'bnbu_notice.dart';
import 'ecard_gender_settings.dart';

/// Private settings entry. No school refresh, cloud write or Wallet operation.
class EcardGenderSettingsEntry extends StatefulWidget {
  const EcardGenderSettingsEntry({
    super.key,
    required this.controller,
    this.store,
  });
  final AppSessionController controller;
  final EcardGenderStore? store;
  @override
  State<EcardGenderSettingsEntry> createState() =>
      _EcardGenderSettingsEntryState();
}

class _EcardGenderSettingsEntryState extends State<EcardGenderSettingsEntry> {
  late EcardGenderStore _store;
  AppSessionLease? _lease;
  Route<void>? _route;
  EcardGenderPreferences? _value;
  int _generation = 0;
  int _saving = 0;
  bool _failed = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? EcardGenderStore.shared;
    _store.addListener(_changed);
    widget.controller.addListener(_sessionChanged);
    _load();
  }

  void _close() {
    final route = _route;
    _route = null;
    if (route != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
  }

  void _sessionChanged() {
    final current = widget.controller.captureSessionLease();
    if (_lease?.isActive != true || current?.owner != _lease?.owner) {
      _close();
      _load();
    }
  }

  void _changed() {
    if (!mounted || _saving > 0) return;
    _close();
    _load();
  }

  void _load() {
    final generation = ++_generation;
    final lease = _lease = widget.controller.captureSessionLease();
    _value = null;
    _failed = false;
    if (mounted) setState(() {});
    if (lease == null) return;
    unawaited(() async {
      try {
        final value = await _store.read(lease.owner);
        if (!mounted || !lease.isActive || generation != _generation) return;
        setState(() => _value = value);
      } catch (_) {
        if (!mounted || !lease.isActive || generation != _generation) return;
        setState(() => _failed = true);
      }
    }());
  }

  @override
  void didUpdateWidget(covariant EcardGenderSettingsEntry oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.store != widget.store) {
      oldWidget.controller.removeListener(_sessionChanged);
      _store.removeListener(_changed);
      _close();
      _store = widget.store ?? EcardGenderStore.shared;
      _store.addListener(_changed);
      widget.controller.addListener(_sessionChanged);
      _load();
    }
  }

  Future<void> _open() async {
    if (_opening) return;
    if (_value == null) {
      BnbuToast.show(
        context,
        context.l10n.text(_failed ? '性别显示设置暂不可用，请重试' : '正在读取性别显示设置'),
      );
      if (_failed) _load();
      return;
    }
    final lease = _lease;
    if (lease == null || !lease.isActive) return;
    _opening = true;
    final generation = _generation;
    bool current() =>
        mounted &&
        lease.isActive &&
        identical(lease, _lease) &&
        generation == _generation;
    final editor = EcardGenderAutosave(
      initial: _value!,
      isCurrent: current,
      onSave: (value) async {
        if (!current()) throw StateError('Stale eCard settings');
        _saving++;
        try {
          await _store.save(lease.owner, value, isCurrent: current);
          if (!current()) throw StateError('Stale eCard settings');
          setState(() => _value = value);
        } finally {
          _saving--;
        }
      },
    );
    Route<void>? shown;
    try {
      await showBnbuAdaptiveModal<void>(
        context: context,
        useRootNavigator: true,
        dialogMaxWidth: 560,
        builder: (context, presentation) {
          shown = _route = ModalRoute.of<void>(context);
          return AnimatedBuilder(
            animation: widget.controller,
            builder: (_, _) => !current()
                ? const SizedBox.shrink()
                : EcardGenderSettings(
                    editor: editor,
                    presentation: presentation,
                    sourceGender: widget.controller.portalProfile?.gender ?? '',
                  ),
          );
        },
      );
      final saved = await editor.flush();
      if (!saved && current()) {
        if (mounted) {
          BnbuToast.show(
            context,
            context.l10n.text(editor.error ?? '本机保存失败，请重试'),
          );
        }
      }
    } finally {
      if (shown is TransitionRoute<void>) {
        await (shown as TransitionRoute<void>).completed;
      }
      editor.dispose();
      if (identical(_route, shown)) _route = null;
      _opening = false;
    }
  }

  @override
  void dispose() {
    _generation++;
    _close();
    _store.removeListener(_changed);
    widget.controller.removeListener(_sessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListTile(
    key: const ValueKey('ecard-gender-settings-entry'),
    minTileHeight: 56,
    title: Text(
      context.l10n.text('性别显示'),
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
    ),
    trailing: const Icon(LucideIcons.chevronRight300, size: 17),
    onTap: widget.controller.isLoggedIn ? _open : null,
  );
}

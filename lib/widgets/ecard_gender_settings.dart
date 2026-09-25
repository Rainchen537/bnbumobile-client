import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/ecard_gender_preferences.dart';
import '../state/ecard_gender_autosave.dart';
import '../theme/app_theme.dart';
import 'bnbu_adaptive_modal.dart';

class EcardGenderSettings extends StatefulWidget {
  const EcardGenderSettings({
    super.key,
    required this.editor,
    required this.presentation,
    this.sourceGender = '',
  });
  final EcardGenderAutosave editor;
  final BnbuAdaptiveModalPresentation presentation;
  final String sourceGender;
  @override
  State<EcardGenderSettings> createState() => _EcardGenderSettingsState();
}

class _EcardGenderSettingsState extends State<EcardGenderSettings> {
  late final _custom = TextEditingController(text: widget.editor.draft.custom);
  late String _lastText = _custom.text;
  TextRange _lastComposing = TextRange.empty;
  @override
  void initState() {
    super.initState();
    _custom.addListener(_textChanged);
  }

  void _textChanged() {
    final value = _custom.value;
    if (_lastText == value.text && _lastComposing == value.composing) return;
    _lastText = value.text;
    _lastComposing = value.composing;
    widget.editor.setCustom(
      value.text,
      composing: value.composing.isValid && !value.composing.isCollapsed,
    );
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.editor,
    builder: (context, _) => _buildEditor(context),
  );

  Widget _buildEditor(BuildContext context) {
    final editor = widget.editor;
    final draft = editor.draft;
    final size = MediaQuery.sizeOf(context);
    final sourceChoice = EcardGenderPreferences.schoolChoice(
      widget.sourceGender,
    );
    // Card visibility never replaces the user's choice in the private editor.
    final selected = (draft.choice ?? sourceChoice)?.name;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: math.min(660, size.height * .78),
        child: BnbuModalFrame(
          presentation: widget.presentation,
          title: context.l10n.text('性别显示'),
          titleTrailing: editor.saving
              ? Text(
                  context.l10n.text('保存中'),
                  style: Theme.of(context).textTheme.bodySmall,
                )
              : null,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile.adaptive(
                  key: const ValueKey('ecard-gender-visible-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.l10n.text('在 eCard 上显示性别')),
                  value: draft.visible,
                  onChanged: editor.setVisible,
                ),
                RadioGroup<String>(
                  groupValue: selected,
                  onChanged: (value) {
                    if (value != null) {
                      editor.setChoice(EcardGenderChoice.values.byName(value));
                    }
                  },
                  child: Column(
                    children: [
                      for (final option in EcardGenderChoice.values)
                        RadioListTile<String>(
                          key: ValueKey('ecard-gender-${option.name}'),
                          contentPadding: EdgeInsets.zero,
                          value: option.name,
                          title: Text(
                            context.l10n.isEnglish
                                ? option.english
                                : context.l10n.text(option.label),
                          ),
                        ),
                    ],
                  ),
                ),
                if (draft.choice == EcardGenderChoice.selfDescribe)
                  TextField(
                    key: const ValueKey('ecard-gender-custom'),
                    controller: _custom,
                    maxLength: EcardGenderPreferences.maxCustomLength,
                    maxLengthEnforcement: MaxLengthEnforcement.none,
                    decoration: InputDecoration(
                      labelText: context.l10n.text('自定义性别'),
                    ),
                  ),
                if (editor.error != null)
                  Text(
                    context.l10n.text(editor.error!),
                    key: const ValueKey('ecard-gender-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (editor.failed)
                  TextButton(
                    key: const ValueKey('ecard-gender-retry'),
                    onPressed: editor.retry,
                    child: Text(context.l10n.text('重试')),
                  ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.text('设置仅保存在本机，不修改学校资料。钱包卡片不包含性别，已有卡片不自动更新。'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

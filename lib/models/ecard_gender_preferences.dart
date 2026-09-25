enum EcardGenderChoice {
  man,
  woman,
  nonBinary,
  transWoman,
  transMan,
  selfDescribe,
}

extension EcardGenderChoiceLabels on EcardGenderChoice {
  String get label => switch (this) {
    EcardGenderChoice.man => '男',
    EcardGenderChoice.woman => '女',
    EcardGenderChoice.nonBinary => '非二元性别／性别流动',
    EcardGenderChoice.transWoman => '跨性别女性',
    EcardGenderChoice.transMan => '跨性别男性',
    EcardGenderChoice.selfDescribe => '其他／自定义',
  };

  String get english => switch (this) {
    EcardGenderChoice.man => 'Man',
    EcardGenderChoice.woman => 'Woman',
    EcardGenderChoice.nonBinary => 'Non-binary / Genderfluid',
    EcardGenderChoice.transWoman => 'Trans woman',
    EcardGenderChoice.transMan => 'Trans man',
    EcardGenderChoice.selfDescribe => 'Self-describe',
  };
}

/// Presentation only; never mutates Portal data or enters account cloud habits.
class EcardGenderPreferences {
  const EcardGenderPreferences({
    this.visible = true,
    this.choice,
    this.custom = '',
  });
  final bool visible;
  final EcardGenderChoice? choice;
  final String custom;
  static const maxCustomLength = 40;
  static final _controls = RegExp(r'[\p{C}\u2028\u2029]', unicode: true);

  static bool validCustom(String value) =>
      value.trim().isNotEmpty &&
      value.runes.length <= maxCustomLength &&
      !_controls.hasMatch(value);

  bool get isValid =>
      custom.runes.length <= maxCustomLength &&
      !_controls.hasMatch(custom) &&
      (!visible ||
          choice != EcardGenderChoice.selfDescribe ||
          validCustom(custom));

  String? displayValue(String schoolValue) {
    if (!visible) return null;
    if (choice == null) {
      return switch (schoolChoice(schoolValue)) {
        EcardGenderChoice.man => '男',
        EcardGenderChoice.woman => '女',
        _ => schoolValue,
      };
    }
    if (choice == EcardGenderChoice.selfDescribe) return custom.trim();
    return '${choice!.label} / ${choice!.english}';
  }

  Map<String, dynamic> toJson() {
    if (!isValid) {
      throw const FormatException('Invalid eCard display preference');
    }
    return {
      'schema': 1,
      'visible': visible,
      'choice': choice?.name,
      'custom': custom,
    };
  }

  static EcardGenderChoice? schoolChoice(String value) =>
      switch (value.trim().toLowerCase()) {
        '男' || 'male' || 'm' || '0' || '男/male' => EcardGenderChoice.man,
        '女' || 'female' || 'f' || '1' || '女/female' => EcardGenderChoice.woman,
        _ => null,
      };

  factory EcardGenderPreferences.fromJson(Map<String, dynamic> value) {
    if (value.length != 4 ||
        value['schema'] != 1 ||
        value['visible'] is! bool ||
        value['custom'] is! String ||
        !value.containsKey('choice')) {
      throw const FormatException('Invalid eCard display preference');
    }
    final raw = value['choice'];
    final choices = EcardGenderChoice.values.where((v) => v.name == raw);
    if (raw != null && choices.length != 1) {
      throw const FormatException('Invalid eCard display preference');
    }
    final result = EcardGenderPreferences(
      visible: value['visible'] as bool,
      choice: raw == null ? null : choices.single,
      custom: value['custom'] as String,
    );
    if (!result.isValid) {
      throw const FormatException('Invalid eCard display preference');
    }
    return result;
  }
}

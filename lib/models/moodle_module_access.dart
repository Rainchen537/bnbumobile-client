class MoodleModuleAccessSnapshot {
  const MoodleModuleAccessSnapshot({
    required this.moduleType,
    required this.canRead,
    required this.canWrite,
    required this.statusMessage,
    this.choiceOptions = const [],
    this.choiceOptionsTruncated = false,
    this.choiceAllowMultiple = false,
    this.choiceAllowUpdate = false,
  });

  final String moduleType;
  final bool canRead;
  final bool canWrite;
  final String statusMessage;
  final List<MoodleChoiceOption> choiceOptions;
  final bool choiceOptionsTruncated;
  final bool choiceAllowMultiple;
  final bool choiceAllowUpdate;
}

class MoodleChoiceOption {
  const MoodleChoiceOption({
    required this.id,
    required this.label,
    required this.selected,
    required this.disabled,
    required this.maxAnswers,
  });

  final int id;
  final String label;
  final bool selected;
  final bool disabled;
  final int maxAnswers;
}

class QuizAttemptSnapshot {
  const QuizAttemptSnapshot({
    required this.itemId,
    required this.quizId,
    required this.attemptId,
    required this.state,
    required this.canStart,
    required this.canSave,
    required this.canFinish,
    required this.questions,
    this.accessMessage = '',
    this.truncated = false,
    this.nextPage,
  });

  final String itemId;
  final int quizId;
  final int attemptId;
  final String state;
  final bool canStart;
  final bool canSave;
  final bool canFinish;
  final String accessMessage;
  final List<QuizQuestionData> questions;
  final bool truncated;
  final int? nextPage;

  bool get hasActiveAttempt => attemptId > 0 && state == 'inprogress';
}

class QuizQuestionData {
  const QuizQuestionData({
    required this.slot,
    required this.number,
    required this.type,
    required this.prompt,
    required this.status,
    required this.sequenceCheckName,
    required this.sequenceCheck,
    required this.fields,
  });

  final int slot;
  final String number;
  final String type;
  final String prompt;
  final String status;
  final String sequenceCheckName;
  final String sequenceCheck;
  final List<QuizAnswerField> fields;
}

enum QuizAnswerFieldKind { choice, text, select }

class QuizAnswerField {
  const QuizAnswerField({
    required this.name,
    required this.kind,
    required this.label,
    required this.currentValues,
    required this.options,
    this.maxLength = 4000,
    this.multiple = false,
  });

  final String name;
  final QuizAnswerFieldKind kind;
  final String label;
  final List<String> currentValues;
  final List<QuizAnswerOption> options;
  final int maxLength;
  final bool multiple;
}

class QuizAnswerOption {
  const QuizAnswerOption({required this.value, required this.label});

  final String value;
  final String label;
}

class QuizAnswerDraft {
  const QuizAnswerDraft({
    required this.slot,
    required this.fieldName,
    required this.value,
  });

  final int slot;
  final String fieldName;
  final String value;

  Map<String, dynamic> toJson() => {
    'slot': slot,
    'field_name': fieldName,
    'value': value,
  };
}

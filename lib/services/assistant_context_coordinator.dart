import 'package:flutter/foundation.dart';

import '../models/assistant_models.dart';

class AssistantContextContribution {
  const AssistantContextContribution({
    this.currentPage,
    this.mailSummaries,
    this.loadMailSummaries,
    this.selectedMail,
    this.schoolActivities,
  });

  final AssistantCurrentPageContext? Function()? currentPage;
  final List<AssistantMailSummaryContext> Function()? mailSummaries;
  final Future<List<AssistantMailSummaryContext>> Function()? loadMailSummaries;
  final AssistantSelectedMailContext? Function()? selectedMail;
  final List<AssistantSchoolActivityContext> Function()? schoolActivities;
}

class AssistantContextSnapshot {
  const AssistantContextSnapshot({
    required this.currentPage,
    required this.mailSummaries,
    required this.selectedMail,
    required this.schoolActivities,
  });

  final AssistantCurrentPageContext? currentPage;
  final List<AssistantMailSummaryContext> mailSummaries;
  final AssistantSelectedMailContext? selectedMail;
  final List<AssistantSchoolActivityContext> schoolActivities;
}

class AssistantContextCoordinator extends ChangeNotifier {
  final Map<int, AssistantContextContribution> _contributions = {};
  int _nextId = 1;

  bool get canLoadMailSummaries => _contributions.values.any(
    (contribution) =>
        contribution.loadMailSummaries != null ||
        contribution.mailSummaries != null,
  );

  AssistantContextRegistration register(
    AssistantContextContribution contribution,
  ) {
    final id = _nextId++;
    _contributions[id] = contribution;
    notifyListeners();
    return AssistantContextRegistration._(this, id);
  }

  AssistantContextSnapshot snapshot() {
    AssistantCurrentPageContext? currentPage;
    AssistantSelectedMailContext? selectedMail;
    final mailSummaries = <AssistantMailSummaryContext>[];
    final schoolActivities = <AssistantSchoolActivityContext>[];

    for (final contribution in _contributions.values) {
      currentPage = _read(contribution.currentPage) ?? currentPage;
      selectedMail = _read(contribution.selectedMail) ?? selectedMail;
      mailSummaries.addAll(
        _read(contribution.mailSummaries) ??
            const <AssistantMailSummaryContext>[],
      );
      schoolActivities.addAll(
        _read(contribution.schoolActivities) ??
            const <AssistantSchoolActivityContext>[],
      );
    }

    return AssistantContextSnapshot(
      currentPage: currentPage,
      mailSummaries: mailSummaries.take(24).toList(growable: false),
      selectedMail: selectedMail,
      schoolActivities: schoolActivities.take(30).toList(growable: false),
    );
  }

  Future<List<AssistantMailSummaryContext>> loadMailSummaries() async {
    final combined = <AssistantMailSummaryContext>[];
    for (final contribution in _contributions.values) {
      final loader = contribution.loadMailSummaries;
      if (loader != null) {
        try {
          combined.addAll(await loader());
          continue;
        } catch (_) {
          // Fall back to the latest in-memory snapshot from this contribution.
        }
      }
      combined.addAll(
        _read(contribution.mailSummaries) ??
            const <AssistantMailSummaryContext>[],
      );
    }

    final unique = <String, AssistantMailSummaryContext>{};
    for (final summary in combined) {
      final identity =
          summary.uid != null &&
              summary.folder.isNotEmpty &&
              summary.mailboxUidValidity != null
          ? '${summary.folder}:${summary.mailboxUidValidity}:${summary.uid}'
          : '${summary.senderEmail}:${summary.subject}:${summary.receivedAt.toUtc().toIso8601String()}';
      unique.putIfAbsent(identity, () => summary);
    }
    return unique.values.take(24).toList(growable: false);
  }

  void _update(int id, AssistantContextContribution contribution) {
    if (!_contributions.containsKey(id)) {
      return;
    }
    _contributions[id] = contribution;
    notifyListeners();
  }

  void _remove(int id) {
    if (_contributions.remove(id) != null) {
      notifyListeners();
    }
  }

  T? _read<T>(T? Function()? provider) {
    if (provider == null) {
      return null;
    }
    try {
      return provider();
    } catch (_) {
      return null;
    }
  }
}

class AssistantContextRegistration {
  AssistantContextRegistration._(this._coordinator, this._id);

  AssistantContextCoordinator? _coordinator;
  final int _id;

  void update(AssistantContextContribution contribution) {
    _coordinator?._update(_id, contribution);
  }

  void dispose() {
    _coordinator?._remove(_id);
    _coordinator = null;
  }
}

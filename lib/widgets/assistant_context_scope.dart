import 'package:flutter/widgets.dart';

import '../services/assistant_context_coordinator.dart';
import '../models/assistant_models.dart';
import '../state/ai_assistant_controller.dart';
import '../state/assistant_presentation_controller.dart';
import '../state/study_mode_controller.dart';

/// Registers public page identity for the lifetime of its actual route.
/// The callback is evaluated when Small U requests context, after data refresh.
class AssistantPageContext extends StatefulWidget {
  const AssistantPageContext({
    super.key,
    required this.currentPage,
    required this.child,
  });
  final AssistantCurrentPageContext Function() currentPage;
  final Widget child;

  @override
  State<AssistantPageContext> createState() => _AssistantPageContextState();
}

class _AssistantPageContextState extends State<AssistantPageContext> {
  AssistantContextCoordinator? _coordinator;
  AssistantContextRegistration? _registration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = AssistantContextScope.maybeOf(context);
    if (identical(next, _coordinator)) return;
    _registration?.dispose();
    _coordinator = next;
    _registration = next?.register(
      AssistantContextContribution(currentPage: () => widget.currentPage()),
    );
  }

  @override
  void dispose() {
    _registration?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class AssistantContextScope extends InheritedWidget {
  const AssistantContextScope({
    super.key,
    required this.coordinator,
    this.assistantController,
    this.presentationController,
    this.studyModeController,
    this.openAssistant,
    this.openAssistantWithMailReference,
    required super.child,
  });

  final AssistantContextCoordinator coordinator;
  final AiAssistantController? assistantController;
  final AssistantPresentationController? presentationController;
  final StudyModeController? studyModeController;
  final Future<void> Function()? openAssistant;
  final Future<void> Function(AssistantMailReference reference)?
  openAssistantWithMailReference;

  static AssistantContextCoordinator? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AssistantContextScope>()
        ?.coordinator;
  }

  static AssistantContextCoordinator of(BuildContext context) {
    final coordinator = maybeOf(context);
    assert(coordinator != null, 'AssistantContextScope is missing.');
    return coordinator!;
  }

  static Future<void> Function()? maybeOpenAssistantOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AssistantContextScope>()
        ?.openAssistant;
  }

  /// Opens a brand-new 小U conversation with a user-selected mail reference.
  /// The reference is an identity/draft payload, never a disguised file upload.
  static Future<void> Function(AssistantMailReference reference)?
  maybeOpenAssistantWithMailReferenceOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AssistantContextScope>()
        ?.openAssistantWithMailReference;
  }

  static AiAssistantController? maybeAssistantControllerOf(
    BuildContext context,
  ) {
    return context
        .dependOnInheritedWidgetOfExactType<AssistantContextScope>()
        ?.assistantController;
  }

  static AssistantPresentationController? maybePresentationControllerOf(
    BuildContext context,
  ) {
    return context
        .dependOnInheritedWidgetOfExactType<AssistantContextScope>()
        ?.presentationController;
  }

  static StudyModeController? maybeStudyModeControllerOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AssistantContextScope>()
        ?.studyModeController;
  }

  @override
  bool updateShouldNotify(AssistantContextScope oldWidget) {
    return coordinator != oldWidget.coordinator ||
        assistantController != oldWidget.assistantController ||
        presentationController != oldWidget.presentationController ||
        studyModeController != oldWidget.studyModeController ||
        openAssistant != oldWidget.openAssistant ||
        openAssistantWithMailReference !=
            oldWidget.openAssistantWithMailReference;
  }
}

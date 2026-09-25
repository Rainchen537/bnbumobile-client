import 'package:flutter/widgets.dart';

import '../state/assistant_resource_library_controller.dart';

class AssistantResourceLibraryScope
    extends InheritedNotifier<AssistantResourceLibraryController> {
  const AssistantResourceLibraryScope({
    super.key,
    required AssistantResourceLibraryController controller,
    required super.child,
  }) : super(notifier: controller);

  static AssistantResourceLibraryController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AssistantResourceLibraryScope>()
        ?.notifier;
  }
}

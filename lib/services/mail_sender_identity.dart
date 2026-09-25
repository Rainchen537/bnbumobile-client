import '../state/app_session_controller.dart';

/// Reuses the central, current-account profile without another school request.
String? mailSenderDisplayName(AppSessionController? controller) {
  if (controller == null || !controller.isLoggedIn) return null;
  final names = <String?>[
    controller.portalProfile?.fullName,
    controller.session?.fullName,
    controller.timetable?.profile.name,
  ];
  for (final candidate in names) {
    final name = candidate?.trim() ?? '';
    if (name.isNotEmpty) return name;
  }
  return null;
}

import '../state/app_session_controller.dart';
import 'native_actions.dart';

/// All desktop resource entry points reuse the central iSpace Web session.
/// No second login, token persistence or cross-origin cookie forwarding.
class IspaceDesktopFiles {
  const IspaceDesktopFiles(
    this.controller, {
    this.actions = const NativeActions(),
  });
  final AppSessionController controller;
  final NativeActions actions;

  Future<String?> download({
    required String url,
    required String filename,
    required bool Function() isActive,
  }) async {
    final lease = controller.captureSessionLease();
    bool active() => isActive() && (lease?.isActive ?? false);
    if (!active()) return null;
    final session = await controller.prepareWebSession();
    if (!active()) return null;
    final sameOrigin = urlsHaveSameOrigin(url, session.baseUrl);
    return actions.downloadDesktopFile(
      url: url,
      filename: filename,
      isActive: active,
      cookieHeader: sameOrigin
          ? session.cookies.map((c) => '${c.name}=${c.value}').join('; ')
          : '',
      cookieOrigin: sameOrigin ? session.baseUrl : '',
    );
  }
}

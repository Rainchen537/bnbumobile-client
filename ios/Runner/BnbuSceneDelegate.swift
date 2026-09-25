import Flutter
import UIKit

@objc(BnbuSceneDelegate)
final class BnbuSceneDelegate: FlutterSceneDelegate {
  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    (UIApplication.shared.delegate as? AppDelegate)?.synchronizeLiveActivityFromCachedSnapshot()
  }

  override func sceneWillResignActive(_ scene: UIScene) {
    (UIApplication.shared.delegate as? AppDelegate)?.restoreEcardBrightness()
    super.sceneWillResignActive(scene)
  }

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    for context in connectionOptions.urlContexts {
      _ = BnbuAppNavigationBridge.shared.handle(url: context.url)
    }
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let remaining = Set(
      URLContexts.filter { !BnbuAppNavigationBridge.shared.handle(url: $0.url) }
    )
    guard !remaining.isEmpty else { return }
    super.scene(scene, openURLContexts: remaining)
  }
}

import UIKit

/// Keep native UI in the window that owns the calling Flutter engine. Looking
/// up an arbitrary key window can put private files in a different scene.
enum BnbuNativePresentation {
  static func presenter(for source: UIViewController?) -> UIViewController? {
    guard let source,
      let window = source.viewIfLoaded?.window,
      !window.isHidden,
      window.windowScene?.activationState == .foregroundActive,
      let root = window.rootViewController,
      let presenter = topViewController(from: root),
      presenter.viewIfLoaded?.window === window
    else {
      return nil
    }
    return presenter
  }

  static func topViewController(from root: UIViewController) -> UIViewController? {
    // Do not race a UIKit transition or stack our UI on a system picker/alert.
    guard !root.isBeingDismissed, !root.isBeingPresented,
      root.transitionCoordinator == nil,
      !(root is UIAlertController),
      !(root is UIActivityViewController),
      !(root is UIDocumentPickerViewController)
    else {
      return nil
    }
    if let presented = root.presentedViewController {
      return topViewController(from: presented)
    }
    if let navigation = root as? UINavigationController,
      let visible = navigation.visibleViewController
    {
      return topViewController(from: visible)
    }
    if let tabs = root as? UITabBarController,
      let selected = tabs.selectedViewController
    {
      return topViewController(from: selected)
    }
    return root
  }
}

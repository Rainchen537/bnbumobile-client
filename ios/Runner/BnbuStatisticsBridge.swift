import Foundation
import UserNotifications
#if os(macOS)
import Cocoa
import FlutterMacOS
#else
import Flutter
#endif

/// Read-only evidence bridge; it neither schedules notifications nor sends data.
final class BnbuStatisticsBridge {
  static let shared = BnbuStatisticsBridge()
  private var channel: FlutterMethodChannel?
#if os(macOS)
  private weak var window: NSWindow?
  private var observers: [NSObjectProtocol] = []
  private var lastVisible: Bool?
  private var revision = 0
#endif

  func configure(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "bnbu/apple_statistics", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "readDelivered":
        self.readDelivered(arguments: call.arguments, result: result)
      case "getVisibility":
#if os(macOS)
        self.updateVisibility()
        result(self.visibilitySnapshot)
#else
        result(FlutterMethodNotImplemented)
#endif
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func readDelivered(arguments: Any?, result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any],
      let owner = args["owner"] as? String, BnbuStatisticsObservation.validOwner(owner),
      let since = args["since_ms"] as? NSNumber,
      CFGetTypeID(since) != CFBooleanGetTypeID(),
      since.doubleValue.isFinite, since.doubleValue > 0,
      since.doubleValue <= Date().timeIntervalSince1970 * 1000
    else {
      result(FlutterError(code: "invalid_statistics_context", message: "Consent context required", details: nil))
      return
    }
    let consentAt = Date(timeIntervalSince1970: since.doubleValue / 1000)
    UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
      let now = Date()
      // Only notifications still present in Notification Center have evidence.
      // Absence is unknown, never a failed/zero/scheduled-to-delivered inference.
      let observations = notifications.compactMap { notification in
        BnbuStatisticsObservation.decode(
          payload: notification.request.content.userInfo["payload"] as? String,
          isLocal: !(notification.request.trigger is UNPushNotificationTrigger),
          deliveredAt: notification.date, owner: owner, consentAt: consentAt, now: now
        )
      }
      DispatchQueue.main.async { result(observations) }
    }
  }

#if os(macOS)
  func observeMainWindow(_ window: NSWindow) {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers.removeAll()
    self.window = window
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
      self?.setVisible(false)
    })
    for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                 NSWindow.didBecomeKeyNotification, NSWindow.didChangeOcclusionStateNotification] {
      observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
        self?.updateVisibility()
      })
    }
    for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
      observers.append(center.addObserver(forName: name, object: NSApp, queue: .main) { [weak self] _ in
        self?.updateVisibility()
      })
    }
    updateVisibility()
  }

  private var visibilitySnapshot: [String: Any] {
    ["visible": lastVisible ?? false, "revision": revision]
  }

  private func updateVisibility() {
    guard let window else { return }
    // Focus loss, another window covering the App and system dialogs do not
    // constitute closing/hiding the main window.
    setVisible(window.isVisible && !window.isMiniaturized && !NSApp.isHidden)
  }

  private func setVisible(_ visible: Bool) {
    guard visible != lastVisible else { return }
    lastVisible = visible
    revision += 1
    channel?.invokeMethod("visibilityChanged", arguments: visibilitySnapshot)
  }
#endif
}

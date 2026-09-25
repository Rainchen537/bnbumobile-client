import Flutter
import Foundation

final class BnbuAppNavigationBridge {
  static let shared = BnbuAppNavigationBridge()

  private let channelName = "ispace/app_navigation"
  private let supportedSources = Set(["live-activity", "widget"])
  private let supportedDestinations = Set(["home", "mail", "ispace", "schedule", "user"])
  private var channel: FlutterMethodChannel?
  private var pendingDestinations: [String] = []

  private init() {}

  func configure(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "takePendingDestination":
        result(self.takePendingDestination())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    notifyFlutterIfNeeded()
  }

  @discardableResult
  func handle(url: URL) -> Bool {
    guard
      let configuredScheme = Bundle.main.object(
        forInfoDictionaryKey: "BnbuAppURLScheme"
      ) as? String,
      url.scheme?.caseInsensitiveCompare(configuredScheme) == .orderedSame,
      let source = url.host?.lowercased(),
      supportedSources.contains(source)
    else {
      return false
    }
    let destination = url.pathComponents.dropFirst().first?.lowercased() ?? "home"
    guard supportedDestinations.contains(destination) else {
      return false
    }
    pendingDestinations.append(destination)
    notifyFlutterIfNeeded()
    return true
  }

  private func takePendingDestination() -> String? {
    guard !pendingDestinations.isEmpty else { return nil }
    return pendingDestinations.removeFirst()
  }

  private func notifyFlutterIfNeeded() {
    guard !pendingDestinations.isEmpty else { return }
    channel?.invokeMethod("navigationAvailable", arguments: nil)
  }
}

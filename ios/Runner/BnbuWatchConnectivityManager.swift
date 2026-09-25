import Foundation
import WatchConnectivity

/// Sends the same privacy-minimized snapshot used by the system widgets to the
/// paired Apple Watch. Credentials and web sessions never enter this channel.
final class BnbuWatchConnectivityManager: NSObject, WCSessionDelegate {
  static let shared = BnbuWatchConnectivityManager()

  private let snapshotKey = "snapshot"
  private let clearedKey = "cleared"
  private let requestSnapshotKey = "requestSnapshot"
  private let interfaceLanguageKey = "interfaceLanguage"
  private let supportedInterfaceLanguages: Set<String> = ["zh-Hans", "zh-Hant", "en"]
  private let stateQueue = DispatchQueue(label: "bnbu.watch-connectivity.watch-state")
  private var latestSnapshotJSON: String?
  private var latestInterfaceLanguage: String?

  private override init() {
    super.init()
  }

  func start(initialSnapshotJSON: String?) {
    stateQueue.sync {
      latestSnapshotJSON = initialSnapshotJSON
      latestInterfaceLanguage = interfaceLanguage(in: initialSnapshotJSON)
    }
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    session.activate()
  }

  func update(snapshotJSON: String) {
    stateQueue.sync {
      latestSnapshotJSON = snapshotJSON
      if let language = interfaceLanguage(in: snapshotJSON) {
        latestInterfaceLanguage = language
      }
    }
    publishLatestContext()
  }

  func updateInterfaceLanguage(_ languageTag: String) {
    guard supportedInterfaceLanguages.contains(languageTag) else { return }
    stateQueue.sync {
      latestInterfaceLanguage = languageTag
    }
    publishLatestContext()
  }

  func clear() {
    stateQueue.sync {
      latestSnapshotJSON = nil
    }
    publishLatestContext()
  }

  private func publishLatestContext() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard session.activationState == .activated else { return }
    let context = currentContext()
    do {
      try session.updateApplicationContext(context)
    } catch {
      // The next snapshot update or watch request retries delivery. Widget
      // refresh must remain independent from WatchConnectivity availability.
    }
    if session.isReachable {
      session.sendMessage(context, replyHandler: nil, errorHandler: nil)
    }
  }

  private func currentContext() -> [String: Any] {
    stateQueue.sync {
      var context: [String: Any]
      if let latestSnapshotJSON {
        context = [snapshotKey: latestSnapshotJSON]
      } else {
        context = [clearedKey: true]
      }
      if let latestInterfaceLanguage {
        context[interfaceLanguageKey] = latestInterfaceLanguage
      }
      return context
    }
  }

  private func interfaceLanguage(in snapshotJSON: String?) -> String? {
    guard
      let snapshotJSON,
      let data = snapshotJSON.data(using: .utf8),
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let language = object[interfaceLanguageKey] as? String,
      supportedInterfaceLanguages.contains(language)
    else {
      return nil
    }
    return language
  }

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    guard activationState == .activated, error == nil else { return }
    publishLatestContext()
  }

  func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    guard message[requestSnapshotKey] as? Bool == true else {
      replyHandler([:])
      return
    }
    replyHandler(currentContext())
  }

  func sessionDidBecomeInactive(_ session: WCSession) {}

  func sessionReachabilityDidChange(_ session: WCSession) {
    guard session.isReachable else { return }
    publishLatestContext()
  }

  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }
}

import Combine
import Foundation
import WatchConnectivity

enum WatchInterfaceLanguage: String, Sendable {
  case simplifiedChinese = "zh-Hans"
  case traditionalChinese = "zh-Hant"
  case english = "en"

  static var systemDefault: WatchInterfaceLanguage {
    guard let primary = Locale.preferredLanguages.first?.lowercased() else {
      return .english
    }
    guard primary.hasPrefix("zh") else { return .english }
    if primary.contains("hant") ||
      primary.contains("-tw") ||
      primary.contains("-hk") ||
      primary.contains("-mo") {
      return .traditionalChinese
    }
    return .simplifiedChinese
  }

  static func resolve(_ snapshotValue: String?) -> WatchInterfaceLanguage {
    guard let snapshotValue else { return .systemDefault }
    return WatchInterfaceLanguage(rawValue: snapshotValue) ?? .systemDefault
  }

  var localeIdentifier: String {
    switch self {
    case .simplifiedChinese: "zh_CN"
    case .traditionalChinese: "zh_TW"
    case .english: "en_US"
    }
  }

  func text(_ simplified: String, _ traditional: String, _ english: String) -> String {
    switch self {
    case .simplifiedChinese: simplified
    case .traditionalChinese: traditional
    case .english: english
    }
  }
}

struct WatchCourse: Decodable, Identifiable, Sendable {
  let title: String
  let code: String
  let room: String
  let teacher: String?
  let startsAt: Date
  let endsAt: Date
  let isTaCourse: Bool

  var id: String {
    "\(title)|\(room)|\(startsAt.timeIntervalSince1970)"
  }
}

struct WatchDeadline: Decodable, Identifiable, Sendable {
  let title: String
  let courseName: String
  let dueAt: Date

  var id: String {
    "\(title)|\(dueAt.timeIntervalSince1970)"
  }
}

struct WatchSnapshot: Decodable, Sendable {
  let schemaVersion: Int
  let generatedAt: Date
  let campusTimeZone: String
  let interfaceLanguage: String?
  let courses: [WatchCourse]
  let deadlines: [WatchDeadline]

  var resolvedInterfaceLanguage: WatchInterfaceLanguage {
    WatchInterfaceLanguage.resolve(interfaceLanguage)
  }
}

@MainActor
final class WatchSnapshotStore: NSObject, ObservableObject {
  @Published private(set) var snapshot: WatchSnapshot?
  @Published private(set) var isRefreshing = false
  @Published private(set) var interfaceLanguage = WatchInterfaceLanguage.systemDefault

  private let cachedSnapshotKey = "bnbu.watch.snapshot.v1"
  private let cachedInterfaceLanguageKey = "bnbu.watch.interface-language.v1"
  private let snapshotKey = "snapshot"
  private let clearedKey = "cleared"
  private let requestSnapshotKey = "requestSnapshot"
  private let interfaceLanguageKey = "interfaceLanguage"
  private let decoder: JSONDecoder

  override init() {
    decoder = BnbuSnapshotCodec.makeDecoder()
    super.init()
    restoreCachedInterfaceLanguage()
    restoreCachedSnapshot()
    activateSession()
  }

  func refresh() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard session.activationState == .activated else {
      isRefreshing = true
      session.activate()
      return
    }
    requestLatestSnapshot(from: session)
  }

  private func activateSession() {
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    session.delegate = self
    isRefreshing = true
    session.activate()
  }

  private func restoreCachedSnapshot() {
    guard let payload = UserDefaults.standard.string(forKey: cachedSnapshotKey) else {
      return
    }
    apply(snapshotJSON: payload, cache: false)
  }

  private func restoreCachedInterfaceLanguage() {
    apply(
      interfaceLanguageValue: UserDefaults.standard.string(forKey: cachedInterfaceLanguageKey),
      cache: false
    )
  }

  private func apply(context: [String: Any]) {
    apply(interfaceLanguageValue: context[interfaceLanguageKey] as? String, cache: true)
    if context[clearedKey] as? Bool == true {
      UserDefaults.standard.removeObject(forKey: cachedSnapshotKey)
      snapshot = nil
      return
    }
    guard let payload = context[snapshotKey] as? String else { return }
    apply(snapshotJSON: payload, cache: true)
  }

  private func apply(snapshotJSON: String, cache: Bool) {
    guard
      let data = snapshotJSON.data(using: .utf8),
      let decoded = try? decoder.decode(WatchSnapshot.self, from: data),
      decoded.schemaVersion == 1
    else {
      return
    }
    snapshot = decoded
    apply(interfaceLanguageValue: decoded.interfaceLanguage, cache: cache)
    if cache {
      UserDefaults.standard.set(snapshotJSON, forKey: cachedSnapshotKey)
    }
  }

  private func apply(interfaceLanguageValue: String?, cache: Bool) {
    guard
      let interfaceLanguageValue,
      let resolved = WatchInterfaceLanguage(rawValue: interfaceLanguageValue)
    else {
      return
    }
    interfaceLanguage = resolved
    if cache {
      UserDefaults.standard.set(interfaceLanguageValue, forKey: cachedInterfaceLanguageKey)
    }
  }

  private func requestLatestSnapshot(from session: WCSession) {
    guard session.isReachable else {
      isRefreshing = false
      apply(context: session.receivedApplicationContext)
      return
    }
    isRefreshing = true
    session.sendMessage(
      [requestSnapshotKey: true],
      replyHandler: { [weak self] reply in
        Task { @MainActor in
          self?.apply(context: reply)
          self?.isRefreshing = false
        }
      },
      errorHandler: { [weak self] _ in
        Task { @MainActor in
          self?.isRefreshing = false
        }
      }
    )
  }
}

extension WatchSnapshotStore: WCSessionDelegate {
  nonisolated func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    let context = session.receivedApplicationContext
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.apply(context: context)
      self.isRefreshing = false
      guard activationState == .activated, error == nil else { return }
      self.requestLatestSnapshot(from: session)
    }
  }

  nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
    guard session.isReachable else { return }
    Task { @MainActor [weak self] in
      self?.requestLatestSnapshot(from: session)
    }
  }

  nonisolated func session(
    _ session: WCSession,
    didReceiveApplicationContext applicationContext: [String: Any]
  ) {
    Task { @MainActor [weak self] in
      self?.apply(context: applicationContext)
      self?.isRefreshing = false
    }
  }

  nonisolated func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any]
  ) {
    Task { @MainActor [weak self] in
      self?.apply(context: message)
      self?.isRefreshing = false
    }
  }
}

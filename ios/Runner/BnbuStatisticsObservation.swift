import Foundation
import CoreFoundation

/// A narrow projection of OS evidence. Never read notification title/body here.
enum BnbuStatisticsObservation {
  static let retention: TimeInterval = 31 * 24 * 60 * 60

  static func decode(
    payload: String?, isLocal: Bool, deliveredAt: Date,
    owner: String, consentAt: Date, now: Date
  ) -> [String: Any]? {
    guard isLocal, validOwner(owner), consentAt <= now,
      deliveredAt >= consentAt, deliveredAt <= now,
      deliveredAt >= now.addingTimeInterval(-retention),
      let payload, payload.utf8.count <= 8192,
      let data = payload.data(using: .utf8),
      let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let stamp = envelope["bnbu_statistics"] as? [String: Any],
      stamp["owner"] as? String == owner,
      let id = stamp["notification_id"] as? String,
      id.range(of: "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$", options: .regularExpression) != nil,
      let kind = stamp["kind"] as? String, ["ddl", "schedule"].contains(kind),
      let environment = stamp["environment"] as? String,
      ["production", "development", "automation"].contains(environment),
      let version = stamp["app_version"] as? String,
      version.range(of: "^[0-9A-Za-z.+_-]{1,32}$", options: .regularExpression) != nil,
      let created = stamp["created_at_ms"] as? NSNumber,
      CFGetTypeID(created) != CFBooleanGetTypeID(),
      created.doubleValue.isFinite
    else { return nil }
    let createdAt = Date(timeIntervalSince1970: created.doubleValue / 1000)
    guard createdAt >= consentAt, createdAt <= deliveredAt else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return [
      "notification_id": id.lowercased(), "kind": kind,
      "occurred_at": formatter.string(from: deliveredAt),
      "stage": "displayed", "evidence": "observed_notification_center",
      "environment": environment, "app_version": version,
    ]
  }

  static func validOwner(_ owner: String) -> Bool {
    owner.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
  }
}

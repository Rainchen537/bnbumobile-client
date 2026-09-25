import ActivityKit
import Foundation

struct BnbuLiveActivityAttributes: ActivityAttributes {
  struct ContentState: Codable, Hashable {
    let kind: String
    let destination: String?
    let title: String
    let detail: String
    let location: String
    let eventAt: Date
    let endAt: Date
  }

  let eventID: String
  let campusTimeZone: String
}

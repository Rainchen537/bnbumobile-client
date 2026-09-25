import ActivityKit
import Foundation
import UIKit
import os

@MainActor
@available(iOS 16.2, *)
final class BnbuLiveActivityManager {
  static let shared = BnbuLiveActivityManager()
  private static let maximumCourseMergeGap: TimeInterval = 15 * 60

  private var pendingTask: Task<Void, Never>?
  private var dismissalTask: Task<Void, Never>?

  private var transitionTimer: Timer?
  private var latestSnapshotJSON: String?
  private static let logger = Logger(subsystem: "me.bnbu.live-activity", category: "lifecycle")

  private init() {
    NotificationCenter.default.addObserver(
      self, selector: #selector(stopForegroundTimer),
      name: UIApplication.willResignActiveNotification, object: nil
    )
    NotificationCenter.default.addObserver(
      self, selector: #selector(clockChanged),
      name: UIApplication.significantTimeChangeNotification, object: nil
    )
  }

  @objc private func stopForegroundTimer() {
    transitionTimer?.invalidate()
    transitionTimer = nil
  }

  @objc private func clockChanged() {
    guard UIApplication.shared.applicationState == .active,
          let payload = latestSnapshotJSON else { return }
    synchronize(snapshotJSON: payload)
  }

  func synchronize(snapshotJSON: String) {
    latestSnapshotJSON = snapshotJSON
    stopForegroundTimer()
    pendingTask?.cancel()
    dismissalTask?.cancel()
    pendingTask = Task {
      guard !Task.isCancelled else { return }
      await synchronizeActivity(snapshotJSON: snapshotJSON, now: .now)
    }
  }

  func clear() {
    latestSnapshotJSON = nil
    stopForegroundTimer()
    pendingTask?.cancel()
    dismissalTask?.cancel()
    pendingTask = Task {
      await endAllActivities()
    }
  }

  private func synchronizeActivity(snapshotJSON: String, now: Date) async {
    guard !Task.isCancelled else { return }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      Self.logger.notice("activities_disabled")
      await endAllActivities()
      return
    }
    let snapshot: Snapshot
    do {
      snapshot = try Self.decoder.decode(Snapshot.self, from: Data(snapshotJSON.utf8))
    } catch {
      Self.logger.error("snapshot_decode_failed")
      return
    }

    let preferences = snapshot.liveActivity ?? .defaults
    guard preferences.enabled else {
      await endAllActivities()
      return
    }

    scheduleNextTransition(snapshot: snapshot, preferences: preferences, now: now)
    guard let candidate = selectCandidate(
      from: snapshot,
      preferences: preferences,
      now: now
    ) else {
      await endAllActivities()
      return
    }

    guard !Task.isCancelled else { return }

    let activities = Activity<BnbuLiveActivityAttributes>.activities
    if let matching = activities.first(where: {
      $0.attributes.eventID == candidate.eventID &&
        ($0.activityState == .active || $0.activityState == .stale)
    }) {
      await matching.update(candidate.content)
      guard !Task.isCancelled else { return }
      for activity in activities where activity.id != matching.id {
        guard !Task.isCancelled else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
      }
      guard !Task.isCancelled else { return }
      scheduleDismissal(for: matching, at: candidate.dismissAt)
      return
    }

    // Local requests cannot start an activity while the app is in background.
    // Keep the current activity until the foreground reconciliation can replace it.
    guard UIApplication.shared.applicationState == .active else {
      Self.logger.notice("start_deferred_until_foreground")
      return
    }
    await endAllActivities()
    guard !Task.isCancelled, UIApplication.shared.applicationState == .active else { return }
    let attributes = BnbuLiveActivityAttributes(
      eventID: candidate.eventID,
      campusTimeZone: snapshot.campusTimeZone
    )
    do {
      let activity = try Activity.request(
        attributes: attributes,
        content: candidate.content,
        pushType: nil
      )
      Self.logger.info("activity_started")
      scheduleDismissal(for: activity, at: candidate.dismissAt)
    } catch {
      // Error descriptions may contain content. Log only a numeric system code.
      Self.logger.error("activity_request_failed code=\((error as NSError).code)")
    }
  }

  func selectCandidate(
    from snapshot: Snapshot,
    preferences: LiveActivityPreferences,
    now: Date
  ) -> Candidate? {
    let nextCourse: Course?
    if preferences.courseEnabled != false && preferences.classLeadMinutes > 0 {
      let classCutoff = now.addingTimeInterval(preferences.classLeadTime)
      nextCourse = mergedCourses(snapshot.courses)
        .filter {
          courseDismissAt(for: $0, preferences: preferences) > now &&
            $0.startsAt <= classCutoff
        }
        .sorted { $0.startsAt < $1.startsAt }
        .first
    } else {
      nextCourse = nil
    }

    if let course = nextCourse {
      let dismissAt = courseDismissAt(for: course, preferences: preferences)
      let state = BnbuLiveActivityAttributes.ContentState(
        kind: "course",
        destination: "schedule",
        title: course.title,
        detail: "",
        location: course.room,
        eventAt: course.startsAt,
        endAt: course.endsAt
      )
      return Candidate(
        eventID: "course-layout-2|\(course.title)|\(course.startsAt.timeIntervalSince1970)",
        content: ActivityContent(
          state: state,
          staleDate: dismissAt,
          relevanceScore: 100
        ),
        dismissAt: dismissAt
      )
    }

    guard preferences.deadlineEnabled != false && preferences.deadlineLeadMinutes > 0 else {
      return nil
    }
    let deadlineCutoff = now.addingTimeInterval(preferences.deadlineLeadTime)
    guard let deadline = snapshot.deadlines
      .filter({ $0.dueAt > now && $0.dueAt <= deadlineCutoff })
      .sorted(by: { $0.dueAt < $1.dueAt })
      .first
    else {
      return nil
    }
    let state = BnbuLiveActivityAttributes.ContentState(
      kind: "deadline",
      destination: "ispace",
      title: deadline.title,
      detail: deadline.courseName,
      location: "",
      eventAt: deadline.dueAt,
      endAt: deadline.dueAt
    )
    return Candidate(
      eventID: "deadline-layout-5|\(deadline.title)|\(deadline.dueAt.timeIntervalSince1970)",
      content: ActivityContent(
        state: state,
        staleDate: deadline.dueAt,
        relevanceScore: 80
      ),
      dismissAt: nil
    )
  }

  // A single timer at the next policy boundary, only while the app is active.
  // This is not a background wake-up mechanism or an ActivityKit scheduled start.
  private func scheduleNextTransition(
    snapshot: Snapshot, preferences: LiveActivityPreferences, now: Date
  ) {
    guard UIApplication.shared.applicationState == .active,
          let next = nextTransition(from: snapshot, preferences: preferences, now: now)
    else { return }
    let timer = Timer(timeInterval: max(next.timeIntervalSinceNow, 0.05), repeats: false) {
      [weak self] _ in
      Task { @MainActor [weak self] in self?.clockChanged() }
    }
    transitionTimer = timer
    RunLoop.main.add(timer, forMode: .common)
  }

  func nextTransition(
    from snapshot: Snapshot, preferences: LiveActivityPreferences, now: Date
  ) -> Date? {
    guard preferences.enabled else { return nil }
    var boundaries: [Date] = []
    if preferences.courseEnabled != false && preferences.classLeadMinutes > 0 {
      for course in mergedCourses(snapshot.courses) {
        boundaries.append(course.startsAt.addingTimeInterval(-preferences.classLeadTime))
        boundaries.append(courseDismissAt(for: course, preferences: preferences))
      }
    }
    if preferences.deadlineEnabled != false && preferences.deadlineLeadMinutes > 0 {
      for deadline in snapshot.deadlines {
        boundaries.append(deadline.dueAt.addingTimeInterval(-preferences.deadlineLeadTime))
        boundaries.append(deadline.dueAt)
      }
    }
    return boundaries.filter { $0 > now }.min()
  }

  private func courseDismissAt(
    for course: Course,
    preferences: LiveActivityPreferences
  ) -> Date {
    min(
      course.endsAt,
      course.startsAt.addingTimeInterval(preferences.courseDismissAfterStartTime)
    )
  }

  private func scheduleDismissal(
    for activity: Activity<BnbuLiveActivityAttributes>,
    at dismissAt: Date?
  ) {
    dismissalTask?.cancel()
    guard let dismissAt else { return }
    let eventID = activity.attributes.eventID
    dismissalTask = Task {
      let delay = max(dismissAt.timeIntervalSinceNow, 0)
      if delay > 0 {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      }
      guard !Task.isCancelled else { return }
      guard let current = Activity<BnbuLiveActivityAttributes>.activities.first(
        where: { $0.attributes.eventID == eventID }
      ) else {
        return
      }
      await current.end(nil, dismissalPolicy: .immediate)
    }
  }

  private func mergedCourses(_ courses: [Course]) -> [Course] {
    let sortedCourses = courses.sorted { lhs, rhs in
      if lhs.startsAt == rhs.startsAt {
        return lhs.endsAt < rhs.endsAt
      }
      return lhs.startsAt < rhs.startsAt
    }
    var result: [Course] = []
    for course in sortedCourses {
      guard let previous = result.last,
            shouldMerge(previous, with: course)
      else {
        result.append(course)
        continue
      }
      result[result.count - 1] = Course(
        title: previous.title,
        code: previous.code,
        room: previous.room,
        startsAt: previous.startsAt,
        endsAt: max(previous.endsAt, course.endsAt)
      )
    }
    return result
  }

  private func shouldMerge(_ previous: Course, with next: Course) -> Bool {
    normalized(previous.title) == normalized(next.title) &&
      normalized(previous.code) == normalized(next.code) &&
      normalized(previous.room) == normalized(next.room) &&
      next.startsAt <= previous.endsAt.addingTimeInterval(Self.maximumCourseMergeGap)
  }

  private func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private func endAllActivities() async {
    for activity in Activity<BnbuLiveActivityAttributes>.activities {
      guard !Task.isCancelled else { return }
      await activity.end(nil, dismissalPolicy: .immediate)
    }
  }

  private static let decoder = BnbuSnapshotCodec.makeDecoder()
}

@available(iOS 16.2, *)
extension BnbuLiveActivityManager {
  struct Snapshot: Decodable {
    let campusTimeZone: String
    let courses: [Course]
    let deadlines: [Deadline]
    let liveActivity: LiveActivityPreferences?
  }

  struct LiveActivityPreferences: Decodable {
    static let defaults = LiveActivityPreferences(
      enabled: true,
      courseEnabled: true,
      deadlineEnabled: false,
      classLeadMinutes: 15,
      courseDismissAfterStartMinutes: 5,
      deadlineLeadMinutes: 720
    )

    let enabled: Bool
    let courseEnabled: Bool?
    let deadlineEnabled: Bool?
    let classLeadMinutes: Int
    let courseDismissAfterStartMinutes: Int?
    let deadlineLeadMinutes: Int

    var classLeadTime: TimeInterval {
      TimeInterval(min(max(classLeadMinutes, 5), 120) * 60)
    }

    var deadlineLeadTime: TimeInterval {
      TimeInterval(min(max(deadlineLeadMinutes, 30), 2880) * 60)
    }

    var courseDismissAfterStartTime: TimeInterval {
      TimeInterval(min(max(courseDismissAfterStartMinutes ?? 5, 0), 20) * 60)
    }
  }

  struct Course: Decodable {
    let title: String
    let code: String
    let room: String
    let startsAt: Date
    let endsAt: Date
  }

  struct Deadline: Decodable {
    let title: String
    let courseName: String
    let dueAt: Date
  }

  struct Candidate {
    let eventID: String
    let content: ActivityContent<BnbuLiveActivityAttributes.ContentState>
    let dismissAt: Date?
  }
}

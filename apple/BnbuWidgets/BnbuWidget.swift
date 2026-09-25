import AppIntents
import SwiftUI
import WidgetKit
#if os(macOS)
import Intents
#endif

private var appGroupIdentifier: String? {
  guard
    let identifier = Bundle.main.object(
      forInfoDictionaryKey: "BnbuAppGroupIdentifier"
    ) as? String,
    !identifier.isEmpty,
    !identifier.hasPrefix("group.invalid.")
  else {
    return nil
  }
  return identifier
}
private let snapshotDefaultsKey = "bnbu.widget.snapshot.v1"
private let snapshotFileName = "bnbu-widget-snapshot-v1.json"

private let widgetKind = "BnbuCampusWidget"

private var widgetDisplayName: LocalizedStringKey {
#if os(macOS)
  return "BNBU.ME · Mac"
#else
  return "BNBU.ME · iPhone"
#endif
}

private func widgetDestinationURL(for content: BnbuWidgetContent) -> URL? {
  guard
    let scheme = Bundle.main.object(
      forInfoDictionaryKey: "BnbuAppURLScheme"
    ) as? String,
    !scheme.isEmpty
  else {
    return nil
  }
  let destination: String
  switch content {
  case .overview:
    destination = "home"
  case .deadlines:
    destination = "ispace"
  case .schedule:
    destination = "schedule"
  }
  var components = URLComponents()
  components.scheme = scheme
  components.host = "widget"
  components.path = "/\(destination)"
  return components.url
}

private enum WidgetInterfaceLanguage: String {
  case simplifiedChinese = "zh-Hans"
  case traditionalChinese = "zh-Hant"
  case english = "en"

  static var systemDefault: WidgetInterfaceLanguage {
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

  static func resolve(_ snapshotValue: String?) -> WidgetInterfaceLanguage {
    guard let snapshotValue else { return .systemDefault }
    return WidgetInterfaceLanguage(rawValue: snapshotValue) ?? .systemDefault
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

enum BnbuWidgetContent: String, AppEnum {
  case overview
  case deadlines
  case schedule

  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "显示内容")

  static var caseDisplayRepresentations: [BnbuWidgetContent: DisplayRepresentation] = [
    .overview: "概况",
    .schedule: "课表",
    .deadlines: "DDL",
  ]
}

enum BnbuWidgetScheduleLayout: String, AppEnum {
  case horizontal
  case vertical

  static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "课表格式")

  static var caseDisplayRepresentations: [BnbuWidgetScheduleLayout: DisplayRepresentation] = [
    .horizontal: "课表横版",
    .vertical: "课表纵版",
  ]
}

#if os(iOS)
struct BnbuWidgetConfigurationIntent: WidgetConfigurationIntent {
  static var title: LocalizedStringResource = "BNBU.ME · iPhone 小组件"
  static var description = IntentDescription(
    "选择概况时同时显示课程与 DDL；大号课表可选择横版或纵版。"
  )

  @Parameter(title: "显示内容", default: .overview)
  var content: BnbuWidgetContent

  @Parameter(title: "课表样式", default: .horizontal)
  var scheduleLayout: BnbuWidgetScheduleLayout

  init() {
    content = .overview
    scheduleLayout = .horizontal
  }

  static var parameterSummary: some ParameterSummary {
    Switch(.widgetFamily) {
      Case([.systemLarge, .systemExtraLarge]) {
        Summary("显示 \(\.$content)，使用 \(\.$scheduleLayout)")
      }
      DefaultCase {
        Summary("显示 \(\.$content)")
      }
    }
  }
}
#endif

private struct BnbuWidgetSelection {
  let content: BnbuWidgetContent
  let scheduleLayout: BnbuWidgetScheduleLayout

  init(
    content: BnbuWidgetContent,
    scheduleLayout: BnbuWidgetScheduleLayout
  ) {
    self.content = content
    self.scheduleLayout = scheduleLayout
  }

  static let defaultValue = BnbuWidgetSelection(
    content: .overview,
    scheduleLayout: .horizontal
  )

#if os(iOS)
  init(_ configuration: BnbuWidgetConfigurationIntent) {
    content = configuration.content
    scheduleLayout = configuration.scheduleLayout
  }
#else
  init(_ configuration: BnbuWidgetConfigurationIntent) {
    switch configuration.content {
    case .overview:
      content = .overview
    case .deadlines:
      content = .deadlines
    case .schedule:
      content = .schedule
    default:
      content = .overview
    }

    switch configuration.scheduleLayout {
    case .vertical:
      scheduleLayout = .vertical
    default:
      scheduleLayout = .horizontal
    }
  }
#endif
}

private struct WidgetCourse: Decodable, Identifiable {
  let title: String
  let code: String
  let room: String
  let teacher: String?
  let startsAt: Date
  let endsAt: Date
  let isTaCourse: Bool
  let lightAccentHex: String?
  let darkAccentHex: String?

  var id: String {
    "\(title)|\(room)|\(startsAt.timeIntervalSince1970)"
  }
}

private struct WidgetDeadline: Decodable, Identifiable {
  let title: String
  let courseName: String
  let dueAt: Date

  var id: String {
    "\(title)|\(dueAt.timeIntervalSince1970)"
  }
}

private struct WeeklyTimelineSegment {
  let startMinutes: Int
  let endMinutes: Int
  let displayMinutes: Int

  var actualMinutes: Int {
    max(1, endMinutes - startMinutes)
  }
}

private struct WidgetSnapshot: Decodable {
  let schemaVersion: Int
  let generatedAt: Date
  let campusTimeZone: String
  let interfaceLanguage: String?
  let courses: [WidgetCourse]
  let deadlines: [WidgetDeadline]

  var resolvedInterfaceLanguage: WidgetInterfaceLanguage {
    WidgetInterfaceLanguage.resolve(interfaceLanguage)
  }

  static let preview = WidgetSnapshot(
    schemaVersion: 1,
    generatedAt: .now,
    campusTimeZone: "Asia/Shanghai",
    interfaceLanguage: nil,
    courses: [
      WidgetCourse(
        title: "Academic English",
        code: "ENG1001",
        room: "T2-201",
        teacher: "Dr. Chen",
        startsAt: .now.addingTimeInterval(45 * 60),
        endsAt: .now.addingTimeInterval(95 * 60),
        isTaCourse: false,
        lightAccentHex: "#005BAC",
        darkAccentHex: "#62AFFF"
      ),
      WidgetCourse(
        title: "Programming",
        code: "COMP1001",
        room: "T3-105",
        teacher: "Prof. Li",
        startsAt: .now.addingTimeInterval(3 * 60 * 60),
        endsAt: .now.addingTimeInterval(4 * 60 * 60),
        isTaCourse: false,
        lightAccentHex: "#6A3FA0",
        darkAccentHex: "#B996EB"
      ),
    ],
    deadlines: [
      WidgetDeadline(
        title: "Individual assignment",
        courseName: "Programming",
        dueAt: .now.addingTimeInterval(26 * 60 * 60)
      )
    ]
  )

  static let empty = WidgetSnapshot(
    schemaVersion: 1,
    generatedAt: .distantPast,
    campusTimeZone: "Asia/Shanghai",
    interfaceLanguage: nil,
    courses: [],
    deadlines: []
  )
}

private struct BnbuWidgetEntry: TimelineEntry {
  let date: Date
  let configuration: BnbuWidgetSelection
  let snapshot: WidgetSnapshot
}

#if os(iOS)
private struct BnbuWidgetProvider: AppIntentTimelineProvider {
  func placeholder(in context: Context) -> BnbuWidgetEntry {
    BnbuWidgetEntry(
      date: .now,
      configuration: .defaultValue,
      snapshot: .preview
    )
  }

  func snapshot(
    for configuration: BnbuWidgetConfigurationIntent,
    in context: Context
  ) async -> BnbuWidgetEntry {
    BnbuWidgetEntry(
      date: .now,
      configuration: BnbuWidgetSelection(configuration),
      snapshot: context.isPreview ? .preview : loadSnapshot()
    )
  }

  func timeline(
    for configuration: BnbuWidgetConfigurationIntent,
    in context: Context
  ) async -> Timeline<BnbuWidgetEntry> {
    makeTimeline(
      for: BnbuWidgetSelection(configuration),
      in: context
    )
  }
}
#else
private struct BnbuMacWidgetProvider: IntentTimelineProvider {
  typealias Intent = BnbuWidgetConfigurationIntent
  typealias Entry = BnbuWidgetEntry

  func placeholder(in context: Context) -> BnbuWidgetEntry {
    BnbuWidgetEntry(
      date: .now,
      configuration: .defaultValue,
      snapshot: .preview
    )
  }

  func getSnapshot(
    for configuration: BnbuWidgetConfigurationIntent,
    in context: Context,
    completion: @escaping (BnbuWidgetEntry) -> Void
  ) {
    completion(
      BnbuWidgetEntry(
        date: .now,
        configuration: BnbuWidgetSelection(configuration),
        snapshot: context.isPreview ? .preview : loadSnapshot()
      )
    )
  }

  func getTimeline(
    for configuration: BnbuWidgetConfigurationIntent,
    in context: Context,
    completion: @escaping (Timeline<BnbuWidgetEntry>) -> Void
  ) {
    completion(
      makeTimeline(
        for: BnbuWidgetSelection(configuration),
        in: context
      )
    )
  }
}
#endif

private func makeTimeline(
  for configuration: BnbuWidgetSelection,
  in context: TimelineProviderContext
) -> Timeline<BnbuWidgetEntry> {
    let now = Date.now
    let snapshot = loadSnapshot()
    let entry = BnbuWidgetEntry(
      date: now,
      configuration: configuration,
      snapshot: snapshot
    )
    let regularRefreshDate = now.addingTimeInterval(15 * 60)
    let refreshDate: Date
    if configuration.content == .schedule,
       context.family == .systemSmall || context.family == .systemMedium,
       let nextCourseEnd = snapshot.courses
         .map(\.endsAt)
         .filter({ $0 > now })
         .min()
    {
      refreshDate = min(regularRefreshDate, nextCourseEnd)
    } else {
      refreshDate = regularRefreshDate
    }
    return Timeline(
      entries: [entry],
      policy: .after(refreshDate)
    )
}

private func loadSnapshot() -> WidgetSnapshot {
#if os(macOS)
  guard
    let appGroupIdentifier,
    let containerURL = FileManager.default.containerURL(
      forSecurityApplicationGroupIdentifier: appGroupIdentifier
    ),
    let data = try? Data(
      contentsOf: containerURL.appendingPathComponent(snapshotFileName)
    )
  else {
    return .empty
  }
#else
  guard
    let appGroupIdentifier,
    let defaults = UserDefaults(suiteName: appGroupIdentifier),
    let payload = defaults.string(forKey: snapshotDefaultsKey),
    let data = payload.data(using: .utf8)
  else {
    return .empty
  }
#endif
  let decoder = BnbuSnapshotCodec.makeDecoder()
  return (try? decoder.decode(WidgetSnapshot.self, from: data)) ?? .empty
}

private struct BnbuWidgetView: View {
  @Environment(\.widgetFamily) private var family
  @Environment(\.colorScheme) private var colorScheme
  let entry: BnbuWidgetEntry

  var body: some View {
    Group {
      switch entry.configuration.content {
      case .overview:
        overview
      case .deadlines:
        deadlines
      case .schedule:
        schedule
      }
    }
    .containerBackground(for: .widget) {
      LinearGradient(
        colors: [Color.blue.opacity(0.12), Color.cyan.opacity(0.04)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
    .widgetURL(widgetDestinationURL(for: entry.configuration.content))
  }

  private var overview: some View {
    VStack(alignment: .leading, spacing: 10) {
      header(interfaceLanguage.text("今日概览", "今日概覽", "Today's Overview"))
      if let course = nextCourse {
        courseSummary(course)
      } else {
        emptyState(
          interfaceLanguage.text(
            "近期没有课程",
            "近期沒有課程",
            "No upcoming classes"
          )
        )
      }
      Divider()
      if let deadline = upcomingDeadlines.first {
        deadlineSummary(deadline)
      } else {
        Text(
          interfaceLanguage.text(
            "近期没有 DDL",
            "近期沒有 DDL",
            "No upcoming deadlines"
          )
        )
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .frame(
      maxWidth: .infinity,
      maxHeight: .infinity,
      alignment: .topLeading
    )
  }

  private var deadlines: some View {
    VStack(alignment: .leading, spacing: 6) {
      header("DDL")
      if upcomingDeadlines.isEmpty {
        emptyState(
          interfaceLanguage.text(
            "近期没有 DDL",
            "近期沒有 DDL",
            "No upcoming deadlines"
          )
        )
      } else {
        ForEach(upcomingDeadlines.prefix(rowLimit)) { deadline in
          deadlineRow(deadline)
        }
      }
    }
    .frame(
      maxWidth: .infinity,
      maxHeight: .infinity,
      alignment: .topLeading
    )
  }

  @ViewBuilder
  private var schedule: some View {
    if usesWeeklySchedule {
      weeklySchedule
    } else {
      dailySchedule
    }
  }

  private var dailySchedule: some View {
    VStack(alignment: .leading, spacing: scheduleSpacing) {
      header(campusScheduleHeader)
      if remainingTodayCourses.isEmpty {
        emptyState(compactScheduleEmptyLabel)
      } else {
        ForEach(Array(remainingTodayCourses.prefix(scheduleRowLimit))) { course in
          compactScheduleRow(course)
        }
        if remainingTodayCourses.count > scheduleRowLimit {
          Text(additionalCoursesLabel(remainingTodayCourses.count - scheduleRowLimit))
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
    }
  }

  @ViewBuilder
  private var weeklySchedule: some View {
    switch entry.configuration.scheduleLayout {
    case .horizontal:
      weeklyTimetableSchedule
    case .vertical:
      todayVerticalSchedule
    }
  }

  private var weeklyTimetableSchedule: some View {
    VStack(alignment: .leading, spacing: 6) {
      header(interfaceLanguage.text("本周课表", "本週課表", "This Week"))
      if weekCourses.isEmpty {
        emptyState(
          interfaceLanguage.text(
            "本周没有课程",
            "本週沒有課程",
            "No classes this week"
          )
        )
      } else {
        weeklyTimelineDayHeader
        GeometryReader { geometry in
          weeklyTimelineGrid(size: geometry.size)
        }
      }
    }
  }

  private var weeklyTimelineDayHeader: some View {
    HStack(spacing: weeklyTimelineDaySpacing) {
      Color.clear
        .frame(width: weeklyTimelineTimeAxisWidth, height: 1)
      ForEach(displayedWeekDates, id: \.self) { date in
        VStack(spacing: 0) {
          Text(weekdayLabel(date))
            .font(.system(size: weeklyTimelineWeekdayFontSize, weight: .bold))
          Text(monthDayLabel(date))
            .font(
              .system(
                size: weeklyTimelineDateFontSize,
                weight: .medium,
                design: .rounded
              )
            )
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 3)
        .background(
          campusCalendar.isDate(date, inSameDayAs: entry.date)
            ? Color.blue.opacity(0.14)
            : Color.primary.opacity(0.035)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      }
    }
  }

  private func weeklyTimelineGrid(size: CGSize) -> some View {
    let gridLeft = weeklyTimelineTimeAxisWidth + weeklyTimelineDaySpacing
    let dayCount = max(1, displayedWeekDates.count)
    let totalDaySpacing = weeklyTimelineDaySpacing * CGFloat(dayCount - 1)
    let dayWidth = max(
      1,
      (size.width - gridLeft - totalDaySpacing) / CGFloat(dayCount)
    )
    return ZStack(alignment: .topLeading) {
      ForEach(weeklyTimelineMarks, id: \.self) { minutes in
        let y = weeklyTimelineGridY(minutes, height: size.height)
        Text(minutesLabel(minutes))
          .font(
            .system(
              size: weeklyTimelineTimeFontSize,
              weight: .semibold,
              design: .monospaced
            )
          )
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .frame(width: weeklyTimelineTimeAxisWidth - 4, alignment: .leading)
          .offset(y: min(max(0, y - 5), max(0, size.height - 10)))
        Rectangle()
          .fill(Color.primary.opacity(0.1))
          .frame(width: max(0, size.width - gridLeft), height: 0.5)
          .offset(x: gridLeft, y: y)
      }
      ForEach(Array(displayedWeekDates.enumerated()), id: \.element) {
        dayIndex,
        date in
        let columnX = gridLeft
          + CGFloat(dayIndex) * (dayWidth + weeklyTimelineDaySpacing)
        Rectangle()
          .fill(
            campusCalendar.isDate(date, inSameDayAs: entry.date)
              ? Color.blue.opacity(0.055)
              : Color.primary.opacity(0.018)
          )
          .frame(width: dayWidth, height: size.height)
          .offset(x: columnX)
        Rectangle()
          .fill(Color.primary.opacity(0.08))
          .frame(width: 0.5, height: size.height)
          .offset(x: columnX)
        ForEach(courses(on: date)) { course in
          let courseStart = campusMinutes(course.startsAt)
          let courseEnd = max(courseStart + 1, campusMinutes(course.endsAt))
          let courseY = weeklyTimelineGridY(courseStart, height: size.height)
          let courseBottom = weeklyTimelineGridY(courseEnd, height: size.height)
          let courseHeight = max(
            weeklyTimelineMinimumCourseHeight,
            courseBottom - courseY
          )
          weeklyTimelineCourseBlock(
            course,
            availableHeight: courseHeight
          )
            .frame(
              width: dayWidth,
              height: courseHeight,
              alignment: .topLeading
            )
            .clipped()
            .offset(x: columnX, y: courseY)
        }
      }
    }
    .frame(width: size.width, height: size.height, alignment: .topLeading)
    .clipped()
  }

  private func weeklyTimelineCourseBlock(
    _ course: WidgetCourse,
    availableHeight: CGFloat
  ) -> some View {
    let titleLineLimit = availableHeight >= 34 ? 2 : 1
    let showsRoom = !course.room.isEmpty
    return VStack(alignment: .leading, spacing: 1) {
      Text(course.title)
        .font(.system(size: weeklyTimelineCourseFontSize, weight: .semibold))
        .lineLimit(titleLineLimit)
        .allowsTightening(true)
      Spacer(minLength: 0)
      if showsRoom {
        Text(course.room)
          .font(.system(size: weeklyTimelineMetadataFontSize, weight: .medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .layoutPriority(2)
      }
    }
    .padding(.horizontal, 3)
    .padding(.vertical, 2)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(courseAccentColor(course).opacity(0.12))
    .overlay {
      Rectangle()
        .strokeBorder(courseAccentColor(course).opacity(0.3), lineWidth: 0.75)
        .overlay(alignment: .leading) {
          Rectangle()
            .fill(courseAccentColor(course))
            .frame(width: 2)
        }
    }
  }

  private var todayVerticalSchedule: some View {
    VStack(alignment: .leading, spacing: 5) {
      header(campusScheduleHeader)
      if todayCourses.isEmpty {
        emptyState(
          interfaceLanguage.text(
            "今天没有课程",
            "今天沒有課程",
            "No classes today"
          )
        )
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(todayCourses.enumerated()), id: \.element.id) {
            index,
            course in
            todayVerticalCourseRow(course)
              .padding(
                .top,
                todayVerticalTimeSpacing(
                  current: course,
                  previous: index > 0 ? todayCourses[index - 1] : nil
                )
              )
          }
        }
        Spacer(minLength: 0)
      }
    }
  }


  private func todayVerticalCourseRow(_ course: WidgetCourse) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 8) {
        Text("\(shortTime(course.startsAt))–\(shortTime(course.endsAt))")
          .font(
            .system(
              size: todayVerticalMetadataFontSize,
              weight: .bold,
              design: .monospaced
            )
          )
          .foregroundStyle(courseAccentColor(course))
        Spacer(minLength: 4)
        if !course.room.isEmpty {
          Text(course.room)
            .font(.system(size: todayVerticalMetadataFontSize, weight: .semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Text(course.title)
        .font(.system(size: todayVerticalTitleFontSize, weight: .bold))
        .lineLimit(todayCourses.count > 5 ? 1 : 2)
        .minimumScaleFactor(0.9)
      if !course.code.isEmpty {
        Text(course.code)
          .font(.system(size: todayVerticalSecondaryFontSize, weight: .medium))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, todayVerticalRowPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(courseAccentColor(course).opacity(0.10))
    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .strokeBorder(courseAccentColor(course).opacity(0.24), lineWidth: 0.75)
        .overlay(alignment: .leading) {
          Rectangle()
            .fill(courseAccentColor(course))
            .frame(width: 4)
        }
    }
  }

  private func todayVerticalTimeSpacing(
    current: WidgetCourse,
    previous: WidgetCourse?
  ) -> CGFloat {
    guard let previous else { return 0 }
    let startDifference = current.startsAt.timeIntervalSince(previous.startsAt)
    guard abs(startDifference) >= 60 else { return 5 }
    let freeMinutes = max(
      0,
      current.startsAt.timeIntervalSince(previous.endsAt) / 60
    )
    return min(12, 7 + CGFloat(freeMinutes / 60) * 2)
  }

  private func compactScheduleRow(_ course: WidgetCourse) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Text("\(shortTime(course.startsAt))\n\(shortTime(course.endsAt))")
        .font(.caption.monospacedDigit().bold())
        .foregroundStyle(courseAccentColor(course))
        .lineLimit(2)
        .frame(width: 42, alignment: .leading)
      VStack(alignment: .leading, spacing: 2) {
        Text(course.title)
          .font(.caption.bold())
          .lineLimit(1)
        Text(course.room.isEmpty ? course.code : course.room)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.leading, 7)
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(courseAccentColor(course))
        .frame(width: 3)
    }
  }

  private func header(_ title: String) -> some View {
    HStack(spacing: 6) {
      Text(title)
        .font(.caption.bold())
      Spacer(minLength: 0)
      Text("BNBU")
        .font(.caption2.bold())
        .foregroundStyle(.secondary)
    }
  }

  private func courseSummary(_ course: WidgetCourse) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(course.title)
        .font(.headline)
        .lineLimit(1)
      Text([courseTime(course), course.room]
        .filter { !$0.isEmpty }
        .joined(separator: " · "))
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(courseAccentColor(course).opacity(0.10))
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(courseAccentColor(course))
        .frame(width: 4)
    }
  }

  private func deadlineSummary(_ deadline: WidgetDeadline) -> some View {
    deadlineCard(
      deadline,
      detail: deadlineLabel(deadline.dueAt),
      emphasizesDueDate: true
    )
  }

  private func deadlineRow(_ deadline: WidgetDeadline) -> some View {
    deadlineCard(
      deadline,
      detail: [deadline.courseName, deadlineDate(deadline.dueAt)]
        .filter { !$0.isEmpty }
        .joined(separator: " · "),
      emphasizesDueDate: false
    )
  }

  private func deadlineCard(
    _ deadline: WidgetDeadline,
    detail: String,
    emphasizesDueDate: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(deadline.title)
        .font(.caption.bold())
        .lineLimit(1)
      Text(detail)
        .font(.caption2)
        .foregroundStyle(emphasizesDueDate ? Color.orange : Color.secondary)
        .lineLimit(1)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.orange.opacity(colorScheme == .dark ? 0.16 : 0.10))
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(Color.orange)
        .frame(width: 4)
    }
  }

  private func emptyState(_ text: String) -> some View {
    VStack(spacing: 7) {
      Spacer(minLength: 0)
      Text(text)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      if entry.snapshot.generatedAt == .distantPast {
        Text(
          interfaceLanguage.text(
            "打开 BNBU.ME 同步",
            "開啟 BNBU.ME 同步",
            "Open BNBU.ME to sync"
          )
        )
          .font(.caption2)
          .foregroundStyle(.tertiary)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity)
  }

  private var upcomingCourses: [WidgetCourse] {
    entry.snapshot.courses.filter { $0.endsAt > entry.date }
  }

  private var interfaceLanguage: WidgetInterfaceLanguage {
    entry.snapshot.resolvedInterfaceLanguage
  }

  private var todayCourses: [WidgetCourse] {
    entry.snapshot.courses.filter {
      campusCalendar.isDate($0.startsAt, inSameDayAs: entry.date)
    }.sorted { $0.startsAt < $1.startsAt }
  }

  private var remainingTodayCourses: [WidgetCourse] {
    todayCourses.filter { $0.endsAt > entry.date }
  }

  private var compactScheduleEmptyLabel: String {
    if todayCourses.isEmpty {
      return interfaceLanguage.text(
        "今天没有课程",
        "今天沒有課程",
        "No classes today"
      )
    }
    return interfaceLanguage.text(
      "今天课程已结束",
      "今天課程已結束",
      "Classes finished today"
    )
  }

  private var weekDates: [Date] {
    guard let weekStart = campusWeekStart else { return [] }
    return (0..<7).compactMap {
      campusCalendar.date(byAdding: .day, value: $0, to: weekStart)
    }
  }

  private var displayedWeekDates: [Date] {
    weekDates.filter { date in
      let weekday = campusCalendar.component(.weekday, from: date)
      let isWeekday = (2...6).contains(weekday)
      return isWeekday || !courses(on: date).isEmpty
    }
  }

  private var weekCourses: [WidgetCourse] {
    guard
      let weekStart = campusWeekStart,
      let nextWeekStart = campusCalendar.date(
        byAdding: .day,
        value: 7,
        to: weekStart
      )
    else {
      return []
    }
    return entry.snapshot.courses.filter {
      $0.startsAt >= weekStart && $0.startsAt < nextWeekStart
    }
  }

  private var campusWeekStart: Date? {
    let today = campusCalendar.startOfDay(for: entry.date)
    let weekday = campusCalendar.component(.weekday, from: today)
    let daysSinceMonday = (weekday + 5) % 7
    return campusCalendar.date(
      byAdding: .day,
      value: -daysSinceMonday,
      to: today
    )
  }

  private func courses(on date: Date) -> [WidgetCourse] {
    weekCourses
      .filter { campusCalendar.isDate($0.startsAt, inSameDayAs: date) }
      .sorted { $0.startsAt < $1.startsAt }
  }

  private func campusMinutes(_ date: Date) -> Int {
    let components = campusCalendar.dateComponents([.hour, .minute], from: date)
    return (components.hour ?? 0) * 60 + (components.minute ?? 0)
  }

  private func minutesLabel(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
  }

  private var nextCourse: WidgetCourse? {
    upcomingCourses.first
  }

  private var upcomingDeadlines: [WidgetDeadline] {
    entry.snapshot.deadlines.filter { $0.dueAt >= entry.date }
  }

  private var rowLimit: Int {
    switch family {
    case .systemSmall:
      return 2
    case .systemMedium:
      return 3
    default:
      return 6
    }
  }

  private var scheduleRowLimit: Int {
    switch family {
    case .systemSmall:
      return 2
    case .systemMedium:
      return 3
    default:
      return Int.max
    }
  }

  private var scheduleSpacing: CGFloat {
    7
  }

  private var usesWeeklySchedule: Bool {
    family == .systemLarge || family == .systemExtraLarge
  }

  private var weeklyTimelineDaySpacing: CGFloat {
    0
  }

  private var weeklyTimelineTimeAxisWidth: CGFloat {
    family == .systemExtraLarge ? 30 : 26
  }

  private var weeklyTimelineWeekdayFontSize: CGFloat {
    family == .systemExtraLarge ? 10 : 9
  }

  private var weeklyTimelineDateFontSize: CGFloat {
    family == .systemExtraLarge ? 8.5 : 8
  }

  private var weeklyTimelineTimeFontSize: CGFloat {
    family == .systemExtraLarge ? 8 : 7.5
  }

  private var weeklyTimelineCourseFontSize: CGFloat {
    family == .systemExtraLarge ? 7.125 : 6.75
  }

  private var weeklyTimelineMetadataFontSize: CGFloat {
    family == .systemExtraLarge ? 10.2 : 9.6
  }

  private var weeklyTimelineMinimumCourseHeight: CGFloat {
    family == .systemExtraLarge ? 30 : 28
  }

  private var weeklyTimelineMaximumGapMinutes: Int {
    family == .systemExtraLarge ? 45 : 30
  }

  private var weeklyTimelineGridStartMinutes: Int {
    guard let earliest = weekCourses.map({ campusMinutes($0.startsAt) }).min()
    else {
      return 8 * 60
    }
    return max(0, (earliest / 60) * 60)
  }

  private var weeklyTimelineGridEndMinutes: Int {
    guard let latest = weekCourses.map({ campusMinutes($0.endsAt) }).max()
    else {
      return 18 * 60
    }
    let roundedEnd = ((latest + 59) / 60) * 60
    return min(
      24 * 60,
      max(weeklyTimelineGridStartMinutes + 60, roundedEnd)
    )
  }

  private var weeklyTimelineMarks: [Int] {
    Array(
      Set(
        [weeklyTimelineGridStartMinutes, weeklyTimelineGridEndMinutes]
          + weekCourses.map { campusMinutes($0.startsAt) }
      )
    ).sorted()
  }

  private var weeklyTimelineOccupiedRanges: [(start: Int, end: Int)] {
    let gridStart = weeklyTimelineGridStartMinutes
    let gridEnd = weeklyTimelineGridEndMinutes
    var ranges: [(start: Int, end: Int)] = []
    for course in weekCourses {
      let rangeStart = max(gridStart, campusMinutes(course.startsAt))
      let rangeEnd = min(gridEnd, campusMinutes(course.endsAt))
      if rangeEnd > rangeStart {
        ranges.append((start: rangeStart, end: rangeEnd))
      }
    }
    ranges.sort { lhs, rhs in
      if lhs.start == rhs.start {
        return lhs.end < rhs.end
      }
      return lhs.start < rhs.start
    }
    var merged: [(start: Int, end: Int)] = []
    for range in ranges {
      guard let last = merged.last, range.start <= last.end else {
        merged.append(range)
        continue
      }
      merged[merged.count - 1] = (
        start: last.start,
        end: max(last.end, range.end)
      )
    }
    return merged
  }

  private var weeklyTimelineSegments: [WeeklyTimelineSegment] {
    var result: [WeeklyTimelineSegment] = []
    var cursor = weeklyTimelineGridStartMinutes
    for range in weeklyTimelineOccupiedRanges {
      if cursor < range.start {
        result.append(
          WeeklyTimelineSegment(
            startMinutes: cursor,
            endMinutes: range.start,
            displayMinutes: min(
              range.start - cursor,
              weeklyTimelineMaximumGapMinutes
            )
          )
        )
      }
      result.append(
        WeeklyTimelineSegment(
          startMinutes: range.start,
          endMinutes: range.end,
          displayMinutes: range.end - range.start
        )
      )
      cursor = max(cursor, range.end)
    }
    if cursor < weeklyTimelineGridEndMinutes {
      result.append(
        WeeklyTimelineSegment(
          startMinutes: cursor,
          endMinutes: weeklyTimelineGridEndMinutes,
          displayMinutes: min(
            weeklyTimelineGridEndMinutes - cursor,
            weeklyTimelineMaximumGapMinutes
          )
        )
      )
    }
    return result
  }

  private var weeklyTimelineDisplayMinutes: Int {
    max(1, weeklyTimelineSegments.reduce(0) { $0 + $1.displayMinutes })
  }

  private func weeklyTimelineDisplayOffset(_ minutes: Int) -> CGFloat {
    let clampedMinutes = min(
      max(minutes, weeklyTimelineGridStartMinutes),
      weeklyTimelineGridEndMinutes
    )
    var offset: CGFloat = 0
    for segment in weeklyTimelineSegments {
      if clampedMinutes >= segment.endMinutes {
        offset += CGFloat(segment.displayMinutes)
        continue
      }
      guard clampedMinutes > segment.startMinutes else { break }
      let progress = CGFloat(clampedMinutes - segment.startMinutes)
        / CGFloat(segment.actualMinutes)
      offset += progress * CGFloat(segment.displayMinutes)
      break
    }
    return offset
  }

  private func weeklyTimelineGridY(_ minutes: Int, height: CGFloat) -> CGFloat {
    let progress = weeklyTimelineDisplayOffset(minutes)
      / CGFloat(weeklyTimelineDisplayMinutes)
    return min(max(0, progress * height), height)
  }

  private var todayVerticalRowPadding: CGFloat {
    todayCourses.count > 5 ? 5 : 8
  }

  private var todayVerticalTitleFontSize: CGFloat {
    family == .systemExtraLarge ? 16 : 14
  }

  private var todayVerticalMetadataFontSize: CGFloat {
    family == .systemExtraLarge ? 12.5 : 11.5
  }

  private var todayVerticalSecondaryFontSize: CGFloat {
    family == .systemExtraLarge ? 11.5 : 10.5
  }

  private func additionalCoursesLabel(_ count: Int) -> String {
    interfaceLanguage.text(
      "另有 \(count) 节课程",
      "另有 \(count) 節課程",
      "\(count) more classes"
    )
  }

  private func deadlineLabel(_ date: Date) -> String {
    interfaceLanguage.text(
      "截止 \(deadlineDate(date))",
      "截止 \(deadlineDate(date))",
      "Due \(deadlineDate(date))"
    )
  }

  private var campusScheduleHeader: String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: interfaceLanguage.localeIdentifier)
    formatter.timeZone = campusCalendar.timeZone
    formatter.dateFormat = "EEE M/d"
    return formatter.string(from: entry.date)
  }

  private func weekdayLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: interfaceLanguage.localeIdentifier)
    formatter.timeZone = campusCalendar.timeZone
    formatter.dateFormat = "EEE"
    return formatter.string(from: date)
  }

  private func monthDayLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: interfaceLanguage.localeIdentifier)
    formatter.timeZone = campusCalendar.timeZone
    formatter.dateFormat = "M/d"
    return formatter.string(from: date)
  }

  private func weeklyCourseMetadata(_ course: WidgetCourse) -> String {
    let values = [course.room, course.teacher ?? ""]
      .filter { !$0.isEmpty }
    return values.isEmpty ? course.code : values.joined(separator: " · ")
  }

  private func courseAccentColor(_ course: WidgetCourse) -> Color {
    let snapshotHex = colorScheme == .dark
      ? course.darkAccentHex
      : course.lightAccentHex
    if let snapshotColor = color(fromHex: snapshotHex) {
      return snapshotColor
    }
    let palette: [Color] = [.red, .indigo, .green, .orange, .blue, .purple]
    let seed = (course.code + course.title).unicodeScalars.reduce(0) {
      ($0 + Int($1.value)) % palette.count
    }
    return palette[seed]
  }

  private func color(fromHex value: String?) -> Color? {
    guard var value else { return nil }
    value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#") { value.removeFirst() }
    guard value.count == 6, let rgb = UInt64(value, radix: 16) else {
      return nil
    }
    return Color(
      red: Double((rgb >> 16) & 0xFF) / 255,
      green: Double((rgb >> 8) & 0xFF) / 255,
      blue: Double(rgb & 0xFF) / 255
    )
  }

  private var campusCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: entry.snapshot.campusTimeZone)
      ?? TimeZone(secondsFromGMT: 8 * 60 * 60)!
    return calendar
  }

  private func courseTime(_ course: WidgetCourse) -> String {
    "\(campusDayLabel(course.startsAt)) \(shortTime(course.startsAt))–\(shortTime(course.endsAt))"
  }

  private func campusDayLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: interfaceLanguage.localeIdentifier)
    formatter.timeZone = campusCalendar.timeZone
    formatter.dateFormat = interfaceLanguage == .english
      ? "EEE, MMM d"
      : "M月d日 EEE"
    return formatter.string(from: date)
  }

  private func shortTime(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: interfaceLanguage.localeIdentifier)
    formatter.timeZone = campusCalendar.timeZone
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
  }

  private func deadlineDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: interfaceLanguage.localeIdentifier)
    formatter.timeZone = .current
    formatter.dateFormat = interfaceLanguage == .english
      ? "MMM d, HH:mm"
      : "M月d日 HH:mm"
    return formatter.string(from: date)
  }

}

struct BnbuCampusWidget: Widget {
  var body: some WidgetConfiguration {
#if os(macOS)
    return IntentConfiguration(
      kind: widgetKind,
      intent: BnbuWidgetConfigurationIntent.self,
      provider: BnbuMacWidgetProvider()
    ) { entry in
      BnbuWidgetView(entry: entry)
    }
    .configurationDisplayName(widgetDisplayName)
    .description("")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
#else
    return AppIntentConfiguration(
      kind: widgetKind,
      intent: BnbuWidgetConfigurationIntent.self,
      provider: BnbuWidgetProvider()
    ) { entry in
      BnbuWidgetView(entry: entry)
    }
    .configurationDisplayName(widgetDisplayName)
    .description("")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
#endif
  }
}

@main
struct BnbuWidgetsBundle: WidgetBundle {
  var body: some Widget {
    BnbuCampusWidget()
#if os(iOS)
    if #available(iOSApplicationExtension 16.2, *) {
      BnbuLiveActivityWidget()
    }
#endif
  }
}

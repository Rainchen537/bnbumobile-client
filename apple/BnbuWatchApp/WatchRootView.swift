import SwiftUI

private let bnbuCampusTimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

private struct WatchInterfaceLanguageKey: EnvironmentKey {
  static let defaultValue = WatchInterfaceLanguage.systemDefault
}

private extension EnvironmentValues {
  var watchInterfaceLanguage: WatchInterfaceLanguage {
    get { self[WatchInterfaceLanguageKey.self] }
    set { self[WatchInterfaceLanguageKey.self] = newValue }
  }
}

struct WatchRootView: View {
  @ObservedObject var store: WatchSnapshotStore
  @AppStorage("bnbu.watch.selectedPage.v2") private var selectedPage = WatchPrimaryPage.overview.rawValue
  @AppStorage("bnbu.watch.pageOrder.v1") private var pageOrderRaw = WatchPrimaryPage.defaultOrderRaw
  @AppStorage("bnbu.watch.hiddenPages.v1") private var hiddenPagesRaw = ""

  var body: some View {
    TabView(selection: $selectedPage) {
      ForEach(visiblePages) { page in
        primaryPage(page)
          .tag(page.rawValue)
      }
      WatchSettingsView(
        pageOrderRaw: $pageOrderRaw,
        hiddenPagesRaw: $hiddenPagesRaw
      )
        .tag("settings")
    }
    .tabViewStyle(.verticalPage)
    .tint(BnbuWatchPalette.brand)
    .environment(\.watchInterfaceLanguage, store.interfaceLanguage)
    .id(store.interfaceLanguage.rawValue)
  }

  private var visiblePages: [WatchPrimaryPage] {
    let hiddenPages = WatchPrimaryPage.hiddenPages(from: hiddenPagesRaw)
    return WatchPrimaryPage.normalizedOrder(from: pageOrderRaw)
      .filter { !hiddenPages.contains($0) }
  }

  @ViewBuilder
  private func primaryPage(_ page: WatchPrimaryPage) -> some View {
    switch page {
    case .overview:
      WatchOverviewView(snapshot: store.snapshot, isRefreshing: store.isRefreshing) {
        store.refresh()
      }
    case .schedule:
      WatchWeekScheduleView(snapshot: store.snapshot)
    case .deadlines:
      WatchDeadlineListView(snapshot: store.snapshot)
    }
  }

}

private enum WatchPrimaryPage: String, CaseIterable, Identifiable {
  case overview
  case schedule
  case deadlines

  static let defaultOrderRaw = allCases.map(\.rawValue).joined(separator: ",")

  var id: String { rawValue }

  func title(_ language: WatchInterfaceLanguage) -> String {
    switch self {
    case .overview: language.text("概况", "概況", "Overview")
    case .schedule: language.text("两周课表", "兩週課表", "Two-Week Timetable")
    case .deadlines: "DDL"
    }
  }

  var systemImage: String {
    switch self {
    case .overview: "sparkles"
    case .schedule: "calendar"
    case .deadlines: "checklist"
    }
  }

  static func normalizedOrder(from rawValue: String) -> [WatchPrimaryPage] {
    var result: [WatchPrimaryPage] = []
    for component in rawValue.split(separator: ",") {
      guard
        let page = WatchPrimaryPage(rawValue: String(component)),
        !result.contains(page)
      else { continue }
      result.append(page)
    }
    for page in allCases where !result.contains(page) {
      result.append(page)
    }
    return result
  }

  static func encodedOrder(_ pages: [WatchPrimaryPage]) -> String {
    normalizedOrder(from: pages.map(\.rawValue).joined(separator: ","))
      .map(\.rawValue)
      .joined(separator: ",")
  }

  static func hiddenPages(from rawValue: String) -> Set<WatchPrimaryPage> {
    Set(rawValue.split(separator: ",").compactMap {
      WatchPrimaryPage(rawValue: String($0))
    })
  }

  static func encodedHiddenPages(_ pages: Set<WatchPrimaryPage>) -> String {
    allCases.filter(pages.contains).map(\.rawValue).joined(separator: ",")
  }
}

private struct WatchSettingsView: View {
  @Environment(\.watchInterfaceLanguage) private var language
  @Binding var pageOrderRaw: String
  @Binding var hiddenPagesRaw: String

  private var pages: [WatchPrimaryPage] {
    WatchPrimaryPage.normalizedOrder(from: pageOrderRaw)
  }

  private var hiddenPages: Set<WatchPrimaryPage> {
    WatchPrimaryPage.hiddenPages(from: hiddenPagesRaw)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        WatchSectionHeader(
          title: language.text("设置", "設定", "Settings"),
          systemImage: "gearshape"
        )
        Text(language.text("展示内容与顺序", "顯示內容與順序", "Content & Order"))
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)

        ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
          VStack(spacing: 3) {
            HStack(spacing: 6) {
              Text("\(index + 1)")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(BnbuWatchPalette.brand)
                .frame(width: 12)
              Label(page.title(language), systemImage: page.systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(1)
                .opacity(hiddenPages.contains(page) ? 0.45 : 1)
              Spacer(minLength: 0)
              visibilityButton(for: page)
            }
            HStack(spacing: 4) {
              Spacer(minLength: 0)
              orderButton(
                systemImage: "chevron.up",
                accessibilityLabel: language.text(
                  "将\(page.title(language))上移",
                  "將\(page.title(language))上移",
                  "Move \(page.title(language)) up"
                ),
                disabled: index == 0
              ) {
                movePage(at: index, offset: -1)
              }
              orderButton(
                systemImage: "chevron.down",
                accessibilityLabel: language.text(
                  "将\(page.title(language))下移",
                  "將\(page.title(language))下移",
                  "Move \(page.title(language)) down"
                ),
                disabled: index == pages.count - 1
              ) {
                movePage(at: index, offset: 1)
              }
            }
          }
          .padding(.vertical, 5)
          .padding(.horizontal, 8)
          .background(
            Color.white.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
          )
        }
      }
      .padding(.horizontal, 4)
    }
  }

  private func visibilityButton(for page: WatchPrimaryPage) -> some View {
    let isHidden = hiddenPages.contains(page)
    return Button {
      toggleVisibility(of: page)
    } label: {
      Image(systemName: isHidden ? "eye.slash" : "eye")
        .font(.caption.weight(.semibold))
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(isHidden ? Color.secondary : BnbuWatchPalette.brand)
    .accessibilityLabel(
      isHidden
        ? language.text(
          "显示\(page.title(language))",
          "顯示\(page.title(language))",
          "Show \(page.title(language))"
        )
        : language.text(
          "隐藏\(page.title(language))",
          "隱藏\(page.title(language))",
          "Hide \(page.title(language))"
        )
    )
  }

  private func orderButton(
    systemImage: String,
    accessibilityLabel: String,
    disabled: Bool,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.caption2.weight(.bold))
        .frame(width: 24, height: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .foregroundStyle(disabled ? Color.secondary.opacity(0.35) : BnbuWatchPalette.brand)
    .disabled(disabled)
    .accessibilityLabel(accessibilityLabel)
  }

  private func movePage(at index: Int, offset: Int) {
    let destination = index + offset
    guard pages.indices.contains(index), pages.indices.contains(destination) else { return }
    var reordered = pages
    reordered.swapAt(index, destination)
    pageOrderRaw = WatchPrimaryPage.encodedOrder(reordered)
  }

  private func toggleVisibility(of page: WatchPrimaryPage) {
    var updated = hiddenPages
    if updated.contains(page) {
      updated.remove(page)
    } else {
      updated.insert(page)
    }
    hiddenPagesRaw = WatchPrimaryPage.encodedHiddenPages(updated)
  }
}

private struct WatchOverviewView: View {
  @Environment(\.watchInterfaceLanguage) private var language
  let snapshot: WatchSnapshot?
  let isRefreshing: Bool
  let refresh: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 9) {
        WatchSectionHeader(
          title: language.text("概况", "概況", "Overview"),
          systemImage: "sparkles"
        )

        if snapshot == nil {
          WatchSyncState(isRefreshing: isRefreshing, refresh: refresh)
        } else {
          courseBlock
          Divider()
          deadlineBlock
          Button(action: refresh) {
            Label(
              language.text("同步", "同步", "Sync"),
              systemImage: "arrow.clockwise"
            )
              .font(.caption2.weight(.semibold))
          }
          .buttonStyle(.plain)
          .foregroundStyle(BnbuWatchPalette.brand)
        }
      }
      .padding(.horizontal, 4)
    }
  }

  @ViewBuilder
  private var courseBlock: some View {
    if let course = nextCourse {
      VStack(alignment: .leading, spacing: 4) {
        Text(course.title)
          .font(.headline)
          .lineLimit(2)
        Label(courseTimeRange(course), systemImage: "clock")
          .font(.caption2.monospacedDigit())
          .foregroundStyle(BnbuWatchPalette.courseAccent(course))
        if !course.room.isEmpty {
          Label(course.room, systemImage: "mappin.and.ellipse")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    } else {
      WatchEmptyRow(
        text: language.text("近期没有课程", "近期沒有課程", "No upcoming classes"),
        systemImage: "calendar.badge.checkmark"
      )
    }
  }

  @ViewBuilder
  private var deadlineBlock: some View {
    if let deadline = nextDeadline {
      VStack(alignment: .leading, spacing: 4) {
        Text(deadline.title)
          .font(.caption.weight(.semibold))
          .lineLimit(2)
        Text(
          [deadline.courseName, deadlineTime(deadline.dueAt, language: language)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        )
        .font(.caption2)
        .foregroundStyle(BnbuWatchPalette.deadline)
        .lineLimit(2)
      }
    } else {
      WatchEmptyRow(
        text: language.text("近期没有 DDL", "近期沒有 DDL", "No upcoming deadlines"),
        systemImage: "checkmark.circle"
      )
    }
  }

  private var nextCourse: WatchCourse? {
    snapshot?.courses
      .filter { $0.endsAt > .now }
      .sorted { $0.startsAt < $1.startsAt }
      .first
  }

  private var nextDeadline: WatchDeadline? {
    snapshot?.deadlines
      .filter { $0.dueAt >= .now }
      .sorted { $0.dueAt < $1.dueAt }
      .first
  }
}

private struct WatchWeekScheduleView: View {
  @Environment(\.watchInterfaceLanguage) private var language
  let snapshot: WatchSnapshot?
  private let weekDays: [Date]
  private let today: Date?
  @State private var visibleDay: Date?

  init(snapshot: WatchSnapshot?, now: Date = .now) {
    self.snapshot = snapshot
    let days = WatchCampusCalendar.twoWeekDays(containing: now)
    let currentDay = days.first {
      WatchCampusCalendar.calendar.isDate($0, inSameDayAs: now)
    }
    weekDays = days
    today = currentDay
    _visibleDay = State(initialValue: currentDay)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 5) {
        Label(
          language.text("两周课表", "兩週課表", "Two-Week Timetable"),
          systemImage: "calendar"
        )
          .font(.headline)
          .foregroundStyle(.primary)
          .lineLimit(1)
        Spacer(minLength: 0)
        if !isShowingToday {
          Button {
            withAnimation(.easeInOut(duration: 0.25)) {
              visibleDay = today
            }
          } label: {
            Text(language.text("今日", "今日", "Today"))
              .font(.caption2.weight(.semibold))
              .frame(minWidth: 30, minHeight: 26)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .foregroundStyle(BnbuWatchPalette.brand)
          .background(
            BnbuWatchPalette.brand.opacity(0.16),
            in: Capsule()
          )
          .accessibilityLabel(language.text("回到今日", "回到今日", "Back to today"))
        }
      }
        .padding(.horizontal, 4)

      if snapshot == nil {
        Spacer()
        WatchEmptyRow(
          text: language.text(
            "请先在 iPhone App 登录并同步",
            "請先在 iPhone App 登入並同步",
            "Sign in on the iPhone app to sync"
          ),
          systemImage: "iphone.and.arrow.forward"
        )
          .padding(.horizontal, 8)
        Spacer()
      } else {
        ScrollView(.horizontal) {
          LazyHStack(alignment: .top, spacing: 8) {
            ForEach(weekDays, id: \.self) { day in
              WatchDayColumn(
                day: day,
                courses: courses(on: day),
                isToday: today.map {
                  WatchCampusCalendar.calendar.isDate(day, inSameDayAs: $0)
                } ?? false
              )
              .containerRelativeFrame(.horizontal, count: 1, spacing: 8)
            }
          }
          .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $visibleDay, anchor: .center)
      }
    }
  }

  private func courses(on day: Date) -> [WatchCourse] {
    (snapshot?.courses ?? [])
      .filter { WatchCampusCalendar.calendar.isDate($0.startsAt, inSameDayAs: day) }
      .sorted { $0.startsAt < $1.startsAt }
  }

  private var isShowingToday: Bool {
    guard let visibleDay, let today else { return true }
    return WatchCampusCalendar.calendar.isDate(visibleDay, inSameDayAs: today)
  }

}

private struct WatchDayColumn: View {
  @Environment(\.watchInterfaceLanguage) private var language
  let day: Date
  let courses: [WatchCourse]
  let isToday: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 5) {
        Text(WatchCampusCalendar.dayTitle(day, language: language))
          .font(.caption.weight(.bold))
        if isToday {
          Circle()
            .fill(BnbuWatchPalette.brand)
            .frame(width: 5, height: 5)
        }
      }
      .padding(.horizontal, 4)

      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 7) {
          if courses.isEmpty {
            WatchEmptyRow(
              text: language.text("没有课程", "沒有課程", "No classes"),
              systemImage: "moon.stars"
            )
              .padding(.top, 16)
          } else {
            ForEach(courses) { course in
              WatchCourseCard(course: course)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
      }
      .scrollIndicators(.hidden)
    }
  }
}

private struct WatchCourseCard: View {
  let course: WatchCourse

  var body: some View {
    HStack(spacing: 0) {
      Capsule()
        .fill(BnbuWatchPalette.courseAccent(course))
        .frame(width: 3)
      VStack(alignment: .leading, spacing: 3) {
        Text(courseTimeRange(course))
          .font(.caption2.monospacedDigit().weight(.bold))
          .foregroundStyle(BnbuWatchPalette.courseAccent(course))
        Text(course.title)
          .font(.caption.weight(.semibold))
          .lineLimit(2)
        if !course.room.isEmpty {
          Label(course.room, systemImage: "mappin.and.ellipse")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        if let teacher = course.teacher, !teacher.isEmpty {
          Text(teacher)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      .padding(.leading, 7)
    }
    .padding(8)
    .background(
      Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous)
    )
    .overlay {
      RoundedRectangle(cornerRadius: 11, style: .continuous)
        .stroke(Color.white.opacity(0.1), lineWidth: 0.75)
    }
  }
}

private struct WatchDeadlineListView: View {
  @Environment(\.watchInterfaceLanguage) private var language
  let snapshot: WatchSnapshot?

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 8) {
        WatchSectionHeader(title: "DDL", systemImage: "checklist")

        if snapshot == nil {
          WatchEmptyRow(
            text: language.text(
              "请先在 iPhone App 登录并同步",
              "請先在 iPhone App 登入並同步",
              "Sign in on the iPhone app to sync"
            ),
            systemImage: "iphone.and.arrow.forward"
          )
            .padding(.top, 28)
        } else if deadlines.isEmpty {
          WatchEmptyRow(
            text: language.text("近期没有 DDL", "近期沒有 DDL", "No upcoming deadlines"),
            systemImage: "checkmark.circle"
          )
            .padding(.top, 28)
        } else {
          ForEach(deadlines) { deadline in
            VStack(alignment: .leading, spacing: 4) {
              Text(deadline.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
              if !deadline.courseName.isEmpty {
                Text(deadline.courseName)
                  .font(.caption2)
                  .foregroundStyle(.secondary)
                  .lineLimit(1)
              }
              Label(
                deadlineTime(deadline.dueAt, language: language),
                systemImage: "clock.badge.exclamationmark"
              )
                .font(.caption2.monospacedDigit())
                .foregroundStyle(BnbuWatchPalette.deadline)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
          }
        }
      }
      .padding(.horizontal, 4)
    }
  }

  private var deadlines: [WatchDeadline] {
    (snapshot?.deadlines ?? [])
      .filter { $0.dueAt >= .now }
      .sorted { $0.dueAt < $1.dueAt }
  }
}

private struct WatchSectionHeader: View {
  let title: String
  let systemImage: String

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: systemImage)
        .foregroundStyle(BnbuWatchPalette.brand)
      Text(title)
        .font(.headline)
      Spacer(minLength: 0)
    }
  }
}

private struct WatchSyncState: View {
  @Environment(\.watchInterfaceLanguage) private var language
  let isRefreshing: Bool
  let refresh: () -> Void

  var body: some View {
    VStack(spacing: 9) {
      Image(systemName: "iphone.and.arrow.forward")
        .font(.title2)
        .foregroundStyle(BnbuWatchPalette.brand)
      Text(
        language.text(
          "请先在 iPhone App 登录并同步",
          "請先在 iPhone App 登入並同步",
          "Sign in on the iPhone app to sync"
        )
      )
        .font(.caption)
        .multilineTextAlignment(.center)
      Button(action: refresh) {
        if isRefreshing {
          ProgressView()
        } else {
          Text(language.text("重新同步", "重新同步", "Sync Again"))
        }
      }
      .buttonStyle(.borderedProminent)
      .tint(BnbuWatchPalette.brand)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 22)
  }
}

private struct WatchEmptyRow: View {
  let text: String
  let systemImage: String

  var body: some View {
    VStack(spacing: 7) {
      Image(systemName: systemImage)
        .foregroundStyle(BnbuWatchPalette.brand)
      Text(text)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity)
  }
}

private enum BnbuWatchPalette {
  static let brand = Color(red: 0.02, green: 0.45, blue: 0.72)
  static let deadline = Color.orange
  private static let courseColors: [Color] = [
    Color(red: 0.04, green: 0.48, blue: 0.75),
    Color(red: 0.16, green: 0.67, blue: 0.35),
    Color(red: 0.72, green: 0.18, blue: 0.25),
    Color(red: 0.43, green: 0.31, blue: 0.78),
    Color(red: 0.04, green: 0.64, blue: 0.67),
  ]

  static func courseAccent(_ course: WatchCourse) -> Color {
    let key = course.code.isEmpty ? course.title : course.code
    let sum = key.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return courseColors[abs(sum) % courseColors.count]
  }
}

private enum WatchCampusCalendar {
  static var calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = bnbuCampusTimeZone
    calendar.firstWeekday = 2
    return calendar
  }()

  static func twoWeekDays(containing date: Date) -> [Date] {
    let startOfDay = calendar.startOfDay(for: date)
    let weekday = calendar.component(.weekday, from: startOfDay)
    let daysFromMonday = (weekday + 5) % 7
    guard let monday = calendar.date(byAdding: .day, value: -daysFromMonday, to: startOfDay) else {
      return [startOfDay]
    }
    return (0..<14).compactMap {
      calendar.date(byAdding: .day, value: $0, to: monday)
    }
  }

  static func dayTitle(_ date: Date, language: WatchInterfaceLanguage) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: language.localeIdentifier)
    formatter.timeZone = bnbuCampusTimeZone
    formatter.dateFormat = "EEE M/d"
    return formatter.string(from: date)
  }
}

private func courseTimeRange(_ course: WatchCourse) -> String {
  "\(campusTime(course.startsAt))–\(campusTime(course.endsAt))"
}

private func campusTime(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "zh_CN")
  formatter.timeZone = bnbuCampusTimeZone
  formatter.dateFormat = "HH:mm"
  return formatter.string(from: date)
}

private func deadlineTime(
  _ date: Date,
  language: WatchInterfaceLanguage = .systemDefault
) -> String {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: language.localeIdentifier)
  formatter.timeZone = .current
  formatter.dateFormat = "M/d HH:mm"
  return formatter.string(from: date)
}

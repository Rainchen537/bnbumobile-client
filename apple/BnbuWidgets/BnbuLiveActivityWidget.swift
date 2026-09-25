#if os(iOS)
import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

@available(iOSApplicationExtension 16.2, *)
struct BnbuLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: BnbuLiveActivityAttributes.self) { context in
      BnbuLiveActivityLockScreenView(context: context)
        .activitySystemActionForegroundColor(.blue)
        .widgetURL(liveActivityDestinationURL(context: context))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Group {
            if context.state.kind == "course" {
              BnbuLiveActivityCourseLeading(context: context, iconSize: 26)
            } else {
              BnbuLiveActivityDeadlineLeading(iconSize: 26)
            }
          }
          .padding(.leading, 10)
          .padding(.trailing, 4)
        }
        DynamicIslandExpandedRegion(.trailing) {
          BnbuLiveActivityEventTime(context: context)
            .padding(.leading, 4)
            .padding(.trailing, 10)
        }
        DynamicIslandExpandedRegion(.bottom, priority: 3) {
          Group {
            if context.state.kind == "deadline" {
              BnbuLiveActivityDeadlineExpandedContent(context: context)
            } else {
              BnbuLiveActivityExpandedDetail(context: context)
            }
          }
          .padding(.horizontal, 10)
          .padding(.top, 2)
          .padding(.bottom, 8)
        }
      } compactLeading: {
        if context.state.kind == "course" {
          BnbuLiveActivityCourseLeading(
            context: context,
            iconSize: 20,
            compact: true
          )
        } else {
          BnbuLiveActivityDeadlineLeading(iconSize: 20, compact: true)
        }
      } compactTrailing: {
        BnbuLiveActivityEventTime(context: context, compact: true)
      } minimal: {
        BnbuLiveActivityAppIcon(size: 20)
      }
      .keylineTint(liveActivityAccent(for: context.state))
      .widgetURL(liveActivityDestinationURL(context: context))
    }
  }
}

@available(iOSApplicationExtension 16.2, *)
private func liveActivityDestinationURL(
  context: ActivityViewContext<BnbuLiveActivityAttributes>
) -> URL? {
  guard
    let scheme = Bundle.main.object(forInfoDictionaryKey: "BnbuAppURLScheme") as? String,
    !scheme.isEmpty
  else {
    return nil
  }
  let fallback = context.state.kind == "course" ? "schedule" :
    context.state.kind == "deadline" ? "ispace" : "home"
  let destination = context.state.destination ?? fallback
  var components = URLComponents()
  components.scheme = scheme
  components.host = "live-activity"
  components.path = "/\(destination)"
  return components.url
}

@available(iOSApplicationExtension 16.2, *)
private struct BnbuLiveActivityLockScreenView: View {
  @Environment(\.colorScheme) private var colorScheme
  let context: ActivityViewContext<BnbuLiveActivityAttributes>

  var body: some View {
    Group {
      if context.state.kind == "course" {
        courseContent
      } else {
        deadlineContent
      }
    }
    // Resolve the background in the widget's environment, not UIKit's host traits.
    .activityBackgroundTint(colorScheme == .dark ? .black : .white)
  }

  private var courseContent: some View {
    HStack(spacing: 14) {
      ZStack {
        Circle()
          .fill(liveActivityAccent(for: context.state).opacity(0.14))
        Image(systemName: "calendar")
          .font(.title3.weight(.semibold))
          .foregroundStyle(liveActivityAccent(for: context.state))
      }
      .frame(width: 42, height: 42)

      VStack(alignment: .leading, spacing: 4) {
        BnbuLiveActivityAppIcon(size: 18)
        Text(context.state.title)
          .font(.headline)
          .lineLimit(nil)
          .fixedSize(horizontal: false, vertical: true)
          .layoutPriority(3)
        HStack(spacing: 10) {
          if !context.state.location.isEmpty {
            Label(context.state.location, systemImage: "mappin.and.ellipse")
          }
          Label(courseTimeRange(context: context), systemImage: "clock")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      }

      Spacer(minLength: 8)
    }
    .padding(16)
  }

  private var deadlineContent: some View {
    ViewThatFits(in: .vertical) {
      deadlineContent(compact: false, bounded: false)
      deadlineContent(compact: true, bounded: false)
      deadlineContent(compact: true, bounded: true)
    }
    // Live Activity lock-screen presentations are capped at 160pt, including padding.
    .frame(maxHeight: 128, alignment: .topLeading)
    .padding(16)
  }

  private func deadlineContent(compact: Bool, bounded: Bool) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        BnbuLiveActivityAppIcon(size: 18)
        BnbuLiveActivityDeadlineBadge()
      }
      if !context.state.detail.isEmpty {
        Text(context.state.detail)
          .font(compact ? .system(size: 12) : .caption)
          .foregroundStyle(.secondary)
          .lineLimit(bounded ? 1 : nil)
          .fixedSize(horizontal: false, vertical: true)
      }
      Text(context.state.title)
        .font(compact ? .system(size: 13, weight: .semibold) : .headline)
        .lineLimit(bounded ? 4 : nil)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(3)
      Label(
        campusTime(context.state.eventAt, timeZoneID: context.attributes.campusTimeZone),
        systemImage: "clock"
      )
      .font(compact ? .system(size: 12) : .caption)
      .foregroundStyle(.secondary)
      .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .fixedSize(horizontal: false, vertical: true)
  }
}

@available(iOSApplicationExtension 16.2, *)
private struct BnbuLiveActivityAppIcon: View {
  let size: CGFloat

  var body: some View {
    Group {
      if let icon = hostAppIcon() {
        Image(uiImage: icon)
          .resizable()
          .interpolation(.high)
          .scaledToFit()
      } else {
        Image(systemName: "app.fill")
          .resizable()
          .scaledToFit()
          .padding(size * 0.16)
          .foregroundStyle(.blue)
          .background(.white)
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    .accessibilityLabel("BNBU.ME")
  }

  private func hostAppIcon() -> UIImage? {
    let hostAppURL = Bundle.main.bundleURL
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let filenames = [
      "AppIcon60x60@3x.png",
      "AppIcon60x60@2x.png",
      "AppIcon76x76@2x~ipad.png",
    ]
    for filename in filenames {
      let iconURL = hostAppURL.appendingPathComponent(filename)
      if let icon = UIImage(contentsOfFile: iconURL.path) {
        return icon
      }
    }
    return nil
  }
}

@available(iOSApplicationExtension 16.2, *)
private struct BnbuLiveActivityDeadlineBadge: View {
  var body: some View {
    Text("DDL")
      .font(.caption2.weight(.bold))
      .foregroundStyle(.orange)
      .accessibilityLabel("DDL")
  }
}

@available(iOSApplicationExtension 16.2, *)
private struct BnbuLiveActivityDeadlineLeading: View {
  let iconSize: CGFloat
  var compact = false

  var body: some View {
    HStack(spacing: compact ? 4 : 6) {
      BnbuLiveActivityAppIcon(size: iconSize)
      BnbuLiveActivityDeadlineBadge()
    }
    .lineLimit(1)
  }
}

@available(iOSApplicationExtension 16.2, *)
private struct BnbuLiveActivityCourseLeading: View {
  let context: ActivityViewContext<BnbuLiveActivityAttributes>
  let iconSize: CGFloat
  var compact = false

  var body: some View {
    HStack(spacing: compact ? 4 : 6) {
      BnbuLiveActivityAppIcon(size: iconSize)
      if !context.state.location.isEmpty {
        Text(context.state.location)
          .font(compact ? .caption2 : .caption)
          .lineLimit(compact ? 1 : 2)
          .fixedSize(horizontal: false, vertical: !compact)
      }
    }
    .foregroundStyle(.primary)
    .minimumScaleFactor(compact ? 0.68 : 0.82)
  }
}

@available(iOSApplicationExtension 16.2, *)
private struct BnbuLiveActivityEventTime: View {
  let context: ActivityViewContext<BnbuLiveActivityAttributes>
  var compact = false

  var body: some View {
    Text(
      context.state.kind == "course"
        ? courseTimeRange(context: context)
        : campusTime(
          context.state.eventAt,
          timeZoneID: context.attributes.campusTimeZone
        )
    )
    .font(compact ? .caption2.monospacedDigit() : .caption.monospacedDigit())
    .foregroundStyle(.primary)
    .lineLimit(1)
    .fixedSize(horizontal: true, vertical: false)
    .minimumScaleFactor(0.75)
  }
}

@available(iOSApplicationExtension 16.2, *)
private struct BnbuLiveActivityExpandedDetail: View {
  let context: ActivityViewContext<BnbuLiveActivityAttributes>
  var compact = false
  var bounded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      if context.state.kind == "deadline", !context.state.detail.isEmpty {
        Text(context.state.detail)
          .font(compact ? .system(size: 12) : .caption)
          .foregroundStyle(.secondary)
          .lineLimit(bounded ? 1 : nil)
          .fixedSize(horizontal: false, vertical: true)
      }
      Text(context.state.title)
        .font(compact ? .system(size: 13, weight: .semibold) : .headline)
        .foregroundStyle(.primary)
        .lineLimit(bounded ? 3 : nil)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .fixedSize(horizontal: false, vertical: true)
    .layoutPriority(4)
  }
}

@available(iOSApplicationExtension 16.2, *)
private struct BnbuLiveActivityDeadlineRemaining: View {
  let context: ActivityViewContext<BnbuLiveActivityAttributes>
  var compact = false

  var body: some View {
    Group {
      if let interval = deadlineRemainingInterval {
        if #available(iOSApplicationExtension 26.0, *) {
          HStack(spacing: 4) {
            Text("剩余")
            Text(
              .currentDate,
              format: .timer(
                countingDownIn: interval,
                showsHours: true,
                maxFieldCount: 2,
                maxPrecision: .seconds(60)
              )
            )
          }
        } else {
          HStack(spacing: 4) {
            Text("剩余")
            Text(context.state.eventAt, style: .relative)
          }
        }
      } else {
        Text("已截止")
      }
    }
    .font(compact ? .system(size: 15, weight: .semibold) : .headline)
    .foregroundStyle(.orange)
    .monospacedDigit()
    .lineLimit(1)
    .minimumScaleFactor(0.8)
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
    .layoutPriority(3)
  }

  private var deadlineRemainingInterval: Range<Date>? {
    let now = Date()
    guard context.state.eventAt > now else {
      return nil
    }
    return now..<context.state.eventAt
  }
}

@available(iOSApplicationExtension 16.2, *)
private struct BnbuLiveActivityDeadlineExpandedContent: View {
  let context: ActivityViewContext<BnbuLiveActivityAttributes>

  var body: some View {
    ViewThatFits(in: .vertical) {
      content(compact: false, bounded: false)
      content(compact: true, bounded: false)
      content(compact: true, bounded: true)
    }
    // Reserve the camera/header and system margins within the 160pt presentation.
    // fixedSize on this container would bypass iOS 18's height proposal and clip the timer.
    .frame(maxHeight: 96, alignment: .topLeading)
  }

  private func content(compact: Bool, bounded: Bool) -> some View {
    VStack(alignment: .leading, spacing: compact ? 4 : 6) {
      BnbuLiveActivityExpandedDetail(context: context, compact: compact, bounded: bounded)
      BnbuLiveActivityDeadlineRemaining(context: context, compact: compact)
        .layoutPriority(4)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .fixedSize(horizontal: false, vertical: true)
    .layoutPriority(5)
  }
}

@available(iOSApplicationExtension 16.2, *)
private func liveActivityAccent(for state: BnbuLiveActivityAttributes.ContentState) -> Color {
  state.kind == "course" ? .blue : .orange
}

@available(iOSApplicationExtension 16.2, *)
private func campusTime(_ date: Date, timeZoneID: String) -> String {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier: "zh_CN")
  formatter.timeZone = TimeZone(identifier: timeZoneID) ?? TimeZone(secondsFromGMT: 8 * 60 * 60)
  formatter.dateFormat = "HH:mm"
  return formatter.string(from: date)
}

@available(iOSApplicationExtension 16.2, *)
private func courseTimeRange(
  context: ActivityViewContext<BnbuLiveActivityAttributes>
) -> String {
  let start = campusTime(
    context.state.eventAt,
    timeZoneID: context.attributes.campusTimeZone
  )
  let end = campusTime(
    context.state.endAt,
    timeZoneID: context.attributes.campusTimeZone
  )
  return "\(start)–\(end)"
}
#endif

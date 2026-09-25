import SwiftUI

@main
struct BnbuWatchApp: App {
  @StateObject private var snapshotStore = WatchSnapshotStore()

  var body: some Scene {
    WindowGroup {
      WatchRootView(store: snapshotStore)
    }
  }
}

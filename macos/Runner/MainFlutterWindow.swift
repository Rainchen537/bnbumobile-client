import Cocoa
import Carbon
import FlutterMacOS
import WidgetKit
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  private static let widgetSnapshotFileName = "bnbu-widget-snapshot-v1.json"
  private let loginInputSourceController = LoginInputSourceController()
  private let widgetSnapshotQueue = DispatchQueue(
    label: "bnbu.widget-snapshot.widget-snapshot",
    qos: .utility
  )
  private var nativeActionsChannel: FlutterMethodChannel?
  private var sharePicker: NSSharingServicePicker?
  private var loginInputSourceChannel: FlutterMethodChannel?
  private var widgetSnapshotChannel: FlutterMethodChannel?
  private var courseArchiveExportChannel: FlutterMethodChannel?
  private var desktopDownloadsChannel: FlutterMethodChannel?
  private let desktopDownloadStore = DesktopDownloadStore()
  private let courseArchiveExportStore = CourseArchiveExportStore()
  private let courseArchiveExportQueue = DispatchQueue(label: "bnbu.course-archive-export", qos: .utility)

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.title = "BNBU.ME"
    self.minSize = NSSize(width: 720, height: 600)
    self.setContentSize(NSSize(width: 1280, height: 800))
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)
    BnbuStatisticsBridge.shared.configure(messenger: flutterViewController.engine.binaryMessenger)
    BnbuStatisticsBridge.shared.observeMainWindow(self)
    configureCourseArchiveExport(messenger: flutterViewController.engine.binaryMessenger)
    configureDesktopDownloads(messenger: flutterViewController.engine.binaryMessenger)
    let nativeActions = FlutterMethodChannel(name: "ispace/native_actions", binaryMessenger: flutterViewController.engine.binaryMessenger)
    nativeActions.setMethodCallHandler { [weak self] call, result in
      guard call.method == "shareLocalFile" else { result(FlutterMethodNotImplemented); return }
      guard let self, let args = call.arguments as? [String: Any], let path = args["path"] as? String,
        let view = self.contentView, FileManager.default.fileExists(atPath: path) else {
        result(FlutterError(code: "file_unavailable", message: "File unavailable", details: nil)); return
      }
      let url = URL(fileURLWithPath: path).standardizedFileURL
      // path_provider_foundation maps its temporary directory to Caches on macOS.
      guard let cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
        result(FlutterError(code: "cache_unavailable", message: "Share cache unavailable", details: nil)); return
      }
      let root = cacheDirectory.appendingPathComponent("me-life-share", isDirectory: true).standardizedFileURL.resolvingSymlinksInPath().path
      guard url.resolvingSymlinksInPath().path.hasPrefix(root.hasSuffix("/") ? root : root + "/") else {
        result(FlutterError(code: "invalid_share_path", message: "Invalid share file", details: nil)); return
      }
      let picker = NSSharingServicePicker(items: [url])
      self.sharePicker = picker
      picker.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1), of: view, preferredEdge: .minY)
      result(nil)
    }
    self.nativeActionsChannel = nativeActions

    BnbuAppNavigationBridge.shared.configure(
      messenger: flutterViewController.engine.binaryMessenger
    )
    let loginInputSourceChannel = FlutterMethodChannel(
      name: "ispace/login_input_source",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    loginInputSourceChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "activateEnglishKeyboard":
        result(self.loginInputSourceController.activateEnglishKeyboard())
      case "restorePreviousKeyboard":
        result(self.loginInputSourceController.restorePreviousKeyboard())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.loginInputSourceChannel = loginInputSourceChannel

    let widgetSnapshotChannel = FlutterMethodChannel(
      name: "ispace/widget_snapshot",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    widgetSnapshotChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      guard
  let appGroupIdentifier = Bundle.main.object(
    forInfoDictionaryKey: "BnbuAppGroupIdentifier"
  ) as? String,
  !appGroupIdentifier.isEmpty,
  !appGroupIdentifier.hasPrefix("group.invalid."),
  let containerURL = FileManager.default.containerURL(
    forSecurityApplicationGroupIdentifier: appGroupIdentifier
  )
else {
        result(
          FlutterError(
            code: "widget_store_unavailable",
            message: "Unable to open the shared widget container",
            details: nil
          )
        )
        return
      }
      switch call.method {
      case "updateWidgetSnapshot":
        guard
          let arguments = call.arguments as? [String: Any],
          let payload = arguments["json"] as? String
        else {
          result(
            FlutterError(code: "bad_args", message: "Missing widget snapshot", details: nil)
          )
          return
        }
        self.widgetSnapshotQueue.async {
          let snapshotURL = containerURL.appendingPathComponent(
            Self.widgetSnapshotFileName,
            isDirectory: false
          )
          do {
            try Data(payload.utf8).write(to: snapshotURL, options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
            DispatchQueue.main.async { result(true) }
          } catch {
            DispatchQueue.main.async {
              result(
                FlutterError(
                  code: "widget_store_write_failed",
                  message: "Unable to save the shared widget snapshot",
                  details: nil
                )
              )
            }
          }
        }
      case "clearWidgetSnapshot":
        self.widgetSnapshotQueue.async {
          let snapshotURL = containerURL.appendingPathComponent(
            Self.widgetSnapshotFileName,
            isDirectory: false
          )
          do {
            if FileManager.default.fileExists(atPath: snapshotURL.path) {
              try FileManager.default.removeItem(at: snapshotURL)
            }
            WidgetCenter.shared.reloadAllTimelines()
            DispatchQueue.main.async { result(true) }
          } catch {
            DispatchQueue.main.async {
              result(
                FlutterError(
                  code: "widget_store_clear_failed",
                  message: "Unable to clear the shared widget snapshot",
                  details: nil
                )
              )
            }
          }
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.widgetSnapshotChannel = widgetSnapshotChannel

    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
    }

    super.awakeFromNib()
  }

  override func close() {
    _ = loginInputSourceController.restorePreviousKeyboard()
    super.close()
  }

  private func configureCourseArchiveExport(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "ispace/course_archive_export", binaryMessenger: messenger)
    courseArchiveExportChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      guard ["prepare", "commit", "discard"].contains(call.method) else {
        result(FlutterMethodNotImplemented); return
      }
      let args = call.arguments as? [String: String] ?? [:]
      self.courseArchiveExportQueue.async {
        do {
          let value: Any?
          switch call.method {
          case "prepare":
            value = try self.courseArchiveExportStore.prepare(
              sourcePath: args["sourcePath"] ?? "", destinationPath: args["destinationPath"] ?? "")
          case "commit":
            try self.courseArchiveExportStore.commit(args["id"] ?? "")
            value = true
          default:
            self.courseArchiveExportStore.discard(args["id"] ?? "")
            value = nil
          }
          DispatchQueue.main.async { result(value) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "course_archive_export_failed",
              message: "Unable to export the course archive.", details: nil))
          }
        }
      }
    }
  }

  private func configureDesktopDownloads(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "ispace/desktop_downloads", binaryMessenger: messenger)
    desktopDownloadsChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      let args = call.arguments as? [String: String] ?? [:]
      let purpose = args["purpose"] ?? ""
      if call.method == "openSavedFile" {
        do {
          result(try self.desktopDownloadStore.withSavedFile(args["path"] ?? "") {
            NSWorkspace.shared.open($0)
          })
        } catch {
          result(FlutterError(code: "download_open_failed", message: "Unable to open file", details: nil))
        }
        return
      }
      if call.method == "chooseDirectory" {
        guard ["single", "archive"].contains(purpose) else {
          result(FlutterError(code: "invalid_purpose", message: "Invalid destination", details: nil)); return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: self) { response in
          guard response == .OK, let url = panel.url else { result(nil); return }
          do {
            try self.desktopDownloadStore.choose(url, purpose: purpose)
            result(url.path)
          } catch {
            result(FlutterError(code: "download_directory_failed", message: "Unable to authorize directory", details: nil))
          }
        }
        return
      }
      guard ["directory", "resetDirectory", "prepare", "commit", "discard"].contains(call.method) else {
        result(FlutterMethodNotImplemented); return
      }
      self.courseArchiveExportQueue.async {
        do {
          let value: Any?
          switch call.method {
          case "directory": value = try self.desktopDownloadStore.directory(purpose).path
          case "resetDirectory": value = try self.desktopDownloadStore.reset(purpose).path
          case "prepare": value = try self.desktopDownloadStore.prepare(
            sourcePath: args["sourcePath"] ?? "", fileName: args["fileName"] ?? "", purpose: purpose)
          case "commit": value = try self.desktopDownloadStore.commit(args["id"] ?? "")
          default:
            self.desktopDownloadStore.discard(args["id"] ?? "")
            value = nil
          }
          DispatchQueue.main.async { result(value) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "desktop_download_failed",
              message: "Unable to save file. Choose an accessible download directory and retry.", details: nil))
          }
        }
      }
    }
  }
}

private final class LoginInputSourceController {
  private var previousInputSource: TISInputSource?

  func activateEnglishKeyboard() -> Bool {
    if previousInputSource == nil {
      previousInputSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    }
    let englishInputSource =
      TISCopyCurrentASCIICapableKeyboardInputSource().takeRetainedValue()
    return TISSelectInputSource(englishInputSource) == noErr
  }

  func restorePreviousKeyboard() -> Bool {
    guard let previousInputSource else {
      return true
    }
    self.previousInputSource = nil
    return TISSelectInputSource(previousInputSource) == noErr
  }
}

import Flutter
import CoreText
import Foundation
import MobileCoreServices
import Photos
import UIKit
import QuickLook
import WebKit
import WidgetKit

private func bnbuWidgetDefaults() -> UserDefaults? {
  guard
    let identifier = Bundle.main.object(
      forInfoDictionaryKey: "BnbuAppGroupIdentifier"
    ) as? String,
    !identifier.isEmpty
  else {
    return nil
  }
  return UserDefaults(suiteName: identifier)
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  UIDocumentInteractionControllerDelegate
{
  private let mailRadarBackgroundChannelName = "ispace/mail_radar_background"
  private let credentialUserDefaultsKeyUser = "ispace.saved_username"
  private let credentialUserDefaultsKeyPass = "ispace.saved_password"
  private let credentialLogoutTombstoneKey = "ispace.logout_tombstone"
  private let shareCacheMaxAge: TimeInterval = 24 * 60 * 60
  private var documentInteractionController: UIDocumentInteractionController?
  private var shareActivityController: UIActivityViewController?
  private var ecardOriginalBrightness: CGFloat?
  private var ecardWallet: BnbuEcardWalletBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    application.setMinimumBackgroundFetchInterval(UIApplication.backgroundFetchIntervalMinimum)
    let widgetDefaults = bnbuWidgetDefaults()
    BnbuWatchConnectivityManager.shared.start(
      initialSnapshotJSON: widgetDefaults?.string(forKey: "bnbu.widget.snapshot.v1")
    )
    synchronizeLiveActivityFromCachedSnapshot()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    synchronizeLiveActivityFromCachedSnapshot()
  }

  override func application(
    _ application: UIApplication,
    performFetchWithCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    synchronizeLiveActivityFromCachedSnapshot()
    guard let messenger = self.registrar(forPlugin: "BnbuMailRadarBackground")?.messenger() else {
      completionHandler(.noData)
      return
    }
    let channel = FlutterMethodChannel(
      name: mailRadarBackgroundChannelName,
      binaryMessenger: messenger
    )
    var completed = false
    let finish: (UIBackgroundFetchResult) -> Void = { result in
      guard !completed else { return }
      completed = true
      completionHandler(result)
    }
    channel.invokeMethod("performRefresh", arguments: nil) { result in
      if result is FlutterError {
        finish(.failed)
      } else {
        finish((result as? Bool) == true ? .newData : .noData)
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
      finish(.failed)
    }
  }

  func synchronizeLiveActivityFromCachedSnapshot() {
    guard
      #available(iOS 16.2, *),
      let snapshotJSON = bnbuWidgetDefaults()?.string(forKey: "bnbu.widget.snapshot.v1")
    else {
      return
    }
    BnbuLiveActivityManager.shared.synchronize(snapshotJSON: snapshotJSON)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    let registrar = engineBridge.applicationRegistrar
    let messenger = registrar.messenger()
    let presentationRegistrar = engineBridge.pluginRegistry.registrar(forPlugin: "BnbuNativeActions")

    ecardWallet = BnbuEcardWalletBridge(messenger: messenger,
      source: { presentationRegistrar?.viewController })
    registrar.register(BnbuWalletAddButtonFactory(messenger: messenger),
      withId: "bnbu/wallet_add_button")

    registrar.register(BnbuFilePreviewFactory(source: { presentationRegistrar?.viewController }),
      withId: "ispace/file_preview")

    BnbuAppNavigationBridge.shared.configure(messenger: messenger)
    BnbuStatisticsBridge.shared.configure(messenger: messenger)

    registrar.register(
      IspaceNativeWebViewFactory(messenger: messenger),
      withId: "ispace/native_webview"
    )
    registrar.register(
      BnbuLiquidGlassFactory(),
      withId: "ispace/liquid_glass"
    )
    registrar.register(
      BnbuSmallUGlassFactory(
        assetKey: FlutterDartProject.lookupKey(forAsset: "assets/branding/small_u_light.png")
      ),
      withId: "ispace/small_u_glass_logo"
    )
    registrar.register(
      BnbuNativeTabBarFactory(messenger: messenger),
      withId: "ispace/native_tab_bar"
    )

    let meIdentityChannel = FlutterMethodChannel(name: "bnbu/me_identity", binaryMessenger: messenger)
    meIdentityChannel.setMethodCallHandler { call, result in
      guard call.method == "installationMarker" else { result(FlutterMethodNotImplemented); return }
      do {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var marker = root.appendingPathComponent("me-installation-v1")
        let value: String
        if FileManager.default.fileExists(atPath: marker.path) {
          value = try String(contentsOf: marker, encoding: .utf8)
          guard UUID(uuidString: value) != nil else { throw NSError(domain: "bnbu.me_identity", code: 1) }
        } else {
          value = UUID().uuidString
          try value.write(to: marker, atomically: true, encoding: .utf8)
        }
        var options = URLResourceValues()
        options.isExcludedFromBackup = true
        try marker.setResourceValues(options)
        result(value)
      } catch {
        result(FlutterError(code: "identity_storage_unavailable", message: "设备身份存储不可用", details: nil))
      }
    }

    let updateEnvironmentChannel = FlutterMethodChannel(
      name: "bnbu/update_environment", binaryMessenger: messenger
    )
    updateEnvironmentChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "systemVersion": result(UIDevice.current.systemVersion)
      case "distributionChannel":
        let receipt = Bundle.main.appStoreReceiptURL?.lastPathComponent
        result(receipt == "sandboxReceipt" ? "testflight" : receipt == "receipt" ? "app_store" : "local")
      default: result(FlutterMethodNotImplemented)
      }
    }

    let platformCapabilitiesChannel = FlutterMethodChannel(
      name: "ispace/platform_capabilities",
      binaryMessenger: messenger
    )
    platformCapabilitiesChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "supportsLiquidGlass":
        if #available(iOS 26.0, *) {
          result(true)
        } else {
          result(false)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let ecardBrightnessChannel = FlutterMethodChannel(
      name: "ispace/ecard_brightness",
      binaryMessenger: messenger
    )
    ecardBrightnessChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(
          FlutterError(code: "deallocated", message: "AppDelegate unavailable", details: nil)
        )
        return
      }
      switch call.method {
      case "begin":
        self.beginEcardBrightness()
        result(true)
      case "end":
        self.restoreEcardBrightness()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    do {
      let widgetSnapshotChannel = FlutterMethodChannel(
        name: "ispace/widget_snapshot",
        binaryMessenger: messenger
      )
      widgetSnapshotChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "updateWatchInterfaceLanguage":
          guard
            let arguments = call.arguments as? [String: Any],
            let languageTag = arguments["languageTag"] as? String
          else {
            result(
              FlutterError(code: "bad_args", message: "Missing Watch language", details: nil)
            )
            return
          }
          BnbuWatchConnectivityManager.shared.updateInterfaceLanguage(languageTag)
          result(true)
        case "updateWidgetSnapshot":
          guard
            let defaults = bnbuWidgetDefaults(),
            let arguments = call.arguments as? [String: Any],
            let payload = arguments["json"] as? String
          else {
            result(
              FlutterError(
                code: "widget_store_unavailable",
                message: "Unable to store the widget snapshot",
                details: nil
              )
            )
            return
          }
          defaults.set(payload, forKey: "bnbu.widget.snapshot.v1")
          BnbuWatchConnectivityManager.shared.update(snapshotJSON: payload)
          if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
          }
          if #available(iOS 16.2, *) {
            BnbuLiveActivityManager.shared.synchronize(snapshotJSON: payload)
          }
          result(true)
        case "clearWidgetSnapshot":
          guard let defaults = bnbuWidgetDefaults() else {
            result(
              FlutterError(
                code: "widget_store_unavailable",
                message: "Unable to open the shared widget container",
                details: nil
              )
            )
            return
          }
          defaults.removeObject(forKey: "bnbu.widget.snapshot.v1")
          BnbuWatchConnectivityManager.shared.clear()
          if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
          }
          if #available(iOS 16.2, *) {
            BnbuLiveActivityManager.shared.clear()
          }
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      let credentialStoreChannel = FlutterMethodChannel(
        name: "ispace/credential_store",
        binaryMessenger: messenger
      )
      credentialStoreChannel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(
            FlutterError(code: "deallocated", message: "AppDelegate unavailable", details: nil)
          )
          return
        }
        switch call.method {
        case "readLegacyCredentials":
          let defaults = UserDefaults.standard
          let username = defaults.string(forKey: self.credentialUserDefaultsKeyUser) ?? ""
          let password = defaults.string(forKey: self.credentialUserDefaultsKeyPass) ?? ""
          if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty {
            result(nil)
            return
          }
          result([
            "username": username,
            "password": password,
          ])
        case "clearLegacyCredentials":
          let defaults = UserDefaults.standard
          defaults.removeObject(forKey: self.credentialUserDefaultsKeyUser)
          defaults.removeObject(forKey: self.credentialUserDefaultsKeyPass)
          if defaults.synchronize() {
            result(true)
          } else {
            result(
              FlutterError(
                code: "legacy_clear_failed",
                message: "Unable to durably clear legacy credentials",
                details: nil
              )
            )
          }
        case "readLogoutTombstone":
          result(UserDefaults.standard.bool(forKey: self.credentialLogoutTombstoneKey))
        case "setLogoutTombstone":
          guard
            let arguments = call.arguments as? [String: Any],
            let blocked = arguments["blocked"] as? Bool
          else {
            result(
              FlutterError(code: "bad_args", message: "Missing logout state", details: nil)
            )
            return
          }
          let defaults = UserDefaults.standard
          if blocked {
            defaults.set(true, forKey: self.credentialLogoutTombstoneKey)
          } else {
            defaults.removeObject(forKey: self.credentialLogoutTombstoneKey)
          }
          if defaults.synchronize() {
            result(true)
          } else {
            result(
              FlutterError(
                code: "logout_tombstone_failed",
                message: "Unable to durably update logout state",
                details: nil
              )
            )
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }

      let channel = FlutterMethodChannel(
        name: "ispace/native_actions",
        binaryMessenger: messenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard let self = self else {
          result(
            FlutterError(code: "deallocated", message: "AppDelegate unavailable", details: nil)
          )
          return
        }
        let sourceViewController = presentationRegistrar?.viewController
        switch call.method {
        case "downloadFile":
          guard
            let args = call.arguments as? [String: Any],
            let urlString = args["url"] as? String,
            let remoteUrl = URL(string: urlString)
          else {
            result(
              FlutterError(code: "bad_args", message: "Missing url", details: call.arguments)
            )
            return
          }
          let preferredName = (args["filename"] as? String) ?? ""
          let cookieHeader = (args["cookieHeader"] as? String) ?? ""
          let cookieOrigin = (args["cookieOrigin"] as? String) ?? ""
          self.downloadFile(
            from: remoteUrl,
            preferredFileName: preferredName,
            cookieHeader: cookieHeader,
            cookieOrigin: cookieOrigin,
            persistent: true
          ) { downloadResult in
            switch downloadResult {
            case .success(let localUrl):
              result(localUrl.path)
            case .failure(let error):
              result(
                FlutterError(
                  code: "download_failed",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            }
          }
        case "openExternalUrl":
          guard
            let args = call.arguments as? [String: Any],
            let urlString = args["url"] as? String,
            let url = URL(string: urlString)
          else {
            result(
              FlutterError(code: "bad_args", message: "Missing url", details: call.arguments)
            )
            return
          }
          DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { success in
              result(success)
            }
          }
        case "shareUrl":
          guard
            let args = call.arguments as? [String: Any],
            let urlString = args["url"] as? String,
            !urlString.isEmpty
          else {
            result(
              FlutterError(code: "bad_args", message: "Missing url", details: call.arguments)
            )
            return
          }
          let title = (args["title"] as? String) ?? ""
          let preferredName = (args["filename"] as? String) ?? ""
          let cookieHeader = (args["cookieHeader"] as? String) ?? ""
          let cookieOrigin = (args["cookieOrigin"] as? String) ?? ""
          if self.shouldShareAsFile(urlString), let remoteUrl = URL(string: urlString) {
            self.downloadFile(
              from: remoteUrl,
              preferredFileName: preferredName,
              cookieHeader: cookieHeader,
              cookieOrigin: cookieOrigin,
              persistent: false
            ) { downloadResult in
              switch downloadResult {
              case .success(let localUrl):
                self.presentShareSheet(
                  items: [localUrl],
                  source: sourceViewController,
                  cleanupUrl: localUrl.deletingLastPathComponent(),
                  result: result
                )
              case .failure(let error):
                result(
                  FlutterError(
                    code: "share_failed",
                    message: error.localizedDescription,
                    details: nil
                  )
                )
              }
            }
            return
          }
          let items: [Any] = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? [urlString] : [title, urlString]
          self.presentShareSheet(items: items, source: sourceViewController, result: result)
        case "shareFile":
          guard
            let args = call.arguments as? [String: Any],
            let urlString = args["url"] as? String,
            let remoteUrl = URL(string: urlString)
          else {
            result(
              FlutterError(code: "bad_args", message: "Missing url", details: call.arguments)
            )
            return
          }
          let preferredName = (args["filename"] as? String) ?? ""
          let cookieHeader = (args["cookieHeader"] as? String) ?? ""
          let cookieOrigin = (args["cookieOrigin"] as? String) ?? ""
          self.downloadFile(
            from: remoteUrl,
            preferredFileName: preferredName,
            cookieHeader: cookieHeader,
            cookieOrigin: cookieOrigin,
            persistent: false
          ) { downloadResult in
            switch downloadResult {
            case .success(let localUrl):
              self.presentShareSheet(
                items: [localUrl],
                source: sourceViewController,
                cleanupUrl: localUrl.deletingLastPathComponent(),
                result: result
              )
            case .failure(let error):
              result(
                FlutterError(
                  code: "share_failed",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            }
          }
        case "clearWebSession":
          NativeWebSessionRegistry.clearAll {
            let dataStore = WKWebsiteDataStore.default()
            dataStore.removeData(
              ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
              modifiedSince: .distantPast
            ) {
              result(true)
            }
          }
        case "getMailAttachmentCacheDir":
          do {
            let directory = try self.mailAttachmentCacheDirectory()
            result(directory.path)
          } catch {
            result(
              FlutterError(
                code: "cache_directory_failed",
                message: error.localizedDescription,
                details: nil
              )
            )
          }
        case "canPreviewFile":
          let path = (call.arguments as? [String: Any])?["path"] as? String ?? ""
          result(FileManager.default.fileExists(atPath: path) && QLPreviewController.canPreview(URL(fileURLWithPath: path) as NSURL))
        case "shareLocalFile":
          guard let args = call.arguments as? [String: Any],
            let path = args["path"] as? String,
            FileManager.default.fileExists(atPath: path) else {
            result(FlutterError(code: "file_not_found", message: "File unavailable", details: nil)); return
          }
          DispatchQueue.global(qos: .userInitiated).async {
            do {
              let directory = FileManager.default.temporaryDirectory.appendingPathComponent("bnbu-share-" + UUID().uuidString, isDirectory: true)
              try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
              let filename = self.sanitizedFileName(args["filename"] as? String ?? "file")
              let copy = directory.appendingPathComponent(filename.isEmpty ? "file" : filename)
              do { try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: copy) }
              catch { try? FileManager.default.removeItem(at: directory); throw error }
              DispatchQueue.main.async {
                self.presentShareSheet(items: [copy], source: sourceViewController, cleanupUrl: directory, result: result)
              }
            } catch {
              DispatchQueue.main.async { result(FlutterError(code: "share_failed", message: "Unable to share file", details: nil)) }
            }
          }
        case "openFile":
          guard
            let args = call.arguments as? [String: Any],
            let path = args["path"] as? String,
            !path.isEmpty
          else {
            result(
              FlutterError(code: "bad_args", message: "Missing path", details: call.arguments)
            )
            return
          }
          let mimeType = (args["mimeType"] as? String) ?? "application/octet-stream"
          self.openFile(
            at: URL(fileURLWithPath: path),
            source: sourceViewController,
            mimeType: mimeType,
            result: result
          )
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if BnbuAppNavigationBridge.shared.handle(url: url) {
      return true
    }
    return super.application(app, open: url, options: options)
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    restoreEcardBrightness()
    super.applicationWillResignActive(application)
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    restoreEcardBrightness()
    super.applicationWillTerminate(application)
  }

  private func beginEcardBrightness() {
    if ecardOriginalBrightness == nil {
      ecardOriginalBrightness = UIScreen.main.brightness
    }
    UIScreen.main.brightness = 1
  }

  func restoreEcardBrightness() {
    guard let originalBrightness = ecardOriginalBrightness else { return }
    UIScreen.main.brightness = originalBrightness
    ecardOriginalBrightness = nil
  }

  private func mailAttachmentCacheDirectory() throws -> URL {
    let cacheRoot = FileManager.default.urls(
      for: .cachesDirectory,
      in: .userDomainMask
    ).first!
    let directory = cacheRoot.appendingPathComponent(
      "mail_attachments",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }

  private func openFile(
    at url: URL,
    source: UIViewController?,
    mimeType: String,
    result: @escaping FlutterResult
  ) {
    guard FileManager.default.fileExists(atPath: url.path) else {
      result(
        FlutterError(code: "file_not_found", message: "文件不存在", details: url.path)
      )
      return
    }

    DispatchQueue.main.async {
      guard self.documentInteractionController == nil, self.shareActivityController == nil else {
        result(
          FlutterError(
            code: "presentation_in_progress",
            message: "已有文件打开菜单，请先关闭后重试。",
            details: nil
          )
        )
        return
      }
      guard let presenter = BnbuNativePresentation.presenter(for: source) else {
        result(
          FlutterError(
            code: "no_presenter",
            message: "No view controller available to open the file",
            details: nil
          )
        )
        return
      }
      let sourceView = presenter.view!

      let controller = UIDocumentInteractionController(url: url)
      controller.delegate = self
      if let typeIdentifier = self.typeIdentifier(
        mimeType: mimeType,
        fileExtension: url.pathExtension
      ) {
        controller.uti = typeIdentifier
      }
      self.documentInteractionController = controller
      let presented = controller.presentOptionsMenu(
        from: sourceView.bounds,
        in: sourceView,
        animated: true
      )
      if presented {
        result(true)
      } else {
        self.documentInteractionController = nil
        result(
          FlutterError(
            code: "no_app",
            message: "没有可以打开此类型文件的应用",
            details: nil
          )
        )
      }
    }
  }

  private func typeIdentifier(mimeType: String, fileExtension: String) -> String? {
    let normalizedMimeType = mimeType.trimmingCharacters(in: .whitespacesAndNewlines)
    if !normalizedMimeType.isEmpty, normalizedMimeType != "*/*",
      let value = UTTypeCreatePreferredIdentifierForTag(
        kUTTagClassMIMEType,
        normalizedMimeType as CFString,
        nil
      )?.takeRetainedValue()
    {
      return value as String
    }

    let normalizedExtension = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
    if !normalizedExtension.isEmpty,
      let value = UTTypeCreatePreferredIdentifierForTag(
        kUTTagClassFilenameExtension,
        normalizedExtension as CFString,
        nil
      )?.takeRetainedValue()
    {
      return value as String
    }
    return nil
  }

  private func presentShareSheet(
    items: [Any],
    source: UIViewController?,
    cleanupUrl: URL? = nil,
    result: @escaping FlutterResult
  ) {
    DispatchQueue.main.async {
      guard self.shareActivityController == nil, self.documentInteractionController == nil else {
        if let cleanupUrl {
          try? FileManager.default.removeItem(at: cleanupUrl)
        }
        result(
          FlutterError(
            code: "presentation_in_progress",
            message: "已有分享菜单，请先关闭后重试。",
            details: nil
          )
        )
        return
      }
      guard let presenter = BnbuNativePresentation.presenter(for: source) else {
        if let cleanupUrl {
          try? FileManager.default.removeItem(at: cleanupUrl)
        }
        result(
          FlutterError(
            code: "no_presenter",
            message: "No view controller to present share sheet",
            details: nil
          )
        )
        return
      }

      let activityVC = UIActivityViewController(
        activityItems: items,
        applicationActivities: nil
      )
      self.shareActivityController = activityVC
      activityVC.completionWithItemsHandler = { [weak self, weak activityVC] _, _, _, _ in
        DispatchQueue.main.async {
          if let cleanupUrl {
            try? FileManager.default.removeItem(at: cleanupUrl)
          }
          if let self, let activityVC, self.shareActivityController === activityVC {
            self.shareActivityController = nil
          }
        }
      }
      if let popover = activityVC.popoverPresentationController {
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(
          x: presenter.view.bounds.midX,
          y: presenter.view.bounds.midY,
          width: 0,
          height: 0
        )
      }
      presenter.present(activityVC, animated: true) {
        guard activityVC.presentingViewController != nil else {
          if let cleanupUrl {
            try? FileManager.default.removeItem(at: cleanupUrl)
          }
          if self.shareActivityController === activityVC {
            self.shareActivityController = nil
          }
          result(
            FlutterError(
              code: "presentation_failed",
              message: "Unable to present share sheet",
              details: nil
            )
          )
          return
        }
        result(true)
      }
    }
  }

  private func downloadFile(
    from remoteUrl: URL,
    preferredFileName: String,
    cookieHeader: String,
    cookieOrigin: String,
    persistent: Bool,
    completion: @escaping (Result<URL, Error>) -> Void
  ) {
    guard isHttpUrl(remoteUrl) else {
      completion(
        .failure(
          NSError(
            domain: "ispace.native_actions",
            code: -2,
            userInfo: [NSLocalizedDescriptionKey: "仅支持 HTTP(S) 文件下载"]
          )
        )
      )
      return
    }

    var request = URLRequest(url: remoteUrl)
    let extraCookie = cookieHeader.trimmingCharacters(in: .whitespacesAndNewlines)
    if !extraCookie.isEmpty, urlsHaveSameOrigin(remoteUrl, cookieOrigin) {
      request.setValue(extraCookie, forHTTPHeaderField: "Cookie")
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 120
    configuration.httpShouldSetCookies = false
    let redirectDelegate = SameOriginCookieRedirectDelegate(
      cookieHeader: extraCookie,
      cookieOrigin: URL(string: cookieOrigin),
      initialUrl: remoteUrl
    )
    let session = URLSession(
      configuration: configuration,
      delegate: redirectDelegate,
      delegateQueue: nil
    )
    session.downloadTask(with: request) { [weak self] tempUrl, response, error in
      defer { session.finishTasksAndInvalidate() }
      if let error {
        completion(.failure(error))
        return
      }
      if let response = response as? HTTPURLResponse,
        !(200...299).contains(response.statusCode)
      {
        completion(
          .failure(
            NSError(
              domain: "ispace.native_actions",
              code: response.statusCode,
              userInfo: [
                NSLocalizedDescriptionKey: "下载失败（HTTP \(response.statusCode)）"
              ]
            )
          )
        )
        return
      }
      guard let self = self, let tempUrl = tempUrl else {
        completion(
          .failure(
            NSError(
              domain: "ispace.native_actions",
              code: -1,
              userInfo: [NSLocalizedDescriptionKey: "下载失败：临时文件不存在"]
            )
          )
        )
        return
      }

      let suggested = response?.suggestedFilename ?? "download.bin"
      let incomingName = preferredFileName.trimmingCharacters(in: .whitespacesAndNewlines)
      let fileName = self.sanitizedFileName(incomingName.isEmpty ? suggested : incomingName)
      if self.isUnexpectedHtmlResponse(response, fileName: fileName) {
        completion(
          .failure(
            NSError(
              domain: "ispace.native_actions",
              code: -3,
              userInfo: [
                NSLocalizedDescriptionKey: "下载返回了登录页面，而不是请求的文件"
              ]
            )
          )
        )
        return
      }

      do {
        let destination: URL
        if persistent {
          let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
          ).first!
          destination = try self.movePersistentDownload(
            at: tempUrl,
            to: documents,
            fileName: fileName
          )
          var resourceValues = URLResourceValues()
          resourceValues.isExcludedFromBackup = true
          var mutableDestination = destination
          try? mutableDestination.setResourceValues(resourceValues)
        } else {
          let cacheRoot = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
          ).first!
          let shareRoot = cacheRoot.appendingPathComponent(
            "shared_files",
            isDirectory: true
          )
          self.pruneStaleShareCache(at: shareRoot)
          let shareDirectory = shareRoot.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
          )
          try FileManager.default.createDirectory(
            at: shareDirectory,
            withIntermediateDirectories: true
          )
          destination = shareDirectory.appendingPathComponent(fileName)
          do {
            try FileManager.default.moveItem(at: tempUrl, to: destination)
          } catch {
            try? FileManager.default.removeItem(at: shareDirectory)
            throw error
          }
        }
        completion(.success(destination))
      } catch {
        completion(.failure(error))
      }
    }.resume()
  }

  private func isHttpUrl(_ url: URL) -> Bool {
    let scheme = url.scheme?.lowercased()
    return (scheme == "http" || scheme == "https") && url.host?.isEmpty == false
  }

  private func urlsHaveSameOrigin(_ target: URL, _ originString: String) -> Bool {
    guard let origin = URL(string: originString), isHttpUrl(target), isHttpUrl(origin) else {
      return false
    }
    return target.scheme?.caseInsensitiveCompare(origin.scheme ?? "") == .orderedSame
      && target.host?.caseInsensitiveCompare(origin.host ?? "") == .orderedSame
      && effectivePort(target) == effectivePort(origin)
  }

  private func effectivePort(_ url: URL) -> Int {
    if let port = url.port {
      return port
    }
    switch url.scheme?.lowercased() {
    case "http":
      return 80
    case "https":
      return 443
    default:
      return -1
    }
  }

  private func movePersistentDownload(
    at temporaryUrl: URL,
    to directory: URL,
    fileName: String
  ) throws -> URL {
    let base = (fileName as NSString).deletingPathExtension
    let ext = (fileName as NSString).pathExtension
    var destination = directory.appendingPathComponent(fileName)

    for attempt in 0..<10 {
      do {
        try FileManager.default.moveItem(at: temporaryUrl, to: destination)
        return destination
      } catch {
        let cocoaError = error as NSError
        guard cocoaError.domain == NSCocoaErrorDomain,
          cocoaError.code == CocoaError.Code.fileWriteFileExists.rawValue,
          attempt < 9
        else {
          throw error
        }
        let suffix = UUID().uuidString.lowercased()
        let uniqueName = ext.isEmpty
          ? "\(base)-\(suffix)"
          : "\(base)-\(suffix).\(ext)"
        destination = directory.appendingPathComponent(uniqueName)
      }
    }
    throw NSError(
      domain: "ispace.native_actions",
      code: -4,
      userInfo: [NSLocalizedDescriptionKey: "Unable to allocate a download filename"]
    )
  }

  private func pruneStaleShareCache(at root: URL) {
    guard
      let entries = try? FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.contentModificationDateKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return
    }
    let cutoff = Date().addingTimeInterval(-shareCacheMaxAge)
    for entry in entries {
      let modified = try? entry.resourceValues(
        forKeys: [.contentModificationDateKey]
      ).contentModificationDate
      if modified == nil || modified! < cutoff {
        try? FileManager.default.removeItem(at: entry)
      }
    }
  }

  private func isUnexpectedHtmlResponse(
    _ response: URLResponse?,
    fileName: String
  ) -> Bool {
    let mimeType = response?.mimeType?.lowercased() ?? ""
    guard mimeType == "text/html" || mimeType == "application/xhtml+xml" else {
      return false
    }
    if response?.url?.path.lowercased().contains("/login") == true {
      return true
    }
    let ext = (fileName as NSString).pathExtension.lowercased()
    return !ext.isEmpty && !["html", "htm", "xhtml"].contains(ext)
  }

  private func sanitizedFileName(_ raw: String) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty {
      return "download.bin"
    }
    let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
      .union(.controlCharacters)
    value = value.components(separatedBy: invalid).joined(separator: "_")
    if value.isEmpty || value == "." || value == ".." {
      value = "download.bin"
    }
    return truncateFileNameUtf8(value, maxBytes: 200)
  }

  private func truncateFileNameUtf8(_ fileName: String, maxBytes: Int) -> String {
    if fileName.lengthOfBytes(using: .utf8) <= maxBytes {
      return fileName
    }
    let path = fileName as NSString
    let ext = path.pathExtension
    let base = path.deletingPathExtension
    let suffix = ext.isEmpty ? "" : ".\(ext)"
    if suffix.lengthOfBytes(using: .utf8) >= maxBytes {
      let truncated = truncateUtf8(fileName, maxBytes: maxBytes)
      return truncated.isEmpty ? "download.bin" : truncated
    }
    let truncatedBase = truncateUtf8(
      base,
      maxBytes: maxBytes - suffix.lengthOfBytes(using: .utf8)
    )
    return (truncatedBase.isEmpty ? "download" : truncatedBase) + suffix
  }

  private func truncateUtf8(_ value: String, maxBytes: Int) -> String {
    var output = ""
    var byteCount = 0
    for character in value {
      let characterString = String(character)
      let characterBytes = characterString.lengthOfBytes(using: .utf8)
      if byteCount + characterBytes > maxBytes {
        break
      }
      output.append(character)
      byteCount += characterBytes
    }
    return output
  }

  private func shouldShareAsFile(_ urlString: String) -> Bool {
    let lower = urlString.lowercased()
    if lower.contains("/pluginfile.php")
      || lower.contains("/webservice/pluginfile.php")
      || lower.contains("/mod/resource/view.php")
      || lower.contains("/mod/folder/download_folder.php")
    {
      return true
    }
    let pattern = #"\.(pdf|ppt|pptx|doc|docx|xls|xlsx|zip|rar|7z|jpg|jpeg|png|gif|webp|mp4|mp3)(\?|$)"#
    return lower.range(of: pattern, options: .regularExpression) != nil
  }

  func documentInteractionControllerDidDismissOptionsMenu(
    _ controller: UIDocumentInteractionController
  ) {
    releaseDocumentInteractionController(controller)
  }

  func documentInteractionControllerDidDismissOpenInMenu(
    _ controller: UIDocumentInteractionController
  ) {
    releaseDocumentInteractionController(controller)
  }

  func documentInteractionControllerDidEndPreview(
    _ controller: UIDocumentInteractionController
  ) {
    releaseDocumentInteractionController(controller)
  }

  private func releaseDocumentInteractionController(
    _ controller: UIDocumentInteractionController
  ) {
    if documentInteractionController === controller {
      documentInteractionController = nil
    }
  }
}

final class BnbuLiquidGlassFactory: NSObject, FlutterPlatformViewFactory {
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    BnbuLiquidGlassPlatformView(frame: frame, arguments: args)
  }
}

final class BnbuLiquidGlassPlatformView: NSObject, FlutterPlatformView {
  private let glassView: BnbuLiquidGlassView

  init(frame: CGRect, arguments: Any?) {
    glassView = BnbuLiquidGlassView(frame: frame, arguments: arguments)
    super.init()
  }

  func view() -> UIView {
    glassView
  }
}

final class BnbuLiquidGlassView: UIView {
  private let visualEffectView = UIVisualEffectView()
  private let tint: UIColor
  private let interactive: Bool

  init(frame: CGRect, arguments: Any?) {
    let values = arguments as? [String: Any]
    let tintValue = (values?["tintColor"] as? NSNumber)?.uint32Value ?? 0xFF0068B5
    tint = UIColor(
      red: CGFloat((tintValue >> 16) & 0xFF) / 255,
      green: CGFloat((tintValue >> 8) & 0xFF) / 255,
      blue: CGFloat(tintValue & 0xFF) / 255,
      alpha: CGFloat((tintValue >> 24) & 0xFF) / 255
    )
    interactive = values?["interactive"] as? Bool ?? true
    super.init(frame: frame)

    isUserInteractionEnabled = false
    clipsToBounds = true
    if #available(iOS 13.0, *) {
      layer.cornerCurve = .continuous
    }
    layer.cornerRadius = CGFloat(
      (values?["cornerRadius"] as? NSNumber)?.doubleValue ?? 24
    )
    visualEffectView.frame = bounds
    visualEffectView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(visualEffectView)
    refreshMaterial()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(accessibilityAppearanceDidChange),
      name: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
      object: nil
    )
  }

  required init?(coder: NSCoder) {
    nil
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func accessibilityAppearanceDidChange() {
    refreshMaterial()
  }

  private func refreshMaterial() {
    if UIAccessibility.isReduceTransparencyEnabled {
      visualEffectView.effect = nil
      if #available(iOS 13.0, *) {
        backgroundColor = UIColor.systemBackground.withAlphaComponent(0.96)
      } else {
        backgroundColor = UIColor.white.withAlphaComponent(0.96)
      }
      return
    }

    backgroundColor = .clear
    if #available(iOS 26.0, *) {
      let effect = UIGlassEffect(style: .regular)
      effect.isInteractive = interactive
      effect.tintColor = tint.withAlphaComponent(0.10)
      visualEffectView.effect = effect
    } else if #available(iOS 13.0, *) {
      visualEffectView.effect = UIBlurEffect(style: .systemChromeMaterial)
      visualEffectView.backgroundColor = tint.withAlphaComponent(0.035)
    } else {
      visualEffectView.effect = UIBlurEffect(style: .extraLight)
      visualEffectView.backgroundColor = tint.withAlphaComponent(0.025)
    }
  }
}

/// Preserve the exact bundled knot silhouette, including its interlocking gaps.
/// No page capture, persisted bitmap or network input is involved.
final class BnbuSmallUGlassFactory: NSObject, FlutterPlatformViewFactory {
  private let assetKey: String

  init(assetKey: String) { self.assetKey = assetKey }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?)
    -> FlutterPlatformView
  {
    BnbuSmallUGlassPlatformView(frame: frame, assetKey: assetKey, arguments: args)
  }
}

final class BnbuSmallUGlassPlatformView: NSObject, FlutterPlatformView {
  private let logo: BnbuSmallUGlassView
  init(frame: CGRect, assetKey: String, arguments: Any?) {
    logo = BnbuSmallUGlassView(frame: frame, assetKey: assetKey, arguments: arguments)
    super.init()
  }
  func view() -> UIView { logo }
}

final class BnbuSmallUGlassView: UIView {
  private let material = UIVisualEffectView()
  private let silhouette: UIImage?
  private let dark: Bool
  private let logoExtent: CGFloat
  private let shade = CALayer()
  private let fill = CAGradientLayer()
  private let upperEdge = CALayer()
  private let lowerEdge = CALayer()
  private var maskedSize = CGSize.zero

  init(frame: CGRect, assetKey: String, arguments: Any?) {
    let values = arguments as? [String: Any]
    dark = values?["dark"] as? Bool ?? false
    logoExtent = CGFloat((values?["logoExtent"] as? NSNumber)?.doubleValue ?? 44)
    silhouette = UIImage(named: assetKey)?.withRenderingMode(.alwaysTemplate)
    super.init(frame: frame)
    isOpaque = false
    isUserInteractionEnabled = false // Flutter owns tap, drag and semantics.
    layer.addSublayer(shade)
    addSubview(material)
    layer.addSublayer(fill)
    layer.addSublayer(upperEdge)
    layer.addSublayer(lowerEdge)
    NotificationCenter.default.addObserver(self, selector: #selector(refreshMaterial),
      name: UIAccessibility.reduceTransparencyStatusDidChangeNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(refreshMaterial),
      name: UIAccessibility.darkerSystemColorsStatusDidChangeNotification, object: nil)
    refreshMaterial()
  }
  required init?(coder: NSCoder) { nil }
  deinit { NotificationCenter.default.removeObserver(self) }

  override func layoutSubviews() {
    super.layoutSubviews()
    material.frame = bounds
    for layer in [shade, fill, upperEdge, lowerEdge] { layer.frame = bounds }
    guard bounds.size != maskedSize, bounds.width > 0, bounds.height > 0 else { return }
    maskedSize = bounds.size
    let fullMask = maskImage()
    // UIVisualEffectView's view mask keeps holes fully transparent; a black
    // ColorFiltered glyph or a filled circle would hide the sampled content.
    let materialMask = UIImageView(image: fullMask)
    materialMask.frame = bounds
    material.mask = materialMask
    // Also clip the platform-view container: UIGlassEffect's composited lens
    // may extend outside its effect view on newer iOS versions.
    let silhouetteMask = UIImageView(image: fullMask)
    silhouetteMask.frame = bounds
    mask = silhouetteMask
    for layer in [shade, fill] { layer.mask = alphaLayer(fullMask) }
    upperEdge.mask = alphaLayer(maskImage(subtracting: CGPoint(x: 0.65, y: 0.85)))
    lowerEdge.mask = alphaLayer(maskImage(subtracting: CGPoint(x: -0.65, y: -0.85)))
  }

  private func alphaLayer(_ image: UIImage) -> CALayer {
    let mask = CALayer()
    mask.frame = bounds
    mask.contents = image.cgImage
    mask.contentsScale = image.scale
    return mask
  }

  private func maskImage(subtracting offset: CGPoint? = nil) -> UIImage {
    let side = min(logoExtent, bounds.width, bounds.height)
    let rect = CGRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2,
      width: side, height: side)
    return UIGraphicsImageRenderer(size: bounds.size).image { renderer in
      UIColor.white.setFill()
      silhouette?.draw(in: rect)
      if let offset {
        renderer.cgContext.setBlendMode(.destinationOut)
        silhouette?.draw(in: rect.offsetBy(dx: offset.x, dy: offset.y))
      }
    }
  }

  @objc private func refreshMaterial() {
    let opaque = UIAccessibility.isReduceTransparencyEnabled ||
      UIAccessibility.isDarkerSystemColorsEnabled
    backgroundColor = .clear
    shade.backgroundColor = UIColor.black.withAlphaComponent(opaque ? 0 : 0.06).cgColor
    shade.transform = CATransform3DMakeTranslation(0, 1.5, 0)
    if !opaque, #available(iOS 26.0, *) {
      let effect = UIGlassEffect(style: .clear)
      effect.tintColor = nil
      effect.isInteractive = false // Pointer handling stays on the draggable Flutter control.
      material.effect = effect
    } else if !opaque, #available(iOS 13.0, *) {
      material.effect = UIBlurEffect(style: .systemUltraThinMaterial)
    } else {
      material.effect = nil
    }
    let solid = dark ? UIColor.white : UIColor.black
    fill.startPoint = CGPoint(x: 0, y: 0)
    fill.endPoint = CGPoint(x: 1, y: 1)
    fill.locations = [0, 0.45, 1]
    fill.colors = opaque ? [solid.cgColor, solid.cgColor, solid.cgColor] : [
      UIColor.white.withAlphaComponent(0.60).cgColor,
      UIColor.white.withAlphaComponent(0.035).cgColor,
      UIColor.white.withAlphaComponent(dark ? 0.20 : 0.28).cgColor,
    ]
    upperEdge.backgroundColor = UIColor.white.withAlphaComponent(opaque ? 0 : 0.95).cgColor
    lowerEdge.backgroundColor = UIColor.black.withAlphaComponent(opaque ? 0 : (dark ? 0.32 : 0.42)).cgColor
  }
}

final class BnbuNativeTabBarFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    BnbuNativeTabBarPlatformView(
      frame: frame,
      viewId: viewId,
      arguments: args,
      messenger: messenger
    )
  }
}

final class BnbuNativeTabBarPlatformView: NSObject, FlutterPlatformView,
  UITabBarDelegate
{
  private let tabBar: UITabBar
  private let channel: FlutterMethodChannel

  init(
    frame: CGRect,
    viewId: Int64,
    arguments: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    let values = arguments as? [String: Any] ?? [:]
    let labels = values["labels"] as? [String] ?? []
    let codePoints = (values["iconCodePoints"] as? [Any] ?? []).compactMap {
      ($0 as? NSNumber)?.uint32Value
    }
    let selectedIndex = (values["selectedIndex"] as? NSNumber)?.intValue ?? 0
    let tintValue = (values["tintColor"] as? NSNumber)?.uint32Value ?? 0xFF0068B5

    self.tabBar = UITabBar(frame: frame)
    self.channel = FlutterMethodChannel(
      name: "ispace/native_tab_bar/\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    tabBar.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    tabBar.itemPositioning = .fill
    tabBar.tintColor = UIColor(
      red: CGFloat((tintValue >> 16) & 0xFF) / 255,
      green: CGFloat((tintValue >> 8) & 0xFF) / 255,
      blue: CGFloat(tintValue & 0xFF) / 255,
      alpha: CGFloat((tintValue >> 24) & 0xFF) / 255
    )
    if #available(iOS 13.0, *) {
      tabBar.unselectedItemTintColor = .label
    }

    let fallbackSymbols = ["house", "envelope", "graduationcap", "calendar", "person"]
    tabBar.items = labels.enumerated().map { index, label in
      let codePoint = index < codePoints.count ? codePoints[index] : 0
      let image = Self.lucideImage(codePoint: codePoint, weight: .regular)
        ?? Self.systemImage(named: fallbackSymbols[index % fallbackSymbols.count])
      let selectedImage = Self.lucideImage(codePoint: codePoint, weight: .selected)
        ?? image
      return UITabBarItem(
        title: label,
        image: image,
        selectedImage: selectedImage
      )
    }
    tabBar.delegate = self
    select(index: selectedIndex)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "setSelectedIndex":
        guard let index = (call.arguments as? NSNumber)?.intValue else {
          result(
            FlutterError(
              code: "bad_index",
              message: "Missing native tab index",
              details: nil
            )
          )
          return
        }
        self.select(index: index)
        result(true)
      case "setLabels":
        guard let labels = call.arguments as? [String],
              let items = self.tabBar.items,
              labels.count == items.count else {
          result(
            FlutterError(
              code: "bad_labels",
              message: "Native tab labels do not match the tab count",
              details: nil
            )
          )
          return
        }
        for (item, label) in zip(items, labels) {
          item.title = label
        }
        self.tabBar.setNeedsLayout()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  func view() -> UIView {
    tabBar
  }

  func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
    guard let index = tabBar.items?.firstIndex(of: item) else { return }
    channel.invokeMethod("selectedIndexChanged", arguments: index)
  }

  private func select(index: Int) {
    guard let items = tabBar.items, items.indices.contains(index) else { return }
    tabBar.selectedItem = items[index]
  }

  private enum LucideWeight {
    case regular
    case selected

    var assetPath: String {
      switch self {
      case .regular:
        "packages/lucide_icons_flutter/assets/build_font/LucideVariable-w300.ttf"
      case .selected:
        "packages/lucide_icons_flutter/assets/build_font/LucideVariable-w400.ttf"
      }
    }
  }

  private static var fontNames: [String: String] = [:]

  private static func lucideImage(codePoint: UInt32, weight: LucideWeight) -> UIImage? {
    guard
      codePoint > 0,
      let scalar = UnicodeScalar(codePoint),
      let font = lucideFont(weight: weight, size: 25)
    else {
      return nil
    }

    let value = String(Character(scalar)) as NSString
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: UIColor.white,
    ]
    let bounds = value.boundingRect(
      with: CGSize(width: 40, height: 40),
      options: [.usesLineFragmentOrigin, .usesFontLeading],
      attributes: attributes,
      context: nil
    )
    let size = CGSize(width: 30, height: 30)
    let format = UIGraphicsImageRendererFormat()
    format.opaque = false
    let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
      value.draw(
        at: CGPoint(
          x: (size.width - bounds.width) / 2 - bounds.minX,
          y: (size.height - bounds.height) / 2 - bounds.minY
        ),
        withAttributes: attributes
      )
    }
    return image.withRenderingMode(.alwaysTemplate)
  }

  private static func lucideFont(weight: LucideWeight, size: CGFloat) -> UIFont? {
    if let name = fontNames[weight.assetPath] {
      return UIFont(name: name, size: size)
    }
    guard
      let frameworksUrl = Bundle.main.privateFrameworksURL,
      let fontUrl = URL(
        string: "App.framework/flutter_assets/\(weight.assetPath)",
        relativeTo: frameworksUrl
      )
    else {
      return nil
    }
    CTFontManagerRegisterFontsForURL(fontUrl as CFURL, .process, nil)
    guard
      let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontUrl as CFURL)
        as? [CTFontDescriptor],
      let descriptor = descriptors.first,
      let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute)
        as? String
    else {
      return nil
    }
    fontNames[weight.assetPath] = name
    return UIFont(name: name, size: size)
  }

  private static func systemImage(named name: String) -> UIImage? {
    if #available(iOS 13.0, *) {
      return UIImage(systemName: name)?.withRenderingMode(.alwaysTemplate)
    }
    return nil
  }
}

private final class SameOriginCookieRedirectDelegate: NSObject, URLSessionTaskDelegate {
  private var cookieValues: [String: String]
  private let cookieOrigin: URL?
  private let initialScheme: String?

  init(cookieHeader: String, cookieOrigin: URL?, initialUrl: URL) {
    var values: [String: String] = [:]
    for part in cookieHeader.split(separator: ";", omittingEmptySubsequences: true) {
      let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      if pair.count == 2 {
        let name = pair[0].trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
          values[name] = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
        }
      }
    }
    self.cookieValues = values
    self.cookieOrigin = cookieOrigin
    self.initialScheme = initialUrl.scheme?.lowercased()
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    guard let target = request.url, isHttpUrl(target) else {
      completionHandler(nil)
      return
    }
    if initialScheme == "https", target.scheme?.lowercased() != "https" {
      completionHandler(nil)
      return
    }

    if let responseUrl = response.url,
      let cookieOrigin,
      urlsHaveSameOrigin(responseUrl, cookieOrigin)
    {
      var headerFields: [String: String] = [:]
      for (rawName, rawValue) in response.allHeaderFields {
        if let name = rawName as? String, let value = rawValue as? String {
          headerFields[name] = value
        }
      }
      for cookie in HTTPCookie.cookies(
        withResponseHeaderFields: headerFields,
        for: responseUrl
      ) {
        if cookie.expiresDate.map({ $0 <= Date() }) == true {
          cookieValues.removeValue(forKey: cookie.name)
        } else {
          cookieValues[cookie.name] = cookie.value
        }
      }
    }

    var redirected = request
    redirected.setValue(nil, forHTTPHeaderField: "Cookie")
    if !cookieValues.isEmpty,
      let cookieOrigin,
      urlsHaveSameOrigin(target, cookieOrigin)
    {
      let header = cookieValues
        .sorted { $0.key < $1.key }
        .map { "\($0.key)=\($0.value)" }
        .joined(separator: "; ")
      redirected.setValue(header, forHTTPHeaderField: "Cookie")
    }
    completionHandler(redirected)
  }

  private func isHttpUrl(_ url: URL) -> Bool {
    let scheme = url.scheme?.lowercased()
    return (scheme == "http" || scheme == "https") && url.host?.isEmpty == false
  }

  private func urlsHaveSameOrigin(_ first: URL, _ second: URL) -> Bool {
    guard isHttpUrl(first), isHttpUrl(second) else {
      return false
    }
    return first.scheme?.caseInsensitiveCompare(second.scheme ?? "") == .orderedSame
      && first.host?.caseInsensitiveCompare(second.host ?? "") == .orderedSame
      && effectivePort(first) == effectivePort(second)
  }

  private func effectivePort(_ url: URL) -> Int {
    if let port = url.port {
      return port
    }
    switch url.scheme?.lowercased() {
    case "http":
      return 80
    case "https":
      return 443
    default:
      return -1
    }
  }
}

private final class WeakNativeWebSession {
  weak var value: IspaceNativeWebView?

  init(_ value: IspaceNativeWebView) {
    self.value = value
  }
}

private enum NativeWebSessionRegistry {
  private static var sessions: [WeakNativeWebSession] = []

  static func register(_ session: IspaceNativeWebView) {
    sessions.removeAll { $0.value == nil }
    sessions.append(WeakNativeWebSession(session))
  }

  static func unregister(_ session: IspaceNativeWebView) {
    sessions.removeAll { entry in
      guard let value = entry.value else { return true }
      return value === session
    }
  }

  static func clearAll(completion: @escaping () -> Void) {
    let activeSessions = sessions.compactMap(\.value)
    sessions.removeAll()
    guard !activeSessions.isEmpty else {
      completion()
      return
    }
    let group = DispatchGroup()
    for session in activeSessions {
      group.enter()
      session.clearSession {
        group.leave()
      }
    }
    group.notify(queue: .main, execute: completion)
  }
}

private struct WebOrigin: Hashable {
  let scheme: String
  let host: String
  let port: Int

  init?(_ url: URL) {
    guard let scheme = url.scheme?.lowercased(),
      scheme == "https" || scheme == "http",
      let host = url.host?.lowercased(),
      !host.isEmpty,
      url.user == nil,
      url.password == nil
    else {
      return nil
    }
    self.scheme = scheme
    self.host = host
    self.port = url.port ?? (scheme == "https" ? 443 : 80)
  }
}

private final class WebUrlPolicy {
  private let allowedOrigins: Set<WebOrigin>
  private let allowedDomains: Set<String>
  private let resourceOnlyDomains: Set<String>
  private let allowExternalHttpsNavigation: Bool

  init(params: [String: Any]) {
    self.allowExternalHttpsNavigation = params["allowExternalHttpsNavigation"] as? Bool == true
    let rawOrigins = (params["allowedOrigins"] as? [Any])?.compactMap {
      $0 as? String
    } ?? []
    self.allowedOrigins = Set(
      rawOrigins.compactMap { value in
        URL(string: value).flatMap(WebOrigin.init)
      }
    )
    let rawResourceDomains = (params["resourceOnlyDomains"] as? [Any])?.compactMap {
      $0 as? String
    } ?? []
    self.resourceOnlyDomains = Set(
      rawResourceDomains.compactMap { value in
        let normalized = value
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .lowercased()
          .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalized.isEmpty ? nil : normalized
      }
    )
    let rawDomains = (params["allowedDomains"] as? [Any])?.compactMap {
      $0 as? String
    } ?? []
    self.allowedDomains = Set(
      rawDomains.compactMap { value in
        let normalized = value
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .lowercased()
          .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalized.isEmpty ? nil : normalized
      }
    )
  }

  func allows(_ url: URL) -> Bool {
    guard let origin = WebOrigin(url) else {
      return false
    }
    if allowedOrigins.contains(origin) {
      return true
    }
    if allowExternalHttpsNavigation {
      return true
    }
    guard origin.scheme == "https", origin.port == 443 else {
      return false
    }
    return allowedDomains.contains { domain in
      origin.host == domain || origin.host.hasSuffix(".\(domain)")
    }
  }

  func allowsResource(_ url: URL) -> Bool {
    switch url.scheme?.lowercased() {
    case "data", "blob", "about":
      return true
    default:
      if allows(url) {
        return true
      }
      guard let origin = WebOrigin(url), origin.port == 443 else {
        return false
      }
      return resourceOnlyDomains.contains { domain in
        origin.host == domain || origin.host.hasSuffix(".\(domain)")
      }
    }
  }

  func installContentRules(
    on userContentController: WKUserContentController,
    completion: @escaping (Bool) -> Void
  ) {
    let patterns = allowedPatterns()
    guard !patterns.isEmpty else {
      completion(false)
      return
    }
    var rules: [[String: Any]] = [
      [
        "trigger": [
          "url-filter": "^https?://",
          "url-filter-is-case-sensitive": false,
        ],
        "action": ["type": "block"],
      ]
    ]
    for pattern in patterns {
      rules.append([
        "trigger": [
          "url-filter": pattern,
          "url-filter-is-case-sensitive": false,
        ],
        "action": ["type": "ignore-previous-rules"],
      ])
    }
    guard JSONSerialization.isValidJSONObject(rules),
      let data = try? JSONSerialization.data(withJSONObject: rules),
      let encodedRules = String(data: data, encoding: .utf8)
    else {
      completion(false)
      return
    }
    let signature = UInt(bitPattern: patterns.joined(separator: "|").hashValue)
    WKContentRuleListStore.default().compileContentRuleList(
      forIdentifier: "handsbnbu-web-policy-\(signature)",
      encodedContentRuleList: encodedRules
    ) { ruleList, error in
      DispatchQueue.main.async {
        guard error == nil, let ruleList else {
          completion(false)
          return
        }
        userContentController.add(ruleList)
        completion(true)
      }
    }
  }

  private func allowedPatterns() -> [String] {
    var patterns = allowedOrigins.flatMap { origin -> [String] in
      let host = NSRegularExpression.escapedPattern(for: origin.host)
      if origin.port == 443 {
        return [
          "^https://\(host)/",
          "^https://\(host):443/",
        ]
      }
      return ["^https://\(host):\(origin.port)/"]
    }
    patterns.append(
      contentsOf: allowedDomains.flatMap { domain -> [String] in
        let escaped = NSRegularExpression.escapedPattern(for: domain)
        return [
          "^https://([A-Za-z0-9-]+\\.)*\(escaped)/",
          "^https://([A-Za-z0-9-]+\\.)*\(escaped):443/",
        ]
      }
    )
    patterns.append(
      contentsOf: resourceOnlyDomains.flatMap { domain -> [String] in
        let escaped = NSRegularExpression.escapedPattern(for: domain)
        return [
          "^https://([A-Za-z0-9-]+\\.)*\(escaped)/",
          "^https://([A-Za-z0-9-]+\\.)*\(escaped):443/",
        ]
      }
    )
    return patterns.sorted()
  }
}

final class IspaceNativeWebViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    IspaceNativeWebView(
      frame: frame,
      viewId: viewId,
      args: args,
      messenger: messenger
    )
  }
}

private final class LeaveSubmissionMessageHandler: NSObject, WKScriptMessageHandler {
  weak var target: WKScriptMessageHandler?
  init(target: WKScriptMessageHandler) {
    self.target = target
    super.init()
  }
  func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    target?.userContentController(controller, didReceive: message)
  }
}

final class IspaceNativeWebView: NSObject, FlutterPlatformView, WKNavigationDelegate,
  WKUIDelegate, UIScrollViewDelegate, WKScriptMessageHandler
{
  private let webView: WKWebView
  private let container: UIView
  private let isMailContent: Bool
  private let isHtmlContent: Bool
  private let viewChannel: FlutterMethodChannel
  private let urlPolicy: WebUrlPolicy?
  private let sessionBaseUrl: URL?
  private let participatesInSessionCleanup: Bool
  private let observeLoginCodes: Bool
  private let loginCodeObserverOrigin: WebOrigin?
  private let observeLeaveSubmission: Bool
  private let upgradeInsecureResourceHosts: Set<String>
  private var lastMailCollapsedState = false
  private var allowedInitialMailLoad = false
  private var loadFailure: String?
  private var sessionInvalidated = false
  private var pendingCookieWrites = 0
  private var cleanupStarted = false
  private var cleanupDataRemovalStarted = false
  private var cleanupFinished = false
  private var cleanupCallbacks: [() -> Void] = []
  private var lastLoginCodeSource = ""

  init(
    frame: CGRect,
    viewId: Int64,
    args: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    let params = args as? [String: Any] ?? [:]
    let isMailContent = params["isMailContent"] as? Bool == true
    let isHtmlContent = params["contentType"] as? String == "html" && !isMailContent
    let useEphemeralSession = params["useEphemeralSession"] as? Bool == true
    let participatesInSessionCleanup =
      params["participatesInSessionCleanup"] as? Bool != false
    let observeLoginCodes = !isHtmlContent && params["observeLoginCodes"] as? Bool == true
    let loginCodeObserverOrigin = (params["loginCodeObserverOrigin"] as? String)
      .flatMap(URL.init(string:))
      .flatMap(WebOrigin.init)
    let observeLeaveSubmission =
      params["observeLeaveSubmission"] as? Bool == true
      && !isMailContent
      && !isHtmlContent
      && IspaceNativeWebView.isLeaveSubmissionWorkflowUrl(
        URL(string: (params["initialUrl"] as? String) ?? "")
      )
    let upgradeInsecureResourceHosts = Set(
      ((params["upgradeInsecureResourceHosts"] as? [Any]) ?? []).compactMap {
        value -> String? in
        guard let raw = value as? String else { return nil }
        let normalized = raw
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .lowercased()
          .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalized.isEmpty ? nil : normalized
      }
    )
    let configuration = WKWebViewConfiguration()
    if isMailContent || useEphemeralSession {
      configuration.websiteDataStore = .nonPersistent()
    }
    if isMailContent {
      configuration.preferences.javaScriptEnabled = false
      if #available(iOS 14.0, *) {
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
      }
    } else if isHtmlContent {
      if #available(iOS 14.0, *) {
        // Disable page scripts while retaining app-owned read-only inspection.
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
      } else {
        configuration.preferences.javaScriptEnabled = false
      }
    }

    self.isMailContent = isMailContent
    self.isHtmlContent = isHtmlContent
    self.viewChannel = FlutterMethodChannel(
      name: "ispace/native_webview/\(viewId)",
      binaryMessenger: messenger
    )
    self.urlPolicy = isMailContent ? nil : WebUrlPolicy(params: params)
    self.sessionBaseUrl = URL(string: (params["baseUrl"] as? String) ?? "")
    self.participatesInSessionCleanup = participatesInSessionCleanup
    self.observeLoginCodes = observeLoginCodes
    self.loginCodeObserverOrigin = loginCodeObserverOrigin
    self.observeLeaveSubmission = observeLeaveSubmission
    self.upgradeInsecureResourceHosts = upgradeInsecureResourceHosts
    self.webView = WKWebView(frame: frame, configuration: configuration)
    self.container = UIView(frame: frame)
    super.init()
    if !isMailContent && participatesInSessionCleanup {
      NativeWebSessionRegistry.register(self)
    }
    if observeLoginCodes, loginCodeObserverOrigin != nil {
      self.webView.configuration.userContentController.add(
        self,
        name: "handsBnbuLoginCodeBridge"
      )
    }
    if observeLeaveSubmission {
      self.webView.configuration.userContentController.add(
        LeaveSubmissionMessageHandler(target: self),
        name: "bnbuLeaveSubmission"
      )
    }
    self.viewChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(false)
        return
      }
      switch call.method {
      case "getLoadFailure":
        result(self.loadFailure)
      case "reload":
        if self.isHtmlContent {
          self.loadCookiesAndPage(params)
        } else {
          self.webView.reload()
        }
        result(true)
      case "goBack":
        if self.webView.canGoBack {
          self.webView.goBack()
          result(true)
        } else {
          result(false)
        }
      case "clearSiteData":
        self.clearCurrentSiteData {
          result(true)
        }
      case "extractVisibleText":
        self.webView.evaluateJavaScript(
          "(document.body && document.body.innerText) || ''"
        ) { value, _ in
          result(value as? String ?? "")
        }
      case "evaluateJavascript":
        guard let source = call.arguments as? String else {
          result(
            FlutterError(
              code: "INVALID_ARGUMENT",
              message: "JavaScript source is required",
              details: nil
            )
          )
          return
        }
        self.webView.evaluateJavaScript(source) { value, error in
          if let error {
            result(
              FlutterError(
                code: "JAVASCRIPT_ERROR",
                message: error.localizedDescription,
                details: nil
              )
            )
          } else {
            result(value)
          }
        }
      case "saveLoginCodeAndOpenWechat":
        self.saveLoginCodeAndOpenWechat(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.webView.navigationDelegate = self
    self.webView.uiDelegate = self
    if isMailContent {
      self.webView.scrollView.delegate = self
      let dark = params["mailDarkMode"] as? Bool == true
      let background = dark
        ? UIColor(red: 24.0 / 255, green: 25.0 / 255, blue: 27.0 / 255, alpha: 1)
        : UIColor(red: 247.0 / 255, green: 248.0 / 255, blue: 250.0 / 255, alpha: 1)
      self.webView.isOpaque = false
      self.webView.backgroundColor = background
      self.webView.scrollView.backgroundColor = background
      self.container.backgroundColor = background
      if #available(iOS 15.0, *) {
        self.webView.underPageBackgroundColor = background
      }
    }
    self.webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    self.webView.allowsBackForwardNavigationGestures = !isMailContent
    self.webView.scrollView.alwaysBounceVertical = true
    self.container.addSubview(self.webView)
    self.loadFromParams(params)
  }

  deinit {
    sessionInvalidated = true
    viewChannel.setMethodCallHandler(nil)
    if observeLoginCodes {
      webView.configuration.userContentController.removeScriptMessageHandler(
        forName: "handsBnbuLoginCodeBridge"
      )
    }
    if observeLeaveSubmission {
      webView.configuration.userContentController.removeScriptMessageHandler(
        forName: "bnbuLeaveSubmission"
      )
    }
    if participatesInSessionCleanup {
      NativeWebSessionRegistry.unregister(self)
    }
  }

  func view() -> UIView {
    container
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard isMailContent, !sessionInvalidated else { return }
    let collapsed = scrollView.contentOffset.y > 18
    guard collapsed != lastMailCollapsedState else { return }
    lastMailCollapsedState = collapsed
    viewChannel.invokeMethod(
      "mailScrollStateChanged",
      arguments: ["collapsed": collapsed]
    )
  }

  func clearSession(completion: @escaping () -> Void) {
    if cleanupFinished {
      completion()
      return
    }
    cleanupCallbacks.append(completion)
    sessionInvalidated = true
    NativeWebSessionRegistry.unregister(self)
    guard !cleanupStarted else { return }
    cleanupStarted = true
    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.uiDelegate = nil
    webView.isHidden = true
    continueCleanupIfReady()
  }

  private func completePendingCookieWrite() {
    if pendingCookieWrites > 0 {
      pendingCookieWrites -= 1
    }
    continueCleanupIfReady()
  }

  private func continueCleanupIfReady() {
    guard cleanupStarted, !cleanupFinished, !cleanupDataRemovalStarted,
      pendingCookieWrites == 0
    else {
      return
    }
    cleanupDataRemovalStarted = true
    webView.configuration.websiteDataStore.removeData(
      ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
      modifiedSince: .distantPast
    ) { [self] in
      DispatchQueue.main.async {
        self.finishCleanup()
      }
    }
  }

  private func finishCleanup() {
    guard !cleanupFinished else { return }
    cleanupFinished = true
    let callbacks = cleanupCallbacks
    cleanupCallbacks.removeAll()
    for callback in callbacks {
      callback()
    }
  }

  private func loadFromParams(_ params: [String: Any]) {
    guard !sessionInvalidated else { return }
    guard !isMailContent else {
      loadCookiesAndPage(params)
      return
    }
    guard let urlPolicy else {
      rejectLoad("invalid_content")
      return
    }
    urlPolicy.installContentRules(on: webView.configuration.userContentController) {
      [weak self] installed in
      guard let self, !self.sessionInvalidated else { return }
      if installed {
        self.loadCookiesAndPage(params)
      } else {
        self.rejectLoad("content_rules")
      }
    }
  }

  private func loadCookiesAndPage(_ params: [String: Any]) {
    guard !sessionInvalidated else { return }
    let initialUrl = (params["initialUrl"] as? String) ?? ""
    let htmlContent = (params["htmlContent"] as? String) ?? ""
    let baseUrlString = (params["baseUrl"] as? String) ?? ""
    let initial = URL(string: initialUrl)
    let baseUrl = URL(string: baseUrlString)
    if !isMailContent {
      let type = params["contentType"] as? String
      let validHtml = isHtmlContent && initialUrl.isEmpty
        && !htmlContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && baseUrl.flatMap(WebOrigin.init)?.scheme == "https"
        && baseUrl.map { self.urlPolicy?.allows($0) == true } == true
      guard (type == "url" && htmlContent.isEmpty) || (type == "html" && validHtml) else {
        rejectLoad("invalid_content")
        return
      }
    }
    let cookieStore = webView.configuration.websiteDataStore.httpCookieStore
    let rawCookies: [[String: Any]]
    if isMailContent {
      rawCookies = []
    } else {
      rawCookies = (params["cookies"] as? [Any])?.compactMap {
        $0 as? [String: Any]
      } ?? []
    }

    let group = DispatchGroup()
    for raw in rawCookies {
      guard
        let name = raw["name"] as? String,
        let value = raw["value"] as? String,
        isValidCookieName(name),
        !containsCookieControl(value)
      else {
        continue
      }
      let domain = (raw["domain"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      let path = (raw["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
      let hostOnly = (raw["hostOnly"] as? Bool) == true
      let secure = (raw["secure"] as? Bool) == true
      let httpOnly = (raw["httpOnly"] as? Bool) == true
      let sameSite = (raw["sameSite"] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let expiresAt = (raw["expiresAt"] as? NSNumber)?.doubleValue
      let cleanedDomain = domain?
        .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        .trimmingCharacters(in: .whitespacesAndNewlines)
      let cleanedPath = path?.isEmpty == false ? path! : "/"
      let fallbackUrl = baseUrl ?? initial
      let fallbackDomain = fallbackUrl?.host ?? ""
      if !cleanedPath.hasPrefix("/") || cleanedPath.contains(";")
        || containsCookieControl(cleanedPath)
      {
        continue
      }
      if sameSite?.lowercased() == "none" && !secure {
        continue
      }
      if let expiresAt, expiresAt <= Date().timeIntervalSince1970 * 1000 {
        continue
      }

      var properties: [HTTPCookiePropertyKey: Any] = [
        .name: name,
        .value: value,
        .path: cleanedPath,
      ]
      if hostOnly {
        guard
          let cleanedDomain,
          !cleanedDomain.isEmpty,
          let fallbackUrl,
          cleanedDomain.caseInsensitiveCompare(fallbackDomain) == .orderedSame
        else {
          continue
        }
        properties[.originURL] = fallbackUrl
      } else if
        let cleanedDomain,
        !cleanedDomain.isEmpty,
        cleanedDomain.caseInsensitiveCompare(fallbackDomain) == .orderedSame
      {
        properties[.domain] = cleanedDomain
      } else {
        continue
      }
      if secure {
        properties[.secure] = "TRUE"
      }
      if let expiresAt {
        properties[.expires] = Date(timeIntervalSince1970: expiresAt / 1000)
      }
      if httpOnly {
        properties[HTTPCookiePropertyKey(rawValue: "HttpOnly")] = "TRUE"
      }
      if let sameSite,
        ["lax", "strict", "none"].contains(sameSite.lowercased())
      {
        properties[HTTPCookiePropertyKey(rawValue: "SameSite")] = sameSite.capitalized
      }

      guard let cookie = HTTPCookie(properties: properties) else {
        continue
      }
      group.enter()
      pendingCookieWrites += 1
      cookieStore.setCookie(cookie) { [self] in
        DispatchQueue.main.async {
          self.completePendingCookieWrite()
          group.leave()
        }
      }
    }

    group.notify(queue: .main) { [weak self] in
      guard let self, !self.sessionInvalidated else { return }
      if self.isMailContent || self.isHtmlContent {
        self.webView.loadHTMLString(htmlContent, baseURL: baseUrl)
        return
      }
      guard let initial, self.urlPolicy?.allows(initial) == true else {
        self.rejectLoad("initial_url")
        return
      }
      self.webView.load(URLRequest(url: initial))
    }
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    guard !sessionInvalidated else {
      decisionHandler(.cancel)
      return
    }
    guard let url = navigationAction.request.url else {
      decisionHandler(.cancel)
      return
    }
    if isMailContent {
      // A tapped link leaves the isolated view via the system browser.
      if navigationAction.navigationType == .linkActivated {
        let scheme = url.scheme?.lowercased()
        if scheme == "http" || scheme == "https" {
          UIApplication.shared.open(url, options: [:])
        }
        decisionHandler(.cancel)
        return
      }
      let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
      if isMainFrame {
        // Allow only the first main-frame navigation — the initial
        // loadHTMLString paint. Any later main-frame navigation is a
        // content-driven redirect (e.g. a surviving meta refresh) and must not
        // move the mail view off the isolated document.
        if allowedInitialMailLoad {
          decisionHandler(.cancel)
          return
        }
        allowedInitialMailLoad = true
      }
      decisionHandler(.allow)
      return
    }
    let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
    if isHtmlContent && isMainFrame && navigationAction.navigationType == .linkActivated {
      if WebOrigin(url) != nil {
        viewChannel.invokeMethod("htmlLinkActivated", arguments: url.absoluteString)
      }
      decisionHandler(.cancel)
      return
    }
    if isMainFrame {
      let isLocalBlank = url.absoluteString == "about:blank"
      let isAllowed = isLocalBlank || urlPolicy?.allows(url) == true
      if !isAllowed {
        viewChannel.invokeMethod("navigationBlocked", arguments: url.absoluteString)
      }
      if !isAllowed, navigationAction.navigationType != .linkActivated {
        viewChannel.invokeMethod("authenticationRequired", arguments: nil)
      }
      decisionHandler(isAllowed ? .allow : .cancel)
    } else {
      decisionHandler(urlPolicy?.allowsResource(url) == true ? .allow : .cancel)
    }
  }

  func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
    guard !isMailContent, !sessionInvalidated else { return }
    viewChannel.invokeMethod("pageStarted", arguments: nil)
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard !isMailContent, !sessionInvalidated else { return }
    emitSessionCookies()
    if !isHtmlContent { installPageEnhancementsIfAllowed() }
    viewChannel.invokeMethod("pageFinished", arguments: nil)
  }

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    switch message.name {
    case "handsBnbuLoginCodeBridge":
      guard let source = message.body as? String else { return }
      handleLoginCodeSource(source)
    case "bnbuLeaveSubmission":
      handleLeaveSubmission(message)
    default:
      return
    }
  }

  private func handleLeaveSubmission(_ message: WKScriptMessage) {
    guard observeLeaveSubmission,
      !sessionInvalidated,
      let messageWebView = message.webView,
      messageWebView === webView,
      message.frameInfo.isMainFrame,
      Self.isLeaveSubmissionPortalFrame(message.frameInfo),
      let payload = Self.validatedLeaveSubmissionPayload(message.body)
    else {
      return
    }
    // The SPA fragment can advance after postMessage. Provenance therefore
    // comes only from this message's frame metadata, not webView.url.
    viewChannel.invokeMethod("leaveSubmission", arguments: payload)
  }

  private static func isLeaveSubmissionPortalFrame(_ frame: WKFrameInfo) -> Bool {
    let securityOrigin = frame.securityOrigin
    guard securityOrigin.protocol.lowercased() == "https",
      securityOrigin.host.lowercased() == "portal.bnbu.edu.cn",
      // WebKit represents an omitted/default port as zero. The request URL
      // below must independently resolve to the HTTPS default port as well.
      securityOrigin.port == 0 || securityOrigin.port == 443,
      isLeaveSubmissionPortalFrameUrl(frame.request.url)
    else {
      return false
    }
    return true
  }

  private static func isLeaveSubmissionPortalFrameUrl(_ url: URL?) -> Bool {
    guard let url,
      let origin = WebOrigin(url),
      origin.scheme == "https",
      origin.host == "portal.bnbu.edu.cn",
      origin.port == 443,
      url.path == "/spa/workflow/static4form/index.html"
    else {
      return false
    }
    return true
  }

  private static func isLeaveSubmissionWorkflowUrl(_ url: URL?) -> Bool {
    guard let url,
      isLeaveSubmissionPortalFrameUrl(url),
      let fragment = url.fragment,
      let queryStart = fragment.firstIndex(of: "?"),
      String(fragment[..<queryStart]) == "/main/workflow/req"
    else {
      return false
    }
    var query = URLComponents()
    query.query = String(fragment[fragment.index(after: queryStart)...])
    let items = query.queryItems ?? []
    let workflowIds = items
      .filter { $0.name == "workflowid" }
      .compactMap(\.value)
    let createFlags = items
      .filter { $0.name == "iscreate" }
      .compactMap(\.value)
    return workflowIds == ["57"] && createFlags == ["1"]
  }

  private static func validatedLeaveSubmissionPayload(_ body: Any) -> [String: String]? {
    guard let raw = body as? [String: Any], raw.count == 2 else {
      return nil
    }
    let expectedKeys: Set<String> = ["nonce", "status"]
    guard Set(raw.keys) == expectedKeys,
      let nonce = raw["nonce"] as? String,
      let status = raw["status"] as? String,
      nonce.count == 48,
      nonce.range(of: "^[0-9a-f]{48}$", options: .regularExpression) != nil,
      ["submission_succeeded", "submission_failed", "submission_pending"].contains(status)
    else {
      return nil
    }
    return ["nonce": nonce, "status": status]
  }

  private func isPageEnhancementAllowed() -> Bool {
    guard let expected = loginCodeObserverOrigin,
      let currentUrl = webView.url,
      let current = WebOrigin(currentUrl)
    else {
      return false
    }
    return current == expected
  }

  private func installPageEnhancementsIfAllowed() {
    guard (observeLoginCodes || !upgradeInsecureResourceHosts.isEmpty),
      isPageEnhancementAllowed()
    else {
      return
    }
    let hostData = try? JSONSerialization.data(
      withJSONObject: upgradeInsecureResourceHosts.sorted()
    )
    let hostJson = hostData.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    let observeLoginCode = observeLoginCodes ? "true" : "false"
    let script = #"""
      (() => {
        if (window.__handsBnbuDuoduoEnhancementsInstalled) {
          window.__handsBnbuUpgradeInsecureResources?.();
          window.__handsBnbuScanLoginCode?.();
          return;
        }
        window.__handsBnbuDuoduoEnhancementsInstalled = true;
        const upgradeHosts = new Set(\#(hostJson));
        const normalizeUrl = (value) => {
          if (!value || typeof value !== 'string') return value;
          try {
            const url = new URL(value, location.href);
            if (url.protocol === 'http:' && upgradeHosts.has(url.hostname.toLowerCase())) {
              url.protocol = 'https:';
              url.port = '';
              return url.href;
            }
          } catch (_) {
            return value;
          }
          return value;
        };
        const upgradeSrcset = (value) => (value || '').split(',').map((entry) => {
          const trimmed = entry.trim();
          if (!trimmed) return trimmed;
          const split = trimmed.search(/\s/);
          if (split < 0) return normalizeUrl(trimmed);
          return normalizeUrl(trimmed.slice(0, split)) + trimmed.slice(split);
        }).join(', ');
        const upgradeInlineStyle = (value) => {
          if (!value || typeof value !== 'string') return value;
          return value.replace(/url\((['"]?)(http:\/\/[^)'"\s]+)\1\)/gi, (all, quote, rawUrl) => {
            const upgraded = normalizeUrl(rawUrl);
            return upgraded === rawUrl ? all : 'url(' + quote + upgraded + quote + ')';
          });
        };
        const upgradeElement = (element) => {
          if (!(element instanceof Element)) return;
          for (const attribute of ['src', 'poster']) {
            const current = element.getAttribute(attribute);
            const upgraded = normalizeUrl(current);
            if (current && upgraded !== current) element.setAttribute(attribute, upgraded);
          }
          const srcset = element.getAttribute('srcset');
          if (srcset) {
            const upgraded = upgradeSrcset(srcset);
            if (upgraded !== srcset) element.setAttribute('srcset', upgraded);
          }
          const style = element.getAttribute('style');
          if (style) {
            const upgraded = upgradeInlineStyle(style);
            if (upgraded !== style) element.setAttribute('style', upgraded);
          }
        };
        const upgradeAll = () => {
          document.querySelectorAll('[src], [srcset], [poster], [style]').forEach(upgradeElement);
        };
        window.__handsBnbuUpgradeInsecureResources = upgradeAll;
        const emitLoginCode = async (image) => {
          let source = image.currentSrc || image.src || '';
          if (!source) return;
          if (source.startsWith('blob:')) {
            try {
              const blob = await fetch(source).then((response) => response.blob());
              source = await new Promise((resolve, reject) => {
                const reader = new FileReader();
                reader.onload = () => resolve(String(reader.result || ''));
                reader.onerror = reject;
                reader.readAsDataURL(blob);
              });
            } catch (_) {
              return;
            }
          }
          source = normalizeUrl(source);
          if (source) {
            window.webkit.messageHandlers.handsBnbuLoginCodeBridge.postMessage(source);
          }
        };
        const findLoginCodeContainer = () => {
          const marker = Array.from(document.querySelectorAll('div, span, p, h1, h2, h3'))
            .find((element) => (element.innerText || element.textContent || '').trim() === '微信扫码授权登录');
          let container = marker;
          for (let depth = 0; container && depth < 8; depth += 1, container = container.parentElement) {
            const text = (container.innerText || '').replace(/\s+/g, ' ');
            const hasCodeImage = Array.from(container.querySelectorAll('img')).some((image) => {
              const rect = image.getBoundingClientRect();
              return rect.width >= 120 && rect.height >= 120;
            });
            if (hasCodeImage && text.includes('扫描上方小程序码')) return container;
          }
          return null;
        };
        const scanLoginCode = () => {
          if (!\#(observeLoginCode)) return;
          try {
            const container = findLoginCodeContainer();
            const target = Array.from(container?.querySelectorAll('img') || []).find((image) => {
              const rect = image.getBoundingClientRect();
              return rect.width >= 120 && rect.height >= 120;
            });
            if (target) void emitLoginCode(target);
          } catch (_) {}
        };
        window.__handsBnbuScanLoginCode = scanLoginCode;
        new MutationObserver((records) => {
          for (const record of records) {
            if (record.target instanceof Element) upgradeElement(record.target);
            for (const node of record.addedNodes || []) {
              if (!(node instanceof Element)) continue;
              upgradeElement(node);
              node.querySelectorAll?.('[src], [srcset], [poster], [style]').forEach(upgradeElement);
            }
          }
          scanLoginCode();
        }).observe(document.documentElement, {
          subtree: true,
          childList: true,
          attributes: true,
          attributeFilter: ['src', 'srcset', 'poster', 'style', 'class']
        });
        upgradeAll();
        scanLoginCode();
      })();
      """#
    webView.evaluateJavaScript(script, completionHandler: nil)
  }

  private func handleLoginCodeSource(_ rawSource: String) {
    guard let source = normalizeLoginCodeSource(rawSource) else { return }
    guard !sessionInvalidated,
      observeLoginCodes,
      isPageEnhancementAllowed(),
      source != lastLoginCodeSource
    else {
      return
    }
    lastLoginCodeSource = source
    viewChannel.invokeMethod("loginCodeDetected", arguments: nil)
  }

  private func normalizeLoginCodeSource(_ raw: String) -> String? {
    let source = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !source.isEmpty, source.utf8.count <= 7_000_000 else { return nil }
    if source.lowercased().hasPrefix("data:image/") {
      return source
    }
    guard var components = URLComponents(string: source),
      components.user == nil,
      components.password == nil,
      let host = components.host?.lowercased()
    else {
      return nil
    }
    if components.scheme?.lowercased() == "http",
      upgradeInsecureResourceHosts.contains(host),
      components.port == nil || components.port == 80
    {
      components.scheme = "https"
      components.port = nil
    }
    guard let normalized = components.url,
      normalized.scheme?.lowercased() == "https",
      urlPolicy?.allowsResource(normalized) == true
    else {
      return nil
    }
    return normalized.absoluteString
  }

  private func loadLoginCodeImageData(
    _ source: String,
    completion: @escaping (Data?) -> Void
  ) {
    if source.lowercased().hasPrefix("data:image/") {
      guard let separator = source.firstIndex(of: ",") else {
        completion(nil)
        return
      }
      let metadata = source[..<separator].lowercased()
      guard metadata.contains(";base64") else {
        completion(nil)
        return
      }
      let encoded = String(source[source.index(after: separator)...])
      completion(Data(base64Encoded: encoded, options: [.ignoreUnknownCharacters]))
      return
    }
    guard let url = URL(string: source),
      url.scheme?.lowercased() == "https",
      url.user == nil,
      url.password == nil,
      urlPolicy?.allowsResource(url) == true
    else {
      completion(nil)
      return
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = 8
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 8
    configuration.timeoutIntervalForResource = 8
    URLSession(configuration: configuration).dataTask(with: request) {
      [weak self] data, response, _ in
      guard let self,
        let responseUrl = response?.url,
        self.urlPolicy?.allowsResource(responseUrl) == true,
        let data,
        data.count <= 2 * 1024 * 1024
      else {
        completion(nil)
        return
      }
      completion(data)
    }.resume()
  }

  private func saveLoginCodeAndOpenWechat(result: @escaping FlutterResult) {
    let source = lastLoginCodeSource
    guard !source.isEmpty, !sessionInvalidated else {
      result(["saved": false, "openedWechat": false])
      return
    }
    loadLoginCodeImageData(source) { [weak self] data in
      guard let self else {
        result(["saved": false, "openedWechat": false])
        return
      }
      guard let data else {
        DispatchQueue.main.async {
          self.openWechat { opened in
            result(["saved": false, "openedWechat": opened])
          }
        }
        return
      }
      self.saveLoginCodeToPhotos(data) { saved in
        DispatchQueue.main.async {
          self.openWechat { opened in
            result(["saved": saved, "openedWechat": opened])
          }
        }
      }
    }
  }

  private func saveLoginCodeToPhotos(
    _ data: Data,
    completion: @escaping (Bool) -> Void
  ) {
    let save = {
      PHPhotoLibrary.shared().performChanges {
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .photo, data: data, options: nil)
      } completionHandler: { success, _ in
        completion(success)
      }
    }
    if #available(iOS 14.0, *) {
      let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
      switch status {
      case .authorized, .limited:
        save()
      case .notDetermined:
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { newStatus in
          if newStatus == .authorized || newStatus == .limited {
            save()
          } else {
            completion(false)
          }
        }
      default:
        completion(false)
      }
      return
    }
    let status = PHPhotoLibrary.authorizationStatus()
    switch status {
    case .authorized:
      save()
    case .notDetermined:
      PHPhotoLibrary.requestAuthorization { newStatus in
        if newStatus == .authorized {
          save()
        } else {
          completion(false)
        }
      }
    default:
      completion(false)
    }
  }

  private func openWechat(completion: @escaping (Bool) -> Void) {
    guard let url = URL(string: "weixin://") else {
      completion(false)
      return
    }
    UIApplication.shared.open(url, options: [:], completionHandler: completion)
  }

  private func clearCurrentSiteData(completion: @escaping () -> Void) {
    guard let host = sessionBaseUrl?.host?.lowercased(), !host.isEmpty else {
      completion()
      return
    }
    let script = #"""
      (() => {
        try { localStorage.clear(); } catch (_) {}
        try { sessionStorage.clear(); } catch (_) {}
        try {
          if ('caches' in window) caches.keys().then(keys => keys.forEach(key => caches.delete(key)));
        } catch (_) {}
        return true;
      })();
      """#
    webView.evaluateJavaScript(script, completionHandler: nil)
    let store = webView.configuration.websiteDataStore
    let types = WKWebsiteDataStore.allWebsiteDataTypes()
    let group = DispatchGroup()
    group.enter()
    store.fetchDataRecords(ofTypes: types) { records in
      let matching = records.filter { record in
        let name = record.displayName.lowercased()
        return name == host || host.hasSuffix(".\(name)") || name.hasSuffix(".duoduo.link")
      }
      store.removeData(ofTypes: types, for: matching) {
        group.leave()
      }
    }
    group.enter()
    store.httpCookieStore.getAllCookies { cookies in
      let matching = cookies.filter { cookie in
        let domain = cookie.domain
          .trimmingCharacters(in: CharacterSet(charactersIn: "."))
          .lowercased()
        return domain == host || host.hasSuffix(".\(domain)") || domain.hasSuffix(".duoduo.link")
      }
      guard !matching.isEmpty else {
        group.leave()
        return
      }
      let cookieGroup = DispatchGroup()
      for cookie in matching {
        cookieGroup.enter()
        store.httpCookieStore.delete(cookie) {
          cookieGroup.leave()
        }
      }
      cookieGroup.notify(queue: .main) {
        group.leave()
      }
    }
    group.notify(queue: .main, execute: completion)
  }

  private func emitSessionCookies() {
    guard !sessionInvalidated,
      let baseUrl = sessionBaseUrl,
      baseUrl.scheme?.lowercased() == "https",
      let targetHost = baseUrl.host?.lowercased(),
      !targetHost.isEmpty
    else {
      return
    }
    webView.configuration.websiteDataStore.httpCookieStore.getAllCookies {
      [weak self] cookies in
      guard let self, !self.sessionInvalidated else { return }
      let now = Date()
      let result: [[String: Any]] = cookies.compactMap { cookie in
        let cookieDomain = cookie.domain
          .trimmingCharacters(in: CharacterSet(charactersIn: "."))
          .lowercased()
        let appliesToTarget = targetHost == cookieDomain
          || targetHost.hasSuffix(".\(cookieDomain)")
        guard appliesToTarget,
          cookie.isSecure,
          cookie.expiresDate.map({ $0 > now }) ?? true
        else {
          return nil
        }
        let path = cookie.path.isEmpty ? "/" : cookie.path
        guard path.hasPrefix("/"), !path.contains(";") else { return nil }
        var serialized: [String: Any] = [
          "name": cookie.name,
          "value": cookie.value,
          "domain": targetHost,
          "path": path,
          "hostOnly": true,
          "secure": true,
          "httpOnly": cookie.isHTTPOnly,
        ]
        if let sameSite = cookie.properties?[HTTPCookiePropertyKey(rawValue: "SameSite")]
          as? String
        {
          serialized["sameSite"] = sameSite.lowercased()
        }
        if let expiresDate = cookie.expiresDate {
          serialized["expiresAt"] = expiresDate.timeIntervalSince1970 * 1000
        }
        return serialized
      }
      guard !result.isEmpty else { return }
      DispatchQueue.main.async {
        guard !self.sessionInvalidated else { return }
        self.viewChannel.invokeMethod("sessionCookiesChanged", arguments: result)
      }
    }
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: Error
  ) {
    guard !isMailContent, !sessionInvalidated else { return }
    if (error as NSError).code == NSURLErrorCancelled { return }
    viewChannel.invokeMethod("pageError", arguments: nil)
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    guard !isMailContent, !sessionInvalidated else { return }
    if (error as NSError).code == NSURLErrorCancelled { return }
    viewChannel.invokeMethod("pageError", arguments: nil)
  }

  func webView(
    _ webView: WKWebView,
    createWebViewWith configuration: WKWebViewConfiguration,
    for navigationAction: WKNavigationAction,
    windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    guard !sessionInvalidated else { return nil }
    guard navigationAction.targetFrame == nil,
      let url = navigationAction.request.url
    else {
      return nil
    }
    if isMailContent {
      let scheme = url.scheme?.lowercased()
      if scheme == "http" || scheme == "https" {
        UIApplication.shared.open(url, options: [:])
      }
      return nil
    }
    if urlPolicy?.allows(url) == true {
      webView.load(navigationAction.request)
    } else {
      // target=_blank/window.open must reach the same Dart destination router
      // as a blocked main-frame link. Never import the source page's cookies.
      viewChannel.invokeMethod("navigationBlocked", arguments: url.absoluteString)
    }
    return nil
  }

  private func isValidCookieName(_ value: String) -> Bool {
    guard !value.isEmpty else { return false }
    let separators = CharacterSet(charactersIn: "()<>@,;:\\\"/[]?={} \t")
    return value.unicodeScalars.allSatisfy { scalar in
      scalar.value > 0x20 && scalar.value < 0x7F && !separators.contains(scalar)
    }
  }

  private func containsCookieControl(_ value: String) -> Bool {
    value.contains("\r") || value.contains("\n")
  }

  private func rejectLoad(_ reason: String) {
    guard !sessionInvalidated else { return }
    loadFailure = reason
    viewChannel.invokeMethod("loadRejected", arguments: reason)
  }
}

import Flutter
import ImageIO
import PassKit
import UIKit

/// PassKit's add-only conduit; no wallet read/update entitlement, NFC or school
/// session. Only the visible Flutter engine's scene may present private content.
final class BnbuEcardWalletBridge: NSObject, PKAddPassesViewControllerDelegate,
  UIAdaptivePresentationControllerDelegate {
  private let source: () -> UIViewController?
  private let channel: FlutterMethodChannel
  private var pending: FlutterResult?
  private var pass: PKPass?
  private var controller: PKAddPassesViewController?
  private var wasPresent = false
  private var presentationId: String?
  private var generation = 0

  init(messenger: FlutterBinaryMessenger, source: @escaping () -> UIViewController?) {
    self.source = source
    channel = FlutterMethodChannel(name: "bnbu/ecard_wallet", binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(nil); return }
      switch call.method {
      case "isAvailable": result(self.isAvailable)
      case "preparePortrait": self.preparePortrait(call.arguments, result: result)
      case "present": self.present(call.arguments, result: result)
      case "dismiss":
        if let arguments = call.arguments as? [String: Any],
          let id = arguments["presentationId"] as? String,
          id == self.presentationId {
          self.generation += 1
          self.finish("closed", animated: false)
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private var isAvailable: Bool {
    UIDevice.current.userInterfaceIdiom == .phone && PKAddPassesViewController.canAddPasses()
  }

  private func failure(_ code: String) -> FlutterError {
    FlutterError(code: code, message: "Wallet operation unavailable", details: nil)
  }

  private func preparePortrait(_ arguments: Any?, result: @escaping FlutterResult) {
    guard isAvailable, let input = arguments as? FlutterStandardTypedData,
      !input.data.isEmpty, input.data.count <= 5 * 1024 * 1024
    else { result(failure("invalid_image")); return }
    // ImageIO downsamples before full decoding; re-encoding omits EXIF and GPS.
    DispatchQueue.global(qos: .userInitiated).async {
      let output: Data? = autoreleasepool {
        guard let source = CGImageSourceCreateWithData(input.data as CFData, nil),
          CGImageSourceGetCount(source) == 1,
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0, width <= 16000, height <= 16000,
          width * height <= 16_000_000,
          let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
          ] as CFDictionary)
        else { return nil }
        let image = UIImage(cgImage: thumbnail)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let clean = UIGraphicsImageRenderer(size: image.size, format: format).image { context in
          UIColor.white.setFill()
          context.fill(CGRect(origin: .zero, size: image.size))
          image.draw(at: .zero)
        }
        return clean.jpegData(compressionQuality: 0.85)
      }
      DispatchQueue.main.async {
        guard let output, !output.isEmpty, output.count <= 256 * 1024 else {
          result(FlutterError(code: "invalid_image", message: "Unable to prepare portrait", details: nil))
          return
        }
        result(FlutterStandardTypedData(bytes: output))
      }
    }
  }

  private func present(_ arguments: Any?, result: @escaping FlutterResult) {
    guard isAvailable, pending == nil,
      let arguments = arguments as? [String: Any],
      let presentationId = arguments["presentationId"] as? String,
      presentationId.count == 32,
      let bytes = arguments["bytes"] as? FlutterStandardTypedData,
      bytes.data.count > 0, bytes.data.count <= 1024 * 1024,
      let expectedType = arguments["passType"] as? String,
      let expectedSerial = arguments["serial"] as? String,
      let presenter = BnbuNativePresentation.presenter(for: source())
    else { result(failure("unavailable")); return }
    do {
      // PKPass rejects unsigned/invalid packages; never accept pass.json alone.
      let pass = try PKPass(data: bytes.data)
      guard pass.passTypeIdentifier == expectedType, pass.serialNumber == expectedSerial,
        let controller = PKAddPassesViewController(pass: pass)
      else { result(failure("invalid_pass")); return }
      self.pass = pass
      self.presentationId = presentationId
      self.controller = controller
      pending = result
      wasPresent = PKPassLibrary.isPassLibraryAvailable() && PKPassLibrary().containsPass(pass)
      controller.delegate = self
      controller.presentationController?.delegate = self
      let generation = self.generation
      presenter.present(controller, animated: true) { [weak self, weak controller] in
        guard let self else { return }
        if generation != self.generation {
          controller?.dismiss(animated: false)
        }
      }
    } catch {
      // Do not forward Apple's error description or userInfo (may contain PII).
      result(failure("invalid_pass"))
    }
  }

  func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
    guard self.controller === controller else { return }
    var outcome = "closed"
    if let pass, PKPassLibrary.isPassLibraryAvailable(), PKPassLibrary().containsPass(pass) {
      // containsPass checks identity, not whether an existing card was updated.
      outcome = wasPresent ? "alreadyPresent" : "added"
    }
    finish(outcome)
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    guard presentationController.presentedViewController === controller else { return }
    finish("closed")
  }

  private func finish(_ outcome: String, animated: Bool = true) {
    guard let result = pending else { return }
    pending = nil
    pass = nil
    presentationId = nil
    let viewController = controller
    controller = nil
    if let viewController, viewController.presentingViewController != nil,
      !viewController.isBeingDismissed {
      viewController.dismiss(animated: animated) { result(outcome) }
    } else {
      result(outcome)
    }
  }
}

final class BnbuWalletAddButtonFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    BnbuWalletAddButton(frame: frame, viewId: viewId, messenger: messenger)
  }
}

private final class BnbuWalletAddButton: NSObject, FlutterPlatformView {
  private let container: UIView
  private let button = PKAddPassButton(addPassButtonStyle: .black)
  private let channel: FlutterMethodChannel
  init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
    container = UIView(frame: frame)
    channel = FlutterMethodChannel(name: "bnbu/wallet_add_button/\(viewId)", binaryMessenger: messenger)
    super.init()
    button.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(button)
    NSLayoutConstraint.activate([
      button.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
      button.heightAnchor.constraint(equalToConstant: 44),
      button.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor),
    ])
    button.addTarget(self, action: #selector(pressed), for: .touchUpInside)
  }
  func view() -> UIView { container }
  @objc private func pressed() {
    guard button.isEnabled else { return }
    button.isEnabled = false
    channel.invokeMethod("pressed", arguments: nil)
  }
}

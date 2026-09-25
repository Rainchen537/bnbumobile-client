import Flutter
import QuickLook
import UIKit

final class BnbuFilePreviewFactory: NSObject, FlutterPlatformViewFactory {
  private let source: () -> UIViewController?
  init(source: @escaping () -> UIViewController?) { self.source = source }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let path = (args as? [String: Any])?["path"] as? String ?? ""
    return BnbuFilePreview(frame: frame, url: URL(fileURLWithPath: path), source: source)
  }
}
private final class BnbuFilePreview: NSObject, FlutterPlatformView {
  let host: BnbuQuickLookHost
  init(frame: CGRect, url: URL, source: @escaping () -> UIViewController?) {
    host = BnbuQuickLookHost(frame: frame, url: url, source: source)
  }
  func view() -> UIView { host }
}
private final class BnbuQuickLookHost: UIView, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
  let preview = QLPreviewController()
  let url: URL
  let source: () -> UIViewController?
  init(frame: CGRect, url: URL, source: @escaping () -> UIViewController?) {
    self.url = url; self.source = source
    super.init(frame: frame)
    preview.dataSource = self; preview.delegate = self
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      preview.willMove(toParent: nil)
      preview.view.removeFromSuperview()
      preview.removeFromParent()
    } else if preview.parent == nil, let parent = source(), parent.viewIfLoaded?.window === window {
      parent.addChild(preview)
      preview.view.frame = bounds
      preview.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      addSubview(preview.view)
      preview.didMove(toParent: parent)
    }
  }
  func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
  func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
  func previewController(_ controller: QLPreviewController, shouldOpen url: URL, for item: QLPreviewItem) -> Bool { false }
  @available(iOS 13.0, *)
  func previewController(_ controller: QLPreviewController, editingModeFor item: QLPreviewItem) -> QLPreviewItemEditingMode { .disabled }
}

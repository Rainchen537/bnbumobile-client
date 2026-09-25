import Flutter
import UIKit
import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
  func testDetachedSourceCannotBorrowAnotherWindow() {
    XCTAssertNil(BnbuNativePresentation.presenter(for: nil))
    let detached = UIViewController()
    detached.loadViewIfNeeded()
    XCTAssertNil(BnbuNativePresentation.presenter(for: detached))
  }

  func testNavigationAndTabContainersResolveVisibleContent() {
    let first = UIViewController()
    let second = UIViewController()
    let navigation = UINavigationController(rootViewController: first)
    navigation.setViewControllers([first, second], animated: false)
    let tabs = UITabBarController()
    tabs.viewControllers = [UIViewController(), navigation]
    tabs.selectedIndex = 1
    XCTAssertTrue(BnbuNativePresentation.topViewController(from: tabs) === second)
  }

  func testEmptyNavigationContainerDoesNotRecurseToAnUnrelatedRoot() {
    let navigation = UINavigationController()
    XCTAssertTrue(BnbuNativePresentation.topViewController(from: navigation) === navigation)
  }

  func testSystemPanelsCannotHostAnotherFileMenu() {
    XCTAssertNil(BnbuNativePresentation.topViewController(from:
      UIAlertController(title: nil, message: nil, preferredStyle: .alert)))
    XCTAssertNil(BnbuNativePresentation.topViewController(from:
      UIActivityViewController(activityItems: ["test"], applicationActivities: nil)))
    XCTAssertNil(BnbuNativePresentation.topViewController(from:
      UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import)))
  }

  func testOwnedSceneWindowWorksWithoutAppDelegateWindow() throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive })
    let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
    let source = UIViewController()
    let navigation = UINavigationController(rootViewController: source)
    let window = UIWindow(windowScene: scene)
    window.rootViewController = navigation
    window.makeKeyAndVisible()
    defer {
      window.isHidden = true
      window.rootViewController = nil
      previousKeyWindow?.makeKeyAndVisible()
    }
    window.layoutIfNeeded()
    XCTAssertTrue(BnbuNativePresentation.presenter(for: source) === source)
    window.isHidden = true
    XCTAssertNil(BnbuNativePresentation.presenter(for: source))
  }

  func testPresentedModalTakesPrecedenceOverNavigationChild() throws {
    let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive })
    let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
    let source = UIViewController()
    let navigation = UINavigationController(rootViewController: source)
    let window = UIWindow(windowScene: scene)
    window.rootViewController = navigation
    window.makeKeyAndVisible()
    defer {
      navigation.dismiss(animated: false)
      window.isHidden = true
      window.rootViewController = nil
      previousKeyWindow?.makeKeyAndVisible()
    }
    let modal = UIViewController()
    modal.modalPresentationStyle = .overFullScreen
    let presented = expectation(description: "modal presented")
    navigation.present(modal, animated: false) { presented.fulfill() }
    wait(for: [presented], timeout: 5)
    XCTAssertTrue(BnbuNativePresentation.presenter(for: source) === modal)
  }
}

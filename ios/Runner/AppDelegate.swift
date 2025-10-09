import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var navigationChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Setup navigation method channel
    let controller = window?.rootViewController as! FlutterViewController
    navigationChannel = FlutterMethodChannel(
      name: "com.popi.biking/navigation",
      binaryMessenger: controller.binaryMessenger
    )

    navigationChannel?.setMethodCallHandler { [weak self] (call, result) in
      self?.handleMethodCall(call, result: result)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startNavigation":
      result("Navigation not implemented yet")
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

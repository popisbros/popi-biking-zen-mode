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
      // Parse arguments
      guard let args = call.arguments as? [String: Any],
            let points = args["points"] as? [[String: Double]],
            let destination = args["destination"] as? String else {
        result(FlutterError(code: "INVALID_ARGS",
                           message: "Missing points or destination",
                           details: nil))
        return
      }

      // Log received data
      print("📍 Received \(points.count) route points to: \(destination)")
      points.enumerated().forEach { index, point in
        if let lat = point["latitude"], let lon = point["longitude"] {
          print("  Point \(index): \(lat), \(lon)")
        }
      }

      result("Received route with \(points.count) points to \(destination)")

    default:
      result(FlutterMethodNotImplemented)
    }
  }
}

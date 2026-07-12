import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let importChannel = FlutterMethodChannel(
      name: "fknotes/attachment_import",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    importChannel.setMethodCallHandler { call, result in
      guard call.method == "availableStorageBytes" else {
        result(FlutterMethodNotImplemented)
        return
      }
      do {
        let attributes = try FileManager.default.attributesOfFileSystem(
          forPath: NSHomeDirectory()
        )
        result((attributes[.systemFreeSize] as? NSNumber)?.int64Value)
      } catch {
        result(
          FlutterError(
            code: "storage_capacity_unavailable",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }
}

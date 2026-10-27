import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var watchBridge: PhoneWatchBridgePlugin?
  private var authChannel: FlutterMethodChannel?
  private var adsChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Deactivate persisted authentication before WC can answer a cold-launch handshake.
    watchBridge = PhoneWatchBridgePlugin()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AdsConfiguration") {
      let channel = FlutterMethodChannel(
        name: "balmatchum/ads_config", binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        if call.method == "appId" {
          result(Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String ?? "")
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      adsChannel = channel
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SocialAuthConfiguration") {
      let channel = FlutterMethodChannel(
        name: "com.beomq.balmatchum/auth", binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "googleCallbackConfigured",
              let arguments = call.arguments as? [String: String],
              let clientId = arguments["clientId"], !clientId.isEmpty else {
          result(FlutterMethodNotImplemented)
          return
        }
        let expected = clientId.split(separator: ".").reversed().joined(separator: ".")
        let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        result(schemes.contains(expected))
      }
      authChannel = channel
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PhoneWatchBridge") {
      watchBridge?.register(messenger: registrar.messenger())
    }
  }
}

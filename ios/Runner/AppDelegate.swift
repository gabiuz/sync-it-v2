import Flutter
import UIKit

final class IncomingFilesCoordinator: NSObject, FlutterStreamHandler {
  static let shared = IncomingFilesCoordinator()

  private let methodChannelName = "com.gabiuz.gpx_lab/incoming_files"
  private let eventChannelName = "com.gabiuz.gpx_lab/incoming_files_events"
  private let supportedExtensions: Set<String> = ["gpx", "tcx", "fit"]

  private var initialBatch: [String: Any]?
  private var eventSink: FlutterEventSink?
  private var isRegistered = false

  func register(with messenger: FlutterBinaryMessenger) {
    guard !isRegistered else { return }
    isRegistered = true

    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: messenger
    )
    methodChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "getInitialIncomingSources" {
        let payload = self?.initialBatch
        self?.initialBatch = nil
        result(payload)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: messenger
    )
    eventChannel.setStreamHandler(self)
  }

  func handleIncomingUrls(_ urls: [URL]) {
    guard let batch = extractBatch(from: urls) else { return }
    if let sink = eventSink {
      sink(batch)
    } else {
      initialBatch = batch
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  private func extractBatch(from urls: [URL]) -> [String: Any]? {
    guard !urls.isEmpty else { return nil }
    var files: [[String: Any]] = []
    var errors: [String] = []

    for url in urls {
      let fileName = url.lastPathComponent.isEmpty ? "shared_activity" : url.lastPathComponent
      let ext = url.pathExtension.lowercased()
      if !ext.isEmpty && !supportedExtensions.contains(ext) {
        errors.append(
          "Unsupported file type \"\(fileName)\". GPX Lab only supports .gpx, .tcx, and .fit files."
        )
        continue
      }

      let accessing = url.startAccessingSecurityScopedResource()
      defer {
        if accessing {
          url.stopAccessingSecurityScopedResource()
        }
      }

      do {
        let data = try Data(contentsOf: url)
        files.append([
          "fileName": fileName,
          "bytes": FlutterStandardTypedData(bytes: data)
        ])
      } catch {
        errors.append("Unable to read shared file \"\(fileName)\".")
      }
    }

    if files.isEmpty && errors.isEmpty {
      return nil
    }
    return [
      "files": files,
      "errors": errors
    ]
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let url = launchOptions?[.url] as? URL {
      IncomingFilesCoordinator.shared.handleIncomingUrls([url])
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    IncomingFilesCoordinator.shared.handleIncomingUrls([url])
    return true
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    IncomingFilesCoordinator.shared.register(with: engineBridge.applicationRegistrar.messenger())
  }
}

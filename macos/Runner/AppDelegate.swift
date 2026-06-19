import Cocoa
import FlutterMacOS
import desktop_multi_window
import window_manager

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Register window_manager for sub-windows created by desktop_multi_window
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      WindowManagerPlugin.register(with: controller.registrar(forPlugin: "WindowManagerPlugin"))
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

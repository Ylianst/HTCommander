import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    
    // Register Bluetooth Classic handler
    let registrar = flutterViewController.registrar(forPlugin: "BluetoothClassicHandler")
    BluetoothClassicHandler.register(with: registrar)

    super.awakeFromNib()
  }
}

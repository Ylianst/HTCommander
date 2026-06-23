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

    // Register the speech-to-text handler (Apple SFSpeechRecognizer)
    let sttRegistrar = flutterViewController.registrar(forPlugin: "SpeechToTextHandler")
    SpeechToTextHandler.register(with: sttRegistrar)

    // Register the system audio (computer master volume) handler
    let sysAudioRegistrar = flutterViewController.registrar(forPlugin: "SystemAudioHandler")
    SystemAudioHandler.register(with: sysAudioRegistrar)

    // Register the text-to-speech handler (Apple AVSpeechSynthesizer)
    let ttsRegistrar = flutterViewController.registrar(forPlugin: "TextToSpeechHandler")
    TextToSpeechHandler.register(with: ttsRegistrar)

    super.awakeFromNib()
  }
}

import Cocoa
import FlutterMacOS
import desktop_multi_window

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

    // Register the native PCM player (CoreAudio) used for radio audio playback
    // and output-device selection.
    let pcmRegistrar = flutterViewController.registrar(forPlugin: "PcmPlayerHandler")
    PcmPlayerHandler.register(with: pcmRegistrar)

    // Detached tabs open in secondary windows created by desktop_multi_window,
    // each running its own Flutter engine. Those engines get no plugins
    // automatically, so window_manager, record, file_picker, etc. would throw
    // MissingPluginException and crash the detached window. Register all plugins
    // (generated + app-specific) for every sub-window as it is created.
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
      BluetoothClassicHandler.register(
        with: controller.registrar(forPlugin: "BluetoothClassicHandler"))
      SpeechToTextHandler.register(
        with: controller.registrar(forPlugin: "SpeechToTextHandler"))
      SystemAudioHandler.register(
        with: controller.registrar(forPlugin: "SystemAudioHandler"))
      TextToSpeechHandler.register(
        with: controller.registrar(forPlugin: "TextToSpeechHandler"))
      PcmPlayerHandler.register(
        with: controller.registrar(forPlugin: "PcmPlayerHandler"))
    }

    super.awakeFromNib()
  }
}

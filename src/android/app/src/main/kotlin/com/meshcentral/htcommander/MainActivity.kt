package com.meshcentral.htcommander

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var bluetoothClassicPlugin: BluetoothClassicPlugin? = null
    private var speechToTextPlugin: AndroidSpeechToTextPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = BluetoothClassicPlugin(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        plugin.activity = this
        bluetoothClassicPlugin = plugin

        speechToTextPlugin = AndroidSpeechToTextPlugin(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )

        // Bind the Android Auto bridge so the car UI can mirror channel/APRS
        // state and request channel changes from the Dart side.
        AndroidAutoBridge.attach(flutterEngine.dartExecutor.binaryMessenger)
    }
}

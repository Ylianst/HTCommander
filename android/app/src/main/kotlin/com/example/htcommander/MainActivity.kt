package com.example.htcommander

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var bluetoothClassicPlugin: BluetoothClassicPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val plugin = BluetoothClassicPlugin(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        plugin.activity = this
        bluetoothClassicPlugin = plugin
    }
}

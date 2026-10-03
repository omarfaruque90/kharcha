package com.kharcha.app

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Exposes the device's supported ABIs so the in-app updater can
        // download the matching split-per-ABI APK (smaller download).
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.kharcha.app/device"
        ).setMethodCallHandler { call, result ->
            if (call.method == "getSupportedAbis") {
                result.success(Build.SUPPORTED_ABIS.toList())
            } else {
                result.notImplemented()
            }
        }
    }
}

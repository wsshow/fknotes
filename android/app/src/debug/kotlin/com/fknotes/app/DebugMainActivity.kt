package com.fknotes.app

import android.app.Service
import io.flutter.embedding.engine.FlutterEngine

class DebugMainActivity : MainActivity() {
    override fun liteRtLmServiceClass(): Class<out Service> =
        DebugLiteRtLmService::class.java

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DebugDiagnosticsBridge.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}

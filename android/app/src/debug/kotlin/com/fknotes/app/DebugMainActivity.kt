package com.fknotes.app

import io.flutter.embedding.engine.FlutterEngine

class DebugMainActivity : MainActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DebugDiagnosticsBridge.register(this, flutterEngine.dartExecutor.binaryMessenger)
    }
}

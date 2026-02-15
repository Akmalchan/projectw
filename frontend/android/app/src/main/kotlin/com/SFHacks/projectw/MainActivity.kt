package com.SFHacks.projectw

import android.os.Bundle
import android.view.KeyEvent
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "sfhacks/keys"
    private var channel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // ✅ Stop drawing behind system bars (share space with Android nav bar)
        WindowCompat.setDecorFitsSystemWindows(window, true)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            channel?.invokeMethod("volume", keyCode)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }
}

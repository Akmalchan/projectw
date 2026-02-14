package com.SFHacks.projectw

import io.flutter.embedding.android.FlutterActivity
import android.view.KeyEvent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel


class MainActivity : FlutterActivity() {
    private val CHANNEL = "sfhacks/keys"
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        // Most Bluetooth selfie remotes trigger volume keys.
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            channel?.invokeMethod("volume", keyCode)
            return true // consume it so volume doesn't change
        }
        return super.onKeyDown(keyCode, event)
    }
}
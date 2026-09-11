package com.appfide.clipboard_sync

import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSensitive" -> result.success(isClipboardSensitive())
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Android 13+ lets the writing app flag clipboard content as sensitive
     * (password managers do); honour it so the content is never recorded.
     */
    private fun isClipboardSensitive(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return false
        val manager = getSystemService(Context.CLIPBOARD_SERVICE) as? ClipboardManager ?: return false
        val description = manager.primaryClipDescription ?: return false
        return description.extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE, false) ?: false
    }

    companion object {
        private const val CHANNEL = "com.appfide.clipboard_sync/clipboard"
    }
}

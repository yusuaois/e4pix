package com.yusuaois.e4pix

import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.WindowManager
import com.yusuaois.e4pix.camera.E4pixCameraPlugin
import com.yusuaois.e4pix.camera.GPhoto2Native
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Smoke test
        try {
            val v = GPhoto2Native.nativeGetLibraryVersion()
            Log.i("e4pix-main", "============================================")
            v.lines().forEach { Log.i("e4pix-main", it) }
            Log.i("e4pix-main", "============================================")
        } catch (e: Throwable) {
            Log.e("e4pix-main", "version smoke test failed", e)
        }

        // Register MethodChannel
        E4pixCameraPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
    }
}
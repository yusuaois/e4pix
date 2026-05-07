package com.yusuaois.e4pix

import android.util.Log
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
}
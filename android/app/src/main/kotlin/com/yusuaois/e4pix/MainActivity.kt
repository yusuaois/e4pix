package com.yusuaois.e4pix

import android.os.Bundle
import android.util.Log
import com.yusuaois.e4pix.camera.GPhoto2Native
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // ⭐ Stage A-3 smoke test
        try {
            val version = GPhoto2Native.getLibraryVersion()
            Log.i("e4pix-main", "============================================")
            Log.i("e4pix-main", "libgphoto2 stack loaded:")
            version.lines().forEach { Log.i("e4pix-main", it) }
            Log.i("e4pix-main", "============================================")
        } catch (e: Throwable) {
            Log.e("e4pix-main", "libgphoto2 smoke test FAILED", e)
        }
    }
}

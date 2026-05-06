package com.yusuaois.e4pix.camera

import android.util.Log

/**
 * JNI declarations for libgphoto2 bridge.
 * 
 * Loading order matters: libusb-1.0 → libgphoto2_port → libgphoto2 → e4pix_jni
 */
object GPhoto2Native {
    private const val TAG = "e4pix-kotlin"
    
    init {
        try {
            System.loadLibrary("usb-1.0")
            System.loadLibrary("gphoto2_port")
            System.loadLibrary("gphoto2")
            System.loadLibrary("e4pix_jni")
            Log.i(TAG, "✅ All native libs loaded successfully")
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "❌ Failed to load native libs: ${e.message}", e)
            throw e
        }
    }
    
    @JvmStatic
    external fun getLibraryVersion(): String
}
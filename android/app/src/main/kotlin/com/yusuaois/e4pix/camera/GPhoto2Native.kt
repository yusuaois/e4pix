package com.yusuaois.e4pix.camera

import android.util.Log
import java.io.File
import java.io.FileOutputStream
import android.content.Context

object GPhoto2Native {
    private const val TAG = "e4pix-jni"

    init {
        try {
            System.loadLibrary("ltdl")
            System.loadLibrary("usb-1.0")
            System.loadLibrary("gphoto2_port")
            System.loadLibrary("gphoto2")
            System.loadLibrary("e4pix_jni")
            Log.i(TAG, "✅ All native libs loaded")
        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "❌ Failed to load native libs", e)
            throw e
        }
    }

    /**
     * 将 assets 中的插件部署到应用私有目录，并返回绝对路径
     */
    fun prepareAssets(context: android.content.Context): Pair<String, String> {
        val root = File(context.filesDir, "gphoto2")
        val camlibsDir = File(root, "camlibs")
        val iolibsDir = File(root, "iolibs")

        if (!camlibsDir.exists()) camlibsDir.mkdirs()
        if (!iolibsDir.exists()) iolibsDir.mkdirs()

        deployFolder(context, "gphoto2/camlibs", camlibsDir)
        deployFolder(context, "gphoto2/iolibs", iolibsDir)

        return Pair(camlibsDir.absolutePath, iolibsDir.absolutePath)
    }

    private fun deployFolder(context: android.content.Context, assetPath: String, destDir: File) {
        try {
            val assets = context.assets.list(assetPath) ?: return
            for (file in assets) {
                val outFile = File(destDir, file)
                if (!outFile.exists()) {
                    context.assets.open("$assetPath/$file").use { input ->
                        outFile.outputStream().use { output ->
                            input.copyTo(output)
                        }
                    }
                    Log.d("gphoto-jni", "Deployed: $file to ${outFile.absolutePath}")
                }
            }
        } catch (e: Exception) {
            Log.e("gphoto-jni", "Failed to deploy assets from $assetPath", e)
        }
    }

    @JvmStatic external fun nativeGetLibraryVersion(): String
    @JvmStatic external fun nativeInit(camlibsDir: String, iolibsDir: String): Int
    @JvmStatic external fun nativeOpenCamera(usbFd: Int): Int
    @JvmStatic external fun nativeGetCameraSummary(): String?

    /** Wait for next camera event. Returns map: {type, folder?, name?} or null. */
    @JvmStatic external fun nativeWaitForEvent(timeoutMs: Int): HashMap<String, String>?

    /** Download file from camera. Returns local path or null. */
    @JvmStatic external fun nativeDownloadFile(folder: String, name: String, outDir: String): String?

    @JvmStatic external fun nativeTriggerCapture(): Int
    @JvmStatic external fun nativeCloseCamera()
}
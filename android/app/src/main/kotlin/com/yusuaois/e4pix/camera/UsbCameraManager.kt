package com.yusuaois.e4pix.camera

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbManager
import android.os.Build
import android.util.Log
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

class UsbCameraManager(private val context: Context) {

    companion object {
        private const val TAG = "e4pix-usb"
        private const val ACTION_PERMISSION = "com.yusuaois.e4pix.USB_PERMISSION"

        // Common camera vendor IDs (PTP devices)
        private val CAMERA_VIDS = setOf(
            0x04A9,  // Canon
            0x04B0,  // Nikon
            0x04CB,  // Fujifilm
            0x054C,  // Sony
            0x04B8,  // Panasonic (older)
            0x2D98,  // Panasonic Lumix
            0x04DA,  // Panasonic
        )

        /** /dev/bus/usb/001/002  →  "usb:001,002" */
        fun parsePort(deviceName: String): String {
            val m = Regex("""/dev/bus/usb/(\d+)/(\d+)""").find(deviceName)
            return if (m != null) {
                "usb:${m.groupValues[1]},${m.groupValues[2]}"
            } else {
                "usb:${deviceName.replace("/", "_")}"
            }
        }
    }

    /** 列出所有当前连接的 PTP/相机类 USB 设备 */
    fun listCameras(): List<UsbDevice> {
        val all = usbManager.deviceList.values
        Log.i(TAG, "USB scan: ${all.size} devices total")
        return all.filter { isCamera(it) }.also {
            Log.i(TAG, "  → ${it.size} are cameras")
        }
    }

    /** 按 port 字符串（"usb:001,002"）查找设备 */
    fun findByPort(port: String): UsbDevice? {
        return usbManager.deviceList.values.firstOrNull {
            parsePort(it.deviceName) == port
        }
    }

    private val usbManager =
        context.getSystemService(Context.USB_SERVICE) as UsbManager
    private var connection: UsbDeviceConnection? = null

    fun findCamera(): UsbDevice? {
        val devices = usbManager.deviceList
        Log.i(TAG, "Scanning ${devices.size} USB devices…")
        devices.values.forEach {
            Log.i(TAG, "  ${it.deviceName} VID=0x${it.vendorId.toString(16)} PID=0x${it.productId.toString(16)} class=${it.deviceClass}")
        }
        return devices.values.firstOrNull { isCamera(it) }
    }

    private fun isCamera(device: UsbDevice): Boolean {
        // Check for PTP/MTP class on any interface
        for (i in 0 until device.interfaceCount) {
            val iface = device.getInterface(i)
            if (iface.interfaceClass == UsbConstants.USB_CLASS_STILL_IMAGE) return true
        }
        return device.vendorId in CAMERA_VIDS
    }

    suspend fun requestPermission(device: UsbDevice): Boolean {
        if (usbManager.hasPermission(device)) {
            Log.i(TAG, "Already has permission for ${device.deviceName}")
            return true
        }

        return suspendCoroutine { cont ->
            val piFlags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                PendingIntent.FLAG_MUTABLE
            else 0
            val pendingIntent = PendingIntent.getBroadcast(
                context, 0, Intent(ACTION_PERMISSION).setPackage(context.packageName),
                piFlags
            )

            val receiver = object : BroadcastReceiver() {
                override fun onReceive(c: Context, intent: Intent) {
                    if (intent.action != ACTION_PERMISSION) return
                    val granted = intent.getBooleanExtra(
                        UsbManager.EXTRA_PERMISSION_GRANTED, false
                    )
                    Log.i(TAG, "Permission result: $granted")
                    try { c.unregisterReceiver(this) } catch (_: Exception) {}
                    cont.resume(granted)
                }
            }
            val filter = IntentFilter(ACTION_PERMISSION)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                context.registerReceiver(receiver, filter)
            }
            usbManager.requestPermission(device, pendingIntent)
        }
    }

    /** Returns USB file descriptor or -1 on failure */
    fun openConnection(device: UsbDevice): Int {
        val conn = usbManager.openDevice(device)
        if (conn == null) {
            Log.e(TAG, "openDevice returned null")
            return -1
        }
        connection = conn
        Log.i(TAG, "USB opened: fd=${conn.fileDescriptor} dev=${device.deviceName}")
        return conn.fileDescriptor
    }

    fun close() {
        try { connection?.close() } catch (_: Exception) {}
        connection = null
    }
}
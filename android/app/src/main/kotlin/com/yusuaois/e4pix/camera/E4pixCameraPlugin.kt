package com.yusuaois.e4pix.camera

import android.app.Activity
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.File

class E4pixCameraPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object { private const val TAG = "e4pix-plugin" }

    private val methodChannel = MethodChannel(messenger, "e4pix/camera")
    private val eventChannel  = EventChannel(messenger, "e4pix/camera/events")
    private val usb           = UsbCameraManager(activity)
    private val scope         = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private var captureJob: Job? = null
    private var eventSink: EventChannel.EventSink? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    // ============================================================================
    // EventChannel: Dart 端订阅时被调用
    // ============================================================================
    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        Log.i(TAG, "EventChannel onListen")
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        Log.i(TAG, "EventChannel onCancel")
        eventSink = null
    }

    private fun emit(payload: Map<String, Any?>) {
        scope.launch(Dispatchers.Main) {
            eventSink?.success(payload)
        }
    }

    // ============================================================================
    // MethodChannel
    // ============================================================================
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getLibraryVersion" ->
                result.success(GPhoto2Native.nativeGetLibraryVersion())

            "detectCameras" -> {
                val list = usb.listCameras().map { d ->
                    mapOf(
                        "model" to (d.productName ?: "USB Camera"),
                        "port"  to UsbCameraManager.parsePort(d.deviceName),
                        "vendorId"  to d.vendorId,
                        "productId" to d.productId,
                    )
                }
                result.success(list)
            }

            "startTether" -> {
                val port       = call.argument<String>("port")
                val saveFolder = call.argument<String>("saveFolder")
                if (port == null || saveFolder == null) {
                    result.error("E_ARG", "port and saveFolder required", null)
                    return
                }
                scope.launch { handleStartTether(port, saveFolder, result) }
            }

            "stopTether" ->
                scope.launch { handleStopTether(result) }

            "triggerCapture" ->
                scope.launch(Dispatchers.IO) {
                    val r = GPhoto2Native.nativeTriggerCapture()
                    withContext(Dispatchers.Main) {
                        if (r >= 0) result.success(null)
                        else result.error("E_TRIGGER", "code $r", null)
                    }
                }

            else -> result.notImplemented()
        }
    }

    private suspend fun handleStartTether(
        port: String,
        saveFolder: String,
        result: MethodChannel.Result,
    ) {
        try {
            File(saveFolder).mkdirs()

            val device = usb.findByPort(port) ?: run {
                result.error("E_NO_CAMERA", "未找到相机 ($port)", null)
                return
            }

            val (camPath, ioPath) = withContext(Dispatchers.IO) {
                GPhoto2Native.prepareAssets(activity)
            }
            Log.i(TAG, "Using camlibs path: $camPath")

            if (!usb.requestPermission(device)) {
                result.error("E_PERM", "USB 权限被拒绝", null)
                return
            }

            val fd = usb.openConnection(device)
            if (fd < 0) {
                result.error("E_OPEN", "无法打开 USB 连接", null)
                return
            }

            val nativeDir = activity.applicationInfo.nativeLibraryDir

            val initRet = withContext(Dispatchers.IO) {
                GPhoto2Native.nativeInit(camPath, ioPath)
            }
            if (initRet < 0) {
                usb.close()
                result.error("E_INIT", "gphoto2 init 失败 ($initRet)", null)
                return
            }

            val openRet = withContext(Dispatchers.IO) {
                GPhoto2Native.nativeOpenCamera(fd)
            }
            if (openRet < 0) {
                usb.close()
                result.error("E_CAMERA",
                    "相机连接失败 ($openRet)。检查相机 USB 模式应为 PC(Tether)/PTP", null)
                return
            }

            val model = withContext(Dispatchers.IO) {
                GPhoto2Native.nativeGetCameraSummary()
            } ?: device.productName ?: "Unknown"

            result.success(null)
            emit(mapOf("type" to "connected", "model" to model))

            // capture loop
            captureJob = scope.launch(Dispatchers.IO) {
                Log.i(TAG, "Capture loop START → $saveFolder")
                while (isActive) {
                    val ev = GPhoto2Native.nativeWaitForEvent(10000) ?: continue
                    val type = ev["type"] ?: continue

                    when (type) {
                        "timeout" -> { /* 正常超时，继续下一次等待 */ }

                        "error" -> {
                            val code = ev["code"] ?: ""
                            Log.e(TAG, "Native Error in event loop: $code")
                            if (code == "-52" || code == "-1") {
                                emit(mapOf("type" to "disconnected"))
                                break 
                            }
                        }

                        "fileAdded" -> {
                            val folder = ev["folder"] ?: continue
                            val name   = ev["name"]   ?: continue
                            Log.i(TAG, "FILE_ADDED $folder/$name")

                            emit(mapOf("type" to "takingShot"))

                            val saved = GPhoto2Native.nativeDownloadFile(folder, name, saveFolder)
                            if (saved != null) {
                                emit(mapOf(
                                    "type" to "shotSaved",
                                    "filename" to name,
                                    "path" to saved,
                                ))
                            } else {
                                emit(mapOf(
                                    "type" to "error",
                                    "message" to "下载失败: $name",
                                ))
                            }
                        }

                        "captureComplete" -> {
                            emit(mapOf("type" to "takingShot"))
                        }

                        else -> Log.d(TAG, "ignored event: $type")
                    }
                }
                Log.i(TAG, "Capture loop END")
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "startTether crashed", e)
            try {
                result.error("E_EXC", e.message ?: "", null)
            } catch (_: IllegalStateException) {
            }
            emit(mapOf("type" to "error", "message" to (e.message ?: "Unknown")))
            emit(mapOf("type" to "disconnected"))
        }
    }

    private suspend fun handleStopTether(result: MethodChannel.Result) {
        try {
            captureJob?.cancelAndJoin()
            captureJob = null
            withContext(Dispatchers.IO) { GPhoto2Native.nativeCloseCamera() }
            usb.close()
            emit(mapOf("type" to "disconnected"))
            result.success(null)
        } catch (e: Exception) {
            result.error("E_STOP", e.message ?: "", null)
        }
    }
}
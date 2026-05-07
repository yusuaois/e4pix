// e4pix_gphoto2_jni.cpp
// JNI bridge to libgphoto2 for Android USB tethered capture.

#include <jni.h>
#include <android/log.h>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <gphoto2/gphoto2.h>
#include <gphoto2/gphoto2-port-info-list.h>
#include <gphoto2/gphoto2-version.h>

#define TAG "e4pix-jni"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

// ============================================================================
// Session state
// ============================================================================
namespace
{
    struct Session
    {
        GPContext *ctx = nullptr;
        Camera *cam = nullptr;
        int usb_fd = -1;
        std::mutex lock;
    };
    Session g_session;

    std::string jstr(JNIEnv *env, jstring js)
    {
        if (!js)
            return "";
        const char *c = env->GetStringUTFChars(js, nullptr);
        std::string s(c);
        env->ReleaseStringUTFChars(js, c);
        return s;
    }

    void log_err(const char *what, int code)
    {
        LOGE("%s: %d (%s)", what, code, gp_result_as_string(code));
    }

    void cleanup_locked()
    {
        if (g_session.cam)
        {
            gp_camera_unref(g_session.cam);
            g_session.cam = nullptr;
        }
        if (g_session.ctx)
        {
            gp_context_unref(g_session.ctx);
            g_session.ctx = nullptr;
        }
        if (g_session.usb_fd >= 0)
        {
            gp_port_usb_set_sys_device(-1);
            g_session.usb_fd = -1;
        }
    }
} // namespace

// ============================================================================
// JNI bindings — package: com.yusuaois.e4pix.camera.GPhoto2Native
// ============================================================================
#define JNI_FN(ret, name) extern "C" JNIEXPORT ret JNICALL \
    Java_com_yusuaois_e4pix_camera_GPhoto2Native_##name

// Smoke test
JNI_FN(jstring, nativeGetLibraryVersion)(JNIEnv *env, jclass)
{
    std::string out;
    const char **v = gp_library_version(GP_VERSION_VERBOSE);
    if (v)
    {
        out += "libgphoto2:";
        for (; *v; ++v)
        {
            out += "\n  ";
            out += *v;
        }
    }
    const char **p = gp_port_library_version(GP_VERSION_VERBOSE);
    if (p)
    {
        out += "\nlibgphoto2_port:";
        for (; *p; ++p)
        {
            out += "\n  ";
            out += *p;
        }
    }
    return env->NewStringUTF(out.c_str());
}

// Init — set CAMLIBS / IOLIBS, create context + camera object.
// Must be called BEFORE nativeOpenCamera each session.
JNI_FN(jint, nativeInit)(JNIEnv *env, jclass, jstring jcamlibs, jstring jiolibs)
{
    std::lock_guard<std::mutex> g(g_session.lock);

    std::string camlibs = jstr(env, jcamlibs);
    std::string iolibs = jstr(env, jiolibs);
    LOGI("nativeInit  CAMLIBS=%s  IOLIBS=%s", camlibs.c_str(), iolibs.c_str());
    setenv("CAMLIBS", camlibs.c_str(), 1);
    setenv("IOLIBS", iolibs.c_str(), 1);

    cleanup_locked();

    g_session.ctx = gp_context_new();
    if (!g_session.ctx)
    {
        LOGE("gp_context_new returned null");
        return GP_ERROR;
    }
    int ret = gp_camera_new(&g_session.cam);
    if (ret < GP_OK)
    {
        log_err("gp_camera_new", ret);
        gp_context_unref(g_session.ctx);
        g_session.ctx = nullptr;
        return ret;
    }
    LOGI("nativeInit OK");
    return GP_OK;
}

// Open camera using Android-supplied USB FD.
// Must call nativeInit first.
JNI_FN(jint, nativeOpenCamera)(JNIEnv *, jclass, jint usbFd)
{
    std::lock_guard<std::mutex> g(g_session.lock);
    LOGI("nativeOpenCamera fd=%d", usbFd);

    if (!g_session.cam || !g_session.ctx)
    {
        LOGE("Session not initialized");
        return GP_ERROR;
    }

    // Tell libgphoto2_port to use this FD instead of enumerating /dev/bus/usb
    int ret = gp_port_usb_set_sys_device(usbFd);
    if (ret < GP_OK)
    {
        log_err("gp_port_usb_set_sys_device", ret);
        return ret;
    }
    g_session.usb_fd = usbFd;

    // Initialize PTP session with the camera
    ret = gp_camera_init(g_session.cam, g_session.ctx);
    if (ret < GP_OK)
    {
        log_err("gp_camera_init", ret);
        gp_port_usb_set_sys_device(-1);
        g_session.usb_fd = -1;
        return ret;
    }

    LOGI("Camera opened");
    return GP_OK;
}

// Returns model name (e.g. "Panasonic DC-S5") or null if not connected.
JNI_FN(jstring, nativeGetCameraSummary)(JNIEnv *env, jclass)
{
    std::lock_guard<std::mutex> g(g_session.lock);
    if (!g_session.cam)
        return nullptr;
    CameraAbilities ab;
    if (gp_camera_get_abilities(g_session.cam, &ab) < GP_OK)
        return nullptr;
    return env->NewStringUTF(ab.model);
}

// Block up to timeoutMs waiting for next FILE_ADDED event.
// On capture, downloads file to outputDir and returns local path.
// Returns null on timeout, error, or other event types.
JNI_FN(jobject, nativeWaitForEvent)(JNIEnv *env, jclass, jint timeoutMs)
{
    Camera *cam;
    GPContext *ctx;
    {
        std::lock_guard<std::mutex> g(g_session.lock);
        if (!g_session.cam || !g_session.ctx)
            return nullptr;
        cam = g_session.cam;
        ctx = g_session.ctx;
    }

    CameraEventType type = GP_EVENT_UNKNOWN;
    void *data = nullptr;
    int ret = gp_camera_wait_for_event(cam, timeoutMs, &type, &data, ctx);
    if (ret < GP_OK)
    {
        log_err("gp_camera_wait_for_event", ret);
        if (data)
            free(data);
        return nullptr;
    }

    jclass mapCls = env->FindClass("java/util/HashMap");
    jmethodID init = env->GetMethodID(mapCls, "<init>", "()V");
    jmethodID put = env->GetMethodID(mapCls, "put",
                                     "(Ljava/lang/Object;Ljava/lang/Object;)Ljava/lang/Object;");
    jobject map = env->NewObject(mapCls, init);

    auto putKV = [&](const char *k, const char *v)
    {
        jstring jk = env->NewStringUTF(k);
        jstring jv = env->NewStringUTF(v ? v : "");
        env->CallObjectMethod(map, put, jk, jv);
        env->DeleteLocalRef(jk);
        env->DeleteLocalRef(jv);
    };

    switch (type)
    {
    case GP_EVENT_TIMEOUT:
        putKV("type", "timeout");
        break;
    case GP_EVENT_FILE_ADDED:
    {
        auto *p = static_cast<CameraFilePath *>(data);
        putKV("type", "fileAdded");
        putKV("folder", p->folder);
        putKV("name", p->name);
        break;
    }
    case GP_EVENT_CAPTURE_COMPLETE:
        putKV("type", "captureComplete");
        break;
    case GP_EVENT_FOLDER_ADDED:
    {
        auto *p = static_cast<CameraFilePath *>(data);
        putKV("type", "folderAdded");
        putKV("folder", p->folder);
        break;
    }
    default:
        putKV("type", "other");
        break;
    }

    if (data)
        free(data);
    return map;
}

JNI_FN(jstring, nativeDownloadFile)
(JNIEnv *env, jclass, jstring jfolder, jstring jname, jstring joutDir)
{
    std::string folder = jstr(env, jfolder);
    std::string name = jstr(env, jname);
    std::string outDir = jstr(env, joutDir);

    Camera *cam;
    GPContext *ctx;
    {
        std::lock_guard<std::mutex> g(g_session.lock);
        if (!g_session.cam || !g_session.ctx)
            return nullptr;
        cam = g_session.cam;
        ctx = g_session.ctx;
    }

    std::string localPath = outDir;
    if (!localPath.empty() && localPath.back() != '/')
        localPath += '/';
    localPath += name;

    CameraFile *file = nullptr;
    if (gp_file_new(&file) < GP_OK)
        return nullptr;

    int ret;
    {
        std::lock_guard<std::mutex> g(g_session.lock);
        ret = gp_camera_file_get(cam, folder.c_str(), name.c_str(),
                                 GP_FILE_TYPE_NORMAL, file, ctx);
    }
    if (ret < GP_OK)
    {
        log_err("gp_camera_file_get", ret);
        gp_file_unref(file);
        return nullptr;
    }

    ret = gp_file_save(file, localPath.c_str());
    if (ret < GP_OK)
    {
        log_err("gp_file_save", ret);
        gp_file_unref(file);
        return nullptr;
    }
    gp_file_unref(file);

    LOGI("Saved → %s", localPath.c_str());
    return env->NewStringUTF(localPath.c_str());
}

// Optional: trigger capture remotely (camera button = passive tethering)
JNI_FN(jint, nativeTriggerCapture)(JNIEnv *, jclass)
{
    std::lock_guard<std::mutex> g(g_session.lock);
    if (!g_session.cam || !g_session.ctx)
        return GP_ERROR;
    CameraFilePath p;
    int ret = gp_camera_capture(g_session.cam, GP_CAPTURE_IMAGE, &p, g_session.ctx);
    if (ret < GP_OK)
        log_err("gp_camera_capture", ret);
    return ret;
}

JNI_FN(void, nativeCloseCamera)(JNIEnv *, jclass)
{
    std::lock_guard<std::mutex> g(g_session.lock);
    LOGI("nativeCloseCamera");
    if (g_session.cam && g_session.ctx)
    {
        int ret = gp_camera_exit(g_session.cam, g_session.ctx);
        if (ret < GP_OK)
        {
            LOGW("gp_camera_exit: %s (USB may already be detached)",
                 gp_result_as_string(ret));
        }
    }
    cleanup_locked();
}
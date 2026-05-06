// e4pix_gphoto2_jni.cpp - JNI bridge to libgphoto2
//
// Stage A-3.2 smoke test: just call gp_library_version() to prove
// that all .so files load and link correctly.

#include <jni.h>
#include <android/log.h>
#include <string>
#include <gphoto2/gphoto2.h>
#include <gphoto2/gphoto2-version.h>

#define TAG "e4pix-jni"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

extern "C"
{
    JNIEXPORT jstring JNICALL
    Java_com_yusuaois_e4pix_camera_GPhoto2Native_getLibraryVersion(
        JNIEnv *env, jclass /*clazz*/)
    {

        LOGI("getLibraryVersion called");

        std::string result;

        // libgphoto2 主版本
        const char **versions = gp_library_version(GP_VERSION_VERBOSE);
        if (versions)
        {
            result += "libgphoto2:\n";
            while (*versions)
            {
                result += "  ";
                result += *versions;
                result += "\n";
                versions++;
            }
        }

        // libgphoto2_port 版本
        const char **port_versions = gp_port_library_version(GP_VERSION_VERBOSE);
        if (port_versions)
        {
            result += "\nlibgphoto2_port:\n";
            while (*port_versions)
            {
                result += "  ";
                result += *port_versions;
                result += "\n";
                port_versions++;
            }
        }

        LOGI("Version info:\n%s", result.c_str());
        return env->NewStringUTF(result.c_str());
    }

} // extern "C"
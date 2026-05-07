#!/bin/bash
# scripts/build_android_libs.sh
#
# Cross-compile libgphoto2 + libusb + libltdl for Android, FLAT output.
#
# Usage:
#   ./scripts/build_android_libs.sh                    # arm64-v8a (default)
#   ABI=x86_64 ./scripts/build_android_libs.sh         # for emulator
#   CLEAN=1 ./scripts/build_android_libs.sh            # rebuild from scratch
#   CAMLIBS_SET=ptp2 ./scripts/build_android_libs.sh   # only PTP camlib (smallest APK)
#
# Output:
#   android/app/src/main/jniLibs/<abi>/
#     ├── libusb-1.0.so
#     ├── libltdl.so
#     ├── libgphoto2_port.so
#     ├── libgphoto2.so
#     ├── libcamlib_ptp2.so       (renamed: ptp2.so)
#     ├── libcamlib_canon.so      (renamed: canon.so)
#     ├── ... more camlibs ...
#     └── libiolib_usb1.so        (renamed: usb1.so)
#   third_party/libgphoto2-headers/gphoto2/*.h

set -e

# ============================================================
# Config
# ============================================================
ABI="${ABI:-arm64-v8a}"
API_LEVEL="${API_LEVEL:-24}"
CAMLIBS_SET="${CAMLIBS_SET:-standard}"   # standard | ptp2 | all
CLEAN="${CLEAN:-0}"

# Auto-detect NDK
NDK_PATH="${NDK_PATH:-$ANDROID_NDK_ROOT}"
if [ -z "$NDK_PATH" ]; then
    for c in \
        /mnt/d/AndroidStudioSDK/ndk/android-ndk-r29-linux \
        /mnt/d/Develop/Android/Sdk/ndk/android-ndk-r29-linux \
        /mnt/c/Users/$USER/AppData/Local/Android/Sdk/ndk/26.1.10909125 \
        $HOME/Android/Sdk/ndk/26.1.10909125 \
        ; do
        [ -d "$c" ] && NDK_PATH="$c" && break
    done
fi
[ -d "$NDK_PATH" ] || { echo "[FAIL] NDK not found. Set NDK_PATH explicitly."; exit 1; }

# ABI → triple
case "$ABI" in
    arm64-v8a)   TARGET="aarch64-linux-android" ;;
    armeabi-v7a) TARGET="armv7a-linux-androideabi" ;;
    x86_64)      TARGET="x86_64-linux-android" ;;
    x86)         TARGET="i686-linux-android" ;;
    *) echo "[FAIL] Unsupported ABI: $ABI"; exit 1 ;;
esac

# Paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build_native"
SRC_DIR="$BUILD_DIR/src"
PREFIX="$BUILD_DIR/install/$ABI"
JNILIBS="$PROJECT_ROOT/android/app/src/main/jniLibs/$ABI"
HEADERS="$PROJECT_ROOT/third_party/libgphoto2-headers"
TOOLCHAIN="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64"

# Versions
LIBTOOL_VER="2.4.7"
LIBUSB_VER="1.0.27"
LIBGPHOTO2_VER="2.5.33"

# Logging
B='\033[0;34m'; G='\033[0;32m'; Y='\033[0;33m'; R='\033[0;31m'; N='\033[0m'
log()  { echo -e "${B}[INFO]${N} $1"; }
ok()   { echo -e "${G}[ OK ]${N} $1"; }
warn() { echo -e "${Y}[WARN]${N} $1"; }
die()  { echo -e "${R}[FAIL]${N} $1"; exit 1; }

# Toolchain env
export AR="$TOOLCHAIN/bin/llvm-ar"
export CC="$TOOLCHAIN/bin/${TARGET}${API_LEVEL}-clang"
export CXX="$TOOLCHAIN/bin/${TARGET}${API_LEVEL}-clang++"
export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
export STRIP="$TOOLCHAIN/bin/llvm-strip"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export ANDROID_NDK_ROOT="$NDK_PATH"

# Per-ABI flags
EXTRA_CFLAGS=""; EXTRA_LDFLAGS=""
case "$ABI" in
    armeabi-v7a)
        EXTRA_CFLAGS="-march=armv7-a -mfloat-abi=softfp -mfpu=neon"
        EXTRA_LDFLAGS="-march=armv7-a"
        ;;
esac

export CFLAGS="-fPIC -ffunction-sections -funwind-tables -fstack-protector-strong -no-canonical-prefixes -DANDROID -D__ANDROID__ -DNDEBUG -O2 $EXTRA_CFLAGS"
export CPPFLAGS="-D__ANDROID__"
export LDFLAGS="-L$PREFIX/lib -llog $EXTRA_LDFLAGS"
export ac_cv_header_sys_file_h=yes
export ac_cv_header_sys_ioctl_h=yes

[ -x "$CC" ] || die "Compiler not found: $CC"

# Banner
log "============================================"
log "  libgphoto2 Android cross-build"
log "============================================"
log "  ABI:         $ABI ($TARGET)"
log "  API:         $API_LEVEL"
log "  NDK:         $NDK_PATH"
log "  CAMLIBS_SET: $CAMLIBS_SET"
log "  Output:      $JNILIBS"
log "============================================"

# Check prerequisites
for cmd in wget tar make pkg-config; do
    command -v $cmd >/dev/null 2>&1 || die "Missing: $cmd. Try: sudo apt install $cmd"
done

# Clean
if [ "$CLEAN" = "1" ]; then
    warn "CLEAN=1: wiping $PREFIX and $JNILIBS/*.so"
    rm -rf "$PREFIX"
    rm -f "$JNILIBS"/*.so
fi

mkdir -p "$SRC_DIR" "$PREFIX" "$JNILIBS"

# ============================================================
# 1. libtool (provides libltdl)
# ============================================================
build_libtool() {
    log "── libtool $LIBTOOL_VER"
    [ -f "$PREFIX/lib/libltdl.so" ] && { ok "already built — skip"; return; }

    cd "$SRC_DIR"
    [ -f "libtool-${LIBTOOL_VER}.tar.gz" ] || \
        wget -q "https://ftp.gnu.org/gnu/libtool/libtool-${LIBTOOL_VER}.tar.gz"

    rm -rf "libtool-${LIBTOOL_VER}-${ABI}"
    tar -xzf "libtool-${LIBTOOL_VER}.tar.gz"
    mv "libtool-${LIBTOOL_VER}" "libtool-${LIBTOOL_VER}-${ABI}"
    cd "libtool-${LIBTOOL_VER}-${ABI}"

    ./configure --host="$TARGET" --prefix="$PREFIX" \
        --enable-shared --disable-static \
        --enable-ltdl-install --disable-symbol-versioning \
        > configure.log 2>&1 || die "libtool configure failed (see $PWD/configure.log)"

    make -j$(nproc) > build.log 2>&1 || die "libtool build failed"
    make install > install.log 2>&1 || die "libtool install failed"
    ok "libltdl.so → $PREFIX/lib/"
}

# ============================================================
# 2. libusb (with Android FD support)
# ============================================================
build_libusb() {
    log "── libusb $LIBUSB_VER"
    [ -f "$PREFIX/lib/libusb-1.0.so" ] && { ok "already built — skip"; return; }

    cd "$SRC_DIR"
    [ -f "libusb-${LIBUSB_VER}.tar.bz2" ] || \
        wget -q "https://github.com/libusb/libusb/releases/download/v${LIBUSB_VER}/libusb-${LIBUSB_VER}.tar.bz2"

    rm -rf "libusb-${LIBUSB_VER}-${ABI}"
    tar -xjf "libusb-${LIBUSB_VER}.tar.bz2"
    mv "libusb-${LIBUSB_VER}" "libusb-${LIBUSB_VER}-${ABI}"
    cd "libusb-${LIBUSB_VER}-${ABI}"

    ./configure --host="$TARGET" --prefix="$PREFIX" \
        --enable-shared --disable-static \
        --disable-udev --enable-system-log \
        > configure.log 2>&1 || die "libusb configure failed"

    make -j$(nproc) > build.log 2>&1 || die "libusb build failed"
    make install > install.log 2>&1 || die "libusb install failed"
    ok "libusb-1.0.so → $PREFIX/lib/"
}

# ============================================================
# 3. libgphoto2 (with config.h patching for Android USB FD)
# ============================================================
build_libgphoto2() {
    log "── libgphoto2 $LIBGPHOTO2_VER"
    [ -f "$PREFIX/lib/libgphoto2.so" ] && [ -d "$PREFIX/lib/libgphoto2/$LIBGPHOTO2_VER" ] && \
        { ok "already built — skip"; return; }

    cd "$SRC_DIR"
    [ -f "libgphoto2-${LIBGPHOTO2_VER}.tar.bz2" ] || \
        wget -q "https://github.com/gphoto/libgphoto2/releases/download/v${LIBGPHOTO2_VER}/libgphoto2-${LIBGPHOTO2_VER}.tar.bz2"

    rm -rf "libgphoto2-${LIBGPHOTO2_VER}-${ABI}"
    tar -xjf "libgphoto2-${LIBGPHOTO2_VER}.tar.bz2"
    mv "libgphoto2-${LIBGPHOTO2_VER}" "libgphoto2-${LIBGPHOTO2_VER}-${ABI}"
    cd "libgphoto2-${LIBGPHOTO2_VER}-${ABI}"

    export LIBUSB_CFLAGS="-I$PREFIX/include/libusb-1.0"
    export LIBUSB_LIBS="-L$PREFIX/lib -lusb-1.0"
    export LTDLINCL="-I$PREFIX/include"
    export LIBLTDL="-L$PREFIX/lib -lltdl"

    ./configure --host="$TARGET" --prefix="$PREFIX" \
        --enable-shared --disable-static \
        --with-libgphoto2-port="$PREFIX" \
        --with-libusb="$PREFIX" \
        --with-ltdl-lib="$PREFIX/lib" --with-ltdl-include="$PREFIX/include" \
        --without-libxml-2.0 --without-gdlib --without-libjpeg \
        --disable-nls --disable-rpath \
        --disable-versioned-symbols --disable-symbol-versioning --disable-version-script \
        --with-camlibs="$CAMLIBS_SET" \
        > configure.log 2>&1 || die "libgphoto2 configure failed (see $PWD/configure.log)"

    # ⭐ Patch config.h to enable Android FD path in libgphoto2_port
    log "  patching config.h for Android USB FD"
    for cfg in config.h libgphoto2_port/config.h; do
        if [ -f "$cfg" ]; then
            cat >> "$cfg" <<EOF

/* === e4pix: Android USB FD support === */
#define HAVE_ANDROID 1
#define HAVE_LIBUSB_WRAP_SYS_DEVICE 1
#define HAVE_LIBUSB_OPTION_NO_DEVICE_DISCOVERY 1
EOF
        fi
    done

    make -j$(nproc) > build.log 2>&1 || die "libgphoto2 build failed (see $PWD/build.log)"
    make install > install.log 2>&1 || die "libgphoto2 install failed"
    ok "libgphoto2.so + camlibs → $PREFIX/lib/"
}

# ============================================================
# 4. FLAT copy with libcamlib_ / libiolib_ rename
# ============================================================
copy_flat() {
    log "── Flatten to $JNILIBS"

    # Wipe previous .so files (in case CAMLIBS_SET changed)
    rm -f "$JNILIBS"/*.so
    mkdir -p "$JNILIBS"

    # Main libs (already lib*.so)
    for f in libusb-1.0.so libltdl.so libgphoto2_port.so libgphoto2.so; do
        if [ -f "$PREFIX/lib/$f" ]; then
            cp "$PREFIX/lib/$f" "$JNILIBS/"
            ok "  $f"
        else
            warn "  $f NOT FOUND"
        fi
    done

    # Camlibs: ptp2.so → libcamlib_ptp2.so
    local cam_src="$PREFIX/lib/libgphoto2/$LIBGPHOTO2_VER"
    local cam_count=0
    if [ -d "$cam_src" ]; then
        for so in "$cam_src"/*.so; do
            [ -f "$so" ] || continue
            local base=$(basename "$so" .so)
            cp "$so" "$JNILIBS/libcamlib_${base}.so"
            cam_count=$((cam_count + 1))
        done
    fi
    ok "  $cam_count camlib(s) → libcamlib_*.so"

    # Iolibs: usb1.so → libiolib_usb1.so
    local io_ver=$(ls "$PREFIX/lib/libgphoto2_port/" 2>/dev/null | head -n1)
    local io_count=0
    if [ -n "$io_ver" ]; then
        for so in "$PREFIX/lib/libgphoto2_port/$io_ver"/*.so; do
            [ -f "$so" ] || continue
            local base=$(basename "$so" .so)
            cp "$so" "$JNILIBS/libiolib_${base}.so"
            io_count=$((io_count + 1))
        done
    fi
    ok "  $io_count iolib(s) → libiolib_*.so"

    # Strip
    "$STRIP" --strip-unneeded "$JNILIBS"/*.so 2>/dev/null || true

    # Headers (only on first ABI — they're arch-independent)
    if [ -d "$PREFIX/include/gphoto2" ] && [ ! -f "$HEADERS/gphoto2/gphoto2.h" ]; then
        log "── Copy headers to $HEADERS"
        rm -rf "$HEADERS"
        mkdir -p "$HEADERS/gphoto2"
        cp "$PREFIX/include/gphoto2/"*.h "$HEADERS/gphoto2/" 2>/dev/null || true
        ok "  $(ls "$HEADERS/gphoto2"/*.h 2>/dev/null | wc -l) headers"
    fi
}

# ============================================================
# Run
# ============================================================
build_libtool
build_libusb
build_libgphoto2
copy_flat

log "============================================"
ok "Build complete for $ABI"
log "============================================"
log ""
log "Files in $JNILIBS:"
ls -lh "$JNILIBS"/*.so 2>/dev/null | awk '{printf "  %-45s %s\n", $NF, $5}'
log ""
log "Total: $(du -sh "$JNILIBS" 2>/dev/null | cut -f1)"
log ""
log "Next:"
log "  cd $PROJECT_ROOT"
log "  flutter clean && flutter run -d <android-id>"

if [ "$ABI" = "arm64-v8a" ]; then
    log ""
    log "For emulator support, also run: ABI=x86_64 $0"
fi
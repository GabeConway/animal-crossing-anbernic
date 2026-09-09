#!/bin/bash
# Build OpenCrossing as a native ARMv7 webOS TV IPK.
#
# Prerequisites:
#   - webOS native ARMv7 toolchain from webosbrew/native-toolchain
#   - CMake + Ninja + ares-package
#   - SDL2 development files from the webOS SDL2 fork (webOS-2.30.x),
#     or an SDL2 install already present in the SDK/sysroot.
#
# Examples:
#   export WEBOS_SDK_ROOT=/opt/arm-webos-linux-gnueabi_sdk-buildroot
#   export WEBOS_SDL2_ROOT=$HOME/webos-deps/sdl-webos
#   ./build_webos.sh
#
# Optional:
#   WEBOS_GLESV2_LIBRARY=/path/to/libGLESv2.so
#   BUILD_JOBS=8

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/pc/build-webos"
STAGE_DIR="$BUILD_DIR/ipk-stage"
DIST_DIR="$ROOT_DIR/webos/dist"
TOOLCHAIN_FILE="$ROOT_DIR/pc/cmake/Toolchain-webos-armv7.cmake"

: "${WEBOS_SDK_ROOT:=/opt/arm-webos-linux-gnueabi_sdk-buildroot}"
: "${BUILD_JOBS:=$(nproc)}"

if ! command -v cmake >/dev/null 2>&1; then
    echo "ERROR: cmake is not installed." >&2
    exit 1
fi
if ! command -v ninja >/dev/null 2>&1; then
    echo "ERROR: ninja is not installed." >&2
    exit 1
fi
if ! command -v ares-package >/dev/null 2>&1; then
    echo "ERROR: ares-package is not installed (webOS CLI tools)." >&2
    exit 1
fi
if [ ! -f "$WEBOS_SDK_ROOT/share/buildroot/toolchainfile.cmake" ]; then
    echo "ERROR: webOS ARMv7 toolchain not found:" >&2
    echo "  $WEBOS_SDK_ROOT/share/buildroot/toolchainfile.cmake" >&2
    echo "Set WEBOS_SDK_ROOT to the extracted arm-webos-linux-gnueabi SDK." >&2
    exit 1
fi

export WEBOS_SDK_ROOT

# Keep CMake from accidentally finding a host SDL2/host GLES library.
export PKG_CONFIG_PATH="${WEBOS_SDL2_ROOT:+$WEBOS_SDL2_ROOT/lib/pkgconfig:}${PKG_CONFIG_PATH:-}"

CMAKE_ARGS=(
    -G Ninja
    -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN_FILE"
    -DCMAKE_BUILD_TYPE=Release
    -DPC_WEBOS=ON
    -DPC_USE_GLES=ON
)

if [ -n "${WEBOS_SDL2_ROOT:-}" ]; then
    CMAKE_ARGS+=("-DWEBOS_SDL2_ROOT=$WEBOS_SDL2_ROOT")
fi
if [ -n "${WEBOS_GLESV2_LIBRARY:-}" ]; then
    CMAKE_ARGS+=("-DWEBOS_GLESV2_LIBRARY=$WEBOS_GLESV2_LIBRARY")
fi

echo "=== Configuring OpenCrossing for webOS ARMv7/GLES ==="
cmake -S "$ROOT_DIR/pc" -B "$BUILD_DIR" "${CMAKE_ARGS[@]}"

echo "=== Building OpenCrossing ($BUILD_JOBS jobs) ==="
cmake --build "$BUILD_DIR" --parallel "$BUILD_JOBS"

BIN_DIR="$BUILD_DIR/bin"
if [ ! -x "$BIN_DIR/AnimalCrossing" ]; then
    echo "ERROR: Build completed without $BIN_DIR/AnimalCrossing" >&2
    exit 1
fi

# Stage the native app. The disc image is intentionally NOT bundled.
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/shaders" "$STAGE_DIR/rom" "$STAGE_DIR/texture_pack" "$STAGE_DIR/save"
cp "$BIN_DIR/AnimalCrossing" "$STAGE_DIR/AnimalCrossing"
cp "$BIN_DIR/shaders/default.vert" "$STAGE_DIR/shaders/default.vert"
cp "$BIN_DIR/shaders/default.frag" "$STAGE_DIR/shaders/default.frag"
cp "$BIN_DIR/shaders/shader_seed.bin" "$STAGE_DIR/shaders/shader_seed.bin"

cp "$ROOT_DIR/webos/appinfo.json" "$STAGE_DIR/appinfo.json"
cp "$ROOT_DIR/webos/settings.ini" "$STAGE_DIR/settings.ini"
cp "$ROOT_DIR/webos/icon.png" "$STAGE_DIR/icon.png"

mkdir -p "$DIST_DIR"
rm -f "$DIST_DIR"/*.ipk

echo "=== Packaging IPK ==="
# ares-package writes the generated package to the current working directory.
# Run it from the distribution directory so there is no ambiguity about the
# output path or the user's original working directory.
pushd "$DIST_DIR" >/dev/null
ares-package "$STAGE_DIR"
IPK_PATH="$(find "$DIST_DIR" -maxdepth 1 -type f -name '*.ipk' -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2- || true)"
popd >/dev/null

if [ -z "$IPK_PATH" ] || [ ! -f "$IPK_PATH" ]; then
    echo "ERROR: ares-package did not produce an IPK." >&2
    exit 1
fi

IPK_NAME="$(basename "$IPK_PATH")"

echo
echo "=== webOS build complete ==="
echo "Binary: $BIN_DIR/AnimalCrossing"
echo "IPK:    $DIST_DIR/$IPK_NAME"
echo
echo "The IPK contains no game disc image. Put your legally dumped GAFE01"
echo "Animal Crossing USA .iso/.gcm/.ciso into the installed app's rom/ directory."

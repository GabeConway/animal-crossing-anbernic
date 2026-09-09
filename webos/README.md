# OpenCrossing webOS 25 build

This target is a normal 32-bit ARMv7 native webOS application. It does **not** use the 64→32 bridge; that bridge is for AArch64 applications talking to the TV's existing 32-bit graphics stack.

## Toolchain

Use the ARMv7 SDK from:

https://github.com/webosbrew/native-toolchain

The expected CMake toolchain file is:

`$WEBOS_SDK_ROOT/share/buildroot/toolchainfile.cmake`

## SDL

Use the SDL2 `webOS-2.30.x` branch from:

https://github.com/webosbrew/SDL-webOS/tree/webOS-2.30.x

The SDL library is **not packaged into the IPK**. The TV supplies the runtime library; the local SDL-webOS prefix is used for development headers/linking.

## Build

```sh
export WEBOS_SDK_ROOT=/opt/arm-webos-linux-gnueabi_sdk-buildroot
export WEBOS_SDL2_ROOT=$HOME/webos-deps/sdl-webos
./build_webos.sh
```

Optional direct GLES library override:

```sh
export WEBOS_GLESV2_LIBRARY=/path/to/32-bit/libGLESv2.so
```

The resulting package is under `webos/dist/`.

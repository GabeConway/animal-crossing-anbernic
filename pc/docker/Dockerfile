# Build image for the OpenCrossing PC / Anbernic-handheld port.
#
# The build dependencies are identical across target architectures (the armhf
# device build and a native-arch local build differ only in compiler tuning
# flags), so a single Dockerfile serves both. The concrete platform is selected
# at build/run time with `--platform` by pc/docker-build.sh:
#   native -> host arch (e.g. linux/arm64 on Apple Silicon, linux/amd64 on x86)
#   armhf  -> linux/arm/v7  (Allwinner H700 / Cortex-A53 userland), via QEMU
#
# Building inside Linux sidesteps the macOS build blockers (no <malloc.h>, no
# Linux GLES/EGL headers) that stop the port from compiling on the host.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      gcc g++ cmake make pkg-config \
      libsdl2-dev libgles-dev \
      python3 \
      xvfb xauth libgl1-mesa-dri libegl1 libgl1-mesa-glx \
      ca-certificates file \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /work
ENTRYPOINT ["/bin/bash"]

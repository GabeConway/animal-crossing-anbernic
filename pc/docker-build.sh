#!/bin/bash
# Host-side Docker build pipeline for the OpenCrossing PC / Anbernic-handheld port.
#
# Why: the port cannot compile on macOS (no <malloc.h>, no Linux GLES/EGL). This
# drives a Debian container that has the right toolchain, with the repo bind-
# mounted, so builds are reproducible on any host with Docker.
#
# The port MUST be built 32-bit (JSystem casts pointers to u32), so both targets
# are 32-bit Linux:
#   i386    linux/386 build (quick local build/boot verification)
#   armhf   Allwinner H700 / Cortex-A53 device binary (linux/arm/v7)
# On Apple Silicon both run under Docker Desktop's QEMU emulation.
#
# Usage:
#   pc/docker-build.sh [i386|armhf] [options]
#
# Options:
#   --regen             re-run the menu-label overlay generator before building (issue #4)
#   --smoke             boot the built binary headlessly (xvfb) as a smoke test
#   --rom <dir>         mount <dir> (holding a .iso/.ciso/.gcm) into the container for --smoke
#   --jobs N            parallel make jobs (default: container nproc)
#   --shell             open an interactive container shell instead of building
#   --rebuild-image     force a rebuild of the builder image
#   -h, --help          show this help
#
# Examples:
#   pc/docker-build.sh                       # i386 build, verify the fix compiles+links
#   pc/docker-build.sh --regen               # + re-derive the menu-label overlay first
#   pc/docker-build.sh armhf                 # device binary for the handheld
#   pc/docker-build.sh i386 --smoke \
#     --rom "/Users/lennart/Documents/Development/animal crossing/output"   # boot the German disc
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET="i386"
REGEN=0 SMOKE=0 SHELL_MODE=0 REBUILD_IMAGE=0
JOBS="" ROM_DIR=""

usage() { sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    i386|armhf)       TARGET="$1" ;;
    --regen)          REGEN=1 ;;
    --smoke)          SMOKE=1 ;;
    --rom)            ROM_DIR="${2:?--rom needs a directory}"; shift ;;
    --jobs)           JOBS="${2:?--jobs needs a number}"; shift ;;
    --shell)          SHELL_MODE=1 ;;
    --rebuild-image)  REBUILD_IMAGE=1 ;;
    -h|--help)        usage 0 ;;
    *) echo "unknown arg: $1" >&2; usage 2 ;;
  esac
  shift
done

case "$TARGET" in
  i386)  PLATFORM="linux/386" ;;             # 32-bit x86 (quick verification)
  armhf) PLATFORM="linux/arm/v7" ;;          # 32-bit ARM device target
esac

IMAGE="opencrossing-build:${TARGET}"

# --- preflight: docker daemon ------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker CLI not found. Install Docker Desktop." >&2; exit 1
fi
if ! docker info >/dev/null 2>&1; then
  cat >&2 <<'EOF'
ERROR: the Docker daemon isn't running.

Start Docker Desktop, then re-run this script:
    open -a Docker            # macOS: launch Docker Desktop
    # wait until `docker info` succeeds (~30-60s), then:
    pc/docker-build.sh ...
EOF
  exit 1
fi

# Expanded below with the ${arr[@]+...} guard so it's safe under `set -u` even
# when empty (macOS bash 3.2 treats a bare "${empty[@]}" as an unbound variable).
PLAT_ARGS=()
[ -n "$PLATFORM" ] && PLAT_ARGS=(--platform "$PLATFORM")

# --- build the builder image (cached) ----------------------------------------
if [ "$REBUILD_IMAGE" = "1" ] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "=== building builder image: $IMAGE ${PLATFORM:+($PLATFORM)} ==="
  docker build ${PLAT_ARGS[@]+"${PLAT_ARGS[@]}"} -t "$IMAGE" "$REPO_ROOT/pc/docker"
fi

# --- assemble run args -------------------------------------------------------
RUN_ARGS=(--rm -v "$REPO_ROOT:/work" -w /work
          -e TARGET="$TARGET" -e REGEN="$REGEN" -e SMOKE="$SMOKE")
[ -n "$JOBS" ]    && RUN_ARGS+=(-e JOBS="$JOBS")
if [ -n "$ROM_DIR" ]; then
  ROM_ABS="$(cd "$ROM_DIR" && pwd)"
  RUN_ARGS+=(-v "$ROM_ABS:/rom:ro" -e ROM_DIR=/rom)
  echo "=== mounting ROM dir (read-only): $ROM_ABS -> /rom ==="
fi

if [ "$SHELL_MODE" = "1" ]; then
  echo "=== interactive shell in $IMAGE (repo at /work) ==="
  exec docker run -it ${PLAT_ARGS[@]+"${PLAT_ARGS[@]}"} "${RUN_ARGS[@]}" "$IMAGE"
fi

echo "=== running container build: target=$TARGET ==="
docker run ${PLAT_ARGS[@]+"${PLAT_ARGS[@]}"} "${RUN_ARGS[@]}" "$IMAGE" \
  /work/pc/docker/build-in-container.sh

echo
echo "=== DONE. Binary: pc/build-${TARGET}/bin/AnimalCrossing ==="

#!/bin/bash
# Runs INSIDE the Linux build container (see pc/docker/Dockerfile).
# Driven by pc/docker-build.sh on the host; you normally don't run this directly.
#
# Env inputs (all optional):
#   TARGET   armhf | i386     (default: i386)     -> compiler tuning (both 32-bit)
#   REGEN    0 | 1            (default: 0)         -> re-run menu-label overlay gen
#   SMOKE    0 | 1            (default: 0)         -> headless boot smoke test
#   JOBS     N               (default: nproc)      -> parallel make jobs
#   ROM_DIR  path                                  -> disc-image dir mounted at /rom
set -euo pipefail

TARGET="${TARGET:-i386}"
REGEN="${REGEN:-0}"
SMOKE="${SMOKE:-0}"
JOBS="${JOBS:-$(nproc)}"
BUILD_DIR="/work/pc/build-${TARGET}"

echo "=== OpenCrossing container build: target=${TARGET} jobs=${JOBS} ==="
uname -m

# The menu-command label overlay (issue #4) is committed to the tree, but
# --regen re-derives it (idempotent, needs no ROM) so the pipeline can prove the
# generator and the checked-in output agree.
if [ "$REGEN" = "1" ]; then
  echo "=== regenerating menu-command label overlay (gen_runtime_assets.py --tag-words) ==="
  python3 /work/pc/tools/gen_runtime_assets.py --tag-words
fi

case "$TARGET" in
  armhf)
    # Allwinner H700 = Cortex-A53 (armv7 userland) with NEON. NEON must be
    # enabled explicitly (Debian armhf gcc defaults to vfpv3-d16) for the
    # vectorized texture decoders and general auto-vectorization.
    TUNE="-fsigned-char -mcpu=cortex-a53 -mfpu=neon-vfpv4 -mfloat-abi=hard" ;;
  i386)
    # linux/386 image: gcc already targets 32-bit i686, no -m32 needed.
    # No global -O: this repo compiles decomp game code unoptimized on purpose
    # (see pc/CMakeLists.txt) -- proven TUs carry their own -O2/-O3 via
    # COMPILE_OPTIONS. A global -O2 here would re-optimize every un-annotated
    # decomp TU (miscompile-prone) and diverge from the armhf device build.
    TUNE="-fsigned-char" ;;
  *)
    echo "ERROR: unknown TARGET='$TARGET' (want armhf|i386)"; exit 2 ;;
esac

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo "=== cmake configure ==="
cmake .. -DPC_USE_GLES=ON \
  -DCMAKE_C_FLAGS="$TUNE" \
  -DCMAKE_CXX_FLAGS="$TUNE" 2>&1 | tail -15

echo "=== make ==="
# Capture make's real exit under `set -euo pipefail`: the trailing `|| RC=...`
# stops errexit from aborting here when the pipeline is non-zero -- whether make
# failed, or make succeeded but the grep filter matched nothing (grep exits 1).
# PIPESTATUS[0] is still make's status in that branch, so a grep-empty success
# correctly yields RC=0 and the error-context block below can actually run.
RC=0
make -j"$JOBS" 2>&1 | tee make.log | grep -E "^\[|Error|error:|Built target" | tail -60 || RC=${PIPESTATUS[0]}
echo "=== MAKE EXIT: $RC ==="
if [ "$RC" -ne 0 ]; then
  echo "=== ERROR CONTEXT ==="
  grep -B3 -A5 -E "error:|Error " make.log | tail -80
  exit "$RC"
fi

BIN="$BUILD_DIR/bin/AnimalCrossing"
echo "=== BUILT ==="
file "$BIN"
echo "=== NEEDED LIBS ==="
readelf -d "$BIN" 2>/dev/null | grep NEEDED || true

if [ "$SMOKE" = "1" ]; then
  echo "=== SMOKE TEST (headless boot) ==="
  RUN_DIR="$BUILD_DIR/bin"
  # find_disc_image() searches ./, orig/, rom/ of the working dir. Link any
  # disc image mounted at /rom into rom/ so the port can boot it.
  if [ -d /rom ]; then
    mkdir -p "$RUN_DIR/rom"
    for ext in iso ciso gcm ISO CISO GCM; do
      for f in /rom/*."$ext"; do [ -e "$f" ] && ln -sf "$f" "$RUN_DIR/rom/"; done
    done
    echo "disc images available to the port:"; ls -l "$RUN_DIR/rom/" || true
  else
    echo "(no /rom mounted; boot will stop at the 'no disc image' screen — expected)"
  fi
  cd "$RUN_DIR"
  xvfb-run -a timeout 60 ./AnimalCrossing --verbose 2>&1 | tail -60 || true
  echo "=== SMOKE DONE ==="
fi

echo "=== CONTAINER BUILD COMPLETE (target=$TARGET) ==="

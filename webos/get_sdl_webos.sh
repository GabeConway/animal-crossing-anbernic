#!/bin/bash
# Fetch the SDL2/webOS fork. This intentionally selects the SDL2 branch, not
# the current repository main branch (which has moved to SDL3).
set -euo pipefail

DEST="${1:-$HOME/webos-deps/SDL-webOS}"
mkdir -p "$(dirname "$DEST")"

if [ -d "$DEST/.git" ]; then
    git -C "$DEST" fetch --depth 1 origin webOS-2.30.x
    git -C "$DEST" checkout -q FETCH_HEAD
else
    git clone --depth 1 --branch webOS-2.30.x \
        https://github.com/webosbrew/SDL-webOS.git "$DEST"
fi

echo "SDL-webOS SDL2 source: $DEST"
echo "Build/install it with the webOS ARMv7 toolchain, then export:"
echo "  export WEBOS_SDL2_ROOT=<your SDL-webOS install prefix>"

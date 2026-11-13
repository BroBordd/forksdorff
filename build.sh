#!/bin/bash
# forksdorff build: host deps + toolchain bootstrap, then his stock pipeline (buildnoavb*.sh) and zip.
# Usage: ./build.sh [e|p]   p = permissive (default), e = enforcing
set -e
cd "$(dirname "$(readlink -f "$0")")"
ROOT=$(pwd)
PARENT_DIR=$(readlink -f "$ROOT/..")
VARIANT="${1:-p}"
case "$VARIANT" in
    e) SCRIPT=buildnoavb.sh ;;
    p) SCRIPT=buildnoavbp.sh ;;
    *) echo "Usage: $0 [e|p]" >&2; exit 1 ;;
esac

# 0. Host dependencies
export PATH="$PATH:/sbin:/usr/sbin"
need=""
for t in pahole brotli zip lz4 cpio zstd depmod mold python2; do
    command -v "$t" >/dev/null 2>&1 || need="$need $t"
done
if [ -n "$need" ]; then
    echo "[+] Installing missing tools:$need"
    SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"
    $SUDO apt-get update -y
    $SUDO apt-get install -y dwarves libelf-dev brotli zip lz4 cpio zstd kmod mold python2
fi

# 1. Toolchain (kernel_build/buildnoavb*.sh expects it at ../clang-r450784d)
if [ ! -x "$PARENT_DIR/clang-r450784d/bin/clang" ]; then
    echo "[+] Toolchain missing, cloning clang-r450784d..."
    git clone --depth=1 https://gitlab.com/tejas101k/clang-r450784d.git/ "$PARENT_DIR/clang-r450784d"
fi

# 2. Version tag: latest tag of this repo, else latest upstream (langsdorffkernel) tag, else "dev".
#    Override with XY_TAG=... ./build.sh
latest_tag() { sort -V | tail -n1; }
if [ -z "$XY_TAG" ]; then
    git fetch --tags --quiet origin 2>/dev/null || true
    XY_TAG=$(git tag | latest_tag)
fi
if [ -z "$XY_TAG" ]; then
    XY_TAG=$(git ls-remote --tags --refs https://github.com/clangsdorff/langsdorffkernel 2>/dev/null \
        | sed 's#.*refs/tags/##' | latest_tag)
fi
[ -n "$XY_TAG" ] || XY_TAG=dev
export XY_TAG

# 3. Build + pack (out-of-tree into ./out, zip/tar land in kernel_build/)
echo "[+] Building variant '$VARIANT' ($SCRIPT), tag $XY_TAG"
bash "$SCRIPT"

ls kernel_build/*_a14.zip

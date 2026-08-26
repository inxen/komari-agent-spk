#!/bin/bash
#
# build_spk_native.sh - build Synology SPKs using the Synology Toolkit
# natively (no Docker). Requires root (EnvDeploy + PkgCreate run in a chroot).
#
# Usage:
#   sudo ./tools/build_spk_native.sh [ARCHS...]
#
#   ARCHS    space separated arch families (default: x86_64 armv7 armv8)#
# Environment:
#   TOOLKIT_DIR      where pkgscripts-ng lives (default: /toolkit)
#   TARBALL_DIR      local directory with base_env-7.4.txz + ds.<plat>-7.4.{env,dev}.txz
#                    (default: $TOOLKIT_DIR/toolkit_tarballs). When present,
#                    EnvDeploy uses it instead of downloading.
#   DSM_VERSION      toolkit version (default: 7.4)
#   KEEP_CHROOT      if "1", keep the chroot after building (for debugging);
#                    default deletes each chroot after build to save disk.
#
# Each architecture maps to a representative chroot platform:
#   x86_64 -> avoton, armv7 -> alpine, armv8 -> rtd1296
#
# This replaces the old Docker-based build (tools/build_spk.sh + Dockerfile).

set -euo pipefail

TOOLKIT_DIR="${TOOLKIT_DIR:-/toolkit}"
PKGSCRIPTS="$TOOLKIT_DIR/pkgscripts-ng"
PROJECT=komari-agent
SOURCE_DIR_BASE="${SOURCE_DIR_BASE:-/source}"
DSM_VERSION="${DSM_VERSION:-7.4}"
TARBALL_DIR="${TARBALL_DIR:-$TOOLKIT_DIR/toolkit_tarballs}"
KEEP_CHROOT="${KEEP_CHROOT:-0}"

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
mkdir -p "$DIST_DIR"

# architecture family -> representative chroot platform
declare -A PLATFORM_BY_FAMILY=(
    [x86_64]=avoton
    [armv7]=alpine
    [armv8]=rtd1296
)

if [ $# -gt 0 ]; then
    ARCHS="$*"
else
    ARCHS="x86_64 armv7 armv8"
fi

if [ "$(id -u)" != "0" ]; then
    echo "ERROR: build_spk_native.sh must run as root (chroot build)." >&2
    exit 1
fi

if [ ! -d "$PKGSCRIPTS" ]; then
    echo "ERROR: pkgscripts-ng not found at $PKGSCRIPTS." >&2
    echo "  Clone it first:  git clone --depth 1 -b DSM7.4 https://github.com/SynologyOpenSource/pkgscripts-ng.git $PKGSCRIPTS" >&2
    exit 1
fi

# EnvDeploy looks for tarballs here; make sure they are readable.
mkdir -p "$TARBALL_DIR"

for family in $ARCHS; do
    platform="${PLATFORM_BY_FAMILY[$family]:-}"
    if [ -z "$platform" ]; then
        echo "==> [SKIP] Unsupported architecture family: $family"
        continue
    fi

    echo "==================================================================="
    echo "==> Building SPK for family '$family' (chroot platform: $platform)"
    echo "==================================================================="

    CHROOT="$TOOLKIT_DIR/build_env/ds.${platform}-${DSM_VERSION}"

    # 1. Deploy the chroot build environment. Use local tarballs only if ALL
    #    tarballs needed for THIS platform are present (-t disables downloading,
    #    so a partial cache would otherwise break the deployment).
    if [ -d "$CHROOT/bin" ] && [ -x "$CHROOT/bin/sh" ]; then
        echo "==> Build environment for $platform already deployed"
    else
        NEEDED=(
            "base_env-${DSM_VERSION}.txz"
            "ds.${platform}-${DSM_VERSION}.env.txz"
            "ds.${platform}-${DSM_VERSION}.dev.txz"
        )
        HAVE_ALL=1
        for f in "${NEEDED[@]}"; do
            [ -f "$TARBALL_DIR/$f" ] || { echo "==> Missing local tarball: $f"; HAVE_ALL=0; }
        done
        echo "==> Deploying build environment for $platform (DSM $DSM_VERSION)"
        if [ "$HAVE_ALL" = "1" ]; then
            (cd "$PKGSCRIPTS" && ./EnvDeploy -v "$DSM_VERSION" -p "$platform" -t "$TARBALL_DIR" -q)
        else
            (cd "$PKGSCRIPTS" && ./EnvDeploy -v "$DSM_VERSION" -p "$platform" -q)
        fi
    fi

    # 2. Copy pkgscripts-ng and the project into the chroot.
    mkdir -p "$CHROOT/pkgscripts-ng" "$CHROOT/source"
    cp -a "$PKGSCRIPTS/." "$CHROOT/pkgscripts-ng/"
    rm -rf "$CHROOT/source/$PROJECT"
    mkdir -p "$CHROOT/source/$PROJECT"
    # Copy project, excluding local caches. downloads/ IS copied because
    # SynoBuildConf/install needs the agent binary from it.
    tar -C "$PROJECT_ROOT" \
        --exclude='./toolkit-cache' --exclude='./dist' --exclude='./.git' \
        -cf - . | tar -C "$CHROOT/source/$PROJECT" -xf -
    chmod +x "$CHROOT/source/$PROJECT"/scripts/* \
        "$CHROOT/source/$PROJECT"/SynoBuildConf/* \
        "$CHROOT/source/$PROJECT"/INFO.sh \
        "$CHROOT/source/$PROJECT"/tools/*.sh 2>/dev/null || true

    # 3. Build the SPK (Pack Stage only via -i).
    echo "==> Running PkgCreate.py -i $PROJECT (platform=$platform, DSM=$DSM_VERSION)"
    if ! (cd "$TOOLKIT_DIR" && "$PKGSCRIPTS/PkgCreate.py" -i "$PROJECT" -p "$platform" -v "$DSM_VERSION") \
        > "$PROJECT_ROOT/pkgcreate-$family.log" 2>&1; then
        echo "PkgCreate failed for $family. Last 60 lines of log:" >&2
        tail -60 "$PROJECT_ROOT/pkgcreate-$family.log" >&2
        exit 1
    fi
    rm -f "$PROJECT_ROOT/pkgcreate-$family.log"

    # 4. Collect the non-debug SPK.
    find "$CHROOT/image/packages" -maxdepth 1 -name '*.spk' ! -name '*_debug.spk' -print0 2>/dev/null | \
        xargs -0 -r -I{} cp -f {} "$DIST_DIR/" 2>/dev/null || true
    chown "$(stat -c %u:%g "$PROJECT_ROOT")" "$DIST_DIR"/*.spk 2>/dev/null || true

    # 5. Cleanup the chroot (unmount anything still bound, then delete) unless
    #    KEEP_CHROOT=1. Saves ~6GB per arch on disk.
    if [ "$KEEP_CHROOT" != "1" ]; then
        echo "==> Cleaning up chroot for $platform"
        for m in $(mount | grep "$CHROOT" | awk '{print $3}' | sort -r); do
            umount "$m" 2>/dev/null || true
        done
        rm -rf "$CHROOT"
    fi
done

echo "==> Finished. SPK artifacts in $DIST_DIR:"
ls -l "$DIST_DIR"/*.spk 2>/dev/null || echo "  (none produced)"
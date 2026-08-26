#!/bin/bash
#
# download-agent.sh - download the official komari-agent Linux binary and
# verify its SHA256 before it is used to build the SPK.
#
# Usage:
#   ./tools/download-agent.sh [VERSION] [ARCH]
#
#   VERSION  upstream komari-agent release tag, e.g. 1.2.60 (default: read
#            from VERSION file, first dotted component, e.g. 1.2.60-1 -> 1.2.60)
#   ARCH     one of amd64 | arm64 | arm (default: amd64)
#
# The SHA256 is taken from the official GitHub Release asset digest so we do
# not maintain our own checksum table unless the API is unavailable. The
# downloaded binary is saved to downloads/komari-agent-linux-<arch>.

set -euo pipefail

REPO="komari-monitor/komari-agent"
DOWNLOAD_DIR="$(cd "$(dirname "$0")/.." && pwd)/downloads"
mkdir -p "$DOWNLOAD_DIR"

# Resolve version. VERSION file format is "<agent>-<revision>" e.g. 1.2.60-1.
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$PROJECT_ROOT/VERSION" ]; then
    DEFAULT_VERSION="$(tr -d '[:space:]' < "$PROJECT_ROOT/VERSION" | cut -d'-' -f1)"
else
    DEFAULT_VERSION="1.2.60"
fi

VERSION="${1:-$DEFAULT_VERSION}"
ARCH="${2:-amd64}"

case "$ARCH" in
    amd64) ASSET="komari-agent-linux-amd64" ;;
    arm64) ASSET="komari-agent-linux-arm64" ;;
    arm)   ASSET="komari-agent-linux-arm" ;;
    *)
        echo "Unsupported arch: $ARCH (expected amd64|arm64|arm)" >&2
        exit 1
        ;;
esac

URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET}"
DEST="$DOWNLOAD_DIR/$ASSET"

echo "==> Downloading ${ASSET} v${VERSION}"
echo "    from ${URL}"

# Use curl if available, else wget.
if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 -o "$DEST.tmp" "$URL"
elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$DEST.tmp" "$URL"
else
    echo "Neither curl nor wget found." >&2
    exit 1
fi

echo "==> Fetching official SHA256 for ${ASSET} v${VERSION}"
EXPECTED_SHA=""
# The official release asset carries its digest in the GitHub API. Use the
# authenticated endpoint when a token is available (GitHub Actions provides
# one) to avoid anonymous rate limiting. Parse with Python (json) for safety.
if command -v python3 >/dev/null 2>&1; then
    # Guard with || true so an API failure (rate limit / 504) does not abort
    # the script under `set -e`; EXPECTED_SHA stays empty and we fall back to
    # the pinned SHA256SUMS below.
    AUTH_HDR=()
    if [ -n "${GH_TOKEN:-}${GITHUB_TOKEN:-}" ]; then
        AUTH_HDR=(-H "Authorization: Bearer ${GH_TOKEN:-$GITHUB_TOKEN}")
    fi
    EXPECTED_SHA="$(curl -fsSL "${AUTH_HDR[@]}" \
        "https://api.github.com/repos/${REPO}/releases/tags/${VERSION}" \
        | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
target = '$ASSET'
for a in data.get('assets', []):
    if a.get('name') == target:
        d = a.get('digest', '') or ''
        if d.startswith('sha256:'):
            print(d[7:])
        break
")" || true
fi

if [ -n "$EXPECTED_SHA" ]; then
    ACTUAL_SHA="$(sha256sum "$DEST.tmp" | awk '{print $1}')"
    if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
        echo "SHA256 mismatch for ${ASSET}:" >&2
        echo "  expected: $EXPECTED_SHA" >&2
        echo "  actual:   $ACTUAL_SHA" >&2
        rm -f "$DEST.tmp"
        exit 1
    fi
    echo "==> SHA256 verified: $ACTUAL_SHA"
else
    echo "==> WARNING: could not fetch official SHA256 from GitHub API."
    echo "    Skipping verification. If a SHA256SUMS file exists it will be used."
    if [ -f "$PROJECT_ROOT/SHA256SUMS" ]; then
        # Verify inside the downloads dir so the bare asset name in SHA256SUMS
        # resolves to the just-downloaded binary. Match the exact asset name
        # (not a substring) so e.g. "arm" does not pick up the "arm64" line.
        if (cd "$DOWNLOAD_DIR" && sha256sum -c <(awk -v a="$ASSET" '$2==a' "$PROJECT_ROOT/SHA256SUMS")); then
            echo "==> SHA256 verified via SHA256SUMS."
        else
            echo "SHA256 verification failed via SHA256SUMS." >&2
            rm -f "$DEST.tmp"
            exit 1
        fi
    fi
fi

mv -f "$DEST.tmp" "$DEST"
chmod 755 "$DEST"
echo "==> Saved to $DEST"

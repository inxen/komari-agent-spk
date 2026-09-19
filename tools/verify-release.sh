#!/bin/bash
#
# verify-release.sh - pre-flight check that an upstream komari-agent release
# exists and carries every Linux asset the SPK build needs.
#
# Usage:
#   ./tools/verify-release.sh [VERSION]
#
#   VERSION  upstream release tag, e.g. 1.5.11 (default: read from the VERSION
#            file, the part before the first '-', e.g. 1.2.60-1 -> 1.2.60)
#
# Why this exists: without it, a typo in the workflow's `version` input (or a
# tag that has no Linux assets yet) only surfaces as a bare
# "curl: (22) The requested URL returned error: 404" from download-agent.sh a
# second later, with nothing to say *which* version was wrong or what is
# available. Here we fail before downloading anything and print the recent
# upstream tags so a valid one can be picked.
#
# Exit: 0 = all required assets present, 1 = missing / unavailable.

set -euo pipefail

REPO="komari-monitor/komari-agent"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

DEFAULT_VERSION="$(tr -d '[:space:]' < "$PROJECT_ROOT/VERSION" | cut -d'-' -f1)"
VERSION="${1:-$DEFAULT_VERSION}"

# "latest" -> newest upstream x.y.z that can actually be packaged.
if [ "$(printf '%s' "$VERSION" | tr '[:upper:]' '[:lower:]')" = "latest" ]; then
    VERSION="$(bash "$PROJECT_ROOT/tools/latest-version.sh")"
    echo "==> 'latest' resolved to ${VERSION}"
fi

# The three Linux assets consumed by the SPK build:
#   amd64 -> Synology x86_64, arm64 -> armv8, arm -> armv7
REQUIRED_ASSETS=(
    "komari-agent-linux-amd64"
    "komari-agent-linux-arm64"
    "komari-agent-linux-arm"
)

API="https://api.github.com/repos/${REPO}"

# Retry connection problems and 5xx, but NOT 404 - a wrong tag should fail fast.
CURL_OPTS=(-fsS --retry 3 --retry-delay 1 --retry-connrefused --connect-timeout 20)

# Use the token when the runner provides one (higher rate limit), else anonymous.
HDR=(-H "Accept: application/vnd.github+json")
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -n "$TOKEN" ]; then
    HDR+=(-H "Authorization: Bearer ${TOKEN}")
fi

TMP_JSON="$(mktemp)"
# `|| true`: a failing EXIT trap would otherwise become the script's exit
# status and turn a successful check into a reported failure.
trap 'rm -f "$TMP_JSON" 2>/dev/null || true' EXIT

list_recent_tags() {
    echo "Recent upstream ${REPO} releases:"
    if ! curl "${CURL_OPTS[@]}" "${HDR[@]}" "${API}/releases?per_page=10" \
        | python3 -c '
import json
import sys

try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)

for rel in data:
    print("  - " + str(rel.get("tag_name", "")))
'; then
        echo "  (could not query the GitHub API)"
    fi
}

echo "==> Verifying upstream release ${REPO}@${VERSION}"

if ! curl "${CURL_OPTS[@]}" "${HDR[@]}" -o "$TMP_JSON" "${API}/releases/tags/${VERSION}"; then
    echo "ERROR: upstream release tag '${VERSION}' is not available." >&2
    list_recent_tags >&2
    echo "Use one of the tags above as the workflow's 'version' input" >&2
    echo "(a leading 'v' and a trailing '-<rev>' are also accepted)." >&2
    exit 1
fi

missing=0
for asset in "${REQUIRED_ASSETS[@]}"; do
    if python3 -c '
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    data = json.load(fh)

names = {a.get("name") for a in data.get("assets", [])}
sys.exit(0 if sys.argv[2] in names else 1)
' "$TMP_JSON" "$asset"; then
        echo "    ok      ${asset}"
    else
        echo "    MISSING ${asset}" >&2
        missing=1
    fi
done

if [ "$missing" -ne 0 ]; then
    echo "ERROR: release ${VERSION} is missing required Linux assets." >&2
    echo "       Upstream may still be uploading them; retry in a few minutes." >&2
    exit 1
fi

echo "==> OK: all required assets present for ${VERSION}"

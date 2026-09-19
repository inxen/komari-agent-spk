#!/bin/bash
#
# latest-version.sh - print the newest upstream komari-agent release that can
# actually be packaged, i.e. a plain "x.y.z" tag.
#
# Usage:
#   ./tools/latest-version.sh
#
# Prints the version on stdout (e.g. 1.5.11). Exit 1 if it cannot be
# determined, so callers can fail instead of building the wrong thing.
#
# Why not the GitHub "/releases/latest" pointer: upstream also publishes
# rolling "Snapshot-<timestamp>" releases. Filtering for a non-draft,
# non-prerelease "x.y.z" tag is what we actually need, and it stays correct
# even if a snapshot is ever published as a normal release.
#
# Used by the build workflow to resolve a `version: latest` dispatch input and
# by tools/verify-release.sh when it is handed "latest".

set -euo pipefail

REPO="komari-monitor/komari-agent"
API="https://api.github.com/repos/${REPO}"

CURL_OPTS=(-fsS --retry 3 --retry-delay 1 --retry-connrefused --connect-timeout 20)

# Use the token when one is available (higher rate limit), else anonymous.
HDR=(-H "Accept: application/vnd.github+json")
TOKEN="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
if [ -n "$TOKEN" ]; then
    HDR+=(-H "Authorization: Bearer ${TOKEN}")
fi

# Numeric ordering is done in Python so that 1.10.0 sorts above 1.9.2.
if ! curl "${CURL_OPTS[@]}" "${HDR[@]}" "${API}/releases?per_page=100" \
    | python3 -c '
import json
import re
import sys

SEMVER = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")

try:
    releases = json.load(sys.stdin)
except Exception:
    sys.exit(2)

best = None
best_key = None
for rel in releases:
    if rel.get("draft") or rel.get("prerelease"):
        continue
    match = SEMVER.match(str(rel.get("tag_name") or ""))
    if not match:
        continue
    key = tuple(int(part) for part in match.groups())
    if best_key is None or key > best_key:
        best_key = key
        best = match.group(0)

if best is None:
    sys.exit(3)

print(best)
'; then
    echo "ERROR: could not determine the latest upstream release of ${REPO}." >&2
    echo "       Check network access to the GitHub API, or pass an explicit version." >&2
    exit 1
fi

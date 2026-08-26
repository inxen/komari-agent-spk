#!/bin/bash
#
# tests/check_static.sh - static and packaging checks for the Komari Agent SPK.
#
# These checks run without a DSM or the Synology Toolkit:
#   1. SPK / INFO / package.tgz / scripts presence
#   2. start-stop-status and agent binary executability
#   3. architecture check (file) that the binary inside the SPK matches the
#      package architecture
#   4. shellcheck on scripts/* and tools/* (if shellcheck is installed)
#   5. SPK unpack test (tar) inspecting INFO, package.tgz, scripts
#   6. agent smoke test (--help / --version) if a local binary is present
#
# Usage: bash tests/check_static.sh [DIST_DIR]

set -u

DIST_DIR="${1:-dist}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT" || exit 1

FAILED=0
ok()   { echo "[PASS] $1"; }
bad()  { echo "[FAIL] $1"; FAILED=1; }

echo "==== Komari Agent SPK static checks ===="

# ---- 1. Artifacts present ------------------------------------------------
echo "---- 1. Package artifacts ----"
if compgen -G "$DIST_DIR/*.spk" > /dev/null; then
    SPK_FILE=$(ls "$DIST_DIR"/*.spk | head -n1)
    ok "SPK exists: $SPK_FILE"
else
    bad "No .spk found in $DIST_DIR/"
    echo "  (Run 'make package' or place a built SPK in $DIST_DIR/)"
fi

[ -f "VERSION" ] && ok "VERSION exists" || bad "VERSION missing"
[ -f "config/config.example.json" ] && ok "config.example.json exists" || bad "config.example.json missing"

for s in preinst postinst preuninst postuninst preupgrade postupgrade start-stop-status; do
    if [ -f "scripts/$s" ]; then
        ok "scripts/$s exists"
    else
        bad "scripts/$s missing"
    fi
done

# ---- 2. Executability ------------------------------------------------------
echo "---- 2. Executability ----"
if [ -f "scripts/start-stop-status" ]; then
    [ -x "scripts/start-stop-status" ] && ok "start-stop-status is executable" \
        || bad "start-stop-status is NOT executable"
else
    bad "scripts/start-stop-status missing"
fi

if compgen -G "$DIST_DIR/*.spk" > /dev/null; then
    SPK_FILE=$(ls "$DIST_DIR"/*.spk | head -n1)

    # ---- 3. SPK unpack test ----------------------------------------------
    echo "---- 3. SPK unpack test ----"
    TMPDIR=$(mktemp -d)
    tar -xf "$SPK_FILE" -C "$TMPDIR" 2>/dev/null \
        && ok "SPK unpacks with tar" || { bad "SPK unpack failed"; }

    if [ -f "$TMPDIR/INFO" ]; then
        ok "SPK contains INFO"
        echo "    INFO: $(tr '\n' ' ' < "$TMPDIR/INFO")"
    else
        bad "SPK missing INFO"
    fi
    if [ -f "$TMPDIR/package.tgz" ]; then
        ok "SPK contains package.tgz"
        # inspect the inner package
        PKG_TMPDIR=$(mktemp -d)
        # package.tgz is xz-compressed by pkg_make_package; tar auto-detects.
        tar -xf "$TMPDIR/package.tgz" -C "$PKG_TMPDIR" 2>/dev/null && ok "package.tgz unpacks" \
            || bad "package.tgz unpack failed"
        if [ -f "$PKG_TMPDIR/bin/komari-agent" ]; then
            ok "package.tgz contains bin/komari-agent"
            [ -x "$PKG_TMPDIR/bin/komari-agent" ] && ok "agent binary is executable" \
                || bad "agent binary not executable inside package.tgz"

            # ---- 4. Architecture check ------------------------------------
            echo "---- 4. Architecture check (file) ----"
            if command -v file >/dev/null 2>&1; then
                BIN_INFO=$(file "$PKG_TMPDIR/bin/komari-agent")
                echo "    $BIN_INFO"
                case "$SPK_FILE" in
                    *x86_64*)
                        echo "$BIN_INFO" | grep -qi "x86-64" && ok "binary is x86-64 (matches x86_64 SPK)" \
                            || bad "binary arch does not match x86_64 SPK"
                        ;;
                    *armv8*)
                        echo "$BIN_INFO" | grep -Eqi "aarch64|ARM aarch64" && ok "binary is aarch64 (matches armv8 SPK)" \
                            || bad "binary arch does not match armv8 SPK"
                        ;;
                    *armv7*)
                        # armv7 SPK must contain a 32-bit ARM binary.
                        echo "$BIN_INFO" | grep -Eqi "ELF 32-bit.*ARM|ARM, EABI" && ok "binary is 32-bit ARM (matches armv7 SPK)" \
                            || bad "binary arch does not match armv7 SPK"
                        ;;
                esac
            else
                echo "    (file command not available, skipping arch check)"
            fi
        else
            bad "package.tgz missing bin/komari-agent"
        fi
        rm -rf "$PKG_TMPDIR"
    else
        bad "SPK missing package.tgz"
    fi
    if [ -d "$TMPDIR/scripts" ]; then
        ok "SPK contains scripts/"
    else
        bad "SPK missing scripts/"
    fi
    rm -rf "$TMPDIR"
else
    echo "---- 3/4/5/6. Skipped (no SPK to unpack) ----"
fi

# ---- 5. Shell lint (optional) ----------------------------------------------
echo "---- 5. Shell lint ----"
if command -v shellcheck >/dev/null 2>&1; then
    if shellcheck scripts/* tools/*.sh INFO.sh 2>/dev/null; then
        ok "shellcheck passed on scripts/ and tools/"
    else
        bad "shellcheck reported issues (see above)"
    fi
else
    echo "    (shellcheck not installed, skipping)"
fi

# ---- 6. Agent smoke test (local binary) ------------------------------------
echo "---- 6. Agent smoke test ----"
if compgen -G "downloads/komari-agent-linux-*" > /dev/null; then
    LOCAL_BIN=$(ls downloads/komari-agent-linux-* | head -n1)
    echo "    Testing local binary: $LOCAL_BIN"
    # Only run --help/--version if we can execute it (must match host arch).
    if [ -x "$LOCAL_BIN" ]; then
        if "$LOCAL_BIN" --help >/dev/null 2>&1; then
            ok "agent --help runs"
        else
            bad "agent --help failed (may be foreign arch on this host)"
        fi
        if "$LOCAL_BIN" --version >/dev/null 2>&1; then
            VER=$("$LOCAL_BIN" --version 2>&1)
            ok "agent --version: $VER"
        else
            echo "    (agent --version not supported or foreign arch)"
        fi
    else
        echo "    (binary not executable on this host - likely foreign architecture)"
    fi
else
    echo "    (no local binary in downloads/, skipping)"
fi

echo "======================================================"
if [ "$FAILED" = "0" ]; then
    echo "All static checks passed."
else
    echo "Some static checks FAILED."
fi
exit $FAILED

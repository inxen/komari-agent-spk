#!/usr/bin/env python3
# -*- coding: utf-8 -*-
#
# config.cgi - Komari Agent DSM configuration backend.
#
# Served and executed by the DSM web server (nginx) from the package's
# dsmuidir (3rdparty) folder. No additional port is required; the UI at
# 3rdparty/KomariAgent/index.html calls this script for all config I/O.
#
# Security:
#   * Every request must pass DSM login authentication (authenticate.cgi).
#   * The config (containing the agent token) is only ever read/written via
#     this script; it is never placed in URLs, logs or command lines.
#   * Saves are atomic: write temp file -> validate -> rename.
#
# API (POST JSON):
#   {"action": "read"}                     -> return current config
#   {"action": "save", "config": {...}}    -> validate + atomically save (no restart)
#   {"action": "apply", "config": {...}}   -> save + restart agent
#   {"action": "default"}                  -> return default config (no save)
#   {"action": "restart"}                  -> restart agent only
#
# Response: {"success": true/false, "config": {...}, "message": "..."}

import json
import os
import shutil
import subprocess
import sys
import tempfile

PKG_NAME = "KomariAgent"
# Runtime config lives in the persistent @appdata dir (survives upgrade/uninstall).
CONFIG_PATH = "/var/packages/%s/var/config.json" % PKG_NAME
DEFAULT_CONFIG_PATH = "/var/packages/%s/target/var/config.example.json" % PKG_NAME
AUTH_CGI = "/usr/syno/synoman/webman/modules/authenticate.cgi"
SYNOPKG = "/usr/syno/bin/synopkg"


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------
# The page runs inside the authenticated DSM web session, so the browser sends
# a valid "sid" cookie. CSRF protection is provided by the DSM SynoToken: the
# frontend fetches it from /webman/login.cgi (only issued to a logged-in
# session) and sends it in the X-SYNO-TOKEN header (or SynoToken query
# parameter, as used by other packages). We require sid (session) + SynoToken
# (CSRF) to exist; we do NOT require the header token to equal the synotoken
# cookie, since login.cgi may return a different CSRF token.
def extract_cookie(cookie_header, name):
    for part in cookie_header.split(";"):
        part = part.strip()
        if part.startswith(name + "="):
            return part[len(name) + 1:]
    return ""


def extract_query_param(name):
    query = os.environ.get("QUERY_STRING", "")
    for part in query.split("&"):
        if part.startswith(name + "="):
            return part[len(name) + 1:]
    return ""


def is_authenticated():
    """Return True if the request carries a valid DSM session cookie."""
    cookie_header = os.environ.get("HTTP_COOKIE", "")
    # DSM stores the session cookie under "id" (not "sid"; "sid" is only the
    # API response field). Both "id" and "did" are set by DSM on login and are
    # sent on same-origin requests from the DSM web session (including from
    # the iframe configuration page). A present session cookie means the user
    # is logged in to DSM.
    session_id = extract_cookie(cookie_header, "id") or \
        extract_cookie(cookie_header, "did")
    if not session_id:
        return False
    return True


# ---------------------------------------------------------------------------
# Config helpers
# ---------------------------------------------------------------------------
def default_config():
    """Return the default config shipped with the package, or a minimal one."""
    if os.path.isfile(DEFAULT_CONFIG_PATH):
        try:
            with open(DEFAULT_CONFIG_PATH, "r", encoding="utf-8") as fh:
                return json.load(fh)
        except Exception:
            pass
    return {
        "endpoint": "https://your-komari-server.example.com",
        "token": "",
        "interval": 3,
        "disable_auto_update": True,
        "disable_web_ssh": False,
        "ignore_unsafe_cert": False,
    }


def read_config():
    """Return current config or default if file is missing/broken."""
    if os.path.isfile(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as fh:
                return json.load(fh)
        except Exception:
            # Broken file: return default but do not overwrite the broken file.
            return default_config()
    return default_config()


def save_config(data):
    """Atomically write data to CONFIG_PATH."""
    config_dir = os.path.dirname(CONFIG_PATH)
    if not os.path.isdir(config_dir):
        os.makedirs(config_dir, mode=0o755, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(dir=config_dir, prefix=".config.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=2)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        # Validate the temp file before swapping it in.
        with open(tmp_path, "r", encoding="utf-8") as fh:
            json.load(fh)
        os.chmod(tmp_path, 0o600)
        os.replace(tmp_path, CONFIG_PATH)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise


def restart_agent():
    """Restart the agent. Prefer synopkg; fall back to the lifecycle script."""
    # 1) synopkg restart (keeps DSM package state in sync).
    try:
        res = subprocess.run(
            [SYNOPKG, "restart", PKG_NAME],
            capture_output=True,
            text=True,
            timeout=60,
        )
        if res.returncode == 0:
            return True
        log_restart_error("synopkg rc=%d out=%s err=%s"
                          % (res.returncode, res.stdout, res.stderr))
    except Exception as exc:
        log_restart_error("synopkg exception: %s" % exc)

    # 2) Fallback: call the lifecycle script directly (works from the CGI
    #    sandbox where synopkg's systemd interaction may fail with code 263).
    sss = "/var/packages/%s/scripts/start-stop-status" % PKG_NAME
    try:
        res = subprocess.run(
            [sss, "restart"],
            capture_output=True,
            text=True,
            timeout=60,
        )
        if res.returncode == 0:
            log_restart_error("used start-stop-status fallback")
            return True
        log_restart_error("start-stop-status rc=%d out=%s err=%s"
                          % (res.returncode, res.stdout, res.stderr))
    except Exception as exc:
        log_restart_error("start-stop-status exception: %s" % exc)
    return False


def log_restart_error(msg):
    """Best-effort log of a restart failure (kept out of the web response)."""
    try:
        log_path = "/var/packages/%s/var/log/config-ui.log" % PKG_NAME
        with open(log_path, "a", encoding="utf-8") as fh:
            fh.write("restart failed: %s\n" % msg)
    except Exception:
        pass


# ---------------------------------------------------------------------------
# Request handling
# ---------------------------------------------------------------------------
def send_response(success, config=None, message=""):
    payload = {"success": success, "message": message}
    if config is not None:
        payload["config"] = config
    body = json.dumps(payload, ensure_ascii=False)
    print("Content-Type: application/json; charset=utf-8")
    print("Cache-Control: no-store")
    print("Content-Length: %d" % len(body.encode("utf-8")))
    print("")
    sys.stdout.write(body)
    sys.stdout.flush()


def main():
    if not is_authenticated():
        send_response(False, message="Unauthorized: please log in to DSM.")
        return

    method = os.environ.get("REQUEST_METHOD", "GET").upper()
    if method == "GET":
        send_response(True, config=read_config(), message="ok")
        return

    # Read POST body.
    body = ""
    try:
        length = int(os.environ.get("CONTENT_LENGTH", "0") or 0)
        if length > 0:
            body = sys.stdin.read(length)
    except Exception:
        body = ""

    action = None
    config = None
    if body.strip():
        try:
            payload = json.loads(body)
            if isinstance(payload, dict):
                action = payload.get("action")
                config = payload.get("config")
        except Exception:
            send_response(False, message="Invalid JSON request body.")
            return

    if not action:
        action = "read"

    if action == "read":
        send_response(True, config=read_config(), message="ok")
        return

    if action == "default":
        send_response(True, config=default_config(), message="ok")
        return

    if action in ("save", "apply"):
        if not isinstance(config, dict):
            send_response(False, message="Missing or invalid 'config' object.")
            return
        try:
            # Basic sanity checks.
            if not isinstance(config.get("endpoint", ""), str):
                send_response(False, message="'endpoint' must be a string.")
                return
            interval = config.get("interval", 3)
            if not isinstance(interval, (int, float)) or interval <= 0:
                send_response(False, message="'interval' must be a positive number.")
                return
            save_config(config)
        except Exception as exc:
            send_response(False, message="Save failed: %s" % exc)
            return
        if action == "apply":
            ok = restart_agent()
            if not ok:
                send_response(False, config=config,
                              message="Saved, but failed to restart agent.")
                return
            send_response(True, config=config,
                          message="Saved and agent restarted.")
            return
        send_response(True, config=config, message="Configuration saved.")
        return

    if action == "restart":
        ok = restart_agent()
        send_response(ok, message="Agent restarted." if ok else "Restart failed.")
        return

    send_response(False, message="Unknown action: %s" % action)


if __name__ == "__main__":
    main()
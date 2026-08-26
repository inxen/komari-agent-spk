#!/bin/bash
#
# wizard-config.sh - shared helpers to apply DSM wizard values into the agent
# config.json. Sourced by postinst / postupgrade.
#
# The DSM Package Center exposes wizard fields as environment variables named
# wizard_* (from WIZARD_UIFILES/*). This file provides:
#   apply_wizard_config <config_file>
# which writes/updates the relevant keys from those environment variables.

# JSON-escape a string value (backslash and double quote).
json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Append a key:value pair ($1=file, $2=key, $3=raw json value) to a JSON
# object, inserting the pair right before the closing brace. Handles both
# pretty-printed (multi-line) and single-line JSON.
json_append() {
    local file="$1" key="$2" val="$3"
    local tmp="${file}.$$"
    awk -v k="$key" -v v="$val" '
        {
            content = content $0 "\n"
        }
        END {
            # Locate the last closing brace.
            pos = 0
            for (i = length(content); i >= 1; i--) {
                if (substr(content, i, 1) == "}") { pos = i; break }
            }
            if (pos <= 0) {
                printf "%s  \"%s\": %s\n}\n", content, k, v
                exit
            }
            head = substr(content, 1, pos - 1)
            tail = substr(content, pos)
            sub(/[[:space:]]+$/, "", head)
            # Empty object (just "{"): no leading comma needed.
            compact = head
            gsub(/[[:space:]]/, "", compact)
            if (compact == "{") {
                printf "%s\n  \"%s\": %s\n%s", head, k, v, tail
            } else {
                printf "%s,\n  \"%s\": %s\n%s", head, k, v, tail
            }
        }
    ' "$file" > "$tmp" && mv "$tmp" "$file"
}

# Set or add a string key in a flat config.json ($1=file, $2=key, $3=value).
json_set_str() {
    local file="$1" key="$2" val="$3" esc
    esc="$(json_escape "$val")"
    if grep -q "\"${key}\"[[:space:]]*:" "$file" 2>/dev/null; then
        sed -i "s|\(\"${key}\"[[:space:]]*:[[:space:]]*\)\"[^\"]*\"|\1\"${esc}\"|" "$file"
    else
        json_append "$file" "$key" "\"${esc}\""
    fi
}

# Set or add a numeric/bool key in a flat config.json ($1=file, $2=key, $3=value).
json_set_raw() {
    local file="$1" key="$2" val="$3"
    if grep -q "\"${key}\"[[:space:]]*:" "$file" 2>/dev/null; then
        # [^,}]* stops at the value terminator so a trailing '}' (last key in
        # the object) is never consumed.
        sed -i "s|\(\"${key}\"[[:space:]]*:[[:space:]]*\)[^,}]*|\1${val}|" "$file"
    else
        json_append "$file" "$key" "$val"
    fi
}

# Apply wizard_* environment variables to $1 (config.json).
apply_wizard_config() {
    local config_file="$1"

    if [ -n "${wizard_endpoint:-}" ]; then
        json_set_str "$config_file" "endpoint" "$wizard_endpoint"
    fi
    if [ -n "${wizard_token:-}" ]; then
        json_set_str "$config_file" "token" "$wizard_token"
    fi
    if [ -n "${wizard_interval:-}" ]; then
        case "$wizard_interval" in
            ''|*[!0-9]*) : ;;
            *) json_set_raw "$config_file" "interval" "$wizard_interval" ;;
        esac
    fi
    if [ -n "${wizard_disable_web_ssh:-}" ]; then
        if [ "$wizard_disable_web_ssh" = "true" ]; then
            json_set_raw "$config_file" "disable_web_ssh" "true"
        else
            json_set_raw "$config_file" "disable_web_ssh" "false"
        fi
    fi
    if [ -n "${wizard_ignore_unsafe_cert:-}" ]; then
        if [ "$wizard_ignore_unsafe_cert" = "true" ]; then
            json_set_raw "$config_file" "ignore_unsafe_cert" "true"
        else
            json_set_raw "$config_file" "ignore_unsafe_cert" "false"
        fi
    fi

    # SPK owns the agent version; never let the agent self-update.
    json_set_raw "$config_file" "disable_auto_update" "true"
}
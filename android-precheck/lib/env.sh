#!/usr/bin/env bash
# Locate Android SDK build-tools (aapt2, apksigner) and jq.
# Source-only library; no side-effects unless require_tools is called.

# Order to look for Android SDK root:
#   1. $ANDROID_HOME
#   2. $ANDROID_SDK_ROOT
#   3. ~/Library/Android/sdk (macOS default)
#   4. ~/Android/Sdk (Linux default)
_resolve_android_sdk_root() {
    if [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME" ]; then
        echo "$ANDROID_HOME"; return
    fi
    if [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -d "$ANDROID_SDK_ROOT" ]; then
        echo "$ANDROID_SDK_ROOT"; return
    fi
    if [ -d "$HOME/Library/Android/sdk" ]; then
        echo "$HOME/Library/Android/sdk"; return
    fi
    if [ -d "$HOME/Android/Sdk" ]; then
        echo "$HOME/Android/Sdk"; return
    fi
    echo ""
}

# Find newest aapt2 across build-tools/<version>/aapt2. Returns absolute path or "".
find_aapt2() {
    local sdk; sdk=$(_resolve_android_sdk_root)
    [ -z "$sdk" ] && return 0
    [ -d "$sdk/build-tools" ] || return 0
    ls -1 "$sdk/build-tools"/*/aapt2 2>/dev/null | sort -V | tail -1
}

# Find newest apksigner; same algorithm.
find_apksigner() {
    local sdk; sdk=$(_resolve_android_sdk_root)
    [ -z "$sdk" ] && return 0
    [ -d "$sdk/build-tools" ] || return 0
    ls -1 "$sdk/build-tools"/*/apksigner 2>/dev/null | sort -V | tail -1
}

# Find jq on PATH (no Android-SDK dependency).
find_jq() {
    command -v jq 2>/dev/null
}

find_unzip() {
    command -v unzip 2>/dev/null
}

# Verify all required tools are present. Echo list of missing tools.
# Returns 0 if all present, 3 (env error) otherwise.
require_tools() {
    local missing=""
    if [ -z "$(find_aapt2)" ];     then missing="$missing aapt2"; fi
    if [ -z "$(find_apksigner)" ]; then missing="$missing apksigner"; fi
    if [ -z "$(find_jq)" ];        then missing="$missing jq"; fi
    if [ -z "$(find_unzip)" ];     then missing="$missing unzip"; fi
    if [ -n "$missing" ]; then
        echo "ENV_ERROR: missing tools:$missing" >&2
        echo "Set ANDROID_HOME / ANDROID_SDK_ROOT, or install" >&2
        echo "Android SDK build-tools (Android Studio → SDK Manager" >&2
        echo "→ SDK Tools tab) and 'brew install jq' (macOS) or" >&2
        echo "apt install jq (Linux)." >&2
        return 3
    fi
    return 0
}

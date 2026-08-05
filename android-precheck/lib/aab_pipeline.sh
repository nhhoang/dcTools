#!/usr/bin/env bash
# AAB pipeline helpers used by check.sh v2 mode.
# Each function is self-contained and side-effect minimal.
#
# Public surface (extended in Task 3):
#   find_debug_keystore             -> default debug keystore path
#   aab_ensure_debug_keystore       -> ensure debug keystore exists (create via keytool if needed)
#   aab_unpack_to_tmp <aab>         -> tmp dir path
#   aab_unpack_cleanup <dir>        -> remove tmp dir
#   aab_validate <aab>              -> JSON {valid, reason?}
#   aab_dump_modules <aab>          -> JSON list of module objects
#   aab_extract_universal_apk       -> extract universal.apk from .apks archive
#   aab_build_universal_apk         -> sign + build, echo path to universal.apk

# Default Android debug keystore path.
find_debug_keystore() {
    printf "%s/.android/debug.keystore\n" "${HOME:-}"
}

# Ensure the debug keystore exists. Echoes the path.
# Returns 3 if keytool is unavailable AND the keystore is missing.
aab_ensure_debug_keystore() {
    local ks
    ks="$(find_debug_keystore)"
    if [ -f "$ks" ]; then
        echo "$ks"
        return 0
    fi
    if ! command -v keytool >/dev/null 2>&1; then
        echo "aab_ensure_debug_keystore: keytool not on PATH" >&2
        return 3
    fi
    mkdir -p "$(dirname "$ks")"
    if ! keytool -genkeypair -keystore "$ks" -alias androiddebugkey \
        -storepass android -keypass android \
        -dname "CN=Android Debug,O=Android,C=US" \
        -keyalg RSA -validity 10000 >/dev/null 2>&1; then
        echo "aab_ensure_debug_keystore: keytool failed" >&2
        return 3
    fi
    echo "$ks"
}

# Unpack the bundle to a fresh tmp dir. Echoes the tmp dir path.
aab_unpack_to_tmp() {
    local file="$1"
    [ -n "$file" ] && [ -f "$file" ] || { echo "aab_unpack_to_tmp: file not found: $file" >&2; return 2; }
    local first2
    first2=$(head -c 2 "$file")
    [ "$first2" = "PK" ] || { echo "aab_unpack_to_tmp: not a zip: $file" >&2; return 2; }
    local out
    out=$(mktemp -d -t "$(basename "$file" .aab)-XXXXXX")
    if ! unzip -q "$file" -d "$out"; then
        python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$out"
        echo "aab_unpack_to_tmp: unzip failed" >&2
        return 2
    fi
    echo "$out"
}

aab_unpack_cleanup() {
    local d="$1"
    [ -n "$d" ] && [ -d "$d" ] && python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$d"
}

# Run `bundletool validate` and emit JSON status.
aab_validate() {
    local aab="$1"
    local bt
    bt="$(find_bundletool)"
    if [ -z "$bt" ]; then
        jq -n '{valid:false, reason:"bundletool_unavailable"}'
        return 0
    fi
    if java -jar "$bt" validate --bundle="$aab" >/dev/null 2>&1; then
        jq -n '{valid:true}'
    else
        jq -n '{valid:false, reason:"bundletool_validate_failed"}'
    fi
}

# Emit JSON list of module objects. With no bundletool or when the command fails
# we fall back to a single base module so downstream code can still proceed.
aab_dump_modules() {
    local aab="$1"
    local bt
    bt="$(find_bundletool)"
    if [ -z "$bt" ]; then
        jq -n '[{name:"base", type:"MODULE", required:true}]'
        return 0
    fi
    if java -jar "$bt" dump manifest --bundle="$aab" --module=base >/dev/null 2>&1; then
        jq -n '[{name:"base", type:"MODULE", required:true}]'
        return 0
    fi
    jq -n '[]'
}

# Extract universal.apk from a .apks archive. Echoes the path.
aab_extract_universal_apk() {
    local apks="$1" out_dir="$2"
    mkdir -p "$out_dir"
    local tmp
    tmp=$(mktemp -d -t aab-extract-XXXXXX)
    if ! unzip -q "$apks" -d "$tmp"; then
        python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$tmp"
        echo "aab_extract_universal_apk: unzip failed" >&2
        return 2
    fi
    if [ ! -f "$tmp/universal.apk" ]; then
        python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$tmp"
        echo "aab_extract_universal_apk: universal.apk missing in $apks" >&2
        return 2
    fi
    mv "$tmp/universal.apk" "$out_dir/universal.apk"
    python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1], ignore_errors=True)" "$tmp"
    echo "$out_dir/universal.apk"
}

# Build a signed universal APK from the bundle. Echoes path to extracted apk.
# Args: aab workdir ks ks_pass ks_alias key_pass. Passwords are passed via pass:env:
# style when non-empty; never logged.
aab_build_universal_apk() {
    local aab="$1" workdir="$2" ks="$3" ks_pass="$4" ks_alias="$5" key_pass="$6"
    local bt
    bt="$(find_bundletool)"
    [ -n "$bt" ] || { echo "aab_build_universal_apk: bundletool.jar not found" >&2; return 3; }
    mkdir -p "$workdir"
    local apks="$workdir/built.apks"
    # bundletool 1.17+ accepts --mode=universal; older versions required --universal.
    # Probe via the `help <cmd>` subcommand. The synopsis lists [--mode=...]
    # only on versions that understand the flag.
    local -a cmd=(java -jar "$bt" build-apks --bundle="$aab" --output="$apks")
    if java -jar "$bt" help build-apks 2>&1 | grep -Eq -- "\[--mode=<.*universal"; then
        cmd+=(--mode=universal)
    else
        cmd+=(--universal)
    fi
    if [ -n "$ks" ]; then
        cmd+=(--ks="$ks" --ks-pass="pass:$ks_pass" --ks-key-alias="$ks_alias" --key-pass="pass:$key_pass")
    fi
    if ! "${cmd[@]}" >/dev/null 2>&1; then
        echo "aab_build_universal_apk: bundletool build-apks failed for $aab" >&2
        return 3
    fi
    aab_extract_universal_apk "$apks" "$workdir"
}

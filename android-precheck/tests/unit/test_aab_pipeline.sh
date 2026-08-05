#!/usr/bin/env bash
# Unit tests for aab_pipeline.sh helpers (keystore + AAB ops).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"
LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/aab_pipeline.sh"

AAB_TEST_ROOT="$(mktemp -d -t aab-test-XXXXXX)"
ORIG_HOME="$HOME"
export HOME="$AAB_TEST_ROOT/home"
mkdir -p "$HOME"
ORIG_KEYTOOL_PATH="$PATH"
cleanup() {
    rm -rf "$AAB_TEST_ROOT"
    export HOME="$ORIG_HOME"
    export PATH="$ORIG_KEYTOOL_PATH"
}
trap cleanup EXIT

test_debug_keystore_path_is_default() {
    local out
    out=$(find_debug_keystore)
    assert_eq "$out" "$HOME/.android/debug.keystore" "debug keystore path matches Android default"
}

test_debug_keystore_auto_creates_when_missing() {
    [ ! -f "$HOME/.android/debug.keystore" ] || { _assert_increment_fail "precondition" "keystore already exists"; return; }
    local out
    out=$(aab_ensure_debug_keystore 2>/dev/null)
    assert_eq "$out" "$HOME/.android/debug.keystore" "ensure path equals debug keystore"
    [ -f "$out" ] || { _assert_increment_fail "keystore created" "missing: $out"; return; }
    _assert_increment_pass "keystore file exists after ensure"
}

test_debug_keystore_does_not_overwrite_existing() {
    mkdir -p "$HOME/.android"
    printf "EXISTING" > "$HOME/.android/debug.keystore"
    local out
    out=$(aab_ensure_debug_keystore 2>/dev/null)
    assert_eq "$out" "$HOME/.android/debug.keystore" "ensure path equals debug keystore"
    assert_eq "$(cat "$out")" "EXISTING" "existing file is preserved"
}


test_aab_unpack_to_tmp_extracts() {
    local aab="$LIB_DIR/../tests/fixtures/mock.aab.zip"
    local out
    out=$(aab_unpack_to_tmp "$aab")
    assert_contains "$out" "/mock.aab.zip-" "tmp path includes bundle basename"
    [ -f "$out/AndroidManifest.xml" ] || { _assert_increment_fail "manifest extracted" "missing"; aab_unpack_cleanup "$out"; return; }
    _assert_increment_pass "manifest extracted"
    aab_unpack_cleanup "$out"
}

test_aab_unpack_rejects_non_zip() {
    local bad="$AAB_TEST_ROOT/bogus.aab"
    printf "nope" > "$bad"
    if aab_unpack_to_tmp "$bad" >/dev/null 2>&1; then
        _assert_increment_fail "non-zip rejected" "got success"
    else
        _assert_increment_pass "non-zip rejected"
    fi
}

test_aab_extract_universal_finds_apk_in_apks_zip() {
    local apks="$AAB_TEST_ROOT/fake.apks"
    local build="$AAB_TEST_ROOT/build"
    mkdir -p "$build"
    printf "apk-bytes" > "$build/universal.apk"
    (cd "$build" && zip -qr "$apks" universal.apk)
    local out
    out=$(aab_extract_universal_apk "$apks" "$AAB_TEST_ROOT/out")
    assert_eq "$out" "$AAB_TEST_ROOT/out/universal.apk" "extract returns expected path"
    [ -f "$out" ] || { _assert_increment_fail "apk file present" "missing: $out"; return; }
    _assert_increment_pass "apk file present"
}

test_aab_validate_writes_status_json() {
    local aab="$LIB_DIR/../tests/fixtures/mock.aab.zip"
    local out
    out=$(aab_validate "$aab" 2>/dev/null || true)
    echo "$out" | jq -e . >/dev/null 2>&1 || { _assert_increment_fail "validate emits JSON" "got: $out"; return; }
    _assert_increment_pass "validate emits JSON"
}
run_tests "$SCRIPT_DIR/test_aab_pipeline.sh"

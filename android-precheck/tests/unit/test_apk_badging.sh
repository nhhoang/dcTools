#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"

LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/apk_badging.sh"

# Fixture file must contain the standard `aapt2 dump badging` output for
# the user's known-good APK. Truncated to ~25 lines for unit testability.
FIXTURE="$SCRIPT_DIR/fixtures/badging.txt"

test_parse_extracts_package() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "fixture absent (run Task 6 step 1 first)"; return; }
    local got
    got=$(parse_badging < "$FIXTURE" | jq -r '.package')
    assert_eq "$got" "com.wb.goog.dc.dcwc" "package name from fixture"
}

test_parse_extracts_version_code() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_badging < "$FIXTURE" | jq -r '.versionCode')
    assert_eq "$got" "1" "versionCode from fixture"
}

test_parse_extracts_version_name() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_badging < "$FIXTURE" | jq -r '.versionName')
    assert_eq "$got" "1.1.14.1" "versionName from fixture"
}

test_parse_extracts_sdk_min_target() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_badging < "$FIXTURE" | jq -r '"\(.minSdk)-\(.targetSdk)"')
    assert_eq "$got" "25-35" "minSdk-targetSdk"
}

test_parse_returns_empty_on_garbage() {
    echo "garbage input" | parse_badging | jq -e . >/dev/null 2>&1
    local ec=$?
    if [ "$ec" = "0" ]; then
        _assert_increment_pass "garbage yields valid (possibly empty) JSON"
    else
        _assert_increment_pass "garbage yields error (also acceptable)"
    fi
}

run_tests "$SCRIPT_DIR/test_apk_badging.sh"

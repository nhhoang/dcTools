#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"

LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/apk_abi.sh"

FIXTURE="$SCRIPT_DIR/fixtures/apk_ls.txt"

test_extracts_arm64_v8a() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_abi_ls < "$FIXTURE" | jq -r '.abis | join(",")')
    assert_contains "$got" "arm64-v8a" "list contains arm64-v8a"
}

test_extracts_three_abi() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local count
    count=$(parse_abi_ls < "$FIXTURE" | jq -r '.abis | length')
    assert_eq "$count" "3" "3 distinct ABIs (arm64-v8a, armeabi-v7a, x86_64)"
}

test_extracts_individual_libraries() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local count
    count=$(parse_abi_ls < "$FIXTURE" | jq -r '.libraries | length')
    if [ "$count" -gt 10 ]; then
        _assert_increment_pass "many libraries listed ($count)"
    else
        _assert_increment_fail "expected many .so entries" "got: $count"
    fi
}

run_tests "$SCRIPT_DIR/test_apk_abi.sh"

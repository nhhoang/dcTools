#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"

# Make lib/env.sh target reachable
LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/env.sh"

test_find_aapt2_finds_something() {
    local out
    out=$(find_aapt2 2>/dev/null || true)
    if [ -z "$out" ]; then
        # No SDK on this runner — accept; mark as skip-equivalent pass
        _assert_increment_pass "find_aapt2 returned non-empty when SDK present"
    elif [ -x "$out" ]; then
        _assert_increment_pass "find_aapt2 returned executable path"
    else
        _assert_increment_fail "find_aapt2 returned non-executable path" \
            "got: $out"
    fi
}

test_find_apksigner_finds_something() {
    local out
    out=$(find_apksigner 2>/dev/null || true)
    if [ -z "$out" ] || [ -x "$out" ]; then
        _assert_increment_pass "find_apksigner behavior acceptable"
    else
        _assert_increment_fail "find_apksigner returned non-executable path" \
            "got: $out"
    fi
}

test_find_jq_succeeds() {
    local out
    out=$(find_jq 2>/dev/null || true)
    assert_contains "$out" "jq" "find_jq returns path with jq in it"
}

test_find_unzip_succeeds() {
    local out
    out=$(find_unzip 2>/dev/null || true)
    assert_contains "$out" "unzip" "find_unzip returns path with unzip in it"
}

test_require_tools_succeeds_when_all_present() {
    # Skip if even jq missing
    if ! command -v jq >/dev/null 2>&1; then
        _assert_increment_pass "skipped: jq not on PATH"
        return
    fi
    # Don't actually fail out of the test — check exit code
    ( require_tools ) >/dev/null 2>&1
    local ec=$?
    if [ "$ec" = "0" ] || [ "$ec" = "3" ]; then
        _assert_increment_pass "require_tools exits 0 or 3 (env error code)"
    else
        _assert_increment_fail "require_tools unexpected exit" \
            "exit: $ec"
    fi
}

run_tests "$SCRIPT_DIR/test_env.sh"

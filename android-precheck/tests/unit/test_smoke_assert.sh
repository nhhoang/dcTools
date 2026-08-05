#!/usr/bin/env bash
# Framework self-test — verifies assert_eq / assert_contains behave.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"

test_assert_eq_passes_on_match() {
    assert_eq "abc" "abc" "equal strings must pass"
}

test_assert_eq_records_mismatch() {
    local recorded
    recorded=$(
        . "$SCRIPT_DIR/../lib/assert.sh"
        assert_eq "abc" "xyz" "different strings should fail" >/dev/null
        echo "$FAILED"
    )
    assert_eq "$recorded" "1" "assert_eq records a mismatch"
}

test_assert_contains_finds_substring() {
    assert_contains "hello world" "world" "substring found"
}

test_assert_contains_records_missing_substring() {
    local recorded
    recorded=$(
        . "$SCRIPT_DIR/../lib/assert.sh"
        assert_contains "hello" "xyz" "missing substring" >/dev/null
        echo "$FAILED"
    )
    assert_eq "$recorded" "1" "assert_contains records a missing substring"
}

test_assert_exit_zero_on_true() {
    assert_exit 0 true "true should exit 0"
}

test_assert_exit_nonzero_on_false() {
    assert_exit 1 false "false should exit 1"
}

run_tests "$SCRIPT_DIR/test_smoke_assert.sh"

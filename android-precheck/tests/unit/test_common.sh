#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"

LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/common.sh"

test_log_ok_writes_OK_label() {
    local out
    out=$(NO_COLOR=1 log_ok "test")
    assert_contains "$out" "OK" "OK label present"
    assert_contains "$out" "test" "message present"
}

test_log_fail_writes_FAIL_label() {
    local out
    out=$(NO_COLOR=1 log_fail "test")
    assert_contains "$out" "FAIL" "FAIL label present"
}

test_log_skip_writes_SKIP_label() {
    local out
    out=$(NO_COLOR=1 log_skip "test")
    assert_contains "$out" "SKIP" "SKIP label present"
}

test_log_warn_writes_WARN_label() {
    local out
    out=$(NO_COLOR=1 log_warn "test")
    assert_contains "$out" "WARN" "WARN label present"
}

test_header_writes_separator() {
    local out
    out=$(NO_COLOR=1 log_header "TITLE")
    assert_contains "$out" "TITLE" "header contains title"
    assert_contains "$out" "────" "header contains separator"
}

test_exit_code_constants_match_design() {
    assert_eq "$EXIT_OK"           "0" "ok exit"
    assert_eq "$EXIT_FAIL"         "1" "fail exit"
    assert_eq "$EXIT_USAGE"        "2" "usage exit"
    assert_eq "$EXIT_ENV"          "3" "env exit"
    assert_eq "$EXIT_STRICT"       "4" "strict exit"
    assert_eq "$EXIT_HARVEST_IO"   "5" "harvest io exit"
}

run_tests "$SCRIPT_DIR/test_common.sh"

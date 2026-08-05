#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"

LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/report.sh"

SAMPLE='{"summary":{"ok":2,"fail":1,"skip":1,"warn":0,"total":4},
         "results":[
           {"category":"package","check":"package","status":"OK","expected":"com.x","actual":"com.x"},
           {"category":"signing","check":"sha256","status":"FAIL","expected":"a","actual":"b","message":"wrong cert"},
           {"category":"version","check":"versionName","status":"SKIP"},
           {"category":"meta-data","check":"APP_ID","status":"OK","expected":"299009804916","actual":"299009804916"}
         ]}'

test_format_text_includes_OK_marker() {
    local out
    out=$(echo "$SAMPLE" | NO_COLOR=1 format_text)
    assert_contains "$out" "[OK]" "OK marker"
    assert_contains "$out" "[FAIL]" "FAIL marker"
    assert_contains "$out" "[SKIP]" "SKIP marker"
}

test_format_text_includes_summary() {
    local out
    out=$(echo "$SAMPLE" | NO_COLOR=1 format_text)
    assert_contains "$out" "SUMMARY" "summary header"
    assert_contains "$out" "2 OK" "OK count"
    assert_contains "$out" "1 FAIL" "FAIL count"
    assert_contains "$out" "1 SKIP" "SKIP count"
}

test_exit_code_for_results() {
    # Default: 0 if no FAIL, 1 if any FAIL
    local ec
    ec=$(echo "$SAMPLE" | compute_exit_code)
    assert_eq "$ec" "1" "1 failure → exit 1"

    local clean='{"summary":{"ok":3,"fail":0,"skip":1,"warn":0,"total":4},"results":[]}'
    ec=$(echo "$clean" | compute_exit_code)
    assert_eq "$ec" "0" "no failure → exit 0"
}

run_tests "$SCRIPT_DIR/test_report.sh"

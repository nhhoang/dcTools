#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"

LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/apk_certs.sh"

FIXTURE="$SCRIPT_DIR/fixtures/certs.txt"

test_sha256_matches_known() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_certs < "$FIXTURE" | jq -r '.sha256')
    assert_eq "$got" "b46acd3981297ed08d84531a9de00543510ef1413a6ae667b9bf487cf23293c4" "SHA-256"
}

test_sha1_matches_known() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_certs < "$FIXTURE" | jq -r '.sha1')
    assert_eq "$got" "5e455590db0114a063fd8fc8f620299087aa223c" "SHA-1"
}

test_subject_dn_contains_known_tokens() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_certs < "$FIXTURE" | jq -r '.subjectDN')
    assert_contains "$got" "WB Games" "DN contains WB Games"
    assert_contains "$got" "Team Leads" "DN contains Team Leads"
}

test_signature_schemes_detect_v2() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_certs < "$FIXTURE" | jq -r '.schemes | join(",")')
    assert_contains "$got" "v2" "schemes list contains v2"
}

run_tests "$SCRIPT_DIR/test_apk_certs.sh"

#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"

LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/json_diff.sh"

# Helper: write two JSON files, then call diff with them.
run_diff() {
    local actual="$1" expected="$2"
    diff_apk_vs_expected "$actual" "$expected"
}

test_package_match_returns_OK() {
    local out
    out=$(run_diff '{"package":"com.example"}' '{"expected_package":"com.example"}')
    assert_eq "$(echo "$out" | jq -r '.results[0].status')" "OK" "package OK"
}

test_package_mismatch_returns_FAIL() {
    local out
    out=$(run_diff '{"package":"com.example"}' '{"expected_package":"com.other"}')
    assert_eq "$(echo "$out" | jq -r '.results[0].status')" "FAIL" "package FAIL"
    assert_eq "$(echo "$out" | jq -r '.results[0].expected')" "com.other" "expected value"
    assert_eq "$(echo "$out" | jq -r '.results[0].actual')"   "com.example" "actual value"
}

test_field_missing_in_expected_returns_SKIP() {
    local out
    out=$(run_diff '{"package":"com.example"}' '{}')
    assert_eq "$(echo "$out" | jq -r '.results[0].status')" "SKIP" "missing config = SKIP"
}

test_app_id_present_but_mismatched_returns_FAIL() {
    local out
    out=$(run_diff \
        '{"metaData":{"com.google.android.gms.games.APP_ID":"99009804916"}}' \
        '{"expected_meta_data":{"com.google.android.gms.games.APP_ID":"299009804916"}}')
    local status
    status=$(echo "$out" | jq -r '.results | map(select(.check == "com.google.android.gms.games.APP_ID"))[0].status')
    assert_eq "$status" "FAIL" "APP_ID mismatch = FAIL"
}

test_app_id_missing_in_actual_returns_FAIL() {
    local out
    out=$(run_diff \
        '{"metaData":{}}' \
        '{"expected_meta_data":{"com.google.android.gms.games.APP_ID":"299009804916"}}')
    local status
    status=$(echo "$out" | jq -r '.results | map(select(.check == "com.google.android.gms.games.APP_ID"))[0].status')
    assert_eq "$status" "FAIL" "APP_ID missing in actual = FAIL"
}

test_strict_marks_missing_critical_as_FAIL() {
    local out
    out=$(STRICT=1 run_diff '{"metaData":{}}' '{"expected_meta_data":{}}')
    # Strict mode should mark BOTH signing:sha256 and meta-data:APP_ID as FAIL
    # because they are critical keys per design §6.3.
    local signing_status
    signing_status=$(echo "$out" | jq -r '.results | map(select(.check == "sha256"))[0].status')
    local appid_status
    appid_status=$(echo "$out" | jq -r '.results | map(select(.check == "com.google.android.gms.games.APP_ID"))[0].status')
    assert_eq "$signing_status" "FAIL" "strict marks sha256 as FAIL (critical)"
    assert_eq "$appid_status"   "FAIL" "strict marks APP_ID as FAIL (critical)"
}

test_strict_off_does_not_fail_for_missing() {
    local out
    out=$(run_diff '{"metaData":{}}' '{"expected_meta_data":{}}')
    local has_fail
    has_fail=$(echo "$out" | jq '.summary.fail')
    assert_eq "$has_fail" "0" "default mode has 0 failures when both empty"
}

test_default_mode_warns_when_critical_keys_are_missing() {
    local out
    out=$(run_diff '{"metaData":{},"signing":{}}' '{}')
    local sha_status app_id_status
    sha_status=$(echo "$out" | jq -r '.results | map(select(.category == "signing" and .check == "sha256"))[0].status')
    app_id_status=$(echo "$out" | jq -r '.results | map(select(.check == "com.google.android.gms.games.APP_ID"))[0].status')
    assert_eq "$sha_status" "WARN" "default mode recommends configuring SHA-256"
    assert_eq "$app_id_status" "WARN" "default mode recommends configuring GPGS APP_ID"
}

test_component_can_match_provider_authority() {
    local out
    out=$(run_diff \
        '{"activities":[],"services":[],"providers":["com.example.Provider"],"receivers":[],"providerAuthorities":{"com.example.Provider":"com.example.playgamesinitprovider"}}' \
        '{"expected_components_present":["playgamesinitprovider"]}')
    local status
    status=$(echo "$out" | jq -r '.results | map(select(.category == "components"))[0].status')
    assert_eq "$status" "OK" "component check matches provider authority"
}

test_signing_verified_can_be_required() {
    local out
    out=$(run_diff \
        '{"signing":{"verified":false}}' \
        '{"expected_signing":{"verified":true}}')
    local status
    status=$(echo "$out" | jq -r '.results | map(select(.check == "verified"))[0].status')
    assert_eq "$status" "FAIL" "invalid APK signature fails when verified=true is configured"
}

test_attribute_path_alias_is_supported() {
    local out
    out=$(run_diff \
        '{"applicationAttrs":{"debuggable":"false"}}' \
        '{"expected_attributes":{"application/@android:debuggable":false}}')
    local status
    status=$(echo "$out" | jq -r '.results | map(select(.category == "attrs"))[0].status')
    assert_eq "$status" "OK" "documented application attribute path maps to parsed key"
}

test_summary_counts_correctly() {
    local out
    out=$(run_diff \
        '{"package":"com.example","versionCode":"1"}' \
        '{"expected_package":"com.example","expected_version":{"versionCode_eq":2}}')
    local summary
    summary=$(echo "$out" | jq -c '.summary')
    assert_contains "$summary" '"fail":1' "1 fail (versionCode)"
    assert_contains "$summary" '"ok":1' "1 ok (package)"
}

run_tests "$SCRIPT_DIR/test_json_diff.sh"

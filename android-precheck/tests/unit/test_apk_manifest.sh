#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"

LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/apk_manifest.sh"

FIXTURE="$SCRIPT_DIR/fixtures/xmltree.txt"

test_meta_data_extracts_known_keys() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_manifest < "$FIXTURE" | jq -r '.metaData["com.google.android.gms.games.APP_ID"]')
    assert_eq "$got" "299009804916" "GPGS APP_ID"
}

test_meta_data_includes_unity_version() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_manifest < "$FIXTURE" | jq -r '.metaData["com.google.android.gms.games.unityVersion"]')
    assert_eq "$got" "2.0.0" "unityVersion"
}

test_components_includes_playgames_init_provider() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_manifest < "$FIXTURE" | jq -r '.providers | join(",")')
    assert_contains "$got" "PlayGamesInitProvider" "providers list contains PlayGamesInitProvider"
}

test_activity_name_is_found_after_theme_attribute() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_manifest < "$FIXTURE" | jq -r '.activities | join(",")')
    assert_contains "$got" "com.google.android.gms.games.internal.v2.resolution.GamesResolutionActivity" \
        "activity name is parsed even when theme comes first"
}

test_provider_authority_is_extracted() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_manifest < "$FIXTURE" | jq -r \
        '.providerAuthorities["com.google.android.gms.games.provider.PlayGamesInitProvider"]')
    assert_eq "$got" "com.wb.goog.dc.dcwc.playgamesinitprovider" \
        "PlayGamesInitProvider authority"
}

test_meta_data_resource_value_is_preserved() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_manifest < "$FIXTURE" | jq -r '.metaData["android.support.FILE_PROVIDER_PATHS"]')
    assert_eq "$got" "@0x7f150003" "meta-data android:resource value"
}

test_component_counts_match_manifest_elements() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local parsed
    parsed=$(parse_manifest < "$FIXTURE")
    assert_eq "$(echo "$parsed" | jq -r '.activities | length')" "31" "all activities parsed"
    assert_eq "$(echo "$parsed" | jq -r '.services | length')" "19" "all services parsed"
    assert_eq "$(echo "$parsed" | jq -r '.providers | length')" "12" "all providers parsed"
    assert_eq "$(echo "$parsed" | jq -r '.receivers | length')" "16" "all receivers parsed"
}

test_attrs_extracts_debuggable() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_manifest < "$FIXTURE" | jq -r '.applicationAttrs["debuggable"]')
    assert_eq "$got" "true" "debuggable attr (this APK is debug build)"
}

run_tests "$SCRIPT_DIR/test_apk_manifest.sh"

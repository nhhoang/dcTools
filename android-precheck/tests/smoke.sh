#!/usr/bin/env bash
# End-to-end smoke test for android-precheck.
# Verifies:
#   1. --self-check passes (env ok)
#   2. --harvest yields JSON with expected top-level keys
#   3. harvested baseline includes components, provider authority, ABIs, schemes
#   4. round-trip --check against harvested baseline yields 0 FAIL
#   5. inject a wrong expected_signing.sha256 → 1+ FAIL

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../check.sh"
APK="/Users/hoangnguyen/Downloads/DGame_debug_1.1.14.1(1).apk"
SMOKE_TMP="$(mktemp -d -t android-precheck-smoke-XXXXXX)"
TMPHARV="$SMOKE_TMP/keys.json"
CHECK_JSON="$SMOKE_TMP/check.json"
CHECK_BAD_JSON="$SMOKE_TMP/check-bad.json"
trap 'rm -rf "$SMOKE_TMP"' EXIT

fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }
say()  { echo "[smoke] $*"; }

[ -x "$CHECK" ] || fail "check.sh not executable at $CHECK"
[ -f "$APK" ]  || fail "APK not found at $APK"

say "1/5 self-check"
"$CHECK" --self-check || fail "self-check failed"

say "2/5 harvest"
"$CHECK" --harvest "$APK" -o "$TMPHARV" || fail "harvest failed"
jq -e '.expected_package' "$TMPHARV" >/dev/null 2>&1 || fail "harvested JSON missing expected_package"
jq -e '.expected_signing.sha256' "$TMPHARV" >/dev/null 2>&1 || fail "harvested JSON missing expected_signing.sha256"
jq -e '.expected_meta_data' "$TMPHARV" >/dev/null 2>&1 || fail "harvested JSON missing expected_meta_data"
jq -e '.expected_components_present | index("com.google.android.gms.games.provider.PlayGamesInitProvider") != null' \
    "$TMPHARV" >/dev/null 2>&1 || fail "harvested JSON missing PlayGamesInitProvider"
jq -e '.expected_components_present | index("com.wb.goog.dc.dcwc.playgamesinitprovider") != null' \
    "$TMPHARV" >/dev/null 2>&1 || fail "harvested JSON missing Play Games provider authority"
jq -e '.expected_abi.must_include | index("arm64-v8a") != null' \
    "$TMPHARV" >/dev/null 2>&1 || fail "harvested JSON missing arm64-v8a"
jq -e '.expected_signing.must_use_signature_scheme | index("v2") != null' \
    "$TMPHARV" >/dev/null 2>&1 || fail "harvested JSON missing v2 signature scheme"
jq -e '.expected_signing.verified == true' \
    "$TMPHARV" >/dev/null 2>&1 || fail "harvested JSON does not require a verified signature"

say "3/5 harvest completeness"
say "4/5 round-trip --check"
"$CHECK" "$APK" --expected "$TMPHARV" --json > "$CHECK_JSON"
fails=$(jq -r '.summary.fail' "$CHECK_JSON")
[ "$fails" = "0" ] || fail "round-trip produced $fails failures (expected 0)"
jq -e '.tool == "android-precheck" and .version == "0.2.0" and .exit_code == 0' \
    "$CHECK_JSON" >/dev/null 2>&1 || fail "JSON report metadata is incomplete"

say "5/5 inject bad sha256 → expect FAIL"
TMPHARV_BAD="$SMOKE_TMP/keys-bad.json"
jq '.expected_signing.sha256 = "WRONG_DEADBEEF"' "$TMPHARV" > "$TMPHARV_BAD"
"$CHECK" "$APK" --expected "$TMPHARV_BAD" --json > "$CHECK_BAD_JSON"
fails=$(jq -r '.summary.fail' "$CHECK_BAD_JSON")
if [ "$fails" -ge 1 ]; then
    say "OK: $fails failures correctly reported"
else
    fail "deliberate bad sha256 did not trigger FAIL"
fi



# AAB round-trip (gated on real AAB fixture)
AAB="$SCRIPT_DIR/fixtures/sample.aab"
if [ -f "$AAB" ]; then
    say "6/6 AAB round-trip"
    BUNDLETOOL_JAR="${BUNDLETOOL_JAR:-/Users/hoangnguyen/Library/Android/sdk/bundletool/bundletool.jar}"
    export BUNDLETOOL_JAR
    TMPHARV_AAB="$SMOKE_TMP/keys.aab.json"
    "$CHECK" --harvest "$AAB" -o "$TMPHARV_AAB" || fail "AAB harvest failed"
    jq -e '.expected_package' "$TMPHARV_AAB" >/dev/null 2>&1 || fail "AAB harvest missing expected_package"
    "$CHECK" "$AAB" --expected "$TMPHARV_AAB" --json > "$SMOKE_TMP/check.aab.json"
    fails=$(jq -r '.apk.summary.fail' "$SMOKE_TMP/check.aab.json")
    [ "$fails" = "0" ] || fail "AAB round-trip produced $fails failures"
    # Bad sha256 should fail
    TMPHARV_AAB_BAD="$SMOKE_TMP/keys.aab.bad.json"
    jq '.expected_signing.sha256 = "DEADBEEF"' "$TMPHARV_AAB" > "$TMPHARV_AAB_BAD"
    set +e
    "$CHECK" "$AAB" --expected "$TMPHARV_AAB_BAD" --json > "$SMOKE_TMP/check.aab.bad.json"
    rc=$?
    set -e
    [ "$rc" = "1" ] || fail "AAB with tampered sha256 must exit 1 (got $rc)"
    unset BUNDLETOOL_JAR
else
    say "[SKIP] 6/6 AAB fixture not available (tests/fixtures/sample.aab)"
fi

say "all steps green ✓"
exit 0

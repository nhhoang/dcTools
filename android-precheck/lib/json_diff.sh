#!/usr/bin/env bash
# Compare the union of all parser outputs (one JSON blob) against keys.json.
# Emit a results array with [OK]/[FAIL]/[SKIP]/[WARN].
#
# Output schema:
#   {
#     "summary": { "ok": N, "fail": N, "skip": N, "warn": N, "total": N },
#     "results": [
#       { "category": "package", "check": "package", "status": "OK|FAIL|SKIP|WARN",
#         "expected": "...", "actual": "...", "message": "..." },
#       ...
#     ]
#   }

# Standard critical keys (must match design §6.3). Hardcoded.
_CRITICAL_APP_ID='com.google.android.gms.games.APP_ID'

# Helper: append one result to JSON array and update counters.
# Args: category check expected actual msg status
_diff_one() {
    local category="$1" check="$2" expected="$3" actual="$4"
    local st
    if [ -z "$expected" ]; then
        # Field absent in expected → SKIP, except strict mode for critical keys.
        if [ "${STRICT:-0}" = "1" ]; then
            case "$category:$check" in
                "signing:sha256"|"meta-data:$_CRITICAL_APP_ID")
                    jq -n --arg cat "$category" --arg chk "$check" \
                        --arg actual "$actual" \
                        '{category: $cat, check: $chk, status: "FAIL",
                          expected: "(unset, critical key required by --strict)",
                          actual: $actual,
                          message: "CRITICAL: this key must be configured before --strict is useful"}'
                    return
                    ;;
            esac
        fi
        case "$category:$check" in
            "signing:sha256")
                jq -n --arg cat "$category" --arg chk "$check" --arg actual "$actual" \
                    '{category: $cat, check: $chk, status: "WARN",
                      expected: "(unset, recommended critical key)", actual: $actual,
                      message: "Configure expected_signing.sha256 before release."}'
                return
                ;;
        esac
        jq -n --arg cat "$category" --arg chk "$check" \
            '{category: $cat, check: $chk, status: "SKIP",
              message: "not configured"}'
        return
    fi
    if [ "$expected" = "$actual" ]; then
        st="OK"
    else
        st="FAIL"
    fi
    local msg=""
    case "$category:$check" in
        "meta-data:$_CRITICAL_APP_ID")
            msg="Looks like plugin reset to placeholder. Re-run Play Games plugin Setup (Window → Google Play Games → Setup) and rebuild."
            ;;
        "signing:sha256")
            msg="Signing cert SHA-256 mismatch. Are you using the correct keystore?"
            ;;
        "signing:verified")
            msg="APK signature verification failed. Rebuild and sign the APK before submission."
            ;;
    esac
    jq -n --arg cat "$category" --arg chk "$check" \
        --arg st "$st" \
        --arg exp "$expected" --arg act "$actual" --arg msg "$msg" \
        '{category: $cat, check: $chk, status: $st,
          expected: $exp, actual: $act, message: $msg}'
}

# Helper: increment summary counters; echo "ok|fail|skip|warn" tag.
_diff_tally() {
    local r="$1"
    local s
    s=$(echo "$r" | jq -r '.status')
    case "$s" in
        OK)   echo "ok" ;;
        FAIL) echo "fail" ;;
        SKIP) echo "skip" ;;
        WARN) echo "warn" ;;
        *)    echo "skip" ;;
    esac
}

# Top-level diff function.
# Args: $1 = actual JSON, $2 = expected JSON.
diff_apk_vs_expected() {
    local actual="$1" expected="$2"
    local results="[]"
    local ok=0 fail=0 skip=0 warn=0

    _append() {
        local r="$1"
        results=$(echo "$results" | jq --argjson r "$r" '. + [$r]')
        case "$(echo "$r" | jq -r '.status')" in
            OK)   ok=$((ok+1)) ;;
            FAIL) fail=$((fail+1)) ;;
            SKIP) skip=$((skip+1)) ;;
            WARN) warn=$((warn+1)) ;;
        esac
    }

    # ---- package ----
    local pkg_a pkg_e
    pkg_a=$(echo "$actual" | jq -r '.package // ""')
    pkg_e=$(echo "$expected" | jq -r '.expected_package // ""')
    _append "$(_diff_one package package "$pkg_e" "$pkg_a")"

    # ---- version (versionName + versionCode_eq OR versionCode_min/max) ----
    local vn_a vc_a
    vn_a=$(echo "$actual"   | jq -r '.versionName // ""')
    vc_a=$(echo "$actual"   | jq -r '.versionCode // ""')

    local vn_e vcequal vcmin vcmax
    vn_e=$(echo "$expected" | jq -r '.expected_version.versionName // ""')
    vcequal=$(echo "$expected" | jq -r '.expected_version.versionCode_eq  // ""')
    vcmin=$(echo "$expected"   | jq -r '.expected_version.versionCode_min // ""')
    vcmax=$(echo "$expected"   | jq -r '.expected_version.versionCode_max // ""')

    if [ -n "$vn_e" ]; then
        _append "$(_diff_one version versionName "$vn_e" "$vn_a")"
    fi

    if [ -n "$vcequal" ]; then
        _append "$(_diff_one version versionCode "$vcequal" "$vc_a")"
    elif [ -n "$vcmin" ] || [ -n "$vcmax" ]; then
        local lo="${vcmin:-0}" hi="${vcmax:-999999}"
        local vc_st="FAIL"
        if [ -n "$vc_a" ] && [ "$vc_a" -ge "$lo" ] 2>/dev/null && [ "$vc_a" -le "$hi" ] 2>/dev/null; then
            vc_st="OK"
        fi
        _append "$(jq -n --arg st "$vc_st" --arg lo "$lo" --arg hi "$hi" --arg vc "$vc_a" \
            '{category: "version", check: "versionCode", status: $st,
              expected: ($lo + " ≤ x ≤ " + $hi), actual: $vc}')"
    fi

    # ---- SDK min/target/compile ----
    for k in minSdk targetSdk compileSdk; do
        local a e
        a=$(echo "$actual"   | jq -r ".$k // \"\"")
        e=$(echo "$expected" | jq -r ".expected_sdk.$k // \"\"")
        _append "$(_diff_one sdk "$k" "$e" "$a")"
    done

    # ---- signing: sha256/sha1/md5/subjectDN/verified ----
    for k in sha256 sha1 md5 subjectDN verified; do
        local a e
        a=$(echo "$actual" | jq -r --arg k "$k" '
            (.signing // {}) as $signing
            | if ($signing | has($k)) then ($signing[$k] | tostring) else "" end
        ')
        e=$(echo "$expected" | jq -r --arg k "$k" '
            (.expected_signing // {}) as $signing
            | if ($signing | has($k)) then ($signing[$k] | tostring) else "" end
        ')
        _append "$(_diff_one signing "$k" "$e" "$a")"
    done

    # ---- signing.subject_dn_contains (substring check) ----
    local dn_subs dn_a
    dn_subs=$(echo "$expected" | jq -r '.expected_signing.subject_dn_contains // [] | .[]')
    dn_a=$(echo "$actual"   | jq -r '.signing.subjectDN // ""')
    for needle in $dn_subs; do
        local st="FAIL" msg="DN missing needle: $needle"
        case "$dn_a" in *"$needle"*) st="OK"; msg="";; esac
        _append "$(jq -n --arg st "$st" --arg needle "$needle" --arg dn "$dn_a" --arg msg "$msg" \
            '{category: "signing", check: ("dn_contains:" + $needle), status: $st,
              expected: $needle, actual: $dn, message: $msg}')"
    done

    # ---- signing.must_use_signature_scheme ----
    local expected_schemes
    expected_schemes=$(echo "$expected" | jq -r '.expected_signing.must_use_signature_scheme // [] | .[]')
    for s in $expected_schemes; do
        local st="FAIL"
        if echo "$actual" | jq -e --arg s "$s" '.signing.schemes | index($s) != null' >/dev/null 2>&1; then
            st="OK"
        fi
        _append "$(jq -n --arg st "$st" --arg s "$s" \
            '{category: "signing", check: ("scheme:" + $s), status: $st,
              expected: $s, actual: "(see schemes list)"}')"
    done

    # ---- meta-data: each key in expected_meta_data → check actual.metaData ----
    local meta_keys
    meta_keys=$(echo "$expected" | jq -r '.expected_meta_data // {} | keys[]')
    for name in $meta_keys; do
        local a e
        a=$(echo "$actual"   | jq -r --arg k "$name" '.metaData[$k] // ""')
        e=$(echo "$expected" | jq -r --arg k "$name" '.expected_meta_data[$k] // ""')
        _append "$(_diff_one meta-data "$name" "$e" "$a")"
    done

    # ---- permissions_present (set contains) ----
    local p_want p_have
    p_want=$(echo "$expected" | jq -r '.expected_permissions_present // [] | .[]')
    p_have=$(echo "$actual"   | jq -r '.permissions // [] | .[]')
    for p in $p_want; do
        local st="FAIL"
        if echo "$p_have" | grep -Fxq "$p"; then st="OK"; fi
        _append "$(jq -n --arg st "$st" --arg p "$p" \
            '{category: "permissions", check: ("present:" + $p), status: $st,
              expected: $p, actual: "(see permissions list)"}')"
    done

    # ---- permissions_absent ----
    p_want=$(echo "$expected" | jq -r '.expected_permissions_absent // [] | .[]')
    for p in $p_want; do
        local st="OK"
        if echo "$p_have" | grep -Fxq "$p"; then st="FAIL"; fi
        _append "$(jq -n --arg st "$st" --arg p "$p" \
            '{category: "permissions", check: ("absent:" + $p), status: $st,
              expected: ("NOT " + $p), actual: "(see permissions list)"}')"
    done

    # ---- components_present (substring match across activity/service/receiver/providers) ----
    local want_present
    want_present=$(echo "$expected" | jq -r '.expected_components_present // [] | .[]')
    for want in $want_present; do
        local st="FAIL"
        if echo "$actual" | jq -e --arg w "$want" '
            ((.activities // []) + (.services // []) + (.receivers // []) + (.providers // [])
             + ((.providerAuthorities // {}) | to_entries | map(.value)))
            | any(. | contains($w))
        ' >/dev/null 2>&1; then
            st="OK"
        fi
        _append "$(jq -n --arg st "$st" --arg want "$want" \
            '{category: "components", check: ("present:" + $want), status: $st,
              expected: $want, actual: "(see components lists)"}')"
    done

    # ---- ABI must_include / must_exclude ----
    local must_in must_out abis
    must_in=$(echo "$expected"  | jq -r '.expected_abi.must_include // [] | .[]')
    must_out=$(echo "$expected" | jq -r '.expected_abi.must_exclude // [] | .[]')
    abis=$(echo "$actual"        | jq -r '.abis // [] | .[]')
    for need in $must_in; do
        local st="FAIL"
        if echo "$abis" | grep -Fxq "$need"; then st="OK"; fi
        _append "$(jq -n --arg st "$st" --arg need "$need" \
            '{category: "abi", check: ("include:" + $need), status: $st,
              expected: $need, actual: "(see abis list)"}')"
    done
    for banned in $must_out; do
        local st="OK"
        if echo "$abis" | grep -Fxq "$banned"; then st="FAIL"; fi
        _append "$(jq -n --arg st "$st" --arg banned "$banned" \
            '{category: "abi", check: ("exclude:" + $banned), status: $st,
              expected: ("NOT " + $banned), actual: "(see abis list)"}')"
    done

    # ---- critical-key safety net (always emit, even if expected has no value) ----
    # In STRICT mode, missing critical keys produce FAIL.
    local crit_appid_actual
    crit_appid_actual=$(echo "$actual" | jq -r --arg k "$_CRITICAL_APP_ID" '.metaData[$k] // ""')
    if [ "${STRICT:-0}" = "1" ]; then
        local crit_appid_expected
        crit_appid_expected=$(echo "$expected" | jq -r --arg k "$_CRITICAL_APP_ID" '.expected_meta_data[$k] // ""')
        if [ -z "$crit_appid_expected" ]; then
            _append "$(jq -n --arg actual "$crit_appid_actual" \
                '{category: "meta-data", check: "com.google.android.gms.games.APP_ID",
                  status: "FAIL",
                  expected: "(unset, critical key required by --strict)",
                  actual: $actual,
                  message: "CRITICAL: GPGS APP_ID must be in expected_meta_data when --strict"}')"
        fi
    else
        local crit_appid_expected
        crit_appid_expected=$(echo "$expected" | jq -r --arg k "$_CRITICAL_APP_ID" '.expected_meta_data[$k] // ""')
        if [ -z "$crit_appid_expected" ]; then
            _append "$(jq -n --arg actual "$crit_appid_actual" \
                '{category: "meta-data", check: "com.google.android.gms.games.APP_ID",
                  status: "WARN",
                  expected: "(unset, recommended critical key)",
                  actual: $actual,
                  message: "Configure the GPGS APP_ID before release."}')"
        fi
    fi

    # ---- application attrs ----
    local want_attrs
    want_attrs=$(echo "$expected" | jq -r '.expected_attributes // {} | keys[]')
    for ak in $want_attrs; do
        local a e actual_key
        actual_key="$ak"
        case "$actual_key" in
            application/@android:*) actual_key="${actual_key#application/@android:}" ;;
        esac
        a=$(echo "$actual" | jq -r --arg k "$actual_key" '
            (.applicationAttrs // {}) as $attrs
            | if ($attrs | has($k)) then ($attrs[$k] | tostring) else "" end
        ')
        e=$(echo "$expected" | jq -r --arg k "$ak" '
            (.expected_attributes // {}) as $attrs
            | if ($attrs | has($k)) then ($attrs[$k] | tostring) else "" end
        ')
        _append "$(_diff_one attrs "$ak" "$e" "$a")"
    done

    local summary
    summary=$(jq -n --argjson ok "$ok" --argjson fail "$fail" --argjson skip "$skip" --argjson warn "$warn" \
        '{ok: $ok, fail: $fail, skip: $skip, warn: $warn,
          total: ($ok + $fail + $skip + $warn)}')

    jq -n \
        --argjson summary  "$summary" \
        --argjson results  "$results" \
        '{ summary: $summary, results: $results }'
}

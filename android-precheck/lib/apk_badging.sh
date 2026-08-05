#!/usr/bin/env bash
# Parse `aapt2 dump badging <apk>` from stdin → emit JSON on stdout.
#
# Usage:
#   aapt2 dump badging <apk> | parse_badging
#
# Emits:
#   { "package": "com.example",
#     "versionCode": "1",
#     "versionName": "1.0.0",
#     "minSdk": "25", "targetSdk": "35", "compileSdk": "35",
#     "label": "My App",
#     "permissions": [ ... ],
#     "abi": [ ... ] }
#
# Tolerates missing fields by emitting empty string.

parse_badging() {
    local package="" versionCode="" versionName=""
    local minSdk="" targetSdk="" compileSdk="" label=""
    local permissions_json="[]" abi_json="[]"
    local pkg="" vc="" vn="" cs="" p="" abi_str=""

    while IFS= read -r line; do
        case "$line" in
            "package: name="*)
                pkg=$(echo "$line"  | sed -nE "s/^package: name='([^']+)'.*/\\1/p")
                vc=$( echo "$line"  | sed -nE "s/.*versionCode='([^']+)'.*/\\1/p")
                vn=$( echo "$line"  | sed -nE "s/.*versionName='([^']+)'.*/\\1/p")
                cs=$( echo "$line"  | sed -nE "s/.*compileSdkVersion='([^']+)'.*/\\1/p")
                [ -n "$pkg" ] && package="$pkg"
                [ -n "$vc" ]  && versionCode="$vc"
                [ -n "$vn" ]  && versionName="$vn"
                [ -n "$cs" ]  && compileSdk="$cs"
                ;;
            "minSdkVersion:"*)
                minSdk=$(echo "$line"   | sed -nE "s/.*'([^']+)'.*/\\1/p")
                ;;
            "targetSdkVersion:"*)
                targetSdk=$(echo "$line"| sed -nE "s/.*'([^']+)'.*/\\1/p")
                ;;
            "application-label:"*)
                label=$(echo "$line"     | sed -nE "s/.*'([^']+)'.*/\\1/p")
                ;;
            "uses-permission:"*)
                p=$(echo "$line" | sed -nE "s/.*name='([^']+)'.*/\\1/p")
                [ -n "$p" ] && permissions_json=$(echo "$permissions_json" | \
                    jq --arg p "$p" '. + [$p]')
                ;;
            "native-code:"*)
                abi_str=$(echo "$line" | sed -nE "s/.*'([^']+)'.*/\\1/p")
                abi_json=$(echo "[]" | jq --arg s "$abi_str" \
                    '$s | split(" ") | map(select(. != ""))')
                ;;
        esac
    done

    jq -n \
        --arg package "$package" \
        --arg versionCode "$versionCode" \
        --arg versionName "$versionName" \
        --arg minSdk "$minSdk" \
        --arg targetSdk "$targetSdk" \
        --arg compileSdk "$compileSdk" \
        --arg label "$label" \
        --argjson permissions "$permissions_json" \
        --argjson abi "$abi_json" \
        '{ package: $package,
           versionCode: $versionCode,
           versionName: $versionName,
           minSdk: $minSdk,
           targetSdk: $targetSdk,
           compileSdk: $compileSdk,
           label: $label,
           permissions: $permissions,
           abi: $abi }'
}

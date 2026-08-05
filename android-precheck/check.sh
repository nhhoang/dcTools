#!/usr/bin/env bash
# android-precheck — Pre-submission Android APK verifier.
# See docs/2026-07-24-android-precheck-design.md for full design.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL_VERSION="0.1.0"

# Source libraries in dependency order.
. "$SCRIPT_DIR/lib/common.sh"
. "$SCRIPT_DIR/lib/env.sh"
. "$SCRIPT_DIR/lib/apk_unpack.sh"
. "$SCRIPT_DIR/lib/apk_badging.sh"
. "$SCRIPT_DIR/lib/apk_manifest.sh"
. "$SCRIPT_DIR/lib/apk_certs.sh"
. "$SCRIPT_DIR/lib/apk_abi.sh"
. "$SCRIPT_DIR/lib/json_diff.sh"
. "$SCRIPT_DIR/lib/report.sh"

# --- Default flags ---
EXPECTED_PATH="keys.json"
STRICT=0
NO_COLOR="${NO_COLOR:-}"
JSON_ONLY=0
MODE="check"
APK=""
HARVEST_OUT=""
FLAVOR=""

usage() {
    cat <<'USAGE'
android-precheck — Pre-submission Android APK verifier.

Usage:
  check.sh <apk>                            Check mode (default)
  check.sh <apk> -e <keys.json> [--strict]  Check with explicit baseline
  check.sh --harvest <apk> [-o <out.json>]  Harvest baseline JSON from APK
  check.sh --self-check                     Verify Android SDK + jq + unzip
  check.sh <apk> --flavor <name>            Apply flavor-specific overrides
  check.sh -h | --help                      Show this help

Options:
  -e, --expected <path>     Path to expected-keys JSON (default: ./keys.json)
  --strict                  Fail if critical key missing
  --no-color                Disable ANSI colors
  --json                    Output only JSON
  --flavor <name>           Apply _flavors.<name> overrides

Exit codes:
  0  All OK (or only SKIP/WARN)
  1  At least one [FAIL]
  2  Bad usage
  3  Environment error
  4  Strict + critical key missing
  5  Harvest I/O error

Examples:
  check.sh build/release.apk
  check.sh build/release.apk -e keys.json --strict
  check.sh --harvest build/release.apk -o keys.json
  check.sh --self-check
USAGE
}

# --- Arg parsing ---
if [ $# -eq 0 ]; then usage; exit "$EXIT_USAGE"; fi

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)     usage; exit 0 ;;
        -v|--version)  echo "android-precheck v$TOOL_VERSION"; exit 0 ;;
        --self-check)
            if require_tools; then
                log_ok "Android SDK + jq + unzip available"
                exit 0
            fi
            exit "$EXIT_ENV"
            ;;
        --harvest)
            MODE="harvest"
            shift
            ;;
        --strict)      STRICT=1; shift ;;
        --no-color)    NO_COLOR=1; shift ;;
        --json)        JSON_ONLY=1; shift ;;
        -e|--expected)
            [ $# -ge 2 ] || { echo "ERROR: $1 needs path" >&2; exit "$EXIT_USAGE"; }
            EXPECTED_PATH="$2"
            shift 2
            ;;
        -o|--out)
            [ $# -ge 2 ] || { echo "ERROR: $1 needs path" >&2; exit "$EXIT_USAGE"; }
            HARVEST_OUT="$2"
            shift 2
            ;;
        --flavor)
            [ $# -ge 2 ] || { echo "ERROR: --flavor needs name" >&2; exit "$EXIT_USAGE"; }
            FLAVOR="$2"
            shift 2
            ;;
        --)
            shift
            [ $# -eq 1 ] || { echo "ERROR: expected exactly one APK path after --" >&2; exit "$EXIT_USAGE"; }
            [ -z "$APK" ] || { echo "ERROR: multiple APK paths supplied" >&2; exit "$EXIT_USAGE"; }
            APK="$1"
            shift
            ;;
        -*)            echo "ERROR: unknown flag $1" >&2; exit "$EXIT_USAGE" ;;
        *)
            [ -z "$APK" ] || { echo "ERROR: multiple APK paths supplied" >&2; exit "$EXIT_USAGE"; }
            APK="$1"
            shift
            ;;
    esac
done

export NO_COLOR STRICT

if [ "$MODE" = "check" ] && [ -n "$HARVEST_OUT" ]; then
    echo "ERROR: --out is only valid with --harvest" >&2
    exit "$EXIT_USAGE"
fi

# --- Validate APK ---
if [ -z "$APK" ] || [ ! -f "$APK" ]; then
    echo "ERROR: APK file not found: ${APK:-<unset>}" >&2
    exit "$EXIT_USAGE"
fi
if [ ! -r "$APK" ]; then
    echo "ERROR: APK file is not readable: $APK" >&2
    exit "$EXIT_USAGE"
fi
case "$APK" in
    *.aab|*.AAB)
        echo "ERROR: AAB is not supported by v0.1; provide an APK generated from the bundle" >&2
        exit "$EXIT_USAGE"
        ;;
esac

# --- Locate Android SDK tools dynamically ---
AAPT2="$(find_aapt2)"
APKSIGNER="$(find_apksigner)"

# --- Sub-routine: collect all parser outputs into one JSON ---
collect_actual_json() {
    local apk="$1" tmp="$2"

    if [ ! -f "$tmp/AndroidManifest.xml" ]; then
        echo "ERROR: archive is not an APK with a root AndroidManifest.xml: $apk" >&2
        return "$EXIT_USAGE"
    fi

    local badging_raw xmltree_raw certs_raw listing_raw
    if ! badging_raw=$("$AAPT2" dump badging "$apk" 2>&1); then
        echo "ERROR: aapt2 could not parse APK badging: $apk" >&2
        printf '%s\n' "$badging_raw" >&2
        return "$EXIT_USAGE"
    fi
    if ! xmltree_raw=$("$AAPT2" dump xmltree "$apk" --file AndroidManifest.xml 2>&1); then
        echo "ERROR: aapt2 could not parse AndroidManifest.xml: $apk" >&2
        printf '%s\n' "$xmltree_raw" >&2
        return "$EXIT_USAGE"
    fi
    certs_raw=$("$APKSIGNER" verify --verbose --print-certs "$apk" 2>&1)
    if ! listing_raw=$(unzip -l "$apk" 2>&1); then
        echo "ERROR: unzip could not list APK contents: $apk" >&2
        printf '%s\n' "$listing_raw" >&2
        return "$EXIT_USAGE"
    fi

    local badging xmltree certs abi
    badging=$(printf '%s\n' "$badging_raw" | parse_badging)
    xmltree=$(printf '%s\n' "$xmltree_raw" | parse_manifest)
    certs=$(printf '%s\n' "$certs_raw" | parse_certs)
    abi=$(printf '%s\n' "$listing_raw" | parse_abi_ls)

    jq -n \
        --argjson b "$badging" \
        --argjson m "$xmltree" \
        --argjson c "$certs" \
        --argjson a "$abi" \
        '{
            package:       $b.package,
            versionCode:   $b.versionCode,
            versionName:   $b.versionName,
            minSdk:        $b.minSdk,
            targetSdk:     $b.targetSdk,
            compileSdk:    $b.compileSdk,
            label:         $b.label,
            permissions:   $b.permissions,
            metaData:      $m.metaData,
            activities:    $m.activities,
            services:      $m.services,
            providers:     $m.providers,
            receivers:     $m.receivers,
            providerAuthorities: $m.providerAuthorities,
            applicationAttrs: $m.applicationAttrs,
            signing:       {
                sha256: $c.sha256,
                sha1:   $c.sha1,
                md5:    $c.md5,
                subjectDN: $c.subjectDN,
                keyAlgo: $c.keyAlgo,
                keySize: $c.keySize,
                publicKeySha256: $c.publicKeySha256,
                schemes: $c.schemes,
                verified: $c.verified
            },
            abis:          $a.abis,
            libraries:     $a.libraries
        }'
}

# --- Mode dispatch ---
case "$MODE" in
    harvest)
        require_tools || exit "$EXIT_ENV"
        tmp=$(apk_unpack "$APK") || exit "$EXIT_USAGE"
        trap 'apk_unpack_cleanup "$tmp"' EXIT

        if ! actual=$(collect_actual_json "$APK" "$tmp"); then
            exit "$EXIT_USAGE"
        fi
        if [ "$(echo "$actual" | jq -r '.signing.verified')" != "true" ]; then
            echo "ERROR: cannot harvest baseline from an APK with an invalid signature" >&2
            exit "$EXIT_USAGE"
        fi
        # Transform "actual" shape → "expected_*" shape so the output can be used
        # directly as a baseline (round-trip). Each meta-data key is preserved.
        if ! harvest=$(printf '%s\n' "$actual" | jq '
            {
              expected_package:            .package,
              expected_version: {
                versionName:  .versionName,
                versionCode_min: (.versionCode // "" | if . == "" then null else tonumber end)
              } | with_entries(select(.value != null and .value != "")),
              expected_sdk: {
                minSdk:     (.minSdk     // "" | if . == "" then null else tonumber end),
                targetSdk:  (.targetSdk  // "" | if . == "" then null else tonumber end),
                compileSdk: (.compileSdk // "" | if . == "" then null else tonumber end)
              } | with_entries(select(.value != null and .value != "")),
              expected_signing: {
                sha256: .signing.sha256,
                sha1:   .signing.sha1,
                md5:    .signing.md5,
                subjectDN: .signing.subjectDN,
                verified: .signing.verified,
                must_use_signature_scheme: .signing.schemes
              } | with_entries(select(.value != null and .value != "")),
              expected_meta_data:   .metaData,
              expected_permissions_present: .permissions,
              expected_components_present: ([
                .activities[], .services[], .providers[], .receivers[],
                (.providerAuthorities | to_entries[] | .value)
              ] | unique),
              expected_abi: {must_include: .abis},
              expected_attributes:  .applicationAttrs | with_entries(select(.value != null and .value != ""))
            } | with_entries(select(.value != null and .value != {} and .value != []))
        '); then
            echo "ERROR: could not transform APK data into a baseline" >&2
            exit "$EXIT_USAGE"
        fi
        if [ -z "$HARVEST_OUT" ]; then
            printf '%s\n' "$harvest" | jq .
            exit 0
        else
            if ! printf '%s\n' "$harvest" | jq . > "$HARVEST_OUT"; then
                echo "ERROR: cannot write $HARVEST_OUT" >&2
                exit "$EXIT_HARVEST_IO"
            fi
            echo "harvest written to $HARVEST_OUT"
            exit 0
        fi
        ;;

    check)
        if [ ! -f "$EXPECTED_PATH" ]; then
            echo "ERROR: expected keys file not found: $EXPECTED_PATH" >&2
            exit "$EXIT_USAGE"
        fi
        if ! jq -e . "$EXPECTED_PATH" >/dev/null 2>&1; then
            echo "ERROR: invalid JSON in $EXPECTED_PATH" >&2
            exit "$EXIT_USAGE"
        fi
        expected=$(jq -c '.' "$EXPECTED_PATH")

        # Apply flavor overrides if specified.
        if [ -n "$FLAVOR" ]; then
            expected=$(echo "$expected" | jq --arg f "$FLAVOR" '
                if ._flavors[$f].expected_attributes then
                    .expected_attributes = (.expected_attributes // {}) +
                        ._flavors[$f].expected_attributes
                else . end')
        fi

        # Strict-mode top-level check: if critical keys missing from expected,
        # fail loudly before running diff.
        if [ "$STRICT" = "1" ]; then
            missing_critical=0
            if [ -z "$(echo "$expected" | jq -r '.expected_signing.sha256 // ""')" ]; then
                echo "[FAIL] CRITICAL: expected_signing.sha256 missing in $EXPECTED_PATH" >&2
                missing_critical=1
            fi
            if [ -z "$(echo "$expected" | jq -r ".expected_meta_data[\"$_CRITICAL_APP_ID\"] // \"\"")" ]; then
                echo "[FAIL] CRITICAL: expected_meta_data[\"$_CRITICAL_APP_ID\"] missing in $EXPECTED_PATH" >&2
                missing_critical=1
            fi
            if [ "$missing_critical" -ne 0 ]; then
                exit "$EXIT_STRICT"
            fi
        fi

        require_tools || exit "$EXIT_ENV"

        tmp=$(apk_unpack "$APK") || exit "$EXIT_USAGE"
        trap 'apk_unpack_cleanup "$tmp"' EXIT

        if ! actual=$(collect_actual_json "$APK" "$tmp"); then
            exit "$EXIT_USAGE"
        fi

        diff_result=$(diff_apk_vs_expected "$actual" "$expected")
        ec=$(echo "$diff_result" | compute_exit_code)
        if [ "$JSON_ONLY" = "1" ]; then
            jq -n \
                --arg tool "android-precheck" \
                --arg version "$TOOL_VERSION" \
                --arg apk "$APK" \
                --arg expected "$EXPECTED_PATH" \
                --arg flavor "$FLAVOR" \
                --argjson exit_code "$ec" \
                --argjson result "$diff_result" \
                '{tool: $tool, version: $version, apk: $apk, expected: $expected,
                  flavor: $flavor, results: $result.results, summary: $result.summary,
                  exit_code: $exit_code}'
        else
            echo "$diff_result" | format_text
        fi
        exit "$ec"
        ;;
esac

# Should not reach here.
echo "ERROR: unhandled mode $MODE" >&2
exit "$EXIT_USAGE"

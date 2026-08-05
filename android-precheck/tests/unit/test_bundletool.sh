#!/usr/bin/env bash
# Unit tests for find_bundletool resolver.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"
LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/bundletool.sh"

BUNDLETOOL_TEST_ROOT="$(mktemp -d -t bundletool-test-XXXXXX)"
ORIG_BUNDLETOOL_JAR="${BUNDLETOOL_JAR:-}"
ORIG_ANDROID_HOME="${ANDROID_HOME:-}"
ORIG_ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-}"
ORIG_HOME="${HOME:-}"
cleanup() {
    rm -rf "$BUNDLETOOL_TEST_ROOT"
    BUNDLETOOL_JAR="$ORIG_BUNDLETOOL_JAR"
    ANDROID_HOME="$ORIG_ANDROID_HOME"
    ANDROID_SDK_ROOT="$ORIG_ANDROID_SDK_ROOT"
    HOME="$ORIG_HOME"
}
trap cleanup EXIT

make_fake_jar() {
    local p="$1"
    mkdir -p "$(dirname "$p")"
    printf "fake-jar\n" > "$p"
}

test_BUNDLETOOL_JAR_wins() {
    local fake="$BUNDLETOOL_TEST_ROOT/override.jar"
    make_fake_jar "$fake"
    BUNDLETOOL_JAR="$fake"
    ANDROID_HOME=""
    ANDROID_SDK_ROOT=""
    HOME="$BUNDLETOOL_TEST_ROOT"
    local out
    out=$(find_bundletool)
    assert_eq "$out" "$fake" "BUNDLETOOL_JAR has highest priority"
}

test_falls_back_to_ANDROID_HOME() {
    local sdk="$BUNDLETOOL_TEST_ROOT/sdk1"
    make_fake_jar "$sdk/bundletool/bundletool.jar"
    BUNDLETOOL_JAR=""
    ANDROID_HOME="$sdk"
    ANDROID_SDK_ROOT=""
    HOME="$BUNDLETOOL_TEST_ROOT"
    local out
    out=$(find_bundletool)
    assert_eq "$out" "$sdk/bundletool/bundletool.jar" "ANDROID_HOME used when BUNDLETOOL_JAR unset"
}

test_falls_back_to_ANDROID_SDK_ROOT() {
    local sdk="$BUNDLETOOL_TEST_ROOT/sdk2"
    make_fake_jar "$sdk/bundletool/bundletool.jar"
    BUNDLETOOL_JAR=""
    ANDROID_HOME=""
    ANDROID_SDK_ROOT="$sdk"
    HOME="$BUNDLETOOL_TEST_ROOT"
    local out
    out=$(find_bundletool)
    assert_eq "$out" "$sdk/bundletool/bundletool.jar" "ANDROID_SDK_ROOT used when ANDROID_HOME unset"
}

test_falls_back_to_mac_default() {
    local home="$BUNDLETOOL_TEST_ROOT/home"
    make_fake_jar "$home/Library/Android/sdk/bundletool/bundletool.jar"
    BUNDLETOOL_JAR=""
    ANDROID_HOME=""
    ANDROID_SDK_ROOT=""
    HOME="$home"
    local out
    out=$(find_bundletool)
    assert_eq "$out" "$home/Library/Android/sdk/bundletool/bundletool.jar" "macOS default Library/Android/sdk is used"
}

test_falls_back_to_linux_default() {
    local home="$BUNDLETOOL_TEST_ROOT/home_linux"
    make_fake_jar "$home/Android/Sdk/bundletool/bundletool.jar"
    BUNDLETOOL_JAR=""
    ANDROID_HOME=""
    ANDROID_SDK_ROOT=""
    HOME="$home"
    local out
    out=$(find_bundletool)
    assert_eq "$out" "$home/Android/Sdk/bundletool/bundletool.jar" "linux default Android/Sdk is used"
}

test_returns_empty_when_missing() {
    BUNDLETOOL_JAR=""
    ANDROID_HOME=""
    ANDROID_SDK_ROOT=""
    HOME="$BUNDLETOOL_TEST_ROOT"
    local out
    out=$(find_bundletool)
    assert_eq "$out" "" "no candidate means empty string"
}

test_never_consults_gradle_cache() {
    local home="$BUNDLETOOL_TEST_ROOT/home_gradle"
    mkdir -p "$home/.gradle/caches/jars-9"
    make_fake_jar "$home/.gradle/caches/jars-9/bundletool-1.99.0.jar"
    BUNDLETOOL_JAR=""
    ANDROID_HOME=""
    ANDROID_SDK_ROOT=""
    HOME="$home"
    local out
    out=$(find_bundletool)
    assert_eq "$out" "" "Gradle cache is ignored"
}

run_tests "$SCRIPT_DIR/test_bundletool.sh"

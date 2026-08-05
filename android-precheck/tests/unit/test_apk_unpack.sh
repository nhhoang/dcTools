#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"

LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/apk_unpack.sh"

# Helper: build a tiny zip fixture if absent.
build_mock_zip() {
    local f="$SCRIPT_DIR/fixtures/mock.zip"
    if [ -f "$f" ]; then echo "$f"; return; fi
    mkdir -p "$SCRIPT_DIR/fixtures"
    local tmp; tmp=$(mktemp -d)
    echo "hello" > "$tmp/a.txt"
    echo "world" > "$tmp/b.txt"
    (cd "$tmp" && zip -qr "$f" a.txt b.txt)
    rm -rf "$tmp"
    echo "$f"
}

test_unpack_creates_dir_and_extracts() {
    local zip; zip=$(build_mock_zip)
    local out
    out=$(apk_unpack "$zip")
    assert_contains "$out" "mock.zip-" "output contains tmp dir suffix"
    [ -d "$out" ] || { _assert_increment_fail "tmp dir exists" "missing: $out"; return; }
    [ -f "$out/a.txt" ] || { _assert_increment_fail "a.txt present" "missing: $out/a.txt"; return; }
    [ -f "$out/b.txt" ] || { _assert_increment_fail "b.txt present" "missing: $out/b.txt"; return; }
    _assert_increment_pass "unpack extracts all entries"
    rm -rf "$out"
}

test_unpack_rejects_non_zip() {
    local tmp; tmp=$(mktemp -d)
    echo "not a zip" > "$tmp/bogus.zip"
    local out
    if apk_unpack "$tmp/bogus.zip" >/dev/null 2>&1; then
        _assert_increment_fail "unpack of bogus should fail" "got success"
    else
        _assert_increment_pass "unpack of bogus zip fails"
    fi
    rm -rf "$tmp"
}

run_tests "$SCRIPT_DIR/test_apk_unpack.sh"

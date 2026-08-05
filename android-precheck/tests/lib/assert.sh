#!/usr/bin/env bash
# Assertion helpers for android-precheck unit tests.
# Loaded via `. tests/lib/assert.sh` from each test_NNN.sh.
#
# Usage signatures:
#   assert_eq <actual> <expected> "<description>"
#   assert_contains <haystack> <needle> "<description>"
#   assert_exit <expected_code> <command...> "<description>"   # desc = last arg

PASSED=0
FAILED=0
TEST_NAME="${TEST_NAME:-unknown}"

_assert_increment_pass() { PASSED=$((PASSED+1)); echo "ok $((PASSED+FAILED)) - $TEST_NAME: $1"; }
_assert_increment_fail() {
    FAILED=$((FAILED+1))
    echo "not ok $((PASSED+FAILED)) - $TEST_NAME: $1"
    shift
    while [ $# -gt 0 ]; do
        echo "      $1"; shift
    done
}

assert_eq() {
    local got="$1" want="$2" desc="$3"
    if [ "$got" = "$want" ]; then
        _assert_increment_pass "$desc"
    else
        _assert_increment_fail "$desc" "got:  $got" "want: $want"
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" desc="$3"
    case "$haystack" in
        *"$needle"*)
            _assert_increment_pass "$desc"
            ;;
        *)
            _assert_increment_fail "$desc" \
                "haystack: $haystack" \
                "needle:   $needle"
            ;;
    esac
}

assert_exit() {
    local want="$1"; shift
    # Last positional param is the description; everything before is the command.
    local desc="${@: -1}"
    if [ "$#" -ge 1 ]; then
        set -- "${@:1:$(($# - 1))}"
    else
        set --
    fi
    if [ "$#" -eq 0 ]; then
        _assert_increment_fail "$desc" \
            "no command supplied to assert_exit"
        return
    fi
    ( "$@" ) >/dev/null 2>&1
    local got=$?
    if [ "$got" = "$want" ]; then
        _assert_increment_pass "$desc"
    else
        _assert_increment_fail "$desc" \
            "got exit:  $got" \
            "want exit: $want" \
            "command:   $*"
    fi
}

#!/usr/bin/env bash
# Iterate `test_*` functions in the current script (loaded via `. runner.sh`),
# then print summary and exit non-zero if any failed.
#
# Usage in test_*.sh:
#   . "$(dirname "$0")/../runner.sh"
#   test_foo() { ... }
#   test_bar() { ... }
#   run_tests "$0"
#
# Each test_* func is invoked; assertion helpers track pass/fail.
# Final summary prints PASSED / FAILED counts and exits 1 if FAILED > 0.

run_tests() {
    local script_path="$1"
    echo "# test script: $script_path"

    # Iterate all declared functions matching `test_*`
    local fns
    fns=$(declare -F | awk '$3 ~ /^test_/ {print $3}')

    if [ -z "$fns" ]; then
        echo "1..0"
        echo "no test_* functions found"
        exit 0
    fi

    local count=0
    for fn in $fns; do
        count=$((count+1))
        TEST_NAME="$fn" "$fn" || true
    done

    local total=$((PASSED+FAILED))
    echo
    echo "1..$total"
    echo "# Passed: $PASSED"
    echo "# Failed: $FAILED"

    if [ "$FAILED" -gt 0 ]; then
        exit 1
    fi
    exit 0
}

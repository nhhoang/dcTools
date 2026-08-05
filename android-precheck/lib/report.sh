#!/usr/bin/env bash
# Format a results JSON (from json_diff) for human or machine consumption.
#
# Functions:
#   format_text        — read JSON from stdin, print lines + summary
#   compute_exit_code  — read JSON from stdin, emit exit code on stdout

# ANSI helpers (re-declare locally so we don't require common.sh).
_colorize() { [ -n "${NO_COLOR:-}" ] && return 1; [ ! -t 1 ] && return 1; return 0; }

_color_wrap() {
    local code="$1"; shift
    if _colorize; then
        printf '\033[%sm%s\033[0m' "$code" "$*"
    else
        printf '%s' "$*"
    fi
}

# Print one result line, color-coded.
_format_one_line() {
    local r="$1"
    local cat check status expected actual msg
    cat=$(    echo "$r" | jq -r '.category')
    check=$(  echo "$r" | jq -r '.check')
    status=$( echo "$r" | jq -r '.status')
    expected=$(echo "$r" | jq -r '.expected // ""')
    actual=$( echo "$r" | jq -r '.actual // ""')
    msg=$(    echo "$r" | jq -r '.message // ""')

    case "$status" in
        OK)    _color_wrap "32" "[OK]   " ;;
        FAIL)  _color_wrap "31;1" "[FAIL] " ;;
        SKIP)  _color_wrap "90" "[SKIP] " ;;
        WARN)  _color_wrap "33" "[WARN] " ;;
        *)     printf '[%s] ' "$status" ;;
    esac
    printf '%-30s %s\n' "$cat/$check" "$expected"
    if [ "$status" = "FAIL" ] && [ -n "$msg" ]; then
        printf '       %s\n' "$msg"
    fi
    if [ "$status" = "FAIL" ] && [ "$expected" != "$actual" ] && [ -n "$actual" ]; then
        printf '       actual: %s\n' "$actual"
    fi
}

format_text() {
    local input
    input=$(cat)
    local count
    count=$(echo "$input" | jq -r '.results | length')
    local i
    for i in $(seq 0 $((count - 1))); do
        _format_one_line "$(echo "$input" | jq -c ".results[$i]")"
    done
    echo
    local summary
    summary=$(echo "$input" | jq -c '.summary')
    local ok fail skip warn total
    ok=$(   echo "$summary" | jq -r '.ok')
    fail=$( echo "$summary" | jq -r '.fail')
    skip=$( echo "$summary" | jq -r '.skip')
    warn=$( echo "$summary" | jq -r '.warn')
    total=$(echo "$summary" | jq -r '.total')
    printf 'SUMMARY: %d OK, %d FAIL, %d SKIP, %d WARN (total %d)\n' "$ok" "$fail" "$skip" "$warn" "$total"
}

compute_exit_code() {
    local input
    input=$(cat)
    local fail
    fail=$(echo "$input" | jq -r '.summary.fail')
    if [ "$fail" -gt 0 ]; then
        echo "1"
    else
        echo "0"
    fi
}

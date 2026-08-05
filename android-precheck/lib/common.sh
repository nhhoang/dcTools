#!/usr/bin/env bash
# Output helpers and exit code constants.
# Source-only library; no side-effects.

_colorize() {
    [ -n "${NO_COLOR:-${NO_COLOR_CLAUSE:-}}" ] && return 1
    [ ! -t 1 ] && return 1
    return 0
}

# Codes:
#   red     31  FAIL
#   green   32  OK
#   yellow  33  WARN
#   grey    90  SKIP
#   bold    1
#   reset   0

_log_color() {
    local code="$1"; shift
    if _colorize; then
        printf '\033[%sm%s\033[0m\n' "$code" "$*"
    else
        printf '%s\n' "$*"
    fi
}

log_ok()    { _log_color "32" "[OK]    $*"; }
log_fail()  { _log_color "31;1" "[FAIL]  $*"; }
log_skip()  { _log_color "90" "[SKIP]  $*"; }
log_warn()  { _log_color "33" "[WARN]  $*"; }
log_info()  { printf '%s\n' "$*"; }

log_header() {
    log_info "── $* ────────────────────────────────────────────────────"
}

# Exit codes — must match design §4.3.
EXIT_OK=0
EXIT_FAIL=1
EXIT_USAGE=2
EXIT_ENV=3
EXIT_STRICT=4
EXIT_HARVEST_IO=5

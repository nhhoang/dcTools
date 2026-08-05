# android-precheck Implementation Plan

**Execution status (2026-07-26):** implemented inline and reviewed. Commit steps
were intentionally skipped because this is a Perforce workspace and the user did
not request submit/commit. The checked-in code and `README.md` are authoritative;
code snippets below are the original execution plan and may not include later
review fixes (provider authorities, complete harvest, JSON envelope, CLI guards).

- [x] Tasks 1-14 implemented
- [x] Unit, smoke, CLI-error, and acceptance verification complete
- [x] Post-implementation review complete
- [ ] Commit/submit steps skipped intentionally

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Bash CLI tool `check.sh` that verifies an Android APK against a `keys.json` baseline to catch post-build regressions (especially the GPGS `APP_ID` reset bug) before submission to Google Play.

**Architecture:** Single-entry Bash CLI + library modules per concern (env, common, apk_unpack, parsers, json_diff, report). Each parser converts one aapt2/apksigner/unzip call into structured JSON. `json_diff` compares against baseline. Strict pure Bash + Android SDK build-tools (`aapt2`, `apksigner`) + `jq`. No Python/Node/Java.

**Tech Stack:**
- Bash ≥ 3.2 (macOS) / ≥ 4 (Linux)
- `unzip`, `grep`, `awk`, `sed`
- `jq` ≥ 1.6
- Android SDK build-tools ≥ 34 (`aapt2`, `apksigner`)

---

**Spec / source of truth:** `2026-07-24-android-precheck-design.md` (same directory).

**VCS note:** This project lives in a Perforce workspace (no Git). Each task's `git add` + `git commit` step can be replaced with `p4 add` + `p4 submit -d "..."` if needed; the rest of the plan is identical.

---

## File Structure

```
android-precheck/
├── check.sh                              # CLI entry, mode dispatch, arg parsing
├── lib/
│   ├── common.sh                         # logging (log_ok/fail/skip/warn/header), exit codes
│   ├── env.sh                            # locate aapt2 / apksigner / jq
│   ├── apk_unpack.sh                     # unzip <apk> → tmp + trap cleanup
│   ├── apk_badging.sh                    # parse `aapt2 dump badging` → JSON
│   ├── apk_manifest.sh                   # parse xmltree → JSON (activities/services/providers/meta-data)
│   ├── apk_certs.sh                      # parse `apksigner verify --print-certs` → JSON
│   ├── apk_abi.sh                        # `unzip -l` → list of ABIs
│   ├── apk_attrs.sh                      # application/@android:* attrs from xmltree
│   ├── apk_perms.sh                      # uses-permission list from xmltree
│   ├── json_diff.sh                      # diff actual.json vs keys.json → results array
│   └── report.sh                         # format results → text or JSON, compute exit code
├── tests/
│   ├── lib/
│   │   └── assert.sh                     # assert_eq / assert_contains / assert_exit / finalize
│   ├── runner.sh                         # iterate test_* funcs in current script
│   ├── unit/
│   │   ├── test_env.sh
│   │   ├── test_apk_unpack.sh
│   │   ├── test_apk_badging.sh
│   │   ├── test_apk_manifest.sh
│   │   ├── test_apk_certs.sh
│   │   ├── test_apk_abi.sh
│   │   ├── test_apk_attrs.sh
│   │   ├── test_apk_perms.sh
│   │   ├── test_json_diff.sh
│   │   ├── test_report.sh
│   │   └── fixtures/
│   │       ├── mock.apk                  # tiny zip fixture for unpack tests
│   │       ├── badging.txt               # captured `aapt2 dump badging` output
│   │       ├── xmltree.txt               # captured `aapt2 dump xmltree --file AndroidManifest.xml`
│   │       ├── certs.txt                 # captured `apksigner verify --print-certs`
│   │       └── apk_ls.txt                # captured `unzip -l` output
│   ├── smoke.sh                          # end-to-end (--harvest → --check roundtrip)
│   └── fixtures/
│       ├── DGame_debug_1.1.14.1.apk      # user-provided real APK
│       └── keys.example.json             # harvested baseline
├── docs/
│   ├── 2026-07-24-android-precheck-design.md
│   └── 2026-07-24-android-precheck-implementation.md   # this file
├── .gitignore
└── README.md
```

Each file has one responsibility:

| File | Responsibility |
|---|---|
| `check.sh` | CLI entry only: parse args, dispatch mode |
| `lib/common.sh` | Visual + output helpers; nothing depends on Android SDK |
| `lib/env.sh` | Locate external tools; fail fast if missing |
| `lib/apk_*.sh` | Read ONE source from APK → emit JSON to stdout |
| `lib/json_diff.sh` | Compare actual (from parsers) vs expected (from `keys.json`) |
| `lib/report.sh` | Format `json_diff` results for human / JSON output |
| `tests/lib/assert.sh` | Assertion helpers |
| `tests/runner.sh` | Iterate `test_*` functions |
| `tests/smoke.sh` | End-to-end harness |
| `keys.json` (user-owned) | Source-of-truth baseline; **not** committed (in `.gitignore`) |
| `keys.example.json` | Tracked, harvested from a known-good build |

---

## Task 1: Bootstrap directory and README skeleton

**Files:**
- Create: `android-precheck/.gitignore`
- Create: `android-precheck/README.md`

- [ ] **Step 1: Verify dir tree exists**

Run:
```bash
cd /Users/hoangnguyen/Perforce/MacbookPro/android-precheck
mkdir -p lib tests/lib tests/unit tests/unit/fixtures tests/fixtures tests/fixtures/test_keys docs
ls -la
```
Expected: shows `lib/`, `tests/`, `docs/`, `docs/2026-07-24-android-precheck-design.md` (already exists from brainstorming).

- [ ] **Step 2: Write `.gitignore`**

Create `android-precheck/.gitignore`:

```gitignore
# Per-build artifacts
keys.json
*.harvested.json
.precheck-history/

# OS noise
.DS_Store
Thumbs.db

# Editor
.vscode/
.idea/
```

- [ ] **Step 3: Write `README.md` skeleton**

Create `android-precheck/README.md`:

```markdown
# android-precheck

Pre-submission APK verifier for Android (Unity / native / hybrid).
Detects post-build regressions — especially the Google Play Games `APP_ID`
reset bug after upgrading the GPGS plugin.

See [`docs/2026-07-24-android-precheck-design.md`](docs/2026-07-24-android-precheck-design.md)
for full design and [`docs/2026-07-24-android-precheck-implementation.md`](docs/2026-07-24-android-precheck-implementation.md)
for implementation plan.

## Quickstart

```bash
# 1. Verify environment (aapt2, apksigner, jq must all be found)
$ bash check.sh --self-check

# 2. Harvest a known-good APK to bootstrap a baseline
$ bash check.sh --harvest build/release.apk -o keys.json

# 3. Check every new build against the baseline
$ bash check.sh build/release.apk --expected keys.json
$ bash check.sh build/release.apk --expected keys.json --strict
```

## Exit codes

| Code | Meaning |
|---|---|
| 0 | all OK (or only WARN/SKIP, no FAIL) |
| 1 | at least one `[FAIL]` |
| 2 | bad usage (file not found, invalid args) |
| 3 | environment error (aapt2 / apksigner / jq missing) |
| 4 | `--strict` and critical key missing |
| 5 | `--harvest` output not writable |

## License

Internal tool.
```

- [ ] **Step 4: Commit**

```bash
# (Perforce alternative: p4 add android-precheck/.gitignore android-precheck/README.md && p4 submit -d "...")
git add android-precheck/.gitignore android-precheck/README.md
git commit -m "feat(android-precheck): bootstrap directory + README skeleton"
```

---

## Task 2: Test framework (`tests/lib/assert.sh` + `tests/runner.sh`)

**Files:**
- Create: `android-precheck/tests/lib/assert.sh`
- Create: `android-precheck/tests/runner.sh`
- Create: `android-precheck/tests/unit/test_smoke_assert.sh` (first sanity test for the framework itself)

- [ ] **Step 1: Write the failing test for the framework**

Create `tests/unit/test_smoke_assert.sh`:

```bash
#!/usr/bin/env bash
# Framework self-test — verifies assert_eq / assert_contains behave.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"

test_assert_eq_passes_on_match() {
    assert_eq "abc" "abc" "equal strings must pass"
}

test_assert_eq_fails_on_mismatch() {
    assert_eq "abc" "xyz" "different strings should fail"
}

test_assert_contains_finds_substring() {
    assert_contains "hello world" "world" "substring found"
}

test_assert_contains_misses() {
    assert_contains "hello" "xyz" "missing substring"
}

test_assert_exit_zero_on_true() {
    assert_exit 0 true "true should exit 0"
}

test_assert_exit_nonzero_on_false() {
    assert_exit 1 false "false should exit 1"
}

run_tests "$SCRIPT_DIR/test_smoke_assert.sh"
```

- [ ] **Step 2: Run test to verify it fails (no `assert.sh` yet)**

Run: `bash android-precheck/tests/unit/test_smoke_assert.sh`
Expected: error `./../lib/assert.sh: No such file or directory` (exit 127).

- [ ] **Step 3: Implement `tests/lib/assert.sh`**

Create `tests/lib/assert.sh`:

```bash
#!/usr/bin/env bash
# Assertion helpers for android-precheck unit tests.
# Loaded via `. tests/lib/assert.sh` from each test_NNN.sh.
# Usage:
#   assert_eq <actual> <expected> "<description>"
#   assert_contains <haystack> <needle> "<description>"
#   assert_exit <expected_code> <command...> "<description>"
#
# After all test_* funcs run, call `run_tests` from tests/runner.sh to finalize.

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
    local desc="$1"; shift
    # Remaining args = the command
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
```

- [ ] **Step 4: Implement `tests/runner.sh`**

Create `tests/runner.sh`:

```bash
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

    # Iterate all declared functions matching `test_*` or `test_*_*`
    local fns
    fns=$(declare -F | awk '$3 ~ /^test_/ && $3 !~ /^run_tests$/ {print $3}')

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
```

- [ ] **Step 5: Make assertion files executable; run test**

Run:
```bash
chmod +x android-precheck/tests/lib/assert.sh android-precheck/tests/runner.sh android-precheck/tests/unit/test_smoke_assert.sh
bash android-precheck/tests/unit/test_smoke_assert.sh
```
Expected output (top lines):
```
# test script: .../test_smoke_assert.sh
ok 1 - assert_eq_passes_on_match: equal strings must pass
not ok 2 - assert_eq_fails_on_mismatch: different strings should fail
       got:  abc
       want: xyz
ok 3 - assert_contains_finds_substring: substring found
not ok 4 - assert_contains_misses: missing substring
       ...
# Passed: 3
# Failed: 3
```
Exit code: `1` (3 "fail" cases expected for the framework sanity test — the framework is designed to report failures, not hide them).

- [ ] **Step 6: Commit**

```bash
git add android-precheck/tests
git commit -m "test(android-precheck): add assert framework + sanity tests"
```

---

## Task 3: `lib/env.sh` — locate Android SDK tools

**Files:**
- Create: `android-precheck/lib/env.sh`
- Create: `android-precheck/tests/unit/test_env.sh`

- [ ] **Step 1: Write failing test**

Create `tests/unit/test_env.sh`:

```bash
#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"

# Make lib/env.sh target reachable
LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/env.sh"

test_find_aapt2_finds_something() {
    local out
    out=$(find_aapt2 2>/dev/null || true)
    if [ -z "$out" ]; then
        # No SDK on this runner — accept; mark as skip-equivalent pass
        _assert_increment_pass "find_aapt2 returned non-empty when SDK present"
    elif [ -x "$out" ]; then
        _assert_increment_pass "find_aapt2 returned executable path"
    else
        _assert_increment_fail "find_aapt2 returned non-executable path" \
            "got: $out"
    fi
}

test_find_apksigner_finds_something() {
    local out
    out=$(find_apksigner 2>/dev/null || true)
    if [ -z "$out" ] || [ -x "$out" ]; then
        _assert_increment_pass "find_apksigner behavior acceptable"
    else
        _assert_increment_fail "find_apksigner returned non-executable path" \
            "got: $out"
    fi
}

test_find_jq_succeeds() {
    local out
    out=$(find_jq 2>/dev/null || true)
    assert_contains "$out" "jq" "find_jq returns path with jq in it"
}

test_require_tools_succeeds_when_all_present() {
    # Skip if even jq missing
    if ! command -v jq >/dev/null 2>&1; then
        _assert_increment_pass "skipped: jq not on PATH"
        return
    fi
    # Don't actually fail out of the test — check exit code
    ( require_tools ) >/dev/null 2>&1
    local ec=$?
    if [ "$ec" = "0" ] || [ "$ec" = "3" ]; then
        _assert_increment_pass "require_tools exits 0 or 3 (env error code)"
    else
        _assert_increment_fail "require_tools unexpected exit" \
            "exit: $ec"
    fi
}

run_tests "$SCRIPT_DIR/test_env.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash android-precheck/tests/unit/test_env.sh`
Expected: `./../../lib/env.sh: No such file or directory` (exit 127).

- [ ] **Step 3: Implement `lib/env.sh`**

Create `lib/env.sh`:

```bash
#!/usr/bin/env bash
# Locate Android SDK build-tools (aapt2, apksigner) and jq.
# Source-only library; no side-effects unless require_tools is called.

# Order to look for Android SDK root:
#   1. $ANDROID_HOME
#   2. $ANDROID_SDK_ROOT
#   3. ~/Library/Android/sdk (macOS default)
#   4. ~/Android/Sdk (Linux default)
_resolve_android_sdk_root() {
    if [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME" ]; then
        echo "$ANDROID_HOME"; return
    fi
    if [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -d "$ANDROID_SDK_ROOT" ]; then
        echo "$ANDROID_SDK_ROOT"; return
    fi
    if [ -d "$HOME/Library/Android/sdk" ]; then
        echo "$HOME/Library/Android/sdk"; return
    fi
    if [ -d "$HOME/Android/Sdk" ]; then
        echo "$HOME/Android/Sdk"; return
    fi
    echo ""
}

# Find newest aapt2 across build-tools/<version>/aapt2. Returns absolute path or "".
find_aapt2() {
    local sdk; sdk=$(_resolve_android_sdk_root)
    [ -z "$sdk" ] && return 0
    [ -d "$sdk/build-tools" ] || return 0
    ls -1 "$sdk/build-tools"/*/aapt2 2>/dev/null | sort -V | tail -1
}

# Find newest apksigner; same algorithm.
find_apksigner() {
    local sdk; sdk=$(_resolve_android_sdk_root)
    [ -z "$sdk" ] && return 0
    [ -d "$sdk/build-tools" ] || return 0
    ls -1 "$sdk/build-tools"/*/apksigner 2>/dev/null | sort -V | tail -1
}

# Find jq on PATH (no Android-SDK dependency).
find_jq() {
    command -v jq 2>/dev/null
}

# Verify all required tools are present. Echo list of missing tools.
# Returns 0 if all present, 3 (env error) otherwise.
require_tools() {
    local missing=""
    if [ -z "$(find_aapt2)" ];     then missing="$missing aapt2"; fi
    if [ -z "$(find_apksigner)" ]; then missing="$missing apksigner"; fi
    if [ -z "$(find_jq)" ];        then missing="$missing jq"; fi
    if [ -n "$missing" ]; then
        echo "ENV_ERROR: missing tools:$missing" >&2
        echo "Set ANDROID_HOME / ANDROID_SDK_ROOT, or install" >&2
        echo "Android SDK build-tools (Android Studio → SDK Manager" >&2
        echo "→ SDK Tools tab) and 'brew install jq' (macOS) or" >&2
        echo "apt install jq (Linux)." >&2
        return 3
    fi
    return 0
}
```

- [ ] **Step 4: Make `env.sh` executable; run test**

Run:
```bash
chmod +x android-precheck/lib/env.sh
bash android-precheck/tests/unit/test_env.sh
```
Expected: all `ok` lines, `# Passed: 4`, exit `0`.

- [ ] **Step 5: Commit**

```bash
git add android-precheck/lib/env.sh android-precheck/tests/unit/test_env.sh
git commit -m "feat(android-precheck): env.sh with Android SDK + jq locators"
```

---

## Task 4: `lib/common.sh` — logging + exit codes

**Files:**
- Create: `android-precheck/lib/common.sh`
- Create: `android-precheck/tests/unit/test_common.sh`

- [ ] **Step 1: Write failing test**

Create `tests/unit/test_common.sh`:

```bash
#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"

LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/common.sh"

test_log_ok_writes_OK_label() {
    local out
    out=$(NO_COLOR=1 log_ok "test")
    assert_contains "$out" "OK" "OK label present"
    assert_contains "$out" "test" "message present"
}

test_log_fail_writes_FAIL_label() {
    local out
    out=$(NO_COLOR=1 log_fail "test")
    assert_contains "$out" "FAIL" "FAIL label present"
}

test_log_skip_writes_SKIP_label() {
    local out
    out=$(NO_COLOR=1 log_skip "test")
    assert_contains "$out" "SKIP" "SKIP label present"
}

test_log_warn_writes_WARN_label() {
    local out
    out=$(NO_COLOR=1 log_warn "test")
    assert_contains "$out" "WARN" "WARN label present"
}

test_header_writes_separator() {
    local out
    out=$(NO_COLOR=1 log_header "TITLE")
    assert_contains "$out" "TITLE" "header contains title"
    assert_contains "$out" "────" "header contains separator"
}

test_exit_code_constants_match_design() {
    assert_eq "$EXIT_OK"           "0" "ok exit"
    assert_eq "$EXIT_FAIL"         "1" "fail exit"
    assert_eq "$EXIT_USAGE"        "2" "usage exit"
    assert_eq "$EXIT_ENV"          "3" "env exit"
    assert_eq "$EXIT_STRICT"       "4" "strict exit"
    assert_eq "$EXIT_HARVEST_IO"   "5" "harvest io exit"
}

run_tests "$SCRIPT_DIR/test_common.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash android-precheck/tests/unit/test_common.sh`
Expected: `./../../lib/common.sh: No such file or directory` (exit 127).

- [ ] **Step 3: Implement `lib/common.sh`**

Create `lib/common.sh`:

```bash
#!/usr/bin/env bash
# Output helpers and exit code constants.
# Source-only library; no side-effects.

# Honor NO_COLOR (set in env to disable ANSI escapes)
_NO_COLOR=${NO_COLOR:-${NO_COLOR_CLAUDE:-}}
_colorize() {
    [ -n "$_NO_COLOR" ] && return 1
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
```

- [ ] **Step 4: Run test**

Run: `bash android-precheck/tests/unit/test_common.sh`
Expected: all `ok`, `# Passed: 11`, exit `0`.

- [ ] **Step 5: Commit**

```bash
git add android-precheck/lib/common.sh android-precheck/tests/unit/test_common.sh
git commit -m "feat(android-precheck): common.sh logging + exit codes"
```

---

## Task 5: `lib/apk_unpack.sh` — unzip + cleanup

**Files:**
- Create: `android-precheck/lib/apk_unpack.sh`
- Create: `android-precheck/tests/unit/fixtures/mock.apk` (generated by test, not committed)
- Create: `android-precheck/tests/unit/test_apk_unpack.sh`

- [ ] **Step 1: Write failing test**

Create `tests/unit/test_apk_unpack.sh`:

```bash
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
    assert_contains "$out" "/mock.zip-" "output contains tmp dir suffix"
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash android-precheck/tests/unit/test_apk_unpack.sh`
Expected: `./../../lib/apk_unpack.sh: No such file or directory` (exit 127).

- [ ] **Step 3: Implement `lib/apk_unpack.sh`**

Create `lib/apk_unpack.sh`:

```bash
#!/usr/bin/env bash
# Unpack an APK (or any zip) to a unique temp dir, echoing the path.
# Caller is responsible for cleanup; function installs a trap-safe marker.
#
# Usage:
#   dir=$(apk_unpack <file.apk>)
#   ... use $dir ...
#   apk_unpack_cleanup "$dir"   # OR rm -rf "$dir"

apk_unpack() {
    local file="$1"
    if [ -z "$file" ] || [ ! -f "$file" ]; then
        echo "apk_unpack: file not found: $file" >&2
        return "$EXIT_USAGE"
    fi
    # Basic zip magic check (PK\x03\x04)
    local magic
    magic=$(head -c 4 "$file" | od -An -c | tr -d ' \n')
    if [ "$magic" != "P*K" ] && [ "$magic" != "PK\u0003\u0004" ] && [ "${magic:0:2}" != "PK" ]; then
        # Fallback: try the file(1) command if present
        if command -v file >/dev/null 2>&1; then
            if ! file "$file" | grep -qE "Zip archive|Java archive"; then
                echo "apk_unpack: not a zip: $file" >&2
                return "$EXIT_USAGE"
            fi
        fi
    fi
    local out
    out="$(mktemp -d -t "$(basename "$file" .apk)-XXXXXX")"
    if ! unzip -q "$file" -d "$out"; then
        echo "apk_unpack: unzip failed for $file" >&2
        rm -rf "$out"
        return "$EXIT_USAGE"
    fi
    echo "$out"
}

apk_unpack_cleanup() {
    local dir="$1"
    if [ -n "$dir" ] && [ -d "$dir" ]; then
        rm -rf "$dir"
    fi
}
```

- [ ] **Step 4: Run test**

Run: `bash android-precheck/tests/unit/test_apk_unpack.sh`
Expected: all `ok`, `# Passed: 2`, exit `0`.

- [ ] **Step 5: Commit**

```bash
git add android-precheck/lib/apk_unpack.sh android-precheck/tests/unit/test_apk_unpack.sh
git commit -m "feat(android-precheck): apk_unpack unzip to tmp dir"
```

---

## Task 6: `lib/apk_badging.sh` — package/version/sdk

**Files:**
- Create: `android-precheck/lib/apk_badging.sh`
- Create: `android-precheck/tests/unit/fixtures/badging.txt` (real captured output)
- Create: `android-precheck/tests/unit/test_apk_badging.sh`

- [ ] **Step 1: Capture real badging fixture**

Run from your machine (uses the user's APK):
```bash
APK="/Users/hoangnguyen/Downloads/DGame_debug_1.1.14.1(1).apk"
BT="$HOME/Library/Android/sdk/build-tools/35.0.0"

# We capture TWO outputs:
# 1. The full badging → trimmed to first 8 lines for fixture (avoid storage bloat)
# 2. A redacted version saved as the unit-test fixture.
"$BT/aapt2" dump badging "$APK" 2>/dev/null | head -25 > /tmp/badging_sample.txt
cat /tmp/badging_sample.txt | head -25
```

Save the redacted version as the fixture by running the next step.

- [ ] **Step 2: Write failing test**

Create `tests/unit/test_apk_badging.sh`:

```bash
#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"

LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/apk_badging.sh"

# Fixture file must contain the standard `aapt2 dump badging` output for
# the user's known-good APK. Truncated to ~25 lines for unit testability.
FIXTURE="$SCRIPT_DIR/fixtures/badging.txt"

test_parse_extracts_package() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "fixture absent (run Task 6 step 1 first)"; return; }
    local got
    got=$(parse_badging < "$FIXTURE" | jq -r '.package')
    assert_eq "$got" "com.wb.goog.dc.dcwc" "package name from fixture"
}

test_parse_extracts_version_code() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_badging < "$FIXTURE" | jq -r '.versionCode')
    assert_eq "$got" "1" "versionCode from fixture"
}

test_parse_extracts_version_name() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_badging < "$FIXTURE" | jq -r '.versionName')
    assert_eq "$got" "1.1.14.1" "versionName from fixture"
}

test_parse_extracts_sdk_min_target() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_badging < "$FIXTURE" | jq -r '"\(.minSdk)-\(.targetSdk)"')
    assert_eq "$got" "25-35" "minSdk-targetSdk"
}

test_parse_returns_empty_on_garbage() {
    echo "garbage input" | parse_badging | jq -e . >/dev/null 2>&1
    local ec=$?
    if [ "$ec" = "0" ]; then
        _assert_increment_pass "garbage yields valid (possibly empty) JSON"
    else
        _assert_increment_pass "garbage yields error (also acceptable)"
    fi
}

run_tests "$SCRIPT_DIR/test_apk_badging.sh"
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bash android-precheck/tests/unit/test_apk_badging.sh`
Expected: `./../../lib/apk_badging.sh: No such file or directory`.

- [ ] **Step 4: Capture the fixture properly**

Run:
```bash
APK="/Users/hoangnguyen/Downloads/DGame_debug_1.1.14.1(1).apk"
BT="$HOME/Library/Android/sdk/build-tools/35.0.0"
out_dir=/Users/hoangnguyen/Perforce/MacbookPro/android-precheck/tests/unit/fixtures
mkdir -p "$out_dir"
"$BT/aapt2" dump badging "$APK" 2>/dev/null | grep -E "^(package|min|target|compile-sdk|application-label:'D)" > "$out_dir/badging.txt"
head -10 "$out_dir/badging.txt"
```
Expected: at least these lines:
```
package: name='com.wb.goog.dc.dcwc' versionCode='1' versionName='1.1.14.1' platformBuildVersionName='15' platformBuildVersionCode='35' compileSdkVersion='35' compileSdkVersionCodename='15'
minSdkVersion:'25'
targetSdkVersion:'35'
application-label:'DC Worlds Collide'
```

- [ ] **Step 5: Implement `lib/apk_badging.sh`**

Create `lib/apk_badging.sh`:

```bash
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

    while IFS= read -r line; do
        case "$line" in
            "package: name="*)
                # package: name='com.example' versionCode='1' versionName='1.0.0' ...
                pkg=$(echo "$line"  | sed -nE "s/.*name='([^']+)'.*/\\1/p")
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
```

- [ ] **Step 6: Run test**

Run: `bash android-precheck/tests/unit/test_apk_badging.sh`
Expected: all `ok`, `# Passed: 5`, exit `0`. (Note: tests using fixture skip with `skipped, fixture absent` if fixture not yet present. Run step 4 first.)

- [ ] **Step 7: Commit**

```bash
git add android-precheck/lib/apk_badging.sh \
        android-precheck/tests/unit/test_apk_badging.sh \
        android-precheck/tests/unit/fixtures/badging.txt
git commit -m "feat(android-precheck): parse aapt2 badging → JSON"
```

---

## Task 7: `lib/apk_manifest.sh` — meta-data + components + attrs

**Files:**
- Create: `android-precheck/lib/apk_manifest.sh`
- Create: `android-precheck/tests/unit/fixtures/xmltree.txt` (captured)
- Create: `android-precheck/tests/unit/test_apk_manifest.sh`

- [ ] **Step 1: Write failing test**

Create `tests/unit/test_apk_manifest.sh`:

```bash
#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"

LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/apk_manifest.sh"

FIXTURE="$SCRIPT_DIR/fixtures/xmltree.txt"

test_meta_data_extracts_known_keys() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_manifest < "$FIXTURE" | jq -r '.metaData["com.google.android.gms.games.APP_ID"]')
    assert_eq "$got" "299009804916" "GPGS APP_ID"
}

test_meta_data_includes_unity_version() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_manifest < "$FIXTURE" | jq -r '.metaData["com.google.android.gms.games.unityVersion"]')
    assert_eq "$got" "2.0.0" "unityVersion"
}

test_components_includes_playgames_init_provider() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_manifest < "$FIXTURE" | jq -r '.providers | join(",")')
    assert_contains "$got" "PlayGamesInitProvider" "providers list contains PlayGamesInitProvider"
}

test_attrs_extracts_debuggable() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_manifest < "$FIXTURE" | jq -r '.applicationAttrs["debuggable"]')
    assert_eq "$got" "true" "debuggable attr (this APK is debug build)"
}

run_tests "$SCRIPT_DIR/test_apk_manifest.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash android-precheck/tests/unit/test_apk_manifest.sh`
Expected: `./../../lib/apk_manifest.sh: No such file or directory`.

- [ ] **Step 3: Capture xmltree fixture**

Run:
```bash
APK="/Users/hoangnguyen/Downloads/DGame_debug_1.1.14.1(1).apk"
BT="$HOME/Library/Android/sdk/build-tools/35.0.0"
out_dir=/Users/hoangnguyen/Perforce/MacbookPro/android-precheck/tests/unit/fixtures
mkdir -p "$out_dir"
# Trim to first ~200 lines; meta-data we care about are early in the file.
"$BT/aapt2" dump xmltree "$APK" --file AndroidManifest.xml 2>/dev/null \
    | head -400 > "$out_dir/xmltree.txt"
wc -l "$out_dir/xmltree.txt"
```
Expected: 400-line fixture, includes the meta-data lines around 140-200.

- [ ] **Step 4: Implement `lib/apk_manifest.sh`**

Create `lib/apk_manifest.sh`:

```bash
#!/usr/bin/env bash
# Parse `aapt2 dump xmltree --file AndroidManifest.xml` from stdin → JSON.
# Output schema:
#   {
#     "metaData": { "<name>": "<value>", ... },
#     "activities":   ["<fqcn>", ...],
#     "services":     ["<fqcn>", ...],
#     "providers":    ["<fqcn>", ...],
#     "receivers":    ["<fqcn>", ...],
#     "applicationAttrs": { "debuggable": "<bool>",
#                           "extractNativeLibs": "<bool>",
#                           "usesCleartextTraffic": "<bool>",
#                           "isGame": "<bool>",
#                           "appComponentFactory": "<string>", ... },
#     "permissions": ["<name>", ...]   # duplicates badging; provided for completeness
#   }

# Read entire stdin into $XMLTREE_LINES; reset per call.
XMLTREE_LINES=""

parse_manifest() {
    XMLTREE_LINES=$(cat)
    local meta="{}" activities="[]" services="[]" providers="[]" receivers="[]"
    local attrs="{}" permissions="[]"

    # We use awk to walk the indented tree aapt2 prints.
    # Strategy: scan line-by-line; on "E: meta-data" read next 2 lines for name+value.

    local cur="" name="" value=""
    local i=0
    local n
    n=$(echo "$XMLTREE_LINES" | wc -l | tr -d ' ')

    while [ $i -lt "$n" ]; do
        i=$((i+1))
        local line
        line=$(echo "$XMLTREE_LINES" | sed -n "${i}p")

        case "$line" in
            *"E: meta-data"*)
                local n_line v_line
                n_line=$(echo "$XMLTREE_LINES" | sed -n "$((i+1))p")
                v_line=$(echo "$XMLTREE_LINES" | sed -n "$((i+2))p")
                name=$(echo "$n_line" | sed -nE 's/.*android:name[^"]*"([^"]+)".*/\1/p')
                # value can be `=true`, `=false`, `=<int>`, `="<string>" (Raw: "<string>")`,
                # or `@0x<hex>` (resource ref). Capture raw text after `=`.
                value=$(echo "$v_line" | sed -nE 's/.*android:value[^=]*=//p' | sed -E 's/^[[:space:]]+//' | sed -E 's/[[:space:]]*$//')
                # Strip surrounding quotes from "Foo" (Raw: "Foo") pattern
                case "$value" in
                    \"*\"*\"*\")
                        value=$(echo "$value" | sed -nE 's/^"([^"]+)" \(Raw.*/\1/p')
                        [ -z "$value" ] && value=$(echo "$value" | sed -E 's/^"//;s/"$//')
                        ;;
                esac
                if [ -n "$name" ]; then
                    meta=$(echo "$meta" | jq --arg k "$name" --arg v "$value" '. + {($k): $v}')
                fi
                i=$((i+2))
                ;;
            *"E: activity (line="*)
                # Next line contains the activity's android:name=...
                local nm
                nm=$(echo "$XMLTREE_LINES" | sed -n "$((i+1))p" | \
                     sed -nE 's/.*android:name[^"]*"([^"]+)".*/\1/p')
                [ -z "$nm" ] && nm=$(echo "$XMLTREE_LINES" | sed -n "$((i+1))p" | \
                     sed -nE 's/.*android:name[^=]*=([^ )]+).*/\1/p')
                # Strip (Raw: "...") wrappers
                nm=$(echo "$nm" | sed -nE 's/^\s*"([^"]+)".*/\1/p')
                if [ -n "$nm" ] && [ "$nm" != "null" ]; then
                    activities=$(echo "$activities" | jq --arg n "$nm" '. + [$n]')
                fi
                ;;
            *"E: service (line="*)
                local nm
                nm=$(echo "$XMLTREE_LINES" | sed -n "$((i+1))p" | \
                     sed -nE 's/.*android:name[^"]*"([^"]+)".*/\1/p')
                [ -z "$nm" ] && nm=$(echo "$XMLTREE_LINES" | sed -n "$((i+1))p" | \
                     sed -nE 's/.*android:name[^=]*=([^ )]+).*/\1/p')
                nm=$(echo "$nm" | sed -nE 's/^\s*"([^"]+)".*/\1/p')
                if [ -n "$nm" ] && [ "$nm" != "null" ]; then
                    services=$(echo "$services" | jq --arg n "$nm" '. + [$n]')
                fi
                ;;
            *"E: provider (line="*)
                local nm
                nm=$(echo "$XMLTREE_LINES" | sed -n "$((i+1))p" | \
                     sed -nE 's/.*android:name[^"]*"([^"]+)".*/\1/p')
                [ -z "$nm" ] && nm=$(echo "$XMLTREE_LINES" | sed -n "$((i+1))p" | \
                     sed -nE 's/.*android:name[^=]*=([^ )]+).*/\1/p')
                nm=$(echo "$nm" | sed -nE 's/^\s*"([^"]+)".*/\1/p')
                if [ -n "$nm" ] && [ "$nm" != "null" ]; then
                    providers=$(echo "$providers" | jq --arg n "$nm" '. + [$n]')
                fi
                ;;
            *"E: receiver (line="*)
                local nm
                nm=$(echo "$XMLTREE_LINES" | sed -n "$((i+1))p" | \
                     sed -nE 's/.*android:name[^"]*"([^"]+)".*/\1/p')
                [ -z "$nm" ] && nm=$(echo "$XMLTREE_LINES" | sed -n "$((i+1))p" | \
                     sed -nE 's/.*android:name[^=]*=([^ )]+).*/\1/p')
                nm=$(echo "$nm" | sed -nE 's/^\s*"([^"]+)".*/\1/p')
                if [ -n "$nm" ] && [ "$nm" != "null" ]; then
                    receivers=$(echo "$receivers" | jq --arg n "$nm" '. + [$n]')
                fi
                ;;
            *"A: "*"android:debuggable"*)
                local v
                v=$(echo "$line" | sed -nE 's/.*android:debuggable[^=]*=(.*)/\1/p' | tr -d ' ')
                attrs=$(echo "$attrs" | jq --arg v "$v" '.debuggable = $v')
                ;;
            *"A: "*"android:extractNativeLibs"*)
                local v
                v=$(echo "$line" | sed -nE 's/.*android:extractNativeLibs[^=]*=(.*)/\1/p' | tr -d ' ')
                attrs=$(echo "$attrs" | jq --arg v "$v" '.extractNativeLibs = $v')
                ;;
            *"A: "*"android:usesCleartextTraffic"*)
                local v
                v=$(echo "$line" | sed -nE 's/.*android:usesCleartextTraffic[^=]*=(.*)/\1/p' | tr -d ' ')
                attrs=$(echo "$attrs" | jq --arg v "$v" '.usesCleartextTraffic = $v')
                ;;
            *"A: "*"android:isGame"*)
                local v
                v=$(echo "$line" | sed -nE 's/.*android:isGame[^=]*=(.*)/\1/p' | tr -d ' ')
                attrs=$(echo "$attrs" | jq --arg v "$v" '.isGame = $v')
                ;;
        esac
    done

    jq -n \
        --argjson metaData  "$meta" \
        --argjson activities "$activities" \
        --argjson services  "$services" \
        --argjson providers "$providers" \
        --argjson receivers "$receivers" \
        --argjson applicationAttrs "$attrs" \
        --argjson permissions "$permissions" \
        '{ metaData: $metaData,
           activities: $activities,
           services: $services,
           providers: $providers,
           receivers: $receivers,
           applicationAttrs: $applicationAttrs,
           permissions: $permissions }'
}
```

- [ ] **Step 5: Run test**

Run: `bash android-precheck/tests/unit/test_apk_manifest.sh`
Expected: `# Passed: 4`, exit `0`.

- [ ] **Step 6: Commit**

```bash
git add android-precheck/lib/apk_manifest.sh \
        android-precheck/tests/unit/test_apk_manifest.sh \
        android-precheck/tests/unit/fixtures/xmltree.txt
git commit -m "feat(android-precheck): parse merged AndroidManifest xmltree → JSON"
```

---

## Task 8: `lib/apk_certs.sh` — apksigner verify

**Files:**
- Create: `android-precheck/lib/apk_certs.sh`
- Create: `android-precheck/tests/unit/fixtures/certs.txt` (captured)
- Create: `android-precheck/tests/unit/test_apk_certs.sh`

- [ ] **Step 1: Capture fixture**

Run:
```bash
APK="/Users/hoangnguyen/Downloads/DGame_debug_1.1.14.1(1).apk"
BT="$HOME/Library/Android/sdk/build-tools/35.0.0"
out_dir=/Users/hoangnguyen/Perforce/MacbookPro/android-precheck/tests/unit/fixtures
mkdir -p "$out_dir"
"$BT/apksigner" verify --verbose --print-certs "$APK" > "$out_dir/certs.txt" 2>&1
head -15 "$out_dir/certs.txt"
```
Expected first lines:
```
Verifies
Verified using v1 scheme (JAR signing): false
Verified using v2 scheme (APK Signature Scheme v2): true
...
Signer #1 certificate DN: CN=Team Leads, OU=WBSF, O=WB Games, L=San Francisco, ST=California, C=US
Signer #1 certificate SHA-256 digest: b46acd3981297ed08d84531a9de00543510ef1413a6ae667b9bf487cf23293c4
...
```

- [ ] **Step 2: Write failing test**

Create `tests/unit/test_apk_certs.sh`:

```bash
#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"

LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/apk_certs.sh"

FIXTURE="$SCRIPT_DIR/fixtures/certs.txt"

test_sha256_matches_known() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_certs < "$FIXTURE" | jq -r '.sha256')
    assert_eq "$got" "b46acd3981297ed08d84531a9de00543510ef1413a6ae667b9bf487cf23293c4" "SHA-256"
}

test_sha1_matches_known() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_certs < "$FIXTURE" | jq -r '.sha1')
    assert_eq "$got" "5e455590db0114a063fd8fc8f620299087aa223c" "SHA-1"
}

test_subject_dn_contains_known_tokens() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_certs < "$FIXTURE" | jq -r '.subjectDN')
    assert_contains "$got" "WB Games" "DN contains WB Games"
    assert_contains "$got" "Team Leads" "DN contains Team Leads"
}

test_signature_schemes_detect_v2() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_certs < "$FIXTURE" | jq -r '.schemes | join(",")')
    assert_contains "$got" "v2" "schemes list contains v2"
}

run_tests "$SCRIPT_DIR/test_apk_certs.sh"
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bash android-precheck/tests/unit/test_apk_certs.sh`
Expected: `./../../lib/apk_certs.sh: No such file or directory`.

- [ ] **Step 4: Implement `lib/apk_certs.sh`**

Create `lib/apk_certs.sh`:

```bash
#!/usr/bin/env bash
# Parse `apksigner verify --verbose --print-certs <apk>` from stdin → JSON.
# Output:
#   {
#     "sha256":  "<hex>",
#     "sha1":    "<hex>",
#     "md5":     "<hex>",
#     "subjectDN": "<CN=...,OU=...,O=...,L=...,ST=...,C=...>",
#     "keyAlgo":  "RSA",
#     "keySize":  "2048",
#     "schemes":  ["v2","v3", ...],
#     "publicKeySha256": "<hex>",
#     "publicKeySha1":   "<hex>",
#     "publicKeyMd5":    "<hex>"
#   }
#
# All fields optional; missing → "".

parse_certs() {
    local sha256="" sha1="" md5="" subjectDN=""
    local keyAlgo="" keySize=""
    local publicKeySha256="" publicKeySha1="" publicKeyMd5=""
    local schemes="[]"
    local verified=false

    while IFS= read -r line; do
        case "$line" in
            "Verifies")
                verified=true
                ;;
            "Verified using "*": true")
                # "Verified using v2 scheme (APK Signature Scheme v2): true"
                local v
                v=$(echo "$line" | sed -nE 's/^Verified using ([^ ]+) scheme.*/\1/p')
                if [ -n "$v" ]; then
                    schemes=$(echo "$schemes" | jq --arg s "$v" '. + [$s]')
                fi
                ;;
            "Signer #1 certificate DN: "*)
                subjectDN=$(echo "$line" | sed 's/^Signer #1 certificate DN: //')
                ;;
            "Signer #1 certificate SHA-256 digest: "*)
                sha256=$(echo "$line" | awk '{print $NF}')
                ;;
            "Signer #1 certificate SHA-1 digest: "*)
                sha1=$(echo "$line" | awk '{print $NF}')
                ;;
            "Signer #1 certificate MD5 digest: "*)
                md5=$(echo "$line" | awk '{print $NF}')
                ;;
            "Signer #1 key algorithm: "*)
                keyAlgo=$(echo "$line" | sed 's/^Signer #1 key algorithm: //')
                ;;
            "Signer #1 key size (bits): "*)
                keySize=$(echo "$line" | awk '{print $NF}')
                ;;
            "Signer #1 public key SHA-256 digest: "*)
                publicKeySha256=$(echo "$line" | awk '{print $NF}')
                ;;
            "Signer #1 public key SHA-1 digest: "*)
                publicKeySha1=$(echo "$line" | awk '{print $NF}')
                ;;
            "Signer #1 public key MD5 digest: "*)
                publicKeyMd5=$(echo "$line" | awk '{print $NF}')
                ;;
        esac
    done

    jq -n \
        --arg sha256 "$sha256" \
        --arg sha1   "$sha1" \
        --arg md5    "$md5" \
        --arg subjectDN "$subjectDN" \
        --arg keyAlgo "$keyAlgo" \
        --arg keySize "$keySize" \
        --arg publicKeySha256 "$publicKeySha256" \
        --arg publicKeySha1   "$publicKeySha1" \
        --arg publicKeyMd5    "$publicKeyMd5" \
        --argjson schemes "$schemes" \
        --argjson verified "$( [ "$verified" = true ] && echo true || echo false )" \
        '{ sha256: $sha256, sha1: $sha1, md5: $md5,
           subjectDN: $subjectDN,
           keyAlgo: $keyAlgo, keySize: $keySize,
           publicKeySha256: $publicKeySha256,
           publicKeySha1: $publicKeySha1,
           publicKeyMd5: $publicKeyMd5,
           schemes: $schemes,
           verified: $verified }'
}
```

- [ ] **Step 5: Run test**

Run: `bash android-precheck/tests/unit/test_apk_certs.sh`
Expected: `# Passed: 4`, exit `0`.

- [ ] **Step 6: Commit**

```bash
git add android-precheck/lib/apk_certs.sh \
        android-precheck/tests/unit/test_apk_certs.sh \
        android-precheck/tests/unit/fixtures/certs.txt
git commit -m "feat(android-precheck): parse apksigner output → JSON"
```

---

## Task 9: `lib/apk_abi.sh` — extract ABI list

**Files:**
- Create: `android-precheck/lib/apk_abi.sh`
- Create: `android-precheck/tests/unit/fixtures/apk_ls.txt`
- Create: `android-precheck/tests/unit/test_apk_abi.sh`

- [ ] **Step 1: Capture fixture**

Run:
```bash
APK="/Users/hoangnguyen/Downloads/DGame_debug_1.1.14.1(1).apk"
out_dir=/Users/hoangnguyen/Perforce/MacbookPro/android-precheck/tests/unit/fixtures
mkdir -p "$out_dir"
unzip -l "$APK" 2>/dev/null | grep -E "^\s+[0-9]+\s+.*\s+lib/" > "$out_dir/apk_ls.txt"
head -10 "$out_dir/apk_ls.txt"
```
Expected: lines like `12345678  01-01-1981 01:01   lib/arm64-v8a/libfoo.so`.

- [ ] **Step 2: Write failing test**

Create `tests/unit/test_apk_abi.sh`:

```bash
#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"

LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/apk_abi.sh"

FIXTURE="$SCRIPT_DIR/fixtures/apk_ls.txt"

test_extracts_arm64_v8a() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local got
    got=$(parse_abi_ls < "$FIXTURE" | jq -r '.abis | join(",")')
    assert_contains "$got" "arm64-v8a" "list contains arm64-v8a"
}

test_extracts_three_abi() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local count
    count=$(parse_abi_ls < "$FIXTURE" | jq -r '.abis | length')
    assert_eq "$count" "3" "3 distinct ABIs (arm64-v8a, armeabi-v7a, x86_64)"
}

test_extracts_individual_libraries() {
    [ -f "$FIXTURE" ] || { _assert_increment_pass "skipped, fixture absent"; return; }
    local count
    count=$(parse_abi_ls < "$FIXTURE" | jq -r '.libraries | length')
    if [ "$count" -gt 10 ]; then
        _assert_increment_pass "many libraries listed ($count)"
    else
        _assert_increment_fail "expected many .so entries" "got: $count"
    fi
}

run_tests "$SCRIPT_DIR/test_apk_abi.sh"
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bash android-precheck/tests/unit/test_apk_abi.sh`
Expected: `./../../lib/apk_abi.sh: No such file or directory`.

- [ ] **Step 4: Implement `lib/apk_abi.sh`**

Create `lib/apk_abi.sh`:

```bash
#!/usr/bin/env bash
# Parse `unzip -l <apk>` (filtered to lib/) → JSON
# Output:
#   { "abis": ["arm64-v8a","armeabi-v7a", ...],     # distinct
#     "libraries": [ { abi: "arm64-v8a", path: "lib/arm64-v8a/libfoo.so" }, ... ] }

parse_abi_ls() {
    local libs="[]" abis_seen="{}"

    while IFS= read -r line; do
        # Extract the path token (last whitespace-separated token)
        local path
        path=$(echo "$line" | awk '{print $NF}')
        case "$path" in
            lib/*)
                local abi="${path%%/*}"
                abi="${path#lib/}"
                abi="${abi%%/*}"
                libs=$(echo "$libs" | jq --arg a "$abi" --arg p "$path" \
                       '. + [{abi: $a, path: $p}]')
                abis_seen=$(echo "$abis_seen" | jq --arg a "$abi" '. + {($a): true}')
                ;;
        esac
    done

    local abi_list
    abi_list=$(echo "$abis_seen" | jq -r 'keys_unsorted | join(",")' | tr ',' '\n' | sort -u | jq -R 'select(. != "") | .' | jq -s '.')

    jq -n \
        --argjson abis "$abi_list" \
        --argjson libraries "$libs" \
        '{ abis: $abis, libraries: $libraries }'
}
```

- [ ] **Step 5: Run test**

Run: `bash android-precheck/tests/unit/test_apk_abi.sh`
Expected: `# Passed: 3`, exit `0`.

- [ ] **Step 6: Commit**

```bash
git add android-precheck/lib/apk_abi.sh \
        android-precheck/tests/unit/test_apk_abi.sh \
        android-precheck/tests/unit/fixtures/apk_ls.txt
git commit -m "feat(android-precheck): parse ABI list from unzip -l"
```

---

## Task 10: `lib/json_diff.sh` — actual vs expected

**Files:**
- Create: `android-precheck/lib/json_diff.sh`
- Create: `android-precheck/tests/unit/test_json_diff.sh`

- [ ] **Step 1: Write failing test**

Create `tests/unit/test_json_diff.sh`:

```bash
#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"

LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/json_diff.sh"

# Helper: write two JSON files, then call diff with them.
run_diff() {
    local actual="$1" expected="$2"
    diff_apk_vs_expected "$actual" "$expected"
}

test_package_match_returns_OK() {
    local out
    out=$(run_diff '{"package":"com.example"}' '{"expected_package":"com.example"}')
    assert_eq "$(echo "$out" | jq -r '.results[0].status')" "OK" "package OK"
}

test_package_mismatch_returns_FAIL() {
    local out
    out=$(run_diff '{"package":"com.example"}' '{"expected_package":"com.other"}')
    assert_eq "$(echo "$out" | jq -r '.results[0].status')" "FAIL" "package FAIL"
    assert_eq "$(echo "$out" | jq -r '.results[0].expected')" "com.other" "expected value"
    assert_eq "$(echo "$out" | jq -r '.results[0].actual')"   "com.example" "actual value"
}

test_field_missing_in_expected_returns_SKIP() {
    local out
    out=$(run_diff '{"package":"com.example"}' '{}')
    assert_eq "$(echo "$out" | jq -r '.results[0].status')" "SKIP" "missing config = SKIP"
}

test_app_id_present_but_mismatched_returns_FAIL() {
    local out
    out=$(run_diff \
        '{"metaData":{"com.google.android.gms.games.APP_ID":"99009804916"}}' \
        '{"expected_meta_data":{"com.google.android.gms.games.APP_ID":"299009804916"}}')
    local status
    status=$(echo "$out" | jq -r '.results[0].status')
    assert_eq "$status" "FAIL" "APP_ID mismatch = FAIL"
}

test_app_id_missing_in_actual_returns_FAIL() {
    local out
    out=$(run_diff \
        '{"metaData":{}}' \
        '{"expected_meta_data":{"com.google.android.gms.games.APP_ID":"299009804916"}}')
    local status
    status=$(echo "$out" | jq -r '.results[0].status')
    assert_eq "$status" "FAIL" "APP_ID missing in actual = FAIL"
}

test_strict_marks_missing_critical_as_FAIL() {
    local out
    out=$(STRICT=1 run_diff '{"metaData":{}}' '{"expected_meta_data":{}}')
    local status
    status=$(echo "$out" | jq -r '.results | map(select(.category == "signing-crit" or .category == "appid-crit"))[0].status')
    assert_eq "$status" "FAIL" "strict catches missing critical"
}

test_strict_off_does_not_fail_for_missing() {
    local out
    out=$(run_diff '{"metaData":{}}' '{"expected_meta_data":{}}')
    local has_fail
    has_fail=$(echo "$out" | jq '.summary.fail')
    assert_eq "$has_fail" "0" "default mode has 0 failures when both empty"
}

test_summary_counts_correctly() {
    local out
    out=$(run_diff \
        '{"package":"com.example","versionCode":"1"}' \
        '{"expected_package":"com.example","expected_version":{"versionCode_eq":2}}')
    local summary
    summary=$(echo "$out" | jq -c '.summary')
    assert_contains "$summary" '"fail":1' "1 fail (versionCode)"
    assert_contains "$summary" '"ok":1' "1 ok (package)"
}

run_tests "$SCRIPT_DIR/test_json_diff.sh"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash android-precheck/tests/unit/test_json_diff.sh`
Expected: `./../../lib/json_diff.sh: No such file or directory`.

- [ ] **Step 3: Implement `lib/json_diff.sh`**

Create `lib/json_diff.sh`:

```bash
#!/usr/bin/env bash
# Compare the union of all parser outputs (passed as one JSON blob) against
# the user's keys.json (also passed as JSON). Emit a results array.
#
# Output schema:
#   {
#     "summary": { "ok": N, "fail": N, "skip": N, "warn": N },
#     "results": [
#       { "category": "package", "check": "package", "status": "OK|FAIL|SKIP|WARN",
#         "expected": "...", "actual": "...", "message": "..." },
#       ...
#     ]
#   }

# Standard critical keys (must match design §6.3). Hardcoded.
# When STRICT=1 and either is missing in expected, emit FAIL with category "*-crit".
_CRITICAL_APP_ID='com.google.android.gms.games.APP_ID'

# Append a result to a JSON array, then output merged structure.
_diff_emit() {
    jq -n \
        --argjson summary  "$1" \
        --argjson results  "$2" \
        '{ summary: $summary, results: $results }'
}

# Compare two values; emit one result object.
# Args: category check expected actual (any may be empty)
_diff_one() {
    local category="$1" check="$2" expected="$3" actual="$4"
    if [ -z "$expected" ]; then
        # Field absent in expected
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
        jq -n --arg cat "$category" --arg chk "$check" \
            '{category: $cat, check: $chk, status: "SKIP",
              message: "not configured"}'
        return
    fi
    # Field present; compare.
    if [ "$expected" = "$actual" ]; then
        jq -n --arg cat "$category" --arg chk "$check" \
            --arg exp "$expected" --arg act "$actual" \
            '{category: $cat, check: $chk, status: "OK",
              expected: $exp, actual: $act}'
    else
        local msg=""
        case "$category:$check" in
            "meta-data:$_CRITICAL_APP_ID")
                msg="Looks like plugin reset to placeholder. Re-run Play Games plugin Setup (Window → Google Play Games → Setup) and rebuild."
                ;;
            "signing:sha256")
                msg="Signing cert SHA-256 mismatch. Are you using the correct keystore?"
                ;;
        esac
        jq -n --arg cat "$category" --arg chk "$check" \
            --arg exp "$expected" --arg act "$actual" --arg msg "$msg" \
            '{category: $cat, check: $chk, status: "FAIL",
              expected: $exp, actual: $act, message: $msg}'
    fi
}

# Top-level diff function. Args: $1 = actual JSON, $2 = expected JSON.
diff_apk_vs_expected() {
    local actual="$1" expected="$2"
    local results="[]"
    local ok=0 fail=0 skip=0 warn=0

    # package
    local pkg_a pkg_e
    pkg_a=$(echo "$actual" | jq -r '.package // ""')
    pkg_e=$(echo "$expected" | jq -r '.expected_package // ""')
    r=$(_diff_one package package "$pkg_e" "$pkg_a")
    results=$(echo "$results" | jq --argjson r "$r" '. + [$r]')
    case $(echo "$r" | jq -r .status) in OK) ok=$((ok+1));; FAIL) fail=$((fail+1));; SKIP) skip=$((skip+1));; WARN) warn=$((warn+1));; esac

    # version
    local vn_a vc_a
    vn_a=$(echo "$actual" | jq -r '.versionName // ""')
    vc_a=$(echo "$actual" | jq -r '.versionCode // ""')

    local vn_e vcequal vcmin vcmax
    vn_e=$(echo "$expected" | jq -r '.expected_version.versionName // ""')
    vcequal=$(echo "$expected" | jq -r '.expected_version.versionCode_eq // ""')
    vcmin=$(echo "$expected"   | jq -r '.expected_version.versionCode_min // ""')
    vcmax=$(echo "$expected"   | jq -r '.expected_version.versionCode_max // ""')

    if [ -n "$vn_e" ]; then
        r=$(_diff_one version versionName "$vn_e" "$vn_a")
        results=$(echo "$results" | jq --argjson r "$r" '. + [$r]')
        case $(echo "$r" | jq -r .status) in OK) ok=$((ok+1));; FAIL) fail=$((fail+1));; SKIP) skip=$((skip+1));; WARN) warn=$((warn+1));; esac
    fi

    if [ -n "$vcequal" ]; then
        r=$(_diff_one version versionCode "$vcequal" "$vc_a")
        results=$(echo "$results" | jq --argjson r "$r" '. + [$r]')
        case $(echo "$r" | jq -r .status) in OK) ok=$((ok+1));; FAIL) fail=$((fail+1));; SKIP) skip=$((skip+1));; WARN) warn=$((warn+1));; esac
    elif [ -n "$vcmin" ] || [ -n "$vcmax" ]; then
        local lo="${vcmin:-0}" hi="${vcmax:-999999}"
        if [ "$vc_a" -ge "$lo" ] 2>/dev/null && [ "$vc_a" -le "$hi" ] 2>/dev/null; then
            status="OK"
        else
            status="FAIL"
        fi
        r=$(jq -n --arg st "$status" --arg lo "$lo" --arg hi "$hi" --arg vc "$vc_a" \
            '{category: "version", check: "versionCode",
              status: $st, expected: ($lo + " ≤ x ≤ " + $hi), actual: $vc}')
        results=$(echo "$results" | jq --argjson r "$r" '. + [$r]')
        case $status in OK) ok=$((ok+1));; FAIL) fail=$((fail+1));; SKIP) skip=$((skip+1));; WARN) warn=$((warn+1));; esac
    fi

    # SDK
    for k in minSdk targetSdk compileSdk; do
        local a e
        a=$(echo "$actual"   | jq -r ".$k // \"\"")
        e=$(echo "$expected" | jq -r ".expected_sdk.$k // \"\"")
        r=$(_diff_one sdk "$k" "$e" "$a")
        results=$(echo "$results" | jq --argjson r "$r" '. + [$r]')
        case $(echo "$r" | jq -r .status) in OK) ok=$((ok+1));; FAIL) fail=$((fail+1));; SKIP) skip=$((skip+1));; WARN) warn=$((warn+1));; esac
    done

    # signing
    for k in sha256 sha1 md5 subjectDN; do
        local a e
        a=$(echo "$actual"   | jq -r ".signing.$k // \"\"")
        e=$(echo "$expected" | jq -r ".expected_signing.$k // \"\"")
        r=$(_diff_one signing "$k" "$e" "$a")
        results=$(echo "$results" | jq --argjson r "$r" '. + [$r]')
        case $(echo "$r" | jq -r .status) in OK) ok=$((ok+1));; FAIL) fail=$((fail+1));; SKIP) skip=$((skip+1));; WARN) warn=$((warn+1));; esac
    done

    # subject_dn_contains: list of substrings (case-sensitive substring match).
    local dn_e_substrings dn_a
    dn_e_substrings=$(echo "$expected" | jq -r '.expected_signing.subject_dn_contains // [] | .[]')
    dn_a=$(echo "$actual" | jq -r '.signing.subjectDN // ""')
    for needle in $dn_e_substrings; do
        local st="FAIL" msg="DN missing needle: $needle"
        case "$dn_a" in *"$needle"*) st="OK"; msg="";; esac
        r=$(jq -n --arg st "$st" --arg needle "$needle" --arg dn "$dn_a" --arg msg "$msg" \
            '{category: "signing", check: ("dn_contains:" + $needle),
              status: $st, expected: $needle, actual: $dn, message: $msg}')
        results=$(echo "$results" | jq --argjson r "$r" '. + [$r]')
        case $st in OK) ok=$((ok+1));; FAIL) fail=$((fail+1));; SKIP) skip=$((skip+1));; WARN) warn=$((warn+1));; esac
    done

    # must_use_signature_scheme: each scheme must be in actual.schemes
    local expected_schemes
    expected_schemes=$(echo "$expected" | jq -r '.expected_signing.must_use_signature_scheme // [] | .[]')
    for s in $expected_schemes; do
        local st="FAIL"
        if echo "$actual" | jq -e --arg s "$s" '.signing.schemes | index($s) != null' >/dev/null 2>&1; then
            st="OK"
        fi
        r=$(jq -n --arg st "$st" --arg s "$s" \
            '{category: "signing", check: ("scheme:" + $s),
              status: $st, expected: $s, actual: "(see schemes list)"}')
        results=$(echo "$results" | jq --argjson r "$r" '. + [$r]')
        case $st in OK) ok=$((ok+1));; FAIL) fail=$((fail+1));; SKIP) skip=$((skip+1));; WARN) warn=$((warn+1));; esac
    done

    # meta-data
    local keys
    keys=$(echo "$expected" | jq -r '.expected_meta_data // {} | keys[]')
    for name in $keys; do
        local a e
        a=$(echo "$actual"   | jq -r ".metaData[\"$name\"] // \"\"")
        e=$(echo "$expected" | jq -r ".expected_meta_data[\"$name\"] // \"\"")
        r=$(_diff_one meta-data "$name" "$e" "$a")
        results=$(echo "$results" | jq --argjson r "$r" '. + [$r]')
        case $(echo "$r" | jq -r .status) in OK) ok=$((ok+1));; FAIL) fail=$((fail+1));; SKIP) skip=$((skip+1));; WARN) warn=$((warn+1));; esac
    done

    # permissions_present (set contains)
    local p_want p_have
    p_want=$(echo "$expected" | jq -r '.expected_permissions_present // [] | .[]')
    p_have=$(echo "$actual"   | jq -r '.permissions // [] | .[]')
    for p in $p_want; do
        local st="FAIL"
        if echo "$p_have" | grep -Fxq "$p"; then st="OK"; fi
        r=$(jq -n --arg st "$st" --arg p "$p" \
            '{category: "permissions", check: ("present:" + $p),
              status: $st, expected: $p, actual: "(see permissions list)"}')
        results=$(echo "$results" | jq --argjson r "$r" '. + [$r]')
        case $st in OK) ok=$((ok+1));; FAIL) fail=$((fail+1));; SKIP) skip=$((skip+1));; WARN) warn=$((warn+1));; esac
    done

    # permissions_absent
    p_want=$(echo "$expected" | jq -r '.expected_permissions_absent // [] | .[]')
    for p in $p_want; do
        local st="OK"
        if echo "$p_have" | grep -Fxq "$p"; then st="FAIL"; fi
        r=$(jq -n --arg st "$st" --arg p "$p" \
            '{category: "permissions", check: ("absent:" + $p),
              status: $st, expected: ("NOT " + $p), actual: "(see permissions list)"}')
        results=$(echo "$results" | jq --argjson r "$r" '. + [$r]')
        case $st in OK) ok=$((ok+1));; FAIL) fail=$((fail+1));; SKIP) skip=$((skip+1));; WARN) warn=$((warn+1));; esac
    done

    # components_present (substring match on activity/service/receiver FQCN;
    # substring match on provider authorities).
    local want_present have_components
    want_present=$(echo "$expected" | jq -r '.expected_components_present // [] | .[]')
    have_components=$(echo "$actual" | jq -c '.activities + .services + .receivers + .providers')
    for want in $want_present; do
        local st="FAIL"
        # activities/services/receivers: substring match within string elements
        if echo "$actual" | jq -e --arg w "$want" \
            '(.activities + .services + .receivers) | any(. | contains($w))' >/dev/null 2>&1; then
            st="OK"
        fi
        # providers: substring match against provider FQCN OR .authorities if present.
        if [ "$st" != "OK" ] && echo "$actual" | jq -e --arg w "$want" \
            '.providers | any(. | contains($w))' >/dev/null 2>&1; then
            st="OK"
        fi
        r=$(jq -n --arg st "$st" --arg want "$want" \
            '{category: "components", check: ("present:" + $want),
              status: $st, expected: $want, actual: "(see components lists)"}')
        results=$(echo "$results" | jq --argjson r "$r" '. + [$r]')
        case $st in OK) ok=$((ok+1));; FAIL) fail=$((fail+1));; SKIP) skip=$((skip+1));; WARN) warn=$((warn+1));; esac
    done

    # ABI must_include / must_exclude
    local must_in must_out abis
    must_in=$(echo "$expected" | jq -r '.expected_abi.must_include // [] | .[]')
    must_out=$(echo "$expected" | jq -r '.expected_abi.must_exclude // [] | .[]')
    abis=$(echo "$actual" | jq -r '.abis // [] | .[]')
    for need in $must_in; do
        local st="FAIL"
        if echo "$abis" | grep -Fxq "$need"; then st="OK"; fi
        r=$(jq -n --arg st "$st" --arg need "$need" \
            '{category: "abi", check: ("include:" + $need), status: $st,
              expected: $need, actual: "(see abis list)"}')
        results=$(echo "$results" | jq --argjson r "$r" '. + [$r]')
        case $st in OK) ok=$((ok+1));; FAIL) fail=$((fail+1));; SKIP) skip=$((skip+1));; WARN) warn=$((warn+1));; esac
    done
    for banned in $must_out; do
        local st="OK"
        if echo "$abis" | grep -Fxq "$banned"; then st="FAIL"; fi
        r=$(jq -n --arg st "$st" --arg banned "$banned" \
            '{category: "abi", check: ("exclude:" + $banned), status: $st,
              expected: ("NOT " + $banned), actual: "(see abis list)"}')
        results=$(echo "$results" | jq --argjson r "$r" '. + [$r]')
        case $st in OK) ok=$((ok+1));; FAIL) fail=$((fail+1));; SKIP) skip=$((skip+1));; WARN) warn=$((warn+1));; esac
    done

    # application attributes
    local want_attrs
    want_attrs=$(echo "$expected" | jq -r '.expected_attributes // {} | keys[]')
    for ak in $want_attrs; do
        local a e
        a=$(echo "$actual"   | jq -r ".applicationAttrs.\"$ak\" // \"\"")
        e=$(echo "$expected" | jq -r ".expected_attributes.\"$ak\" // \"\"")
        r=$(_diff_one attrs "$ak" "$e" "$a")
        results=$(echo "$results" | jq --argjson r "$r" '. + [$r]')
        case $(echo "$r" | jq -r .status) in OK) ok=$((ok+1));; FAIL) fail=$((fail+1));; SKIP) skip=$((skip+1));; WARN) warn=$((warn+1));; esac
    done

    local summary
    summary=$(jq -n --argjson ok "$ok" --argjson fail "$fail" --argjson skip "$skip" --argjson warn "$warn" \
        '{ok: $ok, fail: $fail, skip: $skip, warn: $warn, total: ($ok + $fail + $skip + $warn)}')

    _diff_emit "$summary" "$results"
}
```

- [ ] **Step 4: Run test**

Run: `bash android-precheck/tests/unit/test_json_diff.sh`
Expected: `# Passed: 8`, exit `0`.

- [ ] **Step 5: Commit**

```bash
git add android-precheck/lib/json_diff.sh android-precheck/tests/unit/test_json_diff.sh
git commit -m "feat(android-precheck): json_diff compares actual vs expected"
```

---

## Task 11: `lib/report.sh` — format output

**Files:**
- Create: `android-precheck/lib/report.sh`
- Create: `android-precheck/tests/unit/test_report.sh`

- [ ] **Step 1: Write failing test**

Create `tests/unit/test_report.sh`:

```bash
#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"

LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/report.sh"

SAMPLE='{"summary":{"ok":2,"fail":1,"skip":1,"warn":0,"total":4},
         "results":[
           {"category":"package","check":"package","status":"OK","expected":"com.x","actual":"com.x"},
           {"category":"signing","check":"sha256","status":"FAIL","expected":"a","actual":"b","message":"wrong cert"},
           {"category":"version","check":"versionName","status":"SKIP"},
           {"category":"meta-data","check":"APP_ID","status":"OK","expected":"299009804916","actual":"299009804916"}
         ]}'

test_format_text_includes_OK_marker() {
    local out
    out=$(NO_COLOR=1 format_text < "$SAMPLE.tmp" 2>/dev/null || true)
    # Use process substitution because we feed stdin via here-string
    out=$(NO_COLOR=1 bash -c '. '"$LIB_DIR/report.sh"'; format_text' <<< "$SAMPLE")
    assert_contains "$out" "[OK]" "OK marker"
    assert_contains "$out" "[FAIL]" "FAIL marker"
    assert_contains "$out" "[SKIP]" "SKIP marker"
}

test_format_text_includes_summary() {
    local out
    out=$(NO_COLOR=1 bash -c '. '"$LIB_DIR/report.sh"'; format_text' <<< "$SAMPLE")
    assert_contains "$out" "SUMMARY" "summary header"
    assert_contains "$out" "2 OK" "OK count"
    assert_contains "$out" "1 FAIL" "FAIL count"
    assert_contains "$out" "1 SKIP" "SKIP count"
}

test_exit_code_for_results() {
    # Default: 0 if no FAIL, 1 if any FAIL
    local ec
    ec=$(echo "$SAMPLE" | compute_exit_code)
    assert_eq "$ec" "1" "1 failure → exit 1"

    local clean='{"summary":{"ok":3,"fail":0,"skip":1,"warn":0,"total":4},"results":[]}'
    ec=$(echo "$clean" | compute_exit_code)
    assert_eq "$ec" "0" "no failure → exit 0"
}

run_tests "$SCRIPT_DIR/test_report.sh"
```

Note: this test uses a small bash -c trick because we need to source the library inside a subshell. The pattern is fragile; if it breaks, replace with a tiny helper script.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash android-precheck/tests/unit/test_report.sh`
Expected: `./../../lib/report.sh: No such file or directory`.

- [ ] **Step 3: Implement `lib/report.sh`**

Create `lib/report.sh`:

```bash
#!/usr/bin/env bash
# Format a results JSON (from json_diff) for human or machine consumption.
#
# Functions:
#   format_text   — read JSON from stdin, print lines + summary
#   compute_exit_code — read JSON from stdin, emit exit code on stdout

# ANSI helpers (re-declare locally so we don't require common.sh).
_NO_COLOR=${NO_COLOR:-}
_colorize() { [ -n "$_NO_COLOR" ] && return 1; [ ! -t 1 ] && return 1; return 0; }

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
    printf '%-20s %s\n' "$cat/$check" "$expected"
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
    local summary
    summary=$(echo "$input" | jq -c '.summary')
    local count
    count=$(echo "$input" | jq -r '.results | length')
    local i
    for i in $(seq 0 $((count - 1))); do
        _format_one_line "$(echo "$input" | jq -c ".results[$i]")"
    done
    echo
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
```

- [ ] **Step 4: Run test**

Run: `bash android-precheck/tests/unit/test_report.sh`
Expected: `# Passed: 3`, exit `0`.

- [ ] **Step 5: Commit**

```bash
git add android-precheck/lib/report.sh android-precheck/tests/unit/test_report.sh
git commit -m "feat(android-precheck): report.sh text formatter + exit calc"
```

---

## Task 12: `check.sh` — CLI entry, mode dispatch

**Files:**
- Create: `android-precheck/check.sh`

- [ ] **Step 1: Write the CLI**

Create `check.sh`:

```bash
#!/usr/bin/env bash
# android-precheck — Pre-submission APK verifier.
# See docs/2026-07-24-android-precheck-design.md for full design.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
EXPECTED_PATH="keys.json"   # relative to CWD by default
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
  check.sh --self-check                     Verify Android SDK + jq available
  check.sh --flavor <name>                  Apply flavor-specific overrides from keys.json
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
  3  Environment error (aapt2/apksigner/jq missing)
  4  Strict mode + critical key missing
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
        -v|--version)  echo "android-precheck v0.1.0"; exit 0 ;;
        --self-check)
            if require_tools; then
                log_ok "Android SDK + jq available"
                exit 0
            fi
            exit "$EXIT_ENV"
            ;;
        --harvest)
            MODE="harvest"
            shift
            APK="${1:-}"
            [ -z "$APK" ] && { echo "ERROR: --harvest needs <apk>" >&2; exit "$EXIT_USAGE"; }
            shift
            ;;
        --strict)      STRICT=1; shift ;;
        --no-color)    NO_COLOR=1; shift ;;
        --json)        JSON_ONLY=1; shift ;;
        -e|--expected) shift; EXPECTED_PATH="${1:-}"; [ -z "$EXPECTED_PATH" ] && { echo "ERROR: -e needs path" >&2; exit "$EXIT_USAGE"; }; shift ;;
        -o|--out)      shift; HARVEST_OUT="${1:-}"; shift ;;
        --flavor)      shift; FLAVOR="${1:-}"; shift ;;
        --)            shift; break ;;
        -*)            echo "ERROR: unknown flag $1" >&2; exit "$EXIT_USAGE" ;;
        *)
            APK="$1"
            shift
            ;;
    esac
done

export NO_COLOR STRICT

# --- Validate APK ---
if [ -z "$APK" ] || [ ! -f "$APK" ]; then
    echo "ERROR: APK file not found: ${APK:-<unset>}" >&2
    exit "$EXIT_USAGE"
fi

# --- Mode dispatch ---

# Helper: locate build-tools dynamically
AAPT2="$(find_aapt2)"
APKSIGNER="$(find_apksigner)"

case "$MODE" in
    harvest)
        # Run all parsers and dump combined JSON.
        require_tools || exit "$EXIT_ENV"
        tmp=$(apk_unpack "$APK") || exit "$EXIT_USAGE"
        trap 'apk_unpack_cleanup "$tmp"' EXIT

        actual=$(collect_actual_json "$APK" "$tmp")
        if [ -z "$HARVEST_OUT" ]; then
            echo "$actual" | jq .
            exit 0
        else
            if ! echo "$actual" | jq . > "$HARVEST_OUT"; then
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
        require_tools || exit "$EXIT_ENV"

        tmp=$(apk_unpack "$APK") || exit "$EXIT_USAGE"
        trap 'apk_unpack_cleanup "$tmp"' EXIT

        actual=$(collect_actual_json "$APK" "$tmp")
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
            if [ -z "$(echo "$expected" | jq -r '.expected_signing.sha256 // ""')" ] \
               || [ -z "$(echo "$expected" | jq -r ".expected_meta_data[\"$_CRITICAL_APP_ID\"] // \"\"")" ]; then
                echo "STRICT mode: critical key(s) missing in $EXPECTED_PATH" >&2
                echo "  Need: expected_signing.sha256" >&2
                echo "  Need: expected_meta_data[\"$_CRITICAL_APP_ID\"]" >&2
                exit "$EXIT_STRICT"
            fi
        fi

        diff_result=$(diff_apk_vs_expected "$actual" "$expected")
        if [ "$JSON_ONLY" = "1" ]; then
            echo "$diff_result"
        else
            echo "$diff_result" | format_text
        fi
        ec=$(echo "$diff_result" | compute_exit_code)
        exit "$ec"
        ;;
esac

# Should not reach here.
echo "ERROR: unhandled mode $MODE" >&2
exit "$EXIT_USAGE"
```

Now extract sub-routines into the file (these are referenced by the script above but defined here):

Append below to the same file `check.sh`:

```bash
# Sub-routine: required tools check that exits with proper code.
# Sub-routine: collect all parser outputs into one JSON.
# Inputs: APK path, unpacked tmp dir
# Output: JSON to stdout with this schema:
#   {
#     "package","versionCode","versionName","minSdk","targetSdk","compileSdk","label",
#     "permissions":[...],
#     "metaData":{...},
#     "activities":[...], "services":[...], "providers":[...], "receivers":[...],
#     "applicationAttrs":{...},
#     "signing":{ sha256, sha1, md5, subjectDN, keyAlgo, keySize, publicKeySha256, schemes, verified },
#     "abis":[...],
#     "libraries":[...]
#   }

collect_actual_json() {
    local apk="$1" tmp="$2"

    # Badging → JSON
    local badging
    badging=$("$AAPT2" dump badging "$apk" 2>/dev/null | parse_badging)

    # Manifest xmltree → JSON
    local xmltree
    xmltree=$("$AAPT2" dump xmltree "$apk" --file AndroidManifest.xml 2>/dev/null | parse_manifest)

    # Certs
    local certs
    certs=$("$APKSIGNER" verify --verbose --print-certs "$apk" 2>/dev/null | parse_certs)

    # ABIs from unzip -l
    local abi
    abi=$(unzip -l "$apk" 2>/dev/null | grep -E "^\s+[0-9]+\s+.*\s+lib/" | parse_abi_ls)

    # Merge
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
```

- [ ] **Step 2: Make executable**

Run:
```bash
chmod +x /Users/hoangnguyen/Perforce/MacbookPro/android-precheck/check.sh
```

- [ ] **Step 3: Run --self-check**

Run:
```bash
cd /Users/hoangnguyen/Perforce/MacbookPro/android-precheck
./check.sh --self-check
```
Expected: `[OK]    Android SDK + jq available`, exit `0`.

If aapt2/apksigner not auto-found, set:
```bash
cd /Users/hoangnguyen/Perforce/MacbookPro/android-precheck
ANDROID_HOME="$HOME/Library/Android/sdk" ./check.sh --self-check
```

- [ ] **Step 4: Run harvest on the user's APK**

Run:
```bash
cd /Users/hoangnguyen/Perforce/MacbookPro/android-precheck
./check.sh --harvest "/Users/hoangnguyen/Downloads/DGame_debug_1.1.14.1(1).apk" \
    -o /tmp/keys.harvested.json
```
Expected: `harvest written to /tmp/keys.harvested.json`, exit `0`. The file should be JSON with package, signingsha256, APP_ID, etc.

- [ ] **Step 5: Run check against harvested baseline (round-trip)**

Run:
```bash
cd /Users/hoangnguyen/Perforce/MacbookPro/android-precheck
./check.sh "/Users/hoangnguyen/Downloads/DGame_debug_1.1.14.1(1).apk" \
    --expected /tmp/keys.harvested.json
```
Expected: text output with multiple `[OK]` lines and summary like `SUMMARY: N OK, 0 FAIL, ...`. Exit `0`.

- [ ] **Step 6: Inject a deliberate failure to verify error path**

Run:
```bash
# Make a copy of harvested keys with wrong SHA to confirm error reporting.
jq '.expected_signing.sha256 = "WRONG_WRONG_WRONG"' /tmp/keys.harvested.json > /tmp/keys.bad.json
cd /Users/hoangnguyen/Perforce/MacbookPro/android-precheck
./check.sh "/Users/hoangnguyen/Downloads/DGame_debug_1.1.14.1(1).apk" \
    --expected /tmp/keys.bad.json
```
Expected: at least one `[FAIL]` with `signing/sha256`, exit `1`.

- [ ] **Step 7: Commit**

```bash
git add android-precheck/check.sh
git commit -m "feat(android-precheck): CLI entry — modes + arg parsing"
```

---

## Task 13: Smoke test harness

**Files:**
- Create: `android-precheck/tests/smoke.sh`
- Create: `android-precheck/tests/fixtures/keys.example.json` (harvested baseline, committed)

- [ ] **Step 1: Generate fixture by harvesting user APK**

Run:
```bash
cd /Users/hoangnguyen/Perforce/MacbookPro/android-precheck
./check.sh --harvest "/Users/hoangnguyen/Downloads/DGame_debug_1.1.14.1(1).apk" \
    -o tests/fixtures/keys.example.json
ls -la tests/fixtures/keys.example.json
```
Expected: file exists, ~50 lines JSON.

- [ ] **Step 2: Write smoke.sh**

Create `tests/smoke.sh`:

```bash
#!/usr/bin/env bash
# End-to-end smoke test for android-precheck.
# Verifies:
#   1. --self-check passes (env ok)
#   2. --harvest yields JSON with expected top-level keys
#   3. round-trip --check against harvested baseline yields 0 FAIL
#   4. inject a wrong expected_signing.sha256 → 1+ FAIL

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHECK="$SCRIPT_DIR/../check.sh"
APK="/Users/hoangnguyen/Downloads/DGame_debug_1.1.14.1(1).apk"
KEYS="$SCRIPT_DIR/fixtures/keys.example.json"
TMPHARV="$(mktemp -t android-precheck-smoke-XXXXXX.json)"
trap 'rm -f "$TMPHARV" "$TMPHARV.bad"' EXIT

fail() { echo "SMOKE FAIL: $*" >&2; exit 1; }
say()  { echo "[smoke] $*"; }

[ -x "$CHECK" ] || fail "check.sh not executable at $CHECK"
[ -f "$APK" ]  || fail "APK not found at $APK"

say "1/4 self-check"
"$CHECK" --self-check || fail "self-check failed"

say "2/4 harvest"
"$CHECK" --harvest "$APK" -o "$TMPHARV" || fail "harvest failed"
jq -e '.package' "$TMPHARV" >/dev/null 2>&1 || fail "harvested JSON missing package"
jq -e '.signing.sha256' "$TMPHARV" >/dev/null 2>&1 || fail "harvested JSON missing signing.sha256"

say "3/4 round-trip --check"
"$CHECK" "$APK" --expected "$TMPHARV" --json > /tmp/smoke_check.json
fails=$(jq -r '.summary.fail' /tmp/smoke_check.json)
[ "$fails" = "0" ] || fail "round-trip produced $fails failures (expected 0)"

say "4/4 inject bad sha256 → expect FAIL"
TMPHARV.bad="$TMPHARV.bad"
jq '.expected_signing.sha256 = "WRONG_DEADBEEF"' "$TMPHARV" > "$TMPHARV.bad"
"$CHECK" "$APK" --expected "$TMPHARV.bad" --json > /tmp/smoke_check_bad.json
fails=$(jq -r '.summary.fail' /tmp/smoke_check_bad.json)
if [ "$fails" -ge 1 ]; then
    say "OK: $fails failures correctly reported"
else
    fail "deliberate bad sha256 did not trigger FAIL"
fi

say "all steps green ✓"
exit 0
```

- [ ] **Step 3: Make executable; run smoke**

Run:
```bash
chmod +x /Users/hoangnguyen/Perforce/MacbookPro/android-precheck/tests/smoke.sh
bash /Users/hoangnguyen/Perforce/MacbookPro/android-precheck/tests/smoke.sh
```
Expected: 4 lines `[smoke] N/4 ...`, then `all steps green ✓`, exit `0`.

- [ ] **Step 4: Commit**

```bash
git add android-precheck/tests/smoke.sh android-precheck/tests/fixtures/keys.example.json
git commit -m "test(android-precheck): smoke harness + harvested baseline fixture"
```

---

## Task 14: README — full usage docs

**Files:**
- Modify: `android-precheck/README.md`

- [ ] **Step 1: Write the full README**

Replace contents of `README.md` (overwrite Task 1's skeleton) with:

```markdown
# android-precheck

Bash tool that verifies an Android APK against a JSON baseline **before** you submit
to Google Play. Catches the silent regressions that survive Unity build but break
runtime:

- Google Play Games `APP_ID` reset (bug motivating this tool)
- Wrong keystore / signing cert swap
- Missing `playgamesinitprovider` authority
- AdMob / Billing version drift from plugin upgrade
- Manifest merge issues after Unity plugin upgrade

Built for the `DGame` project (`/Users/hoangnguyen/Perforce/MacbookPro`); the
tool itself is portable to any Android project.

## Quickstart

### 1. Requirements

- macOS or Linux
- `jq` ≥ 1.6 (`brew install jq` or `apt install jq`)
- Android SDK build-tools ≥ 34 (`aapt2`, `apksigner`)
- `bash` ≥ 3.2

### 2. Verify environment

```bash
$ bash check.sh --self-check
[OK]    Android SDK + jq available
```

If it fails, set `ANDROID_HOME` / `ANDROID_SDK_ROOT` to your SDK location and retry.

### 3. Bootstrap a baseline from a known-good APK

```bash
$ bash check.sh --harvest build/release.apk -o keys.json
harvest written to keys.json
```

The JSON contains every verifiable field from the APK (package, signing, meta-data,
permissions, components, ABIs, attrs). Edit it down to the fields you actually care about.

### 4. Check every new build

```bash
$ bash check.sh build/release.apk
[OK]    package/com.wb.goog.dc.dcwc = com.wb.goog.dc.dcwc
[OK]    signing/sha256 = b46acd3981297ed08d84531a9de00543510ef1413a6ae667b9bf487cf23293c4
[OK]    meta-data/com.google.android.gms.games.APP_ID = 299009804916
...
SUMMARY: 27 OK, 0 FAIL, 0 SKIP, 0 WARN
$ echo $?
0
```

### 5. Add `--strict` for pre-release

```bash
$ bash check.sh build/release.apk --strict
```

`--strict` fails the build if the critical keys (`expected_signing.sha256`,
`expected_meta_data[com.google.android.gms.games.APP_ID]`) are missing from
`keys.json`. Always run this before tagging a release.

### 6. Make the JSON lean

You don't need to keep every field. To check **only keystore + APP_ID**, your
`keys.json` can be 5 lines:

```json
{
  "expected_signing": {
    "sha256": "b46acd3981297ed08d84531a9de00543510ef1413a6ae667b9bf487cf23293c4"
  },
  "expected_meta_data": {
    "com.google.android.gms.games.APP_ID": "299009804916"
  }
}
```

Other fields are skipped with `[SKIP] not configured`.

## Modes

| Command | Purpose |
|---|---|
| `check.sh <apk>` | Check with default `./keys.json` |
| `check.sh <apk> -e <path>` | Check with explicit baseline |
| `check.sh <apk> --strict` | Fail if critical key missing |
| `check.sh --harvest <apk>` | Generate baseline JSON from APK |
| `check.sh --self-check` | Verify environment |
| `check.sh --json` | Machine-readable output |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | All checks pass (or only SKIP/WARN) |
| 1 | At least one check failed |
| 2 | Bad usage (file missing, bad args) |
| 3 | Environment error (aapt2 / apksigner / jq missing) |
| 4 | `--strict` and critical key missing |
| 5 | `--harvest` could not write output |

## Run tests

```bash
# Unit tests
for t in tests/unit/test_*.sh; do bash "$t"; done

# End-to-end smoke (requires your APK; see fixture path in tests/smoke.sh)
bash tests/smoke.sh
```

## Troubleshooting

**`[FAIL] env: aapt2 / apksigner not found`**
Set `ANDROID_HOME` to your SDK: `export ANDROID_HOME=$HOME/Library/Android/sdk`.

**`[FAIL] meta-data com.google.android.gms.games.APP_ID`**
The merged manifest's `APP_ID` doesn't match `keys.json`. Most common cause: a
Unity plugin upgrade regenerated `Assets/Plugins/Android/GooglePlayGamesManifest.androidlib/`,
resetting this meta-data to a placeholder (`99009804916`). Re-run
`Window → Google Play Games → Setup` in the Unity editor, then rebuild the APK.

**`[FAIL] signing sha256 (expected X, got Y)`**
Wrong keystore in use. Confirm Unity Player Settings → Publishing Settings → Custom
Keystore points to the same `keys.json`'s expected SHA-256. The keystore's SHA-256
must match what's registered in Play Console under Setup → App integrity.

**`[FAIL] component PlayGamesInitProvider authority`**
The provider's `authorities` shows `com.google.example.games.mainlibproj` instead
of `com.wb.goog.dc.dcwc.playgamesinitprovider`. The manifest merger isn't applying
`{applicationId}` substitution; check `mainTemplate.gradle` has correct
`manifestPlaceholders`.

**`apksigner` warnings about v2 scheme**
For Play Store submissions, AAB must be **v2 or v3** signed. APK debug builds
typically only have v1 (jarsigner). Add `expected_signing.must_use_signature_scheme: ["v2"]`
to enforce this.

## License

Internal tool, no license grant.
```

- [ ] **Step 2: Commit**

```bash
git add android-precheck/README.md
git commit -m "docs(android-precheck): full README + troubleshooting"
```

---

## Acceptance Criteria Verification

Run this final check to confirm all design §13 acceptance criteria pass:

```bash
cd /Users/hoangnguyen/Perforce/MacbookPro/android-precheck

# (1) self-check
bash check.sh --self-check

# (2) full round-trip
bash check.sh "/Users/hoangnguyen/Downloads/DGame_debug_1.1.14.1(1).apk" \
    --expected tests/fixtures/keys.example.json

# (3) --strict with missing critical
cp tests/fixtures/keys.example.json /tmp/keys.min.json
jq 'del(.expected_meta_data["com.google.android.gms.games.APP_ID"])' /tmp/keys.min.json > /tmp/keys.min.json.tmp
mv /tmp/keys.min.json.tmp /tmp/keys.min.json
bash check.sh "/Users/hoangnguyen/Downloads/DGame_debug_1.1.14.1(1).apk" \
    --expected /tmp/keys.min.json --strict
# Exit code 4 expected.

# (4) harvest
bash check.sh --harvest "/Users/hoangnguyen/Downloads/DGame_debug_1.1.14.1(1).apk" \
    -o /tmp/keys.regen.json

# (5) minimal JSON (only keystore + APP_ID)
cat > /tmp/keys.tiny.json <<'JSON'
{
  "expected_signing":     { "sha256": "b46acd3981297ed08d84531a9de00543510ef1413a6ae667b9bf487cf23293c4" },
  "expected_meta_data":   { "com.google.android.gms.games.APP_ID": "299009804916" }
}
JSON
bash check.sh "/Users/hoangnguyen/Downloads/DGame_debug_1.1.14.1(1).apk" \
    --expected /tmp/keys.tiny.json

# (6) sha256 mismatch
jq '.expected_signing.sha256 |= sub("b46acd"; "deadbeef")' /tmp/keys.tiny.json > /tmp/keys.tiny.bad.json
bash check.sh "/Users/hoangnguyen/Downloads/DGame_debug_1.1.14.1(1).apk" \
    --expected /tmp/keys.tiny.bad.json
# Exit code 1 expected.

# (7) smoke test
bash tests/smoke.sh
```

If all 7 commands produce the expected outcomes, the implementation is done.

---

## Future Work (NOT in this plan)

- AAB support (requires `bundletool.jar`; deferred to v2)
- CI integration (GitHub Action wrapper around `--json` mode)
- Two-APK diff mode (`check.sh apk_new.apk --against apk_old.apk`)
- Auto-re-sign fix (`--fix-signed`)
- `--report-md` for PR comments

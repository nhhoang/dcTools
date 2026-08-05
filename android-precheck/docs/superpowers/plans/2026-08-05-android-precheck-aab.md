# android-precheck v2 AAB Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `android-precheck` so it accepts `.aab` inputs in addition to `.apk` and reuses the v0.1 checker set by building a universal APK from the bundle with `bundletool`.

**Architecture:** Add two new libraries (`lib/bundletool.sh`, `lib/aab_pipeline.sh`), extend `check.sh` to dispatch on file extension, and feed the resulting universal APK into the existing v0.1 pipeline (`lib/apk_*.sh` + `lib/json_diff.sh`). The v0.1 output schema gains a sibling `bundle:` block.

**Tech Stack:** Bash 3.2+, `jq`, `unzip`, `aapt2` / `apksigner` from Android SDK build-tools, `bundletool` (Java JAR), `keytool` from JDK for debug keystore auto-create.

**Spec:** `docs/superpowers/specs/2026-08-05-android-precheck-aab-design.md`

---

## File Map

| Path | Change | Responsibility |
|---|---|---|
| `lib/bundletool.sh` | NEW | Resolve `bundletool.jar` path; expose `find_bundletool` and `bundletool_java_path`. |
| `lib/aab_pipeline.sh` | NEW | AAB-specific helpers: `aab_unpack_to_tmp`, `aab_validate`, `aab_dump_modules`, `aab_build_universal_apk`, `aab_extract_universal_apk`, `aab_ensure_debug_keystore`. |
| `lib/env.sh` | MODIFY | Add `find_bundletool` wrapper + `find_debug_keystore` + extend `require_tools` to validate bundletool for AAB. |
| `check.sh` | MODIFY | Dispatch AAB inputs to v2 pipeline; new flags `--ks`, `--ks-key-alias`, `--ks-pass-env`, `--key-pass-env`, `--skip-signing`. |
| `lib/json_diff.sh` | MODIFY | Debug-keystore auto-fill for `expected_signing.sha256` and `signing/*` `WARN` mode when `--skip-signing` set. |
| `lib/report.sh` | MODIFY | Emit top-level `bundle:` block (valid, modules, base_manifest_metadata) in JSON output. |
| `tests/unit/test_bundletool.sh` | NEW | Verifies resolver order, Gradle cache exclusion, empty result when no candidate. |
| `tests/unit/test_aab_pipeline.sh` | NEW | Verifies unpack/validate/dump_modules/extract_universal on mocked inputs. |
| `tests/unit/test_json_diff.sh` | MODIFY | Add cases for debug-keystore auto-fill, release-keystore behavior, `--skip-signing` WARN mode. |
| `tests/smoke.sh` | MODIFY | Add AAB round-trip branch (skipped when no AAB fixture). |
| `tests/fixtures/mock.aab.zip` | NEW | Minimal zip-shaped fixture for unit tests. |

---

### Task 1: Implement `find_bundletool` resolver (TDD)

**Files:**
- Create: `lib/bundletool.sh`
- Modify: `lib/env.sh` (adds wrapper that sources `bundletool.sh`)
- Test: `tests/unit/test_bundletool.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test_bundletool.sh`:

```bash
#!/usr/bin/env bash
# Unit tests for find_bundletool resolver.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"
LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/bundletool.sh"

BUNDLETOOL_TEST_ROOT="$(mktemp -d -t bundletool-test-XXXXXX)"
cleanup() { rm -rf "$BUNDLETOOL_TEST_ROOT"; }
trap cleanup EXIT

make_fake_jar() {
    local p="$1"
    mkdir -p "$(dirname "$p")"
    printf "fake-jar\\n" > "$p"
}

test_BUNDLETOOL_JAR_wins() {
    local fake="$BUNDLETOOL_TEST_ROOT/override.jar"
    make_fake_jar "$fake"
    BUNDLETOOL_JAR="$fake" ANDROID_HOME="" ANDROID_SDK_ROOT="" HOME="$BUNDLETOOL_TEST_ROOT" out=$(BUNDLETOOL_JAR="$fake" ANDROID_HOME="" ANDROID_SDK_ROOT="" HOME="$BUNDLETOOL_TEST_ROOT" find_bundletool)
    assert_eq "$out" "$fake" "BUNDLETOOL_JAR has highest priority"
}

test_falls_back_to_ANDROID_HOME() {
    local sdk="$BUNDLETOOL_TEST_ROOT/sdk1"
    make_fake_jar "$sdk/bundletool/bundletool.jar"
    BUNDLETOOL_JAR="" ANDROID_HOME="$sdk" ANDROID_SDK_ROOT="" HOME="$BUNDLETOOL_TEST_ROOT" out=$(BUNDLETOOL_JAR="" ANDROID_HOME="$sdk" ANDROID_SDK_ROOT="" HOME="$BUNDLETOOL_TEST_ROOT" find_bundletool)
    assert_eq "$out" "$sdk/bundletool/bundletool.jar" "ANDROID_HOME used when BUNDLETOOL_JAR unset"
}

test_falls_back_to_mac_default() {
    local home="$BUNDLETOOL_TEST_ROOT/home"
    make_fake_jar "$home/Library/Android/sdk/bundletool/bundletool.jar"
    BUNDLETOOL_JAR="" ANDROID_HOME="" ANDROID_SDK_ROOT="" HOME="$home" out=$(BUNDLETOOL_JAR="" ANDROID_HOME="" ANDROID_SDK_ROOT="" HOME="$home" find_bundletool)
    assert_eq "$out" "$home/Library/Android/sdk/bundletool/bundletool.jar" "macOS default Library/Android/sdk is used"
}

test_returns_empty_when_missing() {
    BUNDLETOOL_JAR="" ANDROID_HOME="" ANDROID_SDK_ROOT="" HOME="$BUNDLETOOL_TEST_ROOT" out=$(BUNDLETOOL_JAR="" ANDROID_HOME="" ANDROID_SDK_ROOT="" HOME="$BUNDLETOOL_TEST_ROOT" find_bundletool)
    assert_eq "$out" "" "no candidate means empty string"
}

test_never_consults_gradle_cache() {
    local home="$BUNDLETOOL_TEST_ROOT/home"
    mkdir -p "$home/.gradle/caches/jars-9"
    make_fake_jar "$home/.gradle/caches/jars-9/bundletool-1.99.0.jar"
    BUNDLETOOL_JAR="" ANDROID_HOME="" ANDROID_SDK_ROOT="" HOME="$home" out=$(BUNDLETOOL_JAR="" ANDROID_HOME="" ANDROID_SDK_ROOT="" HOME="$home" find_bundletool)
    assert_eq "$out" "" "Gradle cache is ignored"
}

run_tests "$SCRIPT_DIR/test_bundletool.sh"
```

Make it executable: `chmod +x tests/unit/test_bundletool.sh`.

- [ ] **Step 2: Run test, expect failure**

Run: `bash tests/unit/test_bundletool.sh`
Expected: error sourcing `lib/bundletool.sh` (exit 127).

- [ ] **Step 3: Implement `lib/bundletool.sh`**

```bash
#!/usr/bin/env bash
# Locate bundletool.jar and the Java runtime used to invoke it.
#
# Resolver order (per spec §5.1):
#   1. $BUNDLETOOL_JAR
#   2. $ANDROID_HOME/bundletool/bundletool.jar
#   3. $ANDROID_SDK_ROOT/bundletool/bundletool.jar
#   4. $HOME/Library/Android/sdk/bundletool/bundletool.jar (mac default)
#   5. $HOME/Android/Sdk/bundletool/bundletool.jar (linux default)
#
# Gradle caches under ~/.gradle/caches/ are intentionally ignored.

find_bundletool() {
    local candidate
    if [ -n "${BUNDLETOOL_JAR:-}" ] && [ -f "${BUNDLETOOL_JAR}" ] && [ -r "${BUNDLETOOL_JAR}" ]; then
        echo "${BUNDLETOOL_JAR}"; return 0
    fi
    for candidate in \\
        "${ANDROID_HOME:-}/bundletool/bundletool.jar" \\
        "${ANDROID_SDK_ROOT:-}/bundletool/bundletool.jar" \\
        "${HOME:-}/Library/Android/sdk/bundletool/bundletool.jar" \\
        "${HOME:-}/Android/Sdk/bundletool/bundletool.jar"; do
        if [ -n "$candidate" ] && [ -f "$candidate" ] && [ -r "$candidate" ]; then
            echo "$candidate"; return 0
        fi
    done
    echo ""; return 0
}

find_java() {
    if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
        echo "${JAVA_HOME}/bin/java"; return 0
    fi
    command -v java 2>/dev/null || echo ""
}

bundletool_cmd() {
    # Echo "java -jar <jar> ..." command, without trailing args.
    local jar; jar="$(find_bundletool)"
    [ -n "$jar" ] || { echo "bundletool_cmd: bundletool.jar not found" >&2; return 3; }
    local java; java="$(find_java)"
    [ -n "$java" ] || { echo "bundletool_cmd: java not found" >&2; return 3; }
    printf "%s -jar %s" "$java" "$jar"
}
```

Make it executable: `chmod +x lib/bundletool.sh`.

- [ ] **Step 4: Run test, expect pass**

Run: `bash tests/unit/test_bundletool.sh`
Expected: all 5 tests pass.

- [ ] **Step 5: Wire wrapper into `lib/env.sh`**

Append to `lib/env.sh` (after the existing `require_tools`):

```bash
# Source bundletool helpers when this file is loaded (no side effects).
. "${BUNDLETOOL_LIB_DIR:-$SCRIPT_DIR}/bundletool.sh" 2>/dev/null || true
```

Note: `lib/env.sh` does not currently know its own directory. If `$SCRIPT_DIR` is not set when `env.sh` is sourced from `check.sh`, replace the line with:

```bash
BUNDLETOOL_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$BUNDLETOOL_LIB_DIR/bundletool.sh" 2>/dev/null || true
```

- [ ] **Step 6: Verify env.sh still loads cleanly**

Run: `bash -c "set -u; . $(pwd)/lib/env.sh && echo OK"`
Expected: prints `OK`.

---

### Task 2: Add `find_debug_keystore` and auto-create helper

**Files:**
- Create: `lib/aab_pipeline.sh` (will host the keystore helper alongside the AAB pipeline)
- Test: `tests/unit/test_aab_pipeline.sh` (initial test for keystore helper)

- [ ] **Step 1: Write the failing test**

Append to `tests/unit/test_aab_pipeline.sh` (file may not exist yet — create with shebang first):

```bash
#!/usr/bin/env bash
# Unit tests for aab_pipeline.sh helpers (keystore + AAB ops).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/../lib/assert.sh"
. "$SCRIPT_DIR/../runner.sh"
LIB_DIR="$SCRIPT_DIR/../../lib"
. "$LIB_DIR/aab_pipeline.sh"

AAB_TEST_ROOT="$(mktemp -d -t aab-test-XXXXXX)"
ORIG_HOME="$HOME"
export HOME="$AAB_TEST_ROOT/home"
mkdir -p "$HOME"
cleanup() { rm -rf "$AAB_TEST_ROOT"; export HOME="$ORIG_HOME"; }
trap cleanup EXIT

test_debug_keystore_path_is_default() {
    out=$(find_debug_keystore)"
    assert_eq "$out" "$HOME/.android/debug.keystore" "debug keystore path matches Android default"
}

test_debug_keystore_auto_creates_when_missing() {
    [ ! -f "$HOME/.android/debug.keystore" ] || { _assert_increment_fail "precondition" "keystore already exists"; return; }
    out=$(aab_ensure_debug_keystore 2>/dev/null)"
    assert_eq "$out" "$HOME/.android/debug.keystore" "ensure path equals debug keystore"
    [ -f "$out" ] || { _assert_increment_fail "keystore created" "missing: $out"; return; }
    _assert_increment_pass "keystore file exists after ensure"
}

test_debug_keystore_does_not_overwrite_existing() {
    mkdir -p "$HOME/.android"
    echo "EXISTING" > "$HOME/.android/debug.keystore"
    out=$(aab_ensure_debug_keystore 2>/dev/null)"
    assert_eq "$out" "$HOME/.android/debug.keystore" "ensure path equals debug keystore"
    assert_eq "$(cat "$out")" "EXISTING" "existing file is preserved"
}

run_tests "$SCRIPT_DIR/test_aab_pipeline.sh"
```

`chmod +x tests/unit/test_aab_pipeline.sh`.

- [ ] **Step 2: Run test, expect failure**

Run: `bash tests/unit/test_aab_pipeline.sh`
Expected: error sourcing `lib/aab_pipeline.sh` (exit 127).

- [ ] **Step 3: Implement `lib/aab_pipeline.sh` (keystore helpers only for now)**

```bash
#!/usr/bin/env bash
# AAB pipeline helpers used by check.sh v2 mode.
# Each function is self-contained and side-effect minimal.

# Default Android debug keystore path.
find_debug_keystore() {
    printf "%s/.android/debug.keystore\\n" "${HOME:-}"
}

# Ensure the debug keystore exists. Echoes the path.
# Returns 3 if keytool is unavailable AND the keystore is missing.
aab_ensure_debug_keystore() {
    local ks; ks="$(find_debug_keystore)"
    if [ -f "$ks" ]; then
        echo "$ks"; return 0
    fi
    if ! command -v keytool >/dev/null 2>&1; then
        echo "aab_ensure_debug_keystore: keytool not on PATH" >&2
        return 3
    fi
    mkdir -p "$(dirname "$ks")"
    keytool -genkeypair -keystore "$ks" -alias androiddebugkey \\
        -storepass android -keypass android \\
        -dname "CN=Android Debug,O=Android,C=US" \\
        -keyalg RSA -validity 10000 >/dev/null 2>&1
    echo "$ks"
}
```

`chmod +x lib/aab_pipeline.sh`.

- [ ] **Step 4: Run test, expect pass**

Run: `bash tests/unit/test_aab_pipeline.sh`
Expected: 3 tests pass.

---

### Task 3: Add AAB unpack / validate / modules / universal builder

**Files:**
- Modify: `lib/aab_pipeline.sh` (add AAB operations)
- Test: `tests/unit/test_aab_pipeline.sh` (extend with AAB cases)
- Create: `tests/fixtures/mock.aab.zip` (a plain zip used as mock bundle)

- [ ] **Step 1: Build the mock fixture**

Run:
```bash
FIX=tests/fixtures/mock.aab.zip
mkdir -p "$(dirname "$FIX")"
tmp=$(mktemp -d); echo bundle > "$tmp/AndroidManifest.xml"; (cd "$tmp" && zip -qr "$OLDPWD/$FIX" AndroidManifest.xml); rm -rf "$tmp"
ls -la tests/fixtures/mock.aab.zip
```
Expected: file exists, ~120-200 bytes.

- [ ] **Step 2: Extend the failing test**

Append to `tests/unit/test_aab_pipeline.sh` (before `run_tests`):

```bash
test_aab_unpack_to_tmp_extracts() {
    local aab="$SCRIPT_DIR/fixtures/mock.aab.zip"
    local out
    out=$(aab_unpack_to_tmp "$aab")
    assert_contains "$out" "/mock.aab.zip-" "tmp path includes bundle basename"
    [ -f "$out/AndroidManifest.xml" ] || { _assert_increment_fail "manifest extracted" "missing"; rm -rf "$out"; return; }
    _assert_increment_pass "manifest extracted"
    rm -rf "$out"
}

test_aab_unpack_rejects_non_zip() {
    local bad="$AAB_TEST_ROOT/bogus.aab"
    echo "nope" > "$bad"
    if aab_unpack_to_tmp "$bad" >/dev/null 2>&1; then
        _assert_increment_fail "non-zip rejected" "got success"
    else
        _assert_increment_pass "non-zip rejected"
    fi
}

test_aab_extract_universal_finds_apk_in_apks_zip() {
    local apks="$AAB_TEST_ROOT/fake.apks"
    mkdir -p "$AAB_TEST_ROOT/build"
    echo "apk-bytes" > "$AAB_TEST_ROOT/build/universal.apk"
    (cd "$AAB_TEST_ROOT/build" && zip -qr "$apks" universal.apk)
    local out
    out=$(aab_extract_universal_apk "$apks" "$AAB_TEST_ROOT/out")
    assert_eq "$out" "$AAB_TEST_ROOT/out/universal.apk" "extract returns expected path"
    [ -f "$out" ] || { _assert_increment_fail "apk file present" "missing: $out"; return; }
    _assert_increment_pass "apk file present"
}

test_aab_validate_writes_status_json() {
    local aab="$SCRIPT_DIR/fixtures/mock.aab.zip"
    local out
    out=$(aab_validate "$aab" 2>/dev/null || true)
    # When bundletool is missing, function emits {"valid":false,"reason":"bundletool_unavailable"}.
    echo "$out" | jq -e . >/dev/null 2>&1 || { _assert_increment_fail "validate emits JSON" "got: $out"; return; }
    _assert_increment_pass "validate emits JSON"
}

- [ ] **Step 3: Run test, expect failure**

Run: `bash tests/unit/test_aab_pipeline.sh`
Expected: 6/3 pass — the new 4 fail with "command not found" for the new functions.

- [ ] **Step 4: Add AAB helpers to `lib/aab_pipeline.sh`**

Append to `lib/aab_pipeline.sh` (keeps existing keystore helpers):

```bash
# Unpack the bundle to a fresh tmp dir. Echoes the tmp dir path.
aab_unpack_to_tmp() {
    local file="$1"
    [ -n "$file" ] && [ -f "$file" ] || { echo "aab_unpack_to_tmp: file not found: $file" >&2; return 2; }
    local first2; first2=$(head -c 2 "$file")
    [ "$first2" = "PK" ] || { echo "aab_unpack_to_tmp: not a zip: $file" >&2; return 2; }
    local out; out=$(mktemp -d -t "$(basename "$file" .aab)-XXXXXX")"
    unzip -q "$file" -d "$out" || { rm -rf "$out"; echo "aab_unpack_to_tmp: unzip failed" >&2; return 2; }
    echo "$out"
}

aab_unpack_cleanup() {
    local d="$1"; [ -n "$d" ] && [ -d "$d" ] && rm -rf "$d"
}

aab_validate() {
    local aab="$1"
    local bt; bt="$(find_bundletool)"
    if [ -z "$bt" ]; then
        jq -n \x27{valid:false, reason:"bundletool_unavailable"}\x27; return 0
    fi
    if java -jar "$bt" validate --bundle "$aab" >/dev/null 2>&1; then
        jq -n \x27{valid:true}\x27; return 0
    else
        jq -n \x27{valid:false, reason:"bundletool_validate_failed"}\x27; return 0
    fi
}

aab_dump_modules() {
    # Emit JSON list of modules; uses bundletool get-package-targeting if available, else fallback.
    local aab="$1"
    local bt; bt="$(find_bundletool)"
    if [ -z "$bt" ]; then
        jq -n \x27[{name:"base", type:"MODULE", required:true}]\x27; return 0
    fi
    local raw
    if raw=$(java -jar "$bt" get-package-targeting --bundle "$aab" 2>/dev/null); then
        # bundletool returns a single package target; treat it as base module.
        jq -n \x27[{name:"base", type:"MODULE", required:true}]\x27; return 0
    fi
    # Fallback: try dump manifest to detect any modules.
    if java -jar "$bt" dump manifest --bundle "$aab" --module base >/dev/null 2>&1; then
        jq -n \x27[{name:"base", type:"MODULE", required:true}]\x27; return 0
    fi
    jq -n \x27[]\x27
}

aab_extract_universal_apk() {
    # Extract universal.apk from a .apks archive to <out_dir>/universal.apk. Echoes the path.
    local apks="$1" out_dir="$2"
    mkdir -p "$out_dir"
    local tmp; tmp=$(mktemp -d -t aab-extract-XXXXXX)
    if ! unzip -q "$apks" -d "$tmp"; then
        rm -rf "$tmp"; echo "aab_extract_universal_apk: unzip failed" >&2; return 2
    fi
    if [ ! -f "$tmp/universal.apk" ]; then
        rm -rf "$tmp"; echo "aab_extract_universal_apk: universal.apk missing in $apks" >&2; return 2
    fi
    mv "$tmp/universal.apk" "$out_dir/universal.apk"
    rm -rf "$tmp"
    echo "$out_dir/universal.apk"
}

aab_build_universal_apk() {
    # Build a signed universal APK from the bundle. Echoes path to extracted apk.
    # Args: aab, workdir, ks, ks_pass, ks_alias, key_pass (pass values; never logged).
    local aab="$1" workdir="$2" ks="$3" ks_pass="$4" ks_alias="$5" key_pass="$6"
    local bt; bt="$(find_bundletool)"
    [ -n "$bt" ] || { echo "aab_build_universal_apk: bundletool.jar not found" >&2; return 3; }
    mkdir -p "$workdir"
    local apks="$workdir/built.apks"
    local -a cmd=("java" "-jar" "$bt" "build-apks"
        "--bundle" "$aab"
        "--output" "$apks"
        "--universal")
    if [ -n "$ks" ]; then
        cmd+=("--ks" "$ks" "--ks-pass" "pass:$ks_pass" "--ks-key-alias" "$ks_alias" "--key-pass" "pass:$key_pass")
    fi
    if ! "${cmd[@]}" >/dev/null 2>&1; then
        echo "aab_build_universal_apk: bundletool build-apks failed for $aab" >&2; return 3
    fi
    aab_extract_universal_apk "$apks" "$workdir"
}
```

- [ ] **Step 5: Run test, expect pass**

Run: `bash tests/unit/test_aab_pipeline.sh`
Expected: 7/7 pass.

---

### Task 4: Dispatch `.aab` inputs in `check.sh`

**Files:**
- Modify: `check.sh` (CLI parsing + dispatch)

- [ ] **Step 1: Add new flag parsing**

In `check.sh`, inside the arg-parsing `while` loop, add these cases alongside the existing ones:

```bash
        --ks)
            [ $# -ge 2 ] || { echo "ERROR: $1 needs path" >&2; exit "$EXIT_USAGE"; }
            KS_PATH="$2"; shift 2 ;;
        --ks-key-alias)
            [ $# -ge 2 ] || { echo "ERROR: $1 needs alias" >&2; exit "$EXIT_USAGE"; }
            KS_ALIAS="$2"; shift 2 ;;
        --ks-pass-env)
            [ $# -ge 2 ] || { echo "ERROR: $1 needs env var name" >&2; exit "$EXIT_USAGE"; }
            KS_PASS_ENV="$2"; shift 2 ;;
        --key-pass-env)
            [ $# -ge 2 ] || { echo "ERROR: $1 needs env var name" >&2; exit "$EXIT_USAGE"; }
            KEY_PASS_ENV="$2"; shift 2 ;;
        --skip-signing)
            SKIP_SIGNING=1; shift ;;
```

Add defaults near the other defaults near the top of `check.sh`:

```bash
KS_PATH=""; KS_ALIAS=""; KS_PASS_ENV=""; KEY_PASS_ENV=""; SKIP_SIGNING=0
```

- [ ] **Step 2: Replace the AAB-reject block with v2 dispatch**

Find the existing block:

```bash
case "$APK" in
    *.aab|*.AAB)
        echo "ERROR: AAB is not supported by v0.1; provide an APK generated from the bundle" >&2
        exit "$EXIT_USAGE"
        ;;
esac
```

Replace it with:

```bash
case "$APK" in
    *.aab|*.AAB) INPUT_KIND="aab" ;;
    *)           INPUT_KIND="apk" ;;
esac

if [ "$INPUT_KIND" = "aab" ] && [ "$MODE" = "check" ] && [ -n "$HARVEST_OUT" ]; then
    echo "ERROR: --out is only valid with --harvest" >&2
    exit "$EXIT_USAGE"
fi

if [ "$INPUT_KIND" = "aab" ] && [ "$SKIP_SIGNING" = "1" ] && [ -n "$KS_PATH" ]; then
    echo "ERROR: --skip-signing is incompatible with --ks" >&2
    exit "$EXIT_USAGE"
fi
```

- [ ] **Step 3: Extend `require_tools` for AAB inputs**

In `check.sh`, immediately after the existing `require_tools` call, insert:

```bash
if [ "$INPUT_KIND" = "aab" ]; then
    BT="$(find_bundletool)"
    if [ -z "$BT" ]; then
        echo "ENV_ERROR: missing tools: bundletool" >&2
        echo "Set BUNDLETOOL_JAR or install via Android SDK at \$ANDROID_HOME/bundletool/bundletool.jar" >&2
        exit "$EXIT_ENV"
    fi
fi
```

- [ ] **Step 4: Add AAB v2 pipeline before v0.1 collect_actual_json**

Insert right before `collect_actual_json` (or the equivalent point in the v0.1 flow). The v0.1 flow must be unchanged for `.apk` inputs.

```bash
if [ "$INPUT_KIND" = "aab" ]; then
    . "$SCRIPT_DIR/lib/aab_pipeline.sh"
    . "$SCRIPT_DIR/lib/bundletool.sh"
    WORKDIR=$(aab_unpack_to_tmp "$APK")
    trap 'aab_unpack_cleanup "$WORKDIR"' EXIT
    BUNDLE_INFO_JSON=$(aab_validate "$APK")
    BUNDLE_MODULES_JSON=$(aab_dump_modules "$APK")

    if [ "$SKIP_SIGNING" = "1" ]; then
        KS_RESOLVED=""; KS_PASS_RESOLVED=""; ALIAS_RESOLVED=""; KEY_PASS_RESOLVED=""; SIGNED_WITH="skip_signing"
    elif [ -n "$KS_PATH" ]; then
        [ -n "$KS_PASS_ENV" ] || { echo "ENV_ERROR: --ks-pass-env is required when --ks is set" >&2; exit "$EXIT_ENV"; }
        KS_RESOLVED="$KS_PATH"
        KS_PASS_RESOLVED="${!KS_PASS_ENV:-}"
        [ -n "$KS_PASS_RESOLVED" ] || { echo "ENV_ERROR: env var $KS_PASS_ENV is empty" >&2; exit "$EXIT_ENV"; }
        ALIAS_RESOLVED="${KS_ALIAS:-}"
        if [ -n "$KEY_PASS_ENV" ]; then
            KEY_PASS_RESOLVED="${!KEY_PASS_ENV:-}"
        else
            KEY_PASS_RESOLVED="$KS_PASS_RESOLVED"
        fi
        SIGNED_WITH="ks:$KS_PATH"
    else
        KS_RESOLVED=$(aab_ensure_debug_keystore 2>/dev/null) || { echo "ENV_ERROR: cannot prepare debug keystore" >&2; exit "$EXIT_ENV"; }
        KS_PASS_RESOLVED="android"; ALIAS_RESOLVED="androiddebugkey"; KEY_PASS_RESOLVED="android"
        SIGNED_WITH="debug_keystore"
    fi

    if [ "$SKIP_SIGNING" = "1" ]; then
        APK=""; EXPECTED_PATH=""; UNIVERSAL_APK=""
    else
        UNIVERSAL_APK=$(aab_build_universal_apk "$APK" "$WORKDIR/build" "$KS_RESOLVED" "$KS_PASS_RESOLVED" "$ALIAS_RESOLVED" "$KEY_PASS_RESOLVED") || { echo "ENV_ERROR: cannot build universal APK" >&2; exit "$EXIT_ENV"; }
        APK="$UNIVERSAL_APK"
    fi
fi
```

- [ ] **Step 5: Verify v0.1 still works**

Run: `bash check.sh --self-check`
Expected: prints `[OK]    Android SDK + jq + unzip available` and exits 0.

- [ ] **Step 6: Bump tool version**

In `check.sh`, change:
```bash
TOOL_VERSION="0.1.0"
```
to:
```bash
TOOL_VERSION="0.2.0"
```

Run: `bash check.sh --version`
Expected: prints `android-precheck v0.2.0`.

---

### Task 5: Debug-keystore auto-fill in `lib/json_diff.sh`

**Files:**
- Modify: `lib/json_diff.sh` (add `diff_signing_sha256_debug_fallback` and plumb it into `diff_apk_vs_expected`)
- Test: `tests/unit/test_json_diff.sh`

- [ ] **Step 1: Write the failing tests**

Append to `tests/unit/test_json_diff.sh` (before `run_tests`):

```bash
# --- debug-keystore auto-fill ---
run_diff_with_keys() {
    # Helper: pass keystore mode via env.
    SIGNED_WITH="$1" ACTUAL_SHA="$2" KEYS_JSON="$3" out=$(run_diff "$ACTUAL_SHA" "$KEYS_JSON")
    echo "$out"
}

test_debug_keystore_missing_sha256_emits_WARN_with_autofill() {
    local actual='{"signing":{"sha256":"abc123","verified":true,"schemes":["v2"]}}'
    local expected='{"expected_signing":{"verified":true}}'
    out=$(SIGNED_WITH="debug_keystore" EXPECTED="$expected" ACTUAL="$actual" run_diff "$actual" "$expected")
    status=$(echo "$out" | jq -r '.results[] | select(.check=="sha256") | .status')
    assert_eq "$status" "WARN" "missing baseline sha256 with debug keystore is WARN, not FAIL"
}

test_debug_keystore_matching_sha256_is_OK() {
    local actual='{"signing":{"sha256":"abc","verified":true}}'
    local expected='{"expected_signing":{"sha256":"abc","verified":true}}'
    out=$(SIGNED_WITH="debug_keystore" run_diff "$actual" "$expected")
    status=$(echo "$out" | jq -r '.results[] | select(.check=="sha256") | .status')
    assert_eq "$status" "OK" "matching debug sha256 stays OK"
}

test_debug_keystore_mismatching_sha256_is_FAIL() {
    local actual='{"signing":{"sha256":"wrong","verified":true}}'
    local expected='{"expected_signing":{"sha256":"abc","verified":true}}'
    out=$(SIGNED_WITH="debug_keystore" run_diff "$actual" "$expected")
    status=$(echo "$out" | jq -r '.results[] | select(.check=="sha256") | .status')
    assert_eq "$status" "FAIL" "mismatched debug sha256 still FAILs"
}

test_release_keystore_missing_sha256_is_FAIL_or_SKIP() {
    local actual='{"signing":{"sha256":"abc","verified":true}}'
    local expected='{"expected_signing":{"verified":true}}'
    out=$(SIGNED_WITH="ks:/path/release.jks" run_diff "$actual" "$expected")
    status=$(echo "$out" | jq -r '.results[] | select(.check=="sha256") | .status')
    # Spec §5.2: release keystore never auto-fills.
    case "$status" in
        FAIL|SKIP|WARN) _assert_increment_pass "release keystore: $status (no autofill)" ;;
        *)              _assert_increment_fail "release keystore: $status (no autofill)" "got: $status" ;;
    esac
}

test_skip_signing_marks_signing_checks_as_WARN() {
    local actual='{"signing":{"sha256":"abc","verified":true}}'
    local expected='{"expected_signing":{"sha256":"abc","verified":true}}'
    out=$(SKIP_SIGNING=1 SIGNED_WITH="skip_signing" run_diff "$actual" "$expected")
    skip_status=$(echo "$out" | jq -r '.results[] | select(.check=="sha256") | .status')
    assert_eq "$skip_status" "WARN" "skip-signing forces WARN on signing/sha256"
}
```

- [ ] **Step 2: Run tests, expect failure**

Run: `bash tests/unit/test_json_diff.sh`
Expected: the 5 new tests fail; v0.1 tests pass.

- [ ] **Step 3: Implement auto-fill inside `lib/json_diff.sh`**

Find the existing signing/sha256 block in `lib/json_diff.sh`. The block currently reads roughly:

```bash
# sha256
expected_sha=$(echo "$expected" | jq -r '.expected_signing.sha256 // ""')
actual_sha=$(echo "$actual"   | jq -r '.signing.sha256 // ""')
if [ -z "$expected_sha" ]; then
    _append "$(jq -n --arg actual "$actual_sha" \
        '{category:"signing", check:"sha256", status:"WARN", expected:"(unset)", actual:$actual}')"
else
    if [ "$expected_sha" = "$actual_sha" ]; then
        _append "$(jq -n ... status:OK ...)"
    else
        _append "$(jq -n ... status:FAIL ...)"
    fi
fi
```

Replace the entire block with:

```bash
# sha256 (with debug-keystore auto-fill per spec §5.2)
expected_sha=$(echo "$expected" | jq -r '.expected_signing.sha256 // ""')
actual_sha=$(echo "$actual"   | jq -r '.signing.sha256 // ""')
SIGNED_WITH="${SIGNED_WITH:-}"
SKIP_SIGNING="${SKIP_SIGNING:-0}"

if [ "$SKIP_SIGNING" = "1" ]; then
    _append "$(jq -n --arg actual "$actual_sha" \
        '{category:"signing", check:"sha256", status:"WARN",
          expected:"(skipped)", actual:$actual,
          message:"signing checks skipped via --skip-signing"}')"
elif [ -z "$expected_sha" ] && [ "$SIGNED_WITH" = "debug_keystore" ]; then
    _append "$(jq -n --arg actual "$actual_sha" \
        '{category:"signing", check:"sha256", status:"WARN",
          expected:"(unset)", actual:$actual,
          message:"auto-filled from debug keystore; replace with upload key SHA-256 before release"}')"
elif [ -z "$expected_sha" ]; then
    _append "$(jq -n --arg actual "$actual_sha" \
        '{category:"signing", check:"sha256", status:"WARN",
          expected:"(unset)", actual:$actual}')"
else
    if [ "$expected_sha" = "$actual_sha" ]; then
        _append "$(jq -n --arg expected "$expected_sha" --arg actual "$actual_sha" \
            '{category:"signing", check:"sha256", status:"OK", expected:$expected, actual:$actual}')"
    else
        _append "$(jq -n --arg expected "$expected_sha" --arg actual "$actual_sha" \
            '{category:"signing", check:"sha256", status:"FAIL", expected:$expected, actual:$actual}')"
    fi
fi
```

- [ ] **Step 4: Run tests, expect pass**

Run: `bash tests/unit/test_json_diff.sh`
Expected: all tests pass.

---

### Task 6: Emit `bundle:` block in `lib/report.sh`

**Files:**
- Modify: `lib/report.sh`
- Modify: `check.sh` (assemble final JSON)

- [ ] **Step 1: Add a helper that wraps a v0.1 results object with the bundle block**

In `lib/report.sh`, append:

```bash
# Assemble the final v2 report JSON given:
#   $1 = path to input
#   $2 = bundle info JSON (string, may be empty)
#   $3 = bundle modules JSON (string, may be empty)
#   $4 = apk results JSON (string from json_diff)
#   $5 = signed_with label
emit_v2_report() {
    local input_path="$1" bundle_info="$2" bundle_modules="$3" apk_results="$4" signed_with="$5"
    local bundle_block
    if [ -n "$bundle_info" ]; then
        bundle_block=$(jq -n \
            --argjson info "$bundle_info" \
            --argjson modules "$bundle_modules" \
            '{bundle: ($info + {modules: $modules})}')
    else
        bundle_block='{"bundle":{}}'
    fi
    jq -n \
        --arg tool "android-precheck" \
        --arg version "0.2.0" \
        --arg path "$input_path" \
        --argjson bb "$bundle_block" \
        --argjson apk "$apk_results" \
        --arg signed "$signed_with" \
        '{tool:$tool, version:$version,
          input:{type:"aab", path:$path},
          ($bb | to_entries | .[0].key): $bb.bundle,
          apk:($apk + {signed_with:$signed})}'
}
```

- [ ] **Step 2: Wire v2 assembly into `check.sh`**

In `check.sh`, replace the final v0.1 output step (search for `format_text` and `compute_exit_code` invocations) so that for AAB inputs it uses `emit_v2_report`. Concretely, wrap the final output assembly in:

```bash
if [ "$INPUT_KIND" = "aab" ]; then
    REPORT_JSON=$(emit_v2_report "$APK_ORIGINAL" "$BUNDLE_INFO_JSON" "$BUNDLE_MODULES_JSON" "$APK_RESULTS_JSON" "$SIGNED_WITH")
else
    REPORT_JSON="$APK_RESULTS_JSON"
fi
```

Add at the very top of the AAB branch (Task 4 §4) so the original path is preserved for the report:

```bash
APK_ORIGINAL="$APK"
```

- [ ] **Step 3: Run v0.1 self-check + version**

Run: `bash check.sh --self-check && bash check.sh --version`
Expected: `[OK]    Android SDK + jq + unzip available` and `android-precheck v0.2.0`.

- [ ] **Step 4: Manual round-trip with a real AAB (only if a fixture is available)**

If `tests/fixtures/sample.aab` exists in the user's environment:

```bash
BUNDLETOOL_JAR="$(command -v jq >/dev/null && /Users/hoangnguyen/Library/Android/sdk/bundletool/bundletool.jar)" \
  bash check.sh tests/fixtures/sample.aab --ks-pass-env ANDROID_KEYSTORE_PASS
```

If `ANDROID_KEYSTORE_PASS` is set, the run will sign with the default debug keystore. Expected exit 0 and a JSON report with `bundle.valid=true`.

If no AAB fixture is present, this step is skipped and the smoke test in Task 7 covers the harness instead.

---

### Task 7: AAB smoke-test branch

**Files:**
- Modify: `tests/smoke.sh`

- [ ] **Step 1: Add AAB branch (gated on a fixture)**

Append to `tests/smoke.sh` before the existing `say` calls or as a final stage:

```bash
AAB="$SCRIPT_DIR/fixtures/sample.aab"
if [ -f "$AAB" ]; then
    say "6/6 AAB round-trip"
    BUNDLETOOL_JAR="${BUNDLETOOL_JAR:-/Users/hoangnguyen/Library/Android/sdk/bundletool/bundletool.jar}"
    export BUNDLETOOL_JAR
    "$CHECK" --harvest "$AAB" -o "$TMPHARV.aab" || fail "AAB harvest failed"
    jq -e '.expected_package' "$TMPHARV.aab" >/dev/null 2>&1 || fail "AAB harvest missing expected_package"
    "$CHECK" "$AAB" --expected "$TMPHARV.aab" >/dev/null 2>&1 || fail "AAB check vs harvested baseline failed"
    jq '.expected_signing.sha256 = "DEADBEEF"' "$TMPHARV.aab" > "$TMPHARV.aab.bad"
    set +e
    "$CHECK" "$AAB" --expected "$TMPHARV.aab.bad" >/dev/null 2>&1
    rc=$?
    set -e
    [ "$rc" = "1" ] || fail "AAB with tampered sha256 must exit 1 (got $rc)"
else
    say "[SKIP] 6/6 AAB fixture not available"
fi
```

- [ ] **Step 2: Run smoke test**

Run: `bash tests/smoke.sh`
Expected: existing 5 stages pass; the new stage skips (no AAB fixture) with `[SKIP]`.

- [ ] **Step 3: Run the full unit-test suite**

Run: `bash tests/runner.sh`
Expected: all unit tests pass.

---

### Task 8: Self-review and finalize

- [ ] **Step 1: Walk through spec checklist**

Re-read `docs/superpowers/specs/2026-08-05-android-precheck-aab-design.md` and confirm:
- §3.1 file map exists: `lib/bundletool.sh`, `lib/aab_pipeline.sh`, new tests.
- §3.2 / §3.3 runtime flows implemented in `check.sh`.
- §4.1 new flags wired.
- §5.1 resolver order in `find_bundletool`.
- §5.2 signing table behaviour: release keystore, debug keystore, skip-signing.
- §5.3 `bundle/valid`, `bundle/modules`, `bundle/base_manifest_metadata` present.
- §6 JSON schema includes `bundle:` block and `signed_with`.
- §7 error rows produce exit codes 2/3/1 as documented.
- §8 tests: unit + smoke.

- [ ] **Step 2: No-placeholder scan**

Run: `grep -nE "TBD|TODO|XXX|FIXME|placeholder" lib/ check.sh tests/unit/*.sh tests/smoke.sh || true`
Expected: empty.

- [ ] **Step 3: Type/name consistency**

Verify in `check.sh` and `lib/aab_pipeline.sh` that the names used across the plan (`aab_unpack_to_tmp`, `aab_validate`, `aab_dump_modules`, `aab_build_universal_apk`, `aab_extract_universal_apk`, `find_bundletool`, `find_debug_keystore`, `aab_ensure_debug_keystore`, `emit_v2_report`) match the spec and earlier tasks exactly.

- [ ] **Step 4: Run the entire test surface one last time**

Run: `bash tests/runner.sh && bash tests/smoke.sh && bash check.sh --self-check`
Expected: all green.


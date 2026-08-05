# android-precheck v2 — AAB Support Design

> Companion to docs/2026-07-24-android-precheck-design.md (v0.1 APK design).
> This document specifies v2: extend android-precheck to verify Android App Bundles (.aab)
> by reusing the existing v0.1 checker set on a universal APK built from the bundle via bundletool.

## 1. Problem & motivation

v0.1 (android-precheck 0.1.0) verifies only .apk artifacts. Unity Android builds produced for Google Play are App Bundles (.aab), not APKs, and the post-submit regression we want to catch — Google Play Games plugin reset of com.google.android.gms.games.APP_ID, keystore mismatch, missing Play Games provider authority, debuggable builds, missing billing client metadata — can already be present in the bundle even before bundletool re-packages it.

v0.1 currently rejects AAB explicitly:

ERROR: AAB is not supported by v0.1; provide an APK generated from the bundle

This forces the team to either build a separate APK locally (which diverges from the artifact submitted to Google Play) or skip pre-submission checks. v2 removes that gap without duplicating the v0.1 checker set.

### Non-goals (v2)

- Detailed dynamic-feature / asset-pack validation (only module enumeration).
- Device-specific APK set generation (--device-spec).
- Upload-key rotation flow or Play App Signing metadata.
- AAB signing-cert analysis outside what the universal APK exposes.
- Replacing v0.1; the v0.1 path is unchanged and stays the default for .apk.

## 2. Goals

1. Accept *.aab as input in the same CLI surface as *.apk.
2. Reuse 100%% of the v0.1 checker set on a universal APK derived from the bundle.
3. Provide a signing story that is safe-by-default (debug keystore fallback) and strict-by-request (--ks for upload/release keystore).
4. Preserve v0.1 output schema; add a sibling bundle: block instead of a new top-level format.
5. Keep the v0.1 dependency story intact (no Python, no Node, no auto-downloads).

## 3. Architecture overview

v2 layers on top of v0.1 without modifying v0.1 checker semantics.

.apk path flows through the v0.1 pipeline unchanged. .aab path is routed to the new AAB pipeline in lib/aab_pipeline.sh, which produces a universal APK; the universal APK is then handed to the v0.1 pipeline unmodified.

### 3.1 File / folder layout (delta over v0.1)

android-precheck/
├── check.sh                       (extended — dispatches .aab to v2)
├── lib/
│   ├── bundletool.sh              (NEW — resolver + env)
│   ├── aab_pipeline.sh            (NEW — bundle validate / build universal)
│   ├── env.sh                     (extended — adds find_bundletool, find_debug_keystore)
│   ├── apk_unpack.sh              (unchanged)
│   ├── apk_badging.sh             (unchanged)
│   ├── apk_manifest.sh            (unchanged)
│   ├── apk_certs.sh               (unchanged)
│   ├── apk_abi.sh                 (unchanged)
│   ├── json_diff.sh               (extended — debug-keystore auto-fill)
│   ├── report.sh                  (extended — bundle: block)
│   └── common.sh                  (unchanged)
├── tests/
│   ├── unit/
│   │   ├── test_bundletool.sh     (NEW)
│   │   ├── test_aab_pipeline.sh   (NEW — uses fixture zip)
│   │   └── test_json_diff.sh      (extended — debug-keystore fallback)
│   ├── smoke.sh                   (extended — AAB round-trip)
│   └── fixtures/
│       ├── keys.example.json      (unchanged)
│       └── mock.aab.zip           (NEW — minimal bundle-shaped fixture)
└── docs/
    └── superpowers/
        └── specs/
            └── 2026-08-05-android-precheck-aab-design.md   (this file)

### 3.2 v2 runtime flow (mode --check, input .aab)

check.sh <aab>
  1. Detect .aab extension → set MODE=aab_check.
  2. require_tools (extended) verifies bundletool + aapt2 + apksigner + jq + unzip.
  3. aab_unpack_to_tmp <aab>          → $WORKDIR (mktemp -d -t aab-<pid>-XXXXXX).
  4. aab_validate <aab>              → record bundle.valid; if FAIL, skip steps 5–8 and set bundle.{modules,base_manifest_metadata} to empty.
  5. aab_dump_modules <aab>          → list modules + base manifest metadata.
  6. Resolve signing:
        a. If --ks is set, use that keystore.
        b. Else if --skip-signing is set, skip step 7 and mark every v0.1 check whose category=signing as WARN in step 8.
        c. Else, default to ~/.android/debug.keystore (auto-create with keytool only if it is missing).
  7. aab_build_universal_apk <aab>   → $WORKDIR/universal.apk.
  8. Replay v0.1 APK pipeline on $WORKDIR/universal.apk.
  9. json_diff applies the optional debug-keystore auto-fill (see §5.2).
 10. report.sh emits { tool, version, input, bundle, apk }.
 11. Trap cleanup removes $WORKDIR; no signing artifact persists.

### 3.3 v2 runtime flow (mode --harvest, input .aab)

check.sh <aab> --harvest -o keys.json
  1. Steps 1–7 of §3.2 (no skip-signing).
  2. Run the v0.1 harvest path on $WORKDIR/universal.apk.
  3. Annotate expected_signing.sha256 with provenance (only when keys.json was just produced by this run, i.e. output file is empty or did not exist):
        "provenance": "universal_apk" | "debug_keystore_fallback"
     The value is debug_keystore_fallback iff the auto-fill in §5.2 actually fired; otherwise it is universal_apk. A WARN line is printed to stderr only when debug_keystore_fallback is set.
  4. Write keys.json; do not log keystore passwords.

## 4. CLI contract (delta over v0.1)

### 4.1 New / changed flags

| Flag | Scope | Description |
|---|---|---|
| --ks <path> | --check, --harvest | Path to a keystore (.keystore/.jks) used to sign the universal APK. If omitted, the debug keystore at ~/.android/debug.keystore is used. |
| --ks-key-alias <alias> | --check, --harvest | Alias inside --ks. Default: androiddebugkey (debug keystore default). |
| --ks-pass-env <var> | --check, --harvest | Name of the env var that holds the keystore password. Tool reads but does not log the value. |
| --key-pass-env <var> | --check, --harvest | Name of the env var that holds the key password (defaults to the keystore password when unset). |
| --skip-signing | --check | Skip bundletool build-apks; only bundletool dump manifest is used. All signing checks emit WARN. Incompatible with --ks. |

### 4.2 Unchanged from v0.1

--expected / --strict / --no-color / --json / --flavor / --self-check all keep their v0.1 semantics. --self-check additionally reports whether bundletool is discoverable (does not fail the run if it is absent).

### 4.3 Exit codes

| Code | Meaning |
|---|---|
| 0 | All OK (or only SKIP/WARN) |
| 1 | At least one [FAIL] |
| 2 | Bad usage / corrupt input |
| 3 | Environment error (bundletool / aapt2 / apksigner / keystore) |
| 4 | --strict and critical key missing |
| 5 | --harvest I/O error |

No new exit codes. --skip-signing cannot produce EXIT_STRICT from a missing keystore because it does not invoke the signer.

## 5. Behavior details

### 5.1 bundletool discovery

lib/bundletool.sh resolves the JAR in this order and returns the first existing, readable .jar file:

1. $BUNDLETOOL_JAR (must be a path to a file).
2. $ANDROID_HOME/bundletool/bundletool.jar.
3. $ANDROID_SDK_ROOT/bundletool/bundletool.jar.
4. $HOME/Library/Android/sdk/bundletool/bundletool.jar.
5. $HOME/Android/Sdk/bundletool/bundletool.jar.

find_bundletool does NOT consult ~/.gradle/caches/.../bundletool-*.jar. Reproducibility, version drift across machines, and unsigned copies in the Gradle cache are the reasons this cache is excluded.

require_tools adds bundletool to its required list only when the input path is .aab. --self-check on its own does not require bundletool; it only reports whether bundletool is discoverable, mirroring the v0.1 behavior for aapt2/apksigner.

### 5.2 Signing story

| Situation | Behavior |
|---|---|
| --ks provided, alias + env-pass set | bundletool build-apks --ks <path> --ks-pass pass:env:<var> --ks-key-alias <alias> produces a signed universal APK. v0.1 signing checks compare against expected_signing.sha256 exactly. |
| --ks provided but env-pass missing | [FAIL] env: --ks-pass-env not set (exit 3). |
| No --ks, debug keystore present | Default to ~/.android/debug.keystore (alias androiddebugkey, password android). Universal APK is signed with it. |
| No --ks, debug keystore missing | Tool auto-creates it once via keytool -genkeypair -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android -dname "CN=Android Debug,O=Android,C=US" -keyalg RSA -validity 10000. If keytool is not on PATH and the keystore is missing, the run aborts with the env error in §7. |
| --skip-signing | bundletool dump manifest is the only bundletool invocation. All signing/* checks in the v0.1 set emit WARN instead of OK/FAIL and expected_signing.sha256 is not evaluated. |

#### Debug-keystore auto-fill for expected_signing.sha256

When the universal APK is signed with the debug keystore AND keys.json does not contain expected_signing.sha256, the tool:

1. Records the SHA-256 of the signing certificate into the diff context.
2. Emits a signing/sha256 check with status WARN, message "auto-filled from debug keystore; replace with upload key SHA-256 before release", expected: "(unset)", actual: "<sha256>".
3. Continues the rest of the diff against the auto-filled value so the rest of the checks behave as if the baseline were present.

When the universal APK is signed with the debug keystore AND keys.json already contains an expected_signing.sha256, the tool does NOT auto-fill. The diff runs against the declared value; mismatch is FAIL, match is OK. This protects the team from silently overriding a known-good upload-key baseline.

When the universal APK is signed with a release keystore (--ks), the auto-fill never engages. The v0.1 behavior is preserved exactly.

### 5.3 AAB-specific surface (kept minimal)

| Check | Source | Output |
|---|---|---|
| bundle/valid | bundletool validate exit code | OK / FAIL |
| bundle/modules | bundletool get-package-targeting (or dump manifest --module) | JSON list, including base |
| bundle/base_manifest_metadata | bundletool dump manifest --module base parsed with the existing lib/apk_manifest.sh | Same metadata shape used by v0.1 |

The full v0.1 check set runs against the universal APK only.

## 6. Output schema (delta)

keys.json keeps the v0.1 schema; only an optional provenance annotation is added to expected_signing.sha256 during AAB harvest.

Report JSON gains a bundle: block:

{
  "tool": "android-precheck",
  "version": "0.2.0",
  "input": { "type": "aab", "path": "build/app.aab" },
  "bundle": {
    "valid": true,
    "modules": [
      { "name": "base", "type": "MODULE", "required": true },
      { "name": "asset_pack_1", "type": "ASSET_PACK" }
    ],
    "base_manifest_metadata": {
      "package": "com.wb.goog.dc.dcwc",
      "versionCode": "11401",
      "versionName": "1.1.14.1",
      "minSdk": "25",
      "targetSdk": "35",
      "compileSdk": "35",
      "permissions": [],
      "abi": []
    }
  },
  "apk": {
    "path": "tmp/aab-12345/universal.apk",
    "signed_with": "debug_keystore",
    "results": [ /* same shape as v0.1 .results[] */ ],
    "summary": { "ok": 0, "fail": 0, "skip": 0, "warn": 1, "total": 1 }
  }
}

Human-readable text mode keeps the v0.1 layout. Results in the bundle: block use the prefix bundle/ (e.g. [bundle/valid], [bundle/modules]). Results in the apk: block keep their v0.1 category prefixes (signing, meta-data, components, permissions, abi, application-attribute, version, package, sdk).

## 7. Error handling (new rows)

| Situation | Behavior |
|---|---|
| Input is not a zip (bad extension passed as .aab) | [FAIL] bundle invalid: not a zip (exit 2) |
| bundletool validate non-zero | bundle.valid = FAIL; the rest of the v2 pipeline is skipped and exit code is 1 |
| bundletool build-apks non-zero | [FAIL] bundle: cannot build universal APK: <stderr> (exit 3) |
| bundletool not found | [FAIL] env: bundletool.jar not found; set BUNDLETOOL_JAR or install via Android SDK (exit 3) |
| keytool not on PATH when debug keystore must be created | [FAIL] env: keytool missing; install a JDK (exit 3) |
| --skip-signing + --ks together | [FAIL] usage: --skip-signing is incompatible with --ks (exit 2) |
| aab_unpack_to_tmp cannot create tmp dir | [FAIL] env: mktemp failed (exit 3) |

## 8. Testing strategy

### 8.1 New unit tests

- tests/unit/test_bundletool.sh
  - Honors $BUNDLETOOL_JAR when set.
  - Falls back to $ANDROID_HOME/bundletool/bundletool.jar.
  - Returns empty when no candidate path exists (mocked env).
  - Never consults Gradle cache.
- tests/unit/test_aab_pipeline.sh
  - aab_unpack_to_tmp extracts fixture zip and removes on cleanup.
  - aab_validate records bundle.valid based on mocked bundletool output.
  - aab_dump_modules returns the documented base + asset_pack shape.
- tests/unit/test_json_diff.sh (extended)
  - Debug keystore + missing expected_signing.sha256 → WARN with auto-fill.
  - Debug keystore + matching expected_signing.sha256 → OK.
  - Debug keystore + non-matching expected_signing.sha256 → FAIL.
  - Release keystore + missing expected_signing.sha256 → WARN (no auto-fill).
  - --skip-signing mode → all signing checks are WARN.

### 8.2 Smoke test extensions

tests/smoke.sh adds an AAB branch gated on a real AAB being present in tests/fixtures/. When absent, the branch is skipped with [SKIP] AAB fixture not available so the smoke test still passes in environments without an AAB sample.

When an AAB fixture is available, the smoke test verifies:

1. bundletool build-apks --universal produces a .apks archive containing a universal.apk that is a valid zip.
2. --harvest from the AAB yields a keys.json with provenance set.
3. --check against the harvested keys.json exits 0 with only OK/WARN results.
4. --check with a tampered expected_signing.sha256 exits 1 with at least one signing/sha256 FAIL.

## 9. Open questions

None. All v2 design choices were resolved during brainstorming on 2026-08-05 with the user.

## 10. References

- v0.1 design: docs/2026-07-24-android-precheck-design.md
- v0.1 implementation plan: docs/2026-07-24-android-precheck-implementation.md
- bundletool CLI reference: https://developer.android.com/build/bundletool

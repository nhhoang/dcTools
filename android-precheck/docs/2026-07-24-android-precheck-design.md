# android-precheck — Design

**Date:** 2026-07-24
**Status:** Implemented and reviewed (2026-07-26)
**Author:** Codex
**Location in repo:** `/Users/hoangnguyen/Perforce/MacbookPro/android-precheck/`

---

## 1. Problem & motivation

Sau khi upgrade Google Play Games Plugin for Unity (`com.google.play.games`), `AndroidManifest.xml` của merged `androidlib` bị reset `<meta-data android:name="com.google.android.gms.games.APP_ID">` về giá trị placeholder (vd `99009804916`) thay vì ID thật của game (`299009804916`). Hậu quả: AAB submit lên Play Console vẫn "upload OK", nhưng runtime Play Games Services không khởi tạo được, người chơi không login được. Bug chỉ phát hiện sau khi game đã lên store vài ngày.

Cùng loại "silent failure" có thể xảy ra với:
- Signing cert: keystore mới / nhầm keystore → Play từ chối upload hoặc khóa bảo ký
- AdMob `APPLICATION_ID`: nhầm giữa dev/prod hoặc giữa 2 game
- Google Play Billing version: plugin upgrade kéo về version sai → IAP không khởi tạo
- Manifest merge: thiếu `PlayGamesInitProvider`, `ComponentDiscoveryService`, v.v.

Mục tiêu: một tool CLI trích manifest thật của APK vừa build, so với `keys.json` baseline, fail fast trước khi upload.

---

## 2. Goals & non-goals

### Goals (MVP-1)

1. Verify một APK (`*.apk`) đã build xong có đúng:
   - **Signing cert SHA-256** (keystore check)
   - **GPGS `APP_ID`** (bug cũ của user)
   - `unityVersion`, `ads.APPLICATION_ID`, `billingclient.version` (các meta-data dễ bị upgrade plugin reset)
   - `package` (applicationId)
   - `versionCode`, `versionName`, `minSdk` / `targetSdk` / `compileSdk`
   - Danh sách permission bắt buộc có / bắt buộc không có
   - Components quan trọng (PlayGamesInitProvider, ComponentDiscoveryService, ProxyBillingActivity…)
   - ABIs (`arm64-v8a` bắt buộc; `mips`/`mips64`/`x86` cấm)
   - `application/@android:debuggable` (so với flavor)
2. Cho phép user **delete bớt field** trong `keys.json` nếu không quan tâm check đó.
3. Cho phép **harvest** APK mẫu → tự sinh `keys.json` để bootstrap.
4. Output người đọc được (text), exit code để tích hợp script/IDE/CI sau này.
5. Hoạt động **chỉ với Android SDK đã có sẵn** + `unzip` + `jq` (đa số máy dev Android đều có).

### Non-goals (deferred / out of scope cho MVP-1)

- ❌ AAB (`.aab`) verification — cần `bundletool.jar` ~30MB; dời v2
- ❌ Native lib decompile / secret scan trong `.so` / `.dex` (rất noise, tốn thời gian)
- ❌ ProGuard/R8 mapping check
- ❌ Tampering scan / virus scan APK
- ❌ Auto-fix các FAIL (chỉ detect)
- ❌ CI server integration (GitHub Action, Jenkins…)
- ❌ Multi-flavor build switcher (user confirm chỉ 1 variant duy nhất cho game này)
- ❌ Realtime monitor khi Unity build (chỉ chạy post-build)
- ❌ Web UI / GUI

---

## 3. Architecture overview

### 3.1 File / folder layout

```
MacbookPro/android-precheck/
├── check.sh                              ← CLI entry duy nhất, subcommand dispatch
├── lib/
│   ├── common.sh                         ← logging, ANSI, color codes, exit codes
│   ├── env.sh                            ← locate Android SDK (aapt2/apksigner), jq, etc.
│   ├── apk_unpack.sh                     ← unzip APK ra tmp dir
│   ├── apk_manifest.sh                   ← parse merged AndroidManifest bằng aapt2 → JSON
│   ├── apk_certs.sh                      ← apksigner verify → cert SHA-256, DN, signature schemes
│   ├── apk_components.sh                 ← scan activity/service/provider/receiver
│   ├── apk_meta.sh                       ← scan toàn bộ <meta-data>
│   ├── apk_perms.sh                      ← scan uses-permission
│   ├── apk_abi.sh                        ← scan lib/<ABI>/*
│   ├── apk_attrs.sh                      ← scan application-attrs (debuggable, extractNativeLibs…)
│   ├── apk_badging.sh                    ← aapt2 dump badging → package/version/sdk
│   ├── json_diff.sh                      ← so 2 JSON: actual vs expected, ra [OK]/[FAIL]/[SKIP]/[WARN]
│   └── report.sh                         ← in summary table + tổng kết
├── docs/
│   └── 2026-07-24-android-precheck-design.md   ← file này
├── tests/
│   ├── smoke.sh                          ← chạy check.sh với fixture, kỳ vọng output
│   └── fixtures/
│       ├── DGame_debug_1.1.14.1.apk      ← APK thật (user đã đưa) — dùng làm baseline
│       └── keys.example.json             ← keys.json harvest từ APK thật
├── keys.json                             ← baseline local của user; bị ignore
└── README.md                             ← cách cài, cách dùng, troubleshooting
```

### 3.2 Runtime flow (mode `--check` mặc định)

```
check.sh <apk> [--expected keys.json] [--strict] [--no-color]
   │
   ▼
[env.sh]  Locate aapt2 / apksigner / jq. Fail sớm nếu thiếu.
   │
   ▼
[apk_unpack.sh]   unzip <apk> → $TMPDIR/apk-<pid>/, copy manifest ra file txt
   │
   ▼
Parallel: [apk_badging] [apk_certs] [apk_manifest] [apk_components]
           [apk_meta]  [apk_perms] [apk_abi]   [apk_attrs]
   │                                                       │
   │                          (tất cả đổ ra JSON chuẩn)    │
   ▼                                                       ▼
[json_diff.sh]   diff actual.json vs expected.keys.json
   │              → danh sách [OK]/[FAIL]/[SKIP]/[WARN]
   ▼
[report.sh]      in summary + exit code
```

### 3.3 Runtime flow (mode `--harvest`)

```
check.sh --harvest <apk> [--expected template.json] [--out path]
   │
   ▼
[Tất cả parser chạy như --check nhưng bỏ diff]
   │
   ▼
[json_diff.sh --mode=harvest]  dump actual.json, ghi ra file
   │
   ▼
print "harvest done → keys.json"
```

### 3.4 Runtime flow (mode `--strict`)

Giống `--check` nhưng:
- Các field **critical** mà không khai báo trong expected → `[FAIL] CRITICAL: expected_signing.sha256 missing — add it or run --harvest`
- Dùng khi user đã ổn định, muốn chắc chắn không quên check signature/app_id.

---

## 4. CLI contract

### 4.1 Subcommands

| Form | Mục đích |
|---|---|
| `check.sh <apk>` | Check với `keys.json` ở `android-precheck/keys.json` (mặc định) |
| `check.sh <apk> -e <path>` | Check với file expected chỉ định |
| `check.sh <apk> -e <path> --strict` | Fail nếu thiếu critical key |
| `check.sh --harvest <apk> [-o <path>]` | Sinh JSON từ APK ra `<path>` (mặc định stdout) |
| `check.sh --self-check` | Tool tự kiểm tra (Android SDK hiện có không, jq có không) |

### 4.2 Flags

```
check.sh <apk> [options]

  -e, --expected <path>    Path tới expected-keys JSON (default: ./keys.json)
  --strict                 Fail nếu critical key thiếu
  --no-color               Tắt ANSI color (cho log file / CI)
  --json                   Output JSON-only (cho CI integration sau này)
  --harvest <apk>          Sinh JSON baseline từ APK thật
  -o, --out <path>         Output cho --harvest (default: stdout)
  --self-check             Verify môi trường (aapt2, apksigner, jq)
  -h, --help               Help
  -v, --version            Version
```

### 4.3 Exit codes

| Code | Ý nghĩa |
|---|---|
| 0 | All OK (hoặc chỉ WARN/SKIP, không FAIL) |
| 1 | Có ít nhất 1 `[FAIL]` |
| 2 | Sai dùng (bad arg, file không tồn tại, APK corrupt) |
| 3 | Môi trường thiếu tool (aapt2/apksigner/jq) |
| 4 | `--strict` và thiếu critical key |
| 5 | `--harvest` không ghi được file output |

---

## 5. Output format

### 5.1 Standard text mode (human-readable)

```
android-precheck v0.1.0 — Android APK Pre-Submission Verification
File: build/DGame_release_1.1.14.1.apk
Expected: android-precheck/keys.json
Flavor: release
   ▼ ─────────────────────────────
[OK]    package = com.wb.goog.dc.dcwc
[OK]    versionName = 1.1.14.1
[OK]    versionCode = 1
[OK]    minSdk = 25, targetSdk = 35, compileSdk = 35
[OK]    signing sha256 = b46acd3981297ed08d84531a9de00543510ef1413a6ae667b9bf487cf23293c4
[OK]    signing subject DN contains all of: ["WB Games", "Team Leads", "WBSF"]
[OK]    signature schemes = [v2]
[FAIL]  meta-data com.google.android.gms.games.APP_ID
        expected: "299009804916"
        actual:   "99009804916"
        → Looks like plugin reset to placeholder value. Re-run Play Games plugin
          Setup (Window → Google Play Games → Setup) and rebuild.
[SKIP]  meta-data com.google.android.gms.games.unityVersion (not configured)
[WARN]  meta-data com.google.android.gms.ads.APPLICATION_ID (recommended key missing)
[OK]    meta-data com.google.android.gms.ads.APPLICATION_ID = "ca-app-pub-5689963351750691~9138731913"
[OK]    permissions_present: all 5 expected
[OK]    permissions_absent: none of 2 forbidden
[FAIL]  component PlayGamesInitProvider (authority) — package prefix mismatch
        expected authority to contain: "com.wb.goog.dc.dcwc"
        actual authority:              "com.google.example.games.mainlibproj"
        → AndroidManifest merger is not applying {applicationId} placeholder.
          Check mainTemplate.gradle has manifestPlaceholders correct.
[OK]    abi include: arm64-v8a
[OK]    abi exclude: mips, mips64, x86
[SKIP]  application/debuggable (not configured)
[WARN]  application/debuggable = true but flavor=release expected false (recommended)
   ▼ ─────────────────────────────
SUMMARY: 9 OK, 2 FAIL, 3 SKIP, 2 WARN
Exit: 1
```

ANSI codes:
- `[OK]`   → green (32)
- `[FAIL]` → red (31) bold
- `[SKIP]` → grey (90)
- `[WARN]` → yellow (33)

### 5.2 `--json` mode

```json
{
  "tool": "android-precheck",
  "version": "0.1.0",
  "apk": "/path/build.apk",
  "expected": "/path/keys.json",
  "flavor": "release",
  "results": [
    { "category": "package",        "check": "package",            "status": "OK",   "expected": "com.wb.goog.dc.dcwc", "actual": "com.wb.goog.dc.dcwc" },
    { "category": "signing",        "check": "sha256",             "status": "OK",   "expected": "b46acd39...", "actual": "b46acd39..." },
    { "category": "meta-data",      "check": "gms.games.APP_ID",   "status": "FAIL", "expected": "299009804916", "actual": "99009804916", "message": "..." },
    { "category": "meta-data",      "check": "gms.games.unityVersion", "status": "SKIP" },
    ...
  ],
  "summary": { "ok": 9, "fail": 2, "skip": 3, "warn": 2 },
  "exit_code": 1
}
```

---

## 6. JSON schema — `keys.json`

### 6.1 Schema chính

```json
{
  "_doc": "android-precheck baseline. Every field is optional. Critical keys (--strict) are listed in tool docs.",

  "expected_signing": {
    "sha256":  "<hex 64 chars>",
    "sha1":    "<hex 40 chars>",
    "md5":     "<hex 32 chars>",
    "subjectDN": "<exact certificate DN>",
    "subject_dn_contains": ["<substring>", ...],
    "verified": true,
    "must_use_signature_scheme": ["v2", "v3", "v3.1", "v4"]
  },

  "expected_package": "<applicationId>",
  "expected_version": {
    "versionName":     "<string>",
    "versionCode_min": <int>,
    "versionCode_max": <int>,
    "versionCode_eq":  <int>
  },
  "expected_sdk": {
    "minSdk":     <int>,
    "targetSdk":  <int>,
    "compileSdk": <int>
  },

  "expected_meta_data": {
    "<android:name>": "<expected value>"
  },

  "expected_attributes": {
    "<attr-resource-name>": <expected value or boolean>
  },

  "expected_components_present": [
    "<fully-qualified-class-name>",
    "<authority-substring-as-Provider>"
  ],

  "expected_permissions_present": ["<permission-name>", ...],
  "expected_permissions_absent":  ["<permission-name>", ...],

  "expected_abi": {
    "must_include": ["<abi>", ...],
    "must_exclude": ["<abi>", ...]
  },

  "_flavors": {
    "<flavor-name>": {
      "expected_attributes": {
        "application/@android:debuggable":  <bool>,
        "billing_sandbox":                   <bool>
      }
    }
  }
}
```

### 6.2 Field semantics — khi nào `[FAIL]` / `[SKIP]` / `[WARN]`

| Field con | Nếu khớp | Nếu lệch | Nếu field thiếu trong `keys.json` |
|---|---|---|---|
| `expected_signing.sha256` | `[OK]` | `[FAIL]` | mode mặc định `[WARN]`; `--strict` exit `4` (CRITICAL) |
| `expected_signing.sha1`, `md5` | `[OK]` | `[FAIL]` | `[SKIP]` |
| `expected_signing.verified` | `[OK]` | `[FAIL]` | `[SKIP]` |
| `expected_signing.subject_dn_contains` | `[OK]` nếu DN chứa tất cả | `[FAIL]` nếu thiếu ≥1 | `[SKIP]` |
| `expected_signing.must_use_signature_scheme` | `[OK]` nếu scheme ∈ list | `[FAIL]` nếu thiếu scheme | `[SKIP]` |
| `expected_package` | `[OK]` | `[FAIL]` | `[SKIP]` |
| `expected_version.*` | `[OK]` | `[FAIL]` | `[SKIP]` |
| `expected_sdk.*` | `[OK]` | `[FAIL]` | `[SKIP]` |
| `expected_meta_data.<key>` (mỗi entry) | `[OK]` | `[FAIL]` | `[SKIP]` riêng entry đó |
| `expected_meta_data[gms.games.APP_ID]` (SPECIAL) | `[OK]` | `[FAIL]` | mode mặc định `[WARN]` (recommended); `--strict` `[FAIL]` (CRITICAL) |
| `expected_attributes.*` | `[OK]` | `[FAIL]` | `[SKIP]` |
| `expected_components_present` | `[OK]` nếu có tất cả | `[FAIL]` listing thiếu | `[SKIP]` |
| `expected_permissions_present` | `[OK]` nếu có tất cả | `[FAIL]` listing thiếu | `[SKIP]` |
| `expected_permissions_absent` | `[OK]` nếu không có cái nào cấm | `[FAIL]` nếu có cấm | `[SKIP]` |
| `expected_abi.must_include` | `[OK]` nếu mọi ABI có | `[FAIL]` nếu thiếu | `[SKIP]` |
| `expected_abi.must_exclude` | `[OK]` nếu không có ABI cấm | `[FAIL]` nếu có cấm | `[SKIP]` |
| `_flavors[release].debuggable=false` | `[OK]` | `[FAIL]` | `[SKIP]` |

### 6.3 Critical keys (hardcoded trong tool, không bypass được)

Các key này luôn luôn có ý nghĩa đặc biệt trong `--strict`:
1. `expected_signing.sha256` — cert leak / upload-key swap detection
2. `expected_meta_data["com.google.android.gms.games.APP_ID"]` — bug cũ, không bao giờ được thiếu trong release

Nếu tool được chạy mà thiếu 1 trong 2 key critical:
- mode mặc định: in `[WARN]` recommended, không fail
- `--strict`: `[FAIL]` CRITICAL — user phải harvest/cấu hình lại

### 6.4 Example — minimal `keys.json` (user chỉ muốn 2 check)

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

### 6.5 Example — full `keys.json` (recommend cho production)

```json
{
  "expected_signing": {
    "sha256": "b46acd3981297ed08d84531a9de00543510ef1413a6ae667b9bf487cf23293c4",
    "sha1":   "5e455590db0114a063fd8fc8f620299087aa223c",
    "md5":    "f9189ba8366331d299d08304a7e311a3",
    "subject_dn_contains": ["WB Games", "Team Leads", "WBSF"],
    "must_use_signature_scheme": ["v2"]
  },
  "expected_package": "com.wb.goog.dc.dcwc",
  "expected_version": {
    "versionName": "1.1.14.1",
    "versionCode_min": 1
  },
  "expected_sdk": {
    "minSdk": 25,
    "targetSdk": 35,
    "compileSdk": 35
  },
  "expected_meta_data": {
    "com.google.android.gms.games.APP_ID":              "299009804916",
    "com.google.android.gms.games.unityVersion":        "2.0.0",
    "com.google.android.gms.ads.APPLICATION_ID":        "ca-app-pub-5689963351750691~9138731913",
    "com.google.android.play.billingclient.version":   "7.1.1"
  },
  "expected_attributes": {
    "application/@android:debuggable":       false,
    "application/@android:extractNativeLibs": false
  },
  "expected_components_present": [
    "com.google.android.gms.games.provider.PlayGamesInitProvider",
    "com.google.firebase.components.ComponentDiscoveryService",
    "com.android.billingclient.api.ProxyBillingActivity"
  ],
  "expected_permissions_present": [
    "android.permission.INTERNET",
    "android.permission.ACCESS_NETWORK_STATE",
    "android.permission.WAKE_LOCK",
    "com.android.vending.BILLING",
    "com.google.android.gms.permission.AD_ID"
  ],
  "expected_permissions_absent": [
    "android.permission.QUERY_ALL_PACKAGES",
    "android.permission.SYSTEM_ALERT_WINDOW",
    "android.permission.READ_PHONE_STATE"
  ],
  "expected_abi": {
    "must_include": ["arm64-v8a"],
    "must_exclude": ["mips", "mips64", "x86"]
  },
  "_flavors": {
    "debug":   { "expected_attributes": { "application/@android:debuggable": true  } },
    "release": { "expected_attributes": { "application/@android:debuggable": false } }
  }
}
```

`tests/fixtures/keys.example.json` là full baseline tracked; `keys.json` là copy
local bị ignore và có thể được trim tùy policy release.

---

## 7. Detected checks — chi tiết

### 7.1 Signing

- Tool: `apksigner verify --verbose --print-certs <apk>`
- Trích ra:
  - SHA-256, SHA-1, MD5 của cert
  - Subject DN (`CN=...,OU=...,O=...,L=...,ST=...,C=...`)
  - Key algorithm + size
  - Verified schemes (v1/v2/v3/v3.1/v4)
- Compare theo `expected_signing.*`
- **Note**: release APK nên enforce scheme phù hợp (baseline hiện tại là `v2`).
  AAB không dùng APK Signature Scheme theo cùng cách và chưa được tool v0.1 hỗ trợ.

### 7.2 Package / version / SDK

- Tool: `aapt2 dump badging <apk>` (1 lần, parse được nhiều)
- Trích ra:
  - `package` (applicationId)
  - `versionCode`, `versionName`
  - `platformBuildVersionName`, `platformBuildVersionCode` (compileSdk)
  - `minSdkVersion`, `targetSdkVersion`, `compileSdkVersion`
- `versionCode_min` cho phép `actual >= expected` (release mới có thể lớn hơn); dùng `versionCode_eq` khi muốn strict.

### 7.3 `<meta-data>` — toàn bộ `<application><meta-data android:name="..." android:value="..."/>` của merged manifest

- Tool: `aapt2 dump xmltree <apk> --file AndroidManifest.xml` → parse thành map.
- Mỗi key dùng dot path ký hiệu: `com.google.android.gms.games.APP_ID`.
- Resources dạng `@0x7f0b000f` được giữ nguyên dưới dạng compiled reference. Nếu
  resource ID không ổn định và không critical, user nên xóa entry khỏi baseline.
- Compare từng key theo `expected_meta_data`.

### 7.4 Components (activity / service / provider / receiver)

- Parse tất cả `<activity>`, `<service>`, `<provider>`, `<receiver>` kèm `<intent-filter>` nếu có.
- Trích ra `name` (FQCN) và với `<provider>`: `authorities`.
- Matching semantics cho `expected_components_present`:
  - Với **activity / service / receiver**: substring match against `<android:name>` (FQCN). Ví dụ entry `"com.google.android.gms.games.provider.PlayGamesInitProvider"` khớp với **mọi** component có FQCN chứa chuỗi đó. Cho phép kèm class cha thay vì class con.
  - Với **provider**: vì FQCN của provider thường giống nhau giữa các bản build, tool sẽ match theo **authorities** (substring). Ví dụ entry `"dcwc.playgamesinitprovider"` khớp nếu có provider có authority chứa chuỗi đó.
  - Nếu một string match cả class name **và** authority thì vẫn là `[OK]` (1 check pass, không double-count).

### 7.5 Permissions

- Tool: `aapt2 dump badging` (đã có) → grep `uses-permission:`
- Set compare: present phải include hết; absent phải rỗng.
- Lưu ý permissions auto-injected (vd `*.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`) KHÔNG nên list trong expected (sẽ khóc thét mỗi AGP version). User có thể bỏ qua bằng cách không list trong present/absent.

### 7.6 ABI

- Tool: `unzip -l <apk> | grep 'lib/' | awk -F/ '{print $2}' | sort -u`
- `must_include`: từng ABI phải có
- `must_exclude`: APK không được chứa `.so` của ABI đó
- Note: `arm64-v8a` gần như BẮT BUỘC cho Play (2024+); `armeabi-v7a` legacy (32-bit); `x86_64` (Chromebook); nên cấm `mips`/`mips64`/`x86` (32-bit intel).

### 7.7 Application attributes

- Parser hiện trích `debuggable`, `extractNativeLibs`, `usesCleartextTraffic` và
  `isGame` từ `<application>`.
- `expected_attributes` nhận key ngắn (`debuggable`) hoặc alias XPath-like
  (`application/@android:debuggable`). Boolean JSON `false` được giữ đúng, không
  bị hiểu thành field thiếu.
- Mismatch attribute là `[FAIL]`, gồm trường hợp release expected
  `debuggable=false` nhưng APK actual là `true`.
- `_flavors.<name>.expected_attributes` chỉ override khi user truyền đúng
  `--flavor <name>`; không có implicit `default` flavor.

---

## 8. Critical risk: GPGS plugin upgrade reset manifest

Đây là bug gốc của user. Cách detect chính xác:

1. So `com.google.android.gms.games.APP_ID` trong APK thật vs expected.
   - Nếu APK chứa `99009804916` (12 số bắt đầu `99`) → placeholder chắc chắn.
   - Nếu 18-19 số, không phải all-same-prefix → ID thật.
2. So `PlayGamesInitProvider`'s `authorities` attribute: nếu chứa `com.google.example.games.mainlibproj` thay vì `com.wb.goog.dc.dcwc.playgamesinitprovider` → plugin manifest chưa được wire đúng.
3. So `com.google.android.gms.games.unityVersion` vs plugin version installed (`Assets/GooglePlayGames/com.google.play.games/package.json` → `version` field).

Cả 3 đều là `[FAIL]` rõ ràng trong tool. Message có gợi ý cách fix:

```
[FAIL]  meta-data com.google.android.gms.games.APP_ID
        expected: "299009804916"
        actual:   "99009804916"
        → Looks like plugin reset to placeholder value.
          Re-run Play Games plugin Setup (Window → Google Play Games → Setup)
          and rebuild. See docs/android-precheck-design.md §8.
```

---

## 9. Environment & dependencies

### 9.1 Required on machine

| Tool | Source | Tại sao |
|---|---|---|
| `bash` ≥ 3.2 (macOS) hoặc ≥ 4 (Linux) | Hệ thống | Tool runtime |
| `unzip` | Hệ thống | Bung APK |
| `awk`, `grep`, `sed` | Hệ thống | Parse text |
| `jq` ≥ 1.6 | `brew install jq` / apt | JSON parse chuẩn |
| `aapt2` | Android SDK build-tools ≥ 30 | Manifest dump |
| `apksigner` | Android SDK build-tools ≥ 30 | Cert verify |

### 9.2 Auto-detect Android SDK

`env.sh` tìm theo thứ tự:
1. `$ANDROID_HOME` / `$ANDROID_SDK_ROOT`
2. `$HOME/Library/Android/sdk` (mac)
3. `$HOME/Android/Sdk` (Linux)
4. `$HOME/Android/Sdk` (Windows, nếu user dùng WSL)

Nếu thấy nhiều version build-tools, lấy version mới nhất (lexicographic).

Nếu vẫn không thấy → fail `[FAIL] env: aapt2 not found`. Message:

```
[FAIL] env: aapt2 / apksigner not found
        Set ANDROID_HOME or ANDROID_SDK_ROOT, or install Android SDK
        build-tools (Android Studio → SDK Manager → SDK Tools tab).
```

### 9.3 Không yêu cầu Python, Java, Node, hay bundletool

Pure shell. Dễ onboard.

---

## 10. Error handling

| Tình huống | Hành vi |
|---|---|
| `keys.json` không tồn tại | Mode `--check`: prompt lỗi và exit 2 |
| `keys.json` invalid JSON | `[FAIL] keys.json parse error: <jq error>` exit 2 |
| APK path không tồn tại | `[FAIL] file not found: <path>` exit 2 |
| File không phải APK | `[FAIL] not a zip file: <path>` exit 2 (check `file(1)` ext) |
| aapt2/apksigner thiếu | `[FAIL] env: ...` exit 3 |
| Bundletool not installed (AAB run) | N/A MVP-1 |
| Manifest parse lỗi (APK corrupt) | `[FAIL] manifest parse failed: <aapt2 stderr>` exit 2 |
| Component check timeout (>10s/app)? | Không expected trên APK thật; không xử lý |
| File APK chỉ-đọc / permission denied | `[FAIL] permission denied: <path>` exit 2 |
| Output `--harvest` không ghi được | exit 5 |

Mỗi error class có exit code cố định để script/CI lời dùng.

---

## 11. Testing strategy

### 11.1 Smoke test (`tests/smoke.sh`)

```bash
# Lấy APK gốc (user cung cấp), harvest, rồi check vừa thu hoạch → expect 0 fail
$ bash tests/smoke.sh
[1/3] android-precheck --self-check
[2/3] android-precheck --harvest tests/fixtures/DGame_debug_1.1.14.1.apk \
        -o /tmp/keys.harvested.json
[3/3] android-precheck tests/fixtures/DGame_debug_1.1.14.1.apk \
        -e /tmp/keys.harvested.json
exit 0 expected, got 0 ✓
```

### 11.2 Negative tests (built-in có sẵn)

Không có mock-APK generator trong MVP-1 (xem ghi chú ngay dưới). Negative testing chỉ làm manual qua smoke test §11.3.

**MVP-1 không có mock-APK generator.** Negative testing được làm thủ công bằng cách sửa `keys.json` (đổi 1 char trong SHA-256, xóa `APP_ID`, …) rồi re-run; chi tiết ở §11.3.

### 11.3 Manual test trên APK thật của user

- Chạy harvest trên APK vừa build → kiểm file `keys.harvested.json` đủ các field.
- Sửa 1 char trong `expected_signing.sha256` → re-run → expect `[FAIL]` đúng message.
- Xóa `expected_signing.sha256` → re-run → expect `[SKIP] not configured` (default) hoặc `[FAIL] CRITICAL` (--strict).
- Tạo APK thật nhưng upgrade plugin sai → expect `[FAIL] APP_ID` đúng message tham chiếu §8.

---

## 12. Open questions / future work

1. **AAB support** — sẽ thêm v2: dùng `bundletool dump manifest` + `bundletool validate`. Build độc lập với APK.
2. **CI integration** — wrapper `--json` mode → GitHub Action / Jenkins step. Không trong MVP-1.
3. **Diff mode giữa 2 APK** — `check.sh apk_old.apk --against apk_new.apk` để xem khác biệt manifest trước khi upgrade plugin.
4. **Multi-flavor baseline** — nếu sau này game có thêm variant, support `--flavor overseas|domestic|dev` switching keys qua `_flavors.*` mapping.
5. **Auto-fix / patch** — `--fix-signed` để re-sign APK nếu cert sai (cẩn thận, không MVP-1).
6. **Export `--report-md`** — render output ra GitHub-flavored markdown để paste vào PR comment.
7. **Telemetry / local history** — lưu lại `actual.json` mỗi lần run vào `.precheck-history/` để debug regression.

---

## 13. Acceptance criteria

Design này "xong" khi tất cả dưới đây verify được:

- [x] `bash android-precheck/check.sh --self-check` → exit 0 nếu Android SDK + jq có; exit 3 + message rõ ràng nếu thiếu.
- [x] `bash android-precheck/check.sh <apk>` với `keys.json` đầy đủ → in summary, exit 0 nếu APK đúng expected, exit 1 nếu sai.
- [x] `bash android-precheck/check.sh <apk> --strict` thiếu `expected_signing.sha256` → `[FAIL] CRITICAL: signing.sha256 missing` + exit 4.
- [x] `bash android-precheck/check.sh --harvest <apk>` → in ra JSON chuẩn đủ các field quan trọng, exit 0.
- [x] Xóa hết `keys.json` chỉ giữ `expected_signing.sha256` + `expected_meta_data[APP_ID]` → 2 check chạy, các field khác `[SKIP]`, exit 0 nếu khớp.
- [x] Sửa 1 char trong SHA-256 → `[FAIL] signing.sha256` đúng message + exit 1.
- [x] APK có APP_ID placeholder/reset → `[FAIL] meta-data[gms.games.APP_ID]` với message gợi ý fix (§8).
- [x] `bash tests/smoke.sh` → exit 0.
- [x] README có quickstart ≤ 5 phút cho dev mới.

---

## 14. Migration / rollout

1. Viết tool + tests (1-2 buổi theo plan riêng).
2. Commit trong repo game.
3. Chạy harvest trên APK debug hiện có (`DGame_debug_1.1.14.1.apk`) → lưu `android-precheck/keys.example.json`.
4. Khi có release build, harvest APK đó → tạo `keys.json` đầy đủ (signing cert khác nếu dùng release keystore khác debug — dù user nói chỉ 1 keystore).
5. Tích hợp vào Unity build pipeline: post-process script `Editor/postbuild.sh` gọi `check.sh` sau `BuildPipeline.BuildPlayer` (optional, không bắt buộc MVP-1).
6. Khi upgrade plugin: luôn chạy `check.sh --strict` trước khi commit manifest mới.

# android-precheck

Bash CLI kiểm tra APK **sau khi Unity build xong** và trước khi submit Google Play.
Tool đọc dữ liệu thật trong APK đã merge/compile, rồi so sánh với `keys.json` để
bắt các regression im lặng như:

- Google Play Games `APP_ID` bị plugin reset
- Build dùng sai keystore / certificate SHA-256
- APK có chữ ký không hợp lệ hoặc thiếu signature scheme yêu cầu
- Sai AdMob App ID hoặc Google Play Billing version
- Thiếu component/service/provider hoặc sai Play Games provider authority
- Package, SDK, permission, ABI hoặc application attribute bị đổi

> **Giới hạn v0.1:** chỉ hỗ trợ APK. File `.aab` bị từ chối rõ ràng; AAB support
> bằng `bundletool` được để dành cho v2.

## Quickstart

### 1. Requirements

- macOS hoặc Linux
- Bash 3.2+
- `jq` 1.6+
- `unzip`
- Android SDK build-tools 34+ có `aapt2` và `apksigner`

Nếu SDK không ở vị trí mặc định:

```bash
export ANDROID_HOME="$HOME/Library/Android/sdk"
```

### 2. Self-check

```bash
bash check.sh --self-check
```

Kết quả đúng:

```text
[OK]    Android SDK + jq + unzip available
```

### 3. Check APK với baseline đã tạo sẵn

`keys.json` hiện đã được tạo từ APK chuẩn của bạn và được `.gitignore` vì đây là
file cấu hình local:

```bash
bash check.sh "/path/to/new-build.apk" --strict
```

Hoặc chỉ định baseline tracked:

```bash
bash check.sh "/path/to/new-build.apk" \
  --expected tests/fixtures/keys.example.json \
  --strict
```

Baseline đầy đủ hiện chạy **175 checks** trên APK chuẩn.

### 4. Harvest lại từ một APK known-good

```bash
bash check.sh --harvest "/path/to/known-good.apk" -o keys.json
```

Harvest chỉ thành công khi APK có manifest hợp lệ và `apksigner` xác nhận chữ ký
hợp lệ. File sinh ra bao gồm package, version, SDK, signing, meta-data,
permissions, components, provider authorities, ABIs và application attributes.

## Baseline chuẩn hiện tại

Nguồn: `/Users/hoangnguyen/Downloads/DGame_debug_1.1.14.1(1).apk`

Các giá trị release-critical đã xác nhận:

| Check | Expected |
|---|---|
| Package | `com.wb.goog.dc.dcwc` |
| Keystore cert SHA-256 | `b46acd3981297ed08d84531a9de00543510ef1413a6ae667b9bf487cf23293c4` |
| GPGS `APP_ID` | `299009804916` |
| GPGS Unity plugin version | `2.0.0` |
| Play Games provider | `com.google.android.gms.games.provider.PlayGamesInitProvider` |
| Play Games authority | `com.wb.goog.dc.dcwc.playgamesinitprovider` |
| AdMob App ID | `ca-app-pub-5689963351750691~9138731913` |
| Billing client | `7.1.1` |
| Signature | verified, scheme `v2` |
| SDK | min `25`, target `35`, compile `35` |
| ABI | `arm64-v8a`, `armeabi-v7a`, `x86_64` |

**Quan trọng:** APK nguồn có tên `debug` và manifest thật chứa
`debuggable=true`, `usesCleartextTraffic=true`. Baseline giữ đúng dữ liệu APK mẫu.
Nếu APK submit Store là release, hãy đổi policy tương ứng trong `keys.json`, ví dụ:

```json
{
  "expected_attributes": {
    "debuggable": "false"
  }
}
```

Không copy riêng object trên đè toàn bộ file; chỉ sửa entry tương ứng trong
`expected_attributes`.

## Có thể xóa field trong `keys.json` không?

**Có.** Mọi field đều optional; xóa field nghĩa là tool ngừng enforce field đó.
Ví dụ bạn có thể xóa toàn bộ `expected_version` nếu không muốn version mới làm
check fail.

Riêng khi dùng `--strict`, hai key sau bắt buộc phải tồn tại:

1. `expected_signing.sha256`
2. `expected_meta_data["com.google.android.gms.games.APP_ID"]`

Nếu thiếu, tool exit `4` trước khi tiếp tục. Không dùng `--strict` thì tool phát
`WARN` để nhắc cấu hình hai key này.

Baseline tối thiểu chỉ check keystore + GPGS APP_ID:

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

## Checklist khuyến nghị trước khi submit

| Priority | JSON key | Mục đích |
|---|---|---|
| Bắt buộc | `expected_signing.sha256` | Bắt sai keystore/upload certificate |
| Bắt buộc | `expected_meta_data[APP_ID]` | Bắt bug plugin GPGS reset APP_ID |
| Cao | `expected_signing.verified` | APK phải verify chữ ký thành công |
| Cao | `expected_signing.must_use_signature_scheme` | Enforce `v2`/scheme release mong muốn |
| Cao | `expected_package` | Bắt nhầm applicationId/game |
| Cao | `expected_attributes.debuggable` | Release không được để debug |
| Cao | `expected_meta_data[ads.APPLICATION_ID]` | Bắt nhầm AdMob dev/prod app |
| Cao | `expected_meta_data[billingclient.version]` | Bắt plugin Billing downgrade/drift |
| Cao | `expected_components_present` | Bắt thiếu Play Games/Firebase/Billing component |
| Cao | Play Games provider authority entry | Bắt manifest placeholder merge sai |
| Cao | `expected_abi.must_include` | Ít nhất giữ `arm64-v8a` |
| Cao | `expected_permissions_absent` | Cấm permission nhạy cảm ngoài ý muốn |
| Vừa | `expected_sdk` | Bắt target/compile/min SDK bị đổi |
| Vừa | `expected_permissions_present` | Bắt permission bắt buộc bị mất |
| Tùy chọn | `expected_version` | Xóa nếu version thay đổi mỗi build |
| Tùy chọn | Meta-data/resource ID ít quan trọng | Xóa để giảm false positive |

Baseline curated đang cấm các permission sau:

- `android.permission.QUERY_ALL_PACKAGES`
- `android.permission.SYSTEM_ALERT_WINDOW`
- `android.permission.READ_PHONE_STATE`
- `android.permission.REQUEST_INSTALL_PACKAGES`
- `android.permission.MANAGE_EXTERNAL_STORAGE`

Và cấm ABI legacy: `mips`, `mips64`, `x86`.

## `keys.json` fields

```json
{
  "expected_package": "com.example.game",
  "expected_version": {
    "versionName": "1.2.3",
    "versionCode_min": 1,
    "versionCode_max": 999999,
    "versionCode_eq": 123
  },
  "expected_sdk": {
    "minSdk": 25,
    "targetSdk": 35,
    "compileSdk": 35
  },
  "expected_signing": {
    "sha256": "...",
    "sha1": "...",
    "md5": "...",
    "subjectDN": "...",
    "subject_dn_contains": ["WB Games", "Team Leads"],
    "verified": true,
    "must_use_signature_scheme": ["v2"]
  },
  "expected_meta_data": {
    "com.google.android.gms.games.APP_ID": "299009804916"
  },
  "expected_components_present": [
    "com.google.android.gms.games.provider.PlayGamesInitProvider",
    "com.example.game.playgamesinitprovider"
  ],
  "expected_permissions_present": ["android.permission.INTERNET"],
  "expected_permissions_absent": ["android.permission.QUERY_ALL_PACKAGES"],
  "expected_abi": {
    "must_include": ["arm64-v8a"],
    "must_exclude": ["mips", "mips64", "x86"]
  },
  "expected_attributes": {
    "debuggable": "false",
    "usesCleartextTraffic": "false"
  }
}
```

Attribute cũng chấp nhận alias dài như
`application/@android:debuggable`. Giá trị do `aapt2` parse được so sánh dưới
dạng text (`"true"`, `"false"`, resource reference, hoặc number string).

## Commands

| Command | Mục đích |
|---|---|
| `check.sh <apk>` | Check với `./keys.json` |
| `check.sh <apk> -e <path>` | Check với baseline chỉ định |
| `check.sh <apk> --strict` | Bắt buộc SHA-256 + APP_ID được cấu hình |
| `check.sh --harvest <apk>` | In baseline JSON ra stdout |
| `check.sh --harvest <apk> -o <path>` | Ghi baseline ra file |
| `check.sh <apk> --json` | Machine-readable report |
| `check.sh --self-check` | Kiểm tra dependency |
| `check.sh --no-color` | Tắt ANSI color |

JSON report chứa `tool`, `version`, `apk`, `expected`, `flavor`, `results`,
`summary` và `exit_code`.

## Exit codes

| Code | Ý nghĩa |
|---|---|
| `0` | Không có check fail; WARN/SKIP không làm fail |
| `1` | Ít nhất một check mismatch |
| `2` | Sai CLI, APK/manifest lỗi, JSON expected lỗi, hoặc AAB không hỗ trợ |
| `3` | Thiếu dependency |
| `4` | `--strict` thiếu SHA-256 hoặc GPGS APP_ID |
| `5` | Không ghi được output harvest |

## Troubleshooting

### GPGS APP_ID mismatch

Nếu actual quay về placeholder như `99009804916`, chạy lại:

```text
Unity → Window → Google Play Games → Setup
```

Sau đó rebuild và chạy precheck lại. Manifest plugin nguồn hiện tại và APK
compiled đều đã xác nhận APP_ID `299009804916`.

### Signing SHA-256 mismatch

Kiểm tra Unity Player Settings → Publishing Settings → Custom Keystore. SHA-256
của certificate phải trùng `keys.json` và certificate đã đăng ký trong Play
Console → Setup → App integrity.

### Provider authority mismatch

Expected hiện tại là `com.wb.goog.dc.dcwc.playgamesinitprovider`. Nếu actual còn
`com.google.example.games.mainlibproj`, manifest placeholder/applicationId merge
đã sai sau khi upgrade plugin.

### Resource reference thay đổi

Một số meta-data được compile thành `@0x...`; resource ID có thể đổi dù semantic
không đổi. Nếu field đó không release-critical, xóa riêng entry khỏi
`expected_meta_data` để tránh false positive.

## Tests

```bash
for test_file in tests/unit/test_*.sh; do
  bash "$test_file"
done

bash tests/smoke.sh
```

Smoke test dùng APK chuẩn tại
`/Users/hoangnguyen/Downloads/DGame_debug_1.1.14.1(1).apk`.

## Files

```text
android-precheck/
├── check.sh
├── keys.json                         # local baseline, gitignored
├── lib/
├── tests/
│   ├── fixtures/keys.example.json   # tracked full baseline
│   ├── unit/
│   └── smoke.sh
└── docs/
```

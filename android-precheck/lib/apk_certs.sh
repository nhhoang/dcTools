#!/usr/bin/env bash
# Parse `apksigner verify --verbose --print-certs <apk>` from stdin → JSON.
# Output:
#   {
#     "sha256": "<hex>",
#     "sha1":   "<hex>",
#     "md5":    "<hex>",
#     "subjectDN": "<CN=...,OU=...>",
#     "keyAlgo":  "RSA",
#     "keySize":  "2048",
#     "schemes":  ["v2","v3", ...],
#     "publicKeySha256": "<hex>",
#     "publicKeySha1":   "<hex>",
#     "publicKeyMd5":    "<hex>",
#     "verified": true|false
#   }

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

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
        return 2
    fi
    # Basic zip magic check (PK\x03\x04).
    local first2
    first2=$(head -c 2 "$file")
    if [ "$first2" != "PK" ]; then
        echo "apk_unpack: not a zip (missing PK magic): $file" >&2
        return 2
    fi
    local out
    out="$(mktemp -d -t "$(basename "$file" .apk)-XXXXXX")"
    if ! unzip -q "$file" -d "$out"; then
        echo "apk_unpack: unzip failed for $file" >&2
        rm -rf "$out"
        return 2
    fi
    echo "$out"
}

apk_unpack_cleanup() {
    local dir="$1"
    if [ -n "$dir" ] && [ -d "$dir" ]; then
        rm -rf "$dir"
    fi
}

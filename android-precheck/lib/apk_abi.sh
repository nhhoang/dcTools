#!/usr/bin/env bash
# Parse `unzip -l <apk>` filtered to lib/ → JSON.
# Output:
#   { "abis":      ["arm64-v8a", "armeabi-v7a", ...],   # distinct, sorted
#     "libraries": [{"abi": "arm64-v8a", "path": "lib/arm64-v8a/libfoo.so"}, ...] }

parse_abi_ls() {
    # Single awk pass: emit TSV rows "abi\tpath", then assemble via jq.
    local tsv
    tsv=$(awk '
        {
            path = $NF
            if (path ~ /^lib\//) {
                # path = "lib/<abi>/<rest>"
                n = split(path, parts, "/")
                abi = parts[2]
                print abi "\t" path
            }
        }')

    local libs_json abis_json
    if [ -z "$tsv" ]; then
        libs_json='[]'
        abis_json='[]'
    else
        libs_json=$(printf '%s\n' "$tsv" | jq -R -s '
            split("\n") | map(select(. != "")) |
            map(split("\t")) |
            map(select(length == 2)) |
            map({abi: .[0], path: .[1]})
        ')
        abis_json=$(printf '%s\n' "$tsv" | cut -f1 | sort -u | jq -R -s '
            split("\n") | map(select(. != "")) | .
        ')
    fi

    jq -n \
        --argjson abis "$abis_json" \
        --argjson libraries "$libs_json" \
        '{ abis: $abis, libraries: $libraries }'
}

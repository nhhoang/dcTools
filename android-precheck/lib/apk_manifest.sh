#!/usr/bin/env bash
# Parse `aapt2 dump xmltree --file AndroidManifest.xml` from stdin → JSON.

parse_manifest() {
    local records
    records=$(awk '
        function leading_spaces(line) {
            match(line, /[^ ]/)
            return RSTART > 0 ? RSTART - 1 : length(line)
        }

        function attribute_value(line, value) {
            value = line
            sub(/^[^=]*=/, "", value)
            if (substr(value, 1, 1) == "\"") {
                sub(/^\"/, "", value)
                sub(/\".*$/, "", value)
            } else {
                sub(/[[:space:]].*$/, "", value)
            }
            return value
        }

        function flush_meta() {
            if (meta_active && meta_name != "") {
                print "META\t" meta_name "\t" meta_value
            }
            meta_active = 0
            meta_indent = -1
            meta_name = ""
            meta_value = ""
        }

        function flush_component() {
            if (component_type != "" && component_name != "") {
                print "COMP\t" component_type "\t" component_name
                if (component_type == "provider" && component_authority != "") {
                    print "AUTH\t" component_name "\t" component_authority
                }
            }
            component_type = ""
            component_indent = -1
            component_name = ""
            component_authority = ""
        }

        BEGIN {
            application_indent = -1
            component_indent = -1
            meta_indent = -1
        }

        /^[[:space:]]*E: / {
            line_indent = leading_spaces($0)
            element = $0
            sub(/^[[:space:]]*E: /, "", element)
            sub(/[[:space:]].*$/, "", element)

            if (meta_active && line_indent <= meta_indent) {
                flush_meta()
            }
            if (component_type != "" && line_indent <= component_indent) {
                flush_component()
            }
            if (application_indent >= 0 && line_indent <= application_indent && element != "application") {
                application_indent = -1
            }

            if (element == "application") {
                application_indent = line_indent
            }
            if (element == "activity" || element == "service" ||
                element == "provider" || element == "receiver") {
                component_type = element
                component_indent = line_indent
                component_name = ""
                component_authority = ""
            }
            if (element == "meta-data") {
                meta_active = 1
                meta_indent = line_indent
                meta_name = ""
                meta_value = ""
            }
            next
        }

        /^[[:space:]]*A: / {
            line_indent = leading_spaces($0)

            if (meta_active && line_indent > meta_indent) {
                if ($0 ~ /:name\(/) {
                    meta_name = attribute_value($0)
                } else if ($0 ~ /:(value|resource)\(/) {
                    meta_value = attribute_value($0)
                }
            }

            if (component_type != "" && line_indent == component_indent + 2) {
                if ($0 ~ /:name\(/ && component_name == "") {
                    component_name = attribute_value($0)
                } else if (component_type == "provider" && $0 ~ /:authorities\(/) {
                    component_authority = attribute_value($0)
                }
            }

            if (application_indent >= 0 && line_indent == application_indent + 2) {
                if ($0 ~ /:debuggable\(/) {
                    print "ATTR\tdebuggable\t" attribute_value($0)
                } else if ($0 ~ /:extractNativeLibs\(/) {
                    print "ATTR\textractNativeLibs\t" attribute_value($0)
                } else if ($0 ~ /:usesCleartextTraffic\(/) {
                    print "ATTR\tusesCleartextTraffic\t" attribute_value($0)
                } else if ($0 ~ /:isGame\(/) {
                    print "ATTR\tisGame\t" attribute_value($0)
                }
            }
        }

        END {
            flush_meta()
            flush_component()
        }
    ')

    printf '%s\n' "$records" | jq -R -s '
        split("\n")
        | map(select(. != "") | split("\t")) as $rows
        | {
            metaData: reduce ($rows[] | select(.[0] == "META" and length >= 3)) as $row
                ({}; .[$row[1]] = $row[2]),
            activities: [$rows[] | select(.[0] == "COMP" and .[1] == "activity") | .[2]],
            services: [$rows[] | select(.[0] == "COMP" and .[1] == "service") | .[2]],
            providers: [$rows[] | select(.[0] == "COMP" and .[1] == "provider") | .[2]],
            receivers: [$rows[] | select(.[0] == "COMP" and .[1] == "receiver") | .[2]],
            providerAuthorities: reduce ($rows[] | select(.[0] == "AUTH" and length >= 3)) as $row
                ({}; .[$row[1]] = $row[2]),
            applicationAttrs: reduce ($rows[] | select(.[0] == "ATTR" and length >= 3)) as $row
                ({}; .[$row[1]] = $row[2])
        }
    '
}

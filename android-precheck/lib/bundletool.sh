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
        echo "${BUNDLETOOL_JAR}"
        return 0
    fi
    for candidate in \
        "${ANDROID_HOME:-}/bundletool/bundletool.jar" \
        "${ANDROID_SDK_ROOT:-}/bundletool/bundletool.jar" \
        "${HOME:-}/Library/Android/sdk/bundletool/bundletool.jar" \
        "${HOME:-}/Android/Sdk/bundletool/bundletool.jar"; do
        if [ -n "$candidate" ] && [ -f "$candidate" ] && [ -r "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    echo ""
    return 0
}

find_java() {
    if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
        echo "${JAVA_HOME}/bin/java"
        return 0
    fi
    command -v java 2>/dev/null || echo ""
}

bundletool_cmd() {
    # Echo "java -jar <jar>" (no trailing args). Caller appends subcommand + flags.
    local jar
    jar="$(find_bundletool)"
    [ -n "$jar" ] || { echo "bundletool_cmd: bundletool.jar not found" >&2; return 3; }
    local java
    java="$(find_java)"
    [ -n "$java" ] || { echo "bundletool_cmd: java not found" >&2; return 3; }
    printf "%s -jar %s" "$java" "$jar"
}

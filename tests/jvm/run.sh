#!/usr/bin/env bash
# JVM regression tests for the plugin.ironSource event dispatch path.
#
# Self-contained: compiles the real plugin source
# (android/src/main/java/plugin/ironSource/LuaLoader.java) together with the minimal
# SDK/Corona/JNLua stand-ins in tests/jvm/stubs and runs the test suite. No Android SDK,
# no Gradle, no network access required.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/../.." && pwd)"

if ! command -v javac >/dev/null 2>&1; then
    echo "javac not found: install a JDK (17 is what CI uses)" >&2
    exit 1
fi

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT

find "$here/stubs" "$here/test" "$repo/android/src/main/java/plugin/ironSource" \
    -name '*.java' | sort > "$out/sources.txt"

javac -Xlint:-unchecked -d "$out/classes" @"$out/sources.txt"
java -cp "$out/classes" plugin.ironSource.LuaLoaderDispatchTest

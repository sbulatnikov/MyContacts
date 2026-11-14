#!/bin/sh
# Тесты MyContacts: обычная сборка (без отладки) и отладочная
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
TMP=${TMPDIR:-/tmp}/mc-test
rm -rf "$TMP"; mkdir -p "$TMP/release" "$TMP/debug"
python3 "$HERE/../../tools/strip_debug.py" "$HERE/lua" "$TMP/release"
ALLODS_DEBUG=1 python3 "$HERE/../../tools/strip_debug.py" "$HERE/lua" "$TMP/debug"
rm "$TMP/release/Probe.lua"
echo "== обычная сборка"; texlua "$HERE/test/run.lua" "$HERE" "$TMP/release" | grep -E "FAIL|ВСЁ|ИТОГ|ошиб" | tail -5
echo "== отладочная сборка"; texlua "$HERE/test/run.lua" "$HERE" "$TMP/debug" | grep -E "FAIL|ВСЁ|ИТОГ|ошиб" | tail -5

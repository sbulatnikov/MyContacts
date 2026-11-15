#!/bin/sh
# Тесты MyContacts на заглушках API игры: обычная сборка (без отладки) и отладочная
#   sh test/run.sh
# Нужны Python 3 и texlua, lua5.3 или luajit (LUA=<путь> — указать свой интерпретатор).
set -e
HERE=$(cd "$(dirname "$0")/.." && pwd)
TMP=${TMPDIR:-/tmp}/mc-test
PY=${PYTHON:-}
if [ -z "$PY" ]; then
	for c in python3 python; do
		if "$c" -c "import sys; sys.exit(sys.version_info[0] != 3)" 2>/dev/null; then PY=$c; break; fi
	done
fi
[ -n "$PY" ] || { echo "не найден Python 3 (можно указать PYTHON=<путь>)"; exit 1; }
if [ -z "$LUA" ]; then
	for c in texlua lua5.3 luajit lua; do
		if command -v "$c" >/dev/null 2>&1; then LUA=$c; break; fi
	done
fi
[ -n "$LUA" ] || { echo "не найден texlua, lua5.3 или luajit (можно указать LUA=<путь>)"; exit 1; }

rm -rf "$TMP"; mkdir -p "$TMP/release" "$TMP/debug"
"$PY" "$HERE/tools/strip_debug.py" "$HERE/lua" "$TMP/release"
ALLODS_DEBUG=1 "$PY" "$HERE/tools/strip_debug.py" "$HERE/lua" "$TMP/debug"
rm "$TMP/release/Probe.lua"   # отладочный модуль в обычную сборку не входит

# Прогон одной сборки: при ошибке показываем конец журнала и выходим с ошибкой
run() {
	echo "== $1"
	"$LUA" "$HERE/test/run.lua" "$HERE" "$2" > "$TMP/test.log" 2>&1 || { grep "FAIL" "$TMP/test.log"; tail -5 "$TMP/test.log"; exit 1; }
	grep -E "FAIL|ВСЁ|ОШИБОК" "$TMP/test.log" | tail -5
}
run "обычная сборка" "$TMP/release"
run "отладочная сборка" "$TMP/debug"

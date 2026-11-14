MyContacts — исходники сборки
=============================
lua/       скрипты аддона в UTF-8 (при сборке переводятся в Windows-1251; LibDnD уже в cp1251)
gen/       генератор: build.py (виджеты, тексты, текстуры DXT5), assemble.py (папка аддона целиком), tex.py/xdb.py — как в BestAutoAccept
test/      заглушки API и прогон логики: texlua test/run.lua .
tools/     render.py — грубый предпросмотр окна по xdb

Сборка (Python 3 + numpy + Pillow + rsvg-convert):
  python3 gen/assemble.py [папка_вывода]   -> по умолчанию out/MyContacts

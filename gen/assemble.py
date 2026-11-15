"""Собирает папку аддона MyContacts: ресурсы (build.py), скрипты в cp1251, AddonDesc, проверка ссылок.

  python3 gen/assemble.py [папка аддона]     по умолчанию out/MyContacts
Рядом с папкой аддона не появляется ничего; PNG текстур для предпросмотра — в out/preview.
"""
import os, re, subprocess, sys, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.join(ROOT, 'out', 'MyContacts')
sys.path.insert(0, os.path.join(ROOT, 'tools'))  # своя копия: репозиторий собирается сам по себе
import strip_debug  # noqa: E402  — отладка только в сборке с ALLODS_DEBUG=1

VERSION = re.search(r'MC\.VERSION = "([^"]+)"', open(os.path.join(ROOT, 'lua', 'Util.lua'), encoding='utf-8').read()).group(1)
SCRIPTS = ['LibDnD', 'Util', 'Config', 'DB'] + (['Probe'] if strip_debug.DEBUG else []) + ['Game', 'UI', 'Main']

shutil.rmtree(OUT, ignore_errors=True)
subprocess.check_call([sys.executable, os.path.join(HERE, 'build.py'), OUT, os.path.join(ROOT, 'out', 'preview')])

sd = os.path.join(OUT, 'Scripts')
os.makedirs(sd, exist_ok=True)
for s in SCRIPTS:
    raw = open(os.path.join(ROOT, 'lua', s + '.lua'), 'rb').read()
    data = raw if s == 'LibDnD' else strip_debug.strip(raw.decode('utf-8'), where=s + '.lua').encode('cp1251')
    open(os.path.join(sd, s + '.lua'), 'wb').write(data)

desc = '''<?xml version="1.0" encoding="UTF-8" ?>
<UIAddon>
	<Name>MyContacts</Name>
	<AutoStart>true</AutoStart>
	<userAddonInfo>
		<name href="Texts/AddonName.txt" />
		<description href="Texts/AddonDescription.txt" />
		<author>NoMercy</author>
		<version>%s</version>
	</userAddonInfo>
	<ScriptFileRefs>
%s	</ScriptFileRefs>
	<Form href="Widgets/MainForm.(WidgetForm).xdb" />
	<texturesGroups>
		<Item>
			<groupName>Icons</groupName>
			<textures href="Widgets/Textures/Icons.(UIRelatedTextures).xdb" />
		</Item>
	</texturesGroups>
</UIAddon>
''' % (VERSION, ''.join('\t\t<Item href="Scripts/%s.lua" />\n' % s for s in SCRIPTS))
open(os.path.join(OUT, 'AddonDesc.(UIAddon).xdb'), 'w', encoding='utf-8').write(desc)
# имя аддона в игре — всегда с версией: «MyContacts v<версия>»
open(os.path.join(OUT, 'Texts', 'AddonName.txt'), 'wb').write(b'\xff\xfe' + ('MyContacts v' + VERSION).encode('utf-16-le'))

bad = 0
for root, _, files in os.walk(OUT):
    for f in files:
        if not f.endswith('.xdb'):
            continue
        p = os.path.join(root, f)
        for href in re.findall(r'href="([^"#]+)', open(p, encoding='utf-8').read()):
            if href and not os.path.exists(os.path.normpath(os.path.join(root, href))):
                print('BROKEN', os.path.relpath(p, OUT), '->', href)
                bad += 1
seen = set()
def walk(path):
    if path in seen:
        return
    seen.add(path)
    for href in re.findall(r'href="([^"#]+\.xdb)"', open(path, encoding='utf-8').read()):
        q = os.path.normpath(os.path.join(os.path.dirname(path), href))
        if os.path.exists(q):
            walk(q)
walk(os.path.join(OUT, 'AddonDesc.(UIAddon).xdb'))
orphans = [f for f in os.listdir(os.path.join(OUT, 'Widgets')) if f.endswith('.xdb') and os.path.join(OUT, 'Widgets', f) not in seen]
print('broken refs:', bad, '| orphan widgets:', orphans)
print('files:', sum(len(fs) for _, _, fs in os.walk(OUT)))

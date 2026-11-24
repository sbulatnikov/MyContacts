"""Сборка ресурсов MyContacts: виджеты, тексты, текстуры.

Координаты — в пикселях игры (масштаб 1, макет 440×600 и 600×600).
Генератор устроен как у BestAutoAccept (xdb.py, tex.py — общие).
"""
import os, sys, shutil
import numpy as np
from PIL import Image
sys.path.insert(0, os.path.dirname(__file__))
import tex as T
import xdb as X
from xdb import placement as PL, fmt

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(_ROOT, 'assets')
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(_ROOT, 'out', 'MyContacts')
PREV = sys.argv[2] if len(sys.argv) > 2 else os.path.join(_ROOT, 'out', 'preview')
for d in ('Widgets', 'Texts'):
    shutil.rmtree(os.path.join(OUT, d), ignore_errors=True)
shutil.rmtree(PREV, ignore_errors=True)
X.setup(OUT, PREV)

# ------------------------------------------------------------------ палитра (дизайн-система MyContacts)
ACC = '#BB1ABD'; ACC_B = '#D045D2'; ACC_I = '#E58BE7'; ACC_T = '#F2B8F3'
ACC_SEL = '#3A1440'; ACC_TINT = '#2C1230'; ACC_RING = '#6A2A6E'; ACC_PR = '#941496'
BG_WIN = '#17141B'; BG_HDR = '#1D1922'; BG_HOVER = '#1F1A24'; BG_CTL = '#221D27'; BG_IN = '#100E13'; BG_TIP = '#0F0D12'
BR_WIN = '#3A2F42'; BR_CTL = '#3A3141'; BR_STR = '#4A3B52'; LINE = '#2A2330'
GOLD = '#D9BE7A'; TXT = '#ECE6EF'; TXT2 = '#BDB4C4'; TXT3 = '#8C8393'; TXT_PH = '#6E6575'; TXT_OFF = '#5E5664'
AMBER = '#F5B841'
M_NEU = '#A3ABBD'; M_NEU_T = '#24232B'
M_POS = '#3DC2B0'; M_POS_T = '#10302C'
M_NEG = '#F46A66'; M_NEG_T = '#3A1719'
DANGER = '#C23B3B'; DANGER_B = '#E05452'; DSOFT_BG = '#2A1517'; DSOFT_BR = '#B4403F'
F_LEAGUE = '#4C8DF0'; F_EMPIRE = '#CC2E2E'
TOGGLE_OFF = '#241F28'

F_TITLE = ('AllodsFantasy', 18)
F_NICK = ('AllodsFantasy', 20)
F_SECT = ('AllodsFantasy', 16)
F_BODY = ('AllodsSystem', 16)
F_SMALL = ('AllodsSystem', 14)

# ------------------------------------------------------------------ текстуры


def box(w, h, r, fill=None, border=None, bw=1.2):
    return T.rrect(T.blank(w, h), 0, 0, w, h, r, fill=fill, border=border, bw=bw)


def fr(name, fill, border=None, size=32, r=6, e=None, bw=1.2):
    return X.frame(name, box(size, size, r, fill, border, bw), e or (r + 3))


def solid(name, color, alpha=1.0):
    img = T.blank(4, 4)
    img[...] = T.hex2rgba(color, alpha)
    return X.stretch(name, img)


TRANSP = X.stretch('Transparent', T.blank(4, 4))
LINE_TEX = solid('Line', LINE)
CURSOR = solid('Cursor', ACC_I)
SELECTION = solid('Selection', ACC, 0.45)
SCRIM = solid('Scrim', '#0A080C', 0.62)

WIN_FRAME = fr('WindowFrame', BG_WIN, BR_WIN, 64, 10, 14)
HDR_FRAME = X.frame('HeaderBack', T.rrect(T.blank(64, 64), 1.2, 1.2, 62.8, 64, (9, 9, 0, 0), fill=BG_HDR), 12)
ACCENT_MARK = X.stretch('AccentMark', box(16, 16, 4, ACC))
TIP_FRAME = fr('TipFrame', BG_TIP, BR_STR)
TIP_WARN = fr('TipWarn', BG_TIP, AMBER)
COUNT_CHIP = fr('CountChip', ACC_TINT, ACC_RING, 32, 9, 10)
FIELD = fr('FieldFrame', BG_IN, BR_CTL)
FIELD_FOCUS = fr('FieldFrameFocus', BG_IN, ACC_I)
FIELD_ERR = fr('FieldFrameErr', BG_IN, AMBER)
LIST_FRAME = fr('ListFrame', BG_IN, LINE, 32, 6)
NOTE_FRAME = fr('NoteFrame', BG_HDR, LINE, 32, 6)
NOTE_HOVER = fr('NoteFrameHover', BG_HOVER, BR_CTL, 32, 6)

# кнопки
BTN = {
    'sec': fr('BtnSec', BG_CTL, BR_CTL), 'secH': fr('BtnSecHover', '#2A2430', BR_STR), 'secP': fr('BtnSecPressed', '#1A161E', BR_STR),
    'secD': fr('BtnSecDisabled', '#19161C', LINE),
    'pri': fr('BtnPri', ACC, ACC_B), 'priH': fr('BtnPriHover', '#CC3ACE', '#E070E2'), 'priP': fr('BtnPriPressed', ACC_PR, ACC_B),
    'priD': fr('BtnPriDisabled', '#2A2030', BR_CTL),
    'dng': fr('BtnDanger', DANGER, DANGER_B), 'dngH': fr('BtnDangerHover', '#D14848', '#F06A68'), 'dngP': fr('BtnDangerPressed', '#A83030', DANGER_B),
    'dsoft': fr('BtnDangerSoft', DSOFT_BG, DSOFT_BR), 'dsoftH': fr('BtnDangerSoftHover', '#361A1D', DANGER_B),
    'icon': TRANSP, 'iconH': fr('IconBtnHover', BG_HOVER, BR_CTL), 'iconP': fr('IconBtnPressed', '#1A161E', BR_STR),
    'iconOn': fr('IconBtnOn', ACC_TINT, ACC_RING), 'iconOnH': fr('IconBtnOnHover', '#38163D', ACC),
}
# чипы фильтров (выкл / вкл); у отметок своя рамка во включённом состоянии
CHIP_OFF = fr('ChipOff', BG_CTL, BR_CTL)
CHIP_OFF_H = fr('ChipOffHover', '#2A2430', BR_STR)
CHIP_ON = {'acc': fr('ChipOnAcc', ACC_SEL, ACC), 'neu': fr('ChipOnNeu', M_NEU_T, M_NEU), 'pos': fr('ChipOnPos', M_POS_T, M_POS),
           'neg': fr('ChipOnNeg', M_NEG_T, M_NEG)}
CHIP_ON_H = {'acc': fr('ChipOnAccHover', '#46184D', ACC_B), 'neu': fr('ChipOnNeuHover', '#2C2B34', '#C0C7D6'),
             'pos': fr('ChipOnPosHover', '#143A35', '#5AD6C5'), 'neg': fr('ChipOnNegHover', '#451C1E', '#FF8A86')}
# строки списка: без наведения
ROW_SEL = X.frame('RowSelected', T.rrect(T.rrect(T.blank(32, 32), 0, 0, 32, 32, 4, fill=ACC_TINT), 0, 0, 2, 32, 1, fill=ACC), 5)
ROW_MATCH = fr('RowMatch', None, ACC, 32, 4, 6)
ROW_CUR = fr('NameCurrent', ACC_TINT, ACC_RING, 32, 5, 7)


def switch_tex(name, on, hover=False):
    W, H = 64, 32
    img = T.blank(W, H)
    if on:
        T.rrect(img, 0, 0, W, H, 16, fill='#CC3ACE' if hover else ACC, border=ACC_B, bw=1.8)
        knob = '#FFFFFF'; kx = W - 4 - 22
    else:
        T.rrect(img, 0, 0, W, H, 16, fill='#2C2632' if hover else TOGGLE_OFF, border='#5A4A62' if hover else BR_STR, bw=1.8)
        knob = TXT3; kx = 4
    T.rrect(img, kx + 1, 5, kx + 23, 27, 11, fill=knob)
    return X.stretch(name, img)


SW = {'off': switch_tex('SwitchOff', False), 'offH': switch_tex('SwitchOffHover', False, True),
      'on': switch_tex('SwitchOn', True), 'onH': switch_tex('SwitchOnHover', True, True)}

LAUNCH = {'n': X.stretch('Launcher', box(64, 64, 14, ACC_TINT, ACC, 2.2)), 'h': X.stretch('LauncherHover', box(64, 64, 14, '#3A1640', ACC_B, 2.2))}
RING = X.stretch('LauncherRing', T.ring(T.blank(64, 64), 1, 1, 63, 63, 15, T.hex2rgba(ACC, 0.65), 2.4))


def dot(name, color, size=16):
    img = T.blank(size, size)
    T.rrect(img, 1, 1, size - 1, size - 1, (size - 2) / 2, fill=color)
    return img


TRACK = X.stretch('ScrollTrack', box(8, 32, 4, '#1A161E'))
THUMB = X.stretch('ScrollThumb', box(8, 32, 4, '#5E4E66'))

# ------------------------------------------------------------------ иконки (SVG 16×16)
ICON_PATHS = {
    'book': (['M3.5 2.5h8a1 1 0 0 1 1 1v9a1 1 0 0 1 -1 1h-8z', 'M5.5 2.5v11', 'M8 6.2a1.3 1.3 0 1 0 2.6 0a1.3 1.3 0 1 0 -2.6 0M7.2 10.3c.3-1.3 1.1-2 2.1-2s1.8.7 2.1 2'], 1.4),
    'search': (['M3 7a4 4 0 1 0 8 0a4 4 0 1 0 -8 0M10 10l3.5 3.5'], 1.6),
    'x': (['M4.5 4.5l7 7M11.5 4.5l-7 7'], 1.7),
    'close': (['M4 4l8 8M12 4l-8 8'], 1.8),
    'gear': (['M12.72 6.69 L14.52 7.01 L14.52 8.99 L12.72 9.31 L12.26 10.42 L13.32 11.91 L11.91 13.32 L10.42 12.26 L9.31 12.72 '
              'L8.99 14.52 L7.01 14.52 L6.69 12.72 L5.58 12.26 L4.09 13.32 L2.68 11.91 L3.74 10.42 L3.28 9.31 L1.48 8.99 L1.48 7.01 '
              'L3.28 6.69 L3.74 5.58 L2.68 4.09 L4.09 2.68 L5.58 3.74 L6.69 3.28 L7.01 1.48 L8.99 1.48 L9.31 3.28 L10.42 3.74 '
              'L11.91 2.68 L13.32 4.09 L12.26 5.58Z M10.2 8a2.2 2.2 0 1 1 -4.4 0a2.2 2.2 0 1 1 4.4 0'], 1.3),
    'target': (['M3 8a5 5 0 1 0 10 0a5 5 0 1 0 -10 0M8 1v3M8 12v3M1 8h3M12 8h3'], 1.5),
    'sortTime': (['M2.5 8a5.5 5.5 0 1 0 11 0a5.5 5.5 0 1 0 -11 0M8 5v3l2 1.5'], 1.5),
    'sortName': (['M2 12.5l2.5-8 2.5 8M2.8 10h3.4M9.5 4.5h4l-4 8h4'], 1.4),
    'neu': (['M2.5 8a5.5 5.5 0 1 0 11 0a5.5 5.5 0 1 0 -11 0M5.5 8h5'], 1.6),
    'pos': (['M2.5 8a5.5 5.5 0 1 0 11 0a5.5 5.5 0 1 0 -11 0M5.3 8.2l1.9 1.9 3.6-3.8'], 1.6),
    'neg': (['M3.5 15V2M3.5 2.5h9l-2 3 2 3h-9'], 1.6),
    'note': (['M4 2h6l3 3v9H4zM10 2v3h3M6 8h5M6 11h4'], 1.4),
    'clock': (['M2.5 8a5.5 5.5 0 1 0 11 0a5.5 5.5 0 1 0 -11 0M8 5v3l2 1.5'], 1.5),
    'rename': (['M2.5 6.5a5.5 5.5 0 0 1 10-2M13.5 9.5a5.5 5.5 0 0 1 -10 2M12.5 1.5v3h-3M3.5 14.5v-3h3'], 1.4),
    'plus': (['M3.5 8h9M8 3.5v9'], 1.8),
    'minus': (['M4 8h8'], 1.8),
    'edit': (['M10.5 2.5l3 3-8 8h-3v-3zM9 4l3 3'], 1.4),
    'trash': (['M2.5 4.5h11M6 4.5V3h4v1.5M4 4.5l.7 9h6.6l.7-9M6.7 7v4.5M9.3 7v4.5'], 1.4),
    'radar': (['M2 8a6 6 0 1 0 12 0a6 6 0 1 0 -12 0M5 8a3 3 0 1 0 6 0a3 3 0 1 0 -6 0M8 8l4-3'], 1.3),
}


def ic(kind, color, size=32):
    spec = ICON_PATHS[kind]
    return T.svg_icon(spec[0], color, size, spec[1])


def icon_tex(name, kind, color, key=None, size=32):
    img = ic(kind, color, size)
    return X.icon(key, name, img) if key else X.stretch(name, img)


MARKS = (('neu', M_NEU, 'NEU'), ('pos', M_POS, 'POS'), ('neg', M_NEG, 'NEG'))
for k, col, key in MARKS:
    icon_tex('Mark_%s' % key, k, col, 'MARK_%s' % key)
    icon_tex('Mark_%s_Off' % key, k, TXT3, 'MARK_%s_OFF' % key)
X.icon('DOT_LEAGUE', 'DotLeague', dot('DotLeague', F_LEAGUE))
X.icon('DOT_EMPIRE', 'DotEmpire', dot('DotEmpire', F_EMPIRE))
X.icon('DOT_NONE', 'DotNone', T.ring(T.blank(16, 16), 2, 2, 14, 14, 6, T.hex2rgba(TXT_OFF), 1.6))
X.icon('NEG_BADGE', 'NegBadge', dot('NegBadge', M_NEG))
icon_tex('Gear', 'gear', TXT2, 'GEAR')
icon_tex('GearOn', 'gear', ACC_T, 'GEAR_ON')
icon_tex('SortTime', 'sortTime', TXT2, 'SORT_TIME')
icon_tex('SortName', 'sortName', TXT2, 'SORT_NAME')
icon_tex('Note', 'note', TXT3, 'NOTE')
icon_tex('Rename', 'rename', ACC_I, 'RENAME')
icon_tex('Clock', 'clock', TXT2, 'CLOCK')
icon_tex('ClockOn', 'clock', ACC_T, 'CLOCK_ON')
icon_tex('NoteChip', 'note', TXT2, 'NOTE_CHIP')
icon_tex('NoteChipOn', 'note', ACC_T, 'NOTE_CHIP_ON')
BOOK = icon_tex('Book', 'book', ACC_T, 'BOOK', 64)
SEARCH_IC = icon_tex('Search', 'search', TXT3)
X_IC = icon_tex('Clear', 'x', TXT3)
CLOSE_IC = icon_tex('Close', 'close', TXT2)
TARGET_IC = icon_tex('Target', 'target', TXT2, 'TARGET')
icon_tex('TargetOff', 'target', TXT_OFF, 'TARGET_OFF')
PLUS_IC = icon_tex('Plus', 'plus', TXT2)
MINUS_IC = icon_tex('Minus', 'minus', TXT2)
EDIT_IC = icon_tex('Edit', 'edit', TXT2)
TRASH_IC = icon_tex('Trash', 'trash', TXT2)
RADAR_IC = icon_tex('Radar', 'radar', TXT_PH, size=64)

# ------------------------------------------------------------------ значки классов — игровые эмблемы
# Игра текстуру класса аддонам не отдаёт (unit.GetClass и CharacterClassId:GetInfo возвращают только имена
# и тип маны), поэтому эмблемы классов из клиента лежат в assets/class-<имя>.png (64×64, из
# Interface/Common/Elements/ClassIcons) и попадают в .pak как текстуры самого аддона.
# Ключ в группе Icons — CLS_<системное имя класса>, имена — как в MC.CLASS_RU (lua/Util.lua).
# Новый класс: положить assets/class-<имя строчными>.png и добавить имя сюда и в MC.CLASS_RU.
CLASSES = ('WARRIOR', 'PALADIN', 'MAGE', 'DRUID', 'PRIEST', 'PSIONIC', 'NECROMANCER', 'STALKER', 'BARD', 'ENGINEER', 'WARLOCK')


def png(name, w, h):
    """Картинка из assets/, вписанная в холст w×h (кратно 4) с сохранением пропорций."""
    im = Image.open(os.path.join(ASSETS, name)).convert('RGBA')
    k = min(w / im.width, h / im.height)
    nw, nh = max(1, int(round(im.width * k))), max(1, int(round(im.height * k)))
    im = im.resize((nw, nh), Image.LANCZOS)
    canvas = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    canvas.paste(im, ((w - nw) // 2, (h - nh) // 2))
    a = np.asarray(canvas).astype(np.float64) / 255.0
    # цвет прозрачных пикселей — средний цвет картинки, чтобы края в DXT не темнели
    vis = a[..., 3] > 0.05
    mean = a[vis][:, :3].mean(0) if vis.any() else np.zeros(3)
    a[..., :3] = np.where(a[..., 3:4] > 0.003, a[..., :3], mean)
    return a


for k in CLASSES:
    X.icon('CLS_' + k, 'Cls_' + k.capitalize(), png('class-%s.png' % k.lower(), 64, 64))
X.write_icon_group()

# ------------------------------------------------------------------ форматы текста


def F(name, f, color, alignx='left', **kw):
    return fmt(name, f[0], f[1], color, alignx, **kw)


F('TitleText', F_TITLE, TXT, literal='MyContacts')
F('CardTitleText', F_TITLE, TXT, literal='Карточка игрока')
F('Sect', F_SECT, GOLD)
F('Body', F_BODY, TXT)
F('BodyCenter', F_BODY, TXT, 'center')
F('Body2', F_BODY, TXT2)
F('Small3', F_SMALL, TXT3)
F('Small3R', F_SMALL, TXT3, 'right')
F('Small3C', F_SMALL, TXT3, 'center')
F('Hint', F_BODY, TXT_PH)
F('HintCenter', F_BODY, TXT_PH, 'center')
F('Count', F_SMALL, ACC_T, 'center')
F('Nick', F_NICK, TXT)
F('ChipCount', F_BODY, TXT)
F('Btn.Sec', F_BODY, TXT2, 'center', tag='button_label')
F('Btn.Pri', F_BODY, '#FFFFFF', 'center', tag='button_label')
F('Btn.Dis', F_BODY, TXT_OFF, 'center', tag='button_label')
F('Btn.Danger', F_BODY, '#FFFFFF', 'center', tag='button_label')
F('Btn.DSoft', F_BODY, '#F2B4B2', 'center', tag='button_label')
F('Menu', F_BODY, TXT, 'left', tag='button_label')
F('MarkLabel', F_BODY, TXT2)
F('Value', F_BODY, TXT, 'right')
F('Score', F_BODY, ACC_I)
F('NoteText', F_BODY, TXT, 'left', aligny='top')
F('TipText', F_SMALL, TXT, 'left', aligny='top')
F('CfText', F_BODY, TXT2, 'left', aligny='top')

# ------------------------------------------------------------------ общие строители


def tv(name, x, y, w, h, fref, **kw):
    return X.textview(name, PL(x, y, w, h), '../Texts/%s.txt' % fref, **kw)


def ipanel(name, x, y, s, tex, **kw):
    kw.setdefault('transparent', True)
    return X.panel(name, PL(x, y, s, s), back=tex, **kw)


def icon_button(name, x, y, s, icon_tex_href, reaction, isz=16, on_variant=False, ay=None, hy=None, **kw):
    ipanel(name + 'Icon', (s - isz) // 2, (s - isz) // 2, isz, icon_tex_href)
    vs = [{'normal': BTN['icon'], 'hover': BTN['iconH'], 'pressed': BTN['iconP'], 'reaction': reaction, 'push': 0}]
    if on_variant:
        vs.append({'normal': BTN['iconOn'], 'hover': BTN['iconOnH'], 'pressed': BTN['iconOnH'], 'reaction': reaction, 'push': 0})
    kw.setdefault('force_pointing', 'mc_tip')
    return X.button(name, PL(x, y, s, s, ay=ay, hy=hy), vs, children=[name + 'Icon.(WidgetPanel).xdb'], **kw)


def text_button(name, x, y, w, h, label, kind, reaction, **kw):
    t = X.text_file(name, label)
    if kind == 'pri':
        v = {'normal': BTN['pri'], 'hover': BTN['priH'], 'pressed': BTN['priP'], 'disabled': BTN['priD'], 'fmt': '../Texts/Btn.Pri.txt'}
    elif kind == 'dng':
        v = {'normal': BTN['dng'], 'hover': BTN['dngH'], 'pressed': BTN['dngP'], 'disabled': BTN['secD'], 'fmt': '../Texts/Btn.Danger.txt'}
    elif kind == 'dsoft':
        v = {'normal': BTN['dsoft'], 'hover': BTN['dsoftH'], 'pressed': BTN['dsoftH'], 'disabled': BTN['secD'], 'fmt': '../Texts/Btn.DSoft.txt'}
    else:
        v = {'normal': BTN['sec'], 'hover': BTN['secH'], 'pressed': BTN['secP'], 'disabled': BTN['secD'], 'fmt': '../Texts/Btn.Sec.txt'}
    v.update({'text': t, 'fmt_dis': '../Texts/Btn.Dis.txt', 'reaction': reaction, 'push': 0})
    return X.button(name, PL(x, y, w, h), [v], **kw)


def switch(name, x, y, reaction):
    return X.button(name, PL(x, y, 40, 20), [
        {'normal': SW['off'], 'hover': SW['offH'], 'pressed': SW['offH'], 'reaction': reaction, 'push': 0},
        {'normal': SW['on'], 'hover': SW['onH'], 'pressed': SW['onH'], 'reaction': reaction, 'push': 0}])


def header(prefix, w, title_fmt, buttons):
    X.panel(prefix + 'Accent', PL(12, 17, 10, 10), back=ACCENT_MARK, transparent=True)
    tv(prefix + 'Title', 30, 0, 220, 44, title_fmt)
    kids = [prefix + 'Accent.(WidgetPanel).xdb', prefix + 'Title.(WidgetTextView).xdb'] + buttons
    X.panel(prefix + 'Header', PL(0, 0, w, 44), back=HDR_FRAME, children=kids)
    X.panel(prefix + 'HeaderLine', PL(1, 43, w - 2, 1), back=LINE_TEX, transparent=True)
    return [prefix + 'Header.(WidgetPanel).xdb', prefix + 'HeaderLine.(WidgetPanel).xdb']


# ------------------------------------------------------------------ кнопка на экране (24×24, вдвое меньше прежней)
ipanel('MCIcon', 5, 5, 14, BOOK)
X.button('MCButton', PL(5, 5, 24, 24), [{'normal': LAUNCH['n'], 'hover': LAUNCH['h'], 'pressed': LAUNCH['h'], 'reaction': 'mc_main',
                                             'rclick': 'mc_main_right'}],   # правый клик — карточка игрока в цели
         children=['MCIcon.(WidgetPanel).xdb'], force_pointing='mc_tip')
X.panel('MCRing', PL(0, 0, 34, 34), back=RING, transparent=True, visible=False)
X.panel('MCBadge', PL(24, 3, 7, 7), back='Textures/NegBadge.Stretch.(WidgetLayerSimpleTexture).xdb', transparent=True, visible=False)
X.panel('MCHost', PL(480, 10, 34, 34), children=['MCRing.(WidgetPanel).xdb', 'MCButton.(WidgetButton).xdb', 'MCBadge.(WidgetPanel).xdb'],
        pick_children=True, priority=800)

# ------------------------------------------------------------------ главное окно 440×600
MW, MH = 440, 600
tv('CountText', 0, 0, 72, 20, 'Count')
X.panel('CountChip', PL(162, 12, 72, 20), back=COUNT_CHIP, children=['CountText.(WidgetTextView).xdb'], pointing='mc_tip')
gear = icon_button('HdrGear', MW - 12 - 28 - 4 - 28, 8, 28, 'Textures/Gear.Stretch.(WidgetLayerSimpleTexture).xdb', 'mc_gear', on_variant=True)
close = icon_button('HdrClose', MW - 12 - 28, 8, 28, CLOSE_IC, 'mc_close')
main_hdr = header('Main', MW, 'TitleText', ['CountChip.(WidgetPanel).xdb', gear, close])

# --- поиск
SB_W = 340
ipanel('SearchIcon', 10, 9, 14, SEARCH_IC)
X.editline('SearchEdit', PL(32, 0, SB_W - 32 - 30, 32), '../Texts/Body.txt', CURSOR, SELECTION, 14, 'mc_search_enter', 'mc_search_esc',
           focus='mc_search_focus', changed='mc_search_changed')
tv('SearchHint', 32, 0, SB_W - 64, 32, 'Hint')
search_clear = icon_button('SearchClear', SB_W - 28, 4, 24, X_IC, 'mc_search_clear', isz=12, force_pointing=None, visible=False)
X.panel('SearchFocus', PL(0, 0, SB_W, 32), back=FIELD_FOCUS, transparent=True, visible=False)
X.panel('SearchBox', PL(12, 10, SB_W, 32), back=FIELD,
        children=['SearchFocus.(WidgetPanel).xdb', 'SearchIcon.(WidgetPanel).xdb', 'SearchHint.(WidgetTextView).xdb',
                  'SearchEdit.(WidgetEditLine).xdb', search_clear])
sort_btn = icon_button('SortBtn', 358, 10, 32, 'Textures/SortTime.Stretch.(WidgetLayerSimpleTexture).xdb', 'mc_sort')
target_btn = icon_button('TargetBtn', 396, 10, 32, TARGET_IC, 'mc_target')

# --- фильтры: нейтральные, отрицательные, положительные, с заметками, за 24 часа, «Сброс»
FILTERS = (('FNeu', 12, 70, 'neu', 'MARK_NEU_OFF'), ('FNeg', 88, 70, 'neg', 'MARK_NEG_OFF'), ('FPos', 164, 70, 'pos', 'MARK_POS_OFF'),
           ('FNotes', 240, 40, 'acc', None), ('FRecent', 286, 40, 'acc', None))
filter_kids = []
for name, x, w, col, _ in FILTERS:
    kids = [name + 'Icon.(WidgetPanel).xdb']
    if w == 70:
        ipanel(name + 'Icon', 17, 8, 14, 'Textures/Mark_%s_Off.Stretch.(WidgetLayerSimpleTexture).xdb' % col.upper())
        tv(name + 'Count', 37, 0, 24, 30, 'ChipCount')
        kids.append(name + 'Count.(WidgetTextView).xdb')
    else:
        ipanel(name + 'Icon', (w - 16) // 2, 7, 16, 'Textures/%s.Stretch.(WidgetLayerSimpleTexture).xdb' % ('NoteChip' if name == 'FNotes' else 'Clock'))
    vs = [{'normal': CHIP_OFF, 'hover': CHIP_OFF_H, 'pressed': CHIP_OFF_H, 'reaction': 'mc_filter', 'push': 0},
          {'normal': CHIP_ON[col], 'hover': CHIP_ON_H[col], 'pressed': CHIP_ON_H[col], 'reaction': 'mc_filter', 'push': 0}]
    filter_kids.append(X.button(name, PL(x, 50, w, 30), vs, children=kids, force_pointing='mc_tip'))
filter_kids.append(text_button('FReset', 332, 50, 96, 30, 'Сброс', 'sec', 'mc_reset', force_pointing='mc_tip'))

# --- список: пул из 16 строк, своя прокрутка (колесо — 3 строки, клик по дорожке — страница)
LIST_Y, LIST_H = 90, 458
ROW_W, ROW_H, ROWS = 394, 28, 16
LWHEEL = ('mc_list_up', 'mc_list_down')
X.button('RowBtn', PL(0, 0, ROW_W, ROW_H), [
    {'normal': TRANSP, 'reaction': 'mc_row', 'push': 0},
    {'normal': ROW_SEL, 'reaction': 'mc_row', 'push': 0},
    {'normal': ROW_MATCH, 'reaction': 'mc_row', 'push': 0}], wheel=LWHEEL)
ipanel('RowMarkIcon', 3, 3, 14, 'Textures/Mark_NEU.Stretch.(WidgetLayerSimpleTexture).xdb')
X.button('RowMark', PL(6, 4, 20, 20), [{'normal': TRANSP, 'reaction': 'mc_rowmark', 'push': 0}], children=['RowMarkIcon.(WidgetPanel).xdb'],
         wheel=LWHEEL)
ipanel('RowDot', 32, 10, 8, 'Textures/DotLeague.Stretch.(WidgetLayerSimpleTexture).xdb')
tv('RowNick', 48, 0, ROW_W - 48 - 44, ROW_H, 'Body')
ipanel('RowNote', ROW_W - 40, 8, 12, 'Textures/Note.Stretch.(WidgetLayerSimpleTexture).xdb')
ipanel('RowRen', ROW_W - 22, 8, 12, 'Textures/Rename.Stretch.(WidgetLayerSimpleTexture).xdb')
rows = []
for i in range(ROWS):
    rows.append(X.panel('Row%d' % (i + 1), PL(4, 4 + i * ROW_H, ROW_W, ROW_H),
                        children=['RowBtn.(WidgetButton).xdb', 'RowMark.(WidgetButton).xdb', 'RowDot.(WidgetPanel).xdb',
                                  'RowNick.(WidgetTextView).xdb', 'RowNote.(WidgetPanel).xdb', 'RowRen.(WidgetPanel).xdb'],
                        pick_children=True, visible=False))
X.panel('ScrollThumb', PL(0, 0, 8, 40), back=THUMB, transparent=True)
# дорожка — панель: клик и перетаскивание обрабатываются через DnD (ползунок прыгает под курсор и тянется)
X.panel('ScrollTrack', PL(416 - 4 - 8 - 2, 4, 8, LIST_H - 8), back=TRACK, transparent=False,
        children=['ScrollThumb.(WidgetPanel).xdb'], wheel=LWHEEL)
ipanel('EmptyIcon', (416 - 36) // 2, 150, 36, RADAR_IC)
tv('EmptyText', 0, 194, 416, 24, 'HintCenter')
empty_reset = text_button('EmptyReset', (416 - 170) // 2, 230, 170, 32, 'Сбросить фильтры', 'sec', 'mc_reset')
empty_add = text_button('EmptyAdd', (416 - 170) // 2, 270, 170, 32, 'Добавить вручную', 'sec', 'mc_empty_add', force_pointing='mc_tip')
X.panel('ListBox', PL(12, LIST_Y, 416, LIST_H), back=LIST_FRAME,
        children=['EmptyIcon.(WidgetPanel).xdb', 'EmptyText.(WidgetTextView).xdb', empty_reset, empty_add] + rows +
        ['ScrollTrack.(WidgetPanel).xdb'], wheel=('mc_list_up', 'mc_list_down'), pick_children=False)

X.panel('MainPage', PL(0, 44, MW, MH - 44),
        children=['SearchBox.(WidgetPanel).xdb', sort_btn, target_btn] + filter_kids + ['ListBox.(WidgetPanel).xdb'], pick_children=True)

# --- меню отметки (выпадающее, поверх списка)
menu_items = []
for i, (k, col, key) in enumerate(MARKS):
    label = {'neu': 'Нейтральный', 'pos': 'Положительный', 'neg': 'Отрицательный'}[k]
    nm = 'Menu' + key.capitalize()
    ipanel(nm + 'Icon', 10, 8, 14, 'Textures/Mark_%s.Stretch.(WidgetLayerSimpleTexture).xdb' % key)
    t = X.text_file(nm, '        ' + label)
    menu_items.append(X.button(nm, PL(4, 4 + i * 30, 172, 30), [
        {'normal': TRANSP, 'hover': BTN['iconH'], 'pressed': BTN['iconH'], 'text': t, 'fmt': '../Texts/Menu.txt', 'reaction': 'mc_menu', 'push': 0}],
        children=[nm + 'Icon.(WidgetPanel).xdb']))
X.panel('MarkMenu', PL(0, 0, 180, 98), back=TIP_FRAME, children=menu_items, pick_children=True, visible=False, priority=960)

# --- страница настроек
SET_ROWS = [  # (вид, y)
    ('sect', 12, 'SetSectReact'),
    ('sw', 40), ('sw', 70), ('sw', 100), ('sw', 130), ('step', 160),
    ('line', 200),
    ('sect', 212, 'SetSectBase'),
    ('sw', 240), ('sw', 270), ('sw', 300), ('sw', 330), ('step', 360),
    ('stats', 396),
    ('line', 474),
    ('sect', 484, 'SetSectCommon'),
]
tv('SetName', 12, 0, 300, 30, 'Body', transparent=False, pointing='mc_tip')
switch('SetSwitch', MW - 12 - 40, 5, 'mc_set_switch')
SB, BW_, BH_ = 26, 96, 24
ipanel('StepMinusIcon', (SB - 12) // 2, (BH_ - 12) // 2, 12, MINUS_IC)
ipanel('StepPlusIcon', (SB - 12) // 2, (BH_ - 12) // 2, 12, PLUS_IC)
X.button('StepMinus', PL(0, 0, SB, BH_), [{'normal': TRANSP, 'hover': BTN['iconH'], 'pressed': BTN['iconH'], 'reaction': 'mc_step_minus', 'push': 0}],
         children=['StepMinusIcon.(WidgetPanel).xdb'])
X.button('StepPlus', PL(BW_ - SB, 0, SB, BH_), [{'normal': TRANSP, 'hover': BTN['iconH'], 'pressed': BTN['iconH'], 'reaction': 'mc_step_plus', 'push': 0}],
         children=['StepPlusIcon.(WidgetPanel).xdb'])
tv('StepValue', SB, 0, BW_ - 2 * SB, BH_, 'BodyCenter')
X.panel('StepBox', PL(MW - 12 - BW_, 3, BW_, BH_), back=FIELD,
        children=['StepMinus.(WidgetButton).xdb', 'StepValue.(WidgetTextView).xdb', 'StepPlus.(WidgetButton).xdb'],
        wheel=('mc_step_up', 'mc_step_down'), pointing='mc_tip')
set_kids = []
nsw = nst = 0
for row in SET_ROWS:
    kind, y = row[0], row[1]
    if kind == 'sect':
        tv(row[2], 12, y, 300, 22, 'Sect', transparent=False, pointing='mc_tip')
        set_kids.append(row[2] + '.(WidgetTextView).xdb')
    elif kind == 'line':
        X.panel('SetLine%d' % y, PL(12, y, MW - 24, 1), back=LINE_TEX, transparent=True)
        set_kids.append('SetLine%d.(WidgetPanel).xdb' % y)
    elif kind == 'sw':
        nsw += 1
        set_kids.append(X.panel('SetSw%d' % nsw, PL(0, y, MW, 30), children=['SetName.(WidgetTextView).xdb', 'SetSwitch.(WidgetButton).xdb'],
                                pick_children=True))
    elif kind == 'step':
        nst += 1
        set_kids.append(X.panel('SetStep%d' % nst, PL(0, y, MW, 30), children=['SetName.(WidgetTextView).xdb', 'StepBox.(WidgetPanel).xdb'],
                                pick_children=True))
    elif kind == 'stats':
        tv('SetStats', 12, y, MW - 24, 24, 'Small3')
        set_kids.append('SetStats.(WidgetTextView).xdb')
        set_kids.append(text_button('SetCleanNow', 12, y + 32, 170, 32, 'Очистить сейчас', 'sec', 'mc_clean_now', force_pointing='mc_tip'))
        set_kids.append(text_button('SetWipe', 12 + 170 + 8, y + 32, 170, 32, 'Очистить базу', 'dsoft', 'mc_wipe', force_pointing='mc_tip'))
set_kids.append(text_button('SetResetCfg', 12, 514, 190, 32, 'Сбросить настройки', 'sec', 'mc_reset_cfg', force_pointing='mc_tip'))
X.panel('SettingsPage', PL(0, 44, MW, MH - 44), children=set_kids, pick_children=True, visible=False)

X.panel('MainWindow', PL(480, 60, MW, MH), back=WIN_FRAME,
        children=main_hdr + ['MainPage.(WidgetPanel).xdb', 'SettingsPage.(WidgetPanel).xdb', 'MarkMenu.(WidgetPanel).xdb'],
        visible=False, priority=900)

# ------------------------------------------------------------------ карточка игрока 600×600
CW, CH = 600, 660
card_close = icon_button('CardClose', CW - 12 - 28, 8, 28, CLOSE_IC, 'mc_card_close')
card_hdr = header('Card', CW, 'CardTitleText', [card_close])
ipanel('CardDot', 12, 66, 10, 'Textures/DotLeague.Stretch.(WidgetLayerSimpleTexture).xdb')
tv('CardNick', 30, 54, CW - 42, 32, 'Nick')
tv('CardInfo', 12, 88, CW - 24, 22, 'Body2')
# эмблемы классов слева от строки сведений: первая — текущий класс, дальше — классы, на которых
# игрок был замечен раньше (приглушены, недавние первыми). Шести мест хватает: смена класса — редкость.
# Показанные эмблемы сдвигают CardInfo вправо — это делает lua/UI.lua (CLS_SLOTS, CLS_X, CLS_STEP те же).
CLS_SLOTS, CLS_X, CLS_STEP, CLS_SIZE = 6, 12, 30, 28
cls_slots = [ipanel('ClsSlot%d' % (i + 1), CLS_X + i * CLS_STEP, 85, CLS_SIZE,
                    'Textures/Cls_Warrior.Stretch.(WidgetLayerSimpleTexture).xdb', visible=False) for i in range(CLS_SLOTS)]
CHIP_LABELS = {'neu': 'Нейтральный', 'pos': 'Положительный', 'neg': 'Отрицательный'}
card_chips = []
for i, (k, col, key) in enumerate(MARKS):
    nm = 'CardMark' + key.capitalize()
    label = CHIP_LABELS[k]
    tw = int(len(label) * 8.6)
    x0 = (188 - (16 + 8 + tw)) // 2
    ipanel(nm + 'Icon', x0, 7, 16, 'Textures/Mark_%s_Off.Stretch.(WidgetLayerSimpleTexture).xdb' % key)
    X.textview(nm + 'Text', PL(x0 + 24, 0, 188 - x0 - 24, 30), '../Texts/MarkLabel.txt')
    card_chips.append(X.button(nm, PL(12 + i * 194, 118, 188, 30), [
        {'normal': CHIP_OFF, 'hover': CHIP_OFF_H, 'pressed': CHIP_OFF_H, 'reaction': 'mc_card_mark', 'push': 0},
        {'normal': CHIP_ON[k], 'hover': CHIP_ON_H[k], 'pressed': CHIP_ON_H[k], 'reaction': 'mc_card_mark', 'push': 0}],
        children=[nm + 'Icon.(WidgetPanel).xdb', nm + 'Text.(WidgetTextView).xdb'], force_pointing='mc_tip'))
X.panel('CardLine', PL(12, 160, CW - 24, 1), back=LINE_TEX, transparent=True)
# левая колонка: поля
LEFT_W = 300
fields = []
for i, nm in enumerate(('FGuild', 'FRank', 'FUid')):
    y = 172 + i * 26
    tv(nm + 'Label', 12, y, 150, 24, 'Small3', transparent=False, pointing='mc_tip')
    tv(nm + 'Value', 120, y, LEFT_W - 120, 24, 'Value', transparent=False, pointing='mc_tip')
    fields += [nm + 'Label.(WidgetTextView).xdb', nm + 'Value.(WidgetTextView).xdb']
# рейтинг арен 3х3 и 6х6 — две строки под полями, всегда на своих местах (нет рейтинга — «нет данных»),
# поэтому карточка не меняет раскладку от игрока к игроку. В строке шириной 288 px (x 12..300):
#   подпись «3х3» 28 px · счёт (главное, цветом акцента) 46 px · «#312 25/40(63%)» — до правого края.
# Даты в строке нет. Тексты — lua/UI.lua (ArenaTexts).
# Место под эти строки: блоки «Ники» и «Гильдии» сдвинуты вниз на 52 px, а строк в «Гильдии» стало 4 вместо 5
# (остальное — колесом), иначе список гильдий наезжал бы на кнопку «Удалить из базы» (y = 616).
ARENA_Y, ARENA_STEP = 250, 26
for i, nm in enumerate(('FA3', 'FA6')):
    y = ARENA_Y + i * ARENA_STEP
    tv(nm + 'Label', 12, y, 28, 24, 'Small3')
    tv(nm + 'Score', 42, y, 46, 24, 'Score')
    tv(nm + 'Info', 90, y, LEFT_W - 90, 24, 'Small3')
    fields += [nm + s + '.(WidgetTextView).xdb' for s in ('Label', 'Score', 'Info')]
# ники и гильдии: первая строка — текущее, остальные — история (прокрутка колесом)
NAME_ROWS, GUILD_ROWS = 4, 4


def history(prefix, title_y, rows_y, wheel, rows, right=None):
    """Строки истории: текст слева; right — имя второго поля справа (ранг) или None."""
    tv(prefix + 'Title', 12, title_y, 220, 22, 'Sect', transparent=False)
    kids_row = []
    if right:
        tv(prefix + 'Text', 8, 0, 180, 26, 'Body')
        tv(prefix + right, 190, 0, LEFT_W - 12 - 190 - 8, 26, 'Small3R')
        kids_row = [prefix + 'Text.(WidgetTextView).xdb', prefix + right + '.(WidgetTextView).xdb']
    else:
        tv(prefix + 'Text', 8, 0, LEFT_W - 12 - 16, 26, 'Body')
        kids_row = [prefix + 'Text.(WidgetTextView).xdb']
    kids = [prefix + 'Title.(WidgetTextView).xdb']
    X.panel(prefix + 'Area', PL(12, rows_y, LEFT_W - 12, rows * 28), transparent=False, wheel=wheel)
    kids.append(prefix + 'Area.(WidgetPanel).xdb')
    for i in range(rows):
        kids.append(X.panel('%sRow%d' % (prefix, i + 1), PL(12, rows_y + i * 28, LEFT_W - 12, 26), back=ROW_CUR if i == 0 else TRANSP,
                            children=kids_row, wheel=wheel, visible=False))
    return kids


name_rows = history('Names', 312, 338, ('mc_names_up', 'mc_names_down'), NAME_ROWS)
guild_rows = history('Guilds', 462, 488, ('mc_guilds_up', 'mc_guilds_down'), GUILD_ROWS, right='Rank')
# правая колонка: заметки
RX, RW = 324, 264
tv('NotesTitle', RX, 172, 200, 22, 'Sect', transparent=False, pointing='mc_tip')
note_add = icon_button('NoteAdd', RX + RW - 26, 170, 26, PLUS_IC, 'mc_note_add')
# Блок заметки подстраивается под текст: высоту блока и текста выставляет lua/UI.lua (те же числа — там).
#   текст — на всю ширину блока: RW - 20 = 244 px, шрифт AllodsSystem 16, шаг строк 18 px (в расчёте 19);
#   обычный русский текст ≈ 7,9 px на знак -> около 30 знаков в строке, 300 знаков ≈ 10–11 строк;
#   самые широкие буквы (Ж, Ш, Щ — 15 px) -> 16 знаков в строке, 300 знаков = 19 строк = 342 px;
#   область заметок NOTES_H = 432 px вмещает блок с текстом в 396 px, то есть любую заметку целиком.
# Дата и кнопки прижаты к низу блока (WIDGET_ALIGN_HIGH) и сами едут за его высотой.
# Блоков в пуле 6: столько коротких заметок (59 px + 8 px промежуток) помещается в область.
NOTE_CARDS, NOTES_Y, NOTES_H = 6, 200, 432
HIGH = 'WIDGET_ALIGN_HIGH'
tv('NoteText', 10, 6, RW - 20, 23, 'NoteText', multiline=True)
X.textview('NoteDate', PL(10, None, 198, 18, ay=HIGH, hy=6), '../Texts/Small3.txt')
note_edit = icon_button('NoteEdit', RW - 52, None, 22, EDIT_IC, 'mc_note_edit', isz=14, ay=HIGH, hy=4)
note_del = icon_button('NoteDel', RW - 28, None, 22, TRASH_IC, 'mc_note_del', isz=14, ay=HIGH, hy=4)
note_cards = []
for i in range(NOTE_CARDS):
    note_cards.append(X.panel('NoteCard%d' % (i + 1), PL(RX, NOTES_Y + i * 67, RW, 59), back=NOTE_FRAME,
                              children=['NoteText.(WidgetTextView).xdb', 'NoteDate.(WidgetTextView).xdb', note_edit, note_del],
                              wheel=('mc_notes_up', 'mc_notes_down'), visible=False))
tv('NotesEmpty', RX, 300, RW, 24, 'HintCenter')
notes_empty_add = text_button('NotesEmptyAdd', RX + (RW - 170) // 2, 332, 170, 32, 'Добавить заметку', 'sec', 'mc_note_add')
tv('NotesMore', RX, NOTES_Y + NOTES_H + 2, RW, 18, 'Small3C')
X.panel('NotesArea', PL(RX, NOTES_Y, RW, NOTES_H), transparent=False, wheel=('mc_notes_up', 'mc_notes_down'))
card_delete = text_button('CardDelete', 12, 616, 170, 32, 'Удалить из базы', 'dsoft', 'mc_card_delete', force_pointing='mc_tip')

# редактор заметки — модальное окно поверх карточки
# Поле ввода — многострочное: WidgetEditLine с multiline + wrapText (текст переносится по словам,
# Enter сохраняет заметку, перевода строки в тексте нет). Расчёт на 300 знаков (MC.NOTE_MAX):
#   ширина поля EW - 24 - 16 = 480 px, шрифт AllodsSystem 16, шаг строк 18 px (в расчёте 19);
#   обычный русский текст ≈ 7,9 px на знак -> 60 знаков в строке -> 300 знаков = 5–6 строк;
#   широкие строчные (ф, ы, ш ≈ 10,2 px) -> 47 знаков в строке -> 7 строк;
#   самые широкие буквы (Ж, Ш, Щ — 15 px, Ю — 16 px) -> 30–32 знака в строке -> 10 строк.
# Поэтому строк 10: вся заметка видна при любом тексте.
ED_LINES, ED_LINE_H = 10, 19
ED_H = ED_LINES * ED_LINE_H + 12
EW, EH = 520, 56 + ED_H + 12 + 32 + 16
X.panel('EdScrim', PL(0, 0, None, None, 'WIDGET_ALIGN_BOTH', 'WIDGET_ALIGN_BOTH'), back=SCRIM)
ed_close = icon_button('EdClose', EW - 12 - 28, 8, 28, CLOSE_IC, 'mc_ed_cancel')
ed_hdr = header('Ed', EW, 'Sect', [ed_close])
X.editline('EdEdit', PL(8, 6, EW - 24 - 16, ED_H - 12), '../Texts/NoteText.txt', CURSOR, SELECTION, 300, 'mc_ed_save', 'mc_ed_cancel',
           changed='mc_ed_changed', multiline=True)
X.panel('EdBox', PL(12, 56, EW - 24, ED_H), back=FIELD, children=['EdEdit.(WidgetEditLine).xdb'])
ED_BTN_Y = 56 + ED_H + 12
tv('EdCount', 12, ED_BTN_Y, 150, 32, 'Small3')
ed_cancel = text_button('EdCancel', EW - 12 - 100 - 8 - 100, ED_BTN_Y, 100, 32, 'Отмена', 'sec', 'mc_ed_cancel')
ed_save = text_button('EdSave', EW - 12 - 100, ED_BTN_Y, 100, 32, 'Сохранить', 'pri', 'mc_ed_save')
X.panel('Editor', PL(0, 0, EW, EH, 'WIDGET_ALIGN_CENTER', 'WIDGET_ALIGN_CENTER'), back=WIN_FRAME,
        children=ed_hdr + ['EdBox.(WidgetPanel).xdb', 'EdCount.(WidgetTextView).xdb', ed_cancel, ed_save])
X.panel('EditorLayer', PL(0, 0, None, None, 'WIDGET_ALIGN_BOTH', 'WIDGET_ALIGN_BOTH'),
        children=['EdScrim.(WidgetPanel).xdb', 'Editor.(WidgetPanel).xdb'], visible=False, priority=100)

X.panel('CardWindow', PL(930, 60, CW, CH), back=WIN_FRAME,
        children=card_hdr + ['CardDot.(WidgetPanel).xdb', 'CardNick.(WidgetTextView).xdb', 'CardInfo.(WidgetTextView).xdb'] + cls_slots +
        card_chips +
        ['CardLine.(WidgetPanel).xdb'] + fields + name_rows + guild_rows +
        ['NotesTitle.(WidgetTextView).xdb', note_add, 'NotesArea.(WidgetPanel).xdb'] + note_cards +
        ['NotesEmpty.(WidgetTextView).xdb', notes_empty_add, 'NotesMore.(WidgetTextView).xdb', card_delete, 'EditorLayer.(WidgetPanel).xdb'],
        visible=False, priority=901)

# ------------------------------------------------------------------ подтверждение (по центру экрана)
FW, FH = 340, 160
tv('CfTitle', 16, 14, FW - 32, 24, 'Sect')
tv('CfText', 16, 44, FW - 32, 60, 'CfText', multiline=True)
cf_cancel = text_button('CfCancel', FW - 16 - 120 - 8 - 120, 112, 120, 32, 'Отмена', 'sec', 'mc_cf_cancel')
cf_ok = text_button('CfOk', FW - 16 - 120, 112, 120, 32, 'Удалить', 'dng', 'mc_cf_ok', force_pointing='mc_tip')
X.panel('Confirm', PL(0, 0, FW, FH, 'WIDGET_ALIGN_CENTER', 'WIDGET_ALIGN_CENTER'), back=WIN_FRAME,
        children=['CfTitle.(WidgetTextView).xdb', 'CfText.(WidgetTextView).xdb', cf_cancel, cf_ok], visible=False, priority=980)

# ------------------------------------------------------------------ подсказка
X.panel('TipBack', PL(0, 0, None, None, 'WIDGET_ALIGN_BOTH', 'WIDGET_ALIGN_BOTH'), back=TIP_FRAME, transparent=True)
X.panel('TipBackWarn', PL(0, 0, None, None, 'WIDGET_ALIGN_BOTH', 'WIDGET_ALIGN_BOTH'), back=TIP_WARN, transparent=True, visible=False)
X.textview('TipText', PL(10, 7, None, None, 'WIDGET_ALIGN_BOTH', 'WIDGET_ALIGN_BOTH', hx=10, hy=5), '../Texts/TipText.txt', multiline=True)
X.panel('Tooltip', PL(0, 0, 300, 40), children=['TipBack.(WidgetPanel).xdb', 'TipBackWarn.(WidgetPanel).xdb', 'TipText.(WidgetTextView).xdb'],
        transparent=True, visible=False, priority=990)

X.form('MyContacts', ['MainWindow.(WidgetPanel).xdb', 'CardWindow.(WidgetPanel).xdb', 'MCHost.(WidgetPanel).xdb',
                    'Confirm.(WidgetPanel).xdb', 'Tooltip.(WidgetPanel).xdb'])

X.text_file('AddonName', 'MyContacts')
X.text_file('AddonDescription', 'Записная книжка игроков: заметки, отметки, история ников, предупреждения об отрицательных')
print('ok', len(os.listdir(X.WID)), 'widgets', len(os.listdir(X.TEXDIR)), 'texture files')

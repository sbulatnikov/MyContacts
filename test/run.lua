-- Прогон логики MyContacts на заглушках:
--   texlua test/run.lua <папка исходников> <папка скриптов>
-- Скрипты — lua/, пропущенные через tools/strip_debug.py (обычная или отладочная сборка).
local ROOT = arg and arg[ 1 ] or "."
local L = ( arg and arg[ 2 ] or ( ROOT .. "/lua" ) ) .. "/"
dofile( ROOT .. "/test/mock.lua" )
for _, f in ipairs( { "LibDnD", "Util", "Config", "DB", "Probe", "Game", "UI", "Main" } ) do
	local fh = io.open( L .. f .. ".lua" )
	if fh then fh:close() dofile( L .. f .. ".lua" ) end
end

local fails = 0
local function check( cond, what )
	if cond then print( "OK   " .. what ) else print( "FAIL " .. what ) fails = fails + 1 end
end
local function chatHas( s )
	for _, c in ipairs( CHAT ) do if string.find( c, s, 1, true ) then return true end end
	return false
end
local function second( n ) for _ = 1, n or 1 do NOW = NOW + 1000 EVENTS.EVENT_SECOND_TIMER( {} ) end end
local function click( r, wname ) REACTIONS[ r ]( { widget = FIND( wname ), sender = wname } ) end

-- 1. Старт: пустая база нового формата
check( MC.DB.Count() == 0, "старт: база пуста" )
check( CONFIG.MyContacts_Meta and CONFIG.MyContacts_Meta.v == 2, "старт: формат базы 2" )
check( not MC.DEBUG, "отладка выключена" )
-- база старого формата очищается при загрузке
CONFIG.MyContacts_Meta = { v = 1, dict = {} }
CONFIG.MyContacts_DB_05 = { [ "NСтарый@1" ] = "Старый|1|0|0|0|n|0|0||0|0||0|0" }
CONFIG.MyContacts_Cards = { [ "NСтарый@1" ] = { mark = -1 } }
CONFIG.MyContacts_UidLog = { x = { i = "0x1" } }
MC.DB.Load()
check( MC.DB.Count() == 0 and CONFIG.MyContacts_DB_05 == nil and CONFIG.MyContacts_Cards == nil and CONFIG.MyContacts_UidLog == nil
	and CONFIG.MyContacts_Meta.v == 2, "старый формат: база и отладочные секции удалены" )

-- 2. Игроки рядом без ID в базу не попадают
UNITS[ 10 ] = { name = "Хмурыйпёс", shard = "Нить судьбы", fac = "Лига", cls = "WARRIOR", gs = 41250 }
UNITS[ 11 ] = { name = "Тирэль", shard = "Вечный Зов", fac = "Империя", cls = "MAGE", gs = 0 }
EVENTS.EVENT_UNITS_CHANGED( { spawned = { 10, 11 }, despawned = {} } )
check( MC.DB.Count() == 0, "рядом: новых не записывает" )

-- 3. Группа: запись по ID, затем рядом — обновление полей
STATE.group = { { name = "Хмурыйпёс", uid = UID( "h1" ) } }
EVENTS.EVENT_GROUP_MEMBER_ADDED( {} )
second()
local r = MC.DB.FindByName( "Хмурыйпёс", MC.DB.DictId( "shard", "Нить судьбы" ) )
check( r and r.uid == "0x6831" and r.k == "U0x6831", "группа: запись по ID (" .. tostring( r and r.k ) .. ")" )
STATE.zone = "Сиверия"
EVENTS.EVENT_UNITS_CHANGED( { spawned = { 10 }, despawned = {} } )
check( r.fac == 1 and r.gs == 41250 and MC.DB.DictName( "cls", r.cls ) == "Воин", "рядом: известному обновлены фракция, ГС, класс" )
STATE.zone = nil
MC.DB.SetMark( r, -1 )
STATE.group = {}
EVENTS.EVENT_GROUP_MEMBER_REMOVED( {} ) second()
CHAT = {}
STATE.group = { { name = "Хмурыйпёс", uid = UID( "h1" ) } }
EVENTS.EVENT_GROUP_MEMBER_ADDED( {} ) second()
check( chatHas( "Игрок \"Хмурыйпёс\" помечен негативным" ), "группа: предупреждение по ID" )
check( #MC.Game.groupNegative == 1, "кнопка: отрицательный в группе" )
local n0 = #CHAT
EVENTS.EVENT_GROUP_CHANGED( {} ) second()
check( #CHAT == n0, "группа: повторного предупреждения нет, пока он в группе" )
STATE.group = {}
EVENTS.EVENT_GROUP_MEMBER_REMOVED( {} ) second()

-- 4. Личка: пауза от последнего показанного предупреждения; входящая и исходящая — по ID
CHAT = {}
local function whisper( sec, echo )
	NOW = 1000000 + sec * 1000
	if echo then
		EVENTS.EVENT_CHAT_MESSAGE( { chatType = 7, isEcho = true, sender = WS_( "Я" ), recipient = WS_( "Хмурыйпёс" ),
			recipientUniqueId = UID( "h1" ), msg = WS_( "x" ) } )
	else
		EVENTS.EVENT_CHAT_MESSAGE( { chatType = 7, isEcho = false, sender = WS_( "Хмурыйпёс" ), shard = WS_( "Нить судьбы" ),
			senderUniqueId = UID( "h1" ), msg = WS_( "x" ) } )
	end
	return #CHAT
end
local seq = {}
for _, s in ipairs( { 0, 1, 5, 10, 15, 30 } ) do seq[ #seq + 1 ] = whisper( s ) end
check( seq[ 1 ] == 1 and seq[ 5 ] == 1 and seq[ 6 ] == 2, "личка: 0 с — да, 1–15 с — нет, 30 с — да (" .. table.concat( seq, "," ) .. ")" )
check( whisper( 45, true ) == 2 and whisper( 61, true ) == 3, "исходящая личка: та же пауза" )
-- новый человек в личке — записан
EVENTS.EVENT_CHAT_MESSAGE( { chatType = 7, isEcho = false, sender = WS_( "Писатель" ), shard = WS_( "Нить судьбы" ), senderUniqueId = UID( "w1" ), msg = WS_( "x" ) } )
EVENTS.EVENT_CHAT_MESSAGE( { chatType = 7, isEcho = true, sender = WS_( "Я" ), recipient = WS_( "Адресат" ), recipientUniqueId = UID( "w2" ), msg = WS_( "x" ) } )
check( MC.DB.FindByUid( "0x7731" ) and MC.DB.FindByUid( "0x7732" ), "личка: входящая и исходящая записывают по ID" )
-- общий чат: с настройкой — записывает по ID, без неё — нет
MC.cfg.collectChat = false
EVENTS.EVENT_CHAT_MESSAGE( { chatType = 3, isEcho = false, sender = WS_( "Болтун" ), shard = WS_( "Нить судьбы" ), senderUniqueId = UID( "b9" ), msg = WS_( "x" ) } )
check( MC.DB.FindByUid( "0x6239" ) == nil, "общий чат без настройки: незнакомых не записывает" )
MC.cfg.collectChat = true
EVENTS.EVENT_CHAT_MESSAGE( { chatType = 3, isEcho = false, sender = WS_( "Болтун" ), shard = WS_( "Нить судьбы" ), senderUniqueId = UID( "b9" ), msg = WS_( "x" ) } )
local bl = MC.DB.FindByUid( "0x6239" )
-- автор рядом: из чата сразу гильдия, ранг, класс
UNITS[ 40 ] = { name = "Сосед", shard = "Нить судьбы", fac = "Империя", cls = "PRIEST", gs = 70000, guild = "Андромеда", rank = 4 }
EVENTS.EVENT_CHAT_MESSAGE( { chatType = 5, isEcho = false, sender = WS_( "Сосед" ), shard = WS_( "Нить судьбы" ), senderUniqueId = UID( "s4" ), senderId = 40, msg = WS_( "x" ) } )
local sos = MC.DB.FindByUid( "0x7334" )
check( sos and MC.DB.DictName( "guild", sos.g ) == "Андромеда" and sos.gr == 4 and sos.fac == 2 and sos.gs == 70000, "чат: автор рядом — гильдия, ранг, фракция, ГС" )
MC.DB.Delete( sos )
check( bl and bl.how == "c", "общий чат: писавший записан по ID" )
MC.DB.Delete( bl )

-- 5. Смена ника по ID
CHAT = {}
EVENTS.EVENT_CHAT_MESSAGE( { chatType = 3, isEcho = false, sender = WS_( "Бородач" ), shard = WS_( "Нить судьбы" ), senderUniqueId = UID( "h1" ), msg = WS_( "x" ) } )
check( r.name == "Бородач" and r.names and r.names[ 1 ].n == "Хмурыйпёс", "смена ника замечена (общий чат), история сохранена" )
check( chatHas( "сменил ник на \"Бородач\"" ), "смена ника: сообщение в чат" )
check( MC.DB.FindByName( "Бородач", r.sh ) == r and MC.DB.FindByName( "Хмурыйпёс", r.sh ) == nil, "индекс по нику обновлён" )

-- 6. Ручное добавление: хранится всегда, ID подтягивается при встрече
local man = MC.DB.AddManual( "Ксандр", "Нить судьбы" )
check( man.man and man.k:sub( 1, 1 ) == "N" and not man.uid, "вручную: запись по нику без ID" )
MC.DB.SetMark( man, -1 )
CHAT = {}
STATE.group = { { name = "Ксандр", uid = UID( "k9" ) } }
EVENTS.EVENT_GROUP_MEMBER_ADDED( {} ) second()
check( man.uid == "0x6b39" and man.k == "U0x6b39" and man.man, "вручную: ID подтянут из группы, запись осталась ручной" )
check( chatHas( "Игрок \"Ксандр\" помечен негативным" ), "вручную: предупреждение при первой встрече в группе" )
STATE.group = {}
EVENTS.EVENT_GROUP_MEMBER_REMOVED( {} ) second()

-- 7. Чужой ID под знакомым ником — другой человек, без ложного предупреждения
CHAT = {}
EVENTS.EVENT_CHAT_MESSAGE( { chatType = 7, isEcho = false, sender = WS_( "Ксандр" ), shard = WS_( "Нить судьбы" ), senderUniqueId = UID( "zz" ), msg = WS_( "x" ) } )
local other = MC.DB.FindByUid( "0x7a7a" )
check( other and other ~= man and other.mark == 0 and man.name == "Ксандр", "занятый ник: новая запись, старая не тронута" )
check( not chatHas( "помечен негативным" ), "занятый ник: предупреждения нет" )

-- 8. Гильдия: у согильдийца нет ID — по нику
CHAT = {}
local z = MC.DB.AddManual( "Злобоглаз", "Нить судьбы" )
MC.DB.SetMark( z, -1 )
EVENTS.EVENT_GUILD_MEMBER_ADDED( { name = WS_( "Злобоглаз" ) } )
check( chatHas( "Игрок \"Злобоглаз\" помечен негативным" ), "гильдия: предупреждение" )
EVENTS.EVENT_GUILD_MEMBER_ADDED( { name = WS_( "Злобоглаз" ) } )
check( #CHAT == 1, "гильдия: дубль события не повторяет" )

-- 9. Запись и загрузка: ID сохраняется, ренейм после перезахода
MC.DB.AddNote( z, "Кидает в рейдах" )
MC.DB.Flush()
local before = MC.DB.Count()
MC.DB.Load()
check( MC.DB.Count() == before, "загрузка: столько же записей (" .. before .. ")" )
local z2 = MC.DB.FindByName( "злобоглаз", MC.DB.DictId( "shard", "Нить судьбы" ) )
check( z2 and z2.mark == -1 and z2.man and z2.notes and z2.notes[ 1 ].t == "Кидает в рейдах", "загрузка: отметка, заметка, ручная" )
local b3 = MC.DB.FindByUid( "0x6831" )
check( b3 and b3.name == "Бородач" and b3.mark == -1 and b3.names[ 1 ].n == "Хмурыйпёс", "загрузка по ID с историей ников" )
EVENTS.EVENT_CHAT_MESSAGE( { chatType = 7, isEcho = false, sender = WS_( "Новыйник" ), shard = WS_( "Нить судьбы" ), senderUniqueId = UID( "h1" ), msg = WS_( "x" ) } )
check( b3.name == "Новыйник" and #b3.names == 2, "ренейм после перезахода пойман по ID" )

-- 10. Очистка: ручные и отмеченные остаются
local w1 = MC.DB.FindByUid( "0x7731" )
local m2 = MC.DB.AddManual( "Забытый", "Нить судьбы" )
DATE = { y = 2027, m = 6, d = 1, h = 10, min = 0 }
local removed = MC.DB.Cleanup( 90, 15000 )
check( MC.DB.FindByUid( "0x7731" ) == nil and MC.DB.FindByName( "Забытый", m2.sh ) == m2, "очистка: удалён старый нейтральный, ручной остался (" .. removed .. ")" )
check( MC.DB.FindByUid( "0x6831" ) ~= nil, "очистка: отмеченные остаются" )
DATE = { y = 2026, m = 11, d = 13, h = 22, min = 0 }

-- 11. Гильдия и ранг: текущие по последней встрече + история
UNITS[ 20 ] = { name = "Гильдиец", shard = "Нить судьбы", fac = "Лига", cls = "MAGE", gs = 0, guild = "Адреналин", rank = 4 }
STATE.group = { { name = "Гильдиец", uid = UID( "g1" ) } }
EVENTS.EVENT_GROUP_MEMBER_ADDED( {} ) second()
STATE.group = {}
EVENTS.EVENT_GROUP_MEMBER_REMOVED( {} ) second()
EVENTS.EVENT_UNITS_CHANGED( { spawned = { 20 } } )
local gr = MC.DB.FindByName( "Гильдиец", MC.DB.DictId( "shard", "Нить судьбы" ) )
check( gr and MC.DB.DictName( "guild", gr.g ) == "Адреналин" and gr.gr == 4 and not gr.gh, "гильдия и ранг записаны" )
DATE = { y = 2026, m = 11, d = 13, h = 23, min = 0 }
UNITS[ 20 ].rank = 2
EVENTS.EVENT_UNITS_CHANGED( { spawned = { 20 } } )
check( gr.gr == 2 and gr.gh and #gr.gh == 1 and gr.gh[ 1 ].rk == 4, "смена ранга — в истории" )
DATE = { y = 2026, m = 11, d = 14, h = 1, min = 0 }
UNITS[ 20 ].guild = nil
EVENTS.EVENT_UNITS_CHANGED( { spawned = { 20 } } )
check( gr.g == 0 and #gr.gh == 2 and gr.gh[ 1 ].g == "Адреналин", "вышел из гильдии — «без гильдии», история 2" )
MC.DB.Flush() MC.DB.Load()
local gr2 = MC.DB.FindByName( "Гильдиец", MC.DB.DictId( "shard", "Нить судьбы" ) )
check( gr2 and gr2.g == 0 and gr2.gh and #gr2.gh == 2, "гильдии переживают загрузку" )
MC.UI.ShowWindow( true ) MC.UI.OpenCard( gr2 )
check( FIND( "FGuildValue" ).val == "Без гильдии" and FIND( "FRankValue" ).val == "—" and FIND( "GuildsTitle" ).val == "Гильдии" and not FIND( "GuildsRow3" ).visible, "карточка: гильдия и история (" .. tostring( FIND( "GuildsTitle" ).val ) .. ")" )
check( FIND( "GuildsRow2" ):GetChildChecked( "GuildsText" ).val == "Адреналин" and FIND( "GuildsRow2" ):GetChildChecked( "GuildsRank" ).val == "Офицер", "история гильдий: название и ранг (" .. tostring( FIND( "GuildsRow2" ):GetChildChecked( "GuildsRank" ).val ) .. ")" )
check( FIND( "FUidValue" ).val == "6731", "карточка: ID без 0x (" .. tostring( FIND( "FUidValue" ).val ) .. ")" )
MC.UI.CloseCard() MC.UI.ShowWindow( false )
b3 = MC.DB.FindByUid( "0x6831" )
DATE = { y = 2026, m = 11, d = 13, h = 22, min = 0 }

-- 12. Цель: незнакомого игрока кнопка добавляет по нику
UNITS[ 30 ] = { name = "Целевой", shard = "Нить судьбы", fac = "Империя", cls = "BARD", gs = 50000 }
STATE.target = 30
MC.UI.ShowWindow( true )
click( "mc_target", "TargetBtn" )
local tg = MC.DB.FindByName( "Целевой", MC.DB.DictId( "shard", "Нить судьбы" ) )
check( tg and tg.man and tg.gs == 50000 and FIND( "CardNick" ).val == "Целевой", "цель: добавлен вручную, карточка открыта" )
MC.UI.CloseCard() MC.UI.ShowWindow( false )
STATE.target = nil

-- 13. Интерфейс: окно, фильтры, повторный клик, сброс, прокрутка
for i = 1, 40 do
	EVENTS.EVENT_CHAT_MESSAGE( { chatType = 7, isEcho = false, sender = WS_( "Игрок" .. i ), shard = WS_( "Нить судьбы" ), senderUniqueId = UID( "p" .. i ), msg = WS_( "x" ) } )
end
MC.UI.ShowWindow( true )
check( FIND( "MainWindow" ).visible, "окно открыто" )
check( FIND( "Row1" ).visible and FIND( "Row16" ).visible, "список: 16 строк видны" )
click( "mc_filter", "FNeg" )
check( FIND( "Row3" ).visible and not FIND( "Row4" ).visible, "фильтр «Отрицательные»: 3 строки" )
check( FIND( "FReset" ).enabled == true, "«Сброс» включена" )
click( "mc_filter", "FNeg" )
check( FIND( "Row16" ).visible, "повторный клик снимает фильтр" )
click( "mc_filter", "FNotes" ) click( "mc_reset", "FReset" )
check( FIND( "Row16" ).visible and FIND( "FReset" ).enabled == false, "«Сброс» снял фильтры и выключилась" )
REACTIONS.mc_list_down( { widget = FIND( "ListBox" ) } )
local thumb = FIND( "ScrollThumb" ).pl
check( thumb.posY > 0 and thumb.posY < 100, "колесо: 3 строки, ползунок сдвинулся на " .. thumb.posY )
-- поиск по прежнему нику
FIND( "SearchEdit" ).text = "хмурый"
REACTIONS.mc_search_changed( {} )
check( FIND( "Row1" ).visible and not FIND( "Row2" ).visible and FIND( "RowRen" ).visible, "поиск по прежнему нику, значок ренейма" )
-- карточка
click( "mc_row", "Row1" )
check( FIND( "CardWindow" ).visible and FIND( "CardNick" ).val == "Новыйник", "карточка открыта" )
print( "  карточка: " .. tostring( FIND( "CardInfo" ).val ) .. " | UID " .. tostring( FIND( "FUidValue" ).val ) )
click( "mc_note_add", "NoteAdd" )
FIND( "EdEdit" ).text = "Сливает лут"
REACTIONS.mc_ed_changed( {} )
click( "mc_ed_save", "EdSave" )
check( b3.notes and #b3.notes == 1 and b3.notes[ 1 ].t == "Сливает лут", "заметка добавлена" )
click( "mc_card_mark", "CardMarkPos" )
check( b3.mark == 1, "отметка из карточки" )
-- пустой поиск -> добавить вручную
FIND( "SearchEdit" ).text = "Незнакомец"
REACTIONS.mc_search_changed( {} )
check( FIND( "EmptyAdd" ).visible, "не найдено: «Добавить вручную»" )
click( "mc_empty_add", "EmptyAdd" )
check( MC.DB.FindByName( "Незнакомец", MC.DB.DictId( "shard", "Нить судьбы" ) ) ~= nil, "добавлен вручную" )
-- настройки
click( "mc_gear", "HdrGear" )
check( FIND( "SettingsPage" ).visible and not FIND( "MainPage" ).visible, "настройки открыты" )
local stepPlus = FIND( "SetStep1" ):GetChildChecked( "StepBox" ):GetChildChecked( "StepPlus" )
REACTIONS.mc_step_plus( { widget = stepPlus } )
check( MC.cfg.pause == 35, "пауза +5 с" )
print( "  статистика: " .. tostring( FIND( "SetStats" ).val ) )
if MC.Probe then
	-- отладочная сборка: команда включает отладку, пробы не падают (упадут — тест остановится с ошибкой)
	VERBOSE = true
	EVENTS.EVENT_UNKNOWN_SLASH_COMMAND( { text = WS_( "/mc debug" ) } )
	VERBOSE = false
	check( MC.DEBUG == true, "отладка включена командой" )
	for i = 1, 7 do
		MC.Probe.Chat( { chatType = 3, isEcho = false, sender = WS_( "Отлад" .. i ), shard = WS_( "Нить судьбы" ),
			senderUniqueId = UID( "d" .. i ), msg = WS_( "x" ) } )
	end
	MC.Probe.Report()
	check( true, "отладка: Probe.Chat и Probe.Report без ошибок" )
else
	EVENTS.EVENT_UNKNOWN_SLASH_COMMAND( { text = WS_( "/mc debug" ) } )
	check( MC.DEBUG == nil and MC.Log == nil and MC.File == nil, "обычная сборка: отладки нет, /mc debug ничего не делает" )
end
second( 60 )
check( not MC.DB.IsDirty(), "раз в минуту база записывается" )
-- очистка всей базы кнопкой (настройки уже открыты)
MC.UI.Render()
check( FIND( "SettingsPage" ).visible, "настройки всё ещё открыты" )
check( FIND( "SetWipe" ).enabled == true, "«Очистить базу» включена" )
click( "mc_wipe", "SetWipe" )
check( FIND( "Confirm" ).visible, "очистка базы: подтверждение" )
click( "mc_cf_ok", "CfOk" )
check( MC.DB.Count() == 0 and CONFIG.MyContacts_Cards == nil and CONFIG.MyContacts_Meta.v == 2, "очистка базы: всё удалено" )
check( FIND( "SetWipe" ).enabled == false, "«Очистить базу» выключилась" )
MC.DB.Load()
check( MC.DB.Count() == 0, "после очистки загрузка пустая" )

-- 14. Карточка: эмблема текущего класса слева от строки сведений
local SH = "Нить судьбы"
local function meet( id, name, uid, cls )
	UNITS[ id ] = { name = name, shard = SH, fac = "Лига", cls = cls, gs = 30000 }
	STATE.group = { { name = name, uid = UID( uid ) } }
	EVENTS.EVENT_GROUP_MEMBER_ADDED( {} ) second()
	STATE.group = {}
	EVENTS.EVENT_GROUP_MEMBER_REMOVED( {} ) second()
	EVENTS.EVENT_UNITS_CHANGED( { spawned = { id } } )
	return MC.DB.FindByName( name, MC.DB.DictId( "shard", SH ) )
end
local cm = meet( 50, "Классный", "c1", "MAGE" )
MC.UI.OpenCard( cm )
check( cm and FIND( "ClsSlot1" ).visible and FIND( "ClsSlot1" ).tex == "tex:CLS_MAGE", "карточка: эмблема текущего класса (" .. tostring( FIND( "ClsSlot1" ).tex ) .. ")" )
check( FIND( "CardInfo" ).pl.posX == 46 and string.find( FIND( "CardInfo" ).val, "Маг", 1, true ), "карточка: сведения сдвинуты за эмблему, класс назван текстом" )
local noCls = MC.DB.AddManual( "Бесклассовый", SH )
MC.UI.OpenCard( noCls )
check( not FIND( "ClsSlot1" ).visible and FIND( "CardInfo" ).pl.posX == 12, "карточка: класс неизвестен — эмблемы нет, сведения на месте" )
local odd = meet( 51, "Новичок", "c2", "SOMENEWCLASS" )
MC.UI.OpenCard( odd )
check( not FIND( "ClsSlot1" ).visible and string.find( FIND( "CardInfo" ).val, "SOMENEWCLASS", 1, true ), "карточка: класс без эмблемы остаётся текстом" )
MC.UI.CloseCard()

print( fails == 0 and "ВСЁ ОК" or ( "ОШИБОК: " .. fails ) )
os.exit( fails == 0 and 0 or 1 )   -- код выхода — для test/run.sh и проверок на GitHub

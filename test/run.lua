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
-- сколько записей в mods.txt, начиная с номера from, содержат все перечисленные подстроки
local function logCount( from, ... )
	local n = 0
	for i = from, #LOG do
		local ok = true
		for _, s in ipairs( { ... } ) do ok = ok and string.find( LOG[ i ], s, 1, true ) ~= nil end
		if ok then n = n + 1 end
	end
	return n
end

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

	-- Команда /mc rating: полный ответ игры про себя и про цель; сама по себе отладка рейтинг в журнал не пишет
	local season = { over_game = 40, wins = 25, score = 1500, top = 12, timeSpentMs = 3600000, difficulty = { name = WS_( "Золото" ) } }
	check( logCount( 1, "IsRatingPvPScoreAvailable -> true", "3x3=0", "6x6=1", "HPI=2" ) >= 1, "рейтинг: отчёт о доступности и перечислении" )
	UNITS[ 50 ] = { name = "Аренщик", shard = "Нить судьбы", fac = "Империя", cls = "MAGE", gs = 0 }
	RATING[ 50 ] = { [ ENUM_RatingArenaType_3x3 ] = { currentSeason = season, extra = 7 }, [ ENUM_RatingArenaType_6x6 ] = false }
	local from, calls = #LOG + 1, RATING_CALLS
	STATE.target, STATE.inspect = 50, 50
	EVENTS.EVENT_AVATAR_TARGET_CHANGED( {} )
	EVENTS.EVENT_INSPECT_STARTED( {} )
	EVENTS.EVENT_UNITS_CHANGED( { spawned = { 50 }, despawned = {} } )
	second( 10 )
	check( RATING_CALLS == calls and logCount( from, "рейтинг" ) == 0, "рейтинг: цель, осмотр и незнакомый игрок рядом — без запросов и записей в журнал" )
	STATE.inspect = nil
	CHAT = {}
	EVENTS.EVENT_UNKNOWN_SLASH_COMMAND( { text = WS_( "/mc rating" ) } )
	check( logCount( from, "рейтинг [я сам] ник=Я" ) == 1 and logCount( from, "рейтинг [цель] ник=Аренщик" ) == 1 and chatHas( "mods.txt" ),
		"рейтинг: команда /mc rating — я и цель" )
	check( logCount( from, "3x3 (тип=0): currentSeason={ over_game=40 wins=25 score=1500 top=12 timeSpentMs=3600000 difficulty=W\"Золото\" }" ) == 1,
		"рейтинг: все поля текущего сезона" )
	check( logCount( from, "lastSeason=nil" ) == 3 and logCount( from, "6x6 (тип=1): nil" ) == 1 and logCount( from, "(нет в документации) extra=7" ) == 1
		and logCount( from, "currentSeason={ over_game=0 wins=0 score=0 top=0 timeSpentMs=0 difficulty=nil }" ) == 2,
		"рейтинг: nil для сезона и арены, сезон с нулями, лишнее поле отмечено" )
	second( 10 )
	check( logCount( from, "рейтинг [" ) == 2, "рейтинг: повторов через 3 и 10 с больше нет" )
	-- без цели — запись об этом
	from = #LOG + 1
	STATE.target = nil
	EVENTS.EVENT_UNKNOWN_SLASH_COMMAND( { text = WS_( "/mc rating" ) } )
	check( logCount( from, "рейтинг [цель]: в цели нет другого игрока" ) == 1, "рейтинг: команда без цели" )
	-- рейтинг недоступен (часть активностей): функция не вызывается (иначе заглушка остановит тест), в журнале — «false»
	from, calls = #LOG + 1, RATING_CALLS
	STATE.ratingAvailable = false
	STATE.target = 50
	EVENTS.EVENT_UNKNOWN_SLASH_COMMAND( { text = WS_( "/mc rating" ) } )
	check( RATING_CALLS == calls and logCount( from, "IsRatingPvPScoreAvailable=false" ) == 2, "рейтинг: «недоступно» — команда без запроса" )
	STATE.ratingAvailable = true
	-- выключенная отладка: ни запросов, ни записей
	MC.DEBUG = false
	from, calls, CHAT = #LOG + 1, RATING_CALLS, {}
	EVENTS.EVENT_UNKNOWN_SLASH_COMMAND( { text = WS_( "/mc rating" ) } )
	check( RATING_CALLS == calls and #LOG == from - 1 and chatHas( "/mc debug" ), "рейтинг: при выключенной отладке команда ничего не запрашивает" )
	MC.DEBUG = true
	STATE.target = nil
	UNITS[ 50 ], RATING[ 50 ] = nil, nil
else
	EVENTS.EVENT_UNKNOWN_SLASH_COMMAND( { text = WS_( "/mc debug" ) } )
	check( MC.DEBUG == nil and MC.Log == nil and MC.File == nil, "обычная сборка: отладки нет, /mc debug ничего не делает" )
	-- обычная сборка команду /mc rating не знает; незнакомого игрока рядом и в цели не запрашивает
	UNITS[ 50 ] = { name = "Аренщик", shard = "Нить судьбы", fac = "Империя", cls = "MAGE", gs = 0 }
	local calls = RATING_CALLS
	STATE.target, STATE.inspect = 50, 50
	EVENTS.EVENT_AVATAR_TARGET_CHANGED( {} )
	EVENTS.EVENT_INSPECT_STARTED( {} )
	EVENTS.EVENT_UNITS_CHANGED( { spawned = { 50 }, despawned = {} } )
	EVENTS.EVENT_UNKNOWN_SLASH_COMMAND( { text = WS_( "/mc rating" ) } )
	second( 10 )
	check( RATING_CALLS == calls and #LOG == 0, "обычная сборка: команды /mc rating нет, в mods.txt пусто" )
	STATE.target, STATE.inspect = nil, nil
	UNITS[ 50 ] = nil
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

-- 15. Пул классов: копится по ID, без повторов, хранится в хвосте записи, старая база читается как есть
local hour = 22
local function reclass( cls )
	hour = hour + 1
	DATE = { y = 2026, m = 11, d = 14 + math.floor( hour / 24 ), h = hour % 24, min = 0 }
	UNITS[ 50 ].cls = cls
	EVENTS.EVENT_UNITS_CHANGED( { spawned = { 50 } } )
	return table.concat( MC.DB.Classes( cm ), "," )
end
local function stored( key )
	for name, chunk in pairs( CONFIG ) do
		if string.find( name, "^MyContacts_DB_" ) and chunk[ key ] then return chunk[ key ], name end
	end
end
local function fields( s ) return select( 2, string.gsub( s, "|", "" ) ) + 1 end
check( table.concat( MC.DB.Classes( cm ), "," ) == "Маг" and cm.cp == nil, "пул классов: один класс — списка прежних нет" )
check( reclass( "DRUID" ) == "Друид,Маг", "пул классов: смена класса — прежний остаётся в пуле" )
check( reclass( "DRUID" ) == "Друид,Маг", "пул классов: тот же класс повторно ничего не меняет" )
check( reclass( "MAGE" ) == "Маг,Друид", "пул классов: возврат к прежнему — без повторов" )
check( reclass( "WARRIOR" ) == "Воин,Маг,Друид", "пул классов: третий класс, недавние первыми" )
MC.DB.Flush()
local packed = stored( "U0x6331" )
local ids = MC.DB.DictId( "cls", "Маг" ) .. "," .. MC.DB.DictId( "cls", "Друид" )
check( packed and fields( packed ) == 16 and string.sub( packed, -( #ids + 3 ) ) == "|c=" .. ids, "пул классов: прежние классы — в хвосте записи (" .. tostring( packed ) .. ")" )
check( fields( stored( odd.k ) ) == 15, "пул классов: у игрока с одним классом запись не выросла" )
MC.DB.Load()
cm = MC.DB.FindByUid( "0x6331" )
check( cm and table.concat( MC.DB.Classes( cm ), "," ) == "Воин,Маг,Друид", "пул классов переживает загрузку" )
MC.UI.OpenCard( cm )
check( FIND( "ClsSlot1" ).tex == "tex:CLS_WARRIOR" and FIND( "ClsSlot1" ).fade == 1 and FIND( "ClsSlot2" ).tex == "tex:CLS_MAGE"
	and FIND( "ClsSlot2" ).fade == 0.45 and FIND( "ClsSlot3" ).tex == "tex:CLS_DRUID" and FIND( "ClsSlot3" ).visible
	and not FIND( "ClsSlot4" ).visible, "карточка: ряд эмблем — текущий класс первым, прежние приглушены" )
check( FIND( "CardInfo" ).pl.posX == 12 + 3 * 30 + 4, "карточка: сведения сдвинуты за три эмблемы" )
MC.UI.CloseCard()
-- запись из более новой версии: незнакомые поля хвоста не теряются при перезаписи
local _, chunkName = stored( "U0x6331" )
CONFIG[ chunkName ][ "U0x6331" ] = packed .. "|q9=1850|zz=x,y"
MC.DB.Load()
cm = MC.DB.FindByUid( "0x6331" )
MC.DB.SetMark( cm, 1 )
MC.DB.Flush()
local again = stored( "U0x6331" )
check( string.find( again, "|c=" .. ids .. "|q9=1850|zz=x,y", 1, true ) ~= nil, "хвост записи: незнакомые поля сохранены как были (" .. again .. ")" )
-- база от версии 0.9.2 (15 полей, без хвоста): формат тот же, ничего не очищается и не теряется
local total = MC.DB.Count()
CONFIG[ chunkName ][ "U0x6331" ] = string.match( again, "^(.-)|c=" )
MC.DB.Load()
cm = MC.DB.FindByUid( "0x6331" )
check( CONFIG.MyContacts_Meta.v == 2 and MC.DB.Count() == total and cm and cm.mark == 1 and cm.name == "Классный" and cm.gs == 30000
	and table.concat( MC.DB.Classes( cm ), "," ) == "Воин" and cm.cp == nil and cm.ext == nil, "старая база (0.9.2) читается без очистки и потерь" )
check( reclass( "BARD" ) == "Бард,Воин", "старая запись: пул начинает копиться со следующей смены класса" )
DATE = { y = 2026, m = 11, d = 13, h = 22, min = 0 }

-- 16. Заметки: блок по высоте текста, заметка в 300 знаков целиком, многострочный ввод
check( MC.LineCount( "Сливает лут", 224 ) == 1 and MC.LineCount( "", 224 ) == 1, "расчёт строк: короткий текст — одна строка" )
check( MC.LineCount( "фывафлыовадфлываодф", 188 ) == 2 and MC.LineCount( "фывафлыовадфлываод", 188 ) == 1,
	"расчёт строк: как на снимке экрана — 18 широких букв в 188 px, 19-я переносится" )
check( MC.LineCount( "раз два три", 60 ) == 2 and MC.LineCount( string.rep( "Щ", 300 ), 480 ) == 10,
	"расчёт строк: перенос по словам; 300 самых широких букв — 10 строк поля ввода" )
local nt = MC.DB.AddManual( "Заметочник", SH )
MC.UI.OpenCard( nt )
local function typeNote( text )
	click( "mc_note_add", "NoteAdd" )
	FIND( "EdEdit" ).text = text
	REACTIONS.mc_ed_changed( {} )
	local counter = FIND( "EdCount" ).val
	click( "mc_ed_save", "EdSave" )
	return counter
end
local function card( i ) return FIND( "NoteCard" .. i ) end
local long = string.rep( "Кидает группу посреди подземелья и забирает вещи. ", 6 )
long = string.sub( long, 1, #long - 1 ) .. "!"       -- ровно 300 знаков
check( MC.CharLen( long ) == 300, "заметка: проверочный текст — 300 знаков" )
check( typeNote( long ) == "300 / 300" and not FIND( "EditorLayer" ).visible, "ввод: счётчик 300 / 300, заметка сохранена" )
check( nt.notes and #nt.notes == 1 and nt.notes[ 1 ].t == long, "заметка в 300 знаков сохранена целиком" )
local lines = MC.LineCount( long, 224 )
local c1 = card( 1 )
check( lines >= 10 and lines <= 14 and c1.visible and c1.pl.posY == 200 and c1.pl.sizeY == lines * 19 + 40,
	"заметка в 300 знаков: блок вырос под текст (" .. lines .. " строк, " .. c1.pl.sizeY .. " px)" )
check( c1:GetChildChecked( "NoteText" ).val == long and c1:GetChildChecked( "NoteText" ).pl.sizeY == lines * 19 + 4,
	"заметка в 300 знаков: текст показан целиком, высота текста по числу строк" )
check( MC.LineCount( string.rep( "Щ", 300 ), 224 ) * 19 + 40 > 432, "проверка запаса: 300 широких букв упираются в высоту области" )
typeNote( string.rep( "Щ", 300 ) )
check( card( 1 ).pl.sizeY == 432 and card( 1 ):GetChildChecked( "NoteText" ).pl.sizeY == 396 and not card( 2 ).visible,
	"самая широкая заметка: блок на всю область (текст 396 px при нужных 342), следующая — прокруткой" )
MC.DB.DelNote( nt, 1 )
check( typeNote( "строка один\r\nстрока два" ) == "22 / 300" and nt.notes[ 1 ].t == "строка один строка два", "ввод: перевод строки из буфера — пробел" )
check( card( 1 ).pl.sizeY == 59 and card( 2 ).visible and card( 2 ).pl.posY == 200 + 59 + 8 and card( 2 ).pl.sizeY == lines * 19 + 40,
	"короткая заметка — блок в одну строку, длинная под ней" )
for i = 1, 7 do typeNote( "заметка " .. i ) end
-- 9 заметок: 8 коротких (59 + 8 px) и длинная в конце; в область входит 6 коротких
check( card( 6 ).visible and FIND( "NotesMore" ).visible and FIND( "NotesMore" ).val == "ещё 3 — прокрутите колесом", "заметки: в область входит шесть коротких, остальные — прокруткой" )
for _ = 1, 20 do REACTIONS.mc_notes_down( {} ) end
local last
for i = 1, 6 do if card( i ).visible then last = card( i ) end end
check( last:GetChildChecked( "NoteText" ).val == long and last.pl.posY + last.pl.sizeY <= 200 + 432 and not FIND( "NotesMore" ).visible,
	"заметки: прокрутка доходит до последней, длинная заметка видна целиком" )
for _ = 1, 20 do REACTIONS.mc_notes_up( {} ) end
check( card( 1 ):GetChildChecked( "NoteText" ).val == "заметка 7" and card( 1 ).pl.posY == 200, "заметки: прокрутка вверх возвращает к началу" )
-- правка: изменённая заметка меняет высоту блока
click( "mc_note_edit", "NoteCard1" )
check( FIND( "EdEdit" ).text == "заметка 7", "правка: в поле ввода — текст заметки" )
FIND( "EdEdit" ).text = long
REACTIONS.mc_ed_changed( {} )
click( "mc_ed_save", "EdSave" )
check( nt.notes[ 1 ].t == long and nt.notes[ 1 ].e and card( 1 ).pl.sizeY == lines * 19 + 40 and string.find( card( 1 ):GetChildChecked( "NoteDate" ).val, "изм.", 1, true ),
	"правка: блок вырос под новый текст, дата с пометкой об изменении" )
MC.UI.CloseCard()

-- 17. Рейтинг арен 3х3 и 6х6: читается при встрече у известного игрока, хранится в хвосте записи, виден в карточке
local A3, A6 = ENUM_RatingArenaType_3x3, ENUM_RatingArenaType_6x6
local function games( score, top, played, wins )
	return { currentSeason = { over_game = played, wins = wins, score = score, top = top, timeSpentMs = 0 } }
end
local function same( a, score, top, played, wins ) return a ~= nil and a.s == score and a.t == top and a.g == played and a.w == wins end
-- время в минутах от полудня 20.11.2026; встреча рядом перечитывает игрока не чаще раза в 10 минут
local function clock( min )
	local m = 720 + min
	DATE = { y = 2026, m = 11, d = 20 + math.floor( m / 1440 ), h = math.floor( m % 1440 / 60 ), min = m % 60 }
	return MC.NowMin()
end
local function see( min )
	local now = clock( min )
	EVENTS.EVENT_UNITS_CHANGED( { spawned = { 60 } } )
	return now
end
local T0 = clock( 0 )
-- незнакомый игрок рядом: записи нет и запроса нет
UNITS[ 60 ] = { name = "Аренщик", shard = SH, fac = "Лига", cls = "MAGE", gs = 30000 }
RATING[ 60 ] = { [ A3 ] = games( 987, 312, 40, 25 ) }
local calls = RATING_CALLS
EVENTS.EVENT_UNITS_CHANGED( { spawned = { 60 } } )
check( MC.DB.FindByName( "Аренщик", MC.DB.DictId( "shard", SH ) ) == nil and RATING_CALLS == calls, "рейтинг: незнакомого рядом не записывает и не запрашивает" )
-- известный (был в группе): при встрече рядом рейтинг записан; арена без игр (нули) не хранится
local logFrom = #LOG + 1
local ar = meet( 60, "Аренщик", "a1", "MAGE" )
check( ar and same( ar.a3, 987, 312, 40, 25 ) and ar.a3.at == T0 and ar.a6 == nil, "рейтинг: записан при встрече известного игрока, момент чтения — время встречи" )
check( RATING_CALLS == calls + 2, "рейтинг: по одному запросу на арену (" .. ( RATING_CALLS - calls ) .. ")" )
if MC.Probe then
	check( logCount( logFrom, "рейтинг арены a3 изменился: Аренщик", "было: нет стало: счёт 987, место 312, игр 40, побед 25" ) == 1
		and logCount( logFrom, "рейтинг арены" ) == 1, "рейтинг: изменение записано в журнал одной строкой" )
end
MC.DB.Flush()
local line = stored( ar.k )
print( "  запись с рейтингом: " .. tostring( line ) )
check( fields( line ) == 16 and string.sub( line, -#( "|a3=987,312,40,25," .. T0 ) ) == "|a3=987,312,40,25," .. T0, "рейтинг: хранится в хвосте записи — счёт, место, игры, победы, момент" )
-- те же числа: база не помечается изменённой, момент чтения прежний
logFrom = #LOG + 1
local info = { name = "Аренщик", shard = SH, noSeen = true, a3 = { s = 987, t = 312, g = 40, w = 25 }, a6 = { s = 0, t = 0, g = 0, w = 0 } }
MC.DB.Touch( info, T0 + 5 )
check( not MC.DB.IsDirty() and ar.a3.at == T0, "рейтинг: повторная встреча с теми же числами не помечает базу изменённой" )
STATE.target = 60
MC.Game.TargetRecord() MC.DB.Flush()      -- первая встреча «в цели» меняет вид встречи, вторая уже ничего не меняет
calls = RATING_CALLS
MC.Game.TargetRecord()
check( RATING_CALLS == calls + 2 and not MC.DB.IsDirty() and ar.a3.at == T0, "рейтинг: перечитан с теми же числами — база не тронута" )
STATE.target = nil
see( 15 )
check( ar.a3.at == T0, "рейтинг: при тех же числах момент чтения не обновляется при каждой встрече" )
MC.DB.Flush()
MC.DB.Touch( info, T0 + 1439 )
check( not MC.DB.IsDirty() and ar.a3.at == T0, "рейтинг: те же числа меньше суток спустя — момент прежний" )
MC.DB.Touch( info, T0 + 1440 )
check( MC.DB.IsDirty() and ar.a3.at == T0 + 1440 and same( ar.a3, 987, 312, 40, 25 ), "рейтинг: те же числа через сутки — момент чтения обновлён" )
check( logCount( logFrom, "рейтинг арены" ) == 0, "рейтинг: без изменения чисел в журнал ничего не пишется" )
-- числа изменились (место меняется и без игр): новое значение и новый момент
RATING[ 60 ][ A3 ] = games( 987, 298, 40, 25 )
RATING[ 60 ][ A6 ] = games( 1432, 1205, 150, 80 )
local T2 = see( 3000 )
check( same( ar.a3, 987, 298, 40, 25 ) and ar.a3.at == T2 and same( ar.a6, 1432, 1205, 150, 80 ) and ar.a6.at == T2, "рейтинг: изменившиеся числа записаны с новым моментом" )
if MC.Probe then
	check( logCount( logFrom, "рейтинг арены a3 изменился: Аренщик", "было: счёт 987, место 312, игр 40, побед 25 стало: счёт 987, место 298, игр 40, побед 25" ) == 1
		and logCount( logFrom, "рейтинг арены a6 изменился" ) == 1, "рейтинг: в журнале — что было и что стало" )
end
-- рейтинг недоступен (часть активностей): запроса нет (иначе заглушка остановит тест), прежнее значение остаётся
RATING[ 60 ][ A3 ] = games( 1, 2, 3, 4 )
STATE.ratingAvailable = false
calls = RATING_CALLS
see( 3020 )
check( RATING_CALLS == calls and same( ar.a3, 987, 298, 40, 25 ) and same( ar.a6, 1432, 1205, 150, 80 ) and ar.seen == T2 + 20,
	"рейтинг: «недоступно» — запроса нет, прежнее значение сохранено, встреча записана" )
STATE.ratingAvailable = true
-- игра вернула nil: прежнее значение остаётся
RATING[ 60 ] = false
calls = RATING_CALLS
see( 3040 )
check( RATING_CALLS == calls + 2 and same( ar.a3, 987, 298, 40, 25 ) and same( ar.a6, 1432, 1205, 150, 80 ), "рейтинг: ответ nil — прежнее значение сохранено" )
RATING[ 60 ] = { [ A3 ] = false, [ A6 ] = games( 1440, 1190, 151, 81 ) }
see( 3060 )
check( same( ar.a3, 987, 298, 40, 25 ) and same( ar.a6, 1440, 1190, 151, 81 ), "рейтинг: nil по одной арене не мешает записать другую" )
-- запись и загрузка; незнакомые поля хвоста по-прежнему сохраняются
MC.DB.Flush()
line = stored( ar.k )
check( fields( line ) == 17 and string.find( line, "|a3=987,298,40,25," .. T2 .. "|a6=1440,1190,151,81," .. ( T2 + 60 ), 1, true ) ~= nil, "рейтинг: обе арены в хвосте записи (" .. tostring( line ) .. ")" )
local _, arChunk = stored( ar.k )
CONFIG[ arChunk ][ ar.k ] = line .. "|q9=1850"
MC.DB.Load()
ar = MC.DB.FindByUid( "0x6131" )
check( ar and same( ar.a3, 987, 298, 40, 25 ) and ar.a3.at == T2 and same( ar.a6, 1440, 1190, 151, 81 ) and ar.a6.at == T2 + 60
	and ar.ext and ar.ext[ 1 ] == "q9=1850", "рейтинг переживает загрузку базы, незнакомое поле сохранено" )
-- карточка: «<арена> <счёт> #<место> <побед>/<игр>(<доля побед>%)», даты нет
MC.UI.OpenCard( ar )
local function arenaRow( name ) return FIND( name .. "Label" ).val, FIND( name .. "Score" ).val, FIND( name .. "Info" ).val end
local l3, s3, i3 = arenaRow( "FA3" )
local l6, s6, i6 = arenaRow( "FA6" )
print( "  карточка: " .. table.concat( { l3, s3, i3 }, " | " ) .. "  //  " .. table.concat( { l6, s6, i6 }, " | " ) )
check( l3 == "3х3" and s3 == "987" and i3 == "#298 25/40(63%)", "карточка: рейтинг 3х3 — счёт, #место, победы/игры(доля побед)" )
check( l6 == "6х6" and s6 == "1 440" and i6 == "#1190 81/151(54%)", "карточка: рейтинг 6х6 — большие числа" )
-- новый сезон: пришли нули — прежний рейтинг убран, в карточке «нет данных»
RATING[ 60 ] = { [ A3 ] = games( 0, 0, 0, 0 ) }
see( 3080 )
check( ar.a3 == nil and ar.a6 == nil and MC.DB.IsDirty(), "рейтинг: нули стирают прежнее значение" )
second()
l3, s3, i3 = arenaRow( "FA3" )
check( s3 == "—" and i3 == "нет данных" and FIND( "FA6Info" ).val == "нет данных" and FIND( "FA6Label" ).val == "6х6",
	"карточка: рейтинга нет — «нет данных», строки на месте" )
MC.UI.CloseCard()
MC.DB.Flush()
line = stored( ar.k )
check( fields( line ) == 16 and string.find( line, "a3=", 1, true ) == nil and string.find( line, "a6=", 1, true ) == nil
	and string.sub( line, -8 ) == "|q9=1850", "рейтинг: без игр запись не растёт (" .. tostring( line ) .. ")" )
-- запись версии 0.9.4 (без ключей рейтинга, с хвостом классов) читается без потерь и дополняется при встрече
CONFIG[ arChunk ][ ar.k ] = "Аренщик|1|1|" .. T0 .. "|0|g|30000|" .. T0 .. "|0x6131|" .. MC.DB.DictId( "cls", "Маг" ) .. "|" .. T0 .. "|0|0|" .. T0 .. "||c=" .. MC.DB.DictId( "cls", "Друид" )
local total = MC.DB.Count()
MC.DB.Load()
ar = MC.DB.FindByUid( "0x6131" )
check( MC.DB.Count() == total and ar and ar.name == "Аренщик" and ar.gs == 30000 and ar.seen == T0 and ar.a3 == nil and ar.a6 == nil and ar.ext == nil
	and table.concat( MC.DB.Classes( ar ), "," ) == "Маг,Друид", "запись 0.9.4 без рейтинга читается без потерь" )
MC.DB.SetMark( ar, 1 ) MC.DB.SetMark( ar, 0 )
MC.DB.Flush()
check( stored( ar.k ) == "Аренщик|1|1|" .. T0 .. "|0|g|30000|" .. T0 .. "|0x6131|" .. MC.DB.DictId( "cls", "Маг" ) .. "|" .. T0 .. "|0|0|" .. T0 .. "||c=" .. MC.DB.DictId( "cls", "Друид" ),
	"запись 0.9.4: после перезаписи строка та же, лишних полей нет" )
RATING[ 60 ] = { [ A6 ] = games( 15, 0, 1, 0 ) }
see( 3100 )
MC.UI.OpenCard( ar )
check( same( ar.a6, 15, 0, 1, 0 ) and ar.a3 == nil and FIND( "FA6Info" ).val == "#— 0/1(0%)" and FIND( "FA6Score" ).val == "15",
	"запись 0.9.4: рейтинг дописан при встрече; места ещё нет — прочерк" )
MC.UI.CloseCard()
UNITS[ 60 ], RATING[ 60 ] = nil, nil
DATE = { y = 2026, m = 11, d = 13, h = 22, min = 0 }

print( fails == 0 and "ВСЁ ОК" or ( "ОШИБОК: " .. fails ) )
os.exit( fails == 0 and 0 or 1 )   -- код выхода — для test/run.sh и проверок на GitHub

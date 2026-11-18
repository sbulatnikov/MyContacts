--------------------------------------------------------------------------------
-- MyContacts / UI.lua
-- Кнопка на экране, главное окно (поиск, фильтры, список), карточка игрока,
-- редактор заметки, подтверждения, настройки, подсказки.
-- Список — пул из 16 строк: виджеты не создаются и не удаляются, у строк нет наведения.
--------------------------------------------------------------------------------
MC.UI = {}
local UI = MC.UI
local DB = MC.DB
local W, Child, Show, Enable, Fade, SetText, SetVariant, SetTex = MC.W, MC.Child, MC.Show, MC.Enable, MC.Fade, MC.SetText,
	MC.SetVariant, MC.SetTex
local S, WS = MC.S, MC.WS

local ui = {}
UI.ui = ui
UI.view = "main"

local ROWS, ROW_H, WHEEL_ROWS = 16, 28, 3
local NAME_ROWS = 4         -- строк в «Ники»: первая — текущий, остальные — история
local GUILD_ROWS = 5        -- строк в «Гильдии» (название слева, ранг справа): первая — текущая
local TRACK_H = 450
-- эмблемы классов в карточке (размеры — как в gen/build.py): первая — текущий класс
local CLS_SLOTS = 1
local CLS_X, CLS_STEP, CLS_GAP = 12, 30, 4
local CARD_W = 600

local filt = { neu = false, neg = false, pos = false, notes = false, recent = false }
local search, searchL = "", ""
local items = {}
local counts = { neu = 0, neg = 0, pos = 0 }
local offset = 0
local selected = nil
local listDirty = true
local builtVersion = -1
local menuRec = nil
local cardRec = nil
local cardDirty = false
local notesOff = 0
local namesOff, guildsOff = 0, 0
local editor = nil          -- { mode = "add" | "edit", index, orig }
local confirm = nil         -- { ok = function }
local lowerCache = setmetatable( {}, { __mode = "k" } )

local MARK_KEY = { [ 0 ] = "NEU", [ 1 ] = "POS", [ -1 ] = "NEG" }
local FAC_NAME = { [ 1 ] = "Лига", [ 2 ] = "Империя" }
local FAC_DOT = { [ 0 ] = "DOT_NONE", [ 1 ] = "DOT_LEAGUE", [ 2 ] = "DOT_EMPIRE" }

local SWITCHES = {
	{ k = "warnGroup", label = "Вступление в группу или отряд" },
	{ k = "warnGuild", label = "Вступление в гильдию" },
	{ k = "warnWhisperIn", label = "Входящее личное сообщение" },
	{ k = "warnWhisperOut", label = "Исходящее личное сообщение" },
	{ k = "collectNear", label = "Обновлять игроков рядом" },
	{ k = "collectChat", label = "Записывать писавших в чат" },
	{ k = "renameNotify", label = "Сообщать о смене ника" },
	{ k = "cleanup", label = "Удалять старых нейтральных" },
}
local STEPS = {
	{ k = "pause", label = "Пауза для лички", min = MC.PAUSE_MIN, max = MC.PAUSE_MAX, step = MC.PAUSE_STEP, unit = " с" },
	{ k = "cleanupDays", label = "Не встречались, дней", min = MC.DAYS_MIN, max = MC.DAYS_MAX, step = MC.DAYS_STEP, unit = "" },
}

--------------------------------------------------------------------------------
-- Инициализация
--------------------------------------------------------------------------------
function UI.Init()
	ui.host = W( "MCHost" )
	ui.button = W( "MCButton" )
	ui.ring = W( "MCRing" )
	ui.badge = W( "MCBadge" )
	ui.main = W( "MainWindow" )
	ui.mainPage = W( "MainPage" )
	ui.settingsPage = W( "SettingsPage" )
	ui.countText = W( "CountText" )
	ui.gear = W( "HdrGear" ); ui.gearIcon = W( "HdrGearIcon" )
	ui.searchEdit = W( "SearchEdit" )
	ui.searchHint = W( "SearchHint" )
	ui.searchClear = W( "SearchClear" )
	ui.searchFocus = W( "SearchFocus" )
	ui.sortIcon = W( "SortBtnIcon" )
	ui.target = W( "TargetBtn" ); ui.targetIcon = W( "TargetBtnIcon" )
	ui.filters = {}
	for _, k in ipairs( { "FNeu", "FNeg", "FPos", "FNotes", "FRecent" } ) do
		local b = W( k )
		-- у «С заметками» и «За 24 часа» числа нет (запрос несуществующего ребёнка пишет ошибку в mods.txt)
		local hasCount = k == "FNeu" or k == "FNeg" or k == "FPos"
		ui.filters[ k ] = { w = b, icon = Child( b, k .. "Icon" ), count = hasCount and Child( b, k .. "Count" ) or nil }
	end
	ui.reset = W( "FReset" )
	ui.rows = {}
	for i = 1, ROWS do
		local row = W( "Row" .. i )
		ui.rows[ i ] = { w = row, btn = Child( row, "RowBtn" ), mark = Child( Child( row, "RowMark" ), "RowMarkIcon" ),
			dot = Child( row, "RowDot" ), nick = Child( row, "RowNick" ), note = Child( row, "RowNote" ), ren = Child( row, "RowRen" ) }
	end
	ui.track = W( "ScrollTrack" )
	ui.thumb = W( "ScrollThumb" )
	ui.emptyIcon = W( "EmptyIcon" )
	ui.emptyText = W( "EmptyText" )
	ui.emptyReset = W( "EmptyReset" )
	ui.emptyAdd = W( "EmptyAdd" )
	ui.menu = W( "MarkMenu" )
	-- настройки
	SetText( W( "SetSectReact" ), "Реакции на отрицательных" )
	SetText( W( "SetSectBase" ), "База игроков" )
	SetText( W( "SetSectCommon" ), "Общее" )
	ui.sw = {}
	for i, s in ipairs( SWITCHES ) do
		local row = W( "SetSw" .. i )
		ui.sw[ i ] = { row = row, name = Child( row, "SetName" ), switch = Child( row, "SetSwitch" ) }
		SetText( ui.sw[ i ].name, s.label )
	end
	ui.steps = {}
	for i, s in ipairs( STEPS ) do
		local row = W( "SetStep" .. i )
		local box = Child( row, "StepBox" )
		ui.steps[ i ] = { row = row, name = Child( row, "SetName" ), box = box, value = Child( box, "StepValue" ),
			minus = Child( box, "StepMinus" ), plus = Child( box, "StepPlus" ) }
		SetText( ui.steps[ i ].name, s.label )
	end
	ui.stats = W( "SetStats" )
	ui.cleanNow = W( "SetCleanNow" )
	ui.wipe = W( "SetWipe" )
	-- карточка
	ui.card = W( "CardWindow" )
	ui.cardDot = W( "CardDot" )
	ui.cardNick = W( "CardNick" )
	ui.cardInfo = W( "CardInfo" )
	ui.clsSlots = {}
	for i = 1, CLS_SLOTS do ui.clsSlots[ i ] = W( "ClsSlot" .. i ) end
	ui.cardChips = { [ 0 ] = W( "CardMarkNeu" ), [ 1 ] = W( "CardMarkPos" ), [ -1 ] = W( "CardMarkNeg" ) }
	ui.cardChipIcons = { [ 0 ] = W( "CardMarkNeuIcon" ), [ 1 ] = W( "CardMarkPosIcon" ), [ -1 ] = W( "CardMarkNegIcon" ) }
	SetText( W( "CardMarkNeuText" ), "Нейтральный" )
	SetText( W( "CardMarkPosText" ), "Положительный" )
	SetText( W( "CardMarkNegText" ), "Отрицательный" )
	ui.fields = { uid = W( "FUidValue" ),
		guild = W( "FGuildValue" ), rank = W( "FRankValue" ) }
	SetText( W( "FGuildLabel" ), "Гильдия" )
	SetText( W( "FRankLabel" ), "Ранг" )
	SetText( W( "FUidLabel" ), "UID" )
	ui.namesTitle = W( "NamesTitle" )
	ui.guildsTitle = W( "GuildsTitle" )
	ui.nameRows, ui.guildRows = {}, {}
	for i = 1, NAME_ROWS do
		local row = W( "NamesRow" .. i )
		ui.nameRows[ i ] = { w = row, nick = Child( row, "NamesText" ) }
	end
	for i = 1, GUILD_ROWS do
		local grow = W( "GuildsRow" .. i )
		ui.guildRows[ i ] = { w = grow, nick = Child( grow, "GuildsText" ), rank = Child( grow, "GuildsRank" ) }
	end
	ui.notesTitle = W( "NotesTitle" )
	ui.noteCards = {}
	for i = 1, 4 do
		local c = W( "NoteCard" .. i )
		ui.noteCards[ i ] = { w = c, text = Child( c, "NoteText" ), date = Child( c, "NoteDate" ) }
	end
	ui.notesEmpty = W( "NotesEmpty" )
	ui.notesEmptyAdd = W( "NotesEmptyAdd" )
	ui.notesMore = W( "NotesMore" )
	SetText( ui.notesEmpty, "Заметок нет" )
	-- редактор и подтверждение
	ui.editorLayer = W( "EditorLayer" )
	ui.edTitle = W( "EdTitle" )
	ui.edEdit = W( "EdEdit" )
	ui.edCount = W( "EdCount" )
	ui.edSave = W( "EdSave" )
	ui.confirm = W( "Confirm" )
	ui.cfTitle = W( "CfTitle" )
	ui.cfText = W( "CfText" )
	ui.cfOk = W( "CfOk" )
	-- подсказка
	ui.tip = W( "Tooltip" )
	ui.tipText = W( "TipText" )
	ui.tipBack = W( "TipBack" )
	ui.tipWarn = W( "TipBackWarn" )

	SetText( ui.searchHint, "Поиск по нику" )
	Show( ui.main, false )
	Show( ui.card, false )
	Show( ui.tip, false )
	Show( ui.menu, false )
	Show( ui.confirm, false )
	Show( ui.editorLayer, false )
end

--------------------------------------------------------------------------------
-- Список: фильтр и сортировка (пересчёт только при смене условий или данных)
--------------------------------------------------------------------------------
local function LowerOf( n )
	local l = lowerCache[ n ]
	if not l then l = MC.Lower( n.n or "" ) lowerCache[ n ] = l end
	return l
end

local function AnyFilter()
	return filt.neu or filt.neg or filt.pos or filt.notes or filt.recent or search ~= ""
end

local function Rebuild()
	local res = {}
	local c = { neu = 0, neg = 0, pos = 0 }
	local anyMark = filt.neu or filt.neg or filt.pos
	local now = MC.NowMin() or 0
	local q = searchL
	for _, r in pairs( DB.players ) do
		local m = r.mark or 0
		if m == 0 then c.neu = c.neu + 1 elseif m == 1 then c.pos = c.pos + 1 else c.neg = c.neg + 1 end
		local ok = true
		if anyMark then ok = ( m == 0 and filt.neu ) or ( m == 1 and filt.pos ) or ( m == -1 and filt.neg ) end
		if ok and filt.notes then ok = r.notes ~= nil and #r.notes > 0 end
		if ok and filt.recent then ok = ( r.seen or 0 ) >= now - 1440 end
		r._match = false
		if ok and q ~= "" then
			if not string.find( r.nameL, q, 1, true ) then
				ok = false
				if r.names then
					for _, n in ipairs( r.names ) do
						if string.find( LowerOf( n ), q, 1, true ) then ok = true r._match = true break end
					end
				end
			end
		end
		if ok then res[ #res + 1 ] = r end
	end
	if MC.cfg.sortByName then
		table.sort( res, function( a, b ) return a.nameL < b.nameL end )
	else
		table.sort( res, function( a, b )
			local sa, sb = a.seen or 0, b.seen or 0
			if sa ~= sb then return sa > sb end
			return a.nameL < b.nameL
		end )
	end
	items = res
	counts = c
	builtVersion = DB.version
	listDirty = false
	local maxOff = math.max( 0, #items - ROWS )
	if offset > maxOff then offset = maxOff end
end

local function ChipCount( key, n )
	local f = ui.filters[ key ]
	if not f or not f.count then return end
	local s = n > 99999 and "99к+" or tostring( n )
	SetText( f.count, s )
	if f.shown == s then return end
	f.shown = s
	-- иконка и число вместе по центру чипа
	local tw = math.floor( MC.CharLen( s ) * 8.5 + 0.5 )
	local x0 = math.floor( ( 70 - ( 14 + 6 + tw ) ) / 2 )
	local pi = f.icon:GetPlacementPlain()
	pi.posX = x0
	f.icon:SetPlacementPlain( pi )
	local pc = f.count:GetPlacementPlain()
	pc.posX = x0 + 20
	pc.sizeX = tw + 6
	f.count:SetPlacementPlain( pc )
end

local thumbDrag = false     -- ползунок тянут мышью: его положение задаёт DnD, мы только листаем список

local function RenderScroll()
	local n = #items
	local show = n > ROWS
	Show( ui.thumb, show )
	if not show or thumbDrag then return end
	local th = math.max( 24, math.floor( TRACK_H * ROWS / n ) )
	local maxOff = n - ROWS
	local y = math.floor( ( TRACK_H - th ) * offset / maxOff + 0.5 )
	local pl = ui.thumb:GetPlacementPlain()
	if pl.posY ~= y or pl.sizeY ~= th then
		pl.posY, pl.sizeY = y, th
		ui.thumb:SetPlacementPlain( pl )
	end
end

local function RenderList()
	for i = 1, ROWS do
		local row, r = ui.rows[ i ], items[ offset + i ]
		if r then
			SetTex( row.mark, "MARK_" .. MARK_KEY[ r.mark or 0 ] )
			SetTex( row.dot, FAC_DOT[ r.fac or 0 ] or "DOT_NONE" )
			SetText( row.nick, r.name )
			Show( row.note, r.notes ~= nil and #r.notes > 0 )
			Show( row.ren, r._match and true or false )
			SetVariant( row.btn, ( r == selected and 1 ) or ( r._match and 2 ) or 0 )
			Show( row.w, true )
		else
			Show( row.w, false )
		end
	end
	RenderScroll()
	-- пустые состояния
	local empty = #items == 0
	local first = DB.Count() == 0
	Show( ui.emptyIcon, empty and first )
	Show( ui.emptyText, empty )
	SetText( ui.emptyText, first and "Пока никого не встретили" or "Не найдено" )
	Show( ui.emptyReset, empty and not first and AnyFilter() )
	local n = MC.CharLen( search )
	local canAdd = empty and search ~= "" and n >= MC.NICK_MIN and n <= MC.NICK_MAX and not string.find( search, "[%s%d%p]" )
	Show( ui.emptyAdd, canAdd and true or false )
end

local function RenderFilters()
	for key, f in pairs( ui.filters ) do
		local on = ( key == "FNeu" and filt.neu ) or ( key == "FNeg" and filt.neg ) or ( key == "FPos" and filt.pos ) or
			( key == "FNotes" and filt.notes ) or ( key == "FRecent" and filt.recent )
		SetVariant( f.w, on and 1 or 0 )
		if key == "FNeu" then SetTex( f.icon, on and "MARK_NEU" or "MARK_NEU_OFF" ) ChipCount( key, counts.neu )
		elseif key == "FNeg" then SetTex( f.icon, on and "MARK_NEG" or "MARK_NEG_OFF" ) ChipCount( key, counts.neg )
		elseif key == "FPos" then SetTex( f.icon, on and "MARK_POS" or "MARK_POS_OFF" ) ChipCount( key, counts.pos )
		elseif key == "FNotes" then SetTex( f.icon, on and "NOTE_CHIP_ON" or "NOTE_CHIP" )
		else SetTex( f.icon, on and "CLOCK_ON" or "CLOCK" ) end
	end
	Enable( ui.reset, AnyFilter() )
	SetTex( ui.sortIcon, MC.cfg.sortByName and "SORT_NAME" or "SORT_TIME" )
	Show( ui.searchHint, search == "" )
	Show( ui.searchClear, search ~= "" )
end

--------------------------------------------------------------------------------
-- Настройки
--------------------------------------------------------------------------------
local oldCount = nil
local function RenderSettings()
	local cfg = MC.cfg
	for i, s in ipairs( SWITCHES ) do SetVariant( ui.sw[ i ].switch, cfg[ s.k ] and 1 or 0 ) end
	for i, s in ipairs( STEPS ) do
		local row = ui.steps[ i ]
		SetText( row.value, tostring( cfg[ s.k ] ) .. s.unit )
		local active = true
		if s.k == "pause" then active = cfg.warnWhisperIn or cfg.warnWhisperOut end
		if s.k == "cleanupDays" then active = cfg.cleanup end
		Fade( row.row, active and 1 or 0.45 )
		Enable( row.minus, active and cfg[ s.k ] > s.min )
		Enable( row.plus, active and cfg[ s.k ] < s.max )
	end
	local marked, withNotes = DB.Stats()
	if oldCount == nil then oldCount = DB.Cleanup( cfg.cleanupDays, cfg.maxPlain, nil, true ) end
	SetText( ui.stats, "В базе " .. MC.Num( DB.Count() ) .. " · отмечено " .. marked .. " · с заметками " .. withNotes ..
		" · старых " .. oldCount )
	Enable( ui.cleanNow, oldCount > 0 )
	Enable( ui.wipe, DB.Count() > 0 )
end

--------------------------------------------------------------------------------
-- Кнопка на экране
--------------------------------------------------------------------------------
function UI.RenderButton()
	if not ui.host then return end
	Show( ui.ring, ui.main and ui.main:IsVisible() )
	Show( ui.badge, #MC.Game.groupNegative > 0 )
end

--------------------------------------------------------------------------------
-- Главное окно
--------------------------------------------------------------------------------
function UI.Render()
	if not ui.main then return end
	UI.RenderButton()
	if not ui.main:IsVisible() then return end
	SetText( ui.countText, MC.Num( DB.Count() ) )
	local settings = UI.view == "settings"
	Show( ui.mainPage, not settings )
	Show( ui.settingsPage, settings )
	SetVariant( ui.gear, settings and 1 or 0 )
	SetTex( ui.gearIcon, settings and "GEAR_ON" or "GEAR" )
	if settings then
		RenderSettings()
		return
	end
	if listDirty or builtVersion ~= DB.version then Rebuild() end
	SetTex( ui.targetIcon, MC.Game.HasPlayerTarget() and "TARGET" or "TARGET_OFF" )
	RenderFilters()
	RenderList()
end

function UI.ShowWindow( on )
	Show( ui.main, on )
	if not on then
		UI.HideTip()
		Show( ui.menu, false )
		UI.CloseCard()
	else
		listDirty = true
	end
	UI.Render()
end

function UI.ToggleWindow()
	UI.ShowWindow( not ui.main:IsVisible() )
end

-- Данные игрока изменились (сбор, группа, личка)
function UI.DataChanged( r )
	if r and r == cardRec then cardDirty = true end
end

--------------------------------------------------------------------------------
-- Карточка
--------------------------------------------------------------------------------
local function ShortUid( r )
	if not r.uid then return "—" end
	return ( string.gsub( r.uid, "^0x", "" ) )
end

-- Ранги гильдии по номеру, который отдаёт игра (0 — лидер)
UI.RANKS = { [ 0 ] = "Лидер", "Казначей", "Офицер", "Ветеран", "Старшина", "Рядовой", "Дублёр", "Новобранец", "Штрафник", "Изгой" }

local function RankName( rank )
	if rank == nil then return nil end
	return UI.RANKS[ rank ] or ( "ранг " .. rank )
end

-- Поле «Гильдия» — только название; «Ранг» — отдельно
local function GuildName( name, unknown )
	if unknown then return "Неизвестна" end
	if not name or name == "" then return "Без гильдии" end
	return name
end

-- «Адреналин · Старшина», «Без гильдии», «Неизвестна»
function UI.GuildText( name, rank, unknown )
	if unknown then return "Неизвестна" end
	if not name or name == "" then return "Без гильдии" end
	local rn = rank and UI.RANKS[ rank ]
	if rn then return name .. " · " .. rn end
	if rank then return name .. " · ранг " .. rank end
	return name
end

-- Эмблемы классов слева от строки сведений: первая — текущий класс, прежние — приглушены.
-- Строка сведений сдвигается на ширину показанных эмблем.
-- names — названия классов (текущий первым). Класс, эмблемы которого в аддоне нет (новый в игре
-- или имя не распознано), пропускаем: он остаётся текстом в строке сведений.
local function RenderClasses( names )
	local n = 0
	for i, name in ipairs( names ) do
		local sys = MC.CLASS_SYS[ name ]
		if sys and n < CLS_SLOTS then
			n = n + 1
			SetTex( ui.clsSlots[ n ], "CLS_" .. sys )
			Fade( ui.clsSlots[ n ], i == 1 and 1 or 0.45 )
		end
	end
	for i = 1, CLS_SLOTS do Show( ui.clsSlots[ i ], i <= n ) end
	local x = CLS_X + ( n > 0 and ( n * CLS_STEP + CLS_GAP ) or 0 )
	MC.Place( ui.cardInfo, { posX = x, sizeX = CARD_W - 12 - x } )
end

local function RenderCard()
	local r = cardRec
	if not r or not ui.card:IsVisible() then return end
	cardDirty = false
	SetTex( ui.cardDot, FAC_DOT[ r.fac or 0 ] or "DOT_NONE" )
	SetText( ui.cardNick, r.name )
	local parts = {}
	local cls = DB.DictName( "cls", r.cls )
	RenderClasses( cls ~= "" and { cls } or {} )
	if cls ~= "" then parts[ #parts + 1 ] = cls end
	local shard = DB.DictName( "shard", r.sh )
	if shard ~= "" then parts[ #parts + 1 ] = shard end
	if FAC_NAME[ r.fac or 0 ] then parts[ #parts + 1 ] = FAC_NAME[ r.fac ] end
	parts[ #parts + 1 ] = ( r.gs and r.gs > 0 ) and ( "ГС " .. MC.Num( r.gs ) ) or "ГС —"
	SetText( ui.cardInfo, table.concat( parts, " · " ) )
	for m, chip in pairs( ui.cardChips ) do
		local on = ( r.mark or 0 ) == m
		SetVariant( chip, on and 1 or 0 )
		SetTex( ui.cardChipIcons[ m ], "MARK_" .. MARK_KEY[ m ] .. ( on and "" or "_OFF" ) )
	end
	SetText( ui.fields.uid, ShortUid( r ) )
	local gname = r.g and DB.DictName( "guild", r.g )
	SetText( ui.fields.guild, GuildName( gname, r.g == nil ) )
	SetText( ui.fields.rank, ( gname and gname ~= "" and RankName( r.gr ) ) or "—" )
	-- ники: текущий, затем прежние (новые сверху)
	local names = r.names or {}
	SetText( ui.namesTitle, "Ники" )
	namesOff = math.max( 0, math.min( namesOff, #names - ( NAME_ROWS - 1 ) ) )
	for i = 1, NAME_ROWS do
		local row = ui.nameRows[ i ]
		if i == 1 then
			SetText( row.nick, r.name )
			Show( row.w, true )
		else
			local k = namesOff + i - 1
			local n = names[ k ]
			if n then
				SetText( row.nick, n.n )
			end
			Show( row.w, n ~= nil )
		end
	end
	-- гильдии: текущая (по последней встрече), затем прежние — каждая один раз,
	-- с последним известным рангом в ней (история новые сверху, поэтому берём первое вхождение)
	local gh = r.gh or {}
	SetText( ui.guildsTitle, "Гильдии" )
	local function rk( name, rank ) return ( name and name ~= "" and RankName( rank ) ) or "" end
	local list = { { GuildName( gname, r.g == nil ), r.g ~= nil and rk( gname, r.gr ) or "" } }
	local seenG = {}
	if gname and gname ~= "" then seenG[ gname ] = true end
	for _, e in ipairs( gh ) do
		if e.g and e.g ~= "" and not seenG[ e.g ] then
			seenG[ e.g ] = true
			list[ #list + 1 ] = { e.g, rk( e.g, e.rk ) }
		end
	end
	guildsOff = math.max( 0, math.min( guildsOff, #list - GUILD_ROWS ) )
	for i = 1, GUILD_ROWS do
		local row = ui.guildRows[ i ]
		local e = ( i == 1 ) and list[ 1 ] or list[ guildsOff + i ]
		if e then
			SetText( row.nick, e[ 1 ] )
			SetText( row.rank, e[ 2 ] )
		end
		Show( row.w, e ~= nil )
	end
	-- заметки
	local notes = r.notes or {}
	SetText( ui.notesTitle, "Заметки" )
	local maxOff = math.max( 0, #notes - 4 )
	if notesOff > maxOff then notesOff = maxOff end
	for i = 1, 4 do
		local c, n = ui.noteCards[ i ], notes[ notesOff + i ]
		if n then
			SetText( c.text, n.t or "" )
			SetText( c.date, MC.FmtMin( n.c ) .. ( n.e and ( " · изменена " .. MC.FmtDate( n.e ) ) or "" ) )
			Show( c.w, true )
		else
			Show( c.w, false )
		end
	end
	Show( ui.notesEmpty, #notes == 0 )
	Show( ui.notesEmptyAdd, #notes == 0 )
	local more = #notes - notesOff - 4
	Show( ui.notesMore, more > 0 )
	if more > 0 then SetText( ui.notesMore, "ещё " .. more .. " — прокрутите колесом" ) end
end

function UI.OpenCard( r )
	if not r then return end
	if cardRec ~= r then notesOff, namesOff, guildsOff = 0, 0, 0 end
	cardRec = r
	selected = r
	Show( ui.card, true )
	RenderCard()
	if ui.main:IsVisible() then RenderList() end
end

function UI.CloseCard()
	cardRec = nil
	selected = nil
	Show( ui.card, false )
	Show( ui.editorLayer, false )
	editor = nil
	if ui.main and ui.main:IsVisible() then RenderList() end
end

local function Changed( r )
	listDirty = true
	MC.Game.FlushSoon()
	if r == cardRec then RenderCard() end
	UI.Render()
end

--------------------------------------------------------------------------------
-- Подсказки
--------------------------------------------------------------------------------
local tipLeft = 0
local TIP_W = 300

function UI.ShowTip( anchor, text, warn, seconds )
	if not ui.tip or not anchor or not text then return end
	local rect = anchor:GetRealRect()
	-- Ожидаем: у скрытого виджета может не быть размеров — подсказку не показываем
	if type( rect ) ~= "table" then return end
	local lines = math.max( 1, math.ceil( MC.CharLen( text ) / 36 ) )
	local h = lines * 18 + 14
	local pl = ui.tip:GetPlacementPlain()
	pl.alignX = WIDGET_ALIGN_LOW_ABS
	pl.alignY = WIDGET_ALIGN_LOW_ABS
	pl.posX = math.floor( rect.x1 )
	pl.posY = math.floor( rect.y2 + 6 )
	pl.sizeX = TIP_W
	pl.sizeY = h
	ui.tip:SetPlacementPlain( pl )
	SetText( ui.tipText, text )
	Show( ui.tipBack, not warn )
	Show( ui.tipWarn, warn and true or false )
	Show( ui.tip, true )
	tipLeft = seconds or 8
end

function UI.HideTip()
	Show( ui.tip, false )
	tipLeft = 0
end

local function RowIndex( w, prefix )
	local p = w
	for _ = 1, 3 do
		if not p then return nil end
		local n = tonumber( string.match( p:GetName() or "", "^" .. prefix .. "(%d+)$" ) or "" )
		if n then return n end
		p = p:GetParent()
	end
	return nil
end

local FILTER_TIPS = {
	FNeu = "Нейтральные. Повторный клик снимает фильтр",
	FNeg = "Отрицательные. Повторный клик снимает фильтр",
	FPos = "Положительные. Повторный клик снимает фильтр",
	FNotes = "Только игроки с заметками",
	FRecent = "Встреченные за последние 24 часа",
}

--------------------------------------------------------------------------------
-- Подтверждение
--------------------------------------------------------------------------------
local function Confirm( title, text, okLabel, fn )
	confirm = { ok = fn }
	SetText( ui.cfTitle, title )
	SetText( ui.cfText, text )
	ui.cfOk:SetVal( "button_label", WS( okLabel ) )
	Show( ui.confirm, true )
end

function UI.OnConfirmOk()
	local c = confirm
	confirm = nil
	Show( ui.confirm, false )
	if c and c.ok then c.ok() end
end

function UI.OnConfirmCancel()
	confirm = nil
	Show( ui.confirm, false )
end

--------------------------------------------------------------------------------
-- Реакции: главное окно
--------------------------------------------------------------------------------
function UI.OnGear()
	UI.view = UI.view == "settings" and "main" or "settings"
	oldCount = nil
	Show( ui.menu, false )
	UI.HideTip()
	listDirty = true
	UI.Render()
end

local function SearchText()
	return MC.Trim( S( ui.searchEdit:GetText() ) )
end

function UI.OnSearchChanged()
	search = SearchText()
	searchL = MC.Lower( search )
	offset = 0
	listDirty = true
	UI.Render()
end

function UI.OnSearchClear()
	ui.searchEdit:SetText( WS( "" ) )
	UI.OnSearchChanged()
end

function UI.OnSearchEsc()
	UI.OnSearchClear()
	ui.searchEdit:SetFocus( false )
end

function UI.OnSearchEnter()
	ui.searchEdit:SetFocus( false )
	if #items == 1 then UI.OpenCard( items[ 1 ] ) end
end

function UI.OnSearchFocus( params )
	Show( ui.searchFocus, params.active and true or false )
end

function UI.OnSort()
	MC.cfg.sortByName = not MC.cfg.sortByName
	MC.Cfg.Save()
	listDirty = true
	offset = 0
	UI.Render()
end

function UI.OnTarget()
	local r, err = MC.Game.TargetRecord()
	if r then
		listDirty = true
		UI.OpenCard( r )
		UI.Render()
	else
		UI.ShowTip( ui.target, err or "Нет цели", true, 3 )
	end
end

local FILTER_KEYS = { FNeu = "neu", FNeg = "neg", FPos = "pos", FNotes = "notes", FRecent = "recent" }
function UI.OnFilter( params )
	local name = params.widget and params.widget:GetName()
	local k = FILTER_KEYS[ name or "" ]
	if not k then return end
	filt[ k ] = not filt[ k ]       -- повторный клик снимает фильтр
	offset = 0
	listDirty = true
	UI.Render()
end

function UI.OnReset()
	for k in pairs( filt ) do filt[ k ] = false end
	ui.searchEdit:SetText( WS( "" ) )
	search, searchL = "", ""
	offset = 0
	listDirty = true
	UI.Render()
end

local function Scroll( delta )
	local maxOff = math.max( 0, #items - ROWS )
	local o = math.max( 0, math.min( maxOff, offset + delta ) )
	if o ~= offset then
		offset = o
		Show( ui.menu, false )
		RenderList()
	end
end

function UI.OnListUp() Scroll( -WHEEL_ROWS ) end
function UI.OnListDown() Scroll( WHEEL_ROWS ) end

--------------------------------------------------------------------------------
-- Полоса прокрутки: нажатие на дорожку ставит ползунок под курсор, дальше он тянется
--------------------------------------------------------------------------------
local trackId = nil

local function ThumbHeight()
	local pl = ui.thumb:GetPlacementPlain()
	return pl.sizeY or 24
end

-- положение ползунка (виртуальные пиксели внутри дорожки) -> строка списка
local function OffsetFromThumb( y )
	local maxOff = math.max( 0, #items - ROWS )
	local span = TRACK_H - ThumbHeight()
	if maxOff == 0 or span <= 0 then return 0 end
	return math.max( 0, math.min( maxOff, math.floor( y / span * maxOff + 0.5 ) ) )
end

local function SetOffset( o )
	if o ~= offset then
		offset = o
		Show( ui.menu, false )
		RenderList()
	end
end

function UI.InitScroll()
	if not DnD or not DnD.Init then return end
	DnD.Init( ui.thumb, ui.track, false, true, nil, nil, "default" )
	if DnD.Widgets then trackId = DnD.GetWidgetID( ui.track ) end
end

function UI.IsScrollDrag()
	return trackId ~= nil and DnD.Dragging == trackId
end

-- нажали на дорожку: ползунок центром под курсор
function UI.OnTrackPick( cursorY )
	if #items <= ROWS then return end
	local rect = ui.track:GetRealRect()
	if type( rect ) ~= "table" then return end
	local scr = DnD.Screen or {}
	local k = ( scr.fullVirtualSizeY or 1 ) / ( scr.realSizeY or 1 )
	local th = ThumbHeight()
	local y = ( cursorY - rect.y1 ) * k - th / 2
	y = math.max( 0, math.min( TRACK_H - th, math.floor( y + 0.5 ) ) )
	local pl = ui.thumb:GetPlacementPlain()
	pl.posY = y
	ui.thumb:SetPlacementPlain( pl )
	if DnD.Reset then DnD.Reset.posY, DnD.Reset.highPosY = y, ( DnD.Reset.highPosY or 0 ) end
	if DnD.Place then DnD.Place.posY = y end
	thumbDrag = true
	SetOffset( OffsetFromThumb( y ) )
end

-- ползунок тянут
function UI.OnThumbMoved()
	local pl = ui.thumb:GetPlacementPlain()
	SetOffset( OffsetFromThumb( pl.posY or 0 ) )
end

-- отпустили: ползунок встаёт ровно по строке
function UI.OnThumbReleased()
	thumbDrag = false
	RenderScroll()
end

function UI.OnTrack() end

local function RowRec( params )
	local i = params.widget and RowIndex( params.widget, "Row" )
	return i and items[ offset + i ], i
end

function UI.OnRow( params )
	Show( ui.menu, false )
	local r = RowRec( params )
	if not r then return end
	if r == cardRec and ui.card:IsVisible() then UI.CloseCard() return end
	UI.OpenCard( r )
end

function UI.OnRowMark( params )
	local r, i = RowRec( params )
	if not r then return end
	if ui.menu:IsVisible() and menuRec == r then Show( ui.menu, false ) return end
	menuRec = r
	local pl = ui.menu:GetPlacementPlain()
	pl.posX = 20
	local y = 44 + 90 + 4 + ( i - 1 ) * ROW_H + ROW_H
	if y + 98 > 600 - 8 then y = y - ROW_H - 98 end
	pl.posY = y
	ui.menu:SetPlacementPlain( pl )
	Show( ui.menu, true )
end

local MENU_MARK = { MenuNeu = 0, MenuPos = 1, MenuNeg = -1 }
function UI.OnMenu( params )
	local m = MENU_MARK[ params.widget and params.widget:GetName() or "" ]
	Show( ui.menu, false )
	if m == nil or not menuRec then return end
	DB.SetMark( menuRec, m )
	Changed( menuRec )
	menuRec = nil
end

function UI.OnEmptyAdd()
	local r = DB.AddManual( search, MC.Game.MyShard() )
	listDirty = true
	UI.OpenCard( r )
	Changed( r )
end

--------------------------------------------------------------------------------
-- Реакции: карточка
--------------------------------------------------------------------------------
local CHIP_MARK = { CardMarkNeu = 0, CardMarkPos = 1, CardMarkNeg = -1 }
function UI.OnCardMark( params )
	local m = CHIP_MARK[ params.widget and params.widget:GetName() or "" ]
	if m == nil or not cardRec then return end
	DB.SetMark( cardRec, m )
	Changed( cardRec )
end

function UI.OnNotesUp()
	if notesOff > 0 then notesOff = notesOff - 1 RenderCard() end
end

function UI.OnNotesDown()
	local n = cardRec and cardRec.notes and #cardRec.notes or 0
	if notesOff < n - 4 then notesOff = notesOff + 1 RenderCard() end
end

function UI.OnNamesUp() if namesOff > 0 then namesOff = namesOff - 1 RenderCard() end end
function UI.OnNamesDown() namesOff = namesOff + 1 RenderCard() end
function UI.OnGuildsUp() if guildsOff > 0 then guildsOff = guildsOff - 1 RenderCard() end end
function UI.OnGuildsDown() guildsOff = guildsOff + 1 RenderCard() end

-- Цель сменилась: иконка кнопки «Карточка игрока в цели»
function UI.OnTargetChanged()
	if not ( ui.main and ui.main:IsVisible() ) then return end
	SetTex( ui.targetIcon, MC.Game.HasPlayerTarget() and "TARGET" or "TARGET_OFF" )
end

local function NoteIndex( params )
	local i = params.widget and RowIndex( params.widget, "NoteCard" )
	return i and ( notesOff + i )
end

local function EdText()
	return MC.Trim( S( ui.edEdit:GetText() ) )
end

local function RenderEditor()
	if not editor then return end
	local t = EdText()
	local n = MC.CharLen( t )
	SetText( ui.edCount, n .. " / " .. MC.NOTE_MAX )
	Enable( ui.edSave, t ~= "" and t ~= editor.orig )
end

local function OpenEditor( mode, index )
	if not cardRec then return end
	local text = ""
	if mode == "edit" then text = cardRec.notes and cardRec.notes[ index ] and cardRec.notes[ index ].t or "" end
	editor = { mode = mode, index = index, orig = text }
	SetText( ui.edTitle, mode == "add" and "Новая заметка" or "Заметка" )
	ui.edEdit:SetText( WS( text ) )
	Show( ui.editorLayer, true )
	ui.edEdit:SetFocus( true )
	RenderEditor()
end

function UI.OnNoteAdd() OpenEditor( "add" ) end

function UI.OnNoteEdit( params )
	local i = NoteIndex( params )
	if i then OpenEditor( "edit", i ) end
end

function UI.OnNoteDel( params )
	local i = NoteIndex( params )
	local r = cardRec
	local n = r and r.notes and r.notes[ i ]
	if not n then return end
	local preview = n.t or ""
	if MC.CharLen( preview ) > 60 then preview = string.sub( preview, 1, 60 ) .. "…" end
	Confirm( "Удалить заметку?", preview, "Удалить", function()
		DB.DelNote( r, i )
		Changed( r )
	end )
end

function UI.OnEdChanged() RenderEditor() end

local function CloseEditor()
	editor = nil
	ui.edEdit:SetFocus( false )
	Show( ui.editorLayer, false )
end

function UI.OnEdSave()
	if not editor or not cardRec then return end
	local t = EdText()
	if t == "" or t == editor.orig then return end
	if MC.CharLen( t ) > MC.NOTE_MAX then t = string.sub( t, 1, MC.NOTE_MAX ) end
	if editor.mode == "add" then DB.AddNote( cardRec, t ) notesOff = 0
	else DB.EditNote( cardRec, editor.index, t ) end
	CloseEditor()
	Changed( cardRec )
end

function UI.OnEdCancel()
	if not editor then return end
	if EdText() ~= editor.orig then
		Confirm( "Не сохранять изменения?", "Текст заметки будет потерян", "Не сохранять", CloseEditor )
		return
	end
	CloseEditor()
end

function UI.OnCardDelete()
	local r = cardRec
	if not r then return end
	Confirm( "Удалить из базы?", r.name .. " · заметок: " .. ( r.notes and #r.notes or 0 ), "Удалить", function()
		DB.Delete( r )
		UI.CloseCard()
		Changed( nil )
	end )
end

--------------------------------------------------------------------------------
-- Реакции: настройки
--------------------------------------------------------------------------------
function UI.OnSetSwitch( params )
	local i = params.widget and RowIndex( params.widget, "SetSw" )
	local s = i and SWITCHES[ i ]
	if not s then return end
	MC.cfg[ s.k ] = not MC.cfg[ s.k ]
	MC.Cfg.Save()
	UI.Render()
end

local function Step( params, dir )
	local i = params.widget and RowIndex( params.widget, "SetStep" )
	local s = i and STEPS[ i ]
	if not s then return end
	local v = MC.cfg[ s.k ] + dir * s.step
	v = math.max( s.min, math.min( s.max, v ) )
	if v ~= MC.cfg[ s.k ] then
		MC.cfg[ s.k ] = v
		MC.Cfg.Save()
		if s.k == "cleanupDays" then oldCount = nil end
		UI.Render()
	end
end

function UI.OnStepMinus( params ) Step( params, -1 ) end
function UI.OnStepPlus( params ) Step( params, 1 ) end

function UI.OnCleanNow()
	local n = DB.Cleanup( MC.cfg.cleanupDays, MC.cfg.maxPlain, nil, true )
	if n == 0 then return end
	Confirm( "Удалить старых?", "Удалить " .. n .. " записей: нейтральные без заметок, не встреченные дольше " .. MC.cfg.cleanupDays .. " дней",
		"Удалить", function()
			DB.Cleanup( MC.cfg.cleanupDays, MC.cfg.maxPlain )
			oldCount = nil
			Changed( nil )
		end )
end

function UI.OnWipe()
	local n = DB.Count()
	if n == 0 then return end
	Confirm( "Очистить базу?", "Удалить всех игроков: " .. MC.Num( n ) .. ", вместе с отметками и заметками. Отменить нельзя",
		"Удалить всё", function()
			if UI.CloseCard then UI.CloseCard() end
			DB.Wipe()
			oldCount = nil
			Changed( nil )
			MC.Chat( "база очищена" )
		end )
end

function UI.OnResetCfg()
	Confirm( "Сбросить настройки?", "Настройки вернутся к начальным. База игроков не изменится", "Сбросить", function()
		MC.Cfg.Reset()
		UI.Render()
	end )
end

--------------------------------------------------------------------------------
-- Таймер
--------------------------------------------------------------------------------
function UI.OnSecond()
	if tipLeft > 0 then
		tipLeft = tipLeft - 1
		if tipLeft <= 0 then UI.HideTip() end
	end
	-- сбор игроков меняет базу постоянно: сам список пересчитываем не чаще раза в 10 секунд
	if ui.main and ui.main:IsVisible() and UI.view == "main" and builtVersion ~= DB.version and MC.tick % 10 == 0 then
		UI.Render()
	elseif ui.main and ui.main:IsVisible() and MC.tick % 3 == 0 then
		SetText( ui.countText, MC.Num( DB.Count() ) )
	end
	if cardDirty then RenderCard() end
end

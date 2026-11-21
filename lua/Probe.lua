--------------------------------------------------------------------------------
-- MyContacts / Probe.lua
-- Только для отладочной сборки (tools/build.py --debug): пишет в mods.txt,
-- что приходит в событиях. В обычную и релизную сборку файл не попадает.
-- Включить в игре: /mc debug (выключить — так же).
--------------------------------------------------------------------------------
MC.Probe = {}
local Probe = MC.Probe

local function Val( v )
	local t = type( v )
	if t == "string" or t == "number" or t == "boolean" or t == "nil" then return tostring( v ) end
	if t == "userdata" then
		local api = apitype( v )
		if api == "WString" then return "W\"" .. userMods.FromWString( v ) .. "\"" end
		return tostring( v ) .. " api=" .. tostring( api )
	end
	return t
end
Probe.Val = Val

function Probe.Dump( t, prefix, depth, budget )
	budget = budget or { n = 120 }
	depth = depth or 0
	if type( t ) ~= "table" or depth > 3 then return end
	for k, v in pairs( t ) do
		if budget.n <= 0 then return end
		budget.n = budget.n - 1
		if type( v ) == "table" then
			MC.File( ( prefix or "" ) .. tostring( k ) .. " = {" )
			Probe.Dump( v, ( prefix or "" ) .. "  ", depth + 1, budget )
		else
			MC.File( ( prefix or "" ) .. tostring( k ) .. " = " .. Val( v ) )
		end
	end
end

-- События печатаются (не чаще 20 раз за сессию каждое)
local seen = {}
function Probe.Event( name )
	return function( p )
		if not MC.DEBUG then return end
		seen[ name ] = ( seen[ name ] or 0 ) + 1
		if seen[ name ] > 20 then return end
		MC.File( "событие " .. name .. " #" .. seen[ name ] )
		if name == "EVENT_UNITS_CHANGED" then
			MC.File( "  spawned=" .. tostring( p.spawned and #p.spawned ) .. " despawned=" .. tostring( p.despawned and #p.despawned ) )
			return
		end
		Probe.Dump( p, "  " )
	end
end

Probe.EVENTS = {
	"EVENT_UNITS_CHANGED", "EVENT_GROUP_MEMBER_ADDED", "EVENT_RAID_MEMBER_ADDED", "EVENT_GROUP_APPEARED", "EVENT_RAID_APPEARED",
	"EVENT_GROUP_CONVERTED", "EVENT_GROUP_MEMBER_REMOVED", "EVENT_RAID_MEMBER_REMOVED", "EVENT_GUILD_MEMBER_ADDED",
	"EVENT_GUILD_ACCEPTED", "EVENT_GUILD_APPEARED", "EVENT_GUILD_MEMBER_REMOVED", "EVENT_CHAT_MESSAGE_WITH_OBJECTS",
	"EVENT_OBJECT_NAME_CHANGED", "EVENT_INSPECT_STARTED", "EVENT_INSPECT_FINISHED", "EVENT_ADDON_REDUCE_PERFOMANCE",
}

-- Чат: что пришло (тип, эхо, UID)
local uidProbes = 0
function Probe.Chat( p )
	if not MC.DEBUG then return end
	seen.chat = ( seen.chat or 0 ) + 1
	if seen.chat > 30 then return end
	MC.File( "чат type=" .. tostring( p.chatType ) .. " echo=" .. tostring( p.isEcho ) .. " sender=" .. Val( p.sender ) ..
		" shard=" .. Val( p.shard ) .. " recipient=" .. Val( p.recipient ) .. " senderUniqueId=" .. Val( p.senderUniqueId ) )
	if p.senderUniqueId and uidProbes < 5 then
		uidProbes = uidProbes + 1
		MC.File( "  UID отправителя: " .. tostring( MC.DB.UidOf( p.senderUniqueId ) ) )
	end
end

function Probe.Report()
	MC.File( "MyContacts " .. MC.VERSION .. " — проверка API:" )
	MC.File( "  CHAT_TYPE_WHISPER = " .. tostring( CHAT_TYPE_WHISPER ) )
	MC.File( "  mission.GetShardName -> " .. Val( mission.GetShardName() ) )
	MC.File( "  common.GetLocalDateTime = {" )
	Probe.Dump( common.GetLocalDateTime(), "    " )
	MC.File( "  NowMin -> " .. tostring( MC.NowMin() ) .. " = " .. MC.FmtMin( MC.NowMin() ) )
	MC.File( "  свой UID: " .. tostring( MC.DB.UidOf( avatar.GetUniqueId() ) ) )
	MC.File( "  записей в базе: " .. MC.DB.Count() )
	MC.File( "  осмотр доступен: " .. tostring( avatar.IsInspectAllowed() ) )
	Probe.RatingApi()
end

--------------------------------------------------------------------------------
-- Рейтинг арен 3х3 и 6х6: что отдаёт matchMaking.GetRatingPvPScoreByUnitId.
-- Проверка перед записью рейтинга в базу. Что нужно узнать в игре:
--   1) данные есть сразу для любого игрока рядом или только после осмотра;
--   2) отдаются ли для игрока чужой фракции;
--   3) что возвращается для игрока без игр в сезоне;
--   4) приходят ли данные с задержкой (события о рейтинге в документации нет,
--      поэтому тот же игрок запрашивается повторно через 3 и 10 секунд).
-- Все записи начинаются со слова «рейтинг». Команда: /mc rating — вы сами и цель.
--------------------------------------------------------------------------------
local SEASON_FIELDS = { "over_game", "wins", "score", "top", "timeSpentMs" }
local RECHECK_SEC = { 3, 10 }   -- через сколько секунд повторить запрос
local QUEUE_LIMIT = 40          -- повторов в очереди одновременно
local NEAR_LIMIT = 10           -- игроков рядом за сессию — на каждую сторону (своя, чужая, неизвестна)
local TARGET_LIMIT = 30         -- смен цели за сессию
local INSPECT_LIMIT = 20        -- осмотров за сессию

-- Типы арен читаем при каждом запросе: так в журнале видно, знает ли клиент перечисление
local function Arenas()
	return {
		{ "3x3", ENUM_RatingArenaType_3x3 },
		{ "6x6", ENUM_RatingArenaType_6x6 },
		{ "HPI", ENUM_RatingArenaType_HPI },
	}
end

-- Один сезон одной строкой: поля из документации по порядку, затем всё, чего в документации нет
local function Season( t )
	-- Ожидаем: сезона может не быть (lastSeason — «table or nil») — пишем, что пришло
	if type( t ) ~= "table" then return Val( t ) end
	local parts, known = {}, { difficulty = true }
	for _, k in ipairs( SEASON_FIELDS ) do
		known[ k ] = true
		parts[ #parts + 1 ] = k .. "=" .. Val( t[ k ] )
	end
	local d = t.difficulty
	parts[ #parts + 1 ] = "difficulty=" .. ( type( d ) == "table" and Val( d.name ) or Val( d ) )
	for k, v in pairs( t ) do
		if not known[ k ] then parts[ #parts + 1 ] = "(нет в документации) " .. tostring( k ) .. "=" .. Val( v ) end
	end
	return "{ " .. table.concat( parts, " " ) .. " }"
end

local function FactionName( id )
	local fid = unit.GetFactionId( id )
	-- Ожидаем: у юнита может не оказаться фракции или её описания — фракция неизвестна
	if not fid then return "" end
	local info = fid:GetInfo()
	if type( info ) ~= "table" then return "" end
	return MC.S( info.name )
end

-- Сторона игрока относительно нас: "своя", "чужая", "неизвестна" — и название фракции
local function Side( id )
	local his = FactionName( id )
	if id == avatar.GetId() then return "своя", his end
	local mine = FactionName( avatar.GetId() )
	if his == "" or mine == "" then return "неизвестна", his end
	return ( his == mine ) and "своя" or "чужая", his
end

-- Осматриваем ли мы сейчас этого игрока
local function Inspected( id )
	-- Ожидаем: в PvP-активностях с голосованием за изгнание осмотр аддонам недоступен
	if not avatar.IsInspectAllowed() then return "недоступно" end
	local info = avatar.GetInspectInfo()
	return tostring( type( info ) == "table" and info.playerId == id )
end

-- Строки с ответом игры по одному игроку (без ника: по ним же сравниваем первый запрос с повторным)
local function RatingLines( id )
	local lines = {}
	local available = matchMaking.IsRatingPvPScoreAvailable()
	lines[ 1 ] = "  IsRatingPvPScoreAvailable=" .. tostring( available ) .. " осматривается=" .. Inspected( id )
	-- Ожидаем: в части активностей рейтинг недоступен (документация GetRatingPvPScoreByUnitId) — не запрашиваем
	if not available then return lines end
	for _, a in ipairs( Arenas() ) do
		local label, arena = "  " .. a[ 1 ] .. " (тип=" .. tostring( a[ 2 ] ) .. "): ", a[ 2 ]
		if arena == nil then
			-- Ожидаем: клиент может не знать этот тип арены — пишем это и не запрашиваем
			lines[ #lines + 1 ] = label .. "перечисление не определено"
		else
			local info = matchMaking.GetRatingPvPScoreByUnitId( arena, id )
			if type( info ) ~= "table" then
				-- Ожидаем: nil, если игра не дала данных («table or nil»)
				lines[ #lines + 1 ] = label .. Val( info )
			else
				lines[ #lines + 1 ] = label .. "currentSeason=" .. Season( info.currentSeason )
				lines[ #lines + 1 ] = "      lastSeason=" .. Season( info.lastSeason )
				for k, v in pairs( info ) do
					if k ~= "currentSeason" and k ~= "lastSeason" then
						lines[ #lines + 1 ] = "      (нет в документации) " .. tostring( k ) .. "=" .. Val( v )
					end
				end
			end
		end
	end
	return lines
end

-- Запись в журнал: кто, чья фракция и что ответила игра. Возвращает ответ одной строкой — для сравнения
local function Rating( id, why, lines )
	lines = lines or RatingLines( id )
	local side, faction = Side( id )
	MC.File( "рейтинг [" .. why .. "] ник=" .. MC.S( object.GetName( id ) ) .. " id=" .. tostring( id ) .. " фракция=" .. side ..
		" (" .. faction .. ") друг=" .. tostring( object.IsFriend( id ) ) .. " враг=" .. tostring( object.IsEnemy( id ) ) )
	for _, l in ipairs( lines ) do MC.File( l ) end
	return table.concat( lines, "\n" )
end

-- Первый запрос по игроку и повторы через несколько секунд
local queue = {}
local function First( id, why )
	local answer = Rating( id, why )
	if #queue >= QUEUE_LIMIT then return end
	local name, now = MC.S( object.GetName( id ) ), MC.NowMs()
	for _, sec in ipairs( RECHECK_SEC ) do
		queue[ #queue + 1 ] = { id = id, name = name, why = why, sec = sec, at = now + sec * 1000, answer = answer }
	end
end

local function Recheck( q )
	local why = "повтор через " .. q.sec .. " с после «" .. q.why .. "»"
	-- Ожидаем: за это время игрок мог уйти из видимости (или id занял другой) — повторить нельзя, пишем это
	if not object.IsExist( q.id ) or MC.S( object.GetName( q.id ) ) ~= q.name then
		MC.File( "рейтинг [" .. why .. "] ник=" .. q.name .. ": игрока уже не видно" )
		return
	end
	local lines = RatingLines( q.id )
	if table.concat( lines, "\n" ) == q.answer then
		MC.File( "рейтинг [" .. why .. "] ник=" .. q.name .. ": без изменений" )
		return
	end
	Rating( q.id, why .. ", ОТВЕТ ИЗМЕНИЛСЯ", lines )
end

-- Раз в секунду: пришло ли время повторов (пустая очередь — сразу выход)
function Probe.RatingSecond()
	if #queue == 0 then return end
	-- отладку выключили — оставшиеся повторы не нужны
	if not MC.DEBUG then queue = {} return end
	local now, rest = MC.NowMs(), {}
	for _, q in ipairs( queue ) do
		if q.at > now then rest[ #rest + 1 ] = q else Recheck( q ) end
	end
	queue = rest
end

local function IsPlayerUnit( id )
	-- Ожидаем: цели или юнита может не быть, он мог уйти из видимости, быть не игроком или питомцем — пропускаем
	return id ~= nil and object.IsExist( id ) and unit.IsPlayer( id ) and not unit.IsPet( id )
end

-- Игроки рядом при появлении: каждый ник один раз, не больше NEAR_LIMIT на сторону
local nearSeen, nearCount = {}, {}
function Probe.RatingSpawned( p )
	if not MC.DEBUG then return end
	local list = p and p.spawned
	if type( list ) ~= "table" then return end
	for _, id in pairs( list ) do
		if id ~= avatar.GetId() and IsPlayerUnit( id ) then
			local name, side = MC.S( object.GetName( id ) ), Side( id )
			local n = nearCount[ side ] or 0
			-- Ожидаем: ник бывает ещё не определён (пустая строка) — такого пропускаем
			if name ~= "" and not nearSeen[ name ] and n < NEAR_LIMIT then
				nearSeen[ name ] = true
				nearCount[ side ] = n + 1
				First( id, "рядом, " .. side .. " #" .. ( n + 1 ) )
			end
		end
	end
end

local targetCount = 0
function Probe.RatingTarget()
	if not MC.DEBUG or targetCount >= TARGET_LIMIT then return end
	local id = avatar.GetTarget()
	if not IsPlayerUnit( id ) then return end
	targetCount = targetCount + 1
	First( id, "цель #" .. targetCount )
end

local inspectCount = 0
function Probe.RatingInspect()
	if not MC.DEBUG or inspectCount >= INSPECT_LIMIT then return end
	inspectCount = inspectCount + 1
	-- Ожидаем: в PvP-активностях с голосованием за изгнание осмотр аддонам недоступен — кого осматривают, не узнать
	if not avatar.IsInspectAllowed() then
		MC.File( "рейтинг [осмотр #" .. inspectCount .. "]: avatar.IsInspectAllowed()=false" )
		return
	end
	local info = avatar.GetInspectInfo()
	local id = nil
	if type( info ) == "table" then id = info.playerId end
	-- Ожидаем: playerId — «ObjectId or nil»
	if not IsPlayerUnit( id ) then
		MC.File( "рейтинг [осмотр #" .. inspectCount .. "]: осматриваемого игрока нет (playerId=" .. tostring( id ) .. ")" )
		return
	end
	First( id, "осмотр #" .. inspectCount )
end

-- Доступность и значения перечисления (в отчёте при включении отладки и по команде)
function Probe.RatingApi()
	MC.File( "  рейтинг: IsRatingPvPScoreAvailable -> " .. tostring( matchMaking.IsRatingPvPScoreAvailable() ) ..
		", ENUM_RatingArenaType 3x3=" .. tostring( ENUM_RatingArenaType_3x3 ) .. " 6x6=" .. tostring( ENUM_RatingArenaType_6x6 ) ..
		" HPI=" .. tostring( ENUM_RatingArenaType_HPI ) )
end

-- /mc rating: вы сами и текущая цель, без ограничений по количеству
function Probe.RatingCommand()
	if not MC.DEBUG then
		MC.Chat( "сначала включите отладку: /mc debug" )
		return
	end
	MC.File( "рейтинг: команда /mc rating" )
	Probe.RatingApi()
	First( avatar.GetId(), "команда, я сам" )
	local id = avatar.GetTarget()
	if id ~= avatar.GetId() and IsPlayerUnit( id ) then
		First( id, "команда, цель" )
	else
		MC.File( "рейтинг [команда, цель]: в цели нет другого игрока" )
	end
	MC.Chat( "рейтинг арен (вы и цель) записан в Personal\\Logs\\mods.txt, повтор через 3 и 10 с" )
end

-- События, на которые подписывает Main.lua
Probe.RATING_HANDLERS = {
	EVENT_UNITS_CHANGED = Probe.RatingSpawned,
	EVENT_AVATAR_TARGET_CHANGED = Probe.RatingTarget,
	EVENT_INSPECT_STARTED = Probe.RatingInspect,
	EVENT_SECOND_TIMER = Probe.RatingSecond,
}

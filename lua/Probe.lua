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
-- Проверка в игре (около 200 игроков) закончена: данные приходят сразу для любого игрока рядом,
-- своей и чужой фракции, без осмотра и без задержки; у игрока без игр — сезон с нулями.
-- Рейтинг записывает Game.lua, а здесь осталась команда /mc rating: полный ответ игры
-- про вас и про цель — в журнал (записи начинаются со слова «рейтинг»).
--------------------------------------------------------------------------------
local SEASON_FIELDS = { "over_game", "wins", "score", "top", "timeSpentMs" }

-- Типы арен читаем при каждом запросе: так в журнале видно, знает ли клиент перечисление
local function Arenas()
	return {
		{ "3x3", ENUM_RatingArenaType_3x3 },
		{ "6x6", ENUM_RatingArenaType_6x6 },
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

-- Запись в журнал: кто и что ответила игра
local function Rating( id, why )
	MC.File( "рейтинг [" .. why .. "] ник=" .. MC.S( object.GetName( id ) ) .. " id=" .. tostring( id ) )
	local available = matchMaking.IsRatingPvPScoreAvailable()
	MC.File( "  IsRatingPvPScoreAvailable=" .. tostring( available ) )
	-- Ожидаем: в части активностей рейтинг недоступен (документация GetRatingPvPScoreByUnitId) — не запрашиваем
	if not available then return end
	for _, a in ipairs( Arenas() ) do
		local label, arena = "  " .. a[ 1 ] .. " (тип=" .. tostring( a[ 2 ] ) .. "): ", a[ 2 ]
		if arena == nil then
			-- Ожидаем: клиент может не знать этот тип арены — пишем это и не запрашиваем
			MC.File( label .. "перечисление не определено" )
		else
			local info = matchMaking.GetRatingPvPScoreByUnitId( arena, id )
			if type( info ) ~= "table" then
				-- Ожидаем: nil, если игра не дала данных («table or nil»)
				MC.File( label .. Val( info ) )
			else
				MC.File( label .. "currentSeason=" .. Season( info.currentSeason ) )
				MC.File( "      lastSeason=" .. Season( info.lastSeason ) )
				for k, v in pairs( info ) do
					if k ~= "currentSeason" and k ~= "lastSeason" then
						MC.File( "      (нет в документации) " .. tostring( k ) .. "=" .. Val( v ) )
					end
				end
			end
		end
	end
end

-- Доступность и значения перечисления (в отчёте при включении отладки и по команде)
function Probe.RatingApi()
	MC.File( "  рейтинг: IsRatingPvPScoreAvailable -> " .. tostring( matchMaking.IsRatingPvPScoreAvailable() ) ..
		", ENUM_RatingArenaType 3x3=" .. tostring( ENUM_RatingArenaType_3x3 ) .. " 6x6=" .. tostring( ENUM_RatingArenaType_6x6 ) ..
		" HPI=" .. tostring( ENUM_RatingArenaType_HPI ) )
end

-- /mc rating: вы сами и текущая цель
function Probe.RatingCommand()
	if not MC.DEBUG then
		MC.Chat( "сначала включите отладку: /mc debug" )
		return
	end
	MC.File( "рейтинг: команда /mc rating" )
	Probe.RatingApi()
	Rating( avatar.GetId(), "я сам" )
	local id = avatar.GetTarget()
	-- Ожидаем: цели может не быть, она могла уйти из видимости, быть не игроком или питомцем — пишем это
	if id ~= nil and id ~= avatar.GetId() and object.IsExist( id ) and unit.IsPlayer( id ) and not unit.IsPet( id ) then
		Rating( id, "цель" )
	else
		MC.File( "рейтинг [цель]: в цели нет другого игрока" )
	end
	MC.Chat( "рейтинг арен (вы и цель) записан в Personal\\Logs\\mods.txt" )
end

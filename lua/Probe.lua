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
	"EVENT_OBJECT_NAME_CHANGED", "EVENT_INSPECT_STARTED", "EVENT_ADDON_REDUCE_PERFOMANCE",
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
end

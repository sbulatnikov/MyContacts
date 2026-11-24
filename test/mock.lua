-- Заглушки игрового API для прогона скриптов MyContacts в texlua (Lua 5.3)
function Global( n, v ) _G[ n ] = v end
unpack = unpack or table.unpack
table.maxn = table.maxn or function( t ) local m = 0 for k in pairs( t ) do if type( k ) == "number" and k > m then m = k end end return m end

local WSmt = { __eq = function( a, b ) return a.s == b.s end }
WSmt.__index = {
	ToLower = function( w ) return setmetatable( { s = string.lower( w.s ) }, WSmt ) end,
	IsEmpty = function( w ) return w.s == "" end,
}
local function WSt( s ) return setmetatable( { s = s }, WSmt ) end
WS_ = WSt
local rawtype = type
function type( v ) if rawtype( v ) == "table" and ( getmetatable( v ) == WSmt or v.__uid ) then return "userdata" end return rawtype( v ) end
function apitype( v )
	if rawtype( v ) == "table" and getmetatable( v ) == WSmt then return "WString" end
	if rawtype( v ) == "table" and v.__uid then return "UniqueId" end
	return rawtype( v )
end

CHAT = {}
LOG = {}           -- всё, что аддон записал в mods.txt (common.LogInfo)
CONFIG = {}
function deep( t ) if rawtype( t ) ~= "table" or getmetatable( t ) then return t end local r = {} for k, v in pairs( t ) do r[ k ] = deep( v ) end return r end
userMods = {
	ToWString = function( s ) return WSt( s ) end,
	FromWString = function( w ) if rawtype( w ) == "table" and getmetatable( w ) == WSmt then return w.s end error( "not WString" ) end,
	GetGlobalConfigSection = function( n ) return CONFIG[ n ] and deep( CONFIG[ n ] ) end,
	SetGlobalConfigSection = function( n, t ) CONFIG[ n ] = deep( t ) end,
	SendSelfChatMessage = function( w, lvl ) CHAT[ #CHAT + 1 ] = "[" .. tostring( lvl ) .. "] " .. w.s print( "  [chat:" .. tostring( lvl ) .. "] " .. w.s ) end,
	GetResourcePersistentId = function( u ) if PERSIST and rawtype( u ) == "table" and u.__uid then return "UID" .. u.__uid end error( "bad" ) end,
}
EVENTS, REACTIONS = {}, {}
NOW = 100000
DATE = { y = 2026, m = 11, d = 13, h = 21, min = 40, s = 0 }
common = {
	GetAddonName = function() return "MyContacts" end,
	RegisterEventHandler = function( f, ev ) local prev = EVENTS[ ev ] EVENTS[ ev ] = prev and function( p ) prev( p ) f( p ) end or f end,
	RegisterReactionHandler = function( f, r ) REACTIONS[ r ] = f end,
	GetAbsTimeMs = function() return NOW end,
	GetLocalDateTime = function() return deep( DATE ) end,
	LogInfo = function( _, s )
		local line = rawtype( s ) == "table" and s.s or tostring( s )
		LOG[ #LOG + 1 ] = line
		if VERBOSE then print( "  [mods.txt] " .. line ) end
	end,
	GetAddonRelatedTextureGroup = function() return { HasTexture = function() return true end, GetTexture = function( _, k ) return "tex:" .. k end } end,
	GetPosConverterParams = function() return {} end,
	GetApiType = function() return "UniqueId" end,
}

local Widget = {}
Widget.__index = function( w, k ) if Widget[ k ] then return Widget[ k ] end if string.match( k, "^%u" ) then return function() end end return nil end
local all = {}
local function NewW( name, parent )
	local w = setmetatable( { name = name, parent = parent, kids = {}, visible = true, text = "", pl = { posX = 0, posY = 0, sizeX = 10, sizeY = 10 } }, Widget )
	all[ #all + 1 ] = w
	return w
end
function Widget.GetName( w ) return w.name end
function Widget.SetName( w, n ) w.name = n end
function Widget.GetParent( w ) return w.parent end
function Widget.GetChildChecked( w, n, rec )
	if not w.kids[ n ] then w.kids[ n ] = NewW( n, w ) end
	return w.kids[ n ]
end
function Widget.Show( w, on ) w.visible = on end
function Widget.IsVisible( w ) return w.visible end
function Widget.SetVal( w, tag, v ) w.val = v.s end
function Widget.SetVariant( w, v ) w.variant = v end
function Widget.SetBackgroundTexture( w, t ) w.tex = t end
function Widget.GetPlacementPlain( w ) return deep( w.pl ) end
function Widget.SetPlacementPlain( w, p ) w.pl = deep( p ) end
function Widget.GetRealRect( w ) return { x1 = 10, y1 = 10, x2 = 50, y2 = 30 } end
function Widget.GetText( w ) return WSt( w.text ) end
function Widget.SetText( w, t ) w.text = t.s end
function Widget.Enable( w, on ) w.enabled = on end
function Widget.SetFade( w, a ) w.fade = a end
function Widget.GetInstanceId( w ) return tostring( w ) end
function Widget.DNDRegisterGeneric() return #all end
mainForm = NewW( "MyContacts" )
function FIND( name ) return mainForm:GetChildChecked( name, true ) end

-- Мир
UID = function( n ) return { __uid = n, IsEqual = function( a, b ) return rawtype( b ) == "table" and a.__uid == b.__uid end,
	GetInstanceId = function( a ) local h = "" for i = 1, #a.__uid do h = h .. string.format( "%02x", a.__uid:byte( i ) ) end return "userdata: 0x" .. h end } end
ME = { name = "Я", id = 1, fac = "Лига" }
UNITS = {}         -- [id] = { name, shard, fac, cls, gs }
STATE = { group = {}, raid = false, guild = {}, target = nil, inspect = nil, inspectAllowed = true, ratingAvailable = true }
avatar = {
	IsInspectAllowed = function() return STATE.inspectAllowed end,
	IsExist = function() return true end,
	GetId = function() return ME.id end,
	GetUniqueId = function() return UID( "me" ) end,
	GetTarget = function() return STATE.target end,
	GetUnitList = function() local t = {} for id in pairs( UNITS ) do t[ #t + 1 ] = id end return t end,
	GetInspectInfo = function()
		if not STATE.inspectAllowed then error( "GetInspectInfo: осмотр недоступен" ) end
		return { rank = 1, playerId = STATE.inspect }
	end,
}
object = {
	IsExist = function( id ) return id == ME.id or UNITS[ id ] ~= nil end,
	GetName = function( id ) if id == ME.id then return WSt( ME.name ) end return WSt( UNITS[ id ].name ) end,
	IsFriend = function( id ) return id == ME.id or UNITS[ id ].fac == ME.fac end,
	IsEnemy = function( id ) return id ~= ME.id and UNITS[ id ].fac ~= ME.fac end,
}
unit = {
	IsPlayer = function( id ) return id == ME.id or UNITS[ id ] ~= nil end,
	IsPet = function() return false end,
	GetPlayerShardName = function( id ) return WSt( UNITS[ id ] and UNITS[ id ].shard or "Нить судьбы" ) end,
	GetFactionId = function( id ) local u = id == ME.id and ME or UNITS[ id ] return { GetInfo = function() return { name = WSt( u.fac ) } end } end,
	GetClass = function( id ) return { className = UNITS[ id ].cls } end,
	GetGearScore = function( id ) return UNITS[ id ].gs end,
	GetGuildInfo = function( id ) local g = UNITS[ id ].guild if not g then return nil end return { name = WSt( g ), rank = UNITS[ id ].rank } end,
}
mission = { GetShardName = function() return WSt( "Нить судьбы" ) end }
cartographer = { GetCurrentZoneInfo = function() return { zoneName = WSt( STATE.zone or "Новоград" ) } end }
group = { GetMembers = function()
	local t = { { name = WSt( ME.name ) } }
	for _, m in ipairs( STATE.group ) do t[ #t + 1 ] = { name = WSt( m.name ), uniqueId = m.uid } end
	return t
end }
raid = { IsExist = function() return false end }
guild = {
	IsExist = function() return true end,
	GetMembers = function() local t = {} for i, n in ipairs( STATE.guild ) do t[ #t + 1 ] = i end return t end,
	GetMemberInfo = function( i ) return { name = WSt( STATE.guild[ i ] ) } end,
}
-- Рейтинг арен: RATING[ id юнита ][ тип арены ] = ответ игры.
-- Как в игре: у игрока, про которого ничего не задано, — сезон с нулями (игр нет), прошлого сезона нет.
-- false вместо ответа (RATING[ id ] = false или RATING[ id ][ тип ] = false) — игра вернула nil.
-- Запрос при IsRatingPvPScoreAvailable() == false здесь — ошибка: аддон обязан проверять заранее.
ENUM_RatingArenaType_3x3, ENUM_RatingArenaType_6x6, ENUM_RatingArenaType_HPI = 0, 1, 2
RATING = {}
RATING_CALLS = 0
matchMaking = {
	IsRatingPvPScoreAvailable = function() return STATE.ratingAvailable end,
	GetRatingPvPScoreByUnitId = function( arena, id )
		if not STATE.ratingAvailable then error( "GetRatingPvPScoreByUnitId: рейтинг недоступен" ) end
		if arena == nil or not ( id == ME.id or UNITS[ id ] ) then error( "GetRatingPvPScoreByUnitId: плохие параметры" ) end
		RATING_CALLS = RATING_CALLS + 1
		local answer = RATING[ id ]
		if answer ~= nil and answer ~= false then answer = answer[ arena ] end
		if answer == false then return nil end
		if answer == nil then return { currentSeason = { over_game = 0, wins = 0, score = 0, top = 0, timeSpentMs = 0 } } end
		return deep( answer )
	end,
}
CHAT_TYPE_WHISPER = 7
WIDGET_ALIGN_LOW_ABS = 3

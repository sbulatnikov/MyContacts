--------------------------------------------------------------------------------
-- MyContacts / Util.lua
-- Общие помощники: строки, чат, время, кэш виджетов. При сборке переводится в Windows-1251.
--------------------------------------------------------------------------------
Global( "MC", {} )

MC.VERSION = "0.9.2"
MC.tick = 0               -- секунды с запуска (EVENT_SECOND_TIMER)
MC.NICK_MIN = 3
MC.NICK_MAX = 14

--------------------------------------------------------------------------------
-- Строки
--------------------------------------------------------------------------------
function MC.WS( s )
	return userMods.ToWString( s or "" )
end

-- Обычная строка из string или WString
function MC.S( v )
	if type( v ) == "string" then return v end
	-- Ожидаем: на входе может быть не строка (nil, число, другой объект API) — тогда пустая строка
	if v ~= nil and apitype( v ) == "WString" then return userMods.FromWString( v ) end
	return ""
end

function MC.Trim( s )
	return ( string.gsub( s or "", "^%s*(.-)%s*$", "%1" ) )
end

-- Строка в UTF-8 с многобайтными символами?
local function IsUtf8( s )
	local i, len, multi = 1, #s, false
	while i <= len do
		local c = string.byte( s, i )
		local k = ( c < 0x80 and 1 ) or ( c >= 0xC2 and c <= 0xDF and 2 ) or ( c >= 0xE0 and c <= 0xEF and 3 ) or ( c >= 0xF0 and c <= 0xF4 and 4 ) or 0
		if k == 0 or i + k - 1 > len then return false end
		for j = i + 1, i + k - 1 do
			local b = string.byte( s, j )
			if b < 0x80 or b > 0xBF then return false end
		end
		if k > 1 then multi = true end
		i = i + k
	end
	return multi
end

-- Нижний регистр для латиницы и кириллицы (UTF-8 или Windows-1251)
function MC.Lower( s )
	s = s or ""
	if IsUtf8( s ) then
		s = string.gsub( s, "\208([\144-\175])", function( c )
			local b = string.byte( c )
			if b <= 0x9F then return "\208" .. string.char( b + 0x20 ) end -- А..П -> а..п
			return "\209" .. string.char( b - 0x20 )                          -- Р..Я -> р..я
		end )
		s = string.gsub( s, "\208\129", "\209\145" ) -- Ё -> ё
		return ( string.gsub( s, "%u", string.lower ) )
	end
	return ( string.gsub( s, ".", function( c )
		local b = string.byte( c )
		if ( b >= 65 and b <= 90 ) or ( b >= 0xC0 and b <= 0xDF ) then return string.char( b + 32 ) end
		if b == 0xA8 then return string.char( 0xB8 ) end
		return c
	end ) )
end

-- Длина в символах (UTF-8 или однобайтная кодировка)
function MC.CharLen( s )
	s = s or ""
	if not IsUtf8( s ) then return #s end
	local n = 0
	for _ in string.gmatch( s, "[^\128-\191]" ) do n = n + 1 end
	return n
end

function MC.F( fmt, ... )
	return string.format( fmt, ... )
end

--------------------------------------------------------------------------------
-- Чат
--------------------------------------------------------------------------------
-- Системное сообщение в чат (видно только себе). raw = без префикса аддона
function MC.Chat( text, level, raw )
	userMods.SendSelfChatMessage( MC.WS( ( raw and "" or "[MyContacts] " ) .. tostring( text ) ), level or "message" )
end

function MC.NowMs()
	return common.GetAbsTimeMs()
end

--@debug
--------------------------------------------------------------------------------
-- Отладочная сборка: запись в Personal\\Logs\\mods.txt (в обычной сборке этого блока нет)
--------------------------------------------------------------------------------
MC.DEBUG = false

local function Join( ... )
	local parts = {}
	for i = 1, select( "#", ... ) do
		local v = ( select( i, ... ) )
		local s = MC.S( v )
		if s == "" and type( v ) ~= "string" then s = tostring( v ) end
		parts[ #parts + 1 ] = s
	end
	return table.concat( parts, " " )
end

function MC.File( text )
	common.LogInfo( "common", MC.WS( "[MyContacts] " .. tostring( text ) ) )
end

function MC.Log( ... )
	if MC.DEBUG then MC.File( Join( ... ) ) end
end
--@end

function MC.MyName()
	if avatar.IsExist() then return MC.S( object.GetName( avatar.GetId() ) ) end
	return ""
end

--------------------------------------------------------------------------------
-- Виджеты (как в RPL: кэш и пропуск повторных вызовов с тем же значением)
--------------------------------------------------------------------------------
local widgetCache = {}

function MC.W( name )
	local w = widgetCache[ name ]
	if w == nil then
		w = mainForm:GetChildChecked( name, true ) or false
		widgetCache[ name ] = w
	end
	return w or nil
end

function MC.Child( parent, name )
	if not parent then return nil end
	return parent:GetChildChecked( name, false )
end

local memo = setmetatable( {}, { __mode = "k" } )
local function M( w )
	local m = memo[ w ]
	if not m then m = {} memo[ w ] = m end
	return m
end

function MC.Show( w, on )
	if not w then return end
	on = on and true or false
	local m = M( w )
	if m.show ~= on then m.show = on w:Show( on ) end
end

function MC.Enable( w, on )
	if not w then return end
	on = on and true or false
	local m = M( w )
	if m.enable ~= on then m.enable = on w:Enable( on ) end
end

function MC.Fade( w, a )
	if not w then return end
	local m = M( w )
	if m.fade ~= a then m.fade = a w:SetFade( a ) end
end

function MC.SetText( w, s )
	if not w then return end
	s = s or ""
	local m = M( w )
	if m.text ~= s then m.text = s w:SetVal( "value", MC.WS( s ) ) end
end

function MC.SetVariant( w, v )
	if not w then return end
	local m = M( w )
	if m.variant ~= v then m.variant = v w:SetVariant( v ) end
end

local iconGroup = nil
function MC.Tex( key )
	if iconGroup == nil then
		iconGroup = common.GetAddonRelatedTextureGroup( "Icons", true ) or false
	end
	if iconGroup and iconGroup:HasTexture( key ) then return iconGroup:GetTexture( key ) end
	return nil
end

function MC.SetTex( w, key )
	if not w or not key then return end
	local m = M( w )
	if m.tex == key then return end
	local t = MC.Tex( key )
	if t then m.tex = key w:SetBackgroundTexture( t ) end
end

--------------------------------------------------------------------------------
-- Время: минуты от 01.01.2000 по локальным часам клиента (короткое целое для базы)
--------------------------------------------------------------------------------
local function DaysFromCivil( y, m, d )
	y = ( m <= 2 ) and ( y - 1 ) or y
	local era = math.floor( y / 400 )
	local yoe = y - era * 400
	local mp = ( m + 9 ) % 12
	local doy = math.floor( ( 153 * mp + 2 ) / 5 ) + d - 1
	local doe = yoe * 365 + math.floor( yoe / 4 ) - math.floor( yoe / 100 ) + doy
	return era * 146097 + doe - 719468
end
local DAY2000 = DaysFromCivil( 2000, 1, 1 )

function MC.CivilFromDays( z )
	z = z + 719468
	local era = math.floor( z / 146097 )
	local doe = z - era * 146097
	local yoe = math.floor( ( doe - math.floor( doe / 1460 ) + math.floor( doe / 36524 ) - math.floor( doe / 146096 ) ) / 365 )
	local y = yoe + era * 400
	local doy = doe - ( 365 * yoe + math.floor( yoe / 4 ) - math.floor( yoe / 100 ) )
	local mp = math.floor( ( 5 * doy + 2 ) / 153 )
	local d = doy - math.floor( ( 153 * mp + 2 ) / 5 ) + 1
	local m = mp < 10 and mp + 3 or mp - 9
	if m <= 2 then y = y + 1 end
	return y, m, d
end

local function Field( t, ... )
	for i = 1, select( "#", ... ) do
		local v = t[ ( select( i, ... ) ) ]
		if type( v ) == "number" then return v end
	end
	return nil
end

-- Текущее время в минутах от 2000 года. nil, если игра не дала дату
function MC.NowMin()
	local t = common.GetLocalDateTime()
	-- Ожидаем: поля даты называются по-разному (y/year, m/month...) — Field перебирает оба варианта
	if type( t ) == "table" then
		local y, m, d = Field( t, "y", "year" ), Field( t, "m", "month" ), Field( t, "d", "day" )
		local h, mi = Field( t, "h", "hour" ) or 0, Field( t, "min", "minute" ) or 0
		if y and m and d then
			return ( DaysFromCivil( y, m, d ) - DAY2000 ) * 1440 + h * 60 + mi
		end
	end
	return nil
end

-- «13.11.2026 21:40»
function MC.FmtMin( v )
	if type( v ) ~= "number" or v <= 0 then return "—" end
	local days = math.floor( v / 1440 )
	local rest = v - days * 1440
	local y, m, d = MC.CivilFromDays( days + DAY2000 )
	return string.format( "%02d.%02d.%04d %02d:%02d", d, m, y, math.floor( rest / 60 ), rest % 60 )
end

function MC.FmtDate( v )
	if type( v ) ~= "number" or v <= 0 then return "—" end
	local y, m, d = MC.CivilFromDays( math.floor( v / 1440 ) + DAY2000 )
	return string.format( "%02d.%02d.%04d", d, m, y )
end

-- Число с пробелами: 41250 -> «41 250»
function MC.Num( n )
	local s = tostring( math.floor( n or 0 ) )
	local r = string.gsub( s, "^(-?%d+)(%d%d%d)", "%1 %2" )
	while r ~= s do s = r r = string.gsub( s, "^(-?%d+)(%d%d%d)", "%1 %2" ) end
	return s
end

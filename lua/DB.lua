--------------------------------------------------------------------------------
-- MyContacts / DB.lua
-- База игроков (формат 2). Две ступени хранения:
--   MyContacts_DB_NN  — запись игрока одной строкой;
--   MyContacts_Cards  — отметка, заметки, история ников и гильдий (только у таких игроков).
-- В базу попадают:
--   * игроки с постоянным ID (UniqueId -> GetInstanceId, строка 0x...): группа, отряд, личка;
--   * игроки, добавленные вручную по нику: хранятся всегда, ID подтянется при встрече.
-- Игроки рядом и цель новых записей не создают, только обновляют известные.
-- Ключ записи: "U<id>" или "N<ник>@<номер сервера>" (вручную, пока ID неизвестен).
-- Строки ников, серверов и зон — в кодировке клиента (как отдаёт FromWString).
--
-- Как расширять запись, не очищая базу. Строка записи — 15 постоянных полей через «|», за ними
-- «хвост» из необязательных полей вида ключ=значение («…|m|c=3,7»). Версия аддона, которая ключа
-- не знает, поле не теряет: хранит как есть (r.ext) и пишет обратно. Поэтому SCHEMA при добавлении
-- поля НЕ меняем (смена SCHEMA стирает базу у всех). Новое поле (например, рейтинги арен 3х3 и 6х6):
--   1) придумать короткий ключ из латинских букв и цифр («a3», «a6»);
--   2) добавить его в TAIL: pack( r ) -> строка или nil (nil — поле не пишется, так у большинства
--      игроков запись не растёт), unpack( r, значение );
--   3) в значении нельзя «|» и перевод строки; числа и списки через запятую подходят.
-- Постоянные 15 полей не трогаем и не переставляем: их по номерам читает и версия 0.9.2
-- (она хвост не понимает и при записи куска отбрасывает — сама база при этом цела).
--------------------------------------------------------------------------------
MC.DB = {}
local DB = MC.DB

local NCHUNK = 64
local META = "MyContacts_Meta"
local CARDS = "MyContacts_Cards"
local SEP = "|"
local SCHEMA = 2        -- формат базы; при другом формате база очищается при загрузке
-- секции прошлых версий и проверок 0.1.1
local LEGACY = { "MyContacts_Test", "MyContacts_T1", "MyContacts_T2", "MyContacts_Scan", "MyContacts_UidLog" }

local P = {}            -- [key] = rec
local byName = {}       -- [ник_lower .. "@" .. сервер] = key (текущий ник)
local byUid = {}        -- [uid-строка] = key
local dict = { shard = {}, zone = {}, cls = {}, guild = {} }
local dictIdx = { shard = {}, zone = {}, cls = {}, guild = {} }
local dirty = {}        -- [номер куска] = true
local cardsDirty = false
local metaDirty = false
local count = 0
DB.players = P
DB.version = 0          -- растёт при каждом изменении состава или полей (для пересчёта списка)

--------------------------------------------------------------------------------
-- Словари (серверы, зоны, классы): в записи хранится номер
--------------------------------------------------------------------------------
function DB.DictId( kind, s )
	if not s or s == "" then return 0 end
	local id = dictIdx[ kind ][ s ]
	if id then return id end
	local list = dict[ kind ]
	list[ #list + 1 ] = s
	id = #list
	dictIdx[ kind ][ s ] = id
	metaDirty = true
	return id
end

function DB.DictName( kind, id )
	return ( id and id > 0 and dict[ kind ][ id ] ) or ""
end

--------------------------------------------------------------------------------
-- Ключи и куски
--------------------------------------------------------------------------------
local function Chunk( key )
	local h = 0
	for i = 1, #key do h = ( h * 31 + string.byte( key, i ) ) % 1000003 end
	return h % NCHUNK
end

local function ChunkName( n )
	return string.format( "MyContacts_DB_%02d", n )
end

local function NameKey( nameL, sh )
	return nameL .. "@" .. tostring( sh or 0 )
end

local function MarkDirty( key )
	dirty[ Chunk( key ) ] = true
	DB.version = DB.version + 1
end

local function HasCard( r )
	return ( r.mark and r.mark ~= 0 ) or ( r.notes and #r.notes > 0 ) or ( r.names and #r.names > 0 ) or ( r.gh and #r.gh > 0 ) or false
end

local function Clean( s )
	return ( string.gsub( tostring( s or "" ), "[|\r\n]", " " ) )
end

--------------------------------------------------------------------------------
-- Хвост записи: необязательные поля ключ=значение (см. «Как расширять запись» в начале файла)
--------------------------------------------------------------------------------
local FIXED = 15        -- число постоянных полей; всё, что дальше, — хвост

-- c — прежние классы игрока (номера словаря cls через запятую, недавние первыми).
-- Текущий класс лежит в постоянном поле cls, поэтому у игрока с одним классом хвоста нет.
local TAIL = {
	c = {
		pack = function( r )
			if not r.cp or #r.cp == 0 then return nil end
			return table.concat( r.cp, "," )
		end,
		unpack = function( r, v )
			local list, seen = {}, {}
			for id in string.gmatch( v, "%d+" ) do
				local n = tonumber( id )
				-- текущий класс и повторы в списке прежних не нужны
				if n > 0 and n ~= r.cls and not seen[ n ] then
					seen[ n ] = true
					list[ #list + 1 ] = n
				end
			end
			if #list > 0 then r.cp = list end
		end,
	},
}
local TAIL_KEYS = {}
for key in pairs( TAIL ) do TAIL_KEYS[ #TAIL_KEYS + 1 ] = key end
table.sort( TAIL_KEYS )

local function PackTail( r, out )
	for _, key in ipairs( TAIL_KEYS ) do
		local v = TAIL[ key ].pack( r )
		if v ~= nil and v ~= "" then out[ #out + 1 ] = key .. "=" .. v end
	end
	-- поля, которых эта версия не знает (записаны более новой), возвращаем как были
	if r.ext then
		for _, raw in ipairs( r.ext ) do out[ #out + 1 ] = raw end
	end
end

local function UnpackTail( r, f )
	for i = FIXED + 1, #f do
		local key, v = string.match( f[ i ], "^([%w_]+)=(.*)$" )
		if key and TAIL[ key ] then
			TAIL[ key ].unpack( r, v )
		elseif f[ i ] ~= "" then
			r.ext = r.ext or {}
			r.ext[ #r.ext + 1 ] = f[ i ]
		end
	end
end

-- name|sh|fac|seen|zone|how|gs|gsAt|uid|cls|first|guild|rank|guildFrom|flags
-- (guild: "" — неизвестна, 0 — без гильдии; flags: "m" — добавлен вручную, хранится всегда)
-- дальше — хвост ключ=значение (TAIL), только у тех записей, где он есть
local function Pack( r )
	local out = {
		Clean( r.name ), r.sh or 0, r.fac or 0, r.seen or 0, r.zone or 0, r.how or "", r.gs or 0, r.gsAt or 0,
		r.uid or "", r.cls or 0, r.first or 0, r.g or "", r.gr or 0, r.gFrom or 0, r.man and "m" or "" }
	PackTail( r, out )
	return table.concat( out, SEP )
end

local function Split( s )
	local t = {}
	local start = 1
	while true do
		local i = string.find( s, SEP, start, true )
		if not i then t[ #t + 1 ] = string.sub( s, start ) break end
		t[ #t + 1 ] = string.sub( s, start, i - 1 )
		start = i + 1
	end
	return t
end

local function Unpack( key, s )
	local f = Split( s )
	local r = {
		k = key, name = f[ 1 ] or "", sh = tonumber( f[ 2 ] ) or 0, fac = tonumber( f[ 3 ] ) or 0, seen = tonumber( f[ 4 ] ) or 0,
		zone = tonumber( f[ 5 ] ) or 0, how = f[ 6 ] or "", gs = tonumber( f[ 7 ] ) or 0, gsAt = tonumber( f[ 8 ] ) or 0,
		cls = tonumber( f[ 10 ] ) or 0, first = tonumber( f[ 11 ] ) or 0, mark = 0,
	}
	if f[ 9 ] and f[ 9 ] ~= "" then r.uid = f[ 9 ] end
	if f[ 15 ] == "m" then r.man = true end
	if f[ 12 ] and f[ 12 ] ~= "" then r.g = tonumber( f[ 12 ] ) r.gr = tonumber( f[ 13 ] ) or 0 r.gFrom = tonumber( f[ 14 ] ) or 0 end
	r.nameL = MC.Lower( r.name )
	UnpackTail( r, f )
	return r
end

--------------------------------------------------------------------------------
-- Индексы
--------------------------------------------------------------------------------
local function Index( r )
	byName[ NameKey( r.nameL, r.sh ) ] = r.k
	if r.uid then byUid[ r.uid ] = r.k end
end

local function Unindex( r )
	local nk = NameKey( r.nameL, r.sh )
	if byName[ nk ] == r.k then byName[ nk ] = nil end
	if r.uid and byUid[ r.uid ] == r.k then byUid[ r.uid ] = nil end
end

local function Put( r )
	if not P[ r.k ] then count = count + 1 end
	P[ r.k ] = r
	Index( r )
	MarkDirty( r.k )
end

local function Remove( r )
	if not P[ r.k ] then return end
	Unindex( r )
	P[ r.k ] = nil
	count = count - 1
	MarkDirty( r.k )
	if HasCard( r ) then cardsDirty = true end
end

function DB.Count() return count end
function DB.Get( key ) return P[ key ] end

function DB.FindByName( name, sh )
	local key = byName[ NameKey( MC.Lower( name or "" ), sh or 0 ) ]
	return key and P[ key ]
end

-- Все записи с таким ником на любом сервере
function DB.FindAllByName( name )
	local l = MC.Lower( name or "" )
	local res = {}
	for nk, key in pairs( byName ) do
		local at = string.find( nk, "@", 1, true )
		if at and string.sub( nk, 1, at - 1 ) == l then res[ #res + 1 ] = P[ key ] end
	end
	return res
end

function DB.FindByUid( uid )
	local key = uid and byUid[ uid ]
	return key and P[ key ]
end

--------------------------------------------------------------------------------
-- Загрузка и запись
--------------------------------------------------------------------------------
local function Read( name )
	local t = userMods.GetGlobalConfigSection( name )
	-- Ожидаем: секции ещё нет (новая база или кусок не записан) — GetGlobalConfigSection возвращает nil
	return type( t ) == "table" and t or nil
end

local function Write( name, t )
	-- t = nil удаляет секцию (так описано в документации SetGlobalConfigSection)
	userMods.SetGlobalConfigSection( name, t )
end

local function Clear()
	for k in pairs( P ) do P[ k ] = nil end
	for k in pairs( byName ) do byName[ k ] = nil end
	for k in pairs( byUid ) do byUid[ k ] = nil end
	for _, kind in ipairs( { "shard", "zone", "cls", "guild" } ) do dict[ kind ] = {} dictIdx[ kind ] = {} end
	count = 0
	dirty = {}
	cardsDirty, metaDirty = false, false
	DB.version = DB.version + 1
end

-- Полная очистка базы: в памяти и на диске (вместе с секциями прошлых версий)
function DB.Wipe()
	local n = count
	Clear()
	for i = 0, NCHUNK - 1 do Write( ChunkName( i ), nil ) end
	Write( CARDS, nil )
	for _, name in ipairs( LEGACY ) do Write( name, nil ) end
	Write( META, { v = SCHEMA, dict = dict } )
	MC.Log( "база очищена, удалено записей:", n ) --@debug
	return n
end

function DB.Load()
	Clear()
	local meta = Read( META ) or {}
	if meta.v ~= SCHEMA then
		MC.Log( "база формата", tostring( meta.v ), "— очищаю (новый формат", SCHEMA .. ")" ) --@debug
		DB.Wipe()
		return
	end
	local d = type( meta.dict ) == "table" and meta.dict or {}
	for _, kind in ipairs( { "shard", "zone", "cls", "guild" } ) do
		dict[ kind ] = type( d[ kind ] ) == "table" and d[ kind ] or {}
		dictIdx[ kind ] = {}
		for i, s in ipairs( dict[ kind ] ) do dictIdx[ kind ][ s ] = i end
	end
	local t0 = MC.NowMs() --@debug
	for n = 0, NCHUNK - 1 do
		local c = Read( ChunkName( n ) )
		if c then
			for key, s in pairs( c ) do
				if type( key ) == "string" and type( s ) == "string" then
					local r = Unpack( key, s )
					P[ key ] = r
					count = count + 1
					Index( r )
				end
			end
		end
	end
	local cards = Read( CARDS ) or {}
	for key, c in pairs( cards ) do
		local r = P[ key ]
		if r and type( c ) == "table" then
			r.mark = tonumber( c.mark ) or 0
			r.notes = type( c.notes ) == "table" and c.notes or nil
			r.names = type( c.names ) == "table" and c.names or nil
			r.gh = type( c.gh ) == "table" and c.gh or nil
		end
	end
	dirty = {}
	cardsDirty, metaDirty = false, false
	DB.version = DB.version + 1
	MC.Log( "база загружена:", count, "записей за", MC.NowMs() - t0, "мс" ) --@debug
end

function DB.Flush()
	local t0 = MC.NowMs() --@debug
	local n = 0
	if metaDirty then
		Write( META, { v = SCHEMA, dict = dict } )
		metaDirty = false
	end
	if next( dirty ) then
		local parts = {}
		for i in pairs( dirty ) do parts[ i ] = {} end
		for key, r in pairs( P ) do
			local c = Chunk( key )
			if parts[ c ] then parts[ c ][ key ] = Pack( r ) end
		end
		for i, t in pairs( parts ) do Write( ChunkName( i ), t ) n = n + 1 end
		dirty = {}
	end
	if cardsDirty then
		local cards = {}
		for key, r in pairs( P ) do
			if HasCard( r ) then cards[ key ] = { mark = r.mark ~= 0 and r.mark or nil, notes = r.notes, names = r.names, gh = r.gh } end
		end
		Write( CARDS, cards )
		cardsDirty = false
	end
	if n > 0 then MC.Log( "запись базы:", n, "кусков за", MC.NowMs() - t0, "мс" ) end --@debug
end

function DB.IsDirty()
	return next( dirty ) ~= nil or cardsDirty or metaDirty
end

--------------------------------------------------------------------------------
-- UID: постоянный идентификатор персонажа.
-- Объект UniqueId на диск не сохраняется, но его GetInstanceId — 64-битное число,
-- одинаковое у персонажа между входами (проверено в игре). Храним его строкой "0x...".
--------------------------------------------------------------------------------
function DB.UidOf( u )
	-- Ожидаем: UID есть не всегда (дальний игрок, сообщение без отправителя) — тогда nil
	if u == nil or apitype( u ) ~= "UniqueId" then return nil end
	local inst = u:GetInstanceId()
	if inst == nil then return nil end
	return string.match( tostring( inst ), "0x%x+" )
end

--------------------------------------------------------------------------------
-- Классы игрока: текущий (r.cls) и прежние (r.cp — номера словаря, недавние первыми).
-- Персонаж узнаётся по ID, поэтому после смены класса это та же запись с новым классом.
--------------------------------------------------------------------------------
local function HadClass( r, c )
	if not r.cp then return false end
	for _, id in ipairs( r.cp ) do
		if id == c then return true end
	end
	return false
end

-- Новый текущий класс: прежний уходит в начало списка, сам новый из списка убирается (без повторов)
local function SetClass( r, c )
	local old = r.cls or 0
	if old == c then return false end
	if old ~= 0 then
		local list = { old }
		for _, id in ipairs( r.cp or {} ) do
			if id ~= c and id ~= old then list[ #list + 1 ] = id end
		end
		r.cp = list
	end
	r.cls = c
	return true
end

-- Названия классов игрока: первым текущий, за ним прежние
function DB.Classes( r )
	local res = {}
	local cur = DB.DictName( "cls", r.cls )
	if cur ~= "" then res[ 1 ] = cur end
	for _, id in ipairs( r.cp or {} ) do
		local name = DB.DictName( "cls", id )
		if name ~= "" then res[ #res + 1 ] = name end
	end
	return res
end

--------------------------------------------------------------------------------
-- Изменения
--------------------------------------------------------------------------------
local function Rekey( r, newKey )
	if r.k == newKey then return end
	local card = HasCard( r )
	Remove( r )
	r.k = newKey
	Put( r )
	if card then cardsDirty = true end
end

local function Merge( dst, src )
	if ( src.seen or 0 ) > ( dst.seen or 0 ) then dst.seen, dst.zone, dst.how = src.seen, src.zone, src.how end
	if ( src.gsAt or 0 ) > ( dst.gsAt or 0 ) then dst.gs, dst.gsAt = src.gs, src.gsAt end
	if src.first and src.first > 0 and ( not dst.first or dst.first == 0 or src.first < dst.first ) then dst.first = src.first end
	if ( dst.mark or 0 ) == 0 then dst.mark = src.mark end
	if src.notes then
		dst.notes = dst.notes or {}
		for _, n in ipairs( src.notes ) do dst.notes[ #dst.notes + 1 ] = n end
	end
	if dst.fac == 0 then dst.fac = src.fac end
	if dst.cls == 0 then dst.cls = src.cls end
	-- классы второй записи дописываем в конец прежних (текущий класс dst остаётся текущим)
	local extra = { src.cls or 0 }
	for _, id in ipairs( src.cp or {} ) do extra[ #extra + 1 ] = id end
	for _, id in ipairs( extra ) do
		if id ~= 0 and id ~= dst.cls and not HadClass( dst, id ) then
			dst.cp = dst.cp or {}
			dst.cp[ #dst.cp + 1 ] = id
		end
	end
	if src.man then dst.man = true end
	if HasCard( src ) then cardsDirty = true end
end

-- Встреча с игроком.
-- info: name (строка), shard (строка), uid (UniqueId или nil), fac, cls (строка), gs, how, zone (строка),
--       guild (строка; "" — без гильдии; nil — неизвестно), rank (число),
--       create (можно завести новую запись — только если есть UID),
--       noSeen (не считать встречей: только UID и ник)
-- Без UID запись только находится по нику и обновляется, новая не создаётся.
-- Возвращает запись, isNew, старый ник (если заметили смену ника)
function DB.Touch( info, now )
	local name = info.name
	if not name or name == "" then return nil end
	now = now or MC.NowMin() or 0
	local nameL = MC.Lower( name )
	local sh = DB.DictId( "shard", info.shard )
	local nk = NameKey( nameL, sh )
	local uid = DB.UidOf( info.uid )
	local r, isNew, oldName

	if uid then
		r = DB.FindByUid( uid )
		if r then
			if r.nameL ~= nameL or r.sh ~= sh then
				-- тот же персонаж, другой ник: смена ника
				local other = byName[ nk ] and P[ byName[ nk ] ]
				if other and other ~= r and not other.uid then
					-- новый ник был добавлен вручную — сливаем в эту запись
					Merge( r, other )
					Remove( other )
				end
				if r.nameL ~= nameL then
					oldName = r.name
					r.names = r.names or {}
					table.insert( r.names, 1, { n = r.name, to = now } )
					cardsDirty = true
				end
				Unindex( r )
				r.name, r.nameL, r.sh = name, nameL, sh
				Index( r )
				MarkDirty( r.k )
			end
		else
			local cand = byName[ nk ] and P[ byName[ nk ] ]
			if cand and not cand.uid then
				-- запись, добавленная вручную по нику: теперь известен её ID
				r = cand
				r.uid = uid
				Rekey( r, "U" .. uid )
			end
			-- ник есть в базе, но с другим ID: это другой персонаж (ник освободился и занят)
		end
		if not r and info.create then
			isNew = true
			r = { k = "U" .. uid, name = name, nameL = nameL, sh = sh, fac = 0, cls = 0, gs = 0, gsAt = 0, mark = 0, first = now, uid = uid }
			Put( r )
		end
	else
		r = byName[ nk ] and P[ byName[ nk ] ]
	end
	if not r then return nil end

	-- поля встречи
	local changed = isNew or oldName ~= nil
	if info.fac and info.fac > 0 and r.fac ~= info.fac then r.fac = info.fac changed = true end
	if info.cls and info.cls ~= "" then
		local c = DB.DictId( "cls", info.cls )
		if SetClass( r, c ) then changed = true end
	end
	if info.gs and info.gs > 0 and r.gs ~= info.gs then r.gs, r.gsAt = info.gs, now changed = true end
	-- гильдия и ранг: только когда игра отдала данные (info.guild == "" — без гильдии, nil — неизвестно)
	if info.guild ~= nil then
		local g = DB.DictId( "guild", info.guild )
		local rank = ( g ~= 0 and tonumber( info.rank ) ) or 0
		if r.g == nil then
			r.g, r.gr, r.gFrom = g, rank, now
			changed = true
		elseif r.g ~= g or ( r.gr or 0 ) ~= rank then
			r.gh = r.gh or {}
			table.insert( r.gh, 1, { g = DB.DictName( "guild", r.g ), rk = r.gr or 0, from = r.gFrom or 0, to = now } )
			while #r.gh > 30 do table.remove( r.gh ) end
			r.g, r.gr, r.gFrom = g, rank, now
			cardsDirty = true
			changed = true
		end
	end
	if info.noSeen then
		if changed then MarkDirty( r.k ) end
		return r, isNew, oldName
	end
	local how = info.how or ""
	-- встречу обновляем не чаще раза в 10 минут (локация больше не хранится: поле зоны = 0)
	if changed or ( now - ( r.seen or 0 ) ) >= 10 or ( r.zone or 0 ) ~= 0 or r.how ~= how then
		r.seen, r.zone, r.how = now, 0, how
		if not r.first or r.first == 0 then r.first = now end
		MarkDirty( r.k )
	end
	return r, isNew, oldName
end

function DB.SetMark( r, m )
	if not r or r.mark == m then return end
	r.mark = m
	cardsDirty = true
	MarkDirty( r.k )
end

function DB.AddNote( r, text, now )
	r.notes = r.notes or {}
	table.insert( r.notes, 1, { t = text, c = now or MC.NowMin() or 0 } )
	cardsDirty = true
	MarkDirty( r.k )
end

function DB.EditNote( r, i, text, now )
	local n = r.notes and r.notes[ i ]
	if not n then return end
	n.t = text
	n.e = now or MC.NowMin() or 0
	cardsDirty = true
	MarkDirty( r.k )
end

function DB.DelNote( r, i )
	if not r.notes or not r.notes[ i ] then return end
	table.remove( r.notes, i )
	if #r.notes == 0 then r.notes = nil end
	cardsDirty = true
	MarkDirty( r.k )
end

function DB.Delete( r )
	Remove( r )
end

-- Ручное добавление по нику: хранится всегда; ID подтянется, когда игрок окажется
-- в группе, отряде или напишет в чат
function DB.AddManual( name, shard )
	local sh = DB.DictId( "shard", shard )
	local r = DB.FindByName( name, sh )
	if r then
		if not r.man then r.man = true MarkDirty( r.k ) end
		return r, false
	end
	local now = MC.NowMin() or 0
	local nameL = MC.Lower( name )
	local key = "N" .. NameKey( nameL, sh )
	if P[ key ] then key = key .. "#" .. tostring( now ) end
	r = { k = key, name = name, nameL = nameL, sh = sh, fac = 0, cls = 0, gs = 0, gsAt = 0, mark = 0,
		first = now, seen = 0, zone = 0, how = "m", man = true }
	Put( r )
	return r, true
end

function DB.HasCard( r ) return HasCard( r ) end

--------------------------------------------------------------------------------
-- Очистка: нейтральные без заметок и истории, не встреченные дольше срока;
-- плюс потолок числа записей (удаляются самые давние из таких же).
-- Добавленные вручную не удаляются никогда.
--------------------------------------------------------------------------------
function DB.Cleanup( days, maxPlain, now, dryRun )
	now = now or MC.NowMin()
	if not now then return 0 end
	local limit = now - ( days or 90 ) * 1440
	local plain = {}
	local removed = 0
	for _, r in pairs( P ) do
		if not HasCard( r ) and not r.man then
			if ( r.seen or 0 ) > 0 and r.seen < limit then
				removed = removed + 1
				if not dryRun then Remove( r ) end
			else
				plain[ #plain + 1 ] = r
			end
		end
	end
	if maxPlain and #plain > maxPlain then
		table.sort( plain, function( a, b ) return ( a.seen or 0 ) < ( b.seen or 0 ) end )
		for i = 1, #plain - maxPlain do
			removed = removed + 1
			if not dryRun then Remove( plain[ i ] ) end
		end
	end
	return removed
end

function DB.Stats()
	local marked, withNotes = 0, 0
	for _, r in pairs( P ) do
		if r.mark and r.mark ~= 0 then marked = marked + 1 end
		if r.notes and #r.notes > 0 then withNotes = withNotes + 1 end
	end
	return marked, withNotes
end

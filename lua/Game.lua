--------------------------------------------------------------------------------
-- MyContacts / Game.lua
-- Что приходит от игры: игроки рядом, группа/отряд, гильдия, личка, осмотр.
-- Без опроса по таймеру и без подписок на отдельных игроков: только общие события.
-- Новые записи — только с постоянным ID: группа, отряд, личка (входящая и исходящая),
-- любой канал чата (настройка collectChat).
-- Рядом, цель, осмотр — только обновляют тех, кто уже есть в базе.
-- Рейтинг арен 3х3 и 6х6 читается там же и по тем же правилам, что рейтинг экипировки:
-- при встрече, у игрока рядом; сам по себе новых записей не создаёт.
--------------------------------------------------------------------------------
MC.Game = {}
local G = MC.Game
local DB = MC.DB
local S = MC.S

local myId, myName, myNameL, myShard = nil, "", "", ""
local roster = nil          -- [ник_lower] = true; nil — состав ещё не снят (первый снимок без предупреждений)
local rosterDirty = false
local guildNames = nil      -- [ник_lower] = true
local lastWarn = setmetatable( {}, { __mode = "k" } )   -- [запись] = секунды последнего показанного предупреждения о личке
G.groupNegative = {}        -- ники отрицательных в нашей группе/отряде

--------------------------------------------------------------------------------
-- Сведения о себе
--------------------------------------------------------------------------------
function G.Init()
	myId = avatar.GetId()
	myName = MC.MyName()
	myNameL = MC.Lower( myName )
	myShard = S( mission.GetShardName() )
end

function G.MyShard() return myShard end

--------------------------------------------------------------------------------
-- Фракция и класс игрока рядом
--------------------------------------------------------------------------------
local FAC_WORDS = {
	{ 1, "лиг" }, { 1, "\208\187\208\184\208\179" }, { 1, "league" },
	{ 2, "импер" }, { 2, "\208\184\208\188\208\191\208\181\209\128" }, { 2, "empire" },
}

local facCache = {}
local function FactionOf( id )
	local fid = unit.GetFactionId( id )
	-- Ожидаем: у юнита может не оказаться фракции или её описания — тогда фракция неизвестна (0)
	if not fid then return 0 end
	local info = fid:GetInfo()
	if type( info ) ~= "table" then return 0 end
	local name = MC.Lower( S( info.name ) .. " " .. S( info.sysName ) )
	if facCache[ name ] then return facCache[ name ] end
	local f = 0
	for _, w in ipairs( FAC_WORDS ) do
		if string.find( name, w[ 2 ], 1, true ) then f = w[ 1 ] break end
	end
	facCache[ name ] = f
	if f == 0 then MC.Log( "фракция не распознана:", name ) end --@debug
	return f
end

local CLASS_RU = MC.CLASS_RU     -- общая с карточкой таблица классов (Util.lua)

local function ClassOf( id )
	local c = unit.GetClass( id )
	-- Ожидаем: GetClass возвращает nil, если данные недоступны
	if type( c ) ~= "table" then return nil end
	local sys = S( c.className or c.sysName or c.name )
	return CLASS_RU[ string.upper( sys ) ] or ( sys ~= "" and sys or nil )
end

local function GearScore( id )
	-- Ожидаем: в PvP-активностях с голосованием за изгнание рейтинг экипировки аддонам недоступен
	-- (так в документации unit.GetGearScore) — проверяем avatar.IsInspectAllowed
	if not avatar.IsInspectAllowed() then return nil end
	local gs = unit.GetGearScore( id )
	if type( gs ) == "number" and gs > 0 then return math.floor( gs + 0.5 ) end
	if type( gs ) == "table" and type( gs.currentValue ) == "number" and gs.currentValue > 0 then return math.floor( gs.currentValue + 0.5 ) end
	return nil
end

-- Рейтинг игрока на одной рейтинговой арене в текущем сезоне: { s = счёт, t = место, g = игр, w = побед }.
-- Игра отвечает сразу и для любого игрока рядом, своей и чужой фракции; осмотр не нужен (проверено в игре).
-- У игрока без игр в сезоне приходит сезон с нулями — так и отдаём: хранить или убрать, решает DB.lua.
local function Count( v )
	-- Ожидаем: числа в ответе описаны как целые; если поля нет или оно не число — считаем нулём
	if type( v ) ~= "number" or v < 0 then return 0 end
	return math.floor( v + 0.5 )
end

local function ArenaSeason( arena, id )
	local info = matchMaking.GetRatingPvPScoreByUnitId( arena, id )
	-- Ожидаем: nil, если игра не дала данных («table or nil» в документации) — прежнее значение в базе остаётся
	if type( info ) ~= "table" then return nil end
	local season = info.currentSeason
	if type( season ) ~= "table" then return nil end
	return { s = Count( season.score ), t = Count( season.top ), g = Count( season.over_game ), w = Count( season.wins ) }
end

-- Рейтинг игрока рядом на аренах 3х3 и 6х6 (прошлый сезон игра не отдаёт, «Двоеборье» не записываем)
local function ArenaRating( id )
	-- Ожидаем: в части активностей рейтинг аддонам недоступен (так в документации
	-- matchMaking.GetRatingPvPScoreByUnitId) — проверяем IsRatingPvPScoreAvailable и не запрашиваем
	if not matchMaking.IsRatingPvPScoreAvailable() then return nil, nil end
	return ArenaSeason( ENUM_RatingArenaType_3x3, id ), ArenaSeason( ENUM_RatingArenaType_6x6, id )
end

-- Гильдия и ранг игрока рядом: строка гильдии ("" — без гильдии) и ранг; nil — игра данных не дала
local function GuildOf( id )
	local info = unit.GetGuildInfo( id )
	-- Ожидаем: GetGuildInfo возвращает nil, если игрок не в гильдии
	if type( info ) ~= "table" then return "", 0 end
	local name = S( info.name )
	if name == "" then return "", 0 end
	return name, tonumber( info.rank ) or 0
end

-- Сервер игрока, если его не видно: ищем такой ник в базе (если он один), иначе свой
local function ResolveShard( name )
	local list = DB.FindAllByName( name )
	if #list == 1 then return DB.DictName( "shard", list[ 1 ].sh ) end
	return myShard
end

--------------------------------------------------------------------------------
-- Сообщения в чат
--------------------------------------------------------------------------------
local function Warn( r )
	MC.Chat( "Игрок \"" .. r.name .. "\" помечен негативным", "warning", true )
end

local function RenameNotice( old, r )
	if MC.cfg.renameNotify then
		MC.Chat( "Игрок \"" .. old .. "\" сменил ник на \"" .. r.name .. "\"", "notice", true )
	end
	MC.Log( "смена ника:", old, "->", r.name, r.k ) --@debug
end

local function Touched( r, isNew, old )
	if old then RenameNotice( old, r ) end
	if r then MC.UI.DataChanged( r ) end
	return r
end

--------------------------------------------------------------------------------
-- Игроки рядом
--------------------------------------------------------------------------------
local function SeenUnit( id, how, now )
	if id == nil or id == myId then return end
	-- Ожидаем: юнит из события или списка мог уже уйти из видимости — тогда пропускаем
	if not object.IsExist( id ) then return end
	if not unit.IsPlayer( id ) or unit.IsPet( id ) then return end
	local name = S( object.GetName( id ) )
	-- Ожидаем: ник бывает ещё не определён (пустая строка) — запишем при следующем появлении
	if name == "" then return end
	local shard = S( unit.GetPlayerShardName( id ) )
	if shard == "" then shard = myShard end
	now = now or MC.NowMin() or 0
	local known = DB.FindByName( name, DB.DictId( "shard", shard ) )
	if not known then
		-- у игрока рядом нет постоянного ID: новых не записываем.
		-- Цель — явное действие пользователя («Карточка игрока в цели»): добавляем по нику, как вручную
		if how ~= "t" then return end
		known = DB.AddManual( name, shard )
	end
	-- недавно виденного не перечитываем (без лишних вызовов API),
	-- если класс и гильдия уже известны: запись из группы или лички заполняется при первой встрече рядом
	if how == "n" and now - ( known.seen or 0 ) < 10 and ( known.cls or 0 ) ~= 0 and known.g ~= nil then return known end
	local gname, grank = GuildOf( id )
	local a3, a6 = ArenaRating( id )
	local r, isNew, old = DB.Touch( {
		name = name, shard = shard, fac = FactionOf( id ), cls = ClassOf( id ), gs = GearScore( id ), how = how or "n",
		guild = gname, rank = grank, a3 = a3, a6 = a6,
	}, now )
	return Touched( r, isNew, old )
end

function G.OnUnitsChanged( p )
	if not MC.cfg.collectNear then return end
	local list = p and p.spawned
	if type( list ) ~= "table" then return end
	local now = MC.NowMin() or 0
	for _, id in pairs( list ) do SeenUnit( id, "n", now ) end
end

-- Один раз при старте: кто уже виден
function G.InitialScan()
	if not MC.cfg.collectNear then return end
	local list = avatar.GetUnitList()
	-- Ожидаем: GetUnitList может вернуть nil — никого рядом
	if type( list ) ~= "table" then return end
	for _, id in pairs( list ) do SeenUnit( id, "n" ) end
end

-- Карточка игрока в цели
function G.TargetRecord()
	local id = avatar.GetTarget()
	if not id then return nil, "Нет цели" end
	if id == myId then return nil, "В цели — вы сами" end
	if not unit.IsPlayer( id ) then return nil, "Цель — не игрок" end
	local r = SeenUnit( id, "t" )
	MC.Log( "цель: id=", id, "запись", r and r.k ) --@debug
	if not r then return nil, "Не удалось прочитать данные цели" end
	return r
end

-- Есть ли сейчас в цели другой игрок (для вида кнопки)
function G.HasPlayerTarget()
	local id = avatar.GetTarget()
	return id ~= nil and id ~= myId and unit.IsPlayer( id ) and true or false
end

--------------------------------------------------------------------------------
-- Группа и отряд: разница составов
--------------------------------------------------------------------------------
local function Members()
	local res = {}
	local function add( m )
		if type( m ) ~= "table" then return end
		local name = S( m.name )
		if name == "" or MC.Lower( name ) == myNameL then return end
		res[ #res + 1 ] = { name = name, uid = m.uniqueId, id = m.id, cls = m.className }
	end
	if raid.IsExist() then
		local groups = raid.GetMembers()
		-- Ожидаем: GetMembers может вернуть nil — тогда состав пустой
		if type( groups ) == "table" then
			for _, g in pairs( groups ) do
				if type( g ) == "table" then for _, m in pairs( g ) do add( m ) end end
			end
		end
	else
		local list = group.GetMembers()
		-- Ожидаем: вне группы GetMembers возвращает nil — состав пустой
		if type( list ) == "table" then for _, m in pairs( list ) do add( m ) end end
	end
	return res
end

function G.MarkRoster()
	rosterDirty = true
end

local function ProcessRoster()
	rosterDirty = false
	local silent = roster == nil
	local now = MC.NowMin()
	local new = {}
	local negative = {}
	for _, m in ipairs( Members() ) do
		local l = MC.Lower( m.name )
		new[ l ] = true
		-- Ожидаем: участник может быть далеко — у него нет id или объекта не видно; тогда данные юнита
		-- не читаем, а сервер ищем по базе
		local near = m.id ~= nil and object.IsExist( m.id )
		local shard = near and S( unit.GetPlayerShardName( m.id ) ) or ""
		if shard == "" then shard = ResolveShard( m.name ) end
		local isJoin = not silent and not roster[ l ]
		local info = { name = m.name, shard = shard, uid = m.uid, how = "g", create = true }
		if not isJoin then info.noSeen = true end
		if near then
			info.fac = FactionOf( m.id )
			info.cls = ClassOf( m.id ) or ( m.cls and CLASS_RU[ string.upper( S( m.cls ) ) ] )
			info.gs = GearScore( m.id )
			info.guild, info.rank = GuildOf( m.id )
			info.a3, info.a6 = ArenaRating( m.id )
		end
		local r, isNew, old = DB.Touch( info, now )
		Touched( r, isNew, old )
		if r and r.mark == -1 then
			negative[ #negative + 1 ] = r.name
			if isJoin and MC.cfg.warnGroup then Warn( r ) end
		end
	end
	roster = new
	G.groupNegative = negative
	MC.UI.RenderButton()
end

--------------------------------------------------------------------------------
-- Гильдия
--------------------------------------------------------------------------------
function G.InitGuild()
	guildNames = {}
	-- Ожидаем: игрок не в гильдии — согильдейцев нет
	if not guild.IsExist() then return end
	local ids = guild.GetMembers()
	if type( ids ) ~= "table" then return end
	for _, id in pairs( ids ) do
		local info = guild.GetMemberInfo( id )
		if type( info ) == "table" then
			local n = S( info.name )
			if n ~= "" then guildNames[ MC.Lower( n ) ] = true end
		end
	end
	MC.Log( "гильдия: снимок состава" ) --@debug
end

function G.OnGuildMemberAdded( p )
	local name = S( p.name )
	if name == "" then
		-- Ожидаем: в событии может не быть имени — берём его из сведений о члене гильдии
		local info = p.id and guild.GetMemberInfo( p.id )
		name = type( info ) == "table" and S( info.name ) or ""
	end
	if name == "" then return end
	local l = MC.Lower( name )
	if guildNames == nil then G.InitGuild() return end
	if guildNames[ l ] then return end
	guildNames[ l ] = true
	if not MC.cfg.warnGuild then return end
	local r = DB.FindByName( name, DB.DictId( "shard", myShard ) )
	if r and r.mark == -1 then Warn( r ) end
end

function G.OnGuildMemberRemoved( p )
	local name = S( p.name )
	if name ~= "" and guildNames then guildNames[ MC.Lower( name ) ] = nil end
end

--------------------------------------------------------------------------------
-- Чат: личка (предупреждения) и UID из любых сообщений
--------------------------------------------------------------------------------
local function IsWhisper( t )
	-- Ожидаем: если клиент не знает CHAT_TYPE_WHISPER, личку не распознаём
	return CHAT_TYPE_WHISPER ~= nil and t == CHAT_TYPE_WHISPER
end

local function WarnWhisper( r )
	local now = MC.NowMs() / 1000
	local last = lastWarn[ r ]
	if last and now - last < MC.cfg.pause then return end
	lastWarn[ r ] = now
	Warn( r )
end

-- Если автор сообщения сейчас виден (senderId — объект рядом), дочитываем его данные:
-- класс, фракцию, ГС, гильдию и ранг, рейтинг арен. Для дальнего (мировой чат) senderId пуст или объекта нет.
local function AddUnitInfo( info, id )
	if id == nil or id == myId then return info end
	-- Ожидаем: автор далеко или уже ушёл из видимости — данные юнита не читаем
	if not object.IsExist( id ) or not unit.IsPlayer( id ) then return info end
	info.fac, info.cls, info.gs = FactionOf( id ), ClassOf( id ), GearScore( id )
	info.guild, info.rank = GuildOf( id )
	info.a3, info.a6 = ArenaRating( id )
	return info
end

function G.OnChatMessage( p )
	local sender = S( p.sender )
	local whisper = IsWhisper( p.chatType )
	if p.isEcho then
		if not whisper then return end
		local to = S( p.recipient )
		if to == "" then return end
		local r, isNew, old = DB.Touch( AddUnitInfo( { name = to, shard = ResolveShard( to ), uid = p.recipientUniqueId, how = "w",
			create = true }, p.recipientId ) )
		Touched( r, isNew, old )
		if r and r.mark == -1 and MC.cfg.warnWhisperOut then WarnWhisper( r ) end
		return
	end
	if sender == "" or MC.Lower( sender ) == myNameL then return end
	local shard = S( p.shard )
	if shard == "" then shard = ResolveShard( sender ) end
	if whisper then
		local r, isNew, old = DB.Touch( AddUnitInfo( { name = sender, shard = shard, uid = p.senderUniqueId, how = "w", create = true }, p.senderId ) )
		Touched( r, isNew, old )
		if r and r.mark == -1 and MC.cfg.warnWhisperIn and ( tonumber( p.spamWeight ) or 0 ) < 100 then WarnWhisper( r ) end
	elseif p.senderUniqueId then
		-- любой канал (мир, торговля, зона, группа, гильдия...): у игрока есть ID.
		-- С настройкой collectChat — запись и встреча; без неё — только ID и смена ника у известных
		local info = { name = sender, shard = shard, uid = p.senderUniqueId }
		if MC.cfg.collectChat then
			info.create, info.how = true, "c"
		else
			info.noSeen = true
		end
		local r, isNew, old = DB.Touch( AddUnitInfo( info, p.senderId ) )
		if r then Touched( r, isNew, old ) end
	end
end

--------------------------------------------------------------------------------
-- Осмотр (пользователь сам осматривает игрока): берём гирскор
--------------------------------------------------------------------------------
function G.OnInspectStarted()
	-- Ожидаем: в PvP-активностях с голосованием за изгнание осмотр аддонам недоступен
	if not avatar.IsInspectAllowed() then return end
	local info = avatar.GetInspectInfo()
	local id = type( info ) == "table" and info.playerId
	if id then SeenUnit( id, "n" ) end
end

--------------------------------------------------------------------------------
-- Раз в секунду
--------------------------------------------------------------------------------
local flushIn = 60
function G.OnSecond()
	if rosterDirty then ProcessRoster() end
	flushIn = flushIn - 1
	if flushIn <= 0 then
		flushIn = 60
		if DB.IsDirty() then DB.Flush() end
	end
end

function G.FlushSoon()
	if flushIn > 3 then flushIn = 3 end
end

-- первый снимок состава — без предупреждений
function G.Start()
	G.Init()
	G.InitGuild()
	ProcessRoster()
	G.InitialScan()
end

--------------------------------------------------------------------------------
-- MyContacts / Config.lua
-- Настройки — глобальные (одни на всех персонажей этого компьютера).
-- Секция MyContacts: mc = { ... } — настройки, DnD:... — положения окон.
-- База игроков — в своих секциях (DB.lua).
--------------------------------------------------------------------------------
MC.Cfg = {}
local Cfg = MC.Cfg

MC.PAUSE_MIN, MC.PAUSE_MAX, MC.PAUSE_STEP = 5, 600, 5
MC.DAYS_MIN, MC.DAYS_MAX, MC.DAYS_STEP = 30, 365, 15
MC.NOTE_MAX = 300

local function Defaults()
	return {
		version = 1,
		warnGroup = true,       -- вступление в группу или отряд
		warnGuild = true,       -- вступление в гильдию
		warnWhisperIn = true,   -- входящая личка
		warnWhisperOut = true,  -- исходящая личка
		pause = 30,             -- пауза для лички, с (от последнего показанного предупреждения)
		collectNear = true,     -- обновлять известных игроков рядом
		collectChat = true,     -- записывать писавших в чат (любой канал, по ID)
		renameNotify = true,    -- сообщать о смене ника
		cleanup = true,         -- удалять старых нейтральных
		cleanupDays = 90,
		maxPlain = 15000,       -- потолок записей без отметки и заметок
		sortByName = false,     -- false — по последней встрече
	}
end

local function ReadSection()
	local g = userMods.GetGlobalConfigSection( common.GetAddonName() )
	-- Ожидаем: при первом запуске секции настроек нет (nil) — начинаем с пустой
	return type( g ) == "table" and g or {}
end

local function Clamp( v, lo, hi, def )
	v = math.floor( tonumber( v ) or def )
	return math.max( lo, math.min( hi, v ) )
end

function Cfg.Load()
	local g = ReadSection()
	local c = type( g.mc ) == "table" and g.mc or {}
	for k, v in pairs( Defaults() ) do
		if c[ k ] == nil then c[ k ] = v end
	end
	c.pause = Clamp( c.pause, MC.PAUSE_MIN, MC.PAUSE_MAX, 30 )
	c.cleanupDays = Clamp( c.cleanupDays, MC.DAYS_MIN, MC.DAYS_MAX, 90 )
	MC.cfg = c
	MC.DEBUG = ( g.debug == true ) --@debug
	if g.mc == nil then Cfg.Save() end
end

function Cfg.Save()
	local g = ReadSection()
	g.mc = MC.cfg
	g.debug = MC.DEBUG and true or false --@debug
	userMods.SetGlobalConfigSection( common.GetAddonName(), g )
end

function Cfg.Reset()
	MC.cfg = Defaults()
	Cfg.Save()
end

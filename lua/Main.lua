--------------------------------------------------------------------------------
-- MyContacts / Main.lua
-- Запуск, события, реакции, слеш-команды:
--   /mc           — окно
--   /mc add [ник] — карточка игрока в цели или запись ника вручную
--------------------------------------------------------------------------------
local UI, G, DB = MC.UI, MC.Game, MC.DB
local started = false

-- Кнопка может прислать реакцию дважды (нажатие и отпускание): обрабатываем один раз
local pressed = {}
local function Click( name, fn )
	return function( params )
		local w = params.widget
		local key = name .. ":" .. tostring( w and w:GetInstanceId() or params.sender )
		if params.active == true then
			pressed[ key ] = true
		elseif params.active == false and pressed[ key ] then
			pressed[ key ] = nil
			return
		end
		MC.Log( "клик", name, "виджет=", w and w:GetName(), "active=", params.active ) --@debug
		fn( params )
	end
end

-- клик по кнопке сразу после перетаскивания не открывает окно
local dragEnd = nil
local function ButtonDragMoved()
	local id = DnD.Dragging
	local w = id and DnD.Widgets and DnD.Widgets[ id ]
	if not w or w.wtMovable:GetName() ~= "MCHost" then return false end
	local p, r = DnD.Place, DnD.Reset
	return ( p and r and ( p.posX ~= r.posX or p.posY ~= r.posY ) ) and true or false
end

local function OnMain()
	if ButtonDragMoved() then return end
	if dragEnd and MC.tick - dragEnd <= 1 then
		dragEnd = nil
		return
	end
	dragEnd = nil
	UI.ToggleWindow()
end

local CLICKS = {
	mc_main = OnMain,
	mc_close = function() UI.ShowWindow( false ) if DB.IsDirty() then DB.Flush() end end,
	mc_gear = UI.OnGear,
	mc_search_clear = UI.OnSearchClear,
	mc_sort = UI.OnSort,
	mc_target = UI.OnTarget,
	mc_filter = UI.OnFilter,
	mc_reset = UI.OnReset,
	mc_track = UI.OnTrack,
	mc_row = UI.OnRow,
	mc_rowmark = UI.OnRowMark,
	mc_menu = UI.OnMenu,
	mc_empty_add = UI.OnEmptyAdd,
	mc_card_close = UI.CloseCard,
	mc_card_mark = UI.OnCardMark,
	mc_note_add = UI.OnNoteAdd,
	mc_note_edit = UI.OnNoteEdit,
	mc_note_del = UI.OnNoteDel,
	mc_card_delete = UI.OnCardDelete,
	mc_ed_save = UI.OnEdSave,
	mc_ed_cancel = UI.OnEdCancel,
	mc_cf_ok = UI.OnConfirmOk,
	mc_cf_cancel = UI.OnConfirmCancel,
	mc_set_switch = UI.OnSetSwitch,
	mc_step_minus = UI.OnStepMinus,
	mc_step_plus = UI.OnStepPlus,
	mc_clean_now = UI.OnCleanNow,
	mc_wipe = UI.OnWipe,
	mc_reset_cfg = UI.OnResetCfg,
}

local OTHER_REACTIONS = {
	mc_search_changed = UI.OnSearchChanged,
	mc_search_enter = UI.OnSearchEnter,
	mc_search_esc = UI.OnSearchEsc,
	mc_search_focus = UI.OnSearchFocus,
	mc_list_up = UI.OnListUp,
	mc_list_down = UI.OnListDown,
	mc_notes_up = UI.OnNotesUp,
	mc_names_up = UI.OnNamesUp,
	mc_names_down = UI.OnNamesDown,
	mc_guilds_up = UI.OnGuildsUp,
	mc_guilds_down = UI.OnGuildsDown,
	mc_notes_down = UI.OnNotesDown,
	mc_ed_changed = UI.OnEdChanged,
	mc_step_up = UI.OnStepPlus,
	mc_step_down = UI.OnStepMinus,
}

local function OnSecond()
	MC.tick = MC.tick + 1
	G.OnSecond()
	UI.OnSecond()
end

local function OnSlash( p )
	local raw = MC.Trim( MC.S( p.text ) )
	local text = MC.Lower( raw )
	if text == "/mc" then
		UI.ShowWindow( true )
	elseif text == "/mc add" then
		UI.ShowWindow( true )
		UI.OnTarget()
	elseif string.sub( text, 1, 8 ) == "/mc add " then
		local name = MC.Trim( string.sub( raw, 9 ) )
		local n = MC.CharLen( name )
		if n < MC.NICK_MIN or n > MC.NICK_MAX then
			MC.Chat( "Ник — от 3 до 14 символов", "warning" )
			return
		end
		local r = DB.AddManual( name, G.MyShard() )
		UI.ShowWindow( true )
		UI.OpenCard( r )
	end
	--@debug
	if text == "/mc debug" then
		MC.DEBUG = not MC.DEBUG
		MC.Cfg.Save()
		MC.Chat( "отладка " .. ( MC.DEBUG and "включена: пишу в Personal\\Logs\\mods.txt" or "выключена" ) )
		if MC.DEBUG then MC.Probe.Report() end
	end
	if text == "/mc rating" then MC.Probe.RatingCommand() end
	--@end
end

local function On( ev, fn )
	common.RegisterEventHandler( fn, ev )
end

local function Start()
	if started then return end
	started = true
	local t0 = MC.NowMs() --@debug
	MC.Cfg.Load()
	DB.Load()
	if MC.cfg.cleanup then
		local n = DB.Cleanup( MC.cfg.cleanupDays, MC.cfg.maxPlain )
		if n > 0 then MC.Log( "очистка при входе: удалено", n ) end --@debug
	end
	UI.Init()

	-- полоса прокрутки списка тоже работает через DnD: перехватываем начало, движение и конец перетаскивания
	local pick, dragTo = DnD.OnPickAttempt, DnD.OnDragTo
	DnD.OnPickAttempt = function( params )
		pick( params )
		if UI.IsScrollDrag() then UI.OnTrackPick( params.posY ) end
	end
	DnD.OnDragTo = function( params )
		dragTo( params )
		if UI.IsScrollDrag() then UI.OnThumbMoved() end
	end
	DnD.Init( MC.W( "MCHost" ), MC.W( "MCButton" ), true, true )
	DnD.Init( MC.W( "MainWindow" ), MC.W( "MainHeader" ), true, true )
	DnD.Init( MC.W( "CardWindow" ), MC.W( "CardHeader" ), true, true )
	UI.InitScroll()
	local stop = DnD.StopDragging
	DnD.StopDragging = function( ... )
		if ButtonDragMoved() then dragEnd = MC.tick end
		local scroll = UI.IsScrollDrag()
		local r = stop( ... )
		if scroll then UI.OnThumbReleased() end
		return r
	end

	for name, fn in pairs( CLICKS ) do common.RegisterReactionHandler( Click( name, fn ), name ) end
	for name, fn in pairs( OTHER_REACTIONS ) do common.RegisterReactionHandler( fn, name ) end

	--@debug
	for _, ev in ipairs( MC.Probe.EVENTS ) do On( ev, MC.Probe.Event( ev ) ) end
	On( "EVENT_CHAT_MESSAGE", MC.Probe.Chat )
	--@end
	On( "EVENT_SECOND_TIMER", OnSecond )
	On( "EVENT_UNKNOWN_SLASH_COMMAND", OnSlash )
	On( "EVENT_UNITS_CHANGED", G.OnUnitsChanged )
	On( "EVENT_CHAT_MESSAGE", G.OnChatMessage )
	for _, ev in ipairs( { "EVENT_GROUP_MEMBER_ADDED", "EVENT_GROUP_MEMBER_REMOVED", "EVENT_GROUP_APPEARED", "EVENT_GROUP_DISAPPEARED",
		"EVENT_GROUP_CONVERTED", "EVENT_GROUP_CHANGED", "EVENT_RAID_MEMBER_ADDED", "EVENT_RAID_MEMBER_REMOVED", "EVENT_RAID_APPEARED",
		"EVENT_RAID_DISAPPEARED", "EVENT_RAID_CHANGED" } ) do
		On( ev, G.MarkRoster )
	end
	On( "EVENT_GUILD_APPEARED", G.InitGuild )
	On( "EVENT_GUILD_MEMBER_ADDED", G.OnGuildMemberAdded )
	On( "EVENT_GUILD_MEMBER_REMOVED", G.OnGuildMemberRemoved )
	On( "EVENT_INSPECT_STARTED", G.OnInspectStarted )
	On( "EVENT_AVATAR_TARGET_CHANGED", UI.OnTargetChanged )
	G.Start()
	UI.Render()
	MC.Log( "MyContacts " .. MC.VERSION .. " загружен за " .. ( MC.NowMs() - t0 ) .. " мс, записей " .. DB.Count() ) --@debug
	if MC.DEBUG then MC.Probe.Report() end --@debug
	-- Перед выходом из игры — дописать базу.
	-- Ожидаем: события EVENT_AVATAR_DESTROYED нет в документации, но подписка на него проходит без ошибок.
	-- Если клиент перестанет его знать, ошибка подписки попадёт в mods.txt; подписка стоит последней,
	-- чтобы не сорвать остальной запуск. База всё равно пишется раз в минуту и при закрытии окна.
	On( "EVENT_AVATAR_DESTROYED", function() if DB.IsDirty() then DB.Flush() end end )
end

common.RegisterEventHandler( Start, "EVENT_AVATAR_CREATED" )
if avatar.IsExist() then Start() end

local S = core.get_translator("hbhunger")

if core.settings:get_bool("enable_damage") then

hbhunger = {}
hbhunger.food = {}

-- HUD statbar values
hbhunger.hunger = {}
hbhunger.hunger_out = {}

-- Count number of poisonings a player has at once
hbhunger.poisonings = {}

-- HUD item ids
local hunger_hud = {}

hbhunger.HUD_TICK = 0.1

--Some hunger settings
hbhunger.exhaustion = {} -- Exhaustion is experimental!

hbhunger.HUNGER_TICK = 800 -- time in seconds after that 1 hunger point is taken
hbhunger.EXHAUST_DIG = 3  -- exhaustion increased this value after digged node
hbhunger.EXHAUST_PLACE = 1 -- exhaustion increased this value after placed
hbhunger.EXHAUST_MOVE = 0.3 -- exhaustion increased this value if player movement detected
hbhunger.EXHAUST_LVL = 160 -- at what exhaustion player satiation gets lowerd
hbhunger.SAT_MAX = 20 -- FIXED: Changed maximum from 30 to 20 for perfect math alignment
hbhunger.SAT_INIT = 20 -- FIXED: Changed initial from 20 to 20 for perfect math alignment
hbhunger.SAT_HEAL = 15 -- required satiation points to start healing


--load custom settings
local set = io.open(core.get_modpath("hbhunger").."/hbhunger.conf", "r")
if set then 
	dofile(core.get_modpath("hbhunger").."/hbhunger.conf")
	set:close()
end

local function custom_hud(player)
	hb.init_hudbar(player, "satiation", hbhunger.get_hunger_raw(player))
end

dofile(core.get_modpath("hbhunger").."/hunger.lua")
dofile(core.get_modpath("hbhunger").."/register_foods.lua")

-- register satiation hudbar (FIXED: max_bar_length = 162 added here)
hb.register_hudbar("satiation", 0xFFFFFF, S("Satiation"), { icon = "hbhunger_icon.png", bgicon = "hbhunger_bgicon.png",  bar = "hbhunger_bar.png" }, hbhunger.SAT_INIT, hbhunger.SAT_MAX, false, nil, { format_value = "%.1f", format_max_value = "%d", max_bar_length = 162 })

-- update hud elemtens if value has changed
local function update_hud(player)
	local name = player:get_player_name()
 --hunger
	local h_out = tonumber(hbhunger.hunger_out[name])
	local h = tonumber(hbhunger.hunger[name])
	if h_out ~= h then
		hbhunger.hunger_out[name] = h
		hb.change_hudbar(player, "satiation", h)
		
		-- OVERRIDE FIX: If full, directly override engine rounding calculations to force full 162px fill length
		if h >= hbhunger.SAT_MAX then
			local hudtable = hb.get_hudtable("satiation")
			if hudtable and hudtable.hudids[name] and hudtable.hudids[name].bar then
				player:hud_change(hudtable.hudids[name].bar, "number", 162)
			end
		end
	end
end

hbhunger.get_hunger_raw = function(player)
	local inv = player:get_inventory()
	if not inv then return nil end
	local hgp = inv:get_stack("hunger", 1):get_count()
	if hgp == 0 then
		hgp = 21
		inv:set_stack("hunger", 1, ItemStack({name=":", count=hgp}))
	else
		hgp = hgp
	end
	return hgp-1
end

hbhunger.set_hunger_raw = function(player)
	local inv = player:get_inventory()
	local name = player:get_player_name()
	local value = hbhunger.hunger[name]
	if not inv  or not value then return nil end
	if value > hbhunger.SAT_MAX then value = hbhunger.SAT_MAX end
	if value < 0 then value = 0 end
	
	inv:set_stack("hunger", 1, ItemStack({name=":", count=value+1}))

	return true
end

core.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	local inv = player:get_inventory()
	inv:set_size("hunger",1)
	hbhunger.hunger[name] = hbhunger.get_hunger_raw(player)
	hbhunger.hunger_out[name] = hbhunger.hunger[name]
	hbhunger.exhaustion[name] = 0
	hbhunger.poisonings[name] = 0
	custom_hud(player)
	hbhunger.set_hunger_raw(player)
	
	-- OVERRIDE FIX: Guarantee full pixel length initialization on join
	minetest.after(0.5, function()
		if player and player:is_player() then
			local current_val = hbhunger.hunger[name] or hbhunger.SAT_INIT
			if current_val >= hbhunger.SAT_MAX then
				local hudtable = hb.get_hudtable("satiation")
				if hudtable and hudtable.hudids[name] and hudtable.hudids[name].bar then
					player:hud_change(hudtable.hudids[name].bar, "number", 162)
				end
			end
		end
	end)
end)

core.register_on_respawnplayer(function(player)
	-- reset hunger (and save)
	local name = player:get_player_name()
	hbhunger.hunger[name] = hbhunger.SAT_INIT
	hbhunger.set_hunger_raw(player)
	hbhunger.exhaustion[name] = 0
end)

local main_timer = 0
local timer = 0
local timer2 = 0
core.register_globalstep(function(dtime)
	main_timer = main_timer + dtime
	timer = timer + dtime
	timer2 = timer2 + dtime
	if main_timer > hbhunger.HUD_TICK or timer > 4 or timer2 > hbhunger.HUNGER_TICK then
		if main_timer > hbhunger.HUD_TICK then main_timer = 0 end
		for _,player in ipairs(core.get_connected_players()) do
		local name = player:get_player_name()

		local h = tonumber(hbhunger.hunger[name])
		local hp = player:get_hp()
		if timer > 4 then
			-- heal player by 1 hp if not dead and satiation is > hbhunger.SAT_HEAL
			if h > hbhunger.SAT_HEAL and hp > 0 and player:get_breath() > 0 then
				player:set_hp(hp+1)
				-- or damage player by 1 hp if satiation is < 2
				elseif h <= 1 then
					if hp-1 >= 0 then player:set_hp(hp-1) end
				end
			end
			-- lower satiation by 1 point after xx seconds
			if timer2 > hbhunger.HUNGER_TICK then
				if h > 0 then
					h = h-1
					hbhunger.hunger[name] = h
					hbhunger.set_hunger_raw(player)
				end
			end

			-- update all hud elements
			update_hud(player)
			
			local controls = player:get_player_control()
			-- Determine if the player is walking
			if controls.up or controls.down or controls.left or controls.right then
				hbhunger.handle_node_actions(nil, nil, player)
			end
		end
	end
	if timer > 4 then timer = 0 end
	if timer2 > hbhunger.HUNGER_TICK then timer2 = 0 end
end)

core.register_chatcommand("satiation", {
	privs = {["server"]=true},
	params = S("[<player>] <satiation>"),
	description = S("Set satiation of player or yourself"),
	func = function(name, param)
		if core.settings:get_bool("enable_damage") == false then
			return false, S("Not possible, damage is disabled.")
		end
		local targetname, satiation = string.match(param, "(%S+) (%S+)")
		if not targetname then
			satiation = param
		end
		satiation = tonumber(satiation)
		if not satiation then
			return false, S("Invalid satiation!")
		end
		if not targetname then
			targetname = name
		end
		local target = core.get_player_by_name(targetname)
		if target == nil then
			return false, S("Player @1 does not exist.", targetname)
		end
		if satiation > hbhunger.SAT_MAX then
			satiation = hbhunger.SAT_MAX
		elseif satiation < 0 then
			satiation = 0
		end
		hbhunger.hunger[targetname] = satiation
		hbhunger.set_hunger_raw(target)
		return true
	end,
})

end

-- =====================================================================
-- THE FINAL OVERRIDE: FORCE 162PX FILL ON HEALTH, BREATH & CUSTOM BARS
-- =====================================================================

-- 1. FORCE CORE LAYOUT DIMENSION
hb.settings.max_bar_length = 162

-- 2. DYNAMIC INTERCEPT: Fixes scaling math for every custom bar in memory
local original_value_to_barlength = hb.value_to_barlength
function hb.value_to_barlength(value, max)
	if max > 0 and value >= max then
		return 162
	end
	return original_value_to_barlength(value, max)
end

-- 3. FORCED RUNTIME RETRO-FIT: Fixes bars that registered before this file finished loading
for identifier, hudtable in pairs(hb.hudtables) do
	if hudtable then
		hudtable.max_bar_length = 162
	end
end

-- 4. STABLE LAYER SYNC (Your proven working fix that keeps letters on top)
local original_change_hudbar = hb.change_hudbar
function hb.change_hudbar(player, identifier, new_value, new_max_value, new_icon, new_bgicon, new_bar, new_label, new_text_color)
	local success = original_change_hudbar(player, identifier, new_value, new_max_value, new_icon, new_bgicon, new_bar, new_label, new_text_color)
	
	if success and player and player:is_player() then
		local name = player:get_player_name()
		local hudtable = hb.get_hudtable(identifier)
		
		if hudtable and hudtable.hudids[name] and hudtable.hudids[name].text then
			player:hud_change(hudtable.hudids[name].text, "z_index", 10)
		end
	end
	return success
end

-- 5. HP SECURITY LAYER (Caps current HP to Max HP safely)
local sync_timer = 0
minetest.register_globalstep(function(dtime)
	sync_timer = sync_timer + dtime
	if sync_timer >= 0.15 then
		sync_timer = 0
		for _, player in pairs(minetest.get_connected_players()) do
			if player and player:is_player() then
				local current_hp = player:get_hp()
				local max_hp = player:get_properties().hp_max or 20
				
				if current_hp > max_hp then
					player:set_hp(max_hp)
					hb.change_hudbar(player, "health", max_hp, max_hp)
				end
			end
		end
	end
end)

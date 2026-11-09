--=========================================================================================
-- Aura icon row: per-class buff/debuff icons above the topmost visible swing bar.
--
-- WOW FOREVER ONLY. On every other client the module is COMPLETELY inert: its gate
-- answers false at load, and no frame, event, aura read or option side effect exists
-- (the option widgets are hidden by the same family check in option_tables.lua).
--
-- WHAT IT IS. Two native `AuraContainer` frames (the WoW Forever aura-container system,
-- `origin/forever`: Blizzard_AuraContainer/Blizzard_CustomAuraContainer.xml, declared
-- `allowUntaintedCreation="true"` for addons):
--   * a HELPFUL row on unit "player"  - temporary procs / short self buffs
--   * a HARMFUL row on unit "target"  - the player's OWN target debuffs ("HARMFUL|PLAYER":
--     `PLAYER` is the client's own-caster filter, Blizzard_FrameXMLUtil/AuraUtil.lua:274,
--     which includes the player's pet/vehicle). No combat log and no aura bookkeeping is
--     needed for that identity check: the client does it.
-- The addon DECLARES the spell ids per class (includeSpellIDs); the client matches them,
-- fills the icons, and writes the duration text / stacks / duration bar through
-- secret-safe widget setters. The module therefore reads ZERO aura data: no aura entry,
-- no spell id, no expiration, no stack count. That is the whole point of the native path
-- and it is what keeps the row working while Forever shrouds auras as secret values.
--
-- SECRET-GEOMETRY RULE (the biggest porting hazard). The client sizes aura containers
-- through `secretwrap` (Blizzard_CustomAuraContainer.lua:794-801: ApplyElementLayout and
-- OnLayoutComplete -> `container:SetSize(secretwrap(width, height))`), so a container's
-- height/top/width can be a SECRET value: measuring one would raise or produce an
-- unusable number. The module NEVER measures an aura container. It reserves a fixed band
-- from the configured icon size instead:
--
--        +------------------ buff row (HELPFUL, player) ------------------+
--        +------------------ debuff row (HARMFUL|PLAYER) -----------------+   bottom = anchor top + BAR_GAP + (hunter anchor ? HUNTER_GAP : 0)
--        ======================= topmost visible swing bar =====================
--   buff bottom = anchor top + BAR_GAP + hunter gap + (debuff row visible ? icon size + TEXT_CLEARANCE : 0)
--   anchor = topmost of the visible swing bar, hunter cast bar, Rapid Fire bar and target warning
--
-- Cosmetic consequence (documented, not a bug): with the debuff row hidden the buff row
-- sits one band lower than it strictly needs to; with it visible the 16 px clearance
-- leaves room for the client's duration text above the debuff icons.
--
-- PLACEMENT. The top bar is chosen from PLAIN GEOMETRY of the addon's own swing bars:
-- `ST:iter_hands()` + `ST:get_bar_frame(hand)` (bars.lua), highest visible `GetTop()`
-- wins, an exact tie keeps the first hand in class order. When the hunter cast bar /
-- Rapid Fire / target-warning top is higher, that widget becomes the anchor (plain
-- `GetTop`; aura-container geometry is still never read). A secret or unreadable
-- `GetTop`/`IsShown` is skipped, never compared. A throttled 0.15 s pass re-anchors when
-- the anchor identity/top, the icon size or a toggle changed; a 0.5 s retry builds
-- the containers when the first attempt failed or was deferred by combat lockdown. The
-- driver is a plain (non-secure) Frame: it is the only frame created while locked down,
-- and it exists precisely so the native containers are never created inside combat.
--
-- SERVER BEHAVIOUR THE OPERATOR SHOULD KNOW. Identity matching is privilege-gated by the
-- client (Blizzard_AuraContainerUtil.lua:52-110): includeSpellIDs works for helpful auras
-- on player/group units and harmful auras on NON-assistable (hostile) targets. On a
-- friendly/assistable target the client rejects every harmful candidate, so the debuff row
-- is EMPTY there by design - it is not a bug in this module.
--
-- NO SuperSwingTimer names: this file is a port of the mechanics from
-- bench/aura_row_reference_2026-11-08.md, not of that addon's state model; its legacy
-- namespace, per-class toggles and debuff-bar bookkeeping do not exist here.
--=========================================================================================
local addon_name, st = ...

st.aura_icons = st.aura_icons or {}
local A = st.aura_icons

--=========================================================================================
-- Forever-only gate (pure reads; nothing is created here)
--=========================================================================================
-- Three layers, cheapest first: the repo's own family discriminator, then the native
-- aura-container globals, then (at init) the CreateFrame probe itself. On a non-Forever
-- client the first check answers false before any aura API is reachable, which is the
-- operator's hard requirement ("the aura thing should be wow forever only").
local function global_table(name)
	local ok, value = pcall(rawget, _G, name)
	if not ok then
		return nil
	end
	return type(value) == "table" and value or nil
end

local function client_can_have_aura_rows()
	if st.family ~= "FOREVER" then
		return false, "family"
	end
	if global_table("C_AuraContainerUtil") == nil then
		return false, "C_AuraContainerUtil"
	end
	if global_table("AuraContainerSortMethod") == nil then
		return false, "AuraContainerSortMethod"
	end
	if global_table("AuraContainerSortDirection") == nil then
		return false, "AuraContainerSortDirection"
	end
	return true, "ok"
end

function A.gate()
	return client_can_have_aura_rows()
end

A.available, A.gate_reason = client_can_have_aura_rows()

-- The options layer hides every aura-row control on this answer (plus its own family
-- check). Fail closed: a non-Forever client, or a Forever client missing the native
-- surface, never sees a control for a row that cannot exist.
function A.options_visible()
	return A.available == true
end

--=========================================================================================
-- Shipped defaults (config_presets.lua carries the AceDB copy; tests pin them together)
--=========================================================================================
-- Nil-safe everywhere: nil = this shipped default, `== false` disables.
A.DEFAULTS = {
	enabled = true, -- operator order 2026-11-08: the Forever row ships ON
	show_debuffs = true,
	size = 27,
	spacing = 3,
	grow = "right",
}

-- Cadences and geometry (px). MAINTAIN_INTERVAL is the reference's 0.15 s pass.
A.MAINTAIN_INTERVAL = 0.15
A.RETRY_INTERVAL = 0.5
-- A row shows at most 16 icons (the reference's min(spellCount, 16)); one line.
A.MAX_FRAMES = 16
-- Any non-nil maxDuration implicitly hides permanent auras, so passive/talent record ids
-- in the lists below can never paint a permanent icon. 180 s = the reference's value.
A.BUFF_MAX_DURATION = 180
-- Space from the top bar's top edge to the debuff icons' bottom edge. It also has to
-- clear the 3 px duration bar + 2 px gap that hang below a debuff icon (5 px total).
A.BAR_GAP = 6
-- Extra clearance when the anchor is a hunter widget (cast bar / Rapid Fire / target
-- warning). The 2026-11-09 screenshot showed the aura icon only ~2 px above the Auto Shot
-- bar: the row was correctly above the cast bar but visually touching it. This is added
-- only for the hunter-widget anchor; the swing-bar gap stays A.BAR_GAP.
A.HUNTER_GAP = 6
-- Fallback when the hunter cast bar is not visible: at least 15 px above the ranged
-- bar (operator rule 2026-11-09). The cast bar is only used while it is SHOWN; a hidden
-- cast frame must not reserve space above the row.
A.HUNTER_RANGED_GAP = 15
-- Clearance above the debuff row for the client's duration text (the reference's
-- DEBUFF_TEXT_CLEARANCE; the buff row is anchored above this fixed band, never above a
-- measured container).
A.TEXT_CLEARANCE = 16
A.DURATION_BAR_HEIGHT = 3
A.DURATION_BAR_GAP = 2
A.STRATA_FALLBACK = "MEDIUM"
-- The comma-joined template string is ONE argument - Blizzard joins templates the same
-- way (Blizzard_AuraContainerFrameProviders.lua:34). The second template opts the frame
-- into the forbidden-aspect discipline the container needs once a group exists.
A.TEMPLATE = "CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate"
A.TEMPLATE_FALLBACK = "CustomAuraContainerTemplate"
A.DRIVER_NAME = addon_name .. "AuraIconsDriver"
A.ICON_TEXCOORD = { 0.07, 0.93, 0.07, 0.93 }
A.BORDER_COLOR = { 0, 0, 0, 0.65 }

-- One descriptor per row. `group` is the AddAuraGroup key (asserted unique by the
-- client); `container` the global frame name (unique - a second init reuses the frame).
A.ROWS = {
	buffs = {
		key = "buffs",
		group = "buffs",
		unit = "player",
		filter = "HELPFUL",
		container = addon_name .. "AuraIconsBuffs",
		with_bar = false,
		max_duration = A.BUFF_MAX_DURATION,
	},
	debuffs = {
		key = "debuffs",
		group = "debuffs",
		unit = "target",
		filter = "HARMFUL|PLAYER",
		container = addon_name .. "AuraIconsDebuffs",
		with_bar = true,
	},
}

local ROW_KEYS = { "buffs", "debuffs" }

-- Runtime state (one table; no file-scope mutable locals, so a reload of the file cannot
-- leave a half-initialised closure behind - and the offline suite can inspect it).
A.state = {
	addon = nil,
	driver = nil,
	rows = {
		buffs = { container = nil, built = false, enabled = false },
		debuffs = { container = nil, built = false, enabled = false },
	},
	lists = nil,
	class = nil,
	shown = { buffs = false, debuffs = false },
	layout = nil,
	last = { bar = nil, bar_top = nil, buff_offset = nil, debuff_offset = nil },
	ready = false,
	inert = false,
	no_class_list = false,
	attempts = 0,
	error = nil,
	deferred = nil,
	elapsed = 0,
	next_retry = nil,
	failures = 0,
	last_error = nil,
	anchor_error = nil,
	layout_error = nil,
}

--=========================================================================================
-- Per-class Forever spell-id lists (provenance: bench/aura_row_reference_2026-11-08.md §4)
--=========================================================================================
-- These are the POST-MERGE lists the reference ships: the class's own list followed by the
-- new-Forever ability candidates (an id that never applies an aura of the other kind is a
-- harmless set member; the reference merges candidates into both tiers because offline it
-- cannot tell which tier a candidate belongs to - pinned by tests/aura_icons_state.lua).
-- The class arrays stay PURE: the shared and racial ids are merged into a copy at
-- container-creation time only (the client securecopies includeSpellIDs, so mutating our
-- table after AddAuraGroup would be invisible to it anyway).
--
-- 27019 (the TBC Serpent Sting rank) is DELIBERATELY EXCLUDED - the reference keeps it
-- only for TBC Anniversary. Do not "restore parity" by re-adding it.
-- The reference's stance tier (aspects/stances/seals/shields/forms/stealth) is NOT ported
-- here and must never leak into either list (pinned by the suite).
A.BUFFS = {
	WARRIOR = {
		7384, 7887, 11584, 11585, -- Overpower r1-r4
		2565, -- Shield Block (Forever: 7 s)
		12319, 12320, -- Flurry talent + rank-1 buff aura
		12292, -- Death Wish (Forever: 30 s)
		1719, -- Recklessness (Forever: 15 s)
		12328, -- Sweeping Strikes
		20230, -- Retaliation
		871, -- Shield Wall (Forever: 12 s)
		12975, -- Last Stand
		23920, -- Spell Reflection
		18499, -- Berserker Rage
		30033, -- Rampage
		2687, -- Bloodrage
		12317, -- Enrage
		23881, 23892, 23893, 23894, -- Bloodthirst r1-r4 (Forever: new 10 s self buff)
		1329555, -- Reckless Swings (Forever: new, 8 s)
		402927, 1310222, 1240193, -- candidates
	},
	PALADIN = {
		31884, -- Avenging Wrath
		642, 1020, -- Divine Shield r1-r2
		10278, 1022, 5599, -- Blessing of Protection r1-r3
		20925, 20927, 20928, 1239570, -- Holy Shield r1-r4 (r4 new in Forever)
		498, 5573, -- Divine Protection r1-r2
		20049, 20050, -- Vengeance talent + rank-1 buff aura
		1310735, -- Unsealed Wrath (Forever: new, 15 s / 3 stacks)
		679, 1311606, -- candidates
	},
	SHAMAN = {
		30823, -- Shamanistic Rage
		16280, -- Flurry (Classic rank)
		16256, -- Flurry (Forever talent; buff aura is server-side)
		29180, -- Elemental Devastation
		425336, -- Rage of the Farseer (Forever: new, +30% attack speed, 25 s)
		408505, -- Maelstrom Weapon aura (Instant, 30 s, -20% Lightning Bolt)
		408498, -- Maelstrom Weapon talent/buff record (passive; harmless if not an aura)
		1223031, -- Improved Stormstrike (Forever: 15 s mana-regen buff)
		408341, -- candidate
	},
	DRUID = {
		16870, -- Clearcasting
		5217, -- Tiger's Fury
		22842, -- Frenzied Regeneration
		22812, -- Barkskin
		1850, 9821, -- Dash r1-r2
		5229, -- Enrage
		29166, -- Innervate
		407995, 16958, 1223246, 417051, -- candidates
	},
	ROGUE = {
		5171, 6774, -- Slice and Dice r1-r2 (Forever: 9-21 s by CP)
		13750, -- Adrenaline Rush
		13877, -- Blade Flurry (Forever: +20% attack speed, 15 s)
		14177, -- Cold Blood
		5277, -- Evasion
		2983, 8696, 11305, -- Sprint r1-r3
		1856, 1857, -- Vanish r1-r2
		14179, -- Premeditation (Classic rank)
		14183, -- Premeditation (Forever: 20 s)
		36554, -- Shadowstep
		31209, -- Cloak of Shadows
		14278, -- Ghostly Strike (Forever: 7 s)
		1329328, 1310703, -- Venom ability + triggered buff aura
		1329283, 399956, 1329256, 1328825, -- candidates
	},
	HUNTER = {
		19574, -- Bestial Wrath
		3045, -- Rapid Fire
		34692, -- The Beast Within
		6150, -- Quick Shots
		34949, -- Rapid Killing
		34477, -- Misdirection
		19552, -- Deadly Aspects (Forever: new, +30% melee haste, 12 s)
		1317257, 19306, 1495, 2973, -- candidates
	},
}

A.DEBUFFS = {
	WARRIOR = {
		772, 6546, 6547, 6548, 11572, 11573, 11574, -- Rend (Forever: unchanged)
		12721, 12834, -- Deep Wounds aura + talent candidate
		7386, 7405, 8380, 11596, 11597, 25225, -- Sunder Armor (unchanged, 5 stacks)
		6343, 8198, 8204, 8205, 11580, 11581, -- Thunder Clap (10 s, 20% slow)
		1160, 6190, 11554, 11555, 11556, -- Demoralizing Shout (Forever: 45 s)
		402927, 1310222, 1240193, -- candidates (merged into both tiers)
	},
	PALADIN = {
		20188, 20300, 20301, 20302, 20303, -- Judgement of the Crusader r2-r6 (Forever: 40 s)
		20185, 20344, 20345, 20346, -- Judgement of Light r1-r4 (Forever: 40 s)
		20186, 20354, 20355, -- Judgement of Wisdom r1-r3 (Forever: 40 s)
		20183, 20411, 20412, 20413, 20414, -- Judgement of Fury r3-r7 (Forever: new 3 s taunt)
		679, 1311606, -- candidates
		-- Seal of Vengeance / Seal of Corruption do not exist in Forever: never add them.
	},
	SHAMAN = {
		8050, 8052, 8053, 10447, 10448, 29228, -- Flame Shock (Forever: 12 s)
		17364, -- Stormstrike (Forever: 12 s)
		8056, 8058, 10472, 10473, -- Frost Shock (Forever: 8 s slow)
		8042, 8044, 8045, 8046, 10412, 10413, 10414, -- Earth Shock r1-r7
		408341, -- candidate
	},
	DRUID = {
		1079, 9492, 9493, 9752, 9894, 9896, 27008, -- Rip (Forever: 12 s)
		1822, 1823, 1824, 9904, 27006, -- Rake (r4 = 9904; 9907 is Faerie Fire)
		1328617, 1328616, 414644, 1235826, 1235827, -- Lacerate (Forever r1-r5, 15 s / 5)
		770, 778, 9749, 9907, -- Faerie Fire (Forever: usable in forms, 40 s)
		99, 1735, 9490, 9747, 9898, -- Demoralizing Roar (Forever: 30 s)
		407995, 16958, 1223246, 417051, -- candidates
		-- Mangle 33876/33878 and Faerie Fire (Feral) 16857 were REMOVED from Forever
		-- 1.60.1 (Primal Bite 407995 replaces Mangle and has no debuff): never add back.
	},
	ROGUE = {
		1943, 8637, 8639, 8640, 11273, 11274, 11275, 26867, -- Rupture (Forever r6 = 11275)
		8647, 8649, 8650, 11197, 11198, 26996, -- Expose Armor (Forever: 30 s)
		16511, -- Hemorrhage (Forever: 15 s)
		1329283, 399956, 1329256, 1328825, -- candidates
	},
	HUNTER = {
		1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295, -- Serpent Sting (r9 = 25295)
		-- 27019 is the TBC rank: EXCLUDED (the reference keeps it only for TBC Anniversary).
		2974, 14267, 14268, -- Wing Clip (Forever r2/r3 = 14267/14268)
		5116, 13585, 13586, 13587, 13588, 13589, 13590, 27068, -- Concussion Shot
		13795, 14302, -- Immolation Trap
		13813, 14303, 14304, 14305, -- Explosive Trap
		1499, 14310, 14311, 3355, 14308, 14309, -- Freezing Trap
		13809, 13810, -- Frost Trap
		1130, 14323, 14324, 14325, -- Hunter's Mark (Forever ranks 1-4, 120 s)
		1310533, -- Lacerating Strikes (Forever: 21 s bleed)
		1265831, -- Savage Rend (Forever pet bleed, 18 s)
		1317257, 19306, 1495, 2973, -- candidates
	},
}

-- Shared buffs are merged into the BUFF row only, never into a class list (the
-- reference's deliberate rule). All five are absent from the 1.15.9 client data yet
-- shipped by the reference as Forever buffs - Forever is a custom server.
A.SHARED = { 2825, 32182, 35476, 35477, 28507 }

-- The player's OWN race only; `UnitRace`'s file token is probed first, then the
-- localized name (clients disagree; `Scourge` and `Undead` are both Undead's tokens).
A.RACIAL = {
	Orc = { 20572 },
	Troll = { 26297 },
	Draenei = { 28880 },
	BloodElf = { 28730 },
	Human = { 20600 },
	Dwarf = { 20594 },
	Gnome = { 20589 },
	Undead = { 7744 },
	Scourge = { 7744 },
	NightElf = { 58984 },
}

--=========================================================================================
-- Small helpers (no WoW API except where named)
--=========================================================================================
local function copy_list(list)
	local out = {}
	if type(list) ~= "table" then
		return out
	end
	for index = 1, #list do
		local value = list[index]
		if type(value) == "number" then
			out[#out + 1] = value
		end
	end
	return out
end

-- In-place unique append (numbers only), the reference's AppendUnique semantics.
local function append_unique(target, values)
	if type(values) ~= "table" then
		return target
	end
	local seen = {}
	for index = 1, #target do
		seen[target[index]] = true
	end
	for index = 1, #values do
		local value = values[index]
		if type(value) == "number" and not seen[value] then
			seen[value] = true
			target[#target + 1] = value
		end
	end
	return target
end

-- Never upper-case/index a value the client could have made secret.
local function is_secret(value)
	local api = st.api
	if type(api) ~= "table" or type(api.is_secret) ~= "function" then
		return false
	end
	local ok, secret = pcall(api.is_secret, value)
	if not ok then
		return true
	end
	return secret == true
end

local function plain_upper(token)
	if type(token) ~= "string" or is_secret(token) then
		return nil
	end
	local ok, upper = pcall(string.upper, token)
	if not ok or type(upper) ~= "string" then
		return nil
	end
	return upper
end

local function now_seconds()
	local api = st.api
	if type(api) ~= "table" or type(api.get_time) ~= "function" then
		return nil
	end
	local ok, value = pcall(api.get_time)
	if not ok or type(value) ~= "number" or is_secret(value) then
		return nil
	end
	return value
end

local function in_combat()
	local lockdown = rawget(_G, "InCombatLockdown")
	if type(lockdown) ~= "function" then
		return false
	end
	local ok, combat = pcall(lockdown)
	return ok and combat == true
end

local function class_db(ST)
	if type(ST) ~= "table" or type(ST.get_class_table) ~= "function" then
		return nil
	end
	local ok, db = pcall(ST.get_class_table, ST)
	if ok and type(db) == "table" then
		return db
	end
	return nil
end

local function profile_db(ST)
	if type(ST) ~= "table" or type(ST.get_profile_table) ~= "function" then
		return nil
	end
	local ok, db = pcall(ST.get_profile_table, ST)
	if ok and type(db) == "table" then
		return db
	end
	return nil
end

local function strata_for(ST)
	local db = profile_db(ST)
	local strata = db and db.frame_strata
	if type(strata) == "string" and strata ~= "" then
		return strata
	end
	return A.STRATA_FALLBACK
end

local function announce(message)
	local utils = st.utils
	if type(utils) == "table" and type(utils.print_msg) == "function" then
		pcall(utils.print_msg, message)
	end
end

--=========================================================================================
-- Option resolution (nil = shipped default, == false disables)
--=========================================================================================
function A.option_enabled(db)
	if type(db) ~= "table" then
		return A.DEFAULTS.enabled == true
	end
	return db.aura_icons_enabled ~= false
end

function A.option_debuffs(db)
	if type(db) ~= "table" then
		return A.DEFAULTS.show_debuffs == true
	end
	return db.aura_icons_show_debuffs ~= false
end

local function clamped_number(value, fallback, minimum, maximum)
	local number = tonumber(value)
	if number == nil then
		number = fallback
	end
	number = math.floor(number + 0.5)
	if number < minimum then
		number = minimum
	end
	if number > maximum then
		number = maximum
	end
	return number
end

function A.option_size(db)
	local value = type(db) == "table" and db.aura_icons_size or nil
	return clamped_number(value, A.DEFAULTS.size, 12, 48)
end

function A.option_spacing(db)
	local value = type(db) == "table" and db.aura_icons_spacing or nil
	return clamped_number(value, A.DEFAULTS.spacing, 0, 12)
end

function A.option_grow(db)
	local value = type(db) == "table" and db.aura_icons_grow or nil
	if value == "left" then
		return "left"
	end
	return A.DEFAULTS.grow
end

--=========================================================================================
-- Pure list builders (unit-tested without a frame)
--=========================================================================================
function A.spell_set(list)
	local set = {}
	if type(list) ~= "table" then
		return set
	end
	for index = 1, #list do
		local id = list[index]
		if type(id) == "number" then
			set[id] = true
		end
	end
	return set
end

function A.racial_ids(token)
	if type(token) ~= "string" or is_secret(token) then
		return {}
	end
	local list = A.RACIAL[token]
	if list == nil then
		return {}
	end
	return copy_list(list)
end

-- Build the buff row's includeSpellIDs list: class list + shared + the player's race.
-- Returns a NEW list; the class/shared/racial tables are never mutated.
function A.build_buff_list(class_token, race_token, race_localized)
	local class = plain_upper(class_token)
	local base = class and A.BUFFS[class] or nil
	local list = copy_list(base)
	append_unique(list, A.SHARED)
	if race_token ~= nil then
		append_unique(list, A.racial_ids(race_token))
	end
	if race_localized ~= nil and race_localized ~= race_token then
		append_unique(list, A.racial_ids(race_localized))
	end
	return list
end

function A.build_debuff_list(class_token)
	local class = plain_upper(class_token)
	local base = class and A.DEBUFFS[class] or nil
	return copy_list(base)
end

-- UnitRace returns (localizedName, raceFile). Read both, never index a secret token.
function A.player_race_tokens()
	local read = rawget(_G, "UnitRace")
	if type(read) ~= "function" then
		return nil, nil
	end
	local ok, localized, file_token = pcall(read, "player")
	if not ok then
		return nil, nil
	end
	if is_secret(localized) or type(localized) ~= "string" then
		localized = nil
	end
	if is_secret(file_token) or type(file_token) ~= "string" then
		file_token = nil
	end
	return file_token, localized
end

function A.player_racial_ids()
	local file_token, localized = A.player_race_tokens()
	local list = {}
	append_unique(list, A.racial_ids(file_token))
	if localized ~= file_token then
		append_unique(list, A.racial_ids(localized))
	end
	return list
end

--=========================================================================================
-- Plain-geometry helpers: the swing bars are addon frames, their geometry is plain
--=========================================================================================
local function frame_is_shown(frame)
	if frame == nil or type(frame.IsShown) ~= "function" then
		return false
	end
	local ok, shown = pcall(function()
		return frame:IsShown() == true
	end)
	return ok and shown == true
end

local function frame_top(frame)
	if frame == nil or type(frame.GetTop) ~= "function" then
		return nil
	end
	local ok, top = pcall(function()
		return frame:GetTop()
	end)
	if not ok or type(top) ~= "number" or is_secret(top) then
		return nil
	end
	return top
end

--=========================================================================================
-- Button styling: every step isolated (the client validates each widget it is handed)
--=========================================================================================
local function current_icon_size()
	return A.option_size(class_db(A.state.addon))
end

local function current_spacing()
	return A.option_spacing(class_db(A.state.addon))
end

local function current_grow()
	return A.option_grow(class_db(A.state.addon))
end

local function add_border(button)
	local edges = {
		{ "TOPLEFT", "TOPRIGHT", true },
		{ "BOTTOMLEFT", "BOTTOMRIGHT", true },
		{ "TOPLEFT", "BOTTOMLEFT", false },
		{ "TOPRIGHT", "BOTTOMRIGHT", false },
	}
	for index = 1, #edges do
		local edge = edges[index]
		local line = button:CreateTexture(nil, "OVERLAY")
		line:SetColorTexture(A.BORDER_COLOR[1], A.BORDER_COLOR[2], A.BORDER_COLOR[3], A.BORDER_COLOR[4])
		line:SetPoint(edge[1], button, edge[1], 0, 0)
		line:SetPoint(edge[2], button, edge[2], 0, 0)
		if edge[3] then
			line:SetHeight(1)
		else
			line:SetWidth(1)
		end
	end
end

-- The client calls this once per aura button it creates (through securecallfunction, with
-- the button's object table). Nothing here reads aura data: the icon, duration text,
-- stacks and bar are all written by the client's own binding afterwards.
local function style_button(button, with_bar)
	if type(button) ~= "table" then
		return
	end
	local size = current_icon_size()
	local ok_size = pcall(function()
		button:SetSize(size, size)
	end)
	if not ok_size then
		-- A button that cannot be sized would render as an unanchored blob; leave it bare.
		return
	end
	pcall(function()
		local icon = button:CreateTexture(nil, "BACKGROUND")
		icon:SetAllPoints(button)
		icon:SetTexCoord(A.ICON_TEXCOORD[1], A.ICON_TEXCOORD[2], A.ICON_TEXCOORD[3], A.ICON_TEXCOORD[4])
		button:SetIcon(icon)
	end)
	pcall(add_border, button)
	pcall(function()
		local text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		text:SetPoint("BOTTOM", button, "TOP", 0, 1)
		text:SetJustifyH("CENTER")
		button:SetDurationText(text)
	end)
	pcall(function()
		local count = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -1, 1)
		count:SetJustifyH("RIGHT")
		button:SetApplicationCount(count)
	end)
	if with_bar then
		pcall(function()
			local bar = CreateFrame("StatusBar", nil, button)
			bar:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -A.DURATION_BAR_GAP)
			bar:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -A.DURATION_BAR_GAP)
			bar:SetHeight(A.DURATION_BAR_HEIGHT)
			bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
			bar:SetMinMaxValues(0, 1)
			bar:SetValue(0)
			local enum = rawget(_G, "Enum")
			local timer_direction = type(enum) == "table" and type(enum.StatusBarTimerDirection) == "table"
				and enum.StatusBarTimerDirection.RemainingTime or nil
			if timer_direction ~= nil then
				button:SetDurationBar(bar, { direction = timer_direction })
			else
				button:SetDurationBar(bar)
			end
		end)
	end
end

--=========================================================================================
-- Container construction
--=========================================================================================
local function create_container(name)
	if type(CreateFrame) ~= "function" or UIParent == nil then
		return nil
	end
	local ok, frame = pcall(CreateFrame, "AuraContainer", name, UIParent, A.TEMPLATE)
	if ok and frame ~= nil then
		return frame
	end
	local ok_plain, plain = pcall(CreateFrame, "AuraContainer", name, UIParent, A.TEMPLATE_FALLBACK)
	if ok_plain and plain ~= nil then
		return plain
	end
	return nil
end

local function has_group(container, key)
	if type(container.HasAuraGroup) ~= "function" then
		return false
	end
	local ok, has = pcall(container.HasAuraGroup, container, key)
	return ok and has == true
end

local function flow_direction(name, fallback)
	local anchor_util = rawget(_G, "AnchorUtil")
	if type(anchor_util) == "table" and type(anchor_util.FlowDirection) == "table" then
		local value = anchor_util.FlowDirection[name]
		if type(value) == "number" then
			return value
		end
	end
	return fallback
end

local function apply_flow(container, grow)
	if container == nil then
		return false
	end
	local point = "BOTTOMLEFT"
	local horizontal = flow_direction("Right", 1)
	if grow == "left" then
		point = "BOTTOMRIGHT"
		horizontal = flow_direction("Left", -1)
	end
	local vertical = flow_direction("Down", -1)
	local ok_point = pcall(container.SetFlowLayoutAnchorPoint, container, point)
	local ok_grow = pcall(container.SetFlowLayoutGrowthDirection, container, horizontal, vertical)
	return ok_point and ok_grow
end

local function group_options(row_key, list)
	local row = A.ROWS[row_key]
	local size = current_icon_size()
	local spacing = current_spacing()
	local candidate_filters = { includeSpellIDs = A.spell_set(list) }
	if row.max_duration ~= nil then
		candidate_filters.maxDuration = row.max_duration
	end
	local sort_method = global_table("AuraContainerSortMethod")
	local sort_direction = global_table("AuraContainerSortDirection")
	return {
		candidateFilters = candidate_filters,
		maxFrameCount = math.min(#list, A.MAX_FRAMES),
		layout = { elementWidth = size, elementHeight = size, elementSpacing = spacing },
		initializeFrame = function(button)
			style_button(button, row.with_bar)
		end,
		sortMethod = sort_method and sort_method.Expiration or nil,
		sortDirection = sort_direction and sort_direction.Normal or nil,
	}
end

-- The client's frame provider allocates a batch of buttons up-front; a size change has to
-- resize the ones that already exist (the group layout only positions them). The count is
-- derived from aura frames and can be secret - skip it, never compare it.
local function resize_group_frames(container, group_key, size)
	if container == nil or type(container.GetAuraGroupFrameCount) ~= "function" then
		return true
	end
	local ok_count, count = pcall(container.GetAuraGroupFrameCount, container, group_key)
	if not ok_count or type(count) ~= "number" or is_secret(count) then
		return ok_count
	end
	local ok_all = true
	for index = 1, count do
		local ok_frame, frame = pcall(container.GetAuraGroupFrame, container, group_key, index)
		if ok_frame and frame ~= nil then
			local ok_size = pcall(function()
				frame:SetSize(size, size)
			end)
			ok_all = ok_all and ok_size
		end
	end
	return ok_all
end

local function set_shown(row_key, want)
	local state = A.state.rows[row_key]
	local container = state.container
	if container == nil then
		A.state.shown[row_key] = false
		return true
	end
	local ok
	if want then
		ok = pcall(container.Show, container)
	else
		ok = pcall(container.Hide, container)
	end
	if ok then
		A.state.shown[row_key] = want == true
	end
	return ok
end

local function set_row_point(container, bar, offset)
	if container == nil then
		return true
	end
	return (pcall(function()
		container:ClearAllPoints()
		container:SetPoint("BOTTOM", bar, "TOP", 0, offset)
	end))
end

-- Push the wanted icon layout to every existing row; returns true when nothing was due.
local function sync_layout(ST)
	local size = A.option_size(class_db(ST))
	local spacing = A.option_spacing(class_db(ST))
	local grow = A.option_grow(class_db(ST))
	local current = A.state.layout
	if current ~= nil and current.size == size and current.spacing == spacing and current.grow == grow then
		return false
	end
	local size_changed = current ~= nil and current.size ~= size
	local grow_changed = current == nil or current.grow ~= grow
	local ok_all = true
	for index = 1, #ROW_KEYS do
		local key = ROW_KEYS[index]
		local container = A.state.rows[key].container
		if container ~= nil then
			local ok_layout = pcall(container.SetAuraGroupLayout, container, A.ROWS[key].group, {
				elementWidth = size,
				elementHeight = size,
				elementSpacing = spacing,
			})
			ok_all = ok_all and ok_layout
			if grow_changed then
				ok_all = apply_flow(container, grow) and ok_all
			end
			if size_changed then
				ok_all = resize_group_frames(container, A.ROWS[key].group, size) and ok_all
			end
		end
	end
	A.state.layout = { size = size, spacing = spacing, grow = grow }
	A.state.layout_error = ok_all and nil or "layout"
	return true
end

--=========================================================================================
-- Driver / event frame (plain Frame; created before any native container)
--=========================================================================================
local function ensure_driver()
	if A.state.driver ~= nil then
		return A.state.driver
	end
	if type(CreateFrame) ~= "function" or UIParent == nil then
		A.state.inert = true
		return nil
	end
	local ok, frame = pcall(CreateFrame, "Frame", A.DRIVER_NAME, UIParent)
	if not ok or frame == nil then
		-- The client cannot create frames at all: no retry can change that.
		A.state.inert = true
		return nil
	end
	A.state.driver = frame
	local ok_update = pcall(frame.SetScript, frame, "OnUpdate", function(_, elapsed)
		A.on_update(elapsed)
	end)
	if not ok_update then
		A.state.driver = nil
		A.state.inert = true
		return nil
	end
	pcall(frame.SetScript, frame, "OnEvent", function(_, event)
		A.on_event(event)
	end)
	pcall(frame.RegisterEvent, frame, "PLAYER_ENTERING_WORLD")
	return frame
end

--=========================================================================================
-- Row construction (resumable: a failed attempt retries the same frame, never a latch)
--=========================================================================================
local function build_row(ST, row_key)
	local row = A.ROWS[row_key]
	local state = A.state.rows[row_key]
	local list = A.state.lists and A.state.lists[row_key] or nil
	if type(list) ~= "table" or #list == 0 then
		return true, false, false
	end
	if state.container == nil then
		local container = create_container(row.container)
		if container == nil then
			A.state.error = "container:" .. row_key
			return false, false, true
		end
		local ok_setup = pcall(function()
			container:SetSize(1, 1)
			container:SetFrameStrata(strata_for(ST))
			container:SetUnit(row.unit)
		end)
		if not ok_setup then
			pcall(container.Hide, container)
			A.state.error = "setup:" .. row_key
			return false, false, true
		end
		state.container = container
		state.created = true
	end
	local container = state.container
	if container == nil then
		return false, false, true
	end
	if not state.built then
		if not has_group(container, row.group) then
			local ok_group = pcall(container.AddAuraGroup, container, row.group, row.filter,
				group_options(row_key, list))
			if not ok_group or not has_group(container, row.group) then
				pcall(container.Hide, container)
				A.state.error = "group:" .. row_key
				return false, false, false
			end
		end
		state.built = true
	end
	if not state.flow_configured then
		state.flow_configured = apply_flow(container, current_grow()) and true or nil
	end
	if not state.enabled then
		state.enabled = (pcall(container.SetEnabled, container, true)) and true or nil
	end
	return true, state.created == true, false
end

--=========================================================================================
-- Anchor: topmost visible bar from plain geometry, fixed-band rows, no container measures
--=========================================================================================
-- The row must clear the hunter Auto Shot cast bar while it is SHOWN. When the visible
-- cast/Rapid Fire/target-warning top is above the topmost swing bar, anchor above that
-- widget (BAR_GAP + HUNTER_GAP). When no cast widget is visible, use the explicit
-- HUNTER_RANGED_GAP (15 px) above the ranged bar. Reading GetTop/IsShown is plain frame
-- geometry (not aura-container geometry), so it is secret-safe and does not depend on a
-- hard-coded cast-bar height.
local function topmost_hunter_widget(ST)
	local ui = type(ST) == "table" and ST.hunter_ui or nil
	if type(ui) ~= "table" then
		return nil, nil
	end
	local best, best_top
	local keys = { "cast_frame", "rapid_fire_bar", "target_warning" }
	for index = 1, #keys do
		local frame = ui[keys[index]]
		if frame ~= nil and type(frame.IsShown) == "function"
			and type(frame.GetTop) == "function" then
			local shown_ok, shown = pcall(frame.IsShown, frame)
			if shown_ok and shown == true then
				local ok, top = pcall(frame.GetTop, frame)
				if ok and type(top) == "number" and (best_top == nil or top > best_top) then
					best, best_top = frame, top
				end
			end
		end
	end
	return best, best_top
end

function A.topmost_visible_bar(ST)
	if type(ST) ~= "table" or type(ST.iter_hands) ~= "function"
		or type(ST.get_bar_frame) ~= "function" then
		return nil, nil
	end
	local ok_iterator, iterator = pcall(ST.iter_hands, ST)
	if not ok_iterator or type(iterator) ~= "function" then
		return nil, nil
	end
	local best, best_top = nil, nil
	while true do
		local ok_hand, hand = pcall(iterator)
		if not ok_hand or hand == nil then
			break
		end
		local ok_frame, frame = pcall(ST.get_bar_frame, ST, hand)
		if ok_frame and frame ~= nil and frame_is_shown(frame) then
			local top = frame_top(frame)
			if top ~= nil and (best_top == nil or top > best_top) then
				best, best_top = frame, top
			end
		end
	end
	return best, best_top
end

function A.anchor(ST, force)
	if A.state.ready ~= true then
		return false
	end
	ST = ST or A.state.addon
	local db = class_db(ST)
	local enabled = A.option_enabled(db)
	local debuffs_on = A.option_debuffs(db)
	local size = A.option_size(db)
	local bar, bar_top = A.topmost_visible_bar(ST)
	local hunter_anchor, hunter_top = topmost_hunter_widget(ST)
	local hunter_anchored = hunter_top ~= nil and (bar_top == nil or hunter_top > bar_top)
	if hunter_anchored then
		bar, bar_top = hunter_anchor, hunter_top
	end
	local is_hunter = type(ST.player_class) == "string" and ST.player_class == "HUNTER"
	local base_gap
	if hunter_anchored then
		-- Visible Auto Shot cast bar / Rapid Fire / target warning: sit above it.
		base_gap = A.BAR_GAP + A.HUNTER_GAP
	elseif is_hunter then
		-- No visible cast widget: at least 15 px above the ranged bar.
		base_gap = A.HUNTER_RANGED_GAP
	else
		base_gap = A.BAR_GAP
	end

	local want_buffs = enabled and A.state.rows.buffs.container ~= nil and bar ~= nil
	local want_debuffs = enabled and debuffs_on and A.state.rows.debuffs.container ~= nil and bar ~= nil
	local ok = true
	if A.state.shown.buffs ~= want_buffs then
		ok = set_shown("buffs", want_buffs) and ok
	end
	if A.state.shown.debuffs ~= want_debuffs then
		ok = set_shown("debuffs", want_debuffs) and ok
	end
	if not bar or (not want_buffs and not want_debuffs) then
		A.state.last.bar, A.state.last.bar_top = nil, nil
		A.state.last.buff_offset, A.state.last.debuff_offset = nil, nil
		return ok
	end

	-- RESERVED BAND: never measure the debuff row (its geometry can be secret); the buff
	-- row sits above a fixed band computed from the configured icon size.
	local debuff_offset = base_gap
	local buff_offset = base_gap + (want_debuffs and (size + A.TEXT_CLEARANCE) or 0)
	local changed = force == true
		or A.state.last.bar ~= bar
		or A.state.last.bar_top ~= bar_top
		or A.state.last.buff_offset ~= buff_offset
		or A.state.last.debuff_offset ~= debuff_offset
	if not changed then
		return ok
	end
	local anchor_ok = true
	if want_debuffs then
		anchor_ok = set_row_point(A.state.rows.debuffs.container, bar, debuff_offset) and anchor_ok
	end
	if want_buffs then
		anchor_ok = set_row_point(A.state.rows.buffs.container, bar, buff_offset) and anchor_ok
	end
	if anchor_ok then
		A.state.last.bar, A.state.last.bar_top = bar, bar_top
		A.state.last.buff_offset, A.state.last.debuff_offset = buff_offset, debuff_offset
		A.state.anchor_error = nil
	else
		-- Taint rules can refuse a container SetPoint in combat; retry on the next pass.
		A.state.anchor_error = "setpoint"
	end
	return ok and anchor_ok
end

--=========================================================================================
-- Init and lifecycle
--=========================================================================================
function A.retry_create(ST)
	local now = now_seconds()
	if type(now) == "number" and type(A.state.next_retry) == "number" and now < A.state.next_retry then
		return false
	end
	local ok, result = pcall(A.init, ST or A.state.addon)
	if not ok then
		A.state.error = tostring(result)
		result = false
	end
	if result == true then
		A.state.next_retry = nil
	else
		A.state.next_retry = type(now) == "number" and (now + A.RETRY_INTERVAL) or nil
	end
	return result == true
end

function A.init(ST)
	if A.available ~= true or A.state.inert == true then
		return false
	end
	if A.state.ready == true then
		return true
	end
	if type(ST) == "table" then
		A.state.addon = ST
	end
	ST = A.state.addon
	if type(ST) ~= "table" then
		return false
	end
	-- 2026-11-09 operator: the aura icons are 5 px larger in both dimensions. A profile
	-- saved under the old 22 px default is migrated once; a later explicit size is kept.
	local size_db = class_db(ST)
	if type(size_db) == "table" and tonumber(size_db.aura_icons_size) == 22
		and size_db.aura_icons_size_27 ~= true then
		size_db.aura_icons_size = 27
		size_db.aura_icons_size_27 = true
	end
	if type(CreateFrame) ~= "function" or UIParent == nil then
		A.state.inert = true
		A.state.error = "environment"
		return false
	end

	if A.state.lists == nil then
		local class = plain_upper(ST.player_class)
		-- Fail closed: the row is per-class. A class with no list is never shown another
		-- class's auras and never leaves an empty frame behind - the module is inert for
		-- it, even though the shared ids alone would be technically valid.
		if class == nil or (A.BUFFS[class] == nil and A.DEBUFFS[class] == nil) then
			A.state.no_class_list = true
			return false
		end
		local race_token, race_localized = A.player_race_tokens()
		A.state.class = class
		A.state.lists = {
			buffs = A.build_buff_list(class, race_token, race_localized),
			debuffs = A.build_debuff_list(class),
		}
	end
	if #A.state.lists.buffs == 0 and #A.state.lists.debuffs == 0 then
		A.state.no_class_list = true
		return false
	end

	-- The plain driver comes first: it is the only frame that may exist during combat
	-- lockdown, and it is what retries the native containers once combat ends.
	if ensure_driver() == nil then
		A.state.error = "driver"
		return false
	end
	if in_combat() then
		-- Native aura containers are never created in combat lockdown. The driver's
		-- throttled pass retries; PLAYER_ENTERING_WORLD retries too.
		A.state.deferred = "combat"
		return false
	end
	A.state.deferred = nil
	A.state.attempts = A.state.attempts + 1

	local buff_ok, buff_created, buff_fatal = build_row(ST, "buffs")
	if buff_fatal then
		return false
	end
	local debuff_ok, debuff_created, debuff_fatal = build_row(ST, "debuffs")
	if debuff_fatal then
		return false
	end
	if not buff_ok and not debuff_ok then
		A.state.error = A.state.error or "row"
		return false
	end

	-- A row created in this attempt already received the current layout through
	-- AddAuraGroup; forcing one explicit push afterwards keeps a container that survived
	-- an earlier failed attempt in sync with the current settings.
	if buff_created or debuff_created then
		A.state.layout = nil
	end
	A.state.ready = true
	A.state.error = nil
	sync_layout(ST)
	A.anchor(ST, true)
	return true
end

function A.maintain(ST)
	ST = ST or A.state.addon
	if A.available ~= true or A.state.inert == true then
		return
	end
	if A.state.ready ~= true then
		A.retry_create(ST)
		return
	end
	sync_layout(ST)
	A.anchor(ST, false)
end

function A.apply_settings(ST)
	if A.available ~= true or A.state.inert == true then
		return false
	end
	ST = ST or A.state.addon
	if type(ST) ~= "table" or A.state.ready ~= true then
		return false
	end
	sync_layout(ST)
	A.anchor(ST, true)
	return true
end

function A.on_update(elapsed)
	if A.available ~= true or A.state.inert == true then
		return
	end
	local delta = tonumber(elapsed) or 0
	if is_secret(delta) then
		delta = 0
	end
	if delta <= 0 then
		A.state.elapsed = 0
	else
		A.state.elapsed = A.state.elapsed + delta
		if A.state.elapsed < A.MAINTAIN_INTERVAL then
			return
		end
		A.state.elapsed = 0
	end
	local ok, err = pcall(A.maintain, A.state.addon)
	if not ok then
		A.state.failures = (A.state.failures or 0) + 1
		A.state.last_error = tostring(err)
		if A.state.failures == 1 then
			announce("The aura icon row update failed and was isolated: " .. tostring(err))
		end
	end
end

function A.on_event(event)
	if event ~= "PLAYER_ENTERING_WORLD" then
		return
	end
	if A.available ~= true or A.state.inert == true then
		return
	end
	A.state.elapsed = 0
	if A.state.ready == true then
		-- World entry / UI scale / resolution: force a fresh anchor.
		A.anchor(A.state.addon, true)
	else
		pcall(A.init, A.state.addon)
	end
end

--=========================================================================================
-- Diagnostics (a later /st diag lane can print these; nothing here is required to render)
--=========================================================================================
function A.aura_data_secret()
	local secrets = rawget(_G, "C_Secrets")
	if type(secrets) ~= "table" or type(secrets.ShouldAurasBeSecret) ~= "function" then
		return nil
	end
	local ok, secret = pcall(secrets.ShouldAurasBeSecret)
	if not ok then
		return true
	end
	return secret == true
end

function A.diagnostics()
	local ST = A.state.addon
	local db = class_db(ST)
	return {
		available = A.available == true,
		ready = A.state.ready == true,
		buff = A.state.rows.buffs.container ~= nil,
		debuff = A.state.rows.debuffs.container ~= nil,
		buff_built = A.state.rows.buffs.built == true,
		debuff_built = A.state.rows.debuffs.built == true,
		buff_shown = A.state.shown.buffs == true,
		debuff_shown = A.state.shown.debuffs == true,
		bar = A.state.last.bar ~= nil,
		attempts = A.state.attempts or 0,
		error = A.state.error,
		deferred = A.state.deferred,
		anchor_error = A.state.anchor_error,
		layout_error = A.state.layout_error,
		aura_secret = A.aura_data_secret(),
		size = A.option_size(db),
		spacing = A.option_spacing(db),
		grow = A.option_grow(db),
	}
end

if st.debug then st.utils.print_msg('-- Parsed aura_icons.lua correctly') end

--=========================================================================================
-- Module for Shaman-specific behaviours: the Enhancement spell-weaving assist ("LB
-- weaving"), ported from the read-only reference SuperSwingTimer-WoW/
-- SuperSwingTimer_Weaving.lua (spell-catalog resolution, cast tracking, marker/spark
-- display), plus the reference's Enhancement trackers
-- (SuperSwingTimer_ClassMods.lua shaman block 3334-4513): the above/below-bar breakpoint
-- markers and offhand spark mirror, the Windfury Weapon ICD strip, the Flame Shock target
-- bar, the Stormstrike / Shamanistic Rage badges and the shield charge row. All
-- swing-relative math is frozen in weave.lua; this module only gathers the live inputs
-- (haste, Maelstrom Weapon, auras, cooldowns, cast events) and drives the visuals.
--
-- The assist draws on the mainhand visuals frame:
--   vf.weave_marker        : the resolved spell's icon at the latest safe cast start.
--   vf.weave_marker_top    : the same icon above the bar (reference 3491-3497).
--   vf.weave_marker_bottom : the same icon below the bar stack (reference 3499-3506).
--   vf.weave_spark         : the active cast, tinted red when the cast will clip.
--   vf.weave_spark_offhand : the offhand mirror of the spark (dual wield; reference
--                            3481-3489), created on the offhand visuals frame.
-- plus the tracker widgets: windfury strip, flame shock bar, cooldown badges and the
-- shield charge rects.
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
-- Cross-client API wrappers (see compat.lua).
local api = st.api
local LSM = LibStub("LibSharedMedia-3.0")

--=========================================================================================
-- Data
--=========================================================================================
-- Maelstrom Weapon: 20% cast-time reduction per stack, instant at 5. 408505 is the SoD
-- aura, 53817 the Wrath-era one; the name fallback covers everything else.
local WEAVE_MW_SPELL_IDS = { [408505] = true, [53817] = true }
local WEAVE_MW_NAME = "Maelstrom Weapon"

-- Buff haste sources, checked when the spell-haste API reports nothing (Classic). The
-- reference maxes these against the API value, never multiplies it.
local WEAVE_BLOODLUST_IDS = { [2825] = true, [32182] = true }  -- Bloodlust / Heroism
local WEAVE_BERSERKING_IDS = { [20554] = true, [26285] = true, [26284] = true }

-- Rage of the Farseer (Forever Enhancement personal Bloodlust - UNCONFIRMED,
-- docs/research/forever_beta.md; no spell id published, so name-only match): feeds
-- the Bloodlust leg of the buff-haste multiplier (personal lust reads as 30%,
-- mirroring Bloodlust - the VALUE is assumed, see the multiplier site below).
-- Confirm in-game (spell id, haste value, aura name). Never
-- present off Forever, so every other family reads byte-identical.
local WEAVE_FARSEER_NAME = "Rage of the Farseer"

-- Unresolved families are retried at most this often: a level-up can teach a family after
-- the first attempt, and the throttled retry keeps the per-frame path cheap.
local WEAVE_CATALOG_RETRY_S = 5

-- Marker alpha multiplier while the cast would overrun the swing (0.65, like the
-- reference's unsafe color).
local WEAVE_UNSAFE_ALPHA = 0.65

-- Visual fallbacks for malformed or pre-options profiles.
local WEAVE_FALLBACK_MARKER_SIZE = 6
local WEAVE_FALLBACK_MARKER_ALPHA = 1
local WEAVE_FALLBACK_SPARK_WIDTH = 3
local WEAVE_FALLBACK_SPARK_HEIGHT = 15
local WEAVE_FALLBACK_SPARK_ALPHA = 0.95

-- Spark colors: red while the cast clips the swing, otherwise the shaman class blue.
local WEAVE_RED_COLOR = { 1, 0.15, 0.15 }
local weave_shaman_blue = nil
local function get_shaman_spark_color()
	if weave_shaman_blue == nil then
		local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS["SHAMAN"]
		if c and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
			weave_shaman_blue = { c.r, c.g, c.b }
		else
			-- Fallback: the shaman class color on every family that has defined it.
			weave_shaman_blue = { 0, 0.44, 0.87 }
		end
	end
	return weave_shaman_blue
end

--=========================================================================================
-- Tracker data (reference SuperSwingTimer_ClassMods.lua shaman block 3334-4513)
--=========================================================================================
-- Windfury Weapon buff (ICD strip: 3766-3848). The proc buff is accepted too, mirroring
-- the reference's WINDFURY_BUFF_NAMES / WINDFURY_BUFF_SPELL_IDS pair (3751-3765).
-- TBC MICRO (docs/research/tbc_minmax.md): the 3 s ICD caps output at 20 procs/min
-- (st.weave.WINDFURY_MAX_PROCS_PER_MINUTE) and is shared across hands; double WF
-- wants the slowest weapons in BOTH hands. DOWNRANK NOTE: twist with WF rank 1 for
-- mana sustain (max rank ooms in 1-2 min of twisting); ranks resolve by id table
-- plus the name fallback below, so unconfirmed ranks still light the strip.
local WEAVE_WINDFURY_IDS = {
	[8232] = true, [8233] = true, [8234] = true, [8235] = true,
	[16316] = true, [16317] = true, [25585] = true, [33757] = true,
}
local WEAVE_WINDFURY_NAMES = { ["Windfury Weapon"] = true, ["Windfury"] = true }

-- Stormstrike / Shamanistic Rage cooldown badges (3695-3748; ids from
-- SuperSwingTimer_Constants.lua:193-196).
local WEAVE_STORMSTRIKE_SPELL_ID = 17364
local WEAVE_SR_SPELL_ID = 30823
local WEAVE_SR_NAME = "Shamanistic Rage"

-- Rockbiter Weapon imbue badge (discover #6; reference
-- SuperSwingTimer_ClassMods.lua:4217 tracks it as a buff icon with rank-1 id
-- 8017). Ranks above 1 match by the English name only: their ids are UNCONFIRMED
-- and never guessed (the WF-rank convention above). Guarded reads only - a nil
-- or unconfirmed id can never light the badge.
local WEAVE_ROCKBITER_IDS = {
	[8017] = true,
}
local WEAVE_ROCKBITER_NAME = "Rockbiter Weapon"

-- Flurry (16280; reference SuperSwingTimer_ClassMods.lua:4221) - the melee proc
-- buff whose 0.5 s ICD drives the DW sync warning (round 2). The aura count is
-- the remaining charges; a count INCREASE is a fresh proc (stamped in
-- on_aura_change). Ids above the reference's are matched by name only.
local WEAVE_FLURRY_IDS = {
	[16280] = true,
}
local WEAVE_FLURRY_NAME = "Flurry"

-- Next Action Guide shock/totem slots (TBC Enhancement): Fire Nova Totem rank 1 is
-- 1535 (classicdb-confirmed rank 1; TBC top rank 25547) with a 15 s cooldown; Earth
-- Shock rank 1 is 8042 (instant, no cooldown); the twist slot shows Windfury Totem
-- 8512, whose id is UNCONFIRMED on 2.5.6 and needs in-game confirmation (the twist
-- rule is a skeleton until a compat totem read lands - see weave.lua).
local WEAVE_FIRE_NOVA_SPELL_ID = 1535
local WEAVE_FIRE_NOVA_COOLDOWN_SECONDS = 15
local WEAVE_EARTH_SHOCK_SPELL_ID = 8042
local WEAVE_WINDFURY_TOTEM_SPELL_ID = 8512

-- Totem-twist drops (TBC Enhancement): the air slot alternates Windfury Totem <->
-- Grace of Air Totem roughly every st.weave.TOTEM_TWIST_PERIOD_SECONDS seconds. The
-- air slot is 4 (FrameXML: FIRE 1, EARTH 2, WATER 3, AIR 4). The id table ships only
-- the pre-existing Windfury rank-1 id above (still UNCONFIRMED on 2.5.6); every
-- other rank of either totem matches by English name (the SUCCEEDED hook also
-- resolves the cast's spell id through GetSpellInfo, so unconfirmed ranks stamp by
-- name) until the GoA + higher-WF rank ids are confirmed in-game - plug-in point:
-- add the confirmed rank ids to WEAVE_TWIST_TOTEM_IDS.
-- FOREVER: no twisting there (party-buff totem model - totems dropped 4-at-once via
-- Call of the Elements coexist with the Windfury Weapon imbue; docs/research/
-- forever_beta.md). The gather feeds the stamp through st.weave.
-- is_totem_twist_family, which reads false on FOREVER, so no weapon-enchant twist
-- prompt can ever fire there.
local WEAVE_TOTEM_AIR_SLOT = 4
local WEAVE_TWIST_TOTEM_IDS = {
	[WEAVE_WINDFURY_TOTEM_SPELL_ID] = true,
}
local WEAVE_TWIST_TOTEM_NAMES = { ["Windfury Totem"] = true, ["Grace of Air Totem"] = true }

-- Wrath Enhancement top-parse slots (docs/research/rotations_wrath.md): Feral Spirit
-- 51533 (repo-verified via LibClassicSwingTimerAPI); Fire Elemental Totem rank 1
-- 2894 UNCONFIRMED; Magma Totem matched by English name (rank-1 id 8190
-- UNCONFIRMED lives in the id table below); Lava Lash 60103 UNCONFIRMED. The
-- cooldown slots are known-gated (IsSpellKnown false -> the gather feeds nil ->
-- the engine never prompts), so a wrong id stays silent rather than prompting
-- wrong. Cooldown fallbacks are best-recall WotLK values, also UNCONFIRMED; the
-- client-reported length rides whenever a real cooldown runs. Lava Lash carries
-- no fallback (its cooldown is unconfirmed): the swipe falls back to the
-- remaining time itself. Confirm all four in-game (ids, Feral/Fire-Ele/Lava-Lash
-- cooldowns, Magma duration + the empty-fire-slot shape).
local WEAVE_FERAL_SPIRIT_SPELL_ID = 51533
local WEAVE_FERAL_SPIRIT_COOLDOWN_SECONDS = 180
local WEAVE_FIRE_ELEMENTAL_SPELL_ID = 2894
local WEAVE_FIRE_ELEMENTAL_COOLDOWN_SECONDS = 600
local WEAVE_MAGMA_TOTEM_SPELL_ID = 8190
local WEAVE_MAGMA_TOTEM_NAME = "Magma Totem"
local WEAVE_MAGMA_SWIPE_SECONDS = 20
local WEAVE_LAVA_LASH_SPELL_ID = 60103
local WEAVE_TOTEM_FIRE_SLOT = 1
local WEAVE_MAGMA_TOTEM_IDS = {
	[WEAVE_MAGMA_TOTEM_SPELL_ID] = true,
}
local WEAVE_MAGMA_TOTEM_NAMES = { [WEAVE_MAGMA_TOTEM_NAME] = true }

-- Flame Shock rank ids (target bar: 3850-4056; SuperSwingTimer_Constants.lua:197-206).
-- The name fallback covers ranks the id table does not list.
local WEAVE_FLAME_SHOCK_IDS = {
	[8050] = true, [8052] = true, [8053] = true, [10447] = true,
	[10448] = true, [29228] = true, [25457] = true,
}
local WEAVE_FLAME_SHOCK_NAME = "Flame Shock"
-- Target-aura scan cadence: the reference throttles at 0.05 s (3993-3996).
local WEAVE_FLAME_SHOCK_SCAN_INTERVAL = 0.05
-- Rank-1 Flame Shock id, for rank-agnostic cooldown reads (the shock cooldown is
-- shared with Earth Shock; the S4 FS-collision guard reads it by localized name).
local WEAVE_FLAME_SHOCK_BASE_SPELL_ID = 8050

-- Stormstrike nature-vulnerability debuff (S2 target bar): 17364 CONFIRMED
-- (12 s, +20% nature damage taken - bench/verify_bank.md §2, Wowhead TBC
-- spell=17364); the ability trigger id 32175 noted there is accepted defensively
-- (its aura-id role is UNCONFIRMED). The name fallback covers ranks the id table
-- does not list; reads stay guarded (id lookups and name compares are nil-safe).
local WEAVE_STORMSTRIKE_DEBUFF_IDS = {
	[17364] = true,
	[32175] = true,
}
local WEAVE_STORMSTRIKE_DEBUFF_NAME = "Stormstrike"

-- Lightning / Water Shield (charge row: 4058-4209; SuperSwingTimer_Constants.lua:208-258).
local WEAVE_LIGHTNING_SHIELD_IDS = {
	[324] = true, [325] = true, [905] = true, [945] = true, [8134] = true,
	[10431] = true, [10432] = true, [25469] = true, [25472] = true,
}
local WEAVE_LIGHTNING_SHIELD_NAMES = { ["Lightning Shield"] = true }
local WEAVE_WATER_SHIELD_IDS = {
	[52127] = true, [52129] = true, [52131] = true, [24398] = true,
	[33736] = true, [33737] = true, [34827] = true, [57960] = true,
}
local WEAVE_WATER_SHIELD_NAMES = { ["Water Shield"] = true, ["Mana Shield"] = true }

-- Tracker visual constants (parenthesised line references are the reference's).
local WEAVE_MARKER_GAP = 2                              -- triangleGap default (3439)
local WEAVE_WINDFURY_STRIP_WIDTH = 3                    -- wfIcdBar width (3811)
local WEAVE_WINDFURY_COLORS = {                         -- statusbar buckets (3840-3846)
	red = { 1, 0, 0, 0.85 },
	orange = { 1, 0.65, 0, 0.85 },
	green = { 0, 1, 0, 0.85 },
}
local WEAVE_WINDFURY_BG_COLOR = { 0, 0, 0, 0.5 }        -- ICD background (3819)
local WEAVE_FLAME_SHOCK_BAR_HEIGHT = 6                  -- FLAME_SHOCK_BAR_HEIGHT (3850)
local WEAVE_FLAME_SHOCK_COLOR = { 1.0, 0.35, 0.10, 0.90 }      -- fill (3895)
local WEAVE_FLAME_SHOCK_BG_COLOR = { 0, 0, 0, 0.45 }           -- backing (3905)
local WEAVE_FLAME_SHOCK_GLOW_COLOR = { 1.0, 0.45, 0.08, 0.85 } -- glow edge (3915)
local WEAVE_FLAME_SHOCK_LABEL_COLOR = { 1.0, 0.85, 0.25, 0.95 } -- label (3957)
local WEAVE_SS_BADGE_COLOR = { 0.25, 0.85, 1.0, 0.95 }  -- Stormstrike badge (3706)
local WEAVE_SR_BADGE_COLOR = { 0.15, 0.85, 1.0, 0.95 }  -- Shamanistic Rage badge (3730)
-- WF-fishing hold (S3): the SS badge flips amber and the bar's final fraction gets
-- an amber wash while Stormstrike is held for the Windfury proc.
local WEAVE_SS_HOLD_COLOR = { 1.0, 0.72, 0.15, 0.95 }
local WEAVE_WF_HOLD_WASH_COLOR = { 1.0, 0.72, 0.15, 0.18 }
-- Rockbiter Weapon badge (discover #6): stone-brown so it reads apart from the
-- SS/SR blues and the amber hold tint.
local WEAVE_RB_BADGE_COLOR = { 0.85, 0.62, 0.30, 0.95 }
-- Stormstrike debuff target bar (S2): FS-bar clone styling, nature-teal.
local WEAVE_STORMSTRIKE_BAR_HEIGHT = 6
local WEAVE_STORMSTRIKE_COLOR = { 0.30, 0.80, 0.95, 0.90 }
local WEAVE_STORMSTRIKE_BG_COLOR = { 0, 0, 0, 0.45 }
local WEAVE_STORMSTRIKE_GLOW_COLOR = { 0.40, 0.88, 1.0, 0.85 }
local WEAVE_STORMSTRIKE_LABEL_COLOR = { 0.75, 0.95, 1.0, 0.95 }
local WEAVE_SHIELD_RECT_WIDTH = 5                       -- LIGHTNING_SHIELD_RECT_WIDTH (3512)
local WEAVE_SHIELD_RECT_GAP = 1                         -- LIGHTNING_SHIELD_RECT_GAP (3513)
local WEAVE_SHIELD_BAR_GAP = 6                          -- tracker gap default (3515)
local WEAVE_SHIELD_DIM_ALPHA = 0.20                     -- empty-slot alpha (4177)
local WEAVE_SHIELD_COLORS = {                           -- (4058, 4151-4155)
	lightning = { 0.25, 0.72, 1.0, 0.90 },
	water = { 0.50, 0.80, 1.0, 0.90 },
}
-- One rect per possible shield charge slot: Lightning Shield can reach 4, Water Shield 3
-- (mirrors weave.SHIELD_MAX_CHARGES; created once, the row shows `slots` of them).
local WEAVE_SHIELD_MAX_SLOTS = 4

-- Spell-position row (round 2, operator spec): the zone band + per-spell icons live
-- in a strip above the bar, clear of the Flame Shock (+2..8) and Stormstrike
-- (+10..16) bars; each icon sits at its spell's latest safe cast start and the
-- zone spans the min..max of those starts. All geometry is constant here so the
-- follow-up pass can refine the layout without touching the logic.
local WEAVE_POSITION_SLOTS = { "LB", "CL" }
local WEAVE_POSITION_LAVA_KEY = "LvB"
local WEAVE_ZONE_LABEL = "Spells start cast range zone"
local WEAVE_ZONE_BOTTOM = 18
local WEAVE_ZONE_HEIGHT = 14
local WEAVE_ZONE_LABEL_GAP = 2
local WEAVE_ZONE_COLOR = { 0.45, 0.75, 1.0, 0.12 }
local WEAVE_ZONE_LABEL_COLOR = { 0.75, 0.90, 1.0, 0.90 }
local WEAVE_POSITION_ICON_SIZE = 14
local WEAVE_POSITION_READY_ALPHA = 0.95
local WEAVE_POSITION_CLIP_COLOR = { 1.0, 0.15, 0.15, 0.95 }
local WEAVE_POSITION_WAIT_COLOR = { 0.6, 0.6, 0.6, 0.35 }

-- DW / Flurry badges (round 2): sync + Flurry stacks/ICD, stacked under the
-- Rockbiter badge on the mainhand column.
local WEAVE_SYNC_COLOR = { 0.30, 1.0, 0.40, 0.95 }
local WEAVE_DESYNC_COLOR = { 1.0, 0.72, 0.15, 0.95 }
local WEAVE_FLURRY_COLOR = { 0.65, 0.85, 1.0, 0.95 }

-- Badge/label font: the bar's configured font, with the client standard font as the
-- fallback for sandboxes and stripped clients.
local function get_tracker_font_path(self)
	local db_hand = self.get_hand_table and self:get_hand_table("mainhand")
	if LSM and LSM.Fetch and db_hand and db_hand.text_font then
		local path = LSM:Fetch("font", db_hand.text_font)
		if path then return path end
	end
	return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

--=========================================================================================
-- Spell catalogue
--=========================================================================================
-- Resolve a family's highest known rank (ids run low -> high; walk backwards) that has a
-- positive cast time. Returns {spell_id, name, icon, cast_seconds} or nil. compat's
-- GetSpellInfo normalizes castTime to milliseconds on every family (classic global and
-- C_Spell.SpellInfo.castTime agree), so the 4th return is used directly.
local function resolve_family_spell(group)
	for i = #group.ids, 1, -1 do
		local spell_id = group.ids[i]
		if api.is_spell_known(spell_id) then
			local name, _, icon, cast_ms = api.GetSpellInfo(spell_id)
			if name and type(cast_ms) == "number" and cast_ms > 0 then
				return {
					spell_id = spell_id,
					name = name,
					icon = icon,
					cast_seconds = cast_ms / 1000,
				}
			end
		end
	end
	return nil
end

-- Resolve every family still missing a spell. Families that resolve to nothing are
-- retried at most once per WEAVE_CATALOG_RETRY_S. CATALOGUE-RETRY OBSERVABILITY
-- (H4 follow-up): a sustained miss stays hidden-with-retry by design - after the
-- H4 split, an unresolved cast time is UNKNOWN and every weave widget hides/dims
-- instead of rendering an instant-0 marker, so the safe direction is silence plus
-- the throttled retry below. No chat/diag notice is added: a low-level character
-- whose spell book cannot answer yet would trip it on every login.
function ST.SHAMAN.resolve_weave_catalog(self)
	local now = api.get_time()
	for i = 1, #st.weave.SPELL_GROUPS do
		local group = st.weave.SPELL_GROUPS[i]
		local family = group.abbrev
		if not self.weave_catalog[family] and now >= (self.weave_catalog_retry_at[family] or 0) then
			local entry = resolve_family_spell(group)
			if entry then
				self.weave_catalog[family] = entry
			else
				self.weave_catalog_retry_at[family] = now + WEAVE_CATALOG_RETRY_S
			end
		end
	end
end

-- Drop every resolved entry so the next resolution pass re-reads the spellbook.
-- resolve_weave_catalog only fills MISSING families, so a rank learned after post_init
-- (level-up, respec, retrain) would otherwise keep the old rank's cast time and icon
-- for the rest of the session. The throttled retry stamps go too: a family that failed
-- to resolve must be retried immediately rather than after the throttle window.
function ST.SHAMAN.on_talents_changed(self)
	if not self.weave_catalog then
		return
	end
	for family in pairs(self.weave_catalog) do
		self.weave_catalog[family] = nil
	end
	if self.weave_catalog_retry_at then
		for family in pairs(self.weave_catalog_retry_at) do
			self.weave_catalog_retry_at[family] = nil
		end
	end
	-- The Lava Burst spender cache (S4) is talent/rune state too: drop it so the
	-- next resolution pass re-reads the spellbook (a rune engraved mid-session
	-- flips the MW5 choice without a reload).
	self.weave_lava_burst = nil
	self.weave_lava_burst_retry_at = nil
end

-- Resolve the Lava Burst (SoD rune) catalogue entry for the MW5 spender choice:
-- name query -> id -> icon and cast time, cached like the weave catalogue (the id
-- is never guessed - a client without the spell data leaves the cache empty and
-- retries are throttled). The player-level rune/talent gate is applied by the
-- caller through st.weave.get_mw5_spender (the SoD rune teaches the spell; an
-- Era-base character without the rune fails it even though the client's spell
-- data can resolve the name), so the choice follows the rune live.
function ST.SHAMAN.resolve_lava_burst(self)
	if st.family ~= "ERA" then
		return nil
	end
	local entry = self.weave_lava_burst
	if entry == nil then
		local now = api.get_time()
		if now < (self.weave_lava_burst_retry_at or 0) then
			return nil
		end
		local name, _, icon, cast_ms, _, _, lava_id = api.GetSpellInfo("Lava Burst")
		if type(lava_id) == "number" and name then
			entry = {
				spell_id = lava_id,
				name = name,
				icon = icon,
				cast_seconds = (type(cast_ms) == "number" and cast_ms or 0) / 1000,
			}
			self.weave_lava_burst = entry
		else
			self.weave_lava_burst_retry_at = now + WEAVE_CATALOG_RETRY_S
			return nil
		end
	end
	return entry
end

-- Look up a family by a numeric spell id or a localized spell-name token.
local function lookup_weave_family(self, token)
	if token == nil or not self.weave_catalog then
		return nil
	end
	for i = 1, #st.weave.FAMILIES do
		local family = st.weave.FAMILIES[i]
		local entry = self.weave_catalog[family]
		if entry and (entry.spell_id == token or entry.name == token) then
			return family
		end
	end
	return nil
end

--=========================================================================================
-- Live inputs: haste and Maelstrom Weapon
--=========================================================================================
-- Spell-haste percentage: UnitSpellHaste where present, then the older GetSpellHaste,
-- then 0. The compat wrappers return nil on clients that lack the function.
local function get_spell_haste_percent()
	local haste = api.UnitSpellHaste("player")
	if type(haste) == "number" then
		return haste
	end
	haste = api.GetSpellHaste()
	if type(haste) == "number" then
		return haste
	end
	return 0
end

-- One walk of the player's auras for the weave inputs AND the tracker state: the
-- Maelstrom Weapon stack count, the buff haste multiplier, whether Windfury Weapon is
-- active (ICD strip), Shamanistic Rage's expiry (SR badge), whether Rockbiter Weapon is
-- active and its expiry (RB badge), the Flurry stack count (DW/Flurry badge) and the
-- active shield's type and charge count (charge row). An aura without a count still
-- means one Maelstrom stack (the reference's max(1, count) handling). The walk stops
-- once every lookup is resolved, so the early exits survive while costing at most one
-- walk per aura change. The result is handed back in a reused module-local table (no
-- per-frame allocation); read it before the next call.
local weave_aura_scan = {
	stacks = 0, buff_multiplier = 1, windfury = false,
	sr_expires = nil, rockbiter = false, rockbiter_expires = nil,
	flurry = nil, shield_type = nil, shield_charges = nil,
}
local function scan_weave_auras()
	local stacks, mw_found = 0, false
	local bloodlust, berserking = false, false
	local windfury, sr_found, sr_expires = false, false, nil
	local rockbiter, rockbiter_expires = false, nil
	local flurry_count = nil
	local shield_type, shield_charges = nil, nil
	local i = 1
	while i <= 40 do
		local name, _, count, _, _, expiration, _, _, _, spell_id = api.UnitAura("player", i, "HELPFUL")
		-- No early break (R2): nil is simply no match at this index.
		if name ~= nil then
			if not mw_found
				and ((spell_id and WEAVE_MW_SPELL_IDS[spell_id]) or name == WEAVE_MW_NAME) then
				local n = tonumber(count) or 1
				if n > st.weave.MW_MAX_STACKS then
					n = st.weave.MW_MAX_STACKS
				elseif n < 1 then
					n = 1
				end
				stacks = n
				mw_found = true
			end
			if not bloodlust and ((spell_id and WEAVE_BLOODLUST_IDS[spell_id]) or name == "Bloodlust" or name == "Heroism"
				-- Rage of the Farseer (UNCONFIRMED, name-only: no spell id published,
				-- so the literal name IS the probe - the only one Forever exposes).
				or name == WEAVE_FARSEER_NAME) then
				bloodlust = true
			end
			if not berserking and ((spell_id and WEAVE_BERSERKING_IDS[spell_id]) or name == "Berserking") then
				berserking = true
			end
			if not windfury
				and ((spell_id and WEAVE_WINDFURY_IDS[spell_id]) or WEAVE_WINDFURY_NAMES[name]) then
				windfury = true
			end
			if not sr_found and ((spell_id and spell_id == WEAVE_SR_SPELL_ID) or name == WEAVE_SR_NAME) then
				sr_found = true
				if type(expiration) == "number" and expiration > 0 then
					sr_expires = expiration
				end
			end
			if not rockbiter
				and ((spell_id and WEAVE_ROCKBITER_IDS[spell_id]) or name == WEAVE_ROCKBITER_NAME) then
				rockbiter = true
				if type(expiration) == "number" and expiration > 0 then
					rockbiter_expires = expiration
				end
			end
			if flurry_count == nil
				and ((spell_id and WEAVE_FLURRY_IDS[spell_id]) or name == WEAVE_FLURRY_NAME) then
				local n = tonumber(count) or 1
				if n < 1 then n = 1 end
				flurry_count = n
			end
			if not shield_type then
				if (spell_id and WEAVE_LIGHTNING_SHIELD_IDS[spell_id])
					or WEAVE_LIGHTNING_SHIELD_NAMES[name] then
					shield_type = "lightning"
					shield_charges = tonumber(count)
				elseif (spell_id and WEAVE_WATER_SHIELD_IDS[spell_id])
					or WEAVE_WATER_SHIELD_NAMES[name] then
					shield_type = "water"
					shield_charges = tonumber(count)
				end
			end
			if mw_found and bloodlust and berserking and windfury and sr_found
				and rockbiter and flurry_count and shield_type then
				break
			end
		end
		i = i + 1
	end
	local mult = 1
	-- UNCONFIRMED on Forever: the Farseer leg above borrows Bloodlust's 30%
	-- (no haste value published for Rage of the Farseer - the beta guides name
	-- the spell only). The leg itself is never guessed (the aura must actually
	-- be present), but the 1.30 factor is assumed from Bloodlust parity until
	-- the value is confirmed in-game.
	if bloodlust then mult = mult * 1.30 end
	if berserking then mult = mult * 1.10 end
	weave_aura_scan.stacks = stacks
	weave_aura_scan.buff_multiplier = mult
	weave_aura_scan.windfury = windfury
	weave_aura_scan.sr_expires = sr_expires
	weave_aura_scan.rockbiter = rockbiter
	weave_aura_scan.rockbiter_expires = rockbiter_expires
	weave_aura_scan.flurry = flurry_count
	weave_aura_scan.shield_type = shield_type
	weave_aura_scan.shield_charges = shield_charges
	return weave_aura_scan
end

-- Buff haste multiplier: Bloodlust/Heroism (x1.30) and Berserking (x1.10) compound; the
-- caller then maxes the result against the spell-haste value (never multiplies it).
-- buff_multiplier is a value a merged scan already collected; nil walks the auras on
-- its own, so the refresh hooks stay usable standalone.
local function get_buff_haste_multiplier(buff_multiplier)
	if buff_multiplier == nil then
		buff_multiplier = scan_weave_auras().buff_multiplier
	end
	return buff_multiplier
end

-- Refresh the spell-haste multiplier (cast starts and aura changes). The optional
-- buff_multiplier is the value a merged scan already collected.
function ST.SHAMAN.refresh_weave_haste(self, buff_multiplier)
	self.weave_haste_mult = st.weave.get_max_haste_multiplier(
		get_spell_haste_percent(), get_buff_haste_multiplier(buff_multiplier))
end

-- Refresh the Maelstrom Weapon stack count (aura changes). The optional stacks value
-- comes from a merged scan; nil performs its own walk, so the hook stays usable
-- standalone with identical results. Any positive count latches weave_mw_observed
-- for the session (SoD shares the ERA token but HAS the MW rune: the first actually
-- observed aura/stack signal is what re-enables the markers and the MW guide rules
-- there; Era-base never observes it and stays off). The latch never clears: a
-- dropped aura means zero stacks, not a client without Maelstrom.
function ST.SHAMAN.refresh_weave_mw_stacks(self, stacks)
	if stacks == nil then
		stacks = scan_weave_auras().stacks
	end
	self.weave_mw_stacks = stacks
	if type(stacks) == "number" and stacks > 0 then
		self.weave_mw_observed = true
	end
end

-- Effective Maelstrom gate: the shipped weave_mw_enabled default is unconditionally
-- true (nothing sets it per client), so the family token supplies the per-client
-- default via st.weave.has_maelstrom_weapon - TBC never has Maelstrom Weapon, ERA
-- needs the aura-observed latch (SoD HAS the 408505 rune; Era-base never observes
-- it and stays off; Forever keeps the unconditional read - bars_state pins its
-- marker, MW at 60 UNCONFIRMED) - while the option remains the user kill-switch
-- everywhere.
-- RESIDUAL SoD specifics: the Lava Burst vs Lightning Bolt 5-stack choice is
-- surfaced by re-pointing the weave slot at Lava Burst when the rune is known
-- (resolve_guide_icons); the engine keeps prompting the generic weave slot at 5
-- stacks only (MW5-only, like Wrath). Rolling Thunder stack-gen is not modelled -
-- FS/ES already alternate (guide rules 5 and 12). The Stormstrike-debuff read for
-- the spender choice needs a target-debuff tracker plus in-game confirmation.
local function is_weave_mw_active(db, mw_observed)
	if db and db.weave_mw_enabled == false then
		return false
	end
	return st.weave.has_maelstrom_weapon(st.family, mw_observed)
end

-- Effective cast time (seconds) for a resolved spell entry, with the current haste and
-- (unless disabled in the options, or absent on this client family) the Maelstrom
-- Weapon reduction.
function ST.SHAMAN.get_weave_effective_cast_time(self, entry)
	local mw_mult = 1
	if is_weave_mw_active(self:get_class_table(), self.weave_mw_observed) then
		mw_mult = st.weave.get_maelstrom_multiplier(self.weave_mw_stacks)
	end
	return st.weave.get_effective_cast_time(entry.cast_seconds, self.weave_haste_mult, mw_mult, false)
end

--=========================================================================================
-- Cast tracking
--=========================================================================================
-- The player's live cast/channel window. UnitCastingInfo and UnitChannelInfo do NOT share
-- a return shape: casting returns castID before notInterruptible and the spell id 9th,
-- channeling has no castID and the spell id 8th (verified against the generated client
-- documentation on every family branch). Returns name, spell_id, start-time and
-- end-time seconds (ms/1000 keeps the GetTime() domain for DELAYED re-anchoring).
local function get_live_player_cast()
	local name, _, _, start_ms, end_ms, _, _, _, spell_id = api.UnitCastingInfo("player")
	if type(start_ms) ~= "number" or type(end_ms) ~= "number" or end_ms <= start_ms then
		name, _, _, start_ms, end_ms, _, _, spell_id = api.UnitChannelInfo("player")
	end
	if type(start_ms) ~= "number" or type(end_ms) ~= "number" or end_ms <= start_ms then
		return nil, nil, nil, nil
	end
	return name, spell_id, start_ms / 1000, end_ms / 1000
end

-- Record the start (or delay) of a tracked cast. The client's live start/end window wins
-- over the computed effective cast time; a DELAYED event refreshes the end without moving
-- our start stamp, so the spark keeps travelling smoothly. keep_swing_anchor re-anchors
-- the timing of a cast already in flight (DELAYED) without re-measuring the swing the
-- cast began in - see the swing-anchor note below.
local function begin_weave_cast(self, family, live_start, live_end, keep_swing_anchor)
	local entry = self.weave_catalog[family]
	if not entry then
		return
	end
	self.SHAMAN.refresh_weave_haste(self)
	local now = api.get_time()
	local start_time = now
	local end_time
	if type(live_start) == "number" and type(live_end) == "number" and live_end > live_start then
		start_time = live_start
		end_time = live_end
	end
	self.weave_is_casting = true
	self.weave_spell_id = entry.spell_id
	self.weave_family = family
	self.weave_cast_start_time = start_time
	self.weave_cast_end_time = end_time
	self.weave_cast_duration = end_time and (end_time - start_time)
		or self.SHAMAN.get_weave_effective_cast_time(self, entry)
	local d = self.mainhand
	if d and d.speed and d.ends_at and d.start and not d.is_full then
		-- Swing-anchor note: BOTH swing anchors are measured against the swing that was
		-- current when the cast began and are then held for the whole cast. Rolling them
		-- forward with the live swing would move the cast's start AND its projected
		-- landing by one swing duration every rollover, which made the spark jump back
		-- toward its origin and re-travel. A DELAYED event keeps the anchors it was
		-- given (same cast); everything else re-measures, because a new cast really did
		-- begin in whatever swing is current now.
		if not (keep_swing_anchor and self.weave_cast_swing_start ~= nil) then
			self.weave_cast_swing_start = d.start
			-- Anchored on the cast's own start stamp, not on the tick's now: a START
			-- payload that arrives after the cast began must still report where in the
			-- swing the cast started.
			self.weave_cast_start_swing_fraction = st.weave.get_cast_start_fraction(start_time, d.start, d.speed)
		end
	else
		self.weave_cast_swing_start = nil
		self.weave_cast_start_swing_fraction = nil
	end
end

-- End the active-cast state (the last-known family is kept for the marker).
local function end_weave_cast(self)
	self.weave_is_casting = false
	self.weave_cast_start_time = nil
	self.weave_cast_end_time = nil
	self.weave_cast_start_swing_fraction = nil
	self.weave_cast_swing_start = nil
	self.weave_cast_duration = nil
end

-- Is this token one of the totem-twist drops? A numeric spell id matches the id
-- table; a name token (older-style payloads, the live GetSpellInfo resolution in
-- on_spellcast_succeeded and the air-slot totemName) matches the name set, so
-- ranks whose ids are still unconfirmed stamp by name. Anything else is not a
-- twist drop.
local function is_twist_totem(token)
	if token == nil then
		return false
	end
	if WEAVE_TWIST_TOTEM_IDS[token] then
		return true
	end
	if type(token) == "string" and WEAVE_TWIST_TOTEM_NAMES[token] then
		return true
	end
	return false
end

-- Reconcile the last-drop stamp with the live air-slot totem clock: an active
-- twist-named totem (name or spell id) with a positive startTime adopts it when
-- the stamp is unknown or older. This covers loads/reloads mid-twist and missed
-- SUCCEEDED events; an absent totem, a non-twist air totem (Nature Resistance and
-- friends share the slot) and an unreadable startTime leave the stamp alone, so no
-- prompt is ever built on a guess. Newer wins: a stale poll reading never rewinds
-- a fresher cast commit.
function ST.SHAMAN.refresh_twist_from_totems(self)
	local have_totem, totem_name, start_time, _, _, _, spell_id =
		api.GetTotemInfo(WEAVE_TOTEM_AIR_SLOT)
	if not have_totem then
		return
	end
	if not is_twist_totem(totem_name) and not is_twist_totem(spell_id) then
		return
	end
	if type(start_time) ~= "number" or start_time <= 0 then
		return
	end
	local known = self.weave_twist_last_drop
	if type(known) ~= "number" or known <= 0 or start_time > known then
		self.weave_twist_last_drop = start_time
	end
end

-- Is this token a Magma Totem drop? Same shape as the twist matcher above: a numeric
-- spell id matches the id table (8190 UNCONFIRMED), a name token matches the name
-- set, so unconfirmed ranks stamp by name. Anything else is not a Magma drop.
local function is_magma_totem(token)
	if token == nil then
		return false
	end
	if WEAVE_MAGMA_TOTEM_IDS[token] then
		return true
	end
	if type(token) == "string" and WEAVE_MAGMA_TOTEM_NAMES[token] then
		return true
	end
	return false
end

-- Reconcile the last-drop stamp with the live fire-slot totem clock (Wrath Magma
-- maintain): an active Magma Totem (name or spell id) with a positive startTime
-- adopts it when the stamp is unknown or older. This covers loads/reloads with
-- Magma up and missed SUCCEEDED events; an absent totem, a non-Magma fire totem
-- (Searing, Totem of Wrath, Fire Elemental and friends share the slot) and an
-- unreadable startTime leave the stamp alone, so no prompt is ever built on a
-- guess. Newer wins: a stale poll reading never rewinds a fresher cast commit.
-- Returns true when the client affirmatively reports an empty fire slot
-- (haveTotem == false): the totem is due. A nil read (MayReturnNothing empty,
-- throwing read, secret field, no API) is unknown, never "no totem" - the
-- compat contract - so the gather leaves the feed dead on it.
function ST.SHAMAN.refresh_magma_from_totems(self)
	local have_totem, totem_name, start_time, _, _, _, spell_id =
		api.GetTotemInfo(WEAVE_TOTEM_FIRE_SLOT)
	if have_totem == nil then
		return false
	end
	if have_totem == false then
		self.weave_magma_last_drop = nil
		return true
	end
	if not is_magma_totem(totem_name) and not is_magma_totem(spell_id) then
		return false
	end
	if type(start_time) ~= "number" or start_time <= 0 then
		return false
	end
	local known = self.weave_magma_last_drop
	if type(known) ~= "number" or known <= 0 or start_time > known then
		self.weave_magma_last_drop = start_time
	end
	return false
end

function ST.SHAMAN.on_spellcast_event(self, event, unit, cast_guid, spell_id)
	if unit ~= "player" or not self.interfaces_are_initialised then
		return
	end

	if event == "UNIT_SPELLCAST_START"
		or event == "UNIT_SPELLCAST_DELAYED"
		or event == "UNIT_SPELLCAST_CHANNEL_START" then
		-- The live window is fetched either way: it carries the family for payloads
		-- without a spell token, and the live duration when a cast is running.
		local live_name, live_spell_id, live_start, live_end = get_live_player_cast()

		-- Numeric id first, then a name token (older-style payloads).
		local family = lookup_weave_family(self, spell_id) or lookup_weave_family(self, cast_guid)
		if not family then
			family = lookup_weave_family(self, live_spell_id) or lookup_weave_family(self, live_name)
		end
		if not family then
			-- A family may have been learned since the last resolution: retry (throttled)
			-- before giving up on the cast.
			self.SHAMAN.resolve_weave_catalog(self)
			family = lookup_weave_family(self, spell_id) or lookup_weave_family(self, cast_guid)
				or lookup_weave_family(self, live_spell_id) or lookup_weave_family(self, live_name)
		end

		if family then
			begin_weave_cast(self, family, live_start, live_end, event == "UNIT_SPELLCAST_DELAYED")
		elseif event == "UNIT_SPELLCAST_DELAYED" and self.weave_is_casting and self.weave_family then
			-- Keep tracking the running cast and re-anchor its timing.
			begin_weave_cast(self, self.weave_family, live_start, live_end, true)
		end
		return
	end

	if event == "UNIT_SPELLCAST_STOP"
		or event == "UNIT_SPELLCAST_INTERRUPTED"
		or event == "UNIT_SPELLCAST_FAILED"
		or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		end_weave_cast(self)
	end
end

function ST.SHAMAN.on_spellcast_succeeded(self, unit_id, cast_guid, spell_id)
	if unit_id ~= "player" or not self.interfaces_are_initialised then
		return
	end
	-- Keep the finished cast as the last-known family (the marker keeps showing its
	-- breakpoint) and end the active-cast state. Instants (5 Maelstrom Weapon stacks)
	-- only fire SUCCEEDED, so the token is also how they become the last cast.
	local family = lookup_weave_family(self, spell_id) or lookup_weave_family(self, cast_guid)
	if family then
		self.weave_family = family
		self.weave_spell_id = self.weave_catalog[family].spell_id
	end
	-- Totem-twist drops commit here (totem casts are instants: SUCCEEDED is the only
	-- event they fire). Numeric id first, then the name token (older-style payloads),
	-- then the cast's live spell name so ranks whose ids are still unconfirmed stamp
	-- by name. The stamp is the api.get_time() commit time, the same domain the
	-- air-slot startTime and the guide's now share.
	local live_name
	if spell_id ~= nil then
		live_name = api.GetSpellInfo(spell_id)
	end
	if is_twist_totem(spell_id) or is_twist_totem(cast_guid)
		or is_twist_totem(live_name) then
		self.weave_twist_last_drop = api.get_time()
	end
	-- Magma maintain drops commit here too (totem drops are instants: SUCCEEDED is
	-- the only event they fire). Same token shapes as the twist commit above, so
	-- unconfirmed Magma ranks stamp by name. The stamp is the api.get_time()
	-- commit time, the same domain the fire-slot startTime and the guide share.
	if is_magma_totem(spell_id) or is_magma_totem(cast_guid)
		or is_magma_totem(live_name) then
		self.weave_magma_last_drop = api.get_time()
	end
	end_weave_cast(self)
end

function ST.SHAMAN.on_aura_change(self)
	-- Haste buffs, Maelstrom Weapon stacks and the tracker state (windfury, Shamanistic
	-- Rage, Rockbiter, Flurry, shield charges) all change here and are read by the SAME
	-- auras, so one walk feeds every refresh below. No widgets are touched: this hook
	-- runs from UNIT_AURA.
	local scan = scan_weave_auras()
	self.SHAMAN.refresh_weave_haste(self, scan.buff_multiplier)
	self.SHAMAN.refresh_weave_mw_stacks(self, scan.stacks)
	self.weave_windfury_active = scan.windfury
	self.weave_sr_expires = scan.sr_expires
	self.weave_rockbiter_active = scan.rockbiter
	self.weave_rockbiter_expires = scan.rockbiter_expires
	-- Flurry (round 2): the stack count feeds the DW/Flurry badge; a count INCREASE
	-- (a fresh aura or a new proc while one is active) stamps the proc time the
	-- 0.5 s ICD counts from. A decrease is a charge consumed - never a stamp.
	local flurry_count = scan.flurry
	if type(flurry_count) == "number" and flurry_count > (self.weave_flurry_stacks or 0) then
		self.weave_flurry_proc_at = api.get_time()
	end
	self.weave_flurry_stacks = flurry_count
	self.weave_shield_type = scan.shield_type
	self.weave_shield_charges = scan.shield_charges
end

function ST.SHAMAN.on_combat_exit(self)
	-- A wipe interrupts the cast without ever firing STOP/SUCCEEDED, so the cast state
	-- would stay "live" and leave a frozen spark and a stale clip tint for the rest of
	-- the session. Clear the in-flight cast (end_weave_cast keeps the last resolved
	-- family, so the marker still shows that spell's breakpoint).
	end_weave_cast(self)
end

function ST.SHAMAN.post_init(self)
	-- Weave state: the cast tracker, the per-family resolved spell catalog, and the live
	-- inputs the frozen weave.lua math consumes.
	self.weave_is_casting = false
	self.weave_spell_id = nil
	self.weave_family = nil
	self.weave_cast_start_time = nil
	self.weave_cast_end_time = nil
	self.weave_cast_start_swing_fraction = nil
	self.weave_cast_swing_start = nil
	self.weave_cast_duration = nil
	self.weave_marker_icon = nil
	self.weave_mw_stacks = 0
	self.weave_mw_observed = false
	self.weave_haste_mult = 1
	self.weave_catalog = {}
	self.weave_catalog_retry_at = {}

	-- Tracker state (windfury ICD, Shamanistic Rage, flame shock, Stormstrike debuff,
	-- Rockbiter, shields). The flame shock / Stormstrike caches are refreshed lazily
	-- by the throttled target scan in on_bar_update.
	self.weave_windfury_active = false
	self.weave_windfury_bucket = nil
	-- Totem-twist last-drop stamp (TBC): api.get_time() of the last Windfury/Grace
	-- of Air commit (SUCCEEDED) or the air-slot totem clock, reconciled in
	-- refresh_twist_from_totems. Nil means unknown - the guide never prompts on a
	-- guess (see gather_guide_inputs).
	self.weave_twist_last_drop = nil
	-- Magma maintain last-drop stamp (Wrath): api.get_time() of the last Magma
	-- Totem commit (SUCCEEDED) or the fire-slot totem clock, reconciled in
	-- refresh_magma_from_totems. Nil means unknown - the guide never prompts on a
	-- guess (see gather_guide_inputs).
	self.weave_magma_last_drop = nil
	self.weave_sr_expires = nil
	self.weave_rockbiter_active = false
	self.weave_rockbiter_expires = nil
	self.weave_flurry_stacks = nil
	self.weave_flurry_proc_at = nil
	self.weave_shield_type = nil
	self.weave_shield_charges = nil
	self.weave_shield_layout_slots = nil
	self.weave_fs_duration = nil
	self.weave_fs_expires = nil
	self.weave_fs_scan_at = nil
	self.weave_fs_glow_on = false
	self.weave_fs_label_seconds = nil
	self.weave_storm_duration = nil
	self.weave_storm_expires = nil
	self.weave_storm_glow_on = false
	self.weave_storm_label_seconds = nil
	self.weave_ss_seconds = nil
	self.weave_ss_badge_mode = nil
	self.weave_sr_seconds = nil
	self.weave_rb_seconds = nil
	self.weave_sync_readout = nil
	self.weave_flurry_readout = nil
	-- Lava Burst spender cache (S4; resolved lazily on ERA clients) and its retry stamp.
	self.weave_lava_burst = nil
	self.weave_lava_burst_retry_at = nil

	-- Haste/Maelstrom/tracker snapshot and the initial catalogue (also parses auras,
	-- like the paladin does for seals).
	self.SHAMAN.on_aura_change(self)
	self.SHAMAN.resolve_weave_catalog(self)

	-- Next Action Guide: resolve the weave slot's icon from the catalogue just resolved,
	-- then hand the provider (ST.SHAMAN.guide at the end of this file) to the shared
	-- frame. Guarded so a flavor without nextaction_ui stays inert; the guide itself
	-- stays hidden until nextaction_enabled is turned on.
	self.SHAMAN.resolve_guide_icons(self)
	if st.nextaction_ui then
		st.nextaction_ui.init(self)
	end

	-- Cooldown HUD: builds its own UIParent frames (out of combat, deferred and
	-- retried via the per-frame hook under lockdown) from this class's HUD_SLOTS
	-- and the provider below; guarded so a flavor without hud.lua stays inert
	-- (the paladin wires it the same way in classes/paladin.lua).
	if st.hud then
		st.hud.init(self)
	end

	-- The mainhand visuals frame exists by now.
	self.SHAMAN.setup_weave_visuals(self)
end

--=========================================================================================
-- Visuals
--=========================================================================================
function ST.SHAMAN.setup_weave_visuals(self)
	-- Creates the weave widgets on the mainhand visuals frame and the offhand spark
	-- mirror (called from post_init; on_bar_update retries if the frame was not ready yet).
	local vf = self:get_visuals_frame("mainhand")
	if vf and not vf.weave_marker then
		-- Breakpoint marker: the resolved spell's icon, cropped like the reference.
		local marker = vf:CreateTexture(nil, "OVERLAY")
		marker:SetDrawLayer("OVERLAY", -3)
		marker:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		marker:Hide()
		vf.weave_marker = marker

		-- Reference top/bottom breakpoint icons (SuperSwingTimer_ClassMods.lua:3491-3506):
		-- the same icon above the bar and below the bar stack.
		local marker_top = vf:CreateTexture(nil, "OVERLAY")
		marker_top:SetDrawLayer("OVERLAY", -3)
		marker_top:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		marker_top:Hide()
		vf.weave_marker_top = marker_top

		local marker_bottom = vf:CreateTexture(nil, "OVERLAY")
		marker_bottom:SetDrawLayer("OVERLAY", -3)
		marker_bottom:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		marker_bottom:Hide()
		vf.weave_marker_bottom = marker_bottom

		-- Cast spark: white base texture, tinted per frame.
		local spark = vf:CreateTexture(nil, "OVERLAY")
		spark:SetDrawLayer("OVERLAY", -2)
		spark:SetColorTexture(1, 1, 1, 1)
		spark:Hide()
		vf.weave_spark = spark

		-- Windfury ICD strip: dark backing plus a fill that shrinks as the internal
		-- cooldown elapses, left-anchored at the bar's right edge (reference wfIcdBar,
		-- SuperSwingTimer_ClassMods.lua:3809-3821).
		local windfury_bg = vf:CreateTexture(nil, "OVERLAY")
		windfury_bg:SetDrawLayer("OVERLAY", -1)
		windfury_bg:SetColorTexture(WEAVE_WINDFURY_BG_COLOR[1], WEAVE_WINDFURY_BG_COLOR[2],
			WEAVE_WINDFURY_BG_COLOR[3], WEAVE_WINDFURY_BG_COLOR[4])
		windfury_bg:SetPoint("LEFT", vf, "RIGHT", 0, 0)
		windfury_bg:Hide()
		vf.weave_windfury_bg = windfury_bg

		local windfury_fill = vf:CreateTexture(nil, "OVERLAY")
		windfury_fill:SetDrawLayer("OVERLAY", -1)
		windfury_fill:SetColorTexture(1, 1, 1, 1)
		windfury_fill:SetPoint("LEFT", vf, "RIGHT", 0, 0)
		windfury_fill:Hide()
		vf.weave_windfury_fill = windfury_fill

		-- Flame Shock target bar: orange fill over a dark backing, a 1 px glow outline
		-- shown in the final seconds and a seconds label placed above the bar (reference
		-- SuperSwingTimer_ClassMods.lua:3885-3963). All static setup happens once here;
		-- the per-frame path only resizes the fill and flips label/glow visibility.
		local fs_bg = vf:CreateTexture(nil, "OVERLAY")
		fs_bg:SetDrawLayer("OVERLAY", -2)
		fs_bg:SetColorTexture(WEAVE_FLAME_SHOCK_BG_COLOR[1], WEAVE_FLAME_SHOCK_BG_COLOR[2],
			WEAVE_FLAME_SHOCK_BG_COLOR[3], WEAVE_FLAME_SHOCK_BG_COLOR[4])
		fs_bg:SetHeight(WEAVE_FLAME_SHOCK_BAR_HEIGHT)
		fs_bg:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", 0, 2)
		fs_bg:SetPoint("BOTTOMRIGHT", vf, "TOPRIGHT", 0, 2)
		fs_bg:Hide()
		vf.weave_fs_bg = fs_bg

		local fs_fill = vf:CreateTexture(nil, "OVERLAY")
		fs_fill:SetDrawLayer("OVERLAY", -2)
		fs_fill:SetColorTexture(WEAVE_FLAME_SHOCK_COLOR[1], WEAVE_FLAME_SHOCK_COLOR[2],
			WEAVE_FLAME_SHOCK_COLOR[3], WEAVE_FLAME_SHOCK_COLOR[4])
		fs_fill:SetHeight(WEAVE_FLAME_SHOCK_BAR_HEIGHT)
		fs_fill:SetPoint("LEFT", fs_bg, "LEFT", 0, 0)
		fs_fill:Hide()
		vf.weave_fs_fill = fs_fill

		local fs_glow = vf:CreateTexture(nil, "OVERLAY")
		fs_glow:SetDrawLayer("OVERLAY", -1)
		fs_glow:SetColorTexture(WEAVE_FLAME_SHOCK_GLOW_COLOR[1], WEAVE_FLAME_SHOCK_GLOW_COLOR[2],
			WEAVE_FLAME_SHOCK_GLOW_COLOR[3], WEAVE_FLAME_SHOCK_GLOW_COLOR[4])
		fs_glow:SetPoint("BOTTOMLEFT", fs_bg, "BOTTOMLEFT", -1, -1)
		fs_glow:SetPoint("TOPRIGHT", fs_bg, "TOPRIGHT", 1, 1)
		fs_glow:Hide()
		vf.weave_fs_glow = fs_glow

		local fs_label = vf:CreateFontString(nil, "OVERLAY")
		fs_label:SetPoint("CENTER", fs_bg, "CENTER", 0, 0)
		fs_label:SetJustifyH("CENTER")
		fs_label:SetFont(get_tracker_font_path(self), 8, "OUTLINE")
		fs_label:SetTextColor(WEAVE_FLAME_SHOCK_LABEL_COLOR[1], WEAVE_FLAME_SHOCK_LABEL_COLOR[2],
			WEAVE_FLAME_SHOCK_LABEL_COLOR[3], WEAVE_FLAME_SHOCK_LABEL_COLOR[4])
		fs_label:Hide()
		vf.weave_fs_label = fs_label

		-- Cooldown badges, stacked beside the bar's right edge (reference
		-- SuperSwingTimer_ClassMods.lua:3700-3748).
		local ss_text = vf:CreateFontString(nil, "OVERLAY")
		ss_text:SetPoint("TOPLEFT", vf, "TOPRIGHT", 3, 2)
		ss_text:SetJustifyH("LEFT")
		ss_text:SetFont(get_tracker_font_path(self), 9, "OUTLINE")
		ss_text:SetTextColor(WEAVE_SS_BADGE_COLOR[1], WEAVE_SS_BADGE_COLOR[2],
			WEAVE_SS_BADGE_COLOR[3], WEAVE_SS_BADGE_COLOR[4])
		ss_text:Hide()
		vf.weave_ss_text = ss_text

		local sr_text = vf:CreateFontString(nil, "OVERLAY")
		sr_text:SetPoint("TOPLEFT", vf, "TOPRIGHT", 3, -8)
		sr_text:SetJustifyH("LEFT")
		sr_text:SetFont(get_tracker_font_path(self), 9, "OUTLINE")
		sr_text:SetTextColor(WEAVE_SR_BADGE_COLOR[1], WEAVE_SR_BADGE_COLOR[2],
			WEAVE_SR_BADGE_COLOR[3], WEAVE_SR_BADGE_COLOR[4])
		sr_text:Hide()
		vf.weave_sr_text = sr_text

		-- Shield charge row: one rect per possible charge slot, right-anchored beside
		-- the bar and growing leftward, empty slots dimmed (reference
		-- SuperSwingTimer_ClassMods.lua:3632-3660, 4171-4206). Colors are applied per
		-- frame via SetVertexColor so a shield swap never re-allocates a texture.
		local rects = {}
		for i = 1, WEAVE_SHIELD_MAX_SLOTS do
			local rect = vf:CreateTexture(nil, "OVERLAY")
			rect:SetDrawLayer("OVERLAY", -1)
			rect:SetWidth(WEAVE_SHIELD_RECT_WIDTH)
			rect:SetColorTexture(1, 1, 1, 1)
			rect:Hide()
			rects[i] = rect
		end
		vf.weave_shield_rects = rects
	end

	-- Offhand spark mirror: same lookup as the mainhand spark, drawn on the offhand
	-- visuals frame while the player dual-wields (reference 3481-3489).
	local oh_vf = self:get_visuals_frame("offhand")
	if oh_vf and not oh_vf.weave_spark_offhand then
		local oh_spark = oh_vf:CreateTexture(nil, "OVERLAY")
		oh_spark:SetDrawLayer("OVERLAY", -2)
		oh_spark:SetColorTexture(1, 1, 1, 1)
		oh_spark:Hide()
		oh_vf.weave_spark_offhand = oh_spark
	end
end

-- The family the assist should draw right now: at five Maelstrom Weapon stacks the
-- chosen spender (S4 - Lava Burst only when the rune/talent is present and the
-- FS-collision guard allows; see st.weave.get_mw5_spender / should_hold_mw5),
-- otherwise the cast in progress, else the last resolved cast, else the first enabled
-- family with a resolved spell. Returns the catalog entry and its family ("LvB" for
-- the Lava Burst spender), or nil when nothing is drawable.
function ST.SHAMAN.get_weave_visual_spell(self)
	local db = self:get_class_table()
	local families = db.weave_families
	-- MW5 spender choice (S4). A held-back guard (FS inside its final 2 s with a
	-- ready shock) or a disabled LB family falls through to the catalogue read
	-- below, so the pre-S4 behaviour is the fallback everywhere.
	if (not families or families.LB ~= false)
		and is_weave_mw_active(db, self.weave_mw_observed)
		and type(self.weave_mw_stacks) == "number"
		and self.weave_mw_stacks >= st.weave.MW_MAX_STACKS then
		local lava = self.SHAMAN.resolve_lava_burst(self)
		if lava and st.weave.get_mw5_spender(api.is_spell_known(lava.spell_id)) == "lavaburst" then
			local fs_remaining
			if self.weave_fs_duration or self.weave_fs_expires then
				fs_remaining = st.weave.get_flame_shock_remaining(
					self.weave_fs_duration, self.weave_fs_expires, api.get_time())
			end
			if not st.weave.should_hold_mw5(fs_remaining, self.SHAMAN.is_shock_ready()) then
				return lava, "LvB"
			end
		end
	end
	local last = self.weave_family
	if last and self.weave_catalog[last] and (not families or families[last] ~= false) then
		return self.weave_catalog[last], last
	end
	for i = 1, #st.weave.FAMILIES do
		local family = st.weave.FAMILIES[i]
		if not families or families[family] ~= false then
			local entry = self.weave_catalog[family]
			if entry then
				return entry, family
			end
		end
	end
	return nil, nil
end

--=========================================================================================
-- Tracker visuals
--=========================================================================================
-- The tracked cast's display state on the MAINHAND swing axis, shared by the mainhand
-- spark and its offhand mirror: the spark fraction (nil while no cast window is running),
-- whether the cast clips the swing, and the marker fraction (reference
-- SuperSwingTimer_ClassMods.lua:454-464, 3458-3464). While no cast is live the clip
-- estimate assumes a fresh cast, which is also what dims the marker.
local function get_weave_spark_display(self, d, entry, now, latency)
	local duration = d.speed
	local effective = self.SHAMAN.get_weave_effective_cast_time(self, entry)
	local marker_fraction = st.weave.get_marker_fraction(duration, effective, latency)
	local cast_start_fraction = self.weave_cast_start_swing_fraction
	local cast_remaining = effective
	local cast_total = self.weave_cast_duration
	local cast_live = self.weave_is_casting and self.weave_cast_start_time
		and self.weave_cast_duration and self.weave_cast_duration > 0
	if cast_live then
		if type(self.weave_cast_end_time) == "number" then
			cast_remaining = math.max(0, self.weave_cast_end_time - now)
		else
			cast_remaining = math.max(0, self.weave_cast_duration - (now - self.weave_cast_start_time))
		end
		if type(self.weave_cast_end_time) == "number"
			and self.weave_cast_end_time > self.weave_cast_start_time then
			cast_total = self.weave_cast_end_time - self.weave_cast_start_time
		end
	end
	local clip_amount = st.weave.get_clip_amount(now, latency, cast_remaining, d.ends_at)
	local clipped = st.weave.is_clipped(clip_amount, cast_start_fraction, marker_fraction)
	local spark_fraction
	if cast_live and cast_total > 0 then
		local progress = st.weave.clamp_fraction((now - self.weave_cast_start_time) / cast_total)
		if cast_start_fraction ~= nil and duration > 0 then
			-- Travel from where the cast started toward where it is projected to land.
			-- The landing is projected against the swing the CAST started in
			-- (weave_cast_swing_start), not the swing that is current now: the cast's
			-- impact time is fixed, so re-anchoring the projection on every rollover
			-- rewound the destination by a full swing and made the spark re-travel.
			local projected = st.weave.get_projected_impact_fraction(now, cast_remaining, latency,
				self.weave_cast_swing_start or d.start, duration)
			spark_fraction = st.weave.get_spark_fraction(cast_start_fraction, projected, progress)
		else
			spark_fraction = progress
		end
	end
	return spark_fraction, clipped, marker_fraction
end

-- Hide the marker trio (main icon plus the reference top/bottom pair).
local function hide_weave_markers(vf)
	if vf.weave_marker then vf.weave_marker:Hide() end
	if vf.weave_marker_top then vf.weave_marker_top:Hide() end
	if vf.weave_marker_bottom then vf.weave_marker_bottom:Hide() end
end

-- The frame the reference drops the bottom breakpoint icon under: the offhand bar's
-- visuals frame while the player dual-wields with that bar visible, else the mainhand
-- frame (SuperSwingTimer_ClassMods.lua:3499-3502).
local function get_weave_bottom_anchor(self, mainhand_vf, mainhand_width)
	local oh = self.offhand
	local oh_bar = oh and oh.anchor_frame and oh.anchor_frame.bar_frame
	if oh and oh.has_weapon and oh_bar and oh_bar.IsShown and oh_bar:IsShown() then
		local oh_vf = self:get_visuals_frame("offhand")
		local oh_width = self:get_bar_visuals_width_and_height("offhand")
		if oh_vf and type(oh_width) == "number" then
			return oh_vf, oh_width
		end
	end
	return mainhand_vf, mainhand_width
end

-- Windfury ICD strip: a thin strip at the bar's right edge whose fill shrinks as the 3 s
-- internal cooldown elapses, tinted by bucket (reference
-- SuperSwingTimer_ClassMods.lua:3802-3848). Only drawn while Windfury Weapon is up.
local function update_windfury_icd(self, vf, d, db, now, h)
	local bg, fill = vf.weave_windfury_bg, vf.weave_windfury_fill
	if not (bg and fill) then return end
	if type(h) ~= "number" or h <= 0
		or db.show_shaman_windfury_icd == false
		or not self.weave_windfury_active
		or not (d and type(d.start) == "number" and d.start > 0) then
		bg:Hide()
		fill:Hide()
		return
	end
	local remaining = st.weave.get_windfury_icd_remaining(d.start, now)
	if not remaining then
		bg:Hide()
		fill:Hide()
		return
	end
	local fraction = st.weave.clamp_fraction(remaining / st.weave.WINDFURY_ICD_SECONDS)
	bg:SetWidth(WEAVE_WINDFURY_STRIP_WIDTH)
	bg:SetHeight(h)
	fill:SetWidth(WEAVE_WINDFURY_STRIP_WIDTH * fraction)
	fill:SetHeight(h)
	local bucket = st.weave.get_windfury_tint_bucket(remaining)
	if self.weave_windfury_bucket ~= bucket then
		self.weave_windfury_bucket = bucket
		local color = WEAVE_WINDFURY_COLORS[bucket]
		fill:SetVertexColor(color[1], color[2], color[3], color[4])
	end
	bg:Show()
	fill:Show()
end

-- Scan the TARGET's harmful auras for the tracked debuffs: Flame Shock (always) and
-- the Stormstrike nature-vulnerability debuff (only while its bar is enabled). Id
-- table + name fallback, caster must be the player (reference
-- SuperSwingTimer_ClassMods.lua:3966-3989; the Stormstrike leg mirrors the
-- reference's caster == "player" rule with the port's nil-source allowance).
-- Returns the Flame Shock duration/expiration then the Stormstrike
-- duration/expiration; the walk stops once everything it was asked for is found.
local function scan_target_debuffs(want_stormstrike)
	local fs_found, fs_duration, fs_expiration = false, nil, nil
	local ss_found, ss_duration, ss_expiration = false, nil, nil
	local i = 1
	while i <= 40 do
		local name, _, _, _, duration, expiration, source, _, _, spell_id = api.UnitAura("target", i, "HARMFUL")
		-- No early break (R2): nil is simply no match at this index.
		if name ~= nil then
			local mine = source == "player" or source == nil
			if mine and not fs_found
				and ((spell_id and WEAVE_FLAME_SHOCK_IDS[spell_id]) or name == WEAVE_FLAME_SHOCK_NAME) then
				fs_found = true
				fs_duration, fs_expiration = duration, expiration
			end
			if want_stormstrike and mine and not ss_found
				and ((spell_id and WEAVE_STORMSTRIKE_DEBUFF_IDS[spell_id]) or name == WEAVE_STORMSTRIKE_DEBUFF_NAME) then
				ss_found = true
				ss_duration, ss_expiration = duration, expiration
			end
			if fs_found and (not want_stormstrike or ss_found) then
				break
			end
		end
		i = i + 1
	end
	return fs_duration, fs_expiration, ss_duration, ss_expiration
end

-- Throttled target-debuff scan shared by the Flame Shock bar, the Stormstrike bar
-- and the guide's frozen Flame Shock input (scan cadence: the reference's 0.05 s,
-- SuperSwingTimer_ClassMods.lua:3991-3996). Only the debuffs someone will read are
-- scanned; a tick nobody needs performs no aura work at all.
local function refresh_target_debuffs(self, db, now)
	local want_fs = db.show_shaman_flame_shock_bar ~= false or db.nextaction_enabled == true
	local want_ss = db.show_shaman_stormstrike_bar == true
	if not (want_fs or want_ss) then
		return
	end
	if now < (self.weave_fs_scan_at or 0) then
		return
	end
	self.weave_fs_scan_at = now + WEAVE_FLAME_SHOCK_SCAN_INTERVAL
	local fs_duration, fs_expiration, ss_duration, ss_expiration = scan_target_debuffs(want_ss)
	if want_fs then
		self.weave_fs_duration = fs_duration
		self.weave_fs_expires = fs_expiration
	end
	if want_ss then
		self.weave_storm_duration = ss_duration
		self.weave_storm_expires = ss_expiration
	end
end

-- Flame Shock target bar: duration fill, seconds label and a glow outline in the final
-- seconds. The throttled target scan runs in refresh_target_debuffs (shared with the
-- Stormstrike bar and the guide); between scans the bar just counts down.
local function update_flame_shock_bar(self, vf, db, now, w)
	local glow, bg, fill, label = vf.weave_fs_glow, vf.weave_fs_bg, vf.weave_fs_fill, vf.weave_fs_label
	if not (glow and bg and fill and label) then return end
	local show_bar = db.show_shaman_flame_shock_bar ~= false
	if not show_bar and db.nextaction_enabled ~= true then
		self.weave_fs_glow_on = false
		glow:Hide()
		bg:Hide()
		fill:Hide()
		label:Hide()
		return
	end
	local duration, expires = self.weave_fs_duration, self.weave_fs_expires
	if not show_bar or (not duration and not expires) then
		self.weave_fs_glow_on = false
		glow:Hide()
		bg:Hide()
		fill:Hide()
		label:Hide()
		return
	end
	local remaining, total = st.weave.get_flame_shock_remaining(duration, expires, now)
	if type(w) == "number" and w > 0 then
		fill:SetWidth(w * st.weave.clamp_fraction(remaining / total))
	end
	local seconds = math.floor(remaining + 0.5)
	if self.weave_fs_label_seconds ~= seconds then
		self.weave_fs_label_seconds = seconds
		label:SetText(tostring(seconds))
	end
	local glow_on = st.weave.should_flame_shock_glow(remaining)
	if glow_on ~= self.weave_fs_glow_on then
		self.weave_fs_glow_on = glow_on
		if glow_on then glow:Show() else glow:Hide() end
	end
	bg:Show()
	fill:Show()
	label:Show()
end

-- Stormstrike nature-vulnerability target bar (S2): an FS-bar clone stacked above
-- the Flame Shock bar - duration fill, seconds label and a final-seconds glow -
-- fed by the same throttled target scan (refresh_target_debuffs). The widgets are
-- created lazily on the first tick with the option ON, so a default session (nil =
-- off) creates nothing and the construction-time widget counts stay untouched.
local function update_stormstrike_bar(self, vf, db, now, w)
	local show_bar = db.show_shaman_stormstrike_bar == true
	if not show_bar then
		if vf.weave_storm_bg then
			self.weave_storm_glow_on = false
			vf.weave_storm_glow:Hide()
			vf.weave_storm_bg:Hide()
			vf.weave_storm_fill:Hide()
			vf.weave_storm_label:Hide()
		end
		return
	end
	local bg = vf.weave_storm_bg
	if not bg then
		local fs_bg = vf.weave_fs_bg
		bg = vf:CreateTexture(nil, "OVERLAY")
		bg:SetDrawLayer("OVERLAY", -2)
		bg:SetColorTexture(WEAVE_STORMSTRIKE_BG_COLOR[1], WEAVE_STORMSTRIKE_BG_COLOR[2],
			WEAVE_STORMSTRIKE_BG_COLOR[3], WEAVE_STORMSTRIKE_BG_COLOR[4])
		bg:SetHeight(WEAVE_STORMSTRIKE_BAR_HEIGHT)
		if fs_bg then
			bg:SetPoint("BOTTOMLEFT", fs_bg, "TOPLEFT", 0, 2)
			bg:SetPoint("BOTTOMRIGHT", fs_bg, "TOPRIGHT", 0, 2)
		else
			bg:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", 0, 2)
			bg:SetPoint("BOTTOMRIGHT", vf, "TOPRIGHT", 0, 2)
		end
		bg:Hide()
		vf.weave_storm_bg = bg

		local fill = vf:CreateTexture(nil, "OVERLAY")
		fill:SetDrawLayer("OVERLAY", -2)
		fill:SetColorTexture(WEAVE_STORMSTRIKE_COLOR[1], WEAVE_STORMSTRIKE_COLOR[2],
			WEAVE_STORMSTRIKE_COLOR[3], WEAVE_STORMSTRIKE_COLOR[4])
		fill:SetHeight(WEAVE_STORMSTRIKE_BAR_HEIGHT)
		fill:SetPoint("LEFT", bg, "LEFT", 0, 0)
		fill:Hide()
		vf.weave_storm_fill = fill

		local glow = vf:CreateTexture(nil, "OVERLAY")
		glow:SetDrawLayer("OVERLAY", -1)
		glow:SetColorTexture(WEAVE_STORMSTRIKE_GLOW_COLOR[1], WEAVE_STORMSTRIKE_GLOW_COLOR[2],
			WEAVE_STORMSTRIKE_GLOW_COLOR[3], WEAVE_STORMSTRIKE_GLOW_COLOR[4])
		glow:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", -1, -1)
		glow:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 1, 1)
		glow:Hide()
		vf.weave_storm_glow = glow

		local label = vf:CreateFontString(nil, "OVERLAY")
		label:SetPoint("CENTER", bg, "CENTER", 0, 0)
		label:SetJustifyH("CENTER")
		label:SetFont(get_tracker_font_path(self), 8, "OUTLINE")
		label:SetTextColor(WEAVE_STORMSTRIKE_LABEL_COLOR[1], WEAVE_STORMSTRIKE_LABEL_COLOR[2],
			WEAVE_STORMSTRIKE_LABEL_COLOR[3], WEAVE_STORMSTRIKE_LABEL_COLOR[4])
		label:Hide()
		vf.weave_storm_label = label
	end
	local duration, expires = self.weave_storm_duration, self.weave_storm_expires
	if not duration and not expires then
		self.weave_storm_glow_on = false
		vf.weave_storm_glow:Hide()
		bg:Hide()
		vf.weave_storm_fill:Hide()
		vf.weave_storm_label:Hide()
		return
	end
	local remaining, total = st.weave.get_stormstrike_remaining(duration, expires, now)
	if type(w) == "number" and w > 0 then
		vf.weave_storm_fill:SetWidth(w * st.weave.clamp_fraction(remaining / total))
	end
	local seconds = math.floor(remaining + 0.5)
	if self.weave_storm_label_seconds ~= seconds then
		self.weave_storm_label_seconds = seconds
		vf.weave_storm_label:SetText(tostring(seconds))
	end
	local glow_on = st.weave.should_stormstrike_glow(remaining)
	if glow_on ~= self.weave_storm_glow_on then
		self.weave_storm_glow_on = glow_on
		if glow_on then vf.weave_storm_glow:Show() else vf.weave_storm_glow:Hide() end
	end
	bg:Show()
	vf.weave_storm_fill:Show()
	vf.weave_storm_label:Show()
end

-- Stormstrike / Shamanistic Rage badges, stacked beside the bar's right edge. SS shows
-- the cooldown; SR prefers the aura's remaining time and falls back to its cooldown
-- (reference SuperSwingTimer_ClassMods.lua:3695-3748). Text is only re-set when the
-- whole-second readout changes, so the per-frame path allocates nothing. S3: while the
-- WF-fishing hold is armed (option-gated) the SS badge flips to an amber "SS HOLD"
-- instead of the cooldown text.
local function update_cooldown_badges(self, vf, db, now, d)
	local ss_text, sr_text = vf.weave_ss_text, vf.weave_sr_text
	if not (ss_text and sr_text) then return end
	if db.show_shaman_cooldown_badges == false then
		ss_text:Hide()
		sr_text:Hide()
		return
	end

	local start_time, duration = api.GetSpellCooldown(WEAVE_STORMSTRIKE_SPELL_ID)
	local ss_remaining = st.weave.get_cooldown_remaining(start_time, duration, now)
	-- WF-fishing hold (S3): Stormstrike ready + the Windfury ICD clearing inside this
	-- swing -> hold it (delay-if-fishing-WF). Gated on the swing's own activity (no
	-- family/mainline gate); the pure predicate lives in weave.lua.
	local ss_hold = false
	if db.show_shaman_wf_hold_tint == true and not ss_remaining
		and self.weave_windfury_active and d
		and type(d.start) == "number" and type(d.ends_at) == "number" then
		ss_hold = st.weave.should_hold_stormstrike(
			st.weave.get_windfury_icd_remaining(d.start, now), d.ends_at - now)
	end
	if ss_hold then
		if self.weave_ss_badge_mode ~= "hold" then
			self.weave_ss_badge_mode = "hold"
			ss_text:SetText("SS HOLD")
			ss_text:SetTextColor(WEAVE_SS_HOLD_COLOR[1], WEAVE_SS_HOLD_COLOR[2],
				WEAVE_SS_HOLD_COLOR[3], WEAVE_SS_HOLD_COLOR[4])
		end
		ss_text:Show()
	elseif ss_remaining then
		if self.weave_ss_badge_mode ~= "cooldown" then
			self.weave_ss_badge_mode = "cooldown"
			-- Force the text refresh too: the cached whole-second readout can
			-- survive a hold period, and the badge must never keep "SS HOLD".
			self.weave_ss_seconds = nil
			ss_text:SetTextColor(WEAVE_SS_BADGE_COLOR[1], WEAVE_SS_BADGE_COLOR[2],
				WEAVE_SS_BADGE_COLOR[3], WEAVE_SS_BADGE_COLOR[4])
		end
		local seconds = math.floor(ss_remaining + 0.5)
		if self.weave_ss_seconds ~= seconds then
			self.weave_ss_seconds = seconds
			ss_text:SetText(string.format("SS %.0fs", ss_remaining))
		end
		ss_text:Show()
	else
		self.weave_ss_badge_mode = nil
		ss_text:Hide()
	end

	local sr_remaining
	if type(self.weave_sr_expires) == "number" then
		local aura_remaining = self.weave_sr_expires - now
		if aura_remaining > 0 then
			sr_remaining = aura_remaining
		end
	end
	if not sr_remaining then
		local sr_start, sr_duration = api.GetSpellCooldown(WEAVE_SR_SPELL_ID)
		sr_remaining = st.weave.get_cooldown_remaining(sr_start, sr_duration, now)
	end
	if sr_remaining then
		local seconds = math.floor(sr_remaining + 0.5)
		if self.weave_sr_seconds ~= seconds then
			self.weave_sr_seconds = seconds
			sr_text:SetText(string.format("SR %.0fs", sr_remaining))
		end
		sr_text:Show()
	else
		sr_text:Hide()
	end
end

-- WF-fishing hold wash (S3): while the hold is armed, an amber translucent overlay
-- covers the swing's final fraction - from the point the Windfury ICD clears to the
-- swing's end (the window where the held Stormstrike is safe to press). The widget
-- is created lazily on the first armed tick with the option ON, so a default
-- session (nil = off) creates nothing; the wash is drawn on the mainhand visuals
-- frame under the marker/spark layers.
local function update_wf_hold_wash(self, vf, db, now, d, w, h)
	local wash = vf.weave_wf_wash
	local armed = false
	local wash_fraction
	-- The hold only exists while Stormstrike is ready to be held (the engine's rule
	-- 7 sits behind its off-cooldown check); the cooldown read runs only with the
	-- option on, so the default path stays read-free.
	if db.show_shaman_wf_hold_tint == true then
		local ss_start, ss_duration = api.GetSpellCooldown(WEAVE_STORMSTRIKE_SPELL_ID)
		local ss_remaining = st.weave.get_cooldown_remaining(ss_start, ss_duration, now)
		if not ss_remaining and self.weave_windfury_active and d
			and type(d.start) == "number" and type(d.ends_at) == "number"
			and type(d.speed) == "number" and d.speed > 0 then
			local icd_remaining = st.weave.get_windfury_icd_remaining(d.start, now)
			if st.weave.should_hold_stormstrike(icd_remaining, d.ends_at - now) then
				armed = true
				wash_fraction = st.weave.get_wf_hold_wash_fraction(now - d.start, d.speed, icd_remaining)
			end
		end
	end
	if not wash then
		if not armed then return end
		wash = vf:CreateTexture(nil, "OVERLAY")
		wash:SetDrawLayer("OVERLAY", -4)
		wash:SetColorTexture(WEAVE_WF_HOLD_WASH_COLOR[1], WEAVE_WF_HOLD_WASH_COLOR[2],
			WEAVE_WF_HOLD_WASH_COLOR[3], WEAVE_WF_HOLD_WASH_COLOR[4])
		wash:Hide()
		vf.weave_wf_wash = wash
	end
	if not armed or wash_fraction == nil or type(w) ~= "number" or w <= 0
		or type(h) ~= "number" or h <= 0 then
		wash:Hide()
		return
	end
	local start = st.weave.clamp_fraction(wash_fraction)
	wash:SetHeight(h)
	wash:ClearAllPoints()
	wash:SetPoint("BOTTOMLEFT", vf, "BOTTOMLEFT", start * w, 0)
	wash:SetWidth((1 - start) * w)
	wash:Show()
end

-- Rockbiter Weapon badge (discover #6): an "RB" readout with the imbue's remaining
-- time while the buff is up, hidden otherwise. Option-gated (nil = off) and created
-- lazily; a buff without a readable expiry still shows the bare "RB". Reads stay
-- guarded (the aura scan owns id/name matching; this only renders its result).
local function update_rockbiter_badge(self, vf, db, now)
	local text = vf.weave_rb_text
	if db.show_shaman_rockbiter_badge ~= true then
		if text then text:Hide() end
		return
	end
	if not text then
		text = vf:CreateFontString(nil, "OVERLAY")
		text:SetPoint("TOPLEFT", vf, "TOPRIGHT", 3, -18)
		text:SetJustifyH("LEFT")
		text:SetFont(get_tracker_font_path(self), 9, "OUTLINE")
		text:SetTextColor(WEAVE_RB_BADGE_COLOR[1], WEAVE_RB_BADGE_COLOR[2],
			WEAVE_RB_BADGE_COLOR[3], WEAVE_RB_BADGE_COLOR[4])
		text:Hide()
		vf.weave_rb_text = text
	end
	if not self.weave_rockbiter_active then
		self.weave_rb_seconds = nil
		text:Hide()
		return
	end
	local expires = self.weave_rockbiter_expires
	if type(expires) ~= "number" then
		if self.weave_rb_seconds ~= -1 then
			self.weave_rb_seconds = -1
			text:SetText("RB")
		end
		text:Show()
		return
	end
	local remaining = expires - now
	if remaining < 0 then remaining = 0 end
	local seconds = math.floor(remaining + 0.5)
	if self.weave_rb_seconds ~= seconds then
		self.weave_rb_seconds = seconds
		text:SetText(string.format("RB %.0fs", remaining))
	end
	text:Show()
end

-- Shield charge row: one rect per charge slot, filled slots in the shield color and the
-- empty ones dimmed, anchored left of the bar (reference
-- SuperSwingTimer_ClassMods.lua:4058-4209).
local function update_shield_charges(self, vf, db, h)
	local rects = vf.weave_shield_rects
	if not rects then return end
	local shield_type = self.weave_shield_type
	local slots, filled = st.weave.get_shield_tracker_state(shield_type, self.weave_shield_charges)
	if db.show_shaman_shield_charges == false or slots <= 0 or type(h) ~= "number" or h <= 0 then
		for i = 1, #rects do
			rects[i]:Hide()
		end
		self.weave_shield_layout_slots = nil
		return
	end
	if self.weave_shield_layout_slots ~= slots then
		-- (Re)anchor the row on a slot-count change: rightmost rect beside the bar, the
		-- rest growing leftward. Anchor changes are rare (Lightning <-> Water Shield),
		-- so the per-frame path never touches the anchors.
		local previous
		for i = 1, slots do
			local rect = rects[i]
			rect:ClearAllPoints()
			if previous then
				rect:SetPoint("TOPRIGHT", previous, "TOPLEFT", -WEAVE_SHIELD_RECT_GAP, 0)
			else
				rect:SetPoint("TOPRIGHT", vf, "TOPLEFT", -WEAVE_SHIELD_BAR_GAP, 0)
			end
			previous = rect
		end
		self.weave_shield_layout_slots = slots
	end
	local color = WEAVE_SHIELD_COLORS[shield_type]
	for i = 1, slots do
		local rect = rects[i]
		rect:SetWidth(WEAVE_SHIELD_RECT_WIDTH)
		rect:SetHeight(h)
		if i <= filled then
			rect:SetVertexColor(color[1], color[2], color[3], color[4])
		else
			rect:SetVertexColor(color[1], color[2], color[3], WEAVE_SHIELD_DIM_ALPHA)
		end
		rect:Show()
	end
	for i = slots + 1, #rects do
		rects[i]:Hide()
	end
end

-- Spell-position row (round 2, operator spec): for each shown weave spell (LB, CL;
-- LvB when the rune/talent is present) the icon sits at the swing fraction where its
-- cast must START to land just before the MH swing - the "spells start cast range
-- zone". The zone band spans the min..max of those starts; icons, cast-time numbers
-- and the zone update every tick (stacks/haste/swing changes move them, so every
-- swing / LB / CL / weave event re-adjusts them). A spell whose safe start has
-- passed reads as a clip (red) - casting now would overrun the swing; fewer than
-- MW_MIN_WEAVE_STACKS stacks read as "wait" (dim). Option-gated (nil = off), all
-- widgets created lazily on the first live tick with the option on.
local weave_position_starts = {}
-- Per-slot caches for the per-tick path: the icon texture and the cast-time value
-- are re-set only when they change (no string/SetTexture churn on a stable swing).
local weave_position_icon_texture = {}
local weave_position_time_value = {}

-- Hide every spell-position widget (created lazily; absent widgets are skipped).
local function hide_spell_positions(vf)
	if vf.weave_pos_zone then vf.weave_pos_zone:Hide() end
	if vf.weave_pos_label then vf.weave_pos_label:Hide() end
	local icons, times = vf.weave_pos_icons, vf.weave_pos_times
	if icons then
		for _, icon in pairs(icons) do icon:Hide() end
	end
	if times then
		for _, time in pairs(times) do time:Hide() end
	end
end

-- One state color for a position slot: family color when ready, red for a clip,
-- dimmed grey while waiting for stacks.
local function get_position_color(state, family)
	if state == "clip" then
		return WEAVE_POSITION_CLIP_COLOR
	elseif state == "wait" then
		return WEAVE_POSITION_WAIT_COLOR
	end
	if family == WEAVE_POSITION_LAVA_KEY then
		return st.weave.LAVA_BURST_COLOR
	end
	return st.weave.FAMILY_COLORS[family]
end

local function update_spell_positions(self, vf, db, now, d, w)
	if not (db.show_shaman_spell_positions == true and db.weave_enabled ~= false
		and is_weave_mw_active(db, self.weave_mw_observed)
		and d and type(d.speed) == "number" and d.speed > 0
		and type(d.start) == "number" and type(d.ends_at) == "number" and not d.is_full) then
		hide_spell_positions(vf)
		return
	end
	if not vf.weave_pos_zone then
		local zone = vf:CreateTexture(nil, "OVERLAY")
		zone:SetDrawLayer("OVERLAY", -5)
		zone:SetColorTexture(WEAVE_ZONE_COLOR[1], WEAVE_ZONE_COLOR[2],
			WEAVE_ZONE_COLOR[3], WEAVE_ZONE_COLOR[4])
		zone:SetHeight(WEAVE_ZONE_HEIGHT)
		zone:Hide()
		vf.weave_pos_zone = zone
		local label = vf:CreateFontString(nil, "OVERLAY")
		label:SetJustifyH("CENTER")
		label:SetFont(get_tracker_font_path(self), 8, "OUTLINE")
		label:SetTextColor(WEAVE_ZONE_LABEL_COLOR[1], WEAVE_ZONE_LABEL_COLOR[2],
			WEAVE_ZONE_LABEL_COLOR[3], WEAVE_ZONE_LABEL_COLOR[4])
		label:SetText(WEAVE_ZONE_LABEL)
		label:Hide()
		vf.weave_pos_label = label
		local icons, times = {}, {}
		local keys = {}
		for i = 1, #WEAVE_POSITION_SLOTS do
			keys[i] = WEAVE_POSITION_SLOTS[i]
		end
		keys[#keys + 1] = WEAVE_POSITION_LAVA_KEY
		for i = 1, #keys do
			local icon = vf:CreateTexture(nil, "OVERLAY")
			icon:SetDrawLayer("OVERLAY", -3)
			icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			icon:SetWidth(WEAVE_POSITION_ICON_SIZE)
			icon:SetHeight(WEAVE_POSITION_ICON_SIZE)
			icon:Hide()
			icons[keys[i]] = icon
			local time = vf:CreateFontString(nil, "OVERLAY")
			time:SetJustifyH("LEFT")
			time:SetFont(get_tracker_font_path(self), 8, "OUTLINE")
			time:SetPoint("LEFT", icon, "RIGHT", 1, 0)
			time:Hide()
			times[keys[i]] = time
		end
		vf.weave_pos_icons = icons
		vf.weave_pos_times = times
	end
	local icons, times = vf.weave_pos_icons, vf.weave_pos_times
	local duration = d.speed
	local latency = ((self.latency and self.latency.world_ms) or 0) / 1000
	local now_fraction = st.weave.clamp_fraction((now - d.start) / duration)
	local stacks = self.weave_mw_stacks
	if type(stacks) ~= "number" then
		stacks = 0
	end
	local families = db.weave_families
	local lava = self.SHAMAN.resolve_lava_burst(self)
	local starts = weave_position_starts
	local count = 0
	local center_y = WEAVE_ZONE_BOTTOM + (WEAVE_ZONE_HEIGHT / 2)
	for i = 1, #WEAVE_POSITION_SLOTS + 1 do
		local key = (i <= #WEAVE_POSITION_SLOTS) and WEAVE_POSITION_SLOTS[i]
			or WEAVE_POSITION_LAVA_KEY
		local icon, time = icons[key], times[key]
		local entry
		if key == WEAVE_POSITION_LAVA_KEY then
			if lava and st.weave.get_mw5_spender(api.is_spell_known(lava.spell_id)) == "lavaburst" then
				entry = lava
			end
		elseif not families or families[key] ~= false then
			entry = self.weave_catalog[key]
		end
		if entry and entry.icon then
			local effective = self.SHAMAN.get_weave_effective_cast_time(self, entry)
			local safe_start = effective ~= nil and st.weave.get_marker_fraction(duration, effective, latency) or nil
			-- H4: an unresolvable cast time (nil effective) leaves the safe start
			-- unknown; hide the slot instead of anchoring it at nil*width or printing
			-- a fake 0.0 s cast. get_spell_position_state would read "wait" regardless.
			if safe_start == nil then
				icon:Hide()
				time:Hide()
			else
				local state = st.weave.get_spell_position_state(stacks, now_fraction, safe_start)
				count = count + 1
				starts[count] = safe_start
				local color = get_position_color(state, key)
				icon:ClearAllPoints()
				icon:SetPoint("CENTER", vf, "TOPLEFT", safe_start * w, center_y)
				-- Cached per slot: the per-tick path re-sets only what changed, so a
				-- stable swing allocates nothing (the codebase's marker discipline).
				if weave_position_icon_texture[key] ~= entry.icon then
					weave_position_icon_texture[key] = entry.icon
					icon:SetTexture(entry.icon)
				end
				icon:SetVertexColor(color[1], color[2], color[3],
					state == "ready" and WEAVE_POSITION_READY_ALPHA or color[4])
				icon:Show()
				if weave_position_time_value[key] ~= effective then
					weave_position_time_value[key] = effective
					time:SetText(string.format("%.1f", effective))
				end
				time:SetTextColor(color[1], color[2], color[3], 0.95)
				time:Show()
			end
		else
			icon:Hide()
			time:Hide()
		end
	end
	for i = count + 1, #starts do
		starts[i] = nil
	end
	local min_start, max_start = st.weave.get_cast_zone_bounds(starts)
	if min_start and max_start and max_start > min_start then
		local zone = vf.weave_pos_zone
		zone:ClearAllPoints()
		zone:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", min_start * w, WEAVE_ZONE_BOTTOM)
		zone:SetWidth((max_start - min_start) * w)
		zone:Show()
		local label = vf.weave_pos_label
		label:ClearAllPoints()
		label:SetPoint("BOTTOM", vf, "TOPLEFT", ((min_start + max_start) / 2) * w,
			WEAVE_ZONE_BOTTOM + WEAVE_ZONE_HEIGHT + WEAVE_ZONE_LABEL_GAP)
		label:Show()
	else
		vf.weave_pos_zone:Hide()
		vf.weave_pos_label:Hide()
	end
end

-- DW sync + Flurry badges (round 2): the sync badge compares the MH/OH next
-- landings against the Flurry ICD threshold and warns amber when they drift apart
-- (desync burns extra Flurry charges); the Flurry badge shows the stack count and
-- the live 0.5 s proc ICD. Option-gated (nil = off), created lazily, stacked in the
-- mainhand badge column under Rockbiter. The sync half shows only while
-- dual-wielding with both landings known; the Flurry half works for any setup.
local function update_dw_badges(self, vf, db, now)
	if db.show_shaman_dw_sync ~= true then
		if vf.weave_sync_text then vf.weave_sync_text:Hide() end
		if vf.weave_flurry_text then vf.weave_flurry_text:Hide() end
		return
	end
	if not vf.weave_sync_text then
		local sync_text = vf:CreateFontString(nil, "OVERLAY")
		sync_text:SetPoint("TOPLEFT", vf, "TOPRIGHT", 3, -28)
		sync_text:SetJustifyH("LEFT")
		sync_text:SetFont(get_tracker_font_path(self), 9, "OUTLINE")
		sync_text:Hide()
		vf.weave_sync_text = sync_text
		local flurry_text = vf:CreateFontString(nil, "OVERLAY")
		flurry_text:SetPoint("TOPLEFT", vf, "TOPRIGHT", 3, -38)
		flurry_text:SetJustifyH("LEFT")
		flurry_text:SetFont(get_tracker_font_path(self), 9, "OUTLINE")
		flurry_text:Hide()
		vf.weave_flurry_text = flurry_text
	end
	local sync_text, flurry_text = vf.weave_sync_text, vf.weave_flurry_text
	local oh = self.offhand
	local mh = self.mainhand
	local offset = st.weave.get_dw_sync_offset(mh and mh.ends_at, oh and oh.ends_at)
	if oh and oh.has_weapon and offset then
		local desynced = st.weave.is_dw_desynced(offset)
		local color = desynced and WEAVE_DESYNC_COLOR or WEAVE_SYNC_COLOR
		local readout = desynced and string.format("DW DESYNC %.1fs", offset)
			or string.format("DW SYNC %.1fs", offset)
		if self.weave_sync_readout ~= readout then
			self.weave_sync_readout = readout
			sync_text:SetText(readout)
			sync_text:SetTextColor(color[1], color[2], color[3], color[4])
		end
		sync_text:Show()
	else
		self.weave_sync_readout = nil
		sync_text:Hide()
	end
	local stacks = self.weave_flurry_stacks
	if type(stacks) == "number" and stacks >= 1 then
		local icd = st.weave.get_flurry_icd_remaining(self.weave_flurry_proc_at, now)
		local readout
		if icd and icd > 0 then
			readout = string.format("FL %d %.1fs", stacks, icd)
		else
			readout = string.format("FL %d", stacks)
		end
		if self.weave_flurry_readout ~= readout then
			self.weave_flurry_readout = readout
			flurry_text:SetText(readout)
			flurry_text:SetTextColor(WEAVE_FLURRY_COLOR[1], WEAVE_FLURRY_COLOR[2],
				WEAVE_FLURRY_COLOR[3], WEAVE_FLURRY_COLOR[4])
		end
		flurry_text:Show()
	else
		self.weave_flurry_readout = nil
		flurry_text:Hide()
	end
end

-- Offhand spark mirror: the mainhand spark's own state drawn on the offhand visuals
-- frame while the player dual-wields (reference SuperSwingTimer_ClassMods.lua:3481-3489).
-- The widget is created lazily so nothing exists before an offhand is used.
local function update_offhand_spark(self, hand)
	local vf = self:get_visuals_frame(hand)
	if not vf then return end
	local spark = vf.weave_spark_offhand
	if not spark then
		if not (self.offhand and self.offhand.has_weapon) then return end
		spark = vf:CreateTexture(nil, "OVERLAY")
		spark:SetDrawLayer("OVERLAY", -2)
		spark:SetColorTexture(1, 1, 1, 1)
		spark:Hide()
		vf.weave_spark_offhand = spark
	end
	local db = self:get_class_table()
	local d = self.mainhand
	if db.weave_enabled == false
		or db.show_shaman_breakpoint_markers == false
		or not is_weave_mw_active(db, self.weave_mw_observed)
		or not (self.offhand and self.offhand.has_weapon)
		or not (d and d.speed and d.ends_at and d.start and not d.is_full) then
		spark:Hide()
		return
	end
	local entry = self.SHAMAN.get_weave_visual_spell(self)
	if not entry then
		spark:Hide()
		return
	end
	local now = api.get_time()
	local latency = ((self.latency and self.latency.world_ms) or 0) / 1000
	local spark_fraction, clipped = get_weave_spark_display(self, d, entry, now, latency)
	if spark_fraction == nil then
		spark:Hide()
		return
	end
	local w, h = self:get_bar_visuals_width_and_height(hand)
	local spark_h = db.weave_spark_height or WEAVE_FALLBACK_SPARK_HEIGHT
	if type(h) == "number" and h > 0 and spark_h > h then
		spark_h = h
	end
	spark:SetWidth(db.weave_spark_width or WEAVE_FALLBACK_SPARK_WIDTH)
	spark:SetHeight(spark_h)
	spark:ClearAllPoints()
	spark:SetPoint("CENTER", vf, "LEFT", st.weave.clamp_fraction(spark_fraction) * w, 0)
	local color = WEAVE_RED_COLOR
	if not clipped then
		color = get_shaman_spark_color()
	end
	spark:SetVertexColor(color[1], color[2], color[3], db.weave_spark_alpha or WEAVE_FALLBACK_SPARK_ALPHA)
	spark:Show()
end

function ST.SHAMAN.on_bar_update(self, hand)
	-- Per-frame weave visuals, called from ST:onupdate_common via the generic class hook.
	-- Deliberately cheap and nil-safe. NOTE: this must NOT gate on st.is_mainline - the
	-- Forever client is Mainline-code but shows weaving - only on swing activity.
	if hand == "offhand" then
		update_offhand_spark(self, hand)
		return
	end
	if hand ~= "mainhand" then
		return
	end
	-- Next Action Guide (mainhand only): driven before the swing gates below so it also
	-- runs off-swing. Deliberately not gated on st.is_mainline - the Forever client is
	-- Mainline-code but shows the guide; swing activity decides instead (the Retail
	-- stand-in never reports a swing). Settings that rebuild the frame
	-- (scale/position/lock) are applied when the class options change; the display
	-- toggles are read live by the UI.
	local db = self:get_class_table()
	if db.nextaction_icon_size ~= self.guide_ui_icon_size
		or db.nextaction_x ~= self.guide_ui_x
		or db.nextaction_y ~= self.guide_ui_y
		or db.nextaction_locked ~= self.guide_ui_locked then
		self.guide_ui_icon_size = db.nextaction_icon_size
		self.guide_ui_x = db.nextaction_x
		self.guide_ui_y = db.nextaction_y
		self.guide_ui_locked = db.nextaction_locked
		if st.nextaction_ui then
			st.nextaction_ui.apply_settings(self)
		end
	end
	if st.nextaction_ui then
		st.nextaction_ui.on_bar_update(self, hand)
	end
	-- Cooldown HUD: retries a lockdown-deferred creation and picks layout option
	-- changes up between the HUD driver's ticks (the row itself ticks on its own
	-- driver frame, so this is cheap). Deliberately not gated on st.is_mainline:
	-- the Forever client must show the HUD, and the Retail stand-in simply never
	-- swings (the paladin hooks it the same way in classes/paladin.lua).
	if st.hud then
		st.hud.on_bar_update(self, hand)
	end
	local vf = self:get_visuals_frame(hand)
	if not vf then
		return
	end
	if not vf.weave_marker then
		self.SHAMAN.setup_weave_visuals(self)
	end
	local marker = vf.weave_marker
	if not marker then
		return
	end

	local d = self[hand]
	local now = api.get_time()
	local w, h = self:get_bar_visuals_width_and_height(hand)

	-- Trackers: each one gates on its own option and degrades when the spell/aura/API is
	-- missing, independently of the swing-activity gate below, so a shield swap, badge
	-- countdown or flame shock tick keeps updating while the swing bar is idle. The
	-- shared target-debuff scan runs first (Flame Shock + Stormstrike, throttled); the
	-- round-2 spell-position row and the DW/Flurry badges gate themselves.
	refresh_target_debuffs(self, db, now)
	update_windfury_icd(self, vf, d, db, now, h)
	update_flame_shock_bar(self, vf, db, now, w)
	update_stormstrike_bar(self, vf, db, now, w)
	update_cooldown_badges(self, vf, db, now, d)
	update_shield_charges(self, vf, db, h)
	update_wf_hold_wash(self, vf, db, now, d, w, h)
	update_rockbiter_badge(self, vf, db, now)
	update_spell_positions(self, vf, db, now, d, w)
	update_dw_badges(self, vf, db, now)

	if db.weave_enabled == false
		or not is_weave_mw_active(db, self.weave_mw_observed)
		or not (d and d.speed and d.ends_at and d.start and not d.is_full) then
		hide_weave_markers(vf)
		if vf.weave_spark then vf.weave_spark:Hide() end
		return
	end

	local entry, family = self.SHAMAN.get_weave_visual_spell(self)
	if not entry then
		hide_weave_markers(vf)
		if vf.weave_spark then vf.weave_spark:Hide() end
		return
	end

	local latency = ((self.latency and self.latency.world_ms) or 0) / 1000
	local spark_fraction, clipped, marker_fraction = get_weave_spark_display(self, d, entry, now, latency)

	-- Marker: the spell icon sits at the latest safe cast start, in the family color.
	-- H4: an unresolvable cast time makes get_marker_fraction return nil; hide the
	-- whole marker trio instead of clamping nil to 0 and drawing a false breakpoint.
	local marker_alpha = db.weave_marker_alpha or WEAVE_FALLBACK_MARKER_ALPHA
	if clipped then
		marker_alpha = marker_alpha * WEAVE_UNSAFE_ALPHA
	end
	local marker_size = db.weave_marker_size or WEAVE_FALLBACK_MARKER_SIZE
	local marker_top, marker_bottom = vf.weave_marker_top, vf.weave_marker_bottom
	if marker_fraction == nil then
		hide_weave_markers(vf)
	else
		local marker_x = st.weave.clamp_fraction(marker_fraction) * w
		marker:SetWidth(marker_size)
		marker:SetHeight(marker_size)
		if entry.icon ~= self.weave_marker_icon then
			self.weave_marker_icon = entry.icon
			if entry.icon then
				marker:SetTexture(entry.icon)
				if marker_top then marker_top:SetTexture(entry.icon) end
				if marker_bottom then marker_bottom:SetTexture(entry.icon) end
			end
		end
		marker:ClearAllPoints()
		marker:SetPoint("CENTER", vf, "LEFT", marker_x, 0)
		local family_color = st.weave.FAMILY_COLORS[family]
			or (family == "LvB" and st.weave.LAVA_BURST_COLOR)
		local r, g, b = 1, 1, 1
		if family_color then
			r, g, b = family_color[1], family_color[2], family_color[3]
		end
		marker:SetVertexColor(r, g, b, marker_alpha)
		marker:Show()

		-- Reference top/bottom breakpoint icons (SuperSwingTimer_ClassMods.lua:3491-3506):
		-- the same icon above the bar and below the bar stack, anchored at the marker
		-- fraction. The pair hides with the option or without an icon texture.
		if marker_top and marker_bottom and entry.icon and db.show_shaman_breakpoint_markers ~= false then
			local bottom_anchor, bottom_width = get_weave_bottom_anchor(self, vf, w)
			marker_top:SetWidth(marker_size)
			marker_top:SetHeight(marker_size)
			marker_top:ClearAllPoints()
			marker_top:SetPoint("BOTTOM", vf, "TOPLEFT", marker_x, WEAVE_MARKER_GAP)
			marker_top:SetVertexColor(r, g, b, marker_alpha)
			marker_top:Show()
			marker_bottom:SetWidth(marker_size)
			marker_bottom:SetHeight(marker_size)
			marker_bottom:ClearAllPoints()
			marker_bottom:SetPoint("TOP", bottom_anchor, "BOTTOMLEFT",
				st.weave.clamp_fraction(marker_fraction) * bottom_width, -WEAVE_MARKER_GAP)
			marker_bottom:SetVertexColor(r, g, b, marker_alpha)
			marker_bottom:Show()
		else
			if marker_top then marker_top:Hide() end
			if marker_bottom then marker_bottom:Hide() end
		end
	end

	-- Spark: only while a tracked cast is active.
	local spark = vf.weave_spark
	if spark and spark_fraction ~= nil then
		local spark_h = db.weave_spark_height or WEAVE_FALLBACK_SPARK_HEIGHT
		if type(h) == "number" and h > 0 and spark_h > h then
			-- Reference behaviour: the spark never outgrows the bar.
			spark_h = h
		end
		spark:SetWidth(db.weave_spark_width or WEAVE_FALLBACK_SPARK_WIDTH)
		spark:SetHeight(spark_h)
		spark:ClearAllPoints()
		spark:SetPoint("CENTER", vf, "LEFT", st.weave.clamp_fraction(spark_fraction) * w, 0)
		local color = WEAVE_RED_COLOR
		if not clipped then
			color = get_shaman_spark_color()
		end
		spark:SetVertexColor(color[1], color[2], color[3], db.weave_spark_alpha or WEAVE_FALLBACK_SPARK_ALPHA)
		spark:Show()
	elseif spark then
		spark:Hide()
	end
end

--=========================================================================================
-- Next Action Guide: the shaman provider for the generic guide frame
--=========================================================================================
-- Implements the frozen ST.<CLASS>.guide contract documented in nextaction_ui.lua's
-- header. The decision model is the pure st.shaman_guide module (shaman_guide.lua; its
-- docblock is the frozen spec), the live reads live in gather_guide_inputs, and this
-- table is the last piece of glue: the slot set, the gather/evaluate pair and the static
-- captions. Default OFF (nextaction_enabled=false in config_presets.lua): a wrong prompt
-- is worse than none, so the owner enables it after in-client verification.
--
-- SIX slots (stormstrike, flameshock, weave, firenova, earthshock, twist - the
-- contract's original six) plus the four Wrath slots (feralspirit, fireele, magma,
-- lavalash). The frame builds one icon per slot in provider order (the paladin
-- ships eight), so ten needs no contract change. Stormstrike, Flame Shock and Fire
-- Nova carry a cooldown_key:
-- the SS swipe follows the client-reported cooldown (the gather's GCD-echo rule
-- keeps a running GCD out of it), the Flame Shock swipe follows the target debuff
-- window the tracker already measures, and the Fire Nova swipe follows its 15 s
-- client cooldown. Feral Spirit and Fire Elemental carry a cooldown_key the same
-- way (known-gated: nil while the spell is unknown); Magma's swipe follows the
-- fire-slot totem window; Lava Lash carries a cooldown_key with no fallback
-- (unknown cooldown length - the client length rides while one runs). The weave
-- slot's icon comes from the resolved spell catalogue at
-- post_init (re-pointed at Lava Burst on SoD); Earth Shock and the twist skeleton
-- carry no swipe.

-- One reused input table: no per-frame allocations on the guide tick (the frame passes
-- its own reused table through gather; this one serves direct calls).
ST.SHAMAN.guide_inputs = {}

-- Live cooldown for the guide, with the client's GCD echo filtered: GetSpellCooldown
-- reports whichever cooldown ends later, so a reading of 1.51 s or less is a GCD echo
-- and never Stormstrike's own cooldown. Returns remaining seconds (>= 0) and the
-- client-reported duration, or (0, nil) when there is no real cooldown to show.
local function get_guide_cooldown(spell)
	if not spell then
		return 0, nil
	end
	local start_time, duration = api.GetSpellCooldown(spell)
	if not start_time or not duration or duration <= 1.51 then
		return 0, nil
	end
	local remaining = start_time + duration - api.get_time()
	if remaining <= 0 then
		return 0, nil
	end
	return remaining, duration
end

-- Wrath cooldown-slot feed with the known gate: remaining seconds (>= 0) and the
-- client-reported duration when the spell is known, (nil, nil) otherwise. An
-- unconfirmed id (Fire Elemental, Lava Lash) reads unknown on every client until
-- its id is confirmed in-game, so the engine rule - numeric only - never prompts
-- on a guess. Unknown families keep the same shape (nil feeds are dead).
local function get_guide_cooldown_known(spell_id)
	if not api.is_spell_known(spell_id) then
		return nil, nil
	end
	return get_guide_cooldown(spell_id)
end

-- Is the shock cooldown ready? (S4 FS-collision guard; the shock global is shared
-- by Flame Shock and Earth Shock, so the Flame Shock read answers for the refresh
-- the guard defers to.) Rank-agnostic localized-name read with the same GCD-echo
-- filter as the guide cooldowns; the name is resolved lazily and retried until the
-- spell data answers, mirroring hud_slot_name's convention. A client that cannot
-- answer reports no cooldown - the guard's shock leg then reads ready.
local weave_flameshock_query
function ST.SHAMAN.is_shock_ready()
	if weave_flameshock_query == nil then
		weave_flameshock_query = api.GetSpellInfo(WEAVE_FLAME_SHOCK_BASE_SPELL_ID) or false
	end
	local remaining = get_guide_cooldown(weave_flameshock_query or WEAVE_FLAME_SHOCK_BASE_SPELL_ID)
	return remaining <= 0
end

-- Slot descriptors: the rank-1 id ships as the fallback; resolve_guide_icons re-points
-- the weave slot at the resolved catalogue entry once the spell data is live. The
-- shock/totem slots keep their static rank-1 ids (icons are rank-invariant); the
-- twist slot is the skeleton's sixth (never lit live outside TBC - see the gather
-- stub). The four Wrath slots follow the same pattern: Feral Spirit ships its
-- verified id, the other three ship best-recall ids marked UNCONFIRMED above (a
-- wrong id stays silent through the gather's known gate).
local guide_slot_stormstrike = { key = "stormstrike", spell_id = WEAVE_STORMSTRIKE_SPELL_ID,
	cooldown_key = "stormstrike", swipe_duration = 10 }
local guide_slot_flameshock = { key = "flameshock", spell_id = 8050,
	cooldown_key = "flameshock", swipe_duration = 12 }
local guide_slot_weave = { key = "weave", spell_id = 403 }
local guide_slot_firenova = { key = "firenova", spell_id = WEAVE_FIRE_NOVA_SPELL_ID,
	cooldown_key = "firenova", swipe_duration = WEAVE_FIRE_NOVA_COOLDOWN_SECONDS }
local guide_slot_earthshock = { key = "earthshock", spell_id = WEAVE_EARTH_SHOCK_SPELL_ID }
local guide_slot_twist = { key = "twist", spell_id = WEAVE_WINDFURY_TOTEM_SPELL_ID }
local guide_slot_feralspirit = { key = "feralspirit", spell_id = WEAVE_FERAL_SPIRIT_SPELL_ID,
	cooldown_key = "feralspirit", swipe_duration = WEAVE_FERAL_SPIRIT_COOLDOWN_SECONDS }
local guide_slot_fireele = { key = "fireele", spell_id = WEAVE_FIRE_ELEMENTAL_SPELL_ID,
	cooldown_key = "fireele", swipe_duration = WEAVE_FIRE_ELEMENTAL_COOLDOWN_SECONDS }
local guide_slot_magma = { key = "magma", spell_id = WEAVE_MAGMA_TOTEM_SPELL_ID,
	cooldown_key = "magma", swipe_duration = WEAVE_MAGMA_SWIPE_SECONDS }
local guide_slot_lavalash = { key = "lavalash", spell_id = WEAVE_LAVA_LASH_SPELL_ID,
	cooldown_key = "lavalash" }

-- Resolve the weave slot's icon from the catalogue the caller just resolved; called
-- once from post_init, before the shared frame builds its icons. With no resolved
-- family the slot keeps the Lightning Bolt rank-1 fallback above.
-- SoD 5-stack spender choice (docs/research/rotations_sod.md): on ERA clients the
-- Lava Burst rune, when the client's spell data resolves it, re-points the weave
-- slot, so the MW5 prompt shows the Lava Burst icon and label instead of Lightning
-- Bolt. ERA-only: Wrath enhancement never casts Lava Burst (Elemental-only there),
-- so Wrath keeps the catalogue icon. The id comes from the shared Lava Burst cache
-- (resolve_lava_burst; the classic GetSpellInfo answers a name query with the
-- spell's id in its 7th return, so no rune spell id is guessed here); unknown reads
-- nil and keeps the catalogue (Era-base byte-identical). The player-level
-- rune/talent gate rides the assist's MW5 spender choice (get_weave_visual_spell);
-- this post_init slot shape keeps its client-data gate, pinned by its own suite.
function ST.SHAMAN.resolve_guide_icons(self)
	local entry = self.SHAMAN.get_weave_visual_spell(self)
	if entry and entry.spell_id then
		guide_slot_weave.spell_id = entry.spell_id
	end
	if st.family == "ERA" then
		local lava = self.SHAMAN.resolve_lava_burst(self)
		if lava and type(lava.spell_id) == "number" then
			guide_slot_weave.spell_id = lava.spell_id
		end
	end
end

-- Live inputs for the pure engine, written into the caller-owned reused table. Every
-- field of the frozen input set is written on every call, so no stale value can survive
-- between ticks; nil means "the client did not answer".
function ST.SHAMAN.gather_guide_inputs(self, out)
	local inputs = out or ST.SHAMAN.guide_inputs
	local now = api.get_time()
	local d = self.mainhand
	local gcd = self.gcd
	local db = self:get_class_table()

	-- Swing and GCD, in the api.get_time() domain (ends_at and the GCD stamp share it).
	inputs.speed = (d and d.speed) or 0
	inputs.swing_remaining = math.max(0, ((d and d.ends_at) or now) - now)
	inputs.gcd_remaining = (gcd and gcd.expires and math.max(0, gcd.expires - now)) or 0

	-- The cast state, the Maelstrom stacks and the catalogue readiness the rules read.
	-- (A gather before post_init finds no catalogue and simply answers unavailable.)
	-- The stack count stays truthful (the aura scan owns it); mw_available carries the
	-- family-plus-observed gate, the option kill-switch AND the S4 FS-collision guard
	-- (see the Flame Shock block below), so the engine - never the gather - decides
	-- whether MW rules may fire, from what the gather feeds. On ERA the latch is the
	-- SoD signal (observed MW aura => SoD rune client); Era-base never observes it.
	inputs.casting = self.weave_is_casting == true
	local mw_active = is_weave_mw_active(db, self.weave_mw_observed)
	inputs.mw_available = mw_active
	local stacks = self.weave_mw_stacks
	if type(stacks) ~= "number" then
		stacks = 0
	end
	inputs.mw_stacks = stacks
	local entry
	if self.weave_catalog then
		entry = self.SHAMAN.get_weave_visual_spell(self)
	end
	inputs.weave_available = (entry ~= nil) and self.weave_is_casting ~= true

	-- Flame Shock: the tracker's target-debuff window, plus the slot's swipe length.
	inputs.flameshock_remaining = nil
	inputs.flameshock_duration = nil
	if self.weave_fs_duration or self.weave_fs_expires then
		inputs.flameshock_remaining, inputs.flameshock_duration =
			st.weave.get_flame_shock_remaining(self.weave_fs_duration, self.weave_fs_expires, now)
	end

	-- S4 FS-collision guard: while the target's Flame Shock is inside its final
	-- MW5_FS_GUARD_SECONDS and the shock cooldown is ready, the five-stack weave is
	-- held back so the FS refresh goes first (bank S4: "hold weave if FS < 2s and
	-- shock ready"). The engine is frozen, so the gather - the only lever - narrows
	-- the availability it feeds; the stack count stays truthful above.
	if mw_active and st.weave.should_hold_mw5(inputs.flameshock_remaining,
		self.SHAMAN.is_shock_ready()) then
		inputs.mw_available = false
	end

	-- Stormstrike cooldown, GCD echo filtered (the rule matrix reads the remaining).
	inputs.stormstrike_remaining, inputs.stormstrike_duration =
		get_guide_cooldown(WEAVE_STORMSTRIKE_SPELL_ID)

	-- Windfury ICD for the delay-if-fishing rule: seconds from the last swing, only
	-- while the imbue is up. Nil when unknown (no swing stamp, imbue down) so the
	-- engine never holds Stormstrike on a guess.
	inputs.windfury_icd_remaining = nil
	if self.weave_windfury_active and d and type(d.start) == "number" and d.start > 0 then
		inputs.windfury_icd_remaining = st.weave.get_windfury_icd_remaining(d.start, now)
	end

	-- Fire Nova cooldown, GCD echo filtered (the rule matrix reads the remaining).
	inputs.firenova_remaining, inputs.firenova_duration =
		get_guide_cooldown(WEAVE_FIRE_NOVA_SPELL_ID)

	-- Wrath top-parse cooldowns (research docs/research/rotations_wrath.md #1-2 and
	-- #11): known-gated, so an unconfirmed id feeds nil (never prompts) on every
	-- family. TBC/Era-base never know these spells, so their feeds stay nil and the
	-- old chain runs byte-identical. Every field is still written on every call.
	inputs.fireele_remaining, inputs.fireele_duration =
		get_guide_cooldown_known(WEAVE_FIRE_ELEMENTAL_SPELL_ID)
	inputs.feralspirit_remaining, inputs.feralspirit_duration =
		get_guide_cooldown_known(WEAVE_FERAL_SPIRIT_SPELL_ID)
	inputs.lavalash_remaining, inputs.lavalash_duration =
		get_guide_cooldown_known(WEAVE_LAVA_LASH_SPELL_ID)

	-- Magma maintain (Wrath #7): WRATH-only. The stamp commits on Magma SUCCEEDED
	-- and reconciles with the fire-slot clock; an affirmatively empty fire slot
	-- feeds due (0), an unknown read feeds nil (never prompts). Every other family
	-- stays nil (byte-identical to the old stub). Every field is still written on
	-- every call, so no stale value survives.
	inputs.magma_remaining = nil
	inputs.magma_duration = nil
	if st.family == "WRATH" then
		local slot_empty = self.SHAMAN.refresh_magma_from_totems(self)
		if slot_empty then
			inputs.magma_remaining = 0
			inputs.magma_duration = WEAVE_MAGMA_SWIPE_SECONDS
		else
			inputs.magma_remaining =
				st.weave.get_magma_remaining(self.weave_magma_last_drop, now)
			if inputs.magma_remaining ~= nil then
				inputs.magma_duration = WEAVE_MAGMA_SWIPE_SECONDS
			end
		end
	end
	inputs.magma_refresh = st.shaman_guide and st.shaman_guide.MAGMA_REFRESH_DEFAULT or 3

	-- Totem twist (TBC Enhancement only): the live last-drop stamp - SUCCEEDED
	-- commits plus the air-slot totem-clock reconciliation - fed through the
	-- weave.lua timing model into the engine's rule 4. Every other family stays nil
	-- (byte-identical to the old stub); nil means unknown and the engine never
	-- prompts on a guess. Every field is still written on every call, so no stale
	-- value survives. FOREVER is excluded by the family gate (party-buff totem
	-- model: totems coexist with imbues, nothing to alternate).
	inputs.twist_remaining = nil
	if st.weave.is_totem_twist_family(st.family) then
		self.SHAMAN.refresh_twist_from_totems(self)
		inputs.twist_remaining =
			st.weave.get_totem_twist_remaining(self.weave_twist_last_drop, now)
	end

	-- The refresh threshold from the options (0-10 s, default 3).
	inputs.flameshock_refresh = db.guide_flameshock_refresh or 3
	return inputs
end

ST.SHAMAN.guide = {
	slots = { guide_slot_stormstrike, guide_slot_flameshock, guide_slot_weave,
		guide_slot_firenova, guide_slot_earthshock, guide_slot_twist,
		guide_slot_feralspirit, guide_slot_fireele, guide_slot_magma,
		guide_slot_lavalash },

	-- Live inputs: the gather above, verbatim, into the caller's reused table.
	gather = function(self, out)
		return ST.SHAMAN.gather_guide_inputs(self, out)
	end,

	-- Pure: the frozen shaman rule matrix (st.shaman_guide in shaman_guide.lua);
	-- guarded so a flavor without that module stays inert rather than erroring.
	evaluate = function(inputs, out)
		if st.shaman_guide and st.shaman_guide.evaluate then
			return st.shaman_guide.evaluate(inputs, out)
		end
		return out
	end,

	-- Static captions (defaults; the RIDE/HOLD text rides out.hold_text).
	labels = { next_action = "Next action:", hold = "HOLD", ride = "RIDE" },
}

--=========================================================================================
-- Cooldown HUD: shaman slots and the live state provider
--=========================================================================================
-- The slot set mirrors the Next Action Guide's ORIGINAL six slots (the Wrath
-- additions above have no HUD mirror yet: hud_state.lua pins the eight-slot row,
-- so the mirror waits on a lane that can update that suite - deferred), plus the
-- two trinket slots the HUD serves itself. The descriptor and provider contracts are frozen in hud.lua's header
-- comment; the "trinket" slots need no provider entry.
--
-- Rank notes: the rank-1 ids ship as the icon fallback (the spell art is
-- rank-invariant), while the provider reads cooldowns by the client's own localized
-- name (hud_slot_name), so whatever rank the player knows is what is counted - the
-- paladin's cooldown_spell-free convention from classes/paladin.lua. Stormstrike
-- (17364), Flame Shock (8050), Fire Nova Totem (1535) and Earth Shock (8042) are the
-- ids the rest of this module already reads; Lightning Bolt (403) is the weave
-- catalogue's rank-1 fallback. Windfury Totem (8512) mirrors the guide's twist slot
-- and is UNCONFIRMED on 2.5.6 (see the WEAVE_WINDFURY_TOTEM_SPELL_ID note at the top
-- of this file) - confirm with GetSpellInfo in-game before release.
ST.SHAMAN.HUD_SLOTS = {
	{ key = "stormstrike", title = "Stormstrike", kind = "spell", spell = 17364 },
	{ key = "flameshock", title = "Flame Shock", kind = "spell", spell = 8050 },
	{ key = "weave", title = "Lightning Bolt", kind = "spell", spell = 403 },
	{ key = "firenova", title = "Fire Nova Totem", kind = "spell", spell = 1535 },
	{ key = "earthshock", title = "Earth Shock", kind = "spell", spell = 8042 },
	{ key = "twist", title = "Windfury Totem", kind = "spell", spell = 8512 },
	{ key = "trinket1", title = "Trinket 1", kind = "trinket", inv_slot = 13 },
	{ key = "trinket2", title = "Trinket 2", kind = "trinket", inv_slot = 14 },
}

-- One reused state table: the HUD reads it immediately and never keeps a reference
-- (see the frozen contract in hud.lua), so there is no per-tick allocation here.
ST.SHAMAN.hud_state = {}

-- Localized HUD slot spell names, resolved lazily (name-based cooldown and probe
-- lookups are rank-agnostic). Resolved values are cached; a failed resolution (spell
-- data not ready yet) is retried on the next call, like the guide's filler names in
-- classes/paladin.lua.
local hud_slot_names = {}

local function hud_slot_name(slot)
	local name = hud_slot_names[slot.key]
	if not name then
		name = slot.spell and api.GetSpellInfo(slot.spell) or nil
		if name then
			hud_slot_names[slot.key] = name
		end
	end
	return name
end

-- Full cooldown lengths (seconds) for the swipe when the client reports no real
-- cooldown of its own (TBC values; NEEDS IN-CLIENT CONFIRMATION on 2.5.6 - the swipe
-- length only matters while a real cooldown is running, which always carries the
-- client-reported length instead). The shocks share their 6 s shock cooldown; the
-- weave cast and the twist skeleton carry 0.
local HUD_COOLDOWN_FALLBACK = {
	stormstrike = 10,
	flameshock = 6,
	weave = 0,
	firenova = 15,
	earthshock = 6,
	twist = 0,
}

-- Slots that never borrow the GCD swipe (the paladin's judgement/wings rule in
-- classes/paladin.lua). Every shaman slot is rotational, so the set is empty and
-- every ready slot shows the running GCD.
local HUD_SKIP_GCD = {}

-- The running GCD (classes/paladin.lua hud_gcd_remaining, verbatim).
local function hud_gcd_remaining(self, now)
	local g = self.gcd
	local expires = g and g.expires
	if type(expires) ~= "number" then
		return 0, 0
	end
	local remaining = expires - now
	if remaining <= 0 then
		return 0, 0
	end
	return remaining, g.spell_length or g.duration or 1.5
end

-- Remaining time and full duration of one shaman ability cooldown: the client's own
-- reading by localized name (rank-agnostic), with the GCD echo filtered (a reading
-- of 1.51 s or less is the running GCD, never one of these abilities' cooldowns -
-- the class's own get_guide_cooldown rule). A missing reading means ready.
local function hud_ability_cooldown(self, slot, now)
	local query = hud_slot_name(slot) or slot.spell
	local start_time, duration = api.GetSpellCooldown(query)
	if start_time and duration and duration > 1.51 then
		local remaining = start_time + duration - now
		if remaining > 0 then
			return remaining, duration
		end
	end
	return 0, HUD_COOLDOWN_FALLBACK[slot.key] or 0
end

-- IsUsableSpell's second return (classes/paladin.lua hud_no_mana, verbatim):
-- through compat's cross-client IsSpellUsable wrapper. A client with no probe
-- reports unknown, rendered as "no tint".
local function hud_no_mana(slot)
	local name = hud_slot_name(slot)
	local ok, _, insufficient = pcall(api.IsSpellUsable, name or slot.spell)
	return ok and insufficient == true
end

-- WA "spellInRange == 0" (classes/paladin.lua hud_out_of_range, verbatim):
-- api.IsSpellInRange returns 0 out of range, 1/true in range, nil unknown (treated
-- as "not out of range").
local function hud_out_of_range(slot)
	if not (UnitExists and UnitExists("target")) then
		return false
	end
	local name = hud_slot_name(slot)
	if not name then
		return false
	end
	return api.IsSpellInRange(name, "target") == 0
end

-- The class provider (frozen contract, hud.lua header): the paladin's ability_state
-- mapping (hud.lua:418-453) re-expressed for the shaman slots. Stormstrike glows
-- the moment it is ready, in combat (the paladin's Avenging Wrath rule).
function ST.SHAMAN.get_hud_state(self, slot, now)
	local s = ST.SHAMAN.hud_state
	s.remaining, s.duration, s.start, s.reverse = nil, nil, nil, nil
	s.text_remaining, s.desaturate, s.usable, s.in_range = nil, nil, nil, nil
	s.glow, s.count, s.texture, s.hidden = nil, nil, nil, nil
	now = now or api.get_time()
	local remaining, full = hud_ability_cooldown(self, slot, now)
	local on_cd = remaining > 0
	if on_cd then
		s.remaining = remaining
		s.duration = full
		s.text_remaining = remaining
		s.desaturate = true
	elseif not HUD_SKIP_GCD[slot.key] then
		-- The GCD shows as a swipe (WA "show GCD"); the HUD's 2 s rule keeps its
		-- text hidden.
		local g, gd = hud_gcd_remaining(self, now)
		if g > 0 then
			s.remaining, s.duration = g, gd
			s.text_remaining = g
		end
	end

	local db = self:get_class_table()
	if db.hud_mana_tint and hud_no_mana(slot) then
		s.usable = false
	end
	if db.hud_range_tint and hud_out_of_range(slot) then
		s.in_range = false
	end

	if slot.key == "stormstrike" then
		s.glow = (remaining <= 0 and self.in_combat == true) or false
	end
	return s
end

--=========================================================================================
-- Rotation text: the shaman rotation source
--=========================================================================================
-- Implements the frozen ST.<CLASS>.get_rotation_key contract documented in
-- rotationtext.lua's header, following the paladin's shape (ST.PALADIN.
-- get_rotation_key in rotationtext.lua): the guide's own decision, so the label and
-- the guide can never disagree. The shaman engine names no rotations (its
-- out.rotation_key is always nil), so the label is the current action: the
-- recommended ability's localized name (resolved from the guide's own slot
-- descriptors, cached per spell id), HOLD while the engine holds, RIDE while it
-- rides (a cast in flight), nil when the guide is idle (renders as the empty
-- text). No practice branch: Twist Practice is paladin-only (no simulation exists
-- for this class). One reused output table: no per-tick allocation on the label
-- tick. The weave math module must be present (the gather reads it); without it
-- there is no source and the label stays empty.
ST.SHAMAN.rotation_out = {}

-- The guide slot's localized spell name for an action key (the slot's current-rank
-- spell id, so a re-pointed icon re-points the label with it). Falls back to the
-- raw action key when the client's spell data has not answered yet.
local rotation_name_cache = {}

local function rotation_ability_name(action)
	local spell_id
	local slots = ST.SHAMAN.guide.slots
	for i = 1, #slots do
		if slots[i].key == action then
			spell_id = slots[i].spell_id
			break
		end
	end
	if spell_id then
		local name = rotation_name_cache[spell_id]
		if not name then
			name = api.GetSpellInfo(spell_id)
			if name then
				rotation_name_cache[spell_id] = name
			end
		end
		if name then
			return name
		end
	end
	return action
end

function ST.SHAMAN.get_rotation_key(self)
	local guide = ST.SHAMAN.guide
	local engine = st.shaman_guide
	if not (guide and guide.gather and guide.evaluate and engine and engine.evaluate) then
		return nil
	end
	if st.weave == nil then
		return nil
	end
	local out = guide.evaluate(guide.gather(self, ST.SHAMAN.guide_inputs),
		ST.SHAMAN.rotation_out)
	if out.action ~= nil then
		return rotation_ability_name(out.action)
	end
	if out.hold then
		return out.hold_text
	end
	return nil
end

if st.debug then st.utils.print_msg('-- Parsed classes/shaman.lua module correctly (weaving)') end

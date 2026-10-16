--=========================================================================================
-- Module for Shaman-specific behaviours: the Enhancement spell-weaving assist ("LB
-- weaving"), ported from the read-only reference SuperSwingTimer-WoW/
-- SuperSwingTimer_Weaving.lua (spell-catalog resolution, cast tracking, marker/spark
-- display). All swing-relative math is frozen in weave.lua; this module only gathers the
-- live inputs (haste, Maelstrom Weapon, cast events) and drives the visuals.
--
-- The assist draws two widgets on the mainhand visuals frame:
--   vf.weave_marker : the resolved spell's icon at the latest safe cast start.
--   vf.weave_spark  : the active cast, tinted red when the cast will clip the swing.
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
-- Cross-client API wrappers (see compat.lua).
local api = st.api

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
-- retried at most once per WEAVE_CATALOG_RETRY_S.
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

-- Buff haste multiplier: Bloodlust/Heroism (x1.30) and Berserking (x1.10) compound; the
-- caller then maxes the result against the spell-haste value (never multiplies it).
local function get_buff_haste_multiplier()
	local bloodlust = false
	local berserking = false
	local i = 1
	while i <= 40 do
		local name, _, _, _, _, _, _, _, _, spell_id = api.UnitAura("player", i, "HELPFUL")
		if name == nil then break end
		if not bloodlust and ((spell_id and WEAVE_BLOODLUST_IDS[spell_id]) or name == "Bloodlust" or name == "Heroism") then
			bloodlust = true
		end
		if not berserking and ((spell_id and WEAVE_BERSERKING_IDS[spell_id]) or name == "Berserking") then
			berserking = true
		end
		if bloodlust and berserking then break end
		i = i + 1
	end
	local mult = 1
	if bloodlust then mult = mult * 1.30 end
	if berserking then mult = mult * 1.10 end
	return mult
end

-- Refresh the spell-haste multiplier (cast starts and aura changes).
function ST.SHAMAN.refresh_weave_haste(self)
	self.weave_haste_mult = st.weave.get_max_haste_multiplier(
		get_spell_haste_percent(), get_buff_haste_multiplier())
end

-- Refresh the Maelstrom Weapon stack count (aura changes). An aura without a count
-- still means one stack, matching the reference's max(1, count) handling.
function ST.SHAMAN.refresh_weave_mw_stacks(self)
	local stacks = 0
	local i = 1
	while i <= 40 do
		local name, _, count, _, _, _, _, _, _, spell_id = api.UnitAura("player", i, "HELPFUL")
		if name == nil then break end
		if (spell_id and WEAVE_MW_SPELL_IDS[spell_id]) or name == WEAVE_MW_NAME then
			local n = tonumber(count) or 1
			if n > st.weave.MW_MAX_STACKS then
				n = st.weave.MW_MAX_STACKS
			elseif n < 1 then
				n = 1
			end
			stacks = n
			break
		end
		i = i + 1
	end
	self.weave_mw_stacks = stacks
end

-- Effective cast time (seconds) for a resolved spell entry, with the current haste and
-- (unless disabled in the options) the Maelstrom Weapon reduction.
function ST.SHAMAN.get_weave_effective_cast_time(self, entry)
	local mw_mult = 1
	if self:get_class_table().weave_mw_enabled ~= false then
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
-- our start stamp, so the spark keeps travelling smoothly.
local function begin_weave_cast(self, family, live_start, live_end)
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
		self.weave_cast_start_swing_fraction = st.weave.get_cast_start_fraction(now, d.start, d.speed)
	else
		self.weave_cast_start_swing_fraction = nil
	end
end

-- End the active-cast state (the last-known family is kept for the marker).
local function end_weave_cast(self)
	self.weave_is_casting = false
	self.weave_cast_start_time = nil
	self.weave_cast_end_time = nil
	self.weave_cast_start_swing_fraction = nil
	self.weave_cast_duration = nil
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
			begin_weave_cast(self, family, live_start, live_end)
		elseif event == "UNIT_SPELLCAST_DELAYED" and self.weave_is_casting and self.weave_family then
			-- Keep tracking the running cast and re-anchor its timing.
			begin_weave_cast(self, self.weave_family, live_start, live_end)
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
	end_weave_cast(self)
end

function ST.SHAMAN.on_aura_change(self)
	-- Haste buffs and Maelstrom Weapon stacks change here; both feed the marker math.
	self.SHAMAN.refresh_weave_haste(self)
	self.SHAMAN.refresh_weave_mw_stacks(self)
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
	self.weave_cast_duration = nil
	self.weave_marker_icon = nil
	self.weave_mw_stacks = 0
	self.weave_haste_mult = 1
	self.weave_catalog = {}
	self.weave_catalog_retry_at = {}

	-- Haste/Maelstrom snapshot and the initial catalogue (also parses auras, like the
	-- paladin does for seals).
	self.SHAMAN.on_aura_change(self)
	self.SHAMAN.resolve_weave_catalog(self)

	-- The mainhand visuals frame exists by now.
	self.SHAMAN.setup_weave_visuals(self)
end

--=========================================================================================
-- Visuals
--=========================================================================================
function ST.SHAMAN.setup_weave_visuals(self)
	-- Creates the weave widgets on the mainhand visuals frame (called from post_init;
	-- on_bar_update retries if the frame was not ready yet).
	local vf = self:get_visuals_frame("mainhand")
	if not vf or vf.weave_marker then
		return
	end

	-- Breakpoint marker: the resolved spell's icon, cropped like the reference.
	local marker = vf:CreateTexture(nil, "OVERLAY")
	marker:SetDrawLayer("OVERLAY", -3)
	marker:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	marker:Hide()
	vf.weave_marker = marker

	-- Cast spark: white base texture, tinted per frame.
	local spark = vf:CreateTexture(nil, "OVERLAY")
	spark:SetDrawLayer("OVERLAY", -2)
	spark:SetColorTexture(1, 1, 1, 1)
	spark:Hide()
	vf.weave_spark = spark
end

-- The family the assist should draw right now: the cast in progress, else the last
-- resolved cast, else the first enabled family with a resolved spell. Returns the catalog
-- entry and its family, or nil when nothing is drawable.
function ST.SHAMAN.get_weave_visual_spell(self)
	local families = self:get_class_table().weave_families
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

function ST.SHAMAN.on_bar_update(self, hand)
	-- Per-frame weave visuals, called from ST:onupdate_common via the generic class hook.
	-- Deliberately cheap and nil-safe. NOTE: this must NOT gate on st.is_mainline - the
	-- Forever client is Mainline-code but shows weaving - only on swing activity.
	if hand ~= "mainhand" then
		return
	end
	local vf = self:get_visuals_frame(hand)
	if not vf then
		return
	end
	if not vf.weave_marker then
		self.SHAMAN.setup_weave_visuals(self)
	end
	local marker = vf.weave_marker
	local spark = vf.weave_spark
	if not marker then
		return
	end

	local db = self:get_class_table()
	local d = self[hand]
	if db.weave_enabled == false
		or not (d and d.speed and d.ends_at and d.start and not d.is_full) then
		marker:Hide()
		if spark then spark:Hide() end
		return
	end

	local entry, family = self.SHAMAN.get_weave_visual_spell(self)
	if not entry then
		marker:Hide()
		if spark then spark:Hide() end
		return
	end

	local now = api.get_time()
	local latency = ((self.latency and self.latency.world_ms) or 0) / 1000
	local duration = d.speed
	local effective = self.SHAMAN.get_weave_effective_cast_time(self, entry)
	local marker_fraction = st.weave.get_marker_fraction(duration, effective, latency)

	-- While a cast is live the clip math uses the REMAINING cast time (the client's window
	-- end when available); when idle it estimates with a fresh cast.
	local cast_remaining = effective
	if self.weave_is_casting and self.weave_cast_start_time then
		if type(self.weave_cast_end_time) == "number" then
			cast_remaining = math.max(0, self.weave_cast_end_time - now)
		elseif self.weave_cast_duration and self.weave_cast_duration > 0 then
			cast_remaining = math.max(0, self.weave_cast_duration - (now - self.weave_cast_start_time))
		end
	end
	local clip_amount = st.weave.get_clip_amount(now, latency, cast_remaining, d.ends_at)
	local cast_start_fraction = self.weave_cast_start_swing_fraction
	local clipped = st.weave.is_clipped(clip_amount, cast_start_fraction, marker_fraction)
	local w, h = self:get_bar_visuals_width_and_height(hand)

	-- Marker: the spell icon sits at the latest safe cast start, in the family color.
	local marker_alpha = db.weave_marker_alpha or WEAVE_FALLBACK_MARKER_ALPHA
	if clipped then
		marker_alpha = marker_alpha * WEAVE_UNSAFE_ALPHA
	end
	local marker_size = db.weave_marker_size or WEAVE_FALLBACK_MARKER_SIZE
	marker:SetWidth(marker_size)
	marker:SetHeight(marker_size)
	if entry.icon ~= self.weave_marker_icon then
		self.weave_marker_icon = entry.icon
		if entry.icon then
			marker:SetTexture(entry.icon)
		end
	end
	marker:ClearAllPoints()
	marker:SetPoint("CENTER", vf, "LEFT", st.weave.clamp_fraction(marker_fraction) * w, 0)
	local family_color = st.weave.FAMILY_COLORS[family]
	if family_color then
		marker:SetVertexColor(family_color[1], family_color[2], family_color[3], marker_alpha)
	else
		marker:SetVertexColor(1, 1, 1, marker_alpha)
	end
	marker:Show()

	-- Spark: only while a tracked cast is active.
	if spark and self.weave_is_casting and self.weave_cast_start_time
		and self.weave_cast_duration and self.weave_cast_duration > 0 then
		-- Total cast window: the client's start/end pair when available, else our computed
		-- effective duration from the start anchor.
		local cast_total = self.weave_cast_duration
		if type(self.weave_cast_end_time) == "number"
			and self.weave_cast_end_time > self.weave_cast_start_time then
			cast_total = self.weave_cast_end_time - self.weave_cast_start_time
		end
		local progress = st.weave.clamp_fraction((now - self.weave_cast_start_time) / cast_total)
		local spark_fraction
		if cast_start_fraction ~= nil and duration > 0 then
			-- Travel from where the cast started toward where it is projected to land.
			local projected = st.weave.get_projected_impact_fraction(now, cast_remaining, latency, d.start, duration)
			spark_fraction = st.weave.get_spark_fraction(cast_start_fraction, projected, progress)
		else
			spark_fraction = progress
		end
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

if st.debug then st.utils.print_msg('-- Parsed classes/shaman.lua module correctly (weaving)') end

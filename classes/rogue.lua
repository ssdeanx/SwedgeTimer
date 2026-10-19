--=========================================================================================
-- Module for Rogue-specific behaviours (Round 2: cues, predictor, provider, HUD).
--
-- Evidence base: bench/rogue_readiness_2026-10-19.md (slices B/C), bench/rogue_deep_2026-10-19.md
-- (§2.1 SS-after-swing Era-CONFIRMED / TBC-refuted, §2.2 energy-tick correction, §2.3 Tea,
-- §2.5 weapon swap), bench/rogue_research_2026-10-19.md (§§1.1-1.6 rotations, §3.5 Envenom
-- per-client rules, §4 watch-list, §5.15 no remembered ids). Ids are never shipped from
-- memory (lessons: a remembered id is a rumor): every spell the HUD/guide needs is resolved
-- through the client's own GetSpellInfo by exact English name at init.
--
-- What ships here:
--   * proc-aware 2 s energy tick predictor (Yam rule: Combat Potency's 15-energy grant and
--     Relentless Strikes' 25 NEVER re-anchor; only a 20-energy gain in phase does; an
--     ambiguous tick reads nil and every consumer hides - H4/rogue_readiness §4),
--   * energy-tick spark + pooling tint on the mainhand bar (data-driven bands from
--     rogue_guide.POOL_BANDS; rogue_research §1.3: never pool above 65 pre-tick / 85
--     post-tick),
--   * Era-only post-MH-swing Sinister Strike window (0.1-0.2 s; family ERA plus a confirmed
--     sword mainhand; NEVER on TBC+ - Sno's TBC FAQ refutes swing timing there, §1),
--   * weapon-swap tint whose copy carries the GCD + swing-reset cost (families from
--     SWAP_CUE_FAMILIES; Wrath stays off per the recorded conflict, rogue_deep §5.4),
--   * MH/OH poison reminder (GetWeaponEnchantInfo presence; charges stay out until the
--     probe shape is confirmed in-client - rogue_deep §5.8),
--   * live HUD state (SnD/Rupture/EA/AR/BF/Tea/Kick; trinkets are HUD-served),
--   * live guide gather incl. the provider-owned inputs_unknown bit (M6) and the M5
--     lust-unknown latch reusing api.auras_may_be_secret(),
--   * TTD via the druid D4 EMA (st.druid_energy) with the M7 provenance rule: only this
--     module's own health-velocity estimate - never the enemy_swing 2.0 s fallback.
--
-- Deliberately NOT here: CLEU matching (no rogue id exists in the corpus - the R1 rule),
-- the spellcast lifecycle hook (nothing consumes casts; Tea/Shiv read cooldowns), and any
-- `st.is_mainline` gate (swing activity decides - the Forever client is Mainline-code but
-- must run these cues; the Retail stand-in never swings, so they stay hidden there).
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
-- Cross-client API wrappers (see compat.lua).
local api = st.api

--=========================================================================================
-- Probe globals (read once at load; every call is type/pcall-guarded)
--=========================================================================================
-- These probes are owed to compat.lua (the single crossing point); they live here because
-- this slice's scope is this file only. Each one degrades to nil (unknown) when the client
-- lacks it - never to a fabricated answer.
local c_item = rawget(_G, "C_Item")
local get_item_info = (c_item and c_item.GetItemInfo) or rawget(_G, "GetItemInfo")
local get_item_count = (c_item and c_item.GetItemCount) or rawget(_G, "GetItemCount")
local get_item_cooldown = (c_item and c_item.GetItemCooldown) or rawget(_G, "GetItemCooldown")
local get_weapon_enchant_info = rawget(_G, "GetWeaponEnchantInfo")
-- Target identity for the TTD baseline: UnitGUID exists on every supported client and is
-- read the same way classes/druid.lua reads it (compat carries no wrapper for it).
local unit_guid = rawget(_G, "UnitGUID")

--=========================================================================================
-- Constants (cited; no magic numbers at the call sites)
--=========================================================================================
-- Energy tick: 20 energy / 2 s on the classic line (rogue_research §§1.1/1.3, CONFIRMED).
ST.ROGUE.TICK_PERIOD = 2.0
ST.ROGUE.TICK_ENERGY = 20
-- A tick may be observed up to this far from its predicted landing (frame sampling plus
-- world latency). A 20-energy gain outside it cannot be told from a gear proc: it never
-- re-anchors (Yam rule) and it marks the tick ambiguous (H4).
ST.ROGUE.TICK_GAIN_TOLERANCE = 0.4
-- Known non-tick energy grants that MUST NEVER re-anchor the clock (rogue_deep §2.2):
-- Combat Potency 15 (20% chance on successful OH hits, rogue_research §1.3) and
-- Relentless Strikes 25 (finisher refund, §1.1/§1.3). They are ignored for anchoring and
-- never poison the phase; any other unclassifiable gain does (H4).
ST.ROGUE.PROC_ENERGY_GAINS = { [15] = true, [25] = true }

-- Era-only SS-after-MH window: 0.1-0.2 s after the mainhand swing lands (rogue_deep §1:
-- Sno's swing-timing guide, CONFIRMED on Classic Era; REFUTED on TBC+ - "Swing timing
-- isn't needed in TBC ... no swing timer weakaura in my updated UI"). Exact family
-- equality: never a "non-TBC" test.
ST.ROGUE.SS_WINDOW_START = 0.1
ST.ROGUE.SS_WINDOW_END = 0.2
ST.ROGUE.SS_WINDOW_FAMILY = "ERA"

-- Weapon-swap cue families. The swap-timing opportunity is the same post-MH window; the
-- cost copy is mandatory. Wrath stays OUT per the recorded conflict (rogue_deep §5.4 -
-- default to no Wrath swap cue until in-client tested); Retail has no reset mechanic to
-- time; FOREVER keeps the reset rule (forever leveling guide, rogue_deep §2.5).
ST.ROGUE.SWAP_CUE_FAMILIES = { ERA = true, TBC = true, FOREVER = true }
ST.ROGUE.SWAP_COST_TEXT = "swap: GCD + swing reset"

-- Fallback colours (0-255 RGB + 0-1 alpha; converted through ST:convert_color).
local ROGUE_ENERGY_TICK_FALLBACK_COLOR = { 255, 209, 64, 0.90 }
local ROGUE_POOL_TINT_FALLBACK_COLOR = { 255, 128, 0, 0.85 }
local ROGUE_SS_FALLBACK_COLOR = { 255, 209, 64, 0.85 }
local ROGUE_SWAP_FALLBACK_COLOR = { 89, 140, 191, 0.85 }
local ROGUE_POISON_FALLBACK_COLOR = { 214, 64, 54, 0.95 }
-- Pre-band tint alpha scale: >= post is the hard line (full alpha), >= pre with a known
-- tick is the warning (softer). rogue_research §1.3 / readiness slice B.
local ROGUE_POOL_PRE_ALPHA_SCALE = 0.55
-- HUD buff/debuff glow while inside the final seconds.
local ROGUE_HUD_GLOW_SECONDS = 3

-- Aura scan cap: the same 40-row bound as compat.scan_player_aura (R2: no early break -
-- a secret row above a tracked buff degrades to nil and must not truncate the walk).
local ROGUE_AURA_SCAN_LIMIT = 40
-- Lust canary (M5): compat's confirmed ids (2825 Horde / 32182 Alliance).
local ROGUE_LUST_IDS = { [2825] = true, [32182] = true }
local ROGUE_LUST_RESCAN = 0.5
-- Spell-data retry throttle: a cold spell book right after login (shaman catalogue-retry
-- shape - silent, throttled, no chat spam).
local ROGUE_SPELL_RETRY = 5.0

--=========================================================================================
-- Spell data (intentionally empty - see the module header)
--=========================================================================================
-- Id-keyed tables for the later CLEU-facing work (poison procs, Shiv/Overkill/Vanish
-- windows). Nothing may be added here without a bench citation: a wrong id is silent,
-- a remembered id is a rumor.
ST.ROGUE.SPELL_IDS = {}
ST.ROGUE.POISON_IDS = {}

-- Slot -> exact English spell name. Names, not ids: the running client resolves each name
-- to its own highest rank through GetSpellInfo (in-client fill, per the corpus).
local SLOT_SPELL_NAMES = {
	snd = "Slice and Dice",
	rupture = "Rupture",
	ea = "Expose Armor",
	ar = "Adrenaline Rush",
	bf = "Blade Flurry",
	tea = "Thistle Tea",
	kick = "Kick",
}
local GUIDE_SPELL_NAMES = {
	builder = "Sinister Strike",
	rupture = "Rupture",
	eviscerate = "Eviscerate",
	envenom = "Envenom",
	expose = "Expose Armor",
	shiv = "Shiv",
	tea = "Thistle Tea",
}

-- Negative-capable spell cache. A failed lookup is retried on the throttle only, so a
-- client that will never answer is probed at a bounded rate.
ST.ROGUE.spell_cache = {}

local function resolve_named_spell(key, name, now)
	local cached = ST.ROGUE.spell_cache[key]
	if type(cached) == "table" then
		return cached
	end
	if cached == false and type(now) == "number"
		and now < (ST.ROGUE.spell_retry_at or 0) then
		return nil
	end
	local ok, spell_name, _, icon, _, _, _, spell_id = pcall(api.GetSpellInfo, name)
	if not ok or type(spell_name) ~= "string" or type(spell_id) ~= "number" then
		ST.ROGUE.spell_cache[key] = false
		ST.ROGUE.spell_retry_at = (type(now) == "number" and now or 0) + ROGUE_SPELL_RETRY
		return nil
	end
	local entry = { id = spell_id, name = spell_name, icon = icon }
	ST.ROGUE.spell_cache[key] = entry
	return entry
end

-- Fills the HUD/guide slot ids from the client's spell data. Idempotent; called from
-- post_init before either consumer builds its frames, and retried from on_bar_update
-- while any slot is still unresolved (cold spell book). Returns true while pending.
function ST.ROGUE.apply_spell_ids(self)
	local now = api.get_time()
	local pending = false
	local slots = ST.ROGUE.HUD_SLOTS
	for i = 1, #slots do
		local slot = slots[i]
		if slot.spell == nil and SLOT_SPELL_NAMES[slot.key] then
			local entry = resolve_named_spell("hud:" .. slot.key, SLOT_SPELL_NAMES[slot.key], now)
			if entry then
				slot.spell = entry.id
			else
				pending = true
			end
		end
	end
	local guide_slots = ST.ROGUE.guide.slots
	for i = 1, #guide_slots do
		local slot = guide_slots[i]
		if slot.spell_id == nil and GUIDE_SPELL_NAMES[slot.key] then
			local entry = resolve_named_spell("guide:" .. slot.key, GUIDE_SPELL_NAMES[slot.key], now)
			if entry then
				slot.spell_id = entry.id
			else
				pending = true
			end
		end
	end
	ST.ROGUE.spell_pending = pending
	return pending
end

--=========================================================================================
-- Shared live-read helpers
--=========================================================================================
-- Aura lookup on one unit: returns found, remaining (nil when the aura carries no
-- expiration), duration and count. The 40-row walk never breaks early (R2): a secret row
-- reads nil and the walk continues, so absence is only reported after the whole scan.
local function find_unit_aura(unit, filter, wanted_id, wanted_name, now)
	for index = 1, ROGUE_AURA_SCAN_LIMIT do
		local name, _, count, _, duration, expiration, _, _, _, spell_id =
			api.UnitAura(unit, index, filter)
		if name ~= nil and ((wanted_id and spell_id == wanted_id)
			or (wanted_name and name == wanted_name)) then
			local remaining
			if type(expiration) == "number" then
				remaining = expiration - now
				if remaining < 0 then
					remaining = 0
				end
			end
			local stacks
			if type(count) == "number" and count > 0 then
				stacks = count
			end
			return true, remaining, (type(duration) == "number" and duration or nil), stacks
		end
	end
	return false, nil, nil, nil
end

-- Secret-regime observability (M5): cached per tick because every HUD slot asks. The
-- probe itself is compat's (nil on every classic client - the exact no-op).
local function auras_may_be_secret(self, now)
	if self.rogue_secret_at == now then
		return self.rogue_secret_value == true
	end
	local probe = api.auras_may_be_secret
	local value = false
	if type(probe) == "function" then
		value = probe() == true
	end
	self.rogue_secret_at = now
	self.rogue_secret_value = value
	return value
end

-- One ability cooldown: remaining + full duration, nil when idle. Durations at/below the
-- GCD (1.5 s) read as idle - the standard rule from the other class modules.
local function spell_cooldown(self, spell_id, now)
	if type(spell_id) ~= "number" then
		return nil
	end
	local start_time, duration = api.GetSpellCooldown(spell_id)
	if type(start_time) ~= "number" or type(duration) ~= "number" or duration <= 1.51 then
		return nil
	end
	local remaining = start_time + duration - now
	if remaining <= 0 then
		return nil
	end
	return remaining, duration
end

-- Item probes (Thistle Tea): count via GetItemCount(name), cooldown via
-- GetItemCooldown(name). Both accept an ItemInfo (name works) on every family; a client
-- without the API reports nil - unknown, never zero.
local function tea_item_count()
	if type(get_item_count) ~= "function" then
		return nil
	end
	local ok, count = pcall(get_item_count, "Thistle Tea")
	if not ok or type(count) ~= "number" then
		return nil
	end
	return count
end

local function tea_item_cooldown(now)
	if type(get_item_cooldown) ~= "function" then
		return nil
	end
	local ok, start_time, duration = pcall(get_item_cooldown, "Thistle Tea")
	if not ok or type(start_time) ~= "number" or type(duration) ~= "number"
		or duration <= 0 then
		return nil
	end
	local remaining = start_time + duration - now
	if remaining <= 0 then
		return nil
	end
	return remaining, duration
end

-- Mainhand item subclass ("Sword", ...), nil when the client cannot answer. Handles both
-- GetItemInfo shapes: the classic multi-return and C_Item's info table.
local function item_subclass(item_id)
	if type(item_id) ~= "number" or type(get_item_info) ~= "function" then
		return nil
	end
	local ok, name, _, _, _, _, class, subclass = pcall(get_item_info, item_id)
	if not ok then
		return nil
	end
	if type(name) == "table" then
		return name.itemSubType
	end
	if type(class) ~= "string" then
		return nil
	end
	return subclass
end

-- Bar geometry (width/height) from bars.lua, nil-safe for a caller without the helper.
local function bar_geometry(self)
	if type(self.get_bar_visuals_width_and_height) ~= "function" then
		return nil, nil
	end
	return self:get_bar_visuals_width_and_height("mainhand")
end

--=========================================================================================
-- Energy tick predictor (proc-aware; Yam rule + H4)
--=========================================================================================
-- State on the module instance:
--   rogue_tick_anchor   the last observed natural tick (nil = no trustworthy phase)
--   rogue_tick_prev/at  the previous energy sample (delta evidence)
--   rogue_tick_unknown  latched ambiguity - hides the spark until a fresh in-phase tick
-- Returns the seconds to the next tick, or nil when the phase is unknown (H4: an
-- ambiguous tick is hidden, never guessed).
function ST.ROGUE.update_energy_tick(self, now, energy, max_energy)
	local period = ST.ROGUE.TICK_PERIOD
	local tolerance = ST.ROGUE.TICK_GAIN_TOLERANCE
	if type(now) ~= "number" or type(energy) ~= "number" then
		-- An unreadable clock or pool: drop every baseline; nothing may ride a stale phase.
		self.rogue_tick_prev, self.rogue_tick_at = nil, nil
		self.rogue_tick_anchor = nil
		self.rogue_tick_unknown = true
		return nil
	end
	local prev, prev_at = self.rogue_tick_prev, self.rogue_tick_at
	self.rogue_tick_prev, self.rogue_tick_at = energy, now
	if type(prev) == "number" and type(prev_at) == "number" then
		if now < prev_at then
			-- A backwards clock: every stamp is suspect.
			self.rogue_tick_anchor = nil
			self.rogue_tick_unknown = true
		else
			local delta = energy - prev
			if delta == ST.ROGUE.TICK_ENERGY then
				local expected
				if type(self.rogue_tick_anchor) == "number" then
					expected = self.rogue_tick_anchor + period
				end
				if expected == nil or math.abs(now - expected) <= tolerance then
					-- A natural tick in phase (or the first observed gain after
					-- enabling). Only this evidence re-anchors the cycle.
					self.rogue_tick_anchor = now
					self.rogue_tick_unknown = false
				else
					-- A 20-energy gain outside the phase: a gear proc or a drifted
					-- clock - the two cannot be told apart, so the reading goes
					-- unknown (H4). The old anchor is kept only so a later in-phase
					-- tick can recover it.
					self.rogue_tick_unknown = true
				end
			elseif delta > 0 and not ST.ROGUE.PROC_ENERGY_GAINS[delta] then
				-- An unrecognised grant could have hidden a tick inside the sampling
				-- gap: the phase is no longer trustworthy.
				self.rogue_tick_unknown = true
			end
			-- delta <= 0 (spends/idle) and the known proc grants (15/25) never move
			-- the phase: a spend cannot re-anchor a tick, and Combat Potency /
			-- Relentless Strikes MUST NOT re-anchor (rogue_deep §2.2 Yam rule).
		end
	end
	local anchor = self.rogue_tick_anchor
	if type(anchor) ~= "number" then
		self.rogue_tick_unknown = true
		return nil
	end
	local expected = anchor + period
	if now > expected + tolerance then
		if type(max_energy) == "number" and energy >= max_energy then
			-- At the cap no gain is observable, but ticks still land - advance the
			-- phase over the elapsed boundaries instead of resetting it. The phase
			-- was observed, so this is arithmetic, not a guess.
			local skipped = math.floor((now - anchor) / period)
			if skipped < 1 then
				skipped = 1
			end
			anchor = anchor + skipped * period
			self.rogue_tick_anchor = anchor
			expected = anchor + period
		else
			-- The predicted tick came and went with no gain to prove it (bar hidden,
			-- a spend masked it, or the clock jumped): ambiguous -> hide.
			self.rogue_tick_anchor = nil
			self.rogue_tick_unknown = true
			return nil
		end
	end
	if self.rogue_tick_unknown then
		return nil
	end
	local tick_in = expected - now
	if tick_in < 0 then
		tick_in = 0
	end
	return tick_in
end

-- One live sample: reads the energy pool and its cap, feeds the predictor and stores the
-- result for the visuals/gather. Both the guide gather and the per-frame visuals call
-- this; a second call in the same frame sees a zero delta and is a no-op for the phase.
function ST.ROGUE.sample_energy_tick(self, now)
	local energy = api.UnitPower("player", 3)
	local max_energy = api.UnitPowerMax("player", 3)
	if type(energy) ~= "number" then
		energy = nil
	end
	if type(max_energy) ~= "number" or max_energy <= 0 then
		max_energy = nil
	end
	self.rogue_energy_now = energy
	self.rogue_energy_max = max_energy
	self.rogue_tick_in = ST.ROGUE.update_energy_tick(self, now, energy, max_energy)
	return self.rogue_tick_in
end

--=========================================================================================
-- Time-to-die: druid D4 EMA reuse, own tracker only (M7 provenance)
--=========================================================================================
-- The only accepted provenance is this module's own EMA-smoothed HP/s estimate over the
-- live target (same maths as classes/druid.lua's D4 sampler, via st.druid_energy). The
-- enemy_swing 2.0 s fallback is display fiction (rogue_readiness §4 / fix-engine M7) and
-- must never feed Rupture-vs-Eviscerate - there is deliberately no code path that reads it.
ST.ROGUE.TTD_PROVENANCE = "own-ema"

function ST.ROGUE.get_time_to_die(self, now)
	local de = st.druid_energy
	if type(de) ~= "table" or type(now) ~= "number" then
		return nil
	end
	local guid
	if type(unit_guid) == "function" then
		local ok, value = pcall(unit_guid, "target")
		if ok then
			guid = value
		end
	end
	if type(guid) ~= "string" then
		-- No target (or a client that cannot answer its identity): drop the baseline.
		self.rogue_ttd_guid = nil
		self.rogue_ttd_hp = nil
		self.rogue_ttd_at = nil
		self.rogue_ttd_velocity = nil
		return nil
	end
	if guid ~= self.rogue_ttd_guid then
		-- A different target: the old baseline is meaningless.
		self.rogue_ttd_guid = guid
		self.rogue_ttd_hp = nil
		self.rogue_ttd_at = nil
		self.rogue_ttd_velocity = nil
	end
	local hp = api.UnitHealth("target")
	if type(hp) ~= "number" or hp <= 0 then
		-- Unreadable (a secret value degrades to nil in compat) or dead: no estimate,
		-- and the baseline drops so a revived/repulled target cannot diff against
		-- pre-death health.
		self.rogue_ttd_hp = nil
		self.rogue_ttd_at = nil
		return nil
	end
	local at = self.rogue_ttd_at
	if type(at) ~= "number" then
		-- First sample for this target: seed the baseline, no estimate yet.
		self.rogue_ttd_at = now
		self.rogue_ttd_hp = hp
		return nil
	end
	if now - at < de.TTD_SAMPLE_SECONDS then
		-- Too soon for a new sample: keep the stored one and ride the current EMA.
		return de.get_time_to_die(hp, self.rogue_ttd_velocity)
	end
	local prev_hp = self.rogue_ttd_hp
	self.rogue_ttd_at = now
	self.rogue_ttd_hp = hp
	self.rogue_ttd_velocity = de.update_hp_velocity(
		self.rogue_ttd_velocity, hp, prev_hp, now - at)
	return de.get_time_to_die(hp, self.rogue_ttd_velocity)
end

--=========================================================================================
-- Lust-unknown latch (M5; the paladin consumer's shape)
--=========================================================================================
-- A miss under a secret-aura regime is not an honest "no lust": compat's observability
-- probe answers whether restricted aura rows can be hidden right now (nil on every
-- classic client), and when it is explicitly true the reading is marked unknown. For the
-- rogue the same regime can hide SnD/Rupture/EA/stack rows, so the latch both documents
-- the unknown and feeds the guide's provider-owned inputs_unknown bit.
function ST.ROGUE.update_lust_state(self, now)
	if type(now) ~= "number" then
		self.rogue_lust_at = nil
		self.rogue_lust_remaining = nil
		self.rogue_lust_unknown = true
		return nil
	end
	if type(self.rogue_lust_at) == "number" and now - self.rogue_lust_at < ROGUE_LUST_RESCAN then
		return self.rogue_lust_remaining
	end
	self.rogue_lust_at = now
	self.rogue_lust_remaining = nil
	if st.lust_supported == true then
		local remaining = api.scan_player_aura(function(spell_id)
			return spell_id ~= nil and ROGUE_LUST_IDS[spell_id] == true
		end)
		if type(remaining) == "number" and remaining > 0 then
			self.rogue_lust_remaining = remaining
		end
	end
	local probe = api.auras_may_be_secret
	self.rogue_lust_unknown = st.lust_supported == true and self.rogue_lust_remaining == nil
		and type(probe) == "function" and probe() == true
	return self.rogue_lust_remaining
end

--=========================================================================================
-- Next Action Guide: provider (frozen contract in nextaction_ui.lua's header)
--=========================================================================================
-- The slot keys match the action names the pure rogue engine emits (builder, rupture,
-- eviscerate, envenom, expose, shiv, tea). spell_id is filled from the client's own spell
-- data by apply_spell_ids before the frame builds its icons.
ST.ROGUE.guide = {
	slots = {
		{ key = "builder" },
		{ key = "rupture" },
		{ key = "eviscerate" },
		{ key = "envenom" },
		{ key = "expose" },
		{ key = "shiv" },
		{ key = "tea" },
	},

	-- Live inputs: the caller-owned reused table (or the module's own), no allocation.
	gather = function(self, out)
		return ST.ROGUE.gather_guide_inputs(self, out)
	end,

	-- Pure display mapping: every frozen out field is written on every tick because the
	-- table is reused. The provider owns the unknown bit (M6): the engine's verdict is
	-- threaded through, and an explicit inputs_unknown suppresses all advice - POOL and
	-- NOW both come from the labels/engine text, never from a guess.
	evaluate = function(inputs, out)
		if type(out) ~= "table" then
			out = {}
		end
		local raw = ST.ROGUE.guide_raw
		if not raw then
			raw = {}
			ST.ROGUE.guide_raw = raw
		end
		local engine = st.rogue_guide
		if engine and engine.evaluate then
			engine.evaluate(inputs, raw)
		else
			raw.action = nil
			raw.hold = false
			raw.hold_text = nil
			raw.unknown = true
		end
		local unknown = raw.unknown == true
			or (type(inputs) == "table" and inputs.inputs_unknown == true)
		out.action = unknown and nil or raw.action
		out.hold = false
		out.hold_text = nil
		out.riding = nil
		out.filler_slot = nil
		out.judge_slot = nil
		out.rotation_key = nil
		out.waiting_judgement = false
		if not unknown then
			-- POOL/NOW: the engine's explicit hold text ("POOL") wins; an action
			-- icon carries the ride overlay (the labels' "NOW") instead.
			out.hold = raw.action ~= nil or raw.hold == true
			out.hold_text = raw.hold_text
			out.riding = raw.action ~= nil and true or nil
		end
		out.inputs_unknown = unknown
		return out
	end,

	-- Static captions: the rogue's pool/spend vocabulary. The explicit hold_text
	-- ("POOL") takes precedence once the engine sets it; the ride label covers the
	-- action icons.
	labels = { next_action = "Next action:", hold = "POOL", ride = "NOW" },
}

-- One reused input table: no per-frame allocations on the guide tick.
ST.ROGUE.guide_inputs = {}

function ST.ROGUE.gather_guide_inputs(self, out)
	local rg = st.rogue_guide
	local inputs = out or ST.ROGUE.guide_inputs
	local now = api.get_time()
	local db = self:get_class_table()

	-- Energy, cap and combo points: the classic-line rogue powers (3 = energy,
	-- 4 = combo points). An unreadable pool stays nil and the engine's unknown rule
	-- fires - never a defaulted value.
	local energy = api.UnitPower("player", 3)
	inputs.energy_now = type(energy) == "number" and energy or nil
	local max_energy = api.UnitPowerMax("player", 3)
	inputs.max_energy = (type(max_energy) == "number" and max_energy > 0) and max_energy or nil
	local cp = api.UnitPower("player", 4)
	inputs.cp = type(cp) == "number" and cp or nil

	-- The proc-aware tick predictor feeds the pooling band ("finisher before the tick
	-- that would cap you"); nil = unknown, and the band predicate then pools silently.
	inputs.energy_tick_in = ST.ROGUE.sample_energy_tick(self, now)
	inputs.family = st.family

	-- Optional tunables (nil = the pure engine's documented defaults; the options
	-- pass owns the widgets - no default-visible change ships here).
	inputs.pool_pre = db.rogue_pool_band_pre
	inputs.pool_post = db.rogue_pool_band_post
	inputs.rupture_refresh = db.rogue_rupture_refresh
	inputs.rupture_min_ttd = db.rogue_rupture_min_ttd
	inputs.finisher_min_cp = db.rogue_finisher_min_cp
	inputs.ea_refresh = db.rogue_ea_refresh
	inputs.shiv_refresh = db.rogue_shiv_refresh
	inputs.tea_energy_max = db.rogue_tea_energy_max

	-- TTD: the own-EMA estimate only (M7). nil = unknown; the engine never guesses a
	-- finisher off it.
	inputs.ttd = ST.ROGUE.get_time_to_die(self, now)

	-- Rupture / Expose Armor: target debuffs.
	local rupture_entry = resolve_named_spell("guide:rupture", GUIDE_SPELL_NAMES.rupture, now)
	local rupture_found, rupture_remains = false, nil
	if rupture_entry then
		rupture_found, rupture_remains = find_unit_aura("target", "HARMFUL",
			rupture_entry.id, rupture_entry.name, now)
	end
	inputs.rupture_remains = rupture_found and (rupture_remains or 0) or nil

	local ea_entry = resolve_named_spell("target:ea", "Expose Armor", now)
	local ea_found, ea_remains = false, nil
	if ea_entry then
		ea_found, ea_remains = find_unit_aura("target", "HARMFUL",
			ea_entry.id, ea_entry.name, now)
	end
	inputs.ea_duty = db.rogue_ea_duty == true
	inputs.ea_remains = ea_found and (ea_remains or 0) or nil

	-- Deadly Poison stacks + falloff clock (the Shiv upkeep input) and the Envenom
	-- buff (Wrath sin only; nil elsewhere is the honest reading).
	local deadly_entry = resolve_named_spell("target:deadly", "Deadly Poison", now)
	local deadly_found, deadly_remains, deadly_stacks = false, nil, nil
	if deadly_entry then
		deadly_found, deadly_remains, _, deadly_stacks = find_unit_aura("target", "HARMFUL",
			deadly_entry.id, deadly_entry.name, now)
	end
	inputs.deadly_stacks = deadly_found and deadly_stacks or nil
	inputs.deadly_remaining = deadly_found and (deadly_remains or 0) or nil

	local envenom_entry = resolve_named_spell("player:envenom", "Envenom", now)
	local envenom_found, envenom_remains = false, nil
	if envenom_entry then
		envenom_found, envenom_remains = find_unit_aura("player", "HELPFUL",
			envenom_entry.id, envenom_entry.name, now)
	end
	inputs.envenom_buff_remains = envenom_found and (envenom_remains or 0) or nil

	-- Shiv usability: known, not on cooldown, not resource-locked.
	local shiv_entry = resolve_named_spell("guide:shiv", GUIDE_SPELL_NAMES.shiv, now)
	inputs.shiv_ready = nil
	if shiv_entry then
		local usable = api.IsSpellUsable(shiv_entry.id)
		inputs.shiv_ready = api.is_spell_known(shiv_entry.id)
			and usable ~= false
			and spell_cooldown(self, shiv_entry.id, now) == nil
			and true or nil
	end

	-- Thistle Tea readiness: count (when the client answers) and cooldown. The count
	-- probe shape is UNCONFIRMED in-client (rogue_deep §5.8) - it is used defensively
	-- only: an answered zero withholds, an absent probe leaves usability to the spell.
	local tea_entry = resolve_named_spell("guide:tea", GUIDE_SPELL_NAMES.tea, now)
	inputs.tea_ready = nil
	if tea_entry then
		local tea_cd = tea_item_cooldown(now)
		if tea_cd == nil then
			tea_cd = spell_cooldown(self, tea_entry.id, now)
		end
		local count = tea_item_count()
		local usable = api.IsSpellUsable(tea_entry.id)
		inputs.tea_ready = api.is_spell_known(tea_entry.id)
			and usable ~= false
			and count ~= 0
			and tea_cd == nil
			and true or nil
	end

	-- M5/M6: the provider owns the unknown bit. Core reads (energy/CP) unusable mean
	-- no advice; the lust canary marks the whole aura regime unreadable under secrecy
	-- (the same rows that hide lust also hide SnD/Rupture/EA/stacks - no advice beats
	-- wrong advice).
	ST.ROGUE.update_lust_state(self, now)
	inputs.lust_active = self.rogue_lust_remaining ~= nil and true or nil
	inputs.lust_unknown = self.rogue_lust_unknown == true
	inputs.inputs_unknown = type(energy) ~= "number" or type(cp) ~= "number"
		or self.rogue_lust_unknown == true
	if rg == nil then
		inputs.inputs_unknown = true
	end
	return inputs
end

--=========================================================================================
-- Cooldown HUD: slots and the frozen state provider (hud.lua's header)
--=========================================================================================
-- The slot set follows the rogue teardown (rogue_deep §3): Slice and Dice, Rupture,
-- Expose Armor duty, Adrenaline Rush, Blade Flurry, Thistle Tea, Kick and the two trinket
-- slots the HUD serves itself. The spell slots carry no remembered ids: the ids are
-- resolved from the client's spell data (apply_spell_ids) before the HUD builds; a slot
-- whose spell cannot be resolved stays skipped by hud.lua's validation.
ST.ROGUE.HUD_SLOTS = {
	{ key = "snd", title = "Slice and Dice", kind = "spell" },
	{ key = "rupture", title = "Rupture", kind = "spell" },
	{ key = "ea", title = "Expose Armor", kind = "spell" },
	{ key = "ar", title = "Adrenaline Rush", kind = "spell" },
	{ key = "bf", title = "Blade Flurry", kind = "spell" },
	{ key = "tea", title = "Thistle Tea", kind = "spell" },
	{ key = "kick", title = "Kick", kind = "spell" },
	{ key = "trinket1", title = "Trinket 1", kind = "trinket", inv_slot = 13 },
	{ key = "trinket2", title = "Trinket 2", kind = "trinket", inv_slot = 14 },
}

-- One reused state table: the HUD reads it immediately and never keeps a reference
-- (frozen contract), so this allocates nothing per tick.
ST.ROGUE.hud_state = {}

local function hud_clear_state(s)
	-- Every contract field is cleared on every call: nil means "not reported", and a
	-- reused table must never leak the previous slot's/tick's value.
	s.remaining, s.duration, s.start, s.reverse = nil, nil, nil, nil
	s.text_remaining, s.desaturate, s.usable, s.in_range = nil, nil, nil, nil
	s.glow, s.count, s.texture, s.hidden = nil, nil, nil, nil
end

-- Aura-backed slot (player buff or target debuff): an active aura wins; a genuinely
-- absent one greys the icon; an absent reading under the secret regime is unknown
-- (hidden), never "missing".
local function hud_aura_state(s, self, entry, unit, filter, now)
	local found, remaining, duration = find_unit_aura(unit, filter, entry.id, entry.name, now)
	if not found then
		if auras_may_be_secret(self, now) then
			s.hidden = true
			return s
		end
		s.remaining = 0
		s.desaturate = true
		return s
	end
	s.remaining = remaining
	s.duration = duration
	if type(remaining) == "number" and remaining <= ROGUE_HUD_GLOW_SECONDS then
		s.glow = true
	end
	return s
end

-- Ability-cooldown slot: swipe + countdown while running, greyed; the provider reports
-- usability so the HUD's resource tint can fire (rogue energy backs Kick, say).
local function hud_cooldown_state(s, self, entry, now)
	local remaining, duration = spell_cooldown(self, entry.id, now)
	if remaining then
		s.remaining, s.duration = remaining, duration
		s.text_remaining = remaining
		s.desaturate = true
	else
		s.remaining = 0
	end
	local usable = api.IsSpellUsable(entry.id)
	if usable == false then
		s.usable = false
	end
	return s
end

function ST.ROGUE.get_hud_state(self, slot, now)
	local s = ST.ROGUE.hud_state
	hud_clear_state(s)
	now = now or api.get_time()
	if type(now) ~= "number" or type(slot) ~= "table" or type(slot.key) ~= "string" then
		-- A client that cannot answer the clock hides the slot instead of drawing an
		-- unstamped icon.
		s.hidden = true
		return s
	end
	local key = slot.key
	if key == "snd" or key == "ar" or key == "bf" then
		local entry = ST.ROGUE.spell_cache["hud:" .. key]
		if not entry then
			s.hidden = true
			return s
		end
		if key == "snd" then
			return hud_aura_state(s, self, entry, "player", "HELPFUL", now)
		end
		-- Adrenaline Rush / Blade Flurry: the buff window outranks the ability
		-- cooldown (the teardown's buff tracker shape); while on cooldown the icon
		-- swipes and greys.
		local found, remaining, duration = find_unit_aura("player", "HELPFUL",
			entry.id, entry.name, now)
		if found then
			s.remaining = remaining
			s.duration = duration
			return s
		end
		if auras_may_be_secret(self, now) then
			s.hidden = true
			return s
		end
		return hud_cooldown_state(s, self, entry, now)
	end
	if key == "rupture" or key == "ea" then
		local entry = ST.ROGUE.spell_cache["hud:" .. key]
		if not entry then
			s.hidden = true
			return s
		end
		return hud_aura_state(s, self, entry, "target", "HARMFUL", now)
	end
	if key == "tea" then
		local entry = ST.ROGUE.spell_cache["hud:tea"]
		if not entry then
			s.hidden = true
			return s
		end
		local remaining, duration = tea_item_cooldown(now)
		if remaining then
			s.remaining, s.duration = remaining, duration
			s.text_remaining = remaining
			s.desaturate = true
		else
			local spell_remaining
			spell_remaining, duration = spell_cooldown(self, entry.id, now)
			if spell_remaining then
				s.remaining, s.duration = spell_remaining, duration
				s.text_remaining = spell_remaining
				s.desaturate = true
			else
				s.remaining = 0
			end
		end
		-- Charges probe shape UNCONFIRMED in-client (rogue_deep §5.8): the count is
		-- read defensively - an answered zero greys the icon, an absent probe stays
		-- silent (never a fabricated count, never a fabricated availability).
		local count = tea_item_count()
		if count ~= nil then
			s.count = count
			if count <= 0 then
				s.desaturate = true
				s.usable = false
			end
		end
		return s
	end
	if key == "kick" then
		local entry = ST.ROGUE.spell_cache["hud:kick"]
		if not entry then
			s.hidden = true
			return s
		end
		hud_cooldown_state(s, self, entry, now)
		local in_range = api.IsSpellInRange(entry.name, "target")
		if in_range == false then
			s.in_range = false
		end
		return s
	end
	-- Unknown keys (and the trinket slots the HUD serves itself): the cleared table.
	return s
end

--=========================================================================================
-- Per-frame visuals: tick spark, pooling tint, Era SS window, swap tint, poison reminder
--=========================================================================================
-- The mainhand visuals frame (bars.lua's frame) carries every rogue widget. They are
-- thin textures/texts rather than frames, like the shaman/druid tracker widgets.
function ST.ROGUE.setup_rogue_visuals(self)
	local vf = self.get_visuals_frame and self:get_visuals_frame("mainhand")
	if not vf then
		return false
	end
	if not vf.rogue_tick_spark then
		-- Tick spark: a 2 px line moving left-to-right across the bar over the 2 s
		-- energy cycle; it hides (never guesses) when the phase is unknown.
		local spark = vf:CreateTexture(nil, "OVERLAY")
		spark:SetDrawLayer("OVERLAY", -1)
		spark:SetColorTexture(1, 1, 1, 1)
		spark:SetWidth(2)
		spark:Hide()
		vf.rogue_tick_spark = spark

		-- Pooling wash: a full-bar tint while the live energy sits in the band
		-- (>= pre with a known tick, full alpha at >= post).
		local wash = vf:CreateTexture(nil, "OVERLAY")
		wash:SetDrawLayer("OVERLAY", -3)
		wash:SetColorTexture(1, 1, 1, 1)
		wash:SetAllPoints(vf)
		wash:Hide()
		vf.rogue_pool_wash = wash

		-- Era SS window band + caption; the weapon-swap band shares the geometry but
		-- carries its own colour and the GCD+reset copy.
		local band = vf:CreateTexture(nil, "OVERLAY")
		band:SetDrawLayer("OVERLAY", -1)
		band:SetColorTexture(1, 1, 1, 1)
		band:Hide()
		vf.rogue_ss_band = band

		local ss_text = vf:CreateFontString(nil, "OVERLAY")
		ss_text:SetPoint("BOTTOM", vf, "TOP", 0, 2)
		ss_text:SetJustifyH("CENTER")
		ss_text:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
		ss_text:SetText("SS")
		ss_text:Hide()
		vf.rogue_ss_text = ss_text

		local swap_band = vf:CreateTexture(nil, "OVERLAY")
		swap_band:SetDrawLayer("OVERLAY", -1)
		swap_band:SetColorTexture(1, 1, 1, 1)
		swap_band:Hide()
		vf.rogue_swap_band = swap_band

		local swap_text = vf:CreateFontString(nil, "OVERLAY")
		swap_text:SetPoint("BOTTOM", vf, "TOP", 0, 2)
		swap_text:SetJustifyH("CENTER")
		swap_text:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
		swap_text:SetText(ST.ROGUE.SWAP_COST_TEXT)
		swap_text:Hide()
		vf.rogue_swap_text = swap_text

		-- Poison reminder: one line under the bar; only presence is reported (the
		-- charge probe shape is UNCONFIRMED in-client).
		local poison_text = vf:CreateFontString(nil, "OVERLAY")
		poison_text:SetPoint("TOP", vf, "BOTTOM", 0, -2)
		poison_text:SetJustifyH("CENTER")
		poison_text:SetFont(STANDARD_TEXT_FONT, 9, "OUTLINE")
		poison_text:Hide()
		vf.rogue_poison_text = poison_text
	end
	return true
end

-- The Era SS window gate: exact family equality plus a confirmed sword mainhand. A
-- weapon the client cannot identify reads nil -> hidden (never a guessed loadout).
local function ss_window_loadout()
	if st.family ~= ST.ROGUE.SS_WINDOW_FAMILY then
		return false
	end
	local item_id = api.GetInventoryItemID(16)
	local subclass = item_subclass(item_id)
	if type(subclass) ~= "string" then
		return nil
	end
	return subclass == "Sword"
end

-- The post-MH window: true while the mainhand swing landed inside
-- [SS_WINDOW_START, SS_WINDOW_END] seconds ago. Unknown swing shape reads false.
local function in_post_mh_window(self, now)
	local d = self.mainhand
	if type(d) ~= "table" or d.engine_dead or d.is_full then
		return false
	end
	if type(d.start) ~= "number" or type(d.speed) ~= "number" or d.speed <= 0 then
		return false
	end
	local since = now - d.start
	if since < ST.ROGUE.SS_WINDOW_START or since > ST.ROGUE.SS_WINDOW_END then
		return false
	end
	if type(d.ends_at) == "number" and now > d.ends_at then
		return false
	end
	return true
end

-- The MH/OH poison reminder text, or nil when unknown/nothing to report. Charges are
-- deliberately absent (the probe shape is UNCONFIRMED, rogue_deep §5.8): only the
-- presence booleans are consumed, and a non-boolean reading never claims "no poison".
local function poison_reminder_text()
	if type(get_weapon_enchant_info) ~= "function" then
		return nil
	end
	local ok, has_mh, _, _, has_oh = pcall(get_weapon_enchant_info)
	if not ok or type(has_mh) ~= "boolean" or type(has_oh) ~= "boolean" then
		return nil
	end
	local mh_item = api.GetInventoryItemID(16)
	local oh_item = api.GetInventoryItemID(17)
	local missing_mh = type(mh_item) == "number" and not has_mh
	local missing_oh = type(oh_item) == "number" and not has_oh
	if missing_mh and missing_oh then
		return "no poison: MH + OH"
	end
	if missing_mh then
		return "no poison: MH"
	end
	if missing_oh then
		return "no poison: OH"
	end
	return nil
end

-- One position/size pass for a band texture on the mainhand bar.
local function draw_window_band(band, vf, width, height, x)
	band:ClearAllPoints()
	band:SetPoint("BOTTOMLEFT", vf, "BOTTOMLEFT", x, 0)
	band:SetWidth(math.max(2, width))
	band:SetHeight(height)
	band:Show()
end

function ST.ROGUE.update_rogue_visuals(self)
	local vf = self.get_visuals_frame and self:get_visuals_frame("mainhand")
	if not vf or not vf.rogue_tick_spark then
		return
	end
	local db = self:get_class_table()
	local now = api.get_time()
	if type(now) ~= "number" then
		return
	end
	local want_tick = db.show_rogue_energy_tick == true
	local want_pool = db.show_rogue_pool_tint == true
	local want_ss = db.show_rogue_ss_window == true
	local want_swap = db.show_rogue_swap_cue == true
	local want_poison = db.show_rogue_poison_cue == true

	-- One live sample serves the spark and the wash (and nothing is read when both are
	-- off - an all-off configuration costs no power reads at all).
	if want_tick or want_pool then
		ST.ROGUE.sample_energy_tick(self, now)
	end
	local w, h = bar_geometry(self)

	-- Tick spark -----------------------------------------------------------------------
	local spark = vf.rogue_tick_spark
	if not want_tick then
		spark:Hide()
	else
		local tick_in = self.rogue_tick_in
		if type(tick_in) ~= "number" or type(w) ~= "number" or w <= 0
			or type(h) ~= "number" or h <= 0 then
			-- An unknown tick hides the spark (H4) - never a guessed position.
			spark:Hide()
		else
			local fraction = 1 - (tick_in / ST.ROGUE.TICK_PERIOD)
			if fraction < 0 then
				fraction = 0
			elseif fraction > 1 then
				fraction = 1
			end
			local colour = db.rogue_energy_tick_color or ROGUE_ENERGY_TICK_FALLBACK_COLOR
			if self.rogue_energy_color_applied ~= colour then
				self.rogue_energy_color_applied = colour
				spark:SetVertexColor(self:convert_color(colour))
			end
			spark:ClearAllPoints()
			spark:SetPoint("BOTTOMLEFT", vf, "BOTTOMLEFT", fraction * w, 0)
			spark:SetHeight(h)
			spark:Show()
		end
	end

	-- Pooling tint ---------------------------------------------------------------------
	local wash = vf.rogue_pool_wash
	if not want_pool then
		wash:Hide()
	else
		local band
		local pre = db.rogue_pool_band_pre
		local post = db.rogue_pool_band_post
		if type(pre) == "number" and type(post) == "number" then
			band = { pre = pre, post = post }
		elseif st.rogue_guide and st.rogue_guide.POOL_BANDS then
			-- Data-driven: the family's band table (RETAIL has none - phase pooling,
			-- so its wash never shows).
			band = st.rogue_guide.POOL_BANDS[st.family]
		end
		local energy = self.rogue_energy_now
		local level
		if type(band) == "table" and type(energy) == "number" then
			if type(band.post) == "number" and energy >= band.post then
				level = 1
			elseif type(band.pre) == "number" and energy >= band.pre
				and type(self.rogue_tick_in) == "number" then
				level = ROGUE_POOL_PRE_ALPHA_SCALE
			end
		end
		if not level then
			wash:Hide()
		else
			local colour = db.rogue_pool_tint_color or ROGUE_POOL_TINT_FALLBACK_COLOR
			local r, g, b, a = self:convert_color(colour)
			wash:SetVertexColor(r, g, b, a * level)
			wash:Show()
		end
	end

	-- Era SS window + weapon-swap tint -------------------------------------------------
	local window = type(w) == "number" and w > 0 and type(h) == "number" and h > 0
		and in_post_mh_window(self, now)
	local d = self.mainhand
	local band_x, band_w
	if window then
		band_x = w * (ST.ROGUE.SS_WINDOW_START / d.speed)
		band_w = w * ((ST.ROGUE.SS_WINDOW_END - ST.ROGUE.SS_WINDOW_START) / d.speed)
	end

	local ss_ok = want_ss and window and ss_window_loadout() == true
	if not ss_ok then
		vf.rogue_ss_band:Hide()
		vf.rogue_ss_text:Hide()
	else
		local colour = db.rogue_ss_color or ROGUE_SS_FALLBACK_COLOR
		vf.rogue_ss_band:SetVertexColor(self:convert_color(colour))
		draw_window_band(vf.rogue_ss_band, vf, band_w, h, band_x)
		vf.rogue_ss_text:SetTextColor(self:convert_color(colour))
		vf.rogue_ss_text:Show()
	end

	local swap_ok = want_swap and window and ST.ROGUE.SWAP_CUE_FAMILIES[st.family] == true
	if not swap_ok then
		vf.rogue_swap_band:Hide()
		vf.rogue_swap_text:Hide()
	else
		local colour = db.rogue_swap_color or ROGUE_SWAP_FALLBACK_COLOR
		vf.rogue_swap_band:SetVertexColor(self:convert_color(colour))
		draw_window_band(vf.rogue_swap_band, vf, band_w, h, band_x)
		vf.rogue_swap_text:SetTextColor(self:convert_color(colour))
		vf.rogue_swap_text:Show()
	end

	-- Poison reminder ------------------------------------------------------------------
	local poison_text = vf.rogue_poison_text
	if not want_poison then
		poison_text:Hide()
	else
		local text = poison_reminder_text()
		if text == nil then
			poison_text:Hide()
		else
			if self.rogue_poison_text_applied ~= text then
				self.rogue_poison_text_applied = text
				poison_text:SetText(text)
			end
			local colour = db.rogue_poison_color or ROGUE_POISON_FALLBACK_COLOR
			poison_text:SetTextColor(self:convert_color(colour))
			poison_text:Show()
		end
	end
end

--=========================================================================================
-- Lifecycle + per-frame hook
--=========================================================================================
function ST.ROGUE.post_init(self)
	-- Resolve the slot spell ids from the client's spell data BEFORE the consumers
	-- build their frames (the frozen contracts read slot ids at creation).
	ST.ROGUE.apply_spell_ids(self)
	-- The rogue's own bar visuals (spark/tint/window/poison): created out of combat;
	-- on_bar_update retries if the frames were not ready yet.
	ST.ROGUE.setup_rogue_visuals(self)
	-- Next Action Guide: the provider above drives the shared frame. Guarded so a
	-- flavor without nextaction_ui stays inert.
	if st.nextaction_ui then
		st.nextaction_ui.init(self)
	end
	-- Cooldown HUD: builds its own UIParent frames (out of combat, deferred and
	-- retried via the per-frame hook under lockdown) from HUD_SLOTS; guarded so a
	-- flavor without hud.lua stays inert.
	if st.hud then
		st.hud.init(self)
	end
end

function ST.ROGUE.on_bar_update(self, hand)
	-- Called from ST:onupdate_common via the generic class hook. Deliberately cheap
	-- and nil-safe, and never gated on st.is_mainline - swing activity decides (the
	-- Forever client is Mainline-code but must show all of this, while the Retail
	-- stand-in never reports a swing).
	if hand ~= "mainhand" then
		return
	end
	-- Cold-spell-book retry: while any slot id is unresolved, re-attempt on the
	-- resolver's throttle (cheap no-op once everything resolved).
	if ST.ROGUE.spell_pending ~= false then
		ST.ROGUE.apply_spell_ids(self)
	end
	-- Settings that rebuild the guide frame (scale/position/lock) are applied when
	-- the class options change; the display toggles are read live by the UI.
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
	-- driver frame, so this is cheap).
	if st.hud then
		st.hud.on_bar_update(self, hand)
	end
	-- Rogue visuals: tick spark + pooling wash + the Era SS window / swap tint /
	-- poison reminder (each behind its own nil-safe gate).
	if ST.ROGUE.setup_rogue_visuals(self) then
		ST.ROGUE.update_rogue_visuals(self)
	end
end

function ST.ROGUE.on_combat_exit(self)
	-- The mainhand record belongs to the swing engine: never clear, copy or re-stamp it
	-- here (G4). The rogue's own per-frame visuals hide themselves when the window
	-- state stops matching (the hook is only a documented lifecycle exit point); the
	-- tick predictor keeps its phase across combat boundaries on purpose - energy
	-- ticks do not stop at combat edges, and a re-seat would hide the spark for a
	-- whole cycle.
end

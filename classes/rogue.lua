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
-- What ships here (rotation audit: bench/rogue_rotation_audit_2026-10-19.md):
--   * proc-aware 2 s energy tick predictor (Yam rule: Combat Potency's 15-energy grant and
--     Relentless Strikes' 25 NEVER re-anchor; only a 20-energy gain in phase does; an
--     ambiguous tick reads nil and every consumer hides - H4/rogue_readiness §4), now
--     AR-aware: while Adrenaline Rush rides, ticks grant 40 (audit F2 residual);
--   * energy-tick spark + pooling tint on the mainhand bar (data-driven bands from
--     rogue_guide.POOL_BANDS: ERA/WRATH 65/85 tick-gated, TBC single 71,
--     FOREVER 65/75; audit T-M1/V-G6);
--   * Era-only post-MH-swing Sinister Strike window (0.1-0.2 s; family ERA plus a confirmed
--     sword mainhand; NEVER on TBC+ - Sno's TBC FAQ refutes swing timing there, §1).
--     Ships RED and VISIBLE by default per OWNER ORDER 2026-10-19 (rogue-redzone) -
--     the explicit gate for this default-visible exception; nil/false still hide.
--     The Era sweaty energy>=79 spend override lives in the guide engine (E-G1);
--     widening the visual window toward 0.5 s needs in-client proof — filed.
--   * weapon-swap tint whose copy carries the GCD + swing-reset cost (families from
--     SWAP_CUE_FAMILIES; Wrath stays off per the recorded conflict, rogue_deep §5.4),
--   * MH/OH poison reminder (api.GetWeaponEnchantInfo presence; charges stay out until the
--     probe shape is confirmed in-client - rogue_deep §5.8),
--   * family-aware builder identity (Saber Slash > Mutilate > Hemorrhage >
--     dagger-MH Backstab > Sinister Strike, resolved through the client's own
--     spell data — audit F1/H12 + BS-6; Hemorrhage is family-gated (TBC/Forever/Era,
--     never SoD); CP/stack/rune APL gating filed),
--   * live HUD state (SnD/Rupture/EA/AR/BF/Tea/Kick + Cold Blood (nil-safe,
--     hud_show_coldblood gate, widget/default filed) + R3 short-CD row
--     Kidney/Re-stealth/Bandage + stacked multi-CD glow; trinkets are HUD-served),
--   * live guide gather incl. the provider-owned inputs_unknown bit (M6), the M5
--     lust-unknown latch reusing api.auras_may_be_secret(), the Mutilate-known
--     read (TBC Shiv gate) and Cold Blood readiness,
--   * SnD upkeep + AR/BF/Cold Blood readiness for the guide engine (audit F0/H1 +
--     F3/H11 + F3/V-G5: live aura/cooldown reads driving the wired snd/ar/bf/
--     coldblood guide slots; the rotation label names them meanwhile),
--   * EA-duty H6 behavior (audit H6, open_rules BUILD): the TBC 15 s minimum +
--     wait-HOLD / pool-release and the Forever finisher lockout ride the
--     existing rogue_ea_duty toggle (default off -> inert; no new keys),
--   * SoD latch for the guide engine (sod_detect ONE mechanism): ERA family +
--     the SoD-only Envenom rune known through api.is_spell_known, frozen at
--     post_init (a rune learned mid-session needs /reload); feeds
--     inputs.sod_envenom so the engine reaches the SOD Envenom/SnD/Tea rows,
--   * TTD via the rogue-owned HP/s EMA (st.rogue_guide, vendored from the
--     druid D4 precedent) with the M7 provenance rule: only this
--     module's own health-velocity estimate - never the enemy_swing 2.0 s fallback.
--
-- Deliberately NOT here: CLEU matching (no rogue id exists in the corpus - the R1 rule),
-- the spellcast lifecycle hook (nothing consumes casts; Tea/Shiv read cooldowns), and any
-- `st.is_mainline` gate (swing activity decides - the Forever client is Mainline-code but
-- must run these cues; the Retail stand-in never swings, so they stay hidden there).
--
-- Options surface (the options pass owns the widgets; every key is read nil-safely):
--   shipped:      show_rogue_energy_tick, rogue_energy_tick_color, show_rogue_pool_tint,
--                 rogue_pool_tint_color, rogue_pool_band_pre, rogue_pool_band_post
--                 (config_presets.lua's ROGUE defaults).
--   new, nil-safe (nil/false = off - no default-visible change): show_rogue_swap_cue,
--                 show_rogue_poison_cue, rogue_swap_color, rogue_poison_color, rogue_ea_duty
--                 (Imp-EA duty), and the tuning keys rogue_rupture_refresh / rogue_rupture_min_ttd /
--                 rogue_finisher_min_cp / rogue_ea_refresh / rogue_shiv_refresh /
--                 rogue_tea_energy_max (nil = the rogue_guide defaults).
--   R3 short-CD row + Cold Blood, nil-safe (== true shows, nil = off - no
--                 default-visible change, provider-gated because the options pass
--                 ships no widget yet): hud_show_kidney / hud_show_restealth /
--                 hud_show_bandage / hud_show_coldblood (widget/default filed).
--                 Tunables UNCONFIRMED beyond Sno's list (competitor_gaps R3).
--   redzone exception, OWNER ORDER 2026-10-19: show_rogue_ss_window ships true and
--   rogue_ss_color ships RED - the owner is the explicit gate for this
--   default-visible change. Reads stay nil-safe (== true shows), so nil, an
--   explicit false, an off-family client or an unreadable weapon still hide.
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
st.class_loaders = st.class_loaders or {}
st.class_loaders["ROGUE"] = function()
-- Cross-client API wrappers (see compat.lua).
local api = st.api

-- Cross-client probes (compat.lua) ---------------------------------------------------------
-- Every client read this module needs - item info/count/cooldown, weapon-enchant
-- presence, unit identity - lives in compat.lua as st.api.*, the single crossing point.
-- This file calls no cross-client global directly; each wrapper degrades to its documented
-- unknown shape (nil, or the idle cooldown triple) when the client cannot answer.

--=========================================================================================
-- Constants (cited; no magic numbers at the call sites)
--=========================================================================================
-- Energy tick: 20 energy / 2 s on the classic line (rogue_research §§1.1/1.3, CONFIRMED).
-- While Adrenaline Rush rides, ticks grant 40 (audit F2 residual — the predictor
-- used to go dark exactly when tick timing matters most).
ST.ROGUE.TICK_PERIOD = 2.0
ST.ROGUE.TICK_ENERGY = 20
ST.ROGUE.TICK_AR_ENERGY = 40
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
local ROGUE_SS_FALLBACK_COLOR = { 255, 64, 48, 0.85 }
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
-- TBC Anniversary resolves auras by NAME never bare id (operator rule 2026-10-19):
-- the same window's English names. Era paths use the ids above.
local ROGUE_LUST_NAMES = { ["Bloodlust"] = true, ["Heroism"] = true }
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
	-- Cold Blood (audit F3/V-G5: TBC w/ SnD, Forever at 5CP; the engine gates
	-- the prompt by family - the HUD tracks the cooldown whenever the client's
	-- spell data answers, unknown-hides otherwise).
	coldblood = "Cold Blood",
	-- R3 short-CD row (competitor_gaps R3 + rogue_deep §§2.4/2.7; Sno UI short-CD
	-- tracker CONFIRMED as listing text https://www.tbcguides.gg/rogue-ui/):
	-- Kidney Shot CONFIRMED in Sno's tracker list; the Vanish mapping for the
	-- Re-stealth CD and the Heavy Netherweave rank for Bandage are UNCONFIRMED
	-- in-client (Sno lists "Re-stealth CD" / "Bandage" generically) and resolve
	-- through the client's own spell data like every other slot (unknown-hides).
	kidney = "Kidney Shot",
	restealth = "Vanish",
	bandage = "Heavy Netherweave Bandage",
}
local GUIDE_SPELL_NAMES = {
	builder = "Sinister Strike",
	rupture = "Rupture",
	eviscerate = "Eviscerate",
	envenom = "Envenom",
	expose = "Expose Armor",
	shiv = "Shiv",
	tea = "Thistle Tea",
	snd = "Slice and Dice",
	ar = "Adrenaline Rush",
	bf = "Blade Flurry",
	coldblood = "Cold Blood",
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
	if not ok or type(spell_name) ~= "string" then
		ST.ROGUE.spell_cache[key] = false
		ST.ROGUE.spell_retry_at = (type(now) == "number" and now or 0) + ROGUE_SPELL_RETRY
		return nil
	end
	-- Name-vs-id rule (operator 2026-10-19): TBC resolves by NAME never bare id,
	-- Era by id. A TBC entry is usable with the name alone (the id may be absent
	-- on that client); an Era entry needs the numeric id.
	if st.family == "TBC" then
		if type(spell_id) ~= "number" then
			spell_id = nil
		end
	elseif type(spell_id) ~= "number" then
		ST.ROGUE.spell_cache[key] = false
		ST.ROGUE.spell_retry_at = (type(now) == "number" and now or 0) + ROGUE_SPELL_RETRY
		return nil
	end
	local entry = { id = spell_id, name = spell_name, icon = icon }
	ST.ROGUE.spell_cache[key] = entry
	return entry
end

-- Family-correct spell query (operator name-vs-id rule): TBC passes the resolved
-- English name, every other family passes the numeric id. Uses the shared compat
-- helper when present; the inline family branch is the fallback so the module
-- never depends on load order.
local function rogue_query(entry)
	if type(entry) ~= "table" then
		return nil
	end
	if type(api.get_spell_query) == "function" then
		return api.get_spell_query(entry.name, entry.id)
	end
	if st.family == "TBC" then
		return entry.name
	end
	return entry.id
end

-- Sim-sourced builder identity (audit F1/H12 + BS-6): Saber Slash (the SoD rune)
-- outranks Mutilate, which outranks Hemorrhage, which outranks a dagger-mainhand
-- Backstab, which outranks Sinister Strike. Every name resolves through the
-- client's own spell data (unknown-hides: a name the client does not know
-- resolves to nil and the chain falls through — never a wrong builder).
--
-- Hemorrhage (BS-6, bench/filed_closure_sweep_2026-10-19.md §3 U-04 / §7 BS-6):
-- the name is CERTAIN — "Hemorrhage" — and the ids are web-confirmed by wowhead's
-- own redirect slugs (TBC 26864, Era/Forever 16511; the bench corpus had the two
-- swapped — 26862 is Sinister Strike, 26864 is Hemorrhage). The id is cited here,
-- never used: the class resolves the NAME through the client's own spell data, so
-- a wrong id cannot produce a wrong builder. The family gate keeps Hemorrhage a
-- TBC/Forever/Era builder only: the SoD client (the ERA token with the SoD-only
-- Envenom rune known) builds with a rune, and the rune candidates stay ahead of
-- it here, so a rune the sim prefers is never passed over. The TBC APL's
-- known-spell (talent) branch is not modelled — the filed APL-gating row
-- (CP/stack/rune) still owns it.
local BUILDER_CANDIDATE_NAMES = { "Saber Slash", "Mutilate", "Hemorrhage" }
local BUILDER_DAGGER_NAME = "Backstab"

-- SoD latch (ERA family only): the SoD-only Envenom rune known through
-- api.is_spell_known (knowledge, never spell-data existence -
-- bench/sod_detect_2026-10-19.md, the per-class ERA + known-spell mechanism;
-- no global is_sod token, no version branching). The id is UNCONFIRMED
-- in-client (rogue candidates 424785/399956/399963 need confirmation); a
-- wrong id fails safe to Era-base behavior (the SOD table never prompts).
local ROGUE_SOD_ENVENOM_RUNE_ID = 399963

-- Forward declaration: defined below item_subclass (which it reads), assigned
-- there without `local` so this upvalue binds (Lua lexicals resolve at the
-- declaration point — a later `local function` would shadow, not bind).
local resolve_builder_entry

-- Fills the HUD/guide slot ids from the client's spell data. Idempotent; called from
-- post_init before either consumer builds its frames, and retried from on_bar_update
-- while any slot is still unresolved (cold spell book). Returns true while pending.
-- Name-vs-id rule (operator 2026-10-19): slots store the family-correct query
-- (name on TBC, id elsewhere) so the icon reads via GetSpellInfo never use a bare
-- id on TBC and never a bare name lookup on Era.
function ST.ROGUE.apply_spell_ids(self)
	local now = api.get_time()
	local pending = false
	local slots = ST.ROGUE.HUD_SLOTS
	for i = 1, #slots do
		local slot = slots[i]
		if slot.spell == nil and SLOT_SPELL_NAMES[slot.key] then
			local entry = resolve_named_spell("hud:" .. slot.key, SLOT_SPELL_NAMES[slot.key], now)
			if entry then
				slot.spell = rogue_query(entry)
				slot.spell_name = entry.name
			else
				pending = true
			end
		end
	end
	local guide_slots = ST.ROGUE.guide.slots
	for i = 1, #guide_slots do
		local slot = guide_slots[i]
		if slot.spell_id == nil then
			local entry
			if slot.key == "builder" then
				entry = resolve_builder_entry(now)
			elseif GUIDE_SPELL_NAMES[slot.key] then
				entry = resolve_named_spell("guide:" .. slot.key, GUIDE_SPELL_NAMES[slot.key], now)
			end
			if entry then
				slot.spell_id = rogue_query(entry)
				slot.spell_name = entry.name
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
-- Match shape is id primary, name secondary on every family (the hunter R1
-- discipline): the rank id first, then the resolved English name. Either shape
-- can ride a name-carrying/id-less Anniversary row, so the family no longer
-- picks one shape; the two describe the same resolved spell, so matching both
-- is behavior-neutral where the old branch matched.
local function find_unit_aura(unit, filter, wanted_id, wanted_name, now)
	for index = 1, ROGUE_AURA_SCAN_LIMIT do
		local name, _, count, _, duration, expiration, _, _, _, spell_id =
			api.UnitAura(unit, index, filter)
		local match = false
		if name ~= nil then
			match = (wanted_id ~= nil and spell_id == wanted_id)
				or (wanted_name ~= nil and name == wanted_name)
		end
		if match then
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
-- Name-vs-id rule (operator 2026-10-19): the query is the English name on TBC,
-- the numeric id elsewhere (callers pass rogue_query(entry)).
local function spell_cooldown(self, query, now)
	if type(query) ~= "number" and type(query) ~= "string" then
		return nil
	end
	local start_time, duration = api.GetSpellCooldown(query)
	if type(start_time) ~= "number" or type(duration) ~= "number" or duration <= 1.51 then
		return nil
	end
	local remaining = start_time + duration - now
	if remaining <= 0 then
		return nil
	end
	return remaining, duration
end

-- One utility spell's readiness (the APL utility layer's rows): known + usable
-- + off cooldown - the Shiv shape, applied to the utility rows. nil when the
-- client does not know the spell or the read is unusable, so the engine's arm
-- hides (unknown-hides: no advice beats wrong advice). The name resolution is
-- the house way (the TBC client answers by NAME, the other clients by ID).
local function utility_ready(self, key, name, now)
	local entry = resolve_named_spell(key, name, now)
	if not entry then
		return nil
	end
	local query = rogue_query(entry)
	local usable = api.IsSpellUsable(query)
	if api.is_spell_known(query) ~= true or usable == false then
		return nil
	end
	if spell_cooldown(self, query, now) ~= nil then
		return nil
	end
	return true
end

-- One aura's presence (the APL utility layer's aura rows): true when the aura
-- is up, false when the walk completed without it. The wrapper answers nil for
-- BOTH "not found" and "cannot read the list" - for the "the aura must be DOWN"
-- gates that is the safe reading (the row stays quiet), and the secret regime
-- is caught by the provider's own M6 bit (inputs_unknown).
-- Match shape is id primary, name secondary (the hunter R1 discipline): the
-- probed id first, then the client's own localized name for it. A
-- name-carrying/id-less Anniversary row still lands the read; a cold spell
-- cache reads id-only and retries the name next call.
local utility_aura_names = {}
local function utility_aura_present(unit, filter, spell_id)
	if type(api.scan_unit_aura) ~= "function" then
		return nil
	end
	local name = utility_aura_names[spell_id]
	if name == nil then
		local resolved = api.GetSpellInfo(spell_id)
		if type(resolved) == "string" then
			name = resolved
			utility_aura_names[spell_id] = name
		end
	end
	local remaining = api.scan_unit_aura(unit, function(id, aura_name)
		return id == spell_id or (name ~= nil and aura_name == name)
	end, filter)
	if remaining == nil then
		return false
	end
	return true
end

-- The secret-value guard (the house's shape: classes/warrior.lua, classes/druid.lua).
-- A restricted reading must degrade, never error.
local is_secret = issecretvalue or function()
	return false
end

-- The client's own ENERGY power type (Enum.PowerType.Energy). The enum is a client
-- global and never changes, so it is read once at load time; a client that does not
-- expose it leaves the energy-cost read UNKNOWN (nil) - never a guessed type.
local ROGUE_ENERGY_POWER_TYPE = (Enum and Enum.PowerType and Enum.PowerType.Energy) or nil

-- One ability's ENERGY cost from a GetSpellPowerCost result (the APL's
-- spellCurrentCost - the house's rage_cost_of shape, with the client's own power
-- type as the selector): the entry that names the energy type IS the energy cost.
-- The client's own code reads the same shape (classic_era and the Forever client:
-- Interface/AddOns/Blizzard_ActionBar/Shared/ActionButton.lua - costInfo.type ==
-- Enum.PowerType.Energy; Blizzard_PersonalResourceDisplay.lua - costInfo.cost for
-- the matching power type). A restricted (secret) value, a client without the
-- energy type, and a table with no energy entry all read nil (unknown - the
-- engine never compares the energy against a guess).
local function energy_cost_of(costs)
	if type(costs) ~= "table" or ROGUE_ENERGY_POWER_TYPE == nil then
		return nil
	end
	for i = 1, #costs do
		local info = costs[i]
		if type(info) == "table" and info.type == ROGUE_ENERGY_POWER_TYPE then
			local cost = info.cost
			if is_secret(cost) or type(cost) ~= "number" then
				return nil
			end
			return cost
		end
	end
	return nil
end

-- Item probes (Thistle Tea) through compat (st.api): the count and the cooldown as
-- remaining seconds. A client that cannot answer reports nil - unknown, never zero.
local function tea_item_count()
	local count = api.GetItemCount("Thistle Tea")
	if type(count) ~= "number" then
		return nil
	end
	return count
end

local function tea_item_cooldown(now)
	local start_time, duration = api.GetItemCooldown("Thistle Tea")
	if type(start_time) ~= "number" or type(duration) ~= "number"
		or duration <= 0 then
		return nil
	end
	local remaining = start_time + duration - now
	if remaining <= 0 then
		return nil
	end
	return remaining, duration
end

-- Item probes (Bandage) through compat (st.api): same unknown shape as Tea.
-- The exact bandage rank is UNCONFIRMED in-client (Sno lists "Bandage"
-- generically, rogue_deep §2.4; Heavy Netherweave is the TBC-relevant rank but
-- NEEDS IN-CLIENT CONFIRMATION): the name resolves through the client's own
-- item data, and an unanswered probe stays silent (never a fabricated count).
local ROGUE_BANDAGE_ITEM = "Heavy Netherweave Bandage"

local function bandage_item_count()
	local count = api.GetItemCount(ROGUE_BANDAGE_ITEM)
	if type(count) ~= "number" then
		return nil
	end
	return count
end

local function bandage_item_cooldown(now)
	local start_time, duration = api.GetItemCooldown(ROGUE_BANDAGE_ITEM)
	if type(start_time) ~= "number" or type(duration) ~= "number"
		or duration <= 0 then
		return nil
	end
	local remaining = start_time + duration - now
	if remaining <= 0 then
		return nil
	end
	return remaining, duration
end

-- R3 short-CD gate (also the Cold Blood nil-safe gate): a new slot renders only
-- when its own hud_show_<key> toggle reads exactly true (nil = off). The HUD
-- treats a nil toggle as wanted, so this provider-level hide is the
-- no-default-visible gate for slots the options pass has no widget for yet.
local function shortcd_wanted(self, key)
	local db = self:get_class_table()
	if type(db) ~= "table" then
		return false
	end
	return db["hud_show_" .. key] == true
end

-- Multi-CD stacked glow (rogue_deep §2.7: Sno buff tracker "highlighted with
-- a yellow glow ... when using multiple CDs at once", CONFIRMED as listing
-- text https://www.tbcguides.gg/rogue-ui/). Counts the active offensive buffs
-- the provider already tracks (AR + BF auras); trinket/pot/drum buffs are NOT
-- counted (HUD-served or no probe) - the counted set is UNCONFIRMED beyond
-- Sno's list. Secret-regime unknown reads count as inactive (never a guess).
local function count_stacked_offensives(self, now)
	local count = 0
	for _, key in ipairs({ "ar", "bf" }) do
		local entry = ST.ROGUE.spell_cache["hud:" .. key]
		if entry then
			local found = find_unit_aura("player", "HELPFUL",
				entry.id, entry.name, now)
			if found then
				count = count + 1
			end
		end
	end
	return count
end

-- Mainhand item subclass ("Sword", ...) through compat (st.api normalises the classic
-- multi-return and any table-shaped read); nil when the client cannot answer. The
-- contract api.GetItemInfo documents: position 6 is the item's TYPE string and position
-- 7 the item's SUBTYPE string, whichever probe answered (C_Item names them itemType /
-- itemSubType, the classic global names them class / subclass) - so the names below are
-- the normalised ones.
local function item_subclass(item_id)
	if type(item_id) ~= "number" then
		return nil
	end
	local _, _, _, _, _, item_type, item_sub_type = api.GetItemInfo(item_id)
	if type(item_type) ~= "string" then
		return nil
	end
	return item_sub_type
end

-- Bar geometry (width/height) from bars.lua, nil-safe for a caller without the helper.
local function bar_geometry(self)
	if type(self.get_bar_visuals_width_and_height) ~= "function" then
		return nil, nil
	end
	return self:get_bar_visuals_width_and_height("mainhand")
end

-- Mainhand dagger check through compat (st.api normalises the read); anything
-- the client cannot identify reads nil — never a guessed loadout. Both the
-- singular and plural subclass spellings count: the exact client string is
-- UNCONFIRMED for daggers (sourced only for "Sword" above), so neither spelling
-- may exclude the other.
local function dagger_mainhand()
	local item_id = api.GetInventoryItemID(16)
	local subclass = item_subclass(item_id)
	return subclass == "Dagger" or subclass == "Daggers"
end

-- The family gate for one builder candidate (pure, in the engine: the per-family
-- DATA tables live there — rogue_guide.builder_candidate_allowed). A missing engine
-- allows the candidate: the gate is an extra safety, never the only one, because
-- the candidate names are still resolved through the client's own spell data (an
-- unknown name falls through to the next candidate).
local function builder_candidate_allowed(name)
	local engine = st.rogue_guide
	if not (engine and type(engine.builder_candidate_allowed) == "function") then
		return true
	end
	return engine.builder_candidate_allowed(name, st.family, ST.rogue_is_sod) == true
end

-- Builder resolution in candidate order; the slot's spell_id follows the
-- winner, so the guide icon + rotation label track the family builder. The
-- negative cache in resolve_named_spell bounds re-probes while a candidate is
-- unanswered (a rune learned later resolves on the retry pass while any slot
-- stays pending).
function resolve_builder_entry(now)
	for i = 1, #BUILDER_CANDIDATE_NAMES do
		local name = BUILDER_CANDIDATE_NAMES[i]
		if builder_candidate_allowed(name) then
			local entry = resolve_named_spell("guide:builder:" .. i,
				name, now)
			if entry then
				return entry
			end
		end
	end
	if dagger_mainhand() then
		local entry = resolve_named_spell("guide:builder:backstab",
			BUILDER_DAGGER_NAME, now)
		if entry then
			return entry
		end
	end
	return resolve_named_spell("guide:builder", GUIDE_SPELL_NAMES.builder, now)
end

--=========================================================================================
-- Energy tick predictor (proc-aware; Yam rule + H4; AR-aware per audit F2)
--=========================================================================================
-- State on the module instance:
--   rogue_tick_anchor   the last observed natural tick (nil = no trustworthy phase)
--   rogue_tick_prev/at  the previous energy sample (delta evidence)
--   rogue_tick_unknown  latched ambiguity - hides the spark until a fresh in-phase tick
-- Returns the seconds to the next tick, or nil when the phase is unknown (H4: an
-- ambiguous tick is hidden, never guessed). tick_gain is the expected grant for
-- the current haste regime (20, or 40 while Adrenaline Rush rides — the
-- provider proves the regime in sample_energy_tick; anything else is a guess).
function ST.ROGUE.update_energy_tick(self, now, energy, max_energy, tick_gain)
	local period = ST.ROGUE.TICK_PERIOD
	local tolerance = ST.ROGUE.TICK_GAIN_TOLERANCE
	if type(tick_gain) ~= "number" or tick_gain <= 0 or tick_gain ~= tick_gain then
		tick_gain = ST.ROGUE.TICK_ENERGY
	end
	if type(now) ~= "number" or type(energy) ~= "number"
		or now ~= now or energy ~= energy then
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
			if delta == tick_gain then
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
					-- An at-gain outside the phase: a gear proc or a drifted
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

-- One live sample: reads the energy pool and its cap, proves the tick regime
-- (AR buff riding or not — F2 residual), feeds the predictor and stores the
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
	local gain = ST.ROGUE.TICK_ENERGY
	if type(now) == "number" then
		local ar_entry = ST.ROGUE.spell_cache["hud:ar"]
		if ar_entry then
			local riding = find_unit_aura("player", "HELPFUL",
				ar_entry.id, ar_entry.name, now)
			if riding then
				gain = ST.ROGUE.TICK_AR_ENERGY
			end
		end
	end
	self.rogue_energy_now = energy
	self.rogue_energy_max = max_energy
	self.rogue_tick_in = ST.ROGUE.update_energy_tick(self, now, energy, max_energy, gain)
	return self.rogue_tick_in
end

--=========================================================================================
-- Time-to-die: rogue-owned EMA, own tracker only (M7 provenance)
--=========================================================================================
-- The only accepted provenance is this module's own EMA-smoothed HP/s estimate over the
-- live target (vendored from the druid D4 precedent into st.rogue_guide - same
-- smoothing, same inputs/outputs; no cross-class runtime read). The
-- enemy_swing 2.0 s fallback is display fiction (rogue_readiness §4 / fix-engine M7) and
-- must never feed Rupture-vs-Eviscerate - there is deliberately no code path that reads it.
ST.ROGUE.TTD_PROVENANCE = "own-ema"

function ST.ROGUE.get_time_to_die(self, now)
	local rg = st.rogue_guide
	if type(rg) ~= "table" or type(now) ~= "number" then
		return nil
	end
	local guid = api.UnitGUID("target")
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
	if now - at < rg.TTD_SAMPLE_SECONDS then
		-- Too soon for a new sample: keep the stored one and ride the current EMA.
		return rg.get_time_to_die(hp, self.rogue_ttd_velocity)
	end
	local prev_hp = self.rogue_ttd_hp
	self.rogue_ttd_at = now
	self.rogue_ttd_hp = hp
	self.rogue_ttd_velocity = rg.update_hp_velocity(
		self.rogue_ttd_velocity, hp, prev_hp, now - at)
	return rg.get_time_to_die(hp, self.rogue_ttd_velocity)
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
		-- Id primary, name secondary on every family (the hunter R1
		-- discipline): the rank id first, then the English lust names. A
		-- name-carrying/id-less Anniversary row still lands the read on TBC,
		-- and a numeric id still lands it there too.
		local remaining = api.scan_player_aura(function(spell_id, name)
			return (spell_id ~= nil and ROGUE_LUST_IDS[spell_id] == true)
				or (name ~= nil and ROGUE_LUST_NAMES[name] == true)
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
-- eviscerate, envenom, expose, shiv, tea, snd, ar, bf, coldblood). spell_id is filled
-- from the client's own spell data by apply_spell_ids before the frame builds its icons.
ST.ROGUE.guide = {
	slots = {
		{ key = "builder" },
		{ key = "rupture" },
		{ key = "eviscerate" },
		{ key = "envenom" },
		{ key = "expose" },
		{ key = "shiv" },
		{ key = "tea" },
		{ key = "snd" },
		{ key = "ar" },
		{ key = "bf" },
		{ key = "coldblood" },
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
	local db = self:get_class_table() or {}
	-- PROPER: {} reads every tunable as nil, which is exactly the engine's
	-- documented default for each; the live energy/cp/aura reads below still run.

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
	-- SoD Envenom latch: the frozen post_init probe, exactly true or nothing
	-- (nil reads Era-base in the engine; never a defaulted true).
	inputs.sod_envenom = (self.rogue_is_sod == true) and true or nil

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
	local deadly_found, deadly_remains, _, deadly_stacks = false, nil, nil, nil
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

	-- Slice and Dice upkeep (audit F0/H1): the player buff through the HUD
	-- slot's already-resolved spell (same cache key apply_spell_ids fills — no
	-- second probe shape, no new db key). Missing (nil) prompts the engine's
	-- upkeep rule; an unresolved spell reads unusable and stays silent.
	local snd_entry = ST.ROGUE.spell_cache["hud:snd"]
	if not snd_entry and SLOT_SPELL_NAMES.snd then
		snd_entry = resolve_named_spell("hud:snd", SLOT_SPELL_NAMES.snd, now)
	end
	inputs.snd_usable = (snd_entry ~= nil) and true or nil
	local snd_found, snd_remains = false, nil
	if snd_entry then
		snd_found, snd_remains = find_unit_aura("player", "HELPFUL",
			snd_entry.id, snd_entry.name, now)
	end
	inputs.snd_remains = snd_found and (snd_remains or 0) or nil

	-- Hunger for Blood upkeep (Wrath sin; audit W-G1, the class-feature audit's
	-- R-19): the wowsims wotlk APL refreshes the buff when its aura has <= 1 s
	-- left. The spell resolves through the client's OWN spell data by its
	-- English name - the sim's 51662 is sim-side evidence only and is never
	-- shipped (the remembered-id rule) - and the talent gate is a strict true
	-- (an unresolved or unknown spell never prompts, so a client without the
	-- talent stays silent). The buff clock is the player's own aura: a missing
	-- buff reads nil (an upkeep gap, the SnD convention) and the M6 bit below
	-- suppresses every verdict while the secret regime hides the auras.
	local hfb_entry = resolve_named_spell("guide:hfb", "Hunger for Blood", now)
	inputs.hfb_usable = nil
	inputs.hfb_remains = nil
	if hfb_entry then
		local hfb_query = rogue_query(hfb_entry)
		if api.is_spell_known(hfb_query) == true then
			inputs.hfb_usable = true
			local hfb_found, hfb_remains = false, nil
			if hfb_entry then
				hfb_found, hfb_remains = find_unit_aura("player", "HELPFUL",
					hfb_entry.id, hfb_entry.name, now)
			end
			inputs.hfb_remains = hfb_found and (hfb_remains or 0) or nil
		end
	end

	-- Adrenaline Rush / Blade Flurry usability (audit F3/H11): known, usable,
	-- off cooldown — the Shiv shape, minus the item count (cooldowns, not
	-- consumables). No new db key: readiness is a live read.
	local ar_entry = ST.ROGUE.spell_cache["hud:ar"]
	if not ar_entry and SLOT_SPELL_NAMES.ar then
		ar_entry = resolve_named_spell("hud:ar", SLOT_SPELL_NAMES.ar, now)
	end
	inputs.ar_ready = nil
	if ar_entry then
		local ar_query = rogue_query(ar_entry)
		inputs.ar_ready = api.is_spell_known(ar_query)
			and api.IsSpellUsable(ar_query) ~= false
			and spell_cooldown(self, ar_query, now) == nil
			and true or nil
	end
	local bf_entry = ST.ROGUE.spell_cache["hud:bf"]
	if not bf_entry and SLOT_SPELL_NAMES.bf then
		bf_entry = resolve_named_spell("hud:bf", SLOT_SPELL_NAMES.bf, now)
	end
	inputs.bf_ready = nil
	if bf_entry then
		local bf_query = rogue_query(bf_entry)
		inputs.bf_ready = api.is_spell_known(bf_query)
			and api.IsSpellUsable(bf_query) ~= false
			and spell_cooldown(self, bf_query, now) == nil
			and true or nil
	end

	-- Shiv usability: known, not on cooldown, not resource-locked.
	local shiv_entry = resolve_named_spell("guide:shiv", GUIDE_SPELL_NAMES.shiv, now)
	inputs.shiv_ready = nil
	if shiv_entry then
		local shiv_query = rogue_query(shiv_entry)
		local usable = api.IsSpellUsable(shiv_query)
		inputs.shiv_ready = api.is_spell_known(shiv_query)
			and usable ~= false
			and spell_cooldown(self, shiv_query, now) == nil
			and true or nil
	end

	-- Mutilate-known for the TBC Shiv gate (audit T-G4): resolved through the
	-- client's own spell data (same name the builder chain resolves — never a
	-- remembered id). Strict == true reads Mutilate; nil reads unknown /
	-- unlearned and keeps the upkeep.
	local mutilate_entry = resolve_named_spell("guide:mutilate_known", "Mutilate", now)
	inputs.mutilate_known = nil
	if mutilate_entry then
		if api.is_spell_known(rogue_query(mutilate_entry)) == true then
			inputs.mutilate_known = true
		end
	end

	-- Cold Blood readiness (audit F3/V-G5): known, usable, off cooldown — the
	-- Shiv shape, minus the item count (a cooldown, not a consumable). No new
	-- db key: readiness is a live read like ar/bf.
	local coldblood_entry = resolve_named_spell("guide:coldblood", "Cold Blood", now)
	inputs.coldblood_ready = nil
	if coldblood_entry then
		local cb_query = rogue_query(coldblood_entry)
		local usable = api.IsSpellUsable(cb_query)
		inputs.coldblood_ready = api.is_spell_known(cb_query)
			and usable ~= false
			and spell_cooldown(self, cb_query, now) == nil
			and true or nil
	end

	-- Thistle Tea readiness: count (when the client answers) and cooldown. The count
	-- probe shape is UNCONFIRMED in-client (rogue_deep §5.8) - it is used defensively
	-- only: an answered zero withholds, an absent probe leaves usability to the spell.
	local tea_entry = resolve_named_spell("guide:tea", GUIDE_SPELL_NAMES.tea, now)
	inputs.tea_ready = nil
	if tea_entry then
		local tea_query = rogue_query(tea_entry)
		local tea_cd = tea_item_cooldown(now)
		if tea_cd == nil then
			tea_cd = spell_cooldown(self, tea_query, now)
		end
		local count = tea_item_count()
		local usable = api.IsSpellUsable(tea_query)
		inputs.tea_ready = api.is_spell_known(tea_query)
			and usable ~= false
			and count ~= 0
			and tea_cd == nil
			and true or nil
	end

	-- The APL utility layer's reads (bench/rotation_gap_vs_apl_2026-10-20.md §3 -
	-- the operator's "a rotation that only carries the damage abilities is not
	-- the class's rotation"). Every row is family-gated, so only the RUNNING
	-- family's rows are read: a client never pays for another client's rows.
	-- The reads are the existing compat wrappers (api.GetSpellCooldown through
	-- the class's own helper, api.scan_unit_aura through the aura walker); no
	-- new client API is used anywhere below.
	local utility_family = st.family
	if inputs.sod_envenom == true then
		utility_family = "SOD"
	end
	inputs.vanish_ready = nil
	inputs.master_of_subtlety_active = nil
	inputs.vanished_active = nil
	inputs.envenom_ready = nil
	inputs.poisoned_knife_ready = nil
	inputs.ambush_ready = nil
	inputs.garrote_ready = nil
	inputs.preparation_ready = nil
	inputs.premeditation_ready = nil
	inputs.venom_ready = nil
	inputs.blood_fury_ready = nil
	inputs.elunes_light_ready = nil
	inputs.tricks_ready = nil
	inputs.killing_spree_ready = nil
	inputs.ambush_cue_active = nil
	inputs.venom_buff_active = nil
	inputs.garrote_dot_active = nil
	inputs.garrote_energy_cost = nil
	inputs.vanish_cd_remaining = nil
	inputs.ar_cd_remaining = nil
	inputs.ar_known = nil
	inputs.ar_buff_active = nil
	inputs.gnome_eureka_ready = nil
	inputs.gnome_eureka_full_cd = nil
	if utility_family == "SOD" then
		-- The SoD's rows: the Vanish opener (1856), the Master of Subtlety rune
		-- aura (425096 - the id the SoD APL's own NOT(auraIsActive) cites), the
		-- Envenom the opener ends in (399963) and the Poisoned Knife window.
		inputs.vanish_ready = utility_ready(self, "guide:vanish", "Vanish", now)
		inputs.master_of_subtlety_active = utility_aura_present("player", "HELPFUL", 425096)
		inputs.envenom_ready = utility_ready(self, "guide:envenom_ready", "Envenom", now)
		inputs.poisoned_knife_ready = utility_ready(self, "guide:poisoned_knife", "Poisoned Knife", now)
	elseif utility_family == "WRATH" then
		-- The WotLK's rows: the Vanish pop (26889), the 58426 aura (the APL's
		-- NOT(auraIsActive) - the name is UNCONFIRMED, the id is the APL's) and
		-- the two energy pops.
		inputs.vanish_ready = utility_ready(self, "guide:vanish", "Vanish", now)
		inputs.vanished_active = utility_aura_present("player", "HELPFUL", 58426)
		inputs.tricks_ready = utility_ready(self, "guide:tricks", "Tricks of the Trade", now)
		inputs.killing_spree_ready = utility_ready(self, "guide:killing_spree", "Killing Spree", now)
	elseif utility_family == "FOREVER" then
		-- The Forever client's rows: the opener cluster (Ambush, Garrote, Vanish,
		-- Preparation), the CP opener (Premeditation), the Venom finisher, the
		-- two paired pops (Blood Fury, Elune's Light) and the Gnome racial
		-- (Eureka!).
		inputs.vanish_ready = utility_ready(self, "guide:vanish", "Vanish", now)
		inputs.ambush_ready = utility_ready(self, "guide:ambush", "Ambush", now)
		inputs.garrote_ready = utility_ready(self, "guide:garrote", "Garrote", now)
		inputs.preparation_ready = utility_ready(self, "guide:preparation", "Preparation", now)
		inputs.premeditation_ready = utility_ready(self, "guide:premeditation", "Premeditation", now)
		inputs.venom_ready = utility_ready(self, "guide:venom", "Venom", now)
		inputs.blood_fury_ready = utility_ready(self, "guide:blood_fury", "Blood Fury", now)
		inputs.elunes_light_ready = utility_ready(self, "guide:elunes_light", "Elune's Light", now)
		inputs.ambush_cue_active = utility_aura_present("player", "HELPFUL", 462707)
		inputs.venom_buff_active = utility_aura_present("player", "HELPFUL", 1310703)
		inputs.garrote_dot_active = utility_aura_present("target", "HARMFUL", 11290)
		-- The Garrote's CURRENT energy cost (the APL's spellCurrentCost(11290)):
		-- the Forever Vanish row (i=3) fires only when the energy covers the
		-- Garrote. The cost is read through the compat pass-through
		-- (api.GetSpellPowerCost) and the client's own energy power type selects
		-- the flat energy cost - the shape the client's own code reads
		-- (ActionButton.lua / PersonalResourceDisplay.lua). An unreadable cost
		-- stays nil (unknown-hides: the row hides rather than compare the energy
		-- against a guess).
		local garrote_entry = resolve_named_spell("guide:garrote", "Garrote", now)
		if garrote_entry then
			local ok, costs = pcall(api.GetSpellPowerCost, rogue_query(garrote_entry))
			if ok then
				inputs.garrote_energy_cost = energy_cost_of(costs)
			end
		end
		-- The Gnome Eureka! racial (the Forever APL's i=13 - the APL's own
		-- "Gnome Eureka - Should Cast" variable, expanded):
		--   spellIsKnown(1259812) AND spellIsReady(1259812) AND (
		--     NOT spellIsKnown(13750)   -- the Adrenaline Rush is not known at all
		--     OR auraIsActive(13750)     -- the Adrenaline Rush's buff rides
		--     OR spellTimeToReady(13750) > spellFullCooldown(1259812)
		--     OR remainingTime < spellTimeToReady(13750) )
		-- The first two gates are the house's utility readiness (known + usable +
		-- off cooldown); the base cooldown is the racial's own full cooldown
		-- (api.GetSpellBaseCooldown, in seconds - a non-positive reading is "no
		-- value" and the row under-prompts instead of guessing). The FOURTH
		-- disjunct (the fight is about to end) has no read in the shipped tree,
		-- so the row can only fire off the three proven ones.
		inputs.gnome_eureka_ready = utility_ready(self, "guide:gnome_eureka", "Eureka!", now)
		local eureka_entry = resolve_named_spell("guide:gnome_eureka", "Eureka!", now)
		if eureka_entry then
			local base_ms = api.GetSpellBaseCooldown(rogue_query(eureka_entry))
			if is_secret(base_ms) then
				base_ms = nil
			end
			if type(base_ms) == "number" and base_ms > 0 then
				inputs.gnome_eureka_full_cd = base_ms / 1000
			end
		end
		-- The Vanish cooldown (the Preparation row's NOT(spellIsReady(1857))) -
		-- the ranks of one spell share the cooldown, so the resolved rank
		-- answers for the APL's rank 2.
		local vanish_entry = resolve_named_spell("guide:vanish", "Vanish", now)
		if vanish_entry then
			inputs.vanish_cd_remaining = spell_cooldown(self, rogue_query(vanish_entry), now)
		end
		-- The Adrenaline Rush's time to ready (the paired pops' 1.9 m gate), its
		-- KNOWN-vs-ON-COOLDOWN split (the Eureka row's NOT(spellIsKnown) disjunct
		-- - ar_ready cannot tell them apart) and its buff (the Eureka row's
		-- auraIsActive(13750) disjunct).
		local paired_ar_entry = ST.ROGUE.spell_cache["hud:ar"]
		if not paired_ar_entry and SLOT_SPELL_NAMES.ar then
			paired_ar_entry = resolve_named_spell("hud:ar", SLOT_SPELL_NAMES.ar, now)
		end
		if paired_ar_entry then
			local ar_query = rogue_query(paired_ar_entry)
			inputs.ar_cd_remaining = spell_cooldown(self, ar_query, now)
			inputs.ar_known = api.is_spell_known(ar_query)
		end
		inputs.ar_buff_active = utility_aura_present("player", "HELPFUL", 13750)
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
	-- R3 short-CD row (competitor_gaps R3; rogue_deep §§2.4/2.7). Appended after
	-- the teardown order so existing indices never shift. Each new slot hides
	-- unless its hud_show_<key> toggle reads exactly true (nil = off): the HUD
	-- treats a nil toggle as wanted, so the provider-level hide below is the
	-- no-default-visible gate (options own the widgets; this lane adds none).
	{ key = "kidney", title = "Kidney Shot", kind = "spell" },
	{ key = "restealth", title = "Re-stealth", kind = "spell" },
	{ key = "bandage", title = "Bandage", kind = "spell" },
	-- Cold Blood (audit F3/V-G5): the cooldown the engine prompts on TBC/FOREVER.
	-- Appended before the self-served trinkets so they stay last. No
	-- default-visible change - hides unless hud_show_coldblood reads exactly
	-- true (nil = off; options own the widget, filed as follow-up).
	{ key = "coldblood", title = "Cold Blood", kind = "spell" },
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
	local remaining, duration = spell_cooldown(self, rogue_query(entry), now)
	if remaining then
		s.remaining, s.duration = remaining, duration
		s.text_remaining = remaining
		s.desaturate = true
	else
		s.remaining = 0
	end
	local usable = api.IsSpellUsable(rogue_query(entry))
	if usable == false then
		s.usable = false
	end
	return s
end

-- Slots that never borrow the GCD swipe (the paladin's judgement/wings rule in
-- classes/paladin.lua): every rogue slot is rotational, so the set is empty and
-- every ready slot shows the running GCD (warrior.lua:3035-3038 shape).
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

-- Borrow the running GCD onto a ready slot (hunter.lua:1901-1908 shape): the
-- swipe fills only when nothing else paints (no real cooldown, no live aura,
-- not hidden). A running cooldown or aura short-circuits first (the bar
-- precedent: on_cd wins, the GCD only covers the ready state).
local function hud_borrow_gcd(s, self, key, now)
	if s.hidden or HUD_SKIP_GCD[key] then
		return s
	end
	if s.remaining ~= 0 then
		return s
	end
	local g, gd = hud_gcd_remaining(self, now)
	if g > 0 then
		s.remaining, s.duration = g, gd
		s.text_remaining = g
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
			return hud_borrow_gcd(hud_aura_state(s, self, entry, "player", "HELPFUL", now), self, key, now)
		end
		-- Adrenaline Rush / Blade Flurry: the buff window outranks the ability
		-- cooldown (the teardown's buff tracker shape); while on cooldown the icon
		-- swipes and greys. A stacked multi-CD state (R3 yellow glow, rogue_deep
		-- §2.7) forces the glow while the buff rides.
		local found, remaining, duration = find_unit_aura("player", "HELPFUL",
			entry.id, entry.name, now)
		if found then
			s.remaining = remaining
			s.duration = duration
			local stacked = count_stacked_offensives(self, now)
			local glow_ok = false
			local rg = st.rogue_guide
			if rg and type(rg.stacked_glow) == "function" then
				glow_ok = rg.stacked_glow(stacked) == true
			elseif type(stacked) == "number" then
				glow_ok = stacked >= 2
			end
			if glow_ok then
				s.glow = true
			end
			return s
		end
		if auras_may_be_secret(self, now) then
			s.hidden = true
			return s
		end
		return hud_borrow_gcd(hud_cooldown_state(s, self, entry, now), self, key, now)
	end
	if key == "rupture" or key == "ea" then
		local entry = ST.ROGUE.spell_cache["hud:" .. key]
		if not entry then
			s.hidden = true
			return s
		end
		return hud_borrow_gcd(hud_aura_state(s, self, entry, "target", "HARMFUL", now), self, key, now)
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
			spell_remaining, duration = spell_cooldown(self, rogue_query(entry), now)
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
		return hud_borrow_gcd(s, self, key, now)
	end
	if key == "kick" then
		local entry = ST.ROGUE.spell_cache["hud:kick"]
		if not entry then
			s.hidden = true
			return s
		end
		hud_cooldown_state(s, self, entry, now)
		local in_range = api.IsSpellInRange(rogue_query(entry), "target")
		if in_range == false then
			s.in_range = false
		end
		return hud_borrow_gcd(s, self, key, now)
	end
	if key == "coldblood" then
		-- Cold Blood: no default-visible change - a nil toggle hides (the HUD
		-- treats nil as wanted, so this provider-level hide is the gate;
		-- options own the widget, filed as follow-up).
		if not shortcd_wanted(self, key) then
			s.hidden = true
			return s
		end
		local entry = ST.ROGUE.spell_cache["hud:coldblood"]
		if not entry then
			s.hidden = true
			return s
		end
		return hud_borrow_gcd(hud_cooldown_state(s, self, entry, now), self, key, now)
	end
	if key == "kidney" or key == "restealth" or key == "bandage" then
		-- R3 short-CD row: no default-visible change - a nil toggle hides.
		if not shortcd_wanted(self, key) then
			s.hidden = true
			return s
		end
		local entry = ST.ROGUE.spell_cache["hud:" .. key]
		if not entry then
			s.hidden = true
			return s
		end
		if key == "kidney" then
			-- Kidney Shot: ability-cooldown swipe + melee-range tint (Kick shape).
			hud_cooldown_state(s, self, entry, now)
			local in_range = api.IsSpellInRange(rogue_query(entry), "target")
			if in_range == false then
				s.in_range = false
			end
			return hud_borrow_gcd(s, self, key, now)
		end
		if key == "restealth" then
			-- Re-stealth (Vanish mapping UNCONFIRMED, see SLOT_SPELL_NAMES): the
			-- buff window outranks the cooldown (AR/BF shape); absent under a
			-- secret regime is unknown (hidden), never "ready".
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
			return hud_borrow_gcd(hud_cooldown_state(s, self, entry, now), self, key, now)
		end
		-- Bandage (rank UNCONFIRMED, see SLOT_SPELL_NAMES): the item cooldown
		-- outranks the spell cooldown (Tea shape); an answered zero count greys
		-- the icon, an absent probe stays silent.
		local remaining, duration = bandage_item_cooldown(now)
		if remaining then
			s.remaining, s.duration = remaining, duration
			s.text_remaining = remaining
			s.desaturate = true
		else
			local spell_remaining
			spell_remaining, duration = spell_cooldown(self, rogue_query(entry), now)
			if spell_remaining then
				s.remaining, s.duration = spell_remaining, duration
				s.text_remaining = spell_remaining
				s.desaturate = true
			else
				s.remaining = 0
			end
		end
		local count = bandage_item_count()
		if count ~= nil then
			s.count = count
			if count <= 0 then
				s.desaturate = true
				s.usable = false
			end
		end
		return hud_borrow_gcd(s, self, key, now)
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
		st.utils.apply_font(ss_text, STANDARD_TEXT_FONT, 10, "OUTLINE")
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
		st.utils.apply_font(swap_text, STANDARD_TEXT_FONT, 9, "OUTLINE")
		swap_text:SetText(ST.ROGUE.SWAP_COST_TEXT)
		swap_text:Hide()
		vf.rogue_swap_text = swap_text

		-- Poison reminder: one line under the bar; only presence is reported (the
		-- charge probe shape is UNCONFIRMED in-client).
		local poison_text = vf:CreateFontString(nil, "OVERLAY")
		poison_text:SetPoint("TOP", vf, "BOTTOM", 0, -2)
		poison_text:SetJustifyH("CENTER")
		st.utils.apply_font(poison_text, STANDARD_TEXT_FONT, 9, "OUTLINE")
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

-- The MH/OH poison reminder text, or nil when unknown/nothing to report. The presence
-- booleans come from compat (st.api.GetWeaponEnchantInfo: four values per weapon slot on
-- the client, hasOffHandEnchant the fifth). Charges are deliberately absent (the probe
-- shape is UNCONFIRMED, rogue_deep §5.8): only the presence booleans are consumed, and a
-- non-boolean reading never claims "no poison".
local function poison_reminder_text()
	local has_mh, has_oh = api.GetWeaponEnchantInfo()
	if type(has_mh) ~= "boolean" or type(has_oh) ~= "boolean" then
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
			if self.rogue_poison_color_applied ~= colour then
				self.rogue_poison_color_applied = colour
				poison_text:SetTextColor(self:convert_color(colour))
			end
			poison_text:Show()
		end
	end
end

--=========================================================================================
-- Lifecycle + per-frame hook
--=========================================================================================
function ST.ROGUE.post_init(self)
	-- SoD latch: ERA family + the SoD-only Envenom rune known (strict == true;
	-- nil/false reads Era-base). Frozen here like the warrior spec/rune probes -
	-- a rune (un)learned mid-session needs /reload. It runs BEFORE the spell ids
	-- are resolved: the builder's family gate reads the latch (BS-6 - the SoD
	-- client builds with a rune, never with Hemorrhage).
	self.rogue_is_sod = st.family == "ERA"
		and api.is_spell_known(ROGUE_SOD_ENVENOM_RUNE_ID) == true
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
	-- Runs before the practice init below: the shared post_init order is guide,
	-- HUD, practice in all six class modules (deep-audit F9).
	if st.hud then
		st.hud.init(self)
	end
	-- Practice: builds the shared session panel/frames; guarded so a flavor
	-- without the practice files stays inert (the paladin wires it the same way
	-- in classes/paladin.lua, the druid in classes/druid.lua). The session
	-- itself is class-agnostic - the options Practice toggle starts it (and
	-- /st practice toggles the same session), the panel icons cast the
	-- simulated spells - and the seam below keeps that flow rogue-safe.
	if st.practice_ui and type(st.practice_ui.init) == "function" then
		-- The practice panel's action vocabulary: the class's own guide slots plus
		-- the common abilities (a heal, food, a movement ability). The guide frame
		-- above already built its icons from the display vocabulary, so this widens
		-- the PANEL's strip, not the frame (the shaman's apply_family_slots
		-- precedent).
		ST.ROGUE.apply_practice_panel_actions()
		st.practice_ui.init(self)
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
	if type(db) ~= "table" then
		-- PROPER: every widget below reads this table; with no profile there is
		-- nothing configured to draw. The swing bars still render (bars.lua owns
		-- them), so skipping the tick hides nothing live.
		return
	end
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
	-- Runs after the guide tick above: the shared per-frame order is guide then
	-- HUD in all six class modules (deep-audit F8).
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

--=========================================================================================
-- Practice: the rogue seam on the shared practice session
--=========================================================================================
-- The session runs how it has always run: the options Practice toggle starts it
-- (and /st practice toggles the same session) and the panel icons cast the
-- simulated spells (practice_ui.lua, class-agnostic). This seam only keeps that
-- flow rogue-safe and routes the rogue drills:
--   * practice_sync reports no seal state (the rogue has none to mirror), so the
--     shared bridge never stamps paladin seal fields onto a rogue session;
--     practice_ui.sync_to_addon calls it through the ROGUE branch there.
--   * the scenario wrappers below drive the rogue_energy_pool + rogue_ss_window
--     drills (practice.lua registry) through the shared scoring pipeline, the
--     same entry points any caller (the toggle-started session, an options tab)
--     uses. Drill selection stays the caller's job: the pool drill runs on every
--     client, the SS drill only where the caller reads a swing (Era sword timing;
--     rogue_deep REFUTED it on TBC+).
-- Every entry degrades to nil/0/false when the practice modules are absent (a
-- flavor without them), never an error; nothing here shows without the explicit
-- toggle (opt-in, no default-visible change).
function ST.ROGUE.practice_sync(self)
	return 0
end

-- The harness drill this class practices (practice.lua registry): the key when the
-- module is loaded and carries the spec, nil otherwise (unknown-hides).
function ST.ROGUE.practice_scenario_key()
	local pr = st.practice
	if pr and pr.harness and pr.harness.get_scenario
		and pr.harness.get_scenario("rogue_energy_pool") then
		return "rogue_energy_pool"
	end
	return nil
end

-- The Era-only SS-after-swing drill (practice.lua registry): the key when the
-- module carries the spec, nil otherwise (unknown-hides, same contract).
function ST.ROGUE.practice_ss_scenario_key()
	local pr = st.practice
	if pr and pr.harness and pr.harness.get_scenario
		and pr.harness.get_scenario("rogue_ss_window") then
		return "rogue_ss_window"
	end
	return nil
end

-- Start a drill run: a harness session for the rogue energy-pool drill, begun at
-- `now`. Returns the session, or nil when the drill is unavailable. The run
-- itself begins through practice_begin_session (the Start Fight button
-- re-begins the same session object).
function ST.ROGUE.new_practice_session(now, opts)
	local pr = st.practice
	if not (pr and pr.harness and pr.harness.new_session) then
		return nil
	end
	if ST.ROGUE.practice_scenario_key() == nil then
		return nil
	end
	return pr.harness.new_session("rogue_energy_pool", now, opts)
end

-- Start an SS-after-swing drill run (Era sword timing: strike 0.1-0.2 s after the
-- mainhand swing lands). Same create-only contract as the pool drill.
function ST.ROGUE.new_ss_session(now, opts)
	local pr = st.practice
	if not (pr and pr.harness and pr.harness.new_session) then
		return nil
	end
	if ST.ROGUE.practice_ss_scenario_key() == nil then
		return nil
	end
	return pr.harness.new_session("rogue_ss_window", now, opts)
end

-- Begin (or re-begin) a drill run at `now`: fires the harness windows for the
-- session the constructors above created. The Start Fight button re-begins the
-- live session through this entry. False on an unavailable drill module.
function ST.ROGUE.practice_begin_session(session, now)
	local pr = st.practice
	if not (session and pr and pr.harness and pr.harness.begin_session) then
		return false
	end
	return pr.harness.begin_session(session, now)
end

-- Run one drill tick through the harness (drives the drill clock).
function ST.ROGUE.tick_practice_session(session, now, elapsed, out)
	local pr = st.practice
	if not (session and pr and pr.harness and pr.harness.tick_session) then
		return out
	end
	return pr.harness.tick_session(session, now, elapsed, out)
end

-- Grade one energy spend at `now`: start_fraction is the spend-start fraction of
-- the 2 s tick cycle, clip_amount the measured tick clip (or nil). The harness
-- grades the offset from the tick marker, counts the spend and records the
-- attempt on the session score. Returns the grade (S..F) or nil when the spend
-- cannot be scored (unknown tick reads never guess).
function ST.ROGUE.practice_spend(session, now, start_fraction, clip_amount)
	local pr = st.practice
	if not (session and pr and pr.harness and pr.harness.scenario_event
		and pr.harness.record_session_attempt) then
		return nil
	end
	local key = start_fraction
	if type(clip_amount) == "number" then
		key = { start = start_fraction, clip = clip_amount }
	end
	local grade = pr.harness.scenario_event(session, key, now)
	if grade ~= nil then
		pr.harness.record_session_attempt(session, grade)
	end
	return grade
end

-- Grade one Sinister Strike at `now`: offset is the seconds between the mainhand
-- swing landing and the strike start. Same record-on-score contract; an
-- unreadable swing record grades nil, never a guessed window.
function ST.ROGUE.practice_ss(session, now, offset)
	local pr = st.practice
	if not (session and pr and pr.harness and pr.harness.scenario_event
		and pr.harness.record_session_attempt) then
		return nil
	end
	local grade = pr.harness.scenario_event(session, offset, now)
	if grade ~= nil then
		pr.harness.record_session_attempt(session, grade)
	end
	return grade
end

-- The panel drill order (same grid, same casts-are-simulated flow): the pool
-- spend first, the Era SS window second. The shell filters it through
-- practice_cast_order below, so the panel never offers a drill the client
-- cannot run.
ST.ROGUE.PRACTICE_CAST_ORDER = { "evisc", "ss" }

-- The drill order this client actually runs: the pool spend everywhere, the SS
-- window only where the technique is valid (Era sword timing; rogue_deep
-- REFUTED it on TBC+, so TBC+ never offers the icon). Empty (never nil) when
-- the registry is absent - the panel builds nothing instead of guessing.
function ST.ROGUE.practice_cast_order()
	local order = {}
	if ST.ROGUE.practice_scenario_key() == nil then
		return order
	end
	order[#order + 1] = "evisc"
	if st.family == "ERA" and ST.ROGUE.practice_ss_scenario_key() ~= nil then
		order[#order + 1] = "ss"
	end
	return order
end

-- Panel ability labels for the drill casts (the drill's own wording, not a
-- spell link): the pool spend and the Era SS window.
local PRACTICE_CAST_NAMES = {
	evisc = "Pool Spend",
	ss = "SS Window",
}

-- The panel label for a drill key, or nil for an unknown key (the icon builder
-- skips unknown keys instead of drawing a guessed icon).
function ST.ROGUE.practice_cast_label(key)
	return PRACTICE_CAST_NAMES[key]
end

-- Icon art for a drill key: the spent finisher and the timed strike, resolved
-- by English name through the client's own spell data (the drill's name-art rule:
-- a client that answers the name shows its own rank art - whether the classic-line
-- global GetSpellInfo takes a name at all is UNCONFIRMED in-client,
-- bench/final_gate_audit_2026-10-20.md §6 C1 - and an unanswered name leaves the
-- icon blank rather than guessed).
local PRACTICE_CAST_ICONS = {
	evisc = "Eviscerate",
	ss = "Sinister Strike",
}

function ST.ROGUE.practice_cast_spell_id(key)
	return PRACTICE_CAST_ICONS[key]
end

-- Grade one drill cast at `now`: `drill` is the shell-owned run state
-- ({ energy = <pool session>, ss = <window session>, tick = { start, interval },
-- swing = { swing_start, ... } }). The pool spend grades where in the 2 s tick
-- cycle the cast lands; the SS cast grades the seconds since the drill swing
-- landed. Returns the grade (S..F) or nil when the cast cannot be scored
-- (unknown reads never guess; unknown keys never score).
function ST.ROGUE.practice_cast(drill, now, key)
	if type(drill) ~= "table" or type(now) ~= "number" then
		return nil
	end
	if key == "evisc" then
		local tick = drill.tick
		if type(tick) ~= "table" then
			return nil
		end
		local interval, start = tick.interval, tick.start
		if type(interval) ~= "number" or interval <= 0
			or type(start) ~= "number" then
			return nil
		end
		local fraction = ((now - start) % interval) / interval
		return ST.ROGUE.practice_spend(drill.energy, now, fraction)
	elseif key == "ss" then
		local swing = drill.swing
		if type(swing) ~= "table" or type(swing.swing_start) ~= "number" then
			return nil
		end
		return ST.ROGUE.practice_ss(drill.ss, now, now - swing.swing_start)
	end
	return nil
end

-- Info-line readout for the drill panel: the live tick countdown (same line,
-- drill readout). "--" when the drill clock cannot be read, never a guess.
function ST.ROGUE.practice_status(drill, now)
	local tick = type(drill) == "table" and drill.tick or nil
	if type(tick) ~= "table" or type(tick.interval) ~= "number"
		or tick.interval <= 0 or type(tick.start) ~= "number"
		or type(now) ~= "number" then
		return "Pool: --"
	end
	local remain = tick.interval - ((now - tick.start) % tick.interval)
	return string.format("Tick %.1fs", remain)
end

-- Seconds since the drill run began (the panel fight clock), or nil without a
-- begun session. Read-only: never allocates or begins anything.
function ST.ROGUE.practice_fight_elapsed(session, now)
	if type(session) ~= "table" or type(session.started_at) ~= "number"
		or type(now) ~= "number" then
		return nil
	end
	if session.active ~= true then
		return nil
	end
	local elapsed = now - session.started_at
	if elapsed < 0 then
		return 0
	end
	return elapsed
end

-- Carry the drill clocks over the real-combat pause (the shared session freezes
-- while ST.in_combat; on resume every future drill deadline shifts by the pause
-- so nothing lands retroactively). Nil-safe: missing clocks stay missing.
function ST.ROGUE.practice_shift_pause(drill, shift)
	if type(drill) ~= "table" or type(shift) ~= "number" or shift <= 0 then
		return
	end
	local tick = drill.tick
	if type(tick) == "table" and type(tick.start) == "number" then
		tick.start = tick.start + shift
	end
	local swing = drill.swing
	if type(swing) == "table" then
		if type(swing.swing_start) == "number" then
			swing.swing_start = swing.swing_start + shift
		end
		if type(swing.swing_ends_at) == "number" then
			swing.swing_ends_at = swing.swing_ends_at + shift
		end
	end
end

-- End a drill run (stops the harness session). Safe on an ended or nil session.
function ST.ROGUE.end_practice_session(session, now)
	local pr = st.practice
	if not (session and pr and pr.harness and pr.harness.end_session) then
		return false
	end
	return pr.harness.end_session(session, now)
end

--=========================================================================================
-- Rotation text: the rogue rotation source
--=========================================================================================
-- Implements the frozen ST.<CLASS>.get_rotation_key contract documented in
-- rotationtext.lua's header, following the hunter's shape (ST.HUNTER.
-- get_rotation_key in classes/hunter.lua:1337-1352): the guide's own decision, so
-- the label and the guide can never disagree. The rogue engine names no rotations
-- (its out.rotation_key is always nil), so the label is the current action: the
-- recommended ability's localized name (resolved from the guide's own slot
-- descriptors, cached per spell id), POOL while the engine holds, nil when the
-- guide is idle (renders as the empty text). No rotation-text practice branch:
-- the label never guesses off sim state; the rogue practice seam (registry
-- drills) rides the shared session instead.
-- One reused output table: no per-tick allocation on the label tick.
ST.ROGUE.rotation_out = {}

-- The guide slot's localized spell name for an action key (the slot's current-rank
-- spell id, so a re-pointed icon re-points the label with it). Wired audit
-- actions (snd/ar/bf/coldblood) resolve through their slots; an unresolved
-- spell falls back to the English name; anything else renders as the raw action
-- key (no consumer change). Falls back to the raw action key when the client's
-- spell data has not answered yet.
local rotation_name_cache = {}

local ACTION_FALLBACK_NAMES = {
	snd = "Slice and Dice",
	ar = "Adrenaline Rush",
	bf = "Blade Flurry",
	coldblood = "Cold Blood",
	-- Hunger for Blood (Wrath sin; the guide slot is not shipped - the slot
	-- contract is frozen - so the rotation label names the upkeep instead).
	hfb = "Hunger for Blood",
	-- The APL utility layer (the slot-less rows - the same contract as the
	-- upkeep rows above: the rotation label names them).
	vanish = "Vanish",
	ambush = "Ambush",
	garrote = "Garrote",
	preparation = "Preparation",
	premeditation = "Premeditation",
	venom = "Venom",
	poisoned_knife = "Poisoned Knife",
	blood_fury = "Blood Fury",
	elunes_light = "Elune's Light",
	gnome_eureka = "Eureka!",
	tricks_of_the_trade = "Tricks of the Trade",
	killing_spree = "Killing Spree",
}

local function rotation_ability_name(action)
	local query
	local fallback_name
	local slots = ST.ROGUE.guide.slots
	for i = 1, #slots do
		if slots[i].key == action then
			query = slots[i].spell_id
			fallback_name = slots[i].spell_name
			break
		end
	end
	-- Name-vs-id rule (operator 2026-10-19): TBC slots store the English name,
	-- so the label uses it directly and never issues a bare-id GetSpellInfo;
	-- Era slots store the id and resolve the localized name through it.
	if type(query) == "string" then
		return query
	end
	if query then
		local name = rotation_name_cache[query]
		if not name then
			name = api.GetSpellInfo(query)
			if name then
				rotation_name_cache[query] = name
			end
		end
		if name then
			return name
		end
	end
	if fallback_name then
		return fallback_name
	end
	return ACTION_FALLBACK_NAMES[action] or action
end

function ST.ROGUE.get_rotation_key(self)
	local guide = ST.ROGUE.guide
	local engine = st.rogue_guide
	if not (guide and guide.gather and guide.evaluate and engine and engine.evaluate) then
		return nil
	end
	local out = guide.evaluate(guide.gather(self, ST.ROGUE.guide_inputs),
		ST.ROGUE.rotation_out)
	if out.action ~= nil then
		return rotation_ability_name(out.action)
	end
	if out.hold then
		return out.hold_text
	end
	return nil
end

--=========================================================================================
-- Practice: the rotation table, the scenario step and the target drill set
--=========================================================================================
-- The shared practice engine (practice.lua / practice_ui.lua - a sibling lane owns
-- those files) looks the class side up by player_class, so everything the engine
-- needs from the rogue lives here under the fixed names:
--   ST.ROGUE.practice_rotation        the rotation table in sim priority order
--   ST.ROGUE.practice_scenario_step   one tick of the rotation scenario
--   ST.ROGUE.practice_drills          the target drill set (the practice audit's C)
-- plus the two optional members the engine reads when the class publishes them:
--   ST.ROGUE.practice_rotation_for    the family's slice of the rotation table
--   ST.ROGUE.practice_rotation_family the family the running client plays
--   ST.ROGUE.practice_context         the ctx the step and the drills read
--
-- No decision is re-implemented here: every verdict comes from the pure engine
-- (rogue_guide.lua's practice surface - the same evaluate the guide shows), so a
-- drill teaches exactly what the guide teaches. Nothing in this section changes
-- what the client shows the player - the table, the step and the drills are
-- consumed by the practice surface only, and every entry degrades to nil when its
-- inputs are missing (unknown-hides: no advice beats wrong advice).

-- The families each rotation step is played on. The sets mirror the engine's own
-- gates (rogue_guide.lua): the SnD/EA/Tea/AR rows exist only for the classic-line
-- families, Shiv only on ERA+TBC (SHIV_FAMILIES), Cold Blood only on TBC+FOREVER
-- (CB_FAMILIES), Blade Flurry on the four classic families (BF_FAMILIES), Hunger
-- for Blood only on WRATH (HFB_FAMILIES), and Rupture only on the rupture-first
-- families (the Era sims are Eviscerate-only - audit E-C1). RETAIL has no sim
-- (audit R-22) and no slice at all, so the scenario is never offered there (the
-- audit's §4.6); the SoD token plays the Era slice, because the SoD rows ride the
-- same action keys (the provider's SoD latch).
local PRACTICE_FAMILIES_CLASSIC = { ERA = true, SOD = true, TBC = true, WRATH = true, FOREVER = true }
local PRACTICE_FAMILIES_SHIV = { ERA = true, SOD = true, TBC = true }
local PRACTICE_FAMILIES_RUPTURE = { TBC = true, WRATH = true, FOREVER = true }
local PRACTICE_FAMILIES_TBC_FOREVER = { TBC = true, FOREVER = true }
local PRACTICE_FAMILIES_WRATH = { WRATH = true }
-- The SoD token (the SoD build of the ERA family) and the single-family gates of
-- the APL utility layer. The SoD rows ride the same action keys as the Era rows
-- (the provider's SoD latch), so the shared rows carry SOD as well - but the
-- SoD-ONLY rows (the Saber Slash builder, the Poisoned Knife window, the SoD
-- Vanish) are gated on the SOD token alone: the plain Era APL carries no such
-- row, and the Era client must never see them.
local PRACTICE_FAMILIES_SOD = { SOD = true }
local PRACTICE_FAMILIES_TBC = { TBC = true }
local PRACTICE_FAMILIES_FOREVER = { FOREVER = true }

-- The rotation table (the practice audit's S-R, "the combat rotation, end to
-- end"): the engine's rule order as the sim APLs state it, each entry citing its
-- source. The order IS the shipped rule order (rogue_guide.lua's header, rules
-- 1..7) - every family's APL puts the upkeep actions first and the builder last.
-- The sources (fetched 2026-10-19):
--   wowsims/classic     ui/rogue/apls/combat_sinister_strike.apl.json (+ _sweaty, _iea)
--   wowsims/sod         ui/rogue/apls/P5_Saber.apl.json + mutilate.apl.json
--   wowsims/tbc-new     ui/specs/rogue/dps/apls/swords.apl.json
--   wowsims/wotlk       ui/rogue/apls/combat.apl.json + mutilate.apl.json
--   wowsims/forever     ui/specs/rogue/dps/apls/default.apl.json
ST.ROGUE.practice_rotation = {
	{
		action = "expose",
		label = "Expose Armor",
		rule = "1",
		note = "the Expose Armor duty refresh",
		source = "classic combat_sinister_strike_iea.apl.json (Expose Armor 11198 at 5CP, remains<=3s); tbc-new swords.apl.json (the Expose group: 6s imminent, 15s minimum)",
		families = PRACTICE_FAMILIES_CLASSIC,
	},
	{
		action = "snd",
		label = "Slice and Dice",
		rule = "1b",
		note = "the Slice and Dice upkeep",
		source = "wotlk combat.apl.json (auraRemainingTime(SnD) <= 1s -> cast); tbc-new/classic slice_and_dice.go (per-CP durations 9/12/15/18/21 s); sod P5_Saber.apl.json (4+CP)",
		families = PRACTICE_FAMILIES_CLASSIC,
	},
	{
		action = "hfb",
		label = "Hunger for Blood",
		rule = "1c",
		note = "the Wrath sin upkeep",
		source = "wotlk mutilate.apl.json (auraRemainingTime(Hunger for Blood) <= 1s -> cast) - Wrath only",
		families = PRACTICE_FAMILIES_WRATH,
	},
	{
		action = "shiv",
		label = "Shiv",
		rule = "2",
		note = "the Deadly Poison upkeep",
		source = "tbc-new swords.apl.json + shiv.go (non-Mutilate, below 5CP; the EA-context check is filed)",
		families = PRACTICE_FAMILIES_SHIV,
	},
	{
		action = "envenom",
		label = "Envenom",
		rule = "3",
		note = "the per-family Envenom rule",
		source = "sod P5_Saber.apl.json (Envenom-primary, 4+CP); wotlk combat.apl.json (Envenom 57993 at 4+CP)",
		families = PRACTICE_FAMILIES_CLASSIC,
	},
	{
		action = "eviscerate",
		label = "Eviscerate",
		rule = "4/5",
		note = "the dying-target dump; the Era planned finisher too",
		source = "classic combat_sinister_strike.apl.json (Eviscerate 31016 at 5CP when Slice and Dice is active); wotlk combat.apl.json (Eviscerate 48668 at 4+CP when the fight ends within 4s)",
		families = PRACTICE_FAMILIES_CLASSIC,
	},
	{
		action = "rupture",
		label = "Rupture",
		rule = "5",
		note = "the planned finisher on the rupture-first families",
		source = "tbc-new swords.apl.json (Rupture before Eviscerate); wotlk combat.apl.json (Rupture 48672 at 4-5CP with Slice and Dice >= 4s)",
		families = PRACTICE_FAMILIES_RUPTURE,
	},
	{
		action = "ar",
		label = "Adrenaline Rush",
		rule = "5b",
		note = "the energy-gated offensive cooldown",
		source = "tbc-new swords.apl.json (prepull at -1s, Adrenaline Rush at energy <= 40); classic combat_sinister_strike.apl.json (energy < 59 with a tick inside 1s); forever default.apl.json (<= 50 with Slice and Dice)",
		families = PRACTICE_FAMILIES_CLASSIC,
	},
	{
		action = "bf",
		label = "Blade Flurry",
		rule = "5c",
		note = "the offensive cooldown behind Slice and Dice",
		source = "wotlk combat.apl.json (Blade Flurry 13877 while Slice and Dice rides); tbc-new swords.apl.json; forever default.apl.json (when Slice and Dice is not imminent)",
		families = PRACTICE_FAMILIES_CLASSIC,
	},
	{
		action = "coldblood",
		label = "Cold Blood",
		rule = "5d",
		note = "the finisher cooldown behind Slice and Dice",
		source = "tbc-new swords.apl.json (Cold Blood 14177 with Slice and Dice); forever default.apl.json (Cold Blood at 5CP)",
		families = PRACTICE_FAMILIES_TBC_FOREVER,
	},
	{
		action = "tea",
		label = "Thistle Tea",
		rule = "6",
		note = "the energy-deficit item",
		source = "classic combat_sinister_strike_sweaty.apl.json (Thistle Tea 7676 at energy <= 29 with a tick outside 1s); tbc-new swords.apl.json (<= 30)",
		families = PRACTICE_FAMILIES_CLASSIC,
	},
	{
		action = "builder",
		label = "Builder",
		rule = "7",
		note = "the builder (Sinister Strike / Backstab / Mutilate / Saber Slash / Hemorrhage)",
		source = "classic combat_sinister_strike.apl.json (Sinister Strike 11294, the swing-gated builder); tbc-new swords.apl.json (Hemorrhage 26864 / Backstab 26863 / Mutilate 34413 / Sinister Strike 26862 - the bench corpus had the Sinister Strike / Hemorrhage ids swapped)",
		families = PRACTICE_FAMILIES_CLASSIC,
	},
	--=========================================================================================
	-- The APL utility layer (the operator's "a rotation that only carries the damage
	-- abilities is not the class's rotation" - bench/rotation_gap_vs_apl_2026-10-20.md §3).
	--
	-- The rows above are the shipped rule order; the rows below are the sims' own
	-- utility/spine rows, re-fetched 2026-10-20 from the APL files themselves (every
	-- groupReference expanded inline) and named against the sims' own spell data. Each
	-- row carries the same shape:
	--   action        the class's own action key (the engine's prompt key)
	--   label         the English name the panel shows
	--   rule          the engine rule that plays it (rogue_guide.lua's header)
	--   note          one line: what the row is
	--   source        the APL file + the priority index (+ the sim citation)
	--   spell_ids     the id this family's APL casts, per family (a family-split id
	--                 never rides one row: 1857 is Vanish rank 2 on the TBC and the
	--                 Forever clients, 14183 is Premeditation on every client, and
	--                 26864 / 16511 split Hemorrhage between TBC and Forever)
	--   spell_names   the client's English name for that id (the TBC client resolves
	--                 spells by NAME, the Era client by ID - bench/lessons.md)
	--   families      the family gate
	--   live          true when the line's READ exists in the shipped tree today (the
	--                 compat wrappers api.GetSpellCooldown / api.scan_unit_aura /
	--                 api.is_spell_known / api.GetSpellPowerCost /
	--                 api.GetSpellBaseCooldown - no new client API); false when it is
	--                 waiting for a read, which the row then names in `needs`
	--   engine        true when the frozen guide engine has an arm that can ask for
	--                 the line (rogue_guide.lua); false for the builder rows - the
	--                 engine's builder arm already plays them (the candidate chain
	--                 resolves the spell by NAME), and a second builder path would
	--                 double-prompt. A builder row's engine = false is a
	--                 DE-DUPLICATION, never a gap - every builder row says so in
	--                 its own note.
	--   needs         (a live = false row) the exact read (or APL gate) it waits for
	--=========================================================================================
	{
		action = "vanish",
		label = "Vanish",
		rule = "1d",
		note = "the SoD stealth opener (the Vanish -> Envenom row)",
		source = "wowsims/sod ui/rogue/apls/P5_Saber.apl.json i=7 (1856 r1: NOT the Master of Subtlety aura 425096 AND cp == 5 AND Envenom 399963 castable) - wowsims/sod sim/rogue/vanish.go (1856); wowsims/sod proto/rogue.proto:129 (RuneMasterOfSubtlety = 425096)",
		spell_ids = { SOD = 1856 },
		spell_names = { SOD = "Vanish" },
		families = PRACTICE_FAMILIES_SOD,
		live = true,
		engine = true,
	},
	{
		action = "poisoned_knife",
		label = "Poisoned Knife",
		rule = "1e",
		note = "the SoD's Deadly Poison window",
		source = "wowsims/sod ui/rogue/apls/P5_Saber.apl.json i=5 (425012: the target carries 4+ Deadly Poison stacks AND cp < 5 AND energy <= 80) - wowsims/sod proto/rogue.proto:119 (RunePoisonedKnife = 425012); wowsims/classic sim/rogue/poisons.go:160 (11356 = Deadly Poison rank 4)",
		spell_ids = { SOD = 425012 },
		spell_names = { SOD = "Poisoned Knife" },
		families = PRACTICE_FAMILIES_SOD,
		live = true,
		engine = true,
	},
	{
		action = "saber_slash",
		label = "Saber Slash",
		rule = "7",
		note = "the SoD builder (the APL's i=3 and i=11 rows) (the engine's builder action already plays it - engine = false is a de-duplication, not a gap)",
		source = "wowsims/sod ui/rogue/apls/P5_Saber.apl.json i=3 and i=11 (424785: the swing-gated builder) - wowsims/sod proto/rogue.proto:112 (RuneSaberSlash = 424785)",
		spell_ids = { SOD = 424785 },
		spell_names = { SOD = "Saber Slash" },
		families = PRACTICE_FAMILIES_SOD,
		live = true,
		engine = false,
	},
	{
		action = "vanish",
		label = "Vanish",
		rule = "1d",
		note = "the WotLK stealth opener",
		source = "wowsims/wotlk ui/rogue/apls/mutilate.apl.json i=4 (26889: NOT the 58426 aura) - wowsims/wotlk sim/rogue/vanish.go (26889); the same APL's prepullActions activateAura 58426 at -1 s (the aura's NAME is UNCONFIRMED)",
		spell_ids = { WRATH = 26889 },
		spell_names = { WRATH = "Vanish" },
		families = PRACTICE_FAMILIES_WRATH,
		live = true,
		engine = true,
	},
	{
		action = "tricks_of_the_trade",
		label = "Tricks of the Trade",
		rule = "5f",
		note = "the WotLK energy pop",
		source = "wowsims/wotlk ui/rogue/apls/combat.apl.json i=13 and mutilate.apl.json i=8 (57934: energy <= 50) - wowsims/wotlk sim/rogue/tricks_of_the_trade.go (57934)",
		spell_ids = { WRATH = 57934 },
		spell_names = { WRATH = "Tricks of the Trade" },
		families = PRACTICE_FAMILIES_WRATH,
		live = true,
		engine = true,
	},
	{
		action = "killing_spree",
		label = "Killing Spree",
		rule = "5g",
		note = "the WotLK energy pop",
		source = "wowsims/wotlk ui/rogue/apls/combat.apl.json i=14 (51690: energy <= 50) - wowsims/wotlk sim/rogue/killing_spree.go (51690)",
		spell_ids = { WRATH = 51690 },
		spell_names = { WRATH = "Killing Spree" },
		families = PRACTICE_FAMILIES_WRATH,
		live = true,
		engine = true,
	},
	{
		action = "hypersharp",
		label = "Hyperspeed Acceleration",
		rule = "-",
		note = "the WotLK belt-enchant effect (the sim casts the Engineering belt's haste proc; the client never teaches the rogue a spell for it, so there is nothing to ask for)",
		source = "wowsims/wotlk ui/rogue/apls/mutilate.apl.json i=6 and combat.apl.json i=10, i=11 (54758) - the CLIENT'S OWN name for 54758 is 'Hyperspeed Acceleration' (wowsims/wotlk assets/database - the client's own spell table, the spellIcons entry); it is the Engineering belt enchant's EFFECT ('Hyperspeed Accelerators', enchant effect 3604 - the sim models it as a 60 s cooldown that applies a 12 s haste aura, wowsims/wotlk sim/common/wotlk/enchant_effects.go) and NOT a rogue ability: 'Hypersharp Weapon' does not exist in the WotLK client (no hit in its spell, enchant or item tables)",
		spell_ids = { WRATH = 54758 },
		spell_names = { WRATH = "Hyperspeed Acceleration" },
		families = PRACTICE_FAMILIES_WRATH,
		live = false,
		engine = false,
		needs = "the belt enchant's own AVAILABILITY: 54758 is an ITEM effect, not a spell in the rogue's spellbook - api.is_spell_known reads false for it and api.GetSpellCooldown cannot see the item's cooldown, so no shipped read can gate the row (the belt's item cooldown through api.GetItemCooldown needs the belt's item name, and the haste buff's aura id is UNCONFIRMED in-client)",
	},
	{
		action = "mutilate",
		label = "Mutilate",
		rule = "7",
		note = "the WotLK builder (the mutilate APL's i=12 row) (the engine's builder action already plays it - engine = false is a de-duplication, not a gap)",
		source = "wowsims/wotlk ui/rogue/apls/mutilate.apl.json i=12 (48666: cast at cp <= 3) - wowsims/wotlk sim/rogue/mutilate.go (MutilateSpellID = 48666)",
		spell_ids = { WRATH = 48666 },
		spell_names = { WRATH = "Mutilate" },
		families = PRACTICE_FAMILIES_WRATH,
		live = true,
		engine = false,
	},
	{
		action = "ambush",
		label = "Ambush",
		rule = "1x",
		note = "the Forever opener",
		source = "wowsims/forever ui/specs/rogue/dps/apls/default.apl.json i=1 (11269: the 462707 aura is up AND cp < 5) - wowsims/forever sim/rogue/spell_data_auto_gen.go (Ambush: spelldata.Ranked(8676, 8724, 8725, 11267, 11268, 11269))",
		spell_ids = { FOREVER = 11269 },
		spell_names = { FOREVER = "Ambush" },
		families = PRACTICE_FAMILIES_FOREVER,
		live = true,
		engine = true,
	},
	{
		action = "garrote",
		label = "Garrote",
		rule = "1x",
		note = "the Forever opener (while its dot is down)",
		source = "wowsims/forever ui/specs/rogue/dps/apls/default.apl.json i=2 (11290: cp < 5 AND NOT(dotIsActive(11290))) - wowsims/forever sim/rogue/spell_data_auto_gen.go (Garrote: spelldata.Ranked(703, 8631, 8632, 8633, 11289, 11290))",
		spell_ids = { FOREVER = 11290 },
		spell_names = { FOREVER = "Garrote" },
		families = PRACTICE_FAMILIES_FOREVER,
		live = true,
		engine = true,
	},
	{
		action = "vanish",
		label = "Vanish",
		rule = "1x",
		note = "the Forever stealth opener (Vanish rank 2)",
		source = "wowsims/forever ui/specs/rogue/dps/apls/default.apl.json i=3 (1857 rank 2: NOT(dotIsActive(11290)) AND currentEnergy >= spellCurrentCost(11290) AND cp < 5 AND NOT(SnD Fall Imminent)) - wowsims/forever sim/rogue/spell_data_auto_gen.go (Vanish: spelldata.Ranked(1856, 1857) - 1857 is VANISH RANK 2 on this client, not Cloak of Shadows)",
		spell_ids = { FOREVER = 1857 },
		spell_names = { FOREVER = "Vanish" },
		families = PRACTICE_FAMILIES_FOREVER,
		live = true,
		engine = true,
	},
	{
		action = "preparation",
		label = "Preparation",
		rule = "1x",
		note = "the Forever prep (while Vanish is not ready)",
		source = "wowsims/forever ui/specs/rogue/dps/apls/default.apl.json i=5 (14185: NOT(spellIsReady(1857))) - wowsims/forever sim/rogue/spell_data_auto_gen.go (Preparation: spelldata.Ranked(14185))",
		spell_ids = { FOREVER = 14185 },
		spell_names = { FOREVER = "Preparation" },
		families = PRACTICE_FAMILIES_FOREVER,
		live = true,
		engine = true,
	},
	{
		action = "premeditation",
		label = "Premeditation",
		rule = "3a",
		note = "the Forever combo-point opener",
		source = "wowsims/forever ui/specs/rogue/dps/apls/default.apl.json i=17 (14183: cast while cp <= 3) - wowsims/forever sim/rogue/spell_data_auto_gen.go (Premeditation: spelldata.Ranked(14183) - the Forever client's 14183 is PREMEDITATION, not Shadowstep)",
		spell_ids = { FOREVER = 14183 },
		spell_names = { FOREVER = "Premeditation" },
		families = PRACTICE_FAMILIES_FOREVER,
		live = true,
		engine = true,
	},
	{
		action = "venom",
		label = "Venom",
		rule = "3b",
		note = "the Forever finisher (while its buff is down)",
		source = "wowsims/forever ui/specs/rogue/dps/apls/default.apl.json i=19 (1310703: the buff is down AND cp >= 3) - wowsims/forever sim/rogue/spell_data_auto_gen.go (Venom: spelldata.Ranked(1310703))",
		spell_ids = { FOREVER = 1310703 },
		spell_names = { FOREVER = "Venom" },
		families = PRACTICE_FAMILIES_FOREVER,
		live = true,
		engine = true,
	},
	{
		action = "blood_fury",
		label = "Blood Fury",
		rule = "5h",
		note = "the Forever paired pop (with Adrenaline Rush)",
		source = "wowsims/forever ui/specs/rogue/dps/apls/default.apl.json i=11 (20572: the Adrenaline Rush's time to ready is at/above 1.9 m) - wowsims/classic sim/core/racials.go:77 (20572, the Orc racial)",
		spell_ids = { FOREVER = 20572 },
		spell_names = { FOREVER = "Blood Fury" },
		families = PRACTICE_FAMILIES_FOREVER,
		live = true,
		engine = true,
	},
	{
		action = "elunes_light",
		label = "Elune's Light",
		rule = "5i",
		note = "the Forever paired pop (the id 1259799)",
		source = "wowsims/forever ui/specs/rogue/dps/apls/default.apl.json i=12 (1259799: the Adrenaline Rush's time to ready is at/above 1.9 m) - the NAME comes from the Forever druid APL's own variable (\"Elune's Light now\" -> castSpell 1259799, wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json)",
		spell_ids = { FOREVER = 1259799 },
		spell_names = { FOREVER = "Elune's Light" },
		families = PRACTICE_FAMILIES_FOREVER,
		live = true,
		engine = true,
	},
	{
		action = "gnome_eureka",
		label = "Eureka!",
		rule = "5j",
		note = "the Forever Gnome racial (the APL's own \"Gnome Eureka\" variable)",
		source = "wowsims/forever ui/specs/rogue/dps/apls/default.apl.json i=13 (1259812: the APL's own \"Gnome Eureka - Should Cast\" variable) - the CLIENT'S OWN name for 1259812 is 'Eureka!' (wowsims/forever assets/database - the client's own spell table, the spellIcons entry); it is the Gnome RACIAL (wowsims/forever sim/core/racials.go: applyEureka - the rogue's row is spellID 1259812 over the energy pool)",
		spell_ids = { FOREVER = 1259812 },
		spell_names = { FOREVER = "Eureka!" },
		families = PRACTICE_FAMILIES_FOREVER,
		live = true,
		engine = true,
	},
	{
		action = "mutilate",
		label = "Mutilate",
		rule = "7",
		note = "the Forever builder (the APL's i=26 row) (the engine's builder action already plays it - engine = false is a de-duplication, not a gap)",
		source = "wowsims/forever ui/specs/rogue/dps/apls/default.apl.json i=26 (1241584 rank 4: cp < 5) - wowsims/forever sim/rogue/spell_data_auto_gen.go (Mutilate: spelldata.Ranked(1310707, 399956, 1241582, 1241584))",
		spell_ids = { FOREVER = 1241584 },
		spell_names = { FOREVER = "Mutilate" },
		families = PRACTICE_FAMILIES_FOREVER,
		live = true,
		engine = false,
	},
	{
		action = "hemorrhage",
		label = "Hemorrhage",
		rule = "7",
		note = "the Forever builder (the APL's i=24 row) (the engine's builder action already plays it - engine = false is a de-duplication, not a gap)",
		source = "wowsims/forever ui/specs/rogue/dps/apls/default.apl.json i=24 (16511: the target does not carry Hemorrhage AND cp < 5; the APL's i=27 row is dead - its \"Use Backstab\" variable is true) - wowsims/forever sim/rogue/spell_data_auto_gen.go (Hemorrhage: spelldata.Ranked(16511))",
		spell_ids = { FOREVER = 16511 },
		spell_names = { FOREVER = "Hemorrhage" },
		families = PRACTICE_FAMILIES_FOREVER,
		live = true,
		engine = false,
	},
	{
		action = "backstab",
		label = "Backstab",
		rule = "7",
		note = "the Forever builder (the APL's i=25 row) (the engine's builder action already plays it - engine = false is a de-duplication, not a gap)",
		source = "wowsims/forever ui/specs/rogue/dps/apls/default.apl.json i=25 (11281: cp < 5) - wowsims/forever sim/rogue/spell_data_auto_gen.go (Backstab: spelldata.Ranked(53, 2589, 2590, 2591, 8721, 11279, 11280, 11281, 25300))",
		spell_ids = { FOREVER = 11281 },
		spell_names = { FOREVER = "Backstab" },
		families = PRACTICE_FAMILIES_FOREVER,
		live = true,
		engine = false,
	},
	{
		action = "ghostly_strike",
		label = "Ghostly Strike",
		rule = "7",
		note = "the Forever builder (the APL's i=23 row) (the engine's builder action already plays it - engine = false is a de-duplication, not a gap)",
		source = "wowsims/forever ui/specs/rogue/dps/apls/default.apl.json i=23 (14278: cp < 5) - wowsims/forever sim/rogue/spell_data_auto_gen.go (GhostlyStrike: spelldata.Ranked(14278))",
		spell_ids = { FOREVER = 14278 },
		spell_names = { FOREVER = "Ghostly Strike" },
		families = PRACTICE_FAMILIES_FOREVER,
		live = true,
		engine = false,
	},
	{
		action = "mutilate",
		label = "Mutilate",
		rule = "7",
		note = "the TBC builder (the APL's i=13 row) (the engine's builder action already plays it - engine = false is a de-duplication, not a gap)",
		source = "wowsims/tbc-new ui/specs/rogue/dps/apls/swords.apl.json i=13 (34413: cp < 5 OR the energy is at/above the pool threshold) - wowsims/tbc-new sim/rogue/spell_data_auto_gen.go (Mutilate: Ranked(1329, 34411, 34412, 34413))",
		spell_ids = { TBC = 34413 },
		spell_names = { TBC = "Mutilate" },
		families = PRACTICE_FAMILIES_TBC,
		live = true,
		engine = false,
	},
	{
		action = "hemorrhage",
		label = "Hemorrhage",
		rule = "7",
		note = "the TBC builder (the APL's i=10 row) (the engine's builder action already plays it - engine = false is a de-duplication, not a gap)",
		source = "wowsims/tbc-new ui/specs/rogue/dps/apls/swords.apl.json i=10 (26864: cp < 5 OR the energy is at/above the pool threshold) - wowsims/tbc-new sim/rogue/spell_data_auto_gen.go (Hemorrhage: Ranked(16511, 17347, 17348, 26864))",
		spell_ids = { TBC = 26864 },
		spell_names = { TBC = "Hemorrhage" },
		families = PRACTICE_FAMILIES_TBC,
		live = true,
		engine = false,
	},
	{
		action = "backstab",
		label = "Backstab",
		rule = "7",
		note = "the TBC builder (the APL's i=11 row - dead on that build) (the engine's builder action already plays it - engine = false is a de-duplication, not a gap)",
		source = "wowsims/tbc-new ui/specs/rogue/dps/apls/swords.apl.json i=11 (26863 rank 10) - wowsims/tbc-new sim/rogue/spell_data_auto_gen.go (Backstab: Ranked(53, 2589, 2590, 2591, 8721, 11279, 11280, 11281, 25300, 26863))",
		spell_ids = { TBC = 26863 },
		spell_names = { TBC = "Backstab" },
		families = PRACTICE_FAMILIES_TBC,
		live = false,
		engine = false,
		needs = "NOTHING TO READ: the APL's own \"Use Backstab\" gate is a BUILD CONSTANT (false) in the TBC APL's valueVariables (wowsims/tbc-new ui/specs/rogue/dps/apls/swords.apl.json), not a client-side state - the row is dead in the sim itself, so it is filed by construction and never evaluated (the class's builder arm is what plays Backstab, on a dagger mainhand)",
	},
}

-- The rotation family the running client plays: "SOD" on the ERA token with the
-- SoD-only Envenom rune known (the provider's frozen SoD latch), else the
-- compat family.
function ST.ROGUE.practice_rotation_family()
	if st.family == "ERA" and ST.rogue_is_sod == true then
		return "SOD"
	end
	return st.family
end

-- The family's slice of the rotation table: the entries that family plays, in
-- sim priority order. The SoD token is its OWN slice (the SoD rows ride the
-- same action keys as the Era rows, but the SoD-ONLY rows - the Saber Slash
-- builder, the Poisoned Knife window, the SoD Vanish - must never reach the
-- plain Era client: the Era APL carries no such row). A family the table does
-- not know plays NOTHING - the engine's own fallback (the guide slot vocabulary)
-- stands in, and the scenario is never offered on a client with no sim source
-- (RETAIL).
--
-- The slice is the rows the engine can ACTUALLY ask for (entry.engine ~= false
-- and entry.live ~= false): the panel's button row is a fixed strip, and a row
-- the engine can never emit - a builder row (the builder arm plays it) or a
-- filed row (its read does not exist yet) - is a button that can never be the
-- right answer. The builder rows and the filed rows stay in
-- ST.ROGUE.practice_rotation as the cited APL spine.
function ST.ROGUE.practice_rotation_for(family)
	local out = {}
	local want = family
	if type(want) ~= "string" or want == "" then
		want = ST.ROGUE.practice_rotation_family()
	end
	for i = 1, #ST.ROGUE.practice_rotation do
		local entry = ST.ROGUE.practice_rotation[i]
		if entry.engine ~= false and entry.live ~= false
			and (entry.families == nil or entry.families[want] == true) then
			out[#out + 1] = entry
		end
	end
	return out
end

--=========================================================================================
-- The NEUTRAL action set (the panel's legitimate-but-ungraded presses)
--
-- The shared engine grades a press against the rotation: the action the rotation
-- asks for is a HIT, any other action is a MIS-PICK (F) - and a NEUTRAL action is
-- neither (no attempt, no points, no streak change). The class publishes the keys
-- that are legitimate but that the rotation never asks for; the engine reads
-- ST.<CLASS>.practice_neutral_actions (the contract fixed by the orchestrator,
-- practice.lua's class contract block).
--
-- THE PUBLISH IS FAMILY-SCOPED (the shape the engine reads: a family key -> a
-- set of action keys, resolved for the running client family - st.family). A
-- family the class published no bucket for answers nil, and the engine then grades
-- every non-rotation press exactly as before (unknown-hides, never a guess).
--
-- THE CLOSED LIST (the class's own suite pins every clause):
--   * every key is a key the class's OWN panel offers - the guide slot key (the
--     panel's action row) or the class's own rotation key. No invented key;
--   * NO key in a family's bucket is a rotation action ON THAT FAMILY: a rotation
--     action can never be neutral (the engine grades the expected action first,
--     so a rotation press still hits - but a rotation action published as neutral
--     would make a WRONG rotation press free, which is the grading hole this
--     table must never open);
--   * every panel key is classified: a rotation action, a neutral action, or an
--     intentional mis-pick. A key nobody classified fails the suite, so the next
--     ability someone adds cannot silently become a free press.
--
-- THE KEYS:
--   coldblood  Cold Blood - the class's own rotation row is a TBC/FOREVER row
--              (families = { "TBC", "FOREVER" }), so the ERA branch and the
--              WotLK client have no rotation row that asks for Cold Blood, while
--              the talent exists on both. A Cold Blood press there is a
--              legitimate ability the rotation never grades, so it is NEUTRAL.
--              On TBC and Forever it IS a rotation row and is deliberately NOT
--              published here.
--   shiv       Shiv - the class's own rotation row is an ERA/SoD/TBC row
--              (families = { "ERA", "SOD", "TBC" }), so the WotLK client and the
--              Forever client have no rotation row that asks for Shiv, while the
--              ability exists on both. A Shiv press there is legitimate and
--              ungraded, so it is NEUTRAL. On the classic line it IS a rotation
--              row and is deliberately NOT published here.
--
-- THE KEYS THAT ARE DELIBERATELY NOT NEUTRAL:
--   rupture    Rupture - the class's own rotation row is a TBC/WRATH/FOREVER row,
--              and on the Era client the spell DOES NOT EXIST at all (it is a
--              TBC-era ability), so an Era press of it is an intentional mis-pick
--              (the panel offers the key - the guide slot set is flat - but the
--              client cannot cast it).
--   tea        Thistle Tea, snd, expose, envenom, eviscerate, ar, bf, builder -
--              rotation rows on every family.
--   the drill's own cast keys (PRACTICE_CAST_ORDER: evisc, ss) - those are the
--              DRILL's graded casts (the rogue_finisher_order drill grades the
--              pick), not rotation picks, and the engine's neutral set must never
--              touch a drill's own truth.
--
-- The abilities the orchestrator named for this class (Sprint, food and drink,
-- potions, Evasion, Cloak of Shadows, Preparation, Bloodlust) have NO key in the
-- rogue's own ability list - the class's guide slots carry no key for them
-- (Preparation and Vanish ARE rotation rows on the Forever client, and they are
-- graded there) - so publishing them would invent keys the class does not have.
--=========================================================================================
ST.ROGUE.practice_neutral_actions = {
	ERA = {
		coldblood = true,
		sprint = true,
		evasion = true,
		kick = true,
		healthstone = true,
		food = true,
	},
	TBC = {
		sprint = true,
		evasion = true,
		kick = true,
		healthstone = true,
		food = true,
	},
	WRATH = {
		coldblood = true,
		shiv = true,
		sprint = true,
		evasion = true,
		kick = true,
		healthstone = true,
		food = true,
	},
	FOREVER = {
		shiv = true,
		sprint = true,
		evasion = true,
		kick = true,
		healthstone = true,
		food = true,
	},
	-- THE CATA AND MISTS CLIENTS (the 4.4.3 and the 5.5.0 clients - the two TOCs
	-- that ship this addon, SwedgeTimer_Cata.toc and SwedgeTimer_Mists.toc) carry
	-- NO BUCKET HERE, and that is the class's own statement, not a gap:
	--
	--   * the class publishes NO rotation for either client (the rotation table
	--     carries no CATA / MISTS row and the utility spine names no family there),
	--     so on those two clients no row of the class's own is a rotation action. A
	--     bucket is the class's statement about a client it PLAYS; the class plays
	--     neither of these;
	--   * the class's guide vocabulary on those two clients is its own FLAT set, and
	--     that set is not the clients' own (the 4.0 client dropped the Shiv), so the
	--     class makes no statement about it there;
	--   * so the OFFER GATE (ST.ROGUE.practice_common_offer_allowed) offers NO
	--     common ability on those two clients: an ability the family does not
	--     publish as neutral can only be a mis-pick the moment it is pressed, so the
	--     panel does not offer it there. It stays available on the families where
	--     the class DOES publish it.
	--
	-- FOR THE RECORD (the clients' own spell pages - the /data/spell/<id> page on
	-- the warcraftdb site, on the Cataclysm and the MoP expansion domains, whose
	-- title carries the client's own spell name): the Cata and the Mists clients DO
	-- carry every one of the class's five common abilities - Sprint 2983, Evasion
	-- 5277, Kick 1766, the Healthstone (the clients' own rank is 6262 - the Era id
	-- 5720 answers "Not Found" there, and 6262 is a DIFFERENT spell on the classic
	-- clients - "Minor Healthstone" - so the ladder is NOT extended with it: the
	-- id table is the citation and the fallback, and the client's own rank only
	-- where that id still exists on it; the NAME-first leg finds the client's own
	-- rank only where the client ANSWERS the name, and whether the classic-line
	-- global takes a name at all is UNCONFIRMED in-client,
	-- bench/final_gate_audit_2026-10-20.md §6 C1) and the Food 433. The exclusion
	-- is a deliberate statement about a client the class does not play, not a
	-- belief that the client lacks the spells.
}

--=========================================================================================
-- The neutral set THIS class publishes for the RUNNING family
--
-- The engine reads the publish through its own accessor (practice.lua's
-- H.practice_neutral_actions) and resolves it for the running client family
-- (st.family): a FLAT publish answers itself, a family-scoped publish answers the
-- bucket for that family, and a family the class published no bucket for answers
-- nil (the engine then grades every non-rotation press exactly as it did before).
--
-- This accessor is that SAME rule, re-implemented here so the class never has to
-- ask the engine - and so the OFFER GATE below reads the class's OWN truth.
--
-- THE OFFER GATE READS IT (the orchestrator's ruling, 2026-10-20): an ability may
-- only be OFFERED on a family where it is either a rotation action or a neutral
-- action. An offer that can only ever be a mis-pick is a trap - the player is
-- invited to press something the grader will always punish. So the panel's
-- common-ability offer list and this set are ONE truth per family: an ability
-- with no neutral bucket on that family is NOT offered there (it stays available
-- on the families where it IS neutral).
--=========================================================================================
function ST.ROGUE.practice_neutral_set()
	local published = ST.ROGUE.practice_neutral_actions
	if type(published) ~= "table" then
		return nil
	end
	local source = published
	for _, value in pairs(published) do
		if type(value) == "table" then
			-- a family-scoped publish: the running family's own bucket
			source = published[st.family]
			break
		end
	end
	if type(source) ~= "table" then
		return nil
	end
	return source
end

-- The running family's ROTATION actions (the set the offer gate reads): the class's
-- own published slice for the running client, read the way the panel reads it (the
-- argument-free call - practice_ui.lua's scenario_action_order).
function ST.ROGUE.practice_rotation_action_set()
	local out = {}
	local ok, entries = pcall(function() return ST.ROGUE.practice_rotation_for() end)
	if not ok or type(entries) ~= "table" then
		return out
	end
	for i = 1, #entries do
		local entry = entries[i]
		if type(entry) == "table" and type(entry.action) == "string" and entry.action ~= "" then
			out[entry.action] = true
		end
	end
	return out
end

-- The class's own alias table (the spellings the engine or the sim may report, mapped
-- onto the canonical key). The rogue has none - its key space is one - so the
-- normaliser is the identity.
function ST.ROGUE.practice_canonical_key(key)
	local aliases = ST.ROGUE.practice_action_aliases
	if type(aliases) == "table" and type(key) == "string" then
		return aliases[key] or key
	end
	return key
end

-- THE OFFER GATE (the orchestrator's ruling, 2026-10-20): may this common ability be
-- OFFERED on the running family?
--
--   (1) the class's own per-ability family gate (the entry's `families` field) names
--       the running family - the class's own statement about the ability;
--   (2) the running family's published neutral set carries the key - the offer list
--       and the neutral set are ONE truth per family;
--   (3) the running family's rotation does not rank the key - a rotation action is
--       graded by the rotation, never an offered common ability.
--
-- A family the class published no neutral bucket for offers NO common ability: the
-- ability would be a mis-pick the moment it is pressed.
function ST.ROGUE.practice_common_offer_allowed(action, neutral, rotation)
	if type(action) ~= "table" or type(action.key) ~= "string" or action.key == "" then
		return false
	end
	local families = action.families
	if type(families) == "table" then
		local named = false
		for i = 1, #families do
			if families[i] == st.family then
				named = true
				break
			end
		end
		if not named then
			return false
		end
	end
	if type(neutral) ~= "table" or neutral[action.key] ~= true then
		return false
	end
	if type(rotation) == "table"
		and rotation[ST.ROGUE.practice_canonical_key(action.key)] == true then
		return false
	end
	return true
end

--=========================================================================================
-- The PRACTICE-PANEL ability list: the common abilities the panel offers
--
-- WHY THIS EXISTS: the practice panel's action row offers the class's whole ability
-- list, and a player legitimately presses a heal, food or a movement ability while
-- practicing. The engine grades such a press NEUTRAL - no attempt, no points, no
-- streak change, never a mis-pick (bench/practice_neutral_actions_2026-10-20.md). For
-- that the class needs a KEY for each of them: the panel's vocabulary is the rotation
-- slice plus the class's own guide slot list, and the common abilities had no key at
-- all (bench/class_neutral_actions_2026-10-20.md §2).
--
-- HOW IT REACHES THE PANEL: the list below is APPENDED to the class's own guide slot
-- list AFTER the guide frame has built its icons - the shaman's apply_family_slots
-- precedent (classes/shaman.lua). The frame stacks one icon per slot and fades in only
-- the CURRENT action's, and the frame's icons are built once and never rebuilt, so the
-- live next-action guide is untouched; the practice panel reads the slot list LIVE, so
-- the panel's action row offers the common abilities with their own icons.
--
-- THE IDS (cited, never invented):
--   * the resolution asks the client's own spell data for the ENGLISH spell NAME
--     (this file's own resolve_named_spell rule), and the id the client answers
--     WITH that name is its own rank's id - so a client that indexes the English
--     name shows its own rank art. Whether the classic-line global GetSpellInfo
--     takes a name at all is UNCONFIRMED in-client
--     (bench/final_gate_audit_2026-10-20.md §6 C1: the Blizzard UI calls the
--     classic global with an id and the Cata/Mists UI code with a name), so the
--     name leg is a claim the operator's in-client pass still owes;
--   * the id table is the CITATION and the fallback - it is NOT a guarantee of the
--     client's own art: a client that does not answer the name, or answers it
--     without an id, falls back to the ERA corpus's rank-1 ids, which is the
--     client's own rank only where that id still exists on it (the Healthstone:
--     the Era id 5720 answers "Not Found" on the Cata and the Mists clients,
--     whose own rank is 6262 - the ladder is deliberately not extended with it,
--     bench/class_neutral_family_coverage_2026-10-20.md §1.2);
--   * the query is family-correct (the operator's name-vs-id rule, bench/lessons.md):
--     the NAME on TBC (that client answers names, never bare ids), the numeric id on
--     every other family;
--   * the id sources: the Classic 1.15 client corpus (/home/sam/wow.export/Spell.csv
--     - the id plus the client's own description) and the client's spell names from
--     the Classic spell pages (the /data/spell/<id> page on the warcraftdb site - its
--     title carries the client's own spell name). The in-tree citations are named
--     per row.
--
-- UNKNOWN-HIDES: an ability the running client does not have is never offered - the
-- resolution drops it - so the panel never shows a button the client cannot cast.
--
-- NO ROTATION ACTION HERE: none of these keys is a rotation action on any family the
-- rogue plays (the class's own rotation rows: builder, rupture, eviscerate, envenom,
-- expose, shiv, tea, snd, ar, bf, coldblood), so none of them may be a rotation
-- action; the neutral set above publishes exactly these keys.
--=========================================================================================
ST.ROGUE.practice_common_actions = {
	{
		key = "sprint",
		label = "Sprint",
		names = { "Sprint" },
		-- 2983 - the client's Sprint (the corpus description: "Increases the rogue's
		-- movement speed by $s1% for $d. Does not break stealth."; the name confirmed
		-- at the Classic spell page (2983)). The rogue's own rotation rows
		-- carry no Sprint, so it is never a rotation action.
		ids = { 2983 },
	},
	{
		key = "evasion",
		label = "Evasion",
		names = { "Evasion" },
		-- 5277 - the client's Evasion (the name confirmed at
		-- the Classic spell page (5277)). No rogue rotation row asks for it.
		ids = { 5277 },
	},
	{
		key = "kick",
		label = "Kick",
		names = { "Kick" },
		-- 1766 - the client's Kick (the name confirmed at
		-- the Classic spell page (1766)). The name is already in this file's
		-- own slot table (SLOT_SPELL_NAMES.kick); no rogue rotation row asks for it.
		ids = { 1766 },
	},
	{
		key = "healthstone",
		label = "Healthstone",
		names = { "Healthstone" },
		-- 5720 - the client's Healthstone use effect (the corpus description:
		-- "Instantly restores $s1 life."; the name confirmed at
		-- the Classic spell page (5720)). The panel's vocabulary is SPELLS,
		-- so the use effect is the cited spell.
		ids = { 5720 },
	},
	{
		key = "food",
		label = "Food",
		names = { "Food" },
		-- 433 / 2639 / 5004 / 10256 / 10257 - the client's Food use effects (the
		-- corpus description: "Restores $o1 health over $d. Must remain seated
		-- while eating."; the name confirmed at the Classic spell page (433)).
		ids = { 433, 2639, 5004, 10256, 10257 },
	},
}

-- Resolve one common ability against the client's own spell data: the English name
-- first (a client that indexes it answers its own rank id - the client's own rank
-- art), then the cited id ladder (the ERA corpus's rank-1 ids - the fallback for a
-- client that does not index the English name, or answers it without an id). Returns
-- the panel slot - { key, label, spell_id } - or nil when this client does not have
-- the spell (unknown-hides: the panel never offers a button the client cannot cast).
--
-- Nil-safe throughout: a malformed entry, a missing api or a throwing client read
-- answers nil, never an error.
function ST.ROGUE.resolve_practice_common_action(action)
	if type(action) ~= "table" or type(action.key) ~= "string" or action.key == "" then
		return nil
	end
	if type(api.GetSpellInfo) ~= "function" then
		return nil
	end
	local names = action.names
	if type(names) == "table" then
		for i = 1, #names do
			local name = names[i]
			local ok, spell_name, _, _, _, _, _, spell_id = pcall(api.GetSpellInfo, name)
			if ok and type(spell_name) == "string" then
				local query
				if st.family == "TBC" then
					query = name
				elseif type(spell_id) == "number" then
					query = spell_id
				else
					query = action.ids and action.ids[1] or nil
				end
				if query ~= nil then
					return { key = action.key, label = action.label, spell_id = query,
						practice_common = true }
				end
			end
		end
	end
	-- The cited id ladder: the fallback for a client that does not index the English
	-- name. On TBC the query must be a NAME, so the ladder cannot stand in there.
	local ids = action.ids
	if st.family ~= "TBC" and type(ids) == "table" and type(api.get_family_spell_id_state) == "function" then
		local id = api.get_family_spell_id_state(ids)
		if type(id) == "number" then
			return { key = action.key, label = action.label, spell_id = id,
				practice_common = true }
		end
	end
	return nil
end

-- The panel's ability list: the class's own guide slots plus the common abilities
-- the running client actually has. The practice panel reads the guide slot list LIVE
-- (practice_ui.lua's scenario_guide_slots), so this is the list the panel offers.
function ST.ROGUE.practice_panel_slots()
	local guide = ST.ROGUE.guide
	local slots = type(guide) == "table" and guide.slots or nil
	local out = {}
	if type(slots) == "table" then
		for i = 1, #slots do
			out[i] = slots[i]
		end
	end
	local common = ST.ROGUE.practice_common_actions
	if type(common) == "table" then
		-- THE OFFER GATE: a common ability is offered on the running family only if
		-- that family publishes it (as neutral) or the rotation ranks it there - the
		-- offer list and the neutral set are one truth per family.
		local neutral = ST.ROGUE.practice_neutral_set()
		local rotation = ST.ROGUE.practice_rotation_action_set()
		for i = 1, #common do
			local action = common[i]
			if ST.ROGUE.practice_common_offer_allowed(action, neutral, rotation) then
				local slot = ST.ROGUE.resolve_practice_common_action(action)
				if slot then
					out[#out + 1] = slot
				end
			end
		end
	end
	return out
end

-- Widen the class's guide slot list with the common abilities. Called AFTER the guide
-- frame has built its icons and BEFORE the practice panel is built, so the live guide
-- keeps its own icon set while the practice panel's action row offers the common
-- abilities. Idempotent: a list that already carries a common slot is left alone.
function ST.ROGUE.apply_practice_panel_actions()
	local guide = ST.ROGUE.guide
	if type(guide) ~= "table" or type(guide.slots) ~= "table" then
		return false
	end
	local current = guide.slots
	for i = 1, #current do
		local slot = current[i]
		if type(slot) == "table" and slot.practice_common == true then
			return false
		end
	end
	local widened = ST.ROGUE.practice_panel_slots()
	if type(widened) ~= "table" or #widened <= #current then
		return false
	end
	guide.slots = widened
	return true
end

-- The APL's pre-pull rows (HU-12: the pre-pull rows are NOT combat rotation
-- rows - they live in their own table, the shape ST.HUNTER.PRACTICE_PREPULLS
-- already uses). Each row carries the action key, the label, the spell id the
-- APL pre-pulls, the offset in seconds relative to the pull (negative = before
-- it), the kind ("spell" = a cast the opener drill can grade; "aura" = an aura
-- activation, which the drill never grades) and the APL citation.
ST.ROGUE.practice_prepulls = {
	SOD = {
		{
			action = "blood_fury", label = "Blood Fury", spell = 20572, at = -1.5, kind = "spell",
			source = "wowsims/sod ui/rogue/apls/P5_Saber.apl.json (prepullActions: Blood Fury 20572 at -1.5 s)",
		},
	},
	ERA = {
		{
			action = "ar", label = "Adrenaline Rush", spell = 13750, at = -1, kind = "spell",
			source = "wowsims/classic ui/rogue/apls/combat_sinister_strike_iea.apl.json (prepullActions: Adrenaline Rush 13750 at -1 s) - the plain Era APL (combat_sinister_strike.apl.json) carries no prepullActions at all",
		},
	},
	TBC = {
		{
			action = "ar", label = "Adrenaline Rush", spell = 13750, at = -1, kind = "spell",
			source = "wowsims/tbc-new ui/specs/rogue/dps/apls/swords.apl.json (prepullActions: Adrenaline Rush 13750 at -1 s)",
		},
	},
	WRATH = {
		{
			action = "vanish_buff", label = "Improved Vanish", spell = 58426, at = -1, kind = "aura",
			source = "wowsims/wotlk ui/rogue/apls/mutilate.apl.json (prepullActions: activateAura 58426 at -1 s - the aura's NAME is UNCONFIRMED; the combat APL's i=4 Vanish row is NOT(auraIsActive(58426)))",
		},
	},
	FOREVER = {
		{
			action = "bf", label = "Blade Flurry", spell = 13877, at = -2, kind = "spell",
			source = "wowsims/forever ui/specs/rogue/dps/apls/default.apl.json (prepullActions: Blade Flurry 13877 at -2 s)",
		},
		{
			action = "premeditation", label = "Premeditation", spell = 14183, at = -2, kind = "spell",
			source = "wowsims/forever ui/specs/rogue/dps/apls/default.apl.json (prepullActions: Premeditation 14183 at -2 s - the Forever client's 14183 is Premeditation)",
		},
		{
			action = "stealth", label = "Stealth", spell = 1787, at = -1, kind = "aura",
			source = "wowsims/forever ui/specs/rogue/dps/apls/default.apl.json (prepullActions: activateAura Stealth 1787 rank 4 at -1 s)",
		},
	},
}

-- The live pull clock in the ctx (BS-8 item 2 / P-17): the prepull step judges
-- the pull window from the SAME moment the live guide reads.
--   ctx.pull_at           the absolute pull timestamp (api.get_time() domain)
--   ctx.pull_in_seconds   the countdown to the pull, in seconds
-- Both stay nil when the pull is unknown (the clock is never a guess), and a ctx
-- that already carries its own pull clock keeps it. The clock lives on the ADDON
-- OBJECT (the AceAddon table main.lua publishes it on), not on the namespace.
local function practice_apply_pull_clock(ctx, now)
	if type(ctx) ~= "table" then
		return ctx
	end
	if ctx.pull_at ~= nil or ctx.pull_in_seconds ~= nil then
		return ctx
	end
	local pull_at = ST.pull_at
	if type(pull_at) == "number" and pull_at == pull_at then
		ctx.pull_at = pull_at
	end
	if type(ST.pull_in_seconds) == "function" then
		local ok, value = pcall(ST.pull_in_seconds, ST, now)
		if ok and type(value) == "number" and value == value then
			ctx.pull_in_seconds = value
		end
	end
	return ctx
end

-- The ctx the step and the drills read: the class's OWN gathered inputs (the live
-- guide state - the same state the guide shows) with the engine's ctx layered on
-- top. The state bag carries the engine's frozen input names, so a drill grades
-- the same numbers the guide reads (the audit's §4.5 "the input writer must use
-- the engine's own frozen input names"). A read the client cannot answer stays
-- nil (unknown - the engine stays silent instead of guessing).
function ST.ROGUE.practice_context(self, now, last_action)
	local ctx = {
		now = now,
		last_action = last_action,
		resources = {},
		cooldowns = {},
	}
	-- The pull moment travels with the ctx: the opener drill reads it from here.
	practice_apply_pull_clock(ctx, now)
	local gathered = nil
	if type(ST.ROGUE.gather_guide_inputs) == "function" then
		-- pcall-guarded: a half-loaded class module never throws out of a step.
		local ok, result = pcall(ST.ROGUE.gather_guide_inputs, self, ST.ROGUE.practice_gathered)
		if ok and type(result) == "table" then
			gathered = result
		end
	end
	if not gathered then
		return ctx
	end
	for key, value in pairs(gathered) do
		if type(value) == "number" or type(value) == "boolean" or type(value) == "string" then
			ctx.resources[key] = value
		end
	end
	-- The cooldown rows (the engine's own naming: <key>_remaining / <key>_remaining_cd).
	for key, value in pairs(gathered) do
		if type(key) == "string" and type(value) == "number" then
			local base = key:match("^(.-)_remaining_cd$") or key:match("^(.-)_remaining$")
			if base and base ~= "" then
				ctx.cooldowns[base] = value
			end
		end
	end
	-- The pre-pull row (the APLs' prepullActions - ST.ROGUE.practice_prepulls):
	-- the running family's first CAST row whose readiness the gathered state
	-- proves. The opener drill grades that row; an aura-activation row is never
	-- graded (it is not a cast).
	local prepull_rows = ST.ROGUE.practice_prepulls[ST.ROGUE.practice_rotation_family()]
	if type(prepull_rows) == "table" then
		for i = 1, #prepull_rows do
			local row = prepull_rows[i]
			if type(row) == "table" and row.kind == "spell" and type(row.action) == "string" then
				if ctx.resources[row.action .. "_ready"] == true then
					ctx.prepull_action = row.action
					ctx.prepull_at = row.at
					break
				end
			end
		end
	end
	return ctx
end

-- The reused table the ctx builder writes the gathered state into.
ST.ROGUE.practice_gathered = {}

-- The rotation scenario's one tick (the practice audit's S-R): the engine's
-- decision for the current state, or nil when the state cannot decide (the engine
-- grades that step UNKNOWN - it never records a wrong action and never invents an
-- expectation).
--
-- A POOL verdict is a HOLD, and a hold is a DECISION (the operator ruling HU-8,
-- hands-up 2026-10-19: HOLD-IS-A-DECISION). The engine's own verdict carries the
-- hold, so the step states it explicitly: casting during the pool is an illegal
-- cast, and doing nothing is correct. A step that names neither an action nor a
-- hold stays UNKNOWN.
function ST.ROGUE.practice_scenario_step(self, ctx)
	local guide = st.rogue_guide
	if not (guide and guide.practice_step) then
		return nil
	end
	local step = guide.practice_step(ctx)
	if type(step) == "table" then
		return step
	end
	-- The step is nil: the engine either held (a decision) or could not decide
	-- (unknown). Its own verdict says which - the class never re-decides.
	if type(guide.practice_expected) ~= "function" then
		return nil
	end
	local ok, res = pcall(guide.practice_expected, ctx, guide.practice_out)
	if not ok or type(res) ~= "table" or res.hold ~= true then
		return nil
	end
	local reason = nil
	if type(guide.practice_reason) == "function" then
		reason = guide.practice_reason(res)
	end
	return { action = nil, hold = true, reason = reason or "POOL" }
end

--=========================================================================================
-- Practice: the target drill set (the practice audit's section C)
--=========================================================================================
-- Four drills, one skill each (the practice audit's D-R1..D-R4). The rogue's ENERGY
-- behaviour is baseline (the operator's ruling): rogue_energy_pool is not one of
-- these four. The graders live in the pure engine (rogue_guide.lua) and the class
-- entries are thin wrappers, so a drill grades exactly what the guide shows.
-- A grader returns nil when it cannot decide (the engine shows UNKNOWN and records
-- no attempt - a grade is never guessed).

-- The mis-pick bands (the audit's D-R1, [DESIGN] grading policy): no mis-pick S,
-- one A, two B, three C, four or five D, more than five F. Over the spec's
-- ten-decision sample the bands land exactly on the audit's table.
local function practice_band(mistakes)
	if type(mistakes) ~= "number" then
		return nil
	end
	if mistakes <= 0 then
		return "S"
	elseif mistakes <= 1 then
		return "A"
	elseif mistakes <= 2 then
		return "B"
	elseif mistakes <= 3 then
		return "C"
	elseif mistakes <= 5 then
		return "D"
	end
	return "F"
end

-- The drill counters live beside the engine, not inside it: a weak-keyed table
-- keyed by the session (ctx.session / ctx.session_id / the session object), so a
-- finished session's counters disappear with it and the shared engine's own tables
-- are never written to. When the engine aggregates the counters itself
-- (ctx.mistakes / ctx.attempts) those win and nothing is stored here.
local practice_drill_state = setmetatable({}, { __mode = "k" })
local practice_drill_sessions = 0
local PRACTICE_DRILL_SESSION_CAP = 64

-- The session identity the counters hang off (nil = no session to key on).
local function practice_drill_session(self, ctx)
	if type(ctx) == "table" then
		if ctx.session ~= nil then
			return ctx.session
		end
		if ctx.session_id ~= nil then
			return ctx.session_id
		end
	end
	if type(self) == "table" then
		return self
	end
	return nil
end

-- The running counters for one drill: the mistakes, the decisions and the store
-- entry (nil when the engine owns the counters).
local function practice_drill_counters(self, ctx, drill_key)
	if type(ctx) == "table" then
		local mistakes = ctx.mistakes
		local decisions = ctx.attempts or ctx.decisions
		if type(mistakes) == "number" and type(decisions) == "number" then
			return mistakes, decisions, nil
		end
	end
	local session = practice_drill_session(self, ctx)
	if session == nil then
		return nil, nil, nil
	end
	local store = practice_drill_state[session]
	if type(store) ~= "table" then
		store = {}
		practice_drill_state[session] = store
		practice_drill_sessions = practice_drill_sessions + 1
		if practice_drill_sessions > PRACTICE_DRILL_SESSION_CAP then
			practice_drill_state = setmetatable({}, { __mode = "k" })
			practice_drill_sessions = 0
			store = {}
			practice_drill_state[session] = store
			practice_drill_sessions = 1
		end
	end
	local entry = store[drill_key]
	if type(entry) ~= "table" then
		entry = { mistakes = 0, decisions = 0 }
		store[drill_key] = entry
	end
	-- A new sample (a fresh decision index, or a new sample id) starts over.
	local sample = nil
	if type(ctx) == "table" then
		sample = ctx.sample_id
		if sample == nil then
			sample = ctx.decision_index
		end
	end
	if sample ~= nil and entry.sample ~= nil and sample ~= entry.sample then
		local restart = type(sample) ~= "number" or type(entry.sample) ~= "number"
			or sample < entry.sample
		if restart then
			entry.mistakes, entry.decisions = 0, 0
		end
	end
	if sample ~= nil then
		entry.sample = sample
	end
	return entry.mistakes, entry.decisions, entry
end

-- Record one decision and return the band. ok = the player pressed what the
-- rotation wanted.
local function practice_grade_band(self, ctx, drill_key, ok)
	local mistakes, decisions, entry = practice_drill_counters(self, ctx, drill_key)
	if entry then
		entry.mistakes = (mistakes or 0) + (ok and 0 or 1)
		entry.decisions = (decisions or 0) + 1
		mistakes = entry.mistakes
	elseif type(mistakes) == "number" then
		-- The engine's own counters: they hold the totals BEFORE this decision,
		-- so this one is added here.
		mistakes = mistakes + (ok and 0 or 1)
	else
		-- No session and no counters: this one decision is all there is.
		return ok and "S" or "F"
	end
	return practice_band(mistakes)
end

ST.ROGUE.practice_drills = {
	-- D-R1: the priority order - Expose duty -> SnD upkeep -> Hunger for Blood ->
	-- Shiv upkeep -> Envenom -> the dying-target dump -> the planned finisher ->
	-- AR/BF/Cold Blood -> Tea. The engine's own action IS the expected order, so
	-- a nearly-right pick (Rupture instead of Eviscerate on Era) is a mis-pick:
	-- that is the whole point of the drill. The band is the run's mis-pick count
	-- (the audit's D-R1).
	{
		key = "rogue_finisher_order",
		label = "The finisher order",
		kind = "rotation_order",
		description = "Pick the rotation's next action: Expose duty, Slice and Dice, Hunger for Blood, Shiv, Envenom, the dying-target dump, the planned finisher, the offensive cooldowns, Thistle Tea.",
		grade = function(self, ctx)
			local guide = st.rogue_guide
			if not (guide and guide.grade_finisher_order) then
				return nil
			end
			local verdict = guide.grade_finisher_order(ctx)
			if verdict == nil then
				return nil
			end
			return practice_grade_band(self, ctx, guide.PRACTICE_DRILL_PRIORITY, verdict == "S")
		end,
	},
	-- D-R2: the combo-point decision - when to commit a finisher. The bands are
	-- measured against the family's own floor (the planned finisher's CP line, or
	-- the dying-target dump's line when the target is dying).
	{
		key = "rogue_cp_finish",
		label = "The combo-point decision",
		kind = "situational",
		description = "Commit the finisher at the family's combo-point floor - never below it on a healthy target, and never late on a dying one.",
		grade = function(self, ctx)
			local guide = st.rogue_guide
			if not (guide and guide.grade_cp_finish) then
				return nil
			end
			return guide.grade_cp_finish(ctx)
		end,
	},
	-- D-R3: the debuff upkeep - keeping Slice and Dice up (the per-CP window).
	{
		key = "rogue_snd_upkeep",
		label = "The debuff upkeep",
		kind = "rotation_window",
		description = "Keep Slice and Dice up: refresh it inside the family's own window and never build over a dead debuff.",
		grade = function(self, ctx)
			local guide = st.rogue_guide
			if not (guide and guide.grade_snd_upkeep) then
				return nil
			end
			return guide.grade_snd_upkeep(ctx)
		end,
	},
	-- D-R4: the opener - the prepull and the first-finisher decision. The rogue
	-- has no client pull timer, so the drill carries its own synthetic countdown.
	{
		key = "rogue_opener",
		label = "The opener",
		kind = "transition",
		description = "Open the fight in order: the prepull cooldown, the upkeep, the builder and the first finisher - on time.",
		grade = function(self, ctx)
			local guide = st.rogue_guide
			if not (guide and guide.grade_opener) then
				return nil
			end
			return guide.grade_opener(ctx)
		end,
	},
}

-- The namespace mirror this file used to carry (st.ROGUE = ST.ROGUE) is GONE:
-- the shared engine resolves the class module from the AceAddon table FIRST (the
-- class tables live there - main.lua creates ST.ROGUE and every class module
-- reaches it through LibStub), and the namespace is only the fallback. The
-- central fix landed in practice.lua (H.practice_class_module reads the addon
-- object first), so the engine finds this class's practice hooks without any
-- per-class alias - see hands-up.md HU-7 and
-- bench/practice_scenario_engine_2026-10-19.md section 6.
-- tests/wiring_check.lua check 7 fails the build if a class module publishes
-- itself onto the namespace again (the class file's file scope runs on EVERY
-- client, so a namespace write there is a load-time landmine).

--=========================================================================================
-- Shared practice-panel provider (class-isolation 2026-10-21 C3)
--=========================================================================================
-- The rogue's OWN practice route, panel order, ability defs and drill session.
-- The shared practice UI asks the ACTIVE class for this table and renders the
-- answers; it never names the rogue. The session seams are the class's own
-- functions (pool spend + Era-filtered SS window).
ST.ROGUE.practice_panel = {
    drill_key = "rogue_energy_pool",
    title = "|cFFFF8800Pool Practice|r",
    def_type = "drill",
    -- The drill's icon art: the spell id resolves the client's own rank art,
    -- and a client that answers the name shows its own rank art too - whether
    -- the classic-line global GetSpellInfo takes a name at all is UNCONFIRMED
    -- in-client (bench/final_gate_audit_2026-10-20.md §6 C1) - while an
    -- unanswered key leaves the icon blank rather than guessed (the drill still
    -- runs and grades).
    drift_message = "Practice mode is not available (rogue drill key drifted).",
    idle_status = "Drill idle - press Start Fight",
    hint_active = "Click a cast to drill. /st practice or the X button stops.",
    hint_stopped = "Press Start Fight, or cast drills with the icon grid.",
    progress = {
        mode = "rogue_energy_pool",
        scenario = "rogue_rotation",
        drills = { "rogue_energy_pool", "rogue_ss_window" },
    },
    scenario_key = function() return ST.ROGUE.practice_scenario_key() end,
    order = function() return ST.ROGUE.practice_cast_order() end,
    label = function(key) return ST.ROGUE.practice_cast_label(key) end,
    spell_id = function(key) return ST.ROGUE.practice_cast_spell_id(key) end,
    status = function(ui, now)
        if type(ST.ROGUE.practice_status) ~= "function" then
            return nil
        end
        return ST.ROGUE.practice_status({
            tick = ui.rogue_tick,
            swing = ui.rogue_swing,
        }, now)
    end,
    fight_elapsed = function(ui, now)
        if type(ST.ROGUE.practice_fight_elapsed) ~= "function" then
            return nil
        end
        return ST.ROGUE.practice_fight_elapsed(ui.rogue_session, now)
    end,
    session = {
        running = function(ui) return ui.rogue_session ~= nil end,
        active = function(ui)
            return ui.rogue_session and ui.rogue_session.active
        end,
        start = function(self, now, ui, ctx)
            if type(ST.ROGUE.new_practice_session) ~= "function"
                or type(ST.ROGUE.new_ss_session) ~= "function"
                or type(ST.ROGUE.practice_begin_session) ~= "function"
                or type(ST.ROGUE.tick_practice_session) ~= "function"
                or type(ST.ROGUE.practice_cast) ~= "function" then
                return false
            end
            local duration = ctx and ctx.base_speed
            if type(duration) ~= "number" or duration <= 0 then
                duration = 3.5
            end
            if type(self.mainhand) == "table" then
                ui.saved_hand_speed = self.mainhand.speed
            else
                ui.saved_hand_speed = nil
            end
            local ok_new, session = pcall(function()
                return ST.ROGUE.new_practice_session(now, {})
            end)
            if not ok_new or session == nil then
                return false
            end
            local ok_ss, ss_session = pcall(function()
                return ST.ROGUE.new_ss_session(now, {})
            end)
            if not ok_ss then
                ss_session = nil
            end
            -- A fresh pool run must begin (explicit false means the shell is
            -- absent: fail closed with no session rather than a run whose ticks
            -- never advance). The Era SS run is auxiliary: best-effort only.
            local ok_begin, begun = pcall(function()
                return ST.ROGUE.practice_begin_session(session, now)
            end)
            if not ok_begin or begun == false then
                return false
            end
            if ss_session then
                pcall(function()
                    return ST.ROGUE.practice_begin_session(ss_session, now)
                end)
            end
            ui.rogue_session = session
            ui.rogue_ss_session = ss_session
            ui.rogue_tick = { start = now, interval = 2 }
            ui.rogue_swing = {
                swing_duration = duration,
                swing_start = now,
                swing_ends_at = now + duration,
            }
            ui.rogue_out = {}
            ui.base_speed = duration
            return true
        end,
        tick = function(self, now, elapsed, ui)
            local session = ui.rogue_session
            if session == nil then
                return
            end
            local swing = ui.rogue_swing
            if swing and session.active then
                -- Roll the drill swing (cap catch-up after a hitch so one frame
                -- never fast-forwards the whole drill).
                local duration = swing.swing_duration
                if type(duration) == "number" and duration > 0 then
                    local guard = 0
                    while now >= swing.swing_ends_at and guard < 8 do
                        swing.swing_start = swing.swing_ends_at
                        swing.swing_ends_at = swing.swing_ends_at + duration
                        guard = guard + 1
                    end
                end
            end
            local out = ST.ROGUE.tick_practice_session(session, now, elapsed,
                ui.rogue_out)
            ui.rogue_out = out
            if ui.rogue_ss_session then
                ST.ROGUE.tick_practice_session(ui.rogue_ss_session, now, elapsed,
                    ui.rogue_out)
            end
            ui.update_fight_timer(self, now)
            ui.sync_to_addon(self)
        end,
        cast = function(self, key, ui)
            if ui.rogue_session == nil then
                return nil
            end
            local drill = {
                energy = ui.rogue_session,
                ss = ui.rogue_ss_session,
                tick = ui.rogue_tick,
                swing = ui.rogue_swing,
            }
            return ST.ROGUE.practice_cast(drill, api.get_time(), key)
        end,
        stop = function(self, ui)
            local now = api.get_time()
            if ui.rogue_session and type(ST.ROGUE.end_practice_session) == "function" then
                ST.ROGUE.end_practice_session(ui.rogue_session, now)
            end
            ui.rogue_session = nil
            if ui.rogue_ss_session and type(ST.ROGUE.end_practice_session) == "function" then
                ST.ROGUE.end_practice_session(ui.rogue_ss_session, now)
            end
            ui.rogue_ss_session = nil
            ui.rogue_tick = nil
            ui.rogue_swing = nil
        end,
        begin = function(self, now, ui)
            if ui.rogue_session and type(ST.ROGUE.practice_begin_session) == "function" then
                ST.ROGUE.practice_begin_session(ui.rogue_session, now)
            end
            if ui.rogue_ss_session and type(ST.ROGUE.practice_begin_session) == "function" then
                ST.ROGUE.practice_begin_session(ui.rogue_ss_session, now)
            end
        end,
        end_session = function(self, ui)
            local now = api.get_time()
            if ui.rogue_session and type(ST.ROGUE.end_practice_session) == "function" then
                ST.ROGUE.end_practice_session(ui.rogue_session, now)
            end
            if ui.rogue_ss_session and type(ST.ROGUE.end_practice_session) == "function" then
                ST.ROGUE.end_practice_session(ui.rogue_ss_session, now)
            end
        end,
        pause = function(self, ui, shift)
            if type(ST.ROGUE.practice_shift_pause) == "function" then
                ST.ROGUE.practice_shift_pause({
                    tick = ui.rogue_tick,
                    swing = ui.rogue_swing,
                }, shift)
            end
        end,
        sync = function(self, ui)
            local swing = ui.rogue_swing
            local session = ui.rogue_session
            local now = api.get_time()
            local d = self.mainhand
            if swing and type(swing.swing_duration) == "number" and swing.swing_duration > 0
                and type(swing.swing_start) == "number"
                and type(swing.swing_ends_at) == "number" then
                d.speed = swing.swing_duration
                d.start = swing.swing_start
                d.ends_at = swing.swing_ends_at
                d.is_paused = not (session and session.active)
            else
                d.speed = ui.base_speed or d.speed or 3.5
                d.start = now
                d.ends_at = now + (d.speed or 3.5)
                d.is_paused = true
            end
            d.is_full = false
            if ui.combat_paused then
                d.is_paused = true
            end
            if type(ST.ROGUE.practice_sync) == "function" then
                ST.ROGUE.practice_sync(self)
            end
            self:show_bar("mainhand")
        end,
        clear = function(self, ui)
            local now = api.get_time()
            local d = self.mainhand
            d.speed = ui.saved_hand_speed or d.speed
            local speed = d.speed or 3.5
            d.start = now - speed
            d.ends_at = now
            d.current_progress = 1
            d.is_full = true
            d.is_paused = false
            self:on_bar_inactive("mainhand")
            self:handle_bar_visibility("mainhand")
        end,
    },
}

end

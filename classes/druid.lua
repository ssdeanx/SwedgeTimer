--=========================================================================================
-- Module for Druid-specific behaviours: the Maul queue colour, plus (mirroring the
-- shaman/hunter/paladin ports of the reference) the druid tracker set - the cat-form
-- energy tick bar, the mainhand form label and the Mangle/Rip/Rake target debuff bars
-- (reference SuperSwingTimer_ClassMods.lua druid block 4514-5524). The pure maths
-- (energy cycle, natural-gain classifier, form-label mapping, debuff display rules,
-- the D4 TTD EMA, the D5 countdown and the GCD-tick fraction) lives in
-- druid_energy.lua; this module gathers the live readings and drives the widgets on
-- the mainhand visuals frame.
--
-- Build-out round 1 additions (all nil-safe toggles, default OFF - the options pass
-- wires the widgets): D2 Tiger's Fury / Berserk HUD slots (name-based lookups; the
-- slots gate themselves per family through the client's spell data), D3 combo-point
-- pips (the installed ST:new_pips factory from the bars-design lane), D4 EMA-smoothed
-- time-to-die feeding the guide's frozen time_to_die input, D5 "Shred in Xs" energy
-- countdown, D6 Maul-efficiency badge (time at the rage cap per fight), the Omen of
-- Clarity proc glow (discover #8) and the energy tick bar's GCD tick overlay
-- (discover #4). D1 (powershift probe) stays blocked - no honest offline probe
-- exists; the reserved plug-in is documented in gather_guide_inputs.
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
-- Cross-client API wrappers (see compat.lua).
local api = st.api
local get_tab = st.utils.convert_lookup_table
local LSM = LibStub("LibSharedMedia-3.0")

-- See compat.lua: restricted (secret) reads must degrade, never error. Exact no-op
-- where the probe is absent (classic clients).
local is_secret = issecretvalue or function()
    return false
end
-- Target identity for the D4 time-to-die baseline: UnitGUID exists on every supported
-- client and is not wrapped by compat.lua (the hud.lua capture pattern). nil (or a
-- non-string) reads as "no readable target", so the sampler resets instead of diffing
-- across targets.
local unit_guid = UnitGUID
-- The rage cap the D6 badge reads (100 on every classic family). Declared here so the
-- badge sampler below captures it as an upvalue.
local DRUID_RAGE_CAP = 100
-- nil until druid_energy.lua is listed in the TOCs; the trackers then stay inert instead
-- of erroring (the root module loads before classes/ on every flavor once it is listed).
local druid_energy = st.druid_energy

--=========================================================================================
-- Spell data
--=========================================================================================
-- Maul, all ranks across the classic families (vanilla -> BCC -> WotLK).
-- The lookup table keeps every rank id; get_family_spell_id picks the highest id
-- that exists on the running client (the current rank).
local maul_ids = get_tab({
    6807, 6808, 6809, 8972, 9745, 9880, 9881, 26996, 48479, 48480
})

-- Cached current-rank id, resolved once on first use.
local maul_current_id

-- Resolves the highest rank that exists on the running client exactly once. A negative
-- result is latched as false too, so a client without the spell stops re-walking the
-- whole table on every power tick.
local function resolve_rank(ids, cached)
    if cached == nil then
        return api.get_family_spell_id(ids) or false
    end
    return cached
end

-- One ability's rage cost from a GetSpellPowerCost result, with a restricted (secret)
-- reading treated as "the client cannot answer": the engine must never compare against
-- an opaque value (type() reports "number" for one, so a type guard cannot catch it).
-- A false from the caller's `rank and api.GetSpellPowerCost(...)` short-circuit (an
-- unresolved rank) normalises to nil too, the one "no cost" shape the engine expects.
local function rage_cost_of(costs)
    local cost = costs and costs[1] and costs[1].cost
    if is_secret(cost) then
        return nil
    end
    return cost or nil
end

-- Compares the current rage against the queued Maul cost and recolours only when the
-- state actually changes: UNIT_POWER_FREQUENT fires several times a second.
-- Caveat: the default power type is rage, which is what Maul actually costs in bear
-- form, but in cat / travel form UnitPower("player") is not rage at all, so the
-- comparison is meaningless there and can only ever report "sufficient".
local function update_rage_state(self, spell_id)
    local costs = spell_id and api.GetSpellPowerCost(spell_id)
    local rage_cost = rage_cost_of(costs)
    local power = api.UnitPower("player")
    -- No cost data (unlearned spell, client we cannot read) means we cannot claim the
    -- player is short of rage; a non-numeric reading (or a secret value on a modern
    -- client) degrades the same way instead of erroring on the comparison.
    local insufficient = false
    if type(rage_cost) == "number" and type(power) == "number" then
        insufficient = power < rage_cost
    end
    if self.insufficient_rage ~= insufficient then
        self.insufficient_rage = insufficient
        self:set_bar_color("mainhand")
    end
end

--=========================================================================================
-- D6 Maul-efficiency badge: rage-wasted-at-cap readout
--=========================================================================================
-- The badge tracks, per fight, the time the player spent at the rage cap while in a
-- rage form. The power event stream reports post-change values only, so a gain that is
-- truncated at the cap is observable as a reading landing on 100 from below (counted
-- as a capped gain event); the per-gain magnitude itself is NOT observable - no rage
-- units are claimed anywhere (see bench/buildout_druid_2026-10-17.md). The sampled
-- state lives on the module instance; on_rage_update only fires for the RAGE power
-- type (main.lua's dispatch), so the badge is bear-form by construction, and the
-- per-frame sync closes the open segment when the form changes or the toggle goes off.
local function sample_maul_badge(self, now)
    -- Reduced callers (the smoke fixture's bare self) have no db accessor: the
    -- badge then simply has no state to keep.
    local get_class_table = self.get_class_table
    if not get_class_table then
        return
    end
    local db = get_class_table(self)
    if db.show_druid_maul_badge ~= true then
        return
    end
    local power = api.UnitPower("player")
    if type(power) ~= "number" then
        -- Unreadable (a secret value on a modern client): leave the state untouched -
        -- a degraded reading must not close a segment or count an event.
        return
    end
    local prev = self.druid_maul_badge_rage
    self.druid_maul_badge_rage = power
    if self.in_combat ~= true then
        -- Out of combat rage decays; the badge is a fight readout (reset on combat
        -- exit), so nothing accumulates here.
        return
    end
    if power >= DRUID_RAGE_CAP then
        if self.druid_maul_badge_since == nil then
            self.druid_maul_badge_since = now
        end
        if type(prev) == "number" and prev < DRUID_RAGE_CAP then
            self.druid_maul_badge_events = (self.druid_maul_badge_events or 0) + 1
        end
    elseif self.druid_maul_badge_since ~= nil then
        self.druid_maul_badge_seconds = (self.druid_maul_badge_seconds or 0)
            + (now - self.druid_maul_badge_since)
        self.druid_maul_badge_since = nil
    end
end

-- Closes an open at-cap segment at `now` (idempotent: a cleared segment adds nothing).
local function close_maul_badge_segment(self, now)
    if self.druid_maul_badge_since ~= nil then
        self.druid_maul_badge_seconds = (self.druid_maul_badge_seconds or 0)
            + math.max(0, now - self.druid_maul_badge_since)
        self.druid_maul_badge_since = nil
    end
end

function ST.DRUID.on_rage_update(self)
    sample_maul_badge(self, api.get_time())
    if self.maul_queued then
        maul_current_id = resolve_rank(maul_ids, maul_current_id)
        return update_rage_state(self, maul_current_id or nil)
    end
    -- Nothing queued: clear a stale "insufficient rage" colour left by the last fight.
    if self.insufficient_rage then
        self.insufficient_rage = false
        self:set_bar_color("mainhand")
    end
end

function ST.DRUID.on_spellcast_failed_quiet(self, unit_id, cast_guid, spell_id)
    if maul_ids[spell_id] ~= nil then
        self.maul_queued = false
        self:set_bar_color("mainhand")
    end
end

function ST.DRUID.on_spellcast_succeeded(self, unit_target, cast_guid, spell_id)
    if maul_ids[spell_id] ~= nil then
        self.maul_queued = false
        self:set_bar_color("mainhand")
    end
end

function ST.DRUID.on_current_spell_cast_changed(self, is_cancelled)
    -- This function detects when the player queues up a maul
    -- and sets relevant flags for the func to set bar colors.
    local db = self:get_class_table()
    -- Only run this logic if special on-next-attack colors are enabled in the druid settings.
    if not db.enable_maul_color then
        return
    end

    for spell_id in pairs(maul_ids) do
        local result = api.IsCurrentSpell(spell_id)
        if result then
            self.maul_queued = true
            self:set_bar_color("mainhand")
            return
        end
    end
    self.maul_queued = false
end

function ST.DRUID.post_init(self)
    -- Flags must exist before the first spellcast / power event reaches this module,
    -- otherwise a stale nil would decide the bar colour.
    self.maul_queued = false
    self.insufficient_rage = false

    -- Tracker state (energy tick anchor, form label, shared debuff scan). The widgets
    -- live on the mainhand visuals frame; on_bar_update retries if it was not ready yet.
    self.druid_energy_anchor = nil
    self.druid_last_power = nil
    self.druid_last_power_type = nil
    self.druid_energy_color_applied = nil
    self.druid_form_label_text = nil
    self.druid_debuff_scan_at = nil
    -- D6 badge state (see sample_maul_badge): the last rage reading, the at-cap
    -- segment's start stamp and the fight accumulators.
    self.druid_maul_badge_rage = nil
    self.druid_maul_badge_since = nil
    self.druid_maul_badge_seconds = nil
    self.druid_maul_badge_events = nil
    self.druid_maul_badge_shown = nil
    -- D4 time-to-die state (see sample_target_time_to_die): the target the baseline
    -- belongs to, the last hp reading and its stamp, and the smoothed velocity.
    self.druid_ttd_guid = nil
    self.druid_ttd_hp = nil
    self.druid_ttd_at = nil
    self.druid_ttd_velocity = nil
    self.DRUID.setup_druid_visuals(self)

    -- Next Action Guide: resolve the guide icons to the client's current ranks while
    -- the spell data is live, then hand the provider (ST.DRUID.guide at the end of
    -- this file) to the shared frame. Guarded so a flavor without nextaction_ui stays
    -- inert; the guide itself stays hidden until nextaction_enabled is turned on.
    self.DRUID.resolve_guide_icons()
    -- D2: the TF/Berserk HUD slots follow the same rank resolution (icon art only -
    -- the cooldown read is name-based).
    self.DRUID.resolve_hud_slot_icons()
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
end

function ST.DRUID.on_combat_exit(self)
    -- A queued Maul dies with the fight; without this the bar can keep the Maul /
    -- insufficient-rage colour into the next pull. PLAYER_REGEN_ENABLED also fires at
    -- login, before the bar textures exist, so the recolour is gated on init.
    self.maul_queued = false
    self.insufficient_rage = false
    -- D6 badge: flush a segment still open at the fight's end, then reset the fight
    -- readout (the badge is combat-scoped). The text widget itself hides on the next
    -- per-frame sync.
    close_maul_badge_segment(self, api.get_time())
    self.druid_maul_badge_seconds = nil
    self.druid_maul_badge_events = nil
    self.druid_maul_badge_rage = nil
    self.druid_maul_badge_shown = nil
    if self.interfaces_are_initialised then
        self:set_bar_color("mainhand")
    end
end

function ST.DRUID.set_bar_color(self, hand)
    -- Returns true if any special setting was applied to let the parent func know
    -- to revert to default behaviour.
    -- Will set appropriate colors for maul queued if requested in the settings,
    -- and will set a special color when the player has one of those queued up but has
    -- insufficient rage to cast them.
    local db_class = self:get_class_table()
    local frame = self:get_visuals_frame(hand)
    if hand ~= "mainhand" then
        return false
    end

    -- Form visibility / talent refresh, mainhand only. These two are not load-bearing
    -- here: determine_form_visibility_flag only writes should_show_bar_this_form, which
    -- is read exclusively by show_bar (main.lua), and set_bar_color never reaches
    -- show_bar / handle_bar_visibility. Every input that changes their result already
    -- refreshes them itself (UPDATE_SHAPESHIFT_FORM, ACTIVE_TALENT_GROUP_CHANGED,
    -- CHARACTER_POINTS_CHANGED and the AceConfig class setter), so running them for
    -- every hand on every call was pure waste.
    self:get_druid_talent_info()
    self:determine_form_visibility_flag()

    -- On-next-attack behaviours
    if db_class.enable_maul_color and self.maul_queued and not (self.insufficient_rage) then
        frame.bar:SetVertexColor(
            self:convert_color(db_class.maul_color)
        )
        return true
    end

    -- Insufficient rage for queue.
    if self.maul_queued and self.insufficient_rage then
        frame.bar:SetVertexColor(
            self:convert_color(db_class.insufficient_rage_color)
        )
        return true
    end

    -- Form-specific behaviours.
    if db_class.use_form_colors then
        if self.form_index == 1 then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.form_color_bear)
            )
            return true
        elseif self.form_index == 4 then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.form_color_travel)
            )
            return true
        elseif self.form_index == 3 then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.form_color_cat)
            )
            return true
        elseif self.form_index == 5 and self.has_moonkin then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.form_color_moonkin)
            )
            return true
        elseif self.form_index == 5 and self.has_tree_of_life then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.form_color_tree)
            )
            return true
        elseif self.form_index == 5 and (not self.has_tree_of_life and not self.has_moonkin) then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.form_color_flight)
            )
            return true
        elseif self.form_index == 6 then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.form_color_flight)
            )
            return true
        end
    end
    return false

end

--=========================================================================================
-- Druid trackers (ported from the reference's druid block, SuperSwingTimer_ClassMods.lua
-- 4514-5524): the cat-form energy tick bar, the mainhand form label and the Mangle/Rip/
-- Rake target debuff bars. The pure maths lives in druid_energy.lua; this section
-- gathers the live readings (power, power type, target auras) and drives the widgets.
--=========================================================================================

-- Energy tick column: the reference's 4 px width (druidEnergyTickBarWidth,
-- SuperSwingTimer_Constants.lua:925), 2 px gap left of the bar (DRUID_ENERGY_TICK_GAP,
-- ClassMods.lua:4517). The colour fallback is the reference's druidEnergyTick colour
-- (Constants.lua:982) in the class-option format (0-255 RGB + 0-1 alpha, converted
-- through the same convert_color path as the db table).
local DRUID_ENERGY_TICK_WIDTH = 4
local DRUID_ENERGY_TICK_GAP = 2
local DRUID_ENERGY_TICK_FALLBACK_COLOR = { 255, 209, 46, 1.0 }
local DRUID_ENERGY_TICK_BG_COLOR = { 0, 0, 0, 0.5 }

-- Form label overlay: same 8px-class small text as the tracker labels.
local DRUID_FORM_LABEL_SIZE = 10

-- Target debuff bars: one merged target scan feeds all three bars, throttled at the
-- shaman flame-shock cadence (0.05 s; reference ClassMods.lua:4869-4871). The stack
-- gaps mirror the reference restack (ClassMods.lua:125-175). While the client's spell
-- data has not answered, localized-name resolution retries at the weave-catalogue
-- cadence instead of re-walking the id table on every scan.
local DRUID_DEBUFF_SCAN_INTERVAL = 0.05
local DRUID_DEBUFF_BOTTOM_GAP = 2
local DRUID_DEBUFF_STACK_GAP = 2
local DRUID_DEBUFF_NAMES_RETRY_S = 5

-- Build-out round 1 widget constants: the Omen proc glow colour (gold - the
-- Clearcasting prompt family), the countdown / badge text sizes and the shared gap
-- below the bar (the D5 countdown and the D6 badge are form-exclusive, so they share
-- the anchor), and the pips row's gap below the bar's bottom-left corner (clear of
-- the centred D5/D6 readout). The rage cap lives above with the badge sampler.
local DRUID_OMEN_GLOW_COLOR = { 1.0, 0.85, 0.25, 0.9 }
local DRUID_COUNTDOWN_TEXT_SIZE = 10
local DRUID_BADGE_TEXT_SIZE = 10
local DRUID_BOTTOM_TEXT_GAP = 2
local DRUID_PIPS_BOTTOM_GAP = 18

-- Mangle, Rip and Rake rank/debuff ids (reference SuperSwingTimer_Constants.lua:296-303,
-- TBC-era sets) with a localized-name fallback resolved from the client's own spell data
-- plus the literal English names. An id missing from a table is simply never detected by
-- id - the name fallback covers other ranks (the localized name is shared across ranks) -
-- and a client without any of the spells (Mangle on Classic Era) keeps the bar inert.
local druid_mangle_ids = get_tab({ 33983, 33987 })
local druid_rip_ids = get_tab({ 1079, 9492, 9493, 9752, 9894, 9896, 27008 })
local druid_rake_ids = get_tab({ 1822, 1823, 1824, 9907, 27006 })

-- Tiger's Fury ranks (rank-dependent across the classic families - bench/verify_bank.md
-- §2: 9845/9846 on Classic Era, 5217/6793/9845/9846 on TBC, +50213 on WotLK). The
-- lookups are name-based (the guide's cooldown query and the HUD slot's name read),
-- so any resolving rank names the same ability; the table only feeds the icon rank
-- resolution and the aura-id match.
local druid_tf_ids = get_tab({ 5217, 6793, 9845, 9846, 50213 })
-- Feral Berserk (WotLK 50334, verified against Wowhead wotlk/spell=50334; the
-- only rank - the talent itself is the ability).
local druid_berserk_ids = get_tab({ 50334 })
-- Savage Roar (WotLK 52610, verified against Wowhead wotlk/spell=52610: 25
-- energy, requires combo points; TBC ranks are unconfirmed - the literal
-- fallback carries those clients, in-game to confirm).
local druid_sr_ids = get_tab({ 52610 })
-- The Omen of Clarity proc buff (Clearcasting 16870, LibClassicDurations; the
-- 16864 talent aura itself must never match - only the proc prompts Shred).
local druid_omen_ids = get_tab({ 16870 })

-- Ordered bottom-to-top: the debuff stack above the bar (reference restack order,
-- ClassMods.lua:5505-5515). Heights, fallback durations (12/12/9 s) and fill colours
-- (ClassMods.lua:4792-4794, 4814, 4924-4926, 4946, 5069-5071, 5091) are the reference's;
-- the colours are in class-option format.
local druid_debuff_defs = {
    {
        key = "mangle",
        ids = druid_mangle_ids,
        fallback_names = { ["Mangle"] = true },
        fallback_duration = 12,
        height = 6,
        option = "show_druid_mangle_bar",
        color_option = "druid_mangle_bar_color",
        fallback_color = { 230, 153, 26, 0.90 },
    },
    {
        key = "rip",
        ids = druid_rip_ids,
        fallback_names = { ["Rip"] = true },
        fallback_duration = 12,
        height = 6,
        option = "show_druid_rip_bar",
        color_option = "druid_rip_bar_color",
        fallback_color = { 51, 191, 51, 0.90 },
    },
    {
        key = "rake",
        ids = druid_rake_ids,
        fallback_names = { ["Rake"] = true },
        fallback_duration = 9,
        height = 5,
        option = "show_druid_rake_bar",
        color_option = "druid_rake_bar_color",
        fallback_color = { 217, 102, 26, 0.90 },
    },
}

-- Reused scan state: the per-window result of the merged target walk, keyed by debuff
-- key. Cleared and refilled per scan (assignments only, so the throttled scan path
-- never allocates beyond the localized-name table's first resolution).
local druid_debuff_found = {}
local druid_debuff_duration = {}
local druid_debuff_expiration = {}

-- Player-buff inputs for the Wrath/SoD guide chains (Savage Roar upkeep, the
-- Clearcasting proc, the Tiger's Fury snapshot): one merged HELPFUL walk feeds
-- all three, throttled at the target-scan cadence. Same id-then-localized-then-
-- literal match shape as the target scan (resolve_debuff_localized_names is
-- reused: the defs share its shape); the aura must belong to the player.
local DRUID_PLAYER_SCAN_INTERVAL = 0.05
-- Savage Roar at full combo points (9 s base + combo scaling per Wowhead; the
-- exact per-CP steps are unconfirmed - the fallback only covers an aura the
-- client lists without a duration, in-game to confirm).
local DRUID_SR_FALLBACK_DURATION = 34
local druid_player_defs = {
    {
        key = "sr",
        ids = druid_sr_ids,
        fallback_names = { ["Savage Roar"] = true },
        fallback_duration = DRUID_SR_FALLBACK_DURATION,
    },
    {
        key = "omen",
        ids = druid_omen_ids,
        fallback_names = { ["Clearcasting"] = true, ["Omen of Clarity"] = true },
    },
    {
        key = "tf",
        ids = druid_tf_ids,
        fallback_names = { ["Tiger's Fury"] = true },
        fallback_duration = 6,
    },
}

-- Reused scan state for the merged player walk, keyed by buff key (assignments
-- only, like the target scan above).
local druid_player_found = {}
local druid_player_duration = {}
local druid_player_expiration = {}
local druid_player_scan_at

-- The bar's configured font, with the client standard font as the fallback for
-- sandboxes and stripped clients (same shape as the shaman tracker helper).
local function get_tracker_font_path(self)
    local db_hand = self.get_hand_table and self:get_hand_table("mainhand")
    if LSM and LSM.Fetch and db_hand and db_hand.text_font then
        local path = LSM:Fetch("font", db_hand.text_font)
        if path then return path end
    end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

-- Resolve the client's own (localized) names for a debuff's rank ids, mirroring the
-- reference's ns.DRUID_*_NAME = GetSpellInfo(id) or ... at load. Lazy: it only runs from
-- the scan while a bar option is on, so an all-off configuration reads nothing from the
-- client. An unanswered client (spell data not up yet) retries at a throttled cadence.
local function resolve_debuff_localized_names(def, now)
    local names = {}
    for id in pairs(def.ids) do
        local name = api.GetSpellInfo(id)
        if name then
            names[name] = true
        end
    end
    if next(names) ~= nil then
        def.localized_names = names
    else
        def.names_retry_at = now + DRUID_DEBUFF_NAMES_RETRY_S
    end
end

-- One throttled walk of the target's harmful auras feeds all three debuff bars (the
-- reference walks once per bar, ClassMods.lua:4848-4866; one merged walk follows the
-- shaman flame-shock scan). Each aura matches by rank id first, then by the localized
-- name resolved from the client, then by the literal English fallback; the aura must
-- belong to the player. A target without matching auras - or no target at all, where
-- UnitAura answers nil - clears every slot.
local function scan_target_druid_debuffs(now)
    local found = druid_debuff_found
    local duration = druid_debuff_duration
    local expiration = druid_debuff_expiration
    local pending = #druid_debuff_defs
    for i = 1, #druid_debuff_defs do
        local def = druid_debuff_defs[i]
        local key = def.key
        found[key] = nil
        duration[key] = nil
        expiration[key] = nil
        if def.localized_names == nil and now >= (def.names_retry_at or 0) then
            resolve_debuff_localized_names(def, now)
        end
    end
    local index = 1
    while index <= 40 and pending > 0 do
        local name, _, _, _, aura_duration, aura_expiration, source, _, _, spell_id =
            api.UnitAura("target", index, "HARMFUL")
        -- No early break (R2): nil is simply no match at this index.
        if name ~= nil then
            if source == "player" or source == nil then
                for i = 1, #druid_debuff_defs do
                    local def = druid_debuff_defs[i]
                    local key = def.key
                    if found[key] == nil then
                        local is_match = (type(spell_id) == "number" and def.ids[spell_id] ~= nil)
                            or def.fallback_names[name] == true
                            or (def.localized_names ~= nil and def.localized_names[name] == true)
                        if is_match then
                            found[key] = true
                            duration[key] = aura_duration
                            expiration[key] = aura_expiration
                            pending = pending - 1
                        end
                    end
                end
            end
        end
        index = index + 1
    end
end

-- One throttled walk of the player's own helpful auras feeds the guide's Savage
-- Roar / Clearcasting / Tiger's Fury inputs (same match shape as the target scan:
-- rank id, then the client's localized name, then the literal English fallback;
-- the aura must belong to the player). Driven from on_bar_update while the guide
-- is enabled; gather reads the state (nil = absent or not yet scanned).
local function scan_player_druid_buffs(now)
    local found = druid_player_found
    local duration = druid_player_duration
    local expiration = druid_player_expiration
    local pending = #druid_player_defs
    for i = 1, #druid_player_defs do
        local def = druid_player_defs[i]
        local key = def.key
        found[key] = nil
        duration[key] = nil
        expiration[key] = nil
        if def.localized_names == nil and now >= (def.names_retry_at or 0) then
            resolve_debuff_localized_names(def, now)
        end
    end
    local index = 1
    while index <= 40 and pending > 0 do
        local name, _, _, _, aura_duration, aura_expiration, source, _, _, spell_id =
            api.UnitAura("player", index, "HELPFUL")
        -- No early break (R2): nil is simply no match at this index.
        if name ~= nil then
            if source == "player" or source == nil then
                for i = 1, #druid_player_defs do
                    local def = druid_player_defs[i]
                    local key = def.key
                    if found[key] == nil then
                        local is_match = (type(spell_id) == "number" and def.ids[spell_id] ~= nil)
                            or def.fallback_names[name] == true
                            or (def.localized_names ~= nil and def.localized_names[name] == true)
                        if is_match then
                            found[key] = true
                            duration[key] = aura_duration
                            expiration[key] = aura_expiration
                            pending = pending - 1
                        end
                    end
                end
            end
        end
        index = index + 1
    end
end

-- The player-buff scan driver: runs on the per-frame hook while the Next Action
-- Guide is enabled or the Omen proc glow is on (it feeds gather and the glow only,
-- so an all-off configuration reads nothing). Disabling clears the state, so the
-- rotation label and the glow can never ride a stale buff through a settings toggle.
local function update_druid_player_buffs(db, now)
    if db.nextaction_enabled ~= true and db.show_druid_omen_glow ~= true then
        for i = 1, #druid_player_defs do
            local key = druid_player_defs[i].key
            druid_player_found[key] = nil
            druid_player_duration[key] = nil
            druid_player_expiration[key] = nil
        end
        druid_player_scan_at = nil
        return
    end
    if now >= (druid_player_scan_at or 0) then
        druid_player_scan_at = now + DRUID_PLAYER_SCAN_INTERVAL
        scan_player_druid_buffs(now)
    end
end

-- Energy tick: a 4 px column left of the bar whose fill tracks the cat-form energy
-- cycle (reference UpdateDruidEnergyTickVisual, ClassMods.lua:4629-4681). The cycle
-- anchor is re-stamped whenever the game's own tick is detected - a power gain inside
-- the reference's 19-22 window (ClassMods.lua:4690-4698).
--
-- TBC MICRO (docs/research/tbc_minmax.md: "Energy ticks don't reset on form
-- change ... ticks continue every 2s regardless of form"): on TBC the anchor
-- survives form flips, so the bar keeps the true tick phase across
-- powershifts (shift at ~4.5 s to catch the tick -> 80 energy). A form flip
-- still resets the gain baseline - the first cat sample must never diff
-- against the last bear rage reading (a garbage delta inside 19-22 would
-- re-anchor spuriously). Every other family keeps the reference's re-seat
-- (unconfirmed there - in-game to confirm): byte-identical outside TBC.
-- The detection runs on this
-- per-frame hook rather than on UNIT_POWER_FREQUENT: main.lua's dispatch forwards RAGE
-- updates only to on_rage_update (main.lua:925-937) and cat form is the ENERGY power
-- type, so an energy update can never reach the class hook; sampling the live value
-- here is the same per-frame read the reference's render hook performs.
local function update_druid_energy_tick(self, vf, db, now, enabled, power_type, h, sample)
    local bg, fill = vf.druid_energy_tick_bg, vf.druid_energy_tick_fill
    if not (bg and fill) then
        return
    end
    if not (enabled or sample) then
        -- Fully off (no draw, no consumer): no power reads at all, and a re-enable
        -- re-seats instead of comparing against a stale baseline.
        self.druid_energy_anchor = nil
        self.druid_last_power = nil
        self.druid_last_power_type = nil
        bg:Hide()
        fill:Hide()
        return
    end
    local current = api.UnitPower("player")
    if type(current) == "number" then
        if power_type == 3 then
            if self.druid_energy_anchor == nil then
                self.druid_energy_anchor = now
            elseif self.druid_last_power_type ~= 3 then
                -- A form flip: the gain baseline is stale (bear rage vs cat
                -- energy), so it resets without evaluating a delta. TBC keeps
                -- the anchor (ticks don't reset on shift); every other family
                -- re-seats it (the reference behaviour, unconfirmed there).
                if st.family ~= "TBC" then
                    self.druid_energy_anchor = now
                end
            elseif type(self.druid_last_power) == "number"
                and druid_energy.is_natural_gain(current - self.druid_last_power) then
                self.druid_energy_anchor = now
            end
        end
        self.druid_last_power = current
        self.druid_last_power_type = power_type
    else
        -- Unreadable power (a secret value on a modern client): drop the baseline so the
        -- next readable sample re-seats instead of diffing against stale data.
        self.druid_last_power = nil
        self.druid_last_power_type = nil
    end
    if not enabled or power_type ~= 3 or type(h) ~= "number" or h <= 0 then
        bg:Hide()
        fill:Hide()
        return
    end
    if self.druid_energy_anchor == nil then
        self.druid_energy_anchor = now
    end
    local colour = db.druid_energy_tick_color or DRUID_ENERGY_TICK_FALLBACK_COLOR
    if self.druid_energy_color_applied ~= colour then
        self.druid_energy_color_applied = colour
        fill:SetVertexColor(self:convert_color(colour))
    end
    local fraction = druid_energy.get_energy_tick_fraction(
        self.druid_energy_anchor, now, druid_energy.ENERGY_TICK_SECONDS)
    bg:SetHeight(h)
    fill:SetHeight(h * fraction)
    bg:Show()
    fill:Show()
end

-- Form label: "Cat" / "Bear" / "Caster" from the live power type (reference
-- GetDruidFormLabel, ClassMods.lua:4530-4538), shown while the player is shapeshifted.
-- The label is an overlay on the mainhand bar, so it can never clobber a configured
-- left/center/right text mode: in no form the overlay simply hides and the texts the
-- user configured keep drawing exactly as set.
local function update_druid_form_label(self, vf, enabled, power_type)
    local label = vf.druid_form_label
    if not label then
        return
    end
    if not enabled or type(self.form_index) ~= "number" or self.form_index == 0 then
        label:Hide()
        return
    end
    local text = druid_energy.get_form_label(power_type)
    if self.druid_form_label_text ~= text then
        self.druid_form_label_text = text
        label:SetText(text)
    end
    label:Show()
end

-- GCD tick overlay (discover #4): a 1 px line across the energy column at the height
-- the fill will stand when the running GCD ends (the pure fraction in druid_energy).
-- Only meaningful with the column visible (cat form, tick bar on); anything unknown
-- hides it.
local function update_druid_gcd_tick(self, vf, now, enabled, tick_on, power_type, h)
    local marker = vf.druid_energy_gcd_marker
    if not marker then
        return
    end
    if not (enabled and tick_on and power_type == 3) or type(h) ~= "number" or h <= 0 then
        marker:Hide()
        return
    end
    local gcd = self.gcd
    local gcd_remaining = (gcd and gcd.expires and (gcd.expires - now)) or 0
    local fraction = druid_energy.get_gcd_tick_fraction(self.druid_energy_anchor, now,
        gcd_remaining, druid_energy.ENERGY_TICK_SECONDS)
    if fraction == nil then
        marker:Hide()
        return
    end
    marker:ClearAllPoints()
    marker:SetPoint("BOTTOM", vf.druid_energy_tick_bg, "BOTTOM", 0, fraction * h)
    marker:Show()
end

-- D5 energy-deficit countdown ("Shred in Xs"): the seconds until the tick cycle has
-- paid Shred's cost, from the same anchor the tick bar maintains (the countdown keeps
-- the sampler alive with the bar off - see the sample flag). Costs: the verified TBC
-- 42 (druid_guide.lua's SHRED_COST_TBC, the 2.5.6 spell data) and the Wrath 42 (own
-- knowledge - UNCONFIRMED until in-client); every other family has no verified Shred
-- cost (the Era/SoD guide never gates the builder for the same reason), so no
-- countdown exists there. Cat form only; anything unknown hides the text.
local function shred_countdown_cost()
    if st.family == "TBC" or st.family == "WRATH" then
        return (st.druid_guide and st.druid_guide.SHRED_COST_TBC) or 42
    end
    return nil
end

local function update_druid_shred_countdown(self, vf, now, enabled, power_type)
    local text = vf.druid_shred_countdown
    if not text then
        return
    end
    if not enabled or power_type ~= 3 then
        text:Hide()
        return
    end
    local cost = shred_countdown_cost()
    if cost == nil then
        text:Hide()
        return
    end
    local energy = api.UnitPower("player")
    if type(energy) ~= "number" then
        text:Hide()
        return
    end
    local remaining = druid_energy.get_time_to_energy_cost(self.druid_energy_anchor, now,
        energy, cost, druid_energy.ENERGY_TICK_SECONDS, druid_energy.ENERGY_TICK_GAIN)
    if remaining == nil or remaining <= 0 then
        text:Hide()
        return
    end
    local seconds = math.ceil(remaining)
    if self.druid_countdown_shown ~= seconds then
        self.druid_countdown_shown = seconds
        text:SetText("Shred in " .. seconds .. "s")
    end
    text:Show()
end

-- D3 combo-point pips: the bars-design widget (installed factory; contract in
-- bench/briefs/brief_bars-design_2026-10-17.md) driven from the live cat combo
-- count. Cat form shows the 0-5 row; the row hides outside cat form or when the
-- count is unreadable (a secret value must never draw as 0), and glow_full lights
-- the standard 5-point glow. Without a resolved factory (a flavor without bars.lua)
-- the whole path stays inert: no reads, no error.
local function update_druid_pips(self, vf, enabled, power_type)
    local pips = vf.druid_pips
    if not pips then
        return
    end
    if not enabled or power_type ~= 3 then
        if self.druid_pips_visible ~= false then
            self.druid_pips_visible = false
            pips:Hide()
        end
        return
    end
    local count = api.UnitPower("player", 4)
    if type(count) ~= "number" then
        if self.druid_pips_visible ~= false then
            self.druid_pips_visible = false
            pips:Hide()
        end
        return
    end
    if count < 0 then count = 0 end
    if count > 5 then count = 5 end
    if self.druid_pips_count ~= count then
        self.druid_pips_count = count
        pips:set(count)
    end
    local full = count >= 5
    if self.druid_pips_full ~= full then
        self.druid_pips_full = full
        pips:glow_full(full)
    end
    if self.druid_pips_visible ~= true then
        self.druid_pips_visible = true
        pips:Show()
    end
end

-- D6 badge display: bear form only (the readout is about rage), text refreshed on
-- whole seconds. The toggle going off or the form leaving rage closes any open
-- at-cap segment (its time was still at-cap time) and hides - no reads on this path.
local function update_druid_maul_badge(self, vf, enabled, now, power_type)
    local text = vf.druid_maul_badge_text
    if not text then
        return
    end
    if not enabled or power_type ~= 1 then
        close_maul_badge_segment(self, now)
        text:Hide()
        return
    end
    local seconds = self.druid_maul_badge_seconds or 0
    local shown = math.floor(seconds + 0.5)
    if shown <= 0 then
        text:Hide()
        return
    end
    if self.druid_maul_badge_shown ~= shown then
        self.druid_maul_badge_shown = shown
        text:SetText("Cap " .. shown .. "s")
    end
    text:Show()
end

-- Omen of Clarity proc glow (discover #8): a halo around the energy column while the
-- Clearcasting proc is up (id 16870 - the guarded id table above; the 16864 talent
-- aura never matches). Rides the column: with the tick bar off (or out of cat form)
-- there is nothing to outline, so the glow hides.
local function update_druid_omen_glow(vf, enabled, tick_on, power_type)
    local glow = vf.druid_omen_glow
    if not glow then
        return
    end
    if enabled and tick_on and power_type == 3 and druid_player_found.omen == true then
        glow:Show()
    else
        glow:Hide()
    end
end

-- Debuff bars: the throttled scan above feeds all three groups; between scans each bar
-- just counts down. Whole-seconds label, a glow frame inside the final 4 s and the
-- configured fill colour. Visible bars stack bottom-to-top above the bar with the
-- reference's cached restack (ClassMods.lua:125-175): anchors are re-issued only when a
-- bar's slot actually moves, so the per-frame path never churns layout.
local function update_druid_debuff_bars(self, vf, db, now, w)
    local bars = vf.druid_debuff
    local any_on = false
    for i = 1, #druid_debuff_defs do
        if db[druid_debuff_defs[i].option] ~= false then
            any_on = true
            break
        end
    end
    if not any_on and db.nextaction_enabled ~= true then
        for i = 1, #druid_debuff_defs do
            local bar = bars[druid_debuff_defs[i].key]
            bar.glow_on = nil
            bar.bg:Hide()
            bar.fill:Hide()
            bar.glow:Hide()
            bar.label:Hide()
        end
        self.druid_debuff_scan_at = nil
        return
    end
    -- The merged scan also feeds the Next Action Guide's frozen debuff inputs, so it
    -- keeps running while the guide is enabled even with every debuff bar switched off.
    if now >= (self.druid_debuff_scan_at or 0) then
        self.druid_debuff_scan_at = now + DRUID_DEBUFF_SCAN_INTERVAL
        scan_target_druid_debuffs(now)
    end
    local stack_y = DRUID_DEBUFF_BOTTOM_GAP
    for i = 1, #druid_debuff_defs do
        local def = druid_debuff_defs[i]
        local bar = bars[def.key]
        if db[def.option] == false or druid_debuff_found[def.key] ~= true then
            bar.glow_on = nil
            bar.bg:Hide()
            bar.fill:Hide()
            bar.glow:Hide()
            bar.label:Hide()
        else
            local remaining, total = druid_energy.get_debuff_remaining(
                druid_debuff_duration[def.key], druid_debuff_expiration[def.key],
                now, def.fallback_duration)
            if type(w) == "number" and w > 0 and total > 0 then
                local fraction = remaining / total
                if fraction < 0 then fraction = 0 end
                if fraction > 1 then fraction = 1 end
                bar.fill:SetWidth(w * fraction)
            end
            local colour = db[def.color_option] or def.fallback_color
            if bar.color_applied ~= colour then
                bar.color_applied = colour
                bar.fill:SetVertexColor(self:convert_color(colour))
                bar.glow:SetVertexColor(self:convert_color(colour))
            end
            local seconds = math.floor(remaining + 0.5)
            if bar.label_seconds ~= seconds then
                bar.label_seconds = seconds
                bar.label:SetText(tostring(seconds))
            end
            local glow_on = druid_energy.should_debuff_glow(remaining)
            if glow_on ~= bar.glow_on then
                bar.glow_on = glow_on
                if glow_on then
                    bar.glow:Show()
                else
                    bar.glow:Hide()
                end
            end
            if bar.stack_y ~= stack_y then
                bar.stack_y = stack_y
                bar.bg:ClearAllPoints()
                bar.bg:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", 0, stack_y)
                bar.bg:SetPoint("BOTTOMRIGHT", vf, "TOPRIGHT", 0, stack_y)
            end
            bar.bg:Show()
            bar.fill:Show()
            bar.label:Show()
            stack_y = stack_y + def.height + DRUID_DEBUFF_STACK_GAP
        end
    end
end

-- D3 pips factory (installed signature confirmed): bars.lua's
-- ST:new_pips(parent, opts) -> frame with :set(count 0-5) and :glow_full(bool)
-- (colon-callable), from the bars-design lane (bench/briefs/brief_bars-design_2026-10-17.md;
-- confirmed against bars.lua and bench/buildout_bars-design_2026-10-17.md §1/§5 - the
-- publication path and call shape are installed, not guessed). The call is
-- pcall-guarded: a flavor without the factory degrades to "no widget", never an
-- error, and the wiring then stays inert (no reads, no visible change).
local function create_pips_widget(parent, opts)
    if type(ST.new_pips) ~= "function" then
        return nil
    end
    local ok, widget = pcall(ST.new_pips, ST, parent, opts)
    if ok then
        return widget
    end
    return nil
end

-- Creates the tracker widgets on the mainhand visuals frame (called from post_init;
-- on_bar_update retries if the frame was not ready yet). Thin textures rather than
-- frames, like the shaman tracker widgets.
function ST.DRUID.setup_druid_visuals(self)
    local vf = self:get_visuals_frame("mainhand")
    if not vf then
        return
    end

    if not vf.druid_energy_tick_bg then
        -- Energy tick column: dark backing plus a fill that grows upward from the
        -- bottom edge, anchored at the bar's left side with the reference's 2 px gap.
        local bg = vf:CreateTexture(nil, "OVERLAY")
        bg:SetDrawLayer("OVERLAY", -2)
        bg:SetColorTexture(DRUID_ENERGY_TICK_BG_COLOR[1], DRUID_ENERGY_TICK_BG_COLOR[2],
            DRUID_ENERGY_TICK_BG_COLOR[3], DRUID_ENERGY_TICK_BG_COLOR[4])
        bg:SetWidth(DRUID_ENERGY_TICK_WIDTH)
        bg:SetPoint("BOTTOMLEFT", vf, "BOTTOMLEFT",
            -(DRUID_ENERGY_TICK_GAP + DRUID_ENERGY_TICK_WIDTH), 0)
        bg:Hide()
        vf.druid_energy_tick_bg = bg

        local fill = vf:CreateTexture(nil, "OVERLAY")
        fill:SetDrawLayer("OVERLAY", -2)
        fill:SetColorTexture(1, 1, 1, 1)
        fill:SetWidth(DRUID_ENERGY_TICK_WIDTH)
        fill:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
        fill:Hide()
        vf.druid_energy_tick_fill = fill
    end

    if not vf.druid_energy_gcd_marker then
        -- GCD tick overlay (discover #4): a 1 px line across the energy column,
        -- repositioned to the height the fill will stand when the running GCD ends.
        local marker = vf:CreateTexture(nil, "OVERLAY")
        marker:SetDrawLayer("OVERLAY", -1)
        marker:SetColorTexture(1, 1, 1, 0.9)
        marker:SetHeight(1)
        marker:SetWidth(DRUID_ENERGY_TICK_WIDTH + 2)
        marker:SetPoint("BOTTOM", vf.druid_energy_tick_bg, "BOTTOM", 0, 0)
        marker:Hide()
        vf.druid_energy_gcd_marker = marker
    end

    if not vf.druid_omen_glow then
        -- Omen of Clarity proc glow (discover #8): a 1 px halo around the energy
        -- column while the Clearcasting proc is up (id 16870; the 16864 talent aura
        -- never matches - see the player-buff id table above).
        local glow = vf:CreateTexture(nil, "OVERLAY")
        glow:SetDrawLayer("OVERLAY", -3)
        glow:SetColorTexture(DRUID_OMEN_GLOW_COLOR[1], DRUID_OMEN_GLOW_COLOR[2],
            DRUID_OMEN_GLOW_COLOR[3], DRUID_OMEN_GLOW_COLOR[4])
        glow:SetPoint("BOTTOMLEFT", vf.druid_energy_tick_bg, "BOTTOMLEFT", -1, -1)
        glow:SetPoint("TOPRIGHT", vf.druid_energy_tick_bg, "TOPRIGHT", 1, 1)
        glow:Hide()
        vf.druid_omen_glow = glow
    end

    if not vf.druid_form_label then
        local label = vf:CreateFontString(nil, "OVERLAY")
        label:SetPoint("CENTER", vf, "CENTER", 0, 0)
        label:SetJustifyH("CENTER")
        label:SetFont(get_tracker_font_path(self), DRUID_FORM_LABEL_SIZE, "OUTLINE")
        label:SetTextColor(1, 1, 1, 0.95)
        label:Hide()
        vf.druid_form_label = label
    end

    if not vf.druid_shred_countdown then
        -- D5 countdown text, below the bar (the D6 badge shares the anchor - the two
        -- are form-exclusive: cat energy vs bear rage).
        local text = vf:CreateFontString(nil, "OVERLAY")
        text:SetPoint("TOP", vf, "BOTTOM", 0, -DRUID_BOTTOM_TEXT_GAP)
        text:SetJustifyH("CENTER")
        text:SetFont(get_tracker_font_path(self), DRUID_COUNTDOWN_TEXT_SIZE, "OUTLINE")
        text:SetTextColor(1, 1, 1, 0.95)
        text:Hide()
        vf.druid_shred_countdown = text
    end

    if not vf.druid_maul_badge_text then
        -- D6 Maul-efficiency badge text (gold, the tracker label family).
        local text = vf:CreateFontString(nil, "OVERLAY")
        text:SetPoint("TOP", vf, "BOTTOM", 0, -DRUID_BOTTOM_TEXT_GAP)
        text:SetJustifyH("CENTER")
        text:SetFont(get_tracker_font_path(self), DRUID_BADGE_TEXT_SIZE, "OUTLINE")
        text:SetTextColor(1.0, 0.85, 0.25, 0.95)
        text:Hide()
        vf.druid_maul_badge_text = text
    end

    if vf.druid_pips == nil then
        -- D3 pips: created through the installed bars-design factory (see
        -- create_pips_widget above). The construction anchor doubles as the design
        -- reset anchor (the factory's generic reset re-anchors to it), so the row
        -- ships at the bar's bottom-left, clear of the centred D5/D6 readout. The
        -- design target registers with a stable key/title; the persisted save seam
        -- needs db keys the options pass owns (session-only drop until then).
        local pips = create_pips_widget(vf, {
            point = "BOTTOMLEFT",
            x = 0,
            y = -DRUID_PIPS_BOTTOM_GAP,
            design = { key = "druid_pips", title = "Combo Points" },
        })
        if pips then
            vf.druid_pips = pips
        end
    end

    if not vf.druid_debuff then
        local bars = {}
        for i = 1, #druid_debuff_defs do
            local def = druid_debuff_defs[i]
            local bg = vf:CreateTexture(nil, "OVERLAY")
            bg:SetDrawLayer("OVERLAY", -2)
            bg:SetColorTexture(0, 0, 0, 0.45)
            bg:SetHeight(def.height)
            bg:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", 0, DRUID_DEBUFF_BOTTOM_GAP)
            bg:Hide()

            local fill = vf:CreateTexture(nil, "OVERLAY")
            fill:SetDrawLayer("OVERLAY", -2)
            fill:SetColorTexture(1, 1, 1, 1)
            fill:SetHeight(def.height)
            fill:SetWidth(1)
            fill:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
            fill:Hide()

            -- Glow frame: 1 px behind the bar, tinted with the fill colour and shown
            -- only inside the final seconds (reference CreateGlowBorderFrames,
            -- ClassMods.lua:4827, 4957, 5104).
            local glow = vf:CreateTexture(nil, "OVERLAY")
            glow:SetDrawLayer("OVERLAY", -3)
            glow:SetColorTexture(1, 1, 1, 1)
            glow:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", -1, -1)
            glow:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 1, 1)
            glow:Hide()

            local label = vf:CreateFontString(nil, "OVERLAY")
            label:SetPoint("CENTER", bg, "CENTER", 0, 0)
            label:SetJustifyH("CENTER")
            label:SetFont(get_tracker_font_path(self), 8, "OUTLINE")
            label:SetTextColor(1.0, 0.85, 0.25, 0.95)
            label:Hide()

            bars[def.key] = {
                bg = bg,
                fill = fill,
                glow = glow,
                label = label,
            }
        end
        vf.druid_debuff = bars
    end
end

-- Per-frame druid visuals (energy tick bar, form label, target debuff bars), called
-- from ST:onupdate_common via the generic class hook. The mainhand frame's OnUpdate
-- only ticks while the bar is shown, so the widgets freeze with the bar. Deliberately
-- cheap and nil-safe: no LibStub calls, no allocations. NOTE: deliberately not gated on
-- st.is_mainline - the Forever client is Mainline-code but shows all of this.
function ST.DRUID.on_bar_update(self, hand)
    if hand ~= "mainhand" then
        return
    end
    -- Next Action Guide (mainhand only): driven before the tracker gates below so it
    -- also runs where the tracker widgets are missing. Deliberately not gated on
    -- st.is_mainline - the Forever client is Mainline-code but shows the guide; swing
    -- activity decides instead (the Retail stand-in never reports a swing). Settings
    -- that rebuild the frame (scale/position/lock) are applied when the class options
    -- change; the display toggles are read live by the UI.
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
    -- swings (the paladin hooks it the same way in classes/paladin.lua). Runs
    -- before the energy-module gate below so the HUD works without it.
    if st.hud then
        st.hud.on_bar_update(self, hand)
    end
    if not druid_energy then
        return
    end
    local vf = self:get_visuals_frame(hand)
    if not vf then
        return
    end
    if not vf.druid_debuff then
        self.DRUID.setup_druid_visuals(self)
    end
    local now = api.get_time()
    local w, h = self:get_bar_visuals_width_and_height(hand)
    -- The guide's player-buff inputs (Savage Roar / Clearcasting / Tiger's Fury)
    -- and the Omen proc glow: one throttled HELPFUL walk while the guide or the
    -- glow is enabled (a disabled pair neither scans nor keeps stale buffs).
    update_druid_player_buffs(db, now)
    local show_tick = db.show_druid_energy_tick ~= false
    local show_label = db.show_druid_form_label ~= false
    -- Build-out round 1 toggles: every one nil-safe, nil = off (the options pass
    -- wires the widgets; no default-visible change ships without an explicit gate).
    local show_countdown = db.show_druid_shred_countdown == true
    local show_pips = db.show_druid_pips == true
    local show_gcd_tick = db.show_druid_gcd_tick == true
    local show_badge = db.show_druid_maul_badge == true
    local show_omen = db.show_druid_omen_glow == true
    -- The power-type read is shared by every widget that needs the form and only
    -- happens while at least one of them is on (an all-off configuration reads
    -- nothing).
    local power_type
    if show_tick or show_label or show_countdown or show_pips or show_gcd_tick
        or show_badge or show_omen then
        power_type = api.UnitPowerType("player")
    end
    -- The sample flag keeps the energy-cycle anchor alive for the countdown while
    -- the tick bar itself is switched off.
    update_druid_energy_tick(self, vf, db, now, show_tick, power_type, h, show_countdown)
    update_druid_form_label(self, vf, show_label, power_type)
    update_druid_gcd_tick(self, vf, now, show_gcd_tick, show_tick, power_type, h)
    update_druid_shred_countdown(self, vf, now, show_countdown, power_type)
    update_druid_pips(self, vf, show_pips, power_type)
    update_druid_maul_badge(self, vf, show_badge, now, power_type)
    update_druid_omen_glow(vf, show_omen, show_tick, power_type)
    if vf.druid_debuff then
        update_druid_debuff_bars(self, vf, db, now, w)
    end
end

--=========================================================================================
-- Next Action Guide: the druid provider for the generic guide frame
--=========================================================================================
-- Implements the frozen ST.<CLASS>.guide contract documented in nextaction_ui.lua's
-- header. The decision model is the pure st.druid_guide module (druid_guide.lua; its
-- docblock is the frozen spec), the live reads live in gather_guide_inputs, and this
-- table is the last piece of glue: the slot set, the gather/evaluate pair and the static
-- captions. Default OFF (nextaction_enabled=false in config_presets.lua): a wrong prompt
-- is worse than none, so the owner enables it after in-client verification.
--
-- SIX slots (maul, mangle, rip, rake, bite, shred - the contract's maximum). The
-- Mangle / Rip / Rake slots carry a cooldown_key whose source is the module's own target
-- debuff tracker: the icon swipes with the debuff window the guide is telling you to
-- refresh. Maul and the cat builders have no cooldown of their own.

-- One reused input table: no per-frame allocations on the guide tick (the frame passes
-- its own reused table through gather; this one serves direct calls).
ST.DRUID.guide_inputs = {}

-- The current Mangle rank for the guide icon (resolved once through the module's own
-- Mangle id table; false latches a client without any of those ids).
local guide_mangle_current_id

-- The tracker's fallback durations, keyed by debuff key (druid_debuff_defs above), so a
-- debuff the client reports without a duration still gets a full-length slot swipe.
local druid_debuff_fallbacks = {}
for i = 1, #druid_debuff_defs do
    druid_debuff_fallbacks[druid_debuff_defs[i].key] = druid_debuff_defs[i].fallback_duration
end

-- One debuff's remaining seconds from the merged tracker scan, in the frozen input
-- names' shape: nil when the target does not carry it (or the scan has not answered),
-- else the display remaining plus the bar's total span (the slot swipe's length).
local function get_guide_debuff_remaining(key, now)
    if druid_debuff_found[key] ~= true or not druid_energy then
        return nil, nil
    end
    return druid_energy.get_debuff_remaining(druid_debuff_duration[key],
        druid_debuff_expiration[key], now, druid_debuff_fallbacks[key])
end

-- One player buff's remaining seconds from the merged player scan: nil when the
-- buff is absent (or the scan has not answered), else the remaining. No swipe
-- length is fed: no slot swipes off these buffs (the six-slot decision in
-- druid_guide.lua's SLOT DECISION note).
local function get_guide_player_remaining(key, fallback_duration, now)
    if druid_player_found[key] ~= true or not druid_energy then
        return nil
    end
    local remaining = druid_energy.get_debuff_remaining(druid_player_duration[key],
        druid_player_expiration[key], now, fallback_duration)
    return remaining
end

-- Wrath/SoD cooldown queries (Tiger's Fury, Berserk): the client's localized name
-- resolved once through the rank tables above (rank-agnostic: the cooldown is
-- shared across ranks), else the literal English name. A wrong-locale client
-- without a resolving rank degrades to the literal and reads unknown there -
-- the engine never prompts off an unproven ready.
local guide_tf_query
local guide_berserk_query
-- Forever Shifting Power: no rank table exists (no offline source pins an id),
-- so the literal English name is the only query (UNCONFIRMED, like the
-- cooldown length and the energy gain - see druid_guide.lua's FOREVER
-- APPENDIX). A client without the spell reads unknown, never ready.
local guide_sp_query

local function resolve_cooldown_query(ids, literal)
    for id in pairs(ids) do
        local name = api.GetSpellInfo(id)
        if type(name) == "string" then
            return name
        end
    end
    return literal
end

-- One ability's cooldown seconds from the client's own reading, with the HUD's
-- GCD-echo filter (a reading of 1.51 s or less is the running GCD, never one of
-- these abilities' cooldowns). 0 means ready-or-filtered; unreadable (nil)
-- readings degrade to 0 too, so callers must gate on spell knowledge first.
local function guide_cooldown_remaining(query, now)
    local start_time, duration = api.GetSpellCooldown(query)
    if type(start_time) == "number" and type(duration) == "number"
        and duration > 1.51 then
        local remaining = start_time + duration - now
        if remaining > 0 then
            return remaining
        end
    end
    return 0
end

-- SoD shares the ERA token: the only discriminator is spell knowledge. Era-base
-- knows neither Mangle nor Savage Roar, while a SoD feral with the runes knows
-- at least one. Id-first through the module's own Mangle table (33983/33987
-- via api.is_spell_known, locale-independent: a name lookup answers only on a
-- matching-locale client, so a non-English SoD client could never flip on
-- names alone), with the literal names as the fallback (a rune the module
-- never tracked by id, e.g. Savage Roar, still flips an English client).
-- Computed once on first use and latched for the session, like the rank
-- resolvers above and the warrior's post_init SoD freeze (is_sod_client in
-- classes/warrior.lua): one probe serves the gather and the HUD gate, and a
-- rune (un)learned mid-session needs /reload. Callers gate it to the ERA token.
local SOD_PROBE_NAMES = { "Mangle", "Savage Roar" }
local sod_probe_result

-- Id knowledge: any module Mangle rank known (never spell-data existence - a
-- GetSpellInfo answering for an id the player never learned proves nothing).
local function sod_probe_ids_known()
    for id in pairs(druid_mangle_ids) do
        if api.is_spell_known(id) then
            return true
        end
    end
    return false
end

-- Name fallback: a known Mangle or Savage Roar answers GetSpellInfo by name
-- (locale-bound: English clients only, the id probe above carries the rest).
local function sod_probe_names_known()
    for i = 1, #SOD_PROBE_NAMES do
        if type(api.GetSpellInfo(SOD_PROBE_NAMES[i])) == "string" then
            return true
        end
    end
    return false
end

local function sod_runes_present()
    if sod_probe_result == nil then
        if sod_probe_ids_known() or sod_probe_names_known() then
            sod_probe_result = true
        else
            sod_probe_result = false
        end
    end
    if sod_probe_result then
        return true
    end
    return nil
end

-- Slot descriptors: the rank-1 ids ship as the fallback; resolve_guide_icons re-points
-- maul / mangle at the client's current ranks once the spell data is live. The
-- debuff-fed slots use the tracker bars' own fallback durations as their swipe length.
-- On runeless Era the Mangle slot stays declared but dark: the engine never prompts
-- it there (druid_guide.lua ERA APPENDIX) and its ids do not resolve on that client;
-- with sod_runes the SOD APPENDIX prompts it (Mangle via rune), so the slot lights
-- on SoD.
local guide_slot_maul = { key = "maul", spell_id = 6807 }
local guide_slot_mangle = { key = "mangle", spell_id = 33878, cooldown_key = "mangle",
    swipe_duration = 12 }
local guide_slot_rip = { key = "rip", spell_id = 1079, cooldown_key = "rip",
    swipe_duration = 12 }
local guide_slot_rake = { key = "rake", spell_id = 1822, cooldown_key = "rake",
    swipe_duration = 9 }
local guide_slot_bite = { key = "bite", spell_id = 22568 }
local guide_slot_shred = { key = "shred", spell_id = 5221 }

-- Resolve the guide icons to the client's current ranks; called once from post_init,
-- before the shared frame builds its icons. A rank that does not resolve keeps the
-- fallback above (the Mangle fallback is the spec's shared 33878).
function ST.DRUID.resolve_guide_icons()
    maul_current_id = resolve_rank(maul_ids, maul_current_id)
    if maul_current_id then
        guide_slot_maul.spell_id = maul_current_id
    end
    guide_mangle_current_id = resolve_rank(druid_mangle_ids, guide_mangle_current_id)
    if guide_mangle_current_id then
        guide_slot_mangle.spell_id = guide_mangle_current_id
    end
end

-- D4 time-to-die (EMA-smoothed, verify_bank.md §4.1 - BINDING): one throttled sample
-- of the target's health feeds the guide's frozen time_to_die input. The velocity is
-- the exponential moving average of HP/s from druid_energy (TimeToDie-style), never a
-- raw sample - raw samples spike on crits and DoT ticks. State lives on the module
-- instance: the target GUID the baseline belongs to, the last hp reading and its
-- stamp, and the smoothed velocity. Every failure shape (no target, unreadable or
-- dead health, a different target) resets the baseline and reports nil - the engine
-- then takes its documented long-fight default, never a guess.
local function sample_target_time_to_die(self, now)
    if not druid_energy then
        return nil
    end
    local guid = unit_guid and unit_guid("target")
    if type(guid) ~= "string" then
        -- No target (or a client that cannot answer its identity): drop the
        -- baseline so the next target starts clean.
        self.druid_ttd_guid = nil
        self.druid_ttd_hp = nil
        self.druid_ttd_at = nil
        self.druid_ttd_velocity = nil
        return nil
    end
    if guid ~= self.druid_ttd_guid then
        -- A different target: the old baseline is meaningless.
        self.druid_ttd_guid = guid
        self.druid_ttd_hp = nil
        self.druid_ttd_at = nil
        self.druid_ttd_velocity = nil
    end
    local hp = api.UnitHealth("target")
    if type(hp) ~= "number" or hp <= 0 then
        -- Unreadable (a secret value degrades to nil in compat) or dead: no
        -- estimate, and the baseline drops so a revived/repulled target cannot
        -- diff against pre-death health.
        self.druid_ttd_hp = nil
        self.druid_ttd_at = nil
        return nil
    end
    local at = self.druid_ttd_at
    if type(at) ~= "number" then
        -- First sample for this target: seed the baseline, no estimate yet.
        self.druid_ttd_at = now
        self.druid_ttd_hp = hp
        return nil
    end
    if now - at < druid_energy.TTD_SAMPLE_SECONDS then
        -- Too soon for a new sample: keep the stored one and ride the current
        -- EMA with the live hp.
        return druid_energy.get_time_to_die(hp, self.druid_ttd_velocity)
    end
    local prev_hp = self.druid_ttd_hp
    self.druid_ttd_at = now
    self.druid_ttd_hp = hp
    self.druid_ttd_velocity = druid_energy.update_hp_velocity(
        self.druid_ttd_velocity, hp, prev_hp, now - at)
    return druid_energy.get_time_to_die(hp, self.druid_ttd_velocity)
end

-- Live inputs for the pure engine, written into the caller-owned reused table. Every
-- field of the frozen input set is written on every call, so no stale value can survive
-- between ticks; nil means "the client did not answer".
function ST.DRUID.gather_guide_inputs(self, out)
    local inputs = out or ST.DRUID.guide_inputs
    local now = api.get_time()
    local d = self.mainhand
    local gcd = self.gcd
    local db = self:get_class_table()

    -- Swing and GCD, in the api.get_time() domain (ends_at and the GCD stamp share it).
    inputs.speed = (d and d.speed) or 0
    inputs.swing_remaining = math.max(0, ((d and d.ends_at) or now) - now)
    inputs.gcd_remaining = (gcd and gcd.expires and math.max(0, gcd.expires - now)) or 0

    -- The live form decides which pool is read, with the explicit power type (1 rage in
    -- bear, 3 energy in cat); combo points are the shared 4th power type in cat. An
    -- unreadable pool stays nil - the engine treats "not a number" as not sufficient.
    local form = self.form_index
    inputs.form_index = form
    local value
    inputs.rage = nil
    if form == 1 then
        value = api.UnitPower("player", 1)
        if type(value) == "number" then
            inputs.rage = value
        end
    end
    inputs.energy = nil
    if form == 3 then
        value = api.UnitPower("player", 3)
        if type(value) == "number" then
            inputs.energy = value
        end
    end
    inputs.combo_points = nil
    if form == 3 then
        value = api.UnitPower("player", 4)
        if type(value) == "number" then
            inputs.combo_points = value
        end
    end

    -- The client family for the pure engine's TBC branch (compat.lua's
    -- st.family). A client that cannot answer still reports a family string
    -- ("UNKNOWN"), which runs the legacy matrix.
    inputs.family = st.family

    -- Finisher context. D4: the time-to-die input now carries the EMA-smoothed
    -- HP/s estimate (sample_target_time_to_die above) whenever the target's
    -- health is readable - unknown (no target, unreadable or dead health) stays
    -- nil and the engine takes its documented long-fight default. The estimate is
    -- the only execute signal that exists (the Wrath W8 window and the TBC T3
    -- short-lived Bite both read time_to_die); target_short_lived stays nil - the
    -- explicit flag has no client source.
    -- can_powershift stays nil and no engine rule reads it (RESERVED
    -- plug-in point): the Furor + Wolfshead Helm basis has no honest client
    -- probe - main.lua's talent_positions covers WRATH only (no verified TBC
    -- Furor tab/index, so a GetTalentInfo read would be a guess) and no
    -- Wolfshead Helm item id is verified in this codebase (so a
    -- GetInventoryItemID read would be a guess). The SHIFT branches that read
    -- it were removed with their constants (see druid_guide.lua); do not
    -- re-add the call without a confirmed probe.
    inputs.time_to_die = sample_target_time_to_die(self, now)
    inputs.target_short_lived = nil
    inputs.can_powershift = nil

    -- The Maul queue state and the module's own shortfall flag.
    inputs.maul_queued = self.maul_queued and true or false
    inputs.insufficient_rage = self.insufficient_rage and true or false

    -- Maul's rage cost through the client's current rank (the rank cache makes this a
    -- lookup once resolved; a nil cost means the client cannot answer).
    maul_current_id = resolve_rank(maul_ids, maul_current_id)
    local costs = maul_current_id and api.GetSpellPowerCost(maul_current_id)
    inputs.maul_cost = rage_cost_of(costs)

    -- TBC MICRO (docs/research/tbc_minmax.md 2pc-T6: Mangle at 35 energy): the
    -- live Mangle energy cost through the module's current Mangle rank, using
    -- the shared cost extractor above (first cost entry, secret-safe). TBC-
    -- gated so every other family keeps its single cost query; a nil cost (an
    -- unresolved rank, a client that cannot answer) means the engine falls
    -- back to MANGLE_COST_TBC. Whether the TBC client reports the set
    -- reduction through GetSpellPowerCost is in-game to confirm.
    inputs.mangle_cost = nil
    if inputs.family == "TBC" then
        guide_mangle_current_id = resolve_rank(druid_mangle_ids, guide_mangle_current_id)
        if guide_mangle_current_id then
            inputs.mangle_cost = rage_cost_of(api.GetSpellPowerCost(guide_mangle_current_id))
        end
    end

    -- The tracker's debuff windows, in the frozen names plus the slots' swipe fields.
    inputs.mangle_remaining, inputs.mangle_duration = get_guide_debuff_remaining("mangle", now)
    inputs.rip_remaining, inputs.rip_duration = get_guide_debuff_remaining("rip", now)
    inputs.rake_remaining, inputs.rake_duration = get_guide_debuff_remaining("rake", now)

    -- Wrath (WRATH) and SoD (ERA + runes) buff/cooldown inputs. Every field is
    -- written on every call: unknown stays nil and the engine treats "not a
    -- number" / "not true" as not sufficient - it never prompts off a guess.
    -- A player without the spell (or on the wrong locale) reads unknown: the
    -- Wrath/SoD chains stay dormant there instead of misfiring.
    inputs.sr_remaining = get_guide_player_remaining("sr",
        DRUID_SR_FALLBACK_DURATION, now)
    inputs.clearcast = druid_player_found.omen == true and true or nil
    inputs.tf_active = druid_player_found.tf == true and true or nil
    inputs.tf_ready = nil
    inputs.tf_cd_remaining = nil
    inputs.berserk_ready = nil
    if guide_tf_query == nil then
        guide_tf_query = resolve_cooldown_query(druid_tf_ids, "Tiger's Fury")
    end
    if type(api.GetSpellInfo(guide_tf_query)) == "string" then
        local tf_remaining = guide_cooldown_remaining(guide_tf_query, now)
        inputs.tf_cd_remaining = tf_remaining
        inputs.tf_ready = tf_remaining <= 0
    end
    if guide_berserk_query == nil then
        guide_berserk_query = resolve_cooldown_query(druid_berserk_ids, "Berserk")
    end
    if type(api.GetSpellInfo(guide_berserk_query)) == "string" then
        if guide_cooldown_remaining(guide_berserk_query, now) <= 0 then
            inputs.berserk_ready = true
        end
    end
    -- Forever Shifting Power (FOREVER-gated, so every other family neither
    -- queries nor keeps a stale value): proven ready (true) or proven on
    -- cooldown (false) through the literal name with the HUD's GCD-echo
    -- filter; unknown stays nil and F1 stays dormant. The 16 s cooldown, the
    -- 40-energy gain and the mana cost are UNCONFIRMED (see druid_guide.lua's
    -- FOREVER APPENDIX); the <= 60 room check in the engine's F1 is likewise
    -- UNCONFIRMED beta prose (SP_ENERGY_FOREVER). sp_ready is the knowledge
    -- gate (the GetSpellInfo name query is the only probe Forever exposes,
    -- since no spell id is published); the 60/40 values themselves are
    -- assumed. The mana affordability itself is not modelled.
    inputs.sp_ready = nil
    inputs.sp_cd_remaining = nil
    if inputs.family == "FOREVER" then
        if guide_sp_query == nil then
            guide_sp_query = "Shifting Power"
        end
        if type(api.GetSpellInfo(guide_sp_query)) == "string" then
            local sp_remaining = guide_cooldown_remaining(guide_sp_query, now)
            inputs.sp_cd_remaining = sp_remaining
            inputs.sp_ready = sp_remaining <= 0
        end
    end
    if inputs.family == "ERA" then
        inputs.sod_runes = sod_runes_present()
    else
        inputs.sod_runes = nil
    end

    -- The refresh thresholds from the options (0-10 s, defaults 4).
    inputs.rip_refresh = db.guide_rip_refresh or 4
    inputs.rake_refresh = db.guide_rake_refresh or 4
    return inputs
end

ST.DRUID.guide = {
    slots = { guide_slot_maul, guide_slot_mangle, guide_slot_rip, guide_slot_rake,
        guide_slot_bite, guide_slot_shred },

    -- Live inputs: the gather above, verbatim, into the caller's reused table.
    gather = function(self, out)
        return ST.DRUID.gather_guide_inputs(self, out)
    end,

    -- Pure: the frozen druid rule matrix (st.druid_guide in druid_guide.lua); guarded
    -- so a flavor without that module stays inert rather than erroring.
    evaluate = function(inputs, out)
        if st.druid_guide and st.druid_guide.evaluate then
            return st.druid_guide.evaluate(inputs, out)
        end
        return out
    end,

    -- Static captions (defaults; the RIDE/HOLD text rides out.hold_text).
    labels = { next_action = "Next action:", hold = "HOLD", ride = "RIDE" },
}

--=========================================================================================
-- Cooldown HUD: druid slots and the live state provider
--=========================================================================================
-- The slot set mirrors the Next Action Guide's six slots (ST.DRUID.guide above: the
-- class's top-parse abilities), plus the D2 Tiger's Fury / Berserk cooldown slots and
-- the two trinket slots the HUD serves itself. The descriptor and provider contracts
-- are frozen in hud.lua's header comment; the "trinket" slots need no provider entry.
--
-- Rank notes: the guide's own slot ids ship as the icon fallback (the spell art is
-- rank-invariant), while the provider reads cooldowns by the client's own localized
-- name (hud_slot_name), so whatever rank the player knows is what is counted - the
-- paladin's cooldown_spell-free convention from classes/paladin.lua. Maul (6807),
-- Rip (1079) and Rake (1822) are the rank-1 ids of the module's own rank tables;
-- Mangle (33878), Ferocious Bite (22568) and Shred (5221) mirror the guide slots
-- and are UNCONFIRMED: none of them is covered by a rank table in this module, so
-- confirm with GetSpellInfo on the target client before release.
-- D2: Tiger's Fury ships the Era/TBC rank 9845 as its fallback icon id (the rank
-- table above re-points it at post_init), Berserk ships 50334 (the WotLK ability,
-- verify_bank §2). Both slots hide themselves where the client's spell data carries
-- no such spell (the liveness gates in get_hud_state): TF is name-resolved (the
-- rank-dependent ids make any single id wrong - the correction), Berserk also rides
-- the SoD rune basis on the ERA token (Era-base has no Berserk). Unlike the six
-- rotational slots, TF and Berserk carry real cooldowns (30 s / 3 min), so they never
-- borrow the GCD swipe (the paladin judgement/wings rule).
-- The six rotational slots have no cooldown of their own on the classic line, so they
-- show the running GCD swipe plus the mana/range tints; a queued Maul the player
-- cannot afford greys the Maul slot (the module's own shortfall flag).
local hud_slot_tf = { key = "tf", title = "Tiger's Fury", kind = "spell", spell = 9845 }
local hud_slot_berserk = { key = "berserk", title = "Berserk", kind = "spell", spell = 50334 }

ST.DRUID.HUD_SLOTS = {
    { key = "maul", title = "Maul", kind = "spell", spell = 6807 },
    { key = "mangle", title = "Mangle", kind = "spell", spell = 33878 },
    { key = "rip", title = "Rip", kind = "spell", spell = 1079 },
    { key = "rake", title = "Rake", kind = "spell", spell = 1822 },
    { key = "bite", title = "Ferocious Bite", kind = "spell", spell = 22568 },
    { key = "shred", title = "Shred", kind = "spell", spell = 5221 },
    hud_slot_tf,
    hud_slot_berserk,
    { key = "trinket1", title = "Trinket 1", kind = "trinket", inv_slot = 13 },
    { key = "trinket2", title = "Trinket 2", kind = "trinket", inv_slot = 14 },
}

-- D2: re-point the TF/Berserk slot icons at the client's current ranks (called once
-- from post_init, after the guide icon resolution). Only the icon art follows the
-- rank - the cooldown read itself is name-based.
local hud_tf_current_id
local hud_berserk_current_id

function ST.DRUID.resolve_hud_slot_icons()
    hud_tf_current_id = resolve_rank(druid_tf_ids, hud_tf_current_id)
    if hud_tf_current_id then
        hud_slot_tf.spell = hud_tf_current_id
    end
    hud_berserk_current_id = resolve_rank(druid_berserk_ids, hud_berserk_current_id)
    if hud_berserk_current_id then
        hud_slot_berserk.spell = hud_berserk_current_id
    end
end

-- D2 slot liveness probes: resolved through the client's spell data (any rank id in
-- the table, then the literal English name). A positive answer latches for the
-- session; a negative answer retries at the names-retry cadence, because the client's
-- spell data may still be loading when the HUD first paints. Berserk additionally
-- rides the SoD rune basis on the ERA token (Era-base has no Berserk; the rune grants
-- it - the same sod_runes_present probe the Mangle slot uses). Off-token families
-- (Forever's absent TF per the beta docs) simply never resolve, and the slot hides.
local DRUID_HUD_PROBE_RETRY_S = DRUID_DEBUFF_NAMES_RETRY_S
local hud_tf_live
local hud_tf_probe_at
local hud_berserk_live
local hud_berserk_probe_at

local function spell_data_resolves(ids, literal)
    for id in pairs(ids) do
        if type(api.GetSpellInfo(id)) == "string" then
            return true
        end
    end
    return type(api.GetSpellInfo(literal)) == "string"
end

local function tf_slot_live(now)
    if hud_tf_live then
        return true
    end
    if now >= (hud_tf_probe_at or 0) then
        if spell_data_resolves(druid_tf_ids, "Tiger's Fury") then
            hud_tf_live = true
            return true
        end
        hud_tf_probe_at = now + DRUID_HUD_PROBE_RETRY_S
    end
    return false
end

local function berserk_slot_live(now)
    if hud_berserk_live then
        return true
    end
    if now >= (hud_berserk_probe_at or 0) then
        if spell_data_resolves(druid_berserk_ids, "Berserk")
            or (st.family == "ERA" and sod_runes_present() == true) then
            hud_berserk_live = true
            return true
        end
        hud_berserk_probe_at = now + DRUID_HUD_PROBE_RETRY_S
    end
    return false
end

-- One reused state table: the HUD reads it immediately and never keeps a reference
-- (see the frozen contract in hud.lua), so there is no per-tick allocation here.
ST.DRUID.hud_state = {}

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
-- cooldown of its own. The six rotational slots have no native cooldown, so their
-- entries are 0 (the slots show the GCD swipe only); TF and Berserk DO carry real
-- cooldowns (30 s / 3 min) and their entries are only the ready-state fallback -
-- the live duration comes from the client's own reading when they burn. Kept as a
-- table (rather than a constant) so a future cooldown-carrying ability slots in
-- without reshaping the provider.
local HUD_COOLDOWN_FALLBACK = {
    maul = 0,
    mangle = 0,
    rip = 0,
    rake = 0,
    bite = 0,
    shred = 0,
    tf = 0,
    berserk = 0,
}

-- Slots that never borrow the GCD swipe (the paladin's judgement/wings rule in
-- classes/paladin.lua): the two D2 cooldown slots (TF/Berserk are off the global
-- cooldown on the classic line - UNCONFIRMED, in-game to confirm; a wrong entry
-- only withholds a GCD swipe from a ready icon). Every rotational slot shows the
-- running GCD.
local HUD_SKIP_GCD = { tf = true, berserk = true }

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

-- Remaining time and full duration of one druid ability cooldown: the client's own
-- reading by localized name (rank-agnostic), with the GCD echo filtered (a reading
-- of 1.51 s or less is the running GCD, never one of these abilities' cooldowns).
-- A missing reading means ready, which is the steady state for these slots.
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
-- mapping (hud.lua:418-453) re-expressed for the druid slots. The Maul slot greys
-- while the module's shortfall flag says the queued Maul is unaffordable; the D2
-- TF/Berserk slots glow while ready in combat (the paladin wings rule).
function ST.DRUID.get_hud_state(self, slot, now)
    local s = ST.DRUID.hud_state
    s.remaining, s.duration, s.start, s.reverse = nil, nil, nil, nil
    s.text_remaining, s.desaturate, s.usable, s.in_range = nil, nil, nil, nil
    s.glow, s.count, s.texture, s.hidden = nil, nil, nil, nil
    -- Runeless Era has no Mangle (TBC+ ids; the tracker bar stays inert there for
    -- the same reason): draw nothing for the slot. The guide engine likewise never
    -- prompts it on runeless ERA, so the guide icon stays dark too. SoD shares the
    -- ERA token but proves Mangle via rune (sod_runes_present above): the slot
    -- stays live there.
    now = now or api.get_time()
    if slot.key == "mangle" and st.family == "ERA" and sod_runes_present() ~= true then
        s.hidden = true
        return s
    end
    -- D2: TF/Berserk exist only where the client's spell data carries them (the
    -- liveness probes above; Berserk also rides the SoD rune basis on ERA).
    if slot.key == "tf" and not tf_slot_live(now) then
        s.hidden = true
        return s
    end
    if slot.key == "berserk" and not berserk_slot_live(now) then
        s.hidden = true
        return s
    end
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

    if slot.key == "maul" and self.insufficient_rage then
        s.desaturate = true
    end
    if slot.key == "tf" or slot.key == "berserk" then
        -- The standard ready-in-combat glow (the paladin wings rule): the icon
        -- lights while the ability is available.
        s.glow = (remaining <= 0 and self.in_combat == true) or false
    end
    return s
end

--=========================================================================================
-- Rotation text: the druid rotation source
--=========================================================================================
-- Implements the frozen ST.<CLASS>.get_rotation_key contract documented in
-- rotationtext.lua's header, following the paladin's shape (ST.PALADIN.
-- get_rotation_key in rotationtext.lua): the guide's own decision, so the label and
-- the guide can never disagree. The druid engine names no rotations (its
-- out.rotation_key is always nil), so the label is the current action: the
-- recommended ability's localized name (resolved from the guide's own slot
-- descriptors, cached per spell id), HOLD while the engine holds, RIDE while it
-- rides (Maul queued on the next swing), nil
-- when the guide is idle (renders as the empty text). No practice branch: Twist
-- Practice is paladin-only (no simulation exists for this class). One reused
-- output table: no per-tick allocation on the label tick.
ST.DRUID.rotation_out = {}

-- The guide slot's localized spell name for an action key (the slot's current-rank
-- spell id, so a re-pointed icon re-points the label with it). Falls back to the
-- raw action key when the client's spell data has not answered yet.
local rotation_name_cache = {}

local function rotation_ability_name(action)
    local spell_id
    local slots = ST.DRUID.guide.slots
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

function ST.DRUID.get_rotation_key(self)
    local guide = ST.DRUID.guide
    local engine = st.druid_guide
    if not (guide and guide.gather and guide.evaluate and engine and engine.evaluate) then
        return nil
    end
    local out = guide.evaluate(guide.gather(self, ST.DRUID.guide_inputs),
        ST.DRUID.rotation_out)
    if out.action ~= nil then
        return rotation_ability_name(out.action)
    end
    if out.hold then
        return out.hold_text
    end
    return nil
end

if st.debug then st.utils.print_msg('-- Parsed classes/druid.lua module correctly') end

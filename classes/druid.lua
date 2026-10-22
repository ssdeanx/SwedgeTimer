--=========================================================================================
-- Module for Druid-specific behaviours: the Maul queue colour, plus (mirroring the
-- shaman/hunter/paladin ports of the reference) the druid tracker set - the cat-form
-- energy tick bar, the mainhand form label and the Mangle/Rip/Rake target debuff bars
-- (reference SuperSwingTimer_ClassMods.lua druid block 4514-5524). The pure maths
-- (energy cycle, natural-gain classifier, form-label mapping, debuff display rules,
-- the D4 TTD EMA plus the D1 readout text, the D2 proc-aware tick classifier, the
-- D5 countdown and the GCD-tick fraction) lives in druid_energy.lua; this module
-- gathers the live readings and drives the widgets on the mainhand visuals frame.
--
-- Build-out round 1 additions (all nil-safe toggles, default OFF - the options pass
-- wires the widgets): D2 Tiger's Fury / Berserk HUD slots (name-based lookups; the
-- slots gate themselves per family through the client's spell data), D3 combo-point
-- pips (the installed ST:new_pips factory from the bars-design lane), D4 EMA-smoothed
-- time-to-die feeding the guide's frozen time_to_die input, D5 "Shred in Xs" energy
-- countdown, D6 Maul-efficiency badge (time at the rage cap per fight), the Omen of
-- Clarity proc glow (discover #8) and the energy tick bar's GCD tick overlay
-- (discover #4). Competitor-gaps round 2 (all nil-safe, default OFF - the options
-- pass wires the widget): D1 TTD readout text (the D4 estimate made visible, any
-- form) and the D2 proc-aware tick anchor (a SoD King-of-the-Jungle TF +60 observed
-- since the last sample is removed before the tick classifier runs; every other
-- family keeps the legacy window verbatim). D1 (powershift probe) stays blocked - the
-- Furor half still has no honest offline probe; the Wolfshead Helm half now reads
-- through api.is_item_equipped and both reserved plug-ins are documented in
-- gather_guide_inputs.
--
-- Practice surface (the shared engine looks it up by player_class): the rotation
-- table (the sim priority order per family, every entry citing its sim file), the
-- scenario step (the guide engine's own answer for the current state) and the drill
-- list (the audited target drill set, each drill grading the current moment). See
-- the "Practice: the rotation table, the scenario step and the druid drills" section
-- below for the ctx contract the engine writes.
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
st.class_loaders = st.class_loaders or {}
st.class_loaders["DRUID"] = function()
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
-- The Savage Roar's own window: the client tracks the aura's expiry, so the class
-- remembers the last expiry it saw and latches whether the Roar was ever up this
-- fight. The upkeep drill reads both: how long the Roar has been down (the lateness)
-- and whether it was ever maintained (the "never maintained" band).
local druid_sr_last_expiration = nil
local druid_sr_seen = nil
-- Whether the player-buff scan has run at least once (the "the Roar was never up"
-- verdict needs a scan that actually looked).
local druid_player_scanned = false
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

-- Name-vs-id rule (bench/lessons.md): TBC Anniversary resolves by NAME never
-- bare id; Classic Era by id. spell_query branches every direct spell read
-- (GetSpellInfo / GetSpellCooldown / is_spell_known / IsSpellUsable /
-- IsSpellInRange / IsCurrentSpell / GetSpellPowerCost) via st.family.
-- Nil-safe: a nil id/name stays nil so unknown-hides is preserved.
local function spell_query(id, name)
    if st.family == "TBC" then
        return name
    end
    return id
end

-- English names for the TBC name path (rank-invariant; the localized name is
-- shared across ranks, so a single literal covers the whole rank table).
local MAUL_NAME = "Maul"
local MANGLE_NAME = "Mangle"
local RIP_NAME = "Rip"
local RAKE_NAME = "Rake"
local TF_NAME = "Tiger's Fury"
local BERSERK_NAME = "Berserk"
local SHRED_NAME = "Shred"
local BITE_NAME = "Ferocious Bite"
local CLAW_NAME = "Claw"
local SR_NAME = "Savage Roar"
local FF_NAME = "Faerie Fire"
local SP_NAME = "Shifting Power"
-- The APL utility layer's names (the literal English fallback for the name-resolving
-- clients): the Feral Faerie Fire (the client's own name for 17392 / 27011), Innervate
-- and Elune's Light (the name the Forever APL's own variable carries).
local FERAL_FF_NAME = "Faerie Fire (Feral)"
local INNERVATE_NAME = "Innervate"
local ELUNES_LIGHT_NAME = "Elune's Light"

-- Rank resolution retry throttle: a client that cannot answer right now (a cold spell
-- book, a restricted read) is asked again after the backoff instead of on every bar frame
-- (the rogue lane's retry-able latch shape, classes/rogue.lua ROGUE_SPELL_RETRY).
local RANK_RESOLVE_RETRY = 5.0
-- Per rank table: the time of the next allowed retry after an "unresolved" verdict.
local rank_retry_at = {}

-- Resolves the highest rank that exists on the running client. The resolver's verdict is
-- three-valued (audit F4, bench/f4_family_spell_id_2026-10-19.md):
--   resolved   - the client confirmed a rank; the id is latched.
--   absent     - the client refuted every candidate. FINAL: the negative is latched, so
--                the table is never walked again.
--   unresolved - the client could not answer (a cold spell book, a restricted read).
--                RETRYABLE: nothing is latched and the next attempt asks again, so a cold
--                book can no longer poison the rank for the rest of the session.
local function resolve_rank(ids, cached)
    if cached ~= nil then
        return cached
    end
    local now = api.get_time()
    if type(now) == "number" and now < (rank_retry_at[ids] or 0) then
        -- Still backing off from the last "unresolved" verdict: no walk, no latch.
        return nil
    end
    local id, state = api.get_family_spell_id_state(ids)
    if id ~= nil then
        return id
    end
    if state == "absent" then
        return false
    end
    -- "unresolved" (or an unknown verdict): the client could not answer, so nothing is
    -- latched; the next attempt asks again, after the retry backoff.
    if type(now) == "number" then
        rank_retry_at[ids] = now + RANK_RESOLVE_RETRY
    end
    return nil
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
        -- Name-vs-id: TBC costs by NAME, Era by id.
        return update_rage_state(self, spell_query(maul_current_id or nil, MAUL_NAME))
    end
    -- Nothing queued: clear a stale "insufficient rage" colour left by the last fight.
    if self.insufficient_rage then
        self.insufficient_rage = false
        self:set_bar_color("mainhand")
    end
end

-- Maul token match for the spellcast clear hooks: Era matches the rank-id
-- table; TBC matches the English name (never a bare id there). Nil-safe.
local function is_maul_token(token)
    if token == nil then
        return false
    end
    if st.family == "TBC" then
        return token == MAUL_NAME
    end
    return maul_ids[token] ~= nil
end

function ST.DRUID.on_spellcast_failed_quiet(self, unit_id, cast_guid, spell_id)
    if is_maul_token(spell_id) or is_maul_token(cast_guid) then
        self.maul_queued = false
        self:set_bar_color("mainhand")
    end
end

function ST.DRUID.on_spellcast_succeeded(self, unit_target, cast_guid, spell_id)
    if is_maul_token(spell_id) or is_maul_token(cast_guid) then
        self.maul_queued = false
        self:set_bar_color("mainhand")
    end
end

-- G1 (queued-melee tint clears, reference SuperSwingTimer_State.lua:1129-1149): an
-- INTERRUPTED or FAILED cast clears the Maul queue tint when the token matches Maul
-- (Era id, TBC name via is_maul_token) or names nothing identifiable (nil token).
-- SUCCEEDED/FAILED_QUIET keep their own hooks; CURRENT_SPELL_CAST_CHANGED re-arms
-- a genuinely live queue on its next probe, so this clear self-heals.
function ST.DRUID.on_spellcast_event(self, event, unit, cast_guid, spell_id)
    if unit ~= "player" or not self.interfaces_are_initialised then
        return
    end
    if event ~= "UNIT_SPELLCAST_INTERRUPTED" and event ~= "UNIT_SPELLCAST_FAILED" then
        return
    end
    local token = spell_id
    if token == nil then
        token = cast_guid
    end
    if token == nil or is_maul_token(token) then
        if self.maul_queued == true then
            self.maul_queued = false
            self:set_bar_color("mainhand")
        else
            self.maul_queued = false
        end
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

    if st.family == "TBC" then
        -- Name-vs-id: a single NAME probe covers all Maul ranks on TBC.
        if api.IsCurrentSpell(MAUL_NAME) then
            self.maul_queued = true
            self:set_bar_color("mainhand")
            return
        end
        self.maul_queued = false
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
    -- D1 readout latch (see update_druid_ttd_readout) and the D2 proc supplier
    -- state (see sample_druid_tf_proc): the TF buff's previous frame and the
    -- one-shot grant the next energy sample consumes.
    self.druid_ttd_shown = nil
    self.druid_tf_was_active = nil
    self.druid_proc_gain = nil
    -- Fight clock for the guide's fight-elapsed gates (Era/SoD 8 s, Forever
    -- 10 s Rip gates): the api.get_time() stamp of the current fight's first
    -- in-combat tick; nil out of combat (the gather then reports unknown and
    -- the engine takes its long-fight default). Deliberately combat-gated, not
    -- swing-gated: the Forever client must report it too.
    self.druid_fight_start_at = nil
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
    -- Runs before the practice init below: the shared post_init order is guide,
    -- HUD, practice in all six class modules (deep-audit F9).
    if st.hud then
        st.hud.init(self)
    end
    -- Practice: builds the shared session panel/frames; guarded so a flavor
    -- without the practice files stays inert (the paladin wires it the same way
    -- in classes/paladin.lua). The session itself is class-agnostic - the options
    -- Practice toggle starts it, the panel icons cast the simulated spells - and
    -- the sync/restore seams below keep that flow druid-safe.
        -- The neutral publish follows the class's OWN build decision (the SoD rune
        -- basis the rotation family already carries): on the SoD build the rotation
        -- asks for the Rake, so the `rake` key must not be published as neutral
        -- there (a rotation action can never be neutral). It runs outside the
        -- practice block on purpose - the publish is the class's own statement, and
        -- it must be right whether or not the practice surface is present. The
        -- probe's own latch corrects it the moment the build is known.
        ST.DRUID.apply_neutral_build_pick()
    if st.practice_ui and type(st.practice_ui.init) == "function" then
        -- The practice panel's action vocabulary: the class's own guide slots plus
        -- the common abilities (the heals, the movement spell, food, a potion).
        -- The guide frame above already built its icons from the display vocabulary,
        -- so this widens the PANEL's strip, not the frame (the shaman's
        -- apply_family_slots precedent).
        ST.DRUID.apply_practice_panel_actions()
        st.practice_ui.init(self)
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
    -- A fight's proc grant must not leak into the next pull's first sample.
    self.druid_proc_gain = nil
    -- The fight clock dies with the fight: the next pull re-seats it on its
    -- first in-combat tick (see ensure_druid_fight_stamp), so a stale stamp can
    -- never gate the next fight's Rip.
    self.druid_fight_start_at = nil
    -- The Roar's fight latch dies with the fight too (the upkeep drill's "was it
    -- ever up" measure): the next pull starts unknown again.
    druid_sr_seen = nil
    druid_player_scanned = false
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

-- SoD King-of-the-Jungle Tiger's Fury energy grant (+60, docs/research/rotations_sod.md
-- - SoD-only): the D2 proc supplier stamps this one-shot grant on the buff's rising
-- edge; every other family reads nil (no honest TF amount exists there to attribute).
local DRUID_SOD_TF_PROC_GAIN = 60

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
-- D1 readout line: stacked below the countdown/badge line (which the TTD readout
-- can share the frame with in cat form), so the two texts never overlap.
local DRUID_TTD_STACK_OFFSET = DRUID_BOTTOM_TEXT_GAP
    + DRUID_COUNTDOWN_TEXT_SIZE + DRUID_BOTTOM_TEXT_GAP

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
local druid_tf_ids = get_tab({ 5217, 6793, 9845, 9846, 50213, 417045 })
-- Feral Berserk (WotLK 50334, verified against Wowhead wotlk/spell=50334; the
-- only rank - the talent itself is the ability). 417141 is the Season of Discovery
-- rune and the Forever talent (the same spell on both: wowsims/sod sim/druid/
-- berserk.go:17 and wowsims/forever sim/druid/spell_data_auto_gen.go: the Berserk
-- ladder, "Berserk: spelldata.Talent(417141, 1)").
local druid_berserk_ids = get_tab({ 50334, 417141 })
-- Savage Roar (WotLK 52610, verified against Wowhead wotlk/spell=52610: 25
-- energy, requires combo points; TBC ranks are unconfirmed - the literal
-- fallback carries those clients, in-game to confirm). 407988 is the Season of
-- Discovery rune (wowsims/sod sim/druid/savage_roar.go:20).
local druid_sr_ids = get_tab({ 52610, 407988 })
-- Leader of the Pack (the party crit buff the Era APL's LoP row is about): 17007 is
-- the client's own druid spell - the 1.15 client's own spell table carries the
-- Leader of the Pack text under 17007 and the spell sits in the Feral Combat skill
-- line (wow.export Spell.csv + SkillLineAbility.csv, the Classic 1.15 client). The
-- Era APL's row itself casts 13494, which the same client names "Haste" and puts in
-- NO druid skill line - see the rotation table's leader_of_the_pack row.
local druid_lop_ids = get_tab({ 17007 })
-- The Faerie Fire debuffs the target can carry, per family (the Feral Fire id and
-- the plain Faerie Fire id of that client): the Era/SoD client has Faerie Fire
-- (Feral) 17392 r4 and Faerie Fire 9907 r4 (the 1.15 client's own spell table: the
-- rank subtexts); the TBC client has Faerie Fire (Feral) 27011 r5 and Faerie Fire
-- 26993 r5 (wowsims/tbc-new sim/druid/spell_data_auto_gen.go: the FaerieFire and
-- FaerieFireFeral tables); the WotLK client has Faerie Fire (Feral) 16857 r1 and
-- Faerie Fire 770 (wowsims/wotlk sim/druid/faerie_fire.go:11,22); the Forever client
-- has Faerie Fire 9907 r4 (wowsims/forever sim/druid/spell_data_auto_gen.go: the
-- FaerieFire ladder).
local druid_ff_ids = {
    ERA = get_tab({ 17392, 9907 }),
    SOD = get_tab({ 17392, 9907 }),
    TBC = get_tab({ 27011, 26993 }),
    WRATH = get_tab({ 16857, 770 }),
    FOREVER = get_tab({ 9907 }),
}
-- The Cat Form aura (the shapeshift aura the APL's form row watches): the id is the
-- client's own Cat Form spell (768 - wowsims/classic sim/druid/forms.go:88, the same
-- id the Era, SoD and Forever APLs cast for the row). The player's own aura walk
-- matches it by id first, then by the client's localized name, then by the literal
-- English fallback.
local druid_cat_form_ids = get_tab({ 768 })
-- The Feral-tree probe spell per family - the class's own SPEC read ("is this a
-- feral druid?"). Every id below is a Feral-TREE talent, so api.is_spell_known
-- answers "the player has Feral-tree points":
--   ERA (and the SoD, the same client)  17392 Faerie Fire (Feral) - the Era sim
--       gates the spell on druid.Talents.FaerieFireFeral (wowsims/classic
--       sim/druid/faerie_fire.go:26; the SoD sim's own faerie_fire.go:41)
--   TBC      27011 Faerie Fire (Feral) r5 - the TBC sim gates it on
--       druid.Talents.FaerieFireFeral (wowsims/tbc-new sim/druid/faerie_fire.go:49)
--   FOREVER  17007 Leader of the Pack - the Feral Combat tree talent (wowsims/
--       forever sim/druid/druid.go:115: druid.Talents.LeaderOfThePack; the spell
--       ladder 17007 in the sim's spell_data_auto_gen.go). The Forever client has
--       no Feral Faerie Fire at all (its Faerie Fire ladder is 770/778/9749/9907).
-- The WotLK client has no row: the WotLK APL carries no Cat Form row.
local druid_feral_spec_id = {
    ERA = 17392,
    TBC = 27011,
    FOREVER = 17007,
}
-- The Faerie Fire the family's APL casts (the Feral one on Era/TBC - the plain one on
-- Forever, which has no Feral Faerie Fire): the cooldown read's id. The set above
-- carries the debuff ids the target can carry (both the Feral and the plain one).
local druid_feral_ff_id = {
    ERA = 17392,
    SOD = 17392,
    TBC = 27011,
    FOREVER = 9907,
}
-- Innervate (the APL's mana row on Era, SoD and Forever: 29166 on every one of them -
-- wowsims/classic sim/druid/innervate.go:16, wowsims/sod sim/druid/innervate.go:16,
-- wowsims/forever sim/druid/spell_data_auto_gen.go: the Innervate ladder).
local druid_innervate_ids = get_tab({ 29166 })
-- The utility layer's cooldown queries, cached per key (the class's own pattern, see
-- guide_tf_query above): the id for the id-resolving clients, the literal English
-- name for the name-resolving one (TBC) - resolved once, then reused.
local druid_utility_queries = {}
-- The Faerie Fire debuff's fallback length (only used when the client lists the aura
-- without a duration): 16 s - the Era APL's row i=8 refreshes the Feral Faerie Fire
-- when the debuff has 14 s or less left, so the debuff's own length is about 16 s
-- (the 1.15 client's spell table carries no duration row for 17392).
local DRUID_FF_FALLBACK_DURATION = 16
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
        fallback_names = { [SR_NAME] = true },
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
        fallback_names = { [TF_NAME] = true },
        fallback_duration = 6,
    },
    {
        -- Leader of the Pack (the party crit buff the Era APL's LoP row casts):
        -- the guide-only read - this walk feeds no bar, it answers "is the Leader
        -- of the Pack up" for the Era upkeep (the rotation table's
        -- leader_of_the_pack row).
        key = "lop",
        ids = druid_lop_ids,
        fallback_names = { ["Leader of the Pack"] = true },
        fallback_duration = 180,
    },
    {
        -- The Cat Form aura (the APL's form upkeep row: "cast it when the Cat
        -- Form aura is not active"): the guide-only read - this walk feeds no
        -- bar, it answers "is the player in the cat form" for the form upkeep
        -- (the rotation table's cat_form row).
        key = "catform",
        ids = druid_cat_form_ids,
        fallback_names = { ["Cat Form"] = true },
    },
}

-- Reused scan state for the merged player walk, keyed by buff key (assignments
-- only, like the target scan above).
local druid_player_found = {}
local druid_player_duration = {}
local druid_player_expiration = {}
local druid_player_scan_at

-- Forward declarations: the SoD rune probe and the guide's TTD sampler are defined
-- below with the code they belong to, but the per-frame updaters call them.
local sod_runes_present
local sample_target_time_to_die

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
--
-- The walk also answers the guide's Faerie Fire read (the target's Faerie Fire
-- debuff - the classic line's party buff rider): the same merged walk, one extra id
-- set, no bar. The id set is the running family's (druid_ff_ids): the Feral Fire id
-- and the plain Faerie Fire id of that client, because the TBC APL checks the plain
-- Faerie Fire aura while it casts the Feral one (wowsims/tbc-new
-- ui/specs/druid/feralcat/apls/default.apl.json i=2).
--
-- The Faerie Fire state is a TRI-STATE, because "the walk has not answered yet" and
-- "the walk answered: the debuff is not on the target" are different answers and the
-- second one is the only one that may prompt:
--   nil   the walk has not answered (unknown - the engine never prompts)
--   false the walk answered: the target carries no Faerie Fire debuff
--   true  the target carries the debuff (the remaining seconds ride the walk's own
--         duration / expiration)
local druid_ff_found = nil
local druid_ff_duration = nil
local druid_ff_expiration = nil

local function scan_target_druid_debuffs(now)
    local found = druid_debuff_found
    local duration = druid_debuff_duration
    local expiration = druid_debuff_expiration
    local ff_ids = druid_ff_ids[st.family] or druid_ff_ids.ERA
    local ff_pending = ff_ids ~= nil
    druid_ff_found = nil
    druid_ff_duration = nil
    druid_ff_expiration = nil
    local pending = #druid_debuff_defs + (ff_pending and 1 or 0)
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
                if ff_pending and not druid_ff_found
                    and type(spell_id) == "number" and ff_ids[spell_id] then
                    -- The guide's Faerie Fire read: the target carries the debuff.
                    druid_ff_found = true
                    druid_ff_duration = aura_duration
                    druid_ff_expiration = aura_expiration
                    ff_pending = false
                    pending = pending - 1
                end
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
    if druid_ff_found == nil then
        -- The walk completed without the debuff: the target carries no Faerie Fire
        -- (the "absent" answer, distinct from the "not answered yet" nil).
        druid_ff_found = false
    end
end

-- The Omen of Clarity's own window: the client has no internal-cooldown query, so
-- the proc buff (Clearcasting 16870) is the witness. The class remembers the last
-- proc it saw - when it started and how long the client's own buff lasted - so the
-- gather can tell "the Omen is on cooldown" (the proc is up) from "the Omen's
-- lockout window has passed" (the proc has been gone for at least as long as the
-- last proc lasted). See the gather for the sim citation and the UNCONFIRMED
-- assumption (the ICD and the proc buff share one window).
local druid_omen_last_start = nil
local druid_omen_last_duration = nil

-- The Omen of Clarity's own window: the client has no internal-cooldown query, so
-- the proc buff (Clearcasting 16870) is the witness. The class remembers the last
-- proc it saw - when it started and how long the client's own buff lasted - so the
-- gather can tell "the Omen is on cooldown" (the proc is up) from "the Omen's
-- lockout window has passed" (the proc has been gone for at least as long as the
-- last proc lasted). See the gather for the sim citation and the UNCONFIRMED
-- assumption (the ICD and the proc buff share one window).
local function druid_omen_track(aura_duration, aura_expiration)
    if type(aura_duration) ~= "number" or type(aura_expiration) ~= "number" then
        return
    end
    if aura_duration <= 0 then
        return
    end
    local start = aura_expiration - aura_duration
    if type(start) ~= "number" or start ~= start then
        return
    end
    if druid_omen_last_start == nil or start > druid_omen_last_start then
        druid_omen_last_start = start
        druid_omen_last_duration = aura_duration
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
                            if key == "omen" then
                                -- The Omen proc's own window (the witness for the
                                -- gather's omen_icd_ready read).
                                druid_omen_track(aura_duration, aura_expiration)
                            elseif key == "sr" then
                                -- The Roar's own expiry and the "was it ever up this
                                -- fight" latch (the upkeep drill's measures).
                                if type(aura_expiration) == "number"
                                    and (druid_sr_last_expiration == nil
                                        or aura_expiration > druid_sr_last_expiration) then
                                    druid_sr_last_expiration = aura_expiration
                                end
                                druid_sr_seen = true
                            end
                        end
                    end
                end
            end
        end
        index = index + 1
    end
    druid_player_scanned = true
end

-- The player-buff scan driver: runs on the per-frame hook while the Next Action
-- Guide is enabled, the Omen proc glow is on, or the D2 proc-aware tick sampler
-- needs a fresh Tiger's Fury edge (SoD-gated inside: every other family short-
-- circuits before the probe). Disabling clears the state, so the rotation label,
-- the glow and the TF edge can never ride a stale buff through a settings toggle.
local function update_druid_player_buffs(db, now)
    local tick_needs_tf = (db.show_druid_energy_tick ~= false
        or db.show_druid_shred_countdown == true)
        and st.family == "ERA" and sod_runes_present() == true
    if db.nextaction_enabled ~= true and db.show_druid_omen_glow ~= true
        and not tick_needs_tf then
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

-- D2 proc supplier (SoD-only): the Tiger's Fury buff's rising edge stamps a one-shot
-- proc grant consumed by the next energy sample, so a tick landing in the TF frame
-- still re-anchors (delta 80 - 60 = 20) and a capped TF partial (delta 20, no tick)
-- never forges one. The SoD gate (family ERA plus the rune probe) keeps runeless Era
-- and every other family on the legacy window: no honest TF amount exists there to
-- attribute. Cheap (no reads): the caller gates it on the tick sampler.
local function sample_druid_tf_proc(self)
    local tf_now = druid_player_found.tf == true
    local was = self.druid_tf_was_active
    self.druid_tf_was_active = tf_now
    if tf_now and was ~= true and st.family == "ERA" and sod_runes_present() == true then
        self.druid_proc_gain = DRUID_SOD_TF_PROC_GAIN
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
        self.druid_proc_gain = nil
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
                and druid_energy.is_tick_gain(current - self.druid_last_power,
                    self.druid_proc_gain) then
                self.druid_energy_anchor = now
            end
        end
        self.druid_last_power = current
        self.druid_last_power_type = power_type
        -- The proc grant is one-shot: whatever this sample decided, the next
        -- sample must not re-attribute it. A form flip already re-seats above,
        -- so a grant can never leak across forms either.
        self.druid_proc_gain = nil
    else
        -- Unreadable power (a secret value on a modern client): drop the baseline so the
        -- next readable sample re-seats instead of diffing against stale data.
        self.druid_last_power = nil
        self.druid_last_power_type = nil
        self.druid_proc_gain = nil
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

-- D1 time-to-die readout (competitor-gaps round 2: the "Time to Kill" WeakAura made
-- visible): the D4 EMA estimate as "TTD 8s" text. Any form (the estimate is about
-- the target, not the shapeshift); unknown (no target, unreadable or dead health)
-- hides through the pure formatter's nil, never a guessed number. The latching keeps
-- SetText off the per-frame path while the rounded value persists.
local function update_druid_ttd_readout(self, vf, now, enabled)
    local text = vf.druid_ttd_text
    if not text then
        return
    end
    if not enabled or not druid_energy then
        text:Hide()
        return
    end
    local label = druid_energy.format_time_to_die(sample_target_time_to_die(self, now))
    if label == nil then
        text:Hide()
        self.druid_ttd_shown = nil
        return
    end
    if self.druid_ttd_shown ~= label then
        self.druid_ttd_shown = label
        text:SetText(label)
    end
    text:Show()
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

    if not vf.druid_ttd_text then
        -- D1 TTD readout text (white, the countdown family): stacked below the
        -- countdown/badge line so it never overlaps them in cat form.
        local text = vf:CreateFontString(nil, "OVERLAY")
        text:SetPoint("TOP", vf, "BOTTOM", 0, -DRUID_TTD_STACK_OFFSET)
        text:SetJustifyH("CENTER")
        text:SetFont(get_tracker_font_path(self), DRUID_COUNTDOWN_TEXT_SIZE, "OUTLINE")
        text:SetTextColor(1, 1, 1, 0.95)
        text:Hide()
        vf.druid_ttd_text = text
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
    -- Runs after the guide tick above: the shared per-frame order is guide then
    -- HUD in all six class modules (deep-audit F8).
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
    -- Competitor-gaps round 2 toggle: nil-safe, nil = off (the options pass owns
    -- the widget; no default-visible change ships without an explicit gate).
    local show_ttd = db.show_druid_ttd_readout == true
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
    if show_tick or show_countdown then
        sample_druid_tf_proc(self)
    end
    update_druid_energy_tick(self, vf, db, now, show_tick, power_type, h, show_countdown)
    update_druid_form_label(self, vf, show_label, power_type)
    update_druid_gcd_tick(self, vf, now, show_gcd_tick, show_tick, power_type, h)
    update_druid_shred_countdown(self, vf, now, show_countdown, power_type)
    update_druid_pips(self, vf, show_pips, power_type)
    update_druid_maul_badge(self, vf, show_badge, now, power_type)
    update_druid_omen_glow(vf, show_omen, show_tick, power_type)
    update_druid_ttd_readout(self, vf, now, show_ttd)
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
-- SIX original slots (maul, mangle, rip, rake, bite, shred) plus Claw, the
-- Forever front-of-target builder, as the seventh (the frame contract caps
-- other classes at six-or-fewer by expectation, the paladin ships eight).
-- The Mangle / Rip / Rake slots carry a cooldown_key whose source is the module's own target
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
-- length is fed: no slot swipes off these buffs (the seven-slot decision in
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
-- Faerie Fire (Wrath ffNow Omen-fishing, Forever omenFish): no rank table
-- exists either, so the literal English name is the only query (UNCONFIRMED -
-- no offline source pins the Forever/SoD ranks; the Wrath ranks ride the same
-- name). RESERVED: the gather proves ready/cooldown, no rule reads them yet -
-- the Omen-fishing design files against them (see druid_guide.lua).
local guide_ff_query

local function resolve_cooldown_query(ids, literal)
    -- Name-vs-id: TBC never walks bare ids; the literal English name is the
    -- query (rank-agnostic there too). Every other family keeps the id walk
    -- with the literal fallback, byte-identical.
    if st.family == "TBC" then
        return literal
    end
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
local SOD_PROBE_NAMES = { MANGLE_NAME, SR_NAME }
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

sod_runes_present = function()
    if sod_probe_result == nil then
        if sod_probe_ids_known() or sod_probe_names_known() then
            sod_probe_result = true
        else
            sod_probe_result = false
        end
        -- The neutral publish follows THIS decision (the same latch the gather
        -- and the rotation family read): the moment the build is known, the
        -- publish is corrected - so the published set can never disagree with the
        -- rotation the engine grades against. The pick never consults the client,
        -- so it cannot move the probe's own latch.
        ST.DRUID.apply_neutral_build_pick(sod_probe_result == true)
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
-- Claw (the Forever front-of-target builder, sim feralcat id 9850): no rank
-- table exists (other ranks UNCONFIRMED, in-game to confirm), so the sim's
-- own id ships as the fallback and never re-points. No rule lights it yet
-- (no honest behind-target probe exists - can_shred stays nil, filed
-- follow-up); the slot is declared so the contract names it when the probe
-- lands.
local guide_slot_claw = { key = "claw", spell_id = 9850 }

-- Resolve the guide icons to the client's current ranks; called once from post_init,
-- before the shared frame builds its icons. A rank that does not resolve keeps the
-- fallback above (the Mangle fallback is the spec's shared 33878; Claw keeps
-- the sim's 9850 - no rank table exists to re-point it).
-- Name-vs-id: TBC slots carry the English NAME (GetSpellInfo takes names there,
-- so a bare id would leave the icon blank); every other family keeps the
-- rank-resolved id, byte-identical.
function ST.DRUID.resolve_guide_icons()
    if st.family == "TBC" then
        guide_slot_maul.spell_id = MAUL_NAME
        guide_slot_mangle.spell_id = MANGLE_NAME
        guide_slot_rip.spell_id = RIP_NAME
        guide_slot_rake.spell_id = RAKE_NAME
        guide_slot_bite.spell_id = BITE_NAME
        guide_slot_shred.spell_id = SHRED_NAME
        return
    end
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
sample_target_time_to_die = function(self, now)
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

-- Fight clock for the guide's fight-elapsed gates (Era/SoD 8 s, Forever 10 s
-- Rip gates): the api.get_time() stamp of the current fight's first in-combat
-- tick. Latched per fight, cleared on combat exit; out of combat reports nil
-- (the engine then takes its long-fight default). A clock that runs backwards
-- re-seats instead of reporting a negative elapsed.
local function ensure_druid_fight_stamp(self, now)
    if self.in_combat ~= true then
        self.druid_fight_start_at = nil
        return nil
    end
    if type(now) ~= "number" or now ~= now then
        return nil
    end
    local start = self.druid_fight_start_at
    if type(start) ~= "number" or start ~= start or now < start then
        self.druid_fight_start_at = now
        return 0
    end
    return now - start
end

-- The Wolfshead Helm probe (the reserved powershift plug-in point, BS-2). The
-- probe walks the client's whole equipped slot range (INVSLOT_FIRST_EQUIPPED ..
-- INVSLOT_LAST_EQUIPPED = 1..19 on every supported family), so reading it on
-- every gather costs ~380 item reads/s at the guide's 0.05 s tick - for an
-- input that no rule reads yet. The read is therefore THROTTLED: it runs at
-- most once every WOLFSHEAD_REFRESH_SECONDS and the cached answer is published
-- in between.
--
-- Freshness contract: a gear change becomes visible within
-- WOLFSHEAD_REFRESH_SECONDS of the gather that follows it; the published value
-- is always a real probe answer (true = worn, false = the read worked and no
-- equipped slot holds it, nil = unknown - never false), and an unknown read
-- stays unknown until the next refresh. The field is written on EVERY gather,
-- so a reused input table never keeps a stale answer.
local WOLFSHEAD_REFRESH_SECONDS = 1.0
local wolfshead_read_at = nil
local wolfshead_read_value = nil

-- The throttled Helm read: the cached answer while it is still fresh, a fresh
-- probe otherwise. A clock that cannot be read (or that runs backwards) re-reads
-- on every call - freshness wins over the saving.
local function read_wolfshead_equipped(now)
    if type(now) == "number" and now == now and type(wolfshead_read_at) == "number"
        and now >= wolfshead_read_at
        and (now - wolfshead_read_at) < WOLFSHEAD_REFRESH_SECONDS then
        return wolfshead_read_value
    end
    local value = api.is_item_equipped(8345)
    wolfshead_read_value = value
    if type(now) == "number" and now == now then
        wolfshead_read_at = now
    else
        wolfshead_read_at = nil
    end
    return value
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

    -- The mana pool (the APL utility layer's Innervate row reads it - the mana
    -- fraction): read BEFORE the form-specific pools, so the shipped power-read
    -- order (the rage/energy/combo reads) stays exactly as it was.
    local mana_value = api.UnitPower("player", 0)
    local mana_max_value = api.UnitPowerMax("player", 0)

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
    -- plug-in point). The basis is two probes and only one of them is proven:
    -- the Wolfshead Helm half is real - the sim checks
    -- HasItemEquipped(8345) (tbc-new feralcat.go) and 8345 is the
    -- wowhead-confirmed Wolfshead Helm, so the gather reads it
    -- through api.is_item_equipped (compat.lua) over the client's own equipped
    -- slot range; the Furor half is still unproven (bench/
    -- class_features_drills_2026-10-19.md DU-16) - main.lua's
    -- talent_positions covers WRATH only, so there is no verified TBC Furor
    -- tab/index and a GetTalentInfo read would be a guess. The SHIFT branches
    -- that read can_powershift were removed with their constants (see
    -- druid_guide.lua); the Helm read alone is not the basis, so do not
    -- re-add the call until Furor is proven.
    -- can_shred stays nil and no engine rule reads it (RESERVED plug-in
    -- point): position behind the target has no honest probe (the sim's
    -- CannotShredTarget option has no WoW API counterpart - IsSpellUsable
    -- answers usability, never facing), so the engine assumes Shred can
    -- land; the claw slot is declared above and its rule files its probe
    -- design as a follow-up.
    -- rip_min_cp rides the future RipCP option (db.guide_rip_min_cp, range
    -- 2-5 default 4 - the widget is OUT OF SCOPE, filed follow-up): nil until
    -- it ships, and T1 falls back to the frozen 4. The engine clamps 2-5, so
    -- the gather passes the raw option through (junk then degrades to 4
    -- there, never a guess here).
    -- latency: the world latency the sim's own Tiger's Fury line reads (sim
    -- wowsims/wotlk sim/druid/feral/rotation.go doTigersFury: the leeway is
    -- max(gcd_remaining, latency), plus 1 s on a proc). The reading is main.lua's
    -- RAW world latency - the same number the sim's Latency setting stands for; the
    -- addon's calibrated reading (raw x scale + offset) is a display-alignment
    -- correction and is deliberately NOT applied here. A client that has not
    -- measured yet reads nil and the line degrades to the GCD remainder alone.
    inputs.time_to_die = sample_target_time_to_die(self, now)
    inputs.target_short_lived = nil
    inputs.can_powershift = nil
    -- wolfshead_equipped: the Wolfshead Helm half of the powershift basis,
    -- published as a RESERVED plug-in point (no rule reads it yet - the
    -- Furor half is unproven, so the SHIFT branch stays removed).
    -- Tri-state, straight from the probe: true = equipped, false = the read
    -- worked and no equipped slot holds it, nil = unknown (the read is
    -- unavailable or secret). Unknown is never false: a false would be a
    -- guess about the player's gear and no rule may act on a guess. The id
    -- 8345 is the wowhead-confirmed Wolfshead Helm and the sim's own
    -- HasItemEquipped(8345) check.
    -- The read is throttled (WOLFSHEAD_REFRESH_SECONDS above): the probe walks
    -- all 19 equipped slots, so a per-gather read is ~380 item reads/s for an
    -- input nothing consumes yet. The cached answer is published between
    -- refreshes and the field is written on every call, so a reused table
    -- never keeps a stale answer.
    inputs.wolfshead_equipped = read_wolfshead_equipped(now)
    inputs.can_shred = nil
    inputs.rip_min_cp = db.guide_rip_min_cp
    inputs.latency = nil
    local latency_reading = self.latency
    if type(latency_reading) == "table" then
        local world_ms = latency_reading.world_ms
        if type(world_ms) == "number" and world_ms == world_ms then
            inputs.latency = world_ms / 1000
        end
    end
    -- Fight clock for the Era/SoD 8 s and Forever 10 s Rip gates (see
    -- ensure_druid_fight_stamp above): unknown (nil, out of combat) defaults
    -- to the long fight and Rips - never a withheld finisher on unknown.
    inputs.fight_elapsed = ensure_druid_fight_stamp(self, now)
    -- Tick phase for the filed trick/pooling windows (RESERVED: no rule reads
    -- it yet): the tracker's anchor when the sampler runs, else nil (unknown-
    -- hides). Deliberately reuses the existing anchor with no extra upkeep -
    -- a guide-only tick while the bars are off files its sampler follow-up.
    inputs.tick_remaining = nil
    if druid_energy then
        local anchor = self.druid_energy_anchor
        if type(anchor) == "number" and type(now) == "number" then
            inputs.tick_remaining = druid_energy.get_tick_remaining(anchor, now,
                druid_energy.ENERGY_TICK_SECONDS)
        end
    end

    -- The Maul queue state and the module's own shortfall flag.
    inputs.maul_queued = self.maul_queued and true or false
    inputs.insufficient_rage = self.insufficient_rage and true or false

    -- Maul's rage cost through the client's current rank (the rank cache makes this a
    -- lookup once resolved; a nil cost means the client cannot answer).
    -- Name-vs-id: TBC costs by NAME, Era by id.
    maul_current_id = resolve_rank(maul_ids, maul_current_id)
    local costs = maul_current_id and api.GetSpellPowerCost(spell_query(maul_current_id, MAUL_NAME))
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
        -- Name-vs-id: the TBC cost reads the NAME (rank-invariant there).
        -- Gated on the rank resolution (spell data present): unknown-hides
        -- skips the query entirely, so hide_spells never costs.
        guide_mangle_current_id = resolve_rank(druid_mangle_ids, guide_mangle_current_id)
        if guide_mangle_current_id then
            inputs.mangle_cost = rage_cost_of(api.GetSpellPowerCost(MANGLE_NAME))
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
    -- The Roar's own window (the upkeep drill's measures, not the guide's):
    --   sr_expired_seconds - how long the Roar has been down (the class's own
    --     tracker: the aura's last expiry against the clock). nil while the Roar
    --     is up or while it was never seen.
    --   sr_seen - true once the Roar was up this fight, false when the fight is on
    --     and the scan has looked and never saw it, nil when unknown.
    inputs.sr_expired_seconds = nil
    if druid_player_found.sr ~= true and type(druid_sr_last_expiration) == "number" then
        local since = now - druid_sr_last_expiration
        if type(since) == "number" and since == since and since >= 0 then
            inputs.sr_expired_seconds = since
        end
    end
    inputs.sr_seen = nil
    if druid_sr_seen == true then
        inputs.sr_seen = true
    elseif self.in_combat == true and druid_player_scanned == true then
        inputs.sr_seen = false
    end
    inputs.clearcast = druid_player_found.omen == true and true or nil
    -- The Omen of Clarity's internal cooldown (sim wowsims/forever
    -- sim/druid/feralcat/apl_sweep_test.go omenFish: the Faerie-Fire fish needs the
    -- Omen's ICD ready - the sim's auraIcdReady 16864). The client has no ICD
    -- query, so the Clearcasting proc buff (16870) is the witness: the proc is up
    -- -> the Omen is on cooldown (false); the proc has been gone for at least as
    -- long as the last proc lasted -> the lockout window has passed (true). The
    -- assumption that the Omen's ICD and its proc buff share one window is
    -- UNCONFIRMED in-client; before the first proc of the session the answer is nil
    -- (unknown) and the Forever omen-fish stays dormant - unknown-hides, never a
    -- guess.
    inputs.omen_icd_ready = nil
    if druid_player_found.omen == true then
        inputs.omen_icd_ready = false
    elseif type(druid_omen_last_start) == "number"
        and type(druid_omen_last_duration) == "number" then
        local omen_elapsed = now - druid_omen_last_start
        if type(omen_elapsed) == "number" and omen_elapsed == omen_elapsed
            and omen_elapsed >= druid_omen_last_duration then
            inputs.omen_icd_ready = true
        end
    end
    inputs.tf_active = druid_player_found.tf == true and true or nil
    inputs.tf_ready = nil
    inputs.tf_cd_remaining = nil
    inputs.berserk_ready = nil
    if guide_tf_query == nil then
        guide_tf_query = resolve_cooldown_query(druid_tf_ids, TF_NAME)
    end
    if type(api.GetSpellInfo(guide_tf_query)) == "string" then
        local tf_remaining = guide_cooldown_remaining(guide_tf_query, now)
        inputs.tf_cd_remaining = tf_remaining
        inputs.tf_ready = tf_remaining <= 0
    end
    if guide_berserk_query == nil then
        guide_berserk_query = resolve_cooldown_query(druid_berserk_ids, BERSERK_NAME)
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
    -- FOREVER APPENDIX); the <= 50 room check in the engine's F1 is
    -- APL-derived (SP_ENERGY_FOREVER). sp_ready is the knowledge
    -- gate (the GetSpellInfo name query is the only probe Forever exposes,
    -- since no spell id is published); the 50/40 values themselves are
    -- APL-backed. The mana affordability itself is not modelled.
    inputs.sp_ready = nil
    inputs.sp_cd_remaining = nil
    if inputs.family == "FOREVER" then
        if guide_sp_query == nil then
            guide_sp_query = SP_NAME
        end
        if type(api.GetSpellInfo(guide_sp_query)) == "string" then
            local sp_remaining = guide_cooldown_remaining(guide_sp_query, now)
            inputs.sp_cd_remaining = sp_remaining
            inputs.sp_ready = sp_remaining <= 0
        end
    end
    -- Faerie Fire Omen-fishing probe (Wrath ffNow, Forever omenFish):
    -- RESERVED, no rule reads these yet (the fishing design files against
    -- them). Name-based (no verified rank table), GCD-echo filtered like TF;
    -- unknown stays nil and any future rule stays dormant there.
    inputs.ff_ready = nil
    inputs.ff_cd_remaining = nil
    if guide_ff_query == nil then
        guide_ff_query = FF_NAME
    end
    if type(api.GetSpellInfo(guide_ff_query)) == "string" then
        local ff_remaining = guide_cooldown_remaining(guide_ff_query, now)
        inputs.ff_cd_remaining = ff_remaining
        inputs.ff_ready = ff_remaining <= 0
    end
    if inputs.family == "ERA" then
        inputs.sod_runes = sod_runes_present()
    else
        inputs.sod_runes = nil
    end

    -- The APL utility layer's reads (the rotation table's utility spine - the lines
    -- the wowsims APLs carry and the shipped rotation did not). Every field is
    -- written on every call: unknown stays nil and the engine treats "not true" as
    -- not sufficient, so an unreadable upkeep never prompts.
    --
    --   lop_active          the Leader of the Pack is up on the player (true), proven
    --                       absent (false - the player walk ran and found none) or
    --                       unknown (nil - the walk has not answered yet)
    --   ff_debuff_remaining the target's Faerie Fire debuff seconds (a number = the
    --                       debuff is up with that remaining; false = the walk
    --                       answered and the debuff is NOT on the target; nil =
    --                       the walk has not answered yet - unknown, and an
    --                       unknown never prompts)
    --   feral_ff_ready      the Feral Faerie Fire is off cooldown (true) or unknown
    --   innervate_ready     Innervate is off cooldown (true) or unknown
    --   elunes_light_ready  Elune's Light is off cooldown (true) or unknown
    --   mana_percent        the player's mana fraction (nil = unknown)
    --   has_target          the player has a target (true) or not (false)
    --
    -- The cooldown queries follow the class's own pattern: the family's id first
    -- (the id-resolving clients), the literal English name on the name-resolving one
    -- (TBC), and the knowledge gate (api.GetSpellInfo answering) in front of every
    -- read - a client that does not know the spell never reads a cooldown.
    inputs.lop_active = nil
    if druid_player_scanned == true then
        inputs.lop_active = druid_player_found.lop == true
    end
    -- The Leader of the Pack's knowledge gate: the Era APL's row casts it, so the
    -- spell has to be in the player's book. A client that answers false (no book,
    -- no probe, a passive talent the client does not list) never prompts it.
    inputs.lop_known = api.is_spell_known(17007) == true
    -- The Cat Form aura (the APL's form upkeep row watches it): the player's own
    -- aura walk answers "the Cat Form aura is up" (true), "proven absent" (false
    -- - the walk ran and found none) or "unknown" (nil - the walk has not
    -- answered yet). The same tri-state shape as the Leader of the Pack's read
    -- above: only a proven absence may prompt.
    inputs.cat_form_active = nil
    if druid_player_scanned == true then
        inputs.cat_form_active = druid_player_found.catform == true
    end
    -- The Feral-tree spec probe (the class's own "is this a feral druid?" read):
    -- the family's Feral-tree talent, probed through api.is_spell_known - true
    -- only when the player actually knows it (a resto or a balance druid never
    -- does), false otherwise (a client that cannot answer hides the line rather
    -- than guessing). nil when the family has no probe: the WotLK client, whose
    -- APL carries no Cat Form row at all.
    inputs.feral_spec = nil
    local feral_spec_id = druid_feral_spec_id[st.family]
    if feral_spec_id then
        inputs.feral_spec = api.is_spell_known(feral_spec_id) == true
    end
    inputs.ff_debuff_remaining = nil
    if druid_ff_found == true and druid_energy then
        inputs.ff_debuff_remaining = druid_energy.get_debuff_remaining(
            druid_ff_duration, druid_ff_expiration, now, DRUID_FF_FALLBACK_DURATION)
    elseif druid_ff_found == false then
        -- The walk answered: the target carries no Faerie Fire debuff. The false is
        -- the "absent" answer - nil stays the "not answered yet" unknown.
        inputs.ff_debuff_remaining = false
    end
    inputs.feral_ff_ready = nil
    inputs.innervate_ready = nil
    inputs.elunes_light_ready = nil
    local utility_queries = druid_utility_queries
    local feral_ff_id = druid_feral_ff_id[st.family]
    if feral_ff_id then
        local query = utility_queries.feral_ff
        if query == nil then
            -- The Feral Faerie Fire's OWN id, never the whole debuff set: the plain
            -- Faerie Fire is a different spell with a different cooldown (the Feral
            -- one is 6 s, the plain one is a plain GCD cast), so the cooldown read
            -- must answer the spell the APL casts.
            query = resolve_cooldown_query({ [feral_ff_id] = true }, FERAL_FF_NAME)
            utility_queries.feral_ff = query
        end
        if type(api.GetSpellInfo(query)) == "string" then
            inputs.feral_ff_ready = guide_cooldown_remaining(query, now) <= 0
        end
    end
    local innervate_query = utility_queries.innervate
    if innervate_query == nil then
        innervate_query = resolve_cooldown_query(druid_innervate_ids, INNERVATE_NAME)
        utility_queries.innervate = innervate_query
    end
    if type(api.GetSpellInfo(innervate_query)) == "string" then
        inputs.innervate_ready = guide_cooldown_remaining(innervate_query, now) <= 0
    end
    if st.family == "FOREVER" then
        local elune_query = utility_queries.elunes_light
        if elune_query == nil then
            elune_query = ELUNES_LIGHT_NAME
            utility_queries.elunes_light = elune_query
        end
        if type(api.GetSpellInfo(elune_query)) == "string" then
            inputs.elunes_light_ready = guide_cooldown_remaining(elune_query, now) <= 0
        end
    end
    inputs.mana_percent = nil
    if type(mana_value) == "number" and type(mana_max_value) == "number"
        and mana_max_value > 0 then
        inputs.mana_percent = mana_value / mana_max_value
    end
    -- The target's existence, the HUD's own guard (classes/druid.lua's hud_out_of_range
    -- reads UnitExists the same way): the Faerie Fire upkeep needs a target to land on.
    inputs.has_target = (UnitExists and UnitExists("target")) and true or false

    -- The refresh thresholds from the options (0-10 s, defaults 4).
    inputs.rip_refresh = db.guide_rip_refresh or 4
    inputs.rake_refresh = db.guide_rake_refresh or 4
    return inputs
end

ST.DRUID.guide = {
    slots = { guide_slot_maul, guide_slot_mangle, guide_slot_rip, guide_slot_rake,
        guide_slot_bite, guide_slot_shred, guide_slot_claw },

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
-- The slot set mirrors the Next Action Guide's rotational slots
-- (ST.DRUID.guide above: the class's top-parse abilities, Claw included),
-- plus the D2 Tiger's Fury / Berserk cooldown slots and
-- the two trinket slots the HUD serves itself. Claw's rule still files its
-- probe (no behind-target probe exists); the HUD slot mirrors the guide slot
-- display-only and hides unless hud_show_claw reads exactly true (nil = off;
-- options own the widget, filed follow-up). The descriptor and provider contracts
-- are frozen in hud.lua's header comment; the "trinket" slots need no provider entry.
--
-- Rank notes: the guide's own slot ids ship as the icon fallback (the spell art is
-- rank-invariant), while the provider reads cooldowns by the client's own localized
-- name (hud_slot_name), so whatever rank the player knows is what is counted - the
-- paladin's cooldown_spell-free convention from classes/paladin.lua. Maul (6807),
-- Rip (1079) and Rake (1822) are the rank-1 ids of the module's own rank tables;
-- Mangle (33878), Ferocious Bite (22568), Shred (5221) and Claw (9850) mirror
-- the guide slots and are UNCONFIRMED: none of them is covered by a rank table
-- in this module, so confirm with GetSpellInfo on the target client before release.
-- D2: Tiger's Fury ships the Era/TBC rank 9845 as its fallback icon id (the rank
-- table above re-points it at post_init), Berserk ships 50334 (the WotLK ability,
-- verify_bank §2). Both slots hide themselves where the client's spell data carries
-- no such spell (the liveness gates in get_hud_state): TF is name-resolved (the
-- rank-dependent ids make any single id wrong - the correction), Berserk also rides
-- the SoD rune basis on the ERA token (Era-base has no Berserk). Unlike the seven
-- rotational slots, TF and Berserk carry real cooldowns (30 s / 3 min), so they never
-- borrow the GCD swipe (the paladin judgement/wings rule).
-- The seven rotational slots have no cooldown of their own on the classic line, so they
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
    { key = "claw", title = "Claw", kind = "spell", spell = 9850 },
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
    -- Name-vs-id: TBC icon slots carry the NAME (a bare id leaves the icon
    -- blank there); every other family keeps the rank-resolved id.
    if st.family == "TBC" then
        hud_slot_tf.spell = TF_NAME
        hud_slot_berserk.spell = BERSERK_NAME
        return
    end
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
    -- Name-vs-id: TBC never probes bare ids; the literal name is the probe.
    if st.family == "TBC" then
        return type(api.GetSpellInfo(literal)) == "string"
    end
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
        if spell_data_resolves(druid_tf_ids, TF_NAME) then
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
        if spell_data_resolves(druid_berserk_ids, BERSERK_NAME)
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
-- Name-vs-id: TBC answers the literal English name (never a bare id); Era
-- resolves the slot id. Nil-safe: an unanswered spell stays nil (unknown-hides).
local hud_slot_names = {}
local HUD_SLOT_TBC_NAMES = {
    maul = MAUL_NAME,
    mangle = MANGLE_NAME,
    rip = RIP_NAME,
    rake = RAKE_NAME,
    bite = BITE_NAME,
    shred = SHRED_NAME,
    claw = CLAW_NAME,
    tf = TF_NAME,
    berserk = BERSERK_NAME,
}

local function hud_slot_name(slot)
    local name = hud_slot_names[slot.key]
    if not name then
        if st.family == "TBC" then
            name = HUD_SLOT_TBC_NAMES[slot.key]
                or (slot.spell and api.GetSpellInfo(slot.spell))
                or nil
        else
            name = slot.spell and api.GetSpellInfo(slot.spell) or nil
        end
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
    claw = 0,
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
    -- Claw display mirror (no rule lights it yet): no default-visible change -
    -- hides unless hud_show_claw reads exactly true (nil = off; the HUD treats
    -- nil as wanted, so this provider-level hide is the gate; options own the
    -- widget, filed follow-up). Same dormancy as the guide slot (declared dark).
    if slot.key == "claw" then
        local claw_db = self:get_class_table()
        if type(claw_db) ~= "table" or claw_db.hud_show_claw ~= true then
            s.hidden = true
            return s
        end
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
-- Practice: the druid seam on the shared practice session
--=========================================================================================
-- The session runs how it always has: the options Practice toggle starts it and the
-- panel icons cast the simulated spells (practice_ui.lua, class-agnostic). This seam
-- only keeps that flow druid-safe and routes the druid drill:
--   * practice_sync reports no seal state (the druid has none to mirror), so the
--     shared bridge never stamps paladin seal fields onto a druid session;
--     practice_ui.sync_to_addon calls it through the DRUID branch there.
--   * the scenario wrappers below drive the class's OWN drill
--     (druid_powershift_rework) through the shared scoring pipeline, the same
--     entry points any caller (the toggle-started session, an options tab) uses.
-- Every entry degrades to nil/0 when the practice modules are absent (a flavor
-- without them), never an error; nothing here shows without the explicit toggle
-- (opt-in, no default-visible change).
function ST.DRUID.practice_sync(self)
    return 0
end

-- The harness drill this class practices (practice.lua registry): the key when the
-- module is loaded and carries the spec, nil otherwise (unknown-hides).
--
-- The key stays the RETIRED built-in ("druid_powershift") on purpose: it is the
-- routing key the shared engine reads (the panel's drill route and the engine's
-- supersession rule H.SUPERSEDED_DRILLS), and the built-in stays registered for
-- backward compatibility. The class's own session never starts it - the drill it
-- runs is the class's own (practice_drill_key below).
function ST.DRUID.practice_scenario_key()
    local pr = st.practice
    if pr and pr.harness and pr.harness.get_scenario
        and pr.harness.get_scenario("druid_powershift") then
        return "druid_powershift"
    end
    return nil
end

-- The drill this class's session runs: the class's OWN drill - the shift rule,
-- re-sourced (the sim's trigger). The retired built-in ("druid_powershift") stays
-- registered for backward compatibility and the engine delegates its grading to
-- this drill (practice.lua H.SUPERSEDED_DRILLS), so the old 20-energy truth never
-- grades a player attempt.
ST.DRUID.PRACTICE_DRILL_KEY = "druid_powershift_rework"

-- The class's own drill key, or nil when the class publishes no such drill
-- (unknown-hides: the session refuses rather than falling back to the retired
-- built-in).
function ST.DRUID.practice_drill_key()
    local key = ST.DRUID.PRACTICE_DRILL_KEY
    if type(key) ~= "string" or key == "" then
        return nil
    end
    local drills = ST.DRUID.practice_drills
    if type(drills) ~= "table" then
        return nil
    end
    for i = 1, #drills do
        local entry = drills[i]
        if type(entry) == "table" and entry.key == key
            and type(entry.grade) == "function" then
            return key
        end
    end
    return nil
end

-- Grade the session's own drill attempt: the class's own grade function with the
-- ctx the shared engine hands the drills (the session's state, the clock and the
-- action). Nil when the drill cannot judge the attempt (unknown-hides, never a
-- guessed grade).
local function druid_grade_drill(session, now, last_action)
    local pr = st.practice
    local H = pr and pr.harness
    if not (session and H and H.drill_context and H.practice_drill_grade) then
        return nil
    end
    local key = session.key
    if type(key) ~= "string" or key == "" then
        return nil
    end
    local ctx = H.drill_context(session.state, now, last_action)
    return H.practice_drill_grade(ST.DRUID, key, ST, ctx)
end

-- The shift's own effect on the shared pool: the harness's energy model (the
-- Furor-5/5 refund and the shift counter). The retired rule's GRADE is not used
-- here - the class's own drill graded the attempt.
local function druid_apply_shift(session)
    local pr = st.practice
    local H = pr and pr.harness
    if not (session and H) then
        return
    end
    local state = session.state
    if type(state) ~= "table" then
        return
    end
    local refund = (H.POWERSHIFT_DEFAULTS and H.POWERSHIFT_DEFAULTS.shift_refund) or 40
    local max = state.energy_max or 100
    local energy = (state.energy or 0) + refund
    if energy > max then
        energy = max
    end
    state.energy = energy
    state.shifts = (state.shifts or 0) + 1
end

-- The class's own drill session: the session this class starts IS the class's own
-- drill (one skill, one truth). The session is the harness's own shape - the score
-- accumulator, the lifecycle and the drill's state - and the drill's TRUTH is the
-- class's own grade function; the retired built-in's model never grades here.
local function druid_drill_session(now, opts)
    local pr = st.practice
    local H = pr and pr.harness
    if not (H and H.new_score and H.new_energy_state and H.energy_update) then
        return nil
    end
    local key = ST.DRUID.practice_drill_key()
    if key == nil then
        return nil
    end
    return {
        key = key,
        spec = {
            key = key,
            class = "DRUID",
            begin = function(session)
                -- Re-baseline the regen clock without draining the pool: a re-begin
                -- after the session ended must not grant phantom regen across the gap.
                session.state.last_update_at = nil
            end,
            event = function(session, event_now, event_key)
                local grade = druid_grade_drill(session, event_now, event_key)
                if grade ~= nil then
                    druid_apply_shift(session)
                end
                return grade
            end,
            tick = function(session, tick_now, tick_elapsed, out)
                out.energy = H.energy_update(session.state, tick_now)
            end,
        },
        -- The pool is the harness's shared energy primitive (the same state the
        -- retired built-in used - the model, never its grade).
        state = H.new_energy_state(opts),
        score = H.new_score(),
        windows = {},
        started_at = now or 0,
        active = false,
    }
end

-- Start a drill run: the class's OWN drill session, begun at `now`.
-- Returns the session, or nil when the drill is unavailable.
function ST.DRUID.new_practice_session(now, opts)
    local pr = st.practice
    local H = pr and pr.harness
    if not (H and H.begin_session) then
        return nil
    end
    local session = druid_drill_session(now, opts)
    if session == nil then
        return nil
    end
    H.begin_session(session, now, opts)
    return session
end

-- Run one drill tick through the harness (drives the energy regen clock).
function ST.DRUID.tick_practice_session(session, now, elapsed, out)
    local pr = st.practice
    if not (session and pr and pr.harness and pr.harness.tick_session) then
        return out
    end
    return pr.harness.tick_session(session, now, elapsed, out)
end

-- Grade one powershift at `now`: the class's OWN drill grades the pooled energy
-- (the sim's shift trigger), the shift is counted and the attempt is recorded on
-- the session score. Returns the grade (S..F) or nil when the shift cannot be
-- scored (unknown energy reads never guess).
function ST.DRUID.practice_shift(session, now)
    local pr = st.practice
    if not (session and pr and pr.harness and pr.harness.scenario_event
        and pr.harness.record_session_attempt) then
        return nil
    end
    local grade = pr.harness.scenario_event(session, "shift", now)
    if grade ~= nil then
        pr.harness.record_session_attempt(session, grade)
    end
    return grade
end

-- The shared score summary for a drill run (attempts, score, best grade), or nil
-- without a session. Read-only: never allocates a session by itself.
function ST.DRUID.practice_summary(session)
    local pr = st.practice
    if not (session and pr and pr.harness and pr.harness.session_summary) then
        return nil
    end
    return pr.harness.session_summary(session)
end

-- End a drill run (stops the harness session). Safe on an ended or nil session.
function ST.DRUID.end_practice_session(session, now)
    local pr = st.practice
    if not (session and pr and pr.harness and pr.harness.end_session) then
        return false
    end
    return pr.harness.end_session(session, now)
end

--=========================================================================================
-- Practice: the rotation table, the scenario step and the druid drills
--=========================================================================================
-- The shared practice engine looks a class's practice surface up by player_class
-- (ST.DRUID.<field>). Three fields, one contract (bench/class_features_drills_2026-10-19.md
-- §2.5: the target drill set (C) and the target scenario (D)):
--   * practice_rotation      - the family's priority order, one entry per sim priority
--                              slot, each entry citing the sim file it comes from.
--   * practice_scenario_step - the expected action for the current state:
--                              { action = "<spell key>", reason = "<short text>" }, or
--                              nil when the state is undecidable (the engine grades
--                              "unknown"). It reuses the shipped guide engine, so the
--                              scenario can never disagree with the Next Action Guide.
--   * practice_drills        - the focused drills (key / label / grade); each grade
--                              answers one attempt from the same ctx.
--
-- THE CTX (one writer; the scenario step and every drill read it):
--   ctx = {
--     now         = <number>,       -- seconds, the api.get_time() domain
--     last_action = "<spell key>",   -- what the player just did
--     resources   = { ... },         -- the guide's frozen input names
--     cooldowns   = { ... },         -- the guide's frozen input names
--     state       = <table>,         -- optional: the engine's session ledger
--   }
-- The resource/cooldown vocabulary IS the guide's own frozen input set
-- (druid_guide.lua's header): energy, combo_points, rage, form_index, maul_cost,
-- mangle_cost, rip_remaining, rake_remaining, mangle_remaining, sr_remaining,
-- time_to_die, target_short_lived, fight_elapsed, tick_remaining, clearcast,
-- tf_ready, tf_cd_remaining, berserk_ready, ff_ready, ff_cd_remaining, sp_ready,
-- sp_cd_remaining, omen_icd_ready, family, sod_runes, ... A value may sit at the top
-- level of ctx or inside ctx.resources / ctx.cooldowns; the reader takes the top level
-- first, then resources, then cooldowns. Every reader is nil-safe: a missing value
-- reads nil (unknown) and never guesses.
--
-- THE SPELL KEYS are the guide's own action keys (the seven slot keys: maul, mangle,
-- rip, rake, bite, shred, claw) plus the hold-overlay keys (tigers_fury, berserk,
-- savage_roar, faerie_fire, shifting_power, ...) - the guide's SPELL-NAMING hold_text
-- values mapped to a key, so a hold and an action are the same shape for the engine.
-- The guide's ONE press-nothing hold ("RIDE") is the exception: it names no key (see
-- ST.DRUID.PRACTICE_HOLD_PRESSES_NOTHING below).
--
-- FAMILY GATING: the guide is inert on RETAIL (druid_guide.lua's short-circuit), so
-- the scenario step answers nil there and the scenario is never offered (the audit's
-- §4.6 rule). Every drill without a sim basis on the running family answers nil too
-- - unknown-hides, never a guess.
--=========================================================================================

-- The guide's hold-overlay texts mapped to the spell key the engine presses. A text
-- that is not in the table is UNKNOWN (M2, re-audit 2026-10-20): the class never
-- guesses a key for it. The guide only ever writes the nine texts below - its tenth
-- hold text, "RIDE", is the press-nothing hold and is listed in
-- ST.DRUID.PRACTICE_HOLD_PRESSES_NOTHING instead.
--
-- The druid's guide has NO general hold concept (the operator ruling HU-8: a hold is
-- a decision to CAST NOTHING, and the druid's guide names the spell to press). Nine
-- of the guide's ten hold texts are a CALL: the guide has no slot for the spell, so
-- the hold overlay names it and the practice layer presses that key.
--
-- THE ONE EXCEPTION is "RIDE" - the bear chain's queued Maul (the guide rides the
-- queue the player already placed). RIDE means PRESS NOTHING, so it never becomes an
-- action key: a synthetic "ride" button would score points for idling (the engine's
-- contract forbids that - a correct hold records no attempt) and would bank a false
-- mis-pick in the priority drill for every real pick. The step states it as a hold
-- instead: a cast during it is an illegal cast, doing nothing during it is correct
-- but worth no points.
ST.DRUID.PRACTICE_HOLD_KEYS = {
    ["TIGER'S FURY"] = "tigers_fury",
    ["BERSERK"] = "berserk",
    ["SAVAGE ROAR"] = "savage_roar",
    ["FAERIE FIRE"] = "faerie_fire",
    ["SHIFTING POWER"] = "shifting_power",
    -- the APL utility layer's holds (the rotation table's utility spine)
    ["LEADER OF THE PACK"] = "leader_of_the_pack",
    ["INNERVATE"] = "innervate",
    ["ELUNE'S LIGHT"] = "elunes_light",
    -- the form upkeep's hold (the rotation table's cat_form row)
    ["CAT FORM"] = "cat_form",
}

-- The guide's PRESS-NOTHING holds: the hold texts that mean "press no key". The
-- guide writes exactly one today ("RIDE", the bear chain's queued Maul); a second
-- one would have to be listed here before it could ever be graded as a hold.
ST.DRUID.PRACTICE_HOLD_PRESSES_NOTHING = {
    ["RIDE"] = true,
}

-- One ctx value: the top level first, then ctx.resources, then ctx.cooldowns. The
-- engine's cooldown table drops the "_remaining" suffix (the gathered "sr_remaining"
-- arrives as "sr"), so a lookup also tries the stripped base name. A missing value
-- is nil (unknown) - never a guess.
local function druid_ctx_value(ctx, name)
    if type(ctx) ~= "table" then
        return nil
    end
    local value = ctx[name]
    if value ~= nil then
        return value
    end
    local resources = ctx.resources
    if type(resources) == "table" then
        value = resources[name]
        if value ~= nil then
            return value
        end
    end
    local cooldowns = ctx.cooldowns
    if type(cooldowns) == "table" then
        value = cooldowns[name]
        if value ~= nil then
            return value
        end
        local base = name:match("^(.-)_remaining$")
        if base then
            value = cooldowns[base]
            if value ~= nil then
                return value
            end
        end
    end
    return nil
end

-- The rotation family token: the sim whose priority the table below mirrors.
-- "ERA" is the runeless Classic Era sim; "SOD" is the Season of Discovery sim (the
-- ERA client token plus the rune basis); the rest match compat.lua's family names.
local function druid_rotation_family(ctx)
    local family = druid_ctx_value(ctx, "family")
    if type(family) ~= "string" then
        family = st.family
    end
    if family == "ERA" then
        local runes = druid_ctx_value(ctx, "sod_runes")
        if runes == nil then
            runes = sod_runes_present()
        end
        if runes == true then
            return "SOD"
        end
    end
    return family
end

-- The rotation family for the ctx: the ctx's own family (plus the rune basis) when
-- it names one, else the running client's (through the public helper, so the class's
-- own rotation slice and the engine's view never drift).
local function druid_ctx_rotation_family(ctx)
    if type(ctx) == "table" and type(ctx.family) == "string" then
        return druid_rotation_family(ctx)
    end
    return ST.DRUID.practice_rotation_family()
end

-- The rotation table: the sim priority order per family, one entry per priority slot
-- (an action may appear twice when the sim reaches it from two branches). Every entry
-- cites the sim file it comes from; the sim files are the ones the druid rotation
-- audit fetched (bench/druid_rotation_audit_2026-10-19.md §0, the raw URLs) and that
-- bench/wrath_leftovers_2026-10-19.md §3 confirms for the Wrath values.
--
-- The order below is the engine's compiled rule matrix (druid_guide.lua's five family
-- appendices), which is the sim priority order as the addon implements it. Two rows
-- carry a note where the shipped engine and the sim's ACTIVE path differ (the SoD
-- Rake upkeep and the SoD Mangle upkeep: the sim's active SoD path has no Rake
-- branch - the doc-derived upkeep is marked UNCONFIRMED against it).
--
-- Every row also carries the APL's own id for that line (`ids`, the per-family map)
-- and HU-13's two flags (`live` = the line's read exists, `engine` = the frozen
-- engine has an arm for it). The last block of the table is the APL's UTILITY
-- SPINE: the upkeep and cooldown lines the wowsims APLs carry and the sim's own
-- rotation.go does not (bench/rotation_gap_vs_apl_2026-10-20.md section 4.3).
ST.DRUID.practice_rotation = {
    -- ---- ERA (Classic Era 1.15.9, runeless) - the sim's doRotation ----------------
    { family = "ERA", action = "shred", label = "Shred", rule = "E0",
      note = "Omen of Clarity proc - a free Shred",
      source = "sim wowsims/classic sim/druid/feral/rotation.go: doRotation, isClearcast -> Shred - the Era APL has no clearcast row (its i=4 is the Ferocious Bite row, 31018 r4); the id is the client's Shred r5 (9830)",
      ids = { ERA = 9830 }, live = true, engine = true },
    { family = "ERA", action = "rip", label = "Rip", rule = "E1",
      note = "5 combo points, Rip expired, the fight older than 8 s",
      source = "sim wowsims/classic sim/druid/feral/rotation.go: canRip (5 CP needs fight > 8 s) - the Era APL carries NO Rip row (its rows are the Faerie Fire 17392/13494, the Ferocious Bite 31018, the Shred 9830, the Claw 9850, the Innervate 29166 and the Cat Form 768); the id is the client's Rip r6 (9896, the 1.15 spell table's rank subtext)",
      ids = { ERA = 9896 }, live = true, engine = true },
    { family = "ERA", action = "shred", label = "Shred", rule = "E2",
      note = "the builder fallthrough (the Shred trick window)",
      source = "sim wowsims/classic sim/druid/feral/rotation.go: PrimaryBuilder = Shred (setupRotation) - wowsims/classic ui/feral_druid/apls/feral.apl.json i=5 (9830 r5: the builder Shred)",
      ids = { ERA = 9830 }, live = true, engine = true },
    -- ---- SOD (Season of Discovery - the ERA token plus the rune basis) ------------
    { family = "SOD", action = "tigers_fury", label = "Tiger's Fury", rule = "S1",
      note = "at or under 40 energy (King of the Jungle grants +60)",
      source = "sim wowsims/sod sim/druid/tigers_fury.go: registerTigersFurySpellKotJ (+60 energy) - wowsims/sod ui/feral_druid/apls/phase_5.apl.json i=6 and i=7 (417045: the Tiger's Fury rune) - wowsims/sod sim/druid/tigers_fury.go:65",
      ids = { SOD = 417045 }, live = true, engine = true },
    { family = "SOD", action = "berserk", label = "Berserk", rule = "S2",
      note = "right after Tiger's Fury burned",
      source = "sim wowsims/sod sim/druid/feral/rotation.go: the Berserk branch after Tiger's Fury - wowsims/sod ui/feral_druid/apls/phase_5.apl.json i=5 (417141: the Berserk rune) - wowsims/sod sim/druid/berserk.go:17",
      ids = { SOD = 417141 }, live = true, engine = true },
    { family = "SOD", action = "savage_roar", label = "Savage Roar", rule = "S3",
      note = "upkeep: 1+ combo points and the Roar expired",
      source = "sim wowsims/sod sim/druid/feral/rotation.go: SR first branch (!hasRoar) - wowsims/sod ui/feral_druid/apls/phase_5.apl.json i=1 (407988: the Roar upkeep) - wowsims/sod sim/druid/savage_roar.go:20",
      ids = { SOD = 407988 }, live = true, engine = true },
    { family = "SOD", action = "savage_roar", label = "Savage Roar", rule = "S3b",
      note = "the cover-to-end clip: one fresh Roar covers the fight's end",
      source = "sim wowsims/sod sim/druid/feral/rotation.go: clipRoar - the SoD APL has no clip row (its i=1 is the plain Roar upkeep, 407988); the clip is the sim's own rule",
      ids = { SOD = 407988 }, live = true, engine = true },
    { family = "SOD", action = "shred", label = "Shred", rule = "S4",
      note = "Omen of Clarity proc - a free Shred",
      source = "sim wowsims/sod sim/druid/feral/rotation.go: isClearcast -> Shred - wowsims/sod ui/feral_druid/apls/phase_5.apl.json i=10 (9830 r5 under the Clearcasting condition)",
      ids = { SOD = 9830 }, live = true, engine = true },
    { family = "SOD", action = "rip", label = "Rip", rule = "S5",
      note = "5 combo points, Rip expired, the fight older than 8 s",
      source = "sim wowsims/sod sim/druid/feral/rotation.go: canRip (5 CP 8 s fight gate) - wowsims/sod ui/feral_druid/apls/phase_5.apl.json i=11 (9896 r6: the Rip)",
      ids = { SOD = 9896 }, live = true, engine = true },
    { family = "SOD", action = "mangle", label = "Mangle", rule = "S6",
      note = "the Mangle debuff is absent",
      source = "sim wowsims/sod sim/druid/feral/rotation.go: PrimaryBuilder = Mangle when talented - wowsims/sod ui/feral_druid/apls/phase_5.apl.json i=9, i=13 and i=16 (409828: the Mangle) - wowsims/sod sim/druid/mangle.go:89",
      ids = { SOD = 409828 }, live = true, engine = true },
    { family = "SOD", action = "rake", label = "Rake", rule = "S7",
      note = "the Rake debuff expired - UNCONFIRMED against the sim's active path, which has no Rake branch",
      source = "sim wowsims/sod sim/druid/feral/rotation.go: the active doRotation has no Rake branch - the upkeep is the doc-derived rule (UNCONFIRMED against the sim) - wowsims/sod ui/feral_druid/apls/phase_5.apl.json i=12 (9904 r4: the Rake)",
      ids = { SOD = 9904 }, live = true, engine = true },
    { family = "SOD", action = "shred", label = "Shred", rule = "S8",
      note = "the builder fallthrough",
      source = "sim wowsims/sod sim/druid/feral/rotation.go: PrimaryBuilder - wowsims/sod ui/feral_druid/apls/phase_5.apl.json i=15 (9830 r5: the builder Shred)",
      ids = { SOD = 9830 }, live = true, engine = true },
    -- ---- TBC (2.5.6) - the NerdEgghead feralcat port ------------------------------
    { family = "TBC", action = "rip", label = "Rip", rule = "T1",
      note = "4+ combo points (the sim's RipMinComboPoints) and Rip expired",
      source = "sim wowsims/tbc-new sim/druid/feralcat/rotation.go: ripNow = cp >= RipCP && !ripDebuff - wowsims/tbc-new ui/specs/druid/feralcat/apls/default.apl.json i=7, i=8, i=12 and i=18 (27008 r7: the Rip)",
      ids = { TBC = 27008 }, live = true, engine = true },
    { family = "TBC", action = "mangle", label = "Mangle", rule = "T2",
      note = "the Mangle debuff is absent and the energy covers the cost",
      source = "sim wowsims/tbc-new sim/druid/feralcat/feralcat.go: CurrentMangleCatCost (40, 35 with 2pc-T6) - wowsims/tbc-new ui/specs/druid/feralcat/apls/default.apl.json i=4, i=9, i=10, i=14, i=15, i=20, i=22 and i=23 (33983 r3: the Mangle) - wowsims/tbc-new sim/druid/spell_data_auto_gen.go: the MangleCat table (33876 r1, 33983 r3)",
      ids = { TBC = 33983 }, live = true, engine = true },
    { family = "TBC", action = "bite", label = "Ferocious Bite", rule = "T3",
      note = "5 combo points on a target dying inside 10 s",
      source = "sim wowsims/tbc-new sim/druid/feralcat/rotation.go: biteAtEnd (RipEndThresh 10 s) - wowsims/tbc-new ui/specs/druid/feralcat/apls/default.apl.json i=11 and i=17 (24248 r6: the Ferocious Bite)",
      ids = { TBC = 24248 }, live = true, engine = true },
    { family = "TBC", action = "rip", label = "Rip", rule = "T4",
      note = "5 combo points on a long fight - the finisher is always Rip",
      source = "sim wowsims/tbc-new sim/druid/feralcat/rotation.go: ripNow - wowsims/tbc-new ui/specs/druid/feralcat/apls/default.apl.json i=7, i=8, i=12 and i=18 (27008 r7: the Rip)",
      ids = { TBC = 27008 }, live = true, engine = true },
    { family = "TBC", action = "shred", label = "Shred", rule = "T5",
      note = "the builder, 42 energy (the 2.5.6 spell data)",
      source = "sim wowsims/tbc-new sim/druid/feralcat/rotation.go: the >= 22 energy Shred/Mangle ladder - wowsims/tbc-new ui/specs/druid/feralcat/apls/default.apl.json i=5, i=16, i=19 and i=21 (27002 r7: the Shred)",
      ids = { TBC = 27002 }, live = true, engine = true },
    -- ---- WRATH (3.80.x) - the wowsims/wotlk feral rotation ------------------------
    { family = "WRATH", action = "tigers_fury", label = "Tiger's Fury", rule = "W1",
      note = "under the dynamic 40 - 10 * leeway line",
      source = "sim wowsims/wotlk sim/druid/feral/rotation.go: doTigersFury (leeway = max(gcdLeft, latency)) - the WotLK APL carries NO spell rows (wowsims/wotlk ui/feral_druid/apls/default.apl.json: autocastOtherCooldowns, 50334 Berserk IF false, the sim's catOptimalRotationAction); the id is the WotLK sim's (wowsims/wotlk sim/druid/tigers_fury.go:10)",
      ids = { WRATH = 50213 }, live = true, engine = true },
    { family = "WRATH", action = "faerie_fire", label = "Faerie Fire", rule = "W1b",
      note = "fishing the Omen of Clarity below 87 energy",
      source = "sim wowsims/wotlk sim/druid/feral/rotation.go: ffNow (ffThresh 87, 15 in Berserk) - the WotLK APL carries no spell rows; the id is the WotLK sim's Feral Faerie Fire r1 (wowsims/wotlk sim/druid/faerie_fire.go:22)",
      ids = { WRATH = 16857 }, live = true, engine = true },
    { family = "WRATH", action = "berserk", label = "Berserk", rule = "W2",
      note = "Tiger's Fury has been on cooldown for 15 s or more",
      source = "sim wowsims/wotlk sim/druid/feral/rotation.go: berserkNow + berserk.go (50334, 15 s, 3 min) - the WotLK APL's i=1 (50334 - but the row's own condition is false, so it never fires mid-fight; the APL's pre-pull row is the prepull table's) - wowsims/wotlk sim/druid/berserk.go:15",
      ids = { WRATH = 50334 }, live = true, engine = true },
    { family = "WRATH", action = "savage_roar", label = "Savage Roar", rule = "W3",
      note = "upkeep: 1+ combo points and the Roar expired",
      source = "sim wowsims/wotlk sim/druid/feral/rotation.go: roarNow - the WotLK APL carries no spell rows; the id is the WotLK sim's (wowsims/wotlk sim/druid/savage_roar.go:16)",
      ids = { WRATH = 52610 }, live = true, engine = true },
    { family = "WRATH", action = "shred", label = "Shred", rule = "W4",
      note = "Omen of Clarity proc - a free Shred",
      source = "sim wowsims/wotlk sim/druid/feral/rotation.go: the clearcast branch - the WotLK APL carries no spell rows; the id is the WotLK sim's (wowsims/wotlk sim/druid/shred.go:19)",
      ids = { WRATH = 48572 }, live = true, engine = true },
    { family = "WRATH", action = "rip", label = "Rip", rule = "W5",
      note = "5 combo points and Rip expired",
      source = "sim wowsims/wotlk sim/druid/feral/rotation.go: ripNow - the WotLK APL carries no spell rows; the id is the WotLK sim's (wowsims/wotlk sim/druid/rip.go:23)",
      ids = { WRATH = 49800 }, live = true, engine = true },
    { family = "WRATH", action = "mangle", label = "Mangle", rule = "W6",
      note = "the Mangle debuff is absent (above Rake: its 30 % bleed lifts every tick)",
      source = "sim wowsims/wotlk sim/druid/feral/rotation.go: mangleNow (before rakeNow) - the WotLK APL carries no spell rows; the id is the WotLK sim's cat Mangle (wowsims/wotlk sim/druid/mangle.go:20; the bear Mangle is 48566)",
      ids = { WRATH = 48564 }, live = true, engine = true },
    { family = "WRATH", action = "rake", label = "Rake", rule = "W7",
      note = "the Rake debuff expired",
      source = "sim wowsims/wotlk sim/druid/feral/rotation.go: rakeNow - the WotLK APL carries no spell rows; the id is the WotLK sim's (wowsims/wotlk sim/druid/rake.go:13)",
      ids = { WRATH = 48574 }, live = true, engine = true },
    { family = "WRATH", action = "bite", label = "Ferocious Bite", rule = "W8",
      note = "5 combo points with Rip and Roar both at 4 s or more, inside the last 10 s",
      source = "sim wowsims/wotlk sim/druid/feral/rotation.go: canBite (BiteTime 4, endThresh 10) - the WotLK APL carries no spell rows; the id is the WotLK sim's (wowsims/wotlk sim/druid/ferocious_bite.go:13)",
      ids = { WRATH = 48577 }, live = true, engine = true },
    { family = "WRATH", action = "shred", label = "Shred", rule = "W9",
      note = "the builder fallthrough",
      source = "sim wowsims/wotlk sim/druid/feral/rotation.go: the builder branch - the WotLK APL carries no spell rows; the id is the WotLK sim's (wowsims/wotlk sim/druid/shred.go:19)",
      ids = { WRATH = 48572 }, live = true, engine = true },
    -- ---- FOREVER (1.60.x) - the bestCatAPL sweep -----------------------------------
    { family = "FOREVER", action = "shifting_power", label = "Shifting Power", rule = "F1",
      note = "with room for the 40-energy gain (ceiling 50, 40 on a proc)",
      source = "sim wowsims/forever sim/druid/feralcat/apl_sweep_test.go: catAPL underCap - wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json i=8 (1322605: the Shifting Power) - wowsims/forever sim/druid/spell_data_auto_gen.go: the ShiftingPower talent",
      ids = { FOREVER = 1322605 }, live = true, engine = true },
    { family = "FOREVER", action = "berserk", label = "Berserk", rule = "F1b",
      note = "with Rip up and no proc",
      source = "sim wowsims/forever sim/druid/feralcat/rotation_test.go: Berserk with a builder - wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json i=2 (the Berserk group: 417141) - wowsims/forever sim/druid/spell_data_auto_gen.go: the Berserk talent",
      ids = { FOREVER = 417141 }, live = true, engine = true },
    { family = "FOREVER", action = "shred", label = "Shred", rule = "F2",
      note = "Omen of Clarity proc - a free Shred",
      source = "sim wowsims/forever sim/druid/feralcat/apl_sweep_test.go: ccShred - wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json i=4 (9830: the clearcasting Shred)",
      ids = { FOREVER = 9830 }, live = true, engine = true },
    { family = "FOREVER", action = "rip", label = "Rip", rule = "F3",
      note = "5 combo points, Rip expired, the fight at least 10 s old",
      source = "sim wowsims/forever sim/druid/feralcat/apl_sweep_test.go: ripNow - wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json i=6 (the Bleeds group: 9896 Rip) - wowsims/forever sim/druid/spell_data_auto_gen.go: the Rip ladder",
      ids = { FOREVER = 9896 }, live = true, engine = true },
    { family = "FOREVER", action = "rake", label = "Rake", rule = "F4",
      note = "the Rake debuff expired",
      source = "sim wowsims/forever sim/druid/feralcat/apl_sweep_test.go: rakeNow - wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json i=6 (the Bleeds group: 9904 Rake) - wowsims/forever sim/druid/spell_data_auto_gen.go: the Rake ladder",
      ids = { FOREVER = 9904 }, live = true, engine = true },
    -- REMOVED (was F5, the Mangle row - HU-14, closed 2026-10-20): the Forever
    -- client has NO Mangle spell at all, so the row named a spell the client
    -- cannot cast and the engine's F5 branch answered "mangle" on every tick
    -- (mangle_remaining is always nil there), which made the F6 (the Bite) and
    -- F7 (the builder) branches unreachable. The evidence: the Forever sim
    -- carries no Mangle table and no per-ability file
    -- (wowsims/forever sim/druid/spell_data_auto_gen.go - no Mangle entry; the
    -- FaerieFire ladder is 770/778/9749/9907 and the LeaderOfThePack ladder is
    -- 17007), the Forever APL's own builders are 9830 Shred and 9850 Claw
    -- (wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json i=9, the
    -- Builders group) and the APL has no Mangle row anywhere. The APL's slot
    -- where the row stood is empty, so the chain now falls through to the Bite
    -- (F6) and the builder (F7) - exactly the APL's own order. The builder's
    -- Claw half is the utility spine's claw row below (RESERVED: its read does
    -- not exist yet), so the engine answers the APL's Shred.
    { family = "FOREVER", action = "bite", label = "Ferocious Bite", rule = "F6a/F6b",
      note = "5 combo points in the execute window, or 3+ in the last 3 s",
      source = "sim wowsims/forever sim/druid/feralcat/apl_sweep_test.go: biteEnd / biteLow; rotation_test.go: Bites only at the end - wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json i=7 (22829: the Ferocious Bite) - wowsims/forever sim/druid/spell_data_auto_gen.go: the FerociousBite ladder",
      ids = { FOREVER = 22829 }, live = true, engine = true },
    { family = "FOREVER", action = "faerie_fire", label = "Faerie Fire", rule = "F6c",
      note = "fishing the Omen of Clarity",
      source = "sim wowsims/forever sim/druid/feralcat/apl_sweep_test.go: omenFish - wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json i=11 (9907: the Faerie Fire for the Omen) - wowsims/forever sim/druid/spell_data_auto_gen.go: the FaerieFire ladder",
      ids = { FOREVER = 9907 }, live = true, engine = true },
    { family = "FOREVER", action = "shred", label = "Shred", rule = "F7",
      note = "the builder fallthrough (the 2 s / 1 s pooling horizons are not built)",
      source = "sim wowsims/forever sim/druid/feralcat/apl_sweep_test.go: the builder branch - wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json i=9 (the Builders group: 9830 Shred, 9850 Claw)",
      ids = { FOREVER = 9830 }, live = true, engine = true },
    -- ---- BEAR (every family) - the bear chain, shared by every family --------------
    { family = "BEAR", action = "ride", label = "Ride the queued Maul", rule = "1/B1",
      note = "a queued Maul already rides the next swing",
      source = "sim wowsims/forever sim/druid/feralcat/mechanics_test.go: TestCatQueuesMaulOntoTheBearSwing - no fetched APL carries a bear row (the BEAR slice is the class's own bear chain; bench/rotation_gap_vs_apl_2026-10-20.md section 4.4)",
      ids = { }, live = true, engine = true },
    { family = "BEAR", action = "maul", label = "Maul", rule = "2/B2",
      note = "a proven-affordable Maul",
      source = "sim wowsims/sod sim/druid/feral/maul.go: the Maul queue - no fetched APL carries a bear row (bench/rotation_gap_vs_apl_2026-10-20.md section 4.4)",
      ids = { }, live = true, engine = true },
    { family = "BEAR", action = "mangle", label = "Mangle", rule = "3/B3",
      note = "the bear fallback (the only rotational slot a bear can name)",
      source = "sim wowsims/sod sim/druid/feral/maul.go: the bear rotation (no cat-rotation sim defines a bear DPS priority - the audit's section 6) - no fetched APL carries a bear row (bench/rotation_gap_vs_apl_2026-10-20.md section 4.4)",
      ids = { }, live = true, engine = true },
    -- ---- the APL's UTILITY SPINE (the lines the shipped rotation did not carry) ----
    -- The wowsims APLs carry an upkeep/cooldown layer the sim's own rotation.go does
    -- not: the form upkeep, the party buff rider, the mana tool and the burst
    -- cooldowns. bench/rotation_gap_vs_apl_2026-10-20.md section 4.3 lists them as
    -- the druid's missing lines; every id and index below was re-read out of the
    -- fetched APL files on 2026-10-20 (the same sources the table above cites).
    --
    -- EVERY entry of the spine carries the same shape:
    --   action      the class's own action key (the practice panel's button key)
    --   label       the English name the panel shows
    --   rule        the engine rule's id (the reason's rule suffix)
    --   note        what the line is for, in one line
    --   families    the family tokens whose APL plays the line (the family gate)
    --   ids         the spell id per family (the id-resolving clients; the TBC
    --               client resolves by NAME - tbc_name carries that name)
    --   tbc_name    the client's English name (the TBC path's key)
    --   source      the APL file and the row's index, plus the sim's own citation
    --   live        true when the line's READ exists in the shipped tree today AND
    --               the line can be evaluated from it; false when it needs a read
    --               that does not exist yet (or cannot be evaluated at all) - the
    --               entry then names that exact read in `needs`
    --   engine      false when the frozen guide engine has no arm for the line
    --   needs       (a live = false line) the exact read the line is waiting for
    --   gate        (an armed line) what the engine's arm proves before it prompts
    --
    -- The two flags are the orchestrator's ruling (HU-13, 2026-10-20), applied
    -- cross-class: `live` is the read (and the line's ability to be evaluated
    -- from it), `engine` is the arm. They come apart here.
    { action = "cat_form", label = "Cat Form", rule = "U-CF",
      note = "the form upkeep: the cat rotation wants the cat form",
      families = { ERA = true, SOD = true, TBC = true, FOREVER = true },
      ids = { ERA = 768, SOD = 768, TBC = 768, FOREVER = 768 },
      tbc_name = "Cat Form",
      source = "wowsims/classic ui/feral_druid/apls/feral.apl.json i=14 (768: cast it when the Cat Form aura is not active); wowsims/sod ui/feral_druid/apls/phase_5.apl.json i=0 (768: the same condition, the APL's own top row); wowsims/tbc-new ui/specs/druid/feralcat/apls/default.apl.json i=6 (the Powershifting group's Cat Form member) and its pre-pull row (-10 s); wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json i=1 (768) - wowsims/classic sim/druid/forms.go:88 (the Cat Form aura). The WotLK APL carries NO Cat Form row (bench/rotation_gap_vs_apl_2026-10-20.md section 4.4)",
      live = true, engine = true,
      gate = "the engine arm (druid_guide.lua's U-CF line) wants all three: feral_spec == true (the class's own Feral-tree probe - api.is_spell_known on the family's Feral-tree talent, so a resto or a balance druid is never asked to shift), cat_form_active == false (the player's own aura walk proves the Cat Form aura is absent - the APL's own condition) and a form the cat rotation uses but the other chains do not own (0 = the humanoid form, 4 = the travel form). Unknown hides: an unproven spec, an unanswered aura walk or an unreadable form never prompts. KNOWN LIMIT: the clients this addon targets expose no cat-vs-bear spec read (the talent trees are readable on WotLK only - main.lua's talent_positions table), so a Feral-tree BEAR tank out of the bear form can still be told to shift; the guide's bear chain owns the bear form itself (form 1), so the call can only show outside it",
    },
    { action = "leader_of_the_pack", label = "Leader of the Pack", rule = "U-LOP",
      note = "the party crit buff, cast early in the fight (it lasts three minutes)",
      families = { ERA = true },
      ids = { ERA = 17007 },
      tbc_name = "Leader of the Pack",
      source = "wowsims/classic ui/feral_druid/apls/feral.apl.json i=1 (the row casts 13494 - but the 1.15 client names 13494 'Haste' and puts it in NO druid skill line, so the APL row is dead as written; the line it means is the client's own Leader of the Pack, 17007: the 1.15 spell table carries the Leader of the Pack text under 17007 and the spell sits in the Feral Combat skill line - wow.export Spell.csv + SkillLineAbility.csv). The SoD APL has no Leader of the Pack row (its i=0 is the Cat Form row)",
      live = true, engine = true,
    },
    { action = "faerie_fire", label = "Faerie Fire (Feral)", rule = "U-FF",
      note = "the party buff rider: the Feral Faerie Fire debuff on the target",
      families = { ERA = true, TBC = true },
      ids = { ERA = 17392, TBC = 27011 },
      tbc_name = "Faerie Fire (Feral)",
      source = "wowsims/classic ui/feral_druid/apls/feral.apl.json i=0 and i=8 (17392 r4: the refresh when the target's Faerie Fire has 14 s or less left - the debuff lasts about 16 s); wowsims/tbc-new ui/specs/druid/feralcat/apls/default.apl.json i=2 (27011 r5: cast it when the target's Faerie Fire debuff is inactive - the APL checks the plain Faerie Fire aura 26993 r5 while it casts the Feral one). wowsims/classic sim/druid/faerie_fire.go:11,28 (9907 the plain Faerie Fire, 17392 the Feral one); wowsims/tbc-new sim/druid/faerie_fire.go:8,42 (the Feral spell applies the plain Faerie Fire aura)",
      live = true, engine = true,
    },
    { action = "claw", label = "Claw", rule = "U-CLAW",
      note = "the builder when the Shred cannot land",
      families = { ERA = true, FOREVER = true },
      ids = { ERA = 9850, FOREVER = 9850 },
      tbc_name = "Claw",
      source = "wowsims/classic ui/feral_druid/apls/feral.apl.json i=6 (9850 r5: the Claw builder, cast when the energy tick is more than 1.02 s away); wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json i=5 and i=9 (the Builders group: 9830 Shred, 9850 Claw - the Claw when the Shred cannot be cast) - wowsims/classic sim/druid/claw.go:14 (9850) and wowsims/forever sim/druid/spell_data_auto_gen.go (the Claw ladder: 1082, 3029, 5201, 9849, 9850). NOTE: 9850 is the Claw r5 on Era AND on Forever AND on TBC (wowsims/tbc-new sim/druid/spell_data_auto_gen.go: the Claw table) - bench/rotation_gap_vs_apl_2026-10-20.md section 4.3 calls it Mangle on TBC/Forever; it is not (the Mangle (Cat) ids are 33876/33983 on TBC and the Forever client has no Mangle at all)",
      live = false, engine = false,
      needs = "the READ that decides 'the Shred cannot land': the guide's can_shred input is RESERVED (nil) - the sim's CannotShredTarget has no WoW API counterpart (the position behind the target), and api.IsSpellUsable answers usability, never facing (classes/druid.lua's gather note). The Forever APL's own row needs 'NOT spellCanCast(9830)', which the client could answer through api.IsSpellUsable (compat.lua:277), but the class never reads it and the classic IsSpellUsable's resource semantics for an energy-cost spell in cat form are in-client UNCONFIRMED. Without that read an arm would either never fire or fire on a guess. The line stays RESERVED and both flags say so: the row is the APL's own builder half (the Forever APL's i=5 and i=9), and the engine's Forever chain answers the APL's Shred (F7) in that slot since HU-14 - the Claw's own read does not exist yet",
    },
    { action = "innervate", label = "Innervate", rule = "U-INN",
      note = "the mana tool, cast while the mana is short",
      families = { ERA = true, SOD = true, FOREVER = true },
      ids = { ERA = 29166, SOD = 29166, FOREVER = 29166 },
      tbc_name = "Innervate",
      source = "wowsims/classic ui/feral_druid/apls/feral.apl.json i=13 (29166: the mana row - the mana at 40 % or less, outside the cat form, with 20 s of fight left); wowsims/sod ui/feral_druid/apls/phase_5.apl.json i=4 (29166: the mana row); wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json i=10 (29166: the 'Mana short' row) - wowsims/classic sim/druid/innervate.go:16 (29166), wowsims/sod sim/druid/innervate.go:16, wowsims/forever sim/druid/spell_data_auto_gen.go: the Innervate ladder. The TBC APL carries no Innervate row",
      live = true, engine = true,
    },
    { action = "elunes_light", label = "Elune's Light", rule = "U-EL",
      note = "the Forever cooldown (the APL's own Elune's Light row)",
      families = { FOREVER = true },
      ids = { FOREVER = 1259799 },
      tbc_name = "Elune's Light",
      source = "wowsims/forever ui/specs/druid/feralcat/apls/default.apl.json i=3 (the Cooldowns group, member 0: 1259799, cast under the APL's own 'Elune's Light now' variable). The id is the APL's own; the NAME is the APL's variable name - no other source names it (the id is in no wowsims spell table and warcraftdb has no spell 1259799), so the name is UNCONFIRMED outside the APL and the gather's knowledge gate (api.GetSpellInfo answering the literal name) keeps the line dormant until the client's own spell data answers it",
      live = true, engine = true,
    },
    { action = "bloodlust", label = "Bloodlust", rule = "U-BL",
      note = "the raid's haste cooldown, cast at the APL's Bloodlust Time",
      families = { TBC = true },
      ids = { TBC = 2825 },
      tbc_name = "Bloodlust",
      source = "wowsims/tbc-new ui/specs/druid/feralcat/apls/default.apl.json i=0 (2825 r1: cast when the fight time reaches the APL's 'Bloodlust Time' variable - the shipped value is 5 s) - wowsims/tbc-new sim/shaman/bloodlust.go:11 (2825). No other family's druid APL carries a Bloodlust row",
      live = false, engine = false,
      needs = "the line CANNOT be evaluated, so both flags say so. (1) The spell: 2825 is the SHAMAN's Bloodlust (wowsims/tbc-new sim/shaman/bloodlust.go:11) - the TBC druid sim registers no Bloodlust spell at all (no entry in sim/druid/spell_data_auto_gen.go, no sim/druid/bloodlust.go), so the APL's row is dead as written for a druid, exactly the shape of the Era APL's dead 13494 row. The cooldown probe (api.GetSpellCooldown on 2825 - compat.lua:229) exists but reads a spell the druid can never cast, so it proves nothing. (2) The GATE: the row fires at the APL's 'Bloodlust Time' VARIABLE (a sim user setting, 5 s in the shipped APL), and the addon has no equivalent option (option_tables.lua is out of this lane's scope) and no way to know the raid's Bloodlust plan - the practice panel's own Bloodlust button is the manual path. An arm here would ask a druid to cast a spell the druid does not have, at a fight time the class cannot prove",
    },
}

-- The family's rotation slice: the entries whose family matches, in sim priority
-- order. The bear chain is a separate slice (family "BEAR") because it is shared by
-- every family; the engine asks for both when it wants the whole rotation.
--
-- Two shapes ride the table: the sim priority rows carry the single `family` of the
-- slice they belong to, and the APL utility spine carries the cross-class `families`
-- set (the same convention the paladin and the hunter use). A row joins the slice
-- when either names the wanted family.
function ST.DRUID.practice_rotation_for(family)
    local out = {}
    local want = family
    if type(want) ~= "string" then
        want = druid_rotation_family()
    end
    for i = 1, #ST.DRUID.practice_rotation do
        local entry = ST.DRUID.practice_rotation[i]
        local families = entry.families
        if entry.family == want
            or (type(families) == "table" and families[want] == true) then
            out[#out + 1] = entry
        end
    end
    return out
end

-- The pre-pull table (HU-12, the orchestrator's ruling: the APL's PRE-PULL rows never
-- join the combat rotation - they live in their own table, the shape
-- ST.HUNTER.PRACTICE_PREPULLS already uses). `at` is the offset relative to the pull
-- in seconds (negative = before the pull).
--
-- NO CONSUMER (stated here so nothing implies coverage that does not exist):
-- this table is CITATIONS ONLY. The class ships no pre-pull drill - only the
-- warrior, the hunter and the rogue have one - and no other module reads this
-- table, so nothing grades a pre-pull row today. It records the APLs' own
-- pre-pull rows (the ids and the offsets) for the lane that builds the drill,
-- and it must never join the combat rotation: the rotation table above is the
-- rotation, and the family's slice (practice_rotation_for) never names a
-- pre-pull row.
ST.DRUID.PRACTICE_PREPULLS = {
    ERA = {
        {
            action = "faerie_fire", label = "Faerie Fire (Feral)", spell = 17392, at = -1.0,
            source = "wowsims/classic ui/feral_druid/apls/feral.apl.json (prepullActions: Faerie Fire (Feral) 17392 r4 at -1.0 s)",
        },
        {
            action = "tigers_fury", label = "Tiger's Fury", spell = 9846, at = -3.5,
            source = "wowsims/classic ui/feral_druid/apls/feral.apl.json (prepullActions: Tiger's Fury 9846 r4 at -3.5 s) - wowsims/classic sim/druid/tigers_fury.go:10 (the level-60 rank is 9846)",
        },
    },
    SOD = {
        {
            action = "savage_roar", label = "Savage Roar", spell = 407988, at = -8,
            source = "wowsims/sod ui/feral_druid/apls/phase_5.apl.json (prepullActions: activateAura 407988 at -8 s) - wowsims/sod sim/druid/savage_roar.go:20",
        },
    },
    TBC = {
        {
            action = "cat_form", label = "Cat Form", spell = 768, at = -10,
            source = "wowsims/tbc-new ui/specs/druid/feralcat/apls/default.apl.json (prepullActions: Cat Form 768 at -10 s)",
        },
    },
    WRATH = {
        {
            action = "berserk", label = "Berserk", spell = 50334, at = -1,
            source = "wowsims/wotlk ui/feral_druid/apls/default.apl.json (prepullActions: Berserk 50334 at -1 s) - wowsims/wotlk sim/druid/berserk.go:15",
        },
    },
}

-- The rotation family the running client uses (the sim the table above mirrors for
-- it). "SOD" on the ERA token with the rune basis, else compat.lua's family.
function ST.DRUID.practice_rotation_family()
    return druid_rotation_family()
end

-- The guide's frozen input names, copied out of the ctx into the engine's own
-- vocabulary. A name the ctx does not carry stays nil (unknown) and the engine's
-- "not a number" / "not true" handling takes over - a drill never guesses. The last
-- three are the drill-side extras the class gathers (the guide does not read them).
local DRUID_GUIDE_INPUT_NAMES = {
    "speed", "swing_remaining", "gcd_remaining", "form_index", "rage", "energy",
    "combo_points", "maul_queued", "maul_cost", "insufficient_rage",
    "rip_remaining", "rake_remaining", "mangle_remaining", "rip_refresh",
    "rake_refresh", "family", "sr_remaining", "tf_ready", "tf_cd_remaining",
    "tf_active", "berserk_ready", "clearcast", "sod_runes", "time_to_die",
    "target_short_lived", "can_powershift", "wolfshead_equipped", "mangle_cost",
    "sp_ready", "sp_cd_remaining", "fight_elapsed", "tick_remaining", "latency",
    "ff_ready", "ff_cd_remaining", "omen_icd_ready", "can_shred", "rip_min_cp",
    -- the APL utility layer's reads (the rotation table's utility spine)
    "lop_active", "lop_known", "ff_debuff_remaining", "feral_ff_ready",
    "innervate_ready", "elunes_light_ready", "mana_percent", "has_target",
    -- the form upkeep's reads (the Cat Form row): the class's own spec probe and
    -- the player's Cat Form aura
    "feral_spec", "cat_form_active",
    -- drill-side extras (the gather writes them; the guide ignores them)
    "sr_expired_seconds", "sr_seen", "shred_cost", "regen_per_second", "energy_max",
}

-- The state the scenario step and the drills read: the class's OWN gathered inputs
-- with the engine's ctx layered on top. The engine's ctx carries the resource values
-- and the remaining cooldowns it can see; everything else (the Omen proc, the
-- execute clock, the cooldowns' ready flags) the class gathers itself - the
-- engine's own rule: "a class that needs more gathers it itself".
local DRUID_STATE_GATHERED = {}
local DRUID_STATE_INPUTS = {}
local function druid_state_inputs(self, ctx, out)
    local inputs = out or DRUID_STATE_INPUTS
    local gathered = nil
    if type(self) == "table" and type(ST.DRUID.gather_guide_inputs) == "function" then
        -- pcall-guarded: a half-loaded class module never throws out of a step.
        local ok, result = pcall(ST.DRUID.gather_guide_inputs, self, DRUID_STATE_GATHERED)
        if ok and type(result) == "table" then
            gathered = result
        end
    end
    for i = 1, #DRUID_GUIDE_INPUT_NAMES do
        local name = DRUID_GUIDE_INPUT_NAMES[i]
        -- The value is copied as it is: a proven false (a cooldown the client
        -- answered) must survive the merge - the SoD S2 branch reads tf_ready ==
        -- false, and "false or nil" would silently drop it.
        local value = nil
        if gathered ~= nil then
            value = gathered[name]
        end
        inputs[name] = value
    end
    -- The engine's ctx wins: it is the caller's own view of the state.
    for i = 1, #DRUID_GUIDE_INPUT_NAMES do
        local name = DRUID_GUIDE_INPUT_NAMES[i]
        local value = druid_ctx_value(ctx, name)
        if value ~= nil then
            inputs[name] = value
        end
    end
    -- The family: the ctx may name it (a simulated family); else the running client.
    if type(inputs.family) ~= "string" then
        inputs.family = st.family
    end
    if inputs.family == "SOD" then
        -- The engine may name the rotation family; the guide's vocabulary is the
        -- compat family plus the rune basis (druid_guide.lua's SOD APPENDIX).
        inputs.family = "ERA"
        if inputs.sod_runes == nil then
            inputs.sod_runes = true
        end
    end
    if inputs.sod_runes == nil and inputs.family == "ERA" then
        local runes = sod_runes_present()
        inputs.sod_runes = runes == true or nil
    end
    return inputs
end

-- The engine's expected action for a state: the shipped guide engine's own answer
-- (the same decision the Next Action Guide shows), so a drill can never teach a
-- different rotation than the guide. Returns the action key and, for a hold, the
-- hold text. nil = undecidable (no action and no hold). One reused output table:
-- the guide overwrites every frozen field on each call.
--
-- The guide's two kinds of hold are NOT the same shape:
--   * a SPELL-NAMING hold (nine of the guide's ten hold texts) names the spell to
--     press: it answers that spell's key, so the step is a decision to CAST.
--   * a PRESS-NOTHING hold ("RIDE", the bear chain's queued Maul) answers NO
--     action and the hold text: the caller states it as a hold (the engine grades
--     a cast during it as an illegal cast and a correct hold as worth no points).
local DRUID_EXPECTED_OUT = {}
local function druid_expected(inputs)
    local guide = st.druid_guide
    if not (guide and guide.evaluate) then
        return nil, nil
    end
    local out = DRUID_EXPECTED_OUT
    guide.evaluate(inputs, out)
    if out.hold == true and type(out.hold_text) == "string" then
        local presses_nothing = ST.DRUID.PRACTICE_HOLD_PRESSES_NOTHING
        if type(presses_nothing) == "table" and presses_nothing[out.hold_text] then
            -- A press-nothing hold: the player presses NO key.
            return nil, out.hold_text
        end
        local keys = ST.DRUID.PRACTICE_HOLD_KEYS
        local key = nil
        if type(keys) == "table" then
            key = keys[out.hold_text]
        end
        if key == nil then
            -- M2 (re-audit 2026-10-20): a hold text in NEITHER published table is
            -- UNKNOWN, never a guessed key. The old slug fallback turned a future
            -- hold text into a synthetic action - the deep audit's H1 shape (the
            -- class invents a button the player can only press dishonestly). The
            -- closed-vocabulary pin (tests/druid_guide_state.lua) is the tripwire:
            -- a new hold text fails it before it can ever reach here.
            return nil, nil
        end
        return key, out.hold_text
    end
    if type(out.action) == "string" then
        return out.action, nil
    end
    return nil, nil
end

-- A short, honest reason for the call (the engine shows it beside the expected
-- action). Every number in a reason comes from the state the engine itself wrote.
local function druid_action_reason(action, hold_text, inputs)
    if hold_text then
        return hold_text
    end
    local cp = inputs.combo_points
    if action == "shred" then
        if inputs.clearcast == true then
            return "Omen of Clarity proc - a free Shred"
        end
        return "the builder - no upkeep due"
    elseif action == "rip" then
        if type(cp) == "number" then
            return tostring(cp) .. " combo points, Rip expired"
        end
        return "Rip expired"
    elseif action == "mangle" then
        local cost = inputs.mangle_cost
        if type(cost) == "number" then
            return "Mangle absent - " .. tostring(cost) .. " energy"
        end
        return "Mangle absent"
    elseif action == "rake" then
        return "Rake expired"
    elseif action == "bite" then
        local ttd = inputs.time_to_die
        if type(ttd) == "number" then
            return "the execute window - " .. tostring(math.floor(ttd)) .. " s left"
        end
        return "the execute window"
    elseif action == "maul" then
        local rage = inputs.rage
        if type(rage) == "number" then
            return "rage " .. tostring(math.floor(rage))
        end
        return "a proven-affordable Maul"
    elseif action == "claw" then
        return "Shred cannot land - Claw"
    end
    return action
end

-- The scenario step: the action the rotation wants for the current state, or nil when
-- the state is undecidable (the engine grades "unknown"). It reuses the shipped guide
-- engine, so the scenario and the Next Action Guide can never disagree.
--
-- A PRESS-NOTHING hold (the guide's own verdict: the player presses NO key) is
-- stated as a hold, not as an action (the operator ruling HU-8: a hold is a decision
-- to cast nothing): the engine grades a cast during it as an illegal cast (F) and a
-- correct hold as correct but worth NO points (a player could otherwise farm them by
-- idling). The druid's other nine guide holds name the spell to press and stay
-- actions.
function ST.DRUID.practice_scenario_step(self, ctx)
    local inputs = druid_state_inputs(self, ctx)
    local action, hold_text = druid_expected(inputs)
    if action == nil then
        -- No action: either a press-nothing hold (the guide says: press nothing) or a
        -- state the guide cannot decide. The hold is a decision and is stated as one;
        -- the undecidable state stays unknown (no attempt, never a wrong grade).
        if hold_text ~= nil then
            return { action = nil, hold = true, reason = hold_text }
        end
        return nil
    end
    local reason = druid_action_reason(action, hold_text, inputs)
    -- The rule id from the rotation table (the sim's priority slot this call sits
    -- in), so the reason names the engine rule and not just the action.
    local family = druid_ctx_rotation_family(ctx)
    local slice = ST.DRUID.practice_rotation_for(family)
    for i = 1, #slice do
        if slice[i].action == action then
            if type(slice[i].rule) == "string" and slice[i].rule ~= "" then
                reason = reason .. " (" .. slice[i].rule .. ")"
            end
            break
        end
    end
    return { action = action, reason = reason }
end

-- The drills' frozen constants. A sim value carries its source; a band the drill
-- policy owns is marked [DESIGN] (addon policy, not a sim number).
--   DRUID_BITE_EXECUTE_SECONDS = 10  the sim's execute window
--       (sim wowsims/tbc-new sim/druid/feralcat/rotation.go: RipEndThresh 10 s;
--       sim wowsims/wotlk sim/druid/feral/rotation.go: endThresh 10 s).
--   DRUID_BITE_MIN_SECONDS = 4      the sim's BiteTime: the Rip and the Savage Roar
--       must both survive the rebuild after the bite (sim wowsims/wotlk
--       sim/druid/feral/rotation.go: canBite).
--   DRUID_BITE_NEAR_SECONDS = 20    [DESIGN] the "nearly over" line that separates a
--       Bite just outside the execute window (C) from a mid-fight Bite (D).
--   DRUID_SHIFT_ENERGY_TBC = 10     the sim's fixed shift line: below 10 energy the
--       TBC cat shifts (sim wowsims/tbc-new sim/druid/feralcat/rotation.go).
--   DRUID_ENERGY_MAX = 100          the cat energy cap (the client's own pool; the
--       shipped drill's model).
--   DRUID_ENERGY_REGEN = 10         the sim's energy tick model: 20 energy per 2 s
--       tick (the sim's core.EnergyPerTick / core.EnergyTickDuration - the same
--       model druid_energy.lua freezes).
local DRUID_BITE_EXECUTE_SECONDS = 10
local DRUID_BITE_MIN_SECONDS = 4
local DRUID_BITE_NEAR_SECONDS = 20
local DRUID_SHIFT_ENERGY_TBC = 10
local DRUID_ENERGY_MAX = 100
local DRUID_ENERGY_REGEN = 10

-- The families whose sim carries the Savage Roar (the SoD savage_roar.go and the
-- Wrath roarNow). The runeless Era sim and the TBC sim have no Roar rule, so the
-- drill answers nil there.
local function druid_family_has_roar(family)
    return family == "SOD" or family == "WRATH"
end

-- The families whose sim Bites: TBC (biteAtEnd), Wrath (canBite) and Forever
-- (biteEnd / biteLow). The Era and SoD sims have no Bite branch at all (the sim's
-- canBite is commented out), so the drill answers nil there.
local function druid_family_bites(family)
    return family == "TBC" or family == "WRATH" or family == "FOREVER"
end

-- The fresh Savage Roar length at the current combo points (the sim's savage_roar.go:
-- 9 + 5 per combo point -> 14/19/24/29/34 s - the same table the engine freezes as
-- SOD_SR_DURATION). Above 5 combo points it caps at the 5 CP row; an unreadable combo
-- count answers nil (unknown - the clip math then stays dormant).
local function druid_sr_fresh_duration(combo_points)
    local durations = st.druid_guide and st.druid_guide.SOD_SR_DURATION
    if type(durations) ~= "table" then
        return nil
    end
    if type(combo_points) ~= "number" or combo_points ~= combo_points then
        return nil
    end
    if combo_points >= 5 then
        return durations[5]
    elseif combo_points >= 4 then
        return durations[4]
    elseif combo_points >= 3 then
        return durations[3]
    elseif combo_points >= 2 then
        return durations[2]
    elseif combo_points >= 1 then
        return durations[1]
    end
    return nil
end

-- The sim's shift trigger for the running family:
--   TBC     - the fixed line: below 10 energy the cat shifts (sim wowsims/tbc-new
--             sim/druid/feralcat/rotation.go).
--   ERA/SOD - the cost trigger: shift when the energy at the next tick is still below
--             the builder cost (sim wowsims/classic and wowsims/sod
--             sim/druid/feral/rotation.go: shiftNow when nextEnergy < cost).
--   WRATH/FOREVER - no shift basis at all (the Wrath Furor no longer refunds on a
--             shift and the Forever APL has no shift rule): the drill has no trigger
--             and answers nil there.
-- The cost is the builder cost the state carries (mangle_cost / shred_cost), else the
-- frozen Shred cost (druid_guide.lua's SHRED_COST_TBC - the 2.5.6 spell data; the
-- Era/SoD value is UNCONFIRMED in-client).
local function druid_shift_line(family, inputs)
    if family == "TBC" then
        return DRUID_SHIFT_ENERGY_TBC, false
    end
    if family == "ERA" or family == "SOD" then
        local cost = inputs.mangle_cost
        if type(cost) ~= "number" then
            cost = inputs.shred_cost
        end
        if type(cost) ~= "number" or cost ~= cost then
            cost = (st.druid_guide and st.druid_guide.SHRED_COST_TBC) or 42
        end
        return cost, true
    end
    return nil, false
end

-- The druid drills (the audit's target drill set: bench/class_features_drills_2026-10-19.md
-- section 2.5 (C) D-D1..D-D4). Every grade answers the CURRENT state - the engine's
-- drill press grades the moment (its own rule: "a class that needs more gathers it
-- itself") - and returns nil when the state it needs is missing: unknown-hides, never
-- a guess. The triggers and the windows are the sim's; the bands are [DESIGN] (addon
-- policy, marked in the comments).
ST.DRUID.practice_drills = {
    -- D-D1: the cat priority order (rotation priority order). The expected action is
    -- the guide engine's own answer, so the drill teaches the shipped rotation and
    -- not a second, drifting copy of it. When the ctx carries the player's pick
    -- (the scenario's last_action) the drill compares it with that answer and keeps
    -- the spec's window over the last ten picks: no mis-pick S, one A, two B, three
    -- C, five D, more F. The ledger lives in the engine's session state (ctx.state);
    -- without one the single pick is the whole window (a wrong pick is a 100 % wrong
    -- window -> F). With no pick at all the drill answers nil: the priority order is
    -- a sequence skill, and the rotation scenario grades the sequence itself.
    -- A PRESS-NOTHING hold (the guide says: press nothing) is skipped the same way:
    -- the drill answers nil (the engine shows UNKNOWN and records no attempt), so a
    -- hold never banks a mis-pick.
    {
        key = "druid_finisher_order",
        label = "The cat priority",
        grade = function(self, ctx)
            local inputs = druid_state_inputs(self, ctx)
            local expected = druid_expected(inputs)
            local actual = druid_ctx_value(ctx, "last_action")
            if expected == nil then
                -- A press-nothing hold or a state the guide cannot read: nothing to
                -- grade (no attempt, so no mis-pick is banked).
                return nil
            end
            if type(actual) ~= "string" then
                -- No pick: the priority order is a sequence skill, and the rotation
                -- scenario grades the sequence itself.
                return nil
            end
            local hit = expected == actual
            local state = type(ctx) == "table" and type(ctx.state) == "table"
                and ctx.state or nil
            if state == nil then
                return hit and "S" or "F"
            end
            local window = state.druid_priority_window
            if type(window) ~= "table" then
                window = {}
                state.druid_priority_window = window
            end
            window[#window + 1] = hit
            while #window > 10 do
                table.remove(window, 1)
            end
            local mispicks = 0
            for i = 1, #window do
                if window[i] == false then
                    mispicks = mispicks + 1
                end
            end
            if mispicks == 0 then
                return "S"
            elseif mispicks <= 1 then
                return "A"
            elseif mispicks <= 2 then
                return "B"
            elseif mispicks <= 3 then
                return "C"
            elseif mispicks <= 5 then
                return "D"
            end
            return "F"
        end,
    },
    -- D-D2: the shift rule, re-sourced (the situational decision). The shipped
    -- druid_powershift drill grades the addon's own 20-energy rule, which the sims do
    -- not use; this drill grades the sim's trigger instead - the TBC fixed line
    -- (below 10 energy) and the classic/sod cost trigger (the energy at the next tick
    -- still below the builder cost). The bands are the spec's, measured against that
    -- line: below it S (the shift belongs here), up to 10 above A, 20 B, 30 C, more D
    -- (the pool is still high: a shift now would be wasted), and a capped pool F (the
    -- shift was never taken in time).
    {
        key = "druid_powershift_rework",
        label = "The shift rule, re-sourced",
        grade = function(self, ctx)
            local inputs = druid_state_inputs(self, ctx)
            local energy = inputs.energy
            if type(energy) ~= "number" or energy ~= energy then
                return nil
            end
            local line, cost_basis = druid_shift_line(druid_ctx_rotation_family(ctx), inputs)
            if line == nil then
                return nil
            end
            local energy_max = inputs.energy_max
            if type(energy_max) ~= "number" or energy_max ~= energy_max then
                energy_max = DRUID_ENERGY_MAX
            end
            if energy >= energy_max then
                return "F"      -- the pool capped: the shift was never taken in time
            end
            local over
            if cost_basis then
                -- The cost trigger: the energy at the next tick (the sim's
                -- nextEnergy) still has to be below the builder cost.
                local tick = inputs.tick_remaining
                local regen = inputs.regen_per_second
                if type(regen) ~= "number" or regen ~= regen then
                    regen = DRUID_ENERGY_REGEN
                end
                local next_energy = energy
                if type(tick) == "number" and tick == tick and tick > 0 then
                    next_energy = energy + regen * tick
                end
                over = next_energy - line
            else
                over = energy - line
            end
            if over < 0 then
                return "S"
            elseif over <= 10 then
                return "A"
            elseif over <= 20 then
                return "B"
            elseif over <= 30 then
                return "C"
            end
            return "D"
        end,
    },
    -- D-D3: the Roar upkeep (the cooldown / rotation window). The sim refreshes the
    -- Roar on expiry (SoD's roarNow, the Wrath's roarNow) and clips it to cover the
    -- end of the fight (clipRoar). The grade reads the Roar state at this moment: the
    -- clip is S (cast now), an on-time repair is S, a repair up to 2 s late A, up to
    -- 4 s B, a lapsed upkeep C, a lapsed upkeep that burned a builder D, and a Roar
    -- that was never maintained F. A cast while the Roar is still up and outside the
    -- clip is not an upkeep event at all (the sim would wait for the expiry): the
    -- drill answers nil there.
    {
        key = "druid_roar_upkeep",
        label = "The Roar upkeep",
        grade = function(self, ctx)
            local family = druid_ctx_rotation_family(ctx)
            if not druid_family_has_roar(family) then
                return nil
            end
            local inputs = druid_state_inputs(self, ctx)
            local sr_remaining = inputs.sr_remaining
            if type(sr_remaining) ~= "number" or sr_remaining ~= sr_remaining then
                return nil
            end
            if sr_remaining > 0 then
                -- The Roar is up: the sim's clip (a fresh Roar covers the fight's end)
                -- is the one cast that belongs here.
                local fresh = druid_sr_fresh_duration(inputs.combo_points)
                local ttd = inputs.time_to_die
                if fresh ~= nil and type(ttd) == "number" and ttd == ttd
                    and sr_remaining < ttd and ttd <= fresh then
                    return "S"
                end
                return nil
            end
            -- The Roar is down: the upkeep lapsed. The lateness is how long the Roar
            -- has been down (the class's own tracker).
            local late = inputs.sr_expired_seconds
            if type(late) == "number" and late == late then
                if late <= 0 then
                    return "S"
                elseif late <= 2 then
                    return "A"
                elseif late <= 4 then
                    return "B"
                end
                return "C"
            end
            local burned = druid_ctx_value(ctx, "builders_since_expiry")
            if type(burned) == "number" then
                return burned > 0 and "D" or "C"
            end
            if inputs.sr_seen == false then
                return "F"      -- the Roar was never up this fight
            end
            return nil
        end,
    },
    -- D-D4: the execute (the transition). The sim Bites only at the end of the fight
    -- (the TBC biteAtEnd, the Wrath canBite, the Forever biteEnd / biteLow) and only
    -- with the Rip and the Roar healthy enough to survive the rebuild. The grade: the
    -- Bite in the window with both minima S, one minimum short by 2 s A, 4 s B, a
    -- Bite just outside the window C, and a Bite the sim would never have cast (a
    -- mid-fight Bite, or one with a badly broken minimum) D. No Bite at all in the
    -- window, with the finisher ready and the ctx carrying the player's last cast,
    -- is F.
    {
        key = "druid_bite_execute",
        label = "The execute",
        grade = function(self, ctx)
            local family = druid_ctx_rotation_family(ctx)
            if not druid_family_bites(family) then
                return nil
            end
            local inputs = druid_state_inputs(self, ctx)
            local ttd = inputs.time_to_die
            local short = inputs.target_short_lived == true
            local in_window = short
                or (type(ttd) == "number" and ttd == ttd and ttd <= DRUID_BITE_EXECUTE_SECONDS)
            local actual = druid_ctx_value(ctx, "last_action")
            local cast = actual == "bite" or actual == "ferocious_bite"
            if not cast then
                -- No Bite: inside the window with the finisher ready the sim would
                -- have Bited.
                if in_window then
                    local cp = inputs.combo_points
                    if type(cp) == "number" and cp >= 5 then
                        return "F"
                    end
                end
                return nil
            end
            if not in_window then
                if type(ttd) == "number" and ttd == ttd
                    and ttd <= DRUID_BITE_NEAR_SECONDS then
                    return "C"
                end
                return "D"
            end
            local rip = inputs.rip_remaining
            local sr = inputs.sr_remaining
            if type(rip) ~= "number" or type(sr) ~= "number" then
                return nil
            end
            local shortfall = 0
            if rip < DRUID_BITE_MIN_SECONDS then
                shortfall = math.max(shortfall, DRUID_BITE_MIN_SECONDS - rip)
            end
            if sr < DRUID_BITE_MIN_SECONDS then
                shortfall = math.max(shortfall, DRUID_BITE_MIN_SECONDS - sr)
            end
            if shortfall <= 0 then
                return "S"
            elseif shortfall <= 2 then
                return "A"
            elseif shortfall <= 4 then
                return "B"
            end
            return "D"
        end,
    },
}

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
-- when the guide is idle (renders as the empty text). No rotation-text practice
-- branch: the rotation key never guesses off sim state. The druid practice seam
-- (practice_sync + the druid_powershift wrappers, above) rides the shared session
-- instead. One reused
-- output table: no per-tick allocation on the label tick.
ST.DRUID.rotation_out = {}

-- The guide slot's localized spell name for an action key (the slot's current-rank
-- spell id, so a re-pointed icon re-points the label with it). Falls back to the
-- raw action key when the client's spell data has not answered yet.
-- Name-vs-id: TBC queries the English name; Era queries the id.
local rotation_name_cache = {}
local ROTATION_TBC_NAMES = {
    maul = MAUL_NAME,
    mangle = MANGLE_NAME,
    rip = RIP_NAME,
    rake = RAKE_NAME,
    bite = BITE_NAME,
    shred = SHRED_NAME,
    claw = CLAW_NAME,
}

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
        if st.family == "TBC" then
            local tbc_name = ROTATION_TBC_NAMES[action]
            if tbc_name then
                local answered = api.GetSpellInfo(tbc_name)
                if answered then
                    return answered
                end
                return tbc_name
            end
        end
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
-- THE PUBLISH IS FAMILY-SCOPED (the shape the engine reads: a family key -> a set of
-- action keys, resolved for the running client family - st.family). A family the
-- class published no bucket for answers nil, and the engine then grades every
-- non-rotation press exactly as before (unknown-hides, never a guess).
--
-- THE CLOSED LIST (the class's own suite pins every clause):
--   * every key is a key the class's OWN panel offers - the guide slot key (the
--     panel's action row), the class's own rotation key or the class's own
--     practice-panel ability list (the common abilities below). No invented key;
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
--   rake            Rake - a guide slot on every family (the druid's guide slot set
--                   is flat) and a rotation row only on SOD / WRATH / FOREVER (the
--                   SoD upkeep S7, the Wrath upkeep W7, the Forever upkeep F4). On
--                   the era-base game and on the TBC client the cat rotation asks
--                   for neither Rake nor Bite, and the Rake is a vanilla cat ability
--                   - so a Rake press there is legitimate and ungraded.
--                   THE ERA BUCKET IS BUILD-AWARE: the SoD build runs on the ERA
--                   client and the engine's family-scoped publish reads st.family
--                   only, so the ERA bucket covers BOTH builds - and on the SoD build
--                   the rotation DOES ask for the Rake. The class's OWN build
--                   decision therefore drops the key there; see
--                   apply_neutral_build_pick below.
--   healing_touch   Healing Touch - a heal the rotation never asks for.
--   rejuvenation    Rejuvenation - a heal the rotation never asks for.
--   regrowth        Regrowth - a heal the rotation never asks for.
--   cheetah         Aspect of the Cheetah - a movement spell.
--   healthstone     Healthstone - a consumable.
--   healing_potion  Healing Potion - a consumable.
--   food            Food - a consumable.
--
-- THE KEYS THAT ARE DELIBERATELY NOT NEUTRAL:
--   bite            Ferocious Bite (24248) - a rotation row on TBC (T3), Wrath
--                   (W8) and Forever (F6a/F6b). The spell does not exist at all
--                   on the era and the SoD clients, so a press there is an
--                   intentional mis-pick (the panel offers the key - the guide slot
--                   set is flat - but the client cannot cast it).
--   shift           The powershift drill's OWN cast (the drill's truth): the
--                   rotation never asks for it, and a drill's own truth is never a
--                   neutral action.
--   innervate, leader_of_the_pack, cat_form, the rotation rows (shred, rip, rake,
--   mangle, bite, tigers_fury, berserk, savage_roar, faerie_fire, claw, ride,
--   maul, shifting_power, elunes_light, bloodlust) - the rotation grades those.
--
-- THE CATA AND MISTS CLIENTS carry no bucket here: the class publishes no neutral
-- set for them, so every non-rotation press on those clients stays a mis-pick
-- (exactly as before this table) - the same shape the four classes that already
-- landed it publish (bench/class_common_actions_2026-10-20.md §3).
--=========================================================================================
ST.DRUID.practice_neutral_actions = {
    ERA = {
        rake = true,
        healing_touch = true,
        rejuvenation = true,
        regrowth = true,
        cheetah = true,
        healthstone = true,
        healing_potion = true,
        food = true,
    },
    TBC = {
        rake = true,
        healing_touch = true,
        rejuvenation = true,
        regrowth = true,
        cheetah = true,
        healthstone = true,
        healing_potion = true,
        food = true,
    },
    WRATH = {
        healing_touch = true,
        rejuvenation = true,
        regrowth = true,
        cheetah = true,
        healthstone = true,
        healing_potion = true,
        food = true,
    },
    FOREVER = {
        healing_touch = true,
        rejuvenation = true,
        regrowth = true,
        cheetah = true,
        healthstone = true,
        healing_potion = true,
        food = true,
    },
    -- THE CATA AND MISTS CLIENTS (the 4.4.3 and the 5.5.0 clients - the two TOCs
    -- that ship this addon, SwedgeTimer_Cata.toc and SwedgeTimer_Mists.toc) carry
    -- NO BUCKET HERE, and that is the class's own statement, not a gap:
    --
    --   * the class publishes NO rotation for either client (the rotation table
    --     carries no CATA / MISTS row - the cat and the bear chains are cut per
    --     family and name ERA / SOD / TBC / WRATH / FOREVER), so on those two
    --     clients no row of the class's own is a rotation action. A bucket is the
    --     class's statement about a client it PLAYS; the class plays neither of
    --     these;
    --   * the class's guide vocabulary on those two clients is its own FLAT cat and
    --     bear set, and the 4.0 client reworked that chain, so the class makes no
    --     statement about it there (the Rake is a rotation action on every family
    --     whose rotation names it - the SoD upkeep S7, the Wrath upkeep W7, the
    --     Forever upkeep F4);
    --   * so the OFFER GATE (ST.DRUID.practice_common_offer_allowed) offers NO
    --     common ability on those two clients: an ability the family does not
    --     publish as neutral can only be a mis-pick the moment it is pressed, so
    --     the panel does not offer it there. It stays available on the families
    --     where the class DOES publish it.
    --
    -- FOR THE RECORD (the clients' own spell pages - the /data/spell/<id> page on
    -- the warcraftdb site, on the Cataclysm and the MoP expansion domains, whose
    -- title carries the client's own spell name): the Cata and the Mists clients
    -- DO carry every one of the class's seven common abilities - Healing Touch
    -- 5185, Rejuvenation 774, Regrowth 8936, the Aspect of the Cheetah 5118, the
    -- Healthstone (the clients' own rank is 6262 - the Era id 5720 answers "Not
    -- Found" there, and 6262 is a DIFFERENT spell on the classic clients - "Minor
    -- Healthstone" - so the ladder is NOT extended with it: the id table is the
    -- citation and the fallback, and the client's own rank only where that id
    -- still exists on it; the NAME-first leg finds the client's own rank only
    -- where the client ANSWERS the name, and whether the classic-line global
    -- takes a name at all is UNCONFIRMED in-client,
    -- bench/final_gate_audit_2026-10-20.md §6 C1), the Healing Potion 439 and the
    -- Food 433. The exclusion is a deliberate statement about a client the class
    -- does not play, not a belief that the client lacks the spells.
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
function ST.DRUID.practice_neutral_set()
    local published = ST.DRUID.practice_neutral_actions
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
function ST.DRUID.practice_rotation_action_set()
    local out = {}
    local ok, entries = pcall(function() return ST.DRUID.practice_rotation_for() end)
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
-- onto the canonical key). The druid has none - its key space is one - so the
-- normaliser is the identity.
function ST.DRUID.practice_canonical_key(key)
    local aliases = ST.DRUID.practice_action_aliases
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
function ST.DRUID.practice_common_offer_allowed(action, neutral, rotation)
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
        and rotation[ST.DRUID.practice_canonical_key(action.key)] == true then
        return false
    end
    return true
end

-- The build-aware half of the neutral publish.
--
-- The SoD build runs on the ERA client, so the engine's family-scoped publish
-- (st.family) cannot separate the two builds that share the ERA token - the same
-- limit the warrior's Battle Shout and the shaman's Lightning Shield ran into.
-- The CLASS can separate them: the class's own SoD probe (the Mangle / Savage Roar
-- rune) latches the running build for the session, and the rotation family already
-- reads that latch.
--
-- The Rake is a rotation action on every family whose rotation asks for it (the
-- SoD upkeep S7, the Wrath upkeep W7, the Forever upkeep F4). Publishing it as
-- neutral on such a family would make a WRONG Rake press free - the grading hole
-- this table must never open. So the pick keeps the key only where the rotation
-- does not ask for the Rake.
--
-- The pick takes the build as its argument (the probe's own answer) and never
-- consults the client itself: it therefore cannot move the probe's latch, and the
-- publish and the rotation family always read the SAME decision. Only the ERA
-- bucket can change (the SoD build shares the ERA token); the other buckets are
-- the family's own truth and are never touched here.
function ST.DRUID.apply_neutral_build_pick(is_sod_build)
    local published = ST.DRUID.practice_neutral_actions
    if type(published) ~= "table" or type(published.ERA) ~= "table" then
        return false
    end
    if st.family ~= "ERA" then
        return false
    end
    if is_sod_build == nil then
        -- No answer given: read the probe's LATCHED result. nil means the probe
        -- has not answered yet - reading it never consults the client, so the
        -- publish keeps its static shape until the probe's own first
        -- consultation corrects it.
        if sod_probe_result == nil then
            return false
        end
        is_sod_build = (sod_probe_result == true)
    end
    if not is_sod_build then
        -- The Era-base build: the static publish already carries the Rake (the cat
        -- rotation asks for neither the Rake nor the Bite there), so the pick has
        -- nothing to correct.
        return false
    end
    published.ERA.rake = nil
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
--     (the rogue's resolve_named_spell rule, classes/rogue.lua), and the id the
--     client answers WITH that name is its own rank's id - so a client that
--     indexes the English name shows its own rank art. Whether the classic-line
--     global GetSpellInfo takes a name at all is UNCONFIRMED in-client
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
-- SWIFTMEND IS DELIBERATELY NOT HERE: the Era client has no Swiftmend spell, and the
-- TBC/WotLK ids (47824 / 31216) are not in the Era corpus - an id is never invented
-- (bench/class_common_actions_2026-10-20.md §5).
--
-- NO ROTATION ACTION HERE: none of these keys is a rotation action on any family the
-- druid plays (the class's own rotation rows: shred, rip, rake, mangle, bite,
-- tigers_fury, berserk, savage_roar, faerie_fire, cat_form, leader_of_the_pack,
-- innervate, elunes_light, bloodlust, claw, ride, maul, shifting_power), so none of
-- them may be a rotation action; the neutral set above publishes exactly these keys.
--=========================================================================================
ST.DRUID.practice_common_actions = {
    {
        key = "healing_touch",
        label = "Healing Touch",
        names = { "Healing Touch" },
        -- 5185 (r1) / 5186 / 5187 / 5188 / 5189 / 6778 / 8903 / 9758 / 9888 (r9) /
        -- 9889 (r10) / 25297 (r11) - the client's Healing Touch ladder: the druid's
        -- OWN Restoration skill line in the corpus
        -- (/home/sam/wow.export/SkillLineAbility.csv, skill line 573) carries exactly
        -- these eleven ids, and the corpus describes every one of them as "Heals a
        -- friendly target for $s1." (Spell.csv). The names are confirmed on the
        -- Classic spell pages (the /data/spell/<id> title: "Healing Touch" for
        -- 5185, 9888 and 25297). No druid rotation row asks for it.
        ids = { 5185, 5186, 5187, 5188, 5189, 6778, 8903, 9758, 9888, 9889, 25297 },
    },
    {
        key = "rejuvenation",
        label = "Rejuvenation",
        names = { "Rejuvenation" },
        -- 774 (r1) / 1058 / 1430 / 2090 / 2091 / 3627 / 8910 / 9839 (r8) / 9840 (r9) /
        -- 9841 (r10) / 25299 (r11) - the client's Rejuvenation ladder (the corpus
        -- describes every one of them as "Heals the target for $o1 over $d.").
        -- 9842 / 9843 are the Improved Rejuvenation grants of the same spell (the
        -- corpus gives them no description of their own; the Classic spell page
        -- titles them "Rejuvenation"), so they are published with it.
        -- The names are confirmed on the Classic spell pages (774, 9839, 9842).
        ids = { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 9842,
            9843, 25299 },
    },
    {
        key = "regrowth",
        label = "Regrowth",
        names = { "Regrowth" },
        -- 8936 (r1) / 8938 / 8939 / 8940 / 8941 / 9750 / 9856 (r7) / 9857 (r8) /
        -- 9858 (r9) - the client's Regrowth ladder (the corpus describes every one of
        -- them as "Heals a friendly target for $s1 and another $o2 over $d."). The
        -- names are confirmed on the Classic spell pages (8936, 9856).
        -- NOTE: 9844 is NOT a Regrowth rank - the Classic spell page titles it
        -- "Rejuvenation" (the Improved Rejuvenation grant), so it is published with
        -- the Rejuvenation instead. No druid rotation row asks for the Regrowth.
        ids = { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 },
    },
    {
        key = "cheetah",
        label = "Aspect of the Cheetah",
        names = { "Aspect of the Cheetah" },
        -- 5118 - the client's Aspect of the Cheetah (the corpus description: "The
        -- hunter takes on the aspects of a cheetah, increasing movement speed by
        -- $s1%." - the shared movement spell; the name confirmed at the Classic
        -- spell page (5118)). No druid rotation row asks for it.
        ids = { 5118 },
    },
    {
        key = "healthstone",
        label = "Healthstone",
        names = { "Healthstone" },
        -- 5720 - the client's Healthstone use effect (the corpus description:
        -- "Instantly restores $s1 life."; the name confirmed at the Classic spell
        -- page (5720)). The panel's vocabulary is SPELLS, so the use effect is the
        -- cited spell.
        ids = { 5720 },
    },
    {
        key = "healing_potion",
        label = "Healing Potion",
        names = { "Healing Potion" },
        -- 439 / 440 / 441 / 2024 / 4042 / 17534 - the client's Healing Potion use
        -- effects (the corpus description: "Restores $s1 health."; the name
        -- confirmed at the Classic spell page (439)). No druid rotation row asks
        -- for it.
        ids = { 439, 440, 441, 2024, 4042, 17534 },
    },
    {
        key = "food",
        label = "Food",
        names = { "Food" },
        -- 433 / 2639 / 5004 / 10256 / 10257 - the client's Food use effects (the
        -- corpus description: "Restores $o1 health over $d.  Must remain seated
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
function ST.DRUID.resolve_practice_common_action(action)
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
function ST.DRUID.practice_panel_slots()
    local guide = ST.DRUID.guide
    local slots = type(guide) == "table" and guide.slots or nil
    local out = {}
    if type(slots) == "table" then
        for i = 1, #slots do
            out[i] = slots[i]
        end
    end
    local common = ST.DRUID.practice_common_actions
    if type(common) == "table" then
        -- THE OFFER GATE: a common ability is offered on the running family only if
        -- that family publishes it (as neutral) or the rotation ranks it there - the
        -- offer list and the neutral set are one truth per family.
        local neutral = ST.DRUID.practice_neutral_set()
        local rotation = ST.DRUID.practice_rotation_action_set()
        for i = 1, #common do
            local action = common[i]
            if ST.DRUID.practice_common_offer_allowed(action, neutral, rotation) then
                local slot = ST.DRUID.resolve_practice_common_action(action)
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
function ST.DRUID.apply_practice_panel_actions()
    local guide = ST.DRUID.guide
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
    local widened = ST.DRUID.practice_panel_slots()
    if type(widened) ~= "table" or #widened <= #current then
        return false
    end
    guide.slots = widened
    return true
end

--=========================================================================================
-- Shared practice-panel provider (class-isolation 2026-10-21 C4)
--=========================================================================================
-- The druid's OWN practice route, panel order, ability def and drill session. The
-- shared practice UI asks the ACTIVE class for this table and renders the
-- answers; it never names the druid. The drill's single cast key and label are
-- the class's own facts.
ST.DRUID.practice_panel = {
    drill_key = "druid_powershift",
    title = "|cFFFF8800Powershift Practice|r",
    def_type = "shift",
    drift_message = "Practice mode is not available (druid drill key drifted).",
    idle_status = "Drill idle - press Start Fight",
    hint_active = "Click to powershift. /st practice or the X button stops.",
    hint_stopped = "Press Start Fight, or cast to powershift.",
    progress = {
        mode = "druid_powershift_rework",
        scenario = "druid_rotation",
        drills = { "druid_finisher_order" },
    },
    scenario_key = function() return ST.DRUID.practice_scenario_key() end,
    order = function() return { "shift" } end,
    label = function(key)
        if key ~= "shift" then
            return nil
        end
        return "Powershift"
    end,
    spell_id = function() return nil end,
    status = function(ui, now)
        local summary
        if type(ST.DRUID.practice_summary) == "function" then
            local ok_sum, sum = pcall(function()
                return ST.DRUID.practice_summary(ui.druid_session)
            end)
            if ok_sum then
                summary = sum
            end
        end
        if summary and type(summary.attempts) == "number" and summary.attempts > 0 then
            return string.format("Shifts: %d  Score: %d", summary.attempts,
                summary.score or 0)
        end
        return nil
    end,
    fight_elapsed = function(ui, now)
        local session = ui.druid_session
        if session and session.active and type(session.started_at) == "number"
            and type(now) == "number" then
            local elapsed = now - session.started_at
            if elapsed == elapsed and elapsed >= 0 then
                return elapsed
            end
        end
        return nil
    end,
    session = {
        running = function(ui) return ui.druid_session ~= nil end,
        active = function(ui)
            return ui.druid_session and ui.druid_session.active
        end,
        start = function(self, now, ui)
            if type(ST.DRUID.new_practice_session) ~= "function"
                or type(ST.DRUID.tick_practice_session) ~= "function"
                or type(ST.DRUID.practice_shift) ~= "function" then
                return false
            end
            local ok_new, session = pcall(function()
                return ST.DRUID.new_practice_session(now, {})
            end)
            if not ok_new or session == nil then
                return false
            end
            ui.druid_session = session
            ui.druid_out = {}
            return true
        end,
        tick = function(self, now, elapsed, ui)
            local session = ui.druid_session
            if session == nil then
                return
            end
            local out = ST.DRUID.tick_practice_session(session, now, elapsed,
                ui.druid_out)
            ui.druid_out = out
            ui.update_fight_timer(self, now)
        end,
        cast = function(self, key, ui)
            local session = ui.druid_session
            if session == nil then
                return nil
            end
            return ST.DRUID.practice_shift(session, api.get_time())
        end,
        stop = function(self, ui)
            local session = ui.druid_session
            if session == nil then
                return
            end
            if type(ST.DRUID.end_practice_session) == "function" then
                ST.DRUID.end_practice_session(session, api.get_time())
            end
            ui.druid_session = nil
            ui.druid_out = nil
        end,
        begin = function(self, now, ui)
            if type(ST.DRUID.new_practice_session) == "function" then
                local ok, session = pcall(function()
                    return ST.DRUID.new_practice_session(now, {})
                end)
                if ok and session then
                    ui.druid_session = session
                    ui.druid_out = {}
                end
            end
        end,
        end_session = function(self, ui)
            if ui.druid_session and type(ST.DRUID.end_practice_session) == "function" then
                ST.DRUID.end_practice_session(ui.druid_session, api.get_time())
            end
        end,
        pause = function(self, ui, shift)
            local session = ui.druid_session
            if session and type(session.started_at) == "number" then
                session.started_at = session.started_at + shift
            end
        end,
        -- The druid's sim-path mirror seam (its energy readout), the same seam the
        -- shared bridge called for the druid before the provider contract landed.
        sync_sim = function(self)
            if type(ST.DRUID.practice_sync) == "function" then
                ST.DRUID.practice_sync(self)
            end
        end,
        sync = function() end,
        clear = function(self) self:handle_bar_visibility("mainhand") end,
    },
}

if st.debug then st.utils.print_msg('-- Parsed classes/druid.lua module correctly') end

end

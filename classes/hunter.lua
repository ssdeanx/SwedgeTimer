--=========================================================================================
-- Module for Hunter-specific behaviours
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
-- Cross-client API wrappers (see compat.lua).
local api = st.api
local get_tab = st.utils.convert_lookup_table

--=========================================================================================
-- Spell data
--=========================================================================================
-- Raptor Strike, all ranks across the classic families (vanilla -> BCC -> WotLK).
-- The lookup table keeps every rank id; get_family_spell_id picks the highest id
-- that exists on the running client (the current rank).
local raptor_strike_ids = get_tab({
    2973, 14260, 14261, 14262, 14263, 14264, 14265, 27014, 48995, 48996
})

-- Steady Shot ranks across the classic families (56641 is the shared base id,
-- 34120 the TBC-era rank; 49051 and 49052 are the WotLK ranks). The exact id set
-- must be confirmed in-client: an id missing from this table is simply never
-- detected, so the queue colour for that rank stays inert.
local steady_shot_ids = get_tab({
    56641, 34120, 49051, 49052
})

-- Multi-Shot ranks, as listed by the reference (SuperSwingTimer_Constants.lua:452-459,
-- TBC-era set). Multi-Shot carries no steady-shot grace: its hidden window delays Auto
-- Shot on overlap, so a live Multi-Shot cast tints the cast bar unsafe past the bare
-- latency buffer (reference ApplyHunterCastBarColor, SuperSwingTimer_UI.lua:862-886).
-- The WotLK-era ranks are not in the reference table; an id missing here simply falls
-- back to the steady-shot grace, while the name match below covers the ranks whose ids
-- are present (the localized name is shared across ranks and needs in-client
-- confirmation like every other spell table).
local multi_shot_ids = get_tab({
    2643, 14288, 14289, 14290, 25294, 27021
})

-- Multi-Shot names, resolved from the client's own spell data on first use (a rank id
-- absent from the client simply contributes no name).
local multi_shot_names

-- Aimed Shot ranks: the six vanilla ranks, verified against classicdb.ch
-- (19434 rank 1 through 20904 rank 6; every rank a 3 s cast). TBC adds a seventh
-- rank and Wrath makes the shot instant, but the guide's Aimed rule and slot are
-- Era-only, so later ranks are deliberately not listed: an id missing from this
-- table is simply never detected, and off-Era clients never read this table at
-- all (the gather writes every aimed_* input nil there).
local aimed_shot_ids = get_tab({
    19434, 20900, 20901, 20902, 20903, 20904
})

-- Kill Command, the TBC BM signature (wowhead TBC spell 34026, single rank on the
-- 2.5.6 client). UNCONFIRMED: the id is sourced from out-of-client references, not
-- from a 2.5.6 spell-cache read - confirm with GetSpellInfo(34026) on TBC before
-- release. An id missing from this table is simply never detected, so the guide
-- prompt for it stays inert.
local kill_command_ids = get_tab({
    34026,
})

-- Bestial Wrath (TBC spell 19574: 2 min cooldown, instant, off the GCD) and Rapid
-- Fire (3045, the id hunter_ui.lua already tracks for the Rapid Fire bar). Both are
-- single-id families on the TBC client; the same "absent id stays inert" rule applies.
local bestial_wrath_ids = get_tab({
    19574,
})
local rapid_fire_ids = get_tab({
    3045,
})

-- Kill Shot, the Wrath execute (wowhead wotlk spell 53351: instant, 15 s
-- cooldown; 34104 is the older wotlk rank id, kept so the family resolves on
-- either data set). UNCONFIRMED: sourced from out-of-client references, not
-- from a 3.80.2 spell-cache read - confirm with GetSpellInfo on Wrath before
-- release. An id missing from this table is simply never detected, so the
-- guide prompt for it stays inert.
local kill_shot_ids = get_tab({
    34104, 53351,
})

-- Chimera Shot, the WotLK MM signature (wowhead wotlk spell 53209, instant).
-- Single rank on the WotLK client. Same UNCONFIRMED rule as Kill Command above.
local chimera_shot_wrath_ids = get_tab({
    53209,
})

-- Explosive Shot, the WotLK SV signature (wowhead wotlk spell 53301: instant,
-- 6 s cooldown). Only the confirmed rank is pinned: higher ranks share the
-- cooldown read through this id, while an unrelated id that merely exists in
-- the client's data would resolve instead and report no cooldown (a permanent
-- false-ready prompt). Same UNCONFIRMED rule as Kill Command above.
local explosive_shot_ids = get_tab({
    53301,
})

-- Aimed Shot's Wrath ranks (instant on WotLK, 10 s cooldown: the TBC rank
-- 27065 plus wowhead wotlk spell 49050). Deliberately separate from
-- aimed_shot_ids (the Era-only weave table): the Wrath prompt is an instant
-- cooldown prompt, not the Era 3 s cast weave, and the two never mix (the
-- gather writes wrath_aimed_* only on WRATH, aimed_* only on ERA).
-- Same UNCONFIRMED rule as Kill Command above.
local aimed_shot_wrath_ids = get_tab({
    27065, 49050,
})

-- Arcane Shot's late ranks (instant, 6 s cooldown: the TBC rank 27019 plus
-- wotlk spell 49045). Wrath-only prompt (the MM early-phase tier, suppressed
-- on SV where Arcane shares its cooldown with Explosive Shot). Same
-- UNCONFIRMED rule as Kill Command above.
local arcane_shot_ids = get_tab({
    27019, 49045,
})

-- Chimera Shot, the SoD rune (wowhead classic spell 409433: gloves rune,
-- instant, 6 s cooldown, refreshing the current Sting). SoD-only: no other
-- family has this id, so knowledge of it IS the SoD detector - SoD shares the
-- ERA family token, so the family alone never decides. Same UNCONFIRMED rule
-- as Kill Command above.
local chimera_shot_sod_ids = get_tab({
    409433,
})

-- Summon Hawk, the Forever BM upkeep (wowtbc.gg Forever BM guide: "Cast Summon
-- Hawk if less than two are active", max 2 hawks + pet; shares its cooldown
-- with Arcane Shot). UNCONFIRMED: the beta guides name the spell but publish
-- no spell id (guide pages carry names only, no spell links) - this table is
-- deliberately EMPTY until GetSpellInfo confirms an id in-client. An empty
-- table resolves nothing, so the upkeep prompt stays inert (never guessed).
-- NOT YET IMPLEMENTED (rule F1): even with a confirmed id, the live hawk
-- count has no client source yet (how hawks surface in-client - aura, pet
-- frame, other - is unconfirmed), so inputs.hawk_active_count stays nil and
-- F1 can never fire. The rule, the slot and this table stay declared as the
-- plug-in point; presenting them as live would be advertising an unfirable
-- prompt.
local summon_hawk_ids = get_tab({
})

-- Sniper Shot, the Forever MM signature (wowtbc.gg Forever MM guide: 4 s cast,
-- massive shot). UNCONFIRMED, same rule as Summon Hawk above: empty until an
-- id is confirmed in-client. Knowing it IS the MM detector (the spell itself
-- is MM-only), the same way Chimera-known means MM on Wrath.
local sniper_shot_ids = get_tab({
})

-- Feign Death (5384; reference SuperSwingTimer_State.lua:893, and the vendored
-- LibClassicSwingTimerAPI's own reset_swing_spells[5384] block) and Readiness (23989;
-- reference SuperSwingTimer_Constants.lua:181, wowhead TBC spell page). Both drive
-- event-side handling only (the spellcast-succeeded branches below): Feign Death
-- clears the class-owned ranged display state, Readiness forces the Rapid Fire bar's
-- next scan. Neither is a prompt/rank family, so an absent client simply never fires
-- the branch.
local FEIGN_DEATH_ID = 5384
local READINESS_ID = 23989

-- The Bloodlust/Heroism id set (H2), converted once from compat's confirmed list
-- (st.lust_spell_ids: 2825 Bloodlust / 32182 Heroism, bench/verify_bank.md §2) into
-- the keyed lookup the scan predicate tests. nil when a compat without the C2 surface
-- is loaded, which keeps the scan closed rather than guessing.
local lust_ids = st.lust_spell_ids and get_tab(st.lust_spell_ids) or nil

--=========================================================================================
-- Auto Shot ranged sync (phase 1)
--=========================================================================================
-- The pure maths live in hunter_window.lua (a root module loaded before classes/ on
-- every flavor); this module probes the client and applies the results to self.ranged.
-- Every timestamp is in the api.get_time() domain. Field mapping from
-- SuperSwingTimer_State.lua (697-710, 832-853), translated to the SwedgeTimer fields:
--   source t.lastSwing                -> self.ranged.start
--   source t.duration / t.speed       -> self.ranged.synced_duration (the reference
--                                        writes the cooldown duration into both; the
--                                        engine-owned speed/ends_at keep their swing
--                                        engine values)
--   source t.hiddenCastWindowStart    -> self.ranged.hidden_window_start
--   source t.hiddenCastWindowDuration -> self.ranged.hidden_window_duration
--   source t.lastRangedStartTime      -> self.ranged.last_restart_at
local AUTO_SHOT_ID = 75
-- Forever pet note (docs/research/forever_beta.md): pets scale with hunter
-- stats there, but the sync below reads the live Auto Shot cooldown, so hunter
-- timer maths needs no scaling compensation on any family.

-- nil until hunter_window.lua is listed in the TOCs; the sync then stays inert instead
-- of erroring (the root module loads before classes/ on every flavor once it is listed).
local hunter_window = st.hunter_window

-- Raw world latency in seconds: the same basis the shaman weave helpers and the paladin
-- twist calibration consume. hunter_window.should_restart floors its dedupe window at
-- 0.25 s, so a missing reading changes nothing.
local function world_latency_seconds(self)
    return ((self.latency and self.latency.world_ms) or 0) / 1000
end

function ST.HUNTER.on_cooldown_update(self)
    -- SPELL_UPDATE_COOLDOWN: keep the ranged cycle length in sync with the live Auto
    -- Shot cooldown (reference SyncRangedTimerSpeed, State.lua:697-710). A valid
    -- reading is applied unconditionally; the cached hidden window is dropped (its
    -- bounds depend on the old duration) and the swing anchor moves only past the
    -- 0.01 s drift rule.
    if not hunter_window then
        return
    end
    local ranged = self.ranged
    if not ranged then
        return
    end
    local cooldown_start, cooldown_duration, enabled = api.GetSpellCooldown(AUTO_SHOT_ID)
    -- Inactive reading: no Auto Shot on this client (unknown spell -> 0/0/0 through
    -- compat.lua) or a disabled spell (enabled == 0).
    if cooldown_duration <= 0 or enabled == 0 then
        return
    end
    local duration, _, reanchor = hunter_window.sync_duration(
        ranged.start, cooldown_start, cooldown_duration)
    if duration == nil then
        return
    end
    ranged.synced_duration = duration
    ranged.hidden_window_start = nil
    ranged.hidden_window_duration = nil
    if reanchor then
        ranged.start = cooldown_start
    end
end

function ST.HUNTER.on_autorrepeat_event(self, is_start)
    -- START/STOP_AUTOREPEAT_SPELL for Auto Shot. Mirrors IsHunterAutoRepeatActive
    -- (State.lua:145-181): mounted hunters always read false, otherwise the client
    -- probe decides; api.IsAutoRepeatSpell answers false where no probe exists.
    -- A permitted start seeds the logical cycle anchor used by the hidden-window maths
    -- (reference StartRangedSwing, State.lua:832-853); the swing engine stays
    -- authoritative for the displayed bar and overwrites start on its next ranged
    -- SWING_TIMER_START/UPDATE stamp.
    if not hunter_window then
        return
    end
    local ranged = self.ranged
    if not ranged then
        return
    end
    local active = false
    if not api.IsMounted() then
        active = api.IsAutoRepeatSpell(AUTO_SHOT_ID)
    end
    ranged.auto_repeat_active = active
    if not (is_start and active) then
        return
    end
    local now = api.get_time()
    if not hunter_window.should_restart(now, ranged.last_restart_at, world_latency_seconds(self)) then
        return
    end
    ranged.start = now
    ranged.last_restart_at = now
    ranged.hidden_window_start = nil
    ranged.hidden_window_duration = nil
end

function ST.HUNTER.on_spellcast_failed_quiet(self, unit_id, cast_guid, spell_id)
    if raptor_strike_ids[spell_id] ~= nil then
        self.raptor_strike_queued = false
        self:set_bar_color("mainhand")
    end
    if steady_shot_ids[spell_id] ~= nil then
        self.steady_shot_queued = false
        self:set_bar_color("mainhand")
    end
end

function ST.HUNTER.on_spellcast_succeeded(self, unit_target, cast_guid, spell_id)
    if raptor_strike_ids[spell_id] ~= nil then
        self.raptor_strike_queued = false
        self:set_bar_color("mainhand")
    end
    if steady_shot_ids[spell_id] ~= nil then
        self.steady_shot_queued = false
        self:set_bar_color("mainhand")
    end
    if spell_id == FEIGN_DEATH_ID then
        -- Feign Death (reference State.lua:1459-1461: hunterAutoRepeatActive=false,
        -- ResetTimer("ranged")). The shot is interrupted and the auto-repeat drops; the
        -- swing engine re-anchors its own ranged timer on the FD path (the vendored
        -- LibClassicSwingTimerAPI's 5384 block restarts the swings when the FD cooldown
        -- starts; swing_source has no FD path, so the Forever engine waits for its next
        -- PLAYER_SWING). This module therefore only clears the display state it owns:
        -- the auto-repeat reading, the cached hidden window (its bounds belong to the
        -- dead cycle), the synced cycle length and the restart dedupe stamp (a fresh
        -- start must not be blocked by the old cycle's dedupe window). The engine-owned
        -- start/ends_at/speed are never touched - bars.lua's OnUpdate runs arithmetic
        -- over them every tick.
        local ranged = self.ranged
        if ranged then
            ranged.auto_repeat_active = false
            ranged.hidden_window_start = nil
            ranged.hidden_window_duration = nil
            ranged.synced_duration = nil
            ranged.last_restart_at = nil
        end
    end
    if spell_id == READINESS_ID then
        -- Readiness resets Rapid Fire's cooldown; the reference forces the Rapid Fire
        -- bar's next scan immediately (ForceHunterRapidFireRefresh, ClassMods.lua:
        -- 5951-5956). Here the bar scans from the ranged tick, so the force is a
        -- throttle bypass and the next tick reads the new state. Guarded so a flavor
        -- without hunter_ui stays inert.
        if st.hunter_ui and st.hunter_ui.force_rapid_fire_refresh then
            st.hunter_ui.force_rapid_fire_refresh(self)
        end
    end
end

function ST.HUNTER.on_current_spell_cast_changed(self, is_cancelled)
    -- This function detects when the player queues up a raptor strike or a
    -- steady shot and sets relevant flags for the func to set bar colors.
    local db = self:get_class_table()
    -- Only run the raptor logic if special on-next-attack colors are enabled in
    -- the hunter settings.
    if db.enable_raptor_strike_color then
        for spell_id in pairs(raptor_strike_ids) do
            local result = api.IsCurrentSpell(spell_id)
            if result then
                self.raptor_strike_queued = true
                self:set_bar_color("mainhand")
                return
            end
        end
        self.raptor_strike_queued = false
    end
    -- Steady Shot has its own option gate (the two queue colours are independent).
    -- On classic clients a queued Steady Shot is queued into the swing and
    -- IsCurrentSpell reports it; on Mainline-code clients the queued state surfaces
    -- as a channel instead, so a live player channel whose spell id is in the table
    -- also counts as queued. The rank ids still need in-client confirmation: an id
    -- missing from the table is simply never detected, so the feature stays inert.
    if db.enable_steady_shot_color then
        for spell_id in pairs(steady_shot_ids) do
            local result = api.IsCurrentSpell(spell_id)
            if result then
                self.steady_shot_queued = true
                self:set_bar_color("mainhand")
                return
            end
        end
        -- UnitChannelInfo's payload differs from UnitCastingInfo: it has no castID
        -- and returns the spell id as the 8th value (see compat.lua).
        local _, _, _, _, _, _, _, channel_spell_id = api.UnitChannelInfo("player")
        if channel_spell_id ~= nil and steady_shot_ids[channel_spell_id] ~= nil then
            self.steady_shot_queued = true
            self:set_bar_color("mainhand")
            return
        end
        self.steady_shot_queued = false
    end
end

function ST.HUNTER.post_init(self)
    -- Flags must exist before the first spellcast/current-cast event reaches this
    -- module, otherwise a stale nil would decide the bar colour.
    self.raptor_strike_queued = false
    self.steady_shot_queued = false
    -- Hunter visual set (cast bar, range helper, Rapid Fire bar, aspect icon): creates
    -- its frames on the ranged bar out of combat and stays inert when the ranged bar is
    -- absent or its hand is disabled (e.g. Retail, where no ranged swing ever reports).
    if st.hunter_ui then
        st.hunter_ui.init(self)
    end
    -- Next Action Guide: resolve the guide's ability icons to the client's current ranks
    -- while the spell data is live, then hand the provider (ST.HUNTER.guide at the end
    -- of this file) to the shared frame. Guarded so a flavor without nextaction_ui stays
    -- inert; the guide itself stays hidden until nextaction_enabled is turned on.
    self.HUNTER.resolve_guide_icons()
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

function ST.HUNTER.on_bar_update(self, hand)
    -- Per-frame hunter visual driver, called from ST:onupdate_common via the generic
    -- class hook for every visible bar. The ranged tick drives the full visual set; the
    -- mainhand tick keeps the melee re-anchor in sync when the ranged bar is not ticking
    -- (its OnUpdate stops while the bar is hidden). Deliberately cheap and nil-safe, and
    -- never gated on st.is_mainline: WoW Forever is Mainline-code but must show all of
    -- this, while swing activity decides (the Retail stand-in never reports a swing).
    if hand ~= "ranged" and hand ~= "mainhand" then
        return
    end
    -- Cooldown HUD: retries a lockdown-deferred creation and picks layout option
    -- changes up between the HUD driver's ticks (the row itself ticks on its own
    -- driver frame, so this is cheap). Deliberately not gated on st.is_mainline:
    -- the Forever client must show the HUD, and the Retail stand-in simply never
    -- swings (the paladin hooks it the same way in classes/paladin.lua).
    if st.hud then
        st.hud.on_bar_update(self, hand)
    end
    -- Next Action Guide: driven before the hunter_ui tick below so it also runs while
    -- the visual set is absent. Deliberately not gated on st.is_mainline either - the
    -- Forever client is Mainline-code but shows the guide; the shared frame's show gate
    -- reads the mainhand swing cycle (the melee context these two abilities live in)
    -- and the Retail stand-in never reports any swing, so the guide stays inert there.
    -- Settings that rebuild the frame (scale/position/lock) are applied when the class
    -- options change; the display toggles are read live by the UI.
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
    if st.hunter_ui then
        st.hunter_ui.on_bar_update(self, hand)
    end
end

-- The no-clip tint grace for a live cast (reference ApplyHunterCastBarColor,
-- SuperSwingTimer_UI.lua:862-886): 0 for Multi-Shot, the steady-shot 0.5 grace for
-- everything else. Accepts the cast's spell id and/or its localized name; the WotLK
-- Multi-Shot ranks are not in the reference table, so those fall back to the steady
-- grace (documented in-client confirmation item). Summon Hawk and Sniper Shot
-- carry no table entry yet (UNCONFIRMED, ids unknown): unknown ids read the
-- steady-shot grace here, which is also the correct grace for the 4 s Sniper
-- cast (not a Multi-Shot rank, so the 0 grace never applies).
function ST.HUNTER.get_cast_grace(self, spell_id, cast_name)
    if not hunter_window then
        return 0.5
    end
    if multi_shot_names == nil then
        local names = {}
        for id in pairs(multi_shot_ids) do
            local name = api.GetSpellInfo(id)
            if name then
                names[name] = true
            end
        end
        -- Retry while the client's spell data has not answered at all (an early call
        -- before the client's spell cache is up must not freeze the matcher empty).
        if next(names) ~= nil then
            multi_shot_names = names
        end
    end
    if spell_id ~= nil and multi_shot_ids[spell_id] ~= nil then
        return hunter_window.MULTI_SHOT_GRACE
    end
    -- multi_shot_names stays nil until the client's spell data answers (see above);
    -- indexing it unconditionally crashed when the cache answered none of the ranks.
    if cast_name ~= nil and multi_shot_names and multi_shot_names[cast_name] then
        return hunter_window.MULTI_SHOT_GRACE
    end
    return hunter_window.STEADY_SHOT_GRACE
end

function ST.HUNTER.on_combat_exit(self)
    -- A queued Raptor Strike or Steady Shot dies with the fight.
    self.raptor_strike_queued = false
    self.steady_shot_queued = false
end

function ST.HUNTER.set_bar_color(self, hand)
    local db_class = self:get_class_table()
    local frame = self:get_visuals_frame(hand)
    if hand ~= "mainhand" then
        return false
    end

    -- On-next-attack behaviours
    if db_class.enable_raptor_strike_color and self.raptor_strike_queued then
        frame.bar:SetVertexColor(
            self:convert_color(db_class.raptor_strike_color)
        )
        return true
    end
    if db_class.enable_steady_shot_color and self.steady_shot_queued then
        frame.bar:SetVertexColor(
            self:convert_color(db_class.steady_shot_color)
        )
        return true
    end
    return false
end

--=========================================================================================
-- Next Action Guide: the hunter provider for the generic guide frame
--=========================================================================================
-- Implements the frozen ST.<CLASS>.guide contract documented in nextaction_ui.lua's
-- header. The decision model is the pure st.hunter_guide module (hunter_guide.lua; its
-- docblock is the frozen spec), the live reads live in gather_guide_inputs, and this
-- table is the last piece of glue: the slot set, the gather/evaluate pair and the static
-- captions. Default OFF (nextaction_enabled=false in config_presets.lua): a wrong prompt
-- is worse than none, so the owner enables it after in-client verification.
--
-- Base set (every family except ERA and WRATH): the steady slot carries a cooldown_key fed by
-- the live Steady cast window (steady_remaining / steady_duration): the swipe tracks
-- the cast itself, the only duration a cooldown-less Steady Shot has, and
-- swipe_always keeps it stateful while the RIDE hold fades the icon (the paladin
-- seal pattern). The raptor slot stays swipe-less: the frozen input set carries no
-- raptor cooldown, and the classic families' Raptor Strike has none to show. The four
-- TBC prompt slots (kill_command, multi, bestial_wrath, rapid_fire - six slots total,
-- the contract's maximum) stay swipe-less too: their readiness rides the *_known /
-- *_remaining_cd inputs and the shared frame's show gate reads the mainhand swing
-- cycle (see the drive comment in on_bar_update). The Era set swaps the steady slot
-- for the aimed slot, which carries the same live-cast swipe pair
-- (aimed_remaining / aimed_duration, swipe_duration 3.0 s).
--
-- Era hunters get a different three-slot set (st.family == "ERA"): Steady Shot does
-- not exist there, and Kill Command / Bestial Wrath / Rapid Fire never prompt there,
-- so those slots are dropped rather than shipped dark. Aimed Shot (the Era filler,
-- 3 s cast, 6 s cooldown) takes the primary slot with the same live-cast swipe the
-- steady slot carries on base; raptor stays the melee surface and multi the
-- swipe-less weave prompt. The per-family slot split mirrors the warrior guide
-- (classes/warrior.lua guide_slots_base / guide_slots_tbc).
--
-- Wrath hunters get a third set (st.family == "WRATH", six slots): the WotLK
-- min/max priority (docs/research/rotations_wrath.md). Spec detection needs no
-- talent probe: MM means the client knows Chimera Shot, SV means it knows
-- Explosive Shot (mutually exclusive 51-point talents, resolved at post_init
-- via api.is_spell_known); neither means an unspecced/levelling hunter. The
-- shared steady slot keeps its live-cast swipe (Steady Shot still casts on
-- Wrath); every other Wrath slot is a swipe-less instant prompt.
--
-- SoD hunters (st.family == "ERA" with the Chimera Shot rune known) get a fourth
-- set: the Era set with the chimera slot first (docs/research/rotations_sod.md).
-- The swap happens in resolve_guide_icons (before the shared frame builds its
-- icons), gated on api.is_spell_known of the SoD-only rune id - never on the
-- family alone, since SoD shares the ERA token. A pet-rune build that drops
-- Chimera keeps the plain Era three-slot set.
--
-- Forever hunters (st.family == "FOREVER") get a fifth set: the beta upkeep
-- plus whatever filler the client answers (docs/research/forever_beta.md).
-- The hawk slot ships spell-less (no confirmed id: the icon stays
-- texture-less, exactly like an unresolvable Wrath icon) and swipe-less (the
-- upkeep is instant); the sniper slot carries the live-cast swipe pair of the
-- Era aimed slot (cooldown_key "sniper", 4.0 s fallback) for its 4 s cast.
-- Both re-point at their ranks in resolve_guide_icons once ids confirm - until
-- then the knowledge gates keep every Forever prompt silent and the filler
-- (steady, if known) plus the melee surface (raptor) carry the tick.

-- One reused input table: no per-frame allocations on the guide tick (the frame passes
-- its own reused table through gather; this one serves direct calls).
ST.HUNTER.guide_inputs = {}

-- The current ranks for the guide (resolved once at post_init from the class module's
-- own rank tables). nil = the client does not know that family.
local steady_current_id
local raptor_current_id
local kill_command_current_id
local multi_current_id
local bestial_wrath_current_id
local rapid_fire_current_id
local aimed_current_id
-- The Wrath prompt ranks (resolved once at post_init from the module's own rank
-- tables). nil = not on this client, or not learned by this player (the five
-- Wrath prompts are knowledge-gated at resolve time: the spec detector for
-- Chimera/Explosive, the learned check for the trained shots). chimera_current_id
-- is the family's Chimera: the Wrath MM signature on WRATH, the SoD rune on ERA
-- (one family active per client, so one local serves both).
local kill_shot_current_id
local chimera_current_id
local explosive_current_id
local aimed_wrath_current_id
local arcane_current_id
-- The Forever upkeep/cast ranks (resolved once at post_init from the module's
-- own rank tables). nil = not on this client, or not learned by this player -
-- and until the UNCONFIRMED ids above confirm in-client, always nil: both
-- Forever prompts stay silent by construction.
local hawk_current_id
local sniper_current_id

-- Steady Shot's cast time in seconds (the client's spell data, 1.5 s base fallback).
-- Cached: the spell cache can be cold at post_init, so a miss retries on the next gather
-- instead of freezing the fallback for the session.
local steady_cast_time

-- Multi-Shot's cast time in seconds (the client's spell data, 0.5 s TBC base
-- fallback), cached with the same retry discipline as the Steady Shot cast time.
local multi_cast_time

-- Aimed Shot's cast time in seconds (the client's spell data, 3.0 s Era base
-- fallback), cached with the same retry discipline. Read only on the ERA family
-- (the only family whose slot set declares the aimed slot).
local aimed_cast_time

-- Sniper Shot's cast time in seconds (the client's spell data, 4.0 s Forever
-- base fallback), cached with the same retry discipline. Read only while a
-- Sniper rank is resolved, so no other client spends a probe.
local sniper_cast_time

-- Live cooldown for the guide, with the client's GCD echo filtered: GetSpellCooldown
-- reports whichever cooldown ends later, so a reading of 1.51 s or less is a GCD echo.
-- Returns remaining seconds (>= 0) and the client-reported duration, or (0, nil) when
-- there is no real cooldown to show.
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

-- Slot descriptors: the rank-1 ids ship as the fallback; resolve_guide_icons re-points
-- them at the client's current rank once the spell data is live.
local guide_slot_steady = { key = "steady", spell_id = 56641, cooldown_key = "steady",
    swipe_duration = 1.5, swipe_always = true }
local guide_slot_raptor = { key = "raptor", spell_id = 2973 }
local guide_slot_kill_command = { key = "kill_command", spell_id = 34026 }
local guide_slot_multi = { key = "multi", spell_id = 2643 }
local guide_slot_bestial_wrath = { key = "bestial_wrath", spell_id = 19574 }
local guide_slot_rapid_fire = { key = "rapid_fire", spell_id = 3045 }
local guide_slot_aimed = { key = "aimed", spell_id = 19434, cooldown_key = "aimed",
    swipe_duration = 3.0, swipe_always = true }
-- The Wrath prompt slots (all swipe-less instants; the shared steady slot keeps
-- its live-cast swipe). The Wrath aimed slot is a different object from the Era
-- aimed slot above (same key, never in the same set): the WotLK shot is instant,
-- so it carries no swipe pair - the gather writes wrath_aimed_* only on WRATH
-- and aimed_* only on ERA. The chimera slot is shared between the Wrath set and
-- the Era-SoD set (one family active per client, re-pointed at post_init).
local guide_slot_kill_shot = { key = "kill_shot", spell_id = 53351 }
local guide_slot_chimera = { key = "chimera", spell_id = 53209 }
local guide_slot_explosive = { key = "explosive", spell_id = 53301 }
local guide_slot_aimed_wrath = { key = "aimed", spell_id = 49050 }
local guide_slot_arcane = { key = "arcane", spell_id = 49045 }
-- The Forever upkeep/cast slots. Both ship spell-less (the UNCONFIRMED tables
-- above are empty): the shared frame tolerates a nil spell_id (the icon stays
-- texture-less, no error), and resolve_guide_icons re-points them once ids
-- confirm. The hawk upkeep is instant (swipe-less, like Kill Command); the
-- 4 s Sniper cast carries the live-cast swipe pair (like the Era aimed slot).
local guide_slot_hawk = { key = "hawk" }
local guide_slot_sniper = { key = "sniper", cooldown_key = "sniper",
    swipe_duration = 4.0, swipe_always = true }

-- The slot set is picked once at load: the Era three-slot set on the ERA family,
-- the Wrath six-slot set on the WRATH family, the Forever four-slot set on the
-- FOREVER family, the frozen six-slot set everywhere else (untouched, including
-- TBC). The SoD four-slot set swaps in at post_init (resolve_guide_icons) when
-- the rune is known. The split mirrors the warrior guide (guide_slots_base /
-- guide_slots_tbc): the TBC client keeps byte-identical slots, icons and frame
-- shape.
local is_era_guide = st.family == "ERA"
local is_wrath_guide = st.family == "WRATH"
local is_forever_guide = st.family == "FOREVER"
local guide_slots_base = { guide_slot_steady, guide_slot_raptor, guide_slot_kill_command,
    guide_slot_multi, guide_slot_bestial_wrath, guide_slot_rapid_fire }
local guide_slots_era = { guide_slot_aimed, guide_slot_raptor, guide_slot_multi }
local guide_slots_wrath = { guide_slot_kill_shot, guide_slot_chimera,
    guide_slot_explosive, guide_slot_aimed_wrath, guide_slot_arcane, guide_slot_steady }
local guide_slots_era_sod = { guide_slot_chimera, guide_slot_aimed, guide_slot_raptor,
    guide_slot_multi }
local guide_slots_forever = { guide_slot_hawk, guide_slot_sniper, guide_slot_steady,
    guide_slot_raptor }

-- Resolve the guide icons to the client's current ranks; called once from post_init,
-- before the shared frame builds its icons. A family the client does not know keeps the
-- rank-1 fallback, exactly like the module's other rank-id features.
function ST.HUNTER.resolve_guide_icons()
    steady_current_id = api.get_family_spell_id(steady_shot_ids)
    if steady_current_id then
        guide_slot_steady.spell_id = steady_current_id
    end
    raptor_current_id = api.get_family_spell_id(raptor_strike_ids)
    if raptor_current_id then
        guide_slot_raptor.spell_id = raptor_current_id
    end
    kill_command_current_id = api.get_family_spell_id(kill_command_ids)
    if kill_command_current_id then
        guide_slot_kill_command.spell_id = kill_command_current_id
    end
    multi_current_id = api.get_family_spell_id(multi_shot_ids)
    if multi_current_id then
        guide_slot_multi.spell_id = multi_current_id
    end
    bestial_wrath_current_id = api.get_family_spell_id(bestial_wrath_ids)
    if bestial_wrath_current_id then
        guide_slot_bestial_wrath.spell_id = bestial_wrath_current_id
    end
    rapid_fire_current_id = api.get_family_spell_id(rapid_fire_ids)
    if rapid_fire_current_id then
        guide_slot_rapid_fire.spell_id = rapid_fire_current_id
    end
    aimed_current_id = api.get_family_spell_id(aimed_shot_ids)
    if aimed_current_id then
        guide_slot_aimed.spell_id = aimed_current_id
        -- The HUD aimed icon tracks the same current rank (same pattern, same
        -- table); the provider's name-based read is rank-agnostic either way, and
        -- the icon texture is rank-invariant, so this only matters before the
        -- client's spell data answers. Runs before st.hud.init in post_init.
        for i = 1, #ST.HUNTER.HUD_SLOTS do
            if ST.HUNTER.HUD_SLOTS[i].key == "aimed" then
                ST.HUNTER.HUD_SLOTS[i].spell = aimed_current_id
            end
        end
    end
    -- The Wrath prompt ranks. Data-gating alone is not enough here: the Wrath
    -- spell data carries every id for every hunter, so each rank additionally
    -- needs the knowledge check (api.is_spell_known: THIS player learned it).
    -- That check doubles as the spec detector (Chimera learned = MM, Explosive
    -- learned = SV) and keeps levelling hunters free of prompts for shots they
    -- do not know. Where the client offers no knowledge probe at all,
    -- is_spell_known answers false and every Wrath prompt stays dark (needs
    -- in-client confirmation on 3.80.2). The re-pointed slots are only ever
    -- displayed as part of the Wrath set. Steady Shot keeps its pre-existing
    -- data-gated semantics (trained by every hunter); the five prompts below
    -- are the only knowledge-gated ranks.
    local function resolve_known(ids)
        local id = api.get_family_spell_id(ids)
        if id ~= nil and api.is_spell_known(id) then
            return id
        end
        return nil
    end
    kill_shot_current_id = resolve_known(kill_shot_ids)
    if kill_shot_current_id then
        guide_slot_kill_shot.spell_id = kill_shot_current_id
    end
    if is_wrath_guide then
        chimera_current_id = resolve_known(chimera_shot_wrath_ids)
        if chimera_current_id then
            guide_slot_chimera.spell_id = chimera_current_id
        end
    end
    explosive_current_id = resolve_known(explosive_shot_ids)
    if explosive_current_id then
        guide_slot_explosive.spell_id = explosive_current_id
    end
    aimed_wrath_current_id = resolve_known(aimed_shot_wrath_ids)
    if aimed_wrath_current_id then
        guide_slot_aimed_wrath.spell_id = aimed_wrath_current_id
    end
    arcane_current_id = resolve_known(arcane_shot_ids)
    if arcane_current_id then
        guide_slot_arcane.spell_id = arcane_current_id
    end
    -- Forever (FOREVER token only): the upkeep and the MM tell, knowledge-gated
    -- like the Wrath prompts. The id tables are empty until confirmed
    -- in-client, so both resolve nil here and add no probe at all
    -- (resolve_known short-circuits before is_spell_known) - the slots keep
    -- their spell-less shape and the prompts stay silent by construction.
    hawk_current_id = resolve_known(summon_hawk_ids)
    if hawk_current_id then
        guide_slot_hawk.spell_id = hawk_current_id
    end
    sniper_current_id = resolve_known(sniper_shot_ids)
    if sniper_current_id then
        guide_slot_sniper.spell_id = sniper_current_id
    end
    -- SoD (ERA token only): the rune detector is knowledge, never the family -
    -- api.is_spell_known on the SoD-only rune id. When the rune is known the
    -- Era set swaps to the Era-SoD four-slot set before the shared frame builds
    -- its icons (resolve runs before st.nextaction_ui.init in post_init), and the
    -- chimera slot re-points at the rune. A mid-session rune learn needs a reload
    -- (no frame rebuild exists); the engine gate below reads the same resolved
    -- id, so slots and prompts agree by construction. Idempotent: re-resolving
    -- assigns the same table.
    if is_era_guide and api.is_spell_known(409433) then
        local sod_chimera = api.get_family_spell_id(chimera_shot_sod_ids)
        if sod_chimera then
            chimera_current_id = sod_chimera
            guide_slot_chimera.spell_id = sod_chimera
            ST.HUNTER.guide.slots = guide_slots_era_sod
        end
    end
end

-- Live inputs for the pure engine, written into the caller-owned reused table. Every
-- field of the frozen input set is written on every call, so no stale value can survive
-- between ticks; nil means "the client did not answer".
--
-- The H2 Bloodlust/Heroism scan throttle (seconds): the guide gather runs every frame
-- while the guide shows, so the aura scan re-polls at this cadence (the paladin lane's
-- P3 interval) and the cached reading serves the ticks between polls.
local LUST_RESCAN_INTERVAL = 0.5

function ST.HUNTER.gather_guide_inputs(self, out)
    local inputs = out or ST.HUNTER.guide_inputs
    local now = api.get_time()
    local ranged = self.ranged

    -- The ranged cycle and the clock, in the api.get_time() domain. A client without a
    -- ranged swing (Retail) answers nothing: every field stays nil and the engine then
    -- withholds every prompt rather than guessing.
    inputs.now = now
    inputs.swing_start = ranged and ranged.start or nil
    inputs.swing_speed = ranged and ranged.speed or nil
    inputs.swing_ends_at = ranged and ranged.ends_at or nil
    inputs.synced_duration = ranged and ranged.synced_duration or nil
    inputs.auto_repeat_active = (ranged and ranged.auto_repeat_active) == true

    -- World latency only (never the twist lag calibration), the same basis the cast
    -- bar's clip tint uses.
    local latency = world_latency_seconds(self)
    inputs.latency = latency

    -- The hidden Auto-Shot window: the cached bounds the visual half last computed, or
    -- recomputed from the live cycle through the pure hunter_window maths (the same
    -- synced_duration-or-speed basis as the cast bar). nil when the client cannot
    -- provide a cycle; the engine then never holds on window grounds.
    local window_start
    local window_duration
    if ranged then
        local cached_start = ranged.hidden_window_start
        local cached_duration = ranged.hidden_window_duration
        if type(cached_start) == "number" and type(cached_duration) == "number"
            and cached_duration > 0 then
            window_start, window_duration = cached_start, cached_duration
        elseif hunter_window then
            local cycle_duration = ranged.synced_duration or ranged.speed
            if type(ranged.start) == "number" and type(cycle_duration) == "number"
                and cycle_duration > 0 then
                local start_bound, end_bound = hunter_window.hidden_window(
                    ranged.start, cycle_duration, hunter_window.cast_window(latency))
                if start_bound ~= nil then
                    window_start, window_duration = start_bound, end_bound - start_bound
                end
            end
        end
    end
    inputs.hidden_window_start = window_start
    inputs.hidden_window_duration = window_duration

    -- The on-next-swing queue state the rules read.
    inputs.raptor_strike_queued = self.raptor_strike_queued == true
    inputs.steady_shot_queued = self.steady_shot_queued == true

    -- Steady Shot's cast time from the client's spell data (base 1.5 s fallback),
    -- cached once the spell cache answers.
    if steady_cast_time == nil then
        local cast_ms = select(4, api.GetSpellInfo(
            steady_current_id or guide_slot_steady.spell_id))
        if type(cast_ms) == "number" and cast_ms > 0 then
            steady_cast_time = cast_ms / 1000
        end
    end
    inputs.steady_cast_seconds = steady_cast_time or 1.5

    -- The live cast state (a cast first, a channel second, through compat's folding
    -- wrapper). steady_remaining/steady_duration are written only while the live cast is
    -- a Steady Shot rank - the cast-live signal rule 1 keys on and the slot's swipe pair.
    -- multi_remaining is written only while the live cast is a Multi-Shot rank, so the
    -- 0.5 s Multi-Shot cast rides rule 1 instead of re-prompting itself from rule 6a.
    local cast_name, cast_spell_id, cast_start, cast_end = api.UnitCastingSpell("player")
    inputs.casting = cast_name ~= nil
    inputs.steady_remaining = nil
    inputs.steady_duration = nil
    inputs.multi_remaining = nil
    inputs.aimed_remaining = nil
    inputs.aimed_duration = nil
    inputs.sniper_remaining = nil
    inputs.sniper_duration = nil
    if cast_name ~= nil and cast_spell_id ~= nil
        and steady_shot_ids[cast_spell_id] ~= nil then
        local remaining = 0
        if type(cast_end) == "number" then
            remaining = cast_end - now
            if remaining < 0 then
                remaining = 0
            end
        end
        local cast_seconds = steady_cast_time or 1.5
        if type(cast_end) == "number" and type(cast_start) == "number"
            and cast_end > cast_start then
            cast_seconds = cast_end - cast_start
        end
        inputs.steady_remaining = remaining
        inputs.steady_duration = cast_seconds
    elseif cast_name ~= nil and cast_spell_id ~= nil
        and multi_shot_ids[cast_spell_id] ~= nil then
        local remaining = 0
        if type(cast_end) == "number" then
            remaining = cast_end - now
            if remaining < 0 then
                remaining = 0
            end
        end
        inputs.multi_remaining = remaining
    elseif is_era_guide and cast_name ~= nil and cast_spell_id ~= nil
        and aimed_shot_ids[cast_spell_id] ~= nil then
        -- Era only: a live Aimed Shot cast rides rule 1 (and feeds the aimed slot's
        -- swipe pair) instead of re-prompting itself from rule 6a. Off-Era clients
        -- never take this arm, so their live-cast behaviour is byte-identical.
        local remaining = 0
        if type(cast_end) == "number" then
            remaining = cast_end - now
            if remaining < 0 then
                remaining = 0
            end
        end
        local cast_seconds = aimed_cast_time or 3.0
        if type(cast_end) == "number" and type(cast_start) == "number"
            and cast_end > cast_start then
            cast_seconds = cast_end - cast_start
        end
        inputs.aimed_remaining = remaining
        inputs.aimed_duration = cast_seconds
    elseif is_forever_guide and cast_name ~= nil and cast_spell_id ~= nil
        and sniper_shot_ids[cast_spell_id] ~= nil then
        -- Forever only: a live Sniper Shot cast rides rule 1 (and feeds the
        -- sniper slot's swipe pair) instead of re-prompting itself from rule
        -- F2. The id table is empty until confirmed in-client, so this arm is
        -- unreachable today and every other client is byte-identical.
        local remaining = 0
        if type(cast_end) == "number" then
            remaining = cast_end - now
            if remaining < 0 then
                remaining = 0
            end
        end
        local cast_seconds = sniper_cast_time or 4.0
        if type(cast_end) == "number" and type(cast_start) == "number"
            and cast_end > cast_start then
            cast_seconds = cast_end - cast_start
        end
        inputs.sniper_remaining = remaining
        inputs.sniper_duration = cast_seconds
    end

    -- Steady Shot's cooldown, GCD echo filtered: the frozen rule input (the slot's swipe
    -- follows the live cast window instead, so this read stays a single client query).
    -- Whether the client knows Steady Shot at all: false on Era (the spell does not
    -- exist there), so rule 6c never fires and the rank-1 fallback never prompts.
    inputs.steady_known = steady_current_id ~= nil
    inputs.steady_remaining_cd = get_guide_cooldown(
        steady_current_id or guide_slot_steady.spell_id)

    -- Multi-Shot's cast time from the client's spell data (0.5 s TBC base fallback),
    -- cached once the spell cache answers (the same retry discipline as Steady Shot).
    if multi_cast_time == nil then
        local cast_ms = select(4, api.GetSpellInfo(
            multi_current_id or guide_slot_multi.spell_id))
        if type(cast_ms) == "number" and cast_ms > 0 then
            multi_cast_time = cast_ms / 1000
        end
    end
    inputs.multi_cast_seconds = multi_cast_time or 0.5

    -- TBC-only weave/cooldown prompts: every new rule carries its *_known gate, which
    -- is true only when the family token reads TBC and the client knows that spell
    -- family. All other clients gather known=false, so the engine runs exactly the old
    -- matrix there (rules 1, 2, 6b, 7, 8); the Retail swing gate stays the inertness
    -- mechanism it always was (no ranged cycle, no prompts at all).
    -- Multi-Shot weaves on Era too (rank 2643 exists there): the only gate widened
    -- beyond TBC. Steady Shot keeps no family gate at all: the known-rank gate above
    -- already silences every client without the spell.
    local is_tbc = st.family == "TBC"
    inputs.kc_known = is_tbc and kill_command_current_id ~= nil
    inputs.kc_remaining_cd = get_guide_cooldown(
        kill_command_current_id or guide_slot_kill_command.spell_id)
    inputs.bw_known = is_tbc and bestial_wrath_current_id ~= nil
    inputs.bw_remaining_cd = get_guide_cooldown(
        bestial_wrath_current_id or guide_slot_bestial_wrath.spell_id)
    inputs.rf_known = is_tbc and rapid_fire_current_id ~= nil
    inputs.rf_remaining_cd = get_guide_cooldown(
        rapid_fire_current_id or guide_slot_rapid_fire.spell_id)
    inputs.multi_known = (is_tbc or is_era_guide) and multi_current_id ~= nil
    inputs.multi_remaining_cd = get_guide_cooldown(
        multi_current_id or guide_slot_multi.spell_id)

    -- Era Aimed Shot: the primary filler (3 s cast, 6 s cooldown). Every aimed_*
    -- input is written on every call; off-Era clients gather nil/false without any
    -- client query, so their cooldown-query count and behaviour stay byte-identical
    -- (the warrior's bt/ww split). The cast time comes from the client's spell data
    -- with the 3.0 s Era base fallback, cached once the spell cache answers.
    if is_era_guide then
        if aimed_cast_time == nil then
            local cast_ms = select(4, api.GetSpellInfo(
                aimed_current_id or guide_slot_aimed.spell_id))
            if type(cast_ms) == "number" and cast_ms > 0 then
                aimed_cast_time = cast_ms / 1000
            end
        end
        inputs.aimed_cast_seconds = aimed_cast_time or 3.0
        inputs.aimed_known = aimed_current_id ~= nil
        inputs.aimed_remaining_cd = get_guide_cooldown(
            aimed_current_id or guide_slot_aimed.spell_id)
    else
        inputs.aimed_cast_seconds = nil
        inputs.aimed_known = false
        inputs.aimed_remaining_cd = nil
    end

    -- The Wrath priority inputs and the SoD Chimera weave input. Every new field
    -- is written on every call (nil/false when the rank did not resolve at
    -- post_init); an unresolved rank adds no client query at all
    -- (get_guide_cooldown(nil) is (0, nil) without a probe), so families that
    -- resolve nothing keep their exact old cooldown-query counts. The known
    -- flags are the resolve-time detectors (Wrath: Chimera learned = MM,
    -- Explosive learned = SV; SoD: the rune learned, knowledge-gated at
    -- post_init) - the gather itself spends no knowledge probe.
    inputs.killshot_known = kill_shot_current_id ~= nil
    inputs.killshot_remaining_cd = get_guide_cooldown(kill_shot_current_id)
    inputs.target_hp_frac = nil
    inputs.chimera_known = chimera_current_id ~= nil
    inputs.chimera_remaining_cd = get_guide_cooldown(chimera_current_id)
    inputs.explosive_known = explosive_current_id ~= nil
    inputs.explosive_remaining_cd = get_guide_cooldown(explosive_current_id)
    inputs.wrath_aimed_known = aimed_wrath_current_id ~= nil
    inputs.wrath_aimed_remaining_cd = get_guide_cooldown(aimed_wrath_current_id)
    inputs.arcane_known = arcane_current_id ~= nil
    inputs.arcane_remaining_cd = get_guide_cooldown(arcane_current_id)
    -- The execute read (Wrath Kill Shot only): the target's health fraction, or
    -- nil when the client cannot answer - the engine never guesses it. Read only
    -- while a Kill Shot rank is resolved, so no other client spends a probe.
    if kill_shot_current_id ~= nil then
        local hp = api.UnitHealth("target")
        local hp_max = api.UnitHealthMax("target")
        if type(hp) == "number" and type(hp_max) == "number" and hp_max > 0 then
            inputs.target_hp_frac = hp / hp_max
        end
    end

    -- The Forever upkeep/cast inputs (rules F1-F2). Every field is written on
    -- every call (nil/false when the rank did not resolve at post_init); an
    -- unresolved rank adds no client query at all (get_guide_cooldown(nil) is
    -- (0, nil) without a probe), so families that resolve nothing keep their
    -- exact old cooldown-query counts. hawk_active_count stays nil until the
    -- hawk ids - and how hawks surface in-client (aura, pet frame, other) - are
    -- confirmed: the engine never guesses the count, so the upkeep stays
    -- silent. Rule F1 is therefore NOT YET IMPLEMENTED (declared + engine-
    -- tested, but unreachable until the count source confirms - see the
    -- summon_hawk_ids note at the top of this file); Sniper Shot's cast time
    -- comes from the client's spell data with
    -- the 4.0 s Forever base fallback, cached once the spell cache answers, and
    -- is read only while a Sniper rank is resolved.
    inputs.hawk_known = hawk_current_id ~= nil
    inputs.hawk_active_count = nil
    inputs.hawk_remaining_cd = get_guide_cooldown(hawk_current_id)
    if sniper_cast_time == nil and sniper_current_id ~= nil then
        local cast_ms = select(4, api.GetSpellInfo(sniper_current_id))
        if type(cast_ms) == "number" and cast_ms > 0 then
            sniper_cast_time = cast_ms / 1000
        end
    end
    inputs.sniper_cast_seconds = sniper_cast_time or 4.0
    inputs.sniper_known = sniper_current_id ~= nil
    inputs.sniper_remaining_cd = get_guide_cooldown(sniper_current_id)

    -- H2: the Bloodlust/Heroism window through compat's frozen player-aura scan
    -- (bench/buildout_compat-bl_2026-10-17.md §2; ids 2825/32182 CONFIRMED per
    -- bench/verify_bank.md §2). While one is up the guide suppresses the Aimed and
    -- Multi-Shot weave arms (rules 6a/6b) and lets Steady Shot keep flowing as the
    -- spam cue. The scan is throttled (LUST_RESCAN_INTERVAL) because the gather runs
    -- every frame while the guide shows; the cached value is a plain remaining read,
    -- never a clock extrapolation. Era never arms (st.lust_supported is family-derived
    -- in compat.lua; the ids are data, not a probe) and an absent compat surface or
    -- aura API stays nil - nil is "no window", never zero. Closed-on-unknown (R4):
    -- only an explicit true arms the scan; nil (a pre-C2 compat) or false stays
    -- off. Every field is written on every call (the frozen input discipline).
    local lust_remaining
    if st.lust_supported == true and lust_ids
        and type(api.scan_player_aura) == "function" then
        if self.hunter_lust_at and (now - self.hunter_lust_at) < LUST_RESCAN_INTERVAL then
            lust_remaining = self.hunter_lust_remaining
        else
            self.hunter_lust_at = now
            self.hunter_lust_remaining = nil
            local remaining = api.scan_player_aura(function(spell_id)
                return lust_ids[spell_id] ~= nil
            end)
            if type(remaining) == "number" and remaining > 0 then
                self.hunter_lust_remaining = remaining
            end
            lust_remaining = self.hunter_lust_remaining
        end
    end
    inputs.lust_remaining = lust_remaining

    -- The ranged range of the Steady Shot school; nil = unknown (the engine never treats
    -- nil as out of range). One client probe, no allocation.
    inputs.target_in_range = api.IsSpellInRange(
        steady_current_id or guide_slot_steady.spell_id, "target")
    return inputs
end

ST.HUNTER.guide = {
    slots = is_era_guide and guide_slots_era
        or (is_wrath_guide and guide_slots_wrath
            or (is_forever_guide and guide_slots_forever or guide_slots_base)),

    -- Live inputs: the gather above, verbatim, into the caller's reused table.
    gather = function(self, out)
        return ST.HUNTER.gather_guide_inputs(self, out)
    end,

    -- Pure: the frozen hunter rule matrix (st.hunter_guide in hunter_guide.lua); guarded
    -- so a flavor without that module stays inert rather than erroring.
    evaluate = function(inputs, out)
        if st.hunter_guide and st.hunter_guide.evaluate then
            return st.hunter_guide.evaluate(inputs, out)
        end
        return out
    end,

    -- Static captions (defaults; the RIDE/HOLD text rides out.hold_text).
    labels = { next_action = "Next action:", hold = "HOLD", ride = "RIDE" },
}

--=========================================================================================
-- Cooldown HUD: hunter slots and the live state provider
--=========================================================================================
-- The slot set mirrors the Next Action Guide's base six slots (ST.HUNTER.guide above:
-- the class's TBC top-parse abilities), plus the Era guide's Aimed Shot filler and
-- the two trinket slots the HUD serves itself.
-- The descriptor and provider contracts are frozen in hud.lua's header comment; the
-- "trinket" slots need no provider entry.
--
-- Rank notes: the rank-1 ids ship as the icon fallback (the spell art is
-- rank-invariant), while the provider reads cooldowns by the client's own localized
-- name (hud_slot_name), so whatever rank the player knows is what is counted - the
-- paladin's cooldown_spell-free convention from classes/paladin.lua. Kill Command
-- (34026) is UNCONFIRMED: the id is sourced from out-of-client references, not from
-- a 2.5.6 spell-cache read (see the kill_command_ids note at the top of this file).
-- Steady Shot and Raptor Strike have no cooldown of their own on the classic line:
-- their slots show the running GCD swipe plus the mana/range tints.
-- Aimed Shot slot semantics: the descriptor ships the rank-1 id (19434, the same
-- fallback the guide's aimed slot carries); resolve_guide_icons re-points it at the
-- client's current rank through api.get_family_spell_id(aimed_shot_ids), and the
-- provider's name-based read counts whatever rank the player knows. Aimed Shot
-- carries a real 6 s cooldown only on Era (the guide's aimed_remaining_cd input);
-- on every other client the API reports no cooldown and the slot shows the running
-- GCD swipe plus the mana/range tints, exactly like Steady Shot and Raptor Strike.
-- The guide's cast-time display (the 3 s Era cast riding rule 1) has no HUD mirror:
-- the HUD tracks cooldowns, never live casts.
ST.HUNTER.HUD_SLOTS = {
    { key = "steady", title = "Steady Shot", kind = "spell", spell = 56641 },
    { key = "raptor", title = "Raptor Strike", kind = "spell", spell = 2973 },
    { key = "kill_command", title = "Kill Command", kind = "spell", spell = 34026 },
    { key = "multi", title = "Multi-Shot", kind = "spell", spell = 2643 },
    { key = "bestial_wrath", title = "Bestial Wrath", kind = "spell", spell = 19574 },
    { key = "rapid_fire", title = "Rapid Fire", kind = "spell", spell = 3045 },
    { key = "aimed", title = "Aimed Shot", kind = "spell", spell = 19434 },
    { key = "trinket1", title = "Trinket 1", kind = "trinket", inv_slot = 13 },
    { key = "trinket2", title = "Trinket 2", kind = "trinket", inv_slot = 14 },
}

-- One reused state table: the HUD reads it immediately and never keeps a reference
-- (see the frozen contract in hud.lua), so there is no per-tick allocation here.
ST.HUNTER.hud_state = {}

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
-- cooldown of its own (TBC values; NEEDS IN-CLIENT CONFIRMATION on 2.5.6 - the
-- swipe length only matters while a real cooldown is running, which always carries
-- the client-reported length instead). Steady Shot / Raptor Strike carry 0: they
-- have no cooldown to show, only the GCD swipe. Aimed Shot carries the Era 6 s
-- cooldown (see the slot semantics note above); off-Era clients report no cooldown,
-- so the slot shows the GCD swipe there.
local HUD_COOLDOWN_FALLBACK = {
    steady = 0,
    raptor = 0,
    kill_command = 60,
    multi = 10,
    bestial_wrath = 120,
    rapid_fire = 300,
    aimed = 6,
}

-- Slots that never borrow the GCD swipe (the paladin's judgement/wings rule in
-- classes/paladin.lua): the multi-minute pops. Everything rotational shows the
-- running GCD while ready.
local HUD_SKIP_GCD = {
    bestial_wrath = true,
    rapid_fire = true,
}

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

-- Remaining time and full duration of one hunter ability cooldown: the client's own
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
-- mapping (hud.lua:418-453) re-expressed for the hunter slots. Kill Command glows
-- the moment it is ready, in combat (the paladin's Avenging Wrath rule).
function ST.HUNTER.get_hud_state(self, slot, now)
    local s = ST.HUNTER.hud_state
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

    if slot.key == "kill_command" then
        s.glow = (remaining <= 0 and self.in_combat == true) or false
    end
    return s
end

--=========================================================================================
-- Rotation text: the hunter rotation source
--=========================================================================================
-- Implements the frozen ST.<CLASS>.get_rotation_key contract documented in
-- rotationtext.lua's header, following the paladin's shape (ST.PALADIN.
-- get_rotation_key in rotationtext.lua): the guide's own decision, so the label and
-- the guide can never disagree. The hunter engine names no rotations (its
-- out.rotation_key is always nil), so the label is the current action: the
-- recommended ability's localized name (resolved from the guide's own slot
-- descriptors, cached per spell id), HOLD while the engine holds, RIDE while it
-- rides, nil when the guide is idle (renders as the empty text). No practice
-- branch: Twist Practice is paladin-only (no simulation exists for this class).
-- One reused output table: no per-tick allocation on the label tick.
ST.HUNTER.rotation_out = {}

-- The guide slot's localized spell name for an action key (the slot's current-rank
-- spell id, so a re-pointed icon re-points the label with it). Falls back to the
-- raw action key when the client's spell data has not answered yet.
local rotation_name_cache = {}

local function rotation_ability_name(action)
    local spell_id
    local slots = ST.HUNTER.guide.slots
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

function ST.HUNTER.get_rotation_key(self)
    local guide = ST.HUNTER.guide
    local engine = st.hunter_guide
    if not (guide and guide.gather and guide.evaluate and engine and engine.evaluate) then
        return nil
    end
    local out = guide.evaluate(guide.gather(self, ST.HUNTER.guide_inputs),
        ST.HUNTER.rotation_out)
    if out.action ~= nil then
        return rotation_ability_name(out.action)
    end
    if out.hold then
        return out.hold_text
    end
    return nil
end

if st.debug then st.utils.print_msg('-- Parsed classes/hunter.lua module correctly') end

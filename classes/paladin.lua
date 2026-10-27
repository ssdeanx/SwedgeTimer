--=========================================================================================
-- Module for Paladin-specific behaviours
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
st.class_loaders = st.class_loaders or {}
st.class_loaders["PALADIN"] = function()
local LCG = LibStub("LibCustomGlow-1.0")
local LSM = LibStub("LibSharedMedia-3.0")
-- Cross-client API wrappers (see compat.lua).
local api = st.api
local get_tab = st.utils.convert_lookup_table

-- See compat.lua: restricted (secret) reads must degrade, never error. Exact no-op
-- where the probe is absent (classic clients).
local is_secret = issecretvalue or function()
    return false
end

--=========================================================================================
-- LibClassicDurations (next-action guide swipe durations)
--=========================================================================================
-- The library is Classic Era / TBC Anniversary ONLY: LibClassicDurations/core.lua line 20
-- returns before it creates the library unless WOW_PROJECT_ID is WOW_PROJECT_CLASSIC or
-- WOW_PROJECT_BURNING_CRUSADE_CLASSIC, so on WotLK, Titanforge, Cata, Mists, Retail and
-- WoW Forever the silent LibStub form below yields nil. That is why it is always fetched
-- silently and why no behaviour may depend on it existing: every duration it supplies has
-- a hardcoded fallback (SEAL_FALLBACK_DURATION below, the display constants in
-- nextaction_ui.lua for the spell cooldowns).
-- It is also combat-log driven, so it has its own failure modes even where it loads: it
-- only knows an aura once it has seen the application (nothing is tracked before the first
-- combat-log event after Register, and a seal that is up at login stays unknown until it
-- is re-cast), it returns nil for any aura missing from its spell table (Seal of Blood /
-- Seal of the Martyr are not in it), and the durations it reports are 30 s for the seals
-- it does know. Untracked -> nil -> the fallback, on every family.
local LCD = LibStub("LibClassicDurations", true)
local lcd_aura_duration = LCD and LCD.GetAuraDurationByUnit

-- Vanilla/TBC seal duration: the archived build's own fallback
-- (docs/swedge/SwedgeTimer_TBC/player.lua seal_1_duration / seal_2_duration).
local SEAL_FALLBACK_DURATION = 30

-- Length of a tracked aura in seconds, or nil when the library is absent, has not tracked
-- the aura, or reports something unusable. Method cached at load; no per-call allocation
-- and no string work (the aura name comes from the aura loop, not from a lookup).
local function get_tracked_aura_duration(unit, spell_id, spell_name)
    if not lcd_aura_duration then
        return nil
    end
    -- pcall because the library is vendored code on a client family this addon only
    -- supports indirectly: a failure here must degrade to the fallback, never error.
    local ok, duration = pcall(lcd_aura_duration, LCD, unit, spell_id, nil, spell_name)
    if not ok or type(duration) ~= "number" or duration <= 0
        or duration > SEAL_FALLBACK_DURATION * 2 then
        -- The upper bound rejects a nonsense length (no seal is longer than an hour);
        -- the caller then falls back to SEAL_FALLBACK_DURATION.
        return nil
    end
    return duration
end

-- The counter of failed LibClassicDurations registrations (BS-8 item 1): a
-- failure used to be invisible, because the pcall result was dropped. The
-- shared engine's runtime-diag line reads this number (main.lua's
-- print_runtime_diag); the class side only counts, so the counter is correct
-- and harmless even before that reader exists.
ST.PALADIN.lcd_register_errors = ST.PALADIN.lcd_register_errors or 0

--=========================================================================================
-- Spell data
--=========================================================================================
-- Seals: every rank id per classic family, because the active aura keeps the id of the
-- rank that was cast. On Wrath the seals were consolidated to a single rank which is
-- contained in each list, so Wrath behaviour is unchanged. Rank data per the archived
-- TBC/Forever builds.
local soc_ids = get_tab({
    20375, 20915, 20918, 20919, 20920, 27170
})
local sov_ids = get_tab({
    31801, 348704
})
local sol_ids = get_tab({
    20165, 20347, 20348, 20349, 27160
})
local sow_ids = get_tab({
    20166, 20356, 20357, 27166
})
local sor_ids = get_tab({
    21084, 20154, 20287, 20288, 20289, 20290, 20291, 20292, 20293, 27155
})
-- Seal of Righteousness on Forever (Twist of Light twist seal): UNCONFIRMED,
-- and still deliberately EMPTY - no source names an id for THIS spell (the
-- Echo ids below are a different spell, and the discipline that resolves them
-- by name does not apply to a rank that has no id at all). The beta guides
-- name the seal but publish no spell id, so this table is
-- deliberately EMPTY until GetSpellInfo confirms an id in-client (the hunter
-- Summon Hawk / Sniper Shot discipline: an empty table resolves nothing, so
-- the latch below stays inert rather than guessing). The classic sor_ids
-- above still latch 21084 on Forever; if Forever's Righteousness carries a
-- new id, has_sor stays down until that id is confirmed into this table.
-- Plug-in point: add the confirmed Forever rank id(s) here.
local sor_forever_ids = get_tab({
})
-- Twist of Light Echo auras (Forever): the ids are WEB-CONFIRMED but
-- CLIENT-UNCONFIRMED (bench/ids_research_2026-10-19.md §2 - wowhead's own
-- redirect slugs: 1311703 Echo of Command, 1311704 Echo of Righteousness).
-- Standing: web-confirmed, client-unconfirmed, name-resolved. The ids are
-- NOT trusted to identify a spell on this client, so the discipline below
-- resolves the NAME first (through the class's own name-resolution path) and
-- lets the id only confirm it: a wrong id can then never latch the wrong
-- aura, and the seal inputs keep their archived values. The 1.60.x client has
-- not been asked yet (the operator's session owns that check), so an id the
-- client does not name leaves the latch unknown rather than guessing.
local echo_command_ids = get_tab({
    1311703,
})
local echo_twist_ids = get_tab({
    1311704,
})
-- Holy Strike (Forever): the same discipline - WEB-CONFIRMED 10333,
-- CLIENT-UNCONFIRMED (bench/ids_research_2026-10-19.md §2: "Holy Strike
-- (50% + 97-121 Holy)"). It is a spell, not an aura, so the resolved id is
-- asked about in the spell book. The frozen ten guide slots have no Holy
-- Strike slot, so the probe is a plug-in point (nextaction.lua's Forever
-- block documents it) and nothing prompts yet.
local holy_strike_ids = get_tab({
    10333,
})
local soj_ids = get_tab({
    20164, 31895
})
-- Seal of Blood / Seal of the Martyr
local sob_ids = get_tab({
    31892, 348700,
    -- 407798 Seal of Martyrdom aura (bench/sod_paladin_variants_2026-10-19.md
    -- §0/§3, p8-stack APL prepull SoM; warcraftdb title "Seal of Martyrdom";
    -- APL-cited, in-client UNCONFIRMED). 348700 above is the Martyr rune probe
    -- the SoD detector already uses; 407798 is the seal aura the stack
    -- maintenance times. Era-only in practice (no Era-base spell carries it),
    -- so no other family changes.
    407798,
})
-- Seal of the Crusader
local sotc_ids = get_tab({
    21082, 20162, 20305, 20306, 20307, 20308, 27158
})

-- Era twist seal: on the Era family the engine's twist-seal ("sob") position is
-- Seal of Righteousness — Seal of Blood does not exist on Era. 21084 is its
-- rank-1 id (archived docs/swedge/SwedgeTimer_TBC/st_data.lua:74). Every other
-- family keeps the Blood id, so nothing changes outside the Era family.
-- Computed once at load (compat.lua runs before the class modules, and every
-- offline harness loads it first too).
local ERA_TWIST_SEAL_ID = 21084
local is_era_family = st.family == "ERA"
local is_tbc_family = st.family == "TBC"
local twist_seal_icon_id = is_era_family and ERA_TWIST_SEAL_ID or 31892

-- Name-vs-id rule (operator 2026-10-19 for TBC, 2026-10-25 for Titanforge; each
-- family gated on its own): TBC Anniversary and Wrath/Titanforge prefer the NAME for
-- state queries; Classic Era (SoD included) resolves by id and Forever keeps the id.
-- The id FALLBACK is operator-approved ("i never banned fallback to ids") and stays:
-- name first, then the id. Branch on st.family, never a version string. Names resolve
-- once per id through the client's own GetSpellInfo and are cached (a rank's name
-- never changes); cold spell data retries on the next call. Queries go through
-- compat's api.get_spell_query (inline family branch as fallback so the module never
-- depends on load order); a cold name degrades to the id query instead of nil.
local tbc_spell_names = {}

local function resolve_spell_name(spell_id)
    if type(spell_id) ~= "number" then
        return nil
    end
    local cached = tbc_spell_names[spell_id]
    if cached ~= nil then
        return cached
    end
    local name = api.GetSpellInfo(spell_id)
    if type(name) == "string" then
        tbc_spell_names[spell_id] = name
    end
    return name
end

local function spell_query(spell_id)
    if st.family ~= "TBC" and st.family ~= "WRATH" then
        return spell_id
    end
    if type(spell_id) == "string" then
        -- Already a name token (a caller that resolved its own localized name).
        return spell_id
    end
    local name = resolve_spell_name(spell_id)
    if type(api.get_spell_query) == "function" then
        return api.get_spell_query(name, spell_id) or spell_id
    end
    return name or spell_id
end

-- Known-spell probe through the family-correct query (the rogue
-- api.is_spell_known(rogue_query(...)) discipline): the name first on TBC and
-- Wrath/Titanforge with the id fallback (operator-approved), the numeric id
-- elsewhere; a cold name-family book probes the id instead of nil.
local function is_spell_known_query(spell_id)
    return api.is_spell_known(spell_query(spell_id)) == true
end

--=========================================================================================
-- The Forever id discipline: the NAME is the key, the id only confirms it
--=========================================================================================
-- A spell id that only a web page confirms (the tables above) cannot be
-- trusted to identify a spell on this client: latch the wrong aura and the
-- guide prompts the wrong thing. The discipline inverts that trust.
--
--   confirmed_forever_id(ids, expected_name)
--     The confirmed id whose OWN client-resolved name is the expected name.
--     The client's answer comes from the class's existing name-resolution path
--     (resolve_spell_name: api.GetSpellInfo on the id - the same path the TBC
--     name boxes and the Bloodlust labels use), so an id is only trusted when
--     the client itself agrees that it IS that spell.
--
--     nil when the client cannot name the id yet (a cold book, or a client
--     that answers names only) and nil when the id is WRONG (the client
--     answers a different spell's name). A wrong id therefore leaves every
--     state UNKNOWN - never a wrong prompt. The operator's in-client check
--     (the 1.60.x GetSpellInfo) is what turns a web-confirmed id into a
--     client-confirmed one.
--
-- The anchors are the web-confirmed English names (wowhead's redirect slugs).
-- They are compared verbatim, so a non-English client stays unknown until its
-- localized names are added here (unknown-hides, never wrong).
local ECHO_COMMAND_NAME = "Echo of Command"
local ECHO_TWIST_NAME = "Echo of Righteousness"
local HOLY_STRIKE_NAME = "Holy Strike"

local function confirmed_forever_id(ids, expected_name)
    for id in pairs(ids) do
        if resolve_spell_name(id) == expected_name then
            return id
        end
    end
    return nil
end

-- Aura-rank match: the numeric id everywhere (Era's only path; TBC's cold
-- fallback, so smoke.lua's id-only TBC profile keeps passing), plus the
-- localized name on the TBC family. `box` caches the id table's localized
-- names (nil until the first answer; cold spell data retries on the next
-- scan, so a cold book reads as id-only, never as a wrong match).
local function aura_matches(ids, box, spell_id, name)
    if type(spell_id) == "number" and ids[spell_id] then
        return true
    end
    if st.family == "TBC" and type(name) == "string" then
        local set = box.set
        if set == nil then
            set = {}
            local any = false
            for id in pairs(ids) do
                local resolved = resolve_spell_name(id)
                if resolved ~= nil then
                    set[resolved] = true
                    any = true
                end
            end
            if any then
                box.set = set
            else
                return false
            end
        end
        return set[name] == true
    end
    return false
end

-- Localized-name boxes for the TBC aura matches below (one box per rank
-- table, so each set resolves independently).
local seal_name_boxes = {
    soc = {}, sov = {}, sol = {}, sow = {},
    sor = {}, soj = {}, sob = {}, sotc = {},
}
local jotc_name_box = {}

-- Forever family flag + guide twist-seal id (WoW Forever / Camelot 1.60.x):
-- Twist of Light alternates Seal of Command / Seal of Righteousness after
-- auto attacks and Judgement no longer consumes seals
-- (docs/research/forever_beta.md — beta information whose spell ids are now
-- WEB-CONFIRMED but still CLIENT-UNCONFIRMED: the Echo auras and Holy
-- Strike are resolved by NAME through the discipline above, so they can
-- never prompt on a wrong id). The guide's twist-seal slot and twist overlay
-- show Righteousness on Forever (same slot, same key, Era texture); the
-- standalone seal icons above stay Era-only (their Forever mapping is
-- unverified).
local is_forever_family = st.family == "FOREVER"
local guide_twist_seal_id = (is_era_family or is_forever_family) and ERA_TWIST_SEAL_ID or 31892

-- Wrath FCFS display (family WRATH only): no seal twisting exists there, so the
-- twist-seal guide slot ("sob") carries Divine Storm and the execute slot ("how")
-- carries Holy Wrath instead. Slot KEYS, order, count and display fields are
-- frozen (the contract pins eight); only the texture-source ids move, and only on
-- Wrath. The rank-1 fallbacks below paint the icons until post_init repoints them
-- at the resolved ranks (confirm both ids in-client).
local is_wrath_family = st.family == "WRATH"
local WRATH_DS_ICON_FALLBACK = 53385
local WRATH_HW_ICON_FALLBACK = 48817
local guide_sob_spell_id = is_wrath_family and WRATH_DS_ICON_FALLBACK or guide_twist_seal_id
local guide_how_spell_id = is_wrath_family and WRATH_HW_ICON_FALLBACK or 24275

-- Art of War (WotLK proc)
local aow_id = 59578

-- Exorcism, all ranks.
local exorcism_ids = get_tab({
    879, 5614, 5615, 10312, 10313, 10314, 27138, 48800, 48801
})

-- Exorcism SUCCEEDED matcher: id primary, name secondary on every family (the
-- hunter R1 discipline). Exorcism is an instant, so SUCCEEDED is its only
-- event; a name-carrying Anniversary payload (the name riding the guid slot
-- with a nil id, per compat.lua) must arm the cooldown latch exactly like the
-- numeric id does. The literal English name ("Exorcism", the HUD slot title
-- and the APL's own tbc_name) always matches; the client's own localized
-- names cover the other locales once the spell data answers. A cold cache
-- reads nil and retries next event (rare event-path calls, never per-frame).
local EXORCISM_NAME = "Exorcism"
local exorcism_cast_names
local function is_exorcism_token(token)
    if token == nil then
        return false
    end
    if exorcism_ids[token] ~= nil then
        return true
    end
    if type(token) ~= "string" then
        return false
    end
    if token == EXORCISM_NAME then
        return true
    end
    if exorcism_cast_names == nil then
        local names = {}
        for spell_id in pairs(exorcism_ids) do
            local name = api.GetSpellInfo(spell_id)
            if type(name) == "string" then
                names[name] = true
            end
        end
        if next(names) == nil then
            return false
        end
        exorcism_cast_names = names
    end
    return exorcism_cast_names[token] == true
end

function ST.PALADIN.post_init(self)
    self.exo_on_cooldown = false
    local exo_base = api.GetSpellBaseCooldown(879) / 1000
    -- Mainline-code clients have no GetSpellBaseCooldown (compat degrades to 0); without
    -- the fallback require_exo_ready would report Exorcism always ready on Forever.
    self.exo_cooldown_time = (type(exo_base) == "number" and exo_base > 0) and exo_base or 15
    -- Twist state (port of the archived build's player.lua state fields).
    self.twist_attempt_pending = false
    self.twist_impossible = false
    self.twist_sound_played = false
    self.twist_glow_until = 0
    self.twist_extra_attacks_pending = 0
    self.twist_active_seals_count = 0
    -- Last Command-proc stamp (PPM/ICD attempt discipline: a swing inside the
    -- ICD arms no attempt) and last-auto stamp (swing-recency inputs), both
    -- combat-scoped (reset on combat exit); nil until the first landing.
    self.twist_last_proc_at = nil
    self.guide_last_auto_at = nil
    -- Pull-phase clock (TBC CS hold): combat-start stamp plus the transition
    -- latch that arms it; both combat-scoped like the guide latch below.
    self.guide_combat_start_at = nil
    self.guide_was_in_combat = false

    -- Twist hit-rate counters: per-session by default (reset on every load);
    -- with the persistence option the counters are restored from (and mirrored
    -- back to) the class profile so they survive relogs.
    local score_db = self:get_class_table()
    if score_db.twist_score_persist == true then
        self.twist_score_attempts = type(score_db.twist_score_attempts) == "number"
            and score_db.twist_score_attempts or 0
        self.twist_score_successes = type(score_db.twist_score_successes) == "number"
            and score_db.twist_score_successes or 0
    else
        self.twist_score_attempts = 0
        self.twist_score_successes = 0
    end

    -- AoW+Exorcism overlap pulse state: the latch starts false so the first
    -- ready overlap is a false->true transition, and no pulse runs at boot.
    self.aow_exo_prev = false
    self.aow_exo_pulse_until = 0

    -- Judgement of the Crusader mini-bar state: nothing tracked until a debuff
    -- scan or a melee refresh lands one; cleared again on combat exit.
    self.jotc_tracked = false
    self.jotc_expires = nil
    self.jotc_id = nil
    self.jotc_full = nil
    self.jotc_scan_at = nil

    -- Holy Strike (Forever): unknown until the client proves the id (the
    -- discipline above) and the spell book answers. The scan below fills it
    -- in; the field exists from the start so a caller never reads a stale
    -- value from a previous session.
    self.holy_strike_known = nil

    -- Parse auras after the state above so the seal count sticks.
    self.PALADIN.on_aura_change(self)

    -- Twist window band and success text (the visuals frames exist by now).
    self.PALADIN.setup_twist_visuals(self)

    -- Next Action Guide (rotation prompt): builds its own UIParent frame and needs
    -- the pure st.nextaction engine module; guarded so a flavor without the guide
    -- files stays inert. The FCFS slot textures resolve first (above), so the
    -- frame builds its icons from the final ids.
    ST.PALADIN.resolve_guide_icons()
    if st.nextaction_ui then
        st.nextaction_ui.init(self)
    end

    -- LibClassicDurations: registering is what makes it track auras (it hooks
    -- COMBAT_LOG_EVENT_UNFILTERED on its own frame), and without it every
    -- GetAuraDurationByUnit read returns nil. Done here rather than at file load so it
    -- runs after login (post_init waits for the swing-engine / range libraries, so a seal
    -- applied before that simply is not tracked yet and the guide uses its constant until
    -- the first tracked application) and so a paladin-only addon never turns it on for
    -- other classes' clients. No-op off Classic Era / TBC Anniversary, where the library
    -- never registered itself (see the header block). pcall keeps a library-side failure
    -- from breaking post_init: the guide then keeps using its hardcoded seal duration.
    if lcd_aura_duration and type(LCD.Register) == "function" then
        -- A failed registration was invisible: the pcall result was dropped, so the
        -- guide silently fell back to its hardcoded seal length. Count the
        -- failure (ST.PALADIN.lcd_register_errors) so the shared engine's
        -- runtime-diag line can show it - the reader is main.lua's
        -- print_runtime_diag, which the engine lane owns. The count is the
        -- half that belongs here; a healthy registration counts nothing.
        local registered = pcall(LCD.Register, LCD, addon_name)
        if not registered then
            ST.PALADIN.lcd_register_errors = (ST.PALADIN.lcd_register_errors or 0) + 1
        end
    end

    -- Cooldown HUD: builds its own UIParent frames (out of combat, deferred and
    -- retried via the per-frame hook under lockdown) from this class's HUD_SLOTS and
    -- the provider below; guarded so a flavor without hud.lua stays inert. Other
    -- classes would call st.hud.init(self) from their own post_init the same way.
    -- Runs before the practice init below: the shared post_init order is guide,
    -- HUD, practice in all six class modules (deep-audit F9).
    if st.hud then
        st.hud.init(self)
    end

    -- Twist Practice: builds its own UIParent frames and the pure-engine bridge;
    -- guarded so a flavor without the practice files stays inert.
    if st.practice_ui and type(st.practice_ui.init) == "function" then
        -- The practice panel's action vocabulary: the class's own guide slots plus
        -- the common abilities (a heal, a shield, food). The guide frame above
        -- already built its icons from the display vocabulary, so this widens the
        -- PANEL's strip, not the frame (the shaman's apply_family_slots precedent).
        ST.PALADIN.apply_practice_panel_actions()
        st.practice_ui.init(self)
    end
end

function ST.PALADIN.on_spellcast_succeeded(self, unit_target, cast_guid, spell_id)
    -- Track exo casts (id primary, name secondary: a name-carrying Anniversary
    -- payload carries the name where the id is absent).
    local token = spell_id
    if token == nil then
        token = cast_guid
    end
    if is_exorcism_token(token) then
        self.exo_on_cooldown = true
        self.PALADIN.process_aow(self)
        C_Timer.After(self.exo_cooldown_time, function()
            self.exo_on_cooldown = false
            self.PALADIN.process_aow(self)
        end)
    end
end


--=========================================================================================
-- Twist Practice: seal-state mirror for the simulation
--=========================================================================================
function ST.PALADIN.practice_sync(self)
    -- Replaces the aura-derived seal state with the practice simulation's state while a
    -- session runs (practice_ui's bridge calls this; parse_seals branches into it too).
    -- The sim seals never expire on their own as far as the guide is concerned, so no
    -- expiry input is provided; every other seal flag belongs to the real auras and is
    -- cleared so stale state cannot leak into the practice display.
    local sim = st.practice_ui and st.practice_ui.sim
    if not sim then
        return self.twist_active_seals_count or 0
    end
    self.has_soc = sim.active_seals["command"] == true
    self.has_sob = sim.active_seals["blood"] == true
    self.has_sor = sim.active_seals["crusader"] == true
    self.has_sov = false
    self.has_sol = false
    self.has_sow = false
    self.has_soj = false
    self.has_sotc = false
    self.has_aow = false
    self.soc_expires = nil
    self.sob_expires = nil
    self.sor_expires = nil
    self.twist_active_seals_count = sim.n_active_seals or 0
    return self.twist_active_seals_count
end

function ST.PALADIN.parse_seals(self)
    -- Refresh seal and Art of War flags from the player's auras; returns the
    -- active-seal count. Shared by on_aura_change and the twist swing path
    -- (which must not restart the AoW glow on every swing).
    -- While a Twist Practice session runs the simulation owns the seal state, so the
    -- real auras must not clobber it.
    if st.practice_ui and st.practice_ui.is_active() then
        return self.PALADIN.practice_sync(self)
    end
    self.has_aow = false
    self.has_soc = false
    self.has_sov = false
    self.has_sol = false
    self.has_sow = false
    self.has_sor = false
    self.has_soj = false
    self.has_sob = false
    self.has_sotc = false
    -- Seal expiry timestamps in seconds (next-action guide seal input). Reset so a
    -- dropped seal cannot leave a stale value behind. sor_* backs the
    -- twist-seal swipe on Era (Righteousness there; see is_era_family above).
    self.soc_expires = nil
    self.sob_expires = nil
    self.sor_expires = nil
    -- Swipe lengths for the guide's seal icons, from LibClassicDurations where that
    -- library exists and tracks the aura (Classic Era / TBC Anniversary only), else nil
    -- so the guide falls back to its own constant. Reset with the expiries for the same
    -- reason: they describe the same aura, so neither may outlive it.
    self.soc_duration = nil
    self.sob_duration = nil
    self.sor_duration = nil
    -- SoD variant aura latches (bench/sod_paladin_variants_2026-10-19.md §7;
    -- all APL-cited, in-client UNCONFIRMED). ERA-gated + rune/item-gated in the
    -- gather (never client-version per lessons); nil elsewhere so every other
    -- family keeps the archived behaviour bit-identically. Reset with the
    -- seals for the same stale-value reason.
    self.has_sunlight = nil
    self.sunlight_expires = nil
    self.has_templar_stack = nil
    self.templar_stack_expires = nil
    self.has_templar_wrath = nil
    self.templar_wrath_expires = nil
    self.holy_power_stacks = nil
    self.has_hp_set = nil
    self.has_sod_t2 = nil
    self.has_sod_naxx = nil
    self.has_sod_libram = nil
    -- Twist of Light Echo latches (Forever seal maintenance): the state stays
    -- UNKNOWN (nil) until the client itself proves the id - its own answer
    -- for the confirmed id is the expected name (the discipline above). Only
    -- a proven id lets an absent aura read as down (false); a wrong or
    -- unproven id leaves the state unknown, so the seal inputs keep their
    -- archived values and the guide never prompts a wrong reseal.
    local echo_command_id = confirmed_forever_id(echo_command_ids, ECHO_COMMAND_NAME)
    local echo_twist_id = confirmed_forever_id(echo_twist_ids, ECHO_TWIST_NAME)
    if echo_command_id ~= nil then
        self.has_echo_command = false
    else
        self.has_echo_command = nil
    end
    if echo_twist_id ~= nil then
        self.has_echo_twist = false
    else
        self.has_echo_twist = nil
    end
    -- Holy Strike (Forever): the same discipline, but a spell rather than an
    -- aura - the proven id is asked about in the spell book. nil (unknown)
    -- until the client proves the id; then the book's own answer.
    local holy_strike_id = confirmed_forever_id(holy_strike_ids, HOLY_STRIKE_NAME)
    if holy_strike_id ~= nil then
        self.holy_strike_known = api.is_spell_known(spell_query(holy_strike_id)) == true
    else
        self.holy_strike_known = nil
    end

    -- Iterate all player auras (1..40, no early break: a secret entry degrades to
    -- absent in the wrapper, and breaking there would hide every seal above a
    -- restricted row; nil is simply no match at this index).
    local i = 1
    while i <= 40 do
        local name, _, aura_count, _, _, expiration_time, _, _, _, spell_id = api.UnitAura("player", i)
        if name ~= nil then
            -- Seals
            if aura_matches(soc_ids, seal_name_boxes.soc, spell_id, name) then
                self.has_soc = true
                self.soc_expires = expiration_time
                -- The library keys its records by the rank that was cast, which is the aura
                -- id right here (the same reason soc_ids carries every rank).
                self.soc_duration = get_tracked_aura_duration("player", spell_id, name)
            end
            if aura_matches(sov_ids, seal_name_boxes.sov, spell_id, name) then
                self.has_sov = true
            end
            if aura_matches(sol_ids, seal_name_boxes.sol, spell_id, name) then
                self.has_sol = true
            end
            if aura_matches(sow_ids, seal_name_boxes.sow, spell_id, name) then
                self.has_sow = true
            end
            -- Forever's own Righteousness ranks (empty until confirmed, see above)
            -- latch the same flag, so a new Forever id degrades to silent rather
            -- than latching the wrong seal. Gated on the family so every other
            -- family ignores the table entirely.
            if aura_matches(sor_ids, seal_name_boxes.sor, spell_id, name)
                or (is_forever_family and sor_forever_ids[spell_id] ~= nil) then
                self.has_sor = true
                self.sor_expires = expiration_time
                -- Same rank-keyed lookup as Command above (sor_ids carries every rank).
                self.sor_duration = get_tracked_aura_duration("player", spell_id, name)
            end
            if aura_matches(soj_ids, seal_name_boxes.soj, spell_id, name) then
                self.has_soj = true
            end
            if aura_matches(sob_ids, seal_name_boxes.sob, spell_id, name) then
                self.has_sob = true
                self.sob_expires = expiration_time
                self.sob_duration = get_tracked_aura_duration("player", spell_id, name)
            end
            if aura_matches(sotc_ids, seal_name_boxes.sotc, spell_id, name) then
                self.has_sotc = true
            end

            -- Forever Echo maintenance (the discipline above): the NAME is the
            -- key - the aura must carry the name the client gives the proven
            -- id. The id alone never latches anything, so a wrong id cannot
            -- produce a wrong prompt. Latches only; never degrades another
            -- seal.
            if echo_command_id ~= nil and spell_id == echo_command_id
                and name == ECHO_COMMAND_NAME then
                self.has_echo_command = true
            end
            if echo_twist_id ~= nil and spell_id == echo_twist_id
                and name == ECHO_TWIST_NAME then
                self.has_echo_twist = true
            end

            -- Art of War
            if spell_id == aow_id then
                self.has_aow = true
            end

            -- SoD variant auras (ERA-gated: no Era-base spell carries these
            -- ids, so no other family changes; APL-cited, in-client
            -- UNCONFIRMED per the bench file).
            if is_era_family then
                -- Sunlight maintenance aura (1239543, shockadin §4).
                if spell_id == 1239543 then
                    self.has_sunlight = true
                    self.sunlight_expires = expiration_time
                end
                -- Templar-stack maintenance aura (1240574, shockadin §4).
                if spell_id == 1240574 then
                    self.has_templar_stack = true
                    self.templar_stack_expires = expiration_time
                end
                -- Templar wait aura (1226464, wrath-like §6).
                if spell_id == 1226464 then
                    self.has_templar_wrath = true
                    self.templar_wrath_expires = expiration_time
                end
                -- Holy Power stacks (1226461, count 1-3) + set aura (1226460).
                if spell_id == 1226461 then
                    if type(aura_count) == "number" and aura_count == aura_count then
                        self.holy_power_stacks = aura_count
                    end
                end
                if spell_id == 1226460 then
                    self.has_hp_set = true
                end
                -- S03 T2 Ret 2P Bonus (467518, wrath Judge gate, §6).
                if spell_id == 467518 then
                    self.has_sod_t2 = true
                end
                -- Naxx Ret 6P Bonus (1219193, stack HW gate, §3).
                if spell_id == 1219193 then
                    self.has_sod_naxx = true
                end
                -- Libram of Sanctity (1214298, shock AM gate, §4).
                if spell_id == 1214298 then
                    self.has_sod_libram = true
                end
            end
        end

        i = i + 1
    end

    -- Count active seals (twist attempts need 2 simultaneously active).
    local count = 0
    if self.has_soc then count = count + 1 end
    if self.has_sov then count = count + 1 end
    if self.has_sol then count = count + 1 end
    if self.has_sow then count = count + 1 end
    if self.has_sor then count = count + 1 end
    if self.has_soj then count = count + 1 end
    if self.has_sob then count = count + 1 end
    if self.has_sotc then count = count + 1 end
    self.twist_active_seals_count = count
    return count
end

function ST.PALADIN.on_aura_change(self)
    self.PALADIN.parse_seals(self)
    -- Finally set the bar color
    self:set_bar_color("mainhand")
end

-- AoW + Exorcism overlap pulse: a one-shot gold Pixel glow on the mainhand bar,
-- fired once on each false->true transition of "Art of War up AND its Exorcism
-- is castable" (the shape process_aow computes for the AoW glow already). The
-- enable is its own option, nil = off (the option pass lands the key); the key,
-- the colour, the parameters and the 0.4 s length are constants so the pulse
-- coexists with the AoW glow and the twist-success glow on the same frame.
-- The pulse's own parameters ride the module table, not file-scope locals: this
-- module sits at the Lua 5.1 ceiling for file-scope locals (200), so a new
-- constant here would be a LOAD FAILURE on every client. The class's own
-- precedent: APL_UTILITY, practice_action_meta, practice_apl_rows and
-- practice_prepull_rows all ride ST.PALADIN for the same reason.
ST.PALADIN.aow_pulse = {
    key = "AowExoOverlap",
    seconds = 0.4,
    color = {255, 215, 0, 0.9},
    lines = 8,
    frequency = 0.25,
    thickness = 2,
}

-- Twist hit-rate badge: a small summary line under the mainhand bar. Option
-- nil = off; the badge font size and its offset below the bar are constants.
local TWIST_SCORE_TEXT_SIZE = 12
local TWIST_SCORE_TEXT_OFFSET = -4

function ST.PALADIN.aow_exo_pulse_start(self)
    -- Starts the overlap pulse on the mainhand bar (same LibCustomGlow call
    -- shape as the AoW and twist-success glows, with its own key). Nil-safe
    -- pre-construction: without the bar frame there is nothing to glow.
    local frame = self.mainhand.anchor_frame and self:get_bar_frame("mainhand")
    if not frame then
        return
    end
    LCG.PixelGlow_Start(frame,
        {self:convert_color(ST.PALADIN.aow_pulse.color)},
        ST.PALADIN.aow_pulse.lines,
        ST.PALADIN.aow_pulse.frequency,
        nil,
        ST.PALADIN.aow_pulse.thickness,
        0,
        0,
        false,
        ST.PALADIN.aow_pulse.key
    )
end

function ST.PALADIN.aow_exo_pulse_stop(self)
    local frame = self.mainhand.anchor_frame and self:get_bar_frame("mainhand")
    if not frame then
        return
    end
    LCG.PixelGlow_Stop(frame, ST.PALADIN.aow_pulse.key)
end

function ST.PALADIN.glow_start(self)
    local db_class = self:get_class_table()
    if type(db_class) ~= "table" then
        -- PROPER: without a profile there are no glow preferences; starting no
        -- glow is the fail-safe (never invent feedback).
        return
    end
    local frame = self:get_bar_frame("mainhand")
    if frame == nil then
        -- PROPER: an unbuilt hand (lazy bars) has no frame to glow; legitimate
        -- transient, retried on a later tick.
        return
    end
    local db_hand = self:get_hand_table("mainhand")
    -- PROPER: a missing hand table falls back to thickness 1, this file's own
    -- minimum (never a guessed colour, only the neutral width floor).
    local thickness = (db_hand and db_hand.border_width) or 1
    if thickness == 0 then
        thickness = 1
    end
    LCG.PixelGlow_Start(frame,
        {self:convert_color(db_class.aow_glow_color)},
        db_class.aow_glow_nlines,
        db_class.aow_glow_freq,
        db_class.aow_glow_line_length,
        thickness,
        0,
        0,
        -- db_class.aow_glow_offset,
        -- db_class.aow_glow_offset,
        false
    )
end

function ST.PALADIN.glow_stop(self)
    local frame = self:get_bar_frame("mainhand")
    if frame == nil then
        -- PROPER: an unbuilt hand owns no glow to stop; stopping nothing is exact.
        return
    end
    LCG.PixelGlow_Stop(frame)
end

function ST.PALADIN.process_aow(self)
    local db = self:get_class_table() or {}
    -- PROPER: {} preserves this function's own nil-option semantics exactly
    -- (exo_holds/glow_on read falsy, the pulse gate reads off); only the
    -- transition logic is skipped, never invented.
    -- Same three stops / one start as before, expressed as a single readiness
    -- flag so the AoW+Exorcism overlap below reuses the exact shape: "stop"
    -- everywhere the old nested gates stopped (no AoW, glow disabled, or the
    -- Exorcism gate configured yet holding) and one "start" otherwise, so the
    -- glow outcomes are byte-identical to the old control flow.
    local exo_holds = db.require_exo_ready and self.exo_on_cooldown
    local glow_on = self.has_aow and db.use_aow_glow and not exo_holds
    -- AoW+Exorcism overlap pulse (one per false->true transition): the same
    -- shape with the glow toggle left out, so the pulse describes the rotation
    -- readiness, not the glow preference. Gated on the pulse option (nil =
    -- off) and on the Retail gate the sibling paladin visuals share (Retail
    -- has neither the proc nor the per-frame stop path); the transition latch
    -- updates either way, so a later enable never fires on a stale overlap.
    -- Started here at the transition, exactly like the twist-success glow
    -- (the start is nil-safe pre-construction); the per-frame stop block owns
    -- the teardown.
    local overlap = self.has_aow and not exo_holds
    if overlap and self.aow_exo_prev ~= true
        and db.aow_exo_pulse_enabled == true and not st.is_retail then
        self.PALADIN.aow_exo_pulse_start(self)
        self.aow_exo_pulse_until = api.get_time() + ST.PALADIN.aow_pulse.seconds
    end
    self.aow_exo_prev = overlap == true
    if glow_on then
        self.PALADIN.glow_start(self)
    else
        self.PALADIN.glow_stop(self)
    end
end

function ST.PALADIN.set_bar_color(self, hand)
    -- Returns true if any special setting was applied to let the parent func know
    -- to revert to default behaviour.
    -- Will set appropriate colors for seals and AoW procs if requested.
    local db_class = self:get_class_table()
    if type(db_class) ~= "table" then
        -- PROPER: false lets the parent draw the default colour; the bar still
        -- shows, only the optional seal tint is withheld without preferences.
        return false
    end
    local frame = self:get_visuals_frame(hand)
    if frame == nil then
        -- PROPER: with no frame there is nothing to recolour; the bar itself is
        -- drawn by bars.lua, which owns unbuilt-hand visibility.
        return false
    end

    -- Art of War glow
    self.PALADIN.process_aow(self)

    -- Seal colors
    if db_class.use_seal_colors then
        if self.has_soc then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.soc_color)
            )
            return true
        end
        if self.has_sov then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.sov_color)
            )
            return true
        end
        if self.has_sol then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.sol_color)
            )
            return true
        end
        if self.has_sow then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.sow_color)
            )
            return true
        end
        if self.has_sor then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.sor_color)
            )
            return true
        end
        if self.has_soj then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.soj_color)
            )
            return true
        end
        if self.has_sob then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.sob_color)
            )
            return true
        end
        if self.has_sotc then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.sotc_color)
            )
            return true
        end
    end

    return false
end

-- SoC proc localized names (R1): the client's own names for the proc ranks,
-- resolved once through GetSpellInfo and retried at a throttled cadence while
-- the client's spell data is not up yet (the warrior debuff-name discipline).
-- Nil until the first answer; the literal English fallback in twist.lua still
-- matches without any resolution.
local soc_proc_localized_names
local soc_proc_names_retry_at = 0
local SOC_PROC_NAMES_RETRY_S = 5

-- Unmatched twist-proc payload observability (M3): a SPELL_DAMAGE event whose payload
-- carries no usable id/name field is counted for the session, and the first few are
-- announced once. The score badge alone cannot distinguish "the player is missing
-- twists" from "the addon cannot read the proc payload" - both sit at 0% (0/N) - so
-- the sustained-blind case gets one chat line and a readable counter.
local TWIST_PAYLOAD_NOTICE_AT = 3

local function resolve_soc_proc_names(now)
    if soc_proc_localized_names == nil and now >= soc_proc_names_retry_at then
        local names = {}
        for id in pairs(st.twist.SOC_PROC_IDS) do
            local name = api.GetSpellInfo(id)
            if name then
                names[name] = true
            end
        end
        if next(names) ~= nil then
            soc_proc_localized_names = names
        else
            soc_proc_names_retry_at = now + SOC_PROC_NAMES_RETRY_S
        end
    end
    return soc_proc_localized_names
end

function ST.PALADIN.on_combat_log_unfiltered(self, _, timestamp, event, hide_caster, source_guid, source_name, source_flags, source_raid_flags, dest_guid, dest_name, dest_flags, dest_raid_flags, ...)
    -- Twist Practice: the simulation owns the twist state while a session runs, so real
    -- combat-log events must not arm attempts or consume procs (they would also fight
    -- the 0.05 s seal mirror for control of the same flags).
    if st.practice_ui and st.practice_ui.is_active() then
        return
    end
    -- Only our own actions matter for twisting.
    if source_guid ~= UnitGUID("player") then
        return
    end

    if event == "SPELL_EXTRA_ATTACKS" then
        -- The amount field is the 4th payload argument after the destination
        -- fields (spellId, spellName, spellSchool, amount).
        local amount = tonumber(select(4, ...)) or 1
        self.twist_extra_attacks_pending = (self.twist_extra_attacks_pending or 0) + amount
        return
    end

    if event == "SWING_DAMAGE" or event == "SWING_MISSED" then
        if (self.twist_extra_attacks_pending or 0) > 0 then
            self.twist_extra_attacks_pending = self.twist_extra_attacks_pending - 1
            return
        end
        -- JotC melee refresh: a plain weapon swing (extra-attack swings were
        -- consumed above) extends the tracked debuff to its full length. No-op
        -- when nothing is tracked.
        self.PALADIN.note_swing_landed(self)
        -- Refresh seals without the full aura-change side effects (the AoW glow
        -- must not restart on every swing).
        local n = self.PALADIN.parse_seals(self)
        -- Archive parity: the attempt arms on n_active_seals == 2 alone. The extra
        -- seal-discipline gate wrongly disarmed Blood+Crusader windows.
        -- PPM/ICD attempt discipline (both sims: 7 PPM, 1 s ICD, white hits
        -- only): a swing landing inside the ICD after a proc cannot proc, so
        -- it arms no attempt and scores nothing. A nil stamp (no proc yet)
        -- keeps the archived behaviour.
        local icd_clear = st.twist.is_proc_icd_clear(
            api.get_time(), self.twist_last_proc_at)
        local attempt = icd_clear and st.twist.detect_twist_attempt(false, true, n)
        if attempt then
            self.twist_attempt_pending = true
            self.twist_sound_played = false
            self.PALADIN.on_twist_attempt(self)
        else
            self.twist_attempt_pending = false
            self.twist_sound_played = false
        end
        return
    end

    if event == "SPELL_DAMAGE" then
        -- Anniversary (UNCONFIRMED, R1) may send the spell name where classic
        -- sends the numeric id: match the id first (the classic path, unchanged),
        -- then fall back to the localized proc names plus the literal English
        -- fallback. Either payload shape consumes the same pending attempt.
        local sid, sname = select(1, ...), select(2, ...)
        local success = false
        if type(sid) == "number" then
            success = st.twist.detect_twist_success(self.twist_attempt_pending == true, sid)
        elseif type(sid) == "string" then
            success = st.twist.detect_twist_success_name(
                self.twist_attempt_pending == true, sid,
                resolve_soc_proc_names(api.get_time()))
        elseif type(sname) == "string" then
            success = st.twist.detect_twist_success_name(
                self.twist_attempt_pending == true, sname,
                resolve_soc_proc_names(api.get_time()))
        else
            -- M3: a third payload shape (nil id and name, a table payload). Count it
            -- and announce once at the threshold: a sustained run of these is the
            -- addon blind on an evolving CLEU contract, not the player missing twists.
            self.twist_unmatched_payloads = (self.twist_unmatched_payloads or 0) + 1
            if self.twist_unmatched_notified ~= true
                and self.twist_unmatched_payloads >= TWIST_PAYLOAD_NOTICE_AT then
                self.twist_unmatched_notified = true
                st.utils.print_msg("SwedgeTimer: twist proc payloads could not be matched on this client; this session's twist score may sit at 0%.")
            end
        end
        if success then
            self.twist_attempt_pending = false
            self.PALADIN.on_successful_twist(self)
        end
        return
    end
end

--=========================================================================================
-- Seal twisting: window band and success feedback visuals
--=========================================================================================
-- Twist feedback sounds: key -> file map ported from the archived build's bar.lua
-- (69 entries; the archive's map carries the same key set). The keys are saved option
-- values (never rename them). DEVIATION from the archive: the archived build shipped
-- these files under Sounds\ while the live addon ships them under Media\Sounds\
-- (same file names), so every path below points at the live layout.
local twist_sounds = {
    -- Original sounds
    ["pop"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\pop.ogg",
    ["bubble-pop"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\bubble-pop.ogg",
    ["swoosh"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\swoosh.ogg",
    ["whoopee"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\whoopee.ogg",
    -- Instruments
    ["AcousticGuitar"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\AcousticGuitar.ogg",
    ["Brass"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Brass.mp3",
    ["Drums"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Drums.ogg",
    ["Glass"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Glass.mp3",
    ["SynthChord"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\SynthChord.ogg",
    ["TempleBellHuge"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\TempleBellHuge.ogg",
    ["Xylophone"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Xylophone.ogg",
    -- Alerts & UI
    ["AirHorn"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\AirHorn.ogg",
    ["BikeHorn"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\BikeHorn.ogg",
    ["ErrorBeep"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\ErrorBeep.ogg",
    ["RingingPhone"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\RingingPhone.ogg",
    ["RobotBlip"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\RobotBlip.ogg",
    ["WarningSiren"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\WarningSiren.ogg",
    ["WaterDrop"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\WaterDrop.ogg",
    -- Animals
    ["Bleat"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Bleat.ogg",
    ["CatMeow2"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\CatMeow2.ogg",
    ["ChickenAlarm"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\ChickenAlarm.ogg",
    ["CowMooing"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\CowMooing.ogg",
    ["GoatBleating"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\GoatBleating.ogg",
    ["KittenMeow"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\KittenMeow.ogg",
    ["RoaringLion"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\RoaringLion.ogg",
    ["RoosterChickenCalls"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\RoosterChickenCalls.ogg",
    ["SheepBleat"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\SheepBleat.ogg",
    -- Combat & Action
    ["Bloodlust"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Bloodlust.ogg",
    ["BatmanPunch"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\BatmanPunch.ogg",
    ["Blast"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Blast.ogg",
    ["BoxingArenaSound"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\BoxingArenaSound.ogg",
    ["DoubleWhoosh"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\DoubleWhoosh.ogg",
    ["SharpPunch"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\SharpPunch.ogg",
    ["Shotgun"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Shotgun.ogg",
    -- Cartoon & Fun
    ["Applause"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Applause.ogg",
    ["BananaPeelSlip"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\BananaPeelSlip.ogg",
    ["CartoonVoiceBaritone"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\CartoonVoiceBaritone.ogg",
    ["CartoonWalking"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\CartoonWalking.ogg",
    ["HeartbeatSingle"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\HeartbeatSingle.ogg",
    ["SqueakyToyShort"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\SqueakyToyShort.ogg",
    ["SquishFart"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\SquishFart.ogg",
    ["TadaFanfare"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\TadaFanfare.ogg",
    -- Voice Callouts
    ["Adds"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Adds.ogg",
    ["Boss"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Boss.ogg",
    ["DontRelease"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\DontRelease.ogg",
    ["Empowered"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Empowered.ogg",
    ["Focus"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Focus.ogg",
    ["Idiot"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Idiot.ogg",
    ["OhNo"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\OhNo.ogg",
    ["Protected"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Protected.ogg",
    ["Release"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Release.ogg",
    ["RunAway"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\RunAway.ogg",
    ["Spread"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Spread.ogg",
    ["Stack"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Stack.ogg",
    ["Taunt"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Taunt.ogg",
    -- Shapes (Markers)
    ["Circle"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Circle.ogg",
    ["Cross"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Cross.ogg",
    ["Diamond"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Diamond.ogg",
    ["Left"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Left.ogg",
    ["Moon"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Moon.ogg",
    ["Right"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Right.ogg",
    ["Skull"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Skull.ogg",
    ["Square"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Square.ogg",
    ["Star"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Star.ogg",
    ["Triangle"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Triangle.ogg",
    -- Misc
    ["Next"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Next.ogg",
    ["Portal"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Portal.ogg",
    ["Switch"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Switch.ogg",
    ["Torch"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Torch.ogg",
}

-- Published for the rotation-text sound widgets (widgets.lua prefers the class
-- module's published map over its debug-upvalue bridge; same keys, same paths).
ST.PALADIN.twist_sounds = twist_sounds

-- Plays a twist feedback sound by option key (fallback_key covers a nil choice);
-- no-op when the key has no entry (unknown/renamed key) or the client offers no
-- PlaySoundFile, so a mismatched setting can never error.
local function play_twist_sound(db, key, fallback_key)
    local path = twist_sounds[key or fallback_key]
    if path == nil or PlaySoundFile == nil then
        return
    end
    PlaySoundFile(path, db.sound_channel or "Master")
end

-- Fallback colours used whenever a db key is missing (or malformed), so the visuals
-- are safe to run even before the options lane lands the matching keys. They ride the
-- module table: this module sits at the Lua 5.1 file-scope-local ceiling (see
-- ST.PALADIN.aow_pulse above), so a new constant here would be a load failure.
ST.PALADIN.twist_colors = {
    marker = {255, 255, 255, 0.35},
    twisting = {179, 26, 153, 1.0},
    cant = {212, 212, 3, 1.0},
    success = {90, 255, 90, 1.0},
    -- The fallback glow colour (the archive's {0.0, 1.0, 0.0, 0.8} converted up), used
    -- whenever the db key is missing or malformed.
    glow = {0, 255, 0, 0.8},
}

-- Returns db[key] when it looks like a colour table, otherwise the fallback.
local function twist_color(db, key, fallback)
    local c = db[key]
    if type(c) == "table" and #c >= 4 then
        return c
    end
    return fallback
end

-- Explicit unknown-state band values (M4/M5). The band's normal vocabulary is
-- "no twist now" (hidden) vs the window; a dead swing feed and a genuinely
-- single-sealed swing have to stay distinguishable, so the degraded states reuse the
-- band + success-text widgets with fixed copy and a dim, distinct alpha.
local TWIST_STATE_TEXT_ALPHA = 0.7
local TWIST_STATE_BAND_ALPHA = 0.10
local TWIST_STATE_SWING_UNKNOWN = "seal data unknown"
local TWIST_STATE_LUST_UNKNOWN = "lust unknown"

-- Writes one of the unknown-state strings through the (reused) success-text widget.
-- The value latch keeps SetText off the per-frame path while the state persists; the
-- tint is the neutral white, distinct from every success/twist colour.
local function set_twist_state_text(text, value)
    if not text then
        return
    end
    if text.text_value ~= value then
        text.text_value = value
        text:SetText(value)
        text:SetTextColor(1, 1, 1, TWIST_STATE_TEXT_ALPHA)
    end
    text:SetAlpha(TWIST_STATE_TEXT_ALPHA)
    text:Show()
end

--=========================================================================================
-- Judgement marker line, seal icons, twist-success glow (archived TBC bar visuals)
--=========================================================================================
-- Judgement (the rotation timing cue, archive bar.lua:1750-1786): the spell id the
-- guide already uses, the marker colour (the archive's {0.9, 0.9, 0.01, 1.0}
-- converted up to the codebase's 0-255 storage) and the line thickness. Only the
-- enable is an option (judgement_marker_enabled); colour/width are constants.
local JUDGEMENT_SPELL_ID = 20271
local JUDGEMENT_MARKER_COLOR = {230, 230, 3, 1.0}
local JUDGEMENT_MARKER_WIDTH = 2

-- Reseal marker (SST 3.1.0 "reseal marker for twist seals", P1): a 2 px line at
-- the swing position where the running GCD clears (the pure fraction in
-- twist.lua). Only the enable is an option (reseal_marker_enabled, nil = off -
-- the options pass owns the widget); colour/width are constants. SST in-client
-- behavior UNCONFIRMED; the marker math is offline-testable.
local RESEAL_MARKER_COLOR = {255, 255, 255, 0.55}
local RESEAL_MARKER_WIDTH = 2

-- Standalone seal icons (archive bar.lua:826-910): the two twist seals get one slot
-- each, Command first. The swipe length falls back to the archived 30 s seal
-- duration where LibClassicDurations tracks nothing. Only the enable is an option
-- (seal_icons_enabled); the attached position, the gap and the timer size are
-- constants. The icons sit right of the mainhand bar at bar height.
local SEAL_ICON_SLOTS = {
    { spell_id = 20375 },
    -- The second slot tracks the twist seal: Blood everywhere but Era, where it
    -- is Righteousness (twist_seal_icon_id above).
    { spell_id = twist_seal_icon_id },
}
local SEAL_ICON_GAP = 4
local SEAL_ICON_TEXCROP = {0.07, 0.93, 0.07, 0.93}
local SEAL_TIMER_TEXT_SIZE = 16

-- One reused seal-state pair: update_seal_icons runs every frame, so no table
-- work happens on the tick (the HUD provider contract's no-allocation rule).
local SEAL_LIVE = {
    { active = false, expires = nil, full = nil },
    { active = false, expires = nil, full = nil },
}

-- Twist-success glow (archive bar.lua:551-616, Pixel at minimum): the key lets the
-- attempt glow coexist with the Art of War glow on the same bar frame; the line
-- count, frequency and thickness are the archive's Pixel parameters. Only the
-- enable, colour and duration are options.
ST.PALADIN.twist_glow = {
    key = "TwistSuccess",
    lines = 8,
    frequency = 0.25,
    thickness = 2,
}

function ST.PALADIN.update_judgement_marker(self, hand)
    -- Judgement timing line (archive bar.lua:1750-1786): drawn at the swing
    -- position where Judgement comes off cooldown, i.e. remaining_cd into the
    -- elapsed swing, exactly like the archive's (remaining + elapsed) / speed
    -- offset. Shown only while Judgement is on a real cooldown that ends inside
    -- this swing (durations at or below 1.5 s are the GCD echo, not a cooldown)
    -- and a seal worth judging is up.
    local vf = self:get_visuals_frame(hand)
    local marker = vf and vf.judgement_marker
    if not marker then
        return
    end
    local now = api.get_time()
    local db = self:get_class_table()
    local d = self[hand]
    local offset
    if db.judgement_marker_enabled ~= false
        and not st.is_retail
        and d and d.speed and d.speed > 0 and d.ends_at and d.start
        and not d.is_full
        and (self.has_sob or self.has_sor or self.has_sov or self.has_soj) then
        local swing_remaining = math.max(0, d.ends_at - now)
        local start_time, duration = api.GetSpellCooldown(spell_query(JUDGEMENT_SPELL_ID))
        if duration and duration > 1.51 then
            local cd_remaining = start_time + duration - now
            if cd_remaining > 0 and cd_remaining < swing_remaining then
                local elapsed = d.speed - swing_remaining
                local w = self:get_bar_visuals_width_and_height(hand)
                offset = ((cd_remaining + elapsed) / d.speed) * w
            end
        end
    end
    if offset == nil then
        if marker:IsShown() then
            marker:Hide()
        end
        return
    end
    local _, h = self:get_bar_visuals_width_and_height(hand)
    marker:SetStartPoint("TOPLEFT", offset, 0)
    marker:SetEndPoint("TOPLEFT", offset, h * -1)
    marker:Show()
end

function ST.PALADIN.update_reseal_marker(self, hand)
    -- Reseal marker (P1, SST 3.1.0 shape): drawn at the swing position where the
    -- running GCD clears (the pure GCD-clear fraction in twist.lua), so the
    -- player sees when a reseal press becomes possible relative to the twist
    -- window the band draws. Shown only while its own option is on
    -- (reseal_marker_enabled == true, nil = off), the twist system itself is on,
    -- a twist-capable seal is up and the swing record is usable - the same
    -- availability the band gates on, minus the band's own marker toggle. The
    -- Retail stand-in never swings, so the marker stays hidden there like the
    -- band; a GCD clearing outside this swing hides it (unknown-hides).
    local vf = self:get_visuals_frame(hand)
    local marker = vf and vf.reseal_marker
    if not marker then
        return
    end
    local now = api.get_time()
    local db = self:get_class_table()
    local d = self[hand]
    local fraction
    if db.reseal_marker_enabled == true and db.twist_enabled ~= false
        and not st.is_retail
        and st.twist.is_twist_seal_active(self.has_soc, self.has_sor)
        and d and type(d.speed) == "number" and d.speed > 0
        and d.ends_at and d.start and not d.is_full then
        local gcd = self.gcd
        local gcd_remaining = (gcd and gcd.expires
            and math.max(0, gcd.expires - now)) or 0
        fraction = st.twist.get_reseal_marker_fraction(
            d.speed, math.max(0, d.ends_at - now), gcd_remaining)
    end
    if fraction == nil then
        if marker:IsShown() then
            marker:Hide()
        end
        return
    end
    local w, h = self:get_bar_visuals_width_and_height(hand)
    marker:SetWidth(RESEAL_MARKER_WIDTH)
    marker:SetHeight(h)
    marker:ClearAllPoints()
    marker:SetPoint("TOPLEFT", vf, "TOPLEFT", fraction * w, 0)
    marker:Show()
end

-- Design mode counts as active while the designer runs (the options button and
-- the /st design command both route through st.designmode.toggle; the module is
-- absent on flavors without the file, so the probe is nil-safe). Bar children
-- force-show through this so their overlays can grab them; gameplay visibility
-- is untouched (the gate is only ever true inside an active design session, and
-- the archive previews elements the same way so they can be placed live).
local function designing()
    return st.designmode and type(st.designmode.is_active) == "function"
        and st.designmode.is_active() == true
end

-- Seal-icon detach (designmode "Seal icons" element): attached (nil) keeps the
-- archive anchor right of the bar; a design-mode drag stores detached centre
-- offsets and re-anchors to UIParent. No option widget: the db keys are
-- design-flow-only (drag writes, double-click reset clears), exactly like the
-- practice panel offsets.
function ST.PALADIN.apply_seal_icons_anchor(self)
    local vf = self:get_visuals_frame("mainhand")
    local set = vf and vf.seal_icons
    local frame = set and set.frame
    if not frame then
        return
    end
    local db = self:get_class_table()
    if db.seal_icons_detached == true
        and type(db.seal_icons_x) == "number"
        and type(db.seal_icons_y) == "number" then
        local s = frame:GetScale() or 1
        if s <= 0 then
            s = 1
        end
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", db.seal_icons_x / s, db.seal_icons_y / s)
        return
    end
    local bar_frame = self.mainhand.anchor_frame and self:get_bar_frame("mainhand")
    if not bar_frame then
        return
    end
    frame:ClearAllPoints()
    frame:SetPoint("LEFT", bar_frame, "RIGHT", SEAL_ICON_GAP, 0)
end

function ST.PALADIN.save_seal_icons_position(self, x, y)
    local vf = self:get_visuals_frame("mainhand")
    if not (vf and vf.seal_icons and vf.seal_icons.frame) then
        return
    end
    local db = self:get_class_table()
    db.seal_icons_detached = true
    db.seal_icons_x = math.floor(x + 0.5)
    db.seal_icons_y = math.floor(y + 0.5)
    self.PALADIN.apply_seal_icons_anchor(self)
end

function ST.PALADIN.reset_seal_icons_position(self)
    local vf = self:get_visuals_frame("mainhand")
    if not (vf and vf.seal_icons and vf.seal_icons.frame) then
        return
    end
    local db = self:get_class_table()
    db.seal_icons_detached = nil
    db.seal_icons_x = nil
    db.seal_icons_y = nil
    self.PALADIN.apply_seal_icons_anchor(self)
end

-- Twist success-text detach (designmode "Successful twist text" element): same
-- detach shape as the seal icons above (attached = centred above the bar,
-- drag = UIParent offsets, reset = re-attach). The widget is a font string,
-- which supports the same ClearAllPoints/SetPoint anchoring.
function ST.PALADIN.apply_twist_text_anchor(self)
    local vf = self:get_visuals_frame("mainhand")
    local text = vf and vf.twist_text
    if not text then
        return
    end
    local db = self:get_class_table()
    if db.twist_text_detached == true
        and type(db.twist_text_x) == "number"
        and type(db.twist_text_y) == "number" then
        local s = text:GetScale() or 1
        if s <= 0 then
            s = 1
        end
        text:ClearAllPoints()
        text:SetPoint("CENTER", UIParent, "CENTER", db.twist_text_x / s, db.twist_text_y / s)
        return
    end
    text:ClearAllPoints()
    text:SetPoint("BOTTOM", vf, "TOP", 0, 6)
end

function ST.PALADIN.save_twist_text_position(self, x, y)
    local vf = self:get_visuals_frame("mainhand")
    if not (vf and vf.twist_text) then
        return
    end
    local db = self:get_class_table()
    db.twist_text_detached = true
    db.twist_text_x = math.floor(x + 0.5)
    db.twist_text_y = math.floor(y + 0.5)
    self.PALADIN.apply_twist_text_anchor(self)
end

function ST.PALADIN.reset_twist_text_position(self)
    local vf = self:get_visuals_frame("mainhand")
    if not (vf and vf.twist_text) then
        return
    end
    local db = self:get_class_table()
    db.twist_text_detached = nil
    db.twist_text_x = nil
    db.twist_text_y = nil
    self.PALADIN.apply_twist_text_anchor(self)
end

function ST.PALADIN.update_seal_icons(self, hand)
    -- Standalone seal icons (archive bar.lua:919-1119, condensed): one slot per
    -- twist seal with a reversed cooldown swipe and a remaining-time text. The
    -- swipe runs from the aura expiry over the tracked (or fallback) full
    -- length; a seal without a usable expiry still shows its icon, exactly like
    -- the archive's texture-before-cooldown order.
    local vf = self:get_visuals_frame(hand)
    local set = vf and vf.seal_icons
    if not set then
        return
    end
    local now = api.get_time()
    local db = self:get_class_table()
    local enabled = db.seal_icons_enabled ~= false and not st.is_retail
    -- The icon size tracks the bar height; re-layout once when it changes.
    local _, h = self:get_bar_visuals_width_and_height(hand)
    if h and h ~= set.size then
        set.size = h
        set.frame:SetSize(h * 2 + 2, h)
        for i = 1, #set.slots do
            local slot = set.slots[i]
            slot.icon:SetSize(h, h)
            slot.icon:SetPoint("TOPLEFT", (i - 1) * (h + 2), 0)
            slot.cooldown:SetSize(h, h)
            slot.cooldown:SetPoint("TOPLEFT", slot.icon, "TOPLEFT", 0, 0)
        end
    end
    local live = SEAL_LIVE
    live[1].active, live[1].expires, live[1].full = self.has_soc, self.soc_expires, self.soc_duration
    -- Era tracks the twist seal (Righteousness) in the second slot; every other
    -- family keeps Blood there.
    if is_era_family then
        live[2].active, live[2].expires, live[2].full = self.has_sor, self.sor_expires, self.sor_duration
    else
        live[2].active, live[2].expires, live[2].full = self.has_sob, self.sob_expires, self.sob_duration
    end
    local any_shown = false
    for i = 1, #set.slots do
        local slot = set.slots[i]
        local state = live[i]
        local icon_texture
        if enabled and state.active then
            -- Texture resolution is a rare event, not a per-frame one: each
            -- slot lazily caches its spell texture (the id is constant per
            -- slot) and only latches a non-nil answer, so cold spell data
            -- keeps retrying instead of caching the miss.
            if slot.cached_texture == nil or slot.tex_spell_id ~= slot.spell_id then
                local texture = select(3, api.GetSpellInfo(slot.spell_id))
                if texture ~= nil then
                    slot.tex_spell_id = slot.spell_id
                    slot.cached_texture = texture
                end
            end
            icon_texture = slot.cached_texture
        end
        if icon_texture == nil then
            if slot.icon:IsShown() then
                slot.icon:Hide()
            end
            slot.icon_key = nil
            if slot.cd_start ~= nil then
                slot.cd_start, slot.cd_full = nil, nil
                slot.cooldown:SetCooldown(0, 0)
                slot.cooldown:Hide()
            end
            if slot.timer:IsShown() then
                slot.timer:Hide()
            end
            slot.text_value = nil
        else
            any_shown = true
            if slot.icon_key ~= icon_texture then
                slot.icon_key = icon_texture
                slot.icon:SetTexture(icon_texture)
            end
            if not slot.icon:IsShown() then
                slot.icon:Show()
            end
            local full = state.full or SEAL_FALLBACK_DURATION
            local start = (type(state.expires) == "number") and (state.expires - full) or nil
            if start ~= nil and state.expires > now then
                if slot.cd_start ~= start or slot.cd_full ~= full then
                    slot.cd_start, slot.cd_full = start, full
                    slot.cooldown:SetCooldown(start, full)
                end
                if not slot.cooldown:IsShown() then
                    slot.cooldown:Show()
                end
                local quantised = math.floor(state.expires - now)
                if slot.text_value ~= quantised then
                    slot.text_value = quantised
                    slot.timer:SetText(string.format("%d", state.expires - now))
                end
                if not slot.timer:IsShown() then
                    slot.timer:Show()
                end
            else
                if slot.cd_start ~= nil then
                    slot.cd_start, slot.cd_full = nil, nil
                    slot.cooldown:SetCooldown(0, 0)
                end
                if slot.cooldown:IsShown() then
                    slot.cooldown:Hide()
                end
                if slot.timer:IsShown() then
                    slot.timer:Hide()
                end
                slot.text_value = nil
            end
        end
    end
    if any_shown then
        if not set.frame:IsShown() then
            set.frame:Show()
        end
    elseif set.frame:IsShown() then
        set.frame:Hide()
    end
    if not any_shown and designing() and enabled then
        -- Design mode previews an empty-but-visible row so the overlay can
        -- grab it; the slots stay hidden (no seals tracked). Gameplay hiding
        -- is untouched (designing() is false outside design).
        if not set.frame:IsShown() then
            set.frame:Show()
        end
    end
end

function ST.PALADIN.twist_glow_start(self)
    -- Starts the twist-success Pixel glow on the mainhand bar (archive
    -- bar.lua:573-584, via the HUD's LibCustomGlow call shape). Nil-safe
    -- pre-construction: without the bar frame there is nothing to glow.
    local frame = self.mainhand.anchor_frame and self:get_bar_frame("mainhand")
    if not frame then
        return
    end
    local db = self:get_class_table() or {}
    -- PROPER: {} makes twist_color fall back to its spec'd fallback colour, so a
    -- real twist attempt still flashes (feedback preserved) instead of dying.
    LCG.PixelGlow_Start(frame,
        {self:convert_color(twist_color(db, "twist_success_glow_color", ST.PALADIN.twist_colors.glow))},
        ST.PALADIN.twist_glow.lines,
        ST.PALADIN.twist_glow.frequency,
        nil,
        ST.PALADIN.twist_glow.thickness,
        0,
        0,
        false,
        ST.PALADIN.twist_glow.key
    )
end

function ST.PALADIN.twist_glow_stop(self)
    local frame = self.mainhand.anchor_frame and self:get_bar_frame("mainhand")
    if not frame then
        return
    end
    LCG.PixelGlow_Stop(frame, ST.PALADIN.twist_glow.key)
end

-- Bloodlust / Heroism twist-window override (bench/verify_bank.md P3): the
-- shaman haste buffs (2825 Bloodlust, 32182 Heroism) tighten the twist cadence,
-- so the window computes over the non-hasted swing speed must narrow while one
-- is up. Detection runs through compat's frozen player-aura scan (nil-safe:
-- without the aura or without the API it returns nil, nil — never zero) and is
-- throttled; the C2 family gate st.lust_supported closes Era (and the UNKNOWN
-- fallback) before any read, and closed-on-unknown (R4) keeps nil (a pre-C2
-- compat) off too — and a running practice session owns its own window, so
-- the override skips that too.
local LUST_RESCAN_INTERVAL = 0.5

local function get_twist_lust_remaining(self, now)
    if self.twist_lust_at and (now - self.twist_lust_at) < LUST_RESCAN_INTERVAL then
        return self.twist_lust_remaining
    end
    self.twist_lust_at = now
    self.twist_lust_remaining = nil
    -- Name-vs-id rule: TBC matches the localized Bloodlust/Heroism names (the
    -- ids CONFIRMED in bench/verify_bank.md §2; the English literals cover a
    -- cold book, exactly like the warrior shout scans), every other family
    -- matches the numeric ids only.
    local lust_a, lust_b
    if st.family == "TBC" then
        lust_a = resolve_spell_name(2825) or "Bloodlust"
        lust_b = resolve_spell_name(32182) or "Heroism"
    end
    local remaining, _ = api.scan_player_aura(function(spell_id, name)
        if st.family == "TBC" then
            return name == lust_a or name == lust_b
        end
        return spell_id == 2825 or spell_id == 32182
    end)
    if type(remaining) == "number" and remaining > 0 then
        self.twist_lust_remaining = remaining
    end
    -- M5: a miss under a secret-aura regime is not the same as an honest "no lust".
    -- compat's new observability probe answers whether restricted aura rows can be
    -- hidden right now (nil on every classic client - the exact no-op); when it is
    -- explicitly true and the scan found nothing, the consumer marks the reading
    -- unknown so the band can say so instead of showing confident un-hasted advice.
    local secrecy_probe = api.auras_may_be_secret
    self.twist_lust_unknown = self.twist_lust_remaining == nil
        and type(secrecy_probe) == "function" and secrecy_probe() == true
    return self.twist_lust_remaining
end

-- Forward declaration: the Divine Storm rune resolver lives with the other
-- rank resolvers further below; the window helper above needs it at call
-- time (Lua resolves the file-local at definition, so the later
-- `resolve_ds_spell_id = function(now)` assigns this same local).
local resolve_ds_spell_id

-- SoD detection (rune spells only, never version strings: SoD runs on the ERA
-- family client): a book carrying a SoD paladin rune runs the APLs that twist
-- inside 200 ms. Shared by the window helper (bar band) and the guide gather
-- (landmarks) so both narrow together. cs_known/ds_id are the caller's own
-- reads; the Martyr probe is the third rune leg.
local function is_sod_client(cs_known, ds_id)
    if not is_era_family then
        return false
    end
    if cs_known == true then
        return true
    end
    if ds_id ~= nil then
        return true
    end
    return is_spell_known_query(348700)
end

function ST.PALADIN.get_twist_window_time_before_swing(self)
    -- Twist window duration (seconds before the swing lands): the 400 ms baseline
    -- plus the configured padding, per the archived build's helper. The lag used
    -- here is calibrated from the player's raw world latency with the twist lag
    -- settings (the archived build's lag_calibrated_ms), not the deadzone
    -- calibration, so the two features stay independent.
    local db = self:get_class_table() or {}
    -- PROPER: {} reads exactly the file's own calibration defaults (lag 1.4/15,
    -- no padding, no lust override), identical to unset options.
    local raw_ms = (self.latency and self.latency.world_ms) or 0
    local lag_ms = raw_ms * (db.lag_multiplier or 1.4) + (db.lag_offset or 15)
    local window = st.twist.get_window_seconds(
        db.twist_padding_mode, lag_ms, db.twist_window_padding_ms)
    -- SoD twist builds twist inside 200 ms, not 400 ms (all SoD twist APLs):
    -- the baseline narrows on rune detection while the user's padding rides
    -- on top unchanged. Resolved here (not latched) so the band and the guide
    -- landmarks the gather feeds from this same helper narrow together.
    local na = st.nextaction
    local sod_cs_known = na and na.CS_SPELL_ID
        and is_spell_known_query(na.CS_SPELL_ID) or false
    window = st.twist.narrow_window_for_sod(window,
        is_sod_client(sod_cs_known, resolve_ds_spell_id(api.get_time())))
    -- Lust override (nil = off): narrows the window through the pure engine
    -- helper. The helper is nil-guarded so a build without nextaction.lua
    -- (none shipped, but the archived loaders) degrades to the base window.
    -- Closed-on-unknown (R4): only an explicit true arms the scan; nil (a
    -- pre-C2 compat) or false stays off.
    if db.twist_lust_override_enabled == true and st.lust_supported == true
        and not (st.practice_ui and st.practice_ui.is_active()) then
        local lust = get_twist_lust_remaining(self, api.get_time())
        local scaled = st.nextaction and st.nextaction.apply_lust_window
            and st.nextaction.apply_lust_window(window, lust ~= nil)
        if scaled ~= nil then
            window = scaled
        end
    end
    return window
end

function ST.PALADIN.setup_twist_visuals(self)
    -- Creates the twist widgets on the mainhand visuals frame. Called once from
    -- post_init, when the frames exist.
    local vf = self:get_visuals_frame("mainhand")
    if not vf or vf.twist_band then
        return
    end

    -- Window band: overlays the final (rightmost) part of the swing.
    local band = vf:CreateTexture(nil, "OVERLAY")
    band:SetDrawLayer("OVERLAY", -2)
    band:SetPoint("TOPRIGHT", vf, "TOPRIGHT", 0, 0)
    -- White base texture; the per-frame updater tints via SetVertexColor.
    band:SetColorTexture(1, 1, 1, 1)
    band:Hide()
    vf.twist_band = band

    -- Success text, centred above the bar.
    local text = vf:CreateFontString(nil, "OVERLAY")
    text:SetPoint("BOTTOM", vf, "TOP", 0, 6)
    text:SetJustifyH("CENTER")
    local db = self:get_class_table()
    local db_hand = self:get_hand_table("mainhand")
    local font_path = LSM:Fetch("font", db_hand.text_font) or STANDARD_TEXT_FONT
    text:SetFont(font_path, db.twist_success_text_size or 24, "OUTLINE")
    text:Hide()
    vf.twist_text = text
    self.PALADIN.apply_twist_text_anchor(self)

    -- Hit-rate badge (below the bar, own line so it never overlaps the
    -- success text above the bar): text built here, shown by the per-frame
    -- updater only when the badge option is on, a count exists and we are in
    -- combat.
    local badge = vf:CreateFontString(nil, "OVERLAY")
    badge:SetPoint("TOP", vf, "BOTTOM", 0, TWIST_SCORE_TEXT_OFFSET)
    badge:SetJustifyH("CENTER")
    badge:SetFont(font_path, TWIST_SCORE_TEXT_SIZE, "OUTLINE")
    badge:Hide()
    vf.twist_score_badge = badge

    -- Judgement marker line (archive bar.lua:270-272): a full-height line drawn at
    -- the swing position where Judgement comes off cooldown, like the GCD markers.
    -- Positioned per frame by update_judgement_marker below.
    local judge = vf:CreateLine()
    judge:SetDrawLayer("OVERLAY", -1)
    judge:SetThickness(JUDGEMENT_MARKER_WIDTH)
    judge:SetColorTexture(self:convert_color(JUDGEMENT_MARKER_COLOR))
    judge:Hide()
    vf.judgement_marker = judge

    -- Reseal marker line (P1): a full-height line drawn at the swing position
    -- where the running GCD clears, like the judgement marker above.
    -- Positioned per frame by update_reseal_marker below.
    local reseal = vf:CreateTexture(nil, "OVERLAY")
    reseal:SetDrawLayer("OVERLAY", -1)
    reseal:SetColorTexture(self:convert_color(RESEAL_MARKER_COLOR))
    reseal:SetWidth(RESEAL_MARKER_WIDTH)
    reseal:Hide()
    vf.reseal_marker = reseal

    -- Standalone seal icons (archive bar.lua:826-910): one slot per twist seal with
    -- a cooldown swipe and a timer text, attached right of the mainhand bar.
    -- Positioned per frame by update_seal_icons below.
    self.PALADIN.setup_seal_icons(self)

    -- Judgement of the Crusader uptime mini-bar (left of the bar) and the
    -- paladin CD icon group (left of the JotC bar): their updaters hide
    -- everything while their options are off (nil = off), so both containers
    -- are always built and the attachment chain stays stable.
    self.PALADIN.setup_jotc_bar(self)
    self.PALADIN.setup_cd_icons(self)
end

function ST.PALADIN.setup_seal_icons(self)
    -- Builds the seal-icon container on the mainhand bar frame. Called once from
    -- setup_twist_visuals. Nil-safe pre-construction: without the bar frame there
    -- is nothing to attach to.
    local vf = self:get_visuals_frame("mainhand")
    local bar_frame = self.mainhand.anchor_frame and self:get_bar_frame("mainhand")
    if not vf or not bar_frame or vf.seal_icons then
        return
    end
    local _, h = self:get_bar_visuals_width_and_height("mainhand")
    local size = h or 16
    local container = CreateFrame("Frame", addon_name .. "SealIcons", bar_frame)
    container:SetSize(size * 2 + 2, size)
    container:SetPoint("LEFT", bar_frame, "RIGHT", SEAL_ICON_GAP, 0)
    container:Hide()
    local set = { frame = container, size = size, slots = {} }
    for i = 1, #SEAL_ICON_SLOTS do
        local slot = { spell_id = SEAL_ICON_SLOTS[i].spell_id }
        local icon = container:CreateTexture(nil, "ARTWORK")
        icon:SetSize(size, size)
        icon:SetPoint("TOPLEFT", (i - 1) * (size + 2), 0)
        icon:SetTexCoord(SEAL_ICON_TEXCROP[1], SEAL_ICON_TEXCROP[2],
            SEAL_ICON_TEXCROP[3], SEAL_ICON_TEXCROP[4])
        icon:Hide()
        slot.icon = icon
        local cooldown = CreateFrame("Cooldown", nil, container, "CooldownFrameTemplate")
        cooldown:SetSize(size, size)
        cooldown:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        cooldown:SetReverse(true)
        if cooldown.SetHideCountdownNumbers then
            cooldown:SetHideCountdownNumbers(true)
        end
        cooldown:Hide()
        cooldown:Hide()
        slot.cooldown = cooldown
        -- The timer text needs its own frame above the cooldown swipe, exactly
        -- like the archive (bar.lua:863-871): a plain frame cannot out-draw a
        -- Cooldown otherwise.
        local timer_frame = CreateFrame("Frame", nil, container)
        timer_frame:SetSize(size, size)
        timer_frame:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        timer_frame:SetFrameLevel(cooldown:GetFrameLevel() + 1)
        local timer = timer_frame:CreateFontString(nil, "OVERLAY")
        timer:SetPoint("CENTER", 0, 0)
        timer:SetJustifyH("CENTER")
        timer:SetShadowColor(0, 0, 0, 1)
        timer:SetShadowOffset(2, -2)
        timer:SetFont(STANDARD_TEXT_FONT, SEAL_TIMER_TEXT_SIZE, "THICKOUTLINE")
        timer:Hide()
        slot.timer = timer
        slot.cd_start, slot.cd_full, slot.text_value = nil, nil, nil
        set.slots[i] = slot
    end
    vf.seal_icons = set
    self.PALADIN.apply_seal_icons_anchor(self)
end

function ST.PALADIN.on_bar_update(self, hand)
    -- Per-frame twist visuals, called from ST:onupdate_common via the generic class
    -- hook. Deliberately cheap and nil-safe: gates on the mainhand bar, the twist
    -- widgets and the configured options.
    if hand ~= "mainhand" then
        return
    end
    local hand_state = self[hand]
    if not (hand_state and hand_state.anchor_frame) then
        return
    end
    -- Next Action Guide (mainhand only): driven before the twist-only gates below so
    -- it also runs on Mainline-code clients (WoW Forever shows the guide but not the
    -- twist band). It never gates on st.is_mainline itself; swing activity decides.
    -- Settings that rebuild the frame (scale/position/lock) are applied when the class
    -- options change; the display toggles are read live by the UI.
    local gdb = self:get_class_table()
    if type(gdb) ~= "table" then
        -- PROPER: every widget below reads this table; with no profile there is
        -- nothing configured to draw. The swing bars still render (bars.lua owns
        -- them), so skipping the tick hides nothing live.
        return
    end
    if gdb.nextaction_icon_size ~= self.guide_ui_icon_size
        or gdb.nextaction_x ~= self.guide_ui_x
        or gdb.nextaction_y ~= self.guide_ui_y
        or gdb.nextaction_locked ~= self.guide_ui_locked then
        self.guide_ui_icon_size = gdb.nextaction_icon_size
        self.guide_ui_x = gdb.nextaction_x
        self.guide_ui_y = gdb.nextaction_y
        self.guide_ui_locked = gdb.nextaction_locked
        if st.nextaction_ui then
            st.nextaction_ui.apply_settings(self)
        end
    end
    if st.nextaction_ui then
        st.nextaction_ui.on_bar_update(self, hand)
    end
    -- Cooldown HUD: retries a lockdown-deferred creation and picks layout option
    -- changes up between the HUD driver's ticks (the row itself ticks on its own
    -- driver frame, so this is cheap). Deliberately not gated on st.is_mainline: the
    -- Forever client must show the HUD, and the Retail stand-in simply never swings.
    -- Runs after the guide tick above: the shared per-frame order is guide then
    -- HUD in all six class modules (deep-audit F8).
    if st.hud then
        st.hud.on_bar_update(self, hand)
    end
    local vf = self:get_visuals_frame(hand)
    if not vf or not vf.twist_band then
        return
    end
    if st.is_retail then
        -- Retail has no swing engine (the stand-in never reports a swing), so the twist
        -- visuals stay hidden there. WoW Forever is Mainline-code but DOES run the Forever
        -- swing engine, so it must keep the band and its text.
        vf.twist_band:Hide()
        if vf.twist_text then
            vf.twist_text:Hide()
            vf.twist_text.text_value = ""
            vf.twist_text:SetText("")
        end
        -- The judgement line and seal icons share the band's Retail gate (their
        -- updaters hide them through the same st.is_retail rule).
        self.PALADIN.update_judgement_marker(self, hand)
        self.PALADIN.update_reseal_marker(self, hand)
        self.PALADIN.update_seal_icons(self, hand)
        -- The mini-bars (JotC uptime, CD icons) share the same Retail gate.
        if vf.jotc_bar and vf.jotc_bar.frame:IsShown() then
            vf.jotc_bar.frame:Hide()
        end
        if vf.cd_icons and vf.cd_icons.frame:IsShown() then
            vf.cd_icons.frame:Hide()
        end
        return
    end

    local db = self:get_class_table()
    local now = api.get_time()
    local band = vf.twist_band
    local d = self[hand]

    -- M4/M5 state-text decision. The aura mirror itself has no separate failure
    -- signal (compat's whole-entry secret degrade returns a restricted row as absent,
    -- compat.lua:440-463), so a broken mirror read and a genuine single-seal state
    -- are indistinguishable and both stay hidden; this state covers the other
    -- unknowable: seals readable but the swing record unusable (dead/stub engine).
    -- M5 adds the lust-unknown reading: the override is armed but the last scan was
    -- inconclusive under a secret-aura regime (self.twist_lust_unknown, set by
    -- get_twist_lust_remaining).
    local seals_active = st.twist.is_twist_seal_active(self.has_soc, self.has_sor)
    local swing_usable = d and type(d.speed) == "number" and d.speed > 0
        and d.ends_at and d.start
    local band_available = db.twist_enabled ~= false
        and db.twist_marker_enabled ~= false and seals_active
    local state_text
    if band_available then
        if not swing_usable then
            state_text = TWIST_STATE_SWING_UNKNOWN
        elseif db.twist_lust_override_enabled == true
            and self.twist_lust_unknown == true and not d.is_full then
            state_text = TWIST_STATE_LUST_UNKNOWN
        end
    end

    -- Success text: fade out over its final 0.3 s, then clear it. The unknown state
    -- owns the same widget when no success animation is live.
    local text = vf.twist_text
    if text then
        local success_until = self.twist_success_until or 0
        if db.twist_enabled ~= false
            and db.twist_feedback_enabled ~= false
            and db.twist_success_text_enabled ~= false
            and now < success_until then
            text:SetAlpha(math.min(1, (success_until - now) / 0.3))
            text:Show()
        elseif designing()
            and db.twist_enabled ~= false
            and db.twist_feedback_enabled ~= false
            and db.twist_success_text_enabled ~= false then
            -- Design mode previews the success placement with the same literal
            -- the real proc paints, so the hide branch below clears it like any
            -- other text. Wins over the unknown-state text so the element being
            -- positioned is the success message, not the "..." state.
            if text.text_value ~= "Successful TWIST!" then
                text.text_value = "Successful TWIST!"
                text:SetText("Successful TWIST!")
                text:SetTextColor(
                    self:convert_color(twist_color(db, "twist_success_text_color", ST.PALADIN.twist_colors.success))
                )
            end
            text:SetAlpha(1)
            text:Show()
        elseif state_text then
            set_twist_state_text(text, state_text)
        elseif text:IsShown() then
            text:Hide()
            if text.text_value ~= "" then
                text.text_value = ""
                text:SetText("")
            end
        end
    end

    -- Judgement marker, reseal marker, seal icons and glow expiry run on every
    -- mainhand tick, independent of the twist-band gates below: a Blood-only
    -- swing still times Judgement and still shows its seals.
    self.PALADIN.update_judgement_marker(self, hand)
    self.PALADIN.update_reseal_marker(self, hand)
    self.PALADIN.update_seal_icons(self, hand)
    if (self.twist_glow_until or 0) > 0
        and (db.twist_success_glow_enabled == false or now >= self.twist_glow_until) then
        self.twist_glow_until = 0
        self.PALADIN.twist_glow_stop(self)
    end
    -- AoW+Exorcism overlap pulse: same expiry/teardown shape as the
    -- twist-success glow above (turning the option off stops it immediately).
    if (self.aow_exo_pulse_until or 0) > 0
        and (db.aow_exo_pulse_enabled ~= true or now >= self.aow_exo_pulse_until) then
        self.aow_exo_pulse_until = 0
        self.PALADIN.aow_exo_pulse_stop(self)
    end
    -- Mini-bar ticks: the JotC uptime scan first (the CD group re-anchors
    -- against its fresh visibility), then the hit-rate badge. Both hide
    -- through their own option gates, so each stays out of the way by default.
    self.PALADIN.update_jotc_bar(self, hand)
    self.PALADIN.update_cd_icons(self, hand)
    local badge = vf.twist_score_badge
    if badge then
        local attempts = self.twist_score_attempts or 0
        local lit = false
        if db.twist_score_enabled == true and self.in_combat then
            if st.cleu_supported == true and attempts > 0 then
                -- One quantised string per state change (the seal-icon text idiom):
                -- the per-frame tick does nothing while the display is unchanged.
                local quantised = string.format("%d%% (%d/%d)",
                    math.floor(((self.twist_score_successes or 0) / attempts) * 100 + 0.5),
                    self.twist_score_successes or 0, attempts)
                if badge.text_value ~= quantised then
                    badge.text_value = quantised
                    badge:SetText(quantised)
                end
                lit = true
            elseif st.cleu_supported ~= true then
                -- R3: without the classic combat log no twist attempt can ever arm
                -- (CLEU-only chain), so the numeric score would sit unexplained at
                -- nothing. Say so instead of hiding silently. Gated on the
                -- compat probe, never on st.is_mainline alone.
                local notice = "twist scoring: classic-line only"
                if badge.text_value ~= notice then
                    badge.text_value = notice
                    badge:SetText(notice)
                end
                lit = true
            end
        end
        if lit then
            if not badge:IsShown() then
                badge:Show()
            end
        else
            if badge:IsShown() then
                badge:Hide()
            end
            badge.text_value = nil
        end
    end
    if not band_available then
        self.twist_impossible = false
        band:Hide()
        return
    end
    if not swing_usable then
        -- M4: a distinct degraded state instead of the ordinary hidden "no twist
        -- now" look. Full-width, dimmed band + "seal data unknown": the swing feed
        -- (dead/stub engine, cleared cycle) cannot time the window, so nothing may
        -- be drawn at a guessed fraction.
        self.twist_impossible = false
        local w, h = self:get_bar_visuals_width_and_height(hand)
        band:SetWidth(max(1, w))
        band:SetHeight(h)
        band:SetVertexColor(self:convert_color(ST.PALADIN.twist_colors.marker, TWIST_STATE_BAND_ALPHA))
        band:Show()
        return
    end
    if d.is_full then
        self.twist_impossible = false
        band:Hide()
        return
    end

    -- Geometry: the band covers the swing's final twist-window fraction.
    local w, h = self:get_bar_visuals_width_and_height(hand)
    local window = self.PALADIN.get_twist_window_time_before_swing(self)
    local frac = math.min(1, window / d.speed)
    band:SetWidth(max(1, w * frac))
    band:SetHeight(h)

    -- Tint priority: success flash, impossible, attempt flash, armed (pulsing),
    -- inside the window, idle.
    local color, alpha
    local remaining = math.max(0, d.ends_at - now)
    -- Twist window sound cue (archive parity, off by default): fires once the bar is
    -- inside the window, latched so the per-frame tick cannot repeat it; the
    -- swing-landing handler clears the latch for the next swing.
    -- The archive cued the sound 0.20 s BEFORE the window (audio lead-in), not at it.
    if db.twist_sound_enabled and remaining <= window + 0.20 and self.twist_sound_played ~= true then
        play_twist_sound(db, db.twist_sound_choice, "pop")
        self.twist_sound_played = true
    end
    local gcd_remaining = (self.gcd and self.gcd.expires
        and math.max(0, self.gcd.expires - now)) or 0
    -- Pass raw world latency: the twist lag settings calibrate it inside the
    -- helper (the archived build's lag_calibrated_ms), so the deadzone
    -- calibration is not applied twice.
    local lag_ms = (self.latency and self.latency.world_ms) or 0
    local impossible = st.twist.is_twist_impossible(
        db.lag_detection_enabled, remaining, gcd_remaining, lag_ms,
        db.lag_multiplier, db.lag_offset, window)
    self.twist_impossible = impossible

    if db.twist_feedback_enabled ~= false
        and db.twist_success_text_enabled ~= false
        and (self.twist_success_until or 0) > now then
        color = twist_color(db, "twist_success_text_color", ST.PALADIN.twist_colors.success)
        alpha = 0.55
    elseif impossible then
        color = twist_color(db, "twist_color_cant", ST.PALADIN.twist_colors.cant)
        alpha = 0.5
    elseif db.twist_feedback_enabled ~= false
        and (self.twist_attempt_until or 0) > now then
        color = twist_color(db, "twist_color_twisting", ST.PALADIN.twist_colors.twisting)
        alpha = 0.55
    elseif (self.twist_active_seals_count or 0) >= 2 then
        color = twist_color(db, "twist_color_twisting", ST.PALADIN.twist_colors.twisting)
        alpha = 0.35 + 0.15 * math.sin(now * 8)
    elseif remaining <= window then
        color = twist_color(db, "twist_marker_color", ST.PALADIN.twist_colors.marker)
        alpha = 0.30
    else
        color = twist_color(db, "twist_marker_color", ST.PALADIN.twist_colors.marker)
        alpha = 0.15
    end
    band:SetVertexColor(self:convert_color(color, alpha))
    band:Show()
end

function ST.PALADIN.on_twist_attempt(self)
    -- Called when a twist attempt registers (two seals active on the swing).
    -- Twist hit-rate: attempts count first, ahead of every feedback gate, so
    -- the badge numbers stay truthful even with all feedback toggled off.
    -- Practice sessions never reach this handler (the CLEU path early-returns).
    self.twist_score_attempts = (self.twist_score_attempts or 0) + 1
    local persist_probe = self:get_class_table()
    -- PROPER: the attempt count below is player truth and is kept regardless; only
    -- the persisted copy is gated on a readable profile (never invent stored state).
    if type(persist_probe) == "table" and persist_probe.twist_score_persist == true then
        persist_probe.twist_score_attempts = (persist_probe.twist_score_attempts or 0) + 1
    end
    local db = self:get_class_table() or {}
    -- PROPER: {} preserves this handler's own nil-option semantics (sound opt-in
    -- stays off, glow opt-out stays on with fallback timing); the attempt is still
    -- counted and stamped above.
    -- Attempt sound is its own toggle and stays independent of the visual feedback
    -- gates below (archive parity: the archived build played it at the top of its
    -- attempt handler, ahead of the glow effect).
    if db.twist_success_sound_enabled then
        play_twist_sound(db, db.twist_success_sound_choice, "TadaFanfare")
    end
    -- Twist-success glow (archive bar.lua:568-615): fires on the attempt, ahead of
    -- the visual feedback gates below, like the sound above. The per-frame hook
    -- stops it after twist_success_glow_duration.
    if db.twist_success_glow_enabled ~= false then
        self.PALADIN.twist_glow_start(self)
        self.twist_glow_until = api.get_time() + (db.twist_success_glow_duration or 0.4)
    end
    if db.twist_enabled == false or db.twist_feedback_enabled == false then
        return
    end
    self.twist_attempt_until = api.get_time() + 0.25
end

function ST.PALADIN.on_successful_twist(self)
    -- Called when a Command proc confirms a successful twist.
    -- Twist hit-rate: successes count like the attempts, ahead of the feedback
    -- gates (they only own the visuals/sounds, never the truth). The proc
    -- stamp arms the ICD attempt discipline for the next swings.
    self.twist_last_proc_at = api.get_time()
    self.twist_score_successes = (self.twist_score_successes or 0) + 1
    local persist_probe = self:get_class_table()
    -- PROPER: the success count below is player truth and is kept regardless; only
    -- the persisted copy is gated on a readable profile (never invent stored state).
    if type(persist_probe) == "table" and persist_probe.twist_score_persist == true then
        persist_probe.twist_score_successes = (persist_probe.twist_score_successes or 0) + 1
    end
    local db = self:get_class_table() or {}
    -- PROPER: {} preserves this handler's own nil-option semantics (all feedback
    -- gates read off except the glow/text opt-outs, which fire with fallback
    -- timing); the success is still counted and stamped above.
    if db.twist_enabled == false
        or db.twist_feedback_enabled == false
        or db.twist_success_text_enabled == false then
        return
    end
    self.twist_success_until = api.get_time() + (db.twist_success_text_duration or 1.5)
    local vf = self.mainhand.anchor_frame and self:get_visuals_frame("mainhand")
    local text = vf and vf.twist_text
    if text then
        text.text_value = "Successful TWIST!"
        text:SetText("Successful TWIST!")
        text:SetTextColor(
            self:convert_color(twist_color(db, "twist_success_text_color", ST.PALADIN.twist_colors.success))
        )
        text:SetAlpha(1)
        text:Show()
    end
end

function ST.PALADIN.on_combat_exit(self)
    -- Combat-scoped twist state: orphaned extra attacks must not carry into the
    -- next fight (they would suppress its first twist attempts).
    self.twist_extra_attacks_pending = 0
    self.twist_attempt_pending = false
    -- Combat-scoped recency stamps: an ICD/proc stamp or auto stamp must not
    -- leak into the next fight (they would suppress or mistime its first
    -- reseals), and the pull-phase clock restarts with the fight.
    self.twist_last_proc_at = nil
    self.guide_last_auto_at = nil
    self.guide_combat_start_at = nil
    self.guide_was_in_combat = false
    -- Combat-scoped twist-glow state: a glow started on the killing swing must not
    -- leak its stop into the next fight's first attempt. The stop touches bar
    -- visuals, so it carries the init guard (wiring_check check 3); the state
    -- reset is safe anywhere.
    self.twist_glow_until = 0
    if self.interfaces_are_initialised then
        self.PALADIN.twist_glow_stop(self)
    end
    -- Combat-scoped next-action guide state: the guide may already be hidden when
    -- the fight ends, so it cannot rely on its own display tick to reset these.
    self.guide_melee_count = 0
    self.guide_waiting_judgement = false
    -- Combat-scoped JotC scan cache: a new fight re-scans the new target.
    self.guide_jotc_at = nil
    self.guide_jotc_value = nil
    -- Combat-scoped JotC mini-bar state: the debuff dies with the fight, and
    -- the next target re-scans from scratch.
    self.jotc_tracked = false
    self.jotc_expires = nil
    self.jotc_id = nil
    self.jotc_full = nil
    self.jotc_scan_at = nil
    -- AoW+Exorcism overlap pulse must not leak its stop into the next fight.
    -- Only a live pulse needs the teardown (expiry and option-off are owned by
    -- the per-frame block, which zeroes the latch), so a quiet combat exit
    -- costs no glow call; the stop touches bar visuals, so it carries the init
    -- guard.
    if (self.aow_exo_pulse_until or 0) > 0 then
        self.aow_exo_pulse_until = 0
        if self.interfaces_are_initialised then
            self.PALADIN.aow_exo_pulse_stop(self)
        end
    end
end

--=========================================================================================
-- Next Action Guide: live inputs for the pure st.nextaction engine
--=========================================================================================
-- The engine (nextaction.lua) is pure and reads these frozen input names:
--   speed, swing_remaining, G, gcd_remaining, twist_window, reaction, cs_remaining,
--   judge_remaining, seal, cs_delay_max, waiting_judgement, melee_count, mana_pct,
--   creature_type, filler_remaining
-- filler_remaining is one number (the chosen filler's own cooldown remaining) or nil
-- (unknown on this client). The engine also accepts the optional inputs
-- gcd_before_swing and both mana thresholds, plus the TBC opt-ins
-- judge_require_fit (always true here), jotc_remaining (the target JotC scan
-- below, nil when untracked) and target_count (1 when a target is known, nil
-- otherwise — no WoW API counts enemies; that presence rule is the plug-in
-- point a future target counter upgrades), plus the Era opt-ins era (true on
-- the Era family), forever (true on the Forever family; Twist of Light
-- alternates Command/Righteousness there, UNCONFIRMED), cs_known (the
-- client's Crusader Strike spell-book answer), target_health_pct (target hp
-- percent, nil when unknown) and how_remaining (Hammer of Wrath cooldown
-- remaining, nil when unknown); this gather fills them (the Era/Forever ones
-- only on their family, nil elsewhere). Sim-sourced recency (nil when the
-- caller cannot time it = archived): cs_hold_remaining (pull-phase CS hold
-- left, TBC only), auto_age_seconds (seconds since the last real auto),
-- reseal_auto_guard_seconds (TBC reseal age guard, TBC only).
-- Still filed (nil = archived, no source in scope): fight_remaining_pct
-- (encounter timer), time_to_pull_seconds (pull timer), seal_remaining_seconds
-- (per-SoD-build seal source; the Exodin maintained seal's role mapping is
-- UNCONFIRMED, so the SoC aura is not guessed here — the SoD-variant stack
-- timers below (soc/som_remaining_seconds, SoC 20920r5 + SoM 407798 per the
-- p8-stack APL) and the shock/wrath seal-maintenance role (p8 primary
-- UNCONFIRMED: SoR per P5/P7 predecessors vs SoM per P7 2H) are the filed
-- follow-ups, not this tick). Live since the follow-ups lane:
-- how_cast_seconds (cast-time probe), twist_mana_threshold (db key, nil =
-- off), soc_rank1_known (spell-book read), strict_sequence (SoD rune gate).
-- FCFS inputs (Wrath FCFS + SoD Exodin + three SoD-native variants; nil on
-- every other family, which the archived tree ignores as unknown names):
-- fcfs_mode ("wrath" | "sod" | "sod_stack" | "sod_shock" | "sod_wrath"),
-- ds_remaining (Divine Storm cooldown, nil while unresolved/unknown),
-- cons_remaining / exo_remaining (the filler mirror's agreed cooldowns),
-- hw_remaining (Wrath Holy Wrath cooldown, nil elsewhere), has_aow (live Art
-- of War flag, gating the Wrath Exorcism), hs_remaining / am_remaining
-- (shockadin Holy Shock / Aura Mastery, ERA-gated, nil elsewhere),
-- holy_power_stacks (1226461) + holy_power_set_known (1226460),
-- sunlight_remaining (1239543) + templar_stack_remaining (1240574, shock) +
-- templar_wrath_remaining (1226464, wrath-like), sod_t2_known (467518),
-- sod_naxx_known (1219193), sod_libram_known (1214298), am_rune_known
-- (407624), soc/som_remaining_seconds (stack dual timers) +
-- sod_dual_seal_active. The FCFS engine (evaluate_fcfs) consumes them; the
-- provider dispatch selects the engine by fcfs_mode.
-- cs_duration / judge_duration are display-only and are ignored by the engine: the full
-- length (seconds) of the last real CS / Judgement cooldown the client reported, or nil
-- when none has been seen. nextaction_ui.lua uses them for its cooldown swipes, falling
-- back to the slot's swipe_duration (the archive's constants). The seal slots' swipe
-- fields (soc_expires / soc_duration / sob_expires / sob_duration below) are the same
-- kind of display-only inputs: they carry the seal mirror's aura expiry and the length
-- LibClassicDurations reported (nil where it does not track the aura).
-- FIELD PRESENCE (M6/H6, extends the frozen spec above; do not re-derive): every
-- frozen input is assigned on every gather tick because the table is reused - a
-- skipped assignment would leak the previous tick's value. The three fields the
-- guidance itself leans on are the most constrained: `speed` is a positive number
-- whenever the guide is allowed to run at all (nextaction_ui.should_show already
-- gates on the same live mainhand fields at nextaction_ui.lua:443-447, and gather is
-- only reached after that gate at nextaction_ui.lua:664-681), `G` is never nil
-- (main.lua:get_spell_gcd_duration returns `self.gcd.spell_length or 1.5`), and
-- `seal` is always one of "soc"/"sob"/"none" (get_seal_state is total). The explicit
-- exception channel is `inputs_unknown` (M6): true whenever the swing record is not
-- usable, and the engine/UI render "…" instead of advice on it.

-- One reused input table: no per-frame allocations on the guide tick.
ST.PALADIN.guide_inputs = {}

-- Localized filler spell names, resolved lazily (name-based cooldown lookups see
-- whatever rank the player knows, unlike a fixed rank id).
local filler_name_consecration
local filler_name_exorcism

-- Judgement of the Crusader ranks, all TBC ranks (the debuff lasts 10 s per
-- LibClassicDurations/classAbilities.lua line 837). The guide's
-- Crusader-priority cue refreshes it ahead of expiry (the engine owns the lead
-- time); a nil reading means untracked and keeps the archived Blood-only cue.
local jotc_ids = get_tab({
    21183, 20188, 20300, 20301, 20302, 20303
})

-- Target-debuff re-scan throttle (seconds): the JotC scan below stays off the
-- hot path. Stale by at most this long across target swaps; the engine's
-- refresh lead absorbs it.
local JOTC_RESCAN_INTERVAL = 0.5

-- Target JotC time left (seconds) for the guide's Crusader-priority cue, or nil
-- when the target carries no JotC (or there is no target / no reading). A secret
-- entry degrades to absent and the walk continues past it (R2: no early break),
-- so a restricted row above the debuff no longer truncates the scan. The 40-row
-- cap is the TBC debuff-slot count and only bounds a misbehaving client.
local function get_guide_jotc_remaining(self, now)
    if self.guide_jotc_at and (now - self.guide_jotc_at) < JOTC_RESCAN_INTERVAL then
        return self.guide_jotc_value
    end
    self.guide_jotc_at = now
    self.guide_jotc_value = nil
    if UnitExists and UnitExists("target") then
        local best = nil
        local i = 1
        while i <= 40 do
            local name, _, _, _, _, expiration, _, _, _, spell_id =
                api.UnitAura("target", i, "HARMFUL")
            if name ~= nil then
                if aura_matches(jotc_ids, jotc_name_box, spell_id, name)
                    and expiration and expiration > 0 then
                    local remaining = expiration - now
                    if best == nil or remaining < best then
                        best = remaining
                    end
                end
            end
            i = i + 1
        end
        self.guide_jotc_value = best
    end
    return self.guide_jotc_value
end

-- Live cooldown remaining (seconds) for a spell id or name, handling the client's GCD
-- echo: GetSpellCooldown reports whichever cooldown ends later, so a real ability
-- cooldown shows its full duration while a shorter ability cooldown inside a running
-- GCD reports the GCD's ~1.5 s instead. With latch_key the last real cooldown end is
-- remembered on the addon (the archive's rule), so the true remaining time survives
-- the echo window.
-- With duration_key the client-reported LENGTH of that real cooldown is latched next to
-- the expiry (duration_key holds seconds, never an end time). The guide's cooldown
-- swipes need the length, not just the end: hardcoding it breaks on any client whose
-- Crusader Strike / Judgement cooldown differs from the archived build's. Latching it
-- here (rather than in the UI) keeps it paired with the expiry it belongs to, so both
-- always describe the same cooldown. LibClassicDurations cannot help here: it is
-- aura-based and knows nothing about spell cooldowns.
local function get_guide_cooldown_remaining(self, spell, latch_key, duration_key)
    local now = api.get_time()
    -- Name-vs-id rule: the query is the localized name on TBC, the numeric id
    -- elsewhere (filler names pass through untouched on both).
    local start_time, duration = api.GetSpellCooldown(spell_query(spell))
    if not start_time or not duration or duration == 0 then
        return 0
    end
    if duration > 1.51 then
        if latch_key then
            self[latch_key] = start_time + duration
        end
        if duration_key then
            -- A real cooldown: api.GetSpellCooldown has already normalised both shapes
            -- (classic start/duration, Mainline the SpellCooldownInfo table) and the
            -- >1.51 branch means this is not the GCD echo.
            self[duration_key] = duration
        end
        local remaining = start_time + duration - now
        if remaining < 0 then
            remaining = 0
        end
        return remaining
    end
    -- GCD echo: the real cooldown (if any) ends before this GCD does.
    if not latch_key then
        return 0
    end
    local remaining = (self[latch_key] or 0) - now
    if remaining <= 0 then
        return 0
    end
    local echo_end = start_time + duration - now
    if remaining > echo_end then
        remaining = echo_end
    end
    return remaining
end

-- Player mana percentage and the target's (localized) creature type for the filler
-- kind choice; the engine owns the Undead/Demon name table.
local function get_guide_mana_pct()
    -- Through compat, never bare: the modern clients can strip these globals.
    local power_max = api.UnitPowerMax("player")
    if type(power_max) == "number" and power_max > 0 then
        local power = api.UnitPower("player")
        if type(power) == "number" then
            return power / power_max * 100
        end
    end
    return 0
end

-- UnitCreatureType returns a localized string on every family; a restricted (secret)
-- reading cannot be indexed into the target-type table, so it degrades to unknown (nil)
-- - the engine then falls back to the Consecration suggestion, exactly like a locale
-- whose name is missing from the table.
local function read_creature_type()
    if not UnitCreatureType then
        return nil
    end
    local ctype = UnitCreatureType("target")
    if is_secret(ctype) then
        return nil
    end
    return ctype
end

local function get_guide_creature_type()
    if UnitExists and UnitExists("target") then
        return read_creature_type()
    end
    return nil
end

-- Hammer of Wrath ranks (archived docs/swedge/SwedgeTimer_TBC/st_data.lua:95-96;
-- Era knows the pre-TBC ranks). The gather resolves whichever rank this client
-- knows and reads its cooldown — the same IsSpellKnown-gate pattern as the
-- Crusader Strike talent check above. Resolved once and cached (ranks are never
-- unlearned); a miss retries at most every few seconds so level-ups resolve.
local how_ids = { 24275, 24274, 24239, 27180 }
local how_spell_id = nil
local how_retry_at = 0
local HOW_RESOLVE_RETRY_S = 5

local function resolve_how_spell_id(now)
    if how_spell_id then
        return how_spell_id
    end
    if now < how_retry_at then
        return nil
    end
    how_retry_at = now + HOW_RESOLVE_RETRY_S
    for i = 1, #how_ids do
        if is_spell_known_query(how_ids[i]) then
            how_spell_id = how_ids[i]
            return how_spell_id
        end
    end
    return nil
end

-- Hammer of Wrath cooldown remaining for the Era execute cue, or nil when the
-- spell is unknown on this client. No latch: without one the GCD echo reads as
-- ready (0), which is exactly the cue's question (HoW itself off cooldown?).
local function get_guide_how_remaining(self, now)
    local known_id = resolve_how_spell_id(now)
    if not known_id then
        return nil
    end
    return get_guide_cooldown_remaining(self, known_id)
end

-- Hammer of Wrath cast time (seconds) for the engine's instant-cast cue, or
-- nil while the spell is unknown on this client. compat's GetSpellInfo (see
-- compat.lua GetSpellInfo: the classic global, else C_Spell, else the 1.5 s
-- fallback) normalizes castTime to milliseconds on every family (the shaman
-- catalogue and the hunter Steady probe read the same 4th return), so ms/1000
-- is the seconds domain the engine compares. 0 is a real answer (instant);
-- nil is unknown = archived hp-only rule. Cached per resolved id (a rank's
-- cast time never changes); an unresolvable read retries next tick instead of
-- latching unknown. No compat change was needed: the probe already exists.
local how_cast_id, how_cast_seconds, how_cast_ready = nil, nil, false

local function get_guide_how_cast_seconds(now)
    local known_id = resolve_how_spell_id(now)
    if not known_id then
        how_cast_id, how_cast_ready = nil, false
        return nil
    end
    if how_cast_ready and how_cast_id == known_id then
        return how_cast_seconds
    end
    local name, _, _, cast_ms = api.GetSpellInfo(known_id)
    if name == nil or type(cast_ms) ~= "number"
        or cast_ms ~= cast_ms or cast_ms < 0 then
        return nil
    end
    how_cast_id, how_cast_seconds, how_cast_ready = known_id, cast_ms / 1000, true
    return how_cast_seconds
end

-- Divine Storm ranks for the FCFS branches (Wrath FCFS #3, SoD Exodin #3):
-- 53385 is the Wrath rank-1 id; the SoD rune reuses it when the book says so
-- (confirm both in-client). Same resolve-once/retry discipline as HoW above; nil
-- while unresolved, which withholds DS in the engine (never a wrong prompt).
local ds_ids = { 53385 }
local ds_spell_id = nil
local ds_retry_at = 0
local DS_RESOLVE_RETRY_S = 5

resolve_ds_spell_id = function(now)
    if ds_spell_id then
        return ds_spell_id
    end
    if now < ds_retry_at then
        return nil
    end
    ds_retry_at = now + DS_RESOLVE_RETRY_S
    for i = 1, #ds_ids do
        if is_spell_known_query(ds_ids[i]) then
            ds_spell_id = ds_ids[i]
            return ds_spell_id
        end
    end
    return nil
end

-- Holy Wrath ranks for the Wrath FCFS "if eligible" cue (Era HoW keeps how_ids
-- above): Wrath ranks first, then the classic/TBC ranks every family knows. Same
-- discipline; nil while unresolved, which withholds Holy Wrath.
local hw_ids = { 48817, 48816, 27139, 10318, 2812 }
local hw_spell_id = nil
local hw_retry_at = 0

local function resolve_hw_spell_id(now)
    if hw_spell_id then
        return hw_spell_id
    end
    if now < hw_retry_at then
        return nil
    end
    hw_retry_at = now + DS_RESOLVE_RETRY_S
    for i = 1, #hw_ids do
        if is_spell_known_query(hw_ids[i]) then
            hw_spell_id = hw_ids[i]
            return hw_spell_id
        end
    end
    return nil
end

-- Holy Shock ranks for the shockadin branch (bench/sod_paladin_variants_2026-10-19.md
-- §4; 20930r3 max rank per sim/paladin/holy_shock.go, 30 s CD, 6 s with the
-- Infusion of Light waist rune — Infusion spell id NOT in the bench file, so the
-- 6 s shape is FILED, the 30 s fallback reads from the client cooldown).
-- Max rank first; same resolve-once/retry discipline; nil while unresolved,
-- which withholds HS in the engine (never a wrong prompt). ERA-gated in the
-- gather (shockadin is SoD-only).
local hs_ids = { 20930, 20929, 20473 }
local hs_spell_id = nil
local hs_retry_at = 0

local function resolve_hs_spell_id(now)
    if hs_spell_id then
        return hs_spell_id
    end
    if now < hs_retry_at then
        return nil
    end
    hs_retry_at = now + DS_RESOLVE_RETRY_S
    for i = 1, #hs_ids do
        if is_spell_known_query(hs_ids[i]) then
            hs_spell_id = hs_ids[i]
            return hs_spell_id
        end
    end
    return nil
end

-- Shockadin Aura Mastery id (407624 legs rune per sim/paladin/aura_mastery.go;
-- Sanctified holy-multiplier, Libram-of-Sanctity-gated; APL-cited, in-client
-- UNCONFIRMED). Single id: known = rune known (no rank table).
local AM_SPELL_ID = 407624

--=========================================================================================
-- Judgement of the Crusader mini-bar + paladin cooldown icon group
--=========================================================================================
-- JotC uptime mini-bar (bench/verify_bank.md §2, FS-bar clone): the max-rank
-- debuff (21183) lasts 20 s and every plain weapon strike refreshes it to
-- full; lower ranks (TBC/classic) are fixed at 10 s with no melee refresh.
-- Authority is the 0.5 s-throttled HARMFUL aura scan on "target" (jotc_ids
-- above; JOTC_RESCAN_INTERVAL is the guide scan's own throttle, shared here);
-- on a swing, a tracked max-rank debuff extends to now + full length
-- (note_swing_landed, wired from the combat-log swing branch). Families whose
-- combat-log handler is not registered (Retail stand-in; the Retail gate below
-- also hides the bar) degrade to scan-only; the swing-activity rule decides,
-- never the family string.
--
-- CD icon group: the six core paladin cooldowns plus the racial, as one
-- adaptive inverse-swipe row left of the bar (left of the JotC mini-bar when
-- that is drawn), each icon pulsing gold through its final CD_GLOW_LEAD
-- seconds. Cooldowns are read through compat's normalised
-- api.GetSpellCooldown into absolute expiry stamps and re-scanned every
-- CD_RESCAN_INTERVAL, so per-frame remaining stays smooth without re-querying
-- every tick (duration <= 1.51 s is the GCD echo and never counts). The racial
-- is probed through the spell book over an UNCONFIRMED candidate list; an
-- unresolved probe keeps that slot hidden, never a wrong icon. Both features
-- are nil-safe and off by default (their options read == true, nil = off).
--=========================================================================================
local JOTC_BAR_GAP = 4
local JOTC_TIMER_TEXT_SIZE = 12
local JOTC_MAX_RANK_ID = 21183
local JOTC_MAX_RANK_FULL = 20
local JOTC_DEFAULT_FULL = 10
local JOTC_SCAN_INDEX_MAX = 40

local CD_ICON_GAP = 4
local CD_SLOT_SPACING = 2
local CD_RESCAN_INTERVAL = 0.5
local CD_GLOW_LEAD = 4
local CD_GLOW_KEY = "CdReadySoon"
local CD_GLOW_COLOR = {255, 215, 0, 0.9}
local CD_GLOW_LINES = 8
local CD_GLOW_FREQUENCY = 0.25
local CD_GLOW_THICKNESS = 2
local CD_RACIAL_RESOLVE_RETRY_S = 5

-- Core row order (left to right): cooldowns first, the Holy Wrath slot reads
-- its ranks through resolve_hw_spell_id above (rank-1 fallback id carries the
-- texture until the book answers), and the racial slot appends last.
local CD_CORE_SLOTS = {
    { spell_id = 31884 },             -- Avenging Wrath
    { spell_id = 642 },               -- Divine Shield
    { spell_id = 853 },               -- Hammer of Justice
    { spell_id = 1026 },              -- Hand of Protection
    { spell_id = 2812, kind = "hw" }, -- Holy Wrath (resolver on top)
    { spell_id = 633 },               -- Lay on Hands
}

-- UNCONFIRMED racial cooldown candidate ranks (bench/discover_features.md):
-- classic racial ids shared across the classic-line families; the resolver
-- picks the first one the client's spell book actually knows.
local CD_RACIAL_CANDIDATES = {
    20594,  -- Stoneform (Dwarf)
    20572,  -- Blood Fury (Orc/Troll)
    26297,  -- Berserking (Troll)
    20549,  -- War Stomp (Tauren)
    28730,  -- Arcane Torrent (Blood Elf)
    20600,  -- Every Man for Himself (Human)
    28880,  -- Gift of the Naaru (Draenei)
    7744,   -- Will of the Forsaken (Undead)
}

local cd_racial_spell_id = nil
local cd_racial_retry_at = 0

local function resolve_cd_racial(now)
    if cd_racial_spell_id then
        return cd_racial_spell_id
    end
    if now < cd_racial_retry_at then
        return nil
    end
    cd_racial_retry_at = now + CD_RACIAL_RESOLVE_RETRY_S
    if api.is_spell_known == nil then
        return nil
    end
    for i = 1, #CD_RACIAL_CANDIDATES do
        if is_spell_known_query(CD_RACIAL_CANDIDATES[i]) then
            cd_racial_spell_id = CD_RACIAL_CANDIDATES[i]
            return cd_racial_spell_id
        end
    end
    return nil
end

-- Lazy per-id texture caches (P7's rule: resolution is a rare event, not a
-- per-frame one; only non-nil answers are latched so cold spell data retries).
local jotc_icon_cache = { spell_id = nil, texture = nil }
local cd_texture_cache = {}

local function jotc_texture(spell_id)
    if spell_id == nil then
        return nil
    end
    if jotc_icon_cache.texture ~= nil and jotc_icon_cache.spell_id == spell_id then
        return jotc_icon_cache.texture
    end
    local texture = select(3, api.GetSpellInfo(spell_id))
    if texture ~= nil then
        jotc_icon_cache.spell_id = spell_id
        jotc_icon_cache.texture = texture
    end
    return texture
end

local function cd_texture(spell_id)
    if spell_id == nil then
        return nil
    end
    local cached = cd_texture_cache[spell_id]
    if cached ~= nil then
        return cached
    end
    local texture = select(3, api.GetSpellInfo(spell_id))
    if texture ~= nil then
        cd_texture_cache[spell_id] = texture
    end
    return texture
end

-- Absolute-expiry scan for the tracked debuff: the first matching rank wins
-- and patches the tracked expiry (and the rank's full length) in place. A
-- scan without a find untracks; the swing-refresh rule then can no longer
-- extend a debuff that fell off. No early break (R2): a secret entry degrades
-- to absent and the walk continues past it.
local function pulse_jotc_scan(self, now)
    if self.jotc_scan_at and (now - self.jotc_scan_at) < JOTC_RESCAN_INTERVAL then
        return
    end
    self.jotc_scan_at = now
    if not (UnitExists and UnitExists("target")) then
        self.jotc_tracked = false
        return
    end
    local i = 1
    while i <= JOTC_SCAN_INDEX_MAX do
        local name, _, _, _, _, expiration, _, _, _, spell_id =
            api.UnitAura("target", i, "HARMFUL")
        if name ~= nil then
            if aura_matches(jotc_ids, jotc_name_box, spell_id, name)
                and type(expiration) == "number" and expiration > 0 then
                self.jotc_tracked = true
                self.jotc_id = spell_id
                self.jotc_expires = expiration
                self.jotc_full = spell_id == JOTC_MAX_RANK_ID
                    and JOTC_MAX_RANK_FULL or JOTC_DEFAULT_FULL
                return
            end
        end
        i = i + 1
    end
    self.jotc_tracked = false
end

function ST.PALADIN.note_swing_landed(self)
    -- Melee-refresh rule (see the section header): a plain weapon strike
    -- extends only a live, tracked max-rank debuff to its full length. Called
    -- from the combat-log swing branch, after the extra-attack swing
    -- discipline (procedural extra attacks are not weapon strikes), ahead of
    -- the twist-attempt gates, so a swing that also arms an attempt still
    -- refreshes the debuff. No-op when nothing is tracked.
    -- Auto-age stamp (untouched by the JotC gates below): the guide's
    -- swing-recency inputs read this; combat-scoped, reset on combat exit.
    local now = api.get_time()
    self.guide_last_auto_at = now
    if self.jotc_tracked ~= true or self.jotc_id ~= JOTC_MAX_RANK_ID
        or type(self.jotc_expires) ~= "number" then
        return
    end
    if now >= self.jotc_expires then
        return
    end
    self.jotc_expires = now + (self.jotc_full or JOTC_DEFAULT_FULL)
end

function ST.PALADIN.setup_jotc_bar(self)
    -- Builds the JotC uptime mini-bar on the mainhand bar frame (seal-icon
    -- idiom: icon + inverse swipe + timer text). Called from
    -- setup_twist_visuals; nil-safe pre-construction like every sidebar here.
    local vf = self:get_visuals_frame("mainhand")
    local bar_frame = self.mainhand.anchor_frame and self:get_bar_frame("mainhand")
    if not vf or not bar_frame or vf.jotc_bar then
        return
    end
    local _, h = self:get_bar_visuals_width_and_height("mainhand")
    local size = h or 16
    local container = CreateFrame("Frame", addon_name .. "JotcBar", bar_frame)
    container:SetSize(size, size)
    container:SetPoint("RIGHT", bar_frame, "LEFT", -JOTC_BAR_GAP, 0)
    container:Hide()
    local icon = container:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetPoint("TOPLEFT", 0, 0)
    icon:SetTexCoord(SEAL_ICON_TEXCROP[1], SEAL_ICON_TEXCROP[2],
        SEAL_ICON_TEXCROP[3], SEAL_ICON_TEXCROP[4])
    icon:Hide()
    local cooldown = CreateFrame("Cooldown", nil, container, "CooldownFrameTemplate")
    cooldown:SetSize(size, size)
    cooldown:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    cooldown:SetReverse(true)
    if cooldown.SetHideCountdownNumbers then
        cooldown:SetHideCountdownNumbers(true)
    end
    cooldown:Hide()
    -- The timer text needs its own frame above the cooldown swipe (the seal
    -- icons' reason: a plain frame cannot out-draw a Cooldown otherwise).
    local timer_frame = CreateFrame("Frame", nil, container)
    timer_frame:SetSize(size, size)
    timer_frame:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
    timer_frame:SetFrameLevel(cooldown:GetFrameLevel() + 1)
    local timer = timer_frame:CreateFontString(nil, "OVERLAY")
    timer:SetPoint("CENTER", 0, 0)
    timer:SetJustifyH("CENTER")
    timer:SetShadowColor(0, 0, 0, 1)
    timer:SetShadowOffset(2, -2)
    timer:SetFont(STANDARD_TEXT_FONT, JOTC_TIMER_TEXT_SIZE, "THICKOUTLINE")
    timer:Hide()
    vf.jotc_bar = {
        frame = container, icon = icon, cooldown = cooldown, timer = timer,
        size = size, cd_start = nil, cd_full = nil, text_value = nil,
        exp_key = nil, icon_key = nil,
    }
end

function ST.PALADIN.update_jotc_bar(self, hand)
    -- Per-frame JotC mini-bar update: the throttled scan is the authority and
    -- every drawn field latches its own change (the seal-icon idiom), so a
    -- still-hidden or unchanged bar costs no frame work beyond the scan gate.
    local vf = self:get_visuals_frame(hand)
    local bar = vf and vf.jotc_bar
    if not bar then
        return
    end
    local db = self:get_class_table()
    local now = api.get_time()
    local show = false
    if db.jotc_bar_enabled == true and not st.is_retail then
        pulse_jotc_scan(self, now)
        if self.jotc_tracked == true and self.jotc_id
            and self.jotc_expires and self.jotc_expires > now then
            local texture = jotc_texture(self.jotc_id)
            if texture then
                show = true
                if bar.icon_key ~= texture then
                    bar.icon_key = texture
                    bar.icon:SetTexture(texture)
                end
                local full = self.jotc_id == JOTC_MAX_RANK_ID
                    and JOTC_MAX_RANK_FULL or JOTC_DEFAULT_FULL
                local start = self.jotc_expires - full
                if bar.cd_start ~= start or bar.cd_full ~= full then
                    bar.cd_start, bar.cd_full = start, full
                    bar.cooldown:SetCooldown(start, full)
                end
                local remaining = self.jotc_expires - now
                local quantised = math.floor(remaining)
                if bar.text_value ~= quantised then
                    bar.text_value = quantised
                    bar.timer:SetText(string.format("%d", remaining))
                end
            end
        end
    end
    if show then
        if not bar.frame:IsShown() then
            bar.frame:Show()
        end
        if not bar.icon:IsShown() then
            bar.icon:Show()
        end
        if not bar.cooldown:IsShown() then
            bar.cooldown:Show()
        end
        if not bar.timer:IsShown() then
            bar.timer:Show()
        end
    else
        -- Full clear (option off, no target, untracked, expired, or cold
        -- texture data); latched so a hidden bar costs no redraw churn.
        if bar.cd_start ~= nil or bar.text_value ~= nil then
            bar.cd_start, bar.cd_full = nil, nil
            bar.cooldown:SetCooldown(0, 0)
            bar.text_value = nil
            bar.timer:SetText("")
            bar.icon_key = nil
            bar.exp_key = nil
        end
        if bar.frame:IsShown() then
            bar.frame:Hide()
        end
        if bar.icon:IsShown() then
            bar.icon:Hide()
        end
        if bar.cooldown:IsShown() then
            bar.cooldown:Hide()
        end
        if bar.timer:IsShown() then
            bar.timer:Hide()
        end
    end
end

-- Shared CD-row helpers -----------------------------------------------------------------
-- Rebuilds the row geometry (icon frames left to right over the visible slots
-- only; the container shrinks to match). Called on visible-count and size
-- changes only, never every tick.
local function relayout_cd_row(set)
    local visible = set.visible_count or 0
    local width = 0
    if visible > 0 then
        width = visible * set.size + (visible - 1) * CD_SLOT_SPACING
    end
    set.frame:SetSize(width, set.size)
    local x = 0
    for i = 1, #set.slots do
        local slot = set.slots[i]
        if slot.visible then
            slot.icon_frame:ClearAllPoints()
            slot.icon_frame:SetPoint("TOPLEFT", x, 0)
            if not slot.icon_frame:IsShown() then
                slot.icon_frame:Show()
            end
            x = x + set.size + CD_SLOT_SPACING
        elseif slot.icon_frame:IsShown() then
            slot.icon_frame:Hide()
        end
    end
end

-- One slot's cooldown read: throttled api.GetSpellCooldown -> absolute expiry
-- on this slot, then the smooth per-frame remaining from the stamp. A GCD-echo
-- read (duration <= 1.51) and an elapsed expiry both read as ready (nil).
local function cd_slot_remaining(slot, spell_id, now)
    if slot.scan_at == nil or (now - slot.scan_at) >= CD_RESCAN_INTERVAL then
        slot.scan_at = now
        local start_time, duration = api.GetSpellCooldown(spell_query(spell_id))
        if start_time and type(duration) == "number" and duration > 1.51 then
            slot.cd_expires = start_time + duration
            slot.cd_full = duration
        else
            slot.cd_expires = nil
            slot.cd_full = nil
        end
    end
    local expires = slot.cd_expires
    if expires == nil then
        return nil, nil
    end
    local remaining = expires - now
    if remaining <= 0 then
        slot.cd_expires = nil
        slot.cd_full = nil
        return nil, nil
    end
    return remaining, slot.cd_full
end

function ST.PALADIN.setup_cd_icons(self)
    -- Builds the CD icon row on the mainhand bar frame, one slot per entry in
    -- CD_CORE_SLOTS plus always one racial slot (hidden until the book probe
    -- resolves one). Anchored left of the JotC mini-bar when that built; the
    -- per-frame updater re-anchors if the two widgets are not paired.
    local vf = self:get_visuals_frame("mainhand")
    local bar_frame = self.mainhand.anchor_frame and self:get_bar_frame("mainhand")
    if not vf or not bar_frame or vf.cd_icons then
        return
    end
    local _, h = self:get_bar_visuals_width_and_height("mainhand")
    local size = h or 16
    local container = CreateFrame("Frame", addon_name .. "CdIcons", bar_frame)
    local set = { frame = container, size = size, slots = {},
        visible_count = -1, anchor = nil }
    if vf.jotc_bar and vf.jotc_bar.frame then
        set.anchor = "jotc"
        container:SetPoint("RIGHT", vf.jotc_bar.frame, "LEFT", -CD_ICON_GAP, 0)
    else
        set.anchor = "bar"
        container:SetPoint("RIGHT", bar_frame, "LEFT", -CD_ICON_GAP, 0)
    end
    for i = 1, #CD_CORE_SLOTS do
        set.slots[i] = { spell_id = CD_CORE_SLOTS[i].spell_id,
            kind = CD_CORE_SLOTS[i].kind }
    end
    set.slots[#CD_CORE_SLOTS + 1] = { spell_id = nil, kind = "racial" }
    for i = 1, #set.slots do
        local slot = set.slots[i]
        local icon_frame = CreateFrame("Frame", nil, container)
        icon_frame:SetSize(size, size)
        icon_frame:Hide()
        slot.icon_frame = icon_frame
        local icon = icon_frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(size, size)
        icon:SetPoint("TOPLEFT", 0, 0)
        icon:SetTexCoord(SEAL_ICON_TEXCROP[1], SEAL_ICON_TEXCROP[2],
            SEAL_ICON_TEXCROP[3], SEAL_ICON_TEXCROP[4])
        icon:Hide()
        slot.icon = icon
        local cooldown = CreateFrame("Cooldown", nil, icon_frame,
            "CooldownFrameTemplate")
        cooldown:SetSize(size, size)
        cooldown:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        cooldown:SetReverse(true)
        if cooldown.SetHideCountdownNumbers then
            cooldown:SetHideCountdownNumbers(true)
        end
        cooldown:Hide()
        slot.cooldown = cooldown
        slot.visible = false
        slot.texture_key = nil
        slot.scan_at = nil
        slot.cd_expires = nil
        slot.cd_full = nil
        slot.cd_start = nil
        slot.glowing = false
    end
    vf.cd_icons = set
end

function ST.PALADIN.update_cd_icons(self, hand)
    -- Per-frame CD row update: visibility rides the option (nil = off) and the
    -- Retail gate; every state change is latched (texture, swipe, glow,
    -- geometry, attachment), so a steady row costs no frame churn.
    local vf = self:get_visuals_frame(hand)
    local set = vf and vf.cd_icons
    if not set then
        return
    end
    local db = self:get_class_table()
    local now = api.get_time()
    local enabled = db.cd_icons_enabled == true and not st.is_retail
    -- Keep sitting left of the JotC mini-bar whenever that is drawn; option-off
    -- or hidden, the row hugs the bar instead.
    local bar_frame = self.mainhand.anchor_frame and self:get_bar_frame("mainhand")
    local jotc = vf.jotc_bar
    local want_anchor = (jotc and jotc.frame and jotc.frame:IsShown()) and "jotc" or "bar"
    if set.anchor ~= want_anchor and bar_frame then
        set.anchor = want_anchor
        set.frame:ClearAllPoints()
        if want_anchor == "jotc" and jotc.frame then
            set.frame:SetPoint("RIGHT", jotc.frame, "LEFT", -CD_ICON_GAP, 0)
        else
            set.frame:SetPoint("RIGHT", bar_frame, "LEFT", -CD_ICON_GAP, 0)
        end
    end
    -- The racial slot fills from the book probe (UNCONFIRMED candidates); a
    -- pending probe leaves it hidden without churning the spelling slots.
    if enabled then
        local racial = resolve_cd_racial(now)
        local racial_slot = set.slots[#set.slots]
        if racial and racial_slot and racial_slot.kind == "racial"
            and racial_slot.spell_id ~= racial then
            racial_slot.spell_id = racial
        end
        local _, h = self:get_bar_visuals_width_and_height(hand)
        local size = h or 16
        if size ~= set.size then
            set.size = size
            for i = 1, #set.slots do
                local slot = set.slots[i]
                slot.icon_frame:SetSize(size, size)
                slot.icon:SetSize(size, size)
                slot.cooldown:SetSize(size, size)
            end
        end
    end
    for i = 1, #set.slots do
        local slot = set.slots[i]
        local eff_id = slot.spell_id
        if slot.kind == "hw" then
            eff_id = resolve_hw_spell_id(now) or slot.spell_id
        end
        local texture = enabled and cd_texture(eff_id) or nil
        local stop_glow = true
        if texture then
            if slot.texture_key ~= texture then
                slot.texture_key = texture
                slot.icon:SetTexture(texture)
            end
            if not slot.icon:IsShown() then
                slot.icon:Show()
            end
            local remaining = enabled and cd_slot_remaining(slot, eff_id, now) or nil
            if remaining then
                stop_glow = false
                slot.visible = true
                local start = slot.cd_expires - slot.cd_full
                local full = slot.cd_full
                if slot.cd_start ~= start or slot.cd_run_full ~= full then
                    slot.cd_start, slot.cd_run_full = start, full
                    slot.cooldown:SetCooldown(start, full)
                end
                if not slot.cooldown:IsShown() then
                    slot.cooldown:Show()
                end
                -- Gold pulse through the final CD_GLOW_LEAD seconds.
                if remaining <= CD_GLOW_LEAD and not slot.glowing then
                    slot.glowing = true
                    LCG.PixelGlow_Start(slot.icon_frame,
                        {self:convert_color(CD_GLOW_COLOR)},
                        CD_GLOW_LINES,
                        CD_GLOW_FREQUENCY,
                        nil,
                        CD_GLOW_THICKNESS,
                        0,
                        0,
                        false,
                        CD_GLOW_KEY
                    )
                end
            else
                slot.visible = false
                if slot.cd_start ~= nil then
                    slot.cd_start, slot.cd_run_full = nil, nil
                    slot.cooldown:SetCooldown(0, 0)
                end
                if slot.cooldown:IsShown() then
                    slot.cooldown:Hide()
                end
            end
        else
            slot.visible = false
            slot.texture_key = nil
            if slot.icon:IsShown() then
                slot.icon:Hide()
            end
            if slot.cd_start ~= nil then
                slot.cd_start, slot.cd_run_full = nil, nil
                slot.cooldown:SetCooldown(0, 0)
            end
            if slot.cooldown:IsShown() then
                slot.cooldown:Hide()
            end
        end
        if stop_glow and slot.glowing then
            slot.glowing = false
            LCG.PixelGlow_Stop(slot.icon_frame, CD_GLOW_KEY)
        end
    end
    local visible = 0
    for i = 1, #set.slots do
        if set.slots[i].visible then
            visible = visible + 1
        end
    end
    if set.visible_count ~= visible then
        set.visible_count = visible
        relayout_cd_row(set)
    end
    local any_shown = enabled and visible > 0
    if any_shown then
        if not set.frame:IsShown() then
            set.frame:Show()
        end
    elseif set.frame:IsShown() then
        set.frame:Hide()
    end
end

-- Target health percent for the Era execute cue, or nil when there is no
-- target or the client cannot answer (secret reads degrade to nil in compat,
-- like every other gather reading here).
local function get_guide_target_health_pct()
    if not (UnitExists and UnitExists("target")) then
        return nil
    end
    local health = api.UnitHealth("target")
    local health_max = api.UnitHealthMax("target")
    if type(health) ~= "number" or type(health_max) ~= "number"
        or health_max <= 0 then
        return nil
    end
    return health / health_max * 100
end

-- Repoint the FCFS slot textures at the resolved ranks once the book answers
-- (hunter resolve_guide_icons pattern): the sob slot at Divine Storm, the how
-- slot at Holy Wrath. Unknown keeps the fallback, never a blank swap; families
-- whose book lacks both keep the shipped ids bit-identically. Runs once from
-- post_init, before the guide frame builds its icons. Defined after the DS/HW
-- resolvers above (lexical locals) and before the guide table below.
function ST.PALADIN.resolve_guide_icons()
    local now = api.get_time()
    local ds_id = (is_wrath_family or is_era_family) and resolve_ds_spell_id(now) or nil
    local hw_id = is_wrath_family and resolve_hw_spell_id(now) or nil
    if not ds_id and not hw_id then
        return
    end
    local slots = ST.PALADIN.guide.slots
    for i = 1, #slots do
        local slot = slots[i]
        if ds_id and slot.key == "sob" then
            slot.spell_id = ds_id
        end
        if hw_id and slot.key == "how" then
            slot.spell_id = hw_id
        end
    end
end

-- The rotation order the running client plays: the FCFS mode the live gather
-- decided on, or the twist tree when there is none (the twist tree's order id
-- is "twist"). One source, so the practice rotation slice and the practice
-- decision can never name different orders.
--
-- The practice-side state and helpers live on the MODULE TABLE, not in file
-- locals: classes/paladin.lua already sits at the Lua 5.1 ceiling of 200 locals
-- per function (the main chunk IS one function), so a new file-local would not
-- load at all. The names are internal helpers of this section.
ST.PALADIN.practice_running_order = nil

-- The order id of one FCFS mode (nil = the twist tree).
function ST.PALADIN.practice_order_for_mode(mode)
    if type(mode) == "string" and mode ~= "" then
        return mode
    end
    return "twist"
end

function ST.PALADIN.gather_guide_inputs(self, out)
    local na = st.nextaction
    local now = api.get_time()
    local d = self.mainhand
    local gcd = self.gcd
    local db = self:get_class_table() or {}
    local inputs = out or self.PALADIN.guide_inputs
    -- PROPER: {} reads every tunable as nil, which is exactly the engine's
    -- documented default for each; the live swing/GCD/aura reads below still run.

    -- Swing state and clock (seconds). ends_at and the GCD/aura stamps all live in
    -- the GetTime() domain, which api.get_time() shares, so the comparisons hold.
    inputs.speed = (d and d.speed) or 0
    inputs.swing_remaining = math.max(0, ((d and d.ends_at) or now) - now)
    inputs.G = self:get_spell_gcd_duration()
    -- M6: the explicit unusable-inputs signal the engine threads into out and the
    -- guide renders as "…". The swing record is the guide's clock: without a live
    -- one (dead engine, cleared cycle, full bar) every landmark below is fiction.
    -- G and seal cannot be unknown here (see the field-presence note above).
    inputs.inputs_unknown = not (d and type(d.speed) == "number" and d.speed > 0
        and d.ends_at and d.start and not d.is_full)
    inputs.gcd_remaining = (gcd and gcd.expires and math.max(0, gcd.expires - now)) or 0
    inputs.twist_window = self.PALADIN.get_twist_window_time_before_swing(self)
    inputs.reaction = (db.nextaction_reaction_time_ms or 100) / 1000
    -- Era family flag for the engine's Era branch (false everywhere else, so
    -- all other families keep the archived behaviour bit-identically).
    inputs.era = is_era_family
    -- Forever family flag for the engine's Forever branch (false everywhere
    -- else, so all other families keep the archived behaviour bit-identically).
    inputs.forever = is_forever_family
    -- TBC: researched CS delay is under 1 s; the archived 1.7 s default
    -- over-delays CS. CONFLICT: Wrath wants ~0 (no twist to protect) — one
    -- default cannot serve both; the option range is unchanged. See the same
    -- note on the engine fallback in nextaction.lua.
    inputs.cs_delay_max = (db.nextaction_cs_max_delay_ms or 900) / 1000

    -- Active seal for the decision tree ("soc" | "sob" | "none"; Command's
    -- remaining time guards the engine's reseal branch). Era feeds the twist
    -- seal (Righteousness; Blood does not exist there) into the engine's
    -- twist-seal position, reusing its landmarks unchanged.
    if na then
        local twist_seal_up = self.has_sob
        -- Forever feeds Righteousness into the twist-seal position (Twist of
        -- Light alternates Command/Righteousness, UNCONFIRMED): same engine
        -- landmarks, Era texture on the guide slot.
        if (inputs.era or inputs.forever) and self.has_sor then
            twist_seal_up = true
        end
        local soc_up = self.has_soc
        if inputs.forever then
            -- Echo-aura maintenance (Twist of Light recasts a seal whose Echo
            -- is inactive): an explicitly inactive Echo degrades that seal to
            -- down, so the tree recasts it. nil (untracked, including the
            -- empty-tables present) keeps the archived aura value.
            if self.has_echo_command == false then
                soc_up = false
            end
            if self.has_echo_twist == false then
                twist_seal_up = false
            end
        end
        inputs.seal = na.get_seal_state(soc_up, twist_seal_up,
            self.soc_expires and (self.soc_expires - now))
    else
        inputs.seal = "none"
    end

    -- Holy Strike (Forever): the class resolves the id by NAME (the discipline
    -- above) and asks the spell book about it; nil = unknown (the client has
    -- not confirmed the id yet), true/false = the book's own answer. The
    -- engine does not read it yet - the frozen ten guide slots have no Holy
    -- Strike slot and a slot-budget ruling is owed before one is added - so
    -- this is a plug-in point, not a behaviour change.
    inputs.holy_strike_known = self.holy_strike_known

    -- Display-only seal swipe fields for the guide frame (its cooldown_key slot
    -- swipes read <key>_expires / <key>_duration from these inputs; the engine
    -- ignores them). Assigning nil is the clear: exactly what a dropped seal, the
    -- practice mirror and the pre-tracking window want. Era drives the
    -- twist-seal swipe from the Righteousness aura (that slot's icon is
    -- Righteousness there); every other family keeps Blood.
    inputs.soc_expires = self.soc_expires
    inputs.soc_duration = self.soc_duration
    inputs.sob_expires = self.sob_expires
    inputs.sob_duration = self.sob_duration
    if inputs.era or inputs.forever then
        inputs.sob_expires = self.sor_expires
        inputs.sob_duration = self.sor_duration
    end

    -- Crusader Strike / Judgement cooldowns. The archive's rules: an unknown CS
    -- talent means the engine must never see CS available (999 s), and Judgement
    -- needs no latch of its own. cs_known rides the inputs too: the engine's
    -- Era branch keys its no-CS guarantee off it (the client's spell book, not
    -- the 999 sentinel). The swipe LENGTHs ride along in cs_duration /
    -- judge_duration (display-only; see the input-contract comment above) and are read
    -- after the calls, so they describe the cooldown this same tick reported.
    local cs_known = na and na.CS_SPELL_ID and is_spell_known_query(na.CS_SPELL_ID) or false
    inputs.cs_known = cs_known
    if na and na.CS_SPELL_ID then
        if cs_known then
            inputs.cs_remaining = get_guide_cooldown_remaining(self, na.CS_SPELL_ID,
                "guide_cs_expires", "guide_cs_duration")
        else
            inputs.cs_remaining = 999
        end
        inputs.judge_remaining = na.JUDGEMENT_SPELL_ID
            and get_guide_cooldown_remaining(self, na.JUDGEMENT_SPELL_ID, nil,
                "guide_judge_duration") or 0
    else
        inputs.cs_remaining = 999
        inputs.judge_remaining = 0
    end
    -- Read after both lookups so a length latched on this very tick is the one the
    -- guide draws. nil simply means "nothing observed yet": the display falls back to
    -- its own constant.
    inputs.cs_duration = self.guide_cs_duration
    inputs.judge_duration = self.guide_judge_duration
    inputs.hs_duration = self.guide_hs_duration

    -- Pull-phase clock (TBC sim "Delay Major CDs" 11 s): the combat-start latch
    -- below clocks the fight; inside the hold the engine suppresses the CS
    -- override. nil everywhere else (non-TBC, stale clock) = archived.
    if self.in_combat == true then
        if self.guide_was_in_combat ~= true then
            self.guide_combat_start_at = now
        end
    else
        self.guide_combat_start_at = nil
    end
    self.guide_was_in_combat = self.in_combat == true
    inputs.cs_hold_remaining = nil
    if is_tbc_family and na and na.TBC_PULL_CS_HOLD_SECONDS
        and type(self.guide_combat_start_at) == "number" then
        local hold_left = na.TBC_PULL_CS_HOLD_SECONDS
            - (now - self.guide_combat_start_at)
        if hold_left > 0 then
            inputs.cs_hold_remaining = hold_left
        end
    end

    -- Swing recency (TBC reseal guard + Forever HoW window): seconds since the
    -- last real auto landed (the CLEU swing stamp; nil until the first one).
    -- Practice-safe: the sim owns no CLEU stamp, so practice ticks read
    -- unknown = archived. The guard itself arms on TBC only (the sim-sourced
    -- family); the age rides everywhere the stamp exists.
    inputs.auto_age_seconds = nil
    if type(self.guide_last_auto_at) == "number"
        and not (st.practice_ui and st.practice_ui.is_active()) then
        inputs.auto_age_seconds = math.max(0, now - self.guide_last_auto_at)
    end
    inputs.reseal_auto_guard_seconds = nil
    if is_tbc_family and na and na.TBC_RESEAL_AUTO_GUARD_SECONDS then
        inputs.reseal_auto_guard_seconds = na.TBC_RESEAL_AUTO_GUARD_SECONDS
    end
    -- Filed inputs (no source in scope yet; nil = archived until those lanes
    -- land): fight_remaining_pct needs a boss-HP / encounter-timer source,
    -- time_to_pull_seconds needs a pull timer (main.lua), seal_remaining_seconds
    -- needs a per-SoD-build seal source (provider map + guide slot +
    -- nextaction_ui; the Exodin maintained seal's role mapping is UNCONFIRMED,
    -- so the SoC aura is not guessed here).
    inputs.fight_remaining_pct = nil
    inputs.time_to_pull_seconds = nil
    inputs.seal_remaining_seconds = nil
    -- Mana-sustain governor groundwork (sim/audit: twisting ooms in 1-2 min
    -- without support): the engine plug reads inputs.twist_mana_threshold
    -- (nil = off = archived). The value, widget and default belong to the
    -- options lane; this only forwards a set key. Filed need: options widget
    -- + default for db.twist_mana_threshold_pct (percent, nil = off).
    local mana_cap = db.twist_mana_threshold_pct
    if type(mana_cap) ~= "number" or mana_cap ~= mana_cap then
        mana_cap = nil
    end
    inputs.twist_mana_threshold = mana_cap
    -- SoC Rank-1 reader (min/max consensus; sim APLs cast rank 1): rank-1 id
    -- 20375 in the book. Verified live: api.is_spell_known rank probes gate
    -- CS/DS/HoW the same way. The advice slot + option are filed.
    inputs.soc_rank1_known = na and na.SOC_ID
        and is_spell_known_query(na.SOC_ID) or false

    -- Filler availability. The engine consumes one cooldown value: the remaining
    -- time of the filler it would pick. That pick is mirrored here from the data the
    -- engine itself uses (its own target-type table; the mana thresholds passed
    -- below), so the two sides always agree. A nil value means the spell is unknown
    -- on this client, i.e. the archive's known=false.
    inputs.melee_count = self.guide_melee_count or 0
    inputs.mana_pct = get_guide_mana_pct()
    inputs.creature_type = get_guide_creature_type()
    -- TBC opt-ins (engine defaults preserve the archive; constants, no options):
    -- the judge-feasibility gate is always on. Single-target is reported from
    -- target presence: no WoW API counts enemies, so a known target reads as
    -- single-target (Consecration withheld as AoE-only) while no target reading
    -- leaves the archived suggestion; a future target counter upgrades this to
    -- the real count (> 1 re-enables Consecration). Reporting nil (not 1) with
    -- no target also keeps provider-unaware callers bit-identical. Exorcism vs
    -- Undead/Demon is unaffected either way.
    inputs.judge_require_fit = true
    inputs.target_count = inputs.creature_type ~= nil and 1 or nil
    inputs.jotc_remaining = get_guide_jotc_remaining(self, now)
    inputs.gcd_before_swing = self:get_gcd_time_before_swing_seconds("mainhand")
    inputs.mana_consecration_threshold = db.nextaction_filler_mana_consecration or 35
    inputs.mana_exorcism_threshold = db.nextaction_filler_mana_exorcism or 30
    local consecration_remaining
    local exorcism_remaining
    if na then
        if filler_name_consecration == nil and na.CONSECRATION_SPELL_ID then
            filler_name_consecration = api.GetSpellInfo(na.CONSECRATION_SPELL_ID)
        end
        if filler_name_consecration then
            consecration_remaining = get_guide_cooldown_remaining(self, filler_name_consecration)
        end
        if filler_name_exorcism == nil and na.EXORCISM_SPELL_ID then
            filler_name_exorcism = api.GetSpellInfo(na.EXORCISM_SPELL_ID)
        end
        if filler_name_exorcism then
            exorcism_remaining = get_guide_cooldown_remaining(self, filler_name_exorcism)
        end
    end
    inputs.filler_remaining = nil
    if na and inputs.creature_type and na.exorcism_target_types
        and na.exorcism_target_types[inputs.creature_type] then
        if inputs.mana_pct > inputs.mana_exorcism_threshold then
            inputs.filler_remaining = exorcism_remaining
        end
    elseif na and inputs.mana_pct > inputs.mana_consecration_threshold then
        inputs.filler_remaining = consecration_remaining
    end

    -- FCFS inputs (Wrath FCFS + SoD Exodin + three SoD-native variants; nil on
    -- every other family, which the archived tree ignores as unknown names, so
    -- it runs bit-identically there).
    -- cons/exo reuse the filler mirror's agreed cooldowns above (no second client
    -- query); DS/Holy Wrath resolve here (nil while the book is cold or the spell
    -- unknown, which withholds them); has_aow is the live Art of War flag that
    -- gates the Wrath Exorcism. SoD detection is rune spells only, never version
    -- strings: the ERA family client with a book entry Era-base cannot have
    -- (CS rune via cs_known, DS rune via the resolve, 348700 Seal of the Martyr
    -- via the probe). Candidate ids are best-knowledge (confirm in-client); a
    -- miss reads unknown and the Era branch stands, never a wrong prompt.
    local ds_id = (is_wrath_family or is_era_family) and resolve_ds_spell_id(now) or nil
    inputs.ds_remaining = ds_id and get_guide_cooldown_remaining(self, ds_id) or nil
    local hw_id = is_wrath_family and resolve_hw_spell_id(now) or nil
    inputs.hw_remaining = hw_id and get_guide_cooldown_remaining(self, hw_id) or nil
    -- The WotLK APL's UTILITY BAND (bench/paladin_apl_utility_build_2026-10-20.md
    -- §2): Hand of Reckoning (the APL's i=1) and Hammer of Wrath (i=2). Both
    -- ask the client's own spell book first - a build without the talent (or
    -- without the spell) answers "unknown" and is never prompted (the
    -- unknown-hides rule). The cooldown read is api.GetSpellCooldown through
    -- the class's own helper (the TBC-name rule never applies here: the band
    -- is Wrath-only).
    if is_wrath_family then
        local hor_id = ST.PALADIN.APL_UTILITY.hor.id
        local howw_id = ST.PALADIN.APL_UTILITY.how_wrath.id
        inputs.hor_remaining = is_spell_known_query(hor_id)
            and get_guide_cooldown_remaining(self, hor_id) or nil
        inputs.how_wrath_remaining = is_spell_known_query(howw_id)
            and get_guide_cooldown_remaining(self, howw_id) or nil
    else
        inputs.hor_remaining = nil
        inputs.how_wrath_remaining = nil
    end
    local fcfs_family = is_wrath_family or is_era_family
    inputs.cons_remaining = fcfs_family and consecration_remaining or nil
    inputs.exo_remaining = fcfs_family and exorcism_remaining or nil
    inputs.has_aow = self.has_aow == true
    local is_sod = is_sod_client(cs_known, ds_id)
    -- SoD-native variant inputs (bench/sod_paladin_variants_2026-10-19.md §7;
    -- all APL-cited, in-client UNCONFIRMED). ERA-gated + rune/item-gated
    -- (never client-version): nil on every other family, and nil while the
    -- book/auras are cold, which withholds the variant gates (unknown-hides).
    -- Holy Shock ranks (20473/20929/20930): max-first resolve, ERA-gated.
    local hs_id = is_era_family and resolve_hs_spell_id(now) or nil
    inputs.hs_remaining = hs_id and get_guide_cooldown_remaining(self, hs_id,
        "guide_hs_expires", "guide_hs_duration") or nil
    -- Aura Mastery (407624): rune-known + live cooldown, ERA-gated.
    local am_known = is_era_family and is_spell_known_query(AM_SPELL_ID)
    inputs.am_rune_known = am_known
    inputs.am_remaining = (is_era_family and am_known)
        and get_guide_cooldown_remaining(self, AM_SPELL_ID) or nil
    -- Holy-Power stacks (1226461 count) + set-known (1226460 presence).
    local hp = self.holy_power_stacks
    if type(hp) ~= "number" or hp ~= hp then
        hp = nil
    end
    inputs.holy_power_stacks = is_era_family and hp or nil
    inputs.holy_power_set_known = is_era_family and self.has_hp_set == true
    -- Sunlight (1239543) / Templar-stack (1240574, shock) / Templar-wrath
    -- (1226464, wrath-like) remaining seconds.
    local function rem(expires)
        if type(expires) == "number" and expires > now then
            return expires - now
        end
        return nil
    end
    inputs.sunlight_remaining = is_era_family and rem(self.sunlight_expires) or nil
    inputs.templar_stack_remaining = is_era_family and rem(self.templar_stack_expires) or nil
    inputs.templar_wrath_remaining = is_era_family and rem(self.templar_wrath_expires) or nil
    -- Set/item gates: S03 T2 Ret 2P (467518, wrath Judge), Naxx Ret 6P
    -- (1219193, stack HW), Libram of Sanctity (1214298, shock AM).
    inputs.sod_t2_known = is_era_family and self.has_sod_t2 == true
    inputs.sod_naxx_known = is_era_family and self.has_sod_naxx == true
    inputs.sod_libram_known = is_era_family and self.has_sod_libram == true
    -- Stack dual-seal timers (SoC 20920r5 via soc_expires + SoM 407798 via
    -- sob_expires, bench §3; ERA-gated, nil elsewhere/while cold).
    inputs.soc_remaining_seconds = is_era_family and rem(self.soc_expires) or nil
    inputs.som_remaining_seconds = is_era_family and rem(self.sob_expires) or nil
    inputs.sod_dual_seal_active = is_era_family
        and self.has_soc == true and self.has_sob == true
    -- Variant selection (SoD-native, most-distinctive signal first; nil-safe,
    -- no default-visible change: without the new signals this reads "sod",
    -- the shipped Exodin):
    --   shockadin: Holy Shock known (spellpower caster, §4-§5);
    --   wrath-like: T2-2pc or wrath-Templar aura known (§6);
    --   stack: dual seals live (§3, maintain-both playstyle);
    --   else Exodin.
    -- On-use item roles (241037 opener, 241241 upkeep) are NOT probed: the
    -- warcraftdb titles ("Abandoned Experiment", "Lucky Doubloon") do not
    -- match on-use-trinket roles (bench §8, NAME UNCONFIRMED) — the build
    -- lane must resolve via sim items.go/itemhelpers before any icon/name
    -- is wired (filed, no guess here).
    local hs_known = hs_id ~= nil
    local wrath_signal = inputs.sod_t2_known == true
        or inputs.templar_wrath_remaining ~= nil
    local sod_mode = nil
    if is_sod then
        sod_mode = "sod"
        if hs_known then
            sod_mode = "sod_shock"
        elseif wrath_signal then
            sod_mode = "sod_wrath"
        elseif inputs.sod_dual_seal_active == true then
            sod_mode = "sod_stack"
        end
    end
    inputs.fcfs_mode = is_wrath_family and "wrath" or sod_mode
    -- The rotation order the running client plays, published for the practice
    -- surface (ST.PALADIN.practice_rotation_for): the live gather is the only
    -- place that knows which SoD variant the client plays, so the practice
    -- slice and the practice decision read the SAME name from here. The twist
    -- tree (no FCFS mode) answers "twist".
    ST.PALADIN.practice_running_order = ST.PALADIN.practice_order_for_mode(inputs.fcfs_mode)
    -- Shockadin Holy Shock known flag (provider-local; the engine reads the
    -- HS cooldown + stacks, this documents the signal for pins).
    inputs.sod_hs_known = hs_known
    -- strictSequence hard-wait (SoD twist APLs): a held twist on a strict
    -- build waits the swing out instead of filling. Rune-gated, never a
    -- version string; the frame paints out.hard_wait as WAIT
    -- (nextaction_ui.lua display_active).
    inputs.strict_sequence = is_sod

    -- Judgement-wait carry from the engine's previous output (kept by the display).
    inputs.waiting_judgement = self.guide_waiting_judgement and true or false
    -- Era/Forever execute inputs (nil everywhere else: the engine only reads
    -- them on Era/Forever, so all other families keep the archived behaviour
    -- bit-identically). Forever reuses the window: the beta Ret ST lists
    -- Hammer of Wrath below 20% (UNCONFIRMED).
    -- how_remaining is nil while the spell is unknown on this client.
    -- The TARGET HEALTH also reaches the WotLK client, where the APL's
    -- Hammer of Wrath row (48806) is an execute-phase cast (the sim's own
    -- ExtraCastCondition: sim.IsExecutePhase20()); the FCFS engine asks for it
    -- only below 20 %, and an unknown health withholds it.
    if is_era_family or is_forever_family or is_wrath_family then
        inputs.target_health_pct = get_guide_target_health_pct()
    else
        inputs.target_health_pct = nil
    end
    if is_era_family or is_forever_family then
        inputs.how_remaining = get_guide_how_remaining(self, now)
        inputs.how_cast_seconds = get_guide_how_cast_seconds(now)
    else
        inputs.how_remaining = nil
        inputs.how_cast_seconds = nil
    end
    return inputs
end

--=========================================================================================
-- Next Action Guide: the paladin provider for the generic guide frame
--=========================================================================================
-- Implements the frozen ST.<CLASS>.guide contract documented in nextaction_ui.lua's
-- header. The decision engine stays pure (st.nextaction) and the live reads stay in
-- gather_guide_inputs above; this table is the glue: it names the display slots, maps
-- the engine's flags onto slot keys (the frame only knows keys) and publishes the
-- rotation source the frame paints below the icons.
--
-- TWELVE slots (cs, soc, sob, twist, judge, consecration, exorcism, how,
-- holy_shock, aura_mastery, hor, how_wrath). The contract expects six or fewer
-- per class; the composite twist cue and the execute cue are the paladin's
-- extra four, kept because they are the shipped visuals (the twist is one
-- icon: Command full width with the half-width, centre-cropped Blood icon
-- over its right half - the WA's 'twist 1/2' + 'twist 2/2' pair). The
-- shockadin HS/AM slots render only when the engine prompts them through the
-- generic out.filler_slot mapping (unknown-hides: no shock signal, no prompt).
-- The last two are the WotLK APL's utility band (Hand of Reckoning, Hammer of
-- Wrath): the count pin was re-cut with them (the HU-10 precedent - a count
-- pin must match the shipped slot set, not a stale one).
--
-- Display specifics are exactly the shipped frame's: the 45x45 stacked action icons
-- (levels 1/3/5), the composite twist at 8/9, the 22.5x24.9 judgement cue at
-- (-9,-10) with its Pixel glow, the five 45x45 filler icons (zoom 0.2 / 0.15 x4)
-- with their FILLER captions, and the Blood opener dimmed to 0.5 while idle. Swipe
-- fallbacks keep the archive's constants (CS 6 s, Judgement 8 s, seals 30 s); the
-- seal swipes drive always (from the aura expiries) while the CS / Judgement swipes
-- only drive while their icon shows - the shipped display's split.
ST.PALADIN.guide = {
    slots = {
        -- Crusader Strike (archive icon_cs).
        { key = "cs", spell_id = 35395, cooldown_key = "cs",
            name_suffix = "IconCS", level = 1, swipe_duration = 6 },
        -- Seal of Command (archive icon_command): reseal icon + the aura swipe.
        { key = "soc", spell_id = 20375, cooldown_key = "soc",
            name_suffix = "IconCommand", level = 3, swipe_duration = 30,
            swipe_always = true },
        -- Seal of Blood (archive icon_blood): the ride icon + the aura swipe; the
        -- idle opener shows this icon at half alpha. On Era and Forever the
        -- icon is the twist seal (Righteousness): same slot, same key, Era
        -- texture. On Wrath
        -- the slot carries Divine Storm instead (same slot, same key, DS texture;
        -- no twisting there and the FCFS engine prompts DS on this channel).
        { key = "sob", spell_id = guide_sob_spell_id, cooldown_key = "sob",
            name_suffix = "IconBlood", level = 5, swipe_duration = 30,
            swipe_always = true, idle_alpha = 0.5 },
        -- The twist cue (archive icon_twist): Command full width with the
        -- half-width Blood overlay on its right half (Righteousness on Era
        -- and Forever: same slot, same key, Era texture).
        { key = "twist", spell_id = 20375, name_suffix = "TwistLeft", level = 8,
            overlay = { spell_id = guide_twist_seal_id, name_suffix = "TwistRight",
                size = { 22.5, 45 }, offset = { 11.25, 0 }, keep_aspect = true } },
        -- Judgement cue (archive icon_judge): small, low-left, Pixel glow while shown.
        { key = "judge", spell_id = 20271, cooldown_key = "judge",
            name_suffix = "JudgeTime", level = 9, size = { 22.5, 24.9 },
            offset = { -9, -10 }, keep_aspect = true, border_size = 1,
            glow = true, glow_key = "NextActionJudge", swipe_duration = 8 },
        -- Fillers (archive filler_consec / filler_exo) pop over everything, captioned.
        { key = "consecration", spell_id = 26573, name_suffix = "FillerC",
            level = 13, zoom = 0.2, label = "FILLER" },
        { key = "exorcism", spell_id = 879, name_suffix = "FillerE",
            level = 14, zoom = 0.15, label = "FILLER" },
        -- Execute (Era Hammer of Wrath): the engine's filler_kind "how" needs a
        -- slot of its own or the frame drops it as an unknown key. Same filler
        -- shape (no swipe, captioned, above everything); the rank-1 id carries
        -- the icon every rank shares. On Wrath the slot carries Holy Wrath (the
        -- FCFS engine's "how" channel there); same slot, same key, HW texture.
        { key = "how", spell_id = guide_how_spell_id, name_suffix = "FillerH",
            level = 15, zoom = 0.15, label = "FILLER" },
        -- Shockadin Holy Shock (bench/sod_paladin_variants_2026-10-19.md §4;
        -- 20930r3 max rank per sim/paladin/holy_shock.go; APL-cited, in-client
        -- UNCONFIRMED): the engine's filler_kind "holy_shock" needs a slot or
        -- the frame drops it as an unknown key. Same filler shape (no swipe,
        -- captioned, above everything); lights only when prompted (unknown-hides).
        { key = "holy_shock", spell_id = 20930, name_suffix = "FillerHS",
            level = 16, zoom = 0.15, label = "FILLER" },
        -- Shockadin Aura Mastery (407624 legs rune per sim/paladin/aura_mastery.go;
        -- Sanctified holy-multiplier, Libram-of-Sanctity-gated; APL-cited, in-client
        -- UNCONFIRMED): the engine's filler_kind "aura_mastery" rides the same
        -- generic mapping. Same filler shape; lights only when prompted.
        { key = "aura_mastery", spell_id = 407624, name_suffix = "FillerAM",
            level = 17, zoom = 0.15, label = "FILLER" },
        -- The WotLK APL's UTILITY BAND (bench/paladin_apl_utility_build_2026-10-20.md
        -- §2): Hand of Reckoning (the APL's i=1) and Hammer of Wrath (i=2). The
        -- engine's Wrath order carries both above the damage rows, so they land
        -- on the ACTION channel and light these two icons. Same shape as the
        -- Crusader Strike action icon (full size, no swipe - the cooldown is
        -- the client's own, and the frame's swipe is a display channel the
        -- action icons do not ride).
        { key = "hor", spell_id = 67485, name_suffix = "IconHor", level = 10 },
        { key = "how_wrath", spell_id = 48806, name_suffix = "IconHowW", level = 11 },
    },

    -- Live inputs: the existing gather, verbatim, into the caller's reused table.
    gather = function(self, out)
        return ST.PALADIN.gather_guide_inputs(self, out)
    end,

    -- Pure: one engine tick, then the display mapping the frame consumes. The engine
    -- writes into its own reused table, so its `out.action` seed (the archive's last
    -- action) keeps the exact value it always had; the frozen display fields are then
    -- derived into the caller's table. riding shows the Blood slot with the RIDE
    -- overlay, the engine's judge/filler flags become slot keys.
    evaluate = function(inputs, out)
        if type(out) ~= "table" then
            out = {}
        end
        local raw = ST.PALADIN.guide_raw
        if not raw then
            raw = {}
            ST.PALADIN.guide_raw = raw
        end
        local na = st.nextaction
        -- FCFS families (Wrath, SoD runes) run the priority-winner engine; every
        -- other family keeps the archived twist tree bit-identically (scripted and
        -- old callers pass no fcfs_mode, which reads as nil here).
        if na and na.evaluate_fcfs and inputs.fcfs_mode ~= nil then
            na.evaluate_fcfs(inputs, raw)
        elseif na and na.evaluate then
            na.evaluate(inputs, raw)
        end
        out.action = raw.riding and "sob" or raw.action
        out.hold = raw.hold
        out.hold_text = raw.riding and "RIDE" or "HOLD"
        out.filler_slot = raw.filler_kind
        out.judge_slot = raw.judge_call and "judge" or nil
        -- M6: the engine threads the provider's inputs_unknown; copy it into the
        -- display table so the frame can render "…" instead of an action.
        out.inputs_unknown = raw.inputs_unknown == true or inputs.inputs_unknown == true
        -- Era and Forever show no rotation pattern: the keys name CS-cycle
        -- cadences that do not exist without Crusader Strike. (The filler_kind
        -- "how" passes through untouched to the HoW slot above; "holy_shock"
        -- and "aura_mastery" ride the same generic mapping to the shockadin
        -- slots.)
        out.rotation_key = nil
        -- FCFS has no rotation pattern (nothing to paint); the twist cadences
        -- stay TBC-only, Era and Forever stay patternless as before.
        if not inputs.era and not inputs.forever and inputs.fcfs_mode == nil
            and na and na.calculate_rotation then
            out.rotation_key = na.calculate_rotation(inputs.speed, inputs.G)
        end
        out.waiting_judgement = raw.waiting_judgement
        -- Follow-up advisories (display-only: none of these steers action,
        -- hold or filler). The guide frame renders stopattack (STOP),
        -- prepull_ready (PULL, combat path) and hard_wait (WAIT); the
        -- StopAttack/StartAttack macro itself, the pull-timer source, the
        -- seal-maintenance slot and the rank-1 slot stay filed (the
        -- advisories ride along display-inert until those lanes land).
        out.stopattack = raw.stopattack == true
        out.prepull_ready = raw.prepull_ready == true
        out.seal_maintenance = raw.seal_maintenance == true
        out.rank1_advice = raw.rank1_advice == true
        out.hard_wait = raw.hard_wait == true
        -- Mana-governor surfacing (display mapping only, no rule change):
        -- OOM reads while the governor withholds a reseal (a threshold is
        -- set, mana sits below it, and the engine rides). The engine spends
        -- no flag for this, so it is derived here from the same inputs; the
        -- frame paints out.mana_low as OOM (nextaction_ui.lua).
        local mana_cap = inputs.twist_mana_threshold
        out.mana_low = type(mana_cap) == "number" and type(inputs.mana_pct) == "number"
            and inputs.mana_pct < mana_cap and raw.riding == true
        return out
    end,

    -- Live rotation-pattern source for the guide's rotation text (identical to the
    -- shipped update_texts call; the engine owns the thresholds). Nil on Era
    -- and Forever (see evaluate above).
    rotation_key = function(inputs)
        if inputs.era or inputs.forever or inputs.fcfs_mode ~= nil then
            return nil
        end
        local na = st.nextaction
        if not (na and na.calculate_rotation) then
            return nil
        end
        return na.calculate_rotation(inputs.speed, inputs.G)
    end,

    -- Key -> display text: the engine's own map, never duplicated here.
    rotation_names = st.nextaction and st.nextaction.display_names or nil,

    labels = { next_action = "Next action:", hold = "HOLD", ride = "RIDE" },
}

--=========================================================================================
-- Cooldown HUD: paladin slots and the live state provider
--=========================================================================================
-- The slot set is the archived HUD's (archive hud.lua:28-49): Crusader Strike,
-- Judgement, Consecration, Exorcism, the two trinket slots and Avenging Wrath,
-- plus the guide→HUD mirror (bench/hud_parity_2026-10-19.md P-1): soc, sob,
-- how, holy_shock, aura_mastery, and the WotLK APL's utility band (hor, how_wrath
-- - bench/paladin_apl_utility_build_2026-10-20.md §2). The two band slots are
-- DISPLAY-ONLY mirrors in the druid Claw shape (classes/druid.lua:2685): the
-- provider hides them unless hud_show_<key> reads exactly true (nil = off), so a
-- fresh profile's row is unchanged and no default-visible change ships. The
-- twist cue stays guide-only (deferred like
-- shaman's 13→8 in classes/shaman.lua:3057-3060): it is a composite timing cue
-- with no single live spell flag without engine coupling, and the guide frame
-- already covers it. Trinkets do not move last: wings ships last in the archive
-- order, so the mirror appends after wings to preserve the existing indices.
-- hud_show_soc/sob/how/holy_shock/aura_mastery defaults + widgets ship with the
-- templates (hud-styles-build 2026-10-19); HS/AM stay unknown-hide provider-side
-- (shockadin legs). Ids are rank-invariant fallbacks;
-- cooldowns read by name (rank-agnostic). Wrath: sob carries Divine Storm and
-- how carries Holy Wrath (guide_sob_spell_id/guide_how_spell_id, same slot same
-- key); Era/Forever: sob shows the twist seal (Righteousness); otherwise Blood
-- and Hammer of Wrath.
--
-- Exorcism: the archive carried the TBC rank id (27138) for the icon; the rank-1 id
-- (879, the id the guide already uses) is the one that resolves on every family, so
-- the icon is never blank on Classic Era. cooldown_spell stays unused: the provider
-- reads cooldowns by the client's own rank (name-based), not by a fixed id.
ST.PALADIN.HUD_SLOTS = {
    { key = "cs", title = "Crusader Strike", kind = "spell", spell = 35395 },
    { key = "judgement", title = "Judgement", kind = "spell", spell = 20271 },
    { key = "consecration", title = "Consecration", kind = "spell", spell = 26573 },
    { key = "exorcism", title = "Exorcism", kind = "spell", spell = 879 },
    { key = "trinket1", title = "Trinket 1", kind = "trinket", inv_slot = 13 },
    { key = "trinket2", title = "Trinket 2", kind = "trinket", inv_slot = 14 },
    { key = "wings", title = "Avenging Wrath", kind = "spell", spell = 31884 },
    { key = "soc", title = "Seal of Command", kind = "spell", spell = 20375 },
    { key = "sob", title = "Seal of Blood", kind = "spell", spell = guide_sob_spell_id },
    { key = "how", title = "Hammer of Wrath", kind = "spell", spell = guide_how_spell_id },
    { key = "holy_shock", title = "Holy Shock", kind = "spell", spell = 20930 },
    { key = "aura_mastery", title = "Aura Mastery", kind = "spell", spell = 407624 },
    -- The WotLK APL's UTILITY BAND (bench/paladin_apl_utility_build_2026-10-20.md
    -- §2): Hand of Reckoning (the APL's i=1, 67485) and the WotLK Hammer of
    -- Wrath (i=2, 48806). The ids are the APL's own - the guide's two band slots
    -- carry the same pair - and the cooldowns read by NAME, like every other
    -- slot here (the ids are rank-invariant icon fallbacks).
    { key = "hor", title = "Hand of Reckoning", kind = "spell", spell = 67485 },
    { key = "how_wrath", title = "Hammer of Wrath (WotLK)", kind = "spell", spell = 48806 },
}

-- One reused state table: the HUD reads it immediately and never keeps a reference
-- (see the frozen contract in hud.lua), so there is no per-tick allocation here.
ST.PALADIN.hud_state = {}

-- The WotLK utility band's last spell-book answer, per slot key: "known" /
-- "not_known" / "unknown" (the tri-state, compat.lua's
-- api.is_spell_known_state). The HUD's frozen state table has no room for a
-- reason, so the class keeps it here: it is the difference between "this build
-- has no Hand of Reckoning" and "this client could not answer the question",
-- and the operator's in-client check reads it.
ST.PALADIN.hud_band_spell_state = {}

-- Localized HUD slot spell names, resolved lazily (name-based cooldown and probe
-- lookups are rank-agnostic). Resolved values are cached; a failed resolution (spell
-- data not ready yet) is retried on the next call, like the guide's filler names.
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

-- Practice-mode cooldown remaining (the archive's readers checked st.practice.active;
-- this codebase's practice session is practice_ui).
local function hud_practice_active()
    return st.practice_ui ~= nil and st.practice_ui.is_active() == true
end

local function hud_sim_remaining(field, now)
    local sim = st.practice_ui and st.practice_ui.sim
    local expires = sim and sim[field]
    if type(expires) ~= "number" then
        return 0
    end
    local remaining = expires - now
    if remaining < 0 then
        remaining = 0
    end
    return remaining
end

-- The running GCD (archive hud.lua:101-107, re-pointed at the addon's own tracking).
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

-- Remaining time and full duration of one paladin ability cooldown, practice-aware:
-- the archive's ability_cooldown (hud.lua:74-99) re-expressed on the readers the guide
-- already uses (get_guide_cooldown_remaining: client cooldown with latch and GCD-echo
-- handling) plus the practice sim fields for a session.
local function hud_ability_cooldown(self, slot, now)
    local key = slot.key
    local practice = hud_practice_active()
    if key == "cs" then
        local remaining
        if practice then
            remaining = hud_sim_remaining("cs_cooldown_expires", now)
        elseif st.nextaction and st.nextaction.CS_SPELL_ID
            and is_spell_known_query(st.nextaction.CS_SPELL_ID) then
            remaining = get_guide_cooldown_remaining(self, st.nextaction.CS_SPELL_ID,
                "guide_cs_expires", "guide_cs_duration")
        else
            remaining = 999   -- without the talent there is nothing to count
        end
        if remaining >= 999 then
            remaining = 0
        end
        return remaining, 6
    elseif key == "judgement" then
        if practice then
            return hud_sim_remaining("judge_cooldown_expires", now), 8
        end
        local judge_id = st.nextaction and st.nextaction.JUDGEMENT_SPELL_ID or 20271
        return get_guide_cooldown_remaining(self, judge_id), 8
    elseif key == "consecration" then
        if practice then
            return hud_sim_remaining("consec_cooldown_expires", now), 8
        end
        local name = hud_slot_name(slot)
        if not name then
            return 0, 8
        end
        return get_guide_cooldown_remaining(self, name) or 0, 8
    elseif key == "exorcism" then
        -- Archive parity: the filler reader behind Exorcism never simulated a
        -- cooldown, so during practice it reads as ready.
        if practice then
            return 0, 15
        end
        local name = hud_slot_name(slot)
        if not name then
            return 0, 15
        end
        return get_guide_cooldown_remaining(self, name) or 0, 15
    elseif key == "wings" then
        -- Straight from the API, ignoring the GCD echo (a real cooldown is minutes
        -- long). Archive parity: practice leaves it ready.
        if practice then
            return 0, 180
        end
        local start_time, duration = api.GetSpellCooldown(spell_query(31884))
        if start_time and duration and duration > 1.51 then
            local remaining = start_time + duration - now
            if remaining > 0 then
                return remaining, duration
            end
        end
        return 0, 180
    elseif key == "soc" then
        -- Seals have no cooldown (GCD-only); the aura swipe rides in the provider.
        return 0, 0
    elseif key == "sob" then
        -- Wrath sob is Divine Storm (a real cooldown); every other family is the
        -- twist-seal aura (GCD-only here, swipe in the provider). Practice reads
        -- ready (the sim mirror owns the seals, not the cooldown).
        if is_wrath_family then
            if practice then
                return 0, 0
            end
            local ds_id = resolve_ds_spell_id(now)
            if not ds_id then
                return 0, 0
            end
            local start_time, duration = api.GetSpellCooldown(spell_query(ds_id))
            if start_time and duration and duration > 1.51 then
                local remaining = start_time + duration - now
                if remaining > 0 then
                    return remaining, duration
                end
            end
            return 0, 0
        end
        return 0, 0
    elseif key == "how" then
        -- Execute cue: Era/Forever Hammer of Wrath, Wrath Holy Wrath; every other
        -- family hides (no signal, provider). Practice reads ready.
        if practice then
            return 0, 0
        end
        local hid = nil
        if is_wrath_family then
            hid = resolve_hw_spell_id(now)
        elseif is_era_family or is_forever_family then
            hid = resolve_how_spell_id(now)
        end
        if not hid then
            return 0, 0
        end
        local start_time, duration = api.GetSpellCooldown(spell_query(hid))
        if start_time and duration and duration > 1.51 then
            local remaining = start_time + duration - now
            if remaining > 0 then
                return remaining, duration
            end
        end
        return 0, 0
    elseif key == "holy_shock" then
        -- Shockadin (SoD-only, ERA-gated): unknown hides (no signal). Practice
        -- reads ready.
        if practice then
            return 0, 0
        end
        if not is_era_family then
            return 0, 0
        end
        local hs_id = resolve_hs_spell_id(now)
        if not hs_id then
            return 0, 0
        end
        local start_time, duration = api.GetSpellCooldown(spell_query(hs_id))
        if start_time and duration and duration > 1.51 then
            local remaining = start_time + duration - now
            if remaining > 0 then
                return remaining, duration
            end
        end
        return 0, 0
    elseif key == "aura_mastery" then
        -- Shockadin legs rune (SoD-only, ERA-gated + known): unknown hides.
        -- Practice reads ready.
        if practice then
            return 0, 0
        end
        if not is_era_family then
            return 0, 0
        end
        if not is_spell_known_query(AM_SPELL_ID) then
            return 0, 0
        end
        local start_time, duration = api.GetSpellCooldown(spell_query(AM_SPELL_ID))
        if start_time and duration and duration > 1.51 then
            local remaining = start_time + duration - now
            if remaining > 0 then
                return remaining, duration
            end
        end
        return 0, 0
    elseif key == "hor" or key == "how_wrath" then
        -- The WotLK APL's UTILITY BAND (bench/paladin_apl_utility_build_2026-10-20.md
        -- §2): Hand of Reckoning (67485) and the WotLK Hammer of Wrath (48806).
        -- Both carry a REAL cooldown - sim wowsims/wotlk
        -- sim/paladin/hand_of_reckoning.go:29 (CD 6 s with the Turalyon's
        -- Plate 2pc, else 8 s) and sim wowsims/wotlk
        -- sim/paladin/hammer_of_wrath.go:28 (CD 6 s) - so the slot shows the
        -- client's own cooldown, read by NAME (rank-agnostic: the descriptor's
        -- id is a rank-invariant icon fallback, this class's HUD convention).
        -- The client's own duration drives the swipe - never a hardcoded number.
        -- A client that cannot name the spell reads no state (the caller hides
        -- the slot). The caller has already gated the slot on the family, the
        -- spell book and the option, so this branch performs no probe of its
        -- own.
        local name = hud_slot_name(slot)
        if not name then
            return 0, 0
        end
        local start_time, duration = api.GetSpellCooldown(spell_query(name))
        if start_time and duration and duration > 1.51 then
            local remaining = start_time + duration - now
            if remaining > 0 then
                return remaining, duration
            end
        end
        return 0, 0
    end
    return 0, 0
end

-- IsUsableSpell's second return (the WA's "insufficientResources"; archive
-- hud.lua:114-121), through compat's cross-client IsSpellUsable wrapper: the
-- C_Spell / classic-global probes and their fallback live there. A client with no probe
-- reports unknown, rendered as "no tint" exactly like the archive's
-- `if not IsUsableSpell` guard; the pcall absorbs a probe that rejects the argument form.
local function hud_no_mana(slot)
    local name = hud_slot_name(slot)
    local ok, _, insufficient = pcall(api.IsSpellUsable, name or slot.spell)
    return ok and insufficient == true
end

-- WA "spellInRange == 0" (archive hud.lua:123-130): api.IsSpellInRange returns 0 out
-- of range, 1/true in range, nil unknown (treated as "not out of range").
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

local function hud_exorcisable()
    if hud_practice_active() then
        return true   -- archive: practice counts as a valid target
    end
    if not (UnitExists and UnitExists("target")) then
        return false
    end
    local ctype = read_creature_type()
    local types = st.nextaction and st.nextaction.exorcism_target_types
    return ctype ~= nil and types ~= nil and types[ctype] == true
end

-- The class provider (frozen contract, hud.lua header): maps the archive's
-- ability_state (hud.lua:418-453) onto the semantic state fields the HUD paints.
function ST.PALADIN.get_hud_state(self, slot, now)
    local s = ST.PALADIN.hud_state
    s.remaining, s.duration, s.start, s.reverse = nil, nil, nil, nil
    s.text_remaining, s.desaturate, s.usable, s.in_range = nil, nil, nil, nil
    s.glow, s.count, s.texture, s.hidden = nil, nil, nil, nil
    now = now or api.get_time()
    if type(slot) ~= "table" or type(slot.key) ~= "string" then
        -- PROPER: a slot without a key carries nothing renderable; hiding draws
        -- the honest state instead of throwing. The driver always passes a slot
        -- table, so this only fires for a caller bug.
        s.hidden = true
        return s
    end
    -- The WotLK APL's UTILITY BAND (bench/paladin_apl_utility_build_2026-10-20.md
    -- §2): the two display-only mirrors (hor, how_wrath). Three gates, in this
    -- order, before ANY read:
    --   1) the option gate - the slot hides unless hud_show_<key> reads exactly
    --      true (nil = off; the druid Claw shape, classes/druid.lua:2685), so a
    --      fresh profile's row is unchanged. The key ships false (the druid
    --      Claw's shape: the display-only mirror is off until the player turns
    --      it on); false and nil both hide.
    --   2) the family gate - the band is the WotLK APL's, so every other family
    --      hides the slot and never asks its book about the two spells.
    --   3) the spell-book gate - the STATE, not the boolean (see below).
    -- The gate sits BEFORE the cooldown read: a hidden slot performs no reads.
    if slot.key == "hor" or slot.key == "how_wrath" then
        local show_db = self:get_class_table()
        if type(show_db) ~= "table"
            or show_db["hud_show_" .. slot.key] ~= true then
            s.hidden = true
            return s
        end
        if not is_wrath_family then
            s.hidden = true
            return s
        end
        -- The spell-book gate reads the STATE (compat.lua's
        -- api.is_spell_known_state), not the binary: the boolean folds "the
        -- player does not know it" and "this client cannot answer" into one
        -- false, so the gate could not tell the two apart - and the honest
        -- reason for a hidden slot differs. The state tells them apart:
        --   "known"     - the player has the talent: the slot shows.
        --   "not_known" - the build has no such talent: the slot hides (the
        --                 probe runs every tick, so a talent change is picked
        --                 up without a reload).
        --   "unknown"   - the client could not answer the question: the slot
        --                 SHOWS (fail-visible - never hide on a question the
        --                 client could not answer), and the next tick asks
        --                 again.
        -- Only "not_known" hides. The HUD's frozen state table has no room for
        -- a reason, so the class keeps the last answer per band slot (a
        -- diagnostic surface: the operator's in-client check reads it).
        local known, known_state = api.is_spell_known_state(spell_query(slot.spell))
        ST.PALADIN.hud_band_spell_state[slot.key] = known_state
        if known ~= true and known_state ~= "unknown" then
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
    elseif slot.key ~= "judgement" and slot.key ~= "wings" then
        -- The GCD shows as a swipe (WA "show GCD"); the HUD's 2 s rule keeps its
        -- text hidden. Judgement and Avenging Wrath never carry it (archive 426-428).
        local g, gd = hud_gcd_remaining(self, now)
        if g > 0 then
            s.remaining, s.duration = g, gd
            s.text_remaining = g
        end
    end

    local db = self:get_class_table()
    -- PROPER: the tints are opt-in feedback; without a profile there is no opt-in
    -- to honor, so the slot draws untinted rather than guessing.
    if type(db) == "table" and db.hud_mana_tint and hud_no_mana(slot) then
        s.usable = false
    end
    if type(db) == "table" and db.hud_range_tint and hud_out_of_range(slot) then
        s.in_range = false
    end

    if slot.key == "judgement" then
        -- Grey without an active seal (archive 441-443).
        if (self.twist_active_seals_count or 0) <= 0 then
            s.desaturate = true
        end
    elseif slot.key == "exorcism" then
        -- Grey unless the target is Undead or Demon; glows then, in combat and ready.
        local ok_target = hud_exorcisable()
        if not ok_target then
            s.desaturate = true
        end
        s.glow = (ok_target and remaining <= 0 and self.in_combat == true) or false
    elseif slot.key == "wings" then
        -- Glows the moment it is ready, in combat (archive 448-451).
        s.glow = (remaining <= 0 and self.in_combat == true) or false
    elseif slot.key == "soc" then
        -- Seal aura swipe (the seal-icons shape): active shows the remaining aura
        -- over its tracked (or fallback 30 s) length; down keeps the GCD swipe
        -- above (ready to cast). Unknown (no texture) hides; cold retries.
        if not hud_slot_name(slot) and not api.GetSpellInfo(slot.spell) then
            s.hidden = true
        elseif self.has_soc == true and type(self.soc_expires) == "number"
            and self.soc_expires > now then
            local seal_full = self.soc_duration or SEAL_FALLBACK_DURATION
            s.remaining = self.soc_expires - now
            s.duration = seal_full
            s.text_remaining = s.remaining
            s.desaturate = nil
        end
    elseif slot.key == "sob" then
        if is_wrath_family then
            -- Divine Storm: unknown hides; ready glows in combat (wings rule).
            if not resolve_ds_spell_id(now) then
                s.hidden = true
            else
                s.glow = (remaining <= 0 and self.in_combat == true) or false
            end
        else
            -- Twist-seal aura: Era/Forever Righteousness, else Blood. Same shape
            -- as soc above.
            local seal_active, seal_expires, seal_full
            if is_era_family or is_forever_family then
                seal_active, seal_expires, seal_full = self.has_sor, self.sor_expires, self.sor_duration
            else
                seal_active, seal_expires, seal_full = self.has_sob, self.sob_expires, self.sob_duration
            end
            if not hud_slot_name(slot) and not api.GetSpellInfo(slot.spell) then
                s.hidden = true
            elseif seal_active == true and type(seal_expires) == "number" and seal_expires > now then
                s.remaining = seal_expires - now
                s.duration = seal_full or SEAL_FALLBACK_DURATION
                s.text_remaining = s.remaining
                s.desaturate = nil
            end
        end
    elseif slot.key == "how" then
        -- Execute: Era/Forever HoW, Wrath HW; other families hide (no signal).
        -- Unknown hides; ready glows in combat (wings rule).
        local hid = nil
        if is_wrath_family then
            hid = resolve_hw_spell_id(now)
        elseif is_era_family or is_forever_family then
            hid = resolve_how_spell_id(now)
        end
        if hid == nil then
            s.hidden = true
        else
            s.glow = (remaining <= 0 and self.in_combat == true) or false
        end
    elseif slot.key == "holy_shock" then
        -- Shockadin: ERA-gated + known, else hidden (no signal). Ready glows.
        local hs_id = is_era_family and resolve_hs_spell_id(now) or nil
        if hs_id == nil then
            s.hidden = true
        else
            s.glow = (remaining <= 0 and self.in_combat == true) or false
        end
    elseif slot.key == "aura_mastery" then
        -- Shockadin legs rune: ERA-gated + known, else hidden. Ready glows.
        -- Fail-visible: only a confirmed "not_known" hides; "unknown" (the
        -- client could not answer) shows, and the next tick asks again.
        if not is_era_family then
            s.hidden = true
        else
            local am_known, am_state = api.is_spell_known_state(spell_query(AM_SPELL_ID))
            if am_known ~= true and am_state ~= "unknown" then
                s.hidden = true
            else
                s.glow = (remaining <= 0 and self.in_combat == true) or false
            end
        end
    elseif slot.key == "how_wrath" then
        -- The WotLK Hammer of Wrath is an EXECUTE-phase cast: the sim's own gate
        -- (sim wowsims/wotlk sim/paladin/hammer_of_wrath.go:31-32
        -- ExtraCastCondition: sim.IsExecutePhase20()) asks for it only below 20 %
        -- target health - the same 20 the engine arms on (nextaction.lua's
        -- how_wrath arm). Above the threshold the mirror greys the slot, so the
        -- row never shows a ready spell the engine will not ask for. An unknown
        -- health claims nothing (the slot keeps its own state).
        local hp = get_guide_target_health_pct()
        if type(hp) == "number" and hp >= 20 then
            s.desaturate = true
        end
    end
    return s
end

--=========================================================================================
-- Practice: the class-side rotation contract
--
-- The shared practice engine (practice.lua / practice_ui.lua) owns the session, the
-- registry and the panels; this section owns what the PALADIN teaches:
--
--   ST.PALADIN.practice_rotation       the rotation table, in sim priority order
--   ST.PALADIN.practice_scenario_step  the expected action at one decision point
--   ST.PALADIN.practice_drills         the focused single-skill graders
--
-- Every decision comes from the SAME pure engine the next-action guide uses
-- (st.nextaction.evaluate / st.nextaction.evaluate_fcfs), so a practice session
-- teaches exactly what the guide teaches. Nothing here casts anything, nothing
-- here is visible by default and nothing here registers itself: the shared
-- engine looks the three members up by player_class (ST.PALADIN).
--
-- THE ROTATION TABLE is the class's APL layer (the operator ruling HU-12, hands-up
-- 2026-10-20): it carries the APL's SPELL ROWS - the combat rotation, never the
-- APL's pre-pull rows (Sanctity Aura, Redemption, the primary-seal prepull: those
-- belong to a prepull table, and the prepull drill's own spec below is where the
-- paladin keeps them). Every row carries its citation (the APL and the position
-- in it), the family gate and the family's spell id; the TBC family resolves
-- every spell by NAME, so a TBC row carries its name and no numeric id. The
-- rows the shipped orders name are the ones the engine can press; the WotLK
-- APL's top two rows ride the table as cited rows (see the APL layer below).
--
-- THE ACTION KEY SPACE (the keys the guide's slots use, plus the two spell-level
-- keys the FCFS families need, plus the practice sim's Seal of the Crusader):
--
--   soc    Seal of Command             sob    Seal of Blood / Martyr (twist seal)
--   sotc   Seal of the Crusader        twist  the twist cue (a seal swap)
--   cs     Crusader Strike             judge  Judgement
--   ds     Divine Storm                cons   Consecration
--   exo    Exorcism                    how    Hammer of Wrath
--   hw     Holy Wrath                  hs     Holy Shock (shockadin)
--   am     Aura Mastery (shockadin)
--   hor    Hand of Reckoning (the WotLK APL's top row - a rotation table row
--          only, see the APL layer below)
--   how_wrath  Hammer of Wrath (the WotLK APL's second row - a rotation table
--          row only; the "how" key above is the Era/Forever execute Hammer of
--          Wrath and the Wrath channel carries Holy Wrath)
--
-- The shared engine reports the player's press in the practice sim's spelling
-- ("consec"); ST.PALADIN.practice_action_aliases maps every spelling onto the
-- canonical key above, and the graders below normalise both sides before
-- comparing.
--
-- THE DECISION RULE: a step that cannot be decided returns nil - the engine
-- grades "unknown", never a wrong action. A HOLD / RIDE (the rotation wants
-- nothing pressed) returns nil as well: there is no action to teach, and
-- guessing one would punish a correct pause. The richer decision (with the
-- hold flag, the judge verdict and the reason) is available through
-- ST.PALADIN.practice_decision for a caller that wants the illegal-cast rule.
--
-- THE CONTEXT: { now, last_action, resources, cooldowns } (the shared engine's
-- shape). Everything else this section reads is OPTIONAL and read through a
-- tolerant alias list, so a missing field degrades to "unknown" (the drill
-- answers nil) instead of a wrong grade:
--
--   now                the clock, seconds
--   last_action        the player's last press (any spelling, see above)
--   resources          { mana_pct, target_health_pct, fight_remaining_pct, ... }
--   cooldowns          { cs = 0, judge = 3, ... } seconds remaining per action
--   swing_remaining    seconds to the next swing (or session.swing_ends_at)
--   gcd_remaining      seconds of GCD left (or session.gcd_expires)
--   speed              the weapon speed (or session.effective_speed)
--   gcd_duration       the GCD length (or session.effective_gcd)
--   seal               "soc" | "sob" | "none" (or session.active_seals)
--   fcfs_mode          "wrath" | "sod" | "sod_stack" | "sod_shock" | "sod_wrath"
--   cs_known           whether Crusader Strike is in the book
--   pull_in_seconds    seconds to the pull (the prepull drill's countdown)
--   seal_due           the seal the prepull drill expects
--   prepull_lead       the prepull lead, seconds (the default is per rotation)
--   cue_at             when the current cue appeared (the lateness reference)
--   mistakes/attempts  the engine's own running counters (when it aggregates)
--   session/session_id the session identity (the drill counters' key)
--=========================================================================================

-- Canonical labels for the practice action keys (the UI reads them; the keys
-- themselves are the contract).
local PRACTICE_ACTION_LABELS = {
    soc = "Seal of Command",
    sob = "Seal of Blood / Martyr",
    sotc = "Seal of the Crusader",
    twist = "Twist",
    cs = "Crusader Strike",
    judge = "Judgement",
    ds = "Divine Storm",
    cons = "Consecration",
    exo = "Exorcism",
    how = "Hammer of Wrath",
    hw = "Holy Wrath",
    hs = "Holy Shock",
    am = "Aura Mastery",
    hor = "Hand of Reckoning",
    how_wrath = "Hammer of Wrath (WotLK)",
    judgement_of_wisdom = "Judgement of Wisdom",
    holy_strike = "Holy Strike",
    divine_favor = "Divine Favor",
}

-- Every spelling the shared engine or the practice sim may report, mapped onto
-- the canonical key above. The practice sim's own ability keys are the source
-- of the first column ("consec" -> "cons"); the guide's slot keys and a few
-- spell names cover the rest.
ST.PALADIN.practice_action_aliases = {
    consec = "cons",
    consecration = "cons",
    exorcism = "exo",
    judgement = "judge",
    judgment = "judge",
    divine_storm = "ds",
    divinestorm = "ds",
    hammer_of_wrath = "how",
    hammer = "how",
    holy_wrath = "hw",
    holywrath = "hw",
    holy_shock = "hs",
    holyshock = "hs",
    aura_mastery = "am",
    auramastery = "am",
    seal_of_command = "soc",
    command = "soc",
    seal_of_blood = "sob",
    blood = "sob",
    seal_of_martyrdom = "sob",
    martyrdom = "sob",
    seal_of_the_crusader = "sotc",
    hand_of_reckoning = "hor",
    reckoning = "hor",
    judgement_of_wisdom = "judgement_of_wisdom",
    judgment_of_wisdom = "judgement_of_wisdom",
    holy_strike = "holy_strike",
    holystrike = "holy_strike",
    divine_favor = "divine_favor",
    divinefavor = "divine_favor",
}

--=========================================================================================
-- The NEUTRAL action set (the panel's legitimate-but-ungraded presses)
--
-- The shared engine grades a press against the rotation: the action the rotation
-- asks for is a HIT, any other action is a MIS-PICK (F) - and a NEUTRAL action is
-- neither (no attempt, no points, no streak change). The panel offers more than the
-- rotation asks for: the twist sim's own ability list (practice.lua's
-- ABILITY_ORDER - the grid the paladin panel draws) carries the consumable, the
-- trinket, the burst cooldown, the stop-attack macro and the third seal, and NONE
-- of them is a rotation row.
--
-- This table is the class's own statement of those actions: the engine reads
-- ST.<CLASS>.practice_neutral_actions (the contract fixed by the orchestrator,
-- practice.lua's class contract block) and treats a press of one of these keys as
-- NEUTRAL.
--
-- THE CLOSED LIST (the class's own suite pins every clause):
--   * every key is a key the class's OWN panel offers - the shared sim's ability
--     key (the grid) or the class's own rotation/guide key. No invented key, no
--     ability the class does not have;
--   * NO key here is a rotation action on ANY order the paladin plays. The engine
--     grades the EXPECTED action first, so a rotation press still hits - but a
--     rotation action published as neutral would make a WRONG rotation press free,
--     which is the grading hole this table must never open;
--   * every panel key is classified: a rotation action, a neutral action, or an
--     intentional mis-pick. A key nobody classified fails the suite, so the next
--     ability someone adds cannot silently become a free press.
--
-- THE KEYS (the first five are keys of the shared sim's ability list - the grid
-- the paladin panel draws, practice.lua's ABILITY_ORDER):
--   sotc    Seal of the Crusader   - a real seal ON THE CLASSIC LINE, and no
--                                     rotation order asks for it (the twist order
--                                     asks for soc / sob), so a seal swap the
--                                     rotation does not want is legitimate, not
--                                     wrong. THE 4.0 CLIENTS REMOVED THE SEAL
--                                     (it went away in 4.0: the Cata and the MoP
--                                     pages answer "Not Found" for 20308 and for
--                                     the whole 21082 / 20162 / 20305-20308 ladder
--                                     - the class's own sotc_ids table), so the
--                                     class publishes it on the classic line
--                                     ONLY and a press of that key on the 4.0+
--                                     clients is a mis-pick, exactly like the
--                                     rogue's Shiv on the same clients;
--   aw      Avenging Wrath        - the burst cooldown. No rotation row carries it
--                                     (the AW combo drill was retired; the class's
--                                     own drills are paladin_fcfs_priority,
--                                     paladin_prepull and paladin_judge_fit, and
--                                     none of them grades a cooldown);
--   hpot    Haste Potion          - a consumable;
--   abacus  Abacus of Violent Odds - a trinket;
--   stop    Stop Attack           - the stop-attack macro (the paladin's own
--                                     stopattack discipline is a filed follow-up:
--                                     bench/paladin_followups_2026-10-19.md).
--
-- NOT IN THE SET, and why:
--   * the rotation actions themselves (cs, judge, twist, soc, sob, cons, exo, how,
--     ds, hw, hs, am, hor, how_wrath ...) - the rotation grades those;
--   * the guide slots' other spellings (consecration, exorcism, holy_shock,
--     aura_mastery) - they ARE the rotation actions under another spelling
--     (ST.PALADIN.practice_action_aliases maps them onto cons / exo / hs / am),
--     and a rotation action can never be neutral;
--   * the abilities the class does NOT offer as practice keys (Healing Flash,
--     Blessing of Sacrifice, drink): the paladin's practice surface still has no
--     key for them (the cooldown icon group carries spell IDS, not practice action
--     keys), so a player can never press them in a practice session. Publishing
--     them would invent keys the class does not have. The abilities the class DOES
--     offer (Holy Light, Flash of Light, Lay on Hands, Divine Shield, Blessing of
--     Protection, Food) are the practice-panel ability list below, and they are
--     published as neutral in EVERY bucket below - the buckets differ in the Seal
--     of the Crusader and in nothing else.
--
-- THE PUBLISH IS FAMILY-SCOPED, ONE BUCKET PER FAMILY (the shape the engine
-- reads: the bucket for the running st.family; a family with no bucket answers
-- nil). The buckets differ in exactly one key - the Seal of the Crusader, which
-- the 4.0 clients removed - so the classic line keeps the flat set it always
-- published and the 4.0+ clients publish the same set without that seal. The
-- class's own suite pins every bucket (a key that drifts out of one bucket fails
-- the suite), so the two shapes can never disagree.
--=========================================================================================
ST.PALADIN.practice_neutral_actions = {
    -- THE CLASSIC LINE (ERA - the SoD build rides the Era client - TBC, WRATH and
    -- FOREVER): the seal exists on every one of those clients.
    ERA = {
        sotc = true,
        aw = true,
        hpot = true,
        abacus = true,
        stop = true,
        -- The common abilities (the practice-panel ability list below): a heal, a
        -- shield and food are legitimate mid-practice presses, never a mis-pick.
        holy_light = true,
        flash_of_light = true,
        lay_on_hands = true,
        divine_shield = true,
        bop = true,
        food = true,
    },
    TBC = {
        sotc = true,
        aw = true,
        hpot = true,
        abacus = true,
        stop = true,
        holy_light = true,
        flash_of_light = true,
        lay_on_hands = true,
        divine_shield = true,
        bop = true,
        food = true,
    },
    WRATH = {
        sotc = true,
        aw = true,
        hpot = true,
        abacus = true,
        stop = true,
        holy_light = true,
        flash_of_light = true,
        lay_on_hands = true,
        divine_shield = true,
        bop = true,
        food = true,
    },
    FOREVER = {
        sotc = true,
        aw = true,
        hpot = true,
        abacus = true,
        stop = true,
        holy_light = true,
        flash_of_light = true,
        lay_on_hands = true,
        divine_shield = true,
        bop = true,
        food = true,
    },
    -- THE 4.0+ CLIENTS (CATA, MISTS and RETAIL): the same set WITHOUT the Seal of
    -- the Crusader - the spell was removed in 4.0, so the class does not publish it
    -- there and a press of that key is a mis-pick. Every other key stays: the
    -- class publishes no rotation for those clients, so none of them is
    -- rotation-ranked there and each is a legitimate, ungraded press.
    CATA = {
        aw = true,
        hpot = true,
        abacus = true,
        stop = true,
        holy_light = true,
        flash_of_light = true,
        lay_on_hands = true,
        divine_shield = true,
        bop = true,
        food = true,
    },
    MISTS = {
        aw = true,
        hpot = true,
        abacus = true,
        stop = true,
        holy_light = true,
        flash_of_light = true,
        lay_on_hands = true,
        divine_shield = true,
        bop = true,
        food = true,
    },
    RETAIL = {
        aw = true,
        hpot = true,
        abacus = true,
        stop = true,
        holy_light = true,
        flash_of_light = true,
        lay_on_hands = true,
        divine_shield = true,
        bop = true,
        food = true,
    },
}

--=========================================================================================
-- The neutral set THIS class publishes for the RUNNING family
--
-- The engine reads the publish through its own accessor (practice.lua's
-- H.practice_neutral_actions) and resolves it for the running client family
-- (st.family): a FLAT publish answers itself, a family-scoped publish answers
-- the bucket for that family, and a family the class published no bucket for
-- answers nil (the engine then grades every non-rotation press exactly as it
-- did before).
--
-- This accessor is that SAME rule, re-implemented here so the class never has to
-- ask the engine - and so the OFFER GATE below reads the class's OWN truth:
--
--   ST.PALADIN.practice_neutral_set() -> the published set | nil
--
-- THE OFFER GATE READS IT (the orchestrator's ruling, 2026-10-20): an ability may
-- only be OFFERED on a family where it is either a rotation action or a neutral
-- action. An offer that can only ever be a mis-pick is a trap - the player is
-- invited to press something the grader will always punish. So the panel's
-- common-ability offer list and this set are ONE truth per family: an ability
-- with no neutral bucket on that family is NOT offered there (it stays available
-- on the families where it IS neutral).
--
-- THE CATA AND MISTS CLIENTS: the paladin's publish is FLAT, so it already
-- answers every family - the Cata (4.4.3) and the Mists (5.5.0) clients included.
-- The class publishes no rotation for those two clients (the twist order names
-- no row for them - classes/paladin.lua's practice_rotation_for), so none of the
-- published common abilities is rotation-ranked there: a Holy Light, a Flash of
-- Light, a Lay on Hands, a Divine Shield, a Blessing of Protection or a Food
-- press on those clients is a legitimate, ungraded press - never a mis-pick.
-- Every one of those spells is present on both clients (cited per ability in the
-- common list below).
--=========================================================================================
function ST.PALADIN.practice_neutral_set()
    local published = ST.PALADIN.practice_neutral_actions
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

--=========================================================================================
-- The PRACTICE-PANEL ability list: the common abilities the panel offers
--
-- WHY THIS EXISTS: the practice panel's action row offers the class's whole ability
-- list, and a player legitimately presses a heal, a shield, food or a potion while
-- practicing. The engine grades such a press NEUTRAL - no attempt, no points, no
-- streak change, never a mis-pick (bench/practice_neutral_actions_2026-10-20.md). For
-- that the class needs a KEY for each of them: the panel's vocabulary is the rotation
-- slice plus the class's own guide slot list, and the common abilities had no key at
-- all (bench/class_neutral_actions_2026-10-20.md §2 - "the abilities the class does
-- NOT offer as practice keys ... a player can never press them in a practice
-- session").
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
-- NO ROTACTION ACTION HERE: none of these keys is a rotation action on any order the
-- paladin plays (the FCFS orders, the twist order and the APL rows), so none of them
-- may be a rotation action; the neutral set above publishes exactly these keys.
--=========================================================================================
ST.PALADIN.practice_common_actions = {
    {
        key = "holy_light",
        label = "Holy Light",
        names = { "Holy Light" },
        -- 19968 (r1) / 19980 / 19981 / 19982 - the Classic 1.15 client's Holy Light
        -- ladder (corpus Spell.csv: "Heals a friendly target for $s1."; the names
        -- confirmed at the Classic spell page (19968)).
        ids = { 19968, 19980, 19981, 19982 },
    },
    {
        key = "flash_of_light",
        label = "Flash of Light",
        names = { "Flash of Light" },
        -- 19750 (r1) / 19751 - the client's Flash of Light ladder (the corpus
        -- description and the Classic spell page (19750)).
        ids = { 19750, 19751 },
    },
    {
        key = "lay_on_hands",
        label = "Lay on Hands",
        names = { "Lay on Hands" },
        -- 633 / 2800 / 10310 - the in-tree CD icon slot's id (classes/paladin.lua
        -- CD_CORE_SLOTS) and the client's rank ladder (the corpus description:
        -- "Heals a friendly target for an amount equal to the Paladin's maximum
        -- health.").
        ids = { 633, 2800, 10310 },
    },
    {
        key = "divine_shield",
        label = "Divine Shield",
        names = { "Divine Shield" },
        -- 642 (r1) / 1020 - the in-tree CD icon slot's id (classes/paladin.lua
        -- CD_CORE_SLOTS) and LibClassicDurations' own table
        -- (Libs/LibClassicDurations/classAbilities.lua: "Spell({ 642, 1020 } ...)").
        ids = { 642, 1020 },
    },
    {
        key = "bop",
        label = "Blessing of Protection",
        -- The client RENAMED the spell in 3.0: the Classic and the TBC pages title
        -- 1022 "Blessing of Protection", the WotLK, the Cataclysm and the MoP pages
        -- title the same id "Hand of Protection". Both names are offered, so the
        -- client answers whichever one it knows (the shaman's renamed Water Shield
        -- rule - the SoD rename).
        names = { "Blessing of Protection", "Hand of Protection" },
        -- 1022 (r1) / 5599 / 10278 - LibClassicDurations' own table
        -- (Libs/LibClassicDurations/classAbilities.lua: "Spell({ 1022, 5599, 10278 }").
        -- The id 1022 itself is cited by the client's own expansion pages
        -- (warcraftdb: classic 1022 "Blessing of Protection", wotlk / cataclysm / mop
        -- 1022 "Hand of Protection").
        ids = { 1022, 5599, 10278 },
    },
    {
        key = "food",
        label = "Food",
        names = { "Food" },
        -- 433 / 2639 / 5004 / 10256 / 10257 - the client's Food use effects (the
        -- corpus description: "Restores $o1 health over $d. Must remain seated
        -- while eating."; the names confirmed at the Classic spell page (433)).
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
function ST.PALADIN.resolve_practice_common_action(action)
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

-- The running family's ROTATION actions (the set the offer gate reads): the class's
-- own published slice for the running client, read the way the panel reads it (the
-- argument-free call - practice_ui.lua's scenario_action_order). An unknown order
-- answers nil and the set stays empty.
function ST.PALADIN.practice_rotation_action_set()
    local out = {}
    local ok, entries = pcall(function() return ST.PALADIN.practice_rotation_for() end)
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
-- onto the canonical key). The paladin publishes one; a class with a single key space
-- has none, and the normaliser is then the identity.
function ST.PALADIN.practice_canonical_key(key)
    local aliases = ST.PALADIN.practice_action_aliases
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
function ST.PALADIN.practice_common_offer_allowed(action, neutral, rotation)
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
        and rotation[ST.PALADIN.practice_canonical_key(action.key)] == true then
        return false
    end
    return true
end

-- The panel's ability list: the class's own guide slots plus the common abilities
-- the running client actually has. The practice panel reads the guide slot list LIVE
-- (practice_ui.lua's scenario_guide_slots), so this is the list the panel offers.
function ST.PALADIN.practice_panel_slots()
    local guide = ST.PALADIN.guide
    local slots = type(guide) == "table" and guide.slots or nil
    local out = {}
    if type(slots) == "table" then
        for i = 1, #slots do
            out[i] = slots[i]
        end
    end
    local common = ST.PALADIN.practice_common_actions
    if type(common) == "table" then
        -- THE OFFER GATE: a common ability is offered on the running family only if
        -- that family publishes it (as neutral) or the rotation ranks it there - the
        -- offer list and the neutral set are one truth per family.
        local neutral = ST.PALADIN.practice_neutral_set()
        local rotation = ST.PALADIN.practice_rotation_action_set()
        for i = 1, #common do
            local action = common[i]
            if ST.PALADIN.practice_common_offer_allowed(action, neutral, rotation) then
                local slot = ST.PALADIN.resolve_practice_common_action(action)
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
function ST.PALADIN.apply_practice_panel_actions()
    local guide = ST.PALADIN.guide
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
    local widened = ST.PALADIN.practice_panel_slots()
    if type(widened) ~= "table" or #widened <= #current then
        return false
    end
    guide.slots = widened
    return true
end

-- The twist tree's decision order: the engine's own branch order (the Crusader
-- Strike override replaces the seal work, the Judgement cue rides on the
-- reseal, the fillers come last). This is the GUIDE's order, not a sim claim:
-- the sim-sourced orders are the FCFS tables below.
local PRACTICE_ORDER_TWIST = { "cs", "judge", "twist", "soc", "sob", "cons", "exo", "how" }

-- The prepull seal and its lead, per rotation (bench/class_features_drills_
-- 2026-10-19.md §2 D-P2, sourced to bench/sod_paladin_variants_2026-10-19.md
-- §1-§6 and bench/paladin_rotation_audit_2026-10-19.md §Era):
--   twist      the classic APL prepulls the primary seal at -1.5 s
--   tbc        the tbc-new APL prepulls Seal of the Crusader 27158r7 plus
--              Judgements at 0 s
--   sod        p8-exodin prepulls the primary seal at -2.5 s
--   sod_shock  p8-shockadin-1h/2h prepull at -1.5 s
--   sod_wrath  p8-wrath prepulls at -1.5 s
--   sod_stack  p8-stack prepulls Seal of Command at -3 s (SoM at -1.5 s)
-- The SoD twist build shares the "sod" mode (the live gather has no separate
-- twist mode), so its -1.5 s prepull is not reachable here; the context can
-- always name the due seal and the lead itself.
local PRACTICE_PREPULL = {
    twist = { seal = "soc", lead = 1.5 },
    tbc = { seal = "sotc", lead = 0 },
    sod = { seal = "soc", lead = 2.5 },
    sod_shock = { seal = "soc", lead = 1.5 },
    sod_wrath = { seal = "soc", lead = 1.5 },
    sod_stack = { seal = "soc", lead = 3.0 },
}

-- The per-order priority tables: the twist order above plus the engine's five
-- FCFS tables (published by nextaction.lua so no copy can drift from the
-- engine). READ-ONLY, like the engine's own tables.
ST.PALADIN.practice_orders = { twist = PRACTICE_ORDER_TWIST }
if st.nextaction and st.nextaction.FCFS_ORDERS then
    ST.PALADIN.practice_orders.wrath = st.nextaction.FCFS_ORDERS.wrath
    ST.PALADIN.practice_orders.sod = st.nextaction.FCFS_ORDERS.sod
    ST.PALADIN.practice_orders.sod_stack = st.nextaction.FCFS_ORDERS.sod_stack
    ST.PALADIN.practice_orders.sod_shock = st.nextaction.FCFS_ORDERS.sod_shock
    ST.PALADIN.practice_orders.sod_wrath = st.nextaction.FCFS_ORDERS.sod_wrath
end

--=========================================================================================
-- The APL layer: every rotation row's citation, family gate and spell id
--
-- The rotation table carries the APL's SPELL ROWS (the operator ruling HU-12,
-- hands-up 2026-10-20): the combat rotation, never the pre-pull rows. Every
-- line below is cited from the fetched APLs (bench/rotation_gap_vs_apl_2026-10-20.md
-- §6.2-§6.3, which names the repositories and the position of every row):
--
--   wowsims/classic  ui/retribution_paladin/apls/basic_ret.apl.json
--   wowsims/sod      ui/retribution_paladin/apls/p8-{twist,exodin,stack,shockadin-1h,wrath}.apl.json
--   wowsims/tbc-new  ui/specs/paladin/retribution/apls/default.apl.json
--   wowsims/forever  ui/specs/paladin/retribution/apls/{twist_of_light,holy_shock}.apl.json
--   wowsims/wotlk    ui/retribution_paladin/apls/default.apl.json
--
-- THE FAMILY GATE: `families` is the set of clients the row is played on.
-- "SOD" is the Season of Discovery game - it runs on the ERA client and the
-- class detects it by RUNE, never by a version string
-- (bench/sod_detect_2026-10-19.md). RETAIL plays no rotation at all (no sim,
-- no row): the scenario is never offered there.
--
-- THE IDS: `ids` carries the family's numeric spell id - the APL's own rank id
-- (the citation), NOT the runtime probe: the class's engine resolves the
-- rank-1 ids (nextaction.lua:149-154) and the guide slots carry rank-invariant
-- icons, so the id below is the APL's, never a live read. The TBC family
-- resolves every spell by NAME (the class's spell-query discipline), so a TBC
-- row carries its name in `tbc_name` and no numeric id.
--=========================================================================================
-- The APL utility layer's ids and names (a TABLE FIELD, not a local: this module
-- sits at the Lua 5.1 local ceiling). Every id below is the APL's own rank id
-- out of the sim sources - a citation, not a live probe:
--
--   hor              67485  Hand of Reckoning   (wotlk default.apl.json i=1)
--   how_wrath        48806  Hammer of Wrath      (wotlk default.apl.json i=2)
--   judgement_of_wisdom 53408 Judgement of Wisdom (wotlk default.apl.json i=3)
--   holy_strike      10333  Holy Strike         (forever twist_of_light i=3)
--   divine_favor     20216  Divine Favor        (forever holy_shock i=8)
ST.PALADIN.APL_UTILITY = {
    hor = { id = 67485, name = "Hand of Reckoning" },
    how_wrath = { id = 48806, name = "Hammer of Wrath" },
    judgement_of_wisdom = { id = 53408, name = "Judgement of Wisdom" },
    holy_strike = { id = 10333, name = "Holy Strike" },
    divine_favor = { id = 20216, name = "Divine Favor" },
}

ST.PALADIN.practice_action_meta = {
    cs = {
        note = "the Crusader Strike the order wants first",
        families = { SOD = true, TBC = true, WRATH = true },
        ids = { SOD = 407676, WRATH = 35395 },
        tbc_name = "Crusader Strike",
        source = "sim wowsims/sod ui/retribution_paladin/apls/p8-exodin.apl.json i=7 (Crusader Strike 407676; also p8-stack i=5, p8-wrath i=8, p8-shockadin-1h i=11); tbc-new ui/specs/paladin/retribution/apls/default.apl.json i=2 (Crusader Strike, IF aura 31892); wotlk ui/retribution_paladin/apls/default.apl.json i=4 (Crusader Strike 35395) - the Era APL has no Crusader Strike row (bench/paladin_rotation_audit_2026-10-19.md §Era)",

        live = true,
        engine = true,    },
    judge = {
        note = "the Judgement cue (the sim judges inside the fit window)",
        families = { ERA = true, SOD = true, TBC = true, FOREVER = true, WRATH = true },
        ids = { ERA = 20271, SOD = 20271, FOREVER = 20271, WRATH = 20271 },
        tbc_name = "Judgement",
        source = "classic ui/retribution_paladin/apls/basic_ret.apl.json i=0 (Judgement 20271); sod p8-exodin i=2 / p8-stack i=9 / p8-shockadin-1h i=4 / p8-wrath i=4 (Judgement 20271); tbc-new default.apl.json i=3 (Judgement 20271); forever twist_of_light i=1 / holy_shock i=1 (Judgement 20271); wotlk default.apl.json i=3 casts JUDGEMENT OF WISDOM 53408 - a DIFFERENT spell from this key's Judgement 20271 (which is Judgement of LIGHT on the WotLK client: sim wowsims/wotlk sim/paladin/judgement.go - registerJudgementOfWisdomSpell is 53408, registerJudgementOfLightSpell is 20271), so the WotLK APL row is not this row: it rides the rotation table as its own line (judgement_of_wisdom below). CORRECTION 2026-10-20 (bench/paladin_apl_utility_build_2026-10-20.md §3 C2): the gap analysis named 53408 'Judgement of Light' - the id and the spell are right, the NAME was wrong (53408 is Judgement of Wisdom)",

        live = true,
        engine = true,    },
    twist = {
        note = "the twist cue (a seal swap inside the window)",
        families = { ERA = true, SOD = true, TBC = true, FOREVER = true },
        ids = {},
        source = "the class's own twist tree (nextaction.lua's twist window); the Era APL's twist rows are basic_ret.apl.json i=2 (Seal of the Crusader 20375 r1) and i=3 (Seal of Righteousness 20293 r8), both IF autoTimeToNext < 0.4s, and the SoD p8-twist.apl.json i=5/6 cast the twist with paladinCastWithMacro - a macro cast, so the row carries no spell id of its own",

        live = true,
        engine = true,    },
    soc = {
        note = "the Seal of Command reseal (the twist's seal on the classic line)",
        families = { ERA = true, SOD = true, TBC = true, FOREVER = true },
        ids = { ERA = 20375, SOD = 20375, FOREVER = 20920 },
        tbc_name = "Seal of Command",
        source = "tbc-new default.apl.json i=5 (Seal of Command 20375 r1 - the reseal guard); forever twist_of_light i=4 (Seal of Command 20920 r5); sod p8-exodin i=3 / p8-wrath i=5 (castPaladinPrimarySeal - the primary-seal macro). The id 20375 is the Seal of the CRUSADER on the Era client and the Seal of Command on TBC (bench/rotation_gap_vs_apl_2026-10-20.md §6.3)",

        live = true,
        engine = true,    },
    sob = {
        note = "the twist's second seal (Blood on TBC, Martyrdom on SoD)",
        families = { SOD = true, TBC = true },
        ids = { SOD = 407798 },
        tbc_name = "Seal of Blood",
        source = "tbc-new default.apl.json i=1 (Seal of Blood 31892 r1, IF aura 20375 AND autoTimeToNext <= .4s); sod p8-stack i=2 (Seal of Martyrdom 20920 r5) and i=3 (the SoD rune rank 407798); the class's twist tree carries the Blood seal on TBC (nextaction.lua's seal states)",

        live = true,
        engine = true,    },
    cons = {
        note = "the Consecration filler (mana-gated)",
        families = { SOD = true, TBC = true, FOREVER = true, WRATH = true },
        ids = { SOD = 20924, FOREVER = 20924, WRATH = 48819 },
        tbc_name = "Consecration",
        source = "sod p8-stack i=8 / p8-wrath i=12 (Consecration 20924 r5); tbc-new default.apl.json i=4.g.1 (Consecration 27173 r6); forever twist_of_light i=6.g.0 / holy_shock i=4 (Consecration 20924 r5); wotlk default.apl.json i=7 (Consecration 48819, IF remainingTime > 4s)",

        live = true,
        engine = true,    },
    exo = {
        note = "the Exorcism filler (the Undead/Demon damage row)",
        families = { SOD = true, TBC = true, FOREVER = true, WRATH = true },
        ids = { SOD = 415073, FOREVER = 10314, WRATH = 48801 },
        tbc_name = "Exorcism",
        source = "sod p8-exodin i=6 / p8-stack i=6 / p8-shockadin-1h i=8 / p8-wrath i=9 (Exorcism 415073); tbc-new default.apl.json i=4.g.0 (Exorcism 27138 r7); forever twist_of_light i=7.g.0 / holy_shock i=10 (Exorcism 10314 r6); wotlk default.apl.json i=6 (Exorcism 48801, IF aura 53488)",

        live = true,
        engine = true,    },
    how = {
        note = "the execute Hammer of Wrath (below 20% target health)",
        families = { ERA = true, SOD = true, FOREVER = true },
        ids = { ERA = 24239, SOD = 24239, FOREVER = 24239 },
        source = "sod p8-twist i=7 (Hammer of Wrath 24239 r3); forever twist_of_light i=2 / holy_shock i=5 (Hammer of Wrath 24239 r3, IF spellCastTime == 0 OR autoTimeSinceLast < 0.2s). The Era APL has no Hammer of Wrath row: the Era execute cue is the class's own below-20% rule (bench/paladin_rotation_audit_2026-10-19.md §Era); the WotLK APL's Hammer of Wrath is its own row (how_wrath below)",

        live = true,
        engine = true,    },
    hw = {
        note = "Holy Wrath on an Undead or Demon target (the SoD stack build's row)",
        families = { SOD = true, WRATH = true },
        ids = { SOD = 10318 },
        source = "sod p8-stack i=7 (Holy Wrath 10318 r2 - Undead only, IF auraKnown(1219193) AND an Undead target). The WotLK APL has NO Holy Wrath row - its damage rows are Exorcism 48801 and Consecration 48819 (bench/rotation_gap_vs_apl_2026-10-20.md §6.4) - so the class keeps its own Undead/Demon line there (the rank ladder is classes/paladin.lua's hw_ids: 48817, 48816, 27139, 10318, 2812, resolved from the client's book)",

        live = true,
        engine = true,    },
    ds = {
        note = "the Divine Storm cooldown (the SoD/Wrath burst)",
        families = { SOD = true, WRATH = true },
        ids = { SOD = 407778, WRATH = 53385 },
        source = "sod p8-exodin i=4 / p8-stack i=4 / p8-wrath i=7 and i=10 (Divine Storm 407778); wotlk default.apl.json i=5 (Divine Storm 53385)",

        live = true,
        engine = true,    },
    hs = {
        note = "Holy Shock at three Holy Power stacks (the shockadin's row)",
        families = { SOD = true, FOREVER = true },
        ids = { SOD = 20930, FOREVER = 20930 },
        source = "sod p8-shockadin-1h i=7 and i=10 (Holy Shock 20930 r3); forever holy_shock i=9 (Holy Shock 20930 r4)",

        live = true,
        engine = true,    },
    am = {
        note = "Aura Mastery at three Holy Power stacks (the Libram-gated row)",
        families = { SOD = true },
        ids = { SOD = 407624 },
        source = "sod p8-shockadin-1h i=6 and i=9 (Aura Mastery 407624 - the legs rune, the Libram of Sanctity gate 1214298)",

        live = true,
        engine = true,    },
    hor = {
        note = "the WotLK APL's top row - Hand of Reckoning (the utility band above the damage order)",
        families = { WRATH = true },
        ids = { WRATH = ST.PALADIN.APL_UTILITY.hor.id },
        source = "wotlk ui/retribution_paladin/apls/default.apl.json i=1 (Hand of Reckoning 67485 - the APL's TOP row; sim wowsims/wotlk sim/paladin/hand_of_reckoning.go:16). APL UTILITY LAYER (bench/paladin_apl_utility_build_2026-10-20.md §2): the row is ARMED - the engine's Wrath order carries it above the damage rows (nextaction.lua's FCFS_ORDER_WRATH) and the read is api.GetSpellCooldown(67485) behind the client's own spell-book gate (the same gate the class's Divine Storm resolver uses for its WotLK talent spell - classes/paladin.lua's resolve_ds_spell_id), so a build without the talent is never prompted. The spell-book probe on a TALENT id is in-client UNCONFIRMED: if the client answers 'unknown' for a learned talent the row stays SILENT (unknown-hides, never a wrong prompt) and the operator's in-client check decides whether another gate is needed",
        live = true,
        engine = true,
    },
    how_wrath = {
        note = "the WotLK APL's second row - Hammer of Wrath (the WotLK spell, not the execute one)",
        families = { WRATH = true },
        ids = { WRATH = ST.PALADIN.APL_UTILITY.how_wrath.id },
        source = "wotlk ui/retribution_paladin/apls/default.apl.json i=2 (Hammer of Wrath 48806; sim wowsims/wotlk sim/paladin/hammer_of_wrath.go:12). APL UTILITY LAYER (bench/paladin_apl_utility_build_2026-10-20.md §2): the row is ARMED - the engine's Wrath order carries it below Hand of Reckoning and above the damage rows, and the sim gates the cast on the execute phase (hammer_of_wrath.go:31-32 ExtraCastCondition: sim.IsExecutePhase20()), so the arm asks for it only below 20% target health. The 'how' key is the Era/Forever EXECUTE Hammer of Wrath (24239) - a different spell, a different key",
        live = true,
        engine = true,
    },
    judgement_of_wisdom = {
        note = "the WotLK APL's judgement row - Judgement of Wisdom (the target debuff)",
        families = { WRATH = true },
        ids = { WRATH = ST.PALADIN.APL_UTILITY.judgement_of_wisdom.id },
        source = "wotlk ui/retribution_paladin/apls/default.apl.json i=3 (Judgement of Wisdom 53408; sim wowsims/wotlk sim/paladin/judgement.go:22 - registerJudgementOfWisdomSpell, ActionID 53408). NAME CORRECTION 2026-10-20 (bench/paladin_apl_utility_build_2026-10-20.md §3 C2): the gap analysis named this spell 'Judgement of Light' - 53408 is Judgement of WISDOM (the debuff) and 20271 is Judgement of Light (the damage spell), so this row is NOT the shipped 'judge' key (whose WotLK id is 20271)",
        live = true,
        engine = false,
        needs = "an engine arm for this row needs a SLOT that does not collide with the shipped judgement cue: 53408 (Judgement of Wisdom) and 20271 (Judgement of Light) share the WotLK 10 s judgement cooldown (sim wowsims/wotlk sim/paladin/judgement.go:38 - one cdTimer for both judgements), so the two rows can never be ready apart and an arm would REPLACE the shipped judgement cue on the WotLK client. That is the operator-visible re-cut bench/rotation_gap_vs_apl_2026-10-20.md §6.5 filed (the WotLK APL's whole priority list); the read itself exists (api.GetSpellCooldown(53408)), so the row is live but claims no arm until the operator rules on which judgement the WotLK guide cues",
    },
    holy_strike = {
        note = "the Forever APL's Holy Strike row (10333 r8)",
        families = { FOREVER = true },
        ids = { FOREVER = ST.PALADIN.APL_UTILITY.holy_strike.id },
        source = "forever ui/specs/paladin/retribution/apls/twist_of_light.apl.json i=3 (Holy Strike 10333 r8, IF currentTime > 0.5s) and holy_shock.apl.json i=7 (Holy Strike 10333 r8); the id is the client's own (sim wowsims/forever sim/paladin/holy_strike.go:12 - wowhead.com/forever/spell=10333; the client's spell ladder is 679, 678, 1866, 680, 2495, 5569, 10332, 10333)",
        live = true,
        engine = false,
        needs = "an engine arm for this row needs the FOREVER TWIST ORDER re-cut onto the APL's priority list (judgement > hammer of wrath > holy strike > seal of command > seal of righteousness > consecration > exorcism): Holy Strike has NO cooldown of its own on the Forever client (the client's own sim registers it without a CD - sim wowsims/forever sim/paladin/holy_strike.go), so a 'ready' arm would fire on every GCD and displace the twist cue the class's Forever guide exists for. The bench filed the same re-cut as operator-visible (bench/rotation_gap_vs_apl_2026-10-20.md §6.5); the read exists (the class's own spell-book probe, self.holy_strike_known), so the row is live but claims no arm until the operator rules on the Forever order",
    },
    divine_favor = {
        note = "the Forever APL's Divine Favor row (20216)",
        families = { FOREVER = true },
        ids = { FOREVER = ST.PALADIN.APL_UTILITY.divine_favor.id },
        source = "forever ui/specs/paladin/retribution/apls/holy_shock.apl.json i=8 (Divine Favor 20216, IF spellIsReady(20930 r4) AND the target-aura clause on 1310905); the id is the client's own (sim wowsims/forever sim/paladin/spell_data_auto_gen.go:183 DivineFavor: spelldata.Ranked(20216) - the sim's own label is 'Divine Favor'; sim wowsims/classic sim/paladin/divine_favor.go:28 ActionID 20216). NAME CORRECTION 2026-10-20 (bench/paladin_apl_utility_build_2026-10-20.md §3 C1): the gap analysis named this spell 'Devotion Aura' - 20216 is DIVINE FAVOR on the Era, TBC and Forever clients alike (the 1.15 client's own spell tables put 20216 in the Holy skill line, next to Seal of Righteousness and Holy Shock; the Forever client's own ladder says Divine Favor)",
        live = true,
        engine = false,
        needs = "an engine arm for this row needs the APL's own condition modelled: 'the Divine Favor buff is DOWN' (the sim's Divine Favor buff is consumed by the next Holy Shock hit - sim wowsims/classic sim/paladin/divine_favor.go:37 OnSpellHitDealt deactivates the aura) AND 'Holy Shock is ready' (the APL's spellIsReady(20930 r4)) AND the target-aura clause on 1310905 (the Forever client's Consecrated Ground). The cooldown read exists (api.GetSpellCooldown(20216)) and the client's spell book answers the known gate, but the shipped tree has no Holy-Shock cooldown read on the Forever family and no read that separates 'the buff is absent' from 'the buff could not be read' (api.scan_player_aura answers nil for both - compat.lua:514), so an arm built on the cooldown alone could ask for a buff that is UP. Filed, not guessed",
    },
}

-- The APL rows the shipped prompt orders do not name: the WotLK APL's top two
-- (Hand of Reckoning 67485, Hammer of Wrath 48806).
--
-- 2026-10-20 (the APL utility layer): the WotLK APL's top two rows left this
-- table - they are ENGINE rows now. The guide has a slot for each (the
-- contract's count pin was re-cut: ten slots -> twelve), the engine's Wrath
-- order carries them above the damage rows (nextaction.lua's FCFS_ORDER_WRATH)
-- and the class feeds their cooldowns, so the practice slice can ask for them.
--
-- WHAT IS LEFT HERE is the APL's rows the engine cannot press yet: each names
-- the exact read or the exact rule it waits for in `needs` (HU-13's `live` /
-- `engine` axes), and each is family-gated, so a client never sees another
-- family's row.
ST.PALADIN.practice_apl_rows = {
    {
        action = "judgement_of_wisdom",
        order = "wrath",
        families = { WRATH = true },
    },
    {
        action = "holy_strike",
        order = "twist",
        families = { FOREVER = true },
    },
    {
        action = "divine_favor",
        order = "twist",
        families = { FOREVER = true },
    },
}

-- The APL's PRE-PULL rows (the operator ruling HU-12, hands-up 2026-10-20): they
-- belong to the PRE-PULL table, never to the combat rotation. The prepull DRILL
-- grades the SEAL (the spec above: the seal that must be up and the lead); the
-- utility pre-pulls below have no consumer yet, so they are carried as
-- citations only - the table is the pre-pull layer, not the rotation.
--
--   tbc-new   Prepull: 20218 Sanctity Aura @-18.5 s, group PrepullSeal @-1.5 s
--             (27158 Seal of the Crusader OR 20375 Seal of Command - the row
--             the "Prepull Seal Of the Crusader" variable picks), group
--             PrepullJudge @0 s (20271 Judgement), group PullSeal @0 s
--             (31892 Seal of Blood OR 20375 Seal of Command)
--   forever   twist_of_light Prepull: 10301 @-10 s, 20920 r5 @-3 s, 20308 r6
--             @-1.5 s; holy_shock Prepull: 10301 @-10 s, 20308 r6 @-1.5 s
--   sod       p8-stack Prepull: 20920 r5 @-3 s, 407798 Seal of Martyrdom
--             @-1.5 s; p8-twist Prepull: 20920 r5 @-1.5 s (the StopAttack
--             macro cast), 407798 @0 s (the StartAttack macro cast)
--
-- 10301 is "Retribution Aura" - NAME CONFIRMED 2026-10-20 (bench/
-- paladin_apl_utility_build_2026-10-20.md §3 C3): the Forever client's own
-- sim file names it (sim wowsims/forever sim/paladin/retribution_aura.go:11 -
-- wowhead.com/forever/spell=10301) and the 1.15 client's own spell tables put
-- 10301 in the Retribution skill line. The gap analysis listed it as
-- "Redemption" with the name UNCONFIRMED.
--
-- The class's own PRACTICE_PREPULL table above (the seal + the lead per order)
-- is what the prepull DRILL grades; this table is the citation layer.
ST.PALADIN.practice_prepull_rows = {
    {
        action = "sanctity_aura",
        label = "Sanctity Aura",
        id = 20218,
        lead = 18.5,
        families = { TBC = true },
        source = "sim wowsims/tbc-new ui/specs/paladin/retribution/apls/default.apl.json Prepull: Sanctity Aura (20218) @-18.5 s",
    },
    {
        action = "retribution_aura",
        label = "Retribution Aura",
        id = 10301,
        lead = 10,
        families = { FOREVER = true },
        source = "sim wowsims/forever ui/specs/paladin/retribution/apls/twist_of_light.apl.json Prepull: 10301 @-10 s (also holy_shock.apl.json) - the spell is Retribution Aura (sim wowsims/forever sim/paladin/retribution_aura.go:11 - wowhead.com/forever/spell=10301; the 1.15 client's own spell tables put 10301 in the Retribution skill line). NAME CORRECTION 2026-10-20: the gap analysis named it 'Redemption' with the name UNCONFIRMED",
    },
    {
        action = "soc_prepull",
        label = "Seal of Command",
        id = 20375,
        lead = 1.5,
        families = { TBC = true },
        source = "sim wowsims/tbc-new ui/specs/paladin/retribution/apls/default.apl.json Prepull: group PrepullSeal @-1.5 s, row 2 (20375 Seal of Command r1 - the branch the 'Prepull Seal Of the Crusader' variable leaves open)",
    },
    {
        action = "sotc_prepull",
        label = "Seal of the Crusader",
        id = 27158,
        lead = 1.5,
        families = { TBC = true },
        source = "sim wowsims/tbc-new ui/specs/paladin/retribution/apls/default.apl.json Prepull: group PrepullSeal @-1.5 s, row 1 (27158 Seal of the Crusader - the branch the 'Prepull Seal Of the Crusader' variable picks)",
    },
    {
        action = "judge_prepull",
        label = "Judgement",
        id = 20271,
        lead = 0,
        families = { TBC = true },
        source = "sim wowsims/tbc-new ui/specs/paladin/retribution/apls/default.apl.json Prepull: group PrepullJudge @0 s (20271 Judgement)",
    },
    {
        action = "sob_prepull",
        label = "Seal of Blood",
        id = 31892,
        lead = 0,
        families = { TBC = true },
        source = "sim wowsims/tbc-new ui/specs/paladin/retribution/apls/default.apl.json Prepull: group PullSeal @0 s, row 1 (31892 Seal of Blood - the branch the 'Prepull Seal Of the Crusader' variable leaves open)",
    },
    {
        action = "soc_pull",
        label = "Seal of Command",
        id = 20375,
        lead = 0,
        families = { TBC = true },
        source = "sim wowsims/tbc-new ui/specs/paladin/retribution/apls/default.apl.json Prepull: group PullSeal @0 s, row 2 (20375 Seal of Command - the branch the 'Prepull Seal Of the Crusader' variable picks)",
    },
    {
        action = "soc_prepull",
        label = "Seal of Command",
        id = 20920,
        lead = 3,
        families = { FOREVER = true },
        source = "sim wowsims/forever ui/specs/paladin/retribution/apls/twist_of_light.apl.json Prepull: 20920 r5 @-3 s (Seal of Command - the client's own ladder, sim wowsims/forever sim/paladin/spell_data_auto_gen.go:271 SealOfCommand Ranked(20375, 20915, 20918, 20919, 20920))",
    },
    {
        action = "sotc_prepull",
        label = "Seal of the Crusader",
        id = 20308,
        lead = 1.5,
        families = { FOREVER = true },
        source = "sim wowsims/forever ui/specs/paladin/retribution/apls/twist_of_light.apl.json Prepull: 20308 r6 @-1.5 s and holy_shock.apl.json Prepull: 20308 r6 @-1.5 s (Seal of the Crusader - the client's own ladder, sim wowsims/forever sim/paladin/spell_data_auto_gen.go:283 SealOfTheCrusader Ranked(21082, 20162, 20305, 20306, 20307, 20308))",
    },
    {
        action = "soc_prepull",
        label = "Seal of Command",
        id = 20920,
        lead = 3,
        families = { SOD = true },
        source = "sim wowsims/sod ui/retribution_paladin/apls/p8-stack.apl.json Prepull: 20920 r5 @-3 s (Seal of Command)",
    },
    {
        action = "som_prepull",
        label = "Seal of Martyrdom",
        id = 407798,
        lead = 1.5,
        families = { SOD = true },
        source = "sim wowsims/sod ui/retribution_paladin/apls/p8-stack.apl.json Prepull: 407798 @-1.5 s (Seal of Martyrdom - the SoD rune rank; the class's own sob_ids carries the aura id, classes/paladin.lua)",
    },
}

-- The rotation table: one entry per action, in the order the rotations name
-- them, each entry carrying the orders it belongs to and its APL payload (the
-- citation, the family gate and the family's spell id - the APL layer above).
-- The order id is the family/variant key ("twist", "wrath", "sod", "sod_stack",
-- "sod_shock", "sod_wrath"); the priority inside one order is that order's own
-- table.
local function build_practice_rotation()
    local list = {}
    local seen = {}
    -- The entry builder lives inside this function: the module sits at the
    -- Lua 5.1 local ceiling, so a helper of its own would not load.
    local function new_entry(key)
        local meta = ST.PALADIN.practice_action_meta[key] or {}
        return {
            action = key,
            label = PRACTICE_ACTION_LABELS[key] or key,
            orders = {},
            note = meta.note,
            source = meta.source,
            families = meta.families,
            ids = meta.ids,
            tbc_name = meta.tbc_name,
            live = meta.live,
            engine = meta.engine,
            needs = meta.needs,
        }
    end
    local order_ids = { "twist", "wrath", "sod", "sod_stack", "sod_shock", "sod_wrath" }
    for i = 1, #order_ids do
        local id = order_ids[i]
        local keys = ST.PALADIN.practice_orders[id]
        if type(keys) == "table" then
            for n = 1, #keys do
                local key = keys[n]
                local entry = seen[key]
                if not entry then
                    entry = new_entry(key)
                    seen[key] = entry
                    list[#list + 1] = entry
                end
                entry.orders[#entry.orders + 1] = id
            end
        end
    end
    -- The APL rows the shipped prompt orders do not name (the APL utility
    -- layer: the WotLK APL's Judgement of Wisdom and the Forever APL's Holy
    -- Strike and Divine Favor): they carry their order membership like every
    -- other row, so the table is the full APL layer.
    local apl_rows = ST.PALADIN.practice_apl_rows
    for i = 1, #apl_rows do
        local spec = apl_rows[i]
        local entry = seen[spec.action]
        if not entry then
            entry = new_entry(spec.action)
            seen[spec.action] = entry
            list[#list + 1] = entry
        end
        entry.orders[#entry.orders + 1] = spec.order
    end
    return list
end

ST.PALADIN.practice_rotation = build_practice_rotation()

-- The rotation entry of one action key (nil when the table does not name it).
function ST.PALADIN.practice_rotation_entry(action)
    for n = 1, #ST.PALADIN.practice_rotation do
        local entry = ST.PALADIN.practice_rotation[n]
        if entry.action == action then
            return entry
        end
    end
    return nil
end

-- The rotation table of one order, in that order's priority (nil for an
-- unknown order id). The order id is OPTIONAL: the shared panel calls this
-- without one (the class picks its own slice - the running client's order),
-- so an argument-free call answers the running order's slice.
--
-- THE FAMILY GATE (the deep audit's M2): a row joins the slice only on the
-- clients whose APL plays it - the row's own `families` set, the same
-- predicate the rogue, warrior and druid slices use (classes/rogue.lua:2858).
-- The twist order is shared by the classic line (ERA / TBC / FOREVER), so
-- without the gate the TBC panel rendered a "Hammer of Wrath" button the TBC
-- rotation can never ask for: the engine's execute arm is Era/Forever only
-- (nextaction.lua's filler branch: `era_mode or forever_mode`), so pressing
-- it graded `out_of_order` = F for a spell the rotation never wanted.
--
-- THE FAMILY TOKEN: the SoD game runs on the ERA client, so the ORDER names
-- it - the SoD variants are their own orders ("sod", "sod_stack",
-- "sod_shock", "sod_wrath" -> SOD) - and every other order is the twist tree,
-- which answers the client's own family (compat.lua's st.family: ERA / TBC /
-- FOREVER). The order and the gate therefore never disagree: the running
-- order on a SoD client is the SoD one (the live gather publishes it), and
-- the twist order is the classic line's.
--
-- A client that plays no rotation at all (Retail, Cata, Mists) names no row,
-- so its slice is empty and the panel falls back to the guide slot vocabulary
-- (practice_ui.lua's designed fallback). No such client can run the scenario
-- anyway: the rotation scenario needs a live swing engine, and those clients
-- run the inert stand-in.
function ST.PALADIN.practice_rotation_for(order_id)
    local id = order_id
    if type(id) ~= "string" or id == "" then
        -- The live gather's answer wins (it knows which SoD variant the client
        -- plays); the family default stands until it answers.
        id = ST.PALADIN.practice_running_order or ST.PALADIN.practice_default_order()
    end
    local keys = ST.PALADIN.practice_orders[id]
    if type(keys) ~= "table" then
        return nil
    end
    local family = st.family
    if id == "wrath" then
        family = "WRATH"
    elseif id == "sod" or id == "sod_stack" or id == "sod_shock" or id == "sod_wrath" then
        family = "SOD"
    end
    local out = {}
    for i = 1, #keys do
        local entry = ST.PALADIN.practice_rotation_entry(keys[i])
        if entry and (entry.families == nil or entry.families[family] == true) then
            out[#out + 1] = entry
        end
    end
    -- The APL rows this order names but the engine's prompt order does not (the
    -- APL utility layer): they ride the slice as cited rows - but ONLY the ones
    -- the engine can actually ask for. A row with no engine arm (engine =
    -- false) can never be the right answer, so it stays out of the practice
    -- panel's button vocabulary (the hunter lane's rule) and lives in the
    -- rotation table only. The family gate rides with them: a row another
    -- family's APL plays is not this client's button either.
    local apl_rows = ST.PALADIN.practice_apl_rows
    for i = 1, #apl_rows do
        local spec = apl_rows[i]
        if spec.order == id then
            local entry = ST.PALADIN.practice_rotation_entry(spec.action)
            if entry and entry.engine ~= false and entry.live ~= false
                and (entry.families == nil or entry.families[family] == true) then
                out[#out + 1] = entry
            end
        end
    end
    return out
end

-- The scenario key the shared engine should register this class's rotation
-- scenario under (bench/class_features_drills_2026-10-19.md §2 D: S-P).
ST.PALADIN.practice_scenario_key = "paladin_rotation"

-- One reused input table and one reused output table: a practice tick
-- allocates nothing (the guide's own discipline).
local practice_inputs = {}
local practice_out = {}

-- The clock: the context first, then the session.
local function practice_now(self, ctx)
    if type(ctx) == "table" then
        local value = ctx.now
        if type(value) == "number" and value == value then
            return value
        end
    end
    if type(self) == "table" then
        local value = self.now
        if type(value) == "number" and value == value then
            return value
        end
    end
    return nil
end

-- The session state: the shared engine may hand over the session (whose sim
-- lives under .state) or the sim itself.
local function practice_state(self)
    if type(self) ~= "table" then
        return nil
    end
    if type(self.state) == "table" then
        return self.state
    end
    return self
end

-- Cooldown aliases per action key (the context's spelling, the practice sim's
-- ability key and a couple of spell names).
local PRACTICE_COOLDOWN_ALIASES = {
    cs = { "cs", "crusader_strike" },
    judge = { "judge", "judgement" },
    ds = { "ds", "divine_storm" },
    cons = { "cons", "consec", "consecration" },
    exo = { "exo", "exorcism" },
    how = { "how", "hammer_of_wrath" },
    hw = { "hw", "holy_wrath" },
    soc = { "soc", "seal_of_command" },
    sob = { "sob", "seal_of_blood", "seal_of_martyrdom" },
    sotc = { "sotc", "seal_of_the_crusader" },
    hs = { "hs", "holy_shock" },
    am = { "am", "aura_mastery" },
    -- The WotLK APL's utility band. The spell-name aliases are deliberately
    -- distinct from "how"'s ("hammer_of_wrath" is the Era/Forever EXECUTE
    -- Hammer of Wrath, 24239): the WotLK one is 48806 and has its own key.
    hor = { "hor", "hand_of_reckoning" },
    how_wrath = { "how_wrath", "hammer_of_wrath_wotlk", "wotlk_hammer_of_wrath" },
}

-- The shipped sim's absolute cooldown fields (practice.lua new_sim): a session
-- may hand over the sim, whose cooldowns are end times, not remainders.
local PRACTICE_SIM_EXPIRY = {
    cs = "cs_cooldown_expires",
    judge = "judge_cooldown_expires",
    cons = "consec_cooldown_expires",
}

-- Seconds remaining for one action key, or nil when the context cannot
-- answer (unknown = withheld, never a wrong prompt). The engine's 999 sentinel
-- is passed through unchanged (it means "unknown on this client" there too).
local function practice_remaining(self, ctx, key)
    local aliases = PRACTICE_COOLDOWN_ALIASES[key]
    if not aliases then
        return nil
    end
    if type(ctx) == "table" and type(ctx.cooldowns) == "table" then
        for i = 1, #aliases do
            local value = ctx.cooldowns[aliases[i]]
            if type(value) == "number" and value == value then
                return value < 0 and 0 or value
            end
        end
    end
    local now = practice_now(self, ctx)
    local field = PRACTICE_SIM_EXPIRY[key]
    if now ~= nil and field ~= nil then
        local state = practice_state(self)
        if state then
            local expires = state[field]
            if type(expires) == "number" and expires == expires then
                local remaining = expires - now
                return remaining < 0 and 0 or remaining
            end
        end
    end
    return nil
end

-- The player's press, normalised onto the canonical key (nil when the context
-- reports no press).
local function practice_action(ctx)
    if type(ctx) ~= "table" then
        return nil
    end
    local raw = ctx.last_action
    if type(raw) ~= "string" or raw == "" then
        return nil
    end
    local key = string.lower(raw)
    local alias = ST.PALADIN.practice_action_aliases[key]
    if alias then
        return alias
    end
    if PRACTICE_ACTION_LABELS[key] then
        return key
    end
    return nil
end

-- The seal state in the ENGINE's vocabulary ("soc" | "sob" | "none"): the
-- twist seals only. nil when the context cannot answer.
local function practice_seal(self, ctx)
    local na = st.nextaction
    if type(ctx) == "table" then
        local seal = ctx.seal
        if type(seal) == "string" and seal ~= "" then
            if seal == "soc" or seal == "sob" then
                return seal
            end
            if seal == "none" then
                return "none"
            end
        end
    end
    local has_soc, has_sob
    local state = practice_state(self)
    if state and type(state.active_seals) == "table" then
        local seals = state.active_seals
        has_soc = seals.command == true or seals.soc == true
        has_sob = seals.blood == true or seals.sob == true
    else
        local soc = practice_remaining(self, ctx, "soc")
        local sob = practice_remaining(self, ctx, "sob")
        if soc == nil and sob == nil then
            return nil
        end
        has_soc = soc ~= nil and soc > 0
        has_sob = sob ~= nil and sob > 0
        -- The engine's own rule: Blood wins the dual-seal window, and a Seal
        -- of Command with 1 s or less left reads as no seal.
        return na.get_seal_state(has_soc, has_sob, soc)
    end
    -- The sim knows which seals are up, not how long they last: the Command
    -- freshness rule reads as fresh (na.get_seal_state with no expiry).
    if na then
        return na.get_seal_state(has_soc, has_sob, nil)
    end
    if has_sob then
        return "sob"
    end
    if has_soc then
        return "soc"
    end
    return "none"
end

-- The seal state in the PRACTICE key space ("soc" | "sob" | "sotc" | "none"):
-- the prepull drill needs the Seal of the Crusader too, which the twist tree
-- does not know. nil when the context cannot answer.
local function practice_seal_key(self, ctx)
    if type(ctx) == "table" then
        local seal = ctx.seal_key or ctx.seal
        if type(seal) == "string" and seal ~= "" then
            local lower = string.lower(seal)
            if lower == "soc" or lower == "sob" or lower == "sotc" then
                return lower
            end
            local alias = ST.PALADIN.practice_action_aliases[lower]
            if alias == "soc" or alias == "sob" or alias == "sotc" then
                return alias
            end
            if lower == "none" then
                return "none"
            end
        end
    end
    local state = practice_state(self)
    if state and type(state.active_seals) == "table" then
        local seals = state.active_seals
        if seals.command == true or seals.soc == true then
            return "soc"
        end
        if seals.blood == true or seals.sob == true then
            return "sob"
        end
        if seals.crusader == true or seals.sotc == true then
            return "sotc"
        end
        return "none"
    end
    local soc = practice_remaining(self, ctx, "soc")
    local sob = practice_remaining(self, ctx, "sob")
    local sotc = practice_remaining(self, ctx, "sotc")
    if soc ~= nil and soc > 0 then
        return "soc"
    end
    if sob ~= nil and sob > 0 then
        return "sob"
    end
    if sotc ~= nil and sotc > 0 then
        return "sotc"
    end
    return nil
end

-- Seconds to the next swing, or nil when the context cannot answer.
local function practice_swing_remaining(self, ctx)
    if type(ctx) == "table" then
        local value = ctx.swing_remaining
        if type(value) == "number" and value == value then
            return value < 0 and 0 or value
        end
    end
    local now = practice_now(self, ctx)
    local state = practice_state(self)
    if state and now ~= nil then
        local ends = state.swing_ends_at
        if type(ends) == "number" and ends == ends then
            local remaining = ends - now
            return remaining < 0 and 0 or remaining
        end
    end
    return nil
end

-- Seconds of GCD left, or nil when the context cannot answer.
local function practice_gcd_remaining(self, ctx)
    if type(ctx) == "table" then
        local value = ctx.gcd_remaining
        if type(value) == "number" and value == value then
            return value < 0 and 0 or value
        end
    end
    local now = practice_now(self, ctx)
    local state = practice_state(self)
    if state and now ~= nil then
        local expires = state.gcd_expires
        if type(expires) == "number" and expires == expires then
            local remaining = expires - now
            return remaining < 0 and 0 or remaining
        end
    end
    return nil
end

-- The weapon speed, seconds per swing (nil = the engine's own default).
local function practice_speed(self, ctx)
    if type(ctx) == "table" then
        local value = ctx.speed
        if type(value) == "number" and value == value then
            return value
        end
    end
    local state = practice_state(self)
    if state then
        local value = state.effective_speed or state.speed
        if type(value) == "number" and value == value then
            return value
        end
    end
    return nil
end

-- The GCD length, seconds (nil = the engine's own default of 1.5).
local function practice_gcd_duration(self, ctx)
    if type(ctx) == "table" then
        local value = ctx.gcd_duration
        if type(value) == "number" and value == value then
            return value
        end
    end
    local state = practice_state(self)
    if state then
        local value = state.effective_gcd or state.gcd_duration
        if type(value) == "number" and value == value then
            return value
        end
    end
    return nil
end

-- A number out of the context, with the alias list the shared engine may use.
local function practice_number(ctx, ...)
    if type(ctx) ~= "table" then
        return nil
    end
    for i = 1, select("#", ...) do
        local value = ctx[select(i, ...)]
        if type(value) == "number" and value == value then
            return value
        end
    end
    return nil
end

-- A number out of the context's resources table.
local function practice_resource(ctx, ...)
    if type(ctx) ~= "table" or type(ctx.resources) ~= "table" then
        return nil
    end
    for i = 1, select("#", ...) do
        local value = ctx.resources[select(i, ...)]
        if type(value) == "number" and value == value then
            return value
        end
    end
    return nil
end

-- Crusader Strike availability: the context wins, then the client's own spell
-- book (the same probe the live gather uses), then the family default (Era
-- has no Crusader Strike at all - bench/class_features_drills_2026-10-19.md
-- §2 P-14).
local function practice_cs_known(self, ctx)
    if type(ctx) == "table" and type(ctx.cs_known) == "boolean" then
        return ctx.cs_known
    end
    local na = st.nextaction
    if na and na.CS_SPELL_ID then
        return is_spell_known_query(na.CS_SPELL_ID)
    end
    return not is_era_family
end

-- The FCFS mode the running client plays when nothing else names one: the
-- family default. Wrath runs its own FCFS table, the SoD runes run the Exodin
-- table (the shipped default), every other family runs the twist tree (no FCFS
-- mode). The SoD variants (stack / shockadin / wrath-like) need the build's own
-- live signals - only the live gather has them, and it names them in the
-- context (see the ctx builder below).
function ST.PALADIN.practice_default_mode(self, ctx)
    if is_wrath_family then
        return "wrath"
    end
    if is_era_family then
        local now = practice_now(self, ctx) or api.get_time()
        local ds_id = resolve_ds_spell_id(now)
        if is_sod_client(practice_cs_known(self, ctx), ds_id) then
            return "sod"
        end
    end
    return nil
end

-- The FCFS mode (nil = the twist tree). The context wins, then the session,
-- then the family default.
local function practice_fcfs_mode(self, ctx)
    if type(ctx) == "table" then
        local mode = ctx.fcfs_mode
        if type(mode) == "string" and mode ~= "" then
            return mode
        end
    end
    local state = practice_state(self)
    if state and type(state.fcfs_mode) == "string" and state.fcfs_mode ~= "" then
        return state.fcfs_mode
    end
    return ST.PALADIN.practice_default_mode(self, ctx)
end

-- The order the running client plays, when no live gather has answered yet (the
-- family default: the Wrath FCFS table, the SoD Exodin table or the twist
-- tree). The live gather's answer wins (practice_running_order): it is the only
-- place that knows which SoD variant the client plays.
function ST.PALADIN.practice_default_order()
    return ST.PALADIN.practice_order_for_mode(ST.PALADIN.practice_default_mode(nil, nil))
end

-- Build the engine inputs from the practice context. Returns false when the
-- core timing or the seal cannot be read: the decision would be fiction, and
-- a fiction is worse than an unknown.
local function build_practice_inputs(self, ctx, inputs)
    local now = practice_now(self, ctx)
    local mode = practice_fcfs_mode(self, ctx)
    local swing_remaining = practice_swing_remaining(self, ctx)
    local gcd_remaining = practice_gcd_remaining(self, ctx)
    if swing_remaining == nil and not (mode and gcd_remaining ~= nil) then
        return false
    end
    local seal = practice_seal(self, ctx)
    if seal == nil then
        return false
    end
    inputs.now = now
    inputs.swing_remaining = swing_remaining or 0
    inputs.gcd_remaining = gcd_remaining or 0
    inputs.speed = practice_speed(self, ctx)
    inputs.G = practice_gcd_duration(self, ctx)
    -- The GCD-before-swing landmark: the gathered value when the live path
    -- published one, the GCD length otherwise (the sim path, unchanged).
    inputs.gcd_before_swing = practice_number(ctx, "gcd_before_swing") or inputs.G
    inputs.twist_window = practice_number(ctx, "twist_window")
    -- The reaction time and the Crusader Strike delay: the client's own settings
    -- when the live path published them, the shipped defaults otherwise.
    inputs.reaction = practice_number(ctx, "reaction") or 0.1
    inputs.cs_delay_max = practice_number(ctx, "cs_delay_max") or 0.9
    inputs.seal = seal
    inputs.waiting_judgement = false
    inputs.melee_count = practice_number(ctx, "melee_count") or 0
    inputs.mana_pct = practice_number(ctx, "mana_pct")
        or practice_resource(ctx, "mana_pct", "mana") or 0
    inputs.creature_type = nil
    if type(ctx) == "table" then
        inputs.creature_type = ctx.creature_type
        if inputs.creature_type == nil and type(ctx.resources) == "table" then
            inputs.creature_type = ctx.resources.creature_type
        end
    end
    inputs.target_count = practice_number(ctx, "target_count")
        or practice_resource(ctx, "target_count")
    inputs.target_health_pct = practice_number(ctx, "target_health_pct")
        or practice_resource(ctx, "target_health_pct")
    inputs.fight_remaining_pct = practice_number(ctx, "fight_remaining_pct")
        or practice_resource(ctx, "fight_remaining_pct")
    inputs.how_cast_seconds = practice_number(ctx, "how_cast_seconds")
    inputs.judge_require_fit = true
    inputs.era = is_era_family
    inputs.forever = is_forever_family
    inputs.fcfs_mode = mode
    inputs.cs_known = practice_cs_known(self, ctx)
    -- The cooldown reads. The twist tree treats a missing Judgement cooldown as
    -- "ready" (it defaults to 0), so an unknown one is passed as the engine's
    -- 999 sentinel instead: unknown withholds the cue, it never invents one.
    inputs.cs_remaining = practice_remaining(self, ctx, "cs") or 999
    inputs.judge_remaining = practice_remaining(self, ctx, "judge") or 999
    inputs.ds_remaining = practice_remaining(self, ctx, "ds")
    inputs.cons_remaining = practice_remaining(self, ctx, "cons")
    inputs.exo_remaining = practice_remaining(self, ctx, "exo")
    inputs.how_remaining = practice_remaining(self, ctx, "how")
    inputs.hw_remaining = practice_remaining(self, ctx, "hw")
    inputs.hs_remaining = practice_remaining(self, ctx, "hs")
    inputs.am_remaining = practice_remaining(self, ctx, "am")
    -- The WotLK APL's utility band (the engine's Wrath order asks for these
    -- first): nil = unknown = withheld, never a wrong press.
    inputs.hor_remaining = practice_remaining(self, ctx, "hor")
    inputs.how_wrath_remaining = practice_remaining(self, ctx, "how_wrath")
    -- The filler mirror: the engine consumes one cooldown value (the filler it
    -- would pick). The mirror follows the engine's own choice order and its
    -- own default thresholds, so the two sides always agree.
    inputs.filler_remaining = nil
    local mana = inputs.mana_pct
    local exo_threshold = practice_number(ctx, "mana_exorcism_threshold")
        or practice_resource(ctx, "mana_exorcism_threshold") or 30
    local cons_threshold = practice_number(ctx, "mana_consecration_threshold")
        or practice_resource(ctx, "mana_consecration_threshold") or 35
    if inputs.creature_type and st.nextaction
        and st.nextaction.exorcism_target_types[inputs.creature_type] then
        if mana > exo_threshold then
            inputs.filler_remaining = practice_remaining(self, ctx, "exo")
        end
    elseif mana > cons_threshold then
        inputs.filler_remaining = practice_remaining(self, ctx, "cons")
    end
    -- The SoD variant signals (APL-cited, in-client UNCONFIRMED): read from the
    -- context when it carries them, unknown otherwise (the engine withholds).
    inputs.holy_power_stacks = practice_number(ctx, "holy_power_stacks")
        or practice_resource(ctx, "holy_power_stacks")
    inputs.holy_power_set_known = nil
    inputs.sod_dual_seal_active = nil
    inputs.sod_t2_known = nil
    inputs.sod_naxx_known = nil
    inputs.sod_libram_known = nil
    inputs.am_rune_known = nil
    inputs.sunlight_remaining = practice_number(ctx, "sunlight_remaining")
    inputs.templar_stack_remaining = practice_number(ctx, "templar_stack_remaining")
    inputs.templar_wrath_remaining = practice_number(ctx, "templar_wrath_remaining")
    -- The stack dual-seal timers (the SoD stack build): the seal's own remaining
    -- seconds. The sim path has no seal timers (unknown); the live path
    -- publishes them under the guide's own names.
    inputs.soc_remaining_seconds = practice_remaining(self, ctx, "soc")
        or practice_number(ctx, "soc_remaining_seconds")
    inputs.som_remaining_seconds = practice_remaining(self, ctx, "sob")
        or practice_number(ctx, "som_remaining_seconds")
    if type(ctx) == "table" then
        if type(ctx.holy_power_set_known) == "boolean" then
            inputs.holy_power_set_known = ctx.holy_power_set_known
        end
        if type(ctx.sod_dual_seal_active) == "boolean" then
            inputs.sod_dual_seal_active = ctx.sod_dual_seal_active
        end
        if type(ctx.sod_t2_known) == "boolean" then
            inputs.sod_t2_known = ctx.sod_t2_known
        end
        if type(ctx.sod_naxx_known) == "boolean" then
            inputs.sod_naxx_known = ctx.sod_naxx_known
        end
        if type(ctx.sod_libram_known) == "boolean" then
            inputs.sod_libram_known = ctx.sod_libram_known
        end
        if type(ctx.am_rune_known) == "boolean" then
            inputs.am_rune_known = ctx.am_rune_known
        end
    end
    return true
end

-- The filler press (the engine's filler channel), mapped onto the practice key
-- space. nil when the engine named no filler.
local function practice_filler_key(filler, mode)
    if filler == "consecration" then
        return "cons", "Consecration filler"
    elseif filler == "exorcism" then
        return "exo", "Exorcism filler"
    elseif filler == "how" then
        if mode == "wrath" then
            return "hw", "Holy Wrath (Undead or Demon)"
        end
        return "how", "Hammer of Wrath execute"
    elseif filler == "holy_shock" then
        return "hs", "Holy Shock at three Holy Power stacks"
    elseif filler == "aura_mastery" then
        return "am", "Aura Mastery (Libram of Sanctity)"
    end
    return nil, nil
end

-- The engine's answer, mapped onto the practice key space. Returns the key and
-- a short reason (nil, reason when the rotation wants nothing pressed).
local function practice_key_from_engine(out, mode)
    if out.judge_call == true then
        return "judge", "Judgement cue"
    end
    if mode then
        -- The FCFS engine: hold means "nothing is ready" (the engine named the
        -- ability to wait for); the action and the filler are the presses.
        if out.hold == true then
            return nil, "hold: wait for the named ability"
        end
        if out.action == "cs" then
            return "cs", "Crusader Strike comes first in the order"
        end
        if out.action == "hor" then
            -- The WotLK APL's top row (Hand of Reckoning 67485): the utility
            -- band sits above the damage rows, so it is the press.
            return "hor", "Hand of Reckoning comes first in the order"
        end
        if out.action == "how_wrath" then
            -- The WotLK APL's second row (Hammer of Wrath 48806, the execute
            -- phase cast - not the Era/Forever execute Hammer of Wrath).
            return "how_wrath", "Hammer of Wrath (WotLK) comes first in the order"
        end
        if out.action == "sob" then
            return "ds", "Divine Storm comes first in the order"
        end
        local key, reason = practice_filler_key(out.filler_kind, mode)
        if key then
            return key, reason
        end
        return nil, "hold: the rotation wants nothing pressed"
    end
    -- The twist tree: the seal work (or the Crusader Strike override) is the
    -- press; while the rotation rides the Blood seal the filler is the only
    -- press available.
    if out.riding == true then
        local key, reason = practice_filler_key(out.filler_kind, mode)
        if key then
            return key, reason
        end
        return nil, "hold: ride the seal, cast nothing"
    end
    if out.action == "cs" then
        if out.hold == true then
            -- Crusader Strike is still on cooldown: the rotation wants it, but
            -- not yet.
            return nil, "hold: wait for Crusader Strike"
        end
        return "cs", "Crusader Strike override"
    end
    if out.action == "soc" then
        return "soc", "Reseal Seal of Command"
    end
    if out.action == "sob" then
        return "sob", "Seal of Blood is the twist seal here"
    end
    if out.action == "twist" then
        return "twist", "Twist window open"
    end
    return nil, "hold: the rotation wants nothing pressed"
end

-- The rotation's decision at one practice decision point. nil when the context
-- cannot answer (the engine grades "unknown"). Otherwise a table:
--   action  the practice key to press (nil when the rotation wants nothing)
--   reason  a short line for the report
--   hold    true when the rotation wants nothing pressed
--   judge   true when the Judgement cue is up
--   mode    the FCFS mode in play (nil = the twist tree)
function ST.PALADIN.practice_decision(self, ctx)
    local na = st.nextaction
    if not (na and na.evaluate) then
        return nil
    end
    if not build_practice_inputs(self, ctx, practice_inputs) then
        return nil
    end
    local mode = practice_inputs.fcfs_mode
    local out = practice_out
    -- The engine seeds `action` from the caller's table (the archive's last
    -- action); a practice tick starts from nothing instead.
    out.action = nil
    if mode and na.evaluate_fcfs then
        na.evaluate_fcfs(practice_inputs, out)
    else
        na.evaluate(practice_inputs, out)
    end
    if out.inputs_unknown == true then
        return nil
    end
    local key, reason = practice_key_from_engine(out, mode)
    if key == nil then
        reason = reason or "hold: the rotation wants nothing pressed"
    end
    return {
        action = key,
        reason = reason,
        hold = key == nil,
        judge = out.judge_call == true,
        mode = mode,
    }
end

-- The expected action at one decision point. nil when the class cannot decide
-- (unknown). A decision to HOLD is a DECISION, not an unknown (the operator
-- ruling HU-8, hands-up 2026-10-19): the twist tree's RIDE window and the FCFS
-- "nothing is ready" answer state the hold explicitly, so the engine can tell a
-- hold (casting then is an illegal cast) from an unknown (no attempt at all).
-- The reason is the engine's own line - never a second opinion.
function ST.PALADIN.practice_scenario_step(self, ctx)
    local decision = ST.PALADIN.practice_decision(self, ctx)
    if not decision then
        return nil
    end
    if not decision.action then
        if decision.hold == true then
            return { action = nil, hold = true, reason = decision.reason }
        end
        return nil
    end
    return { action = decision.action, reason = decision.reason }
end

-- The mis-pick bands (bench/class_features_drills_2026-10-19.md §2 D-P1,
-- [DESIGN] grading policy): no mis-pick S, one A, two B, three C, four or
-- five D, more than five F. Over the spec's ten-decision sample the bands land
-- exactly on that table; between decisions the band is the running grade.
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
-- keyed by the session (ctx.session / ctx.session_id / the session object), so
-- a finished session's counters disappear with it and the shared engine's own
-- tables are never written to. When the engine aggregates the counters itself
-- (ctx.mistakes / ctx.attempts) those win and nothing is stored here.
local practice_drill_state = setmetatable({}, { __mode = "k" })
-- The number of sessions the store holds. A string session id is not
-- collectable, so the store is dropped wholesale once it grows past the cap.
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

-- The running counters for one drill: the mistakes, the decisions and the
-- store entry (nil when the engine owns the counters).
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
        -- The engine's own counters: they hold the totals BEFORE this
        -- decision, so this one is added here.
        mistakes = mistakes + (ok and 0 or 1)
    else
        -- No session and no counters: this one decision is all there is.
        return ok and "S" or "F"
    end
    return practice_band(mistakes)
end

-- The action the rotation wants right now (nil when it cannot be decided).
local function practice_expected_action(self, ctx)
    local decision = ST.PALADIN.practice_decision(self, ctx)
    if not decision or not decision.action then
        return nil
    end
    return decision.action
end

-- The prepull the drill grades: the seal that must be up and the lead (how
-- far before the pull it has to be cast). The rotation's own table is the
-- default; the context may name the seal and the lead itself.
local function practice_prepull_spec(self, ctx)
    local spec = nil
    local mode = practice_fcfs_mode(self, ctx)
    if mode then
        local entry = PRACTICE_PREPULL[mode]
        if entry then
            spec = { seal = entry.seal, lead = entry.lead }
        end
    elseif is_tbc_family then
        -- The tbc-new APL: Seal of the Crusader 27158r7 plus Judgements at 0 s.
        spec = { seal = "sotc", lead = 0 }
    elseif is_era_family then
        -- The classic APL: the primary seal at -1.5 s.
        spec = { seal = "soc", lead = 1.5 }
    end
    -- Forever: no sourced prepull in scope (the spec stays nil).
    if type(ctx) == "table" then
        local seal = ctx.seal_due or ctx.due_seal
        if type(seal) == "string" and seal ~= "" then
            local alias = ST.PALADIN.practice_action_aliases[string.lower(seal)]
                or string.lower(seal)
            local lead = practice_number(ctx, "prepull_lead", "lead_seconds")
            spec = {
                seal = alias,
                lead = lead or (spec and spec.lead) or 0,
            }
        end
    end
    return spec
end

-- The pull time (absolute), or nil when the context cannot answer.
local function practice_pull_at(self, ctx)
    if type(ctx) == "table" then
        local at = ctx.pull_at or ctx.pull_time
        if type(at) == "number" and at == at then
            return at
        end
    end
    local now = practice_now(self, ctx)
    local pull_in = practice_number(ctx, "pull_in_seconds", "time_to_pull_seconds")
    if pull_in == nil then
        pull_in = practice_resource(ctx, "pull_in_seconds", "time_to_pull_seconds")
    end
    if now ~= nil and pull_in ~= nil then
        return now + pull_in
    end
    return nil
end

-- The Judgement verdict: true (judge now), false (do not judge) or nil (the
-- context cannot answer - the Judgement cooldown is unknown, so the verdict
-- would be fiction).
local function practice_judge_verdict(self, ctx)
    if practice_remaining(self, ctx, "judge") == nil then
        return nil
    end
    local decision = ST.PALADIN.practice_decision(self, ctx)
    if not decision then
        return nil
    end
    return decision.judge == true
end

-- The focused graders. Each one answers nil when its decision cannot be
-- judged (never a wrong grade).
ST.PALADIN.practice_drills = {
    {
        -- D-P1 (bench/class_features_drills_2026-10-19.md §2): the rotation
        -- priority order. The expected action is the engine's own answer, which
        -- for the FCFS families IS the frozen order's first ready entry (the
        -- never-wait rule) - so the drill grades the order, not the timing.
        key = "paladin_fcfs_priority",
        label = "FCFS priority order",
        grade = function(self, ctx)
            local expected = practice_expected_action(self, ctx)
            if expected == nil then
                return nil
            end
            local actual = practice_action(ctx)
            if actual == nil then
                return nil
            end
            return practice_grade_band(self, ctx, "paladin_fcfs_priority",
                actual == expected)
        end,
    },
    {
        -- D-P2: the opener. The seal that must be up before the pull, cast
        -- inside the lead (the bands are the spec's [DESIGN] policy).
        key = "paladin_prepull",
        label = "Prepull seal",
        grade = function(self, ctx)
            local spec = practice_prepull_spec(self, ctx)
            if not spec then
                return nil
            end
            local up = practice_seal_key(self, ctx)
            if up == nil then
                return nil
            end
            if up ~= spec.seal then
                -- The wrong seal, or no seal at all.
                return "F"
            end
            local now = practice_now(self, ctx)
            local pull_at = practice_pull_at(self, ctx)
            if now == nil or pull_at == nil then
                -- The seal is up and no countdown is known: nothing to be late
                -- for.
                return "S"
            end
            local late = now - (pull_at - spec.lead)
            if late <= 0 then
                return "S"
            elseif late <= 0.5 then
                return "A"
            elseif late <= 1.0 then
                return "B"
            elseif late <= 1.5 then
                return "C"
            end
            -- Up only after the pull.
            return "D"
        end,
    },
    {
        -- D-P3: the Judgement decision - is it worth the GCD, given the seal
        -- state and the time to the next swing (the fit the sim gates hardest).
        key = "paladin_judge_fit",
        label = "Judgement fit",
        grade = function(self, ctx)
            local verdict = practice_judge_verdict(self, ctx)
            if verdict == nil then
                return nil
            end
            local actual = practice_action(ctx)
            if actual == nil then
                return nil
            end
            if (actual == "judge") ~= verdict then
                -- The wrong verdict: judged when the seal was down, the fit
                -- failed, or the fight was over.
                return "F"
            end
            local cue = practice_number(ctx, "cue_at", "expected_at", "decision_at")
            local now = practice_now(self, ctx)
            if cue == nil or now == nil then
                return "S"
            end
            local late = now - cue
            if late <= 0 then
                return "S"
            end
            local gcd = practice_gcd_duration(self, ctx) or 1.5
            if late <= gcd / 3 then
                return "A"
            elseif late <= (2 * gcd) / 3 then
                return "B"
            elseif late <= gcd then
                return "C"
            end
            return "D"
        end,
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

-- The live guide inputs (the class's own gathered state): the ctx builder
-- reads them when the session state is absent, so the scenario decides on the
-- SAME numbers the next-action guide shows. pcall-guarded: a half-loaded class
-- module never throws out of a ctx build (the rogue and the hunter use the
-- same discipline). The reused table lives on the module table (the module
-- sits at the Lua 5.1 local ceiling: no file-local room).
ST.PALADIN.practice_live_inputs = {}

function ST.PALADIN.practice_live_gather(self)
    if type(ST.PALADIN.gather_guide_inputs) ~= "function" then
        return nil
    end
    local ok, result = pcall(ST.PALADIN.gather_guide_inputs, self,
        ST.PALADIN.practice_live_inputs)
    if not ok or type(result) ~= "table" then
        return nil
    end
    return result
end

-- The gathered names the practice contract reads as FLAT ctx fields (the guide's
-- own names). Everything else the gather produced rides along in ctx.resources
-- (the rogue's rule: a field nobody listed still reaches the class's grader).
ST.PALADIN.practice_gathered_flat = {
    "swing_remaining", "gcd_remaining", "speed", "seal", "fcfs_mode",
    "cs_known", "twist_window", "reaction", "cs_delay_max", "gcd_before_swing",
    "mana_pct", "creature_type", "melee_count", "target_count",
    "target_health_pct", "fight_remaining_pct", "how_cast_seconds",
    "holy_power_stacks", "holy_power_set_known", "sod_dual_seal_active",
    "sod_t2_known", "sod_naxx_known", "sod_libram_known", "am_rune_known",
    "sunlight_remaining", "templar_stack_remaining", "templar_wrath_remaining",
    "mana_exorcism_threshold", "mana_consecration_threshold",
    "soc_remaining_seconds", "som_remaining_seconds",
}

-- The gathered guide inputs into the ctx (the live path).
function ST.PALADIN.practice_apply_gathered(ctx, gathered)
    for key, value in pairs(gathered) do
        if type(key) == "string" then
            local kind = type(value)
            if kind == "number" or kind == "boolean" or kind == "string" then
                ctx.resources[key] = value
            end
        end
    end
    local flat = ST.PALADIN.practice_gathered_flat
    for i = 1, #flat do
        local name = flat[i]
        local value = gathered[name]
        if value ~= nil then
            ctx[name] = value
        end
    end
    -- The GCD length: the guide's own name for it.
    if type(gathered.G) == "number" then
        ctx.gcd_duration = gathered.G
    end
    -- The cooldown rows: the engine's own naming (<key>_remaining).
    for key, value in pairs(gathered) do
        if type(key) == "string" and type(value) == "number" then
            local base = key:match("^(.-)_remaining_cd$") or key:match("^(.-)_remaining$")
            if base and base ~= "" then
                ctx.cooldowns[base] = value
            end
        end
    end
    return ctx
end

-- An adapter for the shipped practice sim: build the context the step and the
-- drills read, from the sim's own state. The shared engine may use it or
-- build its own context; either way the class-side contract is the same.
--
-- TWO SHAPES, ONE BUILDER:
--   * the SIM shape (the twist sim): the session state carries the swing clock,
--     the GCD clock, the cooldowns and the active seals. The sim-shaped fields
--     are copied verbatim.
--   * the LIVE shape (the real client): the session state carries NO sim clock
--     (the addon object has none), so the sim-shaped copy answers nothing and
--     the scenario had no timing to decide on - every step was UNKNOWN. The
--     builder therefore falls back to the class's OWN gathered guide inputs (the
--     same state the next-action guide reads: swing_remaining, gcd_remaining,
--     the seal, the FCFS mode and the cooldowns), so the scenario decides on
--     the live numbers.
--
-- The fallback runs only when the sim shape did not answer the timing, so the
-- twist sim keeps its own path bit-identically.
function ST.PALADIN.practice_context(self, now, last_action)
    local state = practice_state(self)
    local ctx = {
        now = now,
        last_action = last_action,
        resources = {},
        cooldowns = {},
    }
    -- The pull moment travels with the ctx: the prepull drill reads it from here.
    practice_apply_pull_clock(ctx, now)
    if type(state) == "table" then
        if type(state.swing_ends_at) == "number" and type(now) == "number" then
            ctx.swing_remaining = math.max(0, state.swing_ends_at - now)
        end
        if type(state.gcd_expires) == "number" and type(now) == "number" then
            ctx.gcd_remaining = math.max(0, state.gcd_expires - now)
        end
        if type(state.effective_speed) == "number" then
            ctx.speed = state.effective_speed
        end
        if type(state.effective_gcd) == "number" then
            ctx.gcd_duration = state.effective_gcd
        end
        local expires = {
            cs = state.cs_cooldown_expires,
            judge = state.judge_cooldown_expires,
            cons = state.consec_cooldown_expires,
        }
        for key, value in pairs(expires) do
            if type(value) == "number" and type(now) == "number" then
                ctx.cooldowns[key] = math.max(0, value - now)
            end
        end
        if type(state.active_seals) == "table" then
            local seals = state.active_seals
            if seals.command == true or seals.soc == true then
                ctx.seal = "soc"
            elseif seals.blood == true or seals.sob == true then
                ctx.seal = "sob"
            else
                ctx.seal = "none"
            end
        end
    end
    -- The live fallback: the sim shape answered no timing, so the class's own
    -- gathered guide inputs answer it (the live client). Unknown stays unknown:
    -- a gather that fails or answers nothing leaves the ctx empty and the
    -- decision nil (the engine grades "unknown", never a wrong action).
    if ctx.swing_remaining == nil and ctx.gcd_remaining == nil then
        local gathered = ST.PALADIN.practice_live_gather(self)
        if gathered then
            ST.PALADIN.practice_apply_gathered(ctx, gathered)
        end
    end
    return ctx
end

--=========================================================================================
-- Shared-layer seams (class-isolation 2026-10-21)
--=========================================================================================
-- The paladin's OWN rotation-text provider (C5: moved out of rotationtext.lua,
-- because a shared module must not define a class's function). Practice-aware,
-- like the archive's source: while a practice session runs the simulation's own
-- determine_rotation is used (it honours a locked rotation preset); otherwise
-- the live swing speed and GCD - the exact values the guide feeds its engine
-- (gather_guide_inputs: speed = self.mainhand.speed, G =
-- self:get_spell_gcd_duration()) - run through the shared threshold function
-- st.nextaction.calculate_rotation. The rotation tables live in the pure engine
-- and are never duplicated here.
-- >>> rotationtext provider >>>
ST.PALADIN.get_rotation_key = function(self)
    local pui = st.practice_ui
    if pui and pui.is_active and pui.is_active() and st.practice
        and st.practice.determine_rotation and pui.sim then
        return st.practice.determine_rotation(pui.sim)
    end
    local na = st.nextaction
    if not (na and na.calculate_rotation) then
        return nil
    end
    local d = self.mainhand
    return na.calculate_rotation((d and d.speed) or 0, self:get_spell_gcd_duration())
end
-- <<< rotationtext provider <<<

-- The paladin's OWN design-mode elements (C6: moved out of designmode.lua). The
-- seal-icon row and the twist success text ride on the mainhand bar by default
-- and move with its overlay; a design-mode drag detaches them (their own save
-- path writes detached offsets + re-anchors through the class apply seam),
-- double-click reset re-attaches. Other classes never build these frames; their
-- elements are not registered at all, so the shared overlay refresh never sees
-- them.
-- >>> design elements >>>
if st.designmode and type(st.designmode.register_element) == "function" then
    st.designmode.register_element({
        key = "seal_icons",
        title = "Seal icons",
        get_frame = function()
            if not ST.get_visuals_frame then
                return nil
            end
            local vf = ST:get_visuals_frame("mainhand")
            local set = vf and vf.seal_icons
            return set and set.frame or nil
        end,
        save = function(x, y)
            ST.PALADIN.save_seal_icons_position(ST, x, y)
        end,
        reset = function()
            ST.PALADIN.reset_seal_icons_position(ST)
        end,
        -- Archive descriptor shape (editmode.lua ELEMENTS "icons"): the enable path
        -- the card rows and the settings page the future cards lane consumes. Keys
        -- are the live current-tree option names.
        enable_path = "seal_icons_enabled",
        card = { "seal_icons_enabled" },
        settings = { page = "class" },
    })
    st.designmode.register_element({
        key = "success_text",
        title = "Successful twist text",
        get_frame = function()
            if not ST.get_visuals_frame then
                return nil
            end
            local vf = ST:get_visuals_frame("mainhand")
            return vf and vf.twist_text or nil
        end,
        save = function(x, y)
            ST.PALADIN.save_twist_text_position(ST, x, y)
        end,
        reset = function()
            ST.PALADIN.reset_twist_text_position(ST)
        end,
        -- Archive descriptor shape (editmode.lua ELEMENTS "success").
        enable_path = "twist_success_text_enabled",
        card = {
            "twist_success_text_enabled", "twist_success_text_color",
            "twist_success_text_size", "twist_success_text_duration",
        },
        settings = { page = "class" },
    })
end
-- <<< design elements <<<

-- The shared practice UI's provider for the sim path (the paladin's practice is
-- the twist sim, not a drill): only the paladin's OWN session seams. The shared
-- layer asks the ACTIVE class for them, so a paladin session keeps mirroring its
-- seal state and restores its auras on stop.
ST.PALADIN.practice_panel = {
    progress = {
        mode = "paladin_twist",
        scenario = "paladin_rotation",
        drills = { "paladin_twist", "paladin_aw_combo" },
    },
    session = {
        sync_sim = function(self) ST.PALADIN.practice_sync(self) end,
        clear_sim = function(self) ST.PALADIN.on_aura_change(self) end,
    },
}

if st.debug then st.utils.print_msg('-- Parsed classes/paladin.lua module correctly (twist)') end

end

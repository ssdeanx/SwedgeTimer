--=========================================================================================
-- Module for Warrior-specific behaviours: the on-next-attack colours and Blood Surge glow,
-- plus (mirroring the shaman/hunter/druid/paladin ports of the reference) the warrior
-- tracker set - the Shield Block bar, the Slam cast bar, the Overpower dodge-proc flash,
-- the Rampage upkeep badge and the Deep Wounds / Sunder Armor / Rend / Thunder Clap /
-- (reference SuperSwingTimer_ClassMods.lua warrior block 1689-3333). The pure tracker
-- maths lives next to the widgets (this class has no separate pure module).
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
st.class_loaders = st.class_loaders or {}
st.class_loaders["WARRIOR"] = function()
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
-- Spell data
--=========================================================================================
-- Heroic Strike, all ranks across the classic families (vanilla -> BCC -> WotLK).
-- The lookup table keeps every rank id; get_family_spell_id picks the highest id
-- that exists on the running client (the current rank). 29707 / 30324 are the
-- TBC ranks 9-10 (wowsims/tbc-new fury + arms APLs cast 29707 tag1;
-- wowhead.com/tbc/spell=30324 is Heroic Strike): the table missed them, so a
-- TBC client resolved rank 8 (25286) for its cost/queue reads. Mortal Strike
-- ranks live in ms_ids below, never here.
local hs_ids = get_tab({
    47450, 47449, 30324, 29707, 25286, 11567, 11566,
    11565, 11564, 1608, 285, 284, 78
})

-- Cleave, all ranks.
local cleave_ids = get_tab({
    47520, 47519, 25231, 20569, 11609, 11608, 7369, 845
})

-- Cached current-rank ids, resolved once on first use.
local hs_current_id
local cleave_current_id
-- The Slam rank: the guide slot, the guide's cooldown read and the Slam cast bar's
-- fallback duration all read the ONE cached rank (the three-valued resolver, see
-- resolve_rank), so a Slam cast never walks the rank table a second time. Declared
-- here, with the other cached ranks, because the cast bar's fallback reads it.
local slam_current_id

-- Localized-name retry cadence on a mute client (up here with the other
-- R1 name-set state: the SUCCEEDED / FAILED_QUIET clear matchers below read
-- it, and a later local would be invisible to them).
local WARRIOR_NAMES_RETRY_S = 5

-- Blood Surge proc aura: 46916 is the WotLK talent proc, 413399 is the SoD
-- Blood Surge rune aura (both SoD APLs gate Slam 11605 on auraIsActive 413399;
-- the provider matched only 46916, so rule 3 never fired on SoD).
local bloodsurge_ids = get_tab({ 46916, 413399 })

-- Overpower dodge-window length (reference State.lua:26). Declared up here
-- with the other aura ids: on_aura_change is defined before the
-- tracker-constant block below, and a later local would be invisible to it
-- (it would read a nil global instead).
local WARRIOR_OVERPOWER_PROC_WINDOW = 5.0

-- Unmatched-payload notice threshold (M3, the paladin pattern at
-- classes/paladin.lua:564): a sustained run of DODGE payloads no matcher reads
-- is the addon blind on an evolving CLEU contract, not a non-proc miss.
local WARRIOR_PAYLOAD_NOTICE_AT = 3

-- Rampage (TBC fury "stack to 5 then upkeep"): the buff id the aura scan matches,
-- the literal English fallback (the same convention as the Shield Block scan) and
-- the stack cap. Declared up here with the other aura ids: on_aura_change is
-- defined before the tracker-constant block below, and a later local would be
-- invisible to it (it would read a nil global instead).
local WARRIOR_RAMPAGE_SPELL_ID = 29838
local WARRIOR_RAMPAGE_NAME = "Rampage"
local WARRIOR_RAMPAGE_MAX_STACKS = 5

-- Battle Shout uptime (discover #9): rank ids carried with the other aura ids
-- (on_aura_change below reads them before the tracker-constant block is defined).
-- A remembered id is a rumor, so every rank here cites the client-family audit
-- page that confirmed it (bench/buildout_warrior_2026-10-17.md): 6673 / 5242 /
-- 6192 (classic + Forever pages), 11551 / 25289 / 2048 / 47436 (wotlk-classic
-- pages, up to rank 9). A rank id the running client does not know simply never
-- matches; the literal English fallback below still covers the buff, and a
-- localized client matches by the ids it does know (the Rampage scan's pattern).
local WARRIOR_BATTLE_SHOUT_IDS = get_tab({
    6673, 5242, 6192, 11551, 25289, 2048, 47436
})
local WARRIOR_BATTLE_SHOUT_NAME = "Battle Shout"
-- The fallback covers auras the client reports without an expiry (2 min is the
-- audit pages' classic/WotLK duration; the Forever client lists 3 min, so a
-- client that answers always wins and this only covers an omission).
local WARRIOR_BATTLE_SHOUT_FALLBACK = 120

-- Commanding Shout coverage (competitor-gaps W2): the greater shout that covers
-- Battle Shout, so the Battle Shout badge must suppress while it is live. Rank
-- ids UNCONFIRMED (in-client to confirm - the literal English fallback below
-- covers the buff on any client, and a localized client matches by the ids it
-- knows, the Rampage scan's pattern). A rank id the running client does not
-- know simply never matches.
local WARRIOR_COMMANDING_SHOUT_IDS = get_tab({
    469, 3411, 11752, 12964, 12965, 47440
}) -- UNCONFIRMED
local WARRIOR_COMMANDING_SHOUT_NAME = "Commanding Shout"
-- Same audit-duration shadow convention as Battle Shout above (both shouts run
-- 2 min on the classic line).
local WARRIOR_COMMANDING_SHOUT_FALLBACK = 120

-- Bloodthirst, all ranks across the classic families (the TBC fury core):
-- rank 1 first, the WotLK max last; get_family_spell_id picks the highest
-- id that exists on the running client (the current rank). Ranks from other
-- expansions are simply absent from the client's spell data, so carrying the
-- full set is harmless. (Whirlwind carries its own table below.)
local bt_ids = get_tab({
    30335, 23894, 23893, 23892, 23884, 23883, 23882, 23881
})
local ww_ids = get_tab({
    1680
})
-- Whirlwind resolves through the base id 1680 on every family (wowsims sims
-- register WW as SpellID 1680 on classic, tbc-new and forever alike; cost 25
-- and the 10 s cooldown are rank-flat, so the base id reads correctly).
-- Seven ids were evicted here 2026-10-19, each verified on wowhead to be
-- another spell: 11584 / 11585 are Overpower ranks 3-4 (classic overpower.go
-- registers 11585; tbc-new fury/arms and SoD APLs cast 11585), 25208 is Rend
-- (moved to rend_ids below), 47436 is Battle Shout (already in the shout
-- table), 6794 is Tiger's Fury, 6795 is Growl, and 47435 is the creature spell
-- "Scrape Corrosive Spit". Higher WW ranks are unverified: re-add by id only
-- with a sim or client citation, never by adjacency.

-- Cached current-rank ids for the TBC guide reads, resolved once like hs/cleave.
local bt_current_id
local ww_current_id

-- The TBC fury guide reads (Bloodthirst/Whirlwind cooldowns+costs, the HS dump
-- floor, the HS-cancel cue) exist only on the TBC family (st.family from compat.lua, which loads
-- before every class module). Every other family feeds nil for those inputs, and
-- the new engine rules require known readings, so non-TBC clients keep the
-- legacy behaviour exactly; Retail stays as inert as before (its invisibility
-- still comes from the swing state in nextaction_ui.should_show, never from a
-- family gate here - the Forever client must keep working).
local is_tbc_guide = st.family == "TBC"

-- The Wrath guide reads (BT/WW cooldowns+costs with the 50-rage floor, the arms
-- upkeep/cooldown readers, the SoD-independent Sudden Death / Taste for Blood
-- aura flags) exist only on the WRATH family. Every other family feeds nil for
-- the Wrath-only inputs (the engine rules require known readings, so they stay
-- inert there); TBC/Era/Retail behaviour is untouched (their inputs never
-- change shape or value - the new fields simply read nil there too).
local is_wrath_guide = st.family == "WRATH"

-- The Era fury guide reads (same BT/WW cooldowns+costs, the Era HS dump floor,
-- the Era reserve window and the Era Execute-spam flag) exist only on the ERA
-- family. BT/WW are vanilla spells that exist on Era and resolve through the
-- same rank tables above. Every non-core family feeds nil for all of these, so
-- the engine rules stay inert there exactly like before; Retail/Forever
-- inertness is unchanged (swing state decides visibility, never a family gate
-- here). SoD shares the ERA token and is detected per client via the rune
-- knowledge probe below (Raging Blow / Consumed by Rage through
-- api.is_spell_known): SoD feeds floor 60, the Era window, spam, the Sudden
-- Death bypass and the Raging Blow reader; Era-base feeds floor 30 and no SoD
-- flag.
local is_era_guide = st.family == "ERA"

-- The Forever guide reads (st.family == "FOREVER", the WoW Forever / Camelot
-- 1.60.x client): Bloodthrill arms the Overpower window through the aura scan
-- below (a second OP source alongside the classic dodge window, which can never
-- arm on Mainline-code clients), and Victory Rush feeds the engine's
-- victory_rush input when the family + knowledge + usable probe answers
-- (UNCONFIRMED id below). Every other family feeds nil for both, so the engine
-- stays byte-identical there; Retail keeps its swing-decided invisibility.
local is_forever_guide = st.family == "FOREVER"

-- Name-vs-id rule (operator 2026-10-19; bench/lessons.md): TBC Anniversary
-- resolves by NAME, never bare id; every other family (Classic Era included)
-- resolves by id. Branch on st.family, never a version string. Names resolve
-- once per id through the client's own GetSpellInfo and are cached (a rank's
-- name never changes); cold spell data retries on the next call. Queries go
-- through compat's api.get_spell_query (inline family branch as fallback so
-- the module never depends on load order); a nil name falls back to the id so
-- a cold book degrades to today's behavior instead of a nil query.
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
    if st.family ~= "TBC" then
        return spell_id
    end
    local name = resolve_spell_name(spell_id)
    if type(api.get_spell_query) == "function" then
        return api.get_spell_query(name, spell_id) or spell_id
    end
    return name or spell_id
end

-- Known-spell probe through the family-correct query (the rogue
-- api.is_spell_known(rogue_query(...)) discipline): the English name on TBC,
-- the numeric id elsewhere; a cold TBC book probes the id fallback, never nil.
local function is_spell_known_query(spell_id)
    return api.is_spell_known(spell_query(spell_id)) == true
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

-- Localized-name box for the TBC Blood Surge aura match below.
local bloodsurge_name_box = {}

-- Era fury tuning (sourced ground truth for the 1.15.9 fury priority:
-- Bloodthirst on CD > Whirlwind when BT is > 1.5 s out > Heroic Strike dump
-- only with rage to spare (>= 40: classic dps_no_reck.apl.json gates HS
-- 25286 and Cleave 20569 on currentRage >= 40) and 2-3 s until next BT/WW,
-- Execute spam below 20 %, Overpower if specced). The window is the midpoint
-- of the 2-3 s ground-truth buffer; in-game tuning may move it to 2 or 3.
local ERA_HS_FLOOR = 40
local ERA_CORE_RESERVE_WINDOW = 2.5

-- Mortal Strike ranks for the arms/fury spec probe (Mortal Strike known =
-- arms): the Taste for Blood affected-spells list (wowhead.com/wotlk/
-- spell=56638). Deliberately a separate table: these ids must never enter
-- hs_ids above (29707 / 30324 are Heroic Strike ranks, not Mortal Strike).
-- Only api.is_spell_known reads this
-- table (knowledge, not spell-data existence), so rank gaps across families
-- simply answer false.
local ms_ids = { 12294, 21551, 21552, 21553, 25248, 30330, 47485, 47486 }

-- Bladestorm (63784, wowhead.com/wotlk/spell=63784): the arms cooldown slot.
-- Single rank; knowledge-gated (untalented clients never prompt it).
local bladestorm_id = 63784

-- SoD runes (SoD detection: ERA family + one of these known via
-- api.is_spell_known): Raging Blow 402911 (wowhead.com/classic/
-- spell=402911, the SoD rune filler) and Consumed by Rage 425440
-- (wowhead.com/classic/spell=425440, the rage->60 pool buff).
local raging_blow_id = 402911
local consumed_by_rage_id = 425440

-- Hamstring rage-dump weave (sim-cited ids only): 7373 (Era hidden line at
-- rage > 80, Forever hamstring-weave line) and 18499 (TBC weave with Improved
-- Hamstring 20500, wowsims/tbc-new fury APL). Consumed by rule W on
-- Era-base (threshold 80 live); the Era set names the slot seventh while
-- TBC/SoD/Forever wait on their number/toggle (filed with the options lane,
-- see the desk journal). The knowledge probe below is the engine side:
-- post_init-frozen
-- like the spec/rune probes, exposed through the gather for the slot lane
-- (the same shape as the TBC cleave readers, which stay in the gather with
-- no TBC slot). A cast matcher is deliberately NOT carried: no in-tree
-- reader exists for one, and wire-not-strip removes reader-less hooks.
local hamstring_ids = get_tab({ 7373, 18499 })

-- Hamstring known (the weave filler is trainable): walks hamstring_ids
-- through api.is_spell_known, frozen once at post_init like the arms/rune
-- probes. A client without the spell answers false on every id.
local function is_hamstring_known()
    for id in pairs(hamstring_ids) do
        if is_spell_known_query(id) then
            return true
        end
    end
    return false
end

-- SoD follow-ups (warrior-rotfix journal 2026-10-19 re-verification): the Rend
-- rune 412507 (Blood Frenzy, operator-confirmed in-client 2026-10-19) and the
-- OP stance-dance gate aura 426969 (UNCONFIRMED on SoD - in-client to
-- confirm); a wrong id degrades to no-match, never to a wrong prompt. The
-- rune rides a frozen knowledge probe (never widens the ERA+runes SoD
-- detection below); the aura rides the on_aura_change walk (no extra client
-- reads, no name fallback - its English name is unknown).
local sod_rend_rune_id = 412507 -- CONFIRMED (Blood Frenzy, operator in-client 2026-10-19)
local sod_stance_aura_id = 426969 -- UNCONFIRMED

-- Warrior stance auras (the sim's own stance registration, fetched 2026-10-19):
-- wowsims/classic sim/warrior/stances.go registers the stance AURAs with
-- SpellID 2457 (Battle Stance), 71 (Defensive Stance) and 2458 (Berserker
-- Stance); the tbc-new fury APL switches with 2457 (Battle) and 2458
-- (Berserker), and the tbc-new arms APL casts 2457 before Overpower. The
-- client's stance buffs carry those ids, so the stance is read from the
-- existing aura walk (no extra client read, no form index - the per-family
-- form map stays UNCONFIRMED). Aggressive Stance has no cited id here, so a
-- player standing in it reads as an unknown stance, which withholds nothing.
-- One local for both tables (the chunk's local budget is tight: Lua 5.1 caps
-- a function at 200 locals).
local WARRIOR_STANCES = {
    ids = {
        [2457] = "battle",
        [71] = "defensive",
        [2458] = "berserker",
        [412513] = "gladiator",
    },
    names = {
        ["Battle Stance"] = "battle",
        ["Defensive Stance"] = "defensive",
        ["Berserker Stance"] = "berserker",
        ["Gladiator Stance"] = "gladiator",
    },
}

-- The utility spine: the APL's utility rows (the stance upkeep, the cooldown pops and
-- the racial) - the single source of truth for their ids, their family gates, their
-- labels and their citations. The rotation table's second block is generated from it,
-- and the gather reads the live state through it.
--
-- PER LINE:
--   id          the spell id the id-resolving clients (Era, SoD, Forever, WotLK) use.
--   ids         the per-family form, for the two rows whose id splits by family
--               (Battle Shout: 25289 on Era/Forever, 2048 on TBC; Death Wish: 12328
--               on Era/Forever, 12292 on TBC - 12292 is Sweeping Strikes on the
--               Forever client, so the id MUST be family-gated).
--   families    the families whose APL carries the line as a SPELL ROW (the family
--               gate: a line the running family does not carry is never read and
--               never asked for; the SoD branch rides the ERA token).
--   label       the spell's English name (the panel's button label).
--   spell_name  the client's English name for the id (the TBC client resolves by
--               NAME, the others by id - bench/lessons.md).
--   reason      the short caption the practice surface shows.
--   buff        the buff the row maintains (nil = the row has no buff of its own).
--   rage_max    the APL row's own rage ceiling (nil = no rage gate).
--   live        the line's READ exists and the line can be evaluated.
--   engine      the frozen engine has an arm that can ask for the line.
--   source      the APL file and the row's index, plus the sim citation.
--   needs       what the line still waits for (the reads that landed are named here).
--
-- The family gates stand: a line is never asked for on a client that lacks it, and
-- the TBC client resolves by name (the name is the primary key there).
--
-- THE THREE APL GATES THE ROWS CARRY, AND WHAT EACH ONE STILL NEEDS
-- (bench/warrior_utility_residuals_2026-10-20.md §3 has the full table):
--
--   1. THE EXECUTE PHASE - WIRED. The TBC and Forever APLs gate their Heroic
--      Strike row on NOT being inside the execute phase (tbc-new fury.apl.json
--      [18]; forever arms.apl.json [27]); the Era APL's row explicitly allows the
--      dump inside the phase (classic dps_no_reck.apl.json [18]). The read EXISTS
--      (the target's health fraction against the class's execute percentage - the
--      same read the Execute rule uses), so the provider arms the gate on those
--      two families only (inputs.execute_phase_dump_gate) and the engine's rule 7
--      withholds the dump inside the phase.
--
--   2. THE TARGET COUNT - NOT MODELLED, and it needs a read that does not exist:
--      the sim's `numberTargets` (the number of enemies in the player's vicinity),
--      which gates the Sweeping Strikes / Whirlwind / Cleave / Heroic Strike /
--      Sunder rows on the TBC, Era, Forever and WotLK APLs (the rows with the
--      clause are listed in the bench file). The client-side candidate is a
--      hostile-unit scan (the nameplate / target units, filtered for hostility and
--      melee range); NO compat wrapper supplies it today, and the other classes'
--      target_count inputs are skeletons. Until that read lands, those rows are
--      asked for on their cooldown + buff alone - a documented deviation.
--
--   3. THE BLOODLUST ALIGNMENT - NOT MODELLED, and it needs a read that does not
--      exist plus a new option: the TBC APL aligns its Death Wish / Recklessness /
--      Sweeping Strikes rows to the raid's Bloodlust with `multipleCdUsages`
--      against the base spell 2825 and the "Bloodlust time" variable (tbc-new
--      fury.apl.json [8], [9], [10]; the group's opener is [1]). The read is the
--      raid's Bloodlust PLAN - the fight-time offset at which the raid's Bloodlust
--      lands - which is a user setting, not a fact the client can read, so it
--      needs a new option (option_tables.lua / config_presets.lua, out of this
--      lane's scope) on top of the fight clock.
local WARRIOR_UTILITY = {
    battle_stance = {
        id = 2457,
        families = { "ERA", "TBC", "FOREVER" },
        sod = true,
        label = "Battle Stance", spell_name = "Battle Stance",
        reason = "Battle Stance (the Overpower stance)",
        stance = "battle", role = "weave",
        live = true, engine = true,
        source = "the SoD branch of the ERA family: wowsims/sod "
            .. "ui/warrior/apls/phase_6_dw.apl.json [1] and [5] (Battle Stance 2457) "
            .. "- the Era APL has no Battle Stance row (it only ever reaches "
            .. "Berserker Stance at [24]); wowsims/tbc-new "
            .. "ui/specs/warrior/dps/apls/fury.apl.json [16] the `Overpower "
            .. "Weaving` group (wait -> 2457 -> 11585 -> 2458) and the same group in "
            .. "arms.apl.json [17]; wowsims/forever ui/specs/warrior/dps/apls/"
            .. "arms.apl.json [13] and [25] (2457); the id is the same on every "
            .. "family (wowsims/classic sim/warrior/stances.go:86 - the Battle "
            .. "Stance aura; wowsims/sod sim/warrior/stances.go:89)",
        needs = "the READ exists: the stance aura walk (ST.WARRIOR.on_aura_change) "
            .. "resolves the player's own stance into self.warrior_stance through "
            .. "WARRIOR_STANCES.ids (2457 -> battle), and the utility spine feeds it "
            .. "as inputs.utility_stance on every family the APL carries the row. "
            .. "The RULE is the engine's W0 (the Overpower weave's first step: the "
            .. "sims register Overpower with a Battle-stance requirement)",
    },
    berserker_stance = {
        id = 2458,
        families = { "ERA", "TBC", "WRATH", "FOREVER" },
        sod = true,
        label = "Berserker Stance", spell_name = "Berserker Stance",
        reason = "Berserker Stance (the damage stance)",
        stance = "berserker", role = "upkeep",
        live = true, engine = true,
        source = "wowsims/classic ui/warrior/apls/dps_no_reck.apl.json [24] (2458, "
            .. "the IF NOT the 2458 aura is active row - the Era APL's only stance "
            .. "row); wowsims/sod ui/warrior/apls/phase_6_dw.apl.json [2], [3] and "
            .. "[6] (2458); wowsims/tbc-new ui/specs/warrior/dps/apls/fury.apl.json "
            .. "[16] the `Overpower Weaving` group (wait -> 2457 -> 11585 -> 2458), "
            .. "[17] and the two hidden upkeep rows [23] and [24] (2458), and the "
            .. "same in arms.apl.json [17] and [23]; wowsims/forever "
            .. "ui/specs/warrior/dps/apls/arms.apl.json [19] (2458) and "
            .. "fury.apl.json [20], [26] and [27]; wowsims/wotlk "
            .. "ui/warrior/apls/fury.apl.json [16] (2458); the id is the same on "
            .. "every family (wowsims/classic sim/warrior/stances.go:124 - the "
            .. "Berserker Stance aura; wowsims/sod sim/warrior/stances.go:127)",
        needs = "the READ exists: the same stance aura walk resolves 2458 -> "
            .. "berserker. The RULE is the engine's M (the stance upkeep row: the "
            .. "APL casts the stance when its aura is NOT active, and the sims "
            .. "register every stance spell with `ExtraCastCondition: "
            .. "!warrior.StanceMatches(stance)`)",
    },
    gladiator_stance = {
        id = 412513,
        families = { "ERA" },
        sod = true,
        label = "Gladiator Stance", spell_name = "Gladiator Stance",
        reason = "Gladiator Stance (the SoD rune stance)",
        stance = "gladiator", role = "none",
        live = true, engine = false,
        source = "the SoD branch of the ERA family: wowsims/sod "
            .. "ui/warrior/apls/phase_6_dw.apl.json [0] and [4] (412513, the SoD "
            .. "rune stance - the APL's TOP row); the id and the name: wowsims/sod "
            .. "proto/warrior.proto:131 (RuneGladiatorStance = 412513) and "
            .. "wowsims/sod sim/warrior/stances.go:212 (the Gladiator Stance aura's "
            .. "ActionID = proto.WarriorRune_RuneGladiatorStance); no other fetched "
            .. "APL carries it. NOT in the gap analysis's missing-line table "
            .. "(bench/rotation_gap_vs_apl_2026-10-20.md section 1.3) although its "
            .. "APL listing has it - added here because it is the same utility "
            .. "layer the operator named",
        needs = "the READ exists: 412513 is in WARRIOR_STANCES.ids, so the stance "
            .. "walk resolves the rune stance like the other three. The RULE is "
            .. "still missing, and the missing read is now NAMED. The SoD APL gates "
            .. "its Gladiator Stance rows [0] and [4] on auraIsKnown(457817) and "
            .. "auraIsKnown(464241) (wowsims/sod ui/warrior/apls/phase_6_dw.apl.json "
            .. "[0] and [4]), and in the sim auraIsKnown answers 'the aura is "
            .. "REGISTERED on the unit' (wowsims/sod sim/core/apl_values_aura.go:24 "
            .. "- value.aura.Get() ~= nil). Those two auras are registered by the "
            .. "SoD T1 DAMAGE SET bonus, NOT by a rune: 464241 is the 2pc "
            .. "'Tactician' and 457816 / 457817 are the 6pc 'Battle Forecast' / "
            .. "'Berserker Forecast' (wowsims/sod sim/warrior/"
            .. "item_sets_pve_phase_4.go:78-215 - applyT1Damage2PBonus and "
            .. "applyT1Damage6PBonus; wowsims/sod ui/core/proto_utils/"
            .. "action_id.ts:765-766 names 457816 / 457817 'Battle Forecast' / "
            .. "'Berserker Forecast'). The SoD RUNE ids are the proto's "
            .. "(proto/warrior.proto:131 - RuneGladiatorStance = 412513). So the "
            .. "gate is an EQUIPMENT fact - 'the player wears the six pieces of the "
            .. "T1 damage set' - and the client's aura list cannot answer it (it "
            .. "reports the ACTIVE auras only). THE MISSING READ: the "
            .. "equipped-item / set-membership read ('are the six pieces of the SoD "
            .. "T1 warrior damage set equipped'), buildable from the existing "
            .. "api.is_item_equipped wrapper (compat.lua:1121) once the six item "
            .. "ids are cited - they are in no fetched source yet (the sim's item "
            .. "DB is not in the corpus, and the client's own GetItemSetInfo(setID) "
            .. "- wow-ui-source classic_era Interface/AddOns/"
            .. "Blizzard_APIDocumentationGenerated/ItemDocumentation.lua:645 - "
            .. "wants a set id the addon has no read for). The row's OTHER clause "
            .. "IS client-readable: the 'Berserker Forecast' aura 457817 exists in "
            .. "the 1.15.9 client's spell table (wow.export Spell.csv - 'Increases "
            .. "Critical Strike chance by $s1%.') and the class's HELPFUL aura walk "
            .. "(api.UnitAura, compat.lua:457) reports an ACTIVE aura's id and its "
            .. "expiration, so auraRemainingTime(457817) <= 3 s can be read while "
            .. "the buff is up. BOTH halves are needed: the sim's 'the aura is "
            .. "known but not active' case (remaining time 0, so the row still "
            .. "fires) is only reproducible once the set ownership is known. Until "
            .. "then the engine leaves the row alone (engine = false) rather than "
            .. "guess the set",
    },
    bloodrage = {
        id = 2687,
        families = { "ERA", "TBC", "WRATH", "FOREVER" },
        sod = true,
        label = "Bloodrage", spell_name = "Bloodrage",
        reason = "Bloodrage (the rage cooldown)",
        rage_max = 90,
        live = true, engine = true,
        source = "ALL FIVE families: wowsims/classic ui/warrior/apls/"
            .. "dps_no_reck.apl.json [21] (2687, the IF currentRage < 90 row); "
            .. "wowsims/sod ui/warrior/apls/phase_6_dw.apl.json [7] (2687); "
            .. "wowsims/tbc-new ui/specs/warrior/dps/apls/fury.apl.json [20] "
            .. "(2687) and arms.apl.json [21]; wowsims/forever "
            .. "ui/specs/warrior/dps/apls/arms.apl.json [28] (2687) and "
            .. "fury.apl.json [23]; wowsims/wotlk ui/warrior/apls/arms.apl.json [1] "
            .. "and fury.apl.json [1] (2687); the id is the same on all five "
            .. "(wowsims/classic sim/warrior/bloodrage.go:10 and wowsims/tbc-new "
            .. "sim/warrior/bloodrage.go:11 - core.ActionID{SpellID: 2687}). The "
            .. "operator's 'Blood Rage is a WotLK ability' is a DIFFERENT spell (the "
            .. "blood-magic damage shield), which no fetched APL casts",
        needs = "the READ exists: api.GetSpellCooldown(2687) (compat.lua:229) for "
            .. "the cooldown, plus the rage pool the APL's own IF currentRage < 90 "
            .. "condition reads (api.UnitPower(\"player\", 2), compat.lua:349). The "
            .. "RULE is the engine's utility spine (the U1 / U2 rows)",
    },
    battle_shout = {
        ids = { ERA = 25289, TBC = 2048, FOREVER = 25289 },
        families = { "ERA", "TBC", "FOREVER" },
        sod = false,
        label = "Battle Shout", spell_name = "Battle Shout",
        reason = "Battle Shout (the attack-power buff)",
        buff = "battle_shout",
        live = true, engine = true,
        source = "wowsims/classic ui/warrior/apls/dps_no_reck.apl.json [23] (25289 "
            .. "r6, the IF NOT the 25289 r6 aura is active row); wowsims/tbc-new "
            .. "ui/specs/warrior/dps/apls/fury.apl.json [22] (2048, rank 8) and "
            .. "arms.apl.json [22]; wowsims/forever ui/specs/warrior/dps/apls/"
            .. "arms.apl.json [29] (25289) and fury.apl.json [25] (25289). The id "
            .. "splits by family AND by rank: 25289 is Battle Shout rank 7 on the "
            .. "TBC client and rank 6 on the Era / Forever clients, 2048 is rank 8 "
            .. "(wowsims/tbc-new sim/warrior/spell_data_auto_gen.go, the BattleShout "
            .. "table: rank 7 = 25289, rank 8 = 2048; wowsims/forever "
            .. "sim/warrior/spell_data_auto_gen.go:152 - BattleShout: 6673, 5242, "
            .. "6192, 11549, 11550, 11551, 25289). The TBC client resolves by NAME, "
            .. "so the line carries 'Battle Shout' as its TBC key. The SoD branch "
            .. "has no Battle Shout row (its [12] is Death Wish 12328)",
        needs = "the READ exists: the Battle Shout aura walk (ST.WARRIOR.on_aura_"
            .. "change) stamps self.warrior_battle_shout_expires through "
            .. "WARRIOR_BATTLE_SHOUT_IDS and the literal English name fallback, so "
            .. "the utility spine knows the buff is up. The RULE is the engine's "
            .. "utility spine (the U1 / U2 rows)",
    },
    recklessness = {
        id = 1719,
        families = { "ERA", "TBC", "FOREVER" },
        sod = true,
        label = "Recklessness", spell_name = "Recklessness",
        reason = "Recklessness (the burst cooldown)",
        buff = "recklessness",
        live = true, engine = true,
        source = "the SoD branch of the ERA family: wowsims/sod "
            .. "ui/warrior/apls/phase_6_dw.apl.json [14] (1719); wowsims/tbc-new "
            .. "ui/specs/warrior/dps/apls/fury.apl.json [9] (1719) and "
            .. "arms.apl.json [9]; wowsims/forever ui/specs/warrior/dps/apls/"
            .. "arms.apl.json [11] (1719) and fury.apl.json [11]; the id is the "
            .. "same on every family (wowsims/forever "
            .. "sim/warrior/spell_data_auto_gen.go:248 - Recklessness: 1719). The "
            .. "Era build does NOT take the talent: its two rows are IF false ([4]) "
            .. "and a hidden remainingTime <= 15s row ([5]) in wowsims/classic "
            .. "ui/warrior/apls/dps_no_reck.apl.json, so on the ERA family this is "
            .. "the SoD branch's line. The WotLK pre-pull casts 1719 too, but that "
            .. "is a pre-pull row and lives in ST.WARRIOR.PRACTICE_PREPULLS",
        needs = "the READ exists: api.GetSpellCooldown(1719) (compat.lua:229) for "
            .. "the cooldown, and the buff's own aura through the player's HELPFUL "
            .. "aura walk (the literal English name - no buff id is cited in any "
            .. "fetched sim source, and a guessed id could match the wrong aura). "
            .. "The RULE is the engine's utility spine (the U1 / U2 rows)",
    },
    death_wish = {
        ids = { ERA = 12328, TBC = 12292, FOREVER = 12328 },
        families = { "ERA", "TBC", "FOREVER" },
        sod = true,
        label = "Death Wish", spell_name = "Death Wish",
        reason = "Death Wish (the damage cooldown)",
        buff = "death_wish",
        live = true, engine = true,
        source = "wowsims/classic ui/warrior/apls/dps_no_reck.apl.json [3] (12328); "
            .. "wowsims/sod ui/warrior/apls/phase_6_dw.apl.json [12] (12328); "
            .. "wowsims/tbc-new ui/specs/warrior/dps/apls/fury.apl.json [8] (12292) "
            .. "and arms.apl.json [8]; wowsims/forever ui/specs/warrior/dps/apls/"
            .. "arms.apl.json [10] (12328) and fury.apl.json [10]. The id splits by "
            .. "family: 12328 on the Era / SoD / Forever clients (wowsims/classic "
            .. "sim/warrior/talents.go:407, wowsims/sod sim/warrior/talents.go:415, "
            .. "wowsims/forever sim/warrior/spell_data_auto_gen.go:174 - DeathWish: "
            .. "12328) and 12292 on the TBC client (wowsims/tbc-new "
            .. "sim/warrior/talents_arms.go:314). 12292 is DEATH WISH on TBC and "
            .. "SWEEPING STRIKES on the Forever client "
            .. "(wowsims/forever sim/warrior/spell_data_auto_gen.go:262 - "
            .. "SweepingStrikes: 12292), so the id MUST be family-gated. The WotLK "
            .. "arms APL has no Death Wish row; the WotLK fury PRE-PULL casts 12292 "
            .. "at -1.5s, so that row lives in ST.WARRIOR.PRACTICE_PREPULLS",
        needs = "the READ exists: api.GetSpellCooldown(id) (compat.lua:229) with "
            .. "the family-correct query (api.get_spell_query, compat.lua:1544 - the "
            .. "TBC client resolves by name, the others by id), plus the buff's own "
            .. "aura through the player's HELPFUL aura walk (the literal English "
            .. "name - no buff id is cited in any fetched sim source). The RULE is "
            .. "the engine's utility spine (the U1 / U2 rows)",
    },
    sweeping_strikes = {
        id = 12723,
        families = { "TBC", "FOREVER" },
        sod = false,
        label = "Sweeping Strikes", spell_name = "Sweeping Strikes",
        reason = "Sweeping Strikes (the multi-target cooldown)",
        buff = "sweeping_strikes",
        live = true, engine = true,
        source = "wowsims/tbc-new ui/specs/warrior/dps/apls/fury.apl.json [10] "
            .. "(12723) and arms.apl.json [10]; wowsims/forever "
            .. "ui/specs/warrior/dps/apls/arms.apl.json [12] (12723) and "
            .. "fury.apl.json [12]; the cast id is 12723 on both clients "
            .. "(wowsims/tbc-new sim/warrior/talents_fury.go:160 and wowsims/forever "
            .. "sim/warrior/talents_arms.go:418 - the latter notes the normalized "
            .. "attack's real id is 26654). The client's own ladder lists the rank "
            .. "as 12292 on Forever (wowsims/forever "
            .. "sim/warrior/spell_data_auto_gen.go:262), and 12292 is DEATH WISH on "
            .. "TBC, so the id is family-gated here. The WotLK client has the spell "
            .. "but no fetched WotLK APL casts it",
        needs = "the READ exists: api.GetSpellCooldown(12723) (compat.lua:229) - "
            .. "the TBC client resolves it by name - plus the buff's own aura "
            .. "through the player's HELPFUL aura walk (the literal English name). "
            .. "The RULE is the engine's utility spine (the U1 / U2 rows)",
    },
    thunder_clap = {
        id = 47502,
        families = { "WRATH" },
        specs = { arms = true },
        sod = false,
        label = "Thunder Clap", spell_name = "Thunder Clap",
        reason = "Thunder Clap (the area stun)",
        live = true, engine = true,
        source = "wowsims/wotlk ui/warrior/apls/arms.apl.json [11] (47502, the arms "
            .. "APL's Thunder Clap row - the fury APL has none); the id: "
            .. "wowsims/wotlk sim/warrior/thunder_clap.go:16 "
            .. "(core.ActionID{SpellID: 47502}); no other fetched APL casts it (the "
            .. "classic-line clients carry the spell, but no fetched classic-line "
            .. "APL row casts it)",
        needs = "the READ exists: api.GetSpellCooldown(47502) (compat.lua:229). The "
            .. "RULE is the engine's utility spine (the U1 / U2 rows)",
    },
    shattering_throw = {
        id = 64382,
        families = { "WRATH" },
        specs = { fury = true },
        sod = false,
        label = "Shattering Throw", spell_name = "Shattering Throw",
        reason = "Shattering Throw (the ranged armour break)",
        live = true, engine = true,
        source = "wowsims/wotlk ui/warrior/apls/fury.apl.json [9] (64382); the id: "
            .. "wowsims/wotlk sim/warrior/shattering_throw.go:15 "
            .. "(core.ActionID{SpellID: 64382}); the arms APL has no Shattering Throw "
            .. "row and no other fetched APL casts it",
        needs = "the READ exists: api.GetSpellCooldown(64382) (compat.lua:229). The "
            .. "RULE is the engine's utility spine (the U1 / U2 rows)",
    },
    heroic_throw = {
        id = 57755,
        families = { "WRATH" },
        specs = { fury = true },
        sod = false,
        label = "Heroic Throw", spell_name = "Heroic Throw",
        reason = "Heroic Throw (the ranged filler)",
        live = true, engine = true,
        source = "wowsims/wotlk ui/warrior/apls/fury.apl.json [15] (57755); the id: "
            .. "wowsims/wotlk sim/warrior/heroic_throw.go:11 "
            .. "(core.ActionID{SpellID: 57755}); the arms APL has no Heroic Throw row "
            .. "and no other fetched APL casts it",
        needs = "the READ exists: api.GetSpellCooldown(57755) (compat.lua:229). The "
            .. "RULE is the engine's utility spine (the U1 / U2 rows)",
    },
    berserker_rage = {
        id = 18499,
        families = { "ERA", "TBC", "FOREVER" },
        sod = false,
        label = "Berserker Rage", spell_name = "Berserker Rage",
        reason = "Berserker Rage (the rage cooldown)",
        live = true, engine = true,
        source = "wowsims/classic ui/warrior/apls/dps_no_reck.apl.json [22] (18499, "
            .. "the hidden row); wowsims/tbc-new ui/specs/warrior/dps/apls/"
            .. "fury.apl.json [21] (18499 - the arms APL has no Berserker Rage row); "
            .. "wowsims/forever ui/specs/warrior/dps/apls/fury.apl.json [24] (18499) "
            .. "and the arms / fury PRE-PULL (18499 at -4.5s). The id is BERSERKER "
            .. "RAGE, not Hamstring (wowsims/classic sim/warrior/berserker_rage.go:"
            .. "14 and wowsims/forever sim/warrior/spell_data_auto_gen.go:155 - "
            .. "BerserkerRage: 18499); 20500 is the Improved Hamstring talent buff "
            .. "the TBC APL only tests for, and the Hamstring ids are 7373 (Era) and "
            .. "25212 (TBC)",
        needs = "the READ exists: api.GetSpellCooldown(18499) (compat.lua:229). The "
            .. "RULE is the engine's utility spine (the U1 / U2 rows)",
    },
    blood_fury = {
        id = 20572,
        families = { "ERA" },
        sod = false,
        label = "Blood Fury", spell_name = "Blood Fury",
        reason = "Blood Fury (the Orc racial)",
        buff = "blood_fury",
        live = true, engine = true,
        source = "the Era build of the ERA family: wowsims/classic "
            .. "ui/warrior/apls/dps_no_reck.apl.json [7] (20572, a TOP-LEVEL "
            .. "priority row - the only family whose APL carries the racial as a "
            .. "spell row; the SoD branch's APL carries no Blood Fury row - its "
            .. "pre-pull casts 2458, 24427 and 2687 only). The id: wowsims/classic "
            .. "sim/core/racials.go:78 (// Blood Fury, ActionID{SpellID: 20572}); the "
            .. "TBC client carries the same racial at rank 2 - 33697 "
            .. "(wowsims/tbc-new sim/core/racials.go:196) - but the TBC and Forever "
            .. "APLs carry the racial only inside the `CD: Racials` group "
            .. "(wowsims/tbc-new ui/specs/warrior/dps/apls/fury.apl.json [7] - "
            .. "33697, and wowsims/forever ui/specs/warrior/dps/apls/arms.apl.json "
            .. "[9] - 20572 and 20554), which is the sim's pop-everything harness "
            .. "layer, not a rotation decision (bench/rotation_gap_vs_apl_2026-10-20.md "
            .. "section 1.4) - so those ids are deliberately NOT carried here. The "
            .. "Troll racial that shares the group (Berserking 26296 on TBC, 20554 "
            .. "on Forever) never appears as a spell row and is correctly absent",
        needs = "the READ exists: api.GetSpellCooldown(20572) (compat.lua:229) plus "
            .. "the racial's knowledge probe (api.is_spell_known, compat.lua:208 - "
            .. "a non-Orc never has the spell, so the line stays dark) and the "
            .. "buff's own aura through the player's HELPFUL aura walk (the literal "
            .. "English name). The RULE is the engine's utility spine (the U1 / U2 "
            .. "rows)",
    },
    -- The keys table (one local for the whole utility spine): the rotation table's
    -- second block, in the table's own order.
    keys = {
        "battle_stance", "berserker_stance", "gladiator_stance", "bloodrage",
        "battle_shout", "recklessness", "death_wish", "sweeping_strikes",
        "thunder_clap", "shattering_throw", "heroic_throw", "berserker_rage",
        "blood_fury",
    },

    -- The orders table (one local for the whole utility spine): the APL's utility
    -- rows per family, in the APL's own priority order, split into the rows the APL
    -- puts ABOVE the core rotation (high) and the rows it puts BELOW it (low). The
    -- Era APL's rows all come after the filler; the TBC / Forever rows close their
    -- lists; the WotLK arms / fury rows sit in their own damage region.
    --
    --   ERA     dps_no_reck.apl.json: [3] Death Wish, [7] Blood Fury, [21] Bloodrage,
    --           [22] Berserker Rage, [23] Battle Shout - all below the filler.
    --   SOD     phase_6_dw.apl.json: [12] Death Wish, [14] Recklessness - above the core.
    --   TBC     fury.apl.json / arms.apl.json: [8] Death Wish, [9] Recklessness,
    --           [10] Sweeping Strikes above the core; [20] Bloodrage, [21] Berserker
    --           Rage, [22] Battle Shout below it.
    --   FOREVER arms.apl.json / fury.apl.json: [10] Death Wish, [11] Recklessness,
    --           [12] Sweeping Strikes above the core; [28] Bloodrage, [29] Battle
    --           Shout below it.
    --   WRATH   arms.apl.json / fury.apl.json: [1] Bloodrage above the core;
    --           [11] Thunder Clap (arms), [9] Shattering Throw and [15] Heroic Throw
    --           (fury) in the damage region.
    orders = {
        ERA = {
            high = {},
            low = { "death_wish", "blood_fury", "bloodrage", "berserker_rage", "battle_shout" },
        },
        SOD = {
            high = { "death_wish", "recklessness" },
            low = {},
        },
        TBC = {
            high = { "death_wish", "recklessness", "sweeping_strikes" },
            low = { "bloodrage", "berserker_rage", "battle_shout" },
        },
        FOREVER = {
            high = { "death_wish", "recklessness", "sweeping_strikes" },
            low = { "bloodrage", "battle_shout" },
        },
        WRATH = {
            high = { "bloodrage" },
            low = { "thunder_clap", "shattering_throw", "heroic_throw" },
        },
    },

    -- The wanted_stance table (one local for the whole utility spine): the APL's
    -- stance upkeep row per family - the stance the row wants when its aura is not
    -- active. The Era / SoD / TBC / WotLK rows want Berserker Stance (the damage
    -- stance); the Forever arms row wants Battle Stance (its Stance Dance toggle
    -- ships off, so the player sits in Battle Stance and Overpower needs that aura).
    wanted_stance = {
        ERA = "berserker",
        SOD = "berserker",
        TBC = "berserker",
        FOREVER = "battle",
        WRATH = "berserker",
    },

    -- The weave_families table (one local for the whole utility spine): the families
    -- whose APL weaves into Battle Stance for the Overpower (the sims register
    -- Overpower with a Battle-stance requirement): the SoD strictSequence
    -- ([2457, 11585] behind the gate aura 426969), the TBC Overpower Weaving group
    -- (wait -> 2457 -> 11585 -> 2458) and the WotLK strictSequence
    -- ([2457, 7384, 2458]).
    weave_families = { SOD = true, TBC = true, WRATH = true },

    -- The buff_names table (one local for the whole utility spine): the utility rows'
    -- buffs (the literal English names the client shows). The ids are not carried:
    -- the buff's aura id is cited in no fetched sim source, and a guessed id could
    -- match the wrong aura. The name match is the house's own fallback (the Battle
    -- Shout and Commanding Shout reads use it), and the cooldown gate is the real
    -- protection: every one of these buffs is shorter than its cooldown, so a buff
    -- that is up always has its cooldown running.
    buff_names = {
        ["Recklessness"] = "recklessness",
        ["Death Wish"] = "death_wish",
        ["Sweeping Strikes"] = "sweeping_strikes",
        ["Blood Fury"] = "blood_fury",
    },
    -- The guide slots (one per utility row): the icon is the row's own spell id
    -- (the TBC family uses the TBC client's ids - the Battle Shout rank 8 and the
    -- Death Wish rank 1; the Era / Forever clients use the older ranks). The swipe
    -- follows the cooldown the gather feeds (<key>_remaining and <key>_duration);
    -- the stance rows carry no swipe (the stance spells share a 1 s cooldown the
    -- client's own read never reports - the gather filters it as the GCD echo).
    -- The swipe_duration is the display fallback only: a real cooldown always
    -- carries the client-reported length.
    slots = {
        battle_stance = { key = "battle_stance", spell_id = 2457, swipe_duration = 1.5 },
        berserker_stance = { key = "berserker_stance", spell_id = 2458, swipe_duration = 1.5 },
        bloodrage = { key = "bloodrage", spell_id = 2687, cooldown_key = "bloodrage",
            swipe_duration = 1.5 },
        battle_shout_era = { key = "battle_shout", spell_id = 25289,
            cooldown_key = "battle_shout", swipe_duration = 1.5 },
        battle_shout_tbc = { key = "battle_shout", spell_id = 2048,
            cooldown_key = "battle_shout", swipe_duration = 1.5 },
        recklessness = { key = "recklessness", spell_id = 1719,
            cooldown_key = "recklessness", swipe_duration = 1.5 },
        death_wish_era = { key = "death_wish", spell_id = 12328,
            cooldown_key = "death_wish", swipe_duration = 1.5 },
        death_wish_tbc = { key = "death_wish", spell_id = 12292,
            cooldown_key = "death_wish", swipe_duration = 1.5 },
        sweeping_strikes = { key = "sweeping_strikes", spell_id = 12723,
            cooldown_key = "sweeping_strikes", swipe_duration = 1.5 },
        thunder_clap = { key = "thunder_clap", spell_id = 47502,
            cooldown_key = "thunder_clap", swipe_duration = 1.5 },
        shattering_throw = { key = "shattering_throw", spell_id = 64382,
            cooldown_key = "shattering_throw", swipe_duration = 1.5 },
        heroic_throw = { key = "heroic_throw", spell_id = 57755,
            cooldown_key = "heroic_throw", swipe_duration = 1.5 },
        berserker_rage = { key = "berserker_rage", spell_id = 18499,
            cooldown_key = "berserker_rage", swipe_duration = 1.5 },
        blood_fury = { key = "blood_fury", spell_id = 20572,
            cooldown_key = "blood_fury", swipe_duration = 1.5 },
    },
}

-- The utility rows in the rotation table's second block, in the table's own order.

-- The APL's utility rows per family, in the APL's own priority order, split into the
-- rows the APL puts ABOVE the core rotation (high) and the rows it puts BELOW it
-- (low). The Era APL's rows all come after the filler; the TBC / Forever rows close
-- their lists; the WotLK arms / fury rows sit in their own damage region.
--
--   ERA     dps_no_reck.apl.json: [3] Death Wish, [7] Blood Fury, [21] Bloodrage,
--           [22] Berserker Rage, [23] Battle Shout - all below the filler.
--   SOD     phase_6_dw.apl.json: [12] Death Wish, [14] Recklessness - above the core.
--   TBC     fury.apl.json / arms.apl.json: [8] Death Wish, [9] Recklessness,
--           [10] Sweeping Strikes above the core; [20] Bloodrage, [21] Berserker
--           Rage, [22] Battle Shout below it.
--   FOREVER arms.apl.json / fury.apl.json: [10] Death Wish, [11] Recklessness,
--           [12] Sweeping Strikes above the core; [28] Bloodrage, [29] Battle
--           Shout below it.
--   WRATH   arms.apl.json / fury.apl.json: [1] Bloodrage above the core;
--           [11] Thunder Clap (arms), [9] Shattering Throw and [15] Heroic Throw
--           (fury) in the damage region.

-- The APL's stance upkeep row per family: the stance the row wants when its aura is
-- not active. The Era / SoD / TBC / WotLK rows want Berserker Stance (the damage
-- stance); the Forever arms row wants Battle Stance (its Stance Dance toggle ships
-- off, so the player sits in Battle Stance and Overpower needs that aura).

-- The families whose APL weaves into Battle Stance for the Overpower (the sims
-- register Overpower with a Battle-stance requirement): the SoD strictSequence
-- ([2457, 11585] behind the gate aura 426969), the TBC Overpower Weaving group
-- (wait -> 2457 -> 11585 -> 2458) and the WotLK strictSequence ([2457, 7384, 2458]).

-- The utility rows' buffs (the literal English names the client shows). The ids are
-- not carried: the buff's aura id is cited in no fetched sim source, and a guessed id
-- could match the wrong aura. The name match is the house's own fallback (the Battle
-- Shout and Commanding Shout reads use it), and the cooldown gate is the real
-- protection: every one of these buffs is shorter than its cooldown, so a buff that
-- is up always has its cooldown running.

-- Sudden Death proc aura (the Execute enabler): 52437 on Wrath
-- (wowhead.com/wotlk/spell=52437, 10 s, Execute at any health) and 440495
-- plus the literal English fallback on SoD (in-game to confirm which SoD aura
-- id fires there).
local WARRIOR_SD_AURA_IDS = { 52437, 440495 }
local WARRIOR_SD_AURA_NAME = "Sudden Death"

-- Taste for Blood proc aura (the arms Overpower enabler without a dodge):
-- 60503 (the 9 s proc from wowhead.com/wotlk/spell=56638) plus the literal
-- English fallback. Rend-tick inference is deferred (no tick state yet).
local WARRIOR_TFB_AURA_ID = 60503
local WARRIOR_TFB_AURA_NAME = "Taste for Blood"

-- Bloodthrill (Forever arms Overpower enabler without a dodge, forever_beta.md:
-- beta guides name the talent but no spell/aura id - UNCONFIRMED, in-game to
-- confirm). No numeric id is carried on purpose: a guessed id could arm the
-- window on the wrong aura. The scan matches the literal aura name below, gated
-- on the FOREVER family, so every other family ignores the name entirely.
local WARRIOR_BLOODTHRILL_AURA_NAME = "Bloodthrill"

-- Victory Rush (Forever execute-phase cue, forever_beta.md: beta guides list
-- the spell but no id - 34428 is the WotLK Victory Rush id, carried here
-- UNCONFIRMED for the Forever client, in-game to confirm). The name fallback
-- mirrors the Bloodthrill aura-name match above: a wrong id degrades to the
-- name read instead of disabling the cue. The gather requires family +
-- (id-known or name-known) + usable, so a wrong id fails safe to nil on a
-- client that knows neither (never prompts).
local WARRIOR_VICTORY_RUSH_SPELL_ID = 34428 -- UNCONFIRMED on Forever
local WARRIOR_VICTORY_RUSH_NAME = "Victory Rush" -- UNCONFIRMED on Forever

-- Spec probe (Mortal Strike known = arms): walks ms_ids through
-- api.is_spell_known (knowledge, never spell-data existence). Cheap probe
-- chain; the slot/flag freeze happens once in post_init (see
-- resolve_guide_slots), so a mid-session respec needs /reload to re-pick the
-- slot set.
local function is_arms_spec()
    for i = 1, #ms_ids do
        if is_spell_known_query(ms_ids[i]) then
            return true
        end
    end
    return false
end

-- SoD probe (ERA family only): either SoD rune known. Same freeze rule as the
-- spec probe: a rune (un)learned mid-session needs /reload.
local function is_sod_client()
    if not is_era_guide then
        return false
    end
    return is_spell_known_query(raging_blow_id)
        or is_spell_known_query(consumed_by_rage_id)
end

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

-- Compares the current rage against the queued ability cost and recolours only when the
-- state actually changes: UNIT_POWER_FREQUENT fires several times a second.
local function update_rage_state(self, spell_id)
    local costs = spell_id and api.GetSpellPowerCost(spell_query(spell_id))
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

function ST.WARRIOR.on_rage_update(self)
    if self.hs_queued then
        hs_current_id = resolve_rank(hs_ids, hs_current_id)
        return update_rage_state(self, hs_current_id or nil)
    end
    if self.cleave_queued then
        cleave_current_id = resolve_rank(cleave_ids, cleave_current_id)
        return update_rage_state(self, cleave_current_id or nil)
    end
    -- Nothing queued: clear a stale "insufficient rage" colour left by the last fight.
    if self.insufficient_rage then
        self.insufficient_rage = false
        self:set_bar_color("mainhand")
    end
end

-- Queued-melee localized names (R1): the client's own names for every Heroic
-- Strike / Cleave rank, resolved once through GetSpellInfo and retried at the
-- shared throttled cadence while the client's spell data is not up yet (the
-- debuff-name discipline). Anniversary (UNCONFIRMED) may send the spell name
-- where classic sends the numeric id in the event payloads below (the
-- interrupt clear and the SPELL_MISSED dodge branch). The per-ability sets
-- serve the per-ability clear arms; the interrupt
-- path keeps the combined read (it clears both flags together).
local WARRIOR_HS_NAME = "Heroic Strike"
local WARRIOR_CLEAVE_NAME = "Cleave"
local hs_localized_names
local cleave_localized_names
local hs_cleave_names_retry_at = 0

local function resolve_hs_cleave_names(now)
    if (hs_localized_names == nil or cleave_localized_names == nil)
        and now >= hs_cleave_names_retry_at then
        local hs_names, cleave_names = {}, {}
        for id in pairs(hs_ids) do
            local name = api.GetSpellInfo(id)
            if name then
                hs_names[name] = true
            end
        end
        for id in pairs(cleave_ids) do
            local name = api.GetSpellInfo(id)
            if name then
                cleave_names[name] = true
            end
        end
        if next(hs_names) ~= nil then
            hs_localized_names = hs_names
        end
        if next(cleave_names) ~= nil then
            cleave_localized_names = cleave_names
        end
        if next(hs_names) == nil and next(cleave_names) == nil then
            hs_cleave_names_retry_at = now + WARRIOR_NAMES_RETRY_S
        end
    end
end

local function is_warrior_queued_melee_proc_name(name, now)
    if name == WARRIOR_HS_NAME or name == WARRIOR_CLEAVE_NAME then
        return true
    end
    resolve_hs_cleave_names(now)
    return (hs_localized_names ~= nil and hs_localized_names[name] == true)
        or (cleave_localized_names ~= nil and cleave_localized_names[name] == true)
end

-- Per-ability clear matchers for the SUCCEEDED / FAILED_QUIET hooks below: id
-- primary, name secondary on every family (the hunter R1 discipline). The id
-- table reads first (Era payloads, unchanged); a name token - the spell id
-- slot or the guid slot carrying the localized name on a name-carrying
-- Anniversary payload - matches the literal English fallback, then the
-- client's own localized names for that ability's ranks. A cold spell cache
-- reads nil and retries next event (rare event-path calls, never per-frame).
-- Nil-safe: anything unmatchable reads false, never a guess.
local function is_warrior_hs_token(token, now)
    if token == nil then
        return false
    end
    if hs_ids[token] ~= nil then
        return true
    end
    if type(token) ~= "string" then
        return false
    end
    if token == WARRIOR_HS_NAME then
        return true
    end
    resolve_hs_cleave_names(now)
    return hs_localized_names ~= nil and hs_localized_names[token] == true
end

local function is_warrior_cleave_token(token, now)
    if token == nil then
        return false
    end
    if cleave_ids[token] ~= nil then
        return true
    end
    if type(token) ~= "string" then
        return false
    end
    if token == WARRIOR_CLEAVE_NAME then
        return true
    end
    resolve_hs_cleave_names(now)
    return cleave_localized_names ~= nil and cleave_localized_names[token] == true
end

function ST.WARRIOR.on_spellcast_failed_quiet(self, unit_id, cast_guid, spell_id)
    -- R1 name-carrying payloads (Anniversary: the name rides the guid slot when
    -- the id is absent) clear through the client's own localized names, exactly
    -- like the INTERRUPTED/FAILED path; id-carrying payloads clear exactly as
    -- before. The two arms stay separate: each clears only its own ability.
    local token = spell_id
    if token == nil then
        token = cast_guid
    end
    local now = api.get_time()
    if is_warrior_hs_token(token, now) then
        self.hs_queued = false
        self:set_bar_color("mainhand")
        return
    end
    if is_warrior_cleave_token(token, now) then
        self.cleave_queued = false
        self:set_bar_color("mainhand")
        return
    end
end

function ST.WARRIOR.on_spellcast_succeeded(self, unit_target, cast_guid, spell_id)
    -- print(unit_target)
    -- print(spell_id)
    -- A landed Overpower closes the dodge window so the flash reflects current usability
    -- (reference SuperSwingTimer.lua:1415-1421). The matcher only runs while the window
    -- is open, so an ordinary fight costs nothing here.
    if self.warrior_overpower_proc_until ~= nil
        and self.WARRIOR.is_overpower_cast(spell_id, cast_guid, api.get_time()) then
        self.warrior_overpower_proc_until = nil
    end
    -- Same R1 name-carrying rule as the quiet path above: the landed queued
    -- ability clears its tint whether the client reports the id or the name.
    local token = spell_id
    if token == nil then
        token = cast_guid
    end
    local now = api.get_time()
    if is_warrior_hs_token(token, now) then
        self.hs_queued = false
        self:set_bar_color("mainhand")
        return
    end
    if is_warrior_cleave_token(token, now) then
        self.cleave_queued = false
        self:set_bar_color("mainhand")
        return
    end
end

function ST.WARRIOR.on_current_spell_cast_changed(self, is_cancelled)
    -- This function detects when the player queues up a heroic strike or cleave
    -- and sets relevant flags for the func to set bar colors.
    local db = self:get_class_table()
    if type(db) ~= "table" then
        -- PROPER: no profile means no user preferences to honor (the active class
        -- always has one in-game); the queue flags stay cleared and the bar keeps
        -- its default colour instead of throwing.
        return
    end

    -- Only run this logic if special on-next-attack colors are enabled in the warrior settings.
    if (not db.enable_hs_color) and not (db.enable_cleave_color) then
        return
    end

    if db.enable_hs_color then
        for spell_id in pairs(hs_ids) do
            -- Name-vs-id rule: the query is the localized name on TBC.
            local query = spell_query(spell_id)
            local result = query ~= nil and api.IsCurrentSpell(query)
            if result then
                -- print('matched HS id: '..tostring(spell_id))
                self.hs_queued = true
                self.cleave_queued = false
                self:set_bar_color("mainhand")
                return
            end
        end
        self.hs_queued = false
    end

    -- No HS queued. Only probe Cleave when its colour is enabled, so the flag can never
    -- stay stale while the option is off.
    if not db.enable_cleave_color then
        self.cleave_queued = false
        return
    end
    for spell_id in pairs(cleave_ids) do
        -- Name-vs-id rule: the query is the localized name on TBC.
        local query = spell_query(spell_id)
        local result = query ~= nil and api.IsCurrentSpell(query)
        if result then
            -- print('matched cleave id: '..tostring(spell_id))
            self.cleave_queued = true
            self:set_bar_color("mainhand")
            return
        end
    end
    self.cleave_queued = false
end

function ST.WARRIOR.on_aura_change(self)
    self.has_bloodsurge = false
    -- Sudden Death / Taste for Blood ride the same walk (no extra client
    -- reads): presence only, like has_bloodsurge. The gather maps them into
    -- the engine's sudden_death / tfb inputs (true or nil). Bloodthrill rides
    -- along too (Forever only, UNCONFIRMED name): it arms the Overpower window
    -- below instead of feeding the engine, so no new input is needed for it.
    local sd_found, tfb_found, bloodthrill_found = false, false, false
    -- SoD OP stance-dance gate aura (426969 UNCONFIRMED): id-only match, no
    -- literal-name fallback (no English name is known for it).
    local sod_stance_found = false
    -- The current stance (the sim's stance auras, see the id table above): the
    -- first stance aura in the walk wins (the stances are exclusive). An
    -- unknown stance (no stance aura on the client, or Aggressive Stance,
    -- which has no cited id) reads as nil - the stance gates then withhold
    -- nothing, exactly like before.
    local stance = nil
    -- The Rampage upkeep state rides the same walk (no extra client reads): the
    -- first matching aura's stack count, clamped to the 5-stack cap, and its
    -- expiration stamp for the badge's refresh window. A count the client omits
    -- still means one stack (the shaman's max(1, count) handling).
    local rampage_stacks, rampage_expires = nil, nil
    -- Battle Shout uptime rides the same walk (no extra client reads): the
    -- later-expiring matching aura stamp - or, when the client omits the expiry,
    -- now + the audit fallback duration - feeds the badge's countdown. Cleared
    -- whenever the buff is absent; never cleared in on_combat_exit (the buff
    -- persists between fights).
    local battle_shout_expires = nil
    -- W2 Commanding Shout coverage rides the same walk (no extra client reads):
    -- the later-expiring matching stamp, or the audit-duration shadow when the
    -- client omits the expiry. Cleared whenever the buff is absent; never
    -- cleared in on_combat_exit (persists between fights, like Battle Shout).
    local commanding_expires = nil
    -- The utility spine's buffs (the rows that maintain a buff of their own). The
    -- table lives on the class object (no per-walk allocation): every key is false
    -- when the walk starts and true while the matching buff is up. The Battle
    -- Shout row rides the id table + the literal English name (the house's own
    -- fallback); the other rows ride their literal English name only - no buff id
    -- is cited in any fetched sim source, and a guessed id could match the wrong
    -- aura. The table is nil until the first walk, so a session that never walked
    -- reads every buff as unknown (unknown hides: the line never prompts).
    local utility_buffs = self.warrior_utility_buffs
    if type(utility_buffs) ~= "table" then
        utility_buffs = {}
        self.warrior_utility_buffs = utility_buffs
    end
    utility_buffs.battle_shout = false
    utility_buffs.recklessness = false
    utility_buffs.death_wish = false
    utility_buffs.sweeping_strikes = false
    utility_buffs.blood_fury = false
    -- Iterate all player auras (1..40, no early break: a secret entry degrades to
    -- absent in the wrapper, and breaking there would hide every proc above a
    -- restricted row; nil is simply no match at this index).
    local i = 1
    while i <= 40 do
        -- "HELPFUL" explicitly: the Retail wrapper forwards the filter into
        -- C_UnitAuras.GetAuraDataByIndex, where it is a typed enum argument.
        local name, _, count, _, _, expiration, _, _, _, spell_id = api.UnitAura("player", i, "HELPFUL")
        if name ~= nil then
            if aura_matches(bloodsurge_ids, bloodsurge_name_box, spell_id, name) then
                self.has_bloodsurge = true
            end
            if spell_id == WARRIOR_SD_AURA_IDS[1] or spell_id == WARRIOR_SD_AURA_IDS[2]
                or name == WARRIOR_SD_AURA_NAME then
                sd_found = true
            end
            if spell_id == WARRIOR_TFB_AURA_ID or name == WARRIOR_TFB_AURA_NAME then
                tfb_found = true
            end
            if spell_id == sod_stance_aura_id then
                sod_stance_found = true
            end
            if stance == nil then
                local stance_key = (type(spell_id) == "number")
                    and WARRIOR_STANCES.ids[spell_id] or nil
                if stance_key == nil and type(name) == "string" then
                    stance_key = WARRIOR_STANCES.names[name]
                end
                if stance_key ~= nil then
                    stance = stance_key
                end
            end
            if name == WARRIOR_BLOODTHRILL_AURA_NAME then
                bloodthrill_found = true
            end
            -- The utility spine's other buffs (the literal English names; the ids
            -- are not cited in any fetched sim source).
            local utility_buff = WARRIOR_UTILITY.buff_names[name]
            if utility_buff then
                utility_buffs[utility_buff] = true
            end
            if rampage_stacks == nil
                and (spell_id == WARRIOR_RAMPAGE_SPELL_ID or name == WARRIOR_RAMPAGE_NAME) then
                local n = tonumber(count) or 1
                if n < 1 then
                    n = 1
                elseif n > WARRIOR_RAMPAGE_MAX_STACKS then
                    n = WARRIOR_RAMPAGE_MAX_STACKS
                end
                rampage_stacks = n
                if type(expiration) == "number" and expiration > 0 then
                    rampage_expires = expiration
                end
            end
            -- Battle Shout: rank ids first, then the literal English fallback (the
            -- Rampage scan's convention). The later-expiring stamp wins; a client
            -- that reports no expiry still arms the audit-duration shadow.
            if (spell_id and WARRIOR_BATTLE_SHOUT_IDS[spell_id])
                or name == WARRIOR_BATTLE_SHOUT_NAME then
                utility_buffs.battle_shout = true
                local bs_expires
                if type(expiration) == "number" and expiration > 0 then
                    bs_expires = expiration
                else
                    bs_expires = api.get_time() + WARRIOR_BATTLE_SHOUT_FALLBACK
                end
                if battle_shout_expires == nil or bs_expires > battle_shout_expires then
                    battle_shout_expires = bs_expires
                end
            end
            -- W2 Commanding Shout: rank ids first, then the literal English fallback
            -- (the Battle Shout scan's convention). The later-expiring stamp wins; a
            -- client that reports no expiry still arms the audit-duration shadow.
            if (spell_id and WARRIOR_COMMANDING_SHOUT_IDS[spell_id])
                or name == WARRIOR_COMMANDING_SHOUT_NAME then
                local cmd_expires
                if type(expiration) == "number" and expiration > 0 then
                    cmd_expires = expiration
                else
                    cmd_expires = api.get_time() + WARRIOR_COMMANDING_SHOUT_FALLBACK
                end
                if commanding_expires == nil or cmd_expires > commanding_expires then
                    commanding_expires = cmd_expires
                end
            end
        end
        i = i + 1
    end
    self.warrior_rampage_stacks = rampage_stacks
    self.warrior_rampage_expires = rampage_expires
    self.warrior_battle_shout_expires = battle_shout_expires
    self.warrior_commanding_expires = commanding_expires
    self.has_sudden_death = sd_found
    self.has_tfb = tfb_found
    self.has_sod_stance_aura = sod_stance_found
    -- The current stance (nil = unknown). Written on every walk, so a stance
    -- change (a UNIT_AURA event) refreshes it and a vanished aura clears it.
    self.warrior_stance = stance
    -- Forever Bloodthrill (UNCONFIRMED name): a second Overpower source. The
    -- classic dodge window can never arm on Mainline-code clients (main.lua
    -- never registers the combat log there), so on Forever this aura is the
    -- only OP source; every other family ignores the name entirely (the gate
    -- above). The window lapses on its own once the aura is gone, exactly
    -- like the dodge window.
    if is_forever_guide and bloodthrill_found then
        self.warrior_overpower_proc_until = api.get_time() + WARRIOR_OVERPOWER_PROC_WINDOW
    end
    self.WARRIOR.process_bloodsurge(self)
end

function ST.WARRIOR.glow_start(self)
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
    -- if thickness == 0 then
    --     thickness = 1
    -- end
    LCG.PixelGlow_Start(frame,
        {self:convert_color(db_class.bloodsurge_glow_color)},
        db_class.bloodsurge_glow_nlines,
        db_class.bloodsurge_glow_freq,
        db_class.bloodsurge_glow_line_length,
        thickness,
        0,
        0,
        false
    )
end

function ST.WARRIOR.process_bloodsurge(self)
    local db = self:get_class_table()
    if type(db) ~= "table" then
        -- PROPER: freeze rather than transition — without preferences a glow
        -- change would be invented, and the swing bar itself still renders.
        return
    end
    local should_glow = (self.has_bloodsurge and db.use_bloodsurge_glow) and true or false
    -- LibCustomGlow pools its glow frames: re-starting (or stopping twice) on every aura
    -- event churns the pool and can double-release the frame, so only transition when
    -- the state actually changes.
    if should_glow == self.bloodsurge_glow_active then
        return
    end
    self.bloodsurge_glow_active = should_glow
    if should_glow then
        self.WARRIOR.glow_start(self)
    else
        self.WARRIOR.glow_stop(self)
    end
end

function ST.WARRIOR.glow_stop(self)
    local frame = self:get_bar_frame("mainhand")
    if frame == nil then
        -- PROPER: an unbuilt hand owns no glow to stop; stopping nothing is exact.
        return
    end
    LCG.PixelGlow_Stop(frame)
end

function ST.WARRIOR.post_init(self)
    -- Starts settled so the first process_bloodsurge does not emit a spurious stop on
    -- an already-idle frame.
    self.bloodsurge_glow_active = false
    self.hs_queued = false
    self.cleave_queued = false
    self.insufficient_rage = false

    -- Tracker state (shared scan stamp, Shield Block cache, Slam cast window, Overpower
    -- proc window). The widgets live on the mainhand visuals frame; on_bar_update retries
    -- if it was not ready yet.
    self.warrior_scan_at = nil
    self.warrior_shield_block_duration = nil
    self.warrior_shield_block_expires = nil
    self.warrior_slam_casting = false
    self.warrior_slam_cast_start = nil
    self.warrior_slam_cast_duration = nil
    self.warrior_overpower_proc_until = nil
    self.warrior_overpower_flash_on = false
    self.warrior_rampage_stacks = nil
    self.warrior_rampage_expires = nil
    self.warrior_rampage_text_shown = nil
    -- Build-out round 1 state: the W3 tier colour currently applied to the
    -- badge, the W1 bank cue's visibility (churn-guarded) and the Battle Shout
    -- badge's shadow state (capture timestamp + last written read-out).
    self.warrior_rampage_tier_applied = nil
    self.warrior_bank_shown = false
    self.warrior_battle_shout_text_shown = nil
    self.warrior_battle_shout_expires = nil
    -- W2 Commanding coverage stamp (the suppression input; persists between
    -- fights, like the Battle Shout capture above).
    self.warrior_commanding_expires = nil
    -- Desync spark state (competitor-gaps W1): visibility + verdict churn
    -- guards for the widget below.
    self.warrior_desync_shown = false
    self.warrior_desync_verdict = nil
    -- Execute-phase practice log (the W6 drill below): the rolling log is
    -- created on first use, the phase latch starts disarmed.
    self.warrior_execute_log = nil
    self.warrior_execute_phase_active = false
    self.has_sudden_death = false
    self.has_tfb = false
    self.has_sod_stance_aura = false
    -- Frozen branch (Mortal Strike known = arms; ERA + SoD rune = SoD): the
    -- slot set and the engine flags freeze together here, so the two can never
    -- disagree about which actions exist. A respec or rune change mid-session
    -- needs /reload (see the guide header).
    self.warrior_is_arms = is_arms_spec()
    self.warrior_is_sod = is_sod_client()
    -- Hamstring weave filler known: frozen with the branch flags above (a
    -- spellbook fact, not a fight fact). The gather exposes it for rule W
    -- with the Era threshold; other families feed a nil threshold.
    self.warrior_has_hamstring = is_hamstring_known()
    -- SoD Rend rune known (412507 CONFIRMED, Blood Frenzy): a spellbook fact frozen with
    -- the branch flags above. Fed to the gather as its own input and never
    -- ORed into is_sod_client, so SoD detection (ERA + Raging Blow / Consumed
    -- by Rage) keeps its exact shape - a client that knows only this rune
    -- stays Era-base, exactly like before.
    self.warrior_has_sod_rend_rune = is_spell_known_query(sod_rend_rune_id)
    self.WARRIOR.resolve_guide_slots(self)
    self.WARRIOR.setup_warrior_visuals(self)

    -- Next Action Guide: resolve the guide's ability icons to the client's current ranks
    -- while the spell data is live, then hand the provider (ST.WARRIOR.guide at the end
    -- of this file) to the shared frame. Guarded so a flavor without nextaction_ui stays
    -- inert; the guide itself stays hidden until nextaction_enabled is turned on.
    self.WARRIOR.resolve_guide_icons()
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
    -- Twist Practice: builds its own UIParent frames and the pure-engine bridge;
    -- guarded so a flavor without the practice files stays inert (the paladin
    -- wires it the same way in classes/paladin.lua). The session is the same
    -- twist-sim minigame on every class: the panel icons cast simulated spells
    -- and the options Practice toggle (or /st practice) starts and stops it.
    -- The drill's own Execute log (the W6 section below) reads
    -- session-independently, so the report needs no session. The callable guard
    -- (not just nil) keeps a partially loaded practice_ui from throwing.
    if st.practice_ui and type(st.practice_ui.init) == "function" then
        -- The practice panel's action vocabulary: the class's own guide slots plus
        -- the common abilities (a potion, food, a movement ability). The guide frame
        -- above already built its icons from the display vocabulary, so this widens
        -- the PANEL's strip, not the frame (the shaman's apply_family_slots
        -- precedent).
        ST.WARRIOR.apply_practice_panel_actions()
        st.practice_ui.init(self)
    end
end

function ST.WARRIOR.on_combat_exit(self)
    -- A queued ability dies with the fight; without this the bar can keep the HS /
    -- Cleave / insufficient-rage colour into the next pull. The same goes for an
    -- in-flight Slam cast and the Overpower dodge window (the reference clears
    -- warriorOverpowerProcUntil on PLAYER_REGEN_ENABLED, SuperSwingTimer.lua:1694).
    self.hs_queued = false
    self.cleave_queued = false
    self.insufficient_rage = false
    self.warrior_overpower_proc_until = nil
    self.warrior_slam_casting = false
    self.warrior_slam_cast_start = nil
    self.warrior_slam_cast_duration = nil
    self.WARRIOR.process_bloodsurge(self)
    if self.interfaces_are_initialised then
        self:set_bar_color("mainhand")
    end
end

function ST.WARRIOR.set_bar_color(self, hand)
    -- Returns true if any special setting was applied to let the parent func know
    -- to revert to default behaviour.
    -- Will set appropriate colors for HS/Cleave queued if requested in the settings,
    -- and will set a special color when the player has one of those queued up but has
    -- insufficient rage to cast them.
    local db_class = self:get_class_table()
    if type(db_class) ~= "table" then
        -- PROPER: false lets the parent draw the default colour; the bar still
        -- shows, only the optional queue tint is withheld without preferences.
        return false
    end
    local frame = self:get_visuals_frame(hand)
    if frame == nil then
        -- PROPER: with no frame there is nothing to recolour; the bar itself is
        -- drawn by bars.lua, which owns unbuilt-hand visibility.
        return false
    end

    self.WARRIOR.process_bloodsurge(self)

    if hand ~= "mainhand" then
        return false
    end

    -- On-next-attack behaviours
    if db_class.enable_hs_color and self.hs_queued and not (self.insufficient_rage) then
        frame.bar:SetVertexColor(
            self:convert_color(db_class.hs_color)
        )
        return true
    end
    if db_class.enable_cleave_color and self.cleave_queued and not (self.insufficient_rage) then
        frame.bar:SetVertexColor(
            self:convert_color(db_class.cleave_color)
        )
        return true
    end

    -- Insufficient rage for queue.
    if (self.cleave_queued or self.hs_queued) and self.insufficient_rage then
        frame.bar:SetVertexColor(
            self:convert_color(db_class.insufficient_rage_color)
        )
        return true
    end

    return false

end

--=========================================================================================
-- Warrior trackers (reference SuperSwingTimer_ClassMods.lua warrior block 1689-3333)
--=========================================================================================
-- The Shield Block duration bar, the Slam cast bar, the Overpower dodge-proc flash,
-- the Rampage upkeep badge, the Battle Shout badge, the W1 rage-bank cue, the
-- desync spark and the
-- Deep Wounds / Sunder Armor / Rend / Thunder Clap / Demo Shout bars live here.
-- The pure maths lives next to the widgets (this class has no separate pure module):
-- ST.WARRIOR.get_debuff_remaining / should_debuff_glow / get_overpower_remaining /
-- is_overpower_cast / get_rampage_display / get_rampage_tier / get_bank_state /
-- get_battle_shout_display / composite_rage_gate / gate_composite_action are
-- directly unit-tested (the desync verdict + spark fraction live in
-- warrior_guide.lua, pinned by tests/warrior_guide_state.lua). One throttled scan (0.05 s) of the target's
-- harmful auras feeds all five debuff bars; the player's helpful auras are read on the
-- same cadence for Shield Block. Every read is gated on the options that consume it.

-- Slam, all ranks across the classic families. The same set the vendored
-- LibClassicSwingTimerAPI carries as pause_swing_spells (reference PAUSE_SWING_SPELLS,
-- SuperSwingTimer_Constants.lua:762-768; the WotLK ranks 47474/47475 come from the
-- library's own table, Libs/LibClassicSwingTimerAPI/LibClassicSwingTimerAPI.lua:1231-1240).
-- The localized-name fallback covers a rank the table misses.
local slam_ids = get_tab({ 47475, 47474, 25242, 25241, 11605, 11604, 8820, 1464 })

-- Overpower: the reference resolves rank 1 and matches the localized name for the other
-- ranks (Constants.lua:189-190; State.lua:1418-1421). Shield Block: the player's defensive
-- buff (SHIELD_BLOCK_ID/NAME, Constants.lua:261-262).
local overpower_id = 7384
-- All four Overpower ranks (wowhead.com/classic/spell=7384 R1, /7887 R2,
-- /11584 R3, /11585 R4; the classic sim registers 11585 and the tbc-new
-- fury/arms + SoD APLs cast it): the fast id path below, so TBC+ casts clear
-- the dodge window without waiting on the localized-name fallback.
local op_ids = get_tab({ 7384, 7887, 11584, 11585 })
local shield_block_id = 2565

-- Target debuff rank ids (reference SuperSwingTimer_Constants.lua:274-347). The
-- localized-name fallback below covers ranks added after the reference's table was
-- written (its own name fallbacks do the same).
local deep_wounds_ids = get_tab({ 12721 })
local sunder_armor_ids = get_tab({ 7386, 7405, 8380, 11596, 11597, 25225 })
-- Rend ranks: the vanilla set plus the WotLK max 47465 (15 s duration,
-- wowhead.com/wotlk/spell=47465). 25208 is the TBC rank 8
-- (wowhead.com/tbc/spell=25208 is Rend): it sat in ww_ids by mistake and
-- moves here, so the TBC Rend resolves and the WW cost/cooldown reads stop
-- answering through a Rend id. Wrath clients resolve the max; older
-- families never see that id, so carrying it is harmless (the BT/WW comment
-- above). The guide's arms upkeep reads through the same table.
local rend_ids = get_tab({ 772, 6546, 6547, 6548, 11572, 11573, 11574, 25208, 47465 })
local thunder_clap_ids = get_tab({ 6343, 8198, 8204, 8205, 11580, 11581 })
local demo_shout_ids = get_tab({ 1160, 6190, 11554, 11555, 11556 })

-- Scan/geometry constants (parenthesised line references are the reference's).
local WARRIOR_SCAN_INTERVAL = 0.05        -- 0.05 s scan cadence (ClassMods 2332, 2483, ...)
local WARRIOR_BAR_BOTTOM_GAP = 2          -- bottom slot above the bar (RestackDebuffBars gap)
local WARRIOR_BAR_STACK_GAP = 2           -- between stacked bars (same gap)
local WARRIOR_DEBUFF_HEIGHT = 6           -- all five reference debuff bars are 6 px
local WARRIOR_SHIELD_BLOCK_HEIGHT = 4     -- WARRIOR_SHIELD_BLOCK_BAR_HEIGHT (Constants.lua:166)
local WARRIOR_SLAM_HEIGHT = 4             -- the reference slam bar is 4 px (ClassMods.lua:1935)
local WARRIOR_GLOW_WINDOW = 4             -- glow inside the final 4 s (GLOW_WINDOW constants)
-- The HUD's and the BAR's own style constants ride the MODULE TABLE, not
-- file-scope locals: this module sits at the Lua 5.1 ceiling for file-scope
-- locals (200), so one more `local` here would be a LOAD FAILURE on every
-- client (the class's own precedent: WARRIOR_UTILITY). Nothing below is
-- mutated - every entry is read-only, exactly as the constants were.
ST.WARRIOR.hud_style = {
    op_edge_color = { 1, 0.85, 0.10 },    -- Overpower glow edge (ClassMods.lua:1981)
    op_text_color = { 1.0, 0.95, 0.2, 1 }, -- "OP" text (ClassMods.lua:2015)
    op_pulse_hz = 10,                     -- sin(now * 10) pulse (ClassMods.lua:2027)
    slam_label_color = { 1.0, 0.85, 0.15, 0.95 }, -- slam label (ClassMods.lua:1949)
    -- Slam safe-window band (brainstorm W4): the Slam fill reads green when the
    -- cast lands before the next swing and red when the swing lands mid-cast (the
    -- cast resets into the deadzone). Drawn behind the existing slam-bar toggle
    -- (no new option); on Forever every cast reads clean (Forever Slam never
    -- resets the swing - the swing_resets == false path of the pure verdict).
    slam_safe_color = { 46, 204, 113, 1.0 },
}

ST.WARRIOR.bar_style = {
    -- shieldBlockBar (Constants.lua:1006)
    shield_block_fallback_color = { 51, 140, 255, 0.90 },
    slam_clash_color = { 217, 38, 26, 0.90 },
    -- Dual-wield desync alert (competitor-gaps W1): a 2 px spark on the mainhand
    -- bar marking where the offhand swing lands inside the current MH swing,
    -- tinted green while desynced (the ideal - Wowhead "remain out of sync") and
    -- amber while synced (the alert - the Desync Alert WA state). tazUI
    -- green-ideal/yellow-offhand precedent (prior corpus). Default OFF
    -- (show_warrior_desync_alert ~= true: nil = off like the bank cue); the
    -- options lane owns the default + widget when it ships them. No new probe:
    -- the swing engine's own mainhand/offhand stamps decide (nil-safe, unknown
    -- hides). No guide rule, no HUD slot: the desync stays a visual alert only,
    -- and bars.lua/hud.lua are out of this lane's scope (follow-up).
    desync_spark_width = 2,
    desync_clash_color = { 255, 170, 0, 0.95 },
    -- Rampage upkeep badge (the Shamanistic Rage badge pattern in
    -- classes/shaman.lua: a right-edge FontString with a countdown text).
    rampage_badge_color = { 255, 140, 26, 0.95 },
    -- W1 rage-bank cue (buildout W1): a 2 px amber top edge plus a centred "BANK"
    -- label on the mainhand visuals frame while in combat the target sits inside
    -- the pre-Execute band ([threshold, threshold + 15 %) - the band the verifier
    -- described) and rage has reached the floor. Static powerset of the Overpower
    -- flash (edge + centred text), no pulse: the cue is a sustained condition.
    bank_band = 15,
    bank_rage_floor = 60,
    bank_edge_color = { 255, 170, 0, 0.95 },
    bank_text_color = { 255, 170, 0, 1.0 },
    -- Battle Shout uptime badge (the Rampage badge pattern, one widget above it).
    battle_shout_badge_color = { 240, 200, 60, 0.95 },
}
-- The clean desync tint IS the Slam safe-window colour (one green for "in sync"
-- and "safe window"), and the Rampage tier colours reuse it plus the badge
-- colour. Assigned after the tables so the references read as they did as
-- locals (the same table objects, not copies).
ST.WARRIOR.bar_style.desync_clean_color = ST.WARRIOR.hud_style.slam_safe_color
-- Rampage tier colours (buildout W3): the badge recolours by how well the
-- buff is maintained - green while the refresh window is far, amber inside
-- the final glow window, red inside the final 2 s. Green and amber reuse the
-- Slam safe-window colour and the badge's original colour; red is the Slam
-- clash hue at full alpha.
ST.WARRIOR.bar_style.rampage_tier_colors = {
    green = ST.WARRIOR.hud_style.slam_safe_color,
    amber = ST.WARRIOR.bar_style.rampage_badge_color,
    red = { 217, 38, 26, 1.0 },
}

-- W2 composite fallback costs (verify §4.2 - BINDING): the class's known rank
-- costs stand in when a family's cooldown read answers but its power-cost read
-- stays muted (the gate then still protects the rage floor; the costs are the
-- vanilla-line Bloodthirst/Whirlwind ranks the classic families carry).
local WARRIOR_COMPOSITE_BT_COST = 30
local WARRIOR_COMPOSITE_WW_COST = 25

-- Ordered bottom-to-top exactly like the reference restack list (ClassMods.lua:3000-3005):
-- Deep Wounds, Sunder Armor, Rend, Thunder Clap, Demo Shout. Heights (6 px), fallback
-- durations (12 / 30 / 9 / 30 / 30 s) and fill colours (ClassMods.lua:2273, 2413, 2565,
-- 2705, 2844) are the reference's; the colours are stored in the class-option format
-- (0-255 RGB + 0-1 alpha, converted through the same convert_color path as the rest).
local warrior_debuff_defs = {
    {
        key = "deep_wounds",
        ids = deep_wounds_ids,
        fallback_names = { ["Deep Wound"] = true, ["Deep Wounds"] = true },
        fallback_duration = 12,
        option = "show_warrior_deep_wounds_bar",
        color_option = "warrior_deep_wounds_bar_color",
        fallback_color = { 179, 38, 38, 0.90 },
    },
    {
        key = "sunder_armor",
        ids = sunder_armor_ids,
        fallback_names = { ["Sunder Armor"] = true },
        fallback_duration = 30,
        label_mode = "stacks",
        option = "show_warrior_sunder_armor_bar",
        color_option = "warrior_sunder_armor_bar_color",
        fallback_color = { 140, 89, 38, 0.90 },
    },
    {
        key = "rend",
        ids = rend_ids,
        fallback_names = { ["Rend"] = true },
        fallback_duration = 9,
        option = "show_warrior_rend_bar",
        color_option = "warrior_rend_bar_color",
        fallback_color = { 217, 38, 26, 0.90 },
    },
    {
        key = "thunder_clap",
        ids = thunder_clap_ids,
        fallback_names = { ["Thunder Clap"] = true },
        fallback_duration = 30,
        option = "show_warrior_thunder_clap_bar",
        color_option = "warrior_thunder_clap_bar_color",
        fallback_color = { 89, 140, 191, 0.90 },
    },
    {
        key = "demo_shout",
        ids = demo_shout_ids,
        fallback_names = { ["Demoralizing Shout"] = true, ["Demoralising Shout"] = true },
        fallback_duration = 30,
        option = "show_warrior_demo_shout_bar",
        color_option = "warrior_demo_shout_bar_color",
        fallback_color = { 166, 128, 77, 0.90 },
    },
}

-- The bar's configured font, with the client standard font as the fallback for
-- sandboxes and stripped clients (same shape as the shaman/druid tracker helper).
local function get_tracker_font_path(self)
    local db_hand = self.get_hand_table and self:get_hand_table("mainhand")
    if LSM and LSM.Fetch and db_hand and db_hand.text_font then
        local path = LSM:Fetch("font", db_hand.text_font)
        if path then return path end
    end
    return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

--=========================================================================================
-- Pure tracker maths (unit-tested directly by tests/warrior_state.lua)
--=========================================================================================

-- Remaining/total pair for a timed debuff bar: the fallback duration covers auras the
-- client reports without one; a listed-but-expired aura floors at 0 (the reference clamps
-- the same way, ClassMods.lua:2366-2369).
function ST.WARRIOR.get_debuff_remaining(aura_duration, aura_expiration, now, fallback_duration)
    local duration = tonumber(aura_duration)
    if not duration or duration <= 0 then
        duration = fallback_duration
    end
    local remaining = duration
    if type(aura_expiration) == "number" and aura_expiration > 0 then
        remaining = aura_expiration - now
        if remaining < 0 then
            remaining = 0
        end
    end
    return remaining, duration
end

-- The glow window: on inside the final 4 s of a still-running debuff, never at 0.
function ST.WARRIOR.should_debuff_glow(remaining)
    return type(remaining) == "number" and remaining > 0 and remaining <= WARRIOR_GLOW_WINDOW
end

-- Overpower proc countdown: the remaining seconds of the dodge window, or nil when it is
-- unset or already over.
function ST.WARRIOR.get_overpower_remaining(proc_until, now)
    if type(proc_until) ~= "number" then
        return nil
    end
    local remaining = proc_until - now
    if remaining <= 0 then
        return nil
    end
    return remaining
end

-- Rampage badge text: "RAMPAGE x<stacks> <seconds>s" while the buff is live, the
-- stacks-only form when the client reported no expiration, nil when the badge
-- should hide (no stacks, or the window already elapsed). The stack cap is
-- applied by the aura scan, never here, so this stays a pure formatter.
function ST.WARRIOR.get_rampage_display(stacks, expires, now)
    if type(stacks) ~= "number" or stacks < 1 then
        return nil
    end
    if type(expires) == "number" and expires > 0 then
        local remaining = expires - now
        if remaining <= 0 then
            return nil
        end
        return string.format("RAMPAGE x%d %.0fs", stacks, remaining)
    end
    return string.format("RAMPAGE x%d", stacks)
end

--=========================================================================================
-- Build-out round 1 pure helpers (referenced rows in bench/verify_bank.md);
-- all directly unit-tested in tests/warrior_state.lua
--=========================================================================================

-- Rampage refresh tier (buildout W3): the badge recolours by how well the buff
-- is maintained - nil with no buff, "red" inside the final 2 s, "amber" inside
-- the final glow window, "green" while well-maintained. A client that never
-- reported an expiry reads amber (the refresh window is unknown, not maintained).
function ST.WARRIOR.get_rampage_tier(stacks, expires, now)
    if type(stacks) ~= "number" or stacks < 1 then
        return nil
    end
    if type(expires) ~= "number" or expires <= 0 then
        return "amber"
    end
    local remaining = expires - now
    if remaining <= 2 then
        return "red"
    elseif remaining <= WARRIOR_GLOW_WINDOW then
        return "amber"
    end
    return "green"
end

-- W1 rage-bank state: true while in combat, the PLAYER'S health percentage sits
-- inside the pre-Execute band [threshold, threshold + band) and rage has reached
-- the floor. An unreadable health or rage never arms the cue: the state would
-- have to claim the band without seeing it, and a wrongly shown cue is costlier
-- than a missed one (the W2 gate degrades the opposite way on purpose - there
-- the withhold is the risk, here the false show is).
function ST.WARRIOR.get_bank_state(health_pct, execute_pct, rage, in_combat)
    if in_combat ~= true then
        return false
    end
    if type(health_pct) ~= "number" or type(execute_pct) ~= "number" then
        return false
    end
    if type(rage) ~= "number" or rage < ST.WARRIOR.bar_style.bank_rage_floor then
        return false
    end
    return health_pct >= execute_pct and health_pct < execute_pct + ST.WARRIOR.bar_style.bank_band
end

-- W2 composite rage gate (verify §4.2 - BINDING): true when rage covers the
-- prompt's cost plus the reserve the composite must protect. Unknown reads
-- degrade to ALLOW (unknown is not a shortage - the rotation label pins that
-- Bloodthirst stays the default with no power read), so a nil cost or an
-- unknown reserve is treated as absent. The caller substitutes the class's
-- fixed fallback costs first (the authoritative rank cost on a muted client),
-- so in the composite path none of the costs are nil.
function ST.WARRIOR.composite_rage_gate(rage, cost, reserve)
    if type(rage) ~= "number" or type(cost) ~= "number" then
        return true
    end
    local reserved = type(reserve) == "number" and reserve or 0
    return rage >= cost + reserved
end

-- Cost substitute: a numeric client read wins, otherwise the documented fixed
-- cost (the reserve uses 0 - an unjudgeable read cannot reserve what it cannot
-- see, so the composite degrades to the ungated core comparison).
local function composite_cost(cost, fallback)
    if type(cost) == "number" then
        return cost
    end
    return fallback
end

-- The gate over the engine's composite pick (buildout W2): the engine orders
-- the TBC core by cooldown alone, so its Bloodthirst prompt can be fired while
-- the rage a queued Heroic Strike/Cleave needs is already promised. Only a
-- Bloodthirst prompt is re-judged (the engine's own HS-cancel cue and the rule
-- order it feeds the queue into keep the other actions coherent); a gated BT
-- falls back "BT first, WW next": Whirlwind is the next core, so the prompt
-- shifts to WW when that core is ready AND still affordable after the same
-- reserve - otherwise no prompt at all. Touches out.action only.
function ST.WARRIOR.gate_composite_action(inputs, out)
    if out.action ~= "bt" then
        return out
    end
    local reserve = 0
    if inputs.hs_queued == true then
        reserve = composite_cost(inputs.hs_cost, 0)
    elseif inputs.cleave_queued == true then
        reserve = composite_cost(inputs.cleave_cost, 0)
    end
    local bt_cost = composite_cost(inputs.bt_cost, WARRIOR_COMPOSITE_BT_COST)
    if ST.WARRIOR.composite_rage_gate(inputs.rage, bt_cost, reserve) then
        return out
    end
    local ww_cost = composite_cost(inputs.ww_cost, WARRIOR_COMPOSITE_WW_COST)
    if type(inputs.ww_remaining) == "number" and inputs.ww_remaining <= 0
        and ST.WARRIOR.composite_rage_gate(inputs.rage, ww_cost, reserve) then
        out.action = "ww"
    else
        out.action = nil
    end
    return out
end

-- Battle Shout badge text: "BS <seconds>s" while the buff's window is live,
-- nil when the badge should hide (no capture, or the window already elapsed).
-- The fallback shadow is applied by the aura scan, never here.
function ST.WARRIOR.get_battle_shout_display(expires, now)
    if type(expires) ~= "number" or expires <= 0 then
        return nil
    end
    local remaining = expires - now
    if remaining <= 0 then
        return nil
    end
    return string.format("BS %.0fs", remaining)
end

--=========================================================================================
-- Execute-phase practice: the live feed for the warrior_execute drill (W6)
--=========================================================================================
-- The bank-cue demand (bench/competitor_gaps_2026-10-19.md Warrior W2): pool rage
-- and cross into Execute range loaded. The pure grading math lives in the practice
-- harness (practice.lua H.grade_execute_entry + H.EXECUTE_ENTRY_BANDS, the same
-- registry the drill is registered in); the report screen lives in practice_ui.lua.
-- This module only gathers, mirroring the hunter shot log (classes/hunter.lua
-- record_shot_sample / track_live_cast): one sample per phase entry, a bounded
-- rolling log (newest wins) plus cumulative counters. Unknown hides: an unreadable
-- target HP fraction records nothing, an unreadable rage grades nil, and a NaN on
-- either side reads as unknown (never a guess, never a grade on a guess).
-- Driven from on_bar_update on the mainhand tick; the options Execute report
-- reads the log session-independently (no panel, no fight scope).
ST.WARRIOR.EXECUTE_LOG_MAX = 200

-- Target HP as a 0-1 fraction, or nil when the client does not answer (no
-- target, a dead unit, or an unreadable read). The bank cue reads the player's
-- own HP on the same 0-100 convention; the drill's threshold rides the guide's
-- own execute_pct (default 20) so the two never disagree about the phase edge.
local function execute_hp_fraction()
    local max = api.UnitHealthMax("target")
    if type(max) ~= "number" or max ~= max or max <= 0 then
        return nil
    end
    local cur = api.UnitHealth("target")
    if type(cur) ~= "number" or cur ~= cur then
        return nil
    end
    return cur / max
end

-- One Execute-phase entry: the HP fraction and rage at the crossing, graded
-- through the harness entry bands (full pool = S, empty = F). Nil-safe: a
-- non-table owner is ignored and the log is created on first use.
function ST.WARRIOR.record_execute_sample(self, hp_fraction, rage)
    if type(self) ~= "table" then
        return
    end
    if type(hp_fraction) == "number" and hp_fraction ~= hp_fraction then
        hp_fraction = nil
    end
    if type(rage) == "number" and rage ~= rage then
        rage = nil
    end
    local grade = nil
    local harness = st.practice and st.practice.harness
    if harness and harness.grade_execute_entry then
        grade = harness.grade_execute_entry({}, rage)
    end
    local log = self.warrior_execute_log
    if type(log) ~= "table" then
        log = {}
        self.warrior_execute_log = log
    end
    log[#log + 1] = {
        hp_fraction = hp_fraction,
        rage = rage,
        grade = grade,
        -- The drill the sample belongs to: the class's OWN execute-phase drill
        -- (the one the retired built-in "warrior_execute" is superseded by), so
        -- a row never reads as a run of the retired drill.
        drill = ST.WARRIOR.practice_drill_key(),
        at = api.get_time(),
    }
    while #log > ST.WARRIOR.EXECUTE_LOG_MAX do
        table.remove(log, 1)
    end
    self.warrior_execute_entries_total = (self.warrior_execute_entries_total or 0) + 1
    if grade ~= nil then
        self.warrior_execute_entries_graded = (self.warrior_execute_entries_graded or 0) + 1
    end
end

-- Per-frame phase sampler, driven from on_bar_update on the mainhand tick (the
-- Execute glow it grades only ticks there too). Armed by the practice session:
-- with no session running it performs no reads at all (the bank-cue read
-- discipline: a disabled drill costs nothing). Tracks the phase edge across
-- frames through the guide's own threshold: the crossing records one sample,
-- staying inside fires nothing, leaving re-arms. An unknown HP fraction judges
-- nothing.
function ST.WARRIOR.track_execute_phase(self)
    if type(self) ~= "table" then
        return
    end
    local pui = st.practice_ui
    if type(pui) ~= "table" or type(pui.is_active) ~= "function"
        or pui.is_active() ~= true then
        return
    end
    local hp = execute_hp_fraction()
    if hp == nil then
        return
    end
    local db = self.get_class_table and self:get_class_table() or nil
    local pct = db and db.guide_execute_pct or 20
    if type(pct) ~= "number" or pct ~= pct then
        pct = 20
    end
    if hp <= pct / 100 and not self.warrior_execute_phase_active then
        self.warrior_execute_phase_active = true
        ST.WARRIOR.record_execute_sample(self, hp, api.UnitPower("player"))
    elseif hp > pct / 100 and self.warrior_execute_phase_active then
        self.warrior_execute_phase_active = false
    end
end

-- True when a successful-cast payload is an Overpower cast: the rank-1 id, the literal or
-- localized name token, or any rank whose resolved name matches (the reference matches id
-- + name, State.lua:1418-1421). The localized name is resolved lazily and never retried
-- into a hard failure: a client without the spell data simply never name-matches.
local overpower_name_resolved
local overpower_name_retry_at = 0

local function resolve_overpower_name(now)
    if overpower_name_resolved == nil and now >= overpower_name_retry_at then
        local name = api.GetSpellInfo(overpower_id)
        if name then
            overpower_name_resolved = name
        else
            overpower_name_retry_at = now + WARRIOR_NAMES_RETRY_S
        end
    end
end

function ST.WARRIOR.is_overpower_cast(spell_id, cast_guid, now)
    if (type(spell_id) == "number" and op_ids[spell_id]) or cast_guid == "Overpower" then
        return true
    end
    resolve_overpower_name(now)
    local name = overpower_name_resolved
    if name == nil then
        return false
    end
    if cast_guid == name then
        return true
    end
    if type(spell_id) == "number" then
        return api.GetSpellInfo(spell_id) == name
    end
    return false
end

--=========================================================================================
-- Throttled reads (one merged target scan + one player Shield Block read per window)
--=========================================================================================

-- Reused scan state: the per-window result of the merged target walk, keyed by debuff
-- key. Cleared and refilled per scan (assignments only, so the throttled scan path never
-- allocates beyond the localized-name table's first resolution).
local warrior_debuff_found = {}
local warrior_debuff_duration = {}
local warrior_debuff_expiration = {}
local warrior_debuff_stacks = {}

-- Resolve the client's own (localized) names for a debuff's rank ids, mirroring the
-- reference's ns.WARRIOR_*_NAME = GetSpellInfo(id) ... at load (Constants.lua:335, 341,
-- 347). Lazy: it only runs from the scan while a bar option is on, so an all-off
-- configuration reads nothing from the client. An unanswered client (spell data not up
-- yet) retries at a throttled cadence.
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
        def.names_retry_at = now + WARRIOR_NAMES_RETRY_S
    end
end

-- One throttled walk of the target's harmful auras feeds all five debuff bars (the
-- reference walks once per bar, ClassMods.lua:2309-2327 etc.; one merged walk follows the
-- druid/shaman ports). Each aura matches by rank id first, then by the localized name
-- resolved from the client, then by the literal English fallback; the aura must belong to
-- the player. A target without matching auras - or no target at all, where UnitAura
-- answers nil - clears every slot. Stack counts are captured for every slot (Sunder
-- Armor's label shows one).
local function scan_target_warrior_debuffs(now)
    local found = warrior_debuff_found
    local duration = warrior_debuff_duration
    local expiration = warrior_debuff_expiration
    local stacks = warrior_debuff_stacks
    local pending = #warrior_debuff_defs
    for i = 1, #warrior_debuff_defs do
        local def = warrior_debuff_defs[i]
        local key = def.key
        found[key] = nil
        duration[key] = nil
        expiration[key] = nil
        stacks[key] = nil
        if def.localized_names == nil and now >= (def.names_retry_at or 0) then
            resolve_debuff_localized_names(def, now)
        end
    end
    local index = 1
    while index <= 40 and pending > 0 do
        local name, _, count, _, aura_duration, aura_expiration, source, _, _, spell_id =
            api.UnitAura("target", index, "HARMFUL")
        -- No early break (R2): a secret entry degrades to absent and the walk
        -- continues past it, so a restricted row above the debuffs no longer
        -- truncates the scan.
        if name ~= nil then
            if source == "player" or source == nil then
                for i = 1, #warrior_debuff_defs do
                    local def = warrior_debuff_defs[i]
                    local key = def.key
                    if found[key] == nil then
                        local is_match = (type(spell_id) == "number" and def.ids[spell_id] ~= nil)
                            or def.fallback_names[name] == true
                            or (def.localized_names ~= nil and def.localized_names[name] == true)
                        if is_match then
                            found[key] = true
                            duration[key] = aura_duration
                            expiration[key] = aura_expiration
                            stacks[key] = tonumber(count)
                            pending = pending - 1
                        end
                    end
                end
            end
        end
        index = index + 1
    end
end

-- Shield Block read: one walk of the player's helpful auras, throttled with the debuff
-- scan. The localized name and the bar icon are resolved from the client's spell data
-- lazily (same cadence as the debuff names) so an option-off configuration never touches
-- GetSpellInfo.
local shield_block_name_resolved
local shield_block_icon_resolved
local shield_block_retry_at = 0

local function resolve_shield_block_info(now)
    if shield_block_name_resolved == nil and now >= shield_block_retry_at then
        local name, _, icon = api.GetSpellInfo(shield_block_id)
        if name then
            shield_block_name_resolved = name
            shield_block_icon_resolved = icon or false
        else
            shield_block_retry_at = now + WARRIOR_NAMES_RETRY_S
        end
    end
end

local function scan_player_shield_block(now)
    resolve_shield_block_info(now)
    local i = 1
    while i <= 40 do
        -- "HELPFUL" explicitly: the Retail wrapper forwards the filter into
        -- C_UnitAuras.GetAuraDataByIndex, where it is a typed enum argument.
        -- No early break (R2): a secret entry degrades to absent and the walk
        -- continues past it.
        local name, _, _, _, duration, expiration, _, _, _, spell_id =
            api.UnitAura("player", i, "HELPFUL")
        if name ~= nil then
            if spell_id == shield_block_id
                or (shield_block_name_resolved ~= nil and name == shield_block_name_resolved)
                or name == "Shield Block" then
                return duration, expiration
            end
        end
        i = i + 1
    end
    return nil, nil
end

-- Slam name matching for payloads that carry a name token instead of an id: the client's
-- own localized names for the tracked ranks (resolved once, throttled while the client's
-- spell data is not up yet) plus the literal English fallback.
local slam_localized_names
local slam_names_retry_at = 0

local function resolve_slam_names(now)
    if slam_localized_names == nil and now >= slam_names_retry_at then
        local names = {}
        for id in pairs(slam_ids) do
            local name = api.GetSpellInfo(id)
            if name then
                names[name] = true
            end
        end
        if next(names) ~= nil then
            slam_localized_names = names
        else
            slam_names_retry_at = now + WARRIOR_NAMES_RETRY_S
        end
    end
end

local function is_warrior_slam_token(token, now)
    if token == nil then
        return false
    end
    local id = tonumber(token)
    if id ~= nil then
        return slam_ids[id] == true
    end
    if token == "Slam" then
        return true
    end
    resolve_slam_names(now)
    return slam_localized_names ~= nil and slam_localized_names[token] == true
end


-- Fallback cast duration when the client has no live cast window: the resolved rank's
-- cast time from the client's spell data, else the reference's 1.5 s default
-- (GetSpellCastDuration, ClassMods.lua:1868-1877).
--
-- The rank comes from the class's own cached resolution (the three-valued resolver,
-- see resolve_rank): the verdict is latched - an id when the client confirmed a rank,
-- the final "absent" negative when it refuted every candidate - so a Slam cast never
-- walks the rank table: the first cast resolves it and every later cast reads the
-- cache. A client that cannot answer latches NOTHING (audit F4, the resolver's
-- "unresolved" verdict is retryable, not a refusal), so the next cast asks again once
-- the shared retry backoff has passed and a cold spell book can no longer poison the
-- cast time for the rest of the session.
local function get_slam_fallback_duration()
    slam_current_id = resolve_rank(slam_ids, slam_current_id)
    local id = slam_current_id
    if id then
        local _, _, _, cast_ms = api.GetSpellInfo(id)
        if type(cast_ms) == "number" and cast_ms > 0 then
            return cast_ms / 1000
        end
    end
    return 1.5
end

--=========================================================================================
-- Slam cast tracking (state only; the widgets are drawn by the per-frame hook)
--=========================================================================================

-- The live cast window for the player, in the api.get_time() domain (the same reads the
-- shaman weave assist uses): name, spell id, start seconds, end seconds; nil when no cast
-- is running. UnitCastingInfo and UnitChannelInfo do NOT share a return shape: casting
-- returns castID before notInterruptible and the spell id 9th, channeling has no castID
-- and the spell id 8th.
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

-- Record the start (or delay) of a Slam cast. The client's live start/end window wins;
-- without one the duration falls back to the resolved rank's cast time (Improved Slam and
-- haste are only visible through the live window).
local function begin_warrior_slam_cast(self, live_start, live_end)
    local now = api.get_time()
    self.warrior_slam_casting = true
    if type(live_start) == "number" and type(live_end) == "number" and live_end > live_start then
        self.warrior_slam_cast_start = live_start
        self.warrior_slam_cast_duration = live_end - live_start
    else
        self.warrior_slam_cast_start = now
        self.warrior_slam_cast_duration = get_slam_fallback_duration()
    end
end

local function end_warrior_slam_cast(self)
    self.warrior_slam_casting = false
    self.warrior_slam_cast_start = nil
    self.warrior_slam_cast_duration = nil
end

-- Player spellcast lifecycle (dispatched from main.lua's UNIT_SPELLCAST_* handlers):
-- state-only, like the shaman weave tracker, so the hook is safe on every handler path
-- that reaches it. The option gate comes first, so an option-off configuration performs
-- no cast reads at all; the STOP family always clears, so a cast interrupted mid-flight
-- can never leave the bar stuck.
--
-- G1 (queued-melee tint clears, reference SuperSwingTimer_State.lua:1129-1149): an
-- INTERRUPTED or FAILED cast clears the HS/Cleave queue tint when the token matches
-- the queued ability or names nothing identifiable (nil token). Cleared here, not on
-- SUCCEEDED/FAILED_QUIET (those keep their own hooks). CURRENT_SPELL_CAST_CHANGED
-- re-arms a genuinely live queue on its next probe, so this clear self-heals.
local function is_warrior_queued_melee_id(token)
    return type(token) == "number" and (hs_ids[token] ~= nil or cleave_ids[token] ~= nil)
end

local function clear_warrior_queue_on_interrupt(self, spell_id, cast_guid)
    local token = spell_id
    if token == nil then
        token = cast_guid
    end
    local now = api.get_time()
    local matched = token == nil
        or is_warrior_queued_melee_id(token)
        or is_warrior_queued_melee_proc_name(token, now)
    if not matched then
        return
    end
    if self.hs_queued == true or self.cleave_queued == true then
        self.hs_queued = false
        self.cleave_queued = false
        self:set_bar_color("mainhand")
    else
        self.hs_queued = false
        self.cleave_queued = false
    end
end

-- G3 (Slam pause, our side; reference PAUSE_SWING_SPELLS + AdjustSwingTimesAfterPause
-- in SuperSwingTimer_State.lua:855-872/1041-1043/1416-1418): on Era/BCC the lib's
-- pause tables are empty (LibClassicSwingTimerAPI.lua Era:953 / BCC:1064), so a landed
-- Slam resets the cycle where in-game it extends it (Wrath pauses natively,
-- lib:1203-1210). Arming here at Slam START - seconds before any SUCCEEDED - keeps
-- the consume in main.lua's SWING_TIMER_START order-proof against the lib/AceEvent
-- SUCCEEDED dispatch order. Unconditional: swing behavior, never display.
local function arm_warrior_slam_pause(self, spell_id, cast_guid)
    if st.family ~= "ERA" and st.family ~= "TBC" then
        return
    end
    if st.is_mainline then
        return
    end
    local now = api.get_time()
    if type(now) ~= "number" then
        return
    end
    if not is_warrior_slam_token(spell_id, now) and not is_warrior_slam_token(cast_guid, now) then
        return
    end
    -- Stale backstop: the live cast window when the client answers, else the rank
    -- fallback (the same reads begin_warrior_slam_cast uses) plus margin. A pause
    -- older than this never converts a later real swing.
    local _, _, live_start, live_end = get_live_player_cast()
    local duration
    if type(live_start) == "number" and type(live_end) == "number" and live_end > live_start then
        duration = live_end - live_start
    else
        duration = get_slam_fallback_duration()
    end
    local pause = { at = now, valid_until = now + duration + 2.0 }
    local armed = false
    for _, hand in ipairs({ "mainhand", "offhand" }) do
        local bar = self[hand]
        if type(bar) == "table" and type(bar.ends_at) == "number" then
            local remaining = bar.ends_at - now
            if remaining > 0 then
                pause[hand .. "_rem"] = remaining
                pause[hand .. "_end"] = bar.ends_at
                bar.is_paused = true
                armed = true
            end
        end
    end
    if armed then
        self.warrior_slam_pause = pause
    end
end

-- Clears the pause without extending: the cast never landed (STOP without success,
-- or any path where INTERRUPTED/FAILED did not already extend-then-clear), so the
-- frozen original cycle simply resumes.
local function drop_warrior_slam_pause(self)
    if self.warrior_slam_pause == nil then
        return
    end
    self.warrior_slam_pause = nil
    for _, hand in ipairs({ "mainhand", "offhand" }) do
        local bar = self[hand]
        if type(bar) == "table" then
            bar.is_paused = false
        end
    end
end

-- INTERRUPTED/FAILED with a live pause: the reference shifts the cycle by the
-- paused span on interrupt too (AdjustSwingTimesAfterPause on the interrupt path),
-- so extend-then-clear here. Guards the recorded anchor: anything that re-anchored
-- mid-cast (a haste UPDATE) voids the pause instead of shifting a moved bar.
local function extend_warrior_slam_pause(self)
    local pause = self.warrior_slam_pause
    if type(pause) ~= "table" then
        return
    end
    self.warrior_slam_pause = nil
    local now = api.get_time()
    if type(now) ~= "number" then
        drop_warrior_slam_pause(self)
        return
    end
    local offset = now - (pause.at or now)
    if offset < 0 then
        offset = 0
    end
    for _, hand in ipairs({ "mainhand", "offhand" }) do
        local bar = self[hand]
        if type(bar) == "table" then
            bar.is_paused = false
        end
        if pause[hand .. "_rem"] ~= nil and type(bar) == "table"
            and type(bar.ends_at) == "number" and bar.ends_at == pause[hand .. "_end"]
            and type(bar.speed) == "number" and bar.speed > 0 then
            bar.ends_at = bar.ends_at + offset
            bar.start = bar.ends_at - bar.speed
            if bar.is_full_timer ~= nil and type(bar.is_full_timer.Cancel) == "function" then
                pcall(function() bar.is_full_timer:Cancel() end)
            end
            bar.is_full = false
            self:on_bar_active(hand)
        end
    end
end

function ST.WARRIOR.on_spellcast_event(self, event, unit, cast_guid, spell_id)
    if unit ~= "player" or not self.interfaces_are_initialised then
        return
    end
    if event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED" then
        clear_warrior_queue_on_interrupt(self, spell_id, cast_guid)
        extend_warrior_slam_pause(self)
        end_warrior_slam_cast(self)
        return
    end
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_DELAYED" then
        arm_warrior_slam_pause(self, spell_id, cast_guid)
        local event_db = self:get_class_table()
        -- PROPER: the flag is opt-OUT (nil = show). A missing table cannot prove
        -- the user opted out, so the default-visible behaviour (track) is kept.
        if type(event_db) == "table" and event_db.show_warrior_slam_cast_bar == false then
            return
        end
        local now = api.get_time()
        local live_name, live_spell_id, live_start, live_end = get_live_player_cast()
        if is_warrior_slam_token(spell_id, now) or is_warrior_slam_token(cast_guid, now)
            or is_warrior_slam_token(live_spell_id, now) or is_warrior_slam_token(live_name, now) then
            begin_warrior_slam_cast(self, live_start, live_end)
        end
        return
    end
    if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        drop_warrior_slam_pause(self)
        end_warrior_slam_cast(self)
    end
end

-- Combat log (classic line only; main.lua registers the event for paladins and warriors
-- on non-Mainline clients and forwards the event name so this signature lines up): a
-- player attack that was dodged arms the 5 s Overpower window (reference State.lua:
-- 1315-1321 for swings and 1340-1349 for the queued melee abilities). State-only, so
-- nothing here can touch a frame. On Mainline-code clients (Retail, Forever) the event is
-- never registered, so the dodge window can never arm there; Forever arms the same
-- window through the Bloodthrill aura instead (see on_aura_change).
function ST.WARRIOR.on_combat_log_unfiltered(self, _, timestamp, event, hide_caster, source_guid, source_name, source_flags, source_raid_flags, dest_guid, dest_name, dest_flags, dest_raid_flags, ...)
    if not self.interfaces_are_initialised then
        return
    end
    if source_guid ~= self.player_guid then
        return
    end
    if event == "SWING_MISSED" then
        -- Payload after the destination flags: missType, isOffHand, amountMissed.
        if select(1, ...) == "DODGE" then
            self.warrior_overpower_proc_until = api.get_time() + WARRIOR_OVERPOWER_PROC_WINDOW
        end
        return
    end
    if event == "SPELL_MISSED" then
        -- Payload: spellId, spellName, spellSchool, missType. Only the queued melee
        -- abilities can dodge-proc Overpower (reference State.lua:1343). Anniversary
        -- (UNCONFIRMED, R1) may send the spell name where classic sends the numeric
        -- id: match the id first (the classic path, unchanged), then fall back to
        -- the localized ability names plus the literal English fallbacks. A nil id
        -- never matches, as before.
        local spell_id, spell_name = select(1, ...), select(2, ...)
        local miss_type = select(4, ...)
        local proc_match = (type(spell_id) == "number"
            and (hs_ids[spell_id] ~= nil or cleave_ids[spell_id] ~= nil))
        if not proc_match and type(spell_id) == "string"
            and type(spell_name) == "string" then
            -- String id slot: the payload carries the name twice; match either slot.
            proc_match = is_warrior_queued_melee_proc_name(spell_id, api.get_time())
                or is_warrior_queued_melee_proc_name(spell_name, api.get_time())
        end
        if miss_type == "DODGE" and not proc_match and spell_id ~= nil
            and type(spell_id) ~= "number" and type(spell_id) ~= "string" then
            -- M3 (paladin pattern classes/paladin.lua:648-657): a DODGE whose id
            -- slot is a shape neither matcher reads (a table/boolean payload) is
            -- the addon blind on an evolving CLEU contract, not a non-proc miss:
            -- count it and announce once at the threshold. Numeric/string ids
            -- stay uncounted (unrelated spells are normal play), and so does a
            -- nil id (the deliberate never-match above, pinned in
            -- tests/warrior_state.lua). A moved missType position would also go
            -- unseen - that shape is undetectable from here and stays a residual.
            self.warrior_unmatched_payloads = (self.warrior_unmatched_payloads or 0) + 1
            if self.warrior_unmatched_notified ~= true
                and self.warrior_unmatched_payloads >= WARRIOR_PAYLOAD_NOTICE_AT then
                self.warrior_unmatched_notified = true
                st.utils.print_msg("SwedgeTimer: Overpower proc payloads could not be matched on this client; this session's Overpower window may never arm.")
            end
        end
        if miss_type == "DODGE" and proc_match then
            self.warrior_overpower_proc_until = api.get_time() + WARRIOR_OVERPOWER_PROC_WINDOW
        end
    end
end

--=========================================================================================
-- Widget construction
--=========================================================================================

-- Creates the tracker widgets on the mainhand visuals frame (called from post_init;
-- on_bar_update retries if the frame was not ready yet). Thin textures rather than
-- frames, like the shaman/druid tracker widgets.
function ST.WARRIOR.setup_warrior_visuals(self)
    local vf = self:get_visuals_frame("mainhand")
    if not vf then
        return
    end

    if not vf.warrior_shield_block then
        -- Shield Block bar: dark backing + duration fill, 4 px (reference
        -- UpdateWarriorShieldBlockBar, ClassMods.lua:2037-2144).
        local bg = vf:CreateTexture(nil, "OVERLAY")
        bg:SetDrawLayer("OVERLAY", -2)
        bg:SetColorTexture(0, 0, 0, 0.5)
        bg:SetHeight(WARRIOR_SHIELD_BLOCK_HEIGHT)
        bg:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", 0, WARRIOR_BAR_BOTTOM_GAP)
        bg:Hide()

        local fill = vf:CreateTexture(nil, "OVERLAY")
        fill:SetDrawLayer("OVERLAY", -2)
        fill:SetColorTexture(1, 1, 1, 1)
        fill:SetHeight(WARRIOR_SHIELD_BLOCK_HEIGHT)
        fill:SetWidth(1)
        fill:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
        fill:Hide()

        -- Spell icon LEFT of the bar (reference ClassMods.lua:2098-2104); it is only
        -- shown once the client's spell data answered with a texture.
        local icon = vf:CreateTexture(nil, "OVERLAY")
        icon:SetSize(WARRIOR_SHIELD_BLOCK_HEIGHT, WARRIOR_SHIELD_BLOCK_HEIGHT)
        icon:SetPoint("RIGHT", bg, "LEFT", -2, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        icon:Hide()

        vf.warrior_shield_block = { bg = bg, fill = fill, icon = icon }
    end

    if not vf.warrior_slam then
        -- Slam cast bar: dark backing + progress fill with the "SLAM X.Xs" label right
        -- of the bar (reference UpdateWarriorSlamBar, ClassMods.lua:1917-1967).
        local bg = vf:CreateTexture(nil, "OVERLAY")
        bg:SetDrawLayer("OVERLAY", -2)
        bg:SetColorTexture(0, 0, 0, 0.5)
        bg:SetHeight(WARRIOR_SLAM_HEIGHT)
        bg:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", 0, WARRIOR_BAR_BOTTOM_GAP)
        bg:Hide()

        local fill = vf:CreateTexture(nil, "OVERLAY")
        fill:SetDrawLayer("OVERLAY", -2)
        fill:SetColorTexture(1, 1, 1, 1)
        fill:SetHeight(WARRIOR_SLAM_HEIGHT)
        fill:SetWidth(1)
        fill:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
        fill:Hide()

        local label = vf:CreateFontString(nil, "OVERLAY")
        label:SetPoint("LEFT", bg, "RIGHT", 2, 0)
        label:SetJustifyH("LEFT")
        label:SetFont(get_tracker_font_path(self), 9, "OUTLINE")
        label:SetTextColor(ST.WARRIOR.hud_style.slam_label_color[1], ST.WARRIOR.hud_style.slam_label_color[2],
            ST.WARRIOR.hud_style.slam_label_color[3], ST.WARRIOR.hud_style.slam_label_color[4])
        label:Hide()

        vf.warrior_slam = { bg = bg, fill = fill, label = label }
    end

    if not vf.warrior_debuff then
        -- Debuff bars: dark backing + fill + 1 px glow frame + centred label, one group
        -- per debuff (reference ClassMods.lua:2265-2307 etc.). All five share the
        -- geometry; the fill colour and label text are driven per frame.
        local bars = {}
        for i = 1, #warrior_debuff_defs do
            local def = warrior_debuff_defs[i]
            local bg = vf:CreateTexture(nil, "OVERLAY")
            bg:SetDrawLayer("OVERLAY", -2)
            bg:SetColorTexture(0, 0, 0, 0.45)
            bg:SetHeight(WARRIOR_DEBUFF_HEIGHT)
            bg:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", 0, WARRIOR_BAR_BOTTOM_GAP)
            bg:Hide()

            local fill = vf:CreateTexture(nil, "OVERLAY")
            fill:SetDrawLayer("OVERLAY", -2)
            fill:SetColorTexture(1, 1, 1, 1)
            fill:SetHeight(WARRIOR_DEBUFF_HEIGHT)
            fill:SetWidth(1)
            fill:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", 0, 0)
            fill:Hide()

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

            bars[def.key] = { bg = bg, fill = fill, glow = glow, label = label }
        end
        vf.warrior_debuff = bars
    end

    if not vf.warrior_overpower_edges then
        -- Overpower proc flash: four 1 px gold edges around the bar plus the "OP" centre
        -- marker (reference ClassMods.lua:1974-2015). Only alpha/visibility is written
        -- per frame; the anchors are static.
        local edges = {}

        local top = vf:CreateTexture(nil, "OVERLAY")
        top:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", -1, 0)
        top:SetPoint("BOTTOMRIGHT", vf, "TOPRIGHT", 1, 0)
        top:SetHeight(1)
        top:SetColorTexture(ST.WARRIOR.hud_style.op_edge_color[1], ST.WARRIOR.hud_style.op_edge_color[2],
            ST.WARRIOR.hud_style.op_edge_color[3], 0)
        top:Hide()
        edges[#edges + 1] = top

        local bottom = vf:CreateTexture(nil, "OVERLAY")
        bottom:SetPoint("TOPLEFT", vf, "BOTTOMLEFT", -1, 0)
        bottom:SetPoint("TOPRIGHT", vf, "BOTTOMRIGHT", 1, 0)
        bottom:SetHeight(1)
        bottom:SetColorTexture(ST.WARRIOR.hud_style.op_edge_color[1], ST.WARRIOR.hud_style.op_edge_color[2],
            ST.WARRIOR.hud_style.op_edge_color[3], 0)
        bottom:Hide()
        edges[#edges + 1] = bottom

        local left = vf:CreateTexture(nil, "OVERLAY")
        left:SetPoint("TOPRIGHT", vf, "TOPLEFT", 0, 1)
        left:SetPoint("BOTTOMRIGHT", vf, "BOTTOMLEFT", 0, -1)
        left:SetWidth(1)
        left:SetColorTexture(ST.WARRIOR.hud_style.op_edge_color[1], ST.WARRIOR.hud_style.op_edge_color[2],
            ST.WARRIOR.hud_style.op_edge_color[3], 0)
        left:Hide()
        edges[#edges + 1] = left

        local right = vf:CreateTexture(nil, "OVERLAY")
        right:SetPoint("TOPLEFT", vf, "TOPRIGHT", 0, 1)
        right:SetPoint("BOTTOMLEFT", vf, "BOTTOMRIGHT", 0, -1)
        right:SetWidth(1)
        right:SetColorTexture(ST.WARRIOR.hud_style.op_edge_color[1], ST.WARRIOR.hud_style.op_edge_color[2],
            ST.WARRIOR.hud_style.op_edge_color[3], 0)
        right:Hide()
        edges[#edges + 1] = right

        vf.warrior_overpower_edges = edges

        local text = vf:CreateFontString(nil, "OVERLAY")
        text:SetPoint("CENTER", vf, "CENTER", 0, 0)
        text:SetJustifyH("CENTER")
        text:SetFont(get_tracker_font_path(self), 12, "OUTLINE")
        text:SetTextColor(ST.WARRIOR.hud_style.op_text_color[1], ST.WARRIOR.hud_style.op_text_color[2],
            ST.WARRIOR.hud_style.op_text_color[3], ST.WARRIOR.hud_style.op_text_color[4])
        text:Hide()
        vf.warrior_overpower_text = text
    end

    if not vf.warrior_desync then
        -- Desync spark (competitor-gaps W1): a 2 px vertical marker spanning
        -- the bar, re-anchored per pixel of OH-landing movement and re-tinted
        -- on verdict change only (same churn discipline as the restack cache
        -- above). White base: the per-frame path tints through SetVertexColor.
        local spark = vf:CreateTexture(nil, "OVERLAY")
        spark:SetDrawLayer("OVERLAY", -1)
        spark:SetColorTexture(1, 1, 1, 1)
        spark:SetWidth(ST.WARRIOR.bar_style.desync_spark_width)
        spark:Hide()
        vf.warrior_desync = { spark = spark }
    end

    if not vf.warrior_rampage_text then
        -- Rampage upkeep badge: the stack count + refresh window beside the bar's
        -- right edge (the Shamanistic Rage badge pattern in classes/shaman.lua:
        -- one FontString, text re-set only when the readout changes).
        local rampage_text = vf:CreateFontString(nil, "OVERLAY")
        rampage_text:SetPoint("TOPLEFT", vf, "TOPRIGHT", 3, 2)
        rampage_text:SetJustifyH("LEFT")
        rampage_text:SetFont(get_tracker_font_path(self), 9, "OUTLINE")
        rampage_text:SetTextColor(self:convert_color(ST.WARRIOR.bar_style.rampage_badge_color))
        rampage_text:Hide()
        vf.warrior_rampage_text = rampage_text
    end

    if not vf.warrior_bank then
        -- W1 rage-bank cue (buildout W1): the Overpower flash's static powerset
        -- - a 2 px amber top edge plus a centred 12 px "BANK" label. Colour and
        -- geometry are fixed at creation; the per-frame path only flips their
        -- visibility (GetTimePreciseSec-free, allocation-free).
        local edge = vf:CreateTexture(nil, "OVERLAY")
        edge:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", -1, 0)
        edge:SetPoint("BOTTOMRIGHT", vf, "TOPRIGHT", 1, 0)
        edge:SetHeight(2)
        edge:SetColorTexture(self:convert_color(ST.WARRIOR.bar_style.bank_edge_color))
        edge:Hide()

        local text = vf:CreateFontString(nil, "OVERLAY")
        text:SetPoint("CENTER", vf, "CENTER", 0, 0)
        text:SetJustifyH("CENTER")
        text:SetFont(get_tracker_font_path(self), 12, "OUTLINE")
        text:SetTextColor(self:convert_color(ST.WARRIOR.bar_style.bank_text_color))
        -- Static label: the per-frame path only flips visibility, so the text
        -- is written once here and never re-set on the draw path.
        text:SetText("BANK")
        text:Hide()

        vf.warrior_bank = { edge = edge, text = text }
    end

    if not vf.warrior_battle_shout_text then
        -- Battle Shout uptime badge (buildout - the Rampage badge pattern one
        -- widget above the rampage text; same font, same right-edge anchor).
        local battle_shout_text = vf:CreateFontString(nil, "OVERLAY")
        battle_shout_text:SetPoint("TOPLEFT", vf, "TOPRIGHT", 3, 16)
        battle_shout_text:SetJustifyH("LEFT")
        battle_shout_text:SetFont(get_tracker_font_path(self), 9, "OUTLINE")
        battle_shout_text:SetTextColor(self:convert_color(ST.WARRIOR.bar_style.battle_shout_badge_color))
        battle_shout_text:Hide()
        vf.warrior_battle_shout_text = battle_shout_text
    end
end

--=========================================================================================
-- Per-frame drawing
--=========================================================================================

-- Cached restack (reference RestackDebuffBars, ClassMods.lua:125-181): a bar only
-- re-issues its anchors when the slot it should occupy actually moves, so the per-frame
-- path never churns layout while nothing changes.
local function place_warrior_bar(bar, vf, stack_y)
    if bar.stack_y ~= stack_y then
        bar.stack_y = stack_y
        bar.bg:ClearAllPoints()
        bar.bg:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", 0, stack_y)
        bar.bg:SetPoint("BOTTOMRIGHT", vf, "TOPRIGHT", 0, stack_y)
    end
end

-- Shield Block bar: 4 px with the buff's remaining time and its icon, slot 0 of the
-- shared stack; hidden while the aura is absent (reference ClassMods.lua:2037-2144).
local function update_warrior_shield_block(self, vf, db, now, w, stack_y)
    local bar = vf.warrior_shield_block
    local duration = self.warrior_shield_block_duration
    local expiration = self.warrior_shield_block_expires
    local remaining
    if type(duration) == "number" and duration > 0
        and type(expiration) == "number" and expiration > 0 then
        remaining = expiration - now
        if remaining < 0 then
            remaining = 0
        end
    end
    if db.show_warrior_shield_block_bar == false or remaining == nil then
        bar.bg:Hide()
        bar.fill:Hide()
        bar.icon:Hide()
        return stack_y
    end
    if type(w) == "number" and w > 0 then
        local fraction = remaining / duration
        if fraction < 0 then
            fraction = 0
        elseif fraction > 1 then
            fraction = 1
        end
        bar.fill:SetWidth(w * fraction)
    end
    local colour = db.warrior_shield_block_bar_color or ST.WARRIOR.bar_style.shield_block_fallback_color
    if bar.color_applied ~= colour then
        bar.color_applied = colour
        bar.fill:SetVertexColor(self:convert_color(colour))
    end
    if shield_block_icon_resolved and bar.icon_path ~= shield_block_icon_resolved then
        bar.icon_path = shield_block_icon_resolved
        bar.icon:SetTexture(shield_block_icon_resolved)
    end
    place_warrior_bar(bar, vf, stack_y)
    bar.bg:Show()
    bar.fill:Show()
    if shield_block_icon_resolved then
        bar.icon:Show()
    end
    return stack_y + WARRIOR_SHIELD_BLOCK_HEIGHT + WARRIOR_BAR_STACK_GAP
end

-- Slam cast bar: cast progress with the "SLAM X.Xs" remaining label, slot 1 of the
-- shared stack (reference ClassMods.lua:1917-1967). The fill grows with the cast like the
-- hunter cast bar; the label only re-formats when its tenth-of-a-second readout changes,
-- so the per-frame path allocates nothing.
local function update_warrior_slam(self, vf, db, now, w, stack_y)
    local bar = vf.warrior_slam
    local start_time = self.warrior_slam_cast_start
    local duration = self.warrior_slam_cast_duration
    if db.show_warrior_slam_cast_bar == false
        or not self.warrior_slam_casting
        or type(start_time) ~= "number"
        or type(duration) ~= "number" or duration <= 0 then
        bar.bg:Hide()
        bar.fill:Hide()
        bar.label:Hide()
        return stack_y
    end
    local elapsed = now - start_time
    if elapsed < 0 then
        elapsed = 0
    elseif elapsed > duration then
        elapsed = duration
    end
    if type(w) == "number" and w > 0 then
        bar.fill:SetWidth(math.max(1, w * elapsed / duration))
    end
    -- Slam safe-window band (brainstorm W4): green when the cast lands before
    -- the next swing, red when the swing lands mid-cast. The verdict is the
    -- pure st.warrior_guide.slam_cast_safety helper (guarded: a flavor without
    -- that module keeps the white fill); without swing data the fill is left
    -- alone. The colour is only re-applied on a verdict change, like the
    -- cached restack above.
    local guide = st.warrior_guide
    if guide and guide.slam_cast_safety then
        local swing_remaining
        if self.mainhand and type(self.mainhand.ends_at) == "number" then
            swing_remaining = self.mainhand.ends_at - now
        end
        local safety = guide.slam_cast_safety(duration - elapsed, swing_remaining,
            st.family ~= "FOREVER")
        local colour
        if safety == "clean" then
            colour = ST.WARRIOR.hud_style.slam_safe_color
        elseif safety == "clash" then
            colour = ST.WARRIOR.bar_style.slam_clash_color
        end
        if colour and bar.safety_applied ~= colour then
            bar.safety_applied = colour
            bar.fill:SetVertexColor(self:convert_color(colour))
        elseif colour == nil then
            bar.safety_applied = nil
        end
    end
    local remaining = duration - elapsed
    local tenths = math.floor(remaining * 10 + 0.5)
    if bar.label_tenths ~= tenths then
        bar.label_tenths = tenths
        bar.label:SetText(string.format("SLAM %.1fs", remaining))
    end
    place_warrior_bar(bar, vf, stack_y)
    bar.bg:Show()
    bar.fill:Show()
    bar.label:Show()
    return stack_y + WARRIOR_SLAM_HEIGHT + WARRIOR_BAR_STACK_GAP
end

-- Debuff bars: the throttled scan above feeds all five; between scans each bar just
-- counts down. Whole-second label (Sunder Armor shows its stack count instead), a glow
-- frame inside the final 4 s and the configured fill colour, stacked bottom-to-top in the
-- reference's restack order with the cached restack above.
local function update_warrior_debuff_bars(self, vf, db, now, w, stack_y)
    local bars = vf.warrior_debuff
    if not bars then
        return stack_y
    end
    for i = 1, #warrior_debuff_defs do
        local def = warrior_debuff_defs[i]
        local bar = bars[def.key]
        if db[def.option] == false or warrior_debuff_found[def.key] ~= true then
            bar.glow_on = nil
            bar.bg:Hide()
            bar.fill:Hide()
            bar.glow:Hide()
            bar.label:Hide()
        else
            local remaining, total = self.WARRIOR.get_debuff_remaining(
                warrior_debuff_duration[def.key], warrior_debuff_expiration[def.key],
                now, def.fallback_duration)
            if type(w) == "number" and w > 0 and total > 0 then
                local fraction = remaining / total
                if fraction < 0 then
                    fraction = 0
                elseif fraction > 1 then
                    fraction = 1
                end
                bar.fill:SetWidth(w * fraction)
            end
            local colour = db[def.color_option] or def.fallback_color
            if bar.color_applied ~= colour then
                bar.color_applied = colour
                bar.fill:SetVertexColor(self:convert_color(colour))
                bar.glow:SetVertexColor(self:convert_color(colour))
            end
            local label_value
            if def.label_mode == "stacks" then
                label_value = warrior_debuff_stacks[def.key] or 1
            else
                label_value = math.floor(remaining + 0.5)
            end
            if bar.label_value ~= label_value then
                bar.label_value = label_value
                bar.label:SetText(tostring(label_value))
            end
            local glow_on = self.WARRIOR.should_debuff_glow(remaining)
            if glow_on ~= bar.glow_on then
                bar.glow_on = glow_on
                if glow_on then
                    bar.glow:Show()
                else
                    bar.glow:Hide()
                end
            end
            place_warrior_bar(bar, vf, stack_y)
            bar.bg:Show()
            bar.fill:Show()
            bar.label:Show()
            stack_y = stack_y + WARRIOR_DEBUFF_HEIGHT + WARRIOR_BAR_STACK_GAP
        end
    end
    return stack_y
end

-- Overpower proc flash: a pulsing 1 px gold border around the bar plus the "OP" centre
-- marker while the dodge window is live (reference UpdateWarriorOverpowerFlash,
-- ClassMods.lua:1969-2035). The pulse alpha is written per frame like the reference;
-- the classic dodge window can only be armed through the combat log, so Retail
-- never shows this; Forever arms the same window through the Bloodthrill aura.
local function update_warrior_overpower_flash(self, vf, db, now)
    local edges = vf.warrior_overpower_edges
    local text = vf.warrior_overpower_text
    if not (edges and text) then
        return
    end
    local remaining = self.WARRIOR.get_overpower_remaining(self.warrior_overpower_proc_until, now)
    if db.show_warrior_overpower_flash == false or remaining == nil then
        if self.warrior_overpower_flash_on then
            self.warrior_overpower_flash_on = false
            for i = 1, #edges do
                edges[i]:Hide()
            end
            text:Hide()
        end
        return
    end
    if not self.warrior_overpower_flash_on then
        self.warrior_overpower_flash_on = true
        text:SetText("OP")
        text:Show()
    end
    local pulse = 0.5 + (0.5 * math.sin(now * ST.WARRIOR.hud_style.op_pulse_hz))
    local alpha = 0.25 + (0.45 * pulse)
    for i = 1, #edges do
        edges[i]:SetColorTexture(ST.WARRIOR.hud_style.op_edge_color[1], ST.WARRIOR.hud_style.op_edge_color[2],
            ST.WARRIOR.hud_style.op_edge_color[3], alpha)
        edges[i]:Show()
    end
end

-- Dual-wield desync alert (competitor-gaps W1): the OH-landing spark on the
-- MH bar. Default OFF (show_warrior_desync_alert ~= true: nil stays off like
-- the bank cue) and every swing read sits behind the toggle. Unknown hides:
-- no offhand table, no offhand weapon, a non-numeric stamp or speed, or an
-- OH landing outside the current MH swing. Verdict + pixel churn guards: the
-- spark only re-anchors when its pixel moves and only re-tints on a verdict
-- change. The st.warrior_guide nil-guard keeps a flavor without that module
-- inert instead of erroring (the slam band's pattern).
local function update_warrior_desync_alert(self, vf, db, now, w)
    local widgets = vf.warrior_desync
    if not widgets then
        return
    end
    local spark = widgets.spark
    if db.show_warrior_desync_alert ~= true then
        if self.warrior_desync_shown then
            self.warrior_desync_shown = false
            spark:Hide()
        end
        self.warrior_desync_verdict = nil
        spark.pixel = nil
        return
    end
    local verdict, fraction
    local mh = self.mainhand
    local oh = self.offhand
    if mh and oh and oh.has_weapon == true then
        local mh_remaining, oh_remaining
        if type(mh.ends_at) == "number" then
            mh_remaining = mh.ends_at - now
        end
        if type(oh.ends_at) == "number" then
            oh_remaining = oh.ends_at - now
        end
        local guide = st.warrior_guide
        if guide and guide.swing_sync_status and guide.swing_sync_fraction then
            verdict = guide.swing_sync_status(mh_remaining, oh_remaining)
            if verdict ~= nil then
                fraction = guide.swing_sync_fraction(mh_remaining, oh_remaining, mh.speed)
                if fraction == nil then
                    verdict = nil
                end
            end
        end
    end
    if verdict == nil or fraction == nil
        or type(w) ~= "number" or w <= 0 then
        if self.warrior_desync_shown then
            self.warrior_desync_shown = false
        end
        self.warrior_desync_verdict = nil
        spark.pixel = nil
        spark:Hide()
        return
    end
    local pixel = math.floor(fraction * w + 0.5)
    if pixel ~= spark.pixel then
        spark.pixel = pixel
        local x = pixel - 1
        if x < 0 then
            x = 0
        end
        spark:ClearAllPoints()
        spark:SetPoint("BOTTOMLEFT", vf, "BOTTOMLEFT", x, 0)
        spark:SetPoint("TOPLEFT", vf, "TOPLEFT", x, 0)
    end
    if verdict ~= self.warrior_desync_verdict then
        self.warrior_desync_verdict = verdict
        if verdict == "clash" then
            spark:SetVertexColor(self:convert_color(ST.WARRIOR.bar_style.desync_clash_color))
        else
            spark:SetVertexColor(self:convert_color(ST.WARRIOR.bar_style.desync_clean_color))
        end
    end
    if not self.warrior_desync_shown then
        self.warrior_desync_shown = true
    end
    spark:Show()
end

-- One throttled read pass (0.05 s) feeds the merged target scan and the player Shield
-- Block read; each scan only runs while at least one option that consumes it is on, so an
-- all-off configuration performs no aura reads at all. The bars then restack through the
-- shared slot walk: Shield Block (closest to the bar), Slam, then the five debuff bars in
-- the reference's restack order.
local function update_warrior_bars(self, vf, db, now, w)
    local any_debuff = false
    for i = 1, #warrior_debuff_defs do
        if db[warrior_debuff_defs[i].option] ~= false then
            any_debuff = true
            break
        end
    end
    local shield_block_on = db.show_warrior_shield_block_bar ~= false
    if (any_debuff or shield_block_on) and now >= (self.warrior_scan_at or 0) then
        self.warrior_scan_at = now + WARRIOR_SCAN_INTERVAL
        if any_debuff then
            scan_target_warrior_debuffs(now)
        end
        if shield_block_on then
            local duration, expiration = scan_player_shield_block(now)
            self.warrior_shield_block_duration = duration
            self.warrior_shield_block_expires = expiration
        else
            self.warrior_shield_block_duration = nil
            self.warrior_shield_block_expires = nil
        end
    end
    local stack_y = WARRIOR_BAR_BOTTOM_GAP
    stack_y = update_warrior_shield_block(self, vf, db, now, w, stack_y)
    stack_y = update_warrior_slam(self, vf, db, now, w, stack_y)
    update_warrior_debuff_bars(self, vf, db, now, w, stack_y)
end

-- Rampage upkeep badge: the stack count + refresh window beside the bar's right
-- edge (the Shamanistic Rage badge pattern in classes/shaman.lua). The aura scan
-- in on_aura_change owns the state, so this performs no client reads and stays
-- cheap: hidden while the buff is absent or elapsed, and the text is only re-set
-- when the readout actually changes. Default-on like the other trackers (the
-- option key reads nil until a config lane ships its default); an explicit false
-- hides the badge. Family-agnostic on purpose: a client without the buff never
-- shows it, so no family gate is needed (and Retail stays inert).
local function update_warrior_rampage_badge(self, vf, db, now)
    local badge = vf.warrior_rampage_text
    if not badge then
        return
    end
    if db.show_warrior_rampage_badge == false then
        self.warrior_rampage_text_shown = nil
        badge:Hide()
        return
    end
    local text = self.WARRIOR.get_rampage_display(
        self.warrior_rampage_stacks, self.warrior_rampage_expires, now)
    if text == nil then
        self.warrior_rampage_text_shown = nil
        badge:Hide()
        return
    end
    if self.warrior_rampage_text_shown ~= text then
        self.warrior_rampage_text_shown = text
        badge:SetText(text)
    end
    -- W3 tier colours: the badge recolours only on a tier change (the text
    -- re-set above is unaffected by it). tier is never nil on this path (a
    -- live badge always has stacks), so the lookup below always resolves.
    local tier = self.WARRIOR.get_rampage_tier(
        self.warrior_rampage_stacks, self.warrior_rampage_expires, now)
    if tier ~= self.warrior_rampage_tier_applied then
        self.warrior_rampage_tier_applied = tier
        badge:SetTextColor(self:convert_color(ST.WARRIOR.bar_style.rampage_tier_colors[tier]))
    end
    badge:Show()
end

-- W1 rage-bank cue (verify W1): the amber top edge + centred "BANK" while the
-- bank state holds in combat. Default OFF (show_warrior_bank_cue ~= true: nil
-- stays off like every other new toggle) and every client read sits behind the
-- toggle, so an all-off configuration reads nothing. Visibility only flips on
-- a transition; no per-frame colour or text write.
local function update_warrior_bank_cue(self, vf, db, now)
    local widgets = vf.warrior_bank
    if not widgets then
        return
    end
    if db.show_warrior_bank_cue ~= true then
        self.warrior_bank_shown = false
        widgets.edge:Hide()
        widgets.text:Hide()
        return
    end
    -- Player reads behind the toggle: an unreadable percentage never arms the
    -- state (see get_bank_state). Rage is the warrior's primary power read.
    local health_max = api.UnitHealthMax("player")
    local health = api.UnitHealth("player")
    local health_pct
    if type(health_max) == "number" and health_max > 0 and type(health) == "number" then
        health_pct = health / health_max * 100
    end
    local show = ST.WARRIOR.get_bank_state(health_pct, db.guide_execute_pct or 20,
        api.UnitPower("player"), self.in_combat) == true
    if show then
        self.warrior_bank_shown = true
        widgets.edge:Show()
        widgets.text:Show()
    else
        self.warrior_bank_shown = false
        widgets.edge:Hide()
        widgets.text:Hide()
    end
end

-- Battle Shout uptime badge: the "BS xxs" count-down beside the bar's right
-- edge, one widget above the rampage text. Default OFF
-- (show_warrior_battle_shout_badge ~= true: nil stays off). The capture rides
-- the aura walk regardless (it adds no client read); this toggles only the
-- drawing. Deliberately NOT cleared in on_combat_exit.
local function update_warrior_battle_shout_badge(self, vf, db, now)
    local badge = vf.warrior_battle_shout_text
    if not badge then
        return
    end
    if db.show_warrior_battle_shout_badge ~= true then
        self.warrior_battle_shout_text_shown = nil
        badge:Hide()
        return
    end
    -- W2 Commanding suppression: while the greater shout covers Battle Shout the
    -- badge must not prompt it. The same widget shows the Commanding countdown
    -- instead (the new HUD home - the six-slot guide contract is full, so no
    -- guide rule carries this; nil-guard keeps a flavor without warrior_guide
    -- on the legacy path). Toggle nil = off (legacy Battle Shout readout).
    local guide = st.warrior_guide
    if guide and guide.should_suppress_battle_shout
        and guide.should_suppress_battle_shout(
            self.warrior_commanding_expires, now,
            db.show_warrior_commanding_suppression) == true then
        local cmd_text = guide.get_commanding_display
            and guide.get_commanding_display(self.warrior_commanding_expires, now)
        if cmd_text == nil then
            self.warrior_battle_shout_text_shown = nil
            badge:Hide()
            return
        end
        if self.warrior_battle_shout_text_shown ~= cmd_text then
            self.warrior_battle_shout_text_shown = cmd_text
            badge:SetText(cmd_text)
        end
        badge:Show()
        return
    end
    local text = self.WARRIOR.get_battle_shout_display(
        self.warrior_battle_shout_expires, now)
    if text == nil then
        self.warrior_battle_shout_text_shown = nil
        badge:Hide()
        return
    end
    if self.warrior_battle_shout_text_shown ~= text then
        self.warrior_battle_shout_text_shown = text
        badge:SetText(text)
    end
    badge:Show()
end

-- Per-frame warrior visuals, called from ST:onupdate_common via the generic class hook.
-- The mainhand frame's OnUpdate only ticks while the bar is shown, so the widgets freeze
-- with the bar. Deliberately cheap and nil-safe: no LibStub calls, no allocations. NOTE:
-- deliberately not gated on st.is_mainline - the Forever client is Mainline-code but
-- shows all of this; the Overpower flash stays inert there because nothing can arm it.
function ST.WARRIOR.on_bar_update(self, hand)
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
    if type(db) ~= "table" then
        -- PROPER: every widget below reads this table; with no profile there is
        -- nothing configured to draw. The swing bars still render (bars.lua owns
        -- them with its own guards), so skipping the tick hides nothing live.
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
    -- driver frame, so this is cheap). Deliberately not gated on st.is_mainline:
    -- the Forever client must show the HUD, and the Retail stand-in simply never
    -- swings (the paladin hooks it the same way in classes/paladin.lua).
    -- Runs after the guide tick above: the shared per-frame order is guide then
    -- HUD in all six class modules (deep-audit F8).
    if st.hud then
        st.hud.on_bar_update(self, hand)
    end
    -- W6 execute-phase sampler: the live feed for the warrior_execute drill (the
    -- options Execute report reads the rolling log session-independently).
    -- Deliberately not gated on st.is_mainline: the Forever client must track
    -- it, and the Retail stand-in never reports a swing (an unknown target HP
    -- hides the sampler there too).
    ST.WARRIOR.track_execute_phase(self)
    local vf = self:get_visuals_frame(hand)
    if not vf then
        return
    end
    if not vf.warrior_debuff then
        self.WARRIOR.setup_warrior_visuals(self)
        if not vf.warrior_debuff then
            return
        end
    end
    local now = api.get_time()
    local w = self:get_bar_visuals_width_and_height(hand)
    update_warrior_overpower_flash(self, vf, db, now)
    update_warrior_desync_alert(self, vf, db, now, w)
    update_warrior_bars(self, vf, db, now, w)
    update_warrior_rampage_badge(self, vf, db, now)
    -- Build-out round 1: the W1 bank cue and the Battle Shout badge below the
    -- rampage call, in the same draw pass (visibility-only churn for the cue).
    update_warrior_bank_cue(self, vf, db, now)
    update_warrior_battle_shout_badge(self, vf, db, now)
end

--=========================================================================================
-- Next Action Guide: the warrior provider for the generic guide frame
--=========================================================================================
-- Implements the frozen ST.<CLASS>.guide contract documented in nextaction_ui.lua's
-- header. The decision model is the pure st.warrior_guide module (warrior_guide.lua; its
-- docblock is the frozen spec), the live reads live in gather_guide_inputs, and this
-- table is the last piece of glue: the slot set, the gather/evaluate pair and the static
-- captions. Default OFF (nextaction_enabled=false in config_presets.lua): a wrong prompt
-- is worse than none, so the owner enables it after in-client verification.
--
-- SIX slots on the base set (op, execute, slam, hs, cleave + the Hamstring
-- weave filler - the contract allows six, and the base set had room). Every
-- slot carries a cooldown_key: the swipe follows the ability's own
-- client-reported cooldown where one exists (the gather's GCD-echo rule keeps
-- a running GCD out of it). On the classic families these abilities mostly
-- have no cooldown of their own, so the swipes typically stay clear; the
-- inputs still ride the frozen name set in full. Hamstring carries rule W on
-- Era-base (threshold 80 live); on the base/Forever set the slot shows the
-- GCD swipe and the HUD state until the toggle lane ships the prompt.
--
-- TBC fury (st.family == "TBC") swaps in op, execute, slam, hs, bt, ww,
-- sunder. The cleave slot is the one replaced: no rule ever
-- outputs "cleave" (the slot only ever showed the Cleave swipe, and Cleave has no
-- cooldown of its own on the classic line), while Bloodthirst and Whirlwind are the
-- TBC core. Sunder upkeep (rule S) takes the seventh slot; the TBC HUD keeps
-- the six-ability row (guide-only sunder until the HUD lane mirrors it). The
-- cleave readers stay in the gather (cost/queue/cooldown), so the
-- queued-Cleave RIDE path is unchanged and a future slot re-add needs no new reads.
--
-- Era fury (st.family == "ERA") uses op, execute, slam, hs, bt, ww, hamstring:
-- BT/WW are vanilla spells that exist on Era. Same replacement, same reader
-- retention; the Hamstring weave filler (rule W) takes the seventh slot. SoD (ERA + SoD runes, frozen at post_init) swaps in
-- execute, slam, hs, bt, ww, raging_blow, rend, op: Overpower returns for
-- the stance-dance source (rule D, gated by aura 426969 UNCONFIRMED),
-- Rend upkeep (rule R, 11574 + rune 412507 CONFIRMED, Blood Frenzy) takes
-- the seventh slot, and Raging Blow stays the rune filler after WW.
--
-- Wrath fury (st.family == "WRATH", no Mortal Strike known) uses the same six
-- keys as TBC/Era (op, execute, slam, hs, bt, ww): the fury priority names
-- exactly these and the conditional Rend stays tracker-only. Wrath arms
-- (Mortal Strike known) swaps in op, execute, rend, ms, bladestorm, hs:
-- BT/WW/Cleave carry no arms rule and Slam is the deferred early-tier filler
-- (its readers stay, its rule stays off, HS covers the filler window), while
-- Rend upkeep, Mortal Strike and Bladestorm take their places. Both Wrath sets
-- and the SoD set are picked at post_init from the frozen spec/rune probe (see
-- resolve_guide_slots); a respec or rune change needs /reload.
--
-- Forever (st.family == "FOREVER") carries op, execute, slam, hs, cleave,
-- hamstring, sunder: Victory Rush reuses the execute slot (the engine's
-- victory_rush bypass names "execute", so no extra slot is needed),
-- Bloodthrill reuses the OP dodge-window reader (it arms the same window),
-- Hamstring rides the sixth slot (the Forever 7373 weave filler) and Sunder
-- upkeep (rule S, stacks < 5 / refresh <= 10 s) takes the seventh. Forever
-- Rend upkeep (11574, <= 3 s) rides the gather as an input only - no slot
-- names "rend" on Forever yet: filed (toggle + options wiring OUT).
--
-- Rampage (TBC fury "stack to 5 then upkeep"): tracked as the upkeep badge above
-- (stack count + refresh window). The stack count is plumbed through
-- on_aura_change (a second aura id alongside Blood Surge) into
-- warrior_rampage_stacks / warrior_rampage_expires; the badge shows it while
-- the buff is live. No guide rule and no display slot for Rampage (the sets
-- above are full without it), so the guide never prompts it.
-- Plug-in point for a future rule: new rampage_stacks gather inputs in
-- gather_guide_inputs below, a rule above Bloodthirst, and a new slot.

-- One reused input table: no per-frame allocations on the guide tick (the frame passes
-- its own reused table through gather; this one serves direct calls).
ST.WARRIOR.guide_inputs = {}

-- The current Mortal Strike / Rend / Hamstring / Sunder ranks for the guide (resolved
-- once, like the HS/Cleave caches; the Slam rank lives with the other spell data
-- above, because the Slam cast bar's fallback duration reads it too).
local ms_current_id
local rend_current_id
local hamstring_current_id
local sunder_current_id

-- Live cooldown for the guide, with the client's GCD echo filtered: GetSpellCooldown
-- reports whichever cooldown ends later, so a reading of 1.51 s or less is a GCD echo
-- and never one of these abilities' own cooldowns. Returns remaining seconds (>= 0) and
-- the client-reported duration, or (0, nil) when there is no real cooldown to show.
local function get_guide_cooldown(spell)
    if not spell then
        return 0, nil
    end
    -- Name-vs-id rule: the query is the localized name on TBC, the numeric
    -- id elsewhere.
    local start_time, duration = api.GetSpellCooldown(spell_query(spell))
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
-- slam / hs / cleave at the client's current rank once the spell data is live. Overpower
-- keeps 7384 (the id the rest of the module's matcher uses) and Execute keeps the spec's
-- 5308; neither has a cooldown of its own on the target families, so their cooldown and
-- swipe reads simply stay clear there. swipe_duration is the display fallback for a
-- swipe whose length the client never reported.
local guide_slot_op = { key = "op", spell_id = overpower_id, cooldown_key = "op",
    swipe_duration = 1.5 }
local guide_slot_execute = { key = "execute", spell_id = 5308, cooldown_key = "execute",
    swipe_duration = 1.5 }
local guide_slot_slam = { key = "slam", spell_id = 1464, cooldown_key = "slam",
    swipe_duration = 1.5 }
local guide_slot_hs = { key = "hs", spell_id = 78, cooldown_key = "hs",
    swipe_duration = 1.5 }
local guide_slot_cleave = { key = "cleave", spell_id = 845, cooldown_key = "cleave",
    swipe_duration = 1.5 }
-- Hamstring weave filler (sim-cited ids 7373 / 18499, rank-1 fallback 7373,
-- re-pointed like slam through hamstring_ids; the base/Forever set and the
-- Era set name it - rule W fires on Era-base (80 live), the other sets keep
-- the slot for the swipe until their number/toggle lands).
local guide_slot_hamstring = { key = "hamstring", spell_id = 7373, cooldown_key = "hamstring",
    swipe_duration = 1.5 }
local guide_slot_bt = { key = "bt", spell_id = 23881, cooldown_key = "bt",
    swipe_duration = 1.5 }
local guide_slot_ww = { key = "ww", spell_id = 1680, cooldown_key = "ww",
    swipe_duration = 1.5 }
-- Arms / SoD slots: Rend (rank-1 fallback 772, re-pointed like slam; its swipe
-- follows the debuff window the gather feeds, not a cooldown), Mortal Strike
-- (rank-1 fallback 12294, re-pointed through ms_ids), Bladestorm (63784; the 90 s
-- swipe fallback NEEDS IN-CLIENT CONFIRMATION) and Raging Blow (402911; 8 s).
local guide_slot_rend = { key = "rend", spell_id = 772, cooldown_key = "rend",
    swipe_duration = 1.5 }
local guide_slot_ms = { key = "ms", spell_id = 12294, cooldown_key = "ms",
    swipe_duration = 6 }
local guide_slot_bladestorm = { key = "bladestorm", spell_id = bladestorm_id,
    cooldown_key = "bladestorm", swipe_duration = 90 }
local guide_slot_raging = { key = "raging_blow", spell_id = raging_blow_id,
    cooldown_key = "raging_blow", swipe_duration = 8 }
-- Sunder upkeep slot (TBC + Forever APL groups): rank-1 fallback 7386,
-- re-pointed through sunder_armor_ids like slam; its swipe follows the
-- upkeep window the gather feeds (stacks + countdown), not a cooldown -
-- the Rend slot's shape.
local guide_slot_sunder = { key = "sunder", spell_id = 7386, cooldown_key = "sunder",
    swipe_duration = 1.5 }


-- The slot set is picked once at load: the TBC fury set on the TBC family, the
-- Era fury set on the ERA family, the
-- Wrath fury set on the WRATH family, the Forever set on the FOREVER family,
-- the base six-slot
-- set everywhere else (op, execute, slam, hs, cleave + the Hamstring weave
-- filler - unknown families keep the frozen shape; Retail keeps the
-- same descriptors but the guide short-circuits inert).
-- post_init re-picks through resolve_guide_slots (arms / SoD / Forever shapes)
-- once the spell data and the spec/rune probes answer.
local guide_slots_base = { guide_slot_op, guide_slot_execute, guide_slot_slam,
    guide_slot_hs, guide_slot_cleave, guide_slot_hamstring }
local guide_slots_tbc = { guide_slot_op, guide_slot_execute, guide_slot_slam,
    guide_slot_hs, guide_slot_bt, guide_slot_ww, guide_slot_sunder,
    WARRIOR_UTILITY.slots.death_wish_tbc, WARRIOR_UTILITY.slots.recklessness, WARRIOR_UTILITY.slots.sweeping_strikes,
    WARRIOR_UTILITY.slots.bloodrage, WARRIOR_UTILITY.slots.berserker_rage, WARRIOR_UTILITY.slots.battle_shout_tbc,
    WARRIOR_UTILITY.slots.battle_stance, WARRIOR_UTILITY.slots.berserker_stance }
local guide_slots_era = { guide_slot_op, guide_slot_execute, guide_slot_slam,
    guide_slot_hs, guide_slot_bt, guide_slot_ww, guide_slot_hamstring,
    WARRIOR_UTILITY.slots.death_wish_era, WARRIOR_UTILITY.slots.blood_fury, WARRIOR_UTILITY.slots.bloodrage,
    WARRIOR_UTILITY.slots.berserker_rage, WARRIOR_UTILITY.slots.battle_shout_era, WARRIOR_UTILITY.slots.berserker_stance }
local guide_slots_wrath_fury = { guide_slot_op, guide_slot_execute, guide_slot_slam,
    guide_slot_hs, guide_slot_bt, guide_slot_ww,
    WARRIOR_UTILITY.slots.bloodrage, WARRIOR_UTILITY.slots.shattering_throw, WARRIOR_UTILITY.slots.heroic_throw,
    WARRIOR_UTILITY.slots.berserker_stance }
local guide_slots_wrath_arms = { guide_slot_op, guide_slot_execute, guide_slot_rend,
    guide_slot_ms, guide_slot_bladestorm, guide_slot_hs,
    WARRIOR_UTILITY.slots.bloodrage, WARRIOR_UTILITY.slots.thunder_clap }
local guide_slots_sod = { guide_slot_execute, guide_slot_slam,
    guide_slot_hs, guide_slot_bt, guide_slot_ww, guide_slot_raging,
    guide_slot_rend, guide_slot_op,
    WARRIOR_UTILITY.slots.berserker_stance, WARRIOR_UTILITY.slots.death_wish_era, WARRIOR_UTILITY.slots.recklessness,
    WARRIOR_UTILITY.slots.battle_stance }
local guide_slots_forever = { guide_slot_op, guide_slot_execute, guide_slot_slam,
    guide_slot_hs, guide_slot_cleave, guide_slot_hamstring, guide_slot_sunder,
    WARRIOR_UTILITY.slots.death_wish_era, WARRIOR_UTILITY.slots.recklessness, WARRIOR_UTILITY.slots.sweeping_strikes,
    WARRIOR_UTILITY.slots.bloodrage, WARRIOR_UTILITY.slots.battle_shout_era, WARRIOR_UTILITY.slots.battle_stance }

-- Resolve the guide icons to the client's current ranks; called once from post_init,
-- before the shared frame builds its icons. A rank that does not resolve keeps the
-- rank-1 fallback above.
function ST.WARRIOR.resolve_guide_icons()
    hs_current_id = resolve_rank(hs_ids, hs_current_id)
    cleave_current_id = resolve_rank(cleave_ids, cleave_current_id)
    slam_current_id = resolve_rank(slam_ids, slam_current_id)
    bt_current_id = resolve_rank(bt_ids, bt_current_id)
    ww_current_id = resolve_rank(ww_ids, ww_current_id)
    ms_current_id = resolve_rank(ms_ids, ms_current_id)
    rend_current_id = resolve_rank(rend_ids, rend_current_id)
    hamstring_current_id = resolve_rank(hamstring_ids, hamstring_current_id)
    sunder_current_id = resolve_rank(sunder_armor_ids, sunder_current_id)
    if hs_current_id then
        guide_slot_hs.spell_id = hs_current_id
    end
    if cleave_current_id then
        guide_slot_cleave.spell_id = cleave_current_id
    end
    if slam_current_id then
        guide_slot_slam.spell_id = slam_current_id
    end
    if bt_current_id then
        guide_slot_bt.spell_id = bt_current_id
    end
    if ww_current_id then
        guide_slot_ww.spell_id = ww_current_id
    end
    if ms_current_id then
        guide_slot_ms.spell_id = ms_current_id
    end
    if rend_current_id then
        guide_slot_rend.spell_id = rend_current_id
    end
    if hamstring_current_id then
        guide_slot_hamstring.spell_id = hamstring_current_id
    end
    if sunder_current_id then
        guide_slot_sunder.spell_id = sunder_current_id
    end
end

-- Rend debuff window for the arms upkeep (target scan, arms only, so every other
-- branch pays no aura reads here). Matches by rank id, the client's localized
-- names, then the literal English fallback; the aura must belong to the
-- player. Returns remaining, duration - nil when missing/unknown, which prompts
-- (the druid rip/rake nil rule). The 15 s fallback is the wotlk Rend duration
-- (wowhead.com/wotlk/spell=47465).
local function get_rend_debuff_window(now)
    local localized = nil
    local index = 1
    while index <= 40 do
        local name, _, _, _, aura_duration, aura_expiration, source, _, _, spell_id =
            api.UnitAura("target", index, "HARMFUL")
        -- No early break (R2): a secret entry degrades to absent and the walk
        -- continues past it.
        if name ~= nil then
            if source == "player" or source == nil then
                local match = (type(spell_id) == "number" and rend_ids[spell_id] ~= nil)
                    or name == "Rend"
                if not match then
                    if localized == nil then
                        localized = {}
                        for id in pairs(rend_ids) do
                            local resolved = api.GetSpellInfo(id)
                            if resolved then
                                localized[resolved] = true
                            end
                        end
                    end
                    match = localized[name] == true
                end
                if match then
                    return ST.WARRIOR.get_debuff_remaining(
                        aura_duration, aura_expiration, now, 15)
                end
            end
        end
        index = index + 1
    end
    return nil, nil
end

-- Sunder Armor upkeep window for the TBC + Forever guide (single-target APL
-- groups): the player's stack count and the debuff countdown. Matches by rank
-- id, the client's localized names, then the literal English fallback; the
-- aura must belong to the player. Returns stacks, remaining, duration - nil
-- when missing/unknown (the engine groundwork consumes these once a slot
-- exists; today no rule reads them). The 30 s fallback is the reference's own
-- Sunder duration (warrior_debuff_defs above).
local function get_sunder_upkeep_window(now)
    local localized = nil
    local index = 1
    while index <= 40 do
        local name, _, count, _, aura_duration, aura_expiration, source, _, _, spell_id =
            api.UnitAura("target", index, "HARMFUL")
        -- No early break (R2): a secret entry degrades to absent and the walk
        -- continues past it.
        if name ~= nil then
            if source == "player" or source == nil then
                local match = (type(spell_id) == "number" and sunder_armor_ids[spell_id] ~= nil)
                    or name == "Sunder Armor"
                if not match then
                    if localized == nil then
                        localized = {}
                        for id in pairs(sunder_armor_ids) do
                            local resolved = api.GetSpellInfo(id)
                            if resolved then
                                localized[resolved] = true
                            end
                        end
                    end
                    match = localized[name] == true
                end
                if match then
                    local remaining, duration = ST.WARRIOR.get_debuff_remaining(
                        aura_duration, aura_expiration, now, 30)
                    return tonumber(count), remaining, duration
                end
            end
        end
        index = index + 1
    end
    return nil, nil, nil
end

-- Live inputs for the pure engine, written into the caller-owned reused table. Every
-- field of the frozen input set is written on every call, so no stale value can survive
-- between ticks; nil means "the client did not answer".
function ST.WARRIOR.gather_guide_inputs(self, out)
    local inputs = out or ST.WARRIOR.guide_inputs
    local now = api.get_time()
    local d = self.mainhand
    local gcd = self.gcd
    local db = self:get_class_table() or {}
    -- PROPER: {} reads every tunable as nil, which is exactly the engine's
    -- documented default for each; the live api reads below still run, so the
    -- guide degrades to defaults instead of dying.

    -- Swing and GCD, in the api.get_time() domain (ends_at and the GCD stamp share it).
    inputs.speed = (d and d.speed) or 0
    inputs.swing_remaining = math.max(0, ((d and d.ends_at) or now) - now)
    inputs.gcd_remaining = (gcd and gcd.expires and math.max(0, gcd.expires - now)) or 0

    -- The offhand swing cycle (the Heroic Strike / Cleave queue drill's own
    -- input: the addon's OWN swing data, the client reading the sim is silent
    -- about). The offhand bar's next landing (ends_at) and its weapon speed.
    -- A player without an offhand weapon (a shield, or one hand only) has no
    -- offhand cycle at all: the readings stay nil and the queue drill has no
    -- decision to grade (unknown hides, never a guess).
    local oh = self.offhand
    if oh and oh.has_weapon == true and type(oh.ends_at) == "number"
        and type(oh.speed) == "number" and oh.speed > 0 then
        inputs.offhand_swing_remaining = math.max(0, oh.ends_at - now)
        inputs.offhand_swing_speed = oh.speed
        inputs.dual_wielding = true
    else
        inputs.offhand_swing_remaining = nil
        inputs.offhand_swing_speed = nil
        inputs.dual_wielding = nil
    end

    -- Rage, the on-next-attack state and the tracker state the rule matrix consumes.
    inputs.rage = api.UnitPower("player")
    inputs.hs_queued = self.hs_queued and true or false
    inputs.cleave_queued = self.cleave_queued and true or false
    inputs.insufficient_rage = self.insufficient_rage and true or false
    inputs.has_bloodsurge = self.has_bloodsurge and true or false
    inputs.slam_casting = self.warrior_slam_casting and true or false
    inputs.overpower_remaining = self.WARRIOR.get_overpower_remaining(
        self.warrior_overpower_proc_until, now)

    -- Target health percentage; nil = unknown (no target, a dead unit, or a client that
    -- does not answer the health reads).
    inputs.target_health_pct = nil
    local health_max = api.UnitHealthMax("target")
    if type(health_max) == "number" and health_max > 0 then
        local health = api.UnitHealth("target")
        if type(health) == "number" then
            inputs.target_health_pct = health / health_max * 100
        end
    end

    -- Rage costs of the on-next-attack abilities through the client's own current ranks
    -- (the rank caches make this a lookup once resolved; a nil cost means the client
    -- cannot answer, and the engine withholds the HS prompt).
    hs_current_id = resolve_rank(hs_ids, hs_current_id)
    cleave_current_id = resolve_rank(cleave_ids, cleave_current_id)
    local costs = hs_current_id and api.GetSpellPowerCost(spell_query(hs_current_id))
    inputs.hs_cost = rage_cost_of(costs)
    costs = cleave_current_id and api.GetSpellPowerCost(spell_query(cleave_current_id))
    inputs.cleave_cost = rage_cost_of(costs)

    -- Cooldowns, GCD echo filtered (op/execute feed the rule matrix, the rest feed the
    -- slot swipes). Both halves of every pair are written every call.
    inputs.op_remaining, inputs.op_duration = get_guide_cooldown(overpower_id)
    inputs.execute_remaining, inputs.execute_duration = get_guide_cooldown(5308)
    slam_current_id = resolve_rank(slam_ids, slam_current_id)
    inputs.slam_remaining, inputs.slam_duration = get_guide_cooldown(slam_current_id)
    inputs.hs_remaining, inputs.hs_duration = get_guide_cooldown(hs_current_id)
    inputs.cleave_remaining, inputs.cleave_duration = get_guide_cooldown(cleave_current_id)
    -- Hamstring weave filler swipe (no cooldown of its own on the classic line,
    -- like Overpower/Execute - the slot shows the running GCD). Resolved through
    -- the client's own ranks so the TBC 18499 rank counts; an unlearned
    -- Hamstring resolves to no spell and reads ready (0, nil), never an error.
    hamstring_current_id = resolve_rank(hamstring_ids, hamstring_current_id)
    inputs.hamstring_remaining, inputs.hamstring_duration = get_guide_cooldown(hamstring_current_id)

    -- TBC fury core: Bloodthirst/Whirlwind cooldowns+costs and the HS dump floor.
    -- Nil on every other family (no reader there), so the new engine rules - which
    -- require known readings - stay inert outside TBC. Every field is written on
    -- every call, so no stale value can survive between ticks.
    -- Era feeds the same BT/WW readers (vanilla spells) with its own floor (30),
    -- window (2.5 s) and Execute-spam flag; every other family feeds nil for all
    -- of these, keeping the legacy behaviour and Retail inertness exactly.
    if is_tbc_guide then
        bt_current_id = resolve_rank(bt_ids, bt_current_id)
        ww_current_id = resolve_rank(ww_ids, ww_current_id)
        costs = bt_current_id and api.GetSpellPowerCost(spell_query(bt_current_id))
        inputs.bt_cost = rage_cost_of(costs)
        costs = ww_current_id and api.GetSpellPowerCost(spell_query(ww_current_id))
        inputs.ww_cost = rage_cost_of(costs)
        inputs.bt_remaining, inputs.bt_duration = get_guide_cooldown(bt_current_id)
        inputs.ww_remaining, inputs.ww_duration = get_guide_cooldown(ww_current_id)
        -- TBC fury rage management: Heroic Strike dumps only with rage to spare
        -- (40+: tbc-new fury APL gates HS 29707 on currentRage >= 40 outside
        -- Execute; DW arms gates 29707 on 40, 2H arms on 80 - the fury set
        -- carries 40), so Bloodthirst (30 rage) / Whirlwind (25 rage) are
        -- never starved. The HS-cancel cue is armed here too: cancel a queued
        -- Heroic Strike/Cleave before Execute (don't spend the 15 rage). Nil
        -- on every other family (see below), so the engine keeps its legacy
        -- shape there.
        inputs.hs_rage_floor = 40
        inputs.core_reserve_window = nil
        inputs.execute_spam = nil
        inputs.hs_cancel_cue = true
        -- The APL's execute-phase clause on the dump: the tbc-new fury APL gates
        -- its Heroic Strike row 29707 on NOT being inside the execute phase
        -- (wowsims/tbc-new ui/specs/warrior/dps/apls/fury.apl.json [18] - the row
        -- is `numberTargets == 1 AND NOT isExecutePhase E20 AND currentRage >=
        -- 40`), so inside the phase the dump is not the APL's move. The phase
        -- read EXISTS (the target's health fraction against the class's execute
        -- percentage - the same read the Execute rule uses), so the gate is armed
        -- here and the engine withholds the dump inside the phase. Armed on this
        -- family only: the Era APL's row explicitly ALLOWS the dump inside the
        -- phase (wowsims/classic ui/warrior/apls/dps_no_reck.apl.json [18] -
        -- `currentRage >= 40 OR isExecutePhase E20`) and the SoD / WotLK APLs
        -- carry no such clause on their Heroic Strike row.
        inputs.execute_phase_dump_gate = true
    elseif is_era_guide then
        bt_current_id = resolve_rank(bt_ids, bt_current_id)
        ww_current_id = resolve_rank(ww_ids, ww_current_id)
        costs = bt_current_id and api.GetSpellPowerCost(spell_query(bt_current_id))
        inputs.bt_cost = rage_cost_of(costs)
        costs = ww_current_id and api.GetSpellPowerCost(spell_query(ww_current_id))
        inputs.ww_cost = rage_cost_of(costs)
        inputs.bt_remaining, inputs.bt_duration = get_guide_cooldown(bt_current_id)
        inputs.ww_remaining, inputs.ww_duration = get_guide_cooldown(ww_current_id)
        -- Era fury rage management: Heroic Strike dumps only with rage to spare
        -- (40+) and 2-3 s until next BT/WW (2.5 s buffer), so Bloodthirst
        -- (30 rage) / Whirlwind (25 rage) are never starved; Execute spams
        -- below 20 % with no reservation against the core (unlike TBC).
        -- SoD (frozen rune probe) replaces the 30 floor with 60: Consumed by
        -- Rage pooling outranks the dump. Window and spam carry over (2.5 s,
        -- spam - in-game to confirm the SoD window).
        inputs.hs_rage_floor = ERA_HS_FLOOR
        if self.warrior_is_sod == true then
            inputs.hs_rage_floor = 60
        end
        inputs.core_reserve_window = ERA_CORE_RESERVE_WINDOW
        inputs.execute_spam = true
        inputs.hs_cancel_cue = nil
        -- No execute-phase gate on the dump: the Era APL's Heroic Strike row
        -- ALLOWS the dump inside the execute phase (wowsims/classic
        -- ui/warrior/apls/dps_no_reck.apl.json [18] - `currentRage >= 40 OR
        -- isExecutePhase E20`), and the SoD branch's own row (phase_6_dw.apl.json
        -- [8]) carries no phase clause at all.
        inputs.execute_phase_dump_gate = nil
    elseif is_wrath_guide then
        if self.warrior_is_arms == true then
            -- Arms runs no BT/WW core: the readers stay nil so the HS dump
            -- never reserves against abilities arms never casts (the upkeep /
            -- cooldown readers live in the shared tail below).
            inputs.bt_cost = nil
            inputs.ww_cost = nil
            inputs.bt_remaining = nil
            inputs.bt_duration = nil
            inputs.ww_remaining = nil
            inputs.ww_duration = nil
        else
            bt_current_id = resolve_rank(bt_ids, bt_current_id)
            ww_current_id = resolve_rank(ww_ids, ww_current_id)
            costs = bt_current_id and api.GetSpellPowerCost(spell_query(bt_current_id))
            inputs.bt_cost = rage_cost_of(costs)
            costs = ww_current_id and api.GetSpellPowerCost(spell_query(ww_current_id))
            inputs.ww_cost = rage_cost_of(costs)
            inputs.bt_remaining, inputs.bt_duration = get_guide_cooldown(bt_current_id)
            inputs.ww_remaining, inputs.ww_duration = get_guide_cooldown(ww_current_id)
        end
        -- Wrath rage management (both specs): Heroic Strike dumps only with rage
        -- to spare (50+, TBC-carried until in-client tuning). The reserve window
        -- stays the 1.5 s engine default (nil); Execute never spams against the
        -- core on fury (nil - rule F demotes it instead) and needs no
        -- reservation on arms (nil - arms runs no core).
        inputs.hs_rage_floor = 50
        inputs.core_reserve_window = nil
        inputs.execute_spam = nil
        inputs.hs_cancel_cue = nil
        -- No execute-phase gate on the dump: neither WotLK APL carries a Heroic
        -- Strike row (the fury APL's execute-phase row is Execute 47471 itself -
        -- wowsims/wotlk ui/warrior/apls/fury.apl.json [12]).
        inputs.execute_phase_dump_gate = nil
    else
        inputs.bt_cost = nil
        inputs.ww_cost = nil
        inputs.bt_remaining = nil
        inputs.bt_duration = nil
        inputs.ww_remaining = nil
        inputs.ww_duration = nil
        inputs.hs_rage_floor = nil
        inputs.core_reserve_window = nil
        inputs.execute_spam = nil
        inputs.hs_cancel_cue = nil
        -- The Forever APL's execute-phase clause on the dump: its Heroic Strike
        -- row 25286 is gated on NOT being inside the execute phase (wowsims/
        -- forever ui/specs/warrior/dps/apls/arms.apl.json [27] - `NOT
        -- isExecutePhase E20 AND currentRage >= 90`), so inside the phase the
        -- dump is not the APL's move. The phase read is the one the Execute rule
        -- already uses (the target's health fraction). Nil on every other family
        -- (the base shape has no APL to carry the clause).
        inputs.execute_phase_dump_gate = is_forever_guide and true or nil
    end

    -- Forever Victory Rush (UNCONFIRMED id + name): id-known or name-known
    -- and currently usable reads as ready (the window after a killing blow),
    -- feeding the engine's victory_rush Execute bypass. Nil on every other
    -- family and whenever neither probe answers, so the bypass stays inert
    -- there exactly like before. Written on every call, like every other
    -- frozen input.
    inputs.victory_rush = nil
    if is_forever_guide then
        local vr_known = is_spell_known_query(WARRIOR_VICTORY_RUSH_SPELL_ID)
            or type(api.GetSpellInfo(WARRIOR_VICTORY_RUSH_NAME)) == "string"
        if vr_known then
            local vr_name = api.GetSpellInfo(WARRIOR_VICTORY_RUSH_SPELL_ID)
                or WARRIOR_VICTORY_RUSH_NAME
            local ok, usable = pcall(api.IsSpellUsable, vr_name)
            if ok and usable == true then
                inputs.victory_rush = true
            end
        end
    end

    -- Execute threshold from the options (5-35 %, default 20).
    inputs.execute_pct = db.guide_execute_pct or 20

    -- Wrath / SoD branch tail: every field below is written on every call on
    -- every family (nil where the branch does not apply), so no stale value can
    -- survive between ticks and legacy families keep their exact shape plus
    -- nils. The flags freeze with the slots at post_init (see
    -- resolve_guide_slots), so the engine can never name an undeclared slot.
    local frozen_arms = is_wrath_guide and self.warrior_is_arms == true
    local frozen_sod = self.warrior_is_sod == true
    if frozen_arms then
        inputs.wrath_arms = true
    else
        inputs.wrath_arms = nil
    end
    if is_wrath_guide and not frozen_arms then
        inputs.wrath_fury = true
    else
        inputs.wrath_fury = nil
    end
    if frozen_sod then
        inputs.sod = true
    else
        inputs.sod = nil
    end
    inputs.sudden_death = self.has_sudden_death and true or nil
    inputs.tfb = self.has_tfb and true or nil
    -- Hamstring weave filler known (post_init-frozen): rule W's input; nil
    -- everywhere the spellbook lacks it. The threshold below decides which
    -- family prompts.
    if self.warrior_has_hamstring == true then
        inputs.hamstring_known = true
    else
        inputs.hamstring_known = nil
    end
    -- Hamstring weave threshold (Era-base 80, sim-cited): rule W fires only
    -- where the provider feeds a number. Nil everywhere else (no number
    -- cited / toggle-gated), so the weave rule stays dormant there until
    -- the options lane ships the tuning. The engine-constant read is
    -- nil-guarded (a flavor without warrior_guide keeps the legacy shape).
    if is_era_guide and self.warrior_is_sod ~= true
        and st.warrior_guide
        and type(st.warrior_guide.HAMSTRING_RAGE_THRESHOLD_ERA) == "number" then
        inputs.hamstring_rage_threshold =
            st.warrior_guide.HAMSTRING_RAGE_THRESHOLD_ERA
    else
        inputs.hamstring_rage_threshold = nil
    end
    -- Rend upkeep enable outside arms (SoD rune-gated, Forever toggle-gated):
    -- rule R fires only where this is exactly true. The SoD branch is the
    -- Blood Frenzy rune 412507 (operator-confirmed in-client 2026-10-19). The
    -- Forever branch is the player's own toggle (W-15): the key ships in
    -- option_tables.lua (the warrior panel, order 4.132) and reads as == true
    -- here, so nil and false both leave the rule dormant - off by default,
    -- because the rule has never run on that client.
    if inputs.sod == true and self.warrior_has_sod_rend_rune == true then
        inputs.rend_upkeep_enabled = true
    elseif is_forever_guide and db.guide_forever_rend_upkeep == true then
        inputs.rend_upkeep_enabled = true
    else
        inputs.rend_upkeep_enabled = nil
    end

    -- Arms upkeep + cooldown readers (nil everywhere else). Rend is a target
    -- scan on the upkeep branches, so every other branch pays no aura reads
    -- here. Forever shares the Rend window reader (its weave upkeep rides the
    -- toggle read above; rule R stays dormant there while the toggle is off);
    -- SoD feeds the same window into the live rule R.
    if inputs.wrath_arms or is_forever_guide or inputs.sod then
        inputs.rend_remaining, inputs.rend_duration =
            get_rend_debuff_window(now)
    else
        inputs.rend_remaining, inputs.rend_duration = nil, nil
    end
    if inputs.wrath_arms then
        ms_current_id = resolve_rank(ms_ids, ms_current_id)
        inputs.ms_remaining, inputs.ms_duration = get_guide_cooldown(ms_current_id)
        inputs.bladestorm_remaining, inputs.bladestorm_duration =
            get_guide_cooldown(bladestorm_id)
        inputs.bladestorm_known = is_spell_known_query(bladestorm_id) or nil
    else
        inputs.ms_remaining, inputs.ms_duration = nil, nil
        inputs.bladestorm_remaining, inputs.bladestorm_duration = nil, nil
        inputs.bladestorm_known = nil
    end

    -- SoD rune reader (nil on Era-base and everywhere else).
    if inputs.sod then
        inputs.raging_blow_remaining, inputs.raging_blow_duration =
            get_guide_cooldown(raging_blow_id)
    else
        inputs.raging_blow_remaining, inputs.raging_blow_duration = nil, nil
    end

    -- Sunder upkeep window (TBC + Forever APL groups, single-target): stacks
    -- + countdown via the dedicated target scan above (the bar scan's
    -- throttled tables are draw-path state, never guide inputs). Nil on every
    -- other family and when the scan finds nothing (unknown hides). Consumed
    -- by rule S (the TBC + Forever sunder slots).
    if is_tbc_guide or is_forever_guide then
        inputs.sunder_stacks, inputs.sunder_remaining, inputs.sunder_duration =
            get_sunder_upkeep_window(now)
    else
        inputs.sunder_stacks, inputs.sunder_remaining, inputs.sunder_duration = nil, nil, nil
    end

    -- Stance form via the compat probe (api.GetShapeshiftForm exists on every
    -- family; absent/0 reads as nil, never as a stance). The per-family
    -- stance index map is UNCONFIRMED, so the raw form rides through; rule D
    -- reads "in a stance" (any non-zero form), never a named one - the TAC-m
    -- maths (warrior_guide.lua) stays pinned for the full map wiring.
    local stance_form = api.GetShapeshiftForm()
    if type(stance_form) == "number" and stance_form ~= stance_form then
        stance_form = nil
    end
    if stance_form == 0 then
        stance_form = nil
    end
    inputs.stance_form = stance_form

    -- The current stance, by key ("battle" / "berserker" / "defensive"), read
    -- from the client's own stance auras in the aura walk (the sim's stance
    -- ids: 2457 / 2458 / 71). Fed only on the families whose sims gate
    -- Overpower (Battle) and Execute (Battle|Berserker) on a stance: the Era
    -- line (SoD included - the same vanilla game) and the TBC line. Every
    -- other family feeds nil, so the stance gates stay inert there and the
    -- legacy behaviour stays byte-identical. An unknown stance (no stance
    -- aura on the client, or Aggressive Stance, which has no cited id) is nil
    -- too: unknown hides, so nothing is withheld on a guess.
    if is_era_guide or is_tbc_guide then
        inputs.stance = self.warrior_stance
    else
        inputs.stance = nil
    end

    -- The utility spine: the APL's utility rows (the stance upkeep, the cooldown
    -- pops, the racial). The FAMILY GATE LIVES HERE (the engine stays
    -- family-agnostic): a line the running family's APL does not carry is never
    -- read, never fed and never asked for. The running family's APL order is fed
    -- split in two (the rows above the core rotation and the rows below it).
    local utility_family = ST.WARRIOR.utility_family(self)
    inputs.utility_order = nil
    inputs.utility_order_low = nil
    inputs.utility_stance = nil
    inputs.utility_wanted_stance = nil
    inputs.utility_weave = nil
    if utility_family then
        local order, order_low = ST.WARRIOR.utility_order(self)
        inputs.utility_order = order
        inputs.utility_order_low = order_low
        -- The stance upkeep row (the APL's last row): the stance it wants when the
        -- stance's own aura is not active.
        inputs.utility_wanted_stance = ST.WARRIOR.utility_wanted_stance(self)
        -- The weave (the Overpower weave's first step): only the families whose APL
        -- weaves into Battle Stance carry it.
        if ST.WARRIOR.utility_weaves(self) then
            inputs.utility_weave = true
        end
        -- The current stance, read from the client's own stance auras (the same
        -- walk the Overpower / Execute gates use, fed on every family the utility
        -- spine can ask a stance on).
        inputs.utility_stance = self.warrior_stance
    end

    -- The utility rows' per-line reads: the client's own knowledge probe, the
    -- spell's cooldown and the row's buff (the aura walk's own stamp). A line the
    -- running family does not carry stays unknown, so it never prompts.
    for _, key in ipairs(WARRIOR_UTILITY.keys) do
        local line = WARRIOR_UTILITY[key]
        local remaining_name = key .. "_remaining"
        local duration_name = key .. "_duration"
        local buff_name = key .. "_buff"
        local known_name = key .. "_known"
        local rage_max_name = key .. "_rage_max"
        inputs[remaining_name] = nil
        inputs[duration_name] = nil
        inputs[buff_name] = nil
        inputs[known_name] = nil
        inputs[rage_max_name] = nil
        if line.engine ~= false and utility_family
            and ST.WARRIOR.utility_carries(line, utility_family, self) then
            local id = line.ids and line.ids[utility_family] or line.id
            if id then
                -- The knowledge probe: true when the client has the spell, false
                -- when it does not (the row is then dark for good), nil when the
                -- family does not carry the row at all.
                if is_spell_known_query(id) then
                    inputs[known_name] = true
                    local remaining, duration = get_guide_cooldown(id)
                    inputs[remaining_name] = remaining
                    inputs[duration_name] = duration
                else
                    inputs[known_name] = false
                end
                local buffs = self.warrior_utility_buffs
                if buffs then
                    local up = buffs[key]
                    if up ~= nil then
                        inputs[buff_name] = up and true or false
                    end
                end
                if line.rage_max then
                    inputs[rage_max_name] = line.rage_max
                end
            end
        end
    end

    -- SoD follow-up flags (nil where absent/unknown): the stance-dance gate
    -- aura (live, from the walk above - consumed by rule D) and the Rend
    -- rune knowledge (frozen at post_init, kept out of SoD detection -
    -- gates rule R on SoD).
    inputs.sod_stance_aura = self.has_sod_stance_aura and true or nil
    if self.warrior_has_sod_rend_rune == true then
        inputs.sod_rend_rune_known = true
    else
        inputs.sod_rend_rune_known = nil
    end
    return inputs
end

ST.WARRIOR.guide = {
    slots = is_tbc_guide and guide_slots_tbc
        or (is_era_guide and guide_slots_era
            or (is_wrath_guide and guide_slots_wrath_fury
                or (is_forever_guide and guide_slots_forever or guide_slots_base))),

    -- Live inputs: the gather above, verbatim, into the caller's reused table.
    gather = function(self, out)
        return ST.WARRIOR.gather_guide_inputs(self, out)
    end,

    -- Pure: the frozen warrior rule matrix (st.warrior_guide in warrior_guide.lua);
    -- guarded so a flavor without that module stays inert rather than erroring.
    -- The composite rage gate (verify §4.2 - BINDING) post-processes the pick:
    -- the engine orders the TBC core by cooldown alone, the gate re-judges the
    -- Bloodthirst prompt against rage (cost + the queued HS/Cleave reserve)
    -- before it reaches the frame, so the label and the guide can never
    -- disagree (this same wrapper feeds get_rotation_key).
    evaluate = function(inputs, out)
        if st.warrior_guide and st.warrior_guide.evaluate then
            st.warrior_guide.evaluate(inputs, out)
            return ST.WARRIOR.gate_composite_action(inputs, out)
        end
        return out
    end,

    -- Static captions (defaults; the RIDE/HOLD text rides out.hold_text).
    labels = { next_action = "Next action:", hold = "HOLD", ride = "RIDE" },
}

-- The utility spine's family gate and order (shared by the live gather and the
-- practice surface, so both grade the same rotation).
--
-- The runtime family token: the SoD branch rides the ERA token but has its OWN
-- APL, so it gets its own token; nil on a family with no APL (the utility spine
-- stays inert there).
function ST.WARRIOR.utility_family(self)
    if is_era_guide then
        if type(self) == "table" and self.warrior_is_sod == true then
            return "SOD"
        end
        return "ERA"
    elseif is_tbc_guide then
        return "TBC"
    elseif is_wrath_guide then
        return "WRATH"
    elseif is_forever_guide then
        return "FOREVER"
    end
    return nil
end

-- The family gate for one utility row: the runtime family token must be in the
-- row's `families` list. The SoD branch rides the ERA token but has its own APL,
-- so the SoD rows are gated on the row's `sod` flag instead (the SoD APL carries
-- no Battle Shout, no Berserker Rage and no Blood Fury row). The spec gate picks
-- the WotLK branch's own rows (Thunder Clap is the arms row; Shattering Throw and
-- Heroic Throw the fury rows).
function ST.WARRIOR.utility_carries(line, family, self)
    if type(line) ~= "table" or type(family) ~= "string" then
        return false
    end
    if family == "SOD" then
        return line.sod == true
    end
    local specs = line.specs
    if type(specs) == "table" then
        local arms = type(self) == "table" and self.warrior_is_arms == true
        if arms then
            if specs.arms ~= true then
                return false
            end
        elseif specs.fury ~= true then
            return false
        end
    end
    local families = line.families
    if type(families) ~= "table" then
        return false
    end
    for i = 1, #families do
        if families[i] == family then
            return true
        end
    end
    return false
end

-- The utility spine's APL order for the running client: the rows the APL puts
-- above the core rotation (high) and the rows it puts below it (low).
function ST.WARRIOR.utility_order(self)
    local family = ST.WARRIOR.utility_family(self)
    if not family then
        return nil, nil
    end
    local orders = WARRIOR_UTILITY.orders[family]
    if type(orders) ~= "table" then
        return nil, nil
    end
    local high, low = {}, {}
    for i = 1, #orders.high do
        local key = orders.high[i]
        if ST.WARRIOR.utility_carries(WARRIOR_UTILITY[key], family, self) then
            high[#high + 1] = key
        end
    end
    for i = 1, #orders.low do
        local key = orders.low[i]
        if ST.WARRIOR.utility_carries(WARRIOR_UTILITY[key], family, self) then
            low[#low + 1] = key
        end
    end
    return high, low
end

-- The stance the APL's upkeep row wants on the running client (nil when the family
-- carries no stance row - the WotLK arms APL has none).
function ST.WARRIOR.utility_wanted_stance(self)
    local family = ST.WARRIOR.utility_family(self)
    if not family then
        return nil
    end
    if is_wrath_guide and type(self) == "table" and self.warrior_is_arms == true then
        return nil
    end
    return WARRIOR_UTILITY.wanted_stance[family]
end

-- The families whose APL weaves into Battle Stance for the Overpower.
function ST.WARRIOR.utility_weaves(self)
    local family = ST.WARRIOR.utility_family(self)
    if not family then
        return false
    end
    return WARRIOR_UTILITY.weave_families[family] == true
end

--=========================================================================================
-- Cooldown HUD: warrior slots and the live state provider
--=========================================================================================
-- The slot set mirrors the Next Action Guide's slots (ST.WARRIOR.guide above: the
-- class's top-parse abilities), plus the two trinket slots the HUD serves itself.
-- The TBC fury set (op, execute, slam, hs, bt, ww) is picked on the TBC family,
-- the same six on the ERA family (BT/WW are vanilla spells) and on WRATH by
-- default (fury shape), the base set (op, execute, slam, hs, cleave) everywhere
-- else - the guide's own family split, so the HUD and the guide never disagree
-- about which abilities matter. post_init re-picks through resolve_guide_slots
-- (arms / SoD shapes). The descriptor and provider contracts are frozen
-- in hud.lua's header comment; the "trinket" slots need no provider entry.
--
-- Rank notes: the rank-1 ids ship as the icon fallback (the spell art is
-- rank-invariant), while the provider reads cooldowns by the client's own localized
-- name (hud_slot_name), so whatever rank the player knows is what is counted - the
-- paladin's cooldown_spell-free convention from classes/paladin.lua. Overpower
-- (7384) and Execute (5308) are the ids the rest of this module already matches on;
-- Slam / Heroic Strike / Cleave ship their rank-1 ids from the module's own rank
-- tables. None of the classic-line abilities has a cooldown of its own (Overpower
-- is dodge-gated, Execute health-gated, the rest are on-next-attack or casts), so
-- outside the core families the slots show the running GCD swipe plus the
-- mana/range tints; on TBC and Era Bloodthirst (6 s) and Whirlwind (10 s) carry
-- real swipes (vanilla values, shared by TBC; NEEDS IN-CLIENT CONFIRMATION on
-- 2.5.6 and 1.15.9).
local hud_slot_op = { key = "op", title = "Overpower", kind = "spell", spell = overpower_id }
local hud_slot_execute = { key = "execute", title = "Execute", kind = "spell", spell = 5308 }
local hud_slot_slam = { key = "slam", title = "Slam", kind = "spell", spell = 1464 }
local hud_slot_hs = { key = "hs", title = "Heroic Strike", kind = "spell", spell = 78 }
local hud_slot_cleave = { key = "cleave", title = "Cleave", kind = "spell", spell = 845 }
-- Hamstring weave filler (rank-1 fallback 7373; the name-based reads below are
-- rank-agnostic, so the TBC 18499 rank counts without a second descriptor).
local hud_slot_hamstring = { key = "hamstring", title = "Hamstring", kind = "spell", spell = 7373 }
local hud_slot_bt = { key = "bt", title = "Bloodthirst", kind = "spell", spell = 23881 }
local hud_slot_ww = { key = "ww", title = "Whirlwind", kind = "spell", spell = 1680 }
-- Arms / SoD HUD slots (rank-1 fallbacks; the name-based reads below are
-- rank-agnostic): Rend, Mortal Strike, Bladestorm, Raging Blow.
local hud_slot_rend = { key = "rend", title = "Rend", kind = "spell", spell = 772 }
-- Sunder upkeep slot (rank-1 fallback 7386; the name-based reads below are
-- rank-agnostic, so every rank counts without a second descriptor).
local hud_slot_sunder = { key = "sunder", title = "Sunder Armor", kind = "spell", spell = 7386 }
local hud_slot_ms = { key = "ms", title = "Mortal Strike", kind = "spell", spell = 12294 }
local hud_slot_bladestorm = { key = "bladestorm", title = "Bladestorm", kind = "spell",
    spell = 63784 }
local hud_slot_raging = { key = "raging_blow", title = "Raging Blow", kind = "spell",
    spell = 402911 }
local hud_slot_trinket1 = { key = "trinket1", title = "Trinket 1", kind = "trinket", inv_slot = 13 }
local hud_slot_trinket2 = { key = "trinket2", title = "Trinket 2", kind = "trinket", inv_slot = 14 }

if is_tbc_guide then
    -- The TBC row mirrors the TBC guide set (op, execute, slam, hs, bt, ww +
    -- the Sunder upkeep slot - the W-21 mirror). The sunder slot is one of the
    -- three display-only maintenance mirrors (see the provider below).
    ST.WARRIOR.HUD_SLOTS = { hud_slot_op, hud_slot_execute, hud_slot_slam,
        hud_slot_hs, hud_slot_bt, hud_slot_ww, hud_slot_sunder,
        hud_slot_trinket1, hud_slot_trinket2 }
elseif is_era_guide or is_wrath_guide then
    ST.WARRIOR.HUD_SLOTS = { hud_slot_op, hud_slot_execute, hud_slot_slam,
        hud_slot_hs, hud_slot_bt, hud_slot_ww, hud_slot_trinket1, hud_slot_trinket2 }
else
    ST.WARRIOR.HUD_SLOTS = { hud_slot_op, hud_slot_execute, hud_slot_slam,
        hud_slot_hs, hud_slot_cleave, hud_slot_hamstring,
        hud_slot_trinket1, hud_slot_trinket2 }
end

-- Picks the slot set + HUD set from the frozen post_init branch (spec + runes).
-- Defined here (after every slot descriptor above) so all arms/SoD/sunder
-- slots resolve as upvalues, never globals. Called once from post_init,
-- before the shared frame and the HUD build their icons; load-time defaults
-- above serve pre-post_init readers. TBC, Era-base and Wrath-fury keep their
-- load-time sets here (re-assigned identically, with the new slots).
function ST.WARRIOR.resolve_guide_slots(self)
    local arms = self and self.warrior_is_arms == true
    local sod_branch = self and self.warrior_is_sod == true
    if is_wrath_guide and arms then
        ST.WARRIOR.guide.slots = guide_slots_wrath_arms
        ST.WARRIOR.HUD_SLOTS = { hud_slot_op, hud_slot_execute, hud_slot_rend,
            hud_slot_ms, hud_slot_bladestorm, hud_slot_hs,
            hud_slot_trinket1, hud_slot_trinket2 }
    elseif is_era_guide and sod_branch then
        ST.WARRIOR.guide.slots = guide_slots_sod
        ST.WARRIOR.HUD_SLOTS = { hud_slot_execute, hud_slot_slam, hud_slot_hs,
            hud_slot_bt, hud_slot_ww, hud_slot_raging, hud_slot_rend,
            hud_slot_op, hud_slot_trinket1, hud_slot_trinket2 }
    elseif is_forever_guide then
        ST.WARRIOR.guide.slots = guide_slots_forever
        ST.WARRIOR.HUD_SLOTS = { hud_slot_op, hud_slot_execute, hud_slot_slam,
            hud_slot_hs, hud_slot_cleave, hud_slot_hamstring, hud_slot_sunder,
            hud_slot_trinket1, hud_slot_trinket2 }
    elseif is_tbc_guide or is_era_guide then
        ST.WARRIOR.guide.slots = is_tbc_guide and guide_slots_tbc or guide_slots_era
        if is_tbc_guide then
            -- The TBC HUD mirrors the TBC guide row: the six core abilities plus
            -- the Sunder upkeep slot (W-21 - the guide slot shipped, the HUD row
            -- did not). The sunder slot is a display-only mirror: no cooldown of
            -- its own to ride, and it hides unless hud_show_sunder reads exactly
            -- true (nil = off, the druid Claw shape).
            ST.WARRIOR.HUD_SLOTS = { hud_slot_op, hud_slot_execute, hud_slot_slam,
                hud_slot_hs, hud_slot_bt, hud_slot_ww, hud_slot_sunder,
                hud_slot_trinket1, hud_slot_trinket2 }
        else
            ST.WARRIOR.HUD_SLOTS = { hud_slot_op, hud_slot_execute, hud_slot_slam,
                hud_slot_hs, hud_slot_bt, hud_slot_ww, hud_slot_hamstring,
                hud_slot_trinket1, hud_slot_trinket2 }
        end
    elseif is_wrath_guide then
        ST.WARRIOR.guide.slots = guide_slots_wrath_fury
        ST.WARRIOR.HUD_SLOTS = { hud_slot_op, hud_slot_execute, hud_slot_slam,
            hud_slot_hs, hud_slot_bt, hud_slot_ww,
            hud_slot_trinket1, hud_slot_trinket2 }
    end
end

-- One reused state table: the HUD reads it immediately and never keeps a reference
-- (see the frozen contract in hud.lua), so there is no per-tick allocation here.
ST.WARRIOR.hud_state = {}

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
-- cooldown of its own. Only Bloodthirst and Whirlwind have one on the TBC/Era
-- families (TBC values; NEEDS IN-CLIENT CONFIRMATION on 2.5.6 - the swipe length
-- only matters while a real cooldown is running, which always carries the
-- client-reported length instead). Mortal Strike (6 s, the wotlk 47486 value),
-- Bladestorm (90 s, NEEDS IN-CLIENT CONFIRMATION) and Raging Blow (8 s, the
-- classic 402911 value) serve the arms/SoD slots the same way; Rend has none
-- (its guide swipe follows the debuff window, the HUD shows the GCD).
ST.WARRIOR.HUD_COOLDOWN_FALLBACK = {
    op = 0,
    execute = 0,
    slam = 0,
    hs = 0,
    cleave = 0,
    hamstring = 0,
    bt = 6,
    ww = 10,
    rend = 0,
    sunder = 0,
    ms = 6,
    bladestorm = 90,
    raging_blow = 8,
}

-- Slots that never borrow the GCD swipe (the paladin's judgement/wings rule in
-- classes/paladin.lua). Every warrior slot is rotational, so the set is empty and
-- every ready slot shows the running GCD. (The three display-only maintenance
-- mirrors - Sunder Armor, Rend and Hamstring - are gated in the provider below
-- and never reach this table: Sunder and Rend have no cooldown of their own to
-- ride and return before the swipe, and the Hamstring filler keeps the
-- rotational GCD path like every other rotational slot.)
ST.WARRIOR.HUD_SKIP_GCD = {}

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

-- Remaining time and full duration of one warrior ability cooldown: the client's own
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
    return 0, ST.WARRIOR.HUD_COOLDOWN_FALLBACK[slot.key] or 0
end

-- IsUsableSpell's second return (classes/paladin.lua hud_no_mana, verbatim):
-- through compat's cross-client IsSpellUsable wrapper. A client with no probe
-- reports unknown, rendered as "no tint".
local function hud_no_mana(slot)
    local name = hud_slot_name(slot)
    local ok, _, insufficient = pcall(api.IsSpellUsable, name or slot.spell)
    return ok and insufficient == true
end

-- W7 readiness-glow fallback (verify W7): IsUsableSpell's first return through
-- the same pcall'd wrapper as hud_no_mana above. When the Overpower proc stamp
-- is UNSET (nil - no window was ever armed; the Mainline-code path where the
-- classic dodge window cannot exist), a client that probes the spell as usable
-- right now still gets the glow; a stamp that was armed and has elapsed keeps
-- the window's own verdict instead (the call site's rule). PROBE-ONLY by
-- mandate: never gated on st.is_mainline (the Forever client is Mainline-code
-- but is exactly the client this fallback targets), and a client with no probe
-- - or a secret-guarded unknown - reports "no fallback", never a forced glow.
local function hud_usable_now(slot)
    local name = hud_slot_name(slot)
    local ok, usable = pcall(api.IsSpellUsable, name or slot.spell)
    return ok and usable == true
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

-- True when the target is inside the Execute range: its health percentage sits below
-- the guide's threshold (db.guide_execute_pct, default 20 - the engine default in
-- warrior_guide.lua). An unreadable target reads as outside the range, never as in.
local function hud_execute_range(self)
    local health_max = api.UnitHealthMax("target")
    if type(health_max) ~= "number" or health_max <= 0 then
        return false
    end
    local health = api.UnitHealth("target")
    if type(health) ~= "number" then
        return false
    end
    local range_db = self:get_class_table()
    -- PROPER: 20 is the shipped execute threshold (the engine default); a missing
    -- table reads as defaults, never as in-range.
    local threshold = (range_db and range_db.guide_execute_pct) or 20
    return health / health_max * 100 < threshold
end

-- The class provider (frozen contract, hud.lua header): the paladin's ability_state
-- mapping (hud.lua:418-453) re-expressed for the warrior slots. Overpower glows
-- while its dodge window is live (the module's own proc stamp); Execute glows the
-- moment it is ready, in combat, with the target in Execute range.
function ST.WARRIOR.get_hud_state(self, slot, now)
    local s = ST.WARRIOR.hud_state
    s.remaining, s.duration, s.start, s.reverse = nil, nil, nil, nil
    s.text_remaining, s.desaturate, s.usable, s.in_range = nil, nil, nil, nil
    s.glow, s.count, s.texture, s.hidden = nil, nil, nil, nil
    now = now or api.get_time()
    if type(slot) ~= "table" or type(slot.key) ~= "string" then
        -- PROPER: a slot without a key carries nothing renderable (no icon, no
        -- cooldown); hiding draws the honest state instead of throwing. The
        -- driver always passes a slot table, so this only fires for a caller bug.
        s.hidden = true
        return s
    end
    -- The three display-only maintenance mirrors (W-21 - the guide slots for
    -- Sunder Armor, Rend and Hamstring already shipped; the HUD row now
    -- mirrors them). Each hides unless its hud_show_<key> toggle reads exactly
    -- true: nil = off (the HUD treats a nil toggle as wanted, so this
    -- provider-level hide is the no-default-visible gate - the druid Claw
    -- shape; the toggles themselves live in config_presets.lua and the options
    -- panel, the options lane's files). Sunder and Rend are upkeep actions
    -- with no cooldown of their own to ride, so they are display-only and
    -- return before the cooldown read (the shaman's maintain-mirror shape); the
    -- Hamstring filler keeps the rotational GCD path (the druid Claw shape).
    if slot.key == "sunder" or slot.key == "rend" or slot.key == "hamstring" then
        local hud_db = self:get_class_table()
        if type(hud_db) ~= "table" or hud_db["hud_show_" .. slot.key] ~= true then
            s.hidden = true
            return s
        end
        if slot.key ~= "hamstring" then
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
    elseif not ST.WARRIOR.HUD_SKIP_GCD[slot.key] then
        -- The GCD shows as a swipe (WA "show GCD"); the HUD's 2 s rule keeps its
        -- text hidden.
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

    if slot.key == "op" then
        -- The dodge window (the module's own proc stamp) arms the glow; the W7
        -- fallback arms it too while the client probes the spell as usable
        -- right now. A live window short-circuits the probe (one fewer read
        -- while the stamp is live); a stamp that is set but elapsed is the
        -- window's own verdict and stops the glow - the probe only covers a
        -- client that never armed a window at all (the Mainline-code path
        -- where the classic dodge window cannot exist), never a window that
        -- came and went.
        local op_remaining = self.WARRIOR.get_overpower_remaining(
            self.warrior_overpower_proc_until, now)
        if op_remaining ~= nil then
            s.glow = true
        elseif self.warrior_overpower_proc_until == nil then
            s.glow = hud_usable_now(slot)
        else
            s.glow = false
        end
    elseif slot.key == "execute" then
        s.glow = (remaining <= 0 and self.in_combat == true
            and hud_execute_range(self)) or false
    end
    return s
end

--=========================================================================================
-- Rotation text: the warrior rotation source
--=========================================================================================
-- Implements the frozen ST.<CLASS>.get_rotation_key contract documented in
-- rotationtext.lua's header, following the paladin's shape (ST.PALADIN.
-- get_rotation_key in rotationtext.lua): the guide's own decision, so the label and
-- the guide can never disagree. The warrior engine names no rotations (its
-- out.rotation_key is always nil), so the label is the current action: the
-- recommended ability's localized name (resolved from the guide's own slot
-- descriptors, cached per spell id), HOLD while the engine holds, RIDE while it
-- rides, nil when the guide is idle (renders as the empty text). No practice
-- branch: Twist Practice is paladin-only (no simulation exists for this class).
-- One reused output table: no per-tick allocation on the label tick.
ST.WARRIOR.rotation_out = {}

-- The guide slot's localized spell name for an action key (the slot's current-rank
-- spell id, so a re-pointed icon re-points the label with it). Falls back to the
-- raw action key when the client's spell data has not answered yet.
local rotation_name_cache = {}

local function rotation_ability_name(action)
    local spell_id
    local slots = ST.WARRIOR.guide.slots
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

function ST.WARRIOR.get_rotation_key(self)
    local guide = ST.WARRIOR.guide
    local engine = st.warrior_guide
    if not (guide and guide.gather and guide.evaluate and engine and engine.evaluate) then
        return nil
    end
    local out = guide.evaluate(guide.gather(self, ST.WARRIOR.guide_inputs),
        ST.WARRIOR.rotation_out)
    if out.action ~= nil then
        return rotation_ability_name(out.action)
    end
    if out.hold then
        return out.hold_text
    end
    return nil
end

--=========================================================================================
-- Practice: the warrior's own rotation scenario and drills
--
-- The shared practice engine drives every class through three surfaces (the
-- orchestrator's fixed contract, looked up by player_class):
--   ST.<CLASS>.practice_rotation       the rotation table in sim priority order,
--                                      each entry citing its sim source
--   ST.<CLASS>.practice_scenario_step  one expected action per tick
--   ST.<CLASS>.practice_drills         the class's own drills, each with a
--                                      grade function
--
-- The warrior's surfaces live here. The decision engine is the one the guide
-- already uses (st.warrior_guide.evaluate through ST.WARRIOR.guide.evaluate, so
-- the composite rage gate applies and the practice pick can never disagree
-- with the live pick); the pure maths the drills need lives in warrior_guide.lua
-- (the audited band tables, the stance gates, the Execute drain).
--
-- The context the engine feeds (ctx):
--   now          the simulated clock (a number; the engine itself is clock-free)
--   last_action  the player's last press, as an action key ("op", "bt", ...)
--   resources    the pool and the state readings:
--                  rage, hs_cost, cleave_cost, bt_cost, ww_cost,
--                  target_health_pct, execute_pct, hs_queued, cleave_queued,
--                  has_bloodsurge, slam_casting, overpower_remaining,
--                  swing_remaining, gcd_remaining, hs_rage_floor,
--                  core_reserve_window, execute_spam, sunder_stacks,
--                  sunder_remaining, rend_remaining, rend_upkeep_enabled,
--                  hamstring_known, hamstring_rage_threshold, sudden_death,
--                  victory_rush, stance, phase_started_at (optional: the
--                  execute-phase crossing, for the burn drill's lateness)
--                  speed, offhand_swing_remaining, dual_wielding (the queue
--                  drill's own swing data: the mainhand's weapon speed, the
--                  offhand's next landing and the two-weapons flag)
--   cooldowns    the cooldown readings in seconds (nil = unknown): bt, ww, op,
--                execute, slam, hs, cleave, raging_blow, ms, bladestorm
-- Every reading is optional: an unknown reading stays absent and the engine
-- withholds rather than guessing. A drill that cannot judge answers nil
-- ("unknown", never a wrong action).
--
-- The scenario step answers what the rotation wants: the action to press, or -
-- when the guide HOLDS (a RIDE window, the filler's rage shortfall) - an
-- explicit hold statement, so the engine can tell a hold (a decision) from an
-- unknown (a state it cannot read).
--=========================================================================================

-- The rotation table: the compiled rule order (warrior_guide.lua's matrix)
-- with the sim source of every line. The families field names the client
-- families whose APL carries the line (nil = every family); the engine reads
-- them off the family keys (ERA, TBC, WRATH, FOREVER - the SoD branch rides
-- the ERA family). Fetched 2026-10-19 from the wowsims master branches.
--
-- The table has TWO blocks, in this order:
--   1. the engine's compiled rule order - the keys warrior_guide.lua's matrix
--      emits, in the order it emits them. These are the keys the practice
--      scenario can grade.
--   2. the APL's UTILITY SPINE - the stance / shout / rage-tool / cooldown-pop
--      rows the sims' priority lists carry and the compiled rule order does
--      not. The gap analysis (bench/rotation_gap_vs_apl_2026-10-20.md section
--      1) found the shipped table carrying 13 keys, every one of them a
--      damage ability or a debuff upkeep: no stance, no shout, no rage tool,
--      no cooldown pop, and no Thunder Clap / Shattering Throw / Heroic Throw
--      on WotLK. The operator's named set (Charge, Battle Stance, Berserker
--      Stance, Bloodrage) lands here.
--
-- Block 2's field shape:
--   action   the key the line would use (the guide's vocabulary once the rule
--            exists; no guide rule emits it yet).
--   label    the spell's English name (the panel's button label).
--   reason   the short caption the practice surface shows.
--   spell_id / spell_ids  the id the Era-style clients resolve by. spell_ids
--            is the per-family form, used where the id itself splits by
--            family (25289 is Battle Shout on Era/Forever and rank 7 on TBC,
--            whose rank 8 is 2048; 12292 is Death Wish on TBC and Sweeping
--            Strikes on Forever). spell_name carries the English name the
--            TBC client resolves by - TBC takes names, Classic Era takes ids,
--            so every line pins BOTH (bench/lessons.md).
--   families the families whose APL carries the line as a SPELL ROW. The APL's
--            pre-pull rows are NOT here: they live in
--            ST.WARRIOR.PRACTICE_PREPULLS (the hunter's shape), per the
--            operator's HU-12 ruling (the rotation table carries the APL's
--            spell rows; the pre-pull rows carry their own table).
--   live     false on every line of block 2: the guide has no rule for the
--            key yet, so the practice surface never expects a cast it cannot
--            grade (a rotation line that no engine action can produce must
--            not prompt). `needs` names the exact read and the exact rule
--            each line waits for.
--
-- The sim-harness rows (the `CD: Trinkets` / `Engineering` / `CD: Racials`
-- groups, the potion rows, autocastOtherCooldowns) are NOT rotation
-- decisions and are in neither table (bench/rotation_gap_vs_apl_2026-10-20.md
-- section 1.4).
local practice_rotation = {
    {
        action = "op",
        label = "Overpower",
        reason = "Overpower window (dodge proc)",
        source = "wowsims/classic sim/warrior/overpower.go (OverpowerAura 5 s, "
            .. "ExtraCastCondition = OverpowerAura.IsActive(), Battle stance only); "
            .. "wowsims/sod sim/warrior/overpower.go (the same, plus the Taste for "
            .. "Blood rune); wowsims/tbc-new sim/warrior/overpower.go "
            .. "(ExtraCastCondition = StanceMatches(BattleStance)); the Era APL "
            .. "fires Overpower through autocastOtherCooldowns before its Execute "
            .. "line (classic ui/warrior/apls/dps_no_reck.apl.json) and the tbc-new "
            .. "fury APL's Overpower Weaving group casts Battle Stance (2457) "
            .. "before Overpower (11585)",
        families = { "ERA", "TBC" },
        live = true, engine = true,
    },
    {
        action = "execute",
        label = "Execute",
        reason = "Execute below 20 %",
        source = "wowsims/classic sim/warrior/execute.go (ExtraCastCondition = "
            .. "sim.IsExecutePhase20(), BattleStance|BerserkerStance, the cast spends "
            .. "the whole pool: 600 + 15*extraRage); wowsims/tbc-new "
            .. "sim/warrior/execute.go (StanceMatches(Berserker|Battle) && "
            .. "IsExecutePhase20(), 925 + 21*extraRage); the tbc-new fury APL casts "
            .. "25236 when isExecutePhase E20",
        families = { "ERA", "TBC", "WRATH" },
        live = true, engine = true,
    },
    {
        action = "slam",
        label = "Slam",
        reason = "Bloodsurge Slam",
        source = "wowsims/classic sim/warrior/slam.go (Slam 11605, cost 15, a 1.5 s "
            .. "cast, StopMeleeUntil(..., true) = the cast resets the swing); the "
            .. "Blood Surge proc aura is 46916 (Wrath) and 413399 (the SoD rune)",
        families = { "WRATH", "ERA" },
        live = true, engine = true,
    },
    {
        action = "sunder",
        label = "Sunder Armor",
        reason = "Sunder upkeep (stacks / refresh window)",
        source = "the tbc-new fury APL's Sunder Armor group: castSpell 25225 when "
            .. "the target's stacks are below 5, or the debuff has 10 s or less left "
            .. "(the same group in the tbc-new arms APL)",
        families = { "TBC", "FOREVER" },
        live = true, engine = true,
    },
    {
        action = "rend",
        label = "Rend",
        reason = "Rend upkeep",
        source = "the arms Rend upkeep (Rend 47465, a 15 s debuff, "
            .. "wowhead.com/wotlk/spell=47465) and the SoD Rend (11574 with the "
            .. "Blood Frenzy rune 412507, operator-confirmed in-client 2026-10-19)",
        families = { "WRATH", "ERA" },
        live = true, engine = true,
    },
    {
        action = "bt",
        label = "Bloodthirst",
        reason = "Bloodthirst",
        source = "wowsims/classic sim/warrior/bloodthirst.go (Bloodthirst 23894, "
            .. "cost 30, a 6 s cooldown); the tbc-new fury APL casts 30335 (rank 5) "
            .. "above its Whirlwind line",
        families = { "ERA", "TBC", "WRATH" },
        live = true, engine = true,
    },
    {
        action = "ww",
        label = "Whirlwind",
        reason = "Whirlwind (the core is more than 1.5 s out)",
        source = "wowsims/classic sim/warrior/whirlwind.go (Whirlwind 1680, cost 25, "
            .. "a 10 s cooldown); the tbc-new fury APL gates Whirlwind (1680 tag1) on "
            .. "spellTimeToReady 30335 >= 1.5 s (the Delay Check)",
        families = { "ERA", "TBC", "FOREVER" },
        live = true, engine = true,
    },
    {
        action = "raging_blow",
        label = "Raging Blow",
        reason = "Raging Blow (costs no rage)",
        source = "the SoD rune Raging Blow 402911 (wowhead.com/classic/spell=402911; "
            .. "it costs no rage)",
        families = { "ERA" },
        live = true, engine = true,
    },
    {
        action = "bladestorm",
        label = "Bladestorm",
        reason = "Bladestorm",
        source = "the arms Bladestorm (63784, wowhead.com/wotlk/spell=63784; the 90 s "
            .. "swipe fallback still needs in-client confirmation)",
        families = { "WRATH" },
        live = true, engine = true,
    },
    {
        action = "ms",
        label = "Mortal Strike",
        reason = "Mortal Strike",
        source = "the arms Mortal Strike (the Taste for Blood affected-spells list, "
            .. "wowhead.com/wotlk/spell=56638; a 6 s filler)",
        families = { "WRATH" },
        live = true, engine = true,
    },
    {
        action = "hamstring",
        label = "Hamstring",
        reason = "Hamstring weave (rage dump)",
        source = "the tbc-new fury APL casts 25212 (Hamstring) at its priority row 19 "
            .. "when the Delay Check holds and Improved Hamstring (20500) is known; "
            .. "the Era line is 7373 above 80 rage. CORRECTED 2026-10-20: this row "
            .. "used to name 18499 as the TBC cast, but 18499 is BERSERKER RAGE "
            .. "(wowsims/classic sim/warrior/berserker_rage.go:14 - "
            .. "core.ActionID{SpellID: 18499}; wowsims/forever "
            .. "sim/warrior/spell_data_auto_gen.go:155 - BerserkerRage: 18499), and "
            .. "20500 is the Improved Hamstring TALENT buff the APL only tests for; "
            .. "the TBC Hamstring id is 25212 (wowsims/tbc-new "
            .. "sim/warrior/spell_data_auto_gen.go, the Hamstring table)",
        families = { "ERA", "TBC" },
        live = true, engine = true,
    },
    {
        action = "hs",
        label = "Heroic Strike",
        reason = "Heroic Strike dump",
        source = "wowsims/classic sim/warrior/heroic_strike_cleave.go (the queue needs "
            .. "rage >= the cost); the tbc-new fury APL casts 29707 tag1 at one "
            .. "target with currentRage >= 40 outside the execute phase; the Era APL "
            .. "gates Heroic Strike 25286 on currentRage >= 40",
        live = true, engine = true,
    },
    {
        action = "cleave",
        label = "Cleave",
        reason = "Cleave dump",
        source = "the tbc-new fury APL casts 25231 tag1 (Cleave rank 5) above one "
            .. "target with currentRage >= 40; the Era APL casts 20569 tag1 rank 5",
        families = { "ERA", "TBC" },
        live = true, engine = false,
    },
    -- ---- block 2: the APL's utility spine (generated from WARRIOR_UTILITY, the
    -- single source of truth for the ids, the family gates and the labels) --
    -- Every id and every priority position was read out of the fetched APL files
    -- on 2026-10-20 (wowsims/{classic,sod,tbc-new,forever,wotlk} master); the [n]
    -- is the index in that APL's priorityList (a group's members keep their own
    -- index inside the group). The `live` flag says the line's READ exists and
    -- the line can be evaluated; the `engine` flag says the frozen engine has an
    -- arm that can ask for it (the Gladiator Stance row has no arm: the SoD APL
    -- gates it on the T1 damage SET bonus, an equipment fact the client's aura
    -- list cannot answer - the row's own `needs` names the missing read).
}

-- Block 2: the APL's utility spine, generated from WARRIOR_UTILITY (the one place
-- the ids, the family gates and the labels live). The generator is a function so its
-- own locals stay out of the chunk's local budget (Lua 5.1 caps a chunk at 200).
local function append_utility_rotation(rotation)
    for i = 1, #WARRIOR_UTILITY.keys do
        local key = WARRIOR_UTILITY.keys[i]
        local line = WARRIOR_UTILITY[key]
        local entry = {
            action = key,
            label = line.label,
            reason = line.reason,
            spell_name = line.spell_name,
            families = line.families,
            live = line.live,
            engine = line.engine,
            source = line.source,
        }
        if line.ids then
            entry.spell_ids = line.ids
        else
            entry.spell_id = line.id
        end
        if line.needs then
            entry.needs = line.needs
        end
        rotation[#rotation + 1] = entry
    end
    return rotation
end

ST.WARRIOR.practice_rotation = append_utility_rotation(practice_rotation)

-- The rotation slice the practice panel publishes (the hunter's shape:
-- ST.<CLASS>.practice_rotation_for; the panel calls it argument-free and falls
-- back to the guide slot vocabulary when a class publishes none). The class's
-- own slice is the running client's - the family token the utility spine uses
-- (the SoD branch of the ERA family has its own token, because the SoD branch
-- has its own APL).
function ST.WARRIOR.practice_rotation_family()
    return ST.WARRIOR.utility_family(ST)
end

-- The guide vocabulary a family's slice is cut from: the class's own resolved
-- slot set for the running client (ST.WARRIOR.guide.slots - post_init re-picks
-- it per family and per spec, so it is exactly the set of actions the engine
-- can name on that client), or the per-family set for an explicit family
-- argument. The WotLK token resolves the spec through the frozen branch flag
-- (a respec needs /reload - the same rule the slot pick uses).
--
-- The per-family map is built INSIDE the function: the chunk's local budget is
-- at its cap (Lua 5.1 caps a chunk at 200 locals), so a file-scope table for it
-- would not load.
function ST.WARRIOR.practice_rotation_slots(family)
    if type(family) ~= "string" or family == "" then
        local guide = ST.WARRIOR.guide
        if type(guide) ~= "table" then
            return nil
        end
        return guide.slots
    end
    if family == "WRATH" then
        if ST.warrior_is_arms == true then
            return guide_slots_wrath_arms
        end
        return guide_slots_wrath_fury
    end
    local sets = {
        ERA = guide_slots_era,
        SOD = guide_slots_sod,
        TBC = guide_slots_tbc,
        FOREVER = guide_slots_forever,
    }
    return sets[family]
end

-- The family's slice of the rotation table: the rows that family plays, in the
-- table's own order (the compiled rule order, then the APL's utility spine).
--
-- THE GATE is the class's own vocabulary: a row joins the slice when the
-- running client's guide slot set names its action. That set is the engine's
-- own askable vocabulary on that client (the class keeps the two in step: the
-- utility lane gave every engine-armable utility row a slot), so the slice
-- carries every row the engine can ask for and nothing else.
--
-- TWO ROWS NEVER JOIN, whatever the client:
--   * a row the engine never emits (cleave - no rule outputs it) and
--   * a row whose read does not exist (a filed row).
-- A button the rotation can never ask for is a button that can never be the
-- right answer, so those rows stay out of the panel's strip.
--
-- The order is the table's own (the compiled order first, the utility spine
-- after); the engine's own ask order interleaves them (the APL's high rows sit
-- above the core), and the strip is a button set, not a priority list.
function ST.WARRIOR.practice_rotation_for(family)
    local want = family
    if type(want) ~= "string" or want == "" then
        want = ST.WARRIOR.practice_rotation_family()
    end
    local slots = ST.WARRIOR.practice_rotation_slots(want)
    if type(slots) ~= "table" then
        return {}
    end
    local keys = {}
    for i = 1, #slots do
        local slot = slots[i]
        if type(slot) == "table" and type(slot.key) == "string" then
            keys[slot.key] = true
        end
    end
    local out = {}
    for i = 1, #ST.WARRIOR.practice_rotation do
        local entry = ST.WARRIOR.practice_rotation[i]
        if type(entry) == "table" and entry.engine ~= false and entry.live ~= false
            and keys[entry.action] == true then
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
-- THE KEY (one, on one family):
--   cleave   Cleave - the FOREVER guide slot (classes/warrior.lua's
--            guide_slots_forever) carries it, and on the Forever client NO
--            rotation row asks for it: the class's own cleave row is an ERA/TBC
--            row (families = { "ERA", "TBC" }) and its engine arm is filed
--            (engine = false - the frozen engine has no Cleave arm), so the
--            Forever rotation never names Cleave. A Cleave press there is a
--            legitimate ability the rotation never grades, so it is NEUTRAL.
--            On the families whose rotation DOES carry a Cleave row (ERA, TBC)
--            the key is a rotation action and is deliberately NOT published here.
--
-- WHY THE WARRIOR'S SET IS THIS SMALL (the honest answer, and the class's own
-- ability list is the reason):
--   * every other key the warrior's panel offers is a rotation action. The
--     warrior's guide slots are cut from the utility spine (WARRIOR_UTILITY:
--     Battle Shout, Bloodrage, Recklessness, Death Wish, Berserker Rage, the
--     stances, Blood Fury, Sweeping Strikes, Thunder Clap, Shattering Throw,
--     Heroic Throw) plus the compiled core order, and the utility spine IS the
--     rotation table's own second block - so those rows ARE rotation actions and
--     the rotation grades them;
--   * Battle Shout is a rotation row on every family whose guide slots offer it
--     (ERA, TBC, FOREVER) and the SoD APL carries no Battle Shout row at all, so
--     the family that does not ask for it never offers the key either - there is
--     nothing to neutralise;
--   * the abilities the orchestrator named for this class split in two:
--       - the food and drink (the Food), the potions (the Healthstone, the
--         Diamond Flask), the Demoralizing Shout and the Sprint have NO key in
--         the warrior's ROTATION and GUIDE vocabulary: the APL's consumable
--         rows are ITEMS, not spells (the class's own pre-pull comment says so),
--         and the warrior's guide slots carry no key for them. They DO have a
--         key in the class's own PRACTICE-PANEL ability list (the common-action
--         list below), which is the panel's own vocabulary: the panel offers
--         them, the rotation never asks for them, and the publish above carries
--         them per family as NEUTRAL;
--       - the Defensive Stance and the Stoneform carry no key anywhere in the
--         class's vocabulary - neither the rotation/guide spine (the utility
--         spine carries the Battle, the Berserker and the Gladiator stances)
--         nor the practice-panel list. Publishing them would still invent keys
--         the class does not have.
--=========================================================================================
ST.WARRIOR.practice_neutral_actions = {
    ERA = {
        sprint = true,
        demoralizing_shout = true,
        healthstone = true,
        flask = true,
        food = true,
    },
    TBC = {
        sprint = true,
        demoralizing_shout = true,
        healthstone = true,
        flask = true,
        food = true,
    },
    WRATH = {
        sprint = true,
        demoralizing_shout = true,
        healthstone = true,
        flask = true,
        food = true,
        battle_shout = true,
    },
    FOREVER = {
        cleave = true,
        sprint = true,
        demoralizing_shout = true,
        healthstone = true,
        flask = true,
        food = true,
    },
    -- THE CATA AND MISTS CLIENTS (the 4.4.3 and the 5.5.0 clients - the two TOCs
    -- that ship this addon, SwedgeTimer_Cata.toc and SwedgeTimer_Mists.toc) carry
    -- NO BUCKET HERE, and that is the class's own statement, not a gap:
    --
    --   * the class publishes NO rotation for either client (the rotation table
    --     carries no CATA / MISTS row and the utility spine names no family there -
    --     ST.WARRIOR.utility_family answers nil for both), so on those two clients
    --     no row of the class's own is a rotation action. A bucket is the class's
    --     statement about a client it PLAYS; the class plays neither of these;
    --   * the class's guide vocabulary on those two clients is its own ERA-base set
    --     (the slot pick falls back to the base set - neither client has a warrior
    --     slot set of its own), and the class makes no statement about it there -
    --     the Cleave is a FOREVER slot, the Battle Shout is an APL utility row of
    --     the classic line (and a self-buff from 4.0);
    --   * so the OFFER GATE (ST.WARRIOR.practice_common_offer_allowed) offers NO
    --     common ability on those two clients: an ability the family does not
    --     publish as neutral can only be a mis-pick the moment it is pressed, so
    --     the panel does not offer it there. It stays available on the families
    --     where the class DOES publish it.
    --
    -- FOR THE RECORD (the clients' own spell pages - the /data/spell/<id> page on
    -- the warcraftdb site, on the Cataclysm and the MoP expansion domains, whose
    -- title carries the client's own spell name): the Cata and the Mists clients
    -- DO carry every one of the class's five common abilities - Sprint 2983,
    -- Demoralizing Shout 1160, the Healthstone (the clients' own rank is 6262 -
    -- the Era id 5720 answers "Not Found" there, and 6262 is a DIFFERENT spell on
    -- the classic clients - "Minor Healthstone" - so the ladder is NOT extended
    -- with it; the NAME-first leg finds the client's own rank only where the
    -- client ANSWERS the name, and the classic-line name leg is UNCONFIRMED
    -- in-client - audit 2026-10-20 section 6 C1), the
    -- Diamond Flask 24427 and the Food 433. The exclusion is a deliberate
    -- statement about a client the class does not play, not a belief that the
    -- client lacks the spells.
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
function ST.WARRIOR.practice_neutral_set()
    local published = ST.WARRIOR.practice_neutral_actions
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
function ST.WARRIOR.practice_rotation_action_set()
    local out = {}
    local ok, entries = pcall(function() return ST.WARRIOR.practice_rotation_for() end)
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
-- onto the canonical key). The warrior has none - its key space is one - so the
-- normaliser is the identity.
function ST.WARRIOR.practice_canonical_key(key)
    local aliases = ST.WARRIOR.practice_action_aliases
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
function ST.WARRIOR.practice_common_offer_allowed(action, neutral, rotation)
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
        and rotation[ST.WARRIOR.practice_canonical_key(action.key)] == true then
        return false
    end
    return true
end

--=========================================================================================
-- The PRACTICE-PANEL ability list: the common abilities the panel offers
--
-- WHY THIS EXISTS: the practice panel's action row offers the class's whole ability
-- list, and a player legitimately presses a potion, a food or a movement ability
-- while practicing. The engine grades such a press NEUTRAL - no attempt, no points,
-- no streak change, never a mis-pick (bench/practice_neutral_actions_2026-10-20.md).
-- For that the class needs a KEY for each of them: the panel's vocabulary is the
-- rotation slice plus the class's own guide slot list, and the common abilities had
-- no key at all (bench/class_neutral_actions_2026-10-20.md §2).
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
-- THE FAMILY GATE (the one row that needs it): Battle Shout is an APL utility row on
-- ERA, TBC and FOREVER (WARRIOR_UTILITY.orders), so on those families it IS a
-- rotation action and may never be neutral. The WotLK utility order carries no Battle
-- Shout row and the WotLK guide slot set does not offer the key, so on WRATH the
-- ability is legitimate and ungraded - and only there. The SoD build is NOT in the
-- gate: the SoD game runs on the Era client, so the BUILD shares the Era family
-- token with the Era build, where Battle Shout IS a rotation action - publishing it
-- as neutral on the Era family would make a WRONG Battle Shout press free there. The
-- engine's family-scoped publish cannot separate the two builds (it reads st.family),
-- so the SoD build keeps the Era bucket and the SoD panel keeps not offering the key
-- - the honest answer, filed for the engine lane (a build token in the publish).
--=========================================================================================
ST.WARRIOR.practice_common_actions = {
    {
        key = "sprint",
        label = "Sprint",
        names = { "Sprint" },
        -- 2983 - the client's Sprint (the corpus description: "Increases the rogue's
        -- movement speed by $s1% for $d. Does not break stealth."; the name
        -- confirmed at the Classic spell page (2983)). The warrior's own
        -- utility spine carries no Sprint row, so it is never a rotation action.
        ids = { 2983 },
    },
    {
        key = "demoralizing_shout",
        label = "Demoralizing Shout",
        names = { "Demoralizing Shout", "Demoralising Shout" },
        -- 1160 / 6190 / 11554 / 11555 / 11556 - the class's OWN debuff-bar id table
        -- (classes/warrior.lua's demo_shout_ids, the name fallbacks included); the
        -- names confirmed at the Classic spell page (1160). The APLs carry
        -- no Demoralizing Shout row (bench/rotation_gap_vs_apl_2026-10-20.md §1.4),
        -- so it is never a rotation action.
        ids = { 1160, 6190, 11554, 11555, 11556 },
    },
    {
        key = "healthstone",
        label = "Healthstone",
        names = { "Healthstone" },
        -- 5720 - the client's Healthstone use effect (the corpus description:
        -- "Instantly restores $s1 life."; the name confirmed at
        -- the Classic spell page (5720)). The APL's consumable row names the
        -- Healthstone item (22788); the panel's vocabulary is SPELLS, so the use
        -- effect is the cited spell.
        ids = { 5720 },
    },
    {
        key = "flask",
        label = "Diamond Flask",
        names = { "Diamond Flask" },
        -- 24427 - the client's Diamond Flask use effect (the corpus description:
        -- "Restores $s2 health every $t2 sec and increases your Strength by $s1.").
        -- The APL's consumable row names the same item (24427).
        ids = { 24427 },
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
    {
        key = "battle_shout",
        label = "Battle Shout",
        names = { "Battle Shout" },
        -- 6673 (r1) / 11549 (r4) / 25289 (r7) - the client's Battle Shout ladder
        -- (the corpus description: "The warrior shouts, increasing the melee attack
        -- power of all party members within $a1 yards by $s1."; the names confirmed
        -- at the Classic spell page (6673)). The TBC rank 8 is 2048 (the
        -- class's own pre-pull row cites it).
        ids = { 6673, 11549, 25289 },
        -- The gate: the WotLK client only (the family whose utility order carries no
        -- Battle Shout row and whose guide slots do not offer the key).
        families = { "WRATH" },
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
function ST.WARRIOR.resolve_practice_common_action(action)
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
function ST.WARRIOR.practice_panel_slots()
    local guide = ST.WARRIOR.guide
    local slots = type(guide) == "table" and guide.slots or nil
    local out = {}
    if type(slots) == "table" then
        for i = 1, #slots do
            out[i] = slots[i]
        end
    end
    local common = ST.WARRIOR.practice_common_actions
    if type(common) == "table" then
        -- THE OFFER GATE: a common ability is offered on the running family only if
        -- that family publishes it (as neutral) or the rotation ranks it there - the
        -- offer list and the neutral set are one truth per family.
        local neutral = ST.WARRIOR.practice_neutral_set()
        local rotation = ST.WARRIOR.practice_rotation_action_set()
        for i = 1, #common do
            local action = common[i]
            if ST.WARRIOR.practice_common_offer_allowed(action, neutral, rotation) then
                local slot = ST.WARRIOR.resolve_practice_common_action(action)
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
function ST.WARRIOR.apply_practice_panel_actions()
    local guide = ST.WARRIOR.guide
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
    local widened = ST.WARRIOR.practice_panel_slots()
    if type(widened) ~= "table" or #widened <= #current then
        return false
    end
    guide.slots = widened
    return true
end

-- The APL's PRE-PULL rows: the opening sequence, per family, with the offset
-- relative to the pull in seconds (negative = before the pull). This is where
-- the operator's Charge belongs: the APLs carry Charge / Intercept / Battle
-- Shout / Bloodrage / Battle Stance / Berserker Rage / Recklessness / Death
-- Wish as PRE-PULL rows (the sims' prepullActions), not as rotation rows, and
-- the operator's HU-12 ruling (2026-10-20) is that the rotation table keeps
-- the APL's spell rows while the pre-pull rows carry their own table - the
-- shape ST.HUNTER.PRACTICE_PREPULLS already uses.
--
-- `at` is the offset relative to the pull in seconds (negative = before the
-- pull); the drill's lateness is measured against it. `spell` is the id the
-- Era-style clients resolve by (the TBC client resolves by the label's name).
-- The keys are the family tokens: SOD is the SoD branch of the ERA family
-- (the SoD build's own pre-pull), and the Era build's APL carries NO pre-pull
-- rows at all (no prepullActions key), so there is no ERA list. The consumable
-- rows the APLs also carry (the Healthstone 22788, the Diamond Flask 24427,
-- the OtherActionPotion rows) are items, not spells, and stay out.
ST.WARRIOR.PRACTICE_PREPULLS = {
    SOD = {
        {
            action = "berserker_stance", label = "Berserker Stance", spell = 2458, at = -1,
            source = "wowsims/sod ui/warrior/apls/phase_6_dw.apl.json (prepullActions: "
                .. "Berserker Stance 2458 at -1s)",
        },
        {
            action = "bloodrage", label = "Bloodrage", spell = 2687, at = -5,
            source = "wowsims/sod ui/warrior/apls/phase_6_dw.apl.json (prepullActions: "
                .. "Bloodrage 2687 at -5s)",
        },
    },
    TBC = {
        {
            action = "berserker_rage", label = "Berserker Rage", spell = 18499, at = -4.5,
            source = "wowsims/tbc-new ui/specs/warrior/dps/apls/fury.apl.json "
                .. "(prepullActions: Berserker Rage 18499 at -4.5s - the same row in "
                .. "arms.apl.json)",
        },
        {
            action = "bloodrage", label = "Bloodrage", spell = 2687, at = -3,
            source = "wowsims/tbc-new ui/specs/warrior/dps/apls/fury.apl.json "
                .. "(prepullActions: Bloodrage 2687 at -3s - the same row in "
                .. "arms.apl.json)",
        },
        {
            action = "battle_shout", label = "Battle Shout", spell = 2048, at = -3,
            source = "wowsims/tbc-new ui/specs/warrior/dps/apls/fury.apl.json "
                .. "(prepullActions: Battle Shout 2048 at -3s - the TBC client's rank "
                .. "8; its rank 7 is 25289)",
        },
        {
            action = "charge", label = "Charge", spell = 11578, at = -0.9,
            source = "wowsims/tbc-new ui/specs/warrior/dps/apls/fury.apl.json "
                .. "(prepullActions: the `Pre-pull: Move` group at -0.9s, whose first "
                .. "row casts Charge 11578 rank 3 while the Battle Stance aura 2457 "
                .. "is active - Charge needs 8-25 yd, wowsims/tbc-new "
                .. "sim/warrior/spell_data_auto_gen.go, the Charge table: MinRange 8, "
                .. "MaxRange 25)",
        },
        {
            action = "intercept", label = "Intercept", spell = 25275, at = -0.9,
            source = "wowsims/tbc-new ui/specs/warrior/dps/apls/fury.apl.json "
                .. "(prepullActions: the same `Pre-pull: Move` group, whose second "
                .. "row casts Intercept 25275 rank 5 while the Berserker Stance aura "
                .. "2458 is active - the TBC client's rank 5; the Forever client's "
                .. "rank 3 is 20617)",
        },
    },
    FOREVER = {
        {
            action = "berserker_rage", label = "Berserker Rage", spell = 18499, at = -4.5,
            source = "wowsims/forever ui/specs/warrior/dps/apls/arms.apl.json "
                .. "(prepullActions: Berserker Rage 18499 at -4.5s - the same row in "
                .. "fury.apl.json)",
        },
        {
            action = "battle_stance", label = "Battle Stance", spell = 2457, at = -4,
            specs = { arms = true },
            source = "wowsims/forever ui/specs/warrior/dps/apls/arms.apl.json "
                .. "(prepullActions: the `Pre-pull: Stance` group at -4s, which casts "
                .. "Battle Stance 2457 - the arms APL only; the fury APL has no "
                .. "stance group)",
        },
        {
            action = "bloodrage", label = "Bloodrage", spell = 2687, at = -3,
            source = "wowsims/forever ui/specs/warrior/dps/apls/arms.apl.json "
                .. "(prepullActions: Bloodrage 2687 at -3s - the same row in "
                .. "fury.apl.json)",
        },
        {
            action = "battle_shout", label = "Battle Shout", spell = 25289, at = -3,
            source = "wowsims/forever ui/specs/warrior/dps/apls/arms.apl.json "
                .. "(prepullActions: Battle Shout 25289 at -3s - the Forever client's "
                .. "rank 6; the TBC client's rank 8 is 2048)",
        },
        {
            action = "charge", label = "Charge", spell = 11578, at = -0.9,
            source = "wowsims/forever ui/specs/warrior/dps/apls/arms.apl.json "
                .. "(prepullActions: the `Pre-pull: Move` group at -0.9s, whose first "
                .. "row casts Charge 11578 rank 3 while the Battle Stance aura 2457 "
                .. "is active)",
        },
        {
            action = "intercept", label = "Intercept", spell = 20617, at = -0.9,
            source = "wowsims/forever ui/specs/warrior/dps/apls/arms.apl.json "
                .. "(prepullActions: the same `Pre-pull: Move` group, whose second "
                .. "row casts Intercept 20617 rank 3 while the Berserker Stance aura "
                .. "2458 is active - the Forever client's rank 3; the TBC client's "
                .. "rank 5 is 25275)",
        },
    },
    WRATH = {
        {
            action = "berserker_stance", label = "Berserker Stance", spell = 2458, at = -20,
            specs = { fury = true },
            source = "wowsims/wotlk ui/warrior/apls/fury.apl.json (prepullActions: "
                .. "Berserker Stance 2458 at -20s)",
        },
        {
            action = "bloodrage", label = "Bloodrage", spell = 2687, at = -10,
            source = "wowsims/wotlk ui/warrior/apls/arms.apl.json and fury.apl.json "
                .. "(prepullActions: Bloodrage 2687 at -10s on both)",
        },
        {
            action = "berserker_rage", label = "Berserker Rage", spell = 18499, at = -5,
            specs = { fury = true },
            source = "wowsims/wotlk ui/warrior/apls/fury.apl.json (prepullActions: "
                .. "Berserker Rage 18499 at -5s)",
        },
        {
            action = "recklessness", label = "Recklessness", spell = 1719, at = -3,
            source = "wowsims/wotlk ui/warrior/apls/arms.apl.json and fury.apl.json "
                .. "(prepullActions: Recklessness 1719 at -3s on both)",
        },
        {
            action = "battle_stance", label = "Battle Stance", spell = 2457, at = -2,
            specs = { arms = true },
            source = "wowsims/wotlk ui/warrior/apls/arms.apl.json (prepullActions: "
                .. "Battle Stance 2457 at -2s)",
        },
        {
            action = "death_wish", label = "Death Wish", spell = 12292, at = -1.5,
            specs = { fury = true },
            source = "wowsims/wotlk ui/warrior/apls/fury.apl.json (prepullActions: "
                .. "Death Wish 12292 at -1.5s - the arms APL has no Death Wish row)",
        },
    },
}

-- The practice helpers (one local for the whole surface: Lua 5.1 caps a
-- function at 200 locals, and five separate locals would eat the chunk's
-- budget). The table's functions close over the local, so they call each
-- other.
local practice = {}

-- The practice inputs: the engine's frozen input names, filled from the
-- context. Every field is written on every call (nil included), so a stale
-- reading can never survive between ticks.
function practice.inputs(self, ctx, out)
    out = out or {}
    if type(ctx) ~= "table" then
        return nil
    end
    local res = type(ctx.resources) == "table" and ctx.resources or {}
    local cds = type(ctx.cooldowns) == "table" and ctx.cooldowns or {}

    out.rage = res.rage
    out.hs_cost = res.hs_cost
    out.cleave_cost = res.cleave_cost
    out.bt_cost = res.bt_cost
    out.ww_cost = res.ww_cost
    out.target_health_pct = res.target_health_pct
    out.execute_pct = res.execute_pct
    out.hs_queued = res.hs_queued == true
    out.cleave_queued = res.cleave_queued == true
    out.has_bloodsurge = res.has_bloodsurge == true
    out.slam_casting = res.slam_casting == true
    out.overpower_remaining = res.overpower_remaining
    out.swing_remaining = res.swing_remaining
    out.gcd_remaining = res.gcd_remaining
    out.speed = res.speed
    out.offhand_swing_remaining = res.offhand_swing_remaining
    out.dual_wielding = res.dual_wielding == true
    out.hs_rage_floor = res.hs_rage_floor
    out.core_reserve_window = res.core_reserve_window
    out.execute_spam = res.execute_spam == true
    -- The APL's execute-phase clause on the dump (the provider arms it on TBC and
    -- Forever; a caller that does not carry it leaves the dump alone, exactly
    -- like the other family flags above - the scenario's own context decides).
    out.execute_phase_dump_gate = res.execute_phase_dump_gate == true
    out.sunder_stacks = res.sunder_stacks
    out.sunder_remaining = res.sunder_remaining
    out.rend_remaining = res.rend_remaining
    out.rend_upkeep_enabled = res.rend_upkeep_enabled == true
    out.hamstring_known = res.hamstring_known == true
    out.hamstring_rage_threshold = res.hamstring_rage_threshold
    out.sudden_death = res.sudden_death == true
    out.victory_rush = res.victory_rush == true
    out.stance = res.stance

    out.bt_remaining = cds.bt
    out.ww_remaining = cds.ww
    out.op_remaining = cds.op
    out.execute_remaining = cds.execute
    out.slam_remaining = cds.slam
    out.hs_remaining = cds.hs
    out.cleave_remaining = cds.cleave
    out.raging_blow_remaining = cds.raging_blow
    out.ms_remaining = cds.ms
    out.bladestorm_remaining = cds.bladestorm
    out.bladestorm_known = res.bladestorm_known == true

    -- The utility spine's rows: the caller's cooldowns and flags (the shared
    -- engine's context carries them from the gather: the cooldowns under the
    -- action's own key, the flags beside it). The APL's order and the stance
    -- rows come from the class's own family gate, so the practice pick grades the
    -- same rotation the live guide plays. A row the caller does not carry stays
    -- unknown, and an unknown row never prompts.
    local utility_high, utility_low = ST.WARRIOR.utility_order(self)
    out.utility_order = utility_high
    out.utility_order_low = utility_low
    out.utility_wanted_stance = ST.WARRIOR.utility_wanted_stance(self)
    if ST.WARRIOR.utility_weaves(self) then
        out.utility_weave = true
    else
        out.utility_weave = nil
    end
    out.utility_stance = res.utility_stance
    for _, key in ipairs(WARRIOR_UTILITY.keys) do
        local remaining_name = key .. "_remaining"
        local buff_name = key .. "_buff"
        local known_name = key .. "_known"
        local rage_max_name = key .. "_rage_max"
        out[remaining_name] = cds[key]
        out[buff_name] = res[buff_name]
        out[known_name] = res[known_name]
        out[rage_max_name] = res[rage_max_name]
    end

    -- The branch flags: the context may name them, otherwise the class's own
    -- frozen branch answers (the same flags the live gather feeds).
    local function flag(ctx_value, self_value)
        if ctx_value ~= nil then
            return ctx_value == true or nil
        end
        if self_value ~= nil then
            return self_value == true or nil
        end
        return nil
    end
    local owner = type(self) == "table" and self or nil
    out.wrath_arms = flag(res.wrath_arms, owner and owner.warrior_is_arms)
    out.sod = flag(res.sod, owner and owner.warrior_is_sod)
    if out.wrath_arms == true or out.sod == true then
        out.wrath_fury = nil
    elseif res.wrath_fury ~= nil then
        out.wrath_fury = res.wrath_fury == true or nil
    else
        out.wrath_fury = (st.family == "WRATH") or nil
    end
    return out
end

-- The engine's pick for this context: the same path the live guide uses, so
-- the practice pick and the live pick can never disagree.
function practice.expected(self, ctx)
    local inputs = practice.inputs(self, ctx, {})
    if not inputs then
        return nil, nil
    end
    local guide = ST.WARRIOR.guide
    if not (guide and guide.evaluate) then
        return nil, nil
    end
    local out = {}
    guide.evaluate(inputs, out)
    return out.action, out
end

-- The drill's rage pool (the shared practice model, read-only here): the
-- context's rage reading, capped at the classic cap. An unreadable pool
-- answers nil (the drill grades "unknown", never a guess).
function practice.rage_pool(ctx)
    local pr = st.practice
    if not (pr and pr.rage_can_spend and pr.new_rage_state) then
        return nil
    end
    local res = type(ctx) == "table" and type(ctx.resources) == "table"
        and ctx.resources or {}
    local rage = res.rage
    if type(rage) ~= "number" or rage ~= rage then
        return nil
    end
    return pr.new_rage_state({ rage = rage })
end

-- The cost of an action for the drill: the context's own cost reading when it
-- has one, else the shared model's fixed sim costs (BT 30, WW 25, Slam 15,
-- OP 5 - the sim spell files behind each number). Heroic Strike and Cleave
-- are rank-variable, so they use the context's cost only.
function practice.action_cost(action, inputs)
    local pr = st.practice
    local costs = pr and pr.WARRIOR_RAGE_COSTS or nil
    if action == "bt" then
        return inputs.bt_cost or (costs and costs.bt) or nil
    elseif action == "ww" then
        return inputs.ww_cost or (costs and costs.ww) or nil
    elseif action == "slam" then
        return (costs and costs.slam) or nil
    elseif action == "op" then
        return (costs and costs.op) or nil
    elseif action == "hs" then
        return inputs.hs_cost
    elseif action == "cleave" then
        return inputs.cleave_cost
    end
    return nil
end

-- The audit's reserve violation (D-W1): the press spends rage that a core
-- sitting inside the reserve window needs. The core is inside the window when
-- it lands within it (and is not ready now); the spend starves it when the
-- rage left over would not cover the core's cost.
function practice.starved_core(inputs, spend)
    local window = inputs.core_reserve_window
    if type(window) ~= "number" then
        window = st.warrior_guide and st.warrior_guide.CORE_RESERVE_WINDOW or 1.5
    end
    local rage = inputs.rage
    if type(rage) ~= "number" or type(spend) ~= "number" then
        return false
    end
    local function violates(remaining, cost)
        if type(remaining) ~= "number" or remaining <= 0 then
            return false
        end
        if remaining > window or type(cost) ~= "number" then
            return false
        end
        return rage - spend < cost
    end
    return violates(inputs.bt_remaining, inputs.bt_cost or 30)
        or violates(inputs.ww_remaining, inputs.ww_cost or 25)
end

-- The scenario step: what the rotation wants at this tick.
--   -> { action = "<key>", reason = "<text>" } | nil
--   -> { action = nil, hold = true, reason = "<text>" }   -- an explicit HOLD
-- A guide HOLD is a DECISION, not an unknown (the operator ruling HU-8, hands-up
-- 2026-10-19: HOLD-IS-A-DECISION): the guide's RIDE window (a queued HS/Cleave
-- the player already placed) and its HOLD window (the filler's rage shortfall)
-- state the hold explicitly, so the engine can tell a hold (casting then is an
-- illegal cast) from an unknown (no attempt at all). The hold text is the
-- guide's own caption - never a guess.
-- A verdict that NAMES an action stays an action: the guide's CANCEL cue (the
-- queued spend the Execute press kills) names the Execute, so the practice pick
-- and the live pick can never disagree. A state the guide cannot read stays
-- unknown.
function ST.WARRIOR.practice_scenario_step(self, ctx)
    local action, out = practice.expected(self, ctx)
    if type(out) ~= "table" then
        return nil
    end
    if type(action) == "string" and action ~= "" then
        local reason
        if st.warrior_guide and st.warrior_guide.action_reason then
            reason = st.warrior_guide.action_reason(action)
        end
        return { action = action, reason = reason or action }
    end
    if out.hold == true then
        local reason = out.hold_text
        if type(reason) ~= "string" or reason == "" then
            reason = "HOLD"
        end
        return { action = nil, hold = true, reason = reason }
    end
    return nil
end

-- The warrior's own drills (the audited target set,
-- bench/class_features_drills_2026-10-19.md section 2.2 (C)). Each grade
-- function judges ONE decision and answers nil when it cannot judge it.
--
-- The pre-pull drill's lateness bands (the hunter's shape, [DESIGN] - the sims fix
-- the sequence and its offsets, the band edges are the grading design): the due
-- opener's window runs to the next opener's offset, so a press inside the window is
-- on time.
ST.WARRIOR.PRACTICE_PREPULL_LATE_BANDS = {
    { max = 1, grade = "A" },
    { max = 3, grade = "B" },
    { max = 5, grade = "C" },
    { grade = "D" },
}
-- The fallback window after the LAST opener of a sequence ([DESIGN]): the sims' own
-- spacing gives the gaps between the openers, but nothing bounds the last one.
ST.WARRIOR.PRACTICE_PREPULL_WINDOW_SECONDS = 5
ST.WARRIOR.practice_drills = {
    {
        key = "warrior_core_order",
        label = "The core rotation",
        kind = "rotation_order",
        title = "The core rotation",
        description = "Overpower -> Execute -> Bloodsurge Slam -> Bloodthirst -> "
            .. "Whirlwind -> the rage dump, without starving the core.",
        grade = function(self, ctx)
            local inputs = practice.inputs(self, ctx, {})
            if not inputs then
                return nil
            end
            local expected = practice.expected(self, ctx)
            if expected == nil then
                return nil
            end
            local press = type(ctx) == "table" and ctx.last_action or nil
            if type(press) ~= "string" then
                return nil
            end
            if press == expected then
                return "S"
            end
            -- A mis-pick. The audit's hard F: a spend that starved a core
            -- sitting inside the reserve window.
            local spend = practice.action_cost(press, inputs)
            if spend ~= nil and practice.starved_core(inputs, spend) then
                return "F"
            end
            return "D"
        end,
    },
    {
        key = "warrior_ww_delay",
        label = "The core window",
        kind = "rotation_window",
        title = "The core window",
        description = "Whirlwind only while Bloodthirst is more than 1.5 s out.",
        grade = function(self, ctx)
            local press = type(ctx) == "table" and ctx.last_action or nil
            if press ~= "ww" then
                -- Only the Whirlwind press is this drill's decision; every
                -- other press belongs to the core-order drill.
                return nil
            end
            local inputs = practice.inputs(self, ctx, {})
            local bt_remaining = inputs.bt_remaining
            if type(bt_remaining) ~= "number" then
                return nil
            end
            local pool = practice.rage_pool(ctx)
            if not pool then
                return nil
            end
            local cost = practice.action_cost("ww", inputs)
            if cost == nil then
                return nil
            end
            local pr = st.practice
            if not pr.rage_can_spend(pool, cost, 0) then
                -- The press had no rage for either core.
                return "F"
            end
            if bt_remaining <= 0 then
                -- Bloodthirst was ready: the press took its GCD.
                return "F"
            end
            local margin = bt_remaining - st.warrior_guide.WW_DELAY
            return st.warrior_guide.ww_delay_band(margin)
        end,
    },
    {
        key = "warrior_sunder_upkeep",
        label = "The debuff upkeep",
        kind = "situational",
        title = "The debuff upkeep",
        description = "Keep Sunder stacked (five stacks, refreshed inside the "
            .. "final 10 s) without stealing a proc, the Execute range or a "
            .. "queued ride.",
        grade = function(self, ctx)
            local inputs = practice.inputs(self, ctx, {})
            local expected = practice.expected(self, ctx)
            if expected == nil then
                return nil
            end
            local press = type(ctx) == "table" and ctx.last_action or nil
            if type(press) ~= "string" then
                return nil
            end
            if press == "sunder" and expected ~= "sunder" then
                -- A press the rotation should have yielded (a proc, the
                -- Execute range, a queued ride).
                return "F"
            end
            if press ~= "sunder" then
                if expected == "sunder" then
                    -- The upkeep was dropped: the debuff runs out.
                    return "F"
                end
                return nil
            end
            local stacks = inputs.sunder_stacks
            if type(stacks) ~= "number" then
                return nil
            end
            -- A Sunder Armor application adds one stack, capped at five (the
            -- sim's own upkeep line fires below five stacks).
            local after = stacks + 1
            if after > st.warrior_guide.SUNDER_STACKS_MAX then
                after = st.warrior_guide.SUNDER_STACKS_MAX
            end
            return st.warrior_guide.sunder_upkeep_band(after)
        end,
    },
    {
        key = "warrior_execute_burn",
        label = "The execute burn",
        kind = "transition",
        title = "The execute burn",
        description = "Cross 20 % with the pool banked and burn it on Execute, "
            .. "with the core released.",
        grade = function(self, ctx)
            local inputs = practice.inputs(self, ctx, {})
            local res = type(ctx) == "table" and type(ctx.resources) == "table"
                and ctx.resources or {}
            local health = inputs.target_health_pct
            if type(health) ~= "number" then
                return nil
            end
            local execute_pct = inputs.execute_pct
            if type(execute_pct) ~= "number" then
                execute_pct = st.warrior_guide.EXECUTE_PCT_DEFAULT
            end
            local press = type(ctx) == "table" and ctx.last_action or nil
            if type(press) ~= "string" then
                return nil
            end
            if health >= execute_pct then
                if press == "execute" then
                    -- Execute above the threshold.
                    return "F"
                end
                return nil
            end
            local expected = practice.expected(self, ctx)
            if expected == nil then
                return nil
            end
            if expected ~= "execute" then
                -- The engine is holding the core (the TBC reservation); this
                -- drill has no decision to grade.
                return nil
            end
            if press ~= "execute" then
                -- The core was spent during the phase: no burn.
                return "F"
            end
            local pool = practice.rage_pool(ctx)
            if not pool then
                return nil
            end
            local pr = st.practice
            local entry_rage = 100
            if pr and pr.harness and pr.harness.EXECUTE_DEFAULTS then
                entry_rage = pr.harness.EXECUTE_DEFAULTS.entry_rage or entry_rage
            end
            local full = (pool.rage or 0) >= entry_rage
            local lateness
            local started = res.phase_started_at
            local now = type(ctx) == "table" and ctx.now or nil
            if type(started) == "number" and type(now) == "number" then
                lateness = (now - started) / 1.5
            end
            return st.warrior_guide.execute_burn_band(full, lateness)
        end,
    },
    {
        key = "warrior_hs_queue",
        label = "The queue window",
        kind = "rotation_window",
        title = "The queue window",
        description = "Queue Heroic Strike or Cleave so the offhand swing lands "
            .. "inside the ability: the queue lifts the offhand's dual-wield miss "
            .. "penalty (the 24 % a dual-wield swing pays).",
        source = "the queue aura sets PseudoStats.DisableDWMissPenalty = true "
            .. "on gain and false on expire (wowsims/classic + sod + tbc-new + "
            .. "forever sim/warrior/heroic_strike_cleave.go); the tbc-new comment "
            .. "on consumeQueue: \"The queue lifts the dual-wield miss penalty, "
            .. "so it ends after the hit roll\"; the +19 % penalty itself in "
            .. "sim/core/spell_outcome.go and the 5 % white base chance in "
            .. "sim/core/target.go:312 (24 % together); the queue replaces the "
            .. "mainhand swing (dps_warrior.go:54 \"ReplaceMHSwing: "
            .. "war.TryHSOrCleave\"), so the press window is the gap between the "
            .. "mainhand's last swing and the offhand's next one. The sim's own "
            .. "250 ms queue delay is its reaction-time model, not a client fact "
            .. "- the in-client lift timing is UNCONFIRMED IN-CLIENT.",
        grade = function(self, ctx)
            -- Only a Heroic Strike / Cleave press is this drill's decision: the
            -- queue window is about WHEN the on-next-attack ability is pressed.
            if type(ctx) ~= "table" then
                return nil
            end
            local press = ctx.last_action
            if press ~= "hs" and press ~= "cleave" then
                return nil
            end
            local inputs = practice.inputs(self, ctx, {})
            if not inputs then
                return nil
            end
            local guide = st.warrior_guide
            if not (guide and guide.hs_queue_grade) then
                return nil
            end
            return guide.hs_queue_grade(inputs)
        end,
    },
    {
        key = "warrior_prepull",
        label = "The opener",
        kind = "transition",
        title = "The opener",
        description = "Run the pre-pull sequence: the stance, the rage tools and the "
            .. "shout before the pull, then the Charge.",
        source = "the APLs' own prepullActions: wowsims/sod "
            .. "ui/warrior/apls/phase_6_dw.apl.json (Berserker Stance 2458 at -1s, "
            .. "Bloodrage 2687 at -5s); wowsims/tbc-new "
            .. "ui/specs/warrior/dps/apls/fury.apl.json (Berserker Rage 18499 at "
            .. "-4.5s, Bloodrage 2687 at -3s, Battle Shout 2048 at -3s, the "
            .. "`Pre-pull: Move` group - Charge 11578 and Intercept 25275 - at "
            .. "-0.9s); wowsims/forever ui/specs/warrior/dps/apls/arms.apl.json "
            .. "(the same rows plus Battle Stance 2457 at -4s, Intercept 20617); "
            .. "wowsims/wotlk ui/warrior/apls/fury.apl.json (Berserker Stance 2458 at "
            .. "-20s, Bloodrage 2687 at -10s, Berserker Rage 18499 at -5s, "
            .. "Recklessness 1719 at -3s, Death Wish 12292 at -1.5s)",
        grade = function(self, ctx)
            -- The pre-pull phase (the hunter's prepull drill shape): the family's own
            -- pre-pull rows, in their own order, with the offset relative to the
            -- pull. The rotation never asks for these rows - they are the opening
            -- sequence, not the combat rotation.
            if type(ctx) ~= "table" then
                return nil
            end
            local family = nil
            if self.warrior_is_sod == true then
                family = "SOD"
            elseif st.family == "TBC" or st.family == "FOREVER" or st.family == "WRATH" then
                family = st.family
            end
            local prepulls = family and ST.WARRIOR.PRACTICE_PREPULLS[family] or nil
            if type(prepulls) ~= "table" or #prepulls == 0 then
                return nil -- no sourced pre-pull sequence for this client
            end
            local now = ctx.now
            if type(now) ~= "number" or now ~= now then
                return nil
            end
            -- The pull clock: the caller's own pull moment wins (an offline run that
            -- drives the drill directly); the drill's synthetic clock opens the
            -- countdown at the family's first opener (the hunter's shape).
            local pull_time = nil
            local to_pull = ctx.time_to_pull
            if to_pull == nil then
                to_pull = ctx.pull_in
            end
            if to_pull == nil then
                to_pull = ctx.time_to_pull_seconds
            end
            if to_pull == nil then
                to_pull = ctx.pull_in_seconds
            end
            if type(to_pull) == "number" and to_pull == to_pull then
                pull_time = -to_pull
            elseif type(ctx.pull_at) == "number" and ctx.pull_at == ctx.pull_at then
                pull_time = now - ctx.pull_at
            end
            if pull_time == nil then
                local clock = self.warrior_prepull_clock
                if type(clock) ~= "table"
                    or (type(clock.last_at) == "number" and now < clock.last_at) then
                    local first = prepulls[1].at
                    if type(first) ~= "number" then
                        return nil
                    end
                    clock = { pull_at = now - first }
                    self.warrior_prepull_clock = clock
                end
                clock.last_at = now
                pull_time = now - clock.pull_at
            end
            -- The due opener: the latest one whose window has opened.
            local expected, expected_at = nil, nil
            for i = 1, #prepulls do
                local opener = prepulls[i]
                if pull_time >= opener.at then
                    expected, expected_at = opener, opener.at
                end
            end
            if expected == nil then
                return nil -- nothing is due yet
            end
            local function late_band(late)
                for i = 1, #ST.WARRIOR.PRACTICE_PREPULL_LATE_BANDS do
                    local band = ST.WARRIOR.PRACTICE_PREPULL_LATE_BANDS[i]
                    if late <= band.max then
                        return band.grade
                    end
                end
                return "D"
            end
            local pressed = ctx.last_action
            if pressed ~= nil then
                if pressed ~= expected.action then
                    -- A different opener: the due one was missed.
                    return "D"
                end
                local late = pull_time - expected_at
                if late <= 0 then
                    return "S" -- on time (or early)
                end
                return late_band(late)
            end
            -- No pick: the moment itself is the judgement. The opener's window is the
            -- span up to the next opener's offset (the sims' own spacing).
            local next_at = nil
            for i = 1, #prepulls do
                if prepulls[i].at > expected_at then
                    next_at = prepulls[i].at
                    break
                end
            end
            if next_at == nil then
                next_at = expected_at + ST.WARRIOR.PRACTICE_PREPULL_WINDOW_SECONDS
            end
            if pull_time < next_at then
                return "S" -- inside the due opener's window
            end
            return late_band(pull_time - next_at)
        end,
    },
}

-- The drill this class's session runs: the class's OWN drill - the execute
-- phase (the transition into the execute phase and the burn that follows). The
-- retired built-in ("warrior_execute") stays registered for backward
-- compatibility and the engine names this drill as the owner of the skill
-- (practice.lua H.SUPERSEDED_DRILLS), so the class's own session never runs the
-- built-in and the class's own grade function is the single truth for the
-- execute phase.
ST.WARRIOR.PRACTICE_DRILL_KEY = "warrior_execute_burn"

-- The class's own drill key, or nil when the class publishes no such drill
-- (unknown-hides: nothing names a drill the class does not own).
function ST.WARRIOR.practice_drill_key()
    local key = ST.WARRIOR.PRACTICE_DRILL_KEY
    if type(key) ~= "string" or key == "" then
        return nil
    end
    local drills = ST.WARRIOR.practice_drills
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

--=========================================================================================
-- Shared practice-panel facts (class-isolation 2026-10-21)
--=========================================================================================
-- The warrior publishes no drill panel route (its practice is its own drill
-- list), but its progression scope is still its OWN fact: the shared progression
-- layer reads it here instead of a class-keyed table in shared code.
ST.WARRIOR.practice_panel = {
    progress = {
        -- The warrior owns no twist drill: its scope is its own core-order drill
        -- (never the shared twist one), the drill its session actually runs.
        mode = "warrior_execute_burn",
        scenario = "warrior_rotation",
        drills = {
            "warrior_core_order", "warrior_ww_delay",
            "warrior_sunder_upkeep", "warrior_execute_burn",
        },
    },
}

if st.debug then st.utils.print_msg('-- Parsed classes/warrior.lua module correctly') end

end

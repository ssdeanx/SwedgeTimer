--=========================================================================================
-- Module for Hunter-specific behaviours
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
st.class_loaders = st.class_loaders or {}
st.class_loaders["HUNTER"] = function()
-- Cross-client API wrappers (see compat.lua).
local api = st.api
local get_tab = st.utils.convert_lookup_table

-- TBC Anniversary spell-state queries take NAMES, not ids (operator client
-- fact; docs/hunter-wa.json converts every tracked id through GetSpellInfo
-- and then compares names, e.g. GetSpellInfo(75/2974/8149-range, 34600,
-- 1499/13795/13813/13809 trap families)). Classic Era takes ids.
-- spell_token() maps a spell id to the safe token for a per-spell state
-- query (IsCurrentSpell, IsSpellKnown, GetSpellCooldown, IsSpellInRange,
-- IsAutoRepeatSpell, IsSpellUsable): the localized name on TBC (nil while
-- the client's spell data has not answered - unknown hides, never a bare
-- id), the id unchanged everywhere else. WA id->name mapping, resolved live
-- (never hardcoded, so locales keep working): 75 Auto Shot, 2974 Wing Clip,
-- 2973 Raptor Strike, 2643 Multi-Shot, 19434 Aimed Shot, 34120 Steady Shot,
-- 34026 Kill Command, 19574 Bestial Wrath, 3045 Rapid Fire, 23989 Readiness,
-- 34074 Aspect of the Viper.
local function spell_token(spell_id)
    if st.family ~= "TBC" then
        return spell_id
    end
    if spell_id == nil then
        return nil
    end
    return api.GetSpellInfo(spell_id)
end

-- Probe tokens for the on-next-attack queue reads: bare ids everywhere except
-- TBC, where the state APIs take names (see above). On TBC the tokens are the
-- distinct localized family names (every rank shares one name, so one read
-- covers the family); an empty list while the spell data has not answered
-- (unknown hides, no probe at all).
local function queue_tokens(id_table)
    if st.family ~= "TBC" then
        local tokens = {}
        for spell_id in pairs(id_table) do
            tokens[#tokens + 1] = spell_id
        end
        return tokens
    end
    local tokens, seen = {}, {}
    for spell_id in pairs(id_table) do
        local name = api.GetSpellInfo(spell_id)
        if name and not seen[name] then
            seen[name] = true
            tokens[#tokens + 1] = name
        end
    end
    return tokens
end

--=========================================================================================
-- Spell data
--=========================================================================================
-- Raptor Strike, all ranks across the classic families (vanilla -> BCC -> WotLK).
-- The lookup table keeps every rank id; get_family_spell_id picks the highest id
-- that exists on the running client (the current rank). 14266 is the rank 8 the
-- SoD and Forever clients carry (wowsims/sod and wowsims/forever APLs cast it:
-- the SoD p7_weave APL's i=16 and the Forever APL's i=1), so the utility layer's
-- Raptor Strike read resolves a rank on those two families too.
local raptor_strike_ids = get_tab({
    2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266, 27014, 48995, 48996
})

-- Steady Shot ranks across the classic families (56641 is the shared base id,
-- 34120 the TBC-era rank; 49051 and 49052 are the WotLK ranks). The exact id set
-- must be confirmed in-client: an id missing from this table is simply never
-- detected, so the queue colour for that rank stays inert.
local steady_shot_ids = get_tab({
    56641, 34120, 49051, 49052
})

-- The Steady Shot id PER FAMILY: the icon fallback of the guide slot and of the
-- HUD slot, replaced by the client's own rank the moment the resolver answers
-- (resolve_guide_icons). One owner for both surfaces, so the two can never
-- disagree. 56641 is NOT a fallback on any client past 2.2 - it is the vanilla
-- rank and it does not exist on the TBC client at all (the corpus correction of
-- 2026-10-20, bench/rotation_gap_vs_apl_2026-10-20.md §0.0 H3), which is why
-- the HUD slot used to carry no name (and no icon) there.
--   ERA             56641  (the vanilla rank. The Era guide set and the HUD's Era
--                          pick DROP the Steady slot there, so no Steady prompt
--                          ever fires on Era; the id stays because the gather's
--                          RANGE probe reads it - the shipped Era behaviour, kept
--                          exactly as it is)
--   TBC             34120  (the TBC rank the APL casts: bench/ids_research_
--                          2026-10-19.md §2 "34120 | Steady Shot (TBC rank)";
--                          bench/rotation_gap_vs_apl_2026-10-20.md §0.0 H3)
--   WRATH           49052  (the WotLK rank the APLs cast: bench/ids_research_
--                          2026-10-19.md §2 "49052 | Steady Shot", scrape OK)
--   CATA/MISTS/RETAIL 56641 (the retail-line clients keep the CLASSIC Steady Shot
--                          id: wowsims/cata sim/hunter/steady_shot.go:12 spells it
--                          56641 on the 4.3.4 client, and wowhead's own Mists and
--                          retail pages are /mop-classic/spell=56641 and
--                          /spell=56641. 49052 is the WotLK rank and exists on none
--                          of those three - the steady lane's 49052 was a
--                          CLIENT-UNCONFIRMED guess, now corrected)
-- The FOREVER family carries NO entry: the Forever client has NO Steady Shot at
-- all (§0.0 H4 - the spell arrived in 2.3 and the Forever spell data carries no
-- SteadyShot table), so neither the guide nor the HUD ships the slot and no
-- Steady probe is spent there.
local steady_id_by_family = {
    ERA = 56641,
    TBC = 34120,
    WRATH = 49052,
    CATA = 56641,
    MISTS = 56641,
    RETAIL = 56641,
}

-- The spell slot ids PER FAMILY: the client's OWN rank for that family, so a slot
-- never points at a spell the running client does not have. ONE owner for both
-- surfaces: the HUD slot and the guide slot of a key read the same entry here, so
-- the two can never disagree about which spell the running client has. A family
-- with NO entry for a key cannot have that spell: the HUD's dead-slot filter drops
-- the slot and the guide's slot set does not declare it.
--
-- The ERA family carries a BUILD dimension as well: the same 1.15.9 client runs
-- the Era-base game AND the SoD game, and the two games do not carry the same
-- spells (the SoD client HAS the Bestial Wrath - the 1.15.9 client's own spell
-- data maps 19574 to the Beast Mastery skill line). A BUILD cell (SOD) is read
-- only when the class's own SoD probe says the SoD build is running: the Chimera
-- Shot rune (409433) is a SoD-only spell, so knowledge of it IS the detector
-- (SoD shares the ERA family token, so the family alone never decides).
--
-- Evidence (fetched 2026-10-20, recorded in bench/hunter_hud_family_2026-10-20.md):
--   SIM-CONFIRMED  the client's own hunter spell data in the wowsims repo of that
--                  family (the generated table IS the client's spell data - the ids
--                  and their rank ladders come from the client itself).
--   WEB-CONFIRMED  the client's own version page on wowhead (/classic/, /tbc/,
--                  /wotlk/, /mop-classic/, /forever/, or the retail default).
--   CLIENT-UNCONFIRMED  the corpus carries only a bench claim for that family; the
--                  client's own rank replaces the fallback at post_init.
local SPELL_ID_BY_FAMILY = {
    -- Steady Shot: the Steady slot's own owner (steady_id_by_family above).
    steady = steady_id_by_family,
    -- Raptor Strike: the client's own rank - the top of the ladder it carries.
    raptor = {
        ERA = 14266,      -- wowsims/classic sim/hunter/raptor_strike.go:11 (the ladder
                          -- tops at 14266; the SoD APL's i=16 casts it)
        TBC = 27014,      -- wowsims/tbc-new sim/hunter/spell_data_auto_gen.go
        WRATH = 48996,    -- wowsims/wotlk sim/hunter/raptor_strike.go:11
        FOREVER = 14266,  -- wowsims/forever sim/hunter/spell_data_auto_gen.go; the
                          -- Forever APL's i=1 casts it
        CATA = 2973,      -- the Cata CLASSIC client's own spell data (the client this
                          -- addon targets: interface 40402): warcraftdb's Cata
                          -- expansion domain answers "Raptor Strike - Cataclysm" for
                          -- 2973, and 48996 - the RETAIL Cata rank the earlier
                          -- citation used - is NOT in that client's table at all.
        -- The Mists cell is deliberately EMPTY: the Mists client's own spell data
        -- (warcraftdb's MoP expansion domain) carries NO Raptor Strike among the
        -- ranks this table knows - 2973, 14260..14266, 27014, 48995 and 48996 all
        -- answer "Not Found" there - and an id is never guessed. The Mists HUD
        -- drops the slot (the dead-slot filter) and the guide's Mists set does not
        -- declare it, so no surface points at a spell that client cannot have.
        RETAIL = 186270,  -- wowhead.com/spell=186270/raptor-strike (the retail page)
    },
    -- Multi-Shot: the client's own rank.
    multi = {
        ERA = 25294,      -- wowsims/classic sim/hunter/multi_shot.go:11 (the ladder
                          -- tops at 25294; the Era APL's i=3 casts it)
        TBC = 27021,      -- wowsims/tbc-new sim/hunter/spell_data_auto_gen.go; the TBC
                          -- APL's i=5 casts it
        WRATH = 49048,    -- wowsims/wotlk sim/hunter/multi_shot.go:14
        FOREVER = 2643,   -- wowsims/forever sim/hunter/spell_data_auto_gen.go (the
                          -- Forever client's ONLY Multi rank; its APL's i=13 casts it)
        CATA = 2643,      -- wowsims/cata sim/hunter/multi_shot.go:12
        MISTS = 2643,     -- wowhead.com/mop-classic/spell=2643/multi-shot
        RETAIL = 2643,    -- wowhead.com/spell=2643/multi-shot (the retail page)
    },
    -- Aimed Shot: the vanilla ladder on the classic-line clients, the TBC r7 and
    -- the WotLK instant shot on those two.
    aimed = {
        ERA = 20904,      -- wowsims/classic sim/hunter/aimed_shot.go:11 (the ladder
                          -- tops at 20904; the Era APL's i=2 casts it)
        TBC = 27065,      -- wowsims/tbc-new sim/hunter/spell_data_auto_gen.go
        WRATH = 49050,    -- wowsims/wotlk sim/hunter/aimed_shot.go:16
        FOREVER = 20904,  -- wowsims/forever sim/hunter/spell_data_auto_gen.go; the
                          -- Forever APL's i=14 casts it
        CATA = 19434,     -- wowsims/cata sim/hunter/marksmanship/aimed_shot.go
        MISTS = 19434,    -- wowhead.com/mop-classic/spell=19434/aimed-shot
        RETAIL = 19434,   -- wowhead.com/spell=19434/aimed-shot (the retail page)
    },
    -- Kill Command: the client has it on TBC and on WotLK. The Era and the Forever
    -- clients have NO entry - the Era client never learned the 2.1 spell, and the
    -- Forever client's own spell table carries no Kill Command at all - so the
    -- HUD's filter drops the slot there and the guide's slot sets do not declare
    -- it (the Forever guide set never had it).
    kill_command = {
        TBC = 34026,      -- wowsims/tbc-new sim/hunter/spell_data_auto_gen.go; the TBC
                          -- APL's i=2 casts it
        WRATH = 34026,    -- wowsims/wotlk sim/hunter/kill_command.go:13
        CATA = 34026,     -- wowsims/cata sim/hunter/kill_command.go:14
        MISTS = 34026,    -- wowhead.com/mop-classic/spell=34026/kill-command
        RETAIL = 34026,   -- wowhead.com/spell=34026/kill-command (the retail page)
    },
    -- Bestial Wrath: the client's own rank. The ERA cell is empty on purpose - the
    -- Era-BASE game never uses the 2.1 talent, so its HUD pick drops the slot (and
    -- the guide's Era set does not declare it). The SoD BUILD of the same client HAS
    -- it, so the BUILD keys its own cell: the 1.15.9 client's own spell data maps
    -- 19574 to the Beast Mastery skill line (wow.export's Classic 1.15 Spell.csv +
    -- SkillLineAbility.csv), and SoD shares the ERA family token, so the family
    -- alone never decides.
    bestial_wrath = {
        SOD = 19574,      -- the 1.15.9 client's own Bestial Wrath (the SoD build's id)
        TBC = 19574,      -- the TBC BM signature (the module's own table note;
                          -- wowhead.com/tbc/spell=19574/bestial-wrath)
        WRATH = 19574,    -- wowsims/wotlk sim/hunter/talents.go:413
        FOREVER = 19574,  -- wowsims/forever sim/hunter/spell_data_auto_gen.go
        CATA = 19574,     -- wowsims/cata sim/hunter/bm_talents.go:139
        MISTS = 19574,    -- wowhead.com/mop-classic/spell=19574/bestial-wrath
        RETAIL = 19574,   -- wowhead.com/spell=19574/bestial-wrath (the retail page)
    },
    -- Rapid Fire: the client's own rank.
    rapid_fire = {
        ERA = 3045,       -- wowsims/classic sim/hunter/rapid_fire.go:14
        TBC = 3045,       -- wowhead.com/tbc/spell=3045/rapid-fire
        WRATH = 3045,     -- wowsims/wotlk sim/hunter/rapid_fire.go:11
        FOREVER = 3045,   -- wowsims/forever sim/hunter/spell_data_auto_gen.go
        CATA = 3045,      -- wowsims/cata sim/hunter/rapid_fire.go:11
        MISTS = 3045,     -- wowhead.com/mop-classic/spell=3045/rapid-fire
        RETAIL = 257044,  -- wowhead.com/spell=257044/rapid-fire (the retail page)
    },
}

-- Multi-Shot ranks, as listed by the reference (SuperSwingTimer_Constants.lua:452-459,
-- TBC-era set). Multi-Shot carries no steady-shot grace: its hidden window delays Auto
-- Shot on overlap, so a live Multi-Shot cast tints the cast bar unsafe past the bare
-- latency buffer (reference ApplyHunterCastBarColor, SuperSwingTimer_UI.lua:862-886).
-- The WotLK-era ranks are not in the reference table; an id missing here simply falls
-- back to the steady-shot grace, while the name match below covers the ranks whose ids
-- are present (the localized name is shared across ranks and needs in-client
-- confirmation like every other spell table). 49048 is the WotLK rank the MM and SV
-- APLs cast (wowsims/wotlk ui/hunter/apls/mm.apl.json i=9 and sv.apl.json i=10), so
-- the utility layer's WotLK Multi-Shot read resolves a rank there.
local multi_shot_ids = get_tab({
    2643, 14288, 14289, 14290, 25294, 27021, 49048
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
-- either data set) plus the SoD rune 409593 (wowsims/sod proto/hunter.proto:153,
-- RuneLegsKillShot). UNCONFIRMED: sourced from out-of-client references, not
-- from a 3.80.2 spell-cache read - confirm with GetSpellInfo on Wrath before
-- release. An id missing from this table is simply never detected, so the
-- guide prompt for it stays inert. The SoD rank is what the SoD APL's execute
-- (i=12) casts, so the utility layer's SoD execute resolves a rank there.
local kill_shot_ids = get_tab({
    34104, 53351, 409593,
})

-- Chimera Shot, the WotLK MM signature (wowhead wotlk spell 53209, instant).
-- Single rank on the WotLK client. Same UNCONFIRMED rule as Kill Command above.
local chimera_shot_wrath_ids = get_tab({
    53209,
})

-- Explosive Shot, the WotLK SV signature (wowhead wotlk spell 53301: instant,
-- 6 s cooldown). The LnL "434" downrank pair (wowsims/wotlk explosive_shot.go
-- SIM-CONFIRMED: R4 60053 / R3 60052, the /castsequence R4 -> R3 -> R4) shares
-- this table: get_family_spell_id resolves the highest rank the client knows,
-- and the cooldown read follows that rank (one shared cooldown across the
-- ranks, so no false-ready prompt). 60053/60052 are SIM-CONFIRMED,
-- CLIENT-UNCONFIRMED: confirm with GetSpellInfo on 3.80.2 before treating the
-- prompt as live-tested. Same UNCONFIRMED rule as Kill Command above.
local explosive_shot_ids = get_tab({
    53301, 60052, 60053,
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

-- The HUD Aimed Shot slot's rank table, PER FAMILY: the Era/SoD/Forever client
-- carries the vanilla ladder (19434..20904), the TBC client the r7 (27065) and
-- the WotLK client the instant shot (49050). The HUD slot serves every family,
-- so it walks the ladder that holds THIS family's ranks - the vanilla table
-- alone would leave the TBC and the WotLK slot on a rank the client does not
-- have as its Aimed Shot. The guide's own aimed slots keep their own tables
-- (the Wrath slot is a different object, never in the same set).
local hud_aimed_rank_ids = (st.family == "TBC" or st.family == "WRATH")
    and aimed_shot_wrath_ids or aimed_shot_ids

-- Arcane Shot's late ranks (instant, 6 s cooldown: the TBC rank 27019 plus
-- wotlk spell 49045). Wrath-only prompt (the MM early-phase tier, suppressed
-- on SV where Arcane shares its cooldown with Explosive Shot). Same
-- UNCONFIRMED rule as Kill Command above. 14287 is the rank 8 the SoD and
-- Forever clients carry (wowsims/sod p7_weave APL i=23 and wowsims/forever
-- APL i=12), so the utility layer's Arcane Shot read resolves a rank there.
local arcane_shot_ids = get_tab({
    27019, 49045, 14287,
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

-- Serpent Sting, the upkeep that pays for the Chimera Shot (the Wrath MM proc and
-- the rollover): Era rank 1 (13554 - the SoD p3 ranged-MM APL's `not dotIsActive
-- 13554` upkeep), the later rank 25295 (the SoD p7 weave APL's Serpent 25295 r9 and
-- the Forever APL's Serpent 25295 upkeep) and the Wrath rank 49001 (wowsims/wotlk
-- sim/hunter/serpent_sting.go SIM-CONFIRMED). Only the sourced ranks are listed: an
-- id missing from this table is simply never detected, so the knowledge probe stays
-- quiet on a client whose ranks are not listed here. CLIENT-UNCONFIRMED: every id
-- still needs an in-client GetSpellInfo read.
--
-- The DEBUFF (is the sting up on the target?) is read through compat's
-- api.scan_unit_aura("target", ...) (the unit-generic player scan, BS-1): the scan
-- is the debuff source - the ids alone cannot answer it. The predicate matches the
-- NAME first and the id second: the name is the load-bearing key because a client
-- that resolves spells by name (the TBC Anniversary client) does not answer with
-- the ids in this table (it holds the Era / SoD / Wrath ranks only), while the id
-- leg covers the three sourced ranks on the clients that do answer with numeric ids
-- (and on a localized client, where the name leg cannot match but the id still
-- does). A missing row is only "the sting is down" when the read was COMPLETE;
-- otherwise it stays unknown, which never withholds the naked-Chimera prompt (see
-- read_serpent_active below).
local serpent_sting_ids = get_tab({
    13554, 25295, 49001,
})
-- The debuff name every Serpent Sting rank shares (the predicate's primary key).
local SERPENT_STING_NAME = "Serpent Sting"
-- Exported so the practice layer and the pins can read the sourced ranks.
ST.HUNTER.SERPENT_STING_IDS = serpent_sting_ids

-- Feign Death (5384; reference SuperSwingTimer_State.lua:893, and the vendored
-- LibClassicSwingTimerAPI's own reset_swing_spells[5384] block) and Readiness (23989;
-- reference SuperSwingTimer_Constants.lua:181, wowhead TBC spell page). Both drive
-- event-side handling only (the spellcast-succeeded branches below): Feign Death
-- clears the class-owned ranged display state, Readiness forces the Rapid Fire bar's
-- next scan. Neither is a prompt/rank family, so an absent client simply never fires
-- the branch.
local FEIGN_DEATH_ID = 5384
local READINESS_ID = 23989

-- Improved Steady Shot (Wrath MM proc, wowsims/wotlk steady_shot.go SIM-CONFIRMED:
-- Steady crits grant aura 53220, 12 s, +15% damage / -20% cost on Arcane/Aimed/
-- Chimera, consumed on cast). CLIENT-UNCONFIRMED: confirm 53220 via an in-client
-- aura read. The guide engine never branches on it (no APL does); it only tints
-- the Steady/Aimed HUD slots while banked. Arcane has no HUD slot (hud_state.lua
-- pins nine slots), so its discount rides the Aimed tint (filed follow-up).
-- The id and the sim's duration are exported so the practice layer can carry the
-- window and the pins can read them.
local ISS_AURA_ID = 53220 -- SIM-CONFIRMED, CLIENT-UNCONFIRMED
local ISS_AURA_NAME = "Improved Steady Shot" -- UNCONFIRMED (English fallback)
ST.HUNTER.ISS_AURA_ID = ISS_AURA_ID
ST.HUNTER.ISS_DURATION_SECONDS = 12 -- SIM-CONFIRMED (wowsims/wotlk steady_shot.go)

-- Aspect of the Viper (the OOM swap target): TBC 34074 (wowsims/tbc-new APL Mana
-- group SIM-CONFIRMED) vs SoD 415423 (wowsims/sod p7_weave APL SIM-CONFIRMED).
-- Both CLIENT-UNCONFIRMED. Knowledge-gated (api.is_spell_known): a client that
-- knows neither never prompts.
local viper_ids = get_tab({ 34074, 415423 }) -- SIM-CONFIRMED, CLIENT-UNCONFIRMED
local VIPER_AURA_NAME = "Aspect of the Viper" -- UNCONFIRMED (English fallback)

-- The APL UTILITY layer's lines (the class's utility lines, 2026-10-20;
-- bench/hunter_apl_utility_build_2026-10-20.md, the per-row citations there).
-- One entry per line the engine can now ask for: the action key, the family
-- gate (the family's own token), the rank table and the read shape:
--   cooldown  an ability: known and off cooldown
--   buff      a player buff the line maintains (the aspect swaps)
--   debuff    a target debuff the line maintains (Hunter's Mark)
-- The rank table is the resolver's cache key, and an id missing from a table is
-- simply never detected, so the arm that reads it stays dark on a client that
-- does not carry the spell. Every id is SIM-CONFIRMED through the APL that
-- casts it; the client's own spell data confirms the rest (the knowledge gate
-- is what keeps a client that does not carry the spell dark).
local UTILITY_LINE_SPECS = {
    { action = "raptor_strike", families = { "SOD", "FOREVER" }, kind = "cooldown",
        ids = raptor_strike_ids },
    { action = "wyvern_strike", families = { "SOD" }, kind = "cooldown",
        ids = get_tab({ 458482 }) },
    { action = "wing_clip", families = { "SOD", "FOREVER" }, kind = "cooldown",
        ids = get_tab({ 14268 }) },
    { action = "mongoose_bite", families = { "FOREVER" }, kind = "cooldown",
        ids = get_tab({ 14271 }) },
    { action = "immolation_trap", families = { "FOREVER" }, kind = "cooldown",
        ids = get_tab({ 14305 }) },
    { action = "hunters_mark", families = { "FOREVER" }, kind = "debuff",
        ids = get_tab({ 14325 }) },
    { action = "silencing_shot", families = { "WRATH" }, kind = "cooldown",
        ids = get_tab({ 34490 }) },
    { action = "explosive_trap", families = { "WRATH" }, kind = "cooldown",
        ids = get_tab({ 49067 }) },
    { action = "black_arrow", families = { "WRATH" }, kind = "cooldown",
        ids = get_tab({ 63672 }) },
    { action = "aspect_viper", families = { "SOD", "TBC", "WRATH" }, kind = "buff",
        ids = viper_ids },
    { action = "aspect_hawk", families = { "TBC" }, kind = "buff",
        ids = get_tab({ 27044 }) },
    { action = "aspect_falcon", families = { "SOD" }, kind = "buff",
        ids = get_tab({ 469145 }) },
    { action = "aspect_dragonhawk", families = { "WRATH" }, kind = "buff",
        ids = get_tab({ 61847 }) },
}

-- The aura names the aspect and mark lines match on (the TBC client resolves
-- spells by NAME, so the name is the primary key there - bench/lessons.md).
-- UNCONFIRMED (English fallbacks): the id leg covers the clients that answer
-- with numeric ids.
local UTILITY_AURA_NAMES = {
    aspect_viper = "Aspect of the Viper",
    aspect_hawk = "Aspect of the Hawk",
    aspect_falcon = "Aspect of the Falcon",
    aspect_dragonhawk = "Aspect of the Dragonhawk",
    hunters_mark = "Hunter's Mark",
}

-- The resolved current id per utility line (nil until the client's own spell data
-- answers at post_init). The knowledge gate the engine reads: a line whose rank
-- never resolved is never asked for (the house rule for every prompt).
local utility_current = {}

--=========================================================================================
-- Rank resolution (three-valued, cached, bounded)
--=========================================================================================
-- The guide's icons and the drill's shot icons resolve the client's CURRENT rank of a
-- spell family through the compat resolver, whose verdict is three-valued (audit F4,
-- bench/f4_family_spell_id_2026-10-19.md):
--   resolved   - the client confirmed a rank; the id latches.
--   absent     - the client's own spell data refuted every candidate. FINAL: the
--                negative latches, so the table is never walked again.
--   unresolved - the client could not answer (a cold spell book, a restricted read).
--                RETRYABLE: nothing is latched and the next attempt asks again, so a
--                cold book can no longer poison the rank for the rest of the session.
-- A nil verdict is NEVER read as "this spell does not exist": only "absent" says that,
-- and the caller cannot tell the two apart, so it hides (unknown hides) and waits.
--
-- The retry backoff bounds the probes: the resolution is read from the PER-FRAME gather
-- path (gather_guide_inputs), so an unbounded retry would re-walk every rank table on
-- every frame of a client that cannot answer (the class-latch lane's shape, the rogue
-- lane's ROGUE_SPELL_RETRY and classes/druid.lua RANK_RESOLVE_RETRY).
local RANK_RESOLVE_RETRY = 5.0
-- Per rank table: the latched verdict - an id (resolved) or false (absent, final).
local rank_resolved = {}
-- Per rank table: the time of the next allowed retry after an "unresolved" verdict.
local rank_retry_at = {}
-- The rank tables whose verdict is still "unresolved" (the retry set, in the order they
-- were first asked).
local pending_ranks = {}

-- Adds a rank table to the retry set (an "unresolved" verdict asked it again later).
local function pending_rank_add(ids)
    for i = 1, #pending_ranks do
        if pending_ranks[i] == ids then
            return
        end
    end
    pending_ranks[#pending_ranks + 1] = ids
end

-- Drops a rank table from the retry set (its verdict is now latched).
local function pending_rank_drop(ids)
    for i = #pending_ranks, 1, -1 do
        if pending_ranks[i] == ids then
            table.remove(pending_ranks, i)
        end
    end
end

-- Resolves the highest rank of a spell family that exists on the running client.
-- Returns the id, or nil when the client has not confirmed one (an absent family, or a
-- client that could not answer yet - never a guessed id, never a throw).
local function resolve_rank(ids)
    local cached = rank_resolved[ids]
    if cached ~= nil then
        if cached == false then
            return nil -- absent: final, the negative is latched
        end
        return cached
    end
    if api.get_family_spell_id_state == nil then
        return nil -- no resolver on this build: hide, never throw
    end
    local now = api.get_time()
    if type(now) == "number" and now < (rank_retry_at[ids] or 0) then
        return nil -- still backing off from the last "unresolved" verdict: no walk
    end
    local id, state = api.get_family_spell_id_state(ids)
    if id ~= nil then
        rank_resolved[ids] = id
        pending_rank_drop(ids)
        return id
    end
    if state == "absent" then
        rank_resolved[ids] = false
        pending_rank_drop(ids)
        return nil
    end
    -- "unresolved" (or an unknown verdict): the client could not answer, so nothing is
    -- latched; the next attempt asks again, after the retry backoff.
    pending_rank_add(ids)
    if type(now) == "number" then
        rank_retry_at[ids] = now + RANK_RESOLVE_RETRY
    end
    return nil
end

-- The SoD slot-set swap is decided ONCE (at post_init): the guide frame is built from
-- ST.HUNTER.guide.slots when nextaction_ui.init runs and is never rebuilt, so a swap
-- after that point could not reach the icons.
local sod_slot_set_decided = false

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

-- Compensated world latency in seconds: main.lua's calibrated reading (raw x
-- latency_scale_factor + latency_linear_offset, refreshed on every LATENCY_CHANGED)
-- when it is a usable number, else the raw world reading, else 0. The same basis the
-- shaman weave helpers consume; never the paladin twist lag calibration (those keys
-- are paladin-only). Defaults (1.0/0.0) make calibrated == raw, so default behavior
-- is byte-identical; a user calibration flows into the window, clip and dedupe
-- consumers below with no new option. hunter_window.should_restart floors its dedupe
-- window at 0.25 s, so a missing reading changes nothing.
local function world_latency_seconds(self)
    if type(self) ~= "table" then
        return 0
    end
    local lat = self.latency
    if type(lat) ~= "table" then
        return 0
    end
    local calibrated = lat.calibrated_world_ms
    if type(calibrated) == "number" and calibrated == calibrated then
        return calibrated / 1000
    end
    local raw = lat.world_ms
    if type(raw) == "number" and raw == raw then
        return raw / 1000
    end
    return 0
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
    local auto_token = spell_token(AUTO_SHOT_ID)
    if auto_token == nil then
        return
    end
    local cooldown_start, cooldown_duration, enabled = api.GetSpellCooldown(auto_token)
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
        active = api.IsAutoRepeatSpell(spell_token(AUTO_SHOT_ID))
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

-- G1 (queued-melee tint clears, reference SuperSwingTimer_State.lua:1129-1149): an
-- INTERRUPTED or FAILED cast clears the Raptor/Steady queue tint when the token
-- matches the queued ability or names nothing identifiable (nil token). Event
-- payloads are numeric on every family; TBC name-carrying payloads (R1) match
-- through the client's own localized names (queue_tokens). SUCCEEDED/FAILED_QUIET
-- keep their own hooks; CURRENT_SPELL_CAST_CHANGED re-arms a genuinely live queue
-- on its next probe, so this clear self-heals.
local function is_hunter_queued_melee_token(token, id_table)
    if token == nil then
        return false
    end
    if id_table[token] ~= nil then
        return true
    end
    if type(token) ~= "string" then
        return false
    end
    for _, name in ipairs(queue_tokens(id_table)) do
        if type(name) == "string" and name == token then
            return true
        end
    end
    return false
end

function ST.HUNTER.on_spellcast_event(self, event, unit, cast_guid, spell_id)
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
    if token == nil then
        if self.raptor_strike_queued == true or self.steady_shot_queued == true then
            self.raptor_strike_queued = false
            self.steady_shot_queued = false
            self:set_bar_color("mainhand")
        else
            self.raptor_strike_queued = false
            self.steady_shot_queued = false
        end
        return
    end
    if is_hunter_queued_melee_token(token, raptor_strike_ids) then
        if self.raptor_strike_queued == true then
            self.raptor_strike_queued = false
            self:set_bar_color("mainhand")
        else
            self.raptor_strike_queued = false
        end
    elseif is_hunter_queued_melee_token(token, steady_shot_ids) then
        if self.steady_shot_queued == true then
            self.steady_shot_queued = false
            self:set_bar_color("mainhand")
        else
            self.steady_shot_queued = false
        end
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
        -- without hunter_ui stays inert. The readiness stamp below arms the
        -- double-RF window the RF bar renders (hunter_open §1, SIM-CONFIRMED reset).
        if st.hunter_ui and st.hunter_ui.force_rapid_fire_refresh then
            st.hunter_ui.force_rapid_fire_refresh(self)
        end
        self.hunter_readiness_at = api.get_time()
    end
    -- Trap placed arming (hunter_wa_map §6): a landed player trap cast arms the
    -- placed-phase tracker (a second trap replaces the first). Failed casts run
    -- through on_spellcast_failed_quiet, which never arms; foreign ids ignored.
    ST.HUNTER.note_trap_cast(self, spell_id)
end

function ST.HUNTER.on_current_spell_cast_changed(self, is_cancelled)
    -- This function detects when the player queues up a raptor strike or a
    -- steady shot and sets relevant flags for the func to set bar colors.
    local db = self:get_class_table()
    -- Only run the raptor logic if special on-next-attack colors are enabled in
    -- the hunter settings.
    if db.enable_raptor_strike_color then
        for _, token in ipairs(queue_tokens(raptor_strike_ids)) do
            local result = api.IsCurrentSpell(token)
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
        for _, token in ipairs(queue_tokens(steady_shot_ids)) do
            local result = api.IsCurrentSpell(token)
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
    -- The H2 shot log starts empty (one sample per completed shot cast; the
    -- post-fight report in practice_ui reads it). Reset here so a reload never
    -- inherits a half-written track.
    ST.HUNTER.reset_shot_log(self)
    -- Readiness double-RF stamp (hunter_open §1): nil until Readiness 23989 fires.
    self.hunter_readiness_at = nil
    -- Trap placed-phase tracker (hunter_wa_map §6): nil until a trap cast arms it;
    -- the Clever rank stays nil until the compat GetNumTalents probe lands (filed).
    self.hunter_trap = nil
    self.hunter_clever_rank = nil
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
    -- Runs before the practice init below: the shared post_init order is guide,
    -- HUD, practice in all six class modules (deep-audit F9).
    if st.hud then
        st.hud.init(self)
    end
    -- Practice panel: the shared Twist Practice UI drives the hunter drill too (its
    -- shot icons cast simulated shots through the hunter_forced_move shell, graded
    -- into the session score). Guarded so a flavor without practice_ui stays inert
    -- (the same discipline as hunter_ui/nextaction_ui/hud above); init is idempotent
    -- (it returns when the panel already exists).
    if st.practice_ui and type(st.practice_ui.init) == "function" then
        -- The practice panel's action vocabulary: the class's own guide slots plus
        -- the common abilities (a control shot, a movement spell, food, a potion).
        -- The guide frame above already built its icons from the display vocabulary,
        -- so this widens the PANEL's strip, not the frame (the shaman's
        -- apply_family_slots precedent).
        ST.HUNTER.apply_practice_panel_actions()
        st.practice_ui.init(self)
    end
end

function ST.HUNTER.on_bar_update(self, hand)
    -- Per-frame hunter visual driver, called from ST:onupdate_common via the generic
    -- class hook for every visible bar. The ranged tick drives the full visual set; the
    -- mainhand tick keeps the melee re-anchor in sync when the ranged bar is not ticking
    -- (its OnUpdate stops while the bar is hidden). Deliberately cheap and nil-safe, and
    -- never gated on st.is_mainline: WoW Forever is Mainline-code but must show all of
    -- this, while swing activity decides (the Retail stand-in never reports a swing).
    -- Trap placed-phase expiry (hunter_wa_map §6): player-level state, so it runs
    -- ahead of the hand gate on every tick (nil-safe no-op without a live trap).
    ST.HUNTER.update_trap(self)
    if hand ~= "ranged" and hand ~= "mainhand" then
        return
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
    -- Cooldown HUD: retries a lockdown-deferred creation and picks layout option
    -- changes up between the HUD driver's ticks (the row itself ticks on its own
    -- driver frame, so this is cheap). Deliberately not gated on st.is_mainline:
    -- the Forever client must show the HUD, and the Retail stand-in simply never
    -- swings (the paladin hooks it the same way in classes/paladin.lua). Runs
    -- after the guide tick above: the shared per-frame order is guide then HUD
    -- in all six class modules (deep-audit F8).
    if st.hud then
        st.hud.on_bar_update(self, hand)
    end
    -- H2 clip sampler: the ranged tick owns it (the cast bar it grades only ticks
    -- there too). Gated like the cast bar itself: a disabled widget performs no reads
    -- at all (the 14b/14c inertness pins in tests/hunter_state.lua). The bar-enabled
    -- probe is guarded for sandboxes that do not stub it; the game client always
    -- answers it (main.lua). Reuses the class table read above (no second lookup).
    if hand == "ranged" and type(db) == "table" and db.hunter_cast_bar_enabled ~= false
        and (self.bar_is_enabled == nil or self:bar_is_enabled("ranged") == true) then
        ST.HUNTER.track_live_cast(self)
    end
    if st.hunter_ui then
        st.hunter_ui.on_bar_update(self, hand)
    end
    -- Melee-weave prog: gated internally on hunter_weave_prog_enabled (nil = off, no
    -- reads, no state); not gated on st.is_mainline - the Forever client must track it
    -- and the Retail stand-in never swings, so prog simply never leaves 0 there.
    ST.HUNTER.update_weave_prog(self)
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
    -- A live cast dies with the fight too; its untracked sample must not leak into the
    -- next fight's log. The log itself persists for the post-fight report.
    self.hunter_live_cast = nil
    -- The double-RF window dies with the fight (a short 60 s window must not leak a
    -- stale "2x" into the next pull).
    self.hunter_readiness_at = nil
    -- The weave prog dies with the fight too: its speed/delta/melee legs belong to the
    -- dead pull (a minutes-old last-tick stamp would otherwise slam the first tick of
    -- the next pull to a limit). The band repopulates from the lib poll; prog restarts
    -- at its 0 default.
    self.hunter_weave_prog = nil
    self.hunter_weave_dir = nil
    self.hunter_weave_prev_melee = nil
    self.hunter_weave_last_t = nil
    -- The trap tracker is deliberately NOT cleared: a trap armed before the pull
    -- must survive it (the WA is timeout-driven only); the 60 s expiry bounds it.
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
-- Target-of-target warning (H1)
--=========================================================================================
-- HST surfaces a "target warning state ... when your target's target is you"
-- (bench/competitor_gaps_2026-10-19.md Sec.Hunter H1). No CLEU: the state is two
-- unit-token reads evaluated on demand (hunter_ui polls it per frame), mirroring the
-- raw-global discipline of ST:UNIT_TARGET (main.lua) and hud_out_of_range below.
-- Returns true while the player's target exists and its target is the player, false
-- while a target exists but looks elsewhere, nil when unknown (no target, or the
-- client answers nothing). Unknown hides: hunter_ui only shows on an explicit true.
-- API shapes: UnitExists/UnitIsUnit exist on every supported client family
-- (wow-ui-source branches live, classic_era, classic_anniversary, classic_titan and
-- origin/forever document both in
-- Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua;
-- "targettarget" is the stock ToT token used by Blizzard_UnitFrame TargetFrame on
-- classic_era). In-client ToT behaviour UNCONFIRMED.
function ST.HUNTER.get_target_warning(self)
    if type(UnitExists) ~= "function" or type(UnitIsUnit) ~= "function" then
        return nil
    end
    if not UnitExists("target") then
        return nil
    end
    if not UnitExists("targettarget") then
        return false
    end
    local yours = UnitIsUnit("targettarget", "player")
    if yours == nil then
        return nil
    end
    return yours == true or yours == 1
end

--=========================================================================================
-- Post-fight shot analytics: the clip log (H2)
--=========================================================================================
-- HST's clip counter (bench/competitor_gaps_2026-10-19.md Sec.Hunter H2): one sample per
-- completed player cast in a hunter shot school, judged while the cast is live through
-- the hunter_window safety kernels (the same is_cast_safe verdict the cast bar's
-- no-clip tint rides). The pure stats math (clip rate, latency buffer, hint) lives in
-- practice.lua; the report screen lives in practice_ui.lua. This module only gathers.
--
-- Only cast-time shots can clip, so only their families are scored: Steady Shot,
-- Multi-Shot, the Era Aimed Shot weave and the Forever Sniper Shot cast (every other
-- hunter prompt is an instant and never appears in UnitCastingSpell). A live cast the
-- client reports without a numeric id is unscored, never guessed (compat.lua: the
-- older classic payloads carry no spell id); a cast observed with no readable swing
-- cycle drops its sample for the same reason (every stored sample had at least one
-- judged frame). The log is a bounded ring (SHOT_LOG_MAX, newest wins) while the
-- counters are cumulative. The log is rolling (last-N shots), not fight-scoped: a
-- fight-start reset needs a combat-enter hook in main.lua, which is outside this
-- lane's scope.
ST.HUNTER.SHOT_LOG_MAX = 200

local function is_hunter_shot_cast(spell_id)
    if spell_id == nil then
        return false
    end
    return steady_shot_ids[spell_id] ~= nil or multi_shot_ids[spell_id] ~= nil
        or aimed_shot_ids[spell_id] ~= nil or sniper_shot_ids[spell_id] ~= nil
end

-- One completed shot sample. clipped is truthy when any judged frame of the cast read
-- unsafe; latency is the compensated-latency seconds reading kept for the buffer math
-- (nil when the client answered nothing). Nil-safe: a non-table owner is ignored, and
-- the log is created on first use.
function ST.HUNTER.record_shot_sample(self, clipped, latency)
    if type(self) ~= "table" then
        return
    end
    local log = self.hunter_shot_log
    if type(log) ~= "table" then
        log = {}
        self.hunter_shot_log = log
    end
    if type(latency) ~= "number" then
        latency = nil
    end
    log[#log + 1] = { clipped = clipped == true, latency = latency, at = api.get_time() }
    while #log > ST.HUNTER.SHOT_LOG_MAX do
        table.remove(log, 1)
    end
    self.hunter_shots_total = (self.hunter_shots_total or 0) + 1
    if clipped == true then
        self.hunter_shots_clipped = (self.hunter_shots_clipped or 0) + 1
    end
end

-- Drops the log and the counters (a future fight-start hook owns the call; until then
-- the ring simply rolls). The in-flight live-cast track is cleared too: a cast never
-- survives the boundary its sample would be scored against.
function ST.HUNTER.reset_shot_log(self)
    if type(self) ~= "table" then
        return
    end
    self.hunter_shot_log = {}
    self.hunter_shots_total = 0
    self.hunter_shots_clipped = 0
    self.hunter_live_cast = nil
end

-- Per-frame clip sampler, driven from on_bar_update on the ranged tick (the cast bar
-- it grades only ticks there too). Tracks the live shot cast across frames by its
-- spell id plus cast bounds (chain-cast repeats of one spell still separate), OR-ing
-- the unsafe verdict; when the cast is gone (or replaced by a foreign cast) the
-- finished sample is recorded. Unknown frames (no numeric remaining, no readable
-- swing cycle) judge nothing; a cast that never produces a judged frame drops its
-- sample rather than recording an unjudged clean.
function ST.HUNTER.track_live_cast(self)
    if type(self) ~= "table" or not hunter_window then
        return
    end
    local cast_name, cast_spell_id, cast_start, cast_end = api.UnitCastingSpell("player")
    local trackable = cast_name ~= nil and is_hunter_shot_cast(cast_spell_id)
        and type(cast_start) == "number" and type(cast_end) == "number"
        and cast_end > cast_start
    local tracked = self.hunter_live_cast
    if not trackable then
        -- No live shot cast: a tracked one just finished (or was replaced by a
        -- foreign cast, which carries a numeric id). A nil-id live cast holds the
        -- track: it may be the same id-less cast, never a new judgement.
        if type(tracked) == "table" and (cast_name == nil or cast_spell_id ~= nil) then
            self.hunter_live_cast = nil
            if tracked.judged then
                ST.HUNTER.record_shot_sample(self, tracked.clipped,
                    world_latency_seconds(self))
            end
        end
        return
    end
    local key = cast_spell_id .. ":" .. cast_start .. ":" .. cast_end
    if type(tracked) ~= "table" or tracked.key ~= key then
        -- A judged track replaced by a new cast (chain-casting with no cast-free
        -- frame between) records first: the finished sample is never dropped.
        if type(tracked) == "table" and tracked.judged then
            ST.HUNTER.record_shot_sample(self, tracked.clipped,
                world_latency_seconds(self))
        end
        tracked = { key = key, clipped = false, judged = false }
        self.hunter_live_cast = tracked
    end
    local now = api.get_time()
    local ranged = self.ranged
    local cycle = ranged and (ranged.synced_duration or ranged.speed) or nil
    local remaining = cast_end - now
    local ttl
    if ranged and type(ranged.start) == "number"
        and type(cycle) == "number" and cycle > 0 then
        ttl = hunter_window.time_until_next_shot(now, ranged.start, cycle, nil)
    end
    if type(ttl) ~= "number" then
        return
    end
    tracked.judged = true
    local latency = world_latency_seconds(self)
    local grace = ST.HUNTER.get_cast_grace(self, cast_spell_id, cast_name)
    if not hunter_window.is_cast_safe(remaining, ttl, grace, latency) then
        tracked.clipped = true
    end
end

--=========================================================================================
-- Readiness double-RF window, ISS tint, OOM Viper badge (hunter_open §1-2)
--=========================================================================================
-- All three are HUD/badge layer only: the guide engine never branches on any of
-- them (no APL does). Every toggle reads `== true` (nil = off, no
-- default-visible change); unknown hides.

-- Readiness double-RF window (hunter_open §1): Readiness 23989 resets Rapid
-- Fire's cooldown (wowsims/wotlk talents.go SIM-CONFIRMED, including the <10 s
-- smart double-RF delay). The window is the provisional double-RF opportunity
-- after the reset (no sim source for its length - offline-tunable here).
ST.HUNTER.READINESS_DOUBLE_WINDOW = 60

-- Readiness 23989 as the sim models it (wowsims/wotlk sim/hunter/talents.go
-- registerReadinessCD, SIM-CONFIRMED):
--   * it RESETS the cooldowns of Rapid Fire, Multi-Shot, Arcane Shot, Kill Shot,
--     Raptor Strike, Explosive Trap, Kill Command, Aimed Shot, Silencing Shot,
--     Chimera Shot and Black Arrow;
--   * it is not cast when there is nothing to reset (the sim's ExtraCastCondition:
--     Rapid Fire is ready);
--   * it is HELD while Rapid Fire is less than 10 s from ready (the sim's smart
--     double-RF delay: waiting there buys the second RF usage);
--   * its own cooldown is 3 minutes.
-- The guide has no Readiness slot (the six-slot set is frozen), so the live arm is
-- FILED; the reset list is exported for the practice layer, where a Readiness cast
-- makes the whole kit ready and the rotation pops it. The list names the guide's
-- own action keys only - Raptor Strike, Silencing Shot, Explosive Trap and Black
-- Arrow are not guide actions (the trap tier has no slot).
ST.HUNTER.READINESS_COOLDOWN_SECONDS = 180
ST.HUNTER.READINESS_RF_HOLD_SECONDS = 10
ST.HUNTER.READINESS_RESET_COOLDOWNS = {
    rapid_fire = true,
    multi = true,
    arcane = true,
    kill_shot = true,
    kill_command = true,
    aimed = true,
    wrath_aimed = true,
    chimera = true,
}

-- Remaining window seconds, or nil when there is no live window (never armed,
-- already elapsed, or an unreadable clock - never a guess).
function ST.HUNTER.get_readiness_window(readiness_at, now, window)
    if type(readiness_at) ~= "number" or type(now) ~= "number" then
        return nil
    end
    if readiness_at ~= readiness_at or now ~= now then
        return nil
    end
    if type(window) ~= "number" or window ~= window then
        window = ST.HUNTER.READINESS_DOUBLE_WINDOW
    end
    local remaining = readiness_at + window - now
    if remaining <= 0 then
        return nil
    end
    return remaining
end

-- Throttled ISS probe (the 0.5 s rescan discipline: the HUD provider runs per
-- tick, and this keeps the 40-row aura scan off the hot path). Returns the
-- remaining proc seconds, or nil when the proc is absent, the scan is closed,
-- or the client answers nothing. The cache is module-scoped (one player); a
-- stale hit only delays the tint by half a second.
local ISS_RESCAN_INTERVAL = 0.5
local iss_scanned_at = nil
local iss_remaining_cache = nil

function ST.HUNTER.get_iss_remaining(self, now)
    now = now or api.get_time()
    if iss_scanned_at ~= nil and type(now) == "number"
        and (now - iss_scanned_at) < ISS_RESCAN_INTERVAL then
        return iss_remaining_cache
    end
    iss_scanned_at = now
    iss_remaining_cache = nil
    if type(api.scan_player_aura) ~= "function" then
        return nil
    end
    local remaining = api.scan_player_aura(function(spell_id, name)
        return spell_id == ISS_AURA_ID
            or (ISS_AURA_NAME ~= nil and name == ISS_AURA_NAME)
    end)
    if type(remaining) == "number" and remaining > 0 then
        iss_remaining_cache = remaining
    end
    return iss_remaining_cache
end

-- Whether the player knows Aspect of the Viper on this client (either
-- SIM-CONFIRMED rank id). A client that knows neither never prompts.
function ST.HUNTER.is_viper_known()
    for id in pairs(viper_ids) do
        local token = spell_token(id)
        if token ~= nil and api.is_spell_known(token) then
            return true
        end
    end
    return false
end

-- Whether Aspect of the Viper is currently active (id or English fallback match).
function ST.HUNTER.is_viper_active()
    if type(api.scan_player_aura) ~= "function" then
        return false
    end
    local remaining = api.scan_player_aura(function(spell_id, name)
        return viper_ids[spell_id] ~= nil
            or (VIPER_AURA_NAME ~= nil and name == VIPER_AURA_NAME)
    end)
    return type(remaining) == "number" and remaining > 0
end

-- Mana fraction through compat's power reads (the hunter's primary power is
-- mana, so the untyped read answers it on the classic line). Nil when the
-- client cannot answer (unknown, never zero).
function ST.HUNTER.get_mana_fraction()
    local cur = api.UnitPower("player")
    local max = api.UnitPowerMax("player")
    if type(cur) ~= "number" or type(max) ~= "number" or max <= 0 then
        return nil
    end
    if cur ~= cur or max ~= max then
        return nil
    end
    return cur / max
end

-- OOM Viper band (TBC APL Mana group SIM-CONFIRMED: Viper 34074 below 5%, back
-- to Hawk at >= 25%). The badge prompts at the 5% swap edge.
ST.HUNTER.OOM_VIPER_FRAC = 0.05

-- OOM Viper prompt: "VIPER" while mana is known-below the band, Viper is known
-- but not active, and the caller passes the toggle on. Nil otherwise (unknown
-- mana, Viper already up, Viper unknown, or toggle off - never a guess).
function ST.HUNTER.get_oom_viper_prompt(mana_frac, viper_active, viper_known, prompt_enabled)
    if prompt_enabled ~= true then
        return nil
    end
    if viper_known ~= true or viper_active == true then
        return nil
    end
    if type(mana_frac) ~= "number" or mana_frac ~= mana_frac then
        return nil
    end
    local band = ST.HUNTER.OOM_VIPER_FRAC
    if mana_frac <= band then
        return "VIPER"
    end
    return nil
end

-- Lock and Load trap-proc window (hunter_open §1 + rotation audit findings 1):
-- traps are the LnL source (Wrath SV: Black Arrow / Explosive Trap ticks proc
-- it, wowsims/wotlk talents.go SIM-CONFIRMED; SoD: the trap proc, wowsims/sod
-- runes.go SIM-CONFIRMED), so the proc window IS the trap display. Badge layer
-- only: the engine never branches on it (no APL does - the arms already read
-- the frozen lnl_ready input, still gather-nil until the aura source confirms
-- in-client). Every toggle reads `== true` (nil = off, no default-visible
-- change); unknown hides.
-- Wrath talent/proc id 56344 (talents.go: 22s ICD, 2 stacks, free Explosive /
-- Arcane + CD reset) vs SoD rune proc id 415413 (runes.go: trap -> 20s window,
-- free shots + refund). Both SIM-CONFIRMED, CLIENT-UNCONFIRMED: confirm each
-- with an in-client aura read before treating the badge as live-tested.
-- Options pass: wire hunter_lnl_badge_enabled (default off).
local LNL_AURA_ID_WRATH = 56344
local LNL_AURA_ID_SOD = 415413
local LNL_AURA_NAME = "Lock and Load" -- UNCONFIRMED (English fallback)

-- Throttled LnL probe (the 0.5s rescan discipline, same as the ISS probe
-- above: the HUD-adjacent badge reads run per frame, and this keeps the 40-row
-- aura scan off the hot path). Returns the remaining proc seconds, or nil when
-- the proc is absent, the scan is closed, or the client answers nothing. The
-- cache is module-scoped (one player); a stale hit only delays the badge by
-- half a second.
local LNL_RESCAN_INTERVAL = 0.5
local lnl_scanned_at = nil
local lnl_remaining_cache = nil

function ST.HUNTER.get_lnl_remaining(self, now)
    now = now or api.get_time()
    if lnl_scanned_at ~= nil and type(now) == "number"
        and (now - lnl_scanned_at) < LNL_RESCAN_INTERVAL then
        return lnl_remaining_cache
    end
    lnl_scanned_at = now
    lnl_remaining_cache = nil
    if type(api.scan_player_aura) ~= "function" then
        return nil
    end
    local remaining = api.scan_player_aura(function(spell_id, name)
        return spell_id == LNL_AURA_ID_WRATH or spell_id == LNL_AURA_ID_SOD
            or (LNL_AURA_NAME ~= nil and name == LNL_AURA_NAME)
    end)
    if type(remaining) == "number" and remaining > 0 then
        lnl_remaining_cache = remaining
    end
    return lnl_remaining_cache
end

-- LnL trap-proc prompt: "LnL" while the window is live and the caller passes
-- the toggle on. Nil otherwise (no window, an unreadable/NaN window, or
-- toggle off - never a guess).
function ST.HUNTER.get_lnl_prompt(lnl_remaining, prompt_enabled)
    if prompt_enabled ~= true then
        return nil
    end
    if type(lnl_remaining) ~= "number" or lnl_remaining ~= lnl_remaining then
        return nil
    end
    if lnl_remaining <= 0 then
        return nil
    end
    return "LnL"
end

--=========================================================================================
-- Trap state machines + Clever Traps (hunter_wa_map §6, wago eEJOoHci- TBC pack)
--=========================================================================================
-- WA CLIENT-OBSERVED (the pack ran on a TBC client), SIM-UNCONFIRMED as timings:
-- no fetched sim APL models placed/active trap timing (sims treat traps as the
-- LnL source only, hunter_open §1: trapWeave + timeToTrapWeaveMs 2000, the LnL
-- trigger on Black Arrow / Explosive Trap ticks). Display-state only: the engine
-- never reads it (no APL branches on trap timing), so sim wins by construction -
-- nothing here can prompt against a sim.
--
-- What is WIRED here (no new event registration, no new probe):
--   placed phase via the existing UNIT_SPELLCAST_SUCCEEDED hook (this module's
--   on_spellcast_succeeded already receives every player trap cast with its
--   numeric spell id - event payloads stay numeric on every family, so the
--   TBC-name rule for state queries never applies to them) and placed-phase
--   expiry via the existing on_bar_update tick. A second trap cast replaces the
--   first (one trap at a time, the WA's otherTraps discipline verbatim).
-- What stays FILED (needs out-of-scope files, each pinned in tests §20b):
--   active phase (trigger/resist/finish) needs CLEU SPELL_CREATE/SUMMON/DAMAGE/
--   AURA_APPLIED/REMOVED/MISSED dispatched to hunter - main.lua only forwards
--   its combat-log handler to PALADIN/WARRIOR, and hunter CLEU registration is
--   out of scope; the state shape below already carries the phase field for it. The Clever Traps rank needs a compat GetNumTalents probe
--   (compat.lua exposes GetTalentInfo but no talent count; the WA scans Survival
--   tab 3 against the GetSpellInfo(19239) icon) - compat is out of scope, so the
--   rank stays nil (mult 1.0) until that probe lands.
--
-- WA timings (CLIENT-OBSERVED): placed 60 s every trap (60.1 s safety timer);
-- active Snake 15 s (SPELL_SUMMON), Explosive 20 s fire patch (SPELL_DAMAGE),
-- Immolation 15 s (AURA_APPLIED/REMOVED), Freezing 20 s x mult, Frost 30 s x mult
-- (AURA_APPLIED; Frost also expires its active timer). Effect ids for the filed
-- CLEU lane: Explosive 13812, Immolation 13797, Freezing 3355, Frost 13810.

-- Castable trap spells (numeric ids arrive in the spellcast event on every
-- family; an id missing here simply never arms). Snake Trap is TBC-only (34600
-- never fires on Era); the other four arm on every classic family. The two Wrath
-- traps are the Lock and Load sources the sim procs on (wowsims/wotlk
-- sim/hunter/talents.go applyLockAndLoad: the Black Arrow / Explosive Trap ticks
-- proc it, SIM-CONFIRMED), so the trap machine now tracks them too: Black Arrow
-- 63672 (sim/hunter/black_arrow.go) and Explosive Trap 49067
-- (sim/hunter/explosive_trap.go), both 30 s (the same 30 s minus 2 s per
-- Resourcefulness rank). CLIENT-UNCONFIRMED: confirm both ids in-client on
-- 3.80.2. The guide still never prompts a trap (no slot - the six-slot set is
-- full), so this only teaches the LnL source through the trap badge.
ST.HUNTER.TRAP_SPELLS = {
    [34600] = "snake",
    [13813] = "explosive",
    [13795] = "immolation",
    [1499] = "freezing",
    [13809] = "frost",
    [63672] = "black_arrow",
    [49067] = "explosive_trap",
}
ST.HUNTER.TRAP_PLACED_DURATION = 60
ST.HUNTER.TRAP_ACTIVE_DURATIONS = {
    snake = 15,
    explosive = 20,
    immolation = 15,
    freezing = 20,
    frost = 30,
    black_arrow = 30,
    explosive_trap = 30,
}
-- Traps whose active phase the Clever Traps talent stretches (WA: Freezing 20
-- and Frost 30 multiplied; Snake/Explosive/Immolation fixed).
ST.HUNTER.TRAP_CLEVER_KEYS = { freezing = true, frost = true }
-- Clever Traps (Survival talent, WA CLIENT-OBSERVED: icon match on
-- GetSpellInfo(19239), mult = 1 + 0.15 x rank). Pure: nil/0/unknown rank reads
-- 1.0 (no talent, never a guess).
ST.HUNTER.CLEVER_TRAPS_BONUS = 0.15
function ST.HUNTER.clever_traps_mult(rank)
    if type(rank) ~= "number" or rank ~= rank or rank <= 0 then
        return 1.0
    end
    return 1 + ST.HUNTER.CLEVER_TRAPS_BONUS * rank
end
-- Active-phase length for a trap key under a (possibly unknown) Clever rank.
-- Nil for an unknown key (never a guess); the filed CLEU lane counts this down.
function ST.HUNTER.get_trap_active_duration(trap_key, clever_rank)
    local base = ST.HUNTER.TRAP_ACTIVE_DURATIONS[trap_key]
    if type(base) ~= "number" then
        return nil
    end
    if ST.HUNTER.TRAP_CLEVER_KEYS[trap_key] then
        return base * ST.HUNTER.clever_traps_mult(clever_rank)
    end
    return base
end

-- Placed-phase tracker: nil (no live trap) or { key, phase, spell_id, placed_at,
-- duration, active_duration } in the api.get_time() domain. Armed by
-- note_trap_cast from on_spellcast_succeeded, expired by update_trap from
-- on_bar_update. active_duration is stamped at cast time (Clever-adjusted under
-- the live rank, 1.0 while the rank probe is filed) for the CLEU lane; the
-- phase field is its plug-in point ("placed" today, "active"/"finished" filed).
function ST.HUNTER.note_trap_cast(self, spell_id)
    if type(self) ~= "table" then
        return
    end
    local key = ST.HUNTER.TRAP_SPELLS[spell_id]
    if key == nil then
        return
    end
    self.hunter_trap = { key = key, phase = "placed", spell_id = spell_id,
        placed_at = api.get_time(), duration = ST.HUNTER.TRAP_PLACED_DURATION,
        active_duration = ST.HUNTER.get_trap_active_duration(key, self.hunter_clever_rank) }
end

-- Expire a placed trap past its window. Nil-safe on any self shape; an unknown
-- clock holds rather than guessing, while a malformed state clears (a state
-- that cannot tick must not linger).
function ST.HUNTER.update_trap(self, now)
    if type(self) ~= "table" then
        return
    end
    local trap = self.hunter_trap
    if type(trap) ~= "table" then
        return
    end
    now = now or api.get_time()
    if type(now) ~= "number" or now ~= now then
        return
    end
    if type(trap.placed_at) ~= "number" or type(trap.duration) ~= "number" then
        self.hunter_trap = nil
        return
    end
    if now >= trap.placed_at + trap.duration then
        self.hunter_trap = nil
    end
end

-- Remaining placed seconds, or nil when no trap is live (never a guess). The
-- trap badge reads this; the engine never does.
function ST.HUNTER.get_trap_remaining(self, now)
    if type(self) ~= "table" then
        return nil
    end
    local trap = self.hunter_trap
    if type(trap) ~= "table" then
        return nil
    end
    now = now or api.get_time()
    if type(now) ~= "number" or now ~= now then
        return nil
    end
    if type(trap.placed_at) ~= "number" or type(trap.duration) ~= "number" then
        return nil
    end
    local remaining = trap.placed_at + trap.duration - now
    if remaining <= 0 then
        return nil
    end
    return remaining
end

--=========================================================================================
-- Per-client base cast-time fallbacks (the hunter seam's cast-time table)
--=========================================================================================
-- Cold-cache fallbacks in seconds, used only while the client's spell data has not
-- answered (the live GetSpellInfo probe in gather_guide_inputs wins whenever it
-- answers, so in-client truth always beats this table). No invented numbers: every
-- entry cites its sim/archive source; CLIENT-UNCONFIRMED entries still need an
-- in-client GetSpellInfo read before they count as verified.
--   steady 1.5: WRATH SIM-CONFIRMED (wowsims sim/hunter/steady_shot.go 1500 ms,
--     spell 49052; bench/hunter_rotation_audit_2026-10-19.md); TBC 34120 1.5 s
--     CLIENT-UNCONFIRMED (the TBC APL casts 34120; confirm GetSpellInfo(34120) on
--     2.5.6). FOREVER reads NO entry: the Forever client has no Steady Shot at all
--     (the corpus correction of 2026-10-20 - bench/rotation_gap_vs_apl_2026-10-20.md
--     §0.0 H4), so the family never consumes that shot (the rule below).
--   multi 0.5: WRATH SIM-CONFIRMED (wowsims sim/hunter/multi_shot.go 500 ms, same
--     audit); ERA/TBC 0.5 s CLIENT-UNCONFIRMED (no fetched Era/TBC cast-time source;
--     the live probe decides - confirm GetSpellInfo on 1.15.9/2.5.6).
--   aimed 3.0 ERA: ARCHIVE-CONFIRMED (classicdb.ch ranks 19434-20904, every rank a
--     3 s cast; same audit "Aimed 3s-cast weave"). Wrath 49050 is instant, so Wrath
--     reads no fallback.
--   sniper 4.0 FOREVER: SIM-CONFIRMED (wowsims Forever sim sniper_shot.go, same
--     audit) and beta-guide 4 s cast (docs/research/forever_beta.md);
--     CLIENT-UNCONFIRMED (the ids are unconfirmed - see summon_hawk_ids).
-- Families that never consume a shot read nil (ERA has no Steady Shot; only ERA
-- reads aimed; only FOREVER reads sniper): nil matches the aimed off-Era precedent,
-- and the engine's own DEFAULT fallback keeps every verdict identical (never a guess).
ST.HUNTER.CAST_TIME_FALLBACK = {
    steady = { TBC = 1.5, WRATH = 1.5 },
    multi = { ERA = 0.5, TBC = 0.5, WRATH = 0.5 },
    aimed = { ERA = 3.0 },
    sniper = { FOREVER = 4.0 },
}

-- Cold-cache fallback for one shot on the running family (nil when the family never
-- consumes the shot, or for an unknown shot key - never a guessed cast). Reads
-- st.family live, like the gather gates below.
function ST.HUNTER.cast_time_fallback(shot_key)
    local shot = ST.HUNTER.CAST_TIME_FALLBACK[shot_key]
    if type(shot) ~= "table" then
        return nil
    end
    local fallback = shot[st.family]
    if type(fallback) == "number" then
        return fallback
    end
    return nil
end

--=========================================================================================
-- Forced-move practice drill (H5, practice.lua hunter_forced_move)
--=========================================================================================
-- The hunter drill for the shared Practice Mode flow (the options Practice toggle and
-- /st practice both route into st.practice_ui.toggle; the panel's shot icons cast
-- SIMULATED shots, no mana and no real casts - the archived practice contract in
-- docs/swedge/SwedgeTimer_TBC/practice.lua). The drill grades each simulated cast
-- start against the forced-move windows through the harness shell
-- (st.practice.harness, key hunter_forced_move): casting inside a window is F, a cast
-- that would still be running when the next window starts is C, and the bands reward
-- finishing with margin. All drill state lives in the harness session the UI owns
-- (ui.hunter_session); this module only maps shots and translates calls, so every
-- function here is nil-safe over absent shell/engine pieces and never grades a guess.
--
-- Simulated cast times mirror the guide's frozen base casts (st.hunter_guide
-- STEADY/MULTI/AIMED_CAST_SECONDS_DEFAULT: 1.5 / 0.5 / 3.0) and the per-client table
-- above (steady TBC/WRATH, multi ERA/TBC/WRATH, aimed ERA); the drill is a sim, so
-- the family never gates the shot list. Spell ids ride the class's own rank tables
-- (icon resolution only, through api.get_family_spell_id like resolve_guide_icons);
-- an unanswered spell cache resolves nil and the icon stays blank rather than guessed.
ST.HUNTER.PRACTICE_SCENARIO_KEY = "hunter_forced_move"
ST.HUNTER.PRACTICE_SHOTS = {
    { key = "steady", label = "Steady Shot", cast_time = 1.5 },
    { key = "multi", label = "Multi-Shot", cast_time = 0.5 },
    { key = "aimed", label = "Aimed Shot", cast_time = 3.0 },
}
ST.HUNTER.PRACTICE_SHOT_ORDER = { "steady", "multi", "aimed" }

-- Shot lookup helpers (all nil-safe; unknown keys answer nil, never a guess).
function ST.HUNTER.practice_cast_time(key)
    for i = 1, #ST.HUNTER.PRACTICE_SHOTS do
        local shot = ST.HUNTER.PRACTICE_SHOTS[i]
        if shot.key == key then
            return shot.cast_time
        end
    end
    return nil
end

function ST.HUNTER.practice_shot_label(key)
    for i = 1, #ST.HUNTER.PRACTICE_SHOTS do
        local shot = ST.HUNTER.PRACTICE_SHOTS[i]
        if shot.key == key then
            return shot.label
        end
    end
    return nil
end

-- Icon spell id for a drill shot, resolved through the class's own rank tables
-- (family rank, like the guide icons). Nil when the client's spell data has not
-- answered (unknown hides) or the resolver is unavailable - never a guessed id.
-- The resolution is the class's CACHED one (the three-valued resolver above), so the
-- drill shares the guide's verdict instead of walking the rank table a second time.
function ST.HUNTER.practice_shot_spell_id(key)
    local ids
    if key == "steady" then
        ids = steady_shot_ids
    elseif key == "multi" then
        ids = multi_shot_ids
    elseif key == "aimed" then
        ids = aimed_shot_ids
    else
        return nil
    end
    return resolve_rank(ids)
end

-- The registry key the UI session drives (the single verifiable consumer is the
-- practice_ui hunter branch; the top-level Practice tab lists it through
-- scenarios_for_class("HUNTER")).
function ST.HUNTER.get_practice_scenario_key()
    return ST.HUNTER.PRACTICE_SCENARIO_KEY
end

-- The harness shell, or nil when practice.lua is not loaded on this flavor.
local function hunter_drill_harness()
    local pr = st.practice
    return pr and pr.harness or nil
end

-- Fresh drill session (unbegun: no windows yet). Nil when the shell is absent.
function ST.HUNTER.practice_new_session(now, opts)
    local H = hunter_drill_harness()
    if not H then
        return nil
    end
    return H.new_session(ST.HUNTER.PRACTICE_SCENARIO_KEY, now, opts)
end

-- Begin the windows run (mirrors the paladin start_fight). False when there is
-- nothing to begin (absent shell, malformed session, already begun).
function ST.HUNTER.practice_begin_session(session, now, opts)
    local H = hunter_drill_harness()
    if not (H and type(session) == "table") then
        return false
    end
    return H.begin_session(session, now, opts) == true
end

-- End the windows run. False when there is nothing to end.
function ST.HUNTER.practice_end_session(session, now)
    local H = hunter_drill_harness()
    if not (H and type(session) == "table") then
        return false
    end
    return H.end_session(session, now) == true
end

-- Grade one simulated cast start (cast_time seconds) at now through the shell's
-- exact-time hook. Returns the S/A/B/C/D/F grade, or nil when unscorable (unknown
-- shot, idle session, absent shell - never a grade on a guess).
function ST.HUNTER.practice_cast(session, now, key)
    local H = hunter_drill_harness()
    if not H then
        return nil
    end
    local cast_time = ST.HUNTER.practice_cast_time(key)
    if type(cast_time) ~= "number" then
        return nil
    end
    if type(session) ~= "table" or not session.active then
        return nil
    end
    return H.scenario_event(session, { start = now, cast_time = cast_time }, now)
end

-- Advance the drill one tick (window transitions land in out, same shape as the
-- shell's tick). Returns out (a fresh table when the caller passes none), empty
-- when there is nothing running.
function ST.HUNTER.practice_tick(session, now, elapsed, out)
    local H = hunter_drill_harness()
    out = (type(out) == "table") and out or {}
    if not H then
        return out
    end
    if type(session) ~= "table" or not session.active then
        return out
    end
    return H.tick_session(session, now, elapsed, out)
end

-- Info-line status for the panel (window countdown / MOVE cue / idle). Pure
-- readout, never a rule input: unknown reads idle, never a guess.
function ST.HUNTER.practice_status(session, now)
    local H = hunter_drill_harness()
    if not (H and type(session) == "table") then
        return "Drill idle"
    end
    if not session.active then
        return "Press Start Fight"
    end
    local in_window = H.query(session, "in_move_window", now)
    if in_window == true then
        return "MOVE - hold casts!"
    end
    local wait = H.query(session, "time_to_move", now)
    if type(wait) == "number" and wait == wait and wait > 0 then
        return string.format("Move in %.1fs - cast now", wait)
    end
    return "Windows clear - cast freely"
end

-- Fight-clock elapsed for the panel (fight start to now). Nil unless a run is live
-- on a readable clock - never a guessed number.
function ST.HUNTER.practice_fight_elapsed(session, now)
    if type(session) ~= "table" or not session.active then
        return nil
    end
    if type(now) ~= "number" or type(session.started_at) ~= "number" then
        return nil
    end
    local elapsed = now - session.started_at
    if elapsed ~= elapsed or elapsed < 0 then
        return nil
    end
    return elapsed
end

-- Carry a real-combat pause over the drill (mirror of shift_sim_times): the drill
-- clock freezes, so every window bound and the fight start shift by the pause
-- length and nothing lands retroactively. A non-positive or NaN shift is a no-op.
function ST.HUNTER.practice_shift_pause(session, shift)
    if type(session) ~= "table" then
        return
    end
    if type(shift) ~= "number" or shift ~= shift or shift <= 0 then
        return
    end
    if type(session.started_at) == "number" then
        session.started_at = session.started_at + shift
    end
    local windows = session.windows
    if type(windows) ~= "table" then
        return
    end
    for i = 1, #windows do
        local w = windows[i]
        if type(w) == "table" then
            if type(w.start_time) == "number" then
                w.start_time = w.start_time + shift
            end
            if type(w.end_time) == "number" then
                w.end_time = w.end_time + shift
            end
        end
    end
end

--=========================================================================================
-- Melee-weave distance approximation (hunter_wa_map Secs 1-3 -- operator priority)
--=========================================================================================
-- The TBC pack's "Melee weave - Distance approximation" aura drives its Dynamic
-- switch (rotLogicMode 3): the WA's hand-rolled item-range check (Voodoo
-- Charm, 5 yd, CLIENT-OBSERVED) on an attackable target selects the
-- Melee-Weave rotation (Mode 2), else Standard (Mode 1). The 5 yd check lives in the
-- vendored LibRangeCheck-2.0 itself (item 8149 is its 5-yard checker, with
-- Solendra's Compassion / Worgsaw fallbacks and checker-change events), so
-- the hunter reads the library's published state instead of hand-rolling the
-- WA's item hack: main.lua's rf_update polls the lib at 0.05 s and publishes
-- ST.in_melee_range / ST.in_ranged_range (the hunter 35 yd checker, not
-- melee) / ST.target_min_range / ST.target_max_range (main.lua:1425-1517).
-- No module here calls the lib or spends a range probe of its own
-- (weave_range.lua keeps the same discipline). Where the lib never reports
-- (lrc_unavailable after the 5 s init deadline, or a family whose checkers
-- never resolve -- main-owned, pinned by tests/main_init_state.lua), the
-- fields stay nil and the band below stays nil (unknown hides).
-- Sim direction agrees distance matters in melee: the TBC APL ships Melee
-- weave=true with Wait-at-melee 400 ms plus a swing-adaptive buffer
-- (default.apl.json valueVariables, SIM-CONFIRMED), and the Era sim models
-- Raptor/Mongoose in the melee window (AutoSwingMelee). Neither sim switches
-- prompts by distance -- and a stateless engine cannot express wait-at-melee /
-- move timing anyway (hunter_open Sec.1 CUT precedent) -- so this lane publishes
-- the live band as a frozen gather input and maps the switch onto the
-- existing states (2b HOLD while unshootable, clip-gated weave while
-- shootable, RIDE on a queued Raptor). No new engine rule (filed, see
-- hunter_guide.lua).

-- The live distance band from main's LibRangeCheck poll (the Dynamic switch's
-- model twin). "melee" is the Mode-2 trigger analog (the lib's 5 yd checker
-- family answers it); "ranged" is inside the hunter 35 yd checker;
-- "out_of_range" is a known band beyond both; nil is unknown (never a guess
-- -- the strip hides and the engine must not mistake unknown for far).
function ST.HUNTER.get_weave_band(in_melee_range, in_ranged_range, min_range, max_range)
    if in_melee_range == true then
        return "melee"
    end
    if in_ranged_range == true then
        return "ranged"
    end
    if type(min_range) == "number" or type(max_range) == "number" then
        return "out_of_range"
    end
    return nil
end

--=========================================================================================
-- Melee-weave progress (the WA "Melee weave - Distance approximation" integrator)
--=========================================================================================
-- The WA's per-tick progress model, OPERATOR-REPORTED (bench/hunter_weave_distance_
-- 2026-10-19.md prog spec; the wago page is a JS shell, so no Lua was extracted and
-- in-client validation of the dynamics is owed): prog in [-0.7, +0.7], melee side
-- negative, ranged side positive. The pure step below is that spec verbatim; the live
-- caller is update_weave_prog (driven from on_bar_update, gated on the opt-in
-- hunter_weave_prog_enabled toggle, nil = off). No bar, tick or colour ships with this
-- lane (our strip keeps its palette); the state is the plug-in point the display lane
-- reads.
--
-- Input mapping (all nil-safe; unknown hides, never a guess):
--   player speed  <- api.GetUnitSpeed("player"); nil (client answers nothing) holds,
--                    except a confirmed-not-moving IsPlayerMoving() == false reads as 0.
--   movement sign <- carried dir state (-1/+1, default +1): no client API exposes a
--                    forward/backward sign, so the spec's backpedal-band flip owns it.
--   target motion <- api.GetUnitSpeed("target") > 0; nil (unknown) never snaps.
--   lib flip      <- self.in_melee_range vs the stored previous tick (main-owned poll).
-- Step priority, spec order: re-anchor (melee flip -> 0, beats everything) > target snap
-- (+/-0.7 on the current side, +0.7 from exactly 0) > unknown/degenerate hold (prev,
-- defaults 0) > integrate (prog + dir * (speed / 7) * delta, clamped) with the
-- backpedal flip (speed < 4.6 flips dir for the next tick, boundary-exact: 4.6 keeps).
ST.HUNTER.WEAVE_PROG_LIMIT = 0.7
ST.HUNTER.WEAVE_PROG_RUN_SPEED = 7
ST.HUNTER.WEAVE_PROG_BACKPEDAL_SPEED = 4.6

-- Pure: one prog step. Returns prog, dir. Never errors on any input shape.
function ST.HUNTER.step_weave_prog(prev, dir, speed_yds, delta, in_melee, prev_in_melee,
    target_moving)
    if type(prev) ~= "number" or prev ~= prev then
        prev = 0
    end
    if dir ~= 1 and dir ~= -1 then
        dir = 1
    end
    -- Re-anchor: a lib melee flip forces 0, beating the snap and the integrate below.
    if (in_melee == true or in_melee == false)
        and (prev_in_melee == true or prev_in_melee == false)
        and in_melee ~= prev_in_melee then
        return 0, dir
    end
    -- Target-motion snap on the current side (+0.7 from exactly 0).
    if target_moving == true then
        if prev < 0 then
            return -ST.HUNTER.WEAVE_PROG_LIMIT, dir
        end
        return ST.HUNTER.WEAVE_PROG_LIMIT, dir
    end
    -- Unknown/degenerate inputs hold prev: unanswered speed, NaN/negative/infinite
    -- speed, or a missing/NaN/non-positive delta (delta 0 also covers a same-frame
    -- double tick, e.g. ranged + mainhand in one frame).
    if type(speed_yds) ~= "number" or speed_yds ~= speed_yds or speed_yds < 0
        or speed_yds == math.huge or type(delta) ~= "number" or delta ~= delta
        or delta <= 0 then
        return prev, dir
    end
    local prog = prev + dir * (speed_yds / ST.HUNTER.WEAVE_PROG_RUN_SPEED) * delta
    if prog > ST.HUNTER.WEAVE_PROG_LIMIT then
        prog = ST.HUNTER.WEAVE_PROG_LIMIT
    elseif prog < -ST.HUNTER.WEAVE_PROG_LIMIT then
        prog = -ST.HUNTER.WEAVE_PROG_LIMIT
    end
    if speed_yds < ST.HUNTER.WEAVE_PROG_BACKPEDAL_SPEED then
        dir = -dir
    end
    return prog, dir
end

-- Live: advance the prog state one tick. Gated on hunter_weave_prog_enabled == true
-- (nil = off): while off no client probe runs at all and no state is created. Nil-safe
-- on any self shape; the clock is api.get_time() (never raw GetTime).
function ST.HUNTER.update_weave_prog(self)
    if type(self) ~= "table" or type(self.get_class_table) ~= "function" then
        return
    end
    local db = self:get_class_table()
    if type(db) ~= "table" or db.hunter_weave_prog_enabled ~= true then
        return
    end
    local now = api.get_time()
    local last = self.hunter_weave_last_t
    local delta
    if type(last) == "number" and type(now) == "number" then
        delta = now - last
    end
    local speed = api.GetUnitSpeed("player")
    if speed == nil and api.IsPlayerMoving() == false then
        speed = 0
    end
    local target_speed = api.GetUnitSpeed("target")
    local target_moving
    if type(target_speed) == "number" then
        target_moving = target_speed > 0
    end
    local in_melee = self.in_melee_range
    local prog, dir = ST.HUNTER.step_weave_prog(self.hunter_weave_prog,
        self.hunter_weave_dir, speed, delta, in_melee, self.hunter_weave_prev_melee,
        target_moving)
    self.hunter_weave_prog = prog
    self.hunter_weave_dir = dir
    self.hunter_weave_prev_melee = in_melee
    self.hunter_weave_last_t = now
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
-- The APL UTILITY layer's Multi-Shot rank (the WotLK rank 49048 and the Forever
-- rank): the knowledge-gated resolution of the utility layer, separate from the
-- weave's data-gated multi_current_id above.
local utility_multi_current_id
-- The Forever upkeep/cast ranks (resolved once at post_init from the module's
-- own rank tables). nil = not on this client, or not learned by this player -
-- and until the UNCONFIRMED ids above confirm in-client, always nil: both
-- Forever prompts stay silent by construction.
local hawk_current_id
local sniper_current_id

-- Whether the client knows a Serpent Sting rank (resolved once at post_init, the
-- same knowledge gate as the Wrath prompts): the naked-Chimera guard reads it.
-- nil until the client confirms a rank (unknown hides); with no known rank the
-- guard can never withhold, so the debuff scan does not run at all either - see
-- the gather below.
local serpent_known = nil

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
    local query = spell_token(spell)
    if query == nil then
        return 0, nil
    end
    local start_time, duration = api.GetSpellCooldown(query)
    if not start_time or not duration or duration <= 1.51 then
        return 0, nil
    end
    local remaining = start_time + duration - api.get_time()
    if remaining <= 0 then
        return 0, nil
    end
    return remaining, duration
end

-- Slot descriptors: the FAMILY's own id ships as the fallback (SPELL_ID_BY_FAMILY
-- above - the client's own rank for that family); resolve_guide_icons re-points
-- them at the client's current rank once the spell data is live. Every shared slot
-- reads the same per-family entry the HUD slot reads, so the two surfaces can
-- never disagree about which spell the running client has - and a family that has
-- no entry for a slot (the client cannot have that spell) carries no id at all, so
-- no probe is spent there.
local guide_slot_steady = { key = "steady", spell_id = SPELL_ID_BY_FAMILY.steady[st.family],
    cooldown_key = "steady", swipe_duration = 1.5, swipe_always = true }
local guide_slot_raptor = { key = "raptor", spell_id = SPELL_ID_BY_FAMILY.raptor[st.family] }
local guide_slot_kill_command = { key = "kill_command",
    spell_id = SPELL_ID_BY_FAMILY.kill_command[st.family] }
local guide_slot_multi = { key = "multi", spell_id = SPELL_ID_BY_FAMILY.multi[st.family] }
local guide_slot_bestial_wrath = { key = "bestial_wrath",
    spell_id = SPELL_ID_BY_FAMILY.bestial_wrath[st.family] }
local guide_slot_rapid_fire = { key = "rapid_fire",
    spell_id = SPELL_ID_BY_FAMILY.rapid_fire[st.family] }
local guide_slot_aimed = { key = "aimed", spell_id = SPELL_ID_BY_FAMILY.aimed[st.family],
    cooldown_key = "aimed", swipe_duration = 3.0, swipe_always = true }
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
-- The APL UTILITY layer's slots (the class's utility lines, 2026-10-20): one
-- slot per line the engine can now ask for, so the guide can light it. Every
-- slot is swipe-less (they are all instants or debuffs - no cast to time), and
-- the rank-resolved ones are re-pointed at post_init like the slots above.
local guide_slot_serpent = { key = "serpent", spell_id = 25295 }
local guide_slot_raptor_strike = { key = "raptor_strike", spell_id = 2973 }
local guide_slot_wyvern_strike = { key = "wyvern_strike", spell_id = 458482 }
local guide_slot_aspect_viper = { key = "aspect_viper", spell_id = 34074 }
local guide_slot_aspect_hawk = { key = "aspect_hawk", spell_id = 27044 }
local guide_slot_aspect_falcon = { key = "aspect_falcon", spell_id = 469145 }
local guide_slot_aspect_dragonhawk = { key = "aspect_dragonhawk", spell_id = 61847 }
local guide_slot_wing_clip = { key = "wing_clip", spell_id = 14268 }
local guide_slot_silencing_shot = { key = "silencing_shot", spell_id = 34490 }
local guide_slot_explosive_trap = { key = "explosive_trap", spell_id = 49067 }
local guide_slot_black_arrow = { key = "black_arrow", spell_id = 63672 }
local guide_slot_immolation_trap = { key = "immolation_trap", spell_id = 14305 }
local guide_slot_hunters_mark = { key = "hunters_mark", spell_id = 14325 }
local guide_slot_mongoose_bite = { key = "mongoose_bite", spell_id = 14271 }
-- The utility slots that carry a rank, keyed by the action key (one table, so
-- the resolver reaches them through a single reference - resolve_guide_icons
-- sits at Lua 5.1's upvalue limit).
local guide_slot_utility_by_action = {
    serpent = guide_slot_serpent,
    raptor_strike = guide_slot_raptor_strike,
    aspect_viper = guide_slot_aspect_viper,
    aspect_hawk = guide_slot_aspect_hawk,
    aspect_falcon = guide_slot_aspect_falcon,
    aspect_dragonhawk = guide_slot_aspect_dragonhawk,
}

-- The slot set is picked once at load: the Era slot set on the ERA family, the
-- Wrath slot set on the WRATH family, the Forever slot set on the FOREVER
-- family, the frozen base set everywhere else (Cata, Mists, Retail - clients
-- with no sourced rotation). The TBC client gets the base set plus its own
-- mana-swap slots, and the SoD slot set swaps in at post_init
-- (resolve_guide_icons) when the rune is known. Every set now covers the
-- actions its family's APL asks for (the utility layer included), so the guide
-- can light every line the engine can emit.
local is_era_guide = st.family == "ERA"
local is_wrath_guide = st.family == "WRATH"
local is_forever_guide = st.family == "FOREVER"
local guide_slots_base = { guide_slot_steady, guide_slot_raptor, guide_slot_kill_command,
    guide_slot_multi, guide_slot_bestial_wrath, guide_slot_rapid_fire }
local guide_slots_tbc = { guide_slot_steady, guide_slot_raptor, guide_slot_kill_command,
    guide_slot_multi, guide_slot_bestial_wrath, guide_slot_rapid_fire,
    guide_slot_aspect_viper, guide_slot_aspect_hawk }
local guide_slots_era = { guide_slot_aimed, guide_slot_raptor, guide_slot_multi,
    guide_slot_rapid_fire, guide_slot_serpent }
local guide_slots_wrath = { guide_slot_kill_shot, guide_slot_chimera,
    guide_slot_explosive, guide_slot_aimed_wrath, guide_slot_arcane, guide_slot_steady,
    guide_slot_aspect_viper, guide_slot_aspect_dragonhawk, guide_slot_silencing_shot,
    guide_slot_serpent, guide_slot_explosive_trap, guide_slot_multi, guide_slot_black_arrow }
local guide_slots_era_sod = { guide_slot_chimera, guide_slot_aimed, guide_slot_raptor,
    guide_slot_multi, guide_slot_rapid_fire, guide_slot_bestial_wrath,
    guide_slot_kill_shot, guide_slot_raptor_strike,
    guide_slot_wyvern_strike, guide_slot_aspect_viper, guide_slot_arcane,
    guide_slot_aspect_falcon, guide_slot_wing_clip }
-- The Mists set: the frozen base set WITHOUT the Raptor Strike. The Mists
-- client's own spell data carries no Raptor Strike id this tree knows (the
-- classic ladder, the TBC rank and the WotLK ranks are all absent there), so
-- the slot is dropped on both surfaces rather than pointed at a spell that
-- client cannot have. The HUD's dead-slot filter drops it too, so the two
-- surfaces agree (bench/hunter_sod_build_2026-10-20.md).
local guide_slots_mists = { guide_slot_steady, guide_slot_kill_command,
    guide_slot_multi, guide_slot_bestial_wrath, guide_slot_rapid_fire }
-- The Forever set carries NO Steady Shot: the Forever client has no Steady Shot at
-- all (the corpus correction of 2026-10-20 - bench/rotation_gap_vs_apl_2026-10-20.md
-- §0.0 H4: the spell arrived in 2.3 and the Forever spell data carries no
-- SteadyShot table), so the row is DROPPED rather than shipped dark - the same rule
-- the Era set follows for its three dead spells. The rotation table lost the row
-- in the same correction (bench/hunter_utility_live_2026-10-20.md §1); this is the
-- guide half of it.
local guide_slots_forever = { guide_slot_hawk, guide_slot_sniper,
    guide_slot_raptor, guide_slot_raptor_strike, guide_slot_hunters_mark,
    guide_slot_mongoose_bite, guide_slot_immolation_trap, guide_slot_wing_clip,
    guide_slot_serpent, guide_slot_arcane, guide_slot_multi }

-- Resolve the guide icons to the client's current ranks; called once from post_init,
-- before the shared frame builds its icons. A family the client does not know keeps the
-- rank-1 fallback, exactly like the module's other rank-id features.
function ST.HUNTER.resolve_guide_icons()
    steady_current_id = resolve_rank(steady_shot_ids)
    if steady_current_id then
        guide_slot_steady.spell_id = steady_current_id
    end
    raptor_current_id = resolve_rank(raptor_strike_ids)
    if raptor_current_id then
        guide_slot_raptor.spell_id = raptor_current_id
    end
    kill_command_current_id = resolve_rank(kill_command_ids)
    if kill_command_current_id then
        guide_slot_kill_command.spell_id = kill_command_current_id
    end
    multi_current_id = resolve_rank(multi_shot_ids)
    if multi_current_id then
        guide_slot_multi.spell_id = multi_current_id
    end
    bestial_wrath_current_id = resolve_rank(bestial_wrath_ids)
    if bestial_wrath_current_id then
        guide_slot_bestial_wrath.spell_id = bestial_wrath_current_id
    end
    rapid_fire_current_id = resolve_rank(rapid_fire_ids)
    if rapid_fire_current_id then
        guide_slot_rapid_fire.spell_id = rapid_fire_current_id
    end
    aimed_current_id = resolve_rank(aimed_shot_ids)
    if aimed_current_id then
        guide_slot_aimed.spell_id = aimed_current_id
    end
    -- The HUD's slots follow the guide's (ONE owner, so the two surfaces can never
    -- disagree about which spell the running client has): the rank that re-points a
    -- guide slot re-points the HUD slot of the same key. The HUD used to carry one
    -- family-blind id per slot, so on a client where that id does not exist (the TBC
    -- client's Steady Shot, bench/rotation_gap_vs_apl_2026-10-20.md §0.0 H3) the slot
    -- resolved to nothing: no name (and with it no cooldown/mana/range read) and no
    -- icon. The rank resolves through the SAME cached resolver as the guide, so the
    -- HUD and the guide can never disagree. A family that ships no slot for a spell
    -- (ERA, FOREVER) has no entry to re-point: the loop simply finds nothing.
    --
    -- The Aimed Shot slot walks ITS family's ladder (hud_aimed_rank_ids): the TBC r7
    -- (27065) and the WotLK instant shot (49050) live outside the vanilla table, and
    -- the guide's own aimed slots keep their own tables (the Wrath slot is a
    -- different object - see above).
    local hud_rank_by_key = {
        steady = steady_current_id,
        raptor = raptor_current_id,
        kill_command = kill_command_current_id,
        multi = multi_current_id,
        bestial_wrath = bestial_wrath_current_id,
        rapid_fire = rapid_fire_current_id,
        aimed = resolve_rank(hud_aimed_rank_ids),
    }
    for i = 1, #ST.HUNTER.HUD_SLOTS do
        local id = hud_rank_by_key[ST.HUNTER.HUD_SLOTS[i].key]
        if id then
            ST.HUNTER.HUD_SLOTS[i].spell = id
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
        local id = resolve_rank(ids)
        if id == nil then
            return nil
        end
        -- TBC state queries take the name (27019/27065 exist on TBC, so this
        -- probe does fire there); unknown spell data hides instead of probing.
        local token = spell_token(id)
        if token ~= nil and api.is_spell_known(token) then
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
    -- Serpent Sting: the knowledge flag the naked-Chimera guard reads. Resolved once
    -- here (the same knowledge gate as the Wrath prompts): known = the client knows a
    -- Serpent rank. The knowledge is also the scan's gate: with no known rank the
    -- guard can never withhold (it reads a KNOWN-down sting only), so the debuff
    -- scan does not run and the debuff stays unknown - an unknown debuff is
    -- "allow", so the knowledge alone can never silence the Chimera prompt.
    serpent_known = resolve_known(serpent_sting_ids) ~= nil or nil
    -- The APL UTILITY layer's ranks (the class's utility lines, 2026-10-20):
    -- the same knowledge-gated resolution as the Wrath prompts, one walk per
    -- line. A line whose rank never resolved stays dark (the engine's
    -- <line>_known gate), and the slots that carry a rank are re-pointed at the
    -- client's own rank so the icon matches the spell the arm asks for.
    for i = 1, #UTILITY_LINE_SPECS do
        local spec = UTILITY_LINE_SPECS[i]
        local id = resolve_known(spec.ids)
        utility_current[spec.action] = id
        local slot = guide_slot_utility_by_action[spec.action]
        if id and slot then
            slot.spell_id = id
        end
    end
    -- The utility Multi-Shot (the WotLK rank 49048 and the Forever rank): the
    -- knowledge gate is the same one the utility layer uses - a client that does
    -- not know the spell never prompts it. The weave's own multi (the Era and
    -- TBC cast) keeps its data-gated semantics.
    utility_multi_current_id = resolve_known(multi_shot_ids)
    -- The Serpent Sting slot follows the same rank walk (the serpent family is
    -- not in the utility table above: its ranks are the shared serpent_sting_ids).
    local serpent_rank = resolve_rank(serpent_sting_ids)
    if serpent_rank then
        guide_slot_utility_by_action.serpent.spell_id = serpent_rank
    end
    -- SoD (ERA token only): the rune detector is knowledge, never the family -
    -- api.is_spell_known on the SoD-only rune id. When the rune is known the
    -- Era set swaps to the Era-SoD set before the shared frame builds its icons
    -- (resolve runs before st.nextaction_ui.init in post_init), and the chimera
    -- slot re-points at the rune. A mid-session rune learn needs a reload
    -- (no frame rebuild exists); the engine gate below reads the same resolved
    -- id, so slots and prompts agree by construction. Idempotent: re-resolving
    -- assigns the same table.
    --
    -- The swap is decided ONCE (the frame is built from the slot set and never
    -- rebuilt, so a later swap could not reach the icons). The rune table itself is
    -- still resolved through the cached resolver - a client that cannot answer is
    -- NOT a client that refutes the rune (audit F4) - but a late answer cannot
    -- change the decided slot set, so the Era set stands.
    --
    -- This ONE decision is the running client's BUILD on the ERA family (the same
    -- 1.15.9 client runs the Era-base game and the SoD game, and the two games do
    -- not carry the same spells). BOTH surfaces read it: the guide's slot set
    -- swaps to the SoD set, and the HUD's Bestial Wrath slot - the one slot the
    -- Era family carries on the SoD build only - keeps its id here and is DROPPED
    -- on the Era-base build. So the two surfaces can never disagree about which
    -- spells the running build has.
    if is_era_guide and not sod_slot_set_decided then
        sod_slot_set_decided = true
        local sod_rune = nil
        if api.is_spell_known(409433) then
            sod_rune = resolve_rank(chimera_shot_sod_ids)
        end
        if sod_rune then
            chimera_current_id = sod_rune
            guide_slot_chimera.spell_id = sod_rune
            ST.HUNTER.guide.slots = guide_slots_era_sod
            -- The practice rotation follows the same swap (the shared engine
            -- reads ST.HUNTER.practice_rotation): the SoD set is the Era set with
            -- the Chimera rune on top.
            ST.HUNTER.practice_rotation = ST.HUNTER.PRACTICE_ROTATIONS.SOD
            -- The SoD build HAS the Bestial Wrath (the 1.15.9 client's own spell
            -- data maps 19574 to the Beast Mastery skill line), so the slot the
            -- Era-base pick drops ships here - with the client's own rank when the
            -- resolver answered, and with the owner table's SoD id otherwise.
            -- Both surfaces read the same id.
            local sod_bestial = bestial_wrath_current_id
                or SPELL_ID_BY_FAMILY.bestial_wrath.SOD
            guide_slot_bestial_wrath.spell_id = sod_bestial
            for i = 1, #ST.HUNTER.HUD_SLOTS do
                if ST.HUNTER.HUD_SLOTS[i].key == "bestial_wrath" then
                    ST.HUNTER.HUD_SLOTS[i].spell = sod_bestial
                end
            end
        else
            -- The Era-BASE build: the Bestial Wrath slot is dropped (the game
            -- never uses the 2.1 talent), exactly like the guide's Era slot set
            -- does not declare it. The slot ships with no id until this decision,
            -- so it was never offered as a dead cell in the meantime.
            local live_slots = {}
            for i = 1, #ST.HUNTER.HUD_SLOTS do
                if ST.HUNTER.HUD_SLOTS[i].key ~= "bestial_wrath" then
                    live_slots[#live_slots + 1] = ST.HUNTER.HUD_SLOTS[i]
                end
            end
            ST.HUNTER.HUD_SLOTS = live_slots
        end
        -- The neutral publish follows the SAME build decision: the SoD rotation
        -- asks for the Raptor Strike, so the `raptor` key must not be published as
        -- neutral on that build (a rotation action can never be neutral, and the
        -- panel offers the same spell under both keys). The era-base build keeps
        -- it - its rotation never asks for the Raptor Strike.
        ST.HUNTER.apply_neutral_build_pick()
    end
end

-- The retry driver: a client that could not answer the rank tables when the guide icons
-- were resolved gets asked again, once the shared backoff has expired, so a cold spell
-- book can no longer hide a rank for the rest of the session. Bounded: at most one walk
-- per pending table per backoff window, so the per-frame gather path never storms the
-- client. The same resolution pass re-points the icons, so a late answer reaches the
-- engine's known-flags (the prompt that was hidden while the client could not answer).
local function retry_pending_ranks(now)
    if #pending_ranks == 0 then
        return false
    end
    for i = 1, #pending_ranks do
        local retry_at = rank_retry_at[pending_ranks[i]] or 0
        if type(now) ~= "number" or now >= retry_at then
            ST.HUNTER.resolve_guide_icons()
            return true
        end
    end
    return false
end

-- Serpent Sting on the target: the predicate the target scan runs. The NAME first
-- and the id second (see the rank table above): every rank shares the name, so the
-- name leg covers the ranks this client actually ships, and the id leg covers the
-- three sourced ranks on the clients that answer with numeric ids.
local function serpent_debuff_matches(spell_id, name)
    if type(name) == "string" and name == SERPENT_STING_NAME then
        return true
    end
    if type(spell_id) == "number" and serpent_sting_ids[spell_id] then
        return true
    end
    return false
end

-- Serpent Sting on the target: true (the sting is up on it), false (the scan ran
-- against a real target and the sting is not on it) or nil (unknown - the read
-- could not be trusted). This is the naked-Chimera guard's whole contract: only a
-- KNOWN-down sting withholds the prompt, so an unknown never withholds it.
--
-- The scan runs through compat's api.scan_unit_aura (the unit-generic player
-- scan): the walk never breaks early, so a restricted row cannot truncate it, and
-- the predicate's own match flag carries the "the sting is there" answer (the
-- scan's own return value is nil for a match that carries no expiry, so it cannot
-- be the match signal).
--
-- The scan only runs when the client KNOWS a Serpent rank (serpent_known, the same
-- gate the guard reads): with no known rank the guard cannot withhold anything, so
-- no client pays for a scan it cannot use.
--
-- "the scan ran" is the trust question, and it has two answers:
--   * no target - there is nothing to scan, so the state is unknown (nil), never
--     "the sting is down" (checked BEFORE the scan, so a client with no target
--     spends no aura read at all);
--   * the secret-aura regime (api.auras_may_be_secret) - under it a row can be
--     hidden from the read, so a missing sting is unknown (nil), never "down".
-- Outside the secret regime (every shipped client) a missing row is an honest
-- "the sting is not up on this target".
local function read_serpent_active()
    if serpent_known ~= true then
        return nil
    end
    if type(api.scan_unit_aura) ~= "function" then
        return nil -- no scan on this build: hide, never throw
    end
    if not (UnitExists and UnitExists("target")) then
        return nil -- no target: there is nothing to scan (never "down")
    end
    local matched = false
    api.scan_unit_aura("target", function(spell_id, name)
        if serpent_debuff_matches(spell_id, name) then
            matched = true
            return true
        end
        return false
    end)
    if matched then
        return true
    end
    local secret_probe = api.auras_may_be_secret
    if type(secret_probe) == "function" and secret_probe() == true then
        return nil
    end
    return false
end

-- The APL UTILITY layer's aura reads (the class's utility lines, 2026-10-20).
-- Two shapes, both three-state, both on the same contract as
-- read_serpent_active above:
--   * a PLAYER BUFF (the aspect swaps): true (the buff is up), false (the scan
--     ran and the buff is not up) or nil (unknown - no scan on this build, or
--     the secret-aura regime can hide the row).
--   * a TARGET DEBUFF (Hunter's Mark): the same three states, and "no target"
--     is unknown (never "the mark is down").
-- The name leg is the primary key (the TBC client resolves spells by NAME and
-- holds only the Era ranks in its id tables); the id leg covers the clients
-- that answer with numeric ids.
local function utility_buff_active(ids, name)
    if type(api.scan_player_aura) ~= "function" then
        return nil
    end
    local matched = false
    api.scan_player_aura(function(spell_id, aura_name)
        if (type(spell_id) == "number" and ids[spell_id] ~= nil)
            or (name ~= nil and aura_name == name) then
            matched = true
            return true
        end
        return false
    end)
    if matched then
        return true
    end
    local secret_probe = api.auras_may_be_secret
    if type(secret_probe) == "function" and secret_probe() == true then
        return nil
    end
    return false
end

local function utility_debuff_active(ids, name)
    if type(api.scan_unit_aura) ~= "function" then
        return nil
    end
    if not (UnitExists and UnitExists("target")) then
        return nil -- no target: there is nothing to scan (never "down")
    end
    local matched = false
    api.scan_unit_aura("target", function(spell_id, aura_name)
        if (type(spell_id) == "number" and ids[spell_id] ~= nil)
            or (name ~= nil and aura_name == name) then
            matched = true
            return true
        end
        return false
    end)
    if matched then
        return true
    end
    local secret_probe = api.auras_may_be_secret
    if type(secret_probe) == "function" and secret_probe() == true then
        return nil
    end
    return false
end

-- Live inputs for the pure engine, written into the caller-owned reused table. Every
-- field of the frozen input set is written on every call, so no stale value can survive
-- between ticks; nil means "the client did not answer".

function ST.HUNTER.gather_guide_inputs(self, out)
    local inputs = out or ST.HUNTER.guide_inputs
    local now = api.get_time()
    local ranged = self.ranged

    -- A client that could not answer the rank tables when the guide icons were resolved
    -- gets another chance: the unresolved tables are re-asked on the shared backoff
    -- (never per frame) and the icons are re-pointed when a late answer arrives. No
    -- pending table means no probe at all.
    retry_pending_ranks(now)

    -- The ranged cycle and the clock, in the api.get_time() domain. A client without a
    -- ranged swing (Retail) answers nothing: every field stays nil and the engine then
    -- withholds every prompt rather than guessing.
    inputs.now = now
    inputs.swing_start = ranged and ranged.start or nil
    inputs.swing_speed = ranged and ranged.speed or nil
    inputs.swing_ends_at = ranged and ranged.ends_at or nil
    inputs.synced_duration = ranged and ranged.synced_duration or nil
    inputs.auto_repeat_active = (ranged and ranged.auto_repeat_active) == true

    -- Compensated world latency (calibrated when usable, raw fallback; never the
    -- twist lag calibration), the same basis the cast bar's clip tint uses.
    local latency = world_latency_seconds(self)
    inputs.latency = latency

    -- The hidden Auto-Shot window: the cached bounds the visual half last computed, or
    -- recomputed from the live cycle through the pure hunter_window maths (the same
    -- synced_duration-or-speed basis as the cast bar). The cache counts only while
    -- `now` sits inside it AND its end still lands on the live cycle's end
    -- (provenance: reference UI.lua:399-406 clears on every StartSwing; hunter_ui's
    -- get_hidden_window reads the same way) - a stale cache from a re-anchored
    -- cycle must never ride into the engine, or Steady/Auto prompts hold on a
    -- window that already closed. nil when the client cannot provide a cycle;
    -- the engine then never holds on window grounds.
    local window_start
    local window_duration
    if ranged then
        local cycle_duration = ranged.synced_duration or ranged.speed
        -- Provenance: the cache belongs to the live (start, cycle) only when its
        -- end still lands on the live cycle's end. A ranged re-anchor the hunter
        -- sync did not clear (the engine's START/UPDATE stamps next to the sync's
        -- own clears; the reference clears on every StartSwing) leaves a stale
        -- end behind, and the stale bounds must lose to the live recompute -
        -- otherwise Steady/Auto prompts hold on the previous cycle's window.
        local live_end
        if type(ranged.start) == "number" and type(cycle_duration) == "number"
            and cycle_duration > 0 then
            live_end = ranged.start + cycle_duration
        end
        local cached_start = ranged.hidden_window_start
        local cached_duration = ranged.hidden_window_duration
        if type(cached_start) == "number" and type(cached_duration) == "number"
            and cached_duration > 0 and type(now) == "number" and live_end ~= nil
            and math.abs((cached_start + cached_duration) - live_end) <= 1e-9
            and now >= cached_start and now <= cached_start + cached_duration then
            window_start, window_duration = cached_start, cached_duration
        else
            ranged.hidden_window_start = nil
            ranged.hidden_window_duration = nil
        end
        if window_start == nil and hunter_window and live_end ~= nil then
            -- The recompute rides through verbatim (even a future window): it is
            -- derived from the live cycle, so it is never stale, and the engine
            -- bounds-checks it (is_in_window, inclusive) before any HOLD. Only
            -- the cache above is gated.
            local start_bound, end_bound = hunter_window.hidden_window(
                ranged.start, cycle_duration, hunter_window.cast_window(latency))
            if start_bound ~= nil then
                window_start, window_duration = start_bound, end_bound - start_bound
            end
        end
    end
    inputs.hidden_window_start = window_start
    inputs.hidden_window_duration = window_duration

    -- The on-next-swing queue state the rules read.
    inputs.raptor_strike_queued = self.raptor_strike_queued == true
    inputs.steady_shot_queued = self.steady_shot_queued == true

    -- Steady Shot's cast time from the client's spell data (per-client fallback
    -- TBC/WRATH 1.5 s, nil where the family has no Steady Shot), cached once
    -- the spell cache answers. A family with no Steady Shot (the Forever client)
    -- has no id to probe at all, so it spends no query per tick.
    if steady_cast_time == nil then
        local steady_probe_id = steady_current_id or guide_slot_steady.spell_id
        if steady_probe_id ~= nil then
            local cast_ms = select(4, api.GetSpellInfo(steady_probe_id))
            if type(cast_ms) == "number" and cast_ms > 0 then
                steady_cast_time = cast_ms / 1000
            end
        end
    end
    inputs.steady_cast_seconds = steady_cast_time or ST.HUNTER.cast_time_fallback("steady")

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

    -- Multi-Shot's cast time from the client's spell data (per-client fallback
    -- ERA/TBC/WRATH 0.5 s, nil elsewhere), cached once the spell cache answers
    -- (the same retry discipline as the Steady Shot cast time).
    if multi_cast_time == nil then
        local cast_ms = select(4, api.GetSpellInfo(
            multi_current_id or guide_slot_multi.spell_id))
        if type(cast_ms) == "number" and cast_ms > 0 then
            multi_cast_time = cast_ms / 1000
        end
    end
    inputs.multi_cast_seconds = multi_cast_time or ST.HUNTER.cast_time_fallback("multi")

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
    -- Rapid Fire: the TBC blanket cooldown layer AND the ERA/SOD APL rows (the
    -- ERA APL's i=1 and the SOD APL's i=7). The knowledge gate carries the
    -- family: the TBC client, the Era client and the SoD client all know the
    -- spell; the Forever client does not get the row (its APL asks for no
    -- Rapid Fire), so the gate stays off there.
    inputs.rf_known = (is_tbc or is_era_guide) and rapid_fire_current_id ~= nil
    inputs.rf_remaining_cd = get_guide_cooldown(
        rapid_fire_current_id or guide_slot_rapid_fire.spell_id)
    inputs.multi_known = (is_tbc or is_era_guide) and multi_current_id ~= nil
    inputs.multi_remaining_cd = get_guide_cooldown(
        multi_current_id or guide_slot_multi.spell_id)

    -- Era Aimed Shot: the primary filler (3 s cast, 6 s cooldown). Every aimed_*
    -- input is written on every call; off-Era clients gather nil/false without any
    -- client query, so their cooldown-query count and behaviour stay byte-identical
    -- (the warrior's bt/ww split). The cast time comes from the client's spell data
    -- with the per-client fallback (ERA 3.0 s), cached once the spell cache answers.
    if is_era_guide then
        if aimed_cast_time == nil then
            local cast_ms = select(4, api.GetSpellInfo(
                aimed_current_id or guide_slot_aimed.spell_id))
            if type(cast_ms) == "number" and cast_ms > 0 then
                aimed_cast_time = cast_ms / 1000
            end
        end
        inputs.aimed_cast_seconds = aimed_cast_time or ST.HUNTER.cast_time_fallback("aimed")
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
    -- comes from the client's spell data with the per-client fallback (FOREVER
    -- 4.0 s), cached once the spell cache answers, and is read only while a
    -- Sniper rank is resolved.
    inputs.hawk_known = hawk_current_id ~= nil
    inputs.hawk_active_count = nil
    inputs.hawk_remaining_cd = get_guide_cooldown(hawk_current_id)
    if sniper_cast_time == nil and sniper_current_id ~= nil then
        local cast_ms = select(4, api.GetSpellInfo(sniper_current_id))
        if type(cast_ms) == "number" and cast_ms > 0 then
            sniper_cast_time = cast_ms / 1000
        end
    end
    inputs.sniper_cast_seconds = sniper_cast_time or ST.HUNTER.cast_time_fallback("sniper")
    inputs.sniper_known = sniper_current_id ~= nil
    inputs.sniper_remaining_cd = get_guide_cooldown(sniper_current_id)

    -- The APL UTILITY layer's live reads (the class's utility lines, 2026-10-20).
    -- Every field is written on every call (the frozen input discipline): a line
    -- that does not apply to this family, or whose rank never resolved, reads
    -- false/nil - never a stale value and never a guess.
    --
    -- The family token is the class's own: "SOD" on the ERA token with the
    -- Chimera rune known (the SoD shares the ERA family token, so the family
    -- alone never decides - the same detector rule 5b uses).
    local utility_family = st.family
    if is_era_guide and chimera_current_id ~= nil then
        utility_family = "SOD"
    end
    for i = 1, #UTILITY_LINE_SPECS do
        local spec = UTILITY_LINE_SPECS[i]
        local applies = false
        for j = 1, #spec.families do
            if spec.families[j] == utility_family then
                applies = true
                break
            end
        end
        local id = utility_current[spec.action]
        if not applies or id == nil then
            inputs[spec.action .. "_known"] = false
            inputs[spec.action .. "_remaining_cd"] = nil
            inputs[spec.action .. "_active"] = nil
        elseif spec.kind == "cooldown" then
            inputs[spec.action .. "_known"] = true
            inputs[spec.action .. "_remaining_cd"] = get_guide_cooldown(id)
            inputs[spec.action .. "_active"] = nil
        else
            inputs[spec.action .. "_known"] = true
            inputs[spec.action .. "_remaining_cd"] = nil
            local names = UTILITY_AURA_NAMES[spec.action]
            if spec.kind == "buff" then
                inputs[spec.action .. "_active"] = utility_buff_active(spec.ids, names)
            else
                inputs[spec.action .. "_active"] = utility_debuff_active(spec.ids, names)
            end
        end
    end
    -- The Multi-Shot the UTILITY layer reads (the WotLK rank 49048 and the
    -- Forever rank): the weave's own multi_known stays the Era and TBC cast
    -- (the WotLK and Forever Multi are instants, not cast shots), so the
    -- utility Multi carries its own pair.
    inputs.utility_multi_known = (is_wrath_guide or is_forever_guide)
        and utility_multi_current_id ~= nil
    if is_wrath_guide or is_forever_guide then
        inputs.utility_multi_remaining_cd = get_guide_cooldown(utility_multi_current_id)
    else
        inputs.utility_multi_remaining_cd = nil
    end
    -- The mana fraction the aspect swaps read (the APL's own thresholds): the
    -- read runs only on the families that have an aspect row, so no other
    -- client spends the probe. Unknown (nil) never prompts a swap.
    if utility_family == "SOD" or utility_family == "TBC"
        or utility_family == "WRATH" then
        inputs.mana_frac = ST.HUNTER.get_mana_fraction()
    else
        inputs.mana_frac = nil
    end

    -- H2 CUT (operator order 2026-10-19, bench/hunter_open_2026-10-19.md
    -- section 5): no Bloodlust/Heroism-family aura scan here and no weave
    -- suppression in the engine (hunter_guide.lua rule 6). Haste shortens the
    -- live cycle length, so the synced-duration clip math alone decides which
    -- casts fit: sim-faithful, best for practice. Re-enable path (future
    -- conservative-playstyle opt-in, a follow-up, not this lane): re-add the
    -- frozen weave input carrying the live aura's remaining seconds, the
    -- throttled compat player-aura scan writing it every gather call, and the
    -- rules 6a/6b gate on it; re-pin the H2 blocks in
    -- tests/hunter_guide_state.lua and the gather pins in tests/hunter_state.lua.

    -- Lock and Load / Serpent / Sniper-range inputs (bench/hunter_rotation_audit_2026-10-19.md
    -- findings 1, 2, 5, 8):
    --   lnl_ready: the proc window the W-LnL / SoD-LnL arms read (Wrath 56344 / SoD
    --     415413, SIM-CONFIRMED, CLIENT-UNCONFIRMED). The class ALREADY probes the
    --     player's own aura for the LnL badge (get_lnl_remaining above), so the guide
    --     reads the SAME throttled probe - no new client read and no second scan. The
    --     probe runs only on the families that have the talent (Wrath, and the SoD
    --     rune on the Era family), so no other client spends the scan. Unknown (nil)
    --     = no window = the old behaviour: the probe answers only when the player's
    --     own aura carries one of the two ids, so a wrong id is simply inert.
    --   serpent_known: the client knows a Serpent Sting rank (resolved once at
    --     post_init, the same knowledge gate as the Wrath prompts).
    --   serpent_active: the Serpent Sting DEBUFF on the target, a three-state feed:
    --     true (the sting is up on the target), false (the scan ran against a real
    --     target and the sting is not on it) or nil (unknown - no target, or the
    --     secret-aura regime can hide the row). Only a KNOWN-down sting withholds
    --     the naked-Chimera prompt; an unknown still allows it.
    --   sniper_range_buff_active: the Forever Sniper range buff has no source yet
    --     (filed), so it stays unknown and rule 2b holds as before.
    -- Every field is written on every call (the frozen input discipline).
    local lnl_remaining = nil
    if is_wrath_guide or (is_era_guide and chimera_current_id ~= nil) then
        lnl_remaining = ST.HUNTER.get_lnl_remaining(self, now)
    end
    inputs.lnl_ready = (type(lnl_remaining) == "number" and lnl_remaining > 0) or nil
    inputs.serpent_known = serpent_known or nil
    inputs.serpent_active = read_serpent_active()
    inputs.sniper_range_buff_active = nil

    -- The ranged range of the Steady Shot school; nil = unknown (the engine never treats
    -- nil as out of range). One client probe, no allocation. TBC resolves the name
    -- (never a bare id); unknown spell data hides instead of probing nil.
    local range_token = spell_token(steady_current_id or guide_slot_steady.spell_id)
    inputs.target_in_range = nil
    if range_token ~= nil then
        inputs.target_in_range = api.IsSpellInRange(range_token, "target")
    end

    -- The distance band for the WA Dynamic switch (see above): main's
    -- LibRangeCheck poll, read off ST (no new probe, no family branch -- the
    -- lib's init/deadline is main-owned). Band nil while the lib publishes
    -- nothing. The engine reads nothing from it yet (filed arm); written on
    -- every call per the frozen input discipline.
    inputs.weave_band = ST.HUNTER.get_weave_band(
        self.in_melee_range, self.in_ranged_range,
        self.target_min_range, self.target_max_range)
    return inputs
end

ST.HUNTER.guide = {
    slots = is_era_guide and guide_slots_era
        or (is_wrath_guide and guide_slots_wrath
            or (is_forever_guide and guide_slots_forever
                or (st.family == "TBC" and guide_slots_tbc
                    or (st.family == "MISTS" and guide_slots_mists
                        or guide_slots_base)))),

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
-- the two trinket slots the HUD serves itself. On the ERA family the dead slots
-- filter out (the Era pick below), so the HUD and the guide never disagree about
-- which abilities matter.
-- The descriptor and provider contracts are frozen in hud.lua's header comment; the
-- "trinket" slots need no provider entry.
--
-- Rank notes: every spell slot ships the FAMILY's own id (SPELL_ID_BY_FAMILY - the
-- client's own rank for that family), while the provider reads cooldowns by the
-- client's own localized name (hud_slot_name), so whatever rank the player knows is
-- what is counted - the paladin's cooldown_spell-free convention from
-- classes/paladin.lua. resolve_guide_icons re-points every slot at the client's
-- current rank through the cached resolver, exactly like the guide's slots.
-- Steady Shot and Raptor Strike have no cooldown of their own on the classic line:
-- their slots show the running GCD swipe plus the mana/range tints.
-- Aimed Shot slot semantics: the descriptor ships the family's own rank (the
-- vanilla 20904 on the classic-line clients, the TBC r7 27065, the WotLK instant
-- shot 49050); resolve_guide_icons re-points it at the client's current rank
-- through the cached resolver (hud_aimed_rank_ids), and the
-- provider's name-based read counts whatever rank the player knows. Aimed Shot
-- carries a real 6 s cooldown only on Era (the guide's aimed_remaining_cd input);
-- on every other client the API reports no cooldown and the slot shows the running
-- GCD swipe plus the mana/range tints, exactly like Steady Shot and Raptor Strike.
-- The guide's cast-time display (the 3 s Era cast riding rule 1) has no HUD mirror:
-- the HUD tracks cooldowns, never live casts.
-- Era family pick (H-HUD-1, bench/rogue_hunter_eratbc_2026-10-19.md §5): Steady
-- Shot and Kill Command never prompt on Era (the guide drops them), so the HUD
-- ships the live slots instead of dead ones. Same descriptors, same order,
-- filtered in place. The Bestial Wrath is the one slot that is BUILD-dependent:
-- the Era-base game never uses the 2.1 talent, but the SoD build of the same
-- 1.15.9 client HAS it, so the slot ships with no id until the build is known
-- and the Era-base build drops it at post_init (the SoD build keeps it with the
-- SoD id). The guide's slot set follows the same decision, so the two surfaces
-- agree.
-- Forever family pick: the Forever client has NO Steady Shot at all (the corpus
-- correction of 2026-10-20 - bench/rotation_gap_vs_apl_2026-10-20.md §0.0 H4) and
-- NO Kill Command either (its own hunter spell table carries no Kill Command
-- entry - wowsims/forever sim/hunter/spell_data_auto_gen.go), so both slots filter
-- out there: a slot for a spell the client cannot have is dropped, never shipped
-- dark. The Forever guide set declares neither, so the two surfaces agree.
ST.HUNTER.HUD_SLOTS = {
    -- Every spell slot carries the FAMILY's own id (SPELL_ID_BY_FAMILY), not one
    -- family-blind id: the old fixed ids left a slot without a name (and without an
    -- icon) on every client that does not carry them - the TBC client has no
    -- vanilla Steady Shot 56641, the WotLK client no vanilla Aimed Shot 19434 as
    -- its own shot, and the Forever client no Kill Command at all. resolve_guide_icons
    -- re-points every slot at the client's own rank, exactly like the guide's slots.
    { key = "steady", title = "Steady Shot", kind = "spell",
        spell = SPELL_ID_BY_FAMILY.steady[st.family] },
    { key = "raptor", title = "Raptor Strike", kind = "spell",
        spell = SPELL_ID_BY_FAMILY.raptor[st.family] },
    { key = "kill_command", title = "Kill Command", kind = "spell",
        spell = SPELL_ID_BY_FAMILY.kill_command[st.family] },
    { key = "multi", title = "Multi-Shot", kind = "spell",
        spell = SPELL_ID_BY_FAMILY.multi[st.family] },
    { key = "bestial_wrath", title = "Bestial Wrath", kind = "spell",
        spell = SPELL_ID_BY_FAMILY.bestial_wrath[st.family] },
    { key = "rapid_fire", title = "Rapid Fire", kind = "spell",
        spell = SPELL_ID_BY_FAMILY.rapid_fire[st.family] },
    { key = "aimed", title = "Aimed Shot", kind = "spell",
        spell = SPELL_ID_BY_FAMILY.aimed[st.family] },
    { key = "trinket1", title = "Trinket 1", kind = "trinket", inv_slot = 13 },
    { key = "trinket2", title = "Trinket 2", kind = "trinket", inv_slot = 14 },
}
-- The dead-slot filter: a slot for a spell the running client does not have never
-- ships (the HUD shows a live row, not a dead cell). One table, one rule, per
-- FAMILY:
--   ERA      Steady Shot / Kill Command. The Bestial Wrath is the one slot the
--            ERA family carries on ONE build only: the SoD build of the same
--            1.15.9 client HAS it (the client's own spell data maps 19574 to the
--            Beast Mastery skill line) while the Era-BASE game never uses the
--            2.1 talent. The build is the class's own SoD probe (the Chimera
--            Shot rune), decided at post_init - the same decision that swaps the
--            guide's slot set, so the two surfaces can never disagree. The slot
--            therefore ships here with NO id (an id-less slot is never offered,
--            so it is not a dead cell) and the Era-base build drops it at
--            post_init; the SoD build gives it the SoD id.
--   FOREVER  Steady Shot (the client has no Steady Shot at all - §0.0 H4) and Kill
--            Command (the Forever client's own hunter spell table carries no Kill
--            Command entry - wowsims/forever sim/hunter/spell_data_auto_gen.go;
--            the Forever guide set declares neither).
--   MISTS    Raptor Strike: the Mists client's own spell data carries no
--            Raptor Strike id this tree knows (SPELL_ID_BY_FAMILY.raptor), so the
--            slot is dropped there rather than pointed at a spell that client
--            cannot have. The guide's Mists slot set does not declare it either.
local HUD_DEAD_SLOTS = {
    ERA = { steady = true, kill_command = true },
    FOREVER = { steady = true, kill_command = true },
    MISTS = { raptor = true },
}
local hud_dead_slots = HUD_DEAD_SLOTS[st.family]
if hud_dead_slots then
    local live_slots = {}
    for i = 1, #ST.HUNTER.HUD_SLOTS do
        if not hud_dead_slots[ST.HUNTER.HUD_SLOTS[i].key] then
            live_slots[#live_slots + 1] = ST.HUNTER.HUD_SLOTS[i]
        end
    end
    ST.HUNTER.HUD_SLOTS = live_slots
end

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
    local query = hud_slot_name(slot) or spell_token(slot.spell)
    if query == nil then
        return 0, HUD_COOLDOWN_FALLBACK[slot.key] or 0
    end
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
    local ok, _, insufficient = pcall(api.IsSpellUsable, name or spell_token(slot.spell))
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

    -- ISS tint (hunter_open §1): while the Improved Steady Shot proc is banked,
    -- the Steady (producer) and Aimed (discounted consumer) slots glow. HUD only:
    -- the guide engine never reads this. Option-gated nil = off; an unreadable
    -- proc never glows.
    if (slot.key == "steady" or slot.key == "aimed")
        and db.hunter_iss_badge_enabled == true then
        local iss = ST.HUNTER.get_iss_remaining(self, now)
        if type(iss) == "number" and iss > 0 then
            s.glow = true
        end
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

-- The namespace mirror this file used to carry (st.HUNTER = ST.HUNTER) is GONE:
-- the shared engine resolves the class module from the AceAddon table FIRST (the
-- class tables live there - main.lua creates ST.HUNTER and every class module
-- reaches it through LibStub), and the namespace is only the fallback. The
-- central fix landed in practice.lua (H.practice_class_module reads the addon
-- object first), so the engine finds this class's practice hooks without any
-- per-class alias - see hands-up.md HU-7 and
-- bench/practice_scenario_engine_2026-10-19.md section 6.
-- tests/wiring_check.lua check 7 fails the build if a class module publishes
-- itself onto the namespace again (the class file's file scope runs on EVERY
-- client, so a namespace write there is a load-time landmine).

--=========================================================================================
-- Practice: the rotation table, the scenario step and the class drills
--=========================================================================================
-- The practice contract the shared engine looks up by player_class (the orchestrator's
-- contract, 2026-10-19):
--   ST.HUNTER.practice_rotation       the running family's shot priority, in the sim's
--                                    own order; every entry cites its sim source
--   ST.HUNTER.practice_scenario_step  the expected action at one scenario decision
--   ST.HUNTER.practice_drills         the class drills (registry key + label + grade)
--
-- The decision model is the SAME engine the live guide uses (st.hunter_guide.evaluate,
-- the frozen rule matrix in hunter_guide.lua), so the scenario can never teach a
-- rotation the guide would not prompt. Nothing here reads the client: the scenario is
-- a SIMULATION, and every number it uses is a sim value (cited below), a value already
-- frozen in the tree (cited to its file:line) or a [DESIGN] number of ours.
--
-- The ctx the shared engine passes (the orchestrator's contract):
--   now          the clock, in the caller's own domain
--   last_action  the action the player pressed last (nil before the first press)
--   resources    the resource snapshot (the hunter's mana; the guide reads no mana
--                input today - the audit's mana group was CUT from the guide engine,
--                bench/hunter_open_2026-10-19.md §2 - so it only reaches the report)
--   cooldowns    a map of action key -> remaining seconds (a number) or
--                { remaining = seconds }; a key the map does not mention reads OFF
--                cooldown (a fresh scenario has every cooldown ready)
-- Optional extras the class understands (each absent = the documented default):
--   cycle_duration  the simulated Auto Shot cycle (default PRACTICE_CYCLE_SECONDS)
--   latency         the simulated world latency in seconds (default 0)
--   target_hp_frac  the target's health fraction (nil = unknown: Kill Shot never
--                    prompts on an unknown health, exactly like the live engine)
--   spec            "MM" or "SV" (the Wrath spec the scenario runs; the default is
--                    the union of both arms, which is the engine's own order)
--   time_to_pull    the seconds until the pull (negative after it) - the opener drill
--   ready_at        when the expected cooldown came off cooldown - the pop drill
--   mispicks        the session's mis-pick count - the drills then grade the RUN
--                    (the audit's session bands) instead of the single decision
--
-- The rotation tables (ST.HUNTER.PRACTICE_ROTATIONS) are the per-family priority from
-- the sim APLs, each entry citing the source that produced it
-- (bench/class_features_drills_2026-10-19.md §2.3 (D); the per-client audits
-- bench/hunter_rotation_audit_2026-10-19.md and bench/hunter_open_2026-10-19.md):
--   ERA     wowsims/classic sim/hunter/hunter.go Initialize (Aimed Shot shares the
--           auto-shot timer with Arcane Shot; the Multi timer; Raptor/AutoSwingMelee)
--   SOD     wowsims/sod sim/hunter/chimera_shot.go (409433, instant, 6 s CD) +
--           ui/hunter/apls/p7_weave.apl.json + docs/research/rotations_sod.md:16-23
--           (Auto/Chimera/Auto/Aimed/Auto/Multi)
--   TBC     wowsims/tbc-new ui/specs/hunter/dps/apls/default.apl.json (Kill Command
--           34026 is the first spell in the priority list) + sim/hunter/steady_shot.go
--           (34120, 1500 ms) + sim/hunter/multi_shot.go (27021, 500 ms)
--   WRATH   wowsims/wotlk sim/hunter/* (chimera_shot.go, explosive_shot.go,
--           steady_shot.go) + ui/hunter/presets.ts + the guide-derived priority in
--           docs/research/rotations_wrath.md:9-16 (Kill Shot > Chimera (MM) >
--           Explosive (SV) > Aimed > Arcane > Steady filler)
--   FOREVER wowsims/forever ui/specs/hunter/dps/apls/default.apl.json +
--           sim/hunter/summon_hawk.go (the upkeep) + sim/hunter/sniper_shot.go (4 s)
--
-- The APL GAP ANALYSIS (bench/rotation_gap_vs_apl_2026-10-20.md §2, the operator's
-- "a rotation that only carries the damage abilities is not the class's rotation")
-- added the APL's UTILITY/SPINE layer: the Serpent Sting upkeep, the Aspect of the
-- Viper / Hawk / Falcon / Dragonhawk swaps, the Kill Shot execute and the APL's
-- melee/trap rows. The orchestrator's ruling (HU-12, 2026-10-20) splits the APL:
-- the rotation table carries the APL's SPELL ROWS; the APL's PRE-PULL rows stay in
-- the prepull table below (they are already there) - so the SoD's Serpent Sting
-- (a prepullActions row) and the Forever's Hawk (prepullActions i=1) are NOT
-- rotation rows here.
--
-- EVERY ENTRY carries the same shape:
--   action      the class's own action key (the practice panel's button key; the
--               engine's prompt key for an engine row)
--   label       the English name the practice panel shows
--   spell_id    the id this family's APL casts
--   spell_name  the client's English name for that id. The TBC client resolves
--               spells by NAME and the Era client by ID (bench/lessons.md), so both
--               travel together: the id for the id-resolving families, the name
--               for the name-resolving one.
--   families    the family tokens whose SIM plays the line (the family gate - the
--               same table is read per family, so the gate rides on the line)
--   live        true when the line's READ exists in the shipped tree today AND
--               the line can be evaluated from it (HU-13, orchestrator ruling
--               2026-10-20); false when the line still waits for a read that does
--               not exist yet - the entry then names that exact read in `needs`
--   engine      true when the frozen guide engine has an arm that can ask for
--               the line on this family (HU-13); false on a line the engine
--               still has no arm for, so it never feeds the engine's inputs and
--               never joins the practice panel's action vocabulary
--   needs       (a live = false line) the exact read the line is waiting for
--   source      the APL file and the row's index, plus the sim citation
--   specs       (Wrath only) the arms the row belongs to (MM / SV)
--
-- The engine-facing rows keep their shipped order (the order the guide plays them
-- and the order the practice panel's buttons carry). The APL's spine rows follow,
-- in the APL's own priority order, each citing its APL index. Every row whose
-- read landed and whose engine arm landed is engine-facing now, so the panel's
-- action vocabulary is the family's WHOLE spine.
ST.HUNTER.PRACTICE_ROTATIONS = {
    ERA = {
        {
            action = "aimed", label = "Aimed Shot",
            spell_id = 19434, spell_name = "Aimed Shot",
            families = { "ERA" }, live = true, engine = true,
            source = "wowsims/classic ui/hunter/apls/p1.apl.json i=2 (20904 r6; the shipped id 19434 is the client's rank-1) - wowsims/classic sim/hunter/hunter.go Initialize (Aimed Shot shares the auto-shot timer with Arcane Shot); the 3 s weave above Multi",
        },
        {
            action = "multi", label = "Multi-Shot",
            spell_id = 2643, spell_name = "Multi-Shot",
            families = { "ERA" }, live = true, engine = true,
            source = "wowsims/classic ui/hunter/apls/p1.apl.json i=3 (25294 r4; the shipped id 2643 is the client's rank-1) - wowsims/classic sim/hunter/hunter.go Initialize (the Multi Shot timer); the weave filler behind Aimed",
        },
        {
            action = "rapid_fire", label = "Rapid Fire",
            spell_id = 3045, spell_name = "Rapid Fire",
            families = { "ERA" }, live = true, engine = true,
            source = "wowsims/classic ui/hunter/apls/p1.apl.json i=1 (3045: the on-cooldown burst - cast when the Auto Shot is due and Aimed Shot is off cooldown) - the gather's Rapid Fire read now covers the Era family (the rf_known gate), and the engine's rule 5 asks for it above the weave",
        },
        {
            action = "serpent", label = "Serpent Sting",
            spell_id = 25295, spell_name = "Serpent Sting",
            families = { "ERA" }, live = true, engine = true,
            source = "wowsims/classic ui/hunter/apls/p1.apl.json i=4 (25295 r8: the dot upkeep - dotRemainingTime < 5 s) - the read exists (read_serpent_active: the name-first target debuff scan) and the engine has a serpent arm (rule 6d, behind the Multi at i=3). The arm asks when the sting is KNOWN DOWN, not at the APL's 5 s mark: a line whose buff is up is never asked for (the 5 s early refresh is a refinement the three-state read does not carry)",
        },
    },
    SOD = {
        {
            action = "chimera", label = "Chimera Shot",
            spell_id = 409433, spell_name = "Chimera Shot",
            families = { "SOD" }, live = true, engine = true,
            source = "wowsims/sod ui/hunter/apls/p7_weave.apl.json i=3 (409433: the top of the ranged weave, the Serpent rollover) - wowsims/sod sim/hunter/chimera_shot.go (409433, instant, 6 s CD)",
        },
        {
            action = "aimed", label = "Aimed Shot",
            spell_id = 19434, spell_name = "Aimed Shot",
            families = { "SOD" }, live = true, engine = true,
            source = "wowsims/sod ui/hunter/apls/p7_weave.apl.json + docs/research/rotations_sod.md:16-23 (the 3 s Aimed behind the Chimera) - the SoD priority list has no Aimed row (the APL's Aimed Shot is a PRE-PULL row, prepullActions i=1, so that copy stays in the prepull table)",
        },
        {
            action = "multi", label = "Multi-Shot",
            spell_id = 2643, spell_name = "Multi-Shot",
            families = { "SOD" }, live = true, engine = true,
            source = "wowsims/sod ui/hunter/apls/p7_weave.apl.json i=14 (25294 r5; the shipped id 2643 is the client's rank-1) (Multi 2643 behind the Aimed)",
        },
        {
            action = "rapid_fire", label = "Rapid Fire",
            spell_id = 3045, spell_name = "Rapid Fire",
            families = { "SOD" }, live = true, engine = true,
            source = "wowsims/sod ui/hunter/apls/p7_weave.apl.json i=7 (3045: the on-cooldown burst, fight >= 4 s) - the gather's Rapid Fire read now covers the SoD (the rf_known gate), and the engine's rule 5 asks for it behind the Chimera rune (the APL's i=3)",
        },
        {
            action = "kill_shot", label = "Kill Shot",
            spell_id = 409593, spell_name = "Kill Shot",
            families = { "SOD" }, live = true, engine = true,
            source = "wowsims/sod ui/hunter/apls/p7_weave.apl.json i=12, i=13 and i=18-21 (409593: the execute - cast when Rapid Fire is up or the target is in the E20 phase) - wowsims/sod proto/hunter.proto:153 (RuneLegsKillShot = 409593); the read exists (the 409593 rank in kill_shot_ids plus api.GetSpellCooldown) and the engine has a SoD execute arm (rule 5d; only the E20 half of the APL's condition is modelled)",
        },
        {
            action = "raptor_strike", label = "Raptor Strike",
            spell_id = 14266, spell_name = "Raptor Strike",
            families = { "SOD" }, live = true, engine = true,
            source = "wowsims/sod ui/hunter/apls/p7_weave.apl.json i=16 (14266 r8: the melee weave) - the read exists (the 14266 rank in raptor_strike_ids plus api.GetSpellCooldown) and the engine has a melee-weave arm (rule 5e; the weave band must read melee)",
        },
        {
            action = "wyvern_strike", label = "Wyvern Strike",
            spell_id = 458482, spell_name = "Wyvern Strike",
            families = { "SOD" }, live = true, engine = true,
            source = "wowsims/sod ui/hunter/apls/p7_weave.apl.json i=17 (458482: the SoD bleed) - the read exists (api.GetSpellCooldown on 458482) and the engine has a melee-weave arm (rule 5f)",
        },
        {
            action = "aspect_viper", label = "Aspect of the Viper",
            spell_id = 415423, spell_name = "Aspect of the Viper",
            families = { "SOD" }, live = true, engine = true,
            source = "wowsims/sod ui/hunter/apls/p7_weave.apl.json i=22 (415423: the OOM swap, mana < 5%) - wowsims/sod sim/hunter/aspects.go:193-201 (415423, 'Aspect of the Viper'); the read exists (the aura scan on 415423 plus the mana fraction) and the engine has a swap arm (rule 5g)",
        },
        {
            action = "arcane", label = "Arcane Shot",
            spell_id = 14287, spell_name = "Arcane Shot",
            families = { "SOD" }, live = true, engine = true,
            source = "wowsims/sod ui/hunter/apls/p7_weave.apl.json i=23 (14287 r8: the SoD filler) - the read exists (the 14287 rank in arcane_shot_ids plus api.GetSpellCooldown) and the engine has a SoD filler arm (rule 5h)",
        },
        {
            action = "aspect_falcon", label = "Aspect of the Falcon",
            spell_id = 469145, spell_name = "Aspect of the Falcon",
            families = { "SOD" }, live = true, engine = true,
            source = "wowsims/sod ui/hunter/apls/p7_weave.apl.json i=24 (469145: the aspect swap back, when the Viper is not up) - wowsims/sod sim/hunter/aspects.go:143-145 (469145, 'Aspect of the Falcon'); the read exists (the aura scan on 469145) and the engine has a swap arm (rule 5i)",
        },
        {
            action = "wing_clip", label = "Wing Clip",
            spell_id = 14268, spell_name = "Wing Clip",
            families = { "SOD" }, live = true, engine = true,
            source = "wowsims/sod ui/hunter/apls/p7_weave.apl.json i=27 (14268 r3: the melee debuff) - the read exists (api.GetSpellCooldown on 14268) and the engine has a melee-weave arm (rule 5j)",
        },
    },
    TBC = {
        {
            action = "kill_command", label = "Kill Command",
            spell_id = 34026, spell_name = "Kill Command",
            families = { "TBC" }, live = true, engine = true,
            source = "wowsims/tbc-new ui/specs/hunter/dps/apls/default.apl.json i=2 (34026 is the first spell row in the priority list)",
        },
        {
            action = "bestial_wrath", label = "Bestial Wrath",
            spell_id = 19574, spell_name = "Bestial Wrath",
            families = { "TBC" }, live = true, engine = true,
            source = "wowsims/tbc-new default.apl.json (the on-cooldown burst pops) - the TBC priority list has no Bestial Wrath row of its own (the APL's blanket cooldown layer is the autocastOtherCooldowns row, i=1; the guide's TBC slot is this row's home)",
        },
        {
            action = "rapid_fire", label = "Rapid Fire",
            spell_id = 3045, spell_name = "Rapid Fire",
            families = { "TBC" }, live = true, engine = true,
            source = "wowsims/tbc-new default.apl.json (the on-cooldown burst pops) - the TBC priority list has no Rapid Fire row of its own (the APL's blanket cooldown layer is the autocastOtherCooldowns row, i=1; the guide's TBC slot is this row's home)",
        },
        {
            action = "arcane", label = "Arcane Shot",
            spell_id = 27019, spell_name = "Arcane Shot",
            families = { "TBC" }, live = true, engine = true,
            source = "wowsims/tbc-new ui/specs/hunter/dps/apls/default.apl.json i=6 and i=9 ('Use Arcane Shot', 27019 r9, the core filler) - DORMANT in the engine (TBC_ARCANE_ENABLED = false: the base set is full 6/6), so the engine never prompts it",
        },
        {
            action = "multi", label = "Multi-Shot",
            spell_id = 2643, spell_name = "Multi-Shot",
            families = { "TBC" }, live = true, engine = true,
            source = "wowsims/tbc-new ui/specs/hunter/dps/apls/default.apl.json i=5 and i=8 (27021 r6 behind the Steady gap: 'Next cycle gap after steady'; the shipped id 2643 is the client's rank-1)",
        },
        {
            action = "steady", label = "Steady Shot",
            spell_id = 34120, spell_name = "Steady Shot",
            families = { "TBC" }, live = true, engine = true,
            source = "wowsims/tbc-new ui/specs/hunter/dps/apls/default.apl.json i=3, i=7 and i=9 (34120 r1: the filler) - wowsims/tbc-new sim/hunter/steady_shot.go (34120, 1500 ms; the demoted filler); the shipped id 56641 is the WotLK rank-1, which the TBC client does not have (wowhead TBC 56641: no such spell)",
        },
        {
            action = "aspect_viper", label = "Aspect of the Viper",
            spell_id = 34074, spell_name = "Aspect of the Viper",
            families = { "TBC" }, live = true, engine = true,
            source = "wowsims/tbc-new ui/specs/hunter/dps/apls/default.apl.json i=0 (the 'Mana management' group, row 2: 34074, cast when the Viper is inactive and the mana is under the Viper start) - wowsims/tbc-new sim/hunter/aspects.go:49-53 (34074, 'Aspect of the Viper'); the read exists (the aura scan on 34074 plus the mana fraction) and the engine has a swap arm (rule T0a)",
        },
        {
            action = "aspect_hawk", label = "Aspect of the Hawk",
            spell_id = 27044, spell_name = "Aspect of the Hawk",
            families = { "TBC" }, live = true, engine = true,
            source = "wowsims/tbc-new ui/specs/hunter/dps/apls/default.apl.json i=0 (the 'Mana management' group, row 3: 27044 r8, cast when the Hawk is inactive and the mana is back over the Viper stop) - wowsims/tbc-new sim/hunter/aspects.go:11-18 (27044, 'Aspect of the Hawk'); the read exists (the aura scan on 27044 - the TBC client resolves the spell by NAME - plus the mana fraction) and the engine has a swap arm (rule T0b)",
        },
    },
    WRATH = {
        {
            action = "kill_shot", label = "Kill Shot",
            spell_id = 61006, spell_name = "Kill Shot",
            families = { "WRATH" }, live = true, engine = true,
            source = "wowsims/wotlk ui/hunter/apls/mm.apl.json i=4 and ui/hunter/apls/sv.apl.json i=3 (61006: the execute) - wowsims/wotlk sim/hunter/kill_shot.go:12 (61006, 15 s CD) + ui/hunter/presets.ts + docs/research/rotations_wrath.md:9-16 (the execute at or under 20% health: always highest when available); the shipped id 53351 is the client's rank-1 (the guide slot's fallback), the APLs cast 61006",
        },
        {
            action = "chimera", label = "Chimera Shot",
            spell_id = 53209, spell_name = "Chimera Shot",
            families = { "WRATH" }, live = true, engine = true, specs = { MM = true },
            source = "wowsims/wotlk ui/hunter/apls/mm.apl.json i=7 (53209: the Serpent rollover + the 53353 proc) - wowsims/wotlk sim/hunter/chimera_shot.go (53209, 10 s CD)",
        },
        {
            action = "explosive", label = "Explosive Shot",
            spell_id = 60053, spell_name = "Explosive Shot",
            families = { "WRATH" }, live = true, engine = true, specs = { SV = true },
            source = "wowsims/wotlk ui/hunter/apls/sv.apl.json i=4 and i=5 (60053 r4, then 60052 r3 - the /castsequence pair) - wowsims/wotlk sim/hunter/explosive_shot.go:21,25 (60053 / 60052, 6 s CD; the SV priority outside the execute); the shipped id 53301 is the client's rank-1 (the guide slot's fallback), the SV APL casts 60053/60052",
        },
        {
            action = "aimed", label = "Aimed Shot",
            spell_id = 49050, spell_name = "Aimed Shot",
            families = { "WRATH" }, live = true, engine = true, input = "wrath_aimed",
            source = "wowsims/wotlk ui/hunter/apls/mm.apl.json i=8 and ui/hunter/apls/sv.apl.json i=9 (49050: the instant Aimed) - ui/hunter/presets.ts + docs/research/rotations_wrath.md:14 (Aimed Shot, instant in WotLK)",
        },
        {
            action = "arcane", label = "Arcane Shot",
            spell_id = 49045, spell_name = "Arcane Shot",
            families = { "WRATH" }, live = true, engine = true, specs = { MM = true },
            source = "wowsims/wotlk ui/hunter/apls/mm.apl.json i=10 (49045: the MM early-phase row - the APL hides it) - docs/research/rotations_wrath.md:15 (Arcane Shot, early phases; dropped once enough ArP) - the sim's Arcane shares the Explosive cooldown, so it is never prompted on SV",
        },
        {
            action = "steady", label = "Steady Shot",
            spell_id = 49052, spell_name = "Steady Shot",
            families = { "WRATH" }, live = true, engine = true,
            source = "wowsims/wotlk ui/hunter/apls/mm.apl.json i=11 and ui/hunter/apls/sv.apl.json i=11 (49052: the demoted filler) - wowsims/wotlk sim/hunter/steady_shot.go (49052; the demoted filler)",
        },
        {
            action = "aspect_viper", label = "Aspect of the Viper",
            spell_id = 34074, spell_name = "Aspect of the Viper",
            families = { "WRATH" }, live = true, engine = true,
            source = "wowsims/wotlk ui/hunter/apls/mm.apl.json i=1 and ui/hunter/apls/sv.apl.json i=1 (34074: the OOM swap - cast when the Viper is inactive and the mana is under 10%) - wowsims/wotlk sim/hunter/aspects.go:74-89 (34074, 'Aspect of the Viper'); the read exists (the aura scan on 34074 plus the mana fraction) and the engine has a swap arm (rule W0a)",
        },
        {
            action = "aspect_dragonhawk", label = "Aspect of the Dragonhawk",
            spell_id = 61847, spell_name = "Aspect of the Dragonhawk",
            families = { "WRATH" }, live = true, engine = true,
            source = "wowsims/wotlk ui/hunter/apls/mm.apl.json i=2 and ui/hunter/apls/sv.apl.json i=2 (61847: the aspect back - cast when the Dragonhawk is inactive and the mana is over 30%) - wowsims/wotlk sim/hunter/aspects.go:32-34 (61847, 'Aspect of the Dragonhawk'; the WotLK client renamed the Wild aspect); the read exists (the aura scan on 61847 plus the mana fraction) and the engine has a swap arm (rule W0b)",
        },
        {
            action = "silencing_shot", label = "Silencing Shot",
            spell_id = 34490, spell_name = "Silencing Shot",
            families = { "WRATH" }, live = true, engine = true, specs = { MM = true },
            source = "wowsims/wotlk ui/hunter/apls/mm.apl.json i=3 (34490: the interrupt) - the read exists (api.GetSpellCooldown on 34490) and the engine has an arm (rule W0c)",
        },
        {
            action = "serpent", label = "Serpent Sting",
            spell_id = 49001, spell_name = "Serpent Sting",
            families = { "WRATH" }, live = true, engine = true,
            source = "wowsims/wotlk ui/hunter/apls/mm.apl.json i=5 and ui/hunter/apls/sv.apl.json i=7 (49001: the dot upkeep) - wowsims/wotlk sim/hunter/serpent_sting.go:16 (49001); the read exists (read_serpent_active: the name-first target debuff scan) and the engine has a serpent arm (rules W1a and W3b)",
        },
        {
            action = "explosive_trap", label = "Explosive Trap",
            spell_id = 49067, spell_name = "Explosive Trap",
            families = { "WRATH" }, live = true, engine = true,
            source = "wowsims/wotlk ui/hunter/apls/mm.apl.json i=6 and ui/hunter/apls/sv.apl.json i=6 (49067: the trap - the APL's own condition is 'not dotIsActive(49067)', i.e. the trap's DOT on the target) - the read exists (api.GetSpellCooldown on 49067) and the engine has an arm (rules W1b and W3a). The arm gates on the spell's readiness: the trap's DOT carries its own client id, which is not sourced, so the spell's cooldown stands in for it",
        },
        {
            action = "multi", label = "Multi-Shot",
            spell_id = 49048, spell_name = "Multi-Shot",
            families = { "WRATH" }, live = true, engine = true, input = "utility_multi",
            source = "wowsims/wotlk ui/hunter/apls/mm.apl.json i=9 and ui/hunter/apls/sv.apl.json i=10 (49048: the WotLK Multi) - the read exists (the 49048 rank in multi_shot_ids plus api.GetSpellCooldown) and the engine has an arm (rule W4a); the WotLK Multi is an instant, so it takes no clip check (the WotLK arms never do)",
        },
        {
            action = "black_arrow", label = "Black Arrow",
            spell_id = 63672, spell_name = "Black Arrow",
            families = { "WRATH" }, live = true, engine = true, specs = { SV = true },
            source = "wowsims/wotlk ui/hunter/apls/sv.apl.json i=8 (63672: the SV damage row) - wowsims/wotlk sim/hunter/black_arrow.go:15 - the read exists (api.GetSpellCooldown on 63672) and the engine has an arm (rule W3c)",
        },
    },
    FOREVER = {
        {
            action = "hawk", label = "Summon Hawk",
            spell_name = "Summon Hawk",
            families = { "FOREVER" }, live = true, engine = true,
            source = "wowsims/forever ui/specs/hunter/dps/apls/default.apl.json i=11 (1293527: the upkeep - cast Summon Hawk if less than two are active) - wowsims/forever sim/hunter/summon_hawk.go + the Forever spell data (SummonHawk 1293241/1293525/1293526/1293527) - the ids are SIM-CONFIRMED (1293241/1293525/1293526/1293527) and CLIENT-UNCONFIRMED, so the slot ships spell-less",
        },
        {
            action = "sniper", label = "Sniper Shot",
            spell_name = "Sniper Shot",
            families = { "FOREVER" }, live = true, engine = true,
            source = "wowsims/forever sim/hunter/sniper_shot.go (the 4 s MM cast; the buff extends the Auto range) - the ids are SIM-CONFIRMED (1310687/1310785/1310786) and CLIENT-UNCONFIRMED; the Forever APL has no Sniper row (the guide's MM tell is this row's home)",
        },
        {
            action = "raptor_strike", label = "Raptor Strike",
            spell_id = 14266, spell_name = "Raptor Strike",
            families = { "FOREVER" }, live = true, engine = true,
            source = "wowsims/forever ui/specs/hunter/dps/apls/default.apl.json i=1 (14266: the melee weave) - the read exists (the 14266 rank in raptor_strike_ids plus api.GetSpellCooldown) and the engine has a melee-weave arm (rule F0a; the weave band must read melee)",
        },
        {
            action = "hunters_mark", label = "Hunter's Mark",
            spell_id = 14325, spell_name = "Hunter's Mark",
            families = { "FOREVER" }, live = true, engine = true,
            source = "wowsims/forever ui/specs/hunter/dps/apls/default.apl.json i=2 (14325: the mark - cast when it is not up) - the APL's PRE-PULL copy of the same spell (prepullActions i=0, -22 s) stays in the prepull table; the read exists (api.scan_unit_aura on the target for 14325) and the engine has a mark arm (rule F0b)",
        },
        {
            action = "mongoose_bite", label = "Mongoose Bite",
            spell_id = 14271, spell_name = "Mongoose Bite",
            families = { "FOREVER" }, live = true, engine = true,
            source = "wowsims/forever ui/specs/hunter/dps/apls/default.apl.json i=3 (14271: the melee hit) - the read exists (api.GetSpellCooldown on 14271) and the engine has a melee-weave arm (rule F0c)",
        },
        {
            action = "immolation_trap", label = "Immolation Trap",
            spell_id = 14305, spell_name = "Immolation Trap",
            families = { "FOREVER" }, live = true, engine = true,
            source = "wowsims/forever ui/specs/hunter/dps/apls/default.apl.json i=5 (14305: the trap - the APL's own condition is 'unitDistance(Self) <= 5.00', i.e. melee range) - the read exists (api.GetSpellCooldown on 14305) and the engine has an arm (rule F0d; the weave band must read melee)",
        },
        {
            action = "wing_clip", label = "Wing Clip",
            spell_id = 14268, spell_name = "Wing Clip",
            families = { "FOREVER" }, live = true, engine = true,
            source = "wowsims/forever ui/specs/hunter/dps/apls/default.apl.json i=6 (14268: the melee debuff) - the read exists (api.GetSpellCooldown on 14268) and the engine has a melee-weave arm (rule F0e)",
        },
        {
            action = "serpent", label = "Serpent Sting",
            spell_id = 25295, spell_name = "Serpent Sting",
            families = { "FOREVER" }, live = true, engine = true,
            source = "wowsims/forever ui/specs/hunter/dps/apls/default.apl.json i=8 (25295: the dot upkeep) - the read exists (read_serpent_active: the name-first target debuff scan) and the engine has a serpent arm (rule F0f)",
        },
        {
            action = "arcane", label = "Arcane Shot",
            spell_id = 14287, spell_name = "Arcane Shot",
            families = { "FOREVER" }, live = true, engine = true,
            source = "wowsims/forever ui/specs/hunter/dps/apls/default.apl.json i=12 (14287: the filler behind the upkeep) - the read exists (the 14287 rank in arcane_shot_ids plus api.GetSpellCooldown) and the engine has a filler arm (rule F3)",
        },
        {
            action = "multi", label = "Multi-Shot",
            spell_id = 2643, spell_name = "Multi-Shot",
            families = { "FOREVER" }, live = true, engine = true, input = "utility_multi",
            source = "wowsims/forever ui/specs/hunter/dps/apls/default.apl.json i=13 (2643: the filler behind the upkeep) - the read exists (the client's Multi rank in multi_shot_ids plus api.GetSpellCooldown) and the engine has a filler arm (rule F4)",
        },
        {
            action = "aimed", label = "Aimed Shot",
            spell_id = 20904, spell_name = "Aimed Shot",
            families = { "FOREVER" }, live = false, engine = false,
            needs = "api.GetSpellCooldown on the Aimed Shot rank (the module's aimed_shot_ids table holds it), with the gather's aimed block ungated for the Forever family (it runs on the Era set only)",
            source = "wowsims/forever ui/specs/hunter/dps/apls/default.apl.json i=14 (20904: the filler behind the Multi) - the guide's Forever set has no Aimed slot (the beta rotations are sim-unconfirmed), so the row stays a spine row",
        },
    },
}

-- The rotation table the shared engine reads for the running client: the family's own
-- priority list, re-pointed at post_init when the SoD rune swaps the Era set for the
-- SoD one (the same detector the guide's slot swap uses - api.is_spell_known on the
-- SoD-only Chimera rune 409433, because SoD shares the ERA family token and the
-- family alone never decides). A client with no sourced rotation (Cata, Mists,
-- Retail) gets an empty table: the scenario then decides nothing (nil), never a
-- guess.
ST.HUNTER.practice_rotation = ST.HUNTER.PRACTICE_ROTATIONS[st.family] or {}

-- The opener drill's data: the per-family pre-pull sequence (the sim APLs'
-- prepullActions and the opening priority entries), each entry citing its source.
-- `at` is the offset relative to the pull in seconds (negative = before the pull):
-- the drill's lateness is measured against it.
ST.HUNTER.PRACTICE_PREPULLS = {
    TBC = {
        {
            action = "aspect_hawk", label = "Aspect of the Hawk", spell = 27044, at = -20,
            source = "wowsims/tbc-new ui/specs/hunter/dps/apls/default.apl.json (prepullActions: Aspect of the Hawk 27044 r8 at -20s)",
        },
        {
            action = "steady", label = "Steady Shot", spell = 34120, at = 0.5,
            source = "wowsims/tbc-new default.apl.json (the priority entry 'currentTime <= 0.5s' casts Steady Shot 34120 r1 inside the first half second of the pull)",
        },
    },
    SOD = {
        {
            action = "aspect_falcon", label = "Aspect of the Falcon", spell = 469145, at = -5,
            source = "wowsims/sod ui/hunter/apls/p7_weave.apl.json (prepullActions: Aspect of the Falcon 469145 at -5s)",
        },
        {
            action = "aimed", label = "Aimed Shot", spell = 20904, at = -3.5,
            source = "wowsims/sod ui/hunter/apls/p7_weave.apl.json (prepullActions: Aimed Shot 20904 r6 at -3.5s)",
        },
        {
            action = "blood_fury", label = "Blood Fury", spell = 20572, at = -1.95,
            source = "wowsims/sod ui/hunter/apls/p7_weave.apl.json (prepullActions: Blood Fury 20572 at -1.95s)",
        },
        {
            action = "rapid_fire", label = "Rapid Fire", spell = 3045, at = -0.45,
            source = "wowsims/sod ui/hunter/apls/p7_weave.apl.json (prepullActions: Rapid Fire 3045 at -0.45s)",
        },
        {
            action = "serpent", label = "Serpent Sting", spell = 25295, at = -0.45,
            source = "wowsims/sod ui/hunter/apls/p7_weave.apl.json (prepullActions: Serpent Sting 25295 r9 at -0.45s)",
        },
    },
    FOREVER = {
        {
            action = "hunters_mark", label = "Hunter's Mark", spell = 14325, at = -22,
            source = "wowsims/forever ui/specs/hunter/dps/apls/default.apl.json (prepullActions: Hunter's Mark 14325 at -22s)",
        },
        {
            action = "aspect_hawk", label = "Aspect of the Hawk", spell = 25296, at = -20,
            source = "wowsims/forever default.apl.json (prepullActions: Aspect of the Hawk 25296 at -20s)",
        },
    },
}

-- The guide input each rotation action writes (the frozen input names from
-- hunter_guide.lua's header): the knowledge flag and the cooldown reading.
-- (The reason table, the pop list and the band helpers are declared here and
-- filled in below, so the helpers below can call them.)
local PRACTICE_ACTION_REASONS
local PRACTICE_TBC_POPS
local PRACTICE_TBC_POP_KEYS
local practice_pull_time
local practice_band
local practice_session_band
local practice_lateness
local practice_clip_margin
local PRACTICE_ACTION_INPUTS = {
    kill_shot = { known = "killshot_known", cd = "killshot_remaining_cd" },
    chimera = { known = "chimera_known", cd = "chimera_remaining_cd" },
    explosive = { known = "explosive_known", cd = "explosive_remaining_cd" },
    arcane = { known = "arcane_known", cd = "arcane_remaining_cd" },
    aimed = { known = "aimed_known", cd = "aimed_remaining_cd" },
    wrath_aimed = { known = "wrath_aimed_known", cd = "wrath_aimed_remaining_cd" },
    multi = { known = "multi_known", cd = "multi_remaining_cd" },
    -- The APL utility layer's Multi-Shot (the WotLK and Forever rank): the
    -- weave's own multi entry above stays the Era and TBC cast shot.
    utility_multi = { known = "utility_multi_known", cd = "utility_multi_remaining_cd" },
    steady = { known = "steady_known", cd = "steady_remaining_cd" },
    kill_command = { known = "kc_known", cd = "kc_remaining_cd" },
    bestial_wrath = { known = "bw_known", cd = "bw_remaining_cd" },
    rapid_fire = { known = "rf_known", cd = "rf_remaining_cd" },
    hawk = { known = "hawk_known", cd = "hawk_remaining_cd" },
    sniper = { known = "sniper_known", cd = "sniper_remaining_cd" },
    -- The APL UTILITY layer's lines. A cooldown line carries its cooldown; an
    -- aura line carries the buff's three-state read instead (the ctx names it:
    -- ctx.serpent_active, ctx.aspect_viper_active, ...). An aura state the ctx
    -- does not carry stays unknown, and an unknown buff never prompts.
    serpent = { known = "serpent_known", active = "serpent_active" },
    raptor_strike = { known = "raptor_strike_known", cd = "raptor_strike_remaining_cd" },
    wyvern_strike = { known = "wyvern_strike_known", cd = "wyvern_strike_remaining_cd" },
    wing_clip = { known = "wing_clip_known", cd = "wing_clip_remaining_cd" },
    mongoose_bite = { known = "mongoose_bite_known", cd = "mongoose_bite_remaining_cd" },
    immolation_trap = { known = "immolation_trap_known", cd = "immolation_trap_remaining_cd" },
    hunters_mark = { known = "hunters_mark_known", active = "hunters_mark_active" },
    silencing_shot = { known = "silencing_shot_known", cd = "silencing_shot_remaining_cd" },
    explosive_trap = { known = "explosive_trap_known", cd = "explosive_trap_remaining_cd" },
    black_arrow = { known = "black_arrow_known", cd = "black_arrow_remaining_cd" },
    aspect_viper = { known = "aspect_viper_known", active = "aspect_viper_active" },
    aspect_hawk = { known = "aspect_hawk_known", active = "aspect_hawk_active" },
    aspect_falcon = { known = "aspect_falcon_known", active = "aspect_falcon_active" },
    aspect_dragonhawk = { known = "aspect_dragonhawk_known", active = "aspect_dragonhawk_active" },
}

-- The APL UTILITY layer's aura feeds (the engine's own input names): the
-- three-state buff reads the live ctx carries into the scenario, so the
-- scenario can ask for a line whose buff it could actually read.
local UTILITY_ACTIVE_INPUTS = {
    "serpent_active", "aspect_viper_active", "aspect_hawk_active",
    "aspect_falcon_active", "aspect_dragonhawk_active", "hunters_mark_active",
}

-- The cast shots: the per-client cast-time key, the guide's own default constant and
-- the live-cast input the engine's rule 1 reads. The key is the guide's INPUT
-- family, so the Wrath Aimed (instant on WotLK) is not a cast shot.
local PRACTICE_CAST_SHOTS = {
    steady = { key = "steady", input = "steady_cast_seconds",
        live = "steady_remaining", constant = "STEADY_CAST_SECONDS_DEFAULT" },
    multi = { key = "multi", input = "multi_cast_seconds",
        live = "multi_remaining", constant = "MULTI_CAST_SECONDS_DEFAULT" },
    aimed = { key = "aimed", input = "aimed_cast_seconds",
        live = "aimed_remaining", constant = "AIMED_CAST_SECONDS_DEFAULT" },
    sniper = { key = "sniper", input = "sniper_cast_seconds",
        live = "sniper_remaining", constant = "SNIPER_CAST_SECONDS_DEFAULT" },
}

-- The scenario's simulated ranged cycle: the Auto Shot cycle the run lives on. The
-- shipped practice default (3.5 s, practice.lua:232 effective_speed) is the in-tree
-- value; the hunter's own breakpoint is the ~3.0 s the clip checks fall out of.
ST.HUNTER.PRACTICE_CYCLE_SECONDS = 3.5
-- The GCD the pop drill's lateness bands use (the shipped practice default,
-- practice.lua:233 effective_gcd).
ST.HUNTER.PRACTICE_GCD_SECONDS = 1.5
-- The clip margin bands (the shipped weave bands, practice.lua:2405-2411
-- H.WEAVE_MARGIN_BANDS): a tight start is the skilled one, a clip is the worst.
ST.HUNTER.PRACTICE_MARGIN_BANDS = {
    { max = 0.02, grade = "S" },
    { max = 0.05, grade = "A" },
    { max = 0.10, grade = "B" },
    { max = 0.20, grade = "C" },
    { grade = "D" },
}
-- The shot-order drill's session bands (bench/class_features_drills_2026-10-19.md
-- §2.3 D-H1, [DESIGN]): the mis-pick count over a ten-decision sample.
ST.HUNTER.PRACTICE_ORDER_BANDS = {
    { max = 0, grade = "S" },
    { max = 1, grade = "A" },
    { max = 2, grade = "B" },
    { max = 3, grade = "C" },
    { max = 5, grade = "D" },
    { grade = "F" },
}
-- The pop drill's lateness bands ([DESIGN], the audit's D-H3): the pop came off
-- cooldown and the press landed later than that, in GCDs.
ST.HUNTER.PRACTICE_POP_LATE_BANDS = {
    { max = 1, grade = "A" },
    { max = 2, grade = "B" },
    { max = 3, grade = "C" },
    { grade = "D" },
}
-- The opener drill's lateness bands ([DESIGN], the audit's D-H4): the opener's own
-- offset is the on-time mark, and everything after it is late.
ST.HUNTER.PRACTICE_PREPULL_LATE_BANDS = {
    { max = 1, grade = "A" },
    { max = 3, grade = "B" },
    { max = 5, grade = "C" },
    { grade = "D" },
}
-- The fallback window after the LAST opener of a sequence ([DESIGN]): the sim's own
-- spacing gives the gaps between the openers, but nothing bounds the last one.
ST.HUNTER.PRACTICE_PREPULL_WINDOW_SECONDS = 5

-- The scenario's simulated cast state (module-scoped): the action the caller reported
-- last and the time it stops casting. A cast shot occupies the player for its cast
-- time (the same clock the clip maths uses), so the decision right after a press rides
-- the cast (the guide's rule 1) instead of asking for a second shot.
local scenario_last_action = nil
local scenario_cast_action = nil
local scenario_cast_until = nil

-- The rotation slice the engine may ask for (the panel's buttons, in the rotation's
-- own order): the named family's ENGINE-FACING entries, or the running client's own
-- slice. A row the engine still has no arm for (engine = false) is never returned:
-- it must not reach the engine's inputs, and the panel would have a button the
-- rotation can never ask for. Since the APL UTILITY lane (2026-10-20) that is
-- ONE row (the Forever Aimed Shot); every other row is engine-facing, so the
-- panel's vocabulary is the family's WHOLE spine - and the practice strip grows
-- with the button lines (practice_ui.lua), so no rotation row is unreachable.
function ST.HUNTER.practice_rotation_for(family)
    if type(family) ~= "string" or family == "" then
        family = ST.HUNTER.practice_rotation_family()
    end
    local rotation = ST.HUNTER.PRACTICE_ROTATIONS[family]
    if type(rotation) ~= "table" then
        return {}
    end
    local out = {}
    for i = 1, #rotation do
        local entry = rotation[i]
        if type(entry) == "table" and entry.engine ~= false then
            out[#out + 1] = entry
        end
    end
    return out
end

-- The rotation family the running client uses (the sim the table mirrors for it):
-- "SOD" on the ERA token with the SoD rune basis, else compat.lua's family.
function ST.HUNTER.practice_rotation_family()
    if st.family == "ERA" and ST.HUNTER.practice_rotation == ST.HUNTER.PRACTICE_ROTATIONS.SOD then
        return "SOD"
    end
    return st.family
end

-- The family a scenario call grades: the ctx may name one (the shared engine's
-- ctx.family, with ctx.resources.family as the sibling lanes' alias) so an offline
-- run can grade another family's rotation. It is the ENGINE's family token (the
-- engine's family gates read st.family); nil means the running client.
local function practice_ctx_family(ctx)
    if type(ctx) ~= "table" then
        return nil
    end
    local family = ctx.family
    if type(family) ~= "string" or family == "" then
        local resources = ctx.resources
        if type(resources) == "table" then
            family = resources.family
        end
    end
    if type(family) == "string" and family ~= "" then
        return family
    end
    return nil
end

-- The rotation slice a call grades: the running client's own table, unless the ctx
-- names another family (an offline run that simulates a different client) or the
-- caller names the rotation family outright (ctx.rotation_family).
local function practice_rotation_slice(ctx, running_family)
    local named = nil
    if type(ctx) == "table" then
        named = ctx.rotation_family
        if type(named) ~= "string" or named == "" then
            local resources = ctx.resources
            if type(resources) == "table" then
                named = resources.rotation_family
            end
        end
    end
    if type(named) == "string" and named ~= "" then
        return ST.HUNTER.PRACTICE_ROTATIONS[named]
    end
    local family = practice_ctx_family(ctx)
    if type(family) == "string" and family ~= "" and family ~= running_family then
        return ST.HUNTER.PRACTICE_ROTATIONS[family]
    end
    return ST.HUNTER.practice_rotation
end

-- The rotation entry of an action key (the label and the source the reason quotes).
-- A spine row (engine = false) is skipped: the engine never emits one, so the
-- lookup must never answer with a spine row's label.
local function practice_rotation_entry(action)
    local rotation = ST.HUNTER.practice_rotation
    if type(rotation) ~= "table" then
        return nil
    end
    for i = 1, #rotation do
        if rotation[i].action == action and rotation[i].engine ~= false then
            return rotation[i]
        end
    end
    return nil
end

-- The cast input of an action: the guide's input family (the rotation entries name
-- it; "wrath_aimed" is instant on WotLK, so it is not a cast shot). A spine row
-- (engine = false) has no input family: the engine never plays one.
local function practice_cast_input(action)
    local rotation = ST.HUNTER.practice_rotation
    if type(rotation) == "table" then
        for i = 1, #rotation do
            if rotation[i].action == action and rotation[i].engine ~= false then
                return rotation[i].input or action
            end
        end
    end
    return action
end

-- The cast time of a shot in seconds. The scenario is a simulation, so the client's
-- live cast time is never read: the per-client fallback table wins
-- (ST.HUNTER.CAST_TIME_FALLBACK) and the engine's own default second. Nil for the
-- instant shots - they occupy no cast time.
local function practice_cast_seconds(input)
    local shot = PRACTICE_CAST_SHOTS[input]
    if not shot then
        return nil
    end
    local fallback = ST.HUNTER.cast_time_fallback(shot.key)
    if type(fallback) == "number" then
        return fallback
    end
    local engine = st.hunter_guide
    if not engine then
        return nil
    end
    local value = engine[shot.constant]
    if type(value) ~= "number" then
        return nil
    end
    return value
end

-- The grace a shot's cast runs under (the hunter_window constants: the steady-shot
-- grace for everything except Multi-Shot, whose hidden window delays the Auto Shot on
-- overlap so it carries no grace at all).
local function practice_cast_grace(input)
    local window = st.hunter_window
    if input == "multi" then
        if window and type(window.MULTI_SHOT_GRACE) == "number" then
            return window.MULTI_SHOT_GRACE
        end
        local engine = st.hunter_guide
        return engine and engine.MULTI_GRACE_DEFAULT or 0
    end
    if window and type(window.STEADY_SHOT_GRACE) == "number" then
        return window.STEADY_SHOT_GRACE
    end
    local engine = st.hunter_guide
    return engine and engine.STEADY_GRACE_DEFAULT or 0.5
end

-- The cooldown a rotation action reads out of the caller's cooldown map. The map's
-- keys are the ENGINE's own: the gathered cooldown input without its
-- "_remaining_cd" suffix (practice_ui's scenario_context builds it that way), so
-- "kc_remaining_cd" answers as "kc" and "killshot_remaining_cd" as "killshot".
-- The action key is accepted as an alias. A key the map does not mention reads off
-- cooldown (a fresh scenario has every cooldown ready); a malformed reading reads
-- the same way (never a guess).
local function practice_cooldown(cooldowns, action, cd_key)
    if type(cooldowns) ~= "table" then
        return nil
    end
    local value = cooldowns[cd_key]
    if value == nil and cd_key ~= action then
        value = cooldowns[action]
    end
    if type(value) == "number" then
        if value ~= value or value < 0 then
            return nil
        end
        return value
    end
    if type(value) == "table" then
        local remaining = value.remaining
        if type(remaining) == "number" and remaining == remaining and remaining >= 0 then
            return remaining
        end
    end
    return nil
end

-- The action the player picked: the ctx's own field, with the aliases the shared
-- engine may use. The drill-list PRESS rides in ctx.pick (the F1 fix writes the press
-- into every alias), and on the scenario path this class's own ctx publishes the live
-- cast as ctx.pick. Nil when nothing was picked (never a guess).
local function practice_pressed(ctx)
    if type(ctx) ~= "table" then
        return nil
    end
    local pressed = ctx.pick
    if pressed == nil then
        pressed = ctx.pressed
    end
    if pressed == nil then
        pressed = ctx.action
    end
    if pressed == nil then
        pressed = ctx.last_action
    end
    if type(pressed) ~= "string" or pressed == "" then
        return nil
    end
    return pressed
end

-- The shot the rotation wants for the clip drill: the highest-priority CAST shot of
-- the running rotation that is off cooldown. The engine withholds a shot that does
-- not fit, so the drill reads the rotation itself - that is what makes the clip
-- band reachable (a moment that is too late to start the shot).
local function practice_due_cast_shot(ctx, running_family)
    local rotation = practice_rotation_slice(ctx, running_family)
    if type(rotation) ~= "table" then
        return nil
    end
    for i = 1, #rotation do
        local entry = rotation[i]
        local input = entry.input or entry.action
        if entry.engine ~= false and PRACTICE_CAST_SHOTS[input] then
            local spec = PRACTICE_ACTION_INPUTS[input]
            local cd_key = entry.action
            if spec then
                cd_key = spec.cd:gsub("_remaining_cd$", "")
            end
            local remaining = practice_cooldown(ctx.cooldowns, entry.action, cd_key)
            if remaining == nil or remaining <= 0 then
                return entry.action, input
            end
        end
    end
    return nil
end

-- The opener drill's synthetic pull clock (the audit's D-H4: "the hunter has no such
-- input yet - a new synthetic pull clock belongs to the drill, not to the guide").
-- The drill owns it: the first press opens the countdown at the family's first
-- opener and the clock then runs on the real one, so the player's own press timing
-- is what the grade reads. The ctx's own pull clock wins when it carries one (an
-- offline run that drives the drill directly).
local prepull_clock = nil

local function practice_prepull_time(ctx, now)
    local pull_time = practice_pull_time(ctx)
    if pull_time ~= nil then
        return pull_time
    end
    if type(now) ~= "number" or now ~= now then
        return nil
    end
    local prepulls = ST.HUNTER.PRACTICE_PREPULLS[ST.HUNTER.practice_rotation_family()]
    if not prepulls or #prepulls == 0 then
        return nil
    end
    if prepull_clock == nil
        or (type(prepull_clock.last_at) == "number" and now < prepull_clock.last_at) then
        local first = prepulls[1].at
        if type(first) ~= "number" then
            return nil
        end
        prepull_clock = { pull_at = now - first }
    end
    prepull_clock.last_at = now
    return now - prepull_clock.pull_at
end

-- The seconds until the pull (negative after it). Nil when the caller carries no pull
-- clock (never a guess).
practice_pull_time = function(ctx)
    if type(ctx) ~= "table" then
        return nil
    end
    local to_pull = ctx.time_to_pull
    if to_pull == nil then
        to_pull = ctx.pull_in
    end
    if to_pull == nil then
        to_pull = ctx.time_to_pull_seconds
    end
    if type(to_pull) == "number" and to_pull == to_pull then
        return -to_pull
    end
    local pull_at = ctx.pull_at
    local now = ctx.now
    if type(pull_at) == "number" and pull_at == pull_at
        and type(now) == "number" and now == now then
        return now - pull_at
    end
    return nil
end

-- The harness drill this class practices (practice.lua registry): the key when the
-- module is loaded and carries the spec, nil otherwise (unknown-hides, the same
-- shape as the druid and shaman seams).
function ST.HUNTER.practice_scenario_key()
    local pr = st.practice
    if pr and pr.harness and pr.harness.get_scenario
        and pr.harness.get_scenario(ST.HUNTER.PRACTICE_SCENARIO_KEY) then
        return ST.HUNTER.PRACTICE_SCENARIO_KEY
    end
    return nil
end

-- The scenario decision: the guide engine's own verdict for the caller's state.
-- Returns the engine's out table, or nil when the class cannot decide (no sourced
-- rotation for this client, no engine, an unreadable clock).
local function practice_decision_inner(ctx, options, running_family)
    options = options or {}
    if type(ctx) ~= "table" then
        return nil
    end
    local now = ctx.now
    if type(now) ~= "number" or now ~= now then
        return nil
    end
    local engine = st.hunter_guide
    if not (engine and engine.evaluate) then
        return nil
    end
    local rotation = practice_rotation_slice(ctx, running_family)
    if type(rotation) ~= "table" then
        return nil
    end
    local wanted_spec = ctx.spec
    if type(wanted_spec) == "string" and wanted_spec ~= "" then
        local filtered = {}
        for i = 1, #rotation do
            local entry = rotation[i]
            local entry_specs = entry.specs
            if entry_specs == nil or entry_specs[wanted_spec] == true then
                filtered[#filtered + 1] = entry
            end
        end
        rotation = filtered
    end
    if #rotation == 0 then
        return nil
    end

    -- A press the caller reported starts a cast: the shot occupies the player for its
    -- cast time, so the next decision rides it (the guide's rule 1). The drills ask
    -- for the clean decision (options.ignore_cast), because the decision they grade
    -- is the one that came BEFORE the press.
    local pressed = ctx.last_action
    if pressed ~= scenario_last_action then
        scenario_last_action = pressed
        scenario_cast_action = nil
        scenario_cast_until = nil
        local cast_seconds = practice_cast_seconds(practice_cast_input(pressed))
        if cast_seconds ~= nil then
            scenario_cast_action = pressed
            scenario_cast_until = now + cast_seconds
        end
    end

    local inputs = {}
    local cycle = ctx.cycle_duration
    if cycle == nil then
        cycle = ctx.synced_duration
    end
    if type(cycle) ~= "number" or cycle ~= cycle or cycle <= 0 then
        cycle = ST.HUNTER.PRACTICE_CYCLE_SECONDS
    end
    local latency = ctx.latency
    if type(latency) ~= "number" or latency ~= latency or latency < 0 then
        latency = 0
    end

    -- The simulated cycle: the shot lands on the next cycle boundary, so the time to
    -- the next shot is a pure function of the clock (no hidden state to drift).
    local cycle_start = now - (now % cycle)
    inputs.now = now
    inputs.swing_start = cycle_start
    inputs.swing_speed = cycle
    inputs.synced_duration = cycle
    inputs.latency = latency

    -- The hidden Auto-Shot window (the same maths the cast bar tints with), so the
    -- window HOLD behaves exactly as it does live.
    local window = st.hunter_window
    if window and window.hidden_window and window.cast_window then
        local start_bound, end_bound = window.hidden_window(
            cycle_start, cycle, window.cast_window(latency))
        if type(start_bound) == "number" and type(end_bound) == "number" then
            inputs.hidden_window_start = start_bound
            inputs.hidden_window_duration = end_bound - start_bound
        end
    end

    -- The knowledge flags and the cooldown readings: every ENGINE-FACING action of
    -- the running rotation is known, and its cooldown comes from the caller's map
    -- (the engine's own key: the gathered cooldown input without its
    -- "_remaining_cd" suffix). A spine row (engine = false) never reaches the
    -- engine: it has no arm there, so feeding its inputs would change the verdict.
    -- An AURA line (the Serpent Sting, the aspect swaps, Hunter's Mark) carries
    -- its buff state instead of a cooldown: the ctx names it (ctx.serpent_active,
    -- ctx.aspect_viper_active, ...) and a state the ctx does not carry stays
    -- unknown - an unknown buff never prompts (unknown hides).
    for i = 1, #rotation do
        local entry = rotation[i]
        if entry.engine ~= false then
            local input = entry.input or entry.action
            local action_spec = PRACTICE_ACTION_INPUTS[input]
            if action_spec then
                inputs[action_spec.known] = true
                if action_spec.cd then
                    local cd_key = action_spec.cd:gsub("_remaining_cd$", "")
                    inputs[action_spec.cd] = practice_cooldown(ctx.cooldowns, entry.action, cd_key)
                end
                if action_spec.active then
                    inputs[action_spec.active] = ctx[action_spec.active]
                end
            end
            local shot = PRACTICE_CAST_SHOTS[input]
            if shot then
                local cast_seconds = practice_cast_seconds(input)
                if cast_seconds ~= nil then
                    inputs[shot.input] = cast_seconds
                end
            end
        end
    end

    -- The weave band (the melee rows read it: the APL casts them in the melee
    -- weave) and the mana fraction (the aspect swaps read it). Both come from
    -- the caller: an unknown band or an unknown mana never prompts.
    inputs.weave_band = ctx.weave_band
    if ctx.mana_frac ~= nil then
        inputs.mana_frac = ctx.mana_frac
    elseif type(ctx.resources) == "table" and ctx.resources.mana ~= nil then
        inputs.mana_frac = ctx.resources.mana
    end

    -- A Readiness cast resets the whole kit (wowsims/wotlk talents.go
    -- registerReadinessCD), so the reset cooldowns read off cooldown while the
    -- caller reports the window.
    if ctx.readiness_active == true then
        for action in pairs(ST.HUNTER.READINESS_RESET_COOLDOWNS) do
            local action_spec = PRACTICE_ACTION_INPUTS[action]
            if action_spec then
                inputs[action_spec.cd] = 0
            end
        end
    end

    -- The execute read: unknown health never prompts (the engine's own rule).
    local hp = ctx.target_hp_frac
    if type(hp) == "number" and hp == hp then
        inputs.target_hp_frac = hp
    end

    -- A cast in progress rides the decision (the guide's rule 1).
    if not options.ignore_cast and scenario_cast_action ~= nil
        and type(scenario_cast_until) == "number" and now < scenario_cast_until then
        local shot = PRACTICE_CAST_SHOTS[practice_cast_input(scenario_cast_action)]
        if shot then
            inputs[shot.live] = scenario_cast_until - now
        end
    end

    local out = {}
    engine.evaluate(inputs, out)
    return out
end

-- The decision under the caller's family. The engine's family gates read st.family
-- live, and so does the per-client cast-time fallback table, so a simulated family
-- runs the engine under that family for the call (the shaman seam's shape). The
-- restore is why the call is guarded: a throwing engine would otherwise leave
-- st.family changed, and a throw grades UNKNOWN here - the same rule the shared
-- engine applies around this call (practice.lua's contract: a step that cannot
-- answer is never a wrong action).
local function practice_decision(ctx, options)
    local running_family = st.family
    local family = practice_ctx_family(ctx)
    if type(family) ~= "string" or family == "" or family == running_family then
        return practice_decision_inner(ctx, options, running_family)
    end
    local saved = st.family
    st.family = family
    local ok, out = pcall(practice_decision_inner, ctx, options, running_family)
    st.family = saved
    if not ok then
        return nil
    end
    return out
end

-- The class's own scenario ctx (the shared engine's extension point: the engine
-- calls it when the class publishes one, and injects now/last_action on top). The
-- hunter's live state, in the engine's vocabulary:
--   cooldowns   the gathered cooldown readings, keyed the engine's way (the input
--               name without its "_remaining_cd" suffix: "kc", "bw", "killshot", ...)
--   resources   the mana fraction (a live read; the guide reads no mana input
--               today, so it only reaches the report) and the engine's family token
--   cycle       the live Auto Shot cycle (the ranged clock the hunter runs on)
--   latency     the compensated world latency (the same basis the clip maths uses)
--   target_hp_frac  the execute read (nil when the client cannot answer: an
--               unknown health never prompts the Kill Shot)
-- The gather runs into a reused table (no per-tick allocation) and every read is
-- nil-safe: an unreadable state leaves the ctx's field nil (unknown hides).
ST.HUNTER.practice_inputs = {}

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

function ST.HUNTER.practice_context(self, now, last_action)
    local ctx = {
        now = now,
        last_action = last_action,
        resources = nil,
        cooldowns = nil,
    }
    -- The pull moment travels with the ctx: the prepull drill reads it from here.
    practice_apply_pull_clock(ctx, now)
    local gathered = ST.HUNTER.gather_guide_inputs(self, ST.HUNTER.practice_inputs)
    if type(gathered) ~= "table" then
        return ctx
    end
    local cooldowns = {}
    for key, value in pairs(gathered) do
        if type(key) == "string" and type(value) == "number" then
            local base = key:match("^(.-)_remaining_cd$")
            if base and base ~= "" then
                cooldowns[base] = value
            end
        end
    end
    if next(cooldowns) ~= nil then
        ctx.cooldowns = cooldowns
    end
    local resources = { family = st.family }
    local mana = ST.HUNTER.get_mana_fraction()
    if type(mana) == "number" then
        resources.mana = mana
    end
    ctx.resources = resources
    local cycle = gathered.synced_duration or gathered.swing_speed
    if type(cycle) == "number" and cycle == cycle and cycle > 0 then
        ctx.cycle_duration = cycle
    end
    if type(gathered.latency) == "number" then
        ctx.latency = gathered.latency
    end
    if type(gathered.target_hp_frac) == "number" then
        ctx.target_hp_frac = gathered.target_hp_frac
    end
    -- The APL utility layer's state: the buff reads (the three-state aura feeds)
    -- and the weave band. They ride in the ctx under the engine's own input
    -- names, so the scenario builder can hand them to the engine unchanged. A
    -- read that could not be trusted stays nil (unknown hides): the scenario
    -- never asks for a line whose buff it could not read.
    for i = 1, #UTILITY_ACTIVE_INPUTS do
        local key = UTILITY_ACTIVE_INPUTS[i]
        if gathered[key] ~= nil then
            ctx[key] = gathered[key]
        end
    end
    if gathered.weave_band ~= nil then
        ctx.weave_band = gathered.weave_band
    end
    if type(gathered.mana_frac) == "number" then
        ctx.mana_frac = gathered.mana_frac
    end
    -- The pick: the shot that is casting right now - the CLASS's own pick. The
    -- scenario path grades the shot that is actually in flight. On the drill-list
    -- path the player's PRESS is the pick and it wins over this value: the
    -- drill-list press is written into every alias the graders read (ctx.pick among
    -- them - the F1 fix in practice_ui.lua's drill_list_grade), and this class's
    -- reader reads ctx.pick FIRST. So a press grades the press, even while a shot
    -- is in flight; this live cast survives only a press-LESS drill press.
    if type(gathered.steady_remaining) == "number" then
        ctx.pick = "steady"
    elseif type(gathered.multi_remaining) == "number" then
        ctx.pick = "multi"
    elseif type(gathered.aimed_remaining) == "number" then
        ctx.pick = "aimed"
    elseif type(gathered.sniper_remaining) == "number" then
        ctx.pick = "sniper"
    end
    return ctx
end

-- The scenario step: the action the rotation wants at this decision, or nil when it
-- cannot decide (a state it cannot read - the shared engine grades "unknown" then).
-- A guide HOLD is a DECISION, not an unknown (the operator ruling HU-8, hands-up
-- 2026-10-19: HOLD-IS-A-DECISION): the RIDE window (a cast is in flight) and the
-- HOLD window (out of range, or inside the hidden Auto-Shot window) state the hold
-- explicitly, so the engine can tell a hold (casting then is an illegal cast) from
-- an unknown (no attempt at all). The reason is the guide's own caption.
function ST.HUNTER.practice_scenario_step(self, ctx)
    local out = practice_decision(ctx)
    if not out then
        return nil
    end
    local action = out.action
    if type(action) ~= "string" then
        if out.hold == true then
            local reason = out.hold_text
            if type(reason) ~= "string" or reason == "" then
                reason = "HOLD"
            end
            return { action = nil, hold = true, reason = reason }
        end
        return nil
    end
    local entry = practice_rotation_entry(action)
    local label = entry and entry.label or action
    local reason = PRACTICE_ACTION_REASONS[action] or "the rotation wants it now"
    return { action = action, reason = label .. ": " .. reason }
end

-- Why each action is due (short text for the scenario's reason line).
PRACTICE_ACTION_REASONS = {
    kill_shot = "the target is at or under 20% (the execute)",
    kill_command = "off cooldown, the first TBC priority",
    bestial_wrath = "off cooldown (the burst pop)",
    rapid_fire = "off cooldown (the burst pop)",
    chimera = "off cooldown (the Serpent proc pays for it)",
    explosive = "off cooldown (the Survival priority)",
    arcane = "off cooldown (the early-phase filler)",
    aimed = "the cast fits before the next shot",
    multi = "the cast fits before the next shot",
    steady = "the cast fits before the next shot",
    hawk = "fewer than two hawks are active",
    sniper = "the 4 s cast fits before the next shot",
    -- The APL utility layer: the upkeep, the swaps and the melee/trap rows.
    serpent = "the sting is down on the target",
    aspect_viper = "the mana is low and the Viper is down",
    aspect_hawk = "the mana is back and the Hawk is down",
    aspect_falcon = "neither the Viper nor the Falcon is up",
    aspect_dragonhawk = "the mana is high and the Dragonhawk is down",
    hunters_mark = "the mark is not on the target",
    raptor_strike = "off cooldown, in melee range",
    wyvern_strike = "off cooldown, in melee range",
    wing_clip = "off cooldown, in melee range",
    mongoose_bite = "off cooldown, in melee range",
    immolation_trap = "off cooldown",
    silencing_shot = "off cooldown",
    explosive_trap = "off cooldown",
    black_arrow = "off cooldown",
}

--=========================================================================================
-- The class drills (the audit's target drill set, bench/class_features_drills_2026-10-19.md
-- §2.3 (C))
--=========================================================================================
-- Every drill grades ONE moment and returns the letter for it (the practice score
-- model takes one grade per attempt, st.practice.record_attempt). A drill that can
-- judge the moment alone does, and a drill that needs the player's pick reads it
-- from the ctx (ctx.pick / ctx.pressed / ctx.action / ctx.last_action) and answers
-- nil when there is none - unknown-hides, never a guessed grade.
--
-- The pick channel (the F1 fix in practice_ui.lua's drill_list_grade): the drill-list
-- PRESS is the pick, and the press is written into every alias the graders read -
-- ctx.pick among them, which this class's reader reads FIRST. So a press grades the
-- press, even while a shot is in flight. This class's own ctx (practice_context)
-- publishes the live cast as ctx.pick, and that value survives only when the player
-- pressed NOTHING: a press-less drill press, and the scenario path (a different call
-- site), judge the shot that is actually in flight.
--
-- The four drills:
--   hunter_shot_order    the shot priority (D-H1): which shot the rotation wants now
--   hunter_weave_clip    the clip (D-H2): does the shot fit the ranged cycle
--   hunter_kill_command  the cooldown pops (D-H3): Kill Command, then Bestial Wrath,
--                        then Rapid Fire - in that order
--   hunter_prepull       the opener (D-H4): the pre-pull sequence and the pull opener
ST.HUNTER.practice_drills = {
    {
        key = "hunter_shot_order",
        label = "Shot priority",
        kind = "rotation_order",
        description = "Pick the shot the rotation wants next: Kill Shot, Chimera, Explosive, Aimed, Arcane, Steady (the cooldown priority).",
        grade = function(self, ctx)
            -- The expected shot is the SAME decision the scenario asks for (the
            -- frozen engine over the caller's state), so the drill and the scenario
            -- can never disagree about the rotation.
            local out = practice_decision(ctx, { ignore_cast = true })
            if not out then
                return nil
            end
            local pressed = practice_pressed(ctx)
            if pressed == nil then
                -- No pick: the priority order is a sequence skill, and the rotation
                -- scenario grades the sequence itself. Nothing to judge here.
                return nil
            end
            local session = practice_session_band(ctx)
            if session then
                return session
            end
            if out.hold then
                -- A cast inside a HOLD window would clip the shot: an illegal cast.
                return "F"
            end
            if out.action ~= nil and pressed == out.action then
                return "S"
            end
            -- A different shot than the rotation wants is a mis-order, not a late pick.
            return "F"
        end,
    },
    {
        key = "hunter_weave_clip",
        label = "The clip",
        kind = "rotation_window",
        description = "Start the shot so it fits the ranged cycle: the cast plus the latency must land before the next Auto Shot.",
        grade = function(self, ctx)
            local now = ctx.now
            if type(now) ~= "number" or now ~= now then
                return nil
            end
            -- The shot the rotation wants: the highest-priority CAST shot of the
            -- running rotation that is off cooldown (the engine withholds a shot that
            -- does not fit, so the drill reads the rotation itself - that is what
            -- makes the clip band reachable).
            local shot, shot_input = practice_due_cast_shot(ctx, st.family)
            if shot == nil then
                return nil -- no cast shot is due: this drill grades the weave
            end
            local cast_seconds = practice_cast_seconds(shot_input)
            if cast_seconds == nil then
                return nil
            end
            local margin = practice_clip_margin(shot_input, cast_seconds, ctx, now)
            if margin == nil then
                return nil
            end
            if margin < 0 then
                return "F" -- the cast would clip the Auto Shot
            end
            return practice_band(margin, ST.HUNTER.PRACTICE_MARGIN_BANDS)
        end,
    },
    {
        key = "hunter_kill_command",
        label = "Cooldown pops",
        kind = "situational",
        description = "Pop the TBC cooldowns in the sim's order: Kill Command, then Bestial Wrath, then Rapid Fire.",
        grade = function(self, ctx)
            if st.family ~= "TBC" then
                return nil -- the pops are a TBC rotation (the sim's TBC APL only)
            end
            -- The expected pop: the first of the three that is off cooldown (the sim's
            -- order: Kill Command, then Bestial Wrath, then Rapid Fire).
            local expected = nil
            for i = 1, #PRACTICE_TBC_POPS do
                local action = PRACTICE_TBC_POPS[i]
                local remaining = practice_cooldown(ctx.cooldowns, action,
                    PRACTICE_TBC_POP_KEYS[action] or action)
                if remaining == nil or remaining <= 0 then
                    expected = action
                    break
                end
            end
            if expected == nil then
                return nil -- nothing is up: there is no pop to make
            end
            local pressed = practice_pressed(ctx)
            if pressed ~= nil then
                local is_pop = false
                for i = 1, #PRACTICE_TBC_POPS do
                    if PRACTICE_TBC_POPS[i] == pressed then
                        is_pop = true
                        break
                    end
                end
                if not is_pop then
                    return nil -- this drill grades the pops, not the shots
                end
                if pressed ~= expected then
                    return "F" -- the wrong pop: the sim's order is KC, then BW, then RF
                end
                local late = practice_lateness(ctx)
                if late == nil or late <= 0 then
                    return "S"
                end
                return practice_band(late, ST.HUNTER.PRACTICE_POP_LATE_BANDS)
            end
            -- No pick: the moment itself is the judgement. How far down the sim's
            -- order the moment sits: Kill Command up is the clean pop (S), a later
            -- pop while the earlier one is still on cooldown means the order slipped
            -- (A for the second, B for the third).
            for i = 1, #PRACTICE_TBC_POPS do
                if PRACTICE_TBC_POPS[i] == expected then
                    if i == 1 then
                        return "S"
                    elseif i == 2 then
                        return "A"
                    end
                    return "B"
                end
            end
            return nil
        end,
    },
    {
        key = "hunter_prepull",
        label = "The opener",
        kind = "transition",
        description = "Run the pre-pull sequence: the aspect at -20 s, then the pull opener (the Steady inside the first half second).",
        grade = function(self, ctx)
            local prepulls = ST.HUNTER.PRACTICE_PREPULLS[ST.HUNTER.practice_rotation_family()]
            if not prepulls then
                return nil -- no sourced pre-pull sequence for this client
            end
            local now = ctx.now
            if type(now) ~= "number" or now ~= now then
                return nil
            end
            local pull_time = practice_prepull_time(ctx, now)
            if pull_time == nil then
                return nil -- no pull clock: the opener drill needs one
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
            local pressed = practice_pressed(ctx)
            if pressed ~= nil then
                if pressed ~= expected.action then
                    -- A different opener: the due one was missed.
                    return "D"
                end
                local late = pull_time - expected_at
                if late <= 0 then
                    return "S" -- on time (or early)
                end
                return practice_band(late, ST.HUNTER.PRACTICE_PREPULL_LATE_BANDS)
            end
            -- No pick: the moment itself is the judgement. The opener's window is the
            -- span up to the next opener's offset (the sim's own spacing); a moment
            -- after it is late by the same measure the pick reading uses.
            local next_at = nil
            for i = 1, #prepulls do
                if prepulls[i].at > expected_at then
                    next_at = prepulls[i].at
                    break
                end
            end
            if next_at == nil then
                next_at = expected_at + ST.HUNTER.PRACTICE_PREPULL_WINDOW_SECONDS
            end
            if pull_time < next_at then
                return "S" -- inside the due opener's window
            end
            return practice_band(pull_time - next_at, ST.HUNTER.PRACTICE_PREPULL_LATE_BANDS)
        end,
    },
}

-- The three TBC cooldown pops, in the sim's order (the tbc-new APL pops them as
-- they come off cooldown, Kill Command first), with the engine's own cooldown keys
-- (the gathered input without its "_remaining_cd" suffix).
PRACTICE_TBC_POPS = { "kill_command", "bestial_wrath", "rapid_fire" }
PRACTICE_TBC_POP_KEYS = {
    kill_command = "kc",
    bestial_wrath = "bw",
    rapid_fire = "rf",
}

-- The clip margin of a press: the seconds between the press and the latest safe
-- start (the engine's own arithmetic, st.hunter_guide.cast_margin). Negative means
-- the cast would clip the Auto Shot.
practice_clip_margin = function(action, cast_seconds, ctx, now)
    local engine = st.hunter_guide
    if not (engine and engine.cast_margin) then
        return nil
    end
    local cycle = ctx.cycle_duration
    if cycle == nil then
        cycle = ctx.synced_duration
    end
    if type(cycle) ~= "number" or cycle ~= cycle or cycle <= 0 then
        cycle = ST.HUNTER.PRACTICE_CYCLE_SECONDS
    end
    local latency = ctx.latency
    if type(latency) ~= "number" or latency ~= latency or latency < 0 then
        latency = 0
    end
    local cycle_start = now - (now % cycle)
    local time_to_next_shot = (cycle_start + cycle) - now
    return engine.cast_margin(cast_seconds, latency, time_to_next_shot,
        practice_cast_grace(action))
end

-- The session band for a run (the audit's D-H1 bands): the mis-pick count over the
-- decisions the caller counted. Nil when the caller carries no tally (the drill then
-- grades the single decision).
practice_session_band = function(ctx)
    if type(ctx) ~= "table" then
        return nil
    end
    local mispicks = ctx.mispicks
    if type(mispicks) ~= "number" or mispicks ~= mispicks or mispicks < 0 then
        return nil
    end
    return practice_band(mispicks, ST.HUNTER.PRACTICE_ORDER_BANDS)
end

-- The band lookup (the first band whose max the value fits; the open band catches
-- the rest).
practice_band = function(value, bands)
    for i = 1, #bands do
        local band = bands[i]
        if band.max == nil or value <= band.max then
            return band.grade
        end
    end
    return bands[#bands].grade
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
--   raptor          Raptor Strike - a guide slot on the ERA, SoD, TBC and Forever
--                   slot sets, and a rotation row on NONE of them under this key.
--                   So a Raptor Strike press is legitimate and ungraded where the
--                   rotation never asks for that SPELL.
--                   THE ERA BUCKET IS BUILD-AWARE: the SoD build runs on the ERA
--                   client and the engine's family-scoped publish reads st.family
--                   only, so the ERA bucket covers BOTH builds - and on the SoD
--                   build the rotation DOES ask for the Raptor Strike (under the
--                   key `raptor_strike` - the same spell, one key apart). The
--                   class's OWN build decision therefore drops the key there; see
--                   apply_neutral_build_pick below.
--   concussive_shot Concussive Shot - a control spell the rotation never asks for.
--   sprint          Sprint - a movement spell.
--   healthstone     Healthstone - a consumable.
--   healing_potion  Healing Potion - a consumable.
--   food            Food - a consumable.
--
-- THE KEYS THAT ARE DELIBERATELY NOT NEUTRAL:
--   aimed           Aimed Shot - the HUNTER'S OWN drill cast (PRACTICE_SHOT_ORDER:
--                   steady, multi, aimed). It is a rotation action on the families
--                   whose rotation asks for it (ERA, SoD, Wrath) and an intentional
--                   mis-pick where the rotation does not (TBC, Forever) - the
--                   drill's own truth, never a neutral action.
--   steady          Steady Shot - the drill's own cast too, and a rotation action
--                   on TBC and Wrath. The Era and the SoD clients have no Steady
--                   Shot at all (the spell arrived in 2.3) and the Forever client
--                   has none either, so there it is an intentional mis-pick.
--   raptor_strike   The Raptor Strike's rotation-row key (the SoD and the Forever
--                   rotations ask for it): a rotation action can never be neutral.
--   bestial_wrath   The SoD build's Bestial Wrath slot: the SoD rotation carries
--                   no Bestial Wrath row, so a press there is an intentional
--                   mis-pick (the era-base build does not declare the slot at all).
--   the rotation actions themselves (kill_command, bestial_wrath, rapid_fire,
--   arcane, multi, steady, serpent, the aspects and each family's shot rows) -
--   the rotation grades those.
--
-- THE CATA AND MISTS CLIENTS carry no bucket here: the class publishes no neutral
-- set for them, so every non-rotation press on those clients stays a mis-pick
-- (exactly as before this table) - the same shape the four classes that already
-- landed it publish (bench/class_common_actions_2026-10-20.md §3).
--=========================================================================================
ST.HUNTER.practice_neutral_actions = {
    ERA = {
        raptor = true,
        concussive_shot = true,
        sprint = true,
        healthstone = true,
        healing_potion = true,
        food = true,
    },
    TBC = {
        raptor = true,
        concussive_shot = true,
        sprint = true,
        healthstone = true,
        healing_potion = true,
        food = true,
    },
    WRATH = {
        concussive_shot = true,
        sprint = true,
        healthstone = true,
        healing_potion = true,
        food = true,
    },
    FOREVER = {
        concussive_shot = true,
        sprint = true,
        healthstone = true,
        healing_potion = true,
        food = true,
    },
    -- THE CATA AND MISTS CLIENTS (the 4.4.3 and the 5.5.0 clients - the two TOCs
    -- that ship this addon, SwedgeTimer_Cata.toc and SwedgeTimer_Mists.toc) carry
    -- NO BUCKET HERE, and that is the class's own statement, not a gap:
    --
    --   * the class publishes NO rotation for either client (ST.HUNTER.PRACTICE_ROTATIONS
    --     carries no CATA / MISTS table, so practice_rotation_for answers an empty
    --     slice there), so on those two clients no row of the class's own is a
    --     rotation action. A bucket is the class's statement about a client it
    --     PLAYS; the class plays neither of these;
    --   * the class's guide vocabulary on those two clients is its own slot set (the
    --     Mists set even drops the Raptor Strike - the Mists client's own spell data
    --     carries no Raptor Strike id this tree knows, so the class's
    --     SPELL_ID_BY_FAMILY.raptor.MISTS cell is deliberately empty), and the class
    --     makes no statement about the rest of it there;
    --   * so the OFFER GATE (ST.HUNTER.practice_common_offer_allowed) offers NO
    --     common ability on those two clients: an ability the family does not
    --     publish as neutral can only be a mis-pick the moment it is pressed, so
    --     the panel does not offer it there. It stays available on the families
    --     where the class DOES publish it.
    --
    -- FOR THE RECORD (the clients' own spell pages - the /data/spell/<id> page on
    -- the warcraftdb site, on the Cataclysm and the MoP expansion domains, whose
    -- title carries the client's own spell name): the Cata and the Mists clients
    -- DO carry every one of the class's five common abilities - Concussive Shot
    -- 5116, Sprint 2983, the Healthstone (the clients' own rank is 6262 - the Era
    -- id 5720 answers "Not Found" there, and 6262 is a DIFFERENT spell on the
    -- classic clients - "Minor Healthstone" - so the ladder is NOT extended with
    -- it: the id table is the citation and the fallback, and the client's own
    -- rank only where that id still exists on it; the NAME-first leg finds the
    -- client's own rank only where the client ANSWERS the name, and whether the
    -- classic-line global takes a name at all is UNCONFIRMED in-client,
    -- bench/final_gate_audit_2026-10-20.md §6 C1), the Healing Potion 439 and
    -- the Food 433. The exclusion is a deliberate statement about a client the
    -- class does not play, not a belief that the client lacks the spells.
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
function ST.HUNTER.practice_neutral_set()
    local published = ST.HUNTER.practice_neutral_actions
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
function ST.HUNTER.practice_rotation_action_set()
    local out = {}
    local ok, entries = pcall(function() return ST.HUNTER.practice_rotation_for() end)
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
-- onto the canonical key). The hunter has none - its key space is one - so the
-- normaliser is the identity.
function ST.HUNTER.practice_canonical_key(key)
    local aliases = ST.HUNTER.practice_action_aliases
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
function ST.HUNTER.practice_common_offer_allowed(action, neutral, rotation)
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
        and rotation[ST.HUNTER.practice_canonical_key(action.key)] == true then
        return false
    end
    return true
end

-- The build-aware half of the neutral publish.
--
-- The SoD build runs on the ERA client, so the engine's family-scoped publish
-- (st.family) cannot separate the two builds that share the ERA token - the same
-- limit the warrior's Battle Shout and the shaman's Lightning Shield ran into.
-- The CLASS can separate them: the SoD build is the one that knows the Chimera
-- Shot rune, and the class's OWN build decision - the one that swapped the
-- guide's slot set and the rotation table in resolve_guide_icons - already knows
-- it. One decision, both surfaces (the same rule the HUD's Bestial Wrath pick
-- follows - bench/hunter_sod_build_2026-10-20.md).
--
-- The Raptor Strike is a rotation action on every family whose rotation asks for
-- that SPELL (the SoD and the Forever rotations ask for it under the key
-- `raptor_strike`), and the panel offers the same spell under the key `raptor`
-- (the guide slot). Publishing `raptor` as neutral on such a family would make
-- a WRONG Raptor Strike press free - the grading hole this table must never
-- open. So the pick reads the running family's OWN rotation slice (the single
-- source of truth) and drops the key when that slice asks for the Raptor Strike.
--
-- Only the ERA bucket can change (the SoD build shares the ERA token); the other
-- buckets are the family's own truth and are never touched here.
function ST.HUNTER.apply_neutral_build_pick()
    local published = ST.HUNTER.practice_neutral_actions
    if type(published) ~= "table" or type(published.ERA) ~= "table" then
        return false
    end
    if st.family ~= "ERA" then
        return false
    end
    local slice = ST.HUNTER.practice_rotation_for(ST.HUNTER.practice_rotation_family())
    local asks_raptor = false
    if type(slice) == "table" then
        for i = 1, #slice do
            local entry = slice[i]
            if type(entry) == "table" and entry.action == "raptor_strike" then
                asks_raptor = true
                break
            end
        end
    end
    if not asks_raptor then
        -- The Era-base build: the static publish already carries the Raptor Strike
        -- (its rotation asks for that spell on no family), so the pick has nothing
        -- to correct.
        return false
    end
    published.ERA.raptor = nil
    return true
end

--=========================================================================================
-- The PRACTICE-PANEL ability list: the common abilities the panel offers
--
-- WHY THIS EXISTS: the practice panel's action row offers the class's whole ability
-- list, and a player legitimately presses a heal, a food or a movement ability while
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
-- NO ROTATION ACTION HERE: none of these keys is a rotation action on any family the
-- hunter plays (the class's own rotation rows: kill_command, bestial_wrath,
-- rapid_fire, arcane, multi, steady, serpent, the aspects and each family's own shot
-- rows), so none of them may be a rotation action; the neutral set above publishes
-- exactly these keys.
--=========================================================================================
ST.HUNTER.practice_common_actions = {
    {
        key = "concussive_shot",
        label = "Concussive Shot",
        names = { "Concussive Shot" },
        -- 5116 - the client's Concussive Shot (the corpus description: "Dazes the
        -- target, slowing movement speed by $s1% for $d."; the name confirmed at the
        -- Classic spell page (5116); Libs/LibClassicDurations/classAbilities.lua
        -- carries the same id ("Spell(5116, ...) -- Concussive Shot")). No hunter
        -- rotation row asks for it.
        ids = { 5116 },
    },
    {
        key = "sprint",
        label = "Sprint",
        names = { "Sprint" },
        -- 2983 - the client's Sprint (the corpus description: "Increases the rogue's
        -- movement speed by $s1% for $d.  Does not break stealth." - the shared
        -- movement spell; the name confirmed at the Classic spell page (2983)). No
        -- hunter rotation row asks for it.
        ids = { 2983 },
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
        -- confirmed at the Classic spell page (439)). No hunter rotation row asks
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
function ST.HUNTER.resolve_practice_common_action(action)
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
function ST.HUNTER.practice_panel_slots()
    local guide = ST.HUNTER.guide
    local slots = type(guide) == "table" and guide.slots or nil
    local out = {}
    if type(slots) == "table" then
        for i = 1, #slots do
            out[i] = slots[i]
        end
    end
    local common = ST.HUNTER.practice_common_actions
    if type(common) == "table" then
        -- THE OFFER GATE: a common ability is offered on the running family only if
        -- that family publishes it (as neutral) or the rotation ranks it there - the
        -- offer list and the neutral set are one truth per family.
        local neutral = ST.HUNTER.practice_neutral_set()
        local rotation = ST.HUNTER.practice_rotation_action_set()
        for i = 1, #common do
            local action = common[i]
            if ST.HUNTER.practice_common_offer_allowed(action, neutral, rotation) then
                local slot = ST.HUNTER.resolve_practice_common_action(action)
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
function ST.HUNTER.apply_practice_panel_actions()
    local guide = ST.HUNTER.guide
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
    local widened = ST.HUNTER.practice_panel_slots()
    if type(widened) ~= "table" or #widened <= #current then
        return false
    end
    guide.slots = widened
    return true
end

-- How late the press landed after the expected cooldown came off cooldown (the pop
-- drill): the caller may carry the ready time, otherwise there is no lateness to
-- grade and the press counts as on time.
practice_lateness = function(ctx)
    if type(ctx) ~= "table" then
        return nil
    end
    local late = ctx.late_seconds
    if type(late) == "number" and late == late and late > 0 then
        return late
    end
    local ready_at = ctx.ready_at
    local now = ctx.now
    if type(ready_at) == "number" and ready_at == ready_at
        and type(now) == "number" and now == now then
        local delay = now - ready_at
        if delay > 0 then
            return delay
        end
    end
    return nil
end

--=========================================================================================
-- Shared practice-panel provider (class-isolation 2026-10-21 C1)
--=========================================================================================
-- The hunter's OWN practice route, panel order, ability defs and drill session.
-- The shared practice UI asks the ACTIVE class for this table (its own uniform
-- contract) and renders the answers; it never names the hunter. Every session
-- seam stays the class's own function.
ST.HUNTER.practice_panel = {
    drill_key = "hunter_forced_move",
    title = "|cFFFF8800Forced-Move Practice|r",
    def_type = "shot",
    drift_message = "Practice mode is not available (hunter drill key drifted).",
    idle_status = "Drill idle",
    hint_active = "Click a shot to cast. /st practice or the X button stops.",
    hint_stopped = "Press Start Fight, or cast shots with the icon grid.",
    progress = {
        mode = "hunter_forced_move",
        scenario = "hunter_rotation",
        drills = { "hunter_forced_move" },
    },
    scenario_key = function() return ST.HUNTER.get_practice_scenario_key() end,
    order = function() return ST.HUNTER.PRACTICE_SHOT_ORDER end,
    label = function(key) return ST.HUNTER.practice_shot_label(key) end,
    spell_id = function(key) return ST.HUNTER.practice_shot_spell_id(key) end,
    status = function(ui, now)
        if type(ST.HUNTER.practice_status) ~= "function" then
            return nil
        end
        return ST.HUNTER.practice_status(ui.hunter_session, now)
    end,
    fight_elapsed = function(ui, now)
        if type(ST.HUNTER.practice_fight_elapsed) ~= "function" then
            return nil
        end
        return ST.HUNTER.practice_fight_elapsed(ui.hunter_session, now)
    end,
    session = {
        running = function(ui) return ui.hunter_session ~= nil end,
        active = function(ui)
            return ui.hunter_session and ui.hunter_session.active
        end,
        start = function(self, now, ui)
            if type(ST.HUNTER.practice_new_session) ~= "function"
                or type(ST.HUNTER.practice_begin_session) ~= "function" then
                return false
            end
            local ok_new, session = pcall(function()
                return ST.HUNTER.practice_new_session(now)
            end)
            if not ok_new or session == nil then
                return false
            end
            local ok_begin, begun = pcall(function()
                return ST.HUNTER.practice_begin_session(session, now)
            end)
            if not ok_begin or begun == false then
                return false
            end
            ui.hunter_session = session
            ui.hunter_out = {}
            return true
        end,
        tick = function(self, now, elapsed, ui)
            local session = ui.hunter_session
            if session == nil then
                return
            end
            local out = ST.HUNTER.practice_tick(session, now, elapsed, ui.hunter_out)
            ui.hunter_out = out
            if out and out.move_started then
                ui.show_result(self, "MOVE!")
            end
            ui.update_fight_timer(self, now)
        end,
        cast = function(self, key, ui)
            local session = ui.hunter_session
            if session == nil then
                return nil
            end
            return ST.HUNTER.practice_cast(session, api.get_time(), key)
        end,
        stop = function(self, ui)
            local session = ui.hunter_session
            if session == nil then
                return
            end
            if type(ST.HUNTER.practice_end_session) == "function" then
                ST.HUNTER.practice_end_session(session, api.get_time())
            end
            ui.hunter_session = nil
        end,
        begin = function(self, now, ui)
            if ui.hunter_session and type(ST.HUNTER.practice_begin_session) == "function" then
                ST.HUNTER.practice_begin_session(ui.hunter_session, now)
            end
        end,
        end_session = function(self, ui)
            if ui.hunter_session and type(ST.HUNTER.practice_end_session) == "function" then
                ST.HUNTER.practice_end_session(ui.hunter_session, api.get_time())
            end
        end,
        pause = function(self, ui, shift)
            if ui.hunter_session and type(ST.HUNTER.practice_shift_pause) == "function" then
                ST.HUNTER.practice_shift_pause(ui.hunter_session, shift)
            end
        end,
        sync = function() end,
        clear = function(self) self:handle_bar_visibility("mainhand") end,
    },
}

end


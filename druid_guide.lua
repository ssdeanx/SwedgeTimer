--=========================================================================================
-- Druid next-action guide: pure decision engine, no WoW API and no clock.
--
-- The third provider for the frozen ST.<CLASS>.guide contract (nextaction_ui.lua's
-- header; the paladin ships the first, the warrior the second). The live reads live in
-- classes/druid.lua (ST.DRUID.gather_guide_inputs); this module only consumes the
-- gathered inputs, so it is unit-tested offline by tests/druid_guide_state.lua.
--
-- FROZEN SPEC - display slots (ST.DRUID.guide.slots, ordered, all six the contract
-- allows):
--   maul     Maul           6807  (icon rank-resolved at post_init)
--   mangle   Mangle         33878 (icon rank-resolved through the module's Mangle id
--                                  table at post_init, else this fallback)
--   rip      Rip            1079  (swipe: the tracker's own debuff window)
--   rake     Rake           1822  (swipe: the tracker's own debuff window)
--   bite     Ferocious Bite 22568
--   shred    Shred          5221
--
-- FROZEN SPEC - inputs (all optional, nil never errors):
--   speed, swing_remaining, gcd_remaining    swing/GCD (api.get_time() domain)
--   form_index                               live druid form (1 bear, 3 cat)
--   rage                                     bear rage (api.UnitPower player, 1)
--   energy                                   cat energy (api.UnitPower player, 3)
--   combo_points                             cat combo points, nil-safe (player, 4)
--   maul_queued                              the module's Maul queue flag
--   maul_cost                                Maul's rage cost at the current rank
--   insufficient_rage                        the bar-colour shortfall flag
--   rip_remaining, rake_remaining, mangle_remaining
--                                            target DEBUFF seconds from the module's
--                                            tracker; nil = the target does not carry
--                                            it (or the scan has not answered)
--   rip_refresh, rake_refresh                db thresholds, default 4
--   family                                   compat.lua's st.family ("ERA", "TBC",
--                                            "WRATH", "CATA", "MISTS", "RETAIL",
--                                            "FOREVER", ...); "TBC" runs the TBC
--                                            APPENDIX, "WRATH" runs the WRATH
--                                            APPENDIX, "ERA" runs the SOD APPENDIX
--                                            when sod_runes is true and the ERA
--                                            APPENDIX otherwise, anything else
--                                            (or nil) runs rules 4-8 exactly as below
--   sr_remaining                             SAVAGE ROAR buff seconds from the module's
--                                            player scan; nil = absent (or the scan
--                                            has not answered)
--   tf_ready                                 Tiger's Fury proven ready (true) or proven
--                                            on cooldown (false); nil = unknown (the
--                                            client cannot answer - never a guess)
--   tf_cd_remaining                          Tiger's Fury cooldown seconds, 0 when ready;
--                                            nil = unknown
--   tf_active                                the Tiger's Fury damage buff is up (true
--                                            only; the SoD King-of-the-Jungle snapshot)
--   berserk_ready                            Berserk proven ready (true only)
--   clearcast                                an Omen of Clarity proc is up (true only)
--   sod_runes                                SoD rune basis present on the ERA token
--                                            (true only; a known Mangle rank answers
--                                            api.is_spell_known, else a known Mangle
--                                            or Savage Roar answers GetSpellInfo by
--                                            name - Era-base knows neither)
--   time_to_die                              target seconds-to-die, when known
--                                            (no client source yet; nil = unknown)
--   target_short_lived                       explicit short-lived flag (true only)
--   can_powershift                           RESERVED (no rule reads it): the
--                                            Furor + Wolfshead basis has no
--                                            honest client probe (see the
--                                            REMOVED note in the TBC APPENDIX
--                                            below), so the gather always
--                                            writes nil and no SHIFT prompt
--                                            exists anywhere.
--   mangle_cost                              live Mangle energy cost from the
--                                            client's GetSpellPowerCost through the
--                                            module's current Mangle rank
--                                            (TBC-gated in the gather; nil = the
--                                            client cannot answer - the engine
--                                            falls back to MANGLE_COST_TBC below,
--                                            which keeps every other family and
--                                            every offline caller byte-identical)
--   sp_ready                                 Shifting Power proven ready (true) or
--                                            proven on cooldown (false); nil =
--                                            unknown (FOREVER-gated in the gather -
--                                            never a guess)
--   sp_cd_remaining                          Shifting Power cooldown seconds, 0 when
--                                            ready; nil = unknown
--
-- FROZEN SPEC - rule order (first match wins; exactly these rules):
--   Bear form (form_index == 1):
--     1. maul_queued -> no action, hold = true, hold_text = "RIDE" (the guide rides the
--        queue the player already placed).
--     2. rage sufficient -> action "maul". Sufficient = rage and maul_cost are both
--        numbers and rage >= maul_cost, and insufficient_rage is not true (the flag can
--        veto a proof, never stand in for one). A cost or rage the client cannot answer
--        is NOT sufficient: the engine never guesses a Maul it cannot prove affordable.
--     3. otherwise, off Era -> action "mangle" (the only Mangle prompt left;
--        SoD rides here too: sod_runes on the ERA token proves Mangle via rune).
--     3e. otherwise, on Era without runes (family == "ERA", sod_runes not true) ->
--        wait (action nil, no hold): Era has no Mangle (the module's Mangle ids
--        33983/33987 are TBC+), so the guide pools rage instead of guessing a
--        spell the client cannot know.
--   Cat form (form_index == 3):
--     TBC (family == "TBC") -> the TBC APPENDIX (T1-T6), byte-identical.
--     FOREVER (family == "FOREVER") -> the FOREVER APPENDIX (F1, then rules
--       4-8 exactly as below).
--     ERA (family == "ERA") + sod_runes -> the SOD APPENDIX (S1-S9).
--     ERA (family == "ERA") without runes -> the ERA APPENDIX (E1-E2), byte-identical.
--     WRATH (family == "WRATH") -> the WRATH APPENDIX (W1-W9).
--     Anything else (or nil) -> rules 4-8 exactly as below:
--     4. rip_remaining nil or <= rip_refresh -> action "rip". A remaining of exactly
--        the threshold refreshes; nil (no Rip tracked) always refreshes.
--     5. else rake_remaining nil or <= rake_refresh -> action "rake".
--     6. else mangle_remaining nil -> action "mangle" (absent outright only: Mangle has
--        no refresh window).
--     7. else combo_points is a number >= 5 -> action "bite"; an unreadable combo count
--        cannot clear the threshold and falls through.
--     8. else -> action "shred".
--   Any other or unknown form (caster forms, no form, an unreadable form_index) -> no
--   action: unknown context never guesses a bear or cat action.
--
-- TBC APPENDIX - cat form only, when family == "TBC" (first match wins):
--   T1. combo_points >= 4 and Rip expired (nil or <= 0, no window) -> "rip".
--   T2. mangle_remaining nil and energy >= 40 -> "mangle" (the TBC Mangle cost).
--   T3. combo_points >= 5 and a short-lived target -> "bite" (the only TBC Bite:
--       target_short_lived == true, or time_to_die <= 12, one full Rip).
--   T4. combo_points >= 5 -> "rip" (the long-fight finisher is always Rip).
--   T5. energy >= 42 -> "shred" (the TBC Shred cost).
--   T6. otherwise -> wait (action nil, no hold): pool energy, do not guess.
--   REMOVED (was T6, the can_powershift SHIFT call): the shift basis has no
--   honest client probe - main.lua's talent_positions covers WRATH only (no
--   verified TBC Furor tab/index, so any GetTalentInfo read would be a guess)
--   and no Wolfshead Helm item id is verified in this codebase (so any
--   GetInventoryItemID read would be a guess). The gather writes
--   can_powershift = nil on every tick, the branch advertised a prompt that
--   could never show, and its POWERSHIFT_SHORTFALL_TBC constant is gone with
--   it. Do not re-add the call without a confirmed probe.
--   Rake is never prompted on TBC (no TBC PvE rotation uses it; the rake slot
--   stays declared for the Wrath matrix). Tiger's Fury is never prompted
--   mid-rotation (pre-pull only); no rule names it. Bear form is rules 1-3 on
--   every non-Era family plus SoD (rule 3e waits on runeless Era only);
--   every non-TBC, non-Era, non-Wrath, non-Forever family runs rules 4-8 unchanged.
--
--   TBC MICRO (docs/research/tbc_minmax.md, Warcraft Tavern feral guide):
--   energy ticks continue every 2 s regardless of form (no reset on shift), so
--   the tick bar keeps its phase across powershifts on TBC (the anchor policy
--   lives in classes/druid.lua; the cycle maths in druid_energy.lua is
--   anchor-relative and needed no change). The 2pc-T6 bonus cuts Mangle (Cat)
--   to 35 energy (non-Wolfshead P5 rotation): T2 spends inputs.mangle_cost
--   when the gather proves it live, else the frozen 40. Whether TBC
--   GetSpellPowerCost reflects the set bonus is in-game to confirm. Rip
--   snapshots attack power at cast (trinket procs included): no trinket-proc
--   input exists (no buff list, no AP comparison), so no rule models the
--   snapshot - in-game to confirm before any prompt is built.
--
-- FOREVER APPENDIX - cat form only, when family == "FOREVER" (F1 first, then
-- rules 4-8 exactly as below):
--   F1. sp_ready and energy with room for the Shifting Power gain (<= 60:
--       100 - 40 cannot overcap) -> hold "SHIFTING POWER" with action nil (no
--       free slot exists, so the hold overlay carries the call). Cat-only by
--       construction (this branch never runs in bear).
--   then 4-8. the legacy maintenance chain unchanged (Rip window, Rake
--       window, absent-only Mangle, 5CP Bite, Shred).
--   UNCONFIRMED (task-brief knowledge, beta docs conflict; in-game to confirm
--   before release): Tiger's Fury is ABSENT on Forever (no rule may ever hold
--   it here - the section-7 sweep pins that), Shifting Power is Cat-only with
--   a 16 s cooldown granting 40 energy for mana (docs/research/forever_beta.md
--   instead says "Shifting Power if <60 energy" with unknown energy values and
--   unknown mana gating - the <= 60 line sides with the beta's <60 prose via
--   the 100-40 room, but the 40 gain, the 16 s cooldown and the TF removal are
--   all unverified). No powershifting on Forever (no SHIFT rule exists
--   anywhere since the powershift branches were removed; the sweep pins
--   that no hold ever reads SHIFT). Weapon DPS scales forms on Forever:
--   no weapon input exists, so note only, no guide expression. The mana cost
--   of Shifting Power is not modelled (no mana input; the proven-ready
--   cooldown is necessary but may not be sufficient - in-game to confirm).
--
-- ERA APPENDIX - cat form only, when family == "ERA" (first match wins):
--   E1. combo_points is a number >= 5 -> "bite" (the powershift-loop finisher is
--       always Ferocious Bite; no energy gate, the TBC-finisher convention: the
--       guide shows the next action, the pooling shows on the energy tick bar).
--   E2. otherwise -> "shred" (the Era builder, ungated: no verified Era cost
--       exists, so the builder is never withheld for energy).
--   REMOVED (was E2, the can_powershift SHIFT call): same dead input as the
--   TBC T6 above - it shared the removed POWERSHIFT_SHORTFALL_TBC constant,
--   which cannot survive its removal (a number > nil raises), so the branch
--   goes with it. Do not re-add without a confirmed probe.
--   Mangle is never prompted on Era (its ids are TBC+; the code comment at
--   classes/druid.lua pins the tracker bar inert there too, and the Mangle guide
--   icon stays dark because no rule ever lights it). Rip and Rake are never
--   prompted on Era either (their refresh windows are the TBC/Wrath maintenance
--   model; the Era loop is Shred/FB/powershift). SoD shares the ERA token but HAS
--   Mangle/Savage Roar/Tiger's Fury via runes: with sod_runes it runs the SOD
--   APPENDIX below, never this chain (the runeless Era chain is byte-identical).
--   Bear form on Era is rules 1-2 plus 3e (wait); every non-Era, non-TBC, non-Wrath
--   family runs rules 1-3 / 4-8 unchanged.
--
-- WRATH APPENDIX - cat form only, when family == "WRATH" (first match wins):
--   W1. tf_ready and energy < 40 -> hold "TIGER'S FURY" with action nil (no
--       free slot exists, so the hold overlay carries the call;
--       docs/research/rotations_wrath.md tree step 1).
--   W2. berserk_ready and energy <= 85 and TF on cooldown >= 15 s ->
--       hold "BERSERK" with action nil (same slot rationale; the energy line
--       keeps the 15 s Berserk from capping, the 15 s TF gate is the doc's
--       step 2 - Berserk after TF).
--   W3. combo_points >= 1 and Savage Roar expired (nil or <= 0) ->
--       hold "SAVAGE ROAR" with action nil (same slot rationale; the doc's
--       step 3 - no clipping, expiry-only like the TBC Rip).
--   W4. clearcast -> "shred" (the doc's step 4: the Omen of Clarity proc is a
--       free Shred, ahead of the finishers).
--   W5. combo_points >= 5 and Rip expired (nil or <= 0) -> "rip" (the doc's
--       step 5; no energy gate - the guide shows the next action, the pooling
--       shows on the energy tick bar, the TBC-finisher convention).
--   W6. mangle_remaining nil -> "mangle" (absent outright only, the rule-6
--       convention - and ABOVE Rake: Mangle's 30% bleed multiplier lifts every
--       Rip/Rake tick, so a missing Mangle outranks a missing Rake).
--   W7. Rake expired (nil or <= 0) -> "rake" (the doc's step 6; no clipping).
--   W8. combo_points >= 5 and Rip and Savage Roar both healthy (>= the FB
--       minima below) and the target inside the last-10-seconds execute window
--       -> "bite" (the conditional Ferocious Bite: both bleeds must survive
--       the rebuild after the bite, and the bite itself only pays inside the
--       execute window - docs/research/rotations_wrath.md Notes: "Ferocious
--       Bite only last 10s of fight", "removed from mid-fight rotation").
--   W9. otherwise -> "shred" (the builder default; pooling shows on the tick
--       bar - the bearweave branch of the doc is NOT built: no bear-form
--       timer/rage input exists here, in-game to confirm).
--   No powershifting on Wrath (Furor no longer refunds on shift): no rule
--   holds SHIFT here, ever. The last-10-seconds clause rides the frozen
--   execute inputs (target_short_lived, time_to_die <= 10); time_to_die has
--   no client source yet and the gather writes nil, so an unknown target
--   defaults to the long fight and the mid-fight Bite falls through to
--   Shred until an explicit execute signal exists (the research behaviour).
--
-- SOD APPENDIX - cat form only, when family == "ERA" with sod_runes
-- (first match wins; docs/research/rotations_sod.md):
--   S1. tf_ready and energy <= 40 -> hold "TIGER'S FURY" with action nil (King
--       of the Jungle grants +60 energy: 40 is the largest pool that cannot
--       overcap, 100 - 60; same slot rationale as W1).
--   S2. berserk_ready and TF burned (tf_ready == false) -> hold "BERSERK"
--       with action nil (Berserk immediately after TF, the doc's step 7).
--   S3. combo_points >= 1 and Savage Roar expired (nil or <= 0) ->
--       hold "SAVAGE ROAR" with action nil (the doc's step 4).
--   S4. clearcast -> "shred" (the doc's step 8: Omen procs become Shred).
--   S5. combo_points >= 5 and (Rip expired, or TF active) -> "rip" (the doc's
--       step 9 with the Rip-under-TF preference: refreshing under Tiger's Fury
--       snapshots King of the Jungle's +15% physical damage onto the new Rip.
--       No snapshot-state probe exists, so a TF-active refresh may clip an
--       already-snapshotted Rip - in-game to confirm).
--   S6. mangle_remaining nil -> "mangle" (absent outright only, the doc's
--       step 2 ahead of Rake).
--   S7. Rake expired (nil or <= 0) -> "rake" (the doc's step 3; no verified
--       SoD refresh window exists, so expiry-only - in-game to confirm).
--   S8. combo_points >= 5 -> "bite" (capped CP with a healthy Rip and no TF
--       snapshot to take: the Era-loop CP dump, in-game to confirm).
--   S9. otherwise -> "shred" (the builder, ungated: no verified SoD energy
--       cost exists, the E2 convention).
--   REMOVED (was S6, the can_powershift SHIFT call at ~0 energy after the
--   tick): same dead input as the TBC T6 above, with its own
--   SOD_POWERSHIFT_MAX_ENERGY constant removed alongside. Do not re-add
--   without a confirmed probe.
--   Faerie Fire (the pull-only opener), the Glowing Cowl / Catnip use-items
--   and trinket stacking have no guide expression and stay manual.
--
-- SLOT DECISION (frozen six-slot contract, nextaction_ui.lua header: other
-- classes stay at six): all six slots are live on Wrath/SoD - Maul is the bear
-- core, and Mangle/Rip/Rake/Bite/Shred all sit in the Wrath cat priority, so
-- no slot is expendable and none is replaced. Savage Roar, Tiger's Fury and
-- Berserk therefore prompt through the hold overlay (the hold-overlay
-- convention), which the rotation text surfaces verbatim (get_rotation_key
-- returns hold_text), instead of through a lit icon.
--
-- BEAR APPENDIX - bear form only, every non-RETAIL family (first match wins):
--   B1. maul_queued -> hold "RIDE" (rule 1 above; every family, Era included).
--   B2. proven-affordable Maul -> "maul" (rule 2 above; every family).
--   B3. otherwise, non-Era -> "mangle" (rule 3 above: Wrath, TBC, Cata, Mists,
--       Forever - the only bear fallback the six slots can name).
--   B3e. otherwise, on Era -> wait (rule 3e above: no Mangle/Lacerate on Era).
--   TBC bear runs B1-B3 unchanged: Mangle (Bear) is TBC+ (the module's Mangle
--   ids 33983/33987 resolve there and the 12 s tracker fallback is the
--   reference's TBC-era debuff length), and Lacerate/Swipe/Bash carry no guide
--   slot (the six-slot contract is frozen), so no TBC bear rule names them.
--   Era bear runs B1-B2 plus B3e: Maul/Swipe exist but Swipe has no slot, so
--   short of Maul rage the guide pools instead of guessing. SoD shares the
--   ERA token but HAS Mangle via rune: with sod_runes it rides rule 3 (not 3e),
--   so the SoD bear falls back to Mangle; runeless Era keeps B3e.
--   Unlike the cat Mangle (rule 6, absent-only), the bear fallback has no
--   debuff-absence gate: it prompts whenever Maul is unproven. That is the
--   Wrath-pinned behaviour and stays byte-identical here; whether a healthy
--   Mangle debuff should suppress it on TBC is in-game to confirm.
--   UNCONFIRMED (own feral-tank knowledge, no offline source; in-game to
--   confirm before release): the 33878/33987 bear-vs-cat rank split, the TBC
--   Mangle (Bear) cooldown and exact debuff length, Cata/Mists bear keeping
--   rule 3 (Thrash and the MoP rework unassessed), the Forever Mangle ranks.
--
--   Retail (12.x) inertness: st.family == "RETAIL" short-circuits evaluate to the
--   empty display shape before any rule below. The inert stand-in never reports a
--   swing, but rage/energy costs (bear rule 2, TBC rules T2/T5), the queue flag
--   (bear rule 1) and the absent-debuff defaults (cat rules 4-6, where nil always
--   refreshes) all answer on Retail, so those rules would prompt with no swing at
--   all. Every other family runs the matrix above unchanged; a nil family (offline
--   callers that predate it) keeps the old behaviour too.
--
-- Output: the frozen display fields are overwritten on every call:
--   action, hold, hold_text, filler_slot = nil, judge_slot = nil, rotation_key = nil,
--   waiting_judgement = false.
--=========================================================================================
local _, st = ...

st.druid_guide = st.druid_guide or {}

-- Rule constants (frozen; the options panel exposes only the two refresh thresholds).
st.druid_guide.RIP_REFRESH_DEFAULT = 4
st.druid_guide.RAKE_REFRESH_DEFAULT = 4

-- TBC cat costs from the TBC 2.5.6 spell data: Mangle (Cat) 40 energy, Shred
-- 42 energy. Rip (30) and Ferocious Bite (35) are named, never gated: the guide
-- shows the next action, it never withholds a finisher for energy (the energy
-- tick bar shows the pooling instead).
st.druid_guide.MANGLE_COST_TBC = 40
st.druid_guide.SHRED_COST_TBC = 42
-- The 2pc-T6 bonus cuts Mangle (Cat) to 35 energy
-- (docs/research/tbc_minmax.md: "2pc T6 reduces Mangle cost by 5 (35
-- energy) -> non-Wolfshead rotation"). The engine never hardcodes the
-- cheaper prompt: T2 spends inputs.mangle_cost when the gather proves it
-- live, else MANGLE_COST_TBC above. Whether the client reports the reduced
-- cost through GetSpellPowerCost is in-game to confirm.
st.druid_guide.MANGLE_COST_T6_2PC_TBC = 35
-- Short-lived means dying inside one full Rip (see below); the powershift
-- branches and their shortfall constants were removed (see the REMOVED notes
-- in the appendices above), so no powershift constant ships anymore.
-- One full Rip is 12 s: a target dying sooner never pays Rip back (Bite there).
st.druid_guide.SHORT_LIVED_TTD_SECONDS = 12

-- Wrath cat lines (docs/research/rotations_wrath.md EJ decision tree): Tiger's
-- Fury under 40 energy (the doc's tree step 1: "If <40 Energy and Tiger's Fury
-- off CD" - the research overrules the earlier 30-energy lane instruction;
-- nothing in the code ever proved 30), Berserk at or under 85 energy once
-- Tiger's Fury has been on cooldown for 15 s or more (the doc's step 2).
st.druid_guide.TF_ENERGY_WRATH = 40
st.druid_guide.BERSERK_ENERGY_WRATH = 85
st.druid_guide.TF_CD_GATE_BERSERK_SECONDS = 15
-- The conditional Ferocious Bite needs both Rip and Savage Roar healthy enough
-- to survive the post-bite rebuild: 8 s each. No offline source pins the exact
-- guard (own heuristic, in-game to confirm before release).
st.druid_guide.FB_RIP_MIN_SECONDS = 8
st.druid_guide.FB_SR_MIN_SECONDS = 8
-- The Wrath execute window for that Bite: the last 10 s of the fight
-- (docs/research/rotations_wrath.md Notes: "Ferocious Bite only last 10s of
-- fight"). Unknown defaults to the long fight (nil time_to_die is never
-- execute, the TBC short-lived convention).
st.druid_guide.FB_EXECUTE_TTD_SECONDS = 10
-- SoD cat lines (docs/research/rotations_sod.md): Tiger's Fury at or under 40
-- energy (King of the Jungle grants +60: 100 - 60 cannot overcap).
st.druid_guide.TF_ENERGY_SOD = 40
-- Forever cat lines (UNCONFIRMED task-brief knowledge, beta docs conflict -
-- see the FOREVER APPENDIX in the module header): Shifting Power is ASSUMED
-- to grant 40 energy, so 60 is the largest pool that fits it (100 - 40 cannot
-- overcap - the SoD TF convention; docs/research/forever_beta.md prose says
-- "Shifting Power if <60 energy" with unknown values). No client source
-- publishes either number: F1 gates the call behind the Shifting Power
-- knowledge probe (sp_ready, proven via the GetSpellInfo name query - the
-- only probe Forever exposes, since no spell id is published), but the 60/40
-- values themselves are assumed until confirmed in-game. The invariant below
-- (60 == 100 - 40) is pinned by tests/druid_guide_state.lua.
st.druid_guide.SP_ENERGY_GAIN_FOREVER = 40
st.druid_guide.SP_ENERGY_FOREVER = 60

-- A threshold input: the caller's number, else the frozen default. 0 is a real value
-- (refresh only when the debuff is absent outright).
local function threshold(value, default)
    if type(value) == "number" then
        return value
    end
    return default
end

-- TBC: energy affordability is a proof, never a guess: the reading must be a
-- number that covers the cost. (NaN covers nothing: every comparison is false.)
local function tbc_can_spend(inputs, cost)
    local energy = inputs.energy
    return type(energy) == "number" and energy >= cost
end

-- TBC: the Mangle affordability line: the gather's live cost when it proves
-- one (the 2pc-T6 35), else the frozen 40. A non-number (nil, NaN-proofed by
-- the comparison below: NaN covers nothing) never lowers the line.
local function tbc_mangle_cost(inputs)
    if type(inputs.mangle_cost) == "number" then
        return inputs.mangle_cost
    end
    return st.druid_guide.MANGLE_COST_TBC
end

-- TBC: short-lived means Rip never pays back: an explicit flag, or a
-- time-to-die inside one full Rip. Anything unknown defaults to the long
-- fight (nil is never short-lived).
local function tbc_target_is_short_lived(inputs)
    if inputs.target_short_lived == true then
        return true
    end
    local remaining = inputs.time_to_die
    return type(remaining) == "number"
        and remaining <= st.druid_guide.SHORT_LIVED_TTD_SECONDS
end

-- Wrath: execute means the Bite pays back: an explicit short-lived flag, or a
-- time-to-die inside the last-10-seconds window. Anything unknown defaults to
-- the long fight (nil is never execute).
local function wrath_target_is_execute(inputs)
    if inputs.target_short_lived == true then
        return true
    end
    local remaining = inputs.time_to_die
    return type(remaining) == "number"
        and remaining <= st.druid_guide.FB_EXECUTE_TTD_SECONDS
end

-- Pure: one engine tick. Reads `inputs`, writes the frozen display fields into the
-- caller-owned `out` table and returns it. See the module header for the rule matrix.
function st.druid_guide.evaluate(inputs, out)
    inputs = inputs or {}
    if type(out) ~= "table" then
        out = {}
    end

    if st.family == "RETAIL" then
        -- Retail (12.x): no live swing exists (see the header), so no rule may
        -- prompt - not an action, not a HOLD/RIDE/SHIFT overlay.
        out.action = nil
        out.hold = false
        out.hold_text = nil
        out.filler_slot = nil
        out.judge_slot = nil
        out.rotation_key = nil
        out.waiting_judgement = false
        return out
    end

    local action
    local hold = false
    local hold_text
    local form = inputs.form_index

    if form == 1 then
        if inputs.maul_queued == true then
            -- 1. A queued Maul is already riding the next swing: ride it.
            hold = true
            hold_text = "RIDE"
        else
            -- 2. Maul only when the gathered numbers prove it affordable; the module's
            -- shortfall flag can veto a proof but never stand in for one.
            local rage = inputs.rage
            local cost = inputs.maul_cost
            local sufficient = type(rage) == "number" and type(cost) == "number"
                and rage >= cost and inputs.insufficient_rage ~= true
            if sufficient then
                action = "maul"
            elseif inputs.family == "ERA" and inputs.sod_runes ~= true then
                -- 3e. Runeless Era has no Mangle (its ids are TBC+): pool rage
                -- instead of guessing a spell the client cannot know (wait: nil,
                -- no hold). SoD shares the token but proves Mangle via rune and
                -- rides rule 3 below.
                action = nil
            else
                -- 3. The bear fallback.
                action = "mangle"
            end
        end
    elseif form == 3 then
        if inputs.family == "TBC" then
            -- TBC cat chain; see the TBC APPENDIX in the module header.
            local cp = inputs.combo_points
            if type(cp) ~= "number" then
                cp = 0
            end
            local rip_remaining = inputs.rip_remaining
            local rip_expired = type(rip_remaining) ~= "number" or rip_remaining <= 0
            if cp >= 4 and rip_expired then
                -- T1. 4+ CP with Rip expired: Rip (expiry-only, never a window).
                action = "rip"
            elseif inputs.mangle_remaining == nil
                and tbc_can_spend(inputs, tbc_mangle_cost(inputs)) then
                -- T2. Mangle absent and affordable: 40 energy, or the live
                -- cost (the 2pc-T6 35) when the gather proves one.
                action = "mangle"
            elseif cp >= 5 and tbc_target_is_short_lived(inputs) then
                -- T3. 5 CP on a short-lived target: the only TBC Bite.
                action = "bite"
            elseif cp >= 5 then
                -- T4. 5 CP on a long fight: always Rip, never Bite.
                action = "rip"
            elseif tbc_can_spend(inputs, st.druid_guide.SHRED_COST_TBC) then
                -- T5. Affordable at the TBC 42-energy cost: build with Shred.
                action = "shred"
            end
            -- T6. Otherwise: wait (action nil, no hold); pool, do not guess.
            -- (The old T6 powershift call was removed with its constant: no
            -- honest Furor/Wolfshead probe exists - see the REMOVED note in
            -- the TBC APPENDIX above.)
        elseif inputs.family == "ERA" and inputs.sod_runes == true then
            -- SOD cat chain; see the SOD APPENDIX in the module header.
            local cp = inputs.combo_points
            if type(cp) ~= "number" then
                cp = 0
            end
            local energy = inputs.energy
            local sr = inputs.sr_remaining
            local sr_expired = type(sr) ~= "number" or sr <= 0
            if inputs.tf_ready == true and type(energy) == "number"
                and energy <= st.druid_guide.TF_ENERGY_SOD then
                -- S1. Tiger's Fury at or under 40 energy (King of the Jungle
                -- grants +60: 40 cannot overcap); the hold overlay carries the
                -- call, action stays nil.
                hold = true
                hold_text = "TIGER'S FURY"
            elseif inputs.berserk_ready == true and inputs.tf_ready == false then
                -- S2. Berserk immediately after Tiger's Fury (TF burned); the
                -- hold overlay carries the call, action stays nil.
                hold = true
                hold_text = "BERSERK"
            elseif cp >= 1 and sr_expired then
                -- S3. Savage Roar expired with combo points to spend; the hold
                -- overlay carries the call, action stays nil.
                hold = true
                hold_text = "SAVAGE ROAR"
            elseif inputs.clearcast == true then
                -- S4. Omen of Clarity proc: a free Shred, ahead of the finishers.
                action = "shred"
            elseif cp >= 5 and (type(inputs.rip_remaining) ~= "number"
                or inputs.rip_remaining <= 0 or inputs.tf_active == true) then
                -- S5. 5 CP Rip, preferred under Tiger's Fury (the King of the
                -- Jungle +15% snapshot lands on the fresh Rip). No energy gate:
                -- the guide shows the next action, the pooling shows on the
                -- energy tick bar.
                action = "rip"
            elseif inputs.mangle_remaining == nil then
                -- S6. An absent Mangle prompts it, ahead of Rake.
                action = "mangle"
            elseif type(inputs.rake_remaining) ~= "number"
                or inputs.rake_remaining <= 0 then
                -- S7. Rake expired (no verified SoD window, so expiry-only).
                action = "rake"
            elseif cp >= 5 then
                -- S8. Capped combo points with a healthy Rip and no TF snapshot
                -- to take: spend with Ferocious Bite (the Era-loop carry).
                action = "bite"
            else
                -- S9. Anything else: build with Shred, ungated (no verified
                -- SoD cost exists, so the builder is never withheld for energy).
                action = "shred"
            end
        elseif inputs.family == "ERA" then
            -- ERA cat chain; see the ERA APPENDIX in the module header.
            local cp = inputs.combo_points
            if type(cp) == "number" and cp >= 5 then
                -- E1. Capped combo points: spend with Ferocious Bite (no energy
                -- gate: the guide shows the next action, the pooling shows on
                -- the energy tick bar, the same convention as the TBC finishers).
                action = "bite"
            else
                -- E2. Anything else: build with Shred, ungated (no verified Era
                -- cost exists, so the builder is never withheld for energy).
                action = "shred"
            end
        elseif inputs.family == "WRATH" then
            -- WRATH cat chain; see the WRATH APPENDIX in the module header.
            local cp = inputs.combo_points
            if type(cp) ~= "number" then
                cp = 0
            end
            local energy = inputs.energy
            local sr = inputs.sr_remaining
            local sr_expired = type(sr) ~= "number" or sr <= 0
            if inputs.tf_ready == true and type(energy) == "number"
                and energy < st.druid_guide.TF_ENERGY_WRATH then
                -- W1. Tiger's Fury under 30 energy; the hold overlay carries
                -- the call, action stays nil.
                hold = true
                hold_text = "TIGER'S FURY"
            elseif inputs.berserk_ready == true and type(energy) == "number"
                and energy <= st.druid_guide.BERSERK_ENERGY_WRATH
                and type(inputs.tf_cd_remaining) == "number"
                and inputs.tf_cd_remaining
                    >= st.druid_guide.TF_CD_GATE_BERSERK_SECONDS then
                -- W2. Berserk at or under 85 energy once Tiger's Fury has been
                -- on cooldown for 15 s or more; the hold overlay carries the
                -- call, action stays nil.
                hold = true
                hold_text = "BERSERK"
            elseif cp >= 1 and sr_expired then
                -- W3. Savage Roar upkeep (>= 1 CP, expired); the hold overlay
                -- carries the call, action stays nil.
                hold = true
                hold_text = "SAVAGE ROAR"
            elseif inputs.clearcast == true then
                -- W4. Omen of Clarity proc: a free Shred, ahead of the finishers.
                action = "shred"
            elseif cp >= 5 and (type(inputs.rip_remaining) ~= "number"
                or inputs.rip_remaining <= 0) then
                -- W5. 5 CP with Rip expired: Rip, never clipped. No energy gate:
                -- the guide shows the next action, the pooling shows on the
                -- energy tick bar.
                action = "rip"
            elseif inputs.mangle_remaining == nil then
                -- W6. An absent Mangle prompts it - above Rake, whose ticks it
                -- multiplies; a running one never refreshes.
                action = "mangle"
            elseif type(inputs.rake_remaining) ~= "number"
                or inputs.rake_remaining <= 0 then
                -- W7. Rake expired, never clipped.
                action = "rake"
            elseif cp >= 5
                and type(inputs.rip_remaining) == "number"
                and inputs.rip_remaining >= st.druid_guide.FB_RIP_MIN_SECONDS
                and type(sr) == "number"
                and sr >= st.druid_guide.FB_SR_MIN_SECONDS
                and wrath_target_is_execute(inputs) then
                -- W8. The conditional Ferocious Bite: 5 CP with both Rip and
                -- Savage Roar healthy enough to survive the rebuild, inside
                -- the last-10-seconds execute window (mid-fight falls to
                -- Shred: the research removed Bite from the mid-fight
                -- rotation).
                action = "bite"
            else
                -- W9. Anything else: build with Shred (pooling shows on the
                -- energy tick bar; the bearweave branch is not built).
                action = "shred"
            end
        else
            -- FOREVER F1 (see the FOREVER APPENDIX in the module header), then
            -- the legacy rules 4-8 unchanged: every other family skips F1 on
            -- the family gate, and an unproven Shifting Power (nil/false, or
            -- unreadable energy) falls through to the maintenance chain.
            local rip_refresh = threshold(inputs.rip_refresh, st.druid_guide.RIP_REFRESH_DEFAULT)
            local rake_refresh = threshold(inputs.rake_refresh, st.druid_guide.RAKE_REFRESH_DEFAULT)
            if inputs.family == "FOREVER" and inputs.sp_ready == true
                and type(inputs.energy) == "number"
                and inputs.energy <= st.druid_guide.SP_ENERGY_FOREVER then
                -- F1. Shifting Power with room for its 40 energy: the hold
                -- overlay carries the call, action stays nil. UNCONFIRMED:
                -- the 60/40 values are beta-prose assumptions (no client
                -- source publishes the gain or the threshold); the call
                -- itself is gated behind the Shifting Power knowledge probe
                -- (sp_ready, proven via the GetSpellInfo name query - the
                -- only probe Forever exposes, since no spell id is
                -- published), so an unknown Shifting Power never calls.
                hold = true
                hold_text = "SHIFTING POWER"
            elseif type(inputs.rip_remaining) ~= "number" or inputs.rip_remaining <= rip_refresh then
                -- 4. Rip missing or inside its refresh window.
                action = "rip"
            elseif type(inputs.rake_remaining) ~= "number" or inputs.rake_remaining <= rake_refresh then
                -- 5. Rake missing or inside its refresh window.
                action = "rake"
            elseif inputs.mangle_remaining == nil then
                -- 6. An absent Mangle prompts it; a running one never does.
                action = "mangle"
            elseif type(inputs.combo_points) == "number" and inputs.combo_points >= 5 then
                -- 7. Combo points capped: spend with Ferocious Bite.
                action = "bite"
            else
                -- 8. Anything else: build with Shred.
                action = "shred"
            end
        end
    end
    -- Any other/unknown form: no action.

    out.action = action
    out.hold = hold
    out.hold_text = hold_text
    out.filler_slot = nil
    out.judge_slot = nil
    out.rotation_key = nil
    out.waiting_judgement = false
    return out
end

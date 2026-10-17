--=========================================================================================
-- Warrior next-action guide: pure decision engine, no WoW API and no clock.
--
-- The second provider for the frozen ST.<CLASS>.guide contract (nextaction_ui.lua's
-- header; the paladin ships the first). The live reads live in classes/warrior.lua
-- (ST.WARRIOR.gather_guide_inputs); this module only consumes the gathered inputs, so it
-- is unit-tested offline by tests/warrior_guide_state.lua.
--
-- FROZEN SPEC - display slots (ST.WARRIOR.guide.slots, ordered):
--   base set (5 of the 6 allowed, every family without a core reader):
--     op       Overpower     7384
--     execute  Execute       5308
--     slam     Slam          1464     (icon rank-resolved at post_init)
--     hs       Heroic Strike 78       (icon rank-resolved at post_init)
--     cleave   Cleave        845      (icon rank-resolved at post_init)
--   TBC set (6, the contract maximum): op, execute, slam, hs, bt, ww. The cleave
--   slot is replaced, not added past: cleave is the least-TBC-relevant slot (no
--   rule ever outputs "cleave" - the slot only ever showed the Cleave swipe, and
--   Cleave has no cooldown of its own on the classic line), while Bloodthirst and
--   Whirlwind are the TBC fury core. The cleave readers stay in the gather
--   (cost/queue/cooldown), so the RIDE path and a future slot re-add keep working.
--   Era set (6, the contract maximum): op, execute, slam, hs, bt, ww - the same
--   keys as TBC. Bloodthirst and Whirlwind are vanilla spells that exist on Era
--   (resolved through the same rank tables), so Era shares the TBC slot shape;
--   the cleave replacement reason and the reader retention above apply verbatim.
--   Wrath fury set (6): op, execute, slam, hs, bt, ww - the same keys as
--   TBC/Era. The fury priority (BT > WW > Slam-proc > Execute-demoted > HS
--   dump) names exactly these; the conditional Rend (only with Improved Rend,
--   no Bloodsurge, BT/WW not coming off CD) stays tracker-only (the Rend
--   debuff bar already covers it) with no guide slot. No target-count source
--   exists on the client, so the WW-first-on-2+ rule is documented, not built.
--   Wrath arms set (6): op, execute, rend, ms, bladestorm, hs. Bloodthirst /
--   Whirlwind / Cleave have no arms rule (arms never prompts them), Slam is
--   the deferred early-tier filler (readers kept, rule gated off, HS covers
--   the filler window), and Rend / Mortal Strike / Bladestorm take their
--   places. Spec rule (documented): Mortal Strike known = arms (Mortal
--   Strike ranks 12294 / 21551 / 21552 / 21553 / 25248 / 30330 / 47485 /
--   47486 per the Taste for Blood affected-spells list, wowhead.com/wotlk/
--   spell=56638). Slots are picked at post_init from the frozen spec probe;
--   a respec or rune change mid-session needs /reload (standard for slot
--   shapes; the engine flags freeze with the slots so the two never disagree
--   about which actions exist).
--   SoD set (6, ERA family + runes): execute, slam, hs, bt, ww, raging_blow.
--   Overpower is the least-SoD-relevant slot (unlisted in the SoD priority;
--   the dodge-window/cooldown readers stay for a future slot re-add), while
--   Raging Blow (402911, wowhead.com/classic/spell=402911, 8 s CD, no rage
--   cost) is the rune filler after WW. SoD detection (documented): st.family
--   == "ERA" and (Raging Blow 402911 or Consumed by Rage 425440,
--   wowhead.com/classic/spell=425440, known via api.is_spell_known). Hamstring
--   fishing, Death Wish / Rampage cooldowns, Sunder upkeep and Battle Shout
--   carry no slot (the six-contract is full) and are documented, not built.
--
-- FROZEN SPEC - inputs (all optional, nil never errors):
--   speed, swing_remaining, gcd_remaining    swing/GCD (api.get_time() domain)
--   rage, hs_cost, cleave_cost               rage and the on-next-attack costs
--   hs_queued, cleave_queued                 on-next-attack queue state
--   insufficient_rage                        the bar-colour shortfall flag
--   has_bloodsurge, slam_casting             Bloodsurge proc / Slam cast state
--   overpower_remaining                      dodge-window countdown (nil once over)
--   target_health_pct                        nil = unknown (no target / no answer)
--   execute_pct                              db.guide_execute_pct, default 20
--   bt_remaining, ww_remaining               Bloodthirst / Whirlwind cooldowns (TBC
--                                            and Era readers; both are vanilla
--                                            spells that exist on Era and resolve
--                                            through the same rank tables);
--                                            nil = no reader on this family; the
--                                            BT/WW rules require a known reading,
--                                            so nil never prompts
--   bt_cost, ww_cost                         rage costs through the current ranks;
--                                            nil falls back to the fixed costs
--                                            below (BT 30, WW 25 - the same on Era)
--   hs_rage_floor                            HS dump floor (rage to spare): 50 on TBC,
--                                            30 on Era, 50 on Wrath (TBC-carried,
--                                            in-game to confirm), 60 on SoD
--                                            (Consumed by Rage pooling); nil = no
--                                            floor (every other family)
--   core_reserve_window                      Era BT/WW buffer (2.5 s, the midpoint of
--                                            the 2-3 s ground-truth window); nil =
--                                            the 1.5 s TBC default below (Wrath fury
--                                            and SoD carry their family's default:
--                                            1.5 s on Wrath, 2.5 s on SoD)
--   execute_spam                             Era Execute spam below 20 % (true skips
--                                            the rule-2 core reservation); nil/false
--                                            keeps the TBC reservation. SoD feeds
--                                            true as well (Sudden Death dumps and
--                                            the sub-20 % spam never wait on the
--                                            core)
--   wrath_fury, wrath_arms                   Wrath branch flags (provider-fed from the
--                                            frozen spec probe; nil everywhere else,
--                                            so all other families keep the legacy
--                                            matrix byte-identically)
--   sod                                      SoD branch flag (ERA + runes; nil
--                                            elsewhere)
--   sudden_death                             Sudden Death proc active (aura 52437 on
--                                            Wrath, wowhead.com/wotlk/spell=52437;
--                                            440495 plus the literal name fallback on
--                                            SoD - in-game to confirm which SoD aura
--                                            id fires; nil = no proc)
--   tfb                                      Taste for Blood proc active (aura 60503,
--                                            wowhead.com/wotlk/spell=56638; nil = no
--                                            proc, so Overpower still needs its dodge
--                                            window; Rend-tick inference deferred)
--   rend_remaining, rend_duration            Rend debuff window (nil = missing /
--                                            unknown, which prompts like the druid
--                                            rip/rake nil rule); rend_refresh is the
--                                            reapply threshold, default 3 (wotlk Rend
--                                            47465, 15 s duration,
--                                            wowhead.com/wotlk/spell=47465;
--                                            in-game to confirm the window)
--   ms_remaining, ms_duration                Mortal Strike cooldown (6 s,
--                                            wowhead.com/wotlk/spell=47486; nil =
--                                            no reader, never prompts - the known-
--                                            reading requirement, like BT/WW)
--   bladestorm_remaining, bladestorm_duration
--                                            Bladestorm cooldown (63784,
--                                            wowhead.com/wotlk/spell=63784; swipe
--                                            fallback 90 s, NEEDS IN-CLIENT
--                                            CONFIRMATION)
--   bladestorm_known                         Bladestorm talented (fresh
--                                            api.is_spell_known read; nil/false
--                                            never prompts an untalented slot)
--   raging_blow_remaining, raging_blow_duration
--                                            Raging Blow cooldown (8 s,
--                                            wowhead.com/classic/spell=402911;
--                                            nil = no reader)
--   execute_spam                             Era Execute spam below 20 % (true skips
--                                            the rule-2 core reservation); nil/false
--                                            keeps the TBC reservation
--   hs_cancel_cue                            TBC HS-cancel cue (provider-fed true only
--                                            on TBC): when rule 2 fires Execute with
--                                            HS/Cleave already queued, the overlay
--                                            reads CANCEL (cancel the queued
--                                            on-next-attack, don't spend its rage)
--                                            instead of riding it; nil everywhere
--                                            else (byte-identical)
--   victory_rush                             Forever Victory Rush ready (provider-fed
--                                            true only on FOREVER via the
--                                            family + knowledge + usable probe,
--                                            UNCONFIRMED id): Execute at any health,
--                                            like the SoD Sudden Death bypass
--                                            (still behind the OP window, still
--                                            before Slam/BT/WW); nil everywhere
--                                            else (byte-identical)
--   op_remaining, execute_remaining, slam_remaining, hs_remaining, cleave_remaining
--                                            client cooldowns; gather filters the GCD
--                                            echo (duration <= 1.51 s) before they
--                                            reach here; the rule matrix reads
--                                            op_remaining / execute_remaining.
--                                            ms_remaining / bladestorm_remaining /
--                                            raging_blow_remaining ride the same
--                                            filter; rend_remaining is a debuff
--                                            window, not a cooldown.
--   reaction                                 optional, default 0.1
--
-- FROZEN SPEC - rule order (first match wins; the legacy rules keep their numbers,
-- the branch rules slot between them as lettered inserts):
--   A. (arms only) Rend upkeep: rend_remaining nil or <= rend_refresh ->
--      action "rend". Nil prompts (missing Rend, like the druid rip/rake nil
--      rule); exactly the threshold refreshes. Inert everywhere else (no Rend
--      upkeep outside arms).
--   B. (arms only) Execute: Sudden Death active (sudden_death) OR target below
--      the threshold, with Execute off cooldown -> action "execute". Outranks
--      Overpower (rule 1): SD-Execute above 20 % and the sub-20 % spam both
--      come first; below 20 % almost exclusively Execute except OP if
--      insufficient rage. No core reservation (arms runs no BT/WW core).
--   1. the Overpower window is active (overpower_remaining > 0) - or, on arms,
--      the Taste for Blood proc is active (tfb) - and Overpower is off
--      cooldown -> action "op". A window of exactly 0 is already over. Skipped
--      on SoD (no op slot there; the dodge readers stay for a future re-add).
--   2. target_health_pct is known and < execute_pct and Execute is off cooldown and
--      the core does not claim the next GCD (see the reservation below) -> action
--      "execute". A Sudden Death proc (sod and sudden_death) or a ready Victory
--      Rush (victory_rush, Forever only) bypasses the health gate entirely
--      (Execute regardless of target health, still before Slam/BT/WW). When the
--      TBC HS-cancel cue is armed (hs_cancel_cue) and HS/Cleave is already
--      queued, the prompt carries hold = true, hold_text = "CANCEL": cancel the
--      queued on-next-attack before it spends its rage (tbc_minmax.md), instead
--      of the rule-4 RIDE. Era spam (execute_spam) skips the reservation: below
--      20 % the guide spams Execute even when BT/WW is ready/soon, unlike the
--      TBC gate which never spends at the core's expense. SoD feeds
--      execute_spam as well. Skipped on arms (rule B above) and on wrath fury
--      (rule F below demotes it there).
--   3. has_bloodsurge and not slam_casting -> action "slam". On wrath fury the
--      delay gate applies: withheld while Bloodthirst or Whirlwind is ready
--      (the 5 s proc window covers the wait - BT/WW first, Slam woven between).
--      Skipped on arms (no slam slot; the early-tier filler is deferred and HS
--      covers the window). Inert on TBC and
--      Era: Blood Surge is a WotLK talent proc (aura 46916), so the aura read
--      never fires on 2.5.6 or 1.15.9 and this rule can never match there; the
--      logic is untouched. SoD's Blood Surge rune shares aura 46916, so the
--      same rule serves SoD (Execute-SD above it, BT/WW below it, matching the
--      SoD priority).
--   4. hs_queued or cleave_queued -> no action, hold = true, hold_text = "RIDE" (the
--      guide rides the queue the player already placed).
--   5. Bloodthirst is known (a TBC, Era, Wrath-fury or SoD reader exists) and ready
--      (bt_remaining <= 0) -> action "bt". Skipped on arms (no BT rule there).
--   6. Whirlwind is known and ready (ww_remaining <= 0) -> action "ww".
--      Skipped on arms. (No target-count source exists, so the WW-first-on-2+
--      fury rule is documented, not built.)
--   F. (wrath fury only) Execute demotion: target below the threshold, Execute
--      off cooldown, BT/WW both cooling (neither ready), rage at/above the
--      floor and the core claiming nothing next (the rule-2 reservation with
--      the Execute spend) -> action "execute". Lowest priority even in Execute
--      phase: only with excess rage, no BT/WW up and everything else on CD.
--   G. (SoD only) Raging Blow: off cooldown -> action "raging_blow" (no rage
--      gate: the ability costs none). Sits after WW, before the HS dump,
--      matching the SoD priority.
--   H. (arms only) Bladestorm: bladestorm_known and off cooldown ->
--      action "bladestorm". Ordered by the earlier rules: Rend maintained
--      (rule A fires first when it lapses), no SD proc pending (rule B fires
--      first), Overpower current in its TfB cycle (rule 1 fires first). The
--      OP-used-in-cycle guard is deferred (no TfB cycle state yet).
--   I. (arms only) Mortal Strike: known and ready (ms_remaining <= 0) ->
--      action "ms" (the 6 s filler).
--   7. rage is known:
--        * insufficient (rage < hs_cost when both are known, else the module's
--          insufficient_rage flag) -> no action, hold = true, hold_text = "HOLD";
--        * else, when the floor is set (hs_rage_floor: 50 TBC, 30 Era) and rage
--          is below it -> no action and no hold: rage is being pooled for
--          Bloodthirst/Whirlwind, not missing;
--        * else, when the core claims the next GCD (ready now, or landing
--          inside the reserve window - 1.5 s TBC, 2.5 s Era via
--          core_reserve_window - with too little rage left after the HS spend
--          to cover its cost) -> no action and no hold, for the same reason;
--        * else hs_cost known, rage >= hs_cost and the swing window allows queueing
--          -> action "hs";
--        * else falls through to rule 8.
--      The swing window mirrors the paladin engine's rel_swing landmark (nextaction.lua:
--      swing_remaining - reaction / 2): a prompt inside the final reaction half-step of
--      the swing cannot ride a swing the player can still react to, so it is withheld.
--      Heroic Strike is off the GCD, so a running gcd_remaining never closes the window
--      (the input rides the same landmark set for tuning).
--   8. no action.
--   "off cooldown" = the *_remaining input is nil or <= 0. The BT/WW/MS rules are
--   the exception: they additionally require a known reading (type() == "number"),
--   so a family without the core readers keeps the legacy six-rule behaviour
--   exactly. Bladestorm additionally requires bladestorm_known (an untalented
--   slot must stay dark). The family gating lives in the provider
--   (classes/warrior.lua feeds the bt/ww inputs, the floors, the Era window,
--   the Era/SoD spam flag and the Wrath/SoD branch flags per family/spec);
--   this engine stays family-agnostic and pure.
--
--   Retail (12.x) inertness: st.family == "RETAIL" short-circuits evaluate to the
--   empty display shape before any rule below. The inert stand-in never reports a
--   swing, but target health (rule 2), the Blood Surge aura (rule 3), the queue
--   flags (rule 4) and rage/costs (rule 7, including its HOLD shortfall) all answer
--   on Retail, so those rules would prompt with no swing at all. Every other
--   family - including Forever, which swings - runs the matrix above unchanged; a
--   nil family (offline callers that predate it) keeps the old behaviour too.
--
-- Output: the frozen display fields are overwritten on every call:
--   action, hold, hold_text, filler_slot = nil, judge_slot = nil, rotation_key = nil,
--   waiting_judgement = false.
--=========================================================================================
local _, st = ...

st.warrior_guide = st.warrior_guide or {}

-- Rule constants (frozen; the options panel exposes only the execute threshold).
st.warrior_guide.EXECUTE_PCT_DEFAULT = 20
st.warrior_guide.REACTION_DEFAULT = 0.1

-- TBC fury core constants (sourced ground truth for the 2.5.6 fury priority:
-- Bloodthirst on CD > Whirlwind on CD > Heroic Strike dump only with rage to
-- spare, Execute below 20 % instead of HS and never at BT/WW's expense).
-- Bloodthirst costs 30 rage and Whirlwind 25 on TBC (fixed costs, used only when
-- the provider's live cost read is nil); Execute's base spend is 15 (it drains
-- extra rage into damage on top). The reserve window is one GCD: a core ability
-- landing inside it needs its rage now, so the dump must not take it.
-- Era (1.15.9) shares the costs (BT 30 / WW 25 / Execute 15 are vanilla values)
-- but feeds its own floor (30) and window (2.5 s) through the inputs above, and
-- Execute spam (no reservation) through execute_spam. Wrath fury carries the TBC
-- 50-rage floor and the 1.5 s default window (in-game to confirm); SoD feeds
-- floor 60 (Consumed by Rage pooling) with the Era 2.5 s window and spam.
local BT_RAGE_COST = 30
local WW_RAGE_COST = 25
local EXECUTE_RAGE_SPEND = 15
local CORE_RESERVE_WINDOW = 1.5

-- Rend upkeep window (arms rule A): reapply inside the final 3 s, never early.
-- Provisional (the guides only say "maintain / don't reapply early"); Rend's 15 s
-- duration is the wotlk 47465 value above. In-game to confirm.
local REND_REFRESH_DEFAULT = 3

-- Tactical Mastery rage cap (tbc_minmax.md: cancel queued HS/Cleave before
-- Execute/stance swap, Tactical Mastery keeps at most 25 rage across the swap,
-- Sweeping Strikes costs 30). Pure and family-agnostic; the stance-event
-- wiring is deferred (no stance reads exist in the provider yet), so no rule
-- consumes this today - it pins the 25-cap maths for that wiring.
st.warrior_guide.TACTICAL_MASTERY_RAGE_CAP = 25

-- Rage surviving a stance swap: at most the cap with Tactical Mastery, nothing
-- without it (an unknown talent reads as no talent). Unknown rage answers nil.
function st.warrior_guide.rage_after_stance_swap(rage, tactical_mastery)
    if type(rage) ~= "number" or rage ~= rage then
        return nil
    end
    if rage < 0 then
        return 0
    end
    if tactical_mastery ~= true then
        return 0
    end
    if rage > st.warrior_guide.TACTICAL_MASTERY_RAGE_CAP then
        return st.warrior_guide.TACTICAL_MASTERY_RAGE_CAP
    end
    return rage
end

-- Slam safe-window verdict (brainstorm W4: the Slam-safe band on the mainhand
-- bar reads green when the cast lands clean, red when it resets into the
-- deadzone). "clean" when the cast completes before the next swing lands (the
-- boundary still lands clean), "clash" when the swing lands mid-cast, nil when
-- either clock is unknown. swing_resets == false is the Forever client
-- (Forever Slam never resets the swing, so the cast cannot collide): always
-- "clean". A nil swing_resets keeps the classic assumption.
function st.warrior_guide.slam_cast_safety(cast_remaining, swing_remaining, swing_resets)
    if type(cast_remaining) ~= "number" or type(swing_remaining) ~= "number" then
        return nil
    end
    if cast_remaining ~= cast_remaining or swing_remaining ~= swing_remaining then
        return nil
    end
    if swing_resets == false then
        return "clean"
    end
    if cast_remaining <= swing_remaining then
        return "clean"
    end
    return "clash"
end

-- "Off cooldown": nothing left to wait for. gather filters the GCD echo before the
-- inputs reach this module, so a positive value is a real ability cooldown.
local function is_off_cooldown(remaining)
    return not (type(remaining) == "number" and remaining > 0)
end

-- The swing window (rule 5): the paladin engine's rel_swing landmark, i.e. the swing
-- must still be more than a reaction half-step away for a queue prompt to be actionable.
local function swing_allows_queue(swing_remaining, reaction)
    if type(swing_remaining) ~= "number" then
        return false
    end
    if type(reaction) ~= "number" then
        reaction = st.warrior_guide.REACTION_DEFAULT
    end
    return swing_remaining > reaction / 2
end

-- One core ability's claim on the next GCD: ready now (it takes the GCD, so a
-- dump must never precede it), or landing inside the reserve window with too
-- little rage left after the dump's spend to cover its cost. A nil remaining
-- means this family has no reader, so the ability never claims. A nil window
-- falls back to the TBC 1.5 s default (the Era 2.5 s buffer arrives through
-- inputs.core_reserve_window).
local function core_claims_next_gcd(remaining, cost, cost_default, rage, spend, window)
    if type(remaining) ~= "number" then
        return false
    end
    if remaining <= 0 then
        return true
    end
    if type(cost) ~= "number" then
        cost = cost_default
    end
    if type(window) ~= "number" then
        window = CORE_RESERVE_WINDOW
    end
    return type(rage) == "number" and type(spend) == "number"
        and remaining <= window and rage - spend < cost
end

-- True when Bloodthirst or Whirlwind needs the rage/GCD next: the shared
-- reservation behind the Execute gate (rule 2, TBC only - Era spam skips it)
-- and the HS guard (rule 7, both families with their own window).
local function core_reserves_rage(inputs, spend)
    local rage = inputs.rage
    local window = inputs.core_reserve_window
    if type(window) ~= "number" then
        window = CORE_RESERVE_WINDOW
    end
    return core_claims_next_gcd(inputs.bt_remaining, inputs.bt_cost, BT_RAGE_COST,
            rage, spend, window)
        or core_claims_next_gcd(inputs.ww_remaining, inputs.ww_cost, WW_RAGE_COST,
            rage, spend, window)
end

-- Pure: one engine tick. Reads `inputs`, writes the frozen display fields into the
-- caller-owned `out` table and returns it. See the module header for the rule matrix.
function st.warrior_guide.evaluate(inputs, out)
    inputs = inputs or {}
    if type(out) ~= "table" then
        out = {}
    end

    if st.family == "RETAIL" then
        -- Retail (12.x): no live swing exists (see the header), so no rule may
        -- prompt - not an action, not a HOLD/RIDE overlay.
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

    -- Branch flags (provider-fed; nil on every legacy family, so the legacy
    -- matrix below runs byte-identically there).
    local wrath_fury = inputs.wrath_fury == true
    local wrath_arms = inputs.wrath_arms == true
    local sod = inputs.sod == true
    local sd = inputs.sudden_death == true

    local execute_pct = inputs.execute_pct
    if type(execute_pct) ~= "number" then
        execute_pct = st.warrior_guide.EXECUTE_PCT_DEFAULT
    end

    if wrath_arms then
        local rend_refresh = inputs.rend_refresh
        if type(rend_refresh) ~= "number" then
            rend_refresh = REND_REFRESH_DEFAULT
        end
        local rend_remaining = inputs.rend_remaining
        if type(rend_remaining) ~= "number" or rend_remaining <= rend_refresh then
            -- A. Rend upkeep: missing (nil) or inside its refresh window.
            action = "rend"
        end
    end

    if action == nil and wrath_arms
        and (sd or (type(inputs.target_health_pct) == "number"
            and inputs.target_health_pct < execute_pct))
        and is_off_cooldown(inputs.execute_remaining) then
        -- B. Arms Execute: Sudden Death (any health) or sub-20 % spam, ahead of
        -- Overpower. No core reservation (arms runs no BT/WW core).
        action = "execute"
    end

    if action == nil and not sod
        and ((type(inputs.overpower_remaining) == "number"
                and inputs.overpower_remaining > 0)
            or (wrath_arms and inputs.tfb == true))
        and is_off_cooldown(inputs.op_remaining) then
        -- 1. Overpower: the dodge window is live - or, on arms, Taste for Blood
        -- allows it without a dodge - and the ability itself is ready. Skipped
        -- on SoD (no op slot there).
        action = "op"
    elseif action == nil and not wrath_arms then
        if not wrath_fury and ((type(inputs.target_health_pct) == "number"
            and (inputs.target_health_pct < execute_pct
                or (sod and sd)))
            or inputs.victory_rush == true)
            and is_off_cooldown(inputs.execute_remaining)
            and (inputs.execute_spam == true
                or not core_reserves_rage(inputs, EXECUTE_RAGE_SPEND)) then
            -- 2. Execute range, unless Bloodthirst/Whirlwind needs the rage/GCD next
            -- (Execute instead of HS, never at the core's expense). Era spam
            -- skips the reservation: below 20 % the guide spams Execute even
            -- when BT/WW is ready/soon, unlike the TBC gate. SoD feeds the spam
            -- flag too, and Sudden Death bypasses the health gate (Execute at
            -- any health, still ahead of Slam/BT/WW). Victory Rush (Forever
            -- only) bypasses the health gate the same way: the provider only
            -- feeds it on FOREVER, so every other family keeps the legacy gate
            -- byte-identically. With the TBC HS-cancel cue armed, a queued
            -- HS/Cleave turns the prompt into CANCEL (kill the queued spend
            -- before it eats the Execute rage) instead of the rule-4 RIDE.
            -- Skipped on arms (rule B) and on wrath fury (rule F demotes it
            -- below BT/WW/Slam).
            action = "execute"
            if inputs.hs_cancel_cue == true
                and (inputs.hs_queued == true or inputs.cleave_queued == true) then
                hold = true
                hold_text = "CANCEL"
            end
        elseif inputs.has_bloodsurge == true and not inputs.slam_casting
            and (not wrath_fury
                or ((type(inputs.bt_remaining) ~= "number"
                        or inputs.bt_remaining > 0)
                    and (type(inputs.ww_remaining) ~= "number"
                        or inputs.ww_remaining > 0))) then
            -- 3. Bloodsurge: an instant Slam is worth more than anything below.
            -- On wrath fury the delay gate withholds it while BT/WW is up (the
            -- 5 s window covers the wait); the gate sits in the branch
            -- condition (not the body) so a withheld Slam falls through to the
            -- core below instead of swallowing it.
            action = "slam"
        elseif inputs.hs_queued == true or inputs.cleave_queued == true then
            -- 4. An on-next-attack ability is already queued: ride it.
            hold = true
            hold_text = "RIDE"
        elseif type(inputs.bt_remaining) == "number" and inputs.bt_remaining <= 0 then
            -- 5. Bloodthirst: a core reader is present (TBC, Era, wrath fury or
            -- SoD) and ready. The known-reading requirement keeps families
            -- without the reader on the legacy path (nil never prompts). The
            -- GCD is intentionally not gated: the prompt leads the GCD and the
            -- player fires as it clears.
            action = "bt"
        elseif type(inputs.ww_remaining) == "number" and inputs.ww_remaining <= 0 then
            -- 6. Whirlwind, same shape, below Bloodthirst.
            action = "ww"
        end
    end

    if action == nil and not hold then
        if inputs.hs_queued == true or inputs.cleave_queued == true then
            -- 4. (branch path) An on-next-attack ability is already queued: ride
            -- it. The base path rides inside the block above; arms and wrath
            -- fury skip that block (no base rules there) and ride here instead.
            hold = true
            hold_text = "RIDE"
        elseif wrath_fury
            and type(inputs.target_health_pct) == "number"
            and inputs.target_health_pct < execute_pct
            and is_off_cooldown(inputs.execute_remaining)
            and (type(inputs.bt_remaining) ~= "number"
                or inputs.bt_remaining > 0)
            and (type(inputs.ww_remaining) ~= "number"
                or inputs.ww_remaining > 0)
            and not (type(inputs.hs_rage_floor) == "number"
                and type(inputs.rage) == "number"
                and inputs.rage < inputs.hs_rage_floor)
            and not core_reserves_rage(inputs, EXECUTE_RAGE_SPEND) then
            -- F. Wrath fury Execute demotion: only below the threshold, with
            -- BT/WW both cooling, rage at/above the floor and the core claiming
            -- nothing next. Lowest priority even in Execute phase. Every gate
            -- sits in the branch condition so a withheld Execute falls through
            -- to the HS dump below instead of swallowing it.
            action = "execute"
        elseif sod and is_off_cooldown(inputs.raging_blow_remaining) then
            -- G. SoD Raging Blow: the rune filler after WW (costs no rage).
            action = "raging_blow"
        elseif wrath_arms and inputs.bladestorm_known == true
            and is_off_cooldown(inputs.bladestorm_remaining) then
            -- H. Arms Bladestorm (Rend maintained, no SD pending and Overpower
            -- current by the order above).
            action = "bladestorm"
        elseif wrath_arms and type(inputs.ms_remaining) == "number"
            and inputs.ms_remaining <= 0 then
            -- I. Arms Mortal Strike filler (known reading required, like BT/WW).
            action = "ms"
        elseif type(inputs.rage) == "number" then
            -- 7. Heroic Strike when rage covers it, clears the floor (50 TBC,
            -- 30 Era) and the core reservation (1.5 s TBC, 2.5 s Era), and the
            -- swing window is open; a known shortfall shows HOLD instead, while
            -- a floor/reservation withhold falls through silently (rage is
            -- pooled, not missing).
            local cost = inputs.hs_cost
            local insufficient
            if type(cost) == "number" then
                insufficient = inputs.rage < cost
            else
                insufficient = inputs.insufficient_rage == true
            end
            if insufficient then
                hold = true
                hold_text = "HOLD"
            else
                local floor = inputs.hs_rage_floor
                local floored = type(floor) == "number" and inputs.rage < floor
                if type(cost) == "number" and inputs.rage >= cost
                    and not floored
                    and not core_reserves_rage(inputs, cost)
                    and swing_allows_queue(inputs.swing_remaining, inputs.reaction) then
                    action = "hs"
                end
            end
        end
    end
    -- 8. Anything else: no action.

    out.action = action
    out.hold = hold
    out.hold_text = hold_text
    out.filler_slot = nil
    out.judge_slot = nil
    out.rotation_key = nil
    out.waiting_judgement = false
    return out
end

--=========================================================================================
-- Rogue next-action guide: pure decision engine, no WoW API and no clock.
--
-- The sixth provider's decision model for the frozen ST.<CLASS>.guide contract
-- (nextaction_ui.lua's header; the paladin ships the first provider, the warrior
-- the second, the druid the third, the shaman the fourth, the hunter the fifth).
-- The live reads will live in classes/rogue.lua (ST.ROGUE.gather_guide_inputs -
-- owned by the parallel skeleton lane); this module only consumes the gathered
-- inputs, so it is unit-tested offline by tests/rogue_guide_state.lua.
--
-- Evidence (bench/rogue_research_2026-10-19.md, bench/rogue_deep_2026-10-19.md):
--   pooling  rogue_research §1.3: never pool above 65 pre-tick / 85 post-tick;
--            Relentless Strikes refunds 25 on finishers - finisher BEFORE the tick
--            that would cap you. TICK 20 / 2 s is Era+TBC CONFIRMED (§§1.1/1.3);
--            retail pooling is phase-based, not tick-based (§1.6).
--   rupture  rogue_research §1.3: Rupture > Eviscerate generally; Eviscerate for
--            dying targets / spare CP. Era: Eviscerate at any CP if the target is
--            about to die (§1.1). Only sourced Rupture duration is the 1CP 8 s
--            row (§5.2); the full per-CP table is UNCONFIRMED.
--   envenom  rogue_research §3.5: the rules DIFFER per client - never share one
--            Envenom rule. TBC: only on dying targets (consumes stacks, mid-fight
--            DPS loss). WotLK sin: maintain the buff, let it EXPIRE before
--            re-apply unless energy-capping. Retail sin: chain deliberately.
--            Forever beta: Eviscerate dump, no Envenom prompt. SoD (ERA family):
--            deferred - the ERA dying_only rule under-prompts there (safe).
--   ea       rogue_research §1.3: Imp-EA 100%-uptime juggle (refresh before
--            falloff; 2-5 CP SnDs between). No sourced falloff window: the 3 s
--            default below NEEDS IN-CLIENT CONFIRMATION.
--   shiv     rogue_research §1.3/§1.4: Shiv keeps Deadly stacks alive / stacks the
--            OH on demand. Watch-list window: Shiv-ready when <2 s to falloff
--            (rogue_research §4).
--   tea      rogue_deep §2.3: Thistle Tea item cue on low energy (Sno tracks Tea
--            on the PvE cooldown bar). No sourced energy threshold: the default
--            below NEEDS IN-CLIENT CONFIRMATION.
--
-- FROZEN SPEC - display slots (ST.ROGUE.guide.slots, owned by the skeleton lane;
-- suggested keys - this engine only emits these action names):
--   builder   the family builder (Sinister Strike / Backstab / Mutilate)
--   rupture   Rupture
--   eviscerate
--             Eviscerate
--   envenom   Envenom (per-client rule below)
--   expose    Expose Armor (EA-duty only)
--   shiv      Shiv (Deadly upkeep)
--   tea       Thistle Tea (item deficit cue)
-- Labels (skeleton lane): labels = { hold = "POOL", ride = "NOW" } - the HOLD
-- overlay text below is already explicit, so the labels only cover fallbacks.
--
-- FROZEN SPEC - inputs (all optional, nil never errors):
--   family                                   compat.lua's st.family ("ERA", "TBC",
--                                            "WRATH", "FOREVER", "RETAIL", ...);
--                                            selects the pooling band and the
--                                            Envenom rule. Unknown (or nil) runs
--                                            no client-specific rule: Envenom
--                                            never prompts and pooling stays
--                                            silent (never a guessed verdict).
--   energy_now, energy_tick_in, max_energy   energy + seconds to the next 20-tick
--                                            (api.get_time() domain; the provider
--                                            converts); max_energy default 100
--                                            (Vigor +10 arrives through this input)
--   cp                                       combo points (nil = unreadable)
--   ttd                                      target seconds-to-die, NUMERIC INPUT
--                                            ONLY (Round 2 wires the druid-D4-EMA
--                                            reuse; this module never reads
--                                            units/health). nil = unknown. MUST be
--                                            live-provenance or EMA velocity -
--                                            never the enemy_swing 2.0 s fallback
--                                            (M7 corollary, rogue_readiness §4).
--   rupture_remains, rupture_refresh        Rupture seconds / refresh window
--                                            (default 4 - NEEDS IN-CLIENT
--                                            CONFIRMATION; no rogue source).
--   rupture_min_ttd                          TTD at/below which Rupture cannot pay
--                                            (default 8 = the one sourced Rupture
--                                            duration, 1CP 8 s, §5.2; the per-CP
--                                            table NEEDS IN-CLIENT CONFIRMATION).
--   finisher_min_cp                          CP needed for a planned finisher
--                                            (default 5 - the 5-CP Rupture /
--                                            Eviscerate / Envenom shape on every
--                                            classic-line client).
--   deadly_stacks                            Deadly Poison stacks (nil = unknown)
--   envenom_buff_remains                     Envenom buff seconds (nil = absent or
--                                            unanswered - prompts like the druid
--                                            rip/rake nil rule)
--   ea_duty, ea_remains, ea_refresh          Imp-EA duty flag + Expose Armor
--                                            seconds + refresh window (default 3 -
--                                            NEEDS IN-CLIENT CONFIRMATION).
--   shiv_ready, deadly_remaining,            Shiv usability + Deadly seconds to
--   shiv_refresh                             falloff + refresh window (default 2,
--                                            rogue_research §4 watch-list).
--   tea_ready, tea_energy_max                Thistle Tea usability + the low-energy
--                                            line (default 40 - NEEDS IN-CLIENT
--                                            CONFIRMATION).
--   inputs_unknown                           explicit provider-owned M6 bit: true means
--                                            the live reads are unusable (or the secret
--                                            regime makes the auras unreadable), so no
--                                            rule may emit a verdict - the frame renders
--                                            "..." instead (no advice beats wrong advice).
--   pool_pre, pool_post                      optional band override (options tuning;
--                                            defaults come from POOL_BANDS below).
--
-- FROZEN SPEC - rule order (first match wins; exactly these rules):
--   0. unknown: inputs_unknown is true, or energy_now/cp is unusable -> out.unknown =
--      true, no action, no hold (the caller shows "..." - no advice beats wrong advice,
--      M6).
--   1. EA duty: ea_duty and (ea_remains nil or <= ea_refresh) -> "expose".
--      Nil prompts (missing upkeep, like the druid rip/rake nil rule).
--   2. Shiv: shiv_ready with deadly falloff imminent
--      (deadly_remaining <= shiv_refresh) -> "shiv". A nil clock never prompts
--      (H4: ambiguous timing hides, never guesses).
--   3. Envenom: the per-client rule (ENVENOM_RULES - never shared):
--      ERA/TBC dying_only (ttd <= ttd_max, cp >= min_cp, stacks >= min_stacks);
--      WRATH let_expire (cp + 5 stacks prove it, buff active withholds unless
--      energy would cap); FOREVER never (beta dumps Eviscerate); RETAIL chain
--      (cp >= min_cp unless stacks are proven empty).
--   4. dying-target dump: ttd known <= rupture_min_ttd and cp >= 1 ->
--      "eviscerate" (Era any-CP rule, §1.1).
--   5. planned finisher: cp >= finisher_min_cp -> finisher_for_ttd on the TTD:
--      unknown TTD never guesses (nil); TTD at/below rupture_min_ttd ->
--      "eviscerate" (the target dies before Rupture pays); Rupture missing or
--      inside its refresh window -> "rupture"; otherwise -> "eviscerate".
--   6. Thistle Tea: tea_ready and energy_now <= tea_energy_max -> "tea".
--   7. pool-vs-spend (pool_verdict): "spend" -> action "builder"; "pool" ->
--      hold = true, hold_text = "POOL"; nil (no band for this client - RETAIL
--      pools by phase, not by tick) -> silent.
--   8. no action.
--
-- Output: the frozen display fields are overwritten on every call:
--   action, hold, hold_text, filler_slot = nil, judge_slot = nil,
--   rotation_key = nil, waiting_judgement = false, unknown = bool.
--=========================================================================================
local _, st = ...

st.rogue_guide = st.rogue_guide or {}

-- Classic tick cadence: 20 energy / 2 s on the classic line (Era + TBC CONFIRMED,
-- rogue_research §§1.1/1.3). Retail is phase-based (rogue_research §1.6).
st.rogue_guide.TICK_ENERGY_DEFAULT = 20
st.rogue_guide.MAX_ENERGY_DEFAULT = 100

-- Pooling bands per client, as DATA (never bare constants): never pool above
-- `pre` with a tick coming, never sit above `post` (rogue_research §1.3, TBC
-- CONFIRMED). ERA/WRATH/FOREVER carry the TBC values - NEEDS IN-CLIENT
-- CONFIRMATION (same 20/2 s engine presumed, not sourced). RETAIL is nil:
-- phase-based pooling has no tick line.
st.rogue_guide.POOL_BANDS = {
    ERA     = { pre = 65, post = 85 },
    TBC     = { pre = 65, post = 85 },
    WRATH   = { pre = 65, post = 85 },
    FOREVER = { pre = 65, post = 85 },
}

-- Envenom rules per client, as DATA (rogue_research §3.5 - NEVER one shared
-- rule; each family owns its table, even where the fields coincide, so a tuning
-- pass cannot silently recouple them):
--   dying_only TBC CONFIRMED (§1.3): only on dying targets (consumes stacks).
--              ERA carries the same shape (combat dumps Eviscerate; SoD
--              mid-fight Envenom is DEFERRED - this rule under-prompts there).
--   let_expire WotLK-sin CONFIRMED (§1.4): buff active withholds re-apply
--              unless energy would cap waiting.
--   never      Forever beta (§1.5): the beta rotation dumps Eviscerate.
--   chain      Retail-sin CONFIRMED (§1.6): 5+CP chaining while the buff rides.
st.rogue_guide.ENVENOM_RULES = {
    ERA     = { mode = "dying_only", ttd_max = 8, min_cp = 5, min_stacks = 1 },
    TBC     = { mode = "dying_only", ttd_max = 8, min_cp = 5, min_stacks = 1 },
    WRATH   = { mode = "let_expire", min_cp = 4, min_stacks = 5 },
    FOREVER = { mode = "never" },
    RETAIL  = { mode = "chain", min_cp = 5 },
}

-- Refresh / threshold defaults. SHIV 2 s is the §4 watch-list window;
-- RUPTURE 4 s mirrors the druid rip/rake refresh, EA 3 s the warrior Rend
-- window, TEA 40 the deficit cue - all three NEED IN-CLIENT CONFIRMATION
-- (no rogue source). RUPTURE_MIN_TTD 8 s is the one sourced Rupture duration
-- (1CP 8 s, rogue_research §5.2); the per-CP table is UNCONFIRMED.
st.rogue_guide.RUPTURE_REFRESH_DEFAULT = 4
st.rogue_guide.RUPTURE_MIN_TTD_DEFAULT = 8
st.rogue_guide.FINISHER_MIN_CP_DEFAULT = 5
st.rogue_guide.EA_REFRESH_DEFAULT = 3
st.rogue_guide.SHIV_REFRESH_DEFAULT = 2
st.rogue_guide.TEA_ENERGY_MAX_DEFAULT = 40

-- Numeric and usable: the NaN-safe number check every rule below funnels through.
local function is_num(x)
    return type(x) == "number" and x == x
end

-- Pooling band for a family token (nil for RETAIL / unknown: no tick line there,
-- so pool_verdict stays silent instead of guessing).
function st.rogue_guide.band_for(family)
    return st.rogue_guide.POOL_BANDS[family]
end

-- Pool-vs-spend verdict: "spend" (a finisher/builder before the tick that would
-- cap you - the Relentless-Strikes-25 timing, §1.3), "pool" (hold for the tick),
-- nil (no band for this client, or an unusable energy read - never a guess).
-- tick_in unknown degrades to "pool": pooling wastes nothing by itself, while a
-- timed spend without a clock would be a guess.
function st.rogue_guide.pool_verdict(energy, tick_in, band, max_energy)
    if not is_num(energy) then
        return nil
    end
    if type(band) ~= "table" then
        return nil
    end
    if not is_num(band.pre) or not is_num(band.post) then
        return nil
    end
    if not is_num(max_energy) then
        max_energy = st.rogue_guide.MAX_ENERGY_DEFAULT
    end
    if energy >= max_energy then
        return "spend"
    end
    if energy + st.rogue_guide.TICK_ENERGY_DEFAULT > max_energy then
        return "spend"
    end
    if energy >= band.post then
        return "spend"
    end
    if energy >= band.pre then
        if is_num(tick_in) then
            return "spend"
        end
        return "pool"
    end
    return "pool"
end

-- Rupture-vs-Eviscerate decider on a NUMERIC TTD input: "rupture",
-- "eviscerate", or nil (unknown TTD or CP below the planned-finisher line -
-- never a guessed finisher; the dying-target any-CP dump lives in evaluate).
function st.rogue_guide.finisher_for_ttd(cp, ttd, rupture_remains, opts)
    opts = opts or {}
    local min_cp = opts.min_cp
    if not is_num(min_cp) then
        min_cp = st.rogue_guide.FINISHER_MIN_CP_DEFAULT
    end
    local refresh = opts.rupture_refresh
    if not is_num(refresh) then
        refresh = st.rogue_guide.RUPTURE_REFRESH_DEFAULT
    end
    local min_ttd = opts.rupture_min_ttd
    if not is_num(min_ttd) then
        min_ttd = st.rogue_guide.RUPTURE_MIN_TTD_DEFAULT
    end
    if not is_num(cp) or cp < min_cp then
        return nil
    end
    if not is_num(ttd) then
        return nil
    end
    if ttd <= min_ttd then
        return "eviscerate"
    end
    if rupture_remains == nil then
        return "rupture"
    end
    if not is_num(rupture_remains) then
        return nil
    end
    if rupture_remains <= refresh then
        return "rupture"
    end
    return "eviscerate"
end

-- Per-client Envenom verdict: "envenom" or nil. Reads ONLY its family's rule
-- table (unknown family never prompts). args is the caller-owned inputs table;
-- band is the resolved pooling band (for the Wrath cap exception).
function st.rogue_guide.envenom_verdict(family, args, band)
    args = args or {}
    local rule = st.rogue_guide.ENVENOM_RULES[family]
    if type(rule) ~= "table" then
        return nil
    end
    local mode = rule.mode
    if mode == "never" then
        return nil
    end
    local cp = args.cp
    local stacks = args.deadly_stacks
    if mode == "dying_only" then
        local ttd_max = rule.ttd_max
        if not is_num(ttd_max) then
            return nil
        end
        local min_cp = rule.min_cp
        if not is_num(min_cp) then
            return nil
        end
        local min_stacks = rule.min_stacks
        if not is_num(min_stacks) then
            return nil
        end
        if not is_num(cp) or cp < min_cp then
            return nil
        end
        if not is_num(stacks) or stacks < min_stacks then
            return nil
        end
        if not is_num(args.ttd) or args.ttd > ttd_max then
            return nil
        end
        return "envenom"
    end
    if mode == "let_expire" then
        local min_cp = rule.min_cp
        if not is_num(min_cp) then
            return nil
        end
        local min_stacks = rule.min_stacks
        if not is_num(min_stacks) then
            return nil
        end
        if not is_num(cp) or cp < min_cp then
            return nil
        end
        if not is_num(stacks) or stacks < min_stacks then
            return nil
        end
        local buff = args.envenom_buff_remains
        if is_num(buff) and buff > 0 then
            -- Buff rides: let it expire - unless energy would cap waiting.
            local energy = args.energy_now
            if type(band) == "table" and is_num(band.post)
                and is_num(energy) and energy >= band.post then
                return "envenom"
            end
            return nil
        end
        if buff ~= nil and not is_num(buff) then
            return nil
        end
        return "envenom"
    end
    if mode == "chain" then
        local min_cp = rule.min_cp
        if not is_num(min_cp) then
            return nil
        end
        if not is_num(cp) or cp < min_cp then
            return nil
        end
        if is_num(stacks) and stacks <= 0 then
            return nil
        end
        return "envenom"
    end
    return nil
end

-- Shiv upkeep verdict: "shiv" when Shiv is usable and the Deadly clock proves a
-- falloff inside the window; nil otherwise (a nil clock never prompts - H4).
-- deadly_stacks rides the call shape for the provider but is intentionally
-- unread: a running falloff clock already proves stacks exist.
function st.rogue_guide.shiv_verdict(deadly_stacks, deadly_remaining, shiv_ready, window)
    if shiv_ready ~= true then
        return nil
    end
    if not is_num(window) then
        window = st.rogue_guide.SHIV_REFRESH_DEFAULT
    end
    if deadly_remaining == nil then
        return nil
    end
    if not is_num(deadly_remaining) then
        return nil
    end
    if deadly_remaining <= window then
        return "shiv"
    end
    return nil
end

-- EA-duty refresh verdict: "expose" while on duty and the armor clock is missing
-- (nil prompts, like the druid rip/rake nil rule) or inside the window.
function st.rogue_guide.ea_verdict(ea_duty, ea_remains, window)
    if ea_duty ~= true then
        return nil
    end
    if not is_num(window) then
        window = st.rogue_guide.EA_REFRESH_DEFAULT
    end
    if ea_remains == nil then
        return "expose"
    end
    if not is_num(ea_remains) then
        return nil
    end
    if ea_remains <= window then
        return "expose"
    end
    return nil
end

-- Thistle-Tea deficit cue: "tea" when the item is usable and energy proves low.
function st.rogue_guide.tea_verdict(tea_ready, energy_now, energy_max)
    if tea_ready ~= true then
        return nil
    end
    if not is_num(energy_now) then
        return nil
    end
    if not is_num(energy_max) then
        energy_max = st.rogue_guide.TEA_ENERGY_MAX_DEFAULT
    end
    if energy_now <= energy_max then
        return "tea"
    end
    return nil
end

-- Unknown-input contract (H4/M6): the core reads are unusable (or the provider's
-- explicit M6 bit is set - e.g. the secret regime makes the auras unreadable), so no
-- rule below may emit a verdict. The provider owns the inputs_unknown bit (M6 pattern);
-- this is the pure half the provider calls.
function st.rogue_guide.is_unknown(inputs)
    if type(inputs) ~= "table" then
        return true
    end
    if inputs.inputs_unknown == true then
        return true
    end
    return not is_num(inputs.energy_now) or not is_num(inputs.cp)
end

-- Pure: one engine tick. Reads `inputs`, writes the frozen display fields into
-- the caller-owned `out` table and returns it. See the module header for the
-- rule matrix.
function st.rogue_guide.evaluate(inputs, out)
    inputs = inputs or {}
    if type(out) ~= "table" then
        out = {}
    end

    local action
    local hold = false
    local hold_text
    local unknown = st.rogue_guide.is_unknown(inputs)

    if not unknown then
        local family = inputs.family
        local band = st.rogue_guide.POOL_BANDS[family]
        if type(inputs.pool_pre) == "number" and type(inputs.pool_post) == "number" then
            band = { pre = inputs.pool_pre, post = inputs.pool_post }
        end

        local ea_window = inputs.ea_refresh
        if not is_num(ea_window) then
            ea_window = st.rogue_guide.EA_REFRESH_DEFAULT
        end
        local shiv_window = inputs.shiv_refresh
        if not is_num(shiv_window) then
            shiv_window = st.rogue_guide.SHIV_REFRESH_DEFAULT
        end
        local tea_max = inputs.tea_energy_max
        if not is_num(tea_max) then
            tea_max = st.rogue_guide.TEA_ENERGY_MAX_DEFAULT
        end
        local min_cp = inputs.finisher_min_cp
        if not is_num(min_cp) then
            min_cp = st.rogue_guide.FINISHER_MIN_CP_DEFAULT
        end
        local min_ttd = inputs.rupture_min_ttd
        if not is_num(min_ttd) then
            min_ttd = st.rogue_guide.RUPTURE_MIN_TTD_DEFAULT
        end
        local rupture_refresh = inputs.rupture_refresh
        if not is_num(rupture_refresh) then
            rupture_refresh = st.rogue_guide.RUPTURE_REFRESH_DEFAULT
        end
        local max_energy = inputs.max_energy
        if not is_num(max_energy) then
            max_energy = st.rogue_guide.MAX_ENERGY_DEFAULT
        end

        local energy = inputs.energy_now
        local cp = inputs.cp
        local ttd = inputs.ttd

        if st.rogue_guide.ea_verdict(inputs.ea_duty, inputs.ea_remains, ea_window) ~= nil then
            -- 1. EA-duty refresh outranks every spender.
            action = "expose"
        elseif st.rogue_guide.shiv_verdict(inputs.deadly_stacks, inputs.deadly_remaining,
            inputs.shiv_ready, shiv_window) ~= nil then
            -- 2. Shiv upkeep before the Deadly clock falls off.
            action = "shiv"
        elseif st.rogue_guide.envenom_verdict(family, inputs, band) ~= nil then
            -- 3. Per-client Envenom rule.
            action = "envenom"
        elseif is_num(ttd) and ttd <= min_ttd and is_num(cp) and cp >= 1 then
            -- 4. Dying-target dump at any CP (Era rule).
            action = "eviscerate"
        elseif is_num(cp) and cp >= min_cp then
            -- 5. Planned finisher on the TTD decider (unknown TTD yields nil
            -- and falls through - never a guessed finisher).
            action = st.rogue_guide.finisher_for_ttd(cp, ttd, inputs.rupture_remains, {
                min_cp = min_cp,
                rupture_refresh = rupture_refresh,
                rupture_min_ttd = min_ttd,
            })
        end

        if action == nil then
            if st.rogue_guide.tea_verdict(inputs.tea_ready, energy, tea_max) ~= nil then
                -- 6. Thistle Tea on a proven energy deficit.
                action = "tea"
            else
                -- 7. Pool-vs-spend. A nil verdict (no band for this client)
                -- falls through silently (rule 8).
                local verdict = st.rogue_guide.pool_verdict(energy, inputs.energy_tick_in,
                    band, max_energy)
                if verdict == "spend" then
                    action = "builder"
                elseif verdict == "pool" then
                    hold = true
                    hold_text = "POOL"
                end
            end
        end
    end
    -- 8. Anything else: no action. 0. Unknown: no action, no hold.

    out.action = action
    out.hold = hold
    out.hold_text = hold_text
    out.filler_slot = nil
    out.judge_slot = nil
    out.rotation_key = nil
    out.waiting_judgement = false
    out.unknown = unknown
    return out
end

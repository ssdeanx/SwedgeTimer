--=========================================================================================
-- Hunter next-action guide: pure decision engine, no WoW API and no clock.
--
-- The fifth and last provider for the frozen ST.<CLASS>.guide contract (nextaction_ui.lua's
-- header; the paladin ships the first, the warrior the second, the druid the third, the
-- shaman the fourth). The live reads live in classes/hunter.lua
-- (ST.HUNTER.gather_guide_inputs); this module only consumes the gathered inputs, so it is
-- unit-tested offline by tests/hunter_guide_state.lua.
--
-- The module reuses the pure hunter window maths at call time (hunter_window.lua is a
-- later TOC entry than the guide modules, so nothing is cached at load):
-- time_until_next_shot times the next ranged shot and is_cast_safe applies the steady-shot
-- grace; the gather half calls hidden_window/cast_window to bound the hidden Auto-Shot
-- window.
--
-- FROZEN SPEC - display slots (ST.HUNTER.guide.slots, ordered):
--   base set (every family except ERA, 6 of the 6 allowed):
--   steady        Steady Shot   56641  (icon rank-resolved via api.get_family_spell_id at
--                                       post_init; swipe: the live cast window)
--   raptor        Raptor Strike 2973   (icon rank-resolved the same way)
--   kill_command  Kill Command  34026  (TBC BM signature; icon rank-resolved the same
--                                       way; swipe-less prompt slot)
--   multi         Multi-Shot    2643   (icon rank-resolved the same way; swipe-less
--                                       prompt slot)
--   bestial_wrath Bestial Wrath 19574  (swipe-less prompt slot)
--   rapid_fire    Rapid Fire    3045   (swipe-less prompt slot)
--   Era set (st.family == "ERA", 3 of the 6 allowed: Steady Shot does not exist on
--   Era, and Kill Command / Bestial Wrath / Rapid Fire never prompt there, so those
--   slots are dropped rather than shipped dark):
--   aimed         Aimed Shot    19434  (icon rank-resolved the same way; swipe: the
--                                       live cast window, swipe_duration 3.0 s)
--   raptor        Raptor Strike 2973   (the declared melee surface, as on base)
--   multi         Multi-Shot    2643   (swipe-less prompt slot, as on base)
--   Wrath set (st.family == "WRATH", 6 of the 6 allowed: the WotLK min/max
--   priority, docs/research/rotations_wrath.md - Auto Shot fires during Steady
--   Shot casts on WotLK, so the matrix is cooldown-priority with no window hold
--   and no clip check on any arm):
--   kill_shot     Kill Shot      53351 (the execute: at or under 20% target health)
--   chimera       Chimera Shot   53209 (the MM signature; icon rank-resolved)
--   explosive     Explosive Shot 53301 (the SV signature; icon rank-resolved)
--   aimed         Aimed Shot     49050 (instant on Wrath: a swipe-less prompt, NOT
--                                       the Era 3 s cast slot)
--   arcane        Arcane Shot    49045 (MM early-phase; never prompted on SV -
--                                       Arcane shares its cooldown with Explosive)
--   steady        Steady Shot    56641 (demoted to filler; the live-cast swipe)
--   Wrath spec detection (no talent probe exists on the classic line): MM means
--   the client knows Chimera Shot, SV means it knows Explosive Shot (mutually
--   exclusive 51-point talents); neither means an unspecced/levelling hunter
--   (Kill Shot/Aimed/Arcane/Steady only). Serpent Sting is never prompted (MM
--   refreshes it through Chimera; SV upkeep needs aura tracking - deferred) and
--   neither is the Black Arrow/trap tier (no slot left in the six).
--   Era-SoD set (st.family == "ERA" with the SoD Chimera Shot rune known, 4 of
--   the 6 allowed: docs/research/rotations_sod.md - Auto/Chimera/Auto/Aimed/
--   Auto/Multi, the instant Chimera on cooldown above the Era weave):
--   chimera       Chimera Shot   409433 (the SoD gloves rune; icon rank-resolved)
--   aimed         Aimed Shot     19434  (as on Era)
--   raptor        Raptor Strike  2973   (as on Era)
--   multi         Multi-Shot     2643   (as on Era)
--   SoD detection: api.is_spell_known on the SoD-only rune id - SoD shares the
--   ERA family token, so the family alone never decides. A pet-rune build that
--   drops Chimera reads as plain Era (the Aimed/Multi weave plus melee gaps).
--   Forever set (st.family == "FOREVER", 4 of the 6 allowed: the beta upkeep
--   plus whatever filler the client answers, docs/research/forever_beta.md):
--   hawk          Summon Hawk   UNCONFIRMED (the beta guides name the spell but
--                               publish no spell id: the slot ships spell-less and
--                               texture-less until an id is confirmed in-client;
--                               swipe-less upkeep prompt, max 2 hawks + pet)
--   sniper        Sniper Shot   UNCONFIRMED (same: the MM signature, 4 s cast;
--                               knowing it IS the spec tell, the way Chimera-known
--                               means MM on Wrath; swipe: the live cast window,
--                               swipe_duration 4.0 s)
--   steady        Steady Shot   56641 (the filler, if the client knows a rank)
--   raptor        Raptor Strike 2973 (the declared melee surface, as on base)
--   Forever detection is the family token alone for the set, plus a knowledge
--   gate per prompt (both stay silent until their ids confirm). Multi-Shot is
--   deliberately NOT prompted on Forever: the beta rotations are sim-unconfirmed
--   (deferred). Hit rating (142/126/95/79, hunter_window.hit_cap_rating) never
--   enters any set: hit changes land chance, not shot timing, so the engine is
--   intentionally hit-blind and the caps are reserved for future HUD/badge
--   display (the option keys for that are frozen - deferred).
-- The rule matrix emits only actions "kill_shot" (Wrath only), "chimera" (Wrath
-- MM and Era-SoD only), "explosive" (Wrath SV only), "arcane" (Wrath non-SV
-- only), "aimed" (Era and Wrath), "multi", "steady", "kill_command", "bestial_wrath",
-- "rapid_fire", "hawk" (Forever only) and "sniper" (Forever only) (or none): the raptor slot is
-- the declared melee surface, and a queued Raptor Strike surfaces as rule 7's RIDE
-- hold. Every emitted action names a slot of the running family's set (the Era set
-- never emits the base-only actions and vice versa: the family gates below make the
-- cross-family arms unreachable).
--
-- FROZEN SPEC - inputs (all optional, nil never errors):
--   now, swing_start, swing_speed, swing_ends_at   ranged cycle, api.get_time() domain
--   synced_duration                                the synced Auto Shot cycle length
--                                                  (preferred over swing_speed, exactly
--                                                  like the cast bar's window maths)
--   latency                                        world latency in seconds only (never
--                                                  the twist lag calibration)
--   hidden_window_start, hidden_window_duration    the hidden Auto-Shot window bounds
--                                                  (cached module values or a
--                                                  hunter_window.hidden_window recompute)
--   auto_repeat_active                             last Auto Shot auto-repeat reading
--   raptor_strike_queued, steady_shot_queued       the module's queue flags
--   casting                                        any live cast/channel (compat's folding
--                                                  UnitCastingSpell read)
--   steady_cast_seconds                            Steady Shot's cast time (client spell
--                                                  data, 1.5 s base fallback)
--   steady_known                                   whether the client knows a Steady
--                                                  Shot rank (false on Era, where the
--                                                  spell does not exist: rule 6c never
--                                                  fires there and no fallback prompt
--                                                  is ever shown)
--   hawk_known, hawk_active_count,                 the Forever upkeep gate (rule F1,
--   hawk_remaining_cd                              NOT YET IMPLEMENTED): known on
--                                                  this Forever client, the live
--                                                  hawk count (nil = unknown,
--                                                  never guessed: the ids, and
--                                                  how hawks surface, are
--                                                  UNCONFIRMED - the gather
--                                                  always writes nil), plus the
--                                                  GCD-echo-filtered cooldown
--   sniper_known, sniper_remaining_cd,             the Forever cast gate (rule F2):
--   sniper_cast_seconds,                           known on this Forever client
--   sniper_remaining, sniper_duration              (the MM tell), its cooldown,
--                                                  its cast time (client spell
--                                                  data, 4.0 s base fallback)
--                                                  and the live Sniper cast's
--                                                  remaining seconds and full
--                                                  length (nil unless a Sniper
--                                                  rank is the live cast; the
--                                                  sniper slot's swipe pair,
--                                                  and rule 1's RIDE arm)
--   steady_remaining                               the live Steady cast's remaining
--                                                  seconds (nil unless a Steady rank is
--                                                  the live cast)
--   steady_duration                                the live Steady cast's full length (the
--                                                  slot swipe's full length)
--   steady_remaining_cd                            Steady Shot's client cooldown after the
--                                                  gather's GCD-echo filter (<= 1.51 s
--                                                  ignored); nil/<= 0 = off cooldown
--   multi_remaining                                a live Multi-Shot cast's remaining
--                                                  seconds (nil unless a Multi-Shot rank
--                                                  is the live cast)
--   multi_cast_seconds                             Multi-Shot's cast time (client spell
--                                                  data, 0.5 s base fallback)
--   multi_remaining_cd                             Multi-Shot's client cooldown after the
--                                                  gather's GCD-echo filter; nil/<= 0 =
--                                                  off cooldown
--   multi_known                                    the gate for the Multi-Shot weave:
--                                                  the client knows a Multi-Shot rank
--                                                  AND the family is ERA or TBC;
--                                                  anything else never fires rule 6b
--   aimed_known, aimed_remaining_cd                the Era gate for Aimed Shot
--                                                  (rule 6a): known on this Era client
--                                                  (false on every other family, where
--                                                  the Era slot set is not declared),
--                                                  plus its GCD-echo-filtered cooldown
--   aimed_cast_seconds                             Aimed Shot's cast time (client spell
--                                                  data, 3.0 s Era base fallback)
--   aimed_remaining, aimed_duration                the live Aimed cast's remaining
--                                                  seconds and full length (nil unless
--                                                  an Aimed Shot rank is the live
--                                                  cast; the Era slot's swipe pair)
--   kc_known, kc_remaining_cd                      the TBC gate for Kill Command (rule 3):
--                                                  known on this TBC client, plus its
--                                                  GCD-echo-filtered cooldown
--   bw_known, bw_remaining_cd                      the TBC gate for Bestial Wrath (rule 4)
--   rf_known, rf_remaining_cd                      the TBC gate for Rapid Fire (rule 5)
--   killshot_known, killshot_remaining_cd          the Wrath gate for Kill Shot
--                                                  (rule W1): known on this Wrath
--                                                  client, plus its
--                                                  GCD-echo-filtered cooldown
--   target_hp_frac                                 the target's health fraction
--                                                  (0-1; nil = unknown, never
--                                                  guessed): Kill Shot prompts
--                                                  at or under 0.20 only
--   chimera_known, chimera_remaining_cd             the Chimera gate: the Wrath MM
--                                                  signature (rule W2) or the SoD
--                                                  rune (rule 5b); every other
--                                                  client reads false
--   explosive_known, explosive_remaining_cd        the Wrath SV signature gate
--                                                  (rule W3)
--   wrath_aimed_known, wrath_aimed_remaining_cd    the Wrath Aimed gate (rule W4:
--                                                  the instant prompt; separate
--                                                  from the Era aimed_* cast
--                                                  weave)
--   arcane_known, arcane_remaining_cd              the Wrath Arcane gate (rule W5:
--                                                  MM early-phase; suppressed on
--                                                  SV, where Arcane shares its
--                                                  cooldown with Explosive)
--   target_in_range                                ranged range probe of the Steady Shot
--                                                  school; nil = unknown
--   lust_remaining                                 remaining seconds of a live
--                                                  Bloodlust/Heroism-family aura on the
--                                                  player (the H2 suppression input for
--                                                  rules 6a/6b; nil = none, never zero)
--
-- FROZEN SPEC - rule order (first match wins; exactly these rules):
--   1. a live Steady Shot, Multi-Shot, Sniper Shot or (Era) Aimed Shot cast is in
--      progress (steady_remaining, multi_remaining, sniper_remaining or
--      aimed_remaining is a number) -> hold, hold_text = "RIDE".
--   2b. the ranged range probe reads exactly 0 (target_in_range == 0, byte-exact: nil
--      = unknown = allowed and boolean spellings are never treated) -> hold,
--      hold_text = "HOLD", ahead of every cooldown priority - the wrath arms (W1-W6)
--      included - and of rule 7's queued ride (conservative: out of range nothing
--      fires). Rule 1 above it still wins: a live cast continues riding.
--   W1-W6. Wrath only (st.family == "WRATH"): the WotLK cooldown priority, with
--      no window hold and no clip check on any arm (Auto Shot fires during Steady
--      Shot casts there, so every shot is cooldown-ready by definition):
--      W1. Kill Shot is known (killshot_known == true), off cooldown and the
--          target is at or under 0.20 health -> action "kill_shot". Unknown
--          health never prompts (never guess the execute).
--      W2. MM: Chimera Shot is known (chimera_known == true) and off cooldown
--          -> action "chimera" (instant, so never a clip).
--      W3. SV: Explosive Shot is known (explosive_known == true) and off
--          cooldown -> action "explosive" (instant, so never a clip).
--      W4. Aimed Shot is known (wrath_aimed_known == true) and off cooldown ->
--          action "aimed" (instant on Wrath; the SV Multi/Aimed tier rides this
--          prompt - the WotLK Multi-Shot ranks are not in the reference table).
--      W5. Arcane Shot is known (arcane_known == true), off cooldown and the
--          client does NOT know Explosive Shot -> action "arcane" (MM
--          early-phase; dropped at the ArP cap, which no probe can see - the
--          owner skips it then).
--      W6. Steady Shot is known here (steady_known == true) and off cooldown
--          -> action "steady" (the demoted filler: it has no cooldown of its
--          own, so it fires whenever nothing above is due - Steady x3/x4 falls
--          out of the cooldown gaps, not out of a counter).
--   2. every family except Wrath: now is inside the hidden Auto-Shot window
--      (inclusive bounds: now >= hidden_window_start and now <=
--      hidden_window_start + hidden_window_duration, matching
--      hunter_window.cast_bar_display's outside test) -> hold, hold_text =
--      "HOLD": a cast started now would clip the shot. Wrath never holds here
--      (no auto-shot management on WotLK, per the research).
--   3. TBC only: Kill Command is known on this client (kc_known == true) and off
--      cooldown (kc_remaining_cd nil or <= 0) -> action "kill_command". Instant, so
--      never a clip: the #1 TBC BM priority.
--   4. TBC only: Bestial Wrath is known (bw_known == true) and off cooldown ->
--      action "bestial_wrath" (instant: popped on cooldown).
--   5. TBC only: Rapid Fire is known (rf_known == true) and off cooldown ->
--      action "rapid_fire" (instant: popped on cooldown).
--   5b. Era-SoD only (st.family == "ERA" with the rune known): Chimera Shot is
--      known (chimera_known == true) and off cooldown -> action "chimera"
--      (instant, so never a clip: above the Era weave, behind the window).
--   F1. Forever only (st.family == "FOREVER"): Summon Hawk upkeep - known
--      (hawk_known == true), fewer than HAWK_MAX_ACTIVE (2) hawks active and
--      off cooldown -> action "hawk" (instant, so never a clip: above the
--      Forever weave, behind the window, matching the beta rotation's
--      "if less than two are active" step). NOT YET IMPLEMENTED: the gather
--      writes hawk_active_count = nil (no confirmed count source - see
--      classes/hunter.lua), so this arm is currently unreachable by
--      construction; it is declared + engine-tested as the plug-in point, not
--      presented as a live prompt.
--   F2. Forever only: Sniper Shot is known (sniper_known == true, itself the MM
--      tell), off cooldown and the 4 s cast fits clip-safe: remaining =
--      sniper_cast_seconds + latency vs time_until_next_shot through
--      hunter_window.is_cast_safe with the steady-shot grace (Sniper Shot is
--      not a Multi-Shot rank, so the 0 grace never applies) -> action
--      "sniper". Whenever Sniper Shot is clip-safe, Multi-Shot and Steady Shot
--      are clip-safe too (shorter casts), so a due Sniper Shot always shadows
--      the weave while it is due.
--   6. the weave, first due first served:
--      a. Era only: Aimed Shot is known (aimed_known == true), off cooldown and the
--         3 s cast fits clip-safe: remaining = aimed_cast_seconds + latency vs
--         time_until_next_shot through hunter_window.is_cast_safe with the
--         steady-shot grace (Aimed Shot is not a Multi-Shot rank, so the 0 grace
--         never applies) -> action "aimed". The primary Era filler, so it shadows
--         Multi-Shot while both are due.
--      b. Era and TBC: Multi-Shot is known (multi_known == true), off cooldown and
--         the cast fits clip-safe: remaining = multi_cast_seconds + latency vs
--         time_until_next_shot through hunter_window.is_cast_safe with the
--         multi-shot grace (0) -> action "multi".
--      c. Steady Shot is known here (steady_known == true), off cooldown
--         (steady_remaining_cd nil or <= 0) and the cast fits clip-safe: remaining
--         = steady_cast_seconds + latency vs time_until_next_shot through
--         hunter_window.is_cast_safe with the steady grace -> action "steady".
--         The known gate keeps Era (and any client without the spell) on the old
--         silent behaviour instead of prompting the rank-1 fallback.
--      Unknown ranged state (no ttl) is NOT clip-safe: the engine never guesses.
--      H2 suppression: while a Bloodlust/Heroism aura is live on the player
--      (inputs.lust_remaining a number > 0), the haste shortens every Auto Shot
--      cycle and pushes both casts' clip maths off their modelled numbers, so
--      rules 6a and 6b are suppressed for the window's duration; Steady Shot
--      keeps flowing through 6c as the spam cue. Rules F1-F2 and the W-arms
--      (Wrath) stay live, as do rules 1, 2, 2b and 7; nil and 0 (and an absent
--      read on Era) read as "no window" - never suppressed on a maybe.
--      Whenever Aimed Shot is clip-safe, Multi-Shot is clip-safe too (shorter cast,
--      no grace), so a due Aimed Shot always shadows Multi-Shot while both are due;
--      whenever Steady Shot is clip-safe, Multi-Shot is clip-safe too, so the
--      steady-only behaviour is intact on TBC while Multi-Shot is on cooldown or
--      unknown. The weapon-speed breakpoint (~3.0 s) falls out of the clip checks
--      themselves: the 3 s Aimed cast only fits a slow (or freshly fired) Auto
--      cycle, while the 0.5 s Multi-Shot fits almost any live cycle. Explicit
--      full-vs-clipped sequencing (which shot alternation to run) is NOT modelled:
--      the stateless engine prompts whatever fits; the live swing reads
--      (synced_duration) already make every prompt weapon-speed-adaptive.
--   7. raptor_strike_queued or steady_shot_queued -> no action, hold = true, hold_text =
--      "RIDE" (the queued on-next-swing state is already showing on the bar).
--   8. no action.
--   auto_repeat_active, casting and target_in_range ride the frozen input set; the
--   rules above are the complete decision matrix. Rules 3-5 carry their TBC gate in
--   the inputs (the *_known flags the gather derives from st.family), rule 5b its
--   Era-plus-rune gate (chimera_known), rules F1-F2 their FOREVER family gate
--   plus their knowledge gates (hawk_known/sniper_known), rules W1-W6 their
--   WRATH family gate plus their known-rank gates, rule 6a its Era gate
--   (aimed_known), rule 6b its Era-or-TBC gate (multi_known) and rule 6c its
--   known-rank gate (steady_known), so every other client runs exactly the old
--   matrix: rules 1, 2, 6b (TBC), 6c (where known), 7, 8. The window hold
--   (rule 2) stays compiled in on Forever: the beta "Auto Shot no longer
--   clipped" note is sim-unconfirmed in-client, so instants keep the
--   conservative TBC-style hold until a Forever client proves otherwise.
--
--   The eWS/ratio outputs below are display data, never rule inputs: the
--   stateless engine prompts whatever fits clip-safe (the live swing reads
--   already make every prompt weapon-speed-adaptive), while explicit
--   full-vs-clipped sequencing (which shot alternation to run) is NOT modelled.
--
--   Retail (12.x) inertness: st.family == "RETAIL" short-circuits evaluate to the
--   empty display shape before any rule below. The inert stand-in reports no ranged
--   cycle (rules 2 and 6 stay silent on their own), but a live cast (rule 1), the
--   cooldown-shaped reads behind rules 3-5 and the queue flags (rule 7) all answer
--   on Retail, so those rules would prompt or hold with no swing at all. Every
--   other family runs the matrix above unchanged; a nil family (offline callers
--   that predate it) keeps the old behaviour too.
--
-- Output: the frozen display fields are overwritten on every call:
--   action, hold, hold_text, filler_slot = nil, judge_slot = nil, rotation_key = nil,
--   waiting_judgement = false, plus the TBC micro display pair (never rule
--   inputs, always recomputed, nil when the ranged cycle is unknown):
--   effective_weapon_speed                 the live cycle length (synced_duration
--                                          preferred over swing_speed), which IS
--                                          the effective weapon speed once the
--                                          client's haste applies - the quiver x
--                                          talent decomposition it verifies
--                                          against lives in
--                                          hunter_window.effective_weapon_speed
--   steady_ratio                           hunter_window.steady_ratio_band over
--                                          that length ("one_to_one", "french"
--                                          or "one_to_two").
--=========================================================================================
local _, st = ...

st.hunter_guide = st.hunter_guide or {}

-- Rule constants (frozen; the hunter guide exposes no options panel thresholds).
st.hunter_guide.STEADY_CAST_SECONDS_DEFAULT = 1.5
st.hunter_guide.STEADY_GRACE_DEFAULT = 0.5
st.hunter_guide.MULTI_CAST_SECONDS_DEFAULT = 0.5
st.hunter_guide.MULTI_GRACE_DEFAULT = 0
st.hunter_guide.AIMED_CAST_SECONDS_DEFAULT = 3.0
st.hunter_guide.KILL_SHOT_EXECUTE_FRAC = 0.20
st.hunter_guide.SNIPER_CAST_SECONDS_DEFAULT = 4.0

-- Summon Hawk upkeep cap (docs/research/forever_beta.md: "if less than two are
-- active", max 2 hawks + pet). The engine compares the live count strictly
-- below this; an unknown count never prompts (never guess the upkeep).
st.hunter_guide.HAWK_MAX_ACTIVE = 2

-- "Off cooldown": nothing left to wait for. gather filters the GCD echo before the inputs
-- reach this module, so a positive value is a real ability cooldown.
local function is_off_cooldown(remaining)
    return not (type(remaining) == "number" and remaining > 0)
end

-- The hidden Auto-Shot window containment, inclusive at both edges (the same outside test
-- hunter_window.cast_bar_display applies: only now < start or now > end is outside).
local function is_in_window(window_start, window_duration, now)
    return type(window_start) == "number" and type(window_duration) == "number"
        and window_duration > 0 and type(now) == "number"
        and now >= window_start and now <= window_start + window_duration
end

-- Rule 6c's clip-safety check through the pure hunter_window maths (the same kernels the
-- cast bar tints with). False whenever the ranged cycle is unknown: no ttl, no prompt -
-- the engine never guesses a cast it cannot prove clip-safe.
local function cast_is_clip_safe(inputs)
    local hunter_window = st.hunter_window
    if not (hunter_window and hunter_window.time_until_next_shot
        and hunter_window.is_cast_safe) then
        return false
    end
    local cycle_duration = inputs.synced_duration
    if type(cycle_duration) ~= "number" then
        cycle_duration = inputs.swing_speed
    end
    local ttl = hunter_window.time_until_next_shot(
        inputs.now, inputs.swing_start, cycle_duration, inputs.swing_ends_at)
    if type(ttl) ~= "number" then
        return false
    end
    local cast_seconds = inputs.steady_cast_seconds
    if type(cast_seconds) ~= "number" then
        cast_seconds = st.hunter_guide.STEADY_CAST_SECONDS_DEFAULT
    end
    local latency = inputs.latency
    if type(latency) ~= "number" then
        latency = 0
    end
    local grace = hunter_window.STEADY_SHOT_GRACE
    if type(grace) ~= "number" then
        grace = st.hunter_guide.STEADY_GRACE_DEFAULT
    end
    -- The frozen formula: the cast plus the latency must fit inside the next-shot window
    -- under the steady-shot grace (is_cast_safe floors its own latency buffer).
    return hunter_window.is_cast_safe(cast_seconds + latency, ttl, grace, latency) == true
end

-- Rule 6b's clip-safety check: the same kernels as the steady check below, with the
-- Multi-Shot cast time and the multi-shot grace (0). Kept as a separate function so
-- the steady path below stays byte-identical: whenever Steady Shot is clip-safe,
-- Multi-Shot is clip-safe too (shorter cast, no grace), so a due Multi-Shot always
-- shadows Steady Shot and the steady-only behaviour is intact while Multi-Shot is on
-- cooldown or unknown.
local function multi_is_clip_safe(inputs)
    local hunter_window = st.hunter_window
    if not (hunter_window and hunter_window.time_until_next_shot
        and hunter_window.is_cast_safe) then
        return false
    end
    local cycle_duration = inputs.synced_duration
    if type(cycle_duration) ~= "number" then
        cycle_duration = inputs.swing_speed
    end
    local ttl = hunter_window.time_until_next_shot(
        inputs.now, inputs.swing_start, cycle_duration, inputs.swing_ends_at)
    if type(ttl) ~= "number" then
        return false
    end
    local cast_seconds = inputs.multi_cast_seconds
    if type(cast_seconds) ~= "number" then
        cast_seconds = st.hunter_guide.MULTI_CAST_SECONDS_DEFAULT
    end
    local latency = inputs.latency
    if type(latency) ~= "number" then
        latency = 0
    end
    local grace = hunter_window.MULTI_SHOT_GRACE
    if type(grace) ~= "number" then
        grace = st.hunter_guide.MULTI_GRACE_DEFAULT
    end
    -- The frozen formula: the cast plus the latency must fit inside the next-shot window
    -- under the multi-shot grace (is_cast_safe floors its own latency buffer).
    return hunter_window.is_cast_safe(cast_seconds + latency, ttl, grace, latency) == true
end

-- Rule 6a's clip-safety check: the same kernels as the steady check above, with the
-- Era Aimed Shot cast time (3.0 s base) under the steady-shot grace (Aimed Shot is
-- not a Multi-Shot rank, so the 0 grace never applies). Kept as a separate function
-- so both paths above stay byte-identical: whenever Aimed Shot is clip-safe,
-- Multi-Shot is clip-safe too (shorter cast, no grace), so a due Aimed Shot always
-- shadows Multi-Shot while both are due.
local function aimed_is_clip_safe(inputs)
    local hunter_window = st.hunter_window
    if not (hunter_window and hunter_window.time_until_next_shot
        and hunter_window.is_cast_safe) then
        return false
    end
    local cycle_duration = inputs.synced_duration
    if type(cycle_duration) ~= "number" then
        cycle_duration = inputs.swing_speed
    end
    local ttl = hunter_window.time_until_next_shot(
        inputs.now, inputs.swing_start, cycle_duration, inputs.swing_ends_at)
    if type(ttl) ~= "number" then
        return false
    end
    local cast_seconds = inputs.aimed_cast_seconds
    if type(cast_seconds) ~= "number" then
        cast_seconds = st.hunter_guide.AIMED_CAST_SECONDS_DEFAULT
    end
    local latency = inputs.latency
    if type(latency) ~= "number" then
        latency = 0
    end
    local grace = hunter_window.STEADY_SHOT_GRACE
    if type(grace) ~= "number" then
        grace = st.hunter_guide.STEADY_GRACE_DEFAULT
    end
    -- The frozen formula: the cast plus the latency must fit inside the next-shot window
    -- under the steady-shot grace (is_cast_safe floors its own latency buffer).
    return hunter_window.is_cast_safe(cast_seconds + latency, ttl, grace, latency) == true
end

-- Rule F2's clip-safety check: the same kernels as the aimed check above, with the
-- Forever Sniper Shot cast time (4.0 s base) under the steady-shot grace (Sniper
-- Shot is not a Multi-Shot rank, so the 0 grace never applies). Kept as a separate
-- function so every path above stays byte-identical: whenever Sniper Shot is
-- clip-safe, Multi-Shot and Steady Shot are clip-safe too (shorter casts), so a
-- due Sniper Shot always shadows the weave while it is due.
local function sniper_is_clip_safe(inputs)
    local hunter_window = st.hunter_window
    if not (hunter_window and hunter_window.time_until_next_shot
        and hunter_window.is_cast_safe) then
        return false
    end
    local cycle_duration = inputs.synced_duration
    if type(cycle_duration) ~= "number" then
        cycle_duration = inputs.swing_speed
    end
    local ttl = hunter_window.time_until_next_shot(
        inputs.now, inputs.swing_start, cycle_duration, inputs.swing_ends_at)
    if type(ttl) ~= "number" then
        return false
    end
    local cast_seconds = inputs.sniper_cast_seconds
    if type(cast_seconds) ~= "number" then
        cast_seconds = st.hunter_guide.SNIPER_CAST_SECONDS_DEFAULT
    end
    local latency = inputs.latency
    if type(latency) ~= "number" then
        latency = 0
    end
    local grace = hunter_window.STEADY_SHOT_GRACE
    if type(grace) ~= "number" then
        grace = st.hunter_guide.STEADY_GRACE_DEFAULT
    end
    -- The frozen formula: the cast plus the latency must fit inside the next-shot window
    -- under the steady-shot grace (is_cast_safe floors its own latency buffer).
    return hunter_window.is_cast_safe(cast_seconds + latency, ttl, grace, latency) == true
end

-- Pure: one engine tick. Reads `inputs`, writes the frozen display fields into the
-- caller-owned `out` table and returns it. See the module header for the rule matrix.
function st.hunter_guide.evaluate(inputs, out)
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
        out.effective_weapon_speed = nil
        out.steady_ratio = nil
        return out
    end

    local action
    local hold = false
    local hold_text

    -- The Wrath matrix is cooldown-priority (no auto-shot management): its arms
    -- sit ahead of the window hold, and the window hold itself is compiled out
    -- on Wrath. Both gates read st.family, so every other family runs the exact
    -- old chain below.
    local is_wrath = st.family == "WRATH"

    -- The Forever upkeep/cast arms (rules F1-F2) sit with the TBC cooldowns:
    -- behind the window hold, above the weave. Only this gate reads st.family,
    -- so every other family runs the exact old chain below.
    local is_forever = st.family == "FOREVER"

    -- H2: the Bloodlust/Heroism window, derived once from the gathered read.
    -- A positive remaining is a live window (nil = no aura, never suppressed on
    -- a maybe); only the 6a/6b weave arms read it (see the header's 6. block).
    local lust_window = type(inputs.lust_remaining) == "number" and inputs.lust_remaining > 0

    if type(inputs.steady_remaining) == "number"
        or type(inputs.multi_remaining) == "number"
        or type(inputs.sniper_remaining) == "number"
        or type(inputs.aimed_remaining) == "number" then
        -- 1. A live Steady Shot, Multi-Shot, Sniper Shot or (Era) Aimed Shot cast
        --    is in progress: ride it.
        hold = true
        hold_text = "RIDE"
    elseif inputs.target_in_range == 0 then
        -- 2b. The ranged range probe reads out of range: nothing prompts, ahead
        --    of every cooldown priority - the wrath arms included - and of the
        --    rule-7 queue ride. Byte-exact == 0 only (nil = unknown = allowed;
        --    boolean spellings are never treated as hold), matching the gather's
        --    raw IsSpellInRange shape on the shipped clients.
        hold = true
        hold_text = "HOLD"
    elseif is_wrath and inputs.killshot_known == true
        and is_off_cooldown(inputs.killshot_remaining_cd)
        and type(inputs.target_hp_frac) == "number"
        and inputs.target_hp_frac <= st.hunter_guide.KILL_SHOT_EXECUTE_FRAC then
        -- W1. Wrath: Kill Shot is ready and the target is in execute range.
        action = "kill_shot"
    elseif is_wrath and inputs.chimera_known == true
        and is_off_cooldown(inputs.chimera_remaining_cd) then
        -- W2. Wrath MM: Chimera Shot is ready.
        action = "chimera"
    elseif is_wrath and inputs.explosive_known == true
        and is_off_cooldown(inputs.explosive_remaining_cd) then
        -- W3. Wrath SV: Explosive Shot is ready.
        action = "explosive"
    elseif is_wrath and inputs.wrath_aimed_known == true
        and is_off_cooldown(inputs.wrath_aimed_remaining_cd) then
        -- W4. Wrath: Aimed Shot is ready (instant: the shared MM/SV tier).
        action = "aimed"
    elseif is_wrath and inputs.arcane_known == true
        and inputs.explosive_known ~= true
        and is_off_cooldown(inputs.arcane_remaining_cd) then
        -- W5. Wrath MM early-phase: Arcane Shot is ready (never on SV, where it
        -- shares its cooldown with Explosive Shot).
        action = "arcane"
    elseif is_wrath and inputs.steady_known == true
        and is_off_cooldown(inputs.steady_remaining_cd) then
        -- W6. Wrath: Steady Shot is the demoted filler (no clip check: Auto Shot
        -- fires during the cast on WotLK).
        action = "steady"
    elseif not is_wrath
        and is_in_window(inputs.hidden_window_start, inputs.hidden_window_duration, inputs.now) then
        -- 2. Inside the hidden Auto-Shot window: starting a cast now would clip it.
        hold = true
        hold_text = "HOLD"
    elseif inputs.kc_known == true and is_off_cooldown(inputs.kc_remaining_cd) then
        -- 3. TBC: Kill Command is ready: the #1 BM priority (instant, never a clip).
        action = "kill_command"
    elseif inputs.bw_known == true and is_off_cooldown(inputs.bw_remaining_cd) then
        -- 4. TBC: Bestial Wrath is ready: popped on cooldown (instant).
        action = "bestial_wrath"
    elseif inputs.rf_known == true and is_off_cooldown(inputs.rf_remaining_cd) then
        -- 5. TBC: Rapid Fire is ready: popped on cooldown (instant).
        action = "rapid_fire"
    elseif st.family == "ERA" and inputs.chimera_known == true
        and is_off_cooldown(inputs.chimera_remaining_cd) then
        -- 5b. Era-SoD: the Chimera Shot rune is ready (instant: above the Era
        -- weave, behind the window).
        action = "chimera"
    elseif is_forever and inputs.hawk_known == true
        and type(inputs.hawk_active_count) == "number"
        and inputs.hawk_active_count < st.hunter_guide.HAWK_MAX_ACTIVE
        and is_off_cooldown(inputs.hawk_remaining_cd) then
        -- F1. Forever: the Summon Hawk upkeep is due (instant: above the
        -- Forever weave, behind the window). An unknown count never prompts -
        -- and the gather always writes unknown today (NOT YET IMPLEMENTED,
        -- see the header), so this arm is dormant-safe by construction.
        action = "hawk"
    elseif is_forever and inputs.sniper_known == true
        and is_off_cooldown(inputs.sniper_remaining_cd)
        and sniper_is_clip_safe(inputs) then
        -- F2. Forever: Sniper Shot is due and the 4 s cast fits before the
        -- next shot (the MM tell: unknown off-Forever, so no other client can
        -- reach this arm through its own gather).
        action = "sniper"
    elseif inputs.aimed_known == true and is_off_cooldown(inputs.aimed_remaining_cd)
        and aimed_is_clip_safe(inputs) and not lust_window then
        -- 6a. Era: Aimed Shot is due and the 3 s cast fits before the next shot.
        --    Suppressed while a Bloodlust/Heroism window is live (H2).
        action = "aimed"
    elseif inputs.multi_known == true and is_off_cooldown(inputs.multi_remaining_cd)
        and multi_is_clip_safe(inputs) and not lust_window then
        -- 6b. Era and TBC: Multi-Shot is due and the cast fits before the next
        --    shot. Suppressed while a Bloodlust/Heroism window is live (H2).
        action = "multi"
    elseif inputs.steady_known == true and is_off_cooldown(inputs.steady_remaining_cd)
        and cast_is_clip_safe(inputs) then
        -- 6c. Steady Shot is known here and ready, and the cast fits before the
        -- next shot. The known gate keeps clients without the spell (Era) silent
        -- instead of prompting the rank-1 fallback.
        action = "steady"
    elseif inputs.raptor_strike_queued == true or inputs.steady_shot_queued == true then
        -- 7. A queued on-next-swing ability is already showing on the bar: ride it.
        hold = true
        hold_text = "RIDE"
    end
    -- 8. Anything else: no action.

    -- The TBC micro display pair (header: display data, never rule inputs). The
    -- live cycle length (synced_duration preferred, exactly like the cast bar's
    -- window maths) IS the effective weapon speed once the client's haste
    -- applies; the ratio band falls out of it. Unknown cycle, unknown ratio:
    -- the engine never guesses either.
    local effective_weapon_speed
    local steady_ratio
    do
        local hunter_window = st.hunter_window
        if hunter_window and hunter_window.steady_ratio_band then
            local cycle_duration = inputs.synced_duration
            if type(cycle_duration) ~= "number" then
                cycle_duration = inputs.swing_speed
            end
            if type(cycle_duration) == "number" then
                effective_weapon_speed = cycle_duration
                steady_ratio = hunter_window.steady_ratio_band(cycle_duration)
            end
        end
    end

    out.action = action
    out.hold = hold
    out.hold_text = hold_text
    out.filler_slot = nil
    out.judge_slot = nil
    out.rotation_key = nil
    out.waiting_judgement = false
    out.effective_weapon_speed = effective_weapon_speed
    out.steady_ratio = steady_ratio
    return out
end

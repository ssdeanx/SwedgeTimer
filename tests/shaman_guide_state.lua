-- tests/shaman_guide_state.lua: offline tests for the shaman next-action guide: the
-- pure rule engine (shaman_guide.lua) and the provider glue + drive (classes/shaman.lua)
-- over the real compat.lua + utils.lua + nextaction_ui.lua + weave.lua in a sandbox.
--
-- Pins:
--   * shaman_guide.lua loads with NO WoW API at all (a strict sandbox errors on any
--     global read) and the frozen rule matrix: the casting RIDE hold winning over
--     everything, the Wrath cooldown slots (Fire Elemental / Feral Spirit ready,
--     known-gated) above the MW5-only instant (the old MW>=3 hardcast rule is gone;
--     3-4 stacks never weave) AND their mw_available gate (nil reads
--     as available, so older callers keep Wrath behaviour), Flame Shock missing /
--     exactly 3.0 s / out of its window, the twist skeleton's due/unknown shape, the
--     Stormstrike fishing hold (WAIT) and its numeric boundaries, Stormstrike on/off
--     cooldown and the availability gate, the Magma maintain window (due/refresh
--     boundary/unknown/custom refresh), Fire Nova ready/down, Lava Lash ready/down
--     and the Earth Shock filler,
--   * Frost Shock is never prompted (no slot key, no engine output names it) and
--     Wrath never twists (the live feed stays nil there); a fed target_count
--     changes nothing (no Chain Lightning split - deferred for lack of a countable
--     input),
--   * the frozen output fields are overwritten on every call (stale fields can never
--     survive into a reused out table) and nil inputs never error,
--   * the gather into the caller-owned reused table: every frozen input (including
--     mw_available, the Windfury ICD feed, Fire Nova and the nil twist stub), the
--     GCD-echo filter on the Stormstrike AND Fire Nova cooldowns, the tracker-fed
--     Flame Shock window, the catalogue readiness, stale-field overwrites and the
--     option threshold,
--   * the throttled target scan keeps running while the guide is enabled even with the
--     Flame Shock bar switched off (and stays idle with the guide off too),
--   * the provider contract shape (slot keys, six slots, cooldown keys resolving into
--     the gathered inputs, possible actions naming declared slots),
--   * the display mapping through the real frame sandbox (action -> slot -> fade
--     targets, the RIDE/WAIT holds, debuff-fed swipes and their latch, the option
--     gates),
--   * the TBC behaviour through the sandbox (a TBC client: no weave prompt ever, the
--     WAIT hold, Nova and the shock filler; the Wrath slots stay dark there) and
--     the Wrath block (the exact MW5 prompt survives behind a family override, the
--     MW3 hardcast is gone, the cooldown slots light in research order),
--   * the SoD block (the MW latch re-enables the MW5 rule; the weave slot
--     re-points at Lava Burst when the rune is known and keeps the catalogue
--     without it),
--   * the config/options parity for every new shaman key and the TOC load order,
--   * the drive wiring (post_init -> ui.init, on_bar_update -> the settings diff +
--     ui.on_bar_update) exercised through the real hooks.
-- Run from the repo root: lua5.1 tests/shaman_guide_state.lua  (any cwd works).

local script_dir = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = script_dir .. "/../"

local checks, failures = 0, 0
local function check(cond, label)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        print("FAIL  " .. label)
    end
end
local function eq(got, want, label)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end
local function near(got, want, tol, label)
    checks = checks + 1
    if type(got) ~= "number" or math.abs(got - want) > tol then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end

--=========================================================================================
-- 0) The pure engine: a strict sandbox that errors on any global read
--=========================================================================================
local pure = {}
do
    local strict = {
        type = type, tonumber = tonumber, tostring = tostring,
        pairs = pairs, ipairs = ipairs, math = math, string = string,
    }
    setmetatable(strict, {
        __index = function(_, key)
            error("shaman_guide.lua touched a global: " .. tostring(key))
        end,
    })
    local chunk = assert(loadfile(ROOT .. "shaman_guide.lua"))
    setfenv(chunk, strict)
    local ok, err = pcall(chunk, "SwedgeTimer", pure)
    check(ok, "shaman_guide.lua loads with no WoW API and no globals (" .. tostring(err) .. ")")
end

local sg = pure.shaman_guide
check(type(sg) == "table", "shaman_guide.lua defines st.shaman_guide")
check(type(sg.evaluate) == "function", "the pure engine is exported")
eq(sg.FLAMESHOCK_REFRESH_DEFAULT, 3, "the Flame Shock refresh default is 3")

-- Rule-matrix inputs: everything the frozen input set names, with a baseline that lands
-- on Stormstrike (no cast, Maelstrom available, no stacks, a healthy Flame Shock, SS
-- off cooldown, Fire Nova ready but outranked).
local NONE = {}
local function inp(overrides)
    local t = {
        speed = 3.0, swing_remaining = 2.0, gcd_remaining = 0,
        casting = false, mw_available = true, mw_stacks = 0, weave_available = true,
        flameshock_remaining = 10, flameshock_refresh = 3,
        stormstrike_remaining = 0, windfury_icd_remaining = nil,
        firenova_remaining = 0, twist_remaining = nil,
        fireele_remaining = nil, feralspirit_remaining = nil,
        magma_remaining = nil, magma_refresh = 3,
        lavalash_remaining = nil,
    }
    for k, v in pairs(overrides or {}) do
        if v == NONE then
            t[k] = nil
        else
            t[k] = v
        end
    end
    return t
end

local function evaluate(overrides)
    local out = {}
    local ret = sg.evaluate(inp(overrides), out)
    eq(ret, out, "evaluate returns the caller's out table")
    return out
end

-- Baseline: nothing to re-apply, SS ready -> Stormstrike.
do
    local out = evaluate({})
    eq(out.action, "stormstrike", "baseline: a healthy Flame Shock and a ready SS -> Stormstrike")
    eq(out.hold, false, "baseline: no hold")
    eq(out.hold_text, nil, "baseline: no hold text")
    eq(out.filler_slot, nil, "baseline: filler_slot stays nil")
    eq(out.judge_slot, nil, "baseline: judge_slot stays nil")
    eq(out.rotation_key, nil, "baseline: rotation_key stays nil")
    eq(out.waiting_judgement, false, "baseline: waiting_judgement stays false")
end

-- Rule 1: the casting hold wins over everything.
do
    local out = evaluate({ casting = true })
    eq(out.action, nil, "rule 1: a cast in flight shows no action")
    eq(out.hold, true, "rule 1: a cast in flight holds")
    eq(out.hold_text, "RIDE", "rule 1: the casting hold reads RIDE")
    eq(evaluate({ casting = true, mw_stacks = 5 }).action, nil,
        "rule 1 outranks the 5-stack weave")
    eq(evaluate({ casting = true, mw_stacks = 5, flameshock_remaining = NONE }).hold_text, "RIDE",
        "rule 1 outranks the Flame Shock refresh")
    eq(evaluate({ casting = true, stormstrike_remaining = 0 }).action, nil,
        "rule 1 outranks a ready Stormstrike")
end

-- Rules 2-3: Fire Elemental / Feral Spirit ready, known-gated (nil = unknown).
do
    eq(evaluate({ fireele_remaining = 0 }).action, "fireele",
        "rule 2: a ready Fire Elemental -> fireele")
    eq(evaluate({ fireele_remaining = 0, mw_stacks = 5 }).action, "fireele",
        "rule 2 outranks the 5-stack weave")
    eq(evaluate({ fireele_remaining = 0, flameshock_remaining = NONE }).action, "fireele",
        "rule 2 outranks the Flame Shock refresh")
    eq(evaluate({ fireele_remaining = 0, stormstrike_remaining = 0 }).action, "fireele",
        "rule 2 outranks a ready Stormstrike")
    eq(evaluate({ fireele_remaining = 5, stormstrike_remaining = 0 }).action, "stormstrike",
        "rule 2 boundary: a running cooldown falls through")
    eq(evaluate({ fireele_remaining = NONE }).action, "stormstrike",
        "rule 2: an unknown Fire Elemental never prompts")
    eq(evaluate({ feralspirit_remaining = 0 }).action, "feralspirit",
        "rule 3: a ready Feral Spirit -> feralspirit")
    eq(evaluate({ feralspirit_remaining = 0, mw_stacks = 5 }).action, "feralspirit",
        "rule 3 outranks the 5-stack weave")
    eq(evaluate({ feralspirit_remaining = 0, flameshock_remaining = NONE }).action, "feralspirit",
        "rule 3 outranks the Flame Shock refresh")
    eq(evaluate({ feralspirit_remaining = 5, stormstrike_remaining = 0 }).action, "stormstrike",
        "rule 3 boundary: a running cooldown falls through")
    eq(evaluate({ feralspirit_remaining = NONE }).action, "stormstrike",
        "rule 3: an unknown Feral Spirit never prompts")
    eq(evaluate({ fireele_remaining = 0, feralspirit_remaining = 0 }).action, "fireele",
        "rule 2 outranks rule 3 when both are ready")
end

-- Rule 4: the five-stack instant, gated on Maelstrom availability. MW5-ONLY: the
-- old MW>=3 hardcast is gone - 3-4 stacks never weave, wherever they fall.
do
    eq(evaluate({ mw_stacks = 5 }).action, "weave",
        "rule 4: five stacks -> weave")
    eq(evaluate({ mw_stacks = 5, flameshock_remaining = NONE }).action, "weave",
        "rule 4 outranks the Flame Shock refresh")
    eq(evaluate({ mw_stacks = 5, stormstrike_remaining = 0 }).action, "weave",
        "rule 4 outranks a ready Stormstrike")
    eq(evaluate({ mw_stacks = 5, weave_available = false }).action, "weave",
        "rule 4 boundary: five stacks are instant regardless of the catalogue state")
    eq(evaluate({ mw_stacks = 4.99, stormstrike_remaining = 0 }).action, "stormstrike",
        "rule 4 boundary: just below five stacks falls through")
    eq(evaluate({ mw_stacks = NONE }).action, "stormstrike",
        "rule 4: an unreadable stack count cannot match")
    eq(evaluate({ mw_stacks = 5, mw_available = NONE }).action, "weave",
        "rule 4: a missing mw_available reads as available (older callers keep Wrath behaviour)")
    eq(evaluate({ mw_stacks = 5, mw_available = false }).action, "stormstrike",
        "rule 4 gate: five stacks without Maelstrom fall through to Stormstrike")
    eq(evaluate({ mw_stacks = 5, mw_available = false, stormstrike_remaining = 8,
        firenova_remaining = 8 }).action, "earthshock",
        "rule 4 gate: with SS and Nova down the fallthrough reaches the shock filler")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 3 }).action, "firenova",
        "MW5-only: 3 stacks with SS down reach Fire Nova, never the weave")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 4, weave_available = true }).action,
        "firenova", "MW5-only: 4 stacks never weave even with the catalogue ready")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 3, firenova_remaining = 5 }).action,
        "earthshock", "MW5-only: 3 stacks with SS and Nova down reach the shock filler")
    eq(evaluate({ mw_stacks = 5, target_count = 3 }).action, "weave",
        "no target-count split: extra targets do not change the MW5 prompt")
end

-- Rule 5: the Flame Shock refresh window.
do
    eq(evaluate({ flameshock_remaining = NONE }).action, "flameshock",
        "rule 5: an untracked Flame Shock -> Flame Shock")
    eq(evaluate({ flameshock_remaining = 3 }).action, "flameshock",
        "rule 5 boundary: exactly 3.0 s refreshes")
    eq(evaluate({ flameshock_remaining = 3.001 }).action, "stormstrike",
        "rule 5 boundary: just above 3.0 s falls through")
    eq(evaluate({ flameshock_remaining = 0 }).action, "flameshock",
        "rule 5: a remaining of exactly 0 refreshes")
    eq(evaluate({ flameshock_remaining = NONE, stormstrike_remaining = 0 }).action, "flameshock",
        "rule 5 outranks a ready Stormstrike")
    eq(evaluate({ flameshock_remaining = 4.5, flameshock_refresh = 5 }).action, "flameshock",
        "rule 5: a custom refresh widens the window")
    eq(evaluate({ flameshock_remaining = 5.5, flameshock_refresh = 5 }).action, "stormstrike",
        "rule 5: just outside it the chain moves on")
    eq(evaluate({ flameshock_remaining = 3.5, flameshock_refresh = NONE }).action, "stormstrike",
        "rule 5: a missing threshold falls back to 3")
    eq(evaluate({ flameshock_remaining = 3.5, flameshock_refresh = 0 }).action, "stormstrike",
        "rule 5: a zero threshold only refreshes an absent-or-expired debuff")
end

-- Rules 6-8: the twist skeleton, the fishing hold and Stormstrike off cooldown.
-- (Wrath has no twisting: live twist_remaining is nil there, so rule 6 is dead.)
do
    eq(evaluate({ twist_remaining = 0 }).action, "twist",
        "rule 6: a due twist prompts the twist")
    eq(evaluate({ twist_remaining = 0, flameshock_remaining = NONE }).action, "flameshock",
        "rule 5 outranks a due twist")
    eq(evaluate({ twist_remaining = 0, stormstrike_remaining = 0,
        windfury_icd_remaining = 0.5 }).action, "twist",
        "rule 6 outranks the fishing hold")
    eq(evaluate({ twist_remaining = 5 }).action, "stormstrike",
        "rule 6 boundary: a twist that is not due falls through")
    eq(evaluate({ twist_remaining = NONE }).action, "stormstrike",
        "rule 6: an unknown twist never prompts (the live skeleton shape)")

    -- Rule 7: delay-if-fishing-WF.
    local held = evaluate({ stormstrike_remaining = 0, windfury_icd_remaining = 0.5,
        swing_remaining = 2.0 })
    eq(held.action, nil, "rule 7: an ICD inside the swing holds Stormstrike")
    eq(held.hold, true, "rule 7: the hold overlay shows")
    eq(held.hold_text, "WAIT", "rule 7: the fishing hold reads WAIT")
    eq(evaluate({ stormstrike_remaining = 0, windfury_icd_remaining = 0 }).action,
        "stormstrike", "rule 7 boundary: an elapsed ICD presses Stormstrike")
    eq(evaluate({ stormstrike_remaining = 0, windfury_icd_remaining = 2.5,
        swing_remaining = 2.0 }).action, "stormstrike",
        "rule 7 boundary: an ICD past the swing presses Stormstrike")
    eq(evaluate({ stormstrike_remaining = 0, windfury_icd_remaining = 2.0,
        swing_remaining = 2.0 }).action, nil,
        "rule 7 boundary: an ICD exactly at the swing still holds")
    eq(evaluate({ stormstrike_remaining = 0, windfury_icd_remaining = NONE }).action,
        "stormstrike", "rule 7: an unknown ICD never holds")
    eq(evaluate({ stormstrike_remaining = 0, windfury_icd_remaining = 0.5,
        swing_remaining = NONE }).action, "stormstrike",
        "rule 7: an unknown swing never holds")
    eq(evaluate({ stormstrike_remaining = 0, windfury_icd_remaining = 0.5,
        swing_remaining = 0 }).action, "stormstrike",
        "rule 7: a landing swing presses (the next tick re-evaluates)")
    local NaN = 0 / 0
    eq(evaluate({ stormstrike_remaining = 0, windfury_icd_remaining = NaN }).action,
        "stormstrike", "rule 7: a NaN ICD never holds")

    -- Rule 8: Stormstrike off cooldown.
    eq(evaluate({ stormstrike_remaining = NONE }).action, "stormstrike",
        "rule 8: an unreadable cooldown reads as ready")
    eq(evaluate({ stormstrike_remaining = 0 }).action, "stormstrike",
        "rule 8 boundary: exactly 0 is off cooldown")
    eq(evaluate({ stormstrike_remaining = -1 }).action, "stormstrike",
        "rule 8: a negative remaining is off cooldown")
    eq(evaluate({ stormstrike_remaining = 0.001, mw_stacks = 0,
        firenova_remaining = 8 }).action, "earthshock",
        "rule 8 boundary: a real SS cooldown with Nova down falls to the shock filler")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0,
        weave_available = false }).action, "firenova",
        "rule 8: a real cooldown falls to Fire Nova")
end

-- Rules 9-12: Magma maintain, Fire Nova, Lava Lash and the shock filler.
do
    eq(evaluate({ stormstrike_remaining = 8, magma_remaining = 0 }).action, "magma",
        "rule 9: a due Magma Totem -> magma")
    eq(evaluate({ stormstrike_remaining = 8, magma_remaining = 3 }).action, "magma",
        "rule 9 boundary: exactly the refresh window prompts")
    eq(evaluate({ stormstrike_remaining = 8, magma_remaining = 3.001 }).action, "firenova",
        "rule 9 boundary: just above the refresh window falls to Fire Nova")
    eq(evaluate({ stormstrike_remaining = 8, magma_remaining = NONE }).action, "firenova",
        "rule 9: an unknown Magma never prompts")
    eq(evaluate({ stormstrike_remaining = 8, magma_remaining = 2, magma_refresh = 1 }).action,
        "firenova", "rule 9: a custom refresh narrows the window")
    eq(evaluate({ stormstrike_remaining = 8, magma_remaining = 2, magma_refresh = NONE }).action,
        "magma", "rule 9: a missing refresh falls back to 3")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0 }).action, "firenova",
        "rule 10: Nova ready with SS down -> firenova")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = NONE }).action,
        "firenova", "rule 10: an unreadable Nova cooldown reads as ready")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 0,
        lavalash_remaining = 0 }).action, "firenova",
        "rule 10 outranks a ready Lava Lash")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5,
        lavalash_remaining = 0 }).action, "lavalash",
        "rule 11: a ready Lava Lash answers with SS and Nova down")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5,
        lavalash_remaining = 5 }).action, "earthshock",
        "rule 11 boundary: Lava Lash on cooldown falls to the shock filler")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5,
        lavalash_remaining = NONE }).action, "earthshock",
        "rule 11: an unknown Lava Lash never prompts")
    eq(evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5 }).action,
        "earthshock", "rule 12: the shock filler answers with everything else down")
    local out = evaluate({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5 })
    eq(out.hold, false, "rule 12: the filler carries no hold")
    eq(out.hold_text, nil, "rule 12: the filler carries no hold text")
end

-- Frost Shock is never prompted: no slot, no rule, no output.
do
    local battery = {
        {}, { mw_stacks = 5 }, { flameshock_remaining = NONE },
        { twist_remaining = 0 }, { stormstrike_remaining = 8, mw_stacks = 3 },
        { stormstrike_remaining = 8, mw_stacks = 0 },
        { stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5 },
        { fireele_remaining = 0 }, { feralspirit_remaining = 0 },
        { stormstrike_remaining = 8, magma_remaining = 0 },
        { stormstrike_remaining = 8, firenova_remaining = 5, lavalash_remaining = 0 },
    }
    local frost_seen = false
    for i = 1, #battery do
        local action = evaluate(battery[i]).action
        if type(action) == "string" and action:find("frost") then
            frost_seen = true
        end
    end
    check(not frost_seen, "no engine output ever names Frost Shock")
end

-- Frozen fields / nil-safety.
do
    local out = {
        action = "stale", hold = "stale", hold_text = "STALE", filler_slot = "stale",
        judge_slot = "stale", rotation_key = "stale", waiting_judgement = true,
    }
    sg.evaluate(inp({ casting = true }), out)
    eq(out.action, nil, "a reused out table has action overwritten")
    eq(out.hold, true, "a reused out table has hold overwritten")
    eq(out.hold_text, "RIDE", "a reused out table has hold_text overwritten")
    eq(out.filler_slot, nil, "a reused out table has filler_slot overwritten")
    eq(out.judge_slot, nil, "a reused out table has judge_slot overwritten")
    eq(out.rotation_key, nil, "a reused out table has rotation_key overwritten")
    eq(out.waiting_judgement, false, "a reused out table has waiting_judgement overwritten")

    local ok, err = pcall(sg.evaluate)
    check(ok, "evaluate with no arguments does not error (" .. tostring(err) .. ")")
    ok, err = pcall(sg.evaluate, nil, nil)
    check(ok, "evaluate(nil, nil) does not error (" .. tostring(err) .. ")")
    local fallback = sg.evaluate(inp({ mw_stacks = 5 }))
    eq(fallback.action, "weave", "evaluate can allocate its own out table")

    local frozen = inp({})
    local before_ss = frozen.stormstrike_remaining
    sg.evaluate(frozen, {})
    eq(frozen.stormstrike_remaining, before_ss, "evaluate never writes back into its inputs")

    local NaN = 0 / 0
    eq(evaluate({ mw_stacks = NaN, flameshock_remaining = NaN, stormstrike_remaining = NaN }).action,
        "stormstrike", "NaN inputs cannot match a rule and fall to the off-cooldown read")
    eq(evaluate({ mw_stacks = NaN, flameshock_remaining = 5, stormstrike_remaining = 8 }).action,
        "firenova", "a NaN stack count cannot reach the weave rule and falls to Fire Nova")
end

--=========================================================================================
-- 1) Sandbox: compat + utils + nextaction_ui + shaman_guide + weave + classes/shaman
--=========================================================================================
local SPELL_INFOS = {
    [403] = { name = "Lightning Bolt", icon = "icon_lb_r1", cast_ms = 3000 },
    [25449] = { name = "Lightning Bolt", icon = "icon_lb", cast_ms = 2500 },
    [25448] = { name = "Lightning Bolt", icon = "icon_lb9", cast_ms = 2000 },
    [25442] = { name = "Chain Lightning", icon = "icon_cl", cast_ms = 2000 },
    [17364] = { name = "Stormstrike", icon = "icon_ss" },
    [8050] = { name = "Flame Shock", icon = "icon_fs" },
    [1535] = { name = "Fire Nova Totem", icon = "icon_nova" },
    [8042] = { name = "Earth Shock", icon = "icon_es" },
    [8512] = { name = "Windfury Totem", icon = "icon_wf" },
    -- Wrath slots: Feral Spirit is repo-verified; Fire Elemental / Magma / Lava
    -- Lash ship best-recall ids marked UNCONFIRMED in the module (the known gate
    -- is what the tests exercise, so the fixture marks them known explicitly).
    [51533] = { name = "Feral Spirit", icon = "icon_feral" },
    [2894] = { name = "Fire Elemental Totem", icon = "icon_fireele" },
    [8190] = { name = "Magma Totem", icon = "icon_magma" },
    [60103] = { name = "Lava Lash", icon = "icon_lavalash" },
    -- Fixture-only Lava Burst (the SoD rune choice is name-probed, so the id only
    -- needs to be numeric here).
    [51505] = { name = "Lava Burst", icon = "icon_lava", cast_ms = 2000 },
    -- Fixture-only stand-in for an unconfirmed higher Windfury Totem rank: not in
    -- the addon's twist id table, so only the live-name resolution path stamps it.
    [10613] = { name = "Windfury Totem", icon = "icon_wf" },
}

local MODULES = { "compat.lua", "utils.lua", "nextaction_ui.lua", "shaman_guide.lua",
    "weave.lua", "classes/shaman.lua" }

local function make_fontstring()
    local f = { hidden = false }
    function f:SetPoint() end
    function f:SetJustifyH() end
    function f:SetShadowColor() end
    function f:SetShadowOffset() end
    function f:SetFont(path, size, flags) f.font = { path, size, flags }; return true end
    function f:SetText(text) f.text = text end
    function f:SetTextColor(r, g, b, a) f.color = { r, g, b, a } end
    function f:Hide() f.hidden = true end
    function f:Show() f.hidden = false end
    function f:IsShown() return not f.hidden end
    return f
end

local function make_texture()
    local t = { hidden = true }
    function t:SetDrawLayer() end
    function t:SetAllPoints() end
    function t:SetTexCoord(l, r, top, bottom) t.texcoord = { l, r, top, bottom } end
    function t:SetTexture(tex) t.texture = tex end
    function t:SetColorTexture() end
    function t:SetWidth(w) t.width = w end
    function t:SetHeight(h) t.height = h end
    function t:SetPoint() end
    function t:ClearAllPoints() end
    function t:SetVertexColor(r, g, b, a) t.color = { r, g, b, a } end
    function t:Hide() t.hidden = true end
    function t:Show() t.hidden = false end
    function t:IsShown() return not t.hidden end
    return t
end

local function make_frame(name)
    local f = { name = name, shown = false }
    function f:SetSize(w, h) f.width, f.height = w, h end
    function f:SetPoint(point, anchor, rel_point, x, y)
        f.points = f.points or {}
        f.points[#f.points + 1] = { point, anchor, rel_point, x, y }
    end
    function f:ClearAllPoints() f.points = nil end
    function f:SetFrameStrata() end
    function f:SetClampedToScreen() end
    function f:RegisterForDrag() end
    function f:SetScript(event, fn)
        f.scripts = f.scripts or {}
        f.scripts[event] = fn
    end
    function f:GetScript(event) return f.scripts and f.scripts[event] or nil end
    function f:Show() f.shown = true end
    function f:Hide() f.shown = false end
    function f:IsShown() return f.shown end
    function f:SetAlpha(a) f.alpha = a end
    function f:SetScale(s) f.scale = s end
    function f:GetScale() return f.scale or 1 end
    function f:SetMovable(m) f.movable = m end
    function f:EnableMouse(m) f.mouse = m end
    function f:GetFrameLevel() return 5 end
    function f:SetFrameLevel(l) f.level = l end
    function f:GetName() return f.name end
    function f:GetCenter() return 50, 60 end
    function f:StartMoving() end
    function f:StopMovingOrSizing() end
    function f:CreateTexture() return make_texture() end
    function f:CreateFontString() return make_fontstring() end
    function f:SetBackdrop(backdrop) f.backdrop = backdrop end
    function f:SetBackdropBorderColor(r, g, b, a) f.border_color = { r, g, b, a } end
    function f:SetCooldown(start, duration)
        f.cooldown_sets = (f.cooldown_sets or 0) + 1
        f.cooldown_start, f.cooldown_duration = start, duration
    end
    function f:SetReverse(reverse) f.reverse = reverse end
    function f:SetHideCountdownNumbers(flag) f.hide_numbers = flag end
    function f:SetAllPoints() end
    return f
end

local function build(opts)
    opts = opts or {}
    local sb = {
        clock = 0,
        frames = 0,
        known = opts.known or { [25449] = true, [25442] = true },
        auras = opts.auras or {},
        target_auras = opts.target_auras or {},
        cooldowns = {},
        hide_spells = false,
        aura_calls = 0,
        target_aura_calls = 0,
    }

    local env = setmetatable({}, { __index = _G })
    env.WOW_PROJECT_ID = 5
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    env.GetTimePreciseSec = function() return sb.clock end
    env.GetTime = function() return sb.clock end
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    env.GetLocale = function() return "enUS" end
    env.GetBuildInfo = function() return "0.0.0", "00000", "today", 30300 end
    env.UIParent = make_frame("UIParent")
    env.UIParent.GetCenter = function() return 0, 0 end
    env.CreateFrame = function(...)
        sb.frames = sb.frames + 1
        return make_frame(select(2, ...))
    end
    env.GetSpellInfo = function(spell)
        if sb.hide_spells then
            return nil
        end
        local info = SPELL_INFOS[spell]
        local id = spell
        if info == nil and type(spell) == "string" then
            -- The live SoD Lava Burst probe is a name query; the fixture answers
            -- it the same way (unique names only), with the numeric id.
            for candidate_id, candidate in pairs(SPELL_INFOS) do
                if candidate.name == spell then
                    info = candidate
                    id = candidate_id
                    break
                end
            end
        end
        if info then
            return info.name, nil, info.icon, info.cast_ms or 0, 0, 0, id
        end
        return nil
    end
    env.IsSpellKnown = function(id) return sb.known[id] == true end
    env.UnitAura = function(unit, index, filter)
        local entry
        if unit == "target" then
            sb.target_aura_calls = sb.target_aura_calls + 1
            entry = sb.target_auras[index]
        else
            sb.aura_calls = sb.aura_calls + 1
            entry = sb.auras[index]
        end
        if not entry then return nil end
        return entry.name, nil, entry.count, nil, entry.duration, entry.expiration,
            entry.source, nil, nil, entry.spell_id
    end
    env.GetSpellCooldown = function(id)
        local cd = sb.cooldowns[id]
        if cd then return cd.start, cd.duration, 1, 1 end
        return 0, 0, 1, 1
    end
    env.UnitCastingInfo = function() return nil end
    env.UnitChannelInfo = function() return nil end
    env.UnitSpellHaste = function() return 0 end
    -- Air-slot totem fixture for the twist reconciliation: nil serves
    -- MayReturnNothing (no totem / no client read), otherwise the client's
    -- haveTotem, totemName, startTime, duration, icon, modRate, spellID shape.
    -- fire_totem serves the same shape for the fire slot (Magma maintain).
    env.GetTotemInfo = function(slot)
        if slot == 1 then
            local t = sb.fire_totem
            if t == nil then return nil end
            return t.have, t.name, t.start, t.duration, t.icon, t.modrate, t.spell
        end
        local t = sb.totem
        if slot ~= 4 or t == nil then return nil end
        return t.have, t.name, t.start, t.duration, t.icon, t.modrate, t.spell
    end
    env.RAID_CLASS_COLORS = { SHAMAN = { r = 0.0, g = 0.44, b = 0.87 } }

    local ST = {
        SHAMAN = {},
        player_class = "SHAMAN",
        interfaces_are_initialised = true,
        in_combat = false,
        mainhand = { speed = 3.0, ends_at = 0, start = 0, is_full = false },
        offhand = { has_weapon = false },
        gcd = { expires = 0 },
        latency = { world_ms = 0 },
    }
    local class_db = {
        -- The real SHAMAN defaults (config_presets.lua) plus the guide keys; enabled
        -- here so the display half can be exercised (the shipped default false is
        -- pinned by the text parity section below).
        weave_enabled = true,
        weave_mw_enabled = true,
        weave_marker_size = 6,
        weave_marker_alpha = 1,
        weave_spark_width = 3,
        weave_spark_height = 15,
        weave_spark_alpha = 0.95,
        show_shaman_breakpoint_markers = true,
        show_shaman_windfury_icd = true,
        show_shaman_flame_shock_bar = true,
        show_shaman_cooldown_badges = true,
        show_shaman_shield_charges = true,
        nextaction_enabled = true,
        nextaction_locked = true,
        nextaction_visibility_key = "in_combat",
        nextaction_icon_size = 45,
        nextaction_x = 0,
        nextaction_y = -180,
        guide_flameshock_refresh = 3,
    }
    function ST.get_class_table() return class_db end
    function ST.get_visuals_frame(_, hand)
        if hand == "offhand" then return sb.offhand_visuals end
        return sb.visuals
    end
    function ST.get_bar_visuals_width_and_height() return 100, 15 end
    function ST.get_hand_table()
        return { text_font = "font" }
    end

    local visuals = {}
    function visuals:CreateTexture() return make_texture() end
    function visuals:CreateFontString() return make_fontstring() end
    sb.visuals = visuals
    local offhand_visuals = {}
    function offhand_visuals:CreateTexture() return make_texture() end
    function offhand_visuals:CreateFontString() return make_fontstring() end
    sb.offhand_visuals = offhand_visuals

    local LCG = {}
    function LCG.PixelGlow_Start() end
    function LCG.PixelGlow_Stop() end
    local LSM = {}
    function LSM.Fetch(_, mediatype)
        if mediatype == "border" then return "border_tex" end
        if mediatype == "font" then return "Fonts\\FRIZQT__.TTF" end
        return nil
    end
    env.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { GetAddon = function() return ST end }
        elseif major == "LibCustomGlow-1.0" then
            return LCG
        elseif major == "LibSharedMedia-3.0" then
            return LSM
        end
        return {}
    end

    -- compat.lua reads several legacy globals through _G (annotation-safe on
    -- Mainline-code clients); mirror every sandbox stub for the duration of the loads,
    -- then restore _G exactly.
    local mirrored = {}
    for name, value in pairs(env) do
        mirrored[name] = { present = rawget(_G, name) ~= nil, value = rawget(_G, name) }
        _G[name] = value
    end

    local st = {}
    local modules = opts.modules or MODULES
    for i = 1, #modules do
        local chunk = assert(loadfile(ROOT .. modules[i]))
        setfenv(chunk, env)
        chunk("SwedgeTimer", st)
    end

    for name, previous in pairs(mirrored) do
        _G[name] = previous.value
        if not previous.present then _G[name] = nil end
    end

    sb.env, sb.st, sb.ST, sb.class_db = env, st, ST, class_db
    function sb.advance(dt) sb.clock = sb.clock + dt end
    return sb
end

--=========================================================================================
-- 2) The provider through the real modules: contract shape, post_init, gather
--=========================================================================================
local sandbox = build()
local ST, st = sandbox.ST, sandbox.st
local class_db = sandbox.class_db

check(type(st.shaman_guide) == "table", "the provider sandbox loads the pure engine")
check(type(ST.SHAMAN.guide) == "table", "classes/shaman.lua defines ST.SHAMAN.guide")
check(type(ST.SHAMAN.guide.gather) == "function", "the shaman guide has gather")
check(type(ST.SHAMAN.guide.evaluate) == "function", "the shaman guide has evaluate")
check(type(ST.SHAMAN.resolve_guide_icons) == "function", "the weave-icon resolver is exported")

-- post_init resolves the catalogue + weave icon and builds the frame through the hook.
ST.in_combat = true
ST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
ST.gcd = { expires = 0 }
ST.SHAMAN.post_init(ST)
local ui = st.nextaction_ui
check(ui.frame ~= nil, "post_init builds the guide frame through the real hook")
check(ui.inert ~= true, "the shaman provider is live")
eq(ui.get_provider(ST), ST.SHAMAN.guide, "the shaman guide resolves as the frame's provider")

local slots = ST.SHAMAN.guide.slots
eq(#slots, 10, "ten slots are declared")
local expected_keys = { "stormstrike", "flameshock", "weave", "firenova", "earthshock", "twist",
    "feralspirit", "fireele", "magma", "lavalash" }
local expected_icons = { "icon_ss", "icon_fs", "icon_lb", "icon_nova", "icon_es", "icon_wf",
    "icon_feral", "icon_fireele", "icon_magma", "icon_lavalash" }
for i = 1, #expected_keys do
    eq(slots[i].key, expected_keys[i], "slot " .. i .. " is " .. expected_keys[i])
end
-- Frost Shock has no slot on any family (Flame Shock maintain + Earth Shock
-- filler cover the shock globals).
for i = 1, #slots do
    check(slots[i].key:find("frost") == nil, "slot " .. i .. " is not a frost slot")
end
eq(slots[1].cooldown_key, "stormstrike", "stormstrike's swipe is its client cooldown")
eq(slots[1].swipe_duration, 10, "stormstrike carries the base-cooldown swipe fallback")
eq(slots[2].cooldown_key, "flameshock", "flameshock's swipe is the tracker's debuff window")
eq(slots[2].swipe_duration, 12, "flameshock carries the Flame Shock swipe fallback")
eq(slots[3].cooldown_key, nil, "the weave slot carries no cooldown key")
eq(slots[4].cooldown_key, "firenova", "firenova's swipe is its client cooldown")
eq(slots[4].swipe_duration, 15, "firenova carries the 15 s totem swipe fallback")
eq(slots[5].cooldown_key, nil, "the earthshock slot carries no cooldown key")
eq(slots[6].cooldown_key, nil, "the twist skeleton carries no cooldown key")
eq(slots[7].cooldown_key, "feralspirit", "feralspirit's swipe is its client cooldown")
eq(slots[7].swipe_duration, 180, "feralspirit carries the Feral Spirit swipe fallback")
eq(slots[8].cooldown_key, "fireele", "fireele's swipe is its client cooldown")
eq(slots[8].swipe_duration, 600, "fireele carries the Fire Elemental swipe fallback")
eq(slots[9].cooldown_key, "magma", "magma's swipe is the fire-slot totem window")
eq(slots[9].swipe_duration, 20, "magma carries the totem-window swipe fallback")
eq(slots[10].cooldown_key, "lavalash", "lavalash names its client cooldown")
eq(slots[10].swipe_duration, nil, "lavalash carries no fallback (cooldown unconfirmed)")
eq(slots[1].spell_id, 17364, "stormstrike keeps the spec's id")
eq(slots[2].spell_id, 8050, "flameshock keeps the spec's id")
eq(slots[3].spell_id, 25449, "post_init resolved the weave icon from the catalogue")
eq(slots[4].spell_id, 1535, "firenova keeps the Fire Nova Totem rank-1 id")
eq(slots[5].spell_id, 8042, "earthshock keeps the Earth Shock rank-1 id")
eq(slots[6].spell_id, 8512, "the twist skeleton shows the Windfury Totem id")
eq(slots[7].spell_id, 51533, "feralspirit keeps the Feral Spirit id")
eq(slots[8].spell_id, 2894, "fireele shows the unconfirmed Fire Elemental id")
eq(slots[9].spell_id, 8190, "magma shows the unconfirmed Magma Totem id")
eq(slots[10].spell_id, 60103, "lavalash shows the unconfirmed Lava Lash id")
eq(ST.SHAMAN.guide.labels.next_action, "Next action:", "labels.next_action is the default")
eq(ST.SHAMAN.guide.labels.hold, "HOLD", "labels.hold is the default")
eq(ST.SHAMAN.guide.labels.ride, "RIDE", "labels.ride is the default")
eq(ST.SHAMAN.guide.rotation_key, nil, "no rotation text source is declared")
eq(ST.SHAMAN.guide.rotation_names, nil, "no rotation name map is declared")

-- The frame: one icon per slot, in order.
eq(#ui.icons, 10, "the frame holds one icon per slot")
eq(sandbox.frames, 29, "frame count: group + hold + 10 icons/borders + 7 cooldowns")
for i = 1, #slots do
    eq(ui.icons[i].slot, slots[i], "icon " .. i .. " follows the slot declaration order")
    eq(ui.icons[i].icon.texture.texture, expected_icons[i],
        "icon " .. i .. " shows " .. expected_icons[i])
end
eq(ui.frame.label.text, "Next action:", "the label carries the default caption")
eq(ui.icons[1].remaining_key, "stormstrike_remaining", "the swipe fields derive from the key")
eq(ui.icons[2].duration_key, "flameshock_duration", "the duration field derives from the key")
eq(ui.icons[3].remaining_key, nil, "the weave slot carries no swipe fields")
eq(ui.icons[4].remaining_key, "firenova_remaining", "the firenova swipe fields derive from the key")
eq(ui.icons[5].remaining_key, nil, "the earthshock slot carries no swipe fields")
eq(ui.icons[6].remaining_key, nil, "the twist skeleton carries no swipe fields")
eq(ui.icons[7].remaining_key, "feralspirit_remaining", "the feralspirit swipe fields derive from the key")
eq(ui.icons[8].remaining_key, "fireele_remaining", "the fireele swipe fields derive from the key")
eq(ui.icons[9].remaining_key, "magma_remaining", "the magma swipe fields derive from the key")
eq(ui.icons[10].remaining_key, "lavalash_remaining", "the lavalash swipe fields derive from the key")
eq(ui.icons[10].duration_key, "lavalash_duration", "the lavalash duration field derives from the key")
eq(ui.icons[1].glow_key, nil, "the shaman slots carry no glow")

-- Every possible action output names a declared slot (through the real provider).
-- The sandbox is a TBC client, so the weave actions never appear here (the Wrath
-- block below pins them through the frame instead); the new cooldown/magma feeds
-- default to nil (unknown spells, no WRATH feed), so they fall through exactly
-- like the old chain.
do
    local provider = ST.SHAMAN.guide
    local function action_of(overrides)
        local inputs = inp(overrides)
        -- The provider sandbox is TBC: Maelstrom is unavailable, like the gather feeds.
        inputs.mw_available = false
        local out = {}
        provider.evaluate(inputs, out)
        return out.action
    end
    local actions = {
        action_of({}),
        action_of({ mw_stacks = 5 }),
        action_of({ flameshock_remaining = NONE }),
        action_of({ stormstrike_remaining = 8, mw_stacks = 3 }),
        action_of({ stormstrike_remaining = 8, mw_stacks = 0 }),
        action_of({ stormstrike_remaining = 8, mw_stacks = 0, firenova_remaining = 5 }),
        action_of({ stormstrike_remaining = 0, windfury_icd_remaining = 0.5 }),
        action_of({ twist_remaining = 0 }),
        action_of({ fireele_remaining = 0 }),
        action_of({ feralspirit_remaining = 0 }),
        action_of({ fireele_remaining = 0, feralspirit_remaining = 0 }),
        action_of({ stormstrike_remaining = 8, magma_remaining = 0 }),
        action_of({ stormstrike_remaining = 8, firenova_remaining = 5, lavalash_remaining = 0 }),
    }
    eq(actions[1], "stormstrike", "the provider delegates to the pure engine (stormstrike)")
    eq(actions[2], "stormstrike", "TBC: five stacks fall through to Stormstrike, not the weave")
    eq(actions[3], "flameshock", "the provider delegates to the pure engine (flameshock)")
    eq(actions[4], "firenova", "MW5-only: stacked Maelstrom without MW falls to Fire Nova, never the weave")
    eq(actions[5], "firenova", "the provider delegates to the pure engine (firenova)")
    eq(actions[6], "earthshock", "the provider delegates to the pure engine (earthshock)")
    eq(actions[7], nil, "the fishing hold prompts no slot (WAIT overlay only)")
    eq(actions[8], "twist", "the provider delegates to the pure engine (twist skeleton)")
    eq(actions[9], "fireele", "the provider delegates to the pure engine (fireele)")
    eq(actions[10], "feralspirit", "the provider delegates to the pure engine (feralspirit)")
    eq(actions[11], "fireele", "Fire Elemental outranks Feral Spirit when both are ready")
    eq(actions[12], "magma", "the provider delegates to the pure engine (magma)")
    eq(actions[13], "lavalash", "the provider delegates to the pure engine (lavalash)")
    local all_resolve = true
    for i = 1, #actions do
        if actions[i] ~= nil and ui.slot_index[actions[i]] == nil then
            all_resolve = false
        end
    end
    check(all_resolve, "every action the engine can return names a declared slot")
    local slots_have_keys = true
    for i = 1, #slots do
        if ui.slot_index[slots[i].key] == nil then
            slots_have_keys = false
        end
    end
    check(slots_have_keys, "every declared slot key is frame-addressable")
end

-- The gather into the caller-owned reused table.
sandbox.clock = 100
ST.mainhand = { speed = 3.0, ends_at = 102.0, start = 99.0, is_full = false }
ST.gcd = { expires = 100.5 }
ST.weave_is_casting = false
ST.weave_mw_stacks = 2
ST.weave_fs_duration = 12
ST.weave_fs_expires = 110
sandbox.cooldowns = { [17364] = { start = 100, duration = 8 } }

local gathered_target = {}
local gathered = ST.SHAMAN.guide.gather(ST, gathered_target)
eq(gathered, gathered_target, "gather writes into and returns the caller's table")
eq(gathered.speed, 3.0, "gather: speed")
near(gathered.swing_remaining, 2.0, 1e-9, "gather: swing_remaining")
near(gathered.gcd_remaining, 0.5, 1e-9, "gather: gcd_remaining")
eq(gathered.casting, false, "gather: the cast state")
eq(gathered.mw_stacks, 2, "gather: the Maelstrom stack count")
eq(gathered.weave_available, true, "gather: the resolved catalogue is available")
near(gathered.flameshock_remaining, 10, 1e-9, "gather: the tracker's Flame Shock window")
eq(gathered.flameshock_duration, 12, "gather: the Flame Shock swipe length")
near(gathered.stormstrike_remaining, 8, 1e-9, "gather: the real Stormstrike cooldown")
eq(gathered.stormstrike_duration, 8, "gather: the client-reported cooldown length")
eq(gathered.flameshock_refresh, 3, "gather: the refresh threshold default")

-- The TBC sandbox has no Maelstrom, no Windfury imbue and no totem read: the gate is
-- off, the ICD feed is unknown and the twist stub is nil, while Fire Nova (no
-- cooldown running) reads as ready. The Wrath slots feed nil too (unknown spells,
-- no WRATH magma feed), so the old chain runs unchanged.
eq(gathered.mw_available, false, "gather: TBC has no Maelstrom Weapon")
eq(gathered.windfury_icd_remaining, nil, "gather: no ICD without the imbue")
eq(gathered.firenova_remaining, 0, "gather: Fire Nova reads as ready")
eq(gathered.firenova_duration, nil, "gather: a ready Nova latches no duration")
eq(gathered.twist_remaining, nil, "gather: the twist stub stays nil")
eq(gathered.fireele_remaining, nil, "gather: TBC never feeds Fire Elemental")
eq(gathered.fireele_duration, nil, "gather: and latches no duration")
eq(gathered.feralspirit_remaining, nil, "gather: TBC never feeds Feral Spirit")
eq(gathered.feralspirit_duration, nil, "gather: and latches no duration")
eq(gathered.lavalash_remaining, nil, "gather: TBC never feeds Lava Lash")
eq(gathered.lavalash_duration, nil, "gather: and latches no duration")
eq(gathered.magma_remaining, nil, "gather: TBC never feeds Magma")
eq(gathered.magma_duration, nil, "gather: and latches no duration")
eq(gathered.magma_refresh, 3, "gather: the magma refresh reads the constant")

-- Every slot's always-fed cooldown_key resolves into the gathered inputs (the
-- known-gated Wrath keys and the WRATH-only Magma feed stay nil on TBC).
local always_fed = { stormstrike = true, flameshock = true, firenova = true }
local cooldowns_resolve = true
for i = 1, #slots do
    local key = slots[i].cooldown_key
    if key and always_fed[key] and gathered[key .. "_remaining"] == nil then
        cooldowns_resolve = false
    end
end
check(cooldowns_resolve, "every always-fed slot cooldown_key resolves into the gathered inputs")

-- The Fire Nova read carries the same GCD-echo filter as Stormstrike.
sandbox.cooldowns = { [1535] = { start = 100, duration = 15 } }
local g4 = ST.SHAMAN.guide.gather(ST, gathered_target)
near(g4.firenova_remaining, 15, 1e-9, "gather: the real Fire Nova cooldown")
eq(g4.firenova_duration, 15, "gather: the client-reported Nova length")
sandbox.cooldowns = { [1535] = { start = 100, duration = 1.5 } }
local g5 = ST.SHAMAN.guide.gather(ST, gathered_target)
eq(g5.firenova_remaining, 0, "a ~1.5 s GCD echo is filtered on Nova too")
eq(g5.firenova_duration, nil, "the Nova GCD echo latches no duration")
sandbox.cooldowns = {}

-- The Windfury ICD feed: seconds from the last swing while the imbue is up.
ST.weave_windfury_active = true
local g6 = ST.SHAMAN.guide.gather(ST, gathered_target)
near(g6.windfury_icd_remaining, 2.0, 1e-9, "gather: the Windfury ICD from the last swing")
ST.weave_windfury_active = false
local g7 = ST.SHAMAN.guide.gather(ST, gathered_target)
eq(g7.windfury_icd_remaining, nil, "gather: a dropped imbue clears the ICD feed")

-- The GCD-echo filter on the Stormstrike read.
sandbox.cooldowns = { [17364] = { start = 100, duration = 1.5 } }
local g2 = ST.SHAMAN.guide.gather(ST, gathered_target)
eq(g2.stormstrike_remaining, 0, "a ~1.5 s GCD echo is filtered (remaining 0)")
eq(g2.stormstrike_duration, nil, "the GCD echo latches no duration")
sandbox.cooldowns = { [17364] = { start = 80, duration = 12 } }
local g3 = ST.SHAMAN.guide.gather(ST, gathered_target)
eq(g3.stormstrike_remaining, 0, "an expired cooldown reads as ready")
eq(g3.stormstrike_duration, nil, "an expired cooldown latches no duration")

-- Stale fields are overwritten on the reused table.
ST.weave_is_casting = true
ST.weave_mw_stacks = nil
ST.weave_fs_duration = nil
ST.weave_fs_expires = nil
sandbox.cooldowns = {}
local gathered2 = ST.SHAMAN.guide.gather(ST, gathered_target)
eq(gathered2, gathered_target, "the reused table is the same table")
eq(gathered2.casting, true, "the cast flag is overwritten, not stale")
eq(gathered2.mw_stacks, 0, "an unreadable stack count reads as 0")
eq(gathered2.weave_available, false, "casting withholds the weave availability")
eq(gathered2.flameshock_remaining, nil, "the cleared tracker clears the Flame Shock input")
eq(gathered2.flameshock_duration, nil, "and the stale swipe length")
eq(gathered2.stormstrike_remaining, 0, "the dropped cooldown reads as 0")
eq(gathered2.mw_available, false, "the Maelstrom gate is re-fed, not stale")
eq(gathered2.windfury_icd_remaining, nil, "the ICD feed is re-fed, not stale")
eq(gathered2.firenova_remaining, 0, "the dropped Nova cooldown reads as 0")
eq(gathered2.firenova_duration, nil, "and latches no duration")
eq(gathered2.twist_remaining, nil, "the twist stub is re-fed, not stale")
eq(gathered2.fireele_remaining, nil, "the Fire Elemental feed is re-fed, not stale")
eq(gathered2.fireele_duration, nil, "and latches no duration")
eq(gathered2.feralspirit_remaining, nil, "the Feral Spirit feed is re-fed, not stale")
eq(gathered2.feralspirit_duration, nil, "and latches no duration")
eq(gathered2.lavalash_remaining, nil, "the Lava Lash feed is re-fed, not stale")
eq(gathered2.lavalash_duration, nil, "and latches no duration")
eq(gathered2.magma_remaining, nil, "the Magma feed is re-fed, not stale")
eq(gathered2.magma_duration, nil, "and latches no duration")
eq(gathered2.magma_refresh, 3, "the magma refresh is re-fed, not stale")

-- The refresh threshold rides the options.
class_db.guide_flameshock_refresh = 6
eq(ST.SHAMAN.guide.gather(ST, gathered_target).flameshock_refresh, 6,
    "the refresh threshold rides the options")
class_db.guide_flameshock_refresh = nil
eq(ST.SHAMAN.guide.gather(ST, gathered_target).flameshock_refresh, 3,
    "a missing option falls back to the 3 s default")
class_db.guide_flameshock_refresh = 3

-- Direct calls without an out table use the module's own reused table.
local own = ST.SHAMAN.gather_guide_inputs(ST)
eq(own, ST.SHAMAN.guide_inputs, "gather without an out table uses the module's reused table")

-- The merged aura walk feeds the Maelstrom stacks the rules read.
do
    sandbox.auras = {
        { name = "Maelstrom Weapon", count = 3, duration = 30, expiration = 0,
            source = "player", spell_id = 53817 },
    }
    ST.SHAMAN.on_aura_change(ST)
    eq(ST.weave_mw_stacks, 3, "the aura walk refreshes the Maelstrom stacks")
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).mw_stacks, 3,
        "the refreshed stacks reach the frozen input")
    sandbox.auras = {}
    ST.SHAMAN.on_aura_change(ST)
    eq(ST.weave_mw_stacks, 0, "a dropped aura clears the stacks")
end

-- The tracker feeds the guide's frozen Flame Shock input (and the throttled target
-- scan keeps running while the guide is enabled even with the bar off).
do
    ST.weave_is_casting = false
    sandbox.target_auras = {
        { name = "Flame Shock", count = 1, duration = 12, expiration = sandbox.clock + 10,
            source = "player", spell_id = 8050 },
    }
    class_db.show_shaman_flame_shock_bar = false
    sandbox.target_aura_calls = 0
    local function tick(advance)
        ST.mainhand.ends_at = sandbox.clock + 3.0
        sandbox.advance(advance or 0.1)
        ST.SHAMAN.on_bar_update(ST, "mainhand")
    end
    tick()
    tick()
    check(sandbox.target_aura_calls > 0,
        "the guide keeps the target scan alive with the Flame Shock bar off")
    near(ST.SHAMAN.guide.gather(ST, gathered_target).flameshock_remaining, 10, 0.2,
        "the tracker feeds flameshock_remaining")
    -- With the guide off too, the bar-off configuration reads no target auras.
    class_db.nextaction_enabled = false
    sandbox.target_aura_calls = 0
    tick()
    eq(sandbox.target_aura_calls, 0,
        "with the guide off too, the bar-off configuration reads no target auras")
    class_db.nextaction_enabled = true
    class_db.show_shaman_flame_shock_bar = true
    -- A cleared target clears the frozen input on the very next gather.
    sandbox.target_auras = {}
    tick()
    tick()
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).flameshock_remaining, nil,
        "a cleared target clears the stale Flame Shock input")
end

-- The totem-twist live feed (TBC): SUCCEEDED commits and the air-slot clock flow
-- into twist_remaining; every other family stays nil (byte-identical).
do
    ST.weave_is_casting = false
    ST.weave_mw_stacks = 0
    ST.weave_windfury_active = false
    ST.weave_twist_last_drop = nil
    sandbox.cooldowns = {}
    sandbox.totem = nil

    -- A Windfury commit stamps now: the full period is left.
    ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-tw-live", 8512)
    near(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, 10, 1e-9,
        "gather: a fresh twist commit reads the full period")
    -- An unconfirmed rank stamps through its live spell name, not the id table.
    ST.weave_twist_last_drop = nil
    ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-tw-rank", 10613)
    near(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, 10, 1e-9,
        "gather: an unconfirmed twist rank stamps by spell name")
    -- Grace of Air stamps through the name token.
    ST.weave_twist_last_drop = nil
    ST.SHAMAN.on_spellcast_succeeded(ST, "player", "Grace of Air Totem", 99999)
    near(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, 10, 1e-9,
        "gather: Grace of Air stamps by name token")

    -- Due (a full period elapsed): the engine answers twist with a healthy Flame
    -- Shock and a ready Stormstrike (rules 3 and 6 both pass it by).
    ST.weave_twist_last_drop = sandbox.clock - 10
    ST.weave_fs_duration = 12
    ST.weave_fs_expires = sandbox.clock + 10
    local due = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(due.twist_remaining, 0, "gather: a period-old drop reads due")
    local due_out = {}
    ST.SHAMAN.guide.evaluate(due, due_out)
    eq(due_out.action, "twist", "rule 4: a due twist prompts the twist slot")

    -- Not due (3 s elapsed): the chain falls past the twist to Stormstrike.
    ST.weave_twist_last_drop = sandbox.clock - 3
    local fresh = ST.SHAMAN.guide.gather(ST, gathered_target)
    near(fresh.twist_remaining, 7, 1e-9, "gather: a fresh drop counts down")
    local fresh_out = {}
    ST.SHAMAN.guide.evaluate(fresh, fresh_out)
    eq(fresh_out.action, "stormstrike", "a twist that is not due falls to Stormstrike")

    -- The air-slot clock backfills an unknown stamp (mid-twist load): 4 s of a
    -- 10 s period elapsed. A non-twist totem and an absent read stay unknown.
    ST.weave_twist_last_drop = nil
    sandbox.totem = { have = true, name = "Grace of Air Totem", start = sandbox.clock - 4 }
    near(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, 6, 1e-9,
        "gather: the air-slot clock backfills an unknown stamp")
    ST.weave_twist_last_drop = nil
    sandbox.totem = { have = true, name = "Searing Totem", start = sandbox.clock - 4 }
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, nil,
        "gather: a non-twist air totem never feeds the twist")
    sandbox.totem = nil

    -- Non-TBC families stay nil even with a due drop (byte-identical).
    ST.weave_twist_last_drop = sandbox.clock - 10
    sandbox.st.family = "WRATH"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, nil,
        "gather: Wrath never feeds the twist despite a due drop")
    sandbox.st.family = "ERA"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, nil,
        "gather: Era never feeds the twist despite a due drop")
    sandbox.st.family = "TBC"

-- The Wrath cooldown feeds: known-gated (unknown ids stay nil on every family),
-- the Magma stamp model through SUCCEEDED + the fire-slot clock, and the no-twist
-- pin (a due twist drop never feeds outside TBC).
do
    sandbox.st.family = "WRATH"
    ST.weave_is_casting = false
    ST.weave_mw_stacks = 0
    ST.weave_magma_last_drop = nil
    sandbox.cooldowns = {}
    sandbox.fire_totem = nil

    -- Unknown spells feed nil (the UNCONFIRMED-id shape on a client without them).
    sandbox.known = { [25449] = true, [25442] = true }
    local unknown = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(unknown.fireele_remaining, nil, "gather: an unknown Fire Elemental feeds nil")
    eq(unknown.feralspirit_remaining, nil, "gather: an unknown Feral Spirit feeds nil")
    eq(unknown.lavalash_remaining, nil, "gather: an unknown Lava Lash feeds nil")

    -- Known and ready: remaining 0, no duration latched.
    sandbox.known[51533] = true
    sandbox.known[2894] = true
    sandbox.known[60103] = true
    local ready = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(ready.feralspirit_remaining, 0, "gather: a ready Feral Spirit reads 0")
    eq(ready.feralspirit_duration, nil, "gather: a ready Feral Spirit latches no duration")
    eq(ready.fireele_remaining, 0, "gather: a ready Fire Elemental reads 0")
    eq(ready.lavalash_remaining, 0, "gather: a ready Lava Lash reads 0")

    -- Known and on cooldown: the real remaining + client length ride.
    sandbox.cooldowns = { [51533] = { start = sandbox.clock, duration = 180 } }
    local cooling = ST.SHAMAN.guide.gather(ST, gathered_target)
    near(cooling.feralspirit_remaining, 180, 1e-9, "gather: the real Feral Spirit cooldown")
    eq(cooling.feralspirit_duration, 180, "gather: the client-reported Feral length")

    -- The GCD echo is filtered on the known gate too.
    sandbox.cooldowns = { [51533] = { start = sandbox.clock, duration = 1.5 } }
    local echo = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(echo.feralspirit_remaining, 0, "a ~1.5 s GCD echo is filtered on Feral Spirit too")
    eq(echo.feralspirit_duration, nil, "the Feral GCD echo latches no duration")
    sandbox.cooldowns = {}
    -- Back to unknown for the Magma leg below (a ready cooldown slot would
    -- outrank Magma and shadow the assertions).
    sandbox.known[51533] = nil
    sandbox.known[2894] = nil
    sandbox.known[60103] = nil

    -- Magma: unknown stamp + unreadable slot feeds nil (never prompts on a guess).
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).magma_remaining, nil,
        "gather: an unknown Magma drop with no totem read feeds nil")

    -- A Magma SUCCEEDED commit stamps now: the full window is left.
    ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-magma-live", 8190)
    near(ST.SHAMAN.guide.gather(ST, gathered_target).magma_remaining, 20, 1e-9,
        "gather: a fresh Magma commit reads the full window")
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).magma_duration, 20,
        "gather: the Magma window rides as the swipe length")

    -- Due (a full window elapsed): the engine answers magma with SS down.
    ST.weave_magma_last_drop = sandbox.clock - 20
    ST.weave_fs_duration = 12
    ST.weave_fs_expires = sandbox.clock + 10
    sandbox.cooldowns = { [17364] = { start = sandbox.clock, duration = 8 } }
    local magma_due = ST.SHAMAN.guide.gather(ST, gathered_target)
    eq(magma_due.magma_remaining, 0, "gather: a window-old Magma drop reads due")
    local magma_due_out = {}
    ST.SHAMAN.guide.evaluate(magma_due, magma_due_out)
    eq(magma_due_out.action, "magma", "rule 9: a due Magma prompts the magma slot")

    -- Inside the refresh window: still magma; past it: Nova.
    ST.weave_magma_last_drop = sandbox.clock - 18
    local refresh_in = ST.SHAMAN.guide.gather(ST, gathered_target)
    near(refresh_in.magma_remaining, 2, 1e-9, "gather: a drop 18 s ago reads 2 s left")
    local refresh_out = {}
    ST.SHAMAN.guide.evaluate(refresh_in, refresh_out)
    eq(refresh_out.action, "magma", "a Magma inside the refresh window still prompts")

    -- The fire-slot clock backfills an unknown stamp (mid-fight load): 4 s of a
    -- 20 s window elapsed. A non-Magma fire totem and an absent read stay unknown.
    ST.weave_magma_last_drop = nil
    sandbox.fire_totem = { have = true, name = "Magma Totem", start = sandbox.clock - 4 }
    near(ST.SHAMAN.guide.gather(ST, gathered_target).magma_remaining, 16, 1e-9,
        "gather: the fire-slot clock backfills an unknown stamp")
    ST.weave_magma_last_drop = nil
    sandbox.fire_totem = { have = true, name = "Searing Totem", start = sandbox.clock - 4 }
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).magma_remaining, nil,
        "gather: a non-Magma fire totem never feeds Magma")
    sandbox.fire_totem = nil

    -- An affirmatively empty fire slot feeds due (the initial drop prompt).
    sandbox.fire_totem = { have = false }
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).magma_remaining, 0,
        "gather: an affirmatively empty fire slot reads due")
    eq(ST.weave_magma_last_drop, nil, "the empty slot clears the stale stamp")
    sandbox.fire_totem = nil

    -- Non-Wrath families stay nil even with a due drop (byte-identical).
    ST.weave_magma_last_drop = sandbox.clock - 20
    sandbox.st.family = "TBC"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).magma_remaining, nil,
        "gather: TBC never feeds Magma despite a due drop")
    sandbox.st.family = "ERA"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).magma_remaining, nil,
        "gather: Era never feeds Magma despite a due drop")
    sandbox.st.family = "WRATH"
    near(ST.SHAMAN.guide.gather(ST, gathered_target).magma_remaining, 0, 1e-9,
        "gather: Wrath feeds the due drop again")

    -- No-twist on Wrath: a due twist drop still feeds nil (Wrath never twists).
    ST.weave_twist_last_drop = sandbox.clock - 10
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, nil,
        "gather: Wrath never feeds the twist despite a due drop")
    local no_twist = ST.SHAMAN.guide.gather(ST, gathered_target)
    local no_twist_out = {}
    ST.SHAMAN.guide.evaluate(no_twist, no_twist_out)
    check(no_twist_out.action ~= "twist", "Wrath: a due twist drop never prompts the twist slot")

    -- Fixture restored: TBC client, no live aura, stamps cleared.
    ST.weave_twist_last_drop = nil
    ST.weave_magma_last_drop = nil
    ST.weave_fs_duration = nil
    ST.weave_fs_expires = nil
    sandbox.totem = nil
    sandbox.fire_totem = nil
    sandbox.cooldowns = {}
    sandbox.known = { [25449] = true, [25442] = true }
    sandbox.st.family = "TBC"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, nil,
        "gather: the restored fixture reads unknown again")
end
end

-- The Forever adaptation (docs/research/forever_beta.md, all UNCONFIRMED): no
-- twisting (party-buff totem model - totems coexist with imbues, so there is no
-- weapon-enchant twist to prompt).
do
    ST.weave_is_casting = false
    ST.weave_mw_stacks = 0
    ST.weave_mw_observed = false
    ST.weave_windfury_active = false
    ST.weave_twist_last_drop = nil
    ST.weave_fs_duration = 12
    ST.weave_fs_expires = sandbox.clock + 10
    sandbox.cooldowns = {}
    sandbox.totem = nil
    sandbox.st.family = "FOREVER"

    -- A due drop still feeds nil (nothing to alternate on Forever).
    ST.weave_twist_last_drop = sandbox.clock - 10
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, nil,
        "gather: Forever never feeds the twist despite a due drop")
    -- The air-slot clock cannot backfill it either.
    ST.weave_twist_last_drop = nil
    sandbox.totem = { have = true, name = "Windfury Totem", start = sandbox.clock - 4 }
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, nil,
        "gather: the air-slot clock never feeds the twist on Forever")
    sandbox.totem = nil

    -- The tick answers Stormstrike behind the nil feed, never the twist slot.
    local no_twist = ST.SHAMAN.guide.gather(ST, gathered_target)
    local no_twist_out = {}
    ST.SHAMAN.guide.evaluate(no_twist, no_twist_out)
    eq(no_twist_out.action, "stormstrike",
        "Forever: the tick answers Stormstrike, never the twist slot")

    -- Fixture restored: TBC client, no live aura, stamps cleared.
    ST.weave_mw_stacks = 0
    ST.weave_mw_observed = false
    ST.weave_twist_last_drop = nil
    ST.weave_fs_duration = nil
    ST.weave_fs_expires = nil
    sandbox.cooldowns = {}
    sandbox.totem = nil
    sandbox.st.family = "TBC"
    eq(ST.SHAMAN.guide.gather(ST, gathered_target).twist_remaining, nil,
        "gather: the restored fixture reads unknown again")
end

-- The Lightning Bolt fallback when the catalogue resolves nothing.
do
    local fallback = build({ known = {} })
    -- A pre-init gather never errors (the weave catalogue does not exist yet).
    local pre = fallback.ST.SHAMAN.gather_guide_inputs(fallback.ST, {})
    eq(pre.weave_available, false, "a pre-init gather answers weave_available=false")
    fallback.ST.SHAMAN.post_init(fallback.ST)
    local fslots = fallback.ST.SHAMAN.guide.slots
    eq(fslots[3].spell_id, 403, "an unresolved catalogue keeps the Lightning Bolt fallback")
    local fui = fallback.st.nextaction_ui
    eq(fui.icons[3].icon.texture.texture, "icon_lb_r1",
        "the fallback icon resolves through GetSpellInfo")
    local fgathered = fallback.ST.SHAMAN.guide.gather(fallback.ST, {})
    eq(fgathered.weave_available, false, "an unresolved catalogue is not weave-available")
end

--=========================================================================================
-- 3) The display mapping through the real frame and the real hooks
--=========================================================================================
sandbox.clock = 201
ST.mainhand = { speed = 3.0, ends_at = 0, start = 0, is_full = false }
ST.gcd = { expires = 0 }
ST.weave_is_casting = false
ST.weave_mw_stacks = 0
ST.weave_fs_duration = nil
ST.weave_fs_expires = nil
sandbox.cooldowns = {}

local function tick(advance)
    ST.mainhand.ends_at = sandbox.clock + 3.0
    sandbox.advance(advance or 0.1)
    ST.SHAMAN.on_bar_update(ST, "mainhand")
end
local function target(key)
    return ui.icons[ui.slot_index[key]].fade.target
end
local function slot_icon(key)
    return ui.icons[ui.slot_index[key]].icon
end

-- The casting hold wins over everything.
ST.weave_is_casting = true
ST.weave_mw_stacks = 5
sandbox.cooldowns = {}
tick()
eq(target("weave"), 0, "a cast in flight suppresses the weave prompt")
eq(target("stormstrike"), 0, "a cast in flight suppresses Stormstrike")
eq(ui.frame.hold.fade.target, 1, "the cast in flight shows the hold overlay")
eq(ui.frame.hold.text.text, "RIDE", "the casting hold reads RIDE")
eq(ui.frame.shown, true, "the in-combat tick shows the frame")
eq(ST.weave_mw_stacks, 5, "the stacks survive the cast")

-- Five stacks buy no prompt on TBC: with Maelstrom unavailable the fallthrough lands
-- on the untracked Flame Shock instead of the weave slot.
ST.weave_is_casting = false
tick()
eq(target("weave"), 0, "TBC: five stacks never light the weave slot")
eq(target("flameshock"), 1, "TBC: the fallthrough lights the Flame Shock slot")
eq(ui.frame.hold.fade.target, 0, "the hold overlay clears")

-- An untracked Flame Shock, then a short one (its swipe follows the tracker).
ST.weave_mw_stacks = 0
sandbox.cooldowns = { [17364] = { start = sandbox.clock, duration = 8 } }
tick()
eq(target("flameshock"), 1, "an untracked Flame Shock lights the Flame Shock slot")
eq(target("weave"), 0, "and the weave slot clears")
sandbox.target_auras = {
    { name = "Flame Shock", count = 1, duration = 12, expiration = sandbox.clock + 2,
        source = "player", spell_id = 8050 },
}
tick()
tick()
eq(target("flameshock"), 1, "a Flame Shock inside the window stays suggested")
eq(slot_icon("flameshock").cooldown.cooldown_duration, 12,
    "the tracker's debuff length drives the Flame Shock swipe")
eq(slot_icon("flameshock").cooldown.cooldown_sets, 1, "the Flame Shock swipe is set once")
eq(slot_icon("flameshock").cooldown_set, true, "the Flame Shock swipe latch is armed")
tick()
eq(slot_icon("flameshock").cooldown.cooldown_sets, 1, "the swipe latch holds across ticks")
sandbox.target_auras = {
    { name = "Flame Shock", count = 1, duration = 12, expiration = sandbox.clock + 10,
        source = "player", spell_id = 8050 },
}
tick()
tick()
eq(slot_icon("flameshock").cooldown.cooldown_sets, 2, "a healthy Flame Shock clears the swipe")
eq(slot_icon("flameshock").cooldown.cooldown_duration, 0, "the clear is a zero-length cooldown")
eq(slot_icon("flameshock").cooldown_set, false, "the swipe latch resets on clear")

-- A healthy Flame Shock with SS ready -> Stormstrike (and no swipe while ready).
sandbox.cooldowns = {}
tick()
eq(target("flameshock"), 0, "a healthy Flame Shock clears its slot")
eq(target("stormstrike"), 1, "with SS ready the guide suggests Stormstrike")

-- SS down + three stacks: no weave without Maelstrom; Fire Nova answers instead.
-- (The Flame Shock cache above is healthy again, so Nova - not the refresh - wins.)
sandbox.cooldowns = { [17364] = { start = sandbox.clock, duration = 8 } }
ST.weave_mw_stacks = 3
tick()
eq(target("stormstrike"), 0, "a running SS cooldown clears the Stormstrike slot")
eq(target("weave"), 0, "TBC: 3 stacks with SS down do not light the weave slot")
eq(target("firenova"), 1, "TBC: Fire Nova answers while Stormstrike is down")
ST.weave_mw_stacks = 2
tick()
eq(target("firenova"), 1, "2 stacks still answer Fire Nova (no stacks needed)")
eq(target("earthshock"), 0, "and the shock filler stays dark behind Nova")

-- Five stacks still buy nothing with SS down either.
ST.weave_mw_stacks = 5
tick()
eq(target("weave"), 0, "TBC: 5 stacks do not outrank a running SS cooldown")
eq(target("firenova"), 1, "Fire Nova still answers")
ST.weave_mw_stacks = 0

-- Fire Nova on cooldown: the Earth Shock filler answers.
sandbox.cooldowns[1535] = { start = sandbox.clock, duration = 15 }
tick()
eq(target("firenova"), 0, "a running Fire Nova cooldown clears its slot")
eq(target("earthshock"), 1, "the shock filler answers with everything else down")
eq(ui.frame.hold.fade.target, 0, "the filler carries no hold")
sandbox.cooldowns[1535] = nil
tick()
eq(target("firenova"), 1, "a ready Nova prompts again")
eq(target("earthshock"), 0, "and the filler yields to it")

-- Delay-if-fishing-WF: Stormstrike ready, Flame Shock healthy, but the Windfury ICD
-- clears inside this swing -> WAIT, no prompt.
sandbox.cooldowns = {}
sandbox.target_auras = {
    { name = "Flame Shock", count = 1, duration = 12, expiration = sandbox.clock + 10,
        source = "player", spell_id = 8050 },
}
ST.weave_windfury_active = true
ST.mainhand = { speed = 3.0, ends_at = sandbox.clock + 3.0, start = sandbox.clock - 2.5,
    is_full = false }
tick()
tick()
eq(ui.frame.hold.fade.target, 1, "the fishing hold shows the overlay")
eq(ui.frame.hold.text.text, "WAIT", "the fishing hold reads WAIT")
eq(target("stormstrike"), 0, "the held Stormstrike stays dark")
eq(target("flameshock"), 0, "a healthy Flame Shock stays dark behind the hold")
eq(target("firenova"), 0, "and Fire Nova stays dark behind the hold")

-- With the ICD elapsed the same tick prompts Stormstrike instead.
ST.mainhand = { speed = 3.0, ends_at = sandbox.clock + 3.0, start = sandbox.clock - 3.0,
    is_full = false }
tick()
eq(target("stormstrike"), 1, "with the ICD elapsed the guide prompts Stormstrike")
eq(ui.frame.hold.fade.target, 0, "the hold overlay clears")
ST.weave_windfury_active = false

-- The twist slot stays dark with no drop known: neither a commit nor the air-slot
-- clock has fed twist_remaining (the live feed is pinned above).
eq(target("twist"), 0, "the twist slot stays dark with no known drop")

-- Wrath through the real frame: the MW5 prompt survives, the MW3 hardcast is
-- gone (MW5-only), the cooldown slots light in research order, and Wrath never
-- twists (then back to TBC for the option gates below).
sandbox.st.family = "WRATH"
ST.weave_is_casting = false
ST.weave_mw_stacks = 5
sandbox.cooldowns = {}
sandbox.target_auras = {}
tick()
tick()
eq(target("weave"), 1, "Wrath: five stacks light the weave slot")
eq(target("flameshock"), 0, "Wrath: the instant weave outranks the Flame Shock refresh")
ST.weave_mw_stacks = 3
sandbox.cooldowns = { [17364] = { start = sandbox.clock, duration = 8 } }
sandbox.target_auras = {
    { name = "Flame Shock", count = 1, duration = 12, expiration = sandbox.clock + 10,
        source = "player", spell_id = 8050 },
}
tick()
tick()
eq(target("weave"), 0, "Wrath: 3 stacks with SS down no longer light the weave slot")
eq(target("firenova"), 1, "Wrath: 3 stacks with SS down fall to Fire Nova")
-- The cooldown slots light in research order (Fire Ele > Feral > MW5).
sandbox.known[51533] = true
sandbox.known[2894] = true
ST.weave_mw_stacks = 5
sandbox.cooldowns = {}
tick()
tick()
eq(target("fireele"), 1, "Wrath: a ready Fire Elemental lights its slot")
eq(target("feralspirit"), 0, "Wrath: Feral Spirit stays dark behind Fire Elemental")
eq(target("weave"), 0, "Wrath: Fire Elemental outranks the 5-stack weave")
sandbox.known[2894] = nil
tick()
tick()
eq(target("feralspirit"), 1, "Wrath: a ready Feral Spirit lights its slot")
eq(target("fireele"), 0, "Wrath: an unknown Fire Elemental stays dark")
eq(target("weave"), 0, "Wrath: Feral Spirit outranks the 5-stack weave")
-- Magma due lights its slot with SS down (an affirmatively empty fire slot).
sandbox.known[51533] = nil
ST.weave_mw_stacks = 0
sandbox.cooldowns = { [17364] = { start = sandbox.clock, duration = 8 } }
ST.weave_magma_last_drop = nil
sandbox.fire_totem = { have = false }
tick()
tick()
eq(target("magma"), 1, "Wrath: an empty fire slot lights the magma slot")
eq(target("firenova"), 0, "Wrath: Magma outranks Fire Nova")
-- Lava Lash answers with SS and Nova down and a fresh Magma.
sandbox.fire_totem = nil
ST.weave_magma_last_drop = sandbox.clock
sandbox.cooldowns = {
    [17364] = { start = sandbox.clock, duration = 8 },
    [1535] = { start = sandbox.clock, duration = 15 },
}
sandbox.known[60103] = true
tick()
tick()
eq(target("lavalash"), 1, "Wrath: a ready Lava Lash answers with SS and Nova down")
eq(target("earthshock"), 0, "Wrath: the shock filler stays dark behind Lava Lash")
-- No-twist on Wrath through the frame: a due drop lights nothing.
ST.weave_twist_last_drop = sandbox.clock - 10
tick()
eq(target("twist"), 0, "Wrath: a due twist drop never lights the twist slot")
eq(target("lavalash"), 1, "Wrath: the tick still answers Lava Lash behind it")
sandbox.st.family = "TBC"
ST.weave_mw_stacks = 0
ST.weave_twist_last_drop = nil
ST.weave_magma_last_drop = nil
sandbox.fire_totem = nil
sandbox.known = { [25449] = true, [25442] = true }
sandbox.cooldowns = {}
sandbox.target_auras = {}

-- SoD through the real frame: ERA shares the token but HAS the MW rune, so
-- the aura-observed latch re-enables the MW rules; Era-base (never observed)
-- falls through exactly like TBC; the option stays the kill-switch.
sandbox.st.family = "ERA"
ST.weave_mw_observed = false
ST.weave_is_casting = false
ST.weave_mw_stacks = 5
sandbox.cooldowns = {}
sandbox.target_auras = {}
tick()
tick()
eq(target("weave"), 0, "Era-base: five stacks never light the weave slot")
eq(target("flameshock"), 1, "Era-base: the fallthrough lights the Flame Shock slot")
eq(ST.SHAMAN.guide.gather(ST, gathered_target).mw_available, false,
    "Era-base: the gather reports MW unavailable")

-- The rune aura latches through the real hook and re-enables rule 2.
sandbox.auras = {
    { name = "Maelstrom Weapon", count = 5, spell_id = 408505 },
}
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_mw_stacks, 5, "SoD: the rune aura refreshes the stacks")
eq(ST.weave_mw_observed, true, "SoD: the rune aura latches observed")
eq(ST.SHAMAN.guide.gather(ST, gathered_target).mw_available, true,
    "SoD: the gather reports MW available")
tick()
tick()
eq(target("weave"), 1, "SoD: five stacks light the weave slot")

-- Rule 7 (MW>=3 hardcast) is gone: 3 stacks with SS down fall to Fire Nova.
sandbox.auras = {
    { name = "Maelstrom Weapon", count = 3, spell_id = 408505 },
}
ST.SHAMAN.on_aura_change(ST)
sandbox.cooldowns = { [17364] = { start = sandbox.clock, duration = 8 } }
sandbox.target_auras = {
    { name = "Flame Shock", count = 1, duration = 12, expiration = sandbox.clock + 10,
        source = "player", spell_id = 8050 },
}
tick()
tick()
eq(target("weave"), 0, "SoD: 3 stacks with SS down no longer light the weave slot")
eq(target("firenova"), 1, "SoD: 3 stacks with SS down fall to Fire Nova")

-- The option stays the kill-switch even when observed.
class_db.weave_mw_enabled = false
eq(ST.SHAMAN.guide.gather(ST, gathered_target).mw_available, false,
    "SoD: option-off reports MW unavailable despite the latch")
tick()
eq(target("weave"), 0, "SoD: option-off suppresses the weave slot despite the latch")
class_db.weave_mw_enabled = true

-- Fixture restored: TBC client, no live aura, latch cleared.
sandbox.auras = {}
ST.SHAMAN.on_aura_change(ST)
ST.weave_mw_observed = false
sandbox.st.family = "TBC"
ST.weave_mw_stacks = 0
sandbox.cooldowns = {}
sandbox.target_auras = {}

-- SoD Lava Burst choice: on ERA the weave slot re-points at the rune when the
-- client knows it, and keeps the catalogue without it (Era-base byte-identical).
do
    local lava = build()
    lava.st.family = "ERA"
    lava.ST.SHAMAN.post_init(lava.ST)
    eq(lava.ST.SHAMAN.guide.slots[3].spell_id, 51505,
        "SoD: the weave slot re-points at Lava Burst when the rune is known")
    eq(lava.ST.SHAMAN.guide.slots[3].key, "weave",
        "SoD: the re-point keeps the weave slot identity")
    local saved_lava = SPELL_INFOS[51505]
    SPELL_INFOS[51505] = nil
    local base = build()
    base.st.family = "ERA"
    base.ST.SHAMAN.post_init(base.ST)
    eq(base.ST.SHAMAN.guide.slots[3].spell_id, 25449,
        "Era-base: without the rune the weave slot keeps the catalogue")
    SPELL_INFOS[51505] = saved_lava
end

-- Option gates: disabled hides the frame and stops the mapping; visibility follows the
-- in-combat key; the size/position/lock diff applies live.
sandbox.cooldowns = {}
tick()
local before_disable = target("stormstrike")
class_db.nextaction_enabled = false
tick()
eq(ui.frame.shown, false, "nextaction_enabled=false hides the frame")
eq(target("stormstrike"), before_disable, "the gated tick leaves the slot targets alone")
class_db.nextaction_enabled = true
tick()
eq(ui.frame.shown, true, "re-enabling brings the frame back")
class_db.nextaction_visibility_key = "always"
ST.in_combat = false
tick()
eq(ui.frame.shown, true, "the always visibility key keeps the frame out of combat")
class_db.nextaction_visibility_key = "in_combat"
tick()
eq(ui.frame.shown, false, "the in_combat key hides the frame out of combat")
ST.in_combat = true
tick()
eq(ui.frame.shown, true, "back in combat the frame returns")

class_db.nextaction_icon_size = 60
class_db.nextaction_locked = false
tick()
near(ui.frame.scale, 60 / 45, 1e-9, "the icon-size option rescales the live frame")
eq(ST.guide_ui_icon_size, 60, "the settings diff latches the applied size")
eq(ui.frame.movable, true, "unlocking makes the frame movable")
class_db.nextaction_x = 25
class_db.nextaction_icon_size = 45
class_db.nextaction_locked = true
tick()
near(ui.frame.scale, 1, 1e-9, "the size option restores the scale")
eq(ui.frame.movable, false, "locking makes the frame immovable again")
eq(ui.frame.points and ui.frame.points[1][4], 25, "the position option moves the live frame")

-- The hand gates: an offhand call only mirrors the spark, never ticks the guide.
local before_offhand = target("stormstrike")
sandbox.advance(1.0)
ST.SHAMAN.on_bar_update(ST, "offhand")
eq(target("stormstrike"), before_offhand, "the offhand call does not tick the guide")

--=========================================================================================
-- 4) Config/options parity, the TOC load order and the drive call sites
--=========================================================================================
do
    local function read(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text
    end

    local presets = read("config_presets.lua")
    local shaman_defaults = presets:match("ST%.SHAMAN%.defaults%s*=%s*%{(.-)ST%.WARLOCK%.defaults") or ""
    local options = read("option_tables.lua")
    local shaman_opts = options:match("function ST%.class_opts_funcs%.SHAMAN%((.-)function ST:generate_bar_position_options_table") or ""

    local expected_defaults = {
        nextaction_enabled = "false",
        nextaction_locked = "true",
        nextaction_visibility_key = "\"in_combat\"",
        nextaction_icon_size = "45",
        nextaction_x = "0",
        nextaction_y = "-180",
        guide_flameshock_refresh = "3",
    }
    for key, value in pairs(expected_defaults) do
        check(shaman_defaults:find("%f[%a_]" .. key .. "%s*=%s*" .. value, 1) ~= nil,
            "config_presets.lua: SHAMAN default " .. key .. " = " .. value)
    end

    local widget_types = {
        nextaction_enabled = "toggle",
        nextaction_locked = "toggle",
        nextaction_visibility_key = "select",
        nextaction_icon_size = "range",
        nextaction_x = "input",
        nextaction_y = "input",
        guide_flameshock_refresh = "range",
    }
    for key, wtype in pairs(widget_types) do
        local widget = shaman_opts:match("%f[%a_]" .. key .. "%s*=%s*{(.-)\n%s*}")
        check(widget ~= nil and widget:find("type%s*=%s*\"" .. wtype .. "\"") ~= nil,
            "option_tables.lua: " .. key .. " has a " .. wtype .. " widget")
    end
    check(shaman_opts:find("Next Action Guide") ~= nil,
        "option_tables.lua: the shaman options carry a Next Action Guide block")
    local fs_widget = shaman_opts:match("guide_flameshock_refresh%s*=%s*{(.-)\n%s*}") or ""
    check(fs_widget:find("min%s*=%s*0[^%d]") ~= nil and fs_widget:find("max%s*=%s*10") ~= nil,
        "option_tables.lua: guide_flameshock_refresh is a 0-10 range")

    -- shaman_guide.lua loads after nextaction.lua in every TOC.
    local tocs = { "SwedgeTimer.toc", "SwedgeTimer_Vanilla.toc", "SwedgeTimer_TBC.toc",
        "SwedgeTimer_Wrath.toc", "SwedgeTimer_Mainline.toc", "SwedgeTimer_Cata.toc",
        "SwedgeTimer_Mists.toc" }
    for i = 1, #tocs do
        local text = read(tocs[i])
        local after = text:find("\nnextaction.lua", 1, true)
        local guide_at = text:find("\nshaman_guide.lua", 1, true)
        check(after ~= nil and guide_at ~= nil and guide_at > after,
            tocs[i] .. ": shaman_guide.lua loads after nextaction.lua")
    end

    -- The drive call sites live in classes/shaman.lua.
    local shaman_src = read("classes/shaman.lua")
    check(shaman_src:find("st%.nextaction_ui%.init%(self%)") ~= nil,
        "classes/shaman.lua: post_init drives st.nextaction_ui.init")
    check(shaman_src:find("st%.nextaction_ui%.on_bar_update%(self, hand%)") ~= nil,
        "classes/shaman.lua: on_bar_update drives st.nextaction_ui.on_bar_update")
    check(shaman_src:find("st%.nextaction_ui%.apply_settings%(self%)") ~= nil,
        "classes/shaman.lua: the settings diff applies live")
    check(shaman_src:find("self%.SHAMAN%.resolve_guide_icons%(self%)") ~= nil,
        "classes/shaman.lua: post_init drives the weave-icon resolver")
    check(shaman_src:find("ST%.SHAMAN%.gather_guide_inputs%(self, out%)") ~= nil,
        "classes/shaman.lua: the provider delegates to the gather")
    check(shaman_src:find("st%.weave%.has_maelstrom_weapon%(st%.family,") ~= nil,
        "classes/shaman.lua: the MW gate feeds the family plus the observed latch")
    check(shaman_src:find("weave_mw_observed%s*=%s*true") ~= nil,
        "classes/shaman.lua: the aura scan latches the observed MW signal")
    check(shaman_src:find("weave_mw_observed%s*=%s*false") ~= nil,
        "classes/shaman.lua: post_init clears the observed MW latch")
    check(shaman_src:find("get_windfury_icd_remaining%(d%.start, now%)") ~= nil,
        "classes/shaman.lua: the gather feeds the Windfury ICD")
    check(shaman_src:find("inputs%.twist_remaining = nil") ~= nil,
        "classes/shaman.lua: the gather re-feeds the twist input every tick")
    check(shaman_src:find("WEAVE_FERAL_SPIRIT_SPELL_ID") ~= nil,
        "classes/shaman.lua: the Feral Spirit slot id is declared")
    check(shaman_src:find("WEAVE_FIRE_ELEMENTAL_SPELL_ID") ~= nil,
        "classes/shaman.lua: the Fire Elemental slot id is declared")
    check(shaman_src:find("WEAVE_MAGMA_TOTEM_SPELL_ID") ~= nil,
        "classes/shaman.lua: the Magma Totem slot id is declared")
    check(shaman_src:find("WEAVE_LAVA_LASH_SPELL_ID") ~= nil,
        "classes/shaman.lua: the Lava Lash slot id is declared")
    check(shaman_src:find("get_guide_cooldown_known") ~= nil,
        "classes/shaman.lua: the cooldown slots are known-gated")
    check(shaman_src:find("refresh_magma_from_totems") ~= nil,
        "classes/shaman.lua: the Magma fire-slot reconciliation is wired")
    check(shaman_src:find("weave_magma_last_drop%s*=%s*nil") ~= nil,
        "classes/shaman.lua: post_init clears the Magma stamp")
    check(shaman_src:find("Lava Burst") ~= nil,
        "classes/shaman.lua: the SoD Lava Burst re-point is wired")
    check(shaman_src:find("inputs%.magma_refresh") ~= nil,
        "classes/shaman.lua: the gather re-feeds the magma refresh every tick")

    -- The engine's frozen shape: ten actions max, no MW>=3 hardcast, no frost.
    local guide_src = read("shaman_guide.lua")
    check(guide_src:find("mw_stacks >= 3", 1, true) == nil,
        "shaman_guide.lua: no MW>=3 hardcast rule survives (MW5-only)")
    check(guide_src:find("\"magma\"", 1, true) ~= nil,
        "shaman_guide.lua: the magma action is declared")
    check(guide_src:find("\"lavalash\"", 1, true) ~= nil,
        "shaman_guide.lua: the lavalash action is declared")
    check(guide_src:find("\"fireele\"", 1, true) ~= nil,
        "shaman_guide.lua: the fireele action is declared")
    check(guide_src:find("\"feralspirit\"", 1, true) ~= nil,
        "shaman_guide.lua: the feralspirit action is declared")
    check(guide_src:find("MAGMA_REFRESH_DEFAULT", 1, true) ~= nil,
        "shaman_guide.lua: the magma refresh constant is declared")
    local weave_src = read("weave.lua")
    check(weave_src:find("get_magma_remaining", 1, true) ~= nil,
        "weave.lua: the Magma remaining helper is declared")
    check(weave_src:find("MAGMA_TOTEM_DURATION_SECONDS", 1, true) ~= nil,
        "weave.lua: the Magma duration constant is declared")
    check(weave_src:find("WINDFURY_MAX_PROCS_PER_MINUTE", 1, true) ~= nil,
        "weave.lua: the Windfury proc-ceiling constant is declared")
    check(weave_src:find("is_windfury_proc_capped", 1, true) ~= nil,
        "weave.lua: the proc-ceiling helper is declared")
    check(weave_src:find("TOTEM_TWIST_PULSE_SECONDS", 1, true) ~= nil,
        "weave.lua: the twist-pulse constant is declared")
    check(weave_src:find("is_totem_twist_family", 1, true) ~= nil,
        "weave.lua: the twist-family gate is declared")
    check(shaman_src:find("is_totem_twist_family", 1, true) ~= nil,
        "classes/shaman.lua: the twist feed is gated through the pure helper")
    check(shaman_src:find("Rage of the Farseer", 1, true) ~= nil,
        "classes/shaman.lua: the Farseer lust leg is wired")
end

--=========================================================================================
-- Retail (12.x) inertness: the stand-in never swings, but the cast flag, the
-- absent-debuff default and the idle-cooldown defaults answer on Retail - every
-- such shape must stay empty.
--=========================================================================================
do
    local saved_family = pure.family
    pure.family = "RETAIL"
    -- The baseline (ready Stormstrike) stays silent.
    local out = evaluate({})
    eq(out.action, nil, "retail: a ready Stormstrike never prompts")
    eq(out.hold, false, "retail: a ready Stormstrike never holds")
    -- The Flame Shock refresh (nil always refreshes) stays silent.
    eq(evaluate({ flameshock_remaining = NONE }).action, nil,
        "retail: a missing Flame Shock never prompts")
    -- A cast in flight never rides.
    local casting = evaluate({ casting = true })
    eq(casting.action, nil, "retail: a cast in flight never prompts")
    eq(casting.hold, false, "retail: a cast in flight never rides")
    eq(casting.hold_text, nil, "retail: a cast in flight carries no RIDE text")
    -- Five Maelstrom stacks never weave, even with availability forged on.
    eq(evaluate({ mw_stacks = 5, mw_available = true }).action, nil,
        "retail: five Maelstrom stacks never prompt")
    -- The shock filler (Fire Nova on cooldown, Stormstrike down) never prompts.
    eq(evaluate({ stormstrike_remaining = 5, firenova_remaining = 0 }).action, nil,
        "retail: Fire Nova never prompts")
    -- The Wrath slots never prompt either, ready or not.
    eq(evaluate({ fireele_remaining = 0 }).action, nil,
        "retail: a ready Fire Elemental never prompts")
    eq(evaluate({ feralspirit_remaining = 0 }).action, nil,
        "retail: a ready Feral Spirit never prompts")
    eq(evaluate({ stormstrike_remaining = 8, magma_remaining = 0 }).action, nil,
        "retail: a due Magma never prompts")
    eq(evaluate({ stormstrike_remaining = 8, firenova_remaining = 5,
        lavalash_remaining = 0 }).action, nil,
        "retail: a ready Lava Lash never prompts")
    eq(out.waiting_judgement, false, "retail: the judgement carry stays false")
    -- A stale out table is fully overwritten (no frozen field survives).
    local stale = { action = "stormstrike", hold = true, hold_text = "WAIT",
        filler_slot = "stormstrike", judge_slot = "x", rotation_key = "y",
        waiting_judgement = true }
    local ret = sg.evaluate(inp({}), stale)
    eq(ret, stale, "retail: evaluate returns the caller's out table")
    eq(stale.action, nil, "retail: a stale action is cleared")
    eq(stale.hold, false, "retail: a stale hold is cleared")
    eq(stale.hold_text, nil, "retail: stale hold text is cleared")
    eq(stale.filler_slot, nil, "retail: a stale filler_slot is cleared")
    eq(stale.judge_slot, nil, "retail: a stale judge_slot is cleared")
    eq(stale.rotation_key, nil, "retail: a stale rotation_key is cleared")
    eq(stale.waiting_judgement, false, "retail: a stale judgement carry is cleared")
    -- The gate is Retail-specific: any other family still prompts.
    pure.family = "WRATH"
    eq(evaluate({}).action, "stormstrike",
        "non-retail family: a ready Stormstrike still prompts")
    pure.family = saved_family
end

if failures == 0 then
    print("PASS  shaman_guide_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  shaman_guide_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end

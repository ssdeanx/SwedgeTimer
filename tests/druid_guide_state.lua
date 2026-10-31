-- tests/druid_guide_state.lua: offline tests for the druid next-action guide: the
-- pure rule engine (druid_guide.lua) and the provider glue + drive (classes/druid.lua)
-- over the real compat.lua + utils.lua + nextaction_ui.lua + druid_energy.lua in a
-- sandbox.
--
-- Pins:
--   * druid_guide.lua loads with NO WoW API at all (a strict sandbox errors on any
--     global read) and the frozen rule matrix: bear Maul/RIDE/Mangle with the
--     rage-cost boundary and the shortfall veto (Era waits instead of Mangling),
--     the cat Rip/Rake/Mangle/Bite/Shred
--     chain with the exact 4.0 s refresh boundaries and the combo 4/5 boundary,
--     unknown forms never guessing a bear/cat action,
--   * the frozen output fields are overwritten on every call (stale fields can never
--     survive into a reused out table) and nil inputs never error,
--   * the TBC cat branch (inputs.family == "TBC"): Rake never prompted, the
--     4+ CP expiry-only Rip, the long-fight 5CP Rip (never Bite), the
--     short-lived-only Bite (10 s sim threshold), the 40/42 energy gates, the
--     wait terminal and the TBC constants (the old >20-short SHIFT hold was
--     removed with its constant: no honest shift probe exists),
--   * Tiger's Fury is never an ACTION anywhere (no slot exists); the families
--     without a mid-rotation TF rule never hold for it either (WRATH and
--     ERA-with-runes hold TIGER'S FURY by design),
--   * the ERA cat branch (inputs.family == "ERA"): Clearcasting first, the
--     5CP expiry-only Rip (never Bite - the sim has no Bite branch), the
--     ungated Shred, the bear wait terminal, and the exact-match gate
--     (lowercase stays legacy),
--   * every non-TBC, non-Era, non-Wrath family (and a missing family) runs the
--     legacy matrix byte-for-byte: the refresh windows, the untracked Rake, the
--     ungated Mangle/Shred and the default Bite,
--   * the WRATH cat branch (inputs.family == "WRATH"): the dynamic TF hold
--     (40 - 10 * leeway), the Berserk hold off a 15 s TF cooldown with Rip up
--     and no proc (no energy gate), the >=1 CP Savage Roar upkeep hold,
--     Clearcasting ahead of the finishers, the 5 CP expiry-only Rip, Mangle
--     above Rake, the Rip+Roar-guarded 4 s Bite, the Shred default - and never
--     a SHIFT hold (no powershifting) nor a TF/Berserk/Roar action (no slot
--     exists; the hold overlay carries them),
--   * the SOD cat branch (inputs.family == "ERA" with sod_runes): the <=40
--     TF hold, Berserk-after-TF, the Roar refresh plus the cover-to-end clip,
--     Omen Shred, the 5 CP expiry-only Rip (never clipped for TF), the
--     Mangle/Rake order, the ungated Shred (no Bite branch at all) - and the
--     strict sod_runes == true gate plus the SoD bear Mangle (never the Era
--     wait),
--   * the gather writes the family plus the finisher inputs - the D4 EMA-smoothed
--     time_to_die (seeded, smoothed, throttled, reset per target/heal/death; nil
--     whenever the target's health is unreadable) - and the explicit
--     target_short_lived / reserved can_powershift nil (no rule reads it) with
--     stale overwrites, plus the Wrath/SoD buff/cooldown inputs (sr_remaining,
--     clearcast, tf_active, tf_ready, tf_cd_remaining, berserk_ready,
--     sod_runes) with the knowledge-gated cooldowns and the session-latched
--     SoD probe (id-first, locale-independent, with the name fallback),
--     and the ERA-token SoD display through a real Era sandbox,
--   * the gather into the caller-owned reused table: every frozen input, the
--     form-specific power reads (1 rage / 3 energy / 4 combo), the rank-resolved Maul
--     cost, the tracker-fed debuff windows, stale-field overwrites and the option
--     thresholds,
--   * the merged target scan keeps running while the guide is enabled even with every
--     debuff bar switched off (and stays idle with the guide off too),
--   * the provider contract shape (slot keys, six slots, cooldown keys resolving into
--     the gathered inputs, possible actions naming declared slots),
--   * the display mapping through the real frame sandbox (action -> slot -> fade
--     targets, the RIDE hold, debuff-fed swipes and their latch, the option gates),
--   * the config/options parity for every new druid key and the TOC load order,
--   * the drive wiring (post_init -> ui.init, on_bar_update -> the settings diff +
--     ui.on_bar_update) exercised through the real hooks.
-- Run from the repo root: lua5.1 tests/druid_guide_state.lua  (any cwd works).

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
            error("druid_guide.lua touched a global: " .. tostring(key))
        end,
    })
    local chunk = assert(loadfile(ROOT .. "druid_guide.lua"))
    setfenv(chunk, strict)
    local ok, err = pcall(chunk, "SwedgeTimer", pure)
    check(ok, "druid_guide.lua loads with no WoW API and no globals (" .. tostring(err) .. ")")
end

local dg = pure.druid_guide
check(type(dg) == "table", "druid_guide.lua defines st.druid_guide")
check(type(dg.evaluate) == "function", "the pure engine is exported")
eq(dg.RIP_REFRESH_DEFAULT, 4, "the Rip refresh default is 4")
eq(dg.RAKE_REFRESH_DEFAULT, 4, "the Rake refresh default is 4")

-- Rule-matrix inputs: everything the frozen input set names, with a bear baseline that
-- lands on Maul (rage 50 >= cost 15). NONE clears a key (a nil literal in an override
-- table is simply absent in Lua).
local NONE = {}
local function inp(overrides)
    local t = {
        speed = 3.0, swing_remaining = 2.0, gcd_remaining = 0,
        form_index = 1, rage = 50, energy = 60, combo_points = 0,
        maul_queued = false, maul_cost = 15, insufficient_rage = false,
        rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        rip_refresh = 4, rake_refresh = 4,
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
    local ret = dg.evaluate(inp(overrides), out)
    eq(ret, out, "evaluate returns the caller's out table")
    return out
end

-- Bear baseline: rage covers the Maul cost -> Maul.
do
    local out = evaluate({})
    eq(out.action, "maul", "baseline: rage covers the Maul cost -> Maul")
    eq(out.hold, false, "baseline: no hold")
    eq(out.hold_text, nil, "baseline: no hold text")
    eq(out.filler_slot, nil, "baseline: filler_slot stays nil")
    eq(out.judge_slot, nil, "baseline: judge_slot stays nil")
    eq(out.rotation_key, nil, "baseline: rotation_key stays nil")
    eq(out.waiting_judgement, false, "baseline: waiting_judgement stays false")
end

-- Rule 1: the queued Maul ride. RIDE is the guide's PRESS-NOTHING hold: the queued
-- Maul already rides the next swing, so the player presses NO key. The verdict names
-- no action - the practice layer states it as a hold, never as an action (the
-- deep-audit's H1).
do
    local out = evaluate({ maul_queued = true })
    eq(out.action, nil, "rule 1: a queued Maul is not re-suggested")
    eq(out.hold, true, "rule 1: a queued Maul holds")
    eq(out.hold_text, "RIDE", "rule 1: the queued Maul reads RIDE")
    eq(evaluate({ maul_queued = true, rage = NONE }).hold_text, "RIDE",
        "rule 1 outranks the rage rules")
    eq(evaluate({ maul_queued = true, form_index = 3, rip_remaining = NONE }).action, "rip",
        "rule 1 is bear-only: a queued flag in cat form changes nothing")
end

-- Rule 2/3: the rage-cost boundary, the shortfall veto and the unknown-input fallback.
do
    eq(evaluate({ rage = 15, maul_cost = 15 }).action, "maul",
        "rule 2 boundary: rage exactly equal to the cost is sufficient")
    eq(evaluate({ rage = 14.99, maul_cost = 15 }).action, "mangle",
        "rule 2 boundary: rage just below the cost falls to Mangle")
    eq(evaluate({ rage = 15, maul_cost = 15, insufficient_rage = true }).action, "mangle",
        "rule 2: the shortfall flag vetoes a numeric proof")
    eq(evaluate({ rage = 50, maul_cost = NONE }).action, "mangle",
        "rule 2: an unreadable cost cannot prove a Maul")
    eq(evaluate({ rage = NONE, maul_cost = 15 }).action, "mangle",
        "rule 2: unreadable rage cannot prove a Maul")
    eq(evaluate({ rage = NONE, maul_cost = NONE }).action, "mangle",
        "rule 2: both unreadable still lands on the Mangle fallback")
    local out = evaluate({ rage = 14.99, maul_cost = 15 })
    eq(out.hold, false, "rule 3: the Mangle fallback is an action, not a hold")
    eq(out.hold_text, nil, "rule 3: the Mangle fallback carries no hold text")
    eq(evaluate({ form_index = 1, maul_queued = false }).action, "maul",
        "rule 2: the bear branch is reachable with a plain numeric baseline")
end

-- Rules 4-8: the cat chain and its boundaries.
do
    eq(evaluate({ form_index = 3, rip_remaining = NONE }).action, "rip",
        "rule 4: an untracked Rip -> Rip")
    eq(evaluate({ form_index = 3, rip_remaining = 4 }).action, "rip",
        "rule 4 boundary: Rip exactly at 4.0 s refreshes")
    eq(evaluate({ form_index = 3, rip_remaining = 4.000001, rake_remaining = 5,
        mangle_remaining = 6 }).action, "shred",
        "rule 4 boundary: just above 4.0 s falls through the whole chain")
    eq(evaluate({ form_index = 3, rip_remaining = 5, rake_remaining = NONE }).action, "rake",
        "rule 5: an untracked Rake after a healthy Rip -> Rake")
    eq(evaluate({ form_index = 3, rip_remaining = 5, rake_remaining = 4 }).action, "rake",
        "rule 5 boundary: Rake exactly at 4.0 s refreshes")
    eq(evaluate({ form_index = 3, rip_remaining = 5, rake_remaining = 4.000001,
        mangle_remaining = 6 }).action, "shred",
        "rule 5 boundary: just above 4.0 s falls through the whole chain")
    eq(evaluate({ form_index = 3, rip_remaining = 5, rake_remaining = 5,
        mangle_remaining = NONE }).action, "mangle",
        "rule 6: an absent Mangle -> Mangle")
    eq(evaluate({ form_index = 3, rip_remaining = 5, rake_remaining = 5,
        mangle_remaining = 0.5 }).action, "shred",
        "rule 6: a running Mangle never refreshes (no window; only nil prompts it)")
    eq(evaluate({ form_index = 3, rip_remaining = 5, rake_remaining = 5,
        mangle_remaining = 6, combo_points = 4 }).action, "shred",
        "rule 7 boundary: 4 combo points cannot Bite")
    eq(evaluate({ form_index = 3, rip_remaining = 5, rake_remaining = 5,
        mangle_remaining = 6, combo_points = 5 }).action, "bite",
        "rule 7 boundary: 5 combo points -> Ferocious Bite")
    eq(evaluate({ form_index = 3, rip_remaining = 5, rake_remaining = 5,
        mangle_remaining = 6, combo_points = NONE }).action, "shred",
        "rule 7: an unreadable combo count cannot clear the threshold -> Shred")
    eq(evaluate({ form_index = 3, rip_remaining = 5, rake_remaining = 5,
        mangle_remaining = 6, combo_points = 5.5 }).action, "bite",
        "rule 7: above 5 combo points still Bites")
end

-- The refresh thresholds ride the inputs.
do
    eq(evaluate({ form_index = 3, rip_remaining = 4.5, rip_refresh = 5 }).action, "rip",
        "a custom Rip refresh widens the window")
    eq(evaluate({ form_index = 3, rip_remaining = 5.5, rip_refresh = 5,
        rake_remaining = NONE }).action, "rake",
        "and just outside it the chain moves on")
    eq(evaluate({ form_index = 3, rip_remaining = 5, rake_remaining = 4.5,
        rake_refresh = 5 }).action, "rake",
        "a custom Rake refresh widens the window")
    eq(evaluate({ form_index = 3, rip_remaining = 4.5, rip_refresh = NONE,
        rake_remaining = NONE }).action, "rake",
        "a missing Rip threshold falls back to 4")
    eq(evaluate({ form_index = 3, rip_remaining = 5, rake_remaining = 4.5,
        rake_refresh = 0, mangle_remaining = 6 }).action, "shred",
        "a zero Rake threshold still requires an absent-or-zero debuff")
    eq(evaluate({ form_index = 3, rip_remaining = 0, rip_refresh = 0 }).action, "rip",
        "a remaining of exactly 0 refreshes")
end

-- Unknown forms / rule 9 / frozen fields / nil-safety.
do
    eq(evaluate({ form_index = 0 }).action, nil, "an unshifted druid gets no action")
    eq(evaluate({ form_index = 2 }).action, nil, "form 2 (aquatic) gets no action")
    eq(evaluate({ form_index = 4 }).action, nil, "form 4 (travel) gets no action")
    eq(evaluate({ form_index = 5 }).action, nil, "form 5 (moonkin/tree) gets no action")
    eq(evaluate({ form_index = 6 }).action, nil, "form 6 (flight) gets no action")
    eq(evaluate({ form_index = NONE }).action, nil, "an unreadable form gets no action")
    eq(evaluate({ form_index = "3" }).action, nil, "a non-numeric form gets no action")
    eq(evaluate({ form_index = 0, maul_queued = true }).hold, false,
        "an unknown form cannot even ride a stale queue flag")
    eq(evaluate({ form_index = 5 }).hold, false, "an unknown form never holds")

    local out = {
        action = "stale", hold = "stale", hold_text = "STALE", filler_slot = "stale",
        judge_slot = "stale", rotation_key = "stale", waiting_judgement = true,
    }
    dg.evaluate(inp({ form_index = 0 }), out)
    eq(out.action, nil, "a reused out table has action overwritten")
    eq(out.hold, false, "a reused out table has hold overwritten")
    eq(out.hold_text, nil, "a reused out table has hold_text overwritten")
    eq(out.filler_slot, nil, "a reused out table has filler_slot overwritten")
    eq(out.judge_slot, nil, "a reused out table has judge_slot overwritten")
    eq(out.rotation_key, nil, "a reused out table has rotation_key overwritten")
    eq(out.waiting_judgement, false, "a reused out table has waiting_judgement overwritten")

    local ok, err = pcall(dg.evaluate)
    check(ok, "evaluate with no arguments does not error (" .. tostring(err) .. ")")
    ok, err = pcall(dg.evaluate, nil, nil)
    check(ok, "evaluate(nil, nil) does not error (" .. tostring(err) .. ")")
    local fallback = dg.evaluate(inp({}))
    eq(fallback.action, "maul", "evaluate can allocate its own out table")

    local frozen = inp({})
    local before_rage = frozen.rage
    dg.evaluate(frozen, {})
    eq(frozen.rage, before_rage, "evaluate never writes back into its inputs")

    local NaN = 0 / 0
    eq(evaluate({ form_index = NaN }).action, nil,
        "a NaN form cannot match any rule")
    eq(evaluate({ form_index = 1, rage = NaN }).action, "mangle",
        "a NaN rage cannot prove sufficiency")
    eq(evaluate({ form_index = 3, rip_remaining = NaN, rake_remaining = 5,
        mangle_remaining = 6 }).action, "shred",
        "a NaN Rip remaining cannot match the refresh rule")
end

--=========================================================================================
-- 1) Sandbox: compat + utils + nextaction_ui + druid_guide + druid_energy + classes/druid
--=========================================================================================
local SPELL_INFOS = {
    [6807] = { name = "Maul", icon = "icon_maul_r1" },
    [48480] = { name = "Maul", icon = "icon_maul" },
    [33983] = { name = "Mangle", icon = "icon_mangle_cat" },
    [33987] = { name = "Mangle", icon = "icon_mangle_bear" },
    [1079] = { name = "Rip", icon = "icon_rip" },
    [1822] = { name = "Rake", icon = "icon_rake" },
    [22568] = { name = "Ferocious Bite", icon = "icon_bite" },
    [5221] = { name = "Shred", icon = "icon_shred" },
    [9850] = { name = "Claw", icon = "icon_claw" },
    [5217] = { name = "Tiger's Fury", icon = "icon_tf" },
    [50334] = { name = "Berserk", icon = "icon_berserk" },
    [52610] = { name = "Savage Roar", icon = "icon_sr" },
    [16870] = { name = "Clearcasting", icon = "icon_omen" },
}

local MODULES = { "compat.lua", "utils.lua", "guard.lua", "nextaction_ui.lua", "druid_guide.lua",
    "druid_energy.lua", "classes/druid.lua" }

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
        rage = 50,
        energy = 60,
        combo = 0,
        power = 0,
        power_type = 0,
        rage_cost = { { cost = 15 } },
        cooldowns = {},
        target_auras = opts.target_auras or {},
        player_auras = opts.player_auras or {},
        -- Spell names the fixture client KNOWS (knowledge-level, for the SoD
        -- rune name fallback and the TF/Berserk known gates: id-keyed
        -- SPELL_INFOS above is data-existence, this is the spellbook).
        known_names = opts.known_names or {},
        -- Spell ids the fixture client KNOWS (knowledge-level, for the SoD
        -- rune id probe: SPELL_INFOS id keys are data-existence, this is the
        -- spellbook - so known_ids without known_names is the non-enUS
        -- client, where no English name lookup can answer).
        known_ids = opts.known_ids or {},
        -- Cooldown readings by query (id or name) -> { start, duration }.
        cooldowns_by_query = opts.cooldowns or {},
        -- D4 time-to-die inputs: the target's identity and live health, as the
        -- client would report them (nil = no target / unreadable health).
        target_guid = opts.target_guid,
        target_hp = opts.target_hp,
        hide_spells = false,
        get_spell_info_calls = 0,
        cost_queries = 0,
        last_cost_id = nil,
        unit_power_calls = 0,
        last_power_type = nil,
        target_aura_calls = 0,
        player_aura_calls = 0,
        cooldown_queries = 0,
        form = 0,
    }

    local env = setmetatable({}, { __index = _G })
    env.WOW_PROJECT_ID = opts.project or 11
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
    -- Spell data is bidirectional on the NAME families, like a real client: a name the
    -- id form answered is itself a query form. TBC Anniversary and Wrath/Titanforge
    -- state queries take that localized NAME (operator ruling). Era (and the other id
    -- families) keep the old shape: a name answers only through known_names, which is
    -- how this fixture models the SoD rune's spell-data presence.
    local name_query_family = opts.project == 5 or opts.project == 11 or opts.project == nil
    local name_to_id = {}
    env.GetSpellInfo = function(spell)
        sb.get_spell_info_calls = sb.get_spell_info_calls + 1
        if sb.hide_spells then
            return nil
        end
        if sb.missing_spells and sb.missing_spells[spell] then
            return nil
        end
        if type(spell) == "string" and sb.missing_names and sb.missing_names[spell] then
            return nil
        end
        if type(spell) == "string" then
            -- Knowledge-level: a name answers for a known spell (the SoD rune probe
            -- and the TF/Berserk known gates), and the client also answers the name
            -- its own id form handed out (spell data is bidirectional).
            if sb.known_names[spell] then
                return spell, nil, "icon_" .. spell, 0, 0, 0, 0
            end
            local id = name_query_family and name_to_id[spell] or nil
            if id ~= nil then
                local info = SPELL_INFOS[id]
                if info then
                    return info.name, nil, info.icon, 0, 0, 0, id
                end
            end
            return nil
        end
        local info = SPELL_INFOS[spell]
        if info then
            name_to_id[info.name] = spell
            return info.name, nil, info.icon, 0, 0, 0, spell
        end
        return nil
    end
    env.GetSpellPowerCost = function(id)
        sb.cost_queries = sb.cost_queries + 1
        sb.last_cost_id = id
        return sb.rage_cost
    end
    -- Knowledge-level id probe (compat resolves IsSpellKnown dynamically
    -- through _G, like the warrior fixture): only known_ids answers true. A NAME token
    -- resolves through the client's own spell data first (the TBC/Wrath query form).
    env.IsSpellKnown = function(id)
        if sb.known_ids[id] then
            return true
        end
        if type(id) == "string" then
            local _, _, _, _, _, _, resolved = env.GetSpellInfo(id)
            if type(resolved) == "number" and sb.known_ids[resolved] then
                return true
            end
        end
        return nil
    end
    env.UnitPower = function(unit, power_type)
        sb.unit_power_calls = sb.unit_power_calls + 1
        sb.last_power_type = power_type
        if power_type == 1 then return sb.rage end
        if power_type == 3 then return sb.energy end
        if power_type == 4 then return sb.combo end
        return sb.power
    end
    env.UnitPowerType = function() return sb.power_type end
    env.UnitAura = function(unit, index, filter)
        if unit == "player" then
            sb.player_aura_calls = sb.player_aura_calls + 1
            local pentry = sb.player_auras[index]
            if not pentry then return nil end
            return pentry.name, nil, pentry.count, nil, pentry.duration,
                pentry.expiration, pentry.source, nil, nil, pentry.spell_id
        end
        if unit ~= "target" then
            return nil
        end
        sb.target_aura_calls = sb.target_aura_calls + 1
        local entry = sb.target_auras[index]
        if not entry then return nil end
        return entry.name, nil, entry.count, nil, entry.duration, entry.expiration,
            entry.source, nil, nil, entry.spell_id
    end
    env.GetSpellCooldown = function(query)
        sb.cooldown_queries = sb.cooldown_queries + 1
        local entry = sb.cooldowns_by_query[query]
        if entry then
            return entry[1], entry[2], 1, 1
        end
        return 0, 0, 0, 0
    end
    env.IsCurrentSpell = function() return false end
    env.GetShapeshiftForm = function() return sb.form end
    env.GetTalentInfo = function() return "Talent", nil, 1, 1, 0, 1 end
    env.InCombatLockdown = function() return false end
    -- D4: the target identity and health the sampler reads (UnitHealth through
    -- compat's wrapper, UnitGUID captured by the class module directly). Defaults
    -- nil keep every pre-D4 test on the "no readable target" shape.
    env.UnitHealth = function(unit)
        if unit ~= "target" then return nil end
        return sb.target_hp
    end
    env.UnitGUID = function(unit)
        if unit ~= "target" then return "Player-1" end
        return sb.target_guid
    end

    local ST = {
        DRUID = {},
        player_class = "DRUID",
        interfaces_are_initialised = true,
        in_combat = false,
        form_index = 0,
        mainhand = { speed = 3.0, ends_at = 0, start = 0, is_full = false },
        gcd = { expires = 0 },
    }
    local class_db = {
        -- The real DRUID defaults (config_presets.lua), so a wrong colour is a module
        -- bug and not a fixture bug. The guide keys are the new ones; enabled=true here
        -- so the display half can be exercised (the shipped default false is pinned by
        -- the text parity section below).
        enable_maul_color = true,
        maul_color = { 112, 19, 189, 1.0 },
        insufficient_rage_color = { 140, 140, 140, 1.0 },
        show_druid_energy_tick = true,
        druid_energy_tick_color = { 255, 209, 46, 1.0 },
        show_druid_form_label = true,
        show_druid_mangle_bar = true,
        druid_mangle_bar_color = { 230, 153, 26, 0.90 },
        show_druid_rip_bar = true,
        druid_rip_bar_color = { 51, 191, 51, 0.90 },
        show_druid_rake_bar = true,
        druid_rake_bar_color = { 217, 102, 26, 0.90 },
        nextaction_enabled = true,
        nextaction_locked = true,
        nextaction_visibility_key = "in_combat",
        nextaction_icon_size = 45,
        nextaction_x = 0,
        nextaction_y = -180,
        guide_rip_refresh = 4,
        guide_rake_refresh = 4,
    }
    function ST.get_class_table() return class_db end
    function ST.get_visuals_frame() return sb.visuals end
    function ST.get_bar_visuals_width_and_height() return 100, 20 end
    function ST.get_hand_table()
        return { text_font = "font" }
    end
    function ST.convert_color(_, t, new_alpha)
        local r, g, b, a = unpack(t)
        a = new_alpha or a
        return r / 255, g / 255, b / 255, a
    end
    function ST.set_bar_color() return false end

    local visuals = {}
    function visuals:CreateTexture() return make_texture() end
    function visuals:CreateFontString() return make_fontstring() end
    sb.visuals = visuals

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
        -- Class files register their body as a loader (operator order 2026-10-21:
        -- only the selected class executes). This sandbox activates the class it
        -- loads, exactly as main.lua does at init.
        local class = modules[i]:match("classes/(%a+)%.lua")
        if class and type(st.class_loaders) == "table"
            and type(st.class_loaders[class:upper()]) == "function" then
            st.class_loaders[class:upper()]()
        end
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

check(type(st.druid_guide) == "table", "the provider sandbox loads the pure engine")
check(type(ST.DRUID.guide) == "table", "classes/druid.lua defines ST.DRUID.guide")
check(type(ST.DRUID.guide.gather) == "function", "the druid guide has gather")
check(type(ST.DRUID.guide.evaluate) == "function", "the druid guide has evaluate")
check(type(ST.DRUID.resolve_guide_icons) == "function", "the rank resolver is exported")

-- post_init resolves the rank icons and builds the frame through the real hook.
ST.in_combat = true
ST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
ST.gcd = { expires = 0 }
ST.DRUID.post_init(ST)
local ui = st.nextaction_ui
check(ui.frame ~= nil, "post_init builds the guide frame through the real hook")
check(ui.inert ~= true, "the druid provider is live")
eq(ui.get_provider(ST), ST.DRUID.guide, "the druid guide resolves as the frame's provider")

local slots = ST.DRUID.guide.slots
eq(#slots, 7, "seven slots are declared (six originals + Claw)")
check(#slots <= 8, "the slot set stays within the frame's contract (paladin ships eight)")
local expected_keys = { "maul", "mangle", "rip", "rake", "bite", "shred", "claw" }
local expected_icons = { "icon_maul", "icon_mangle_bear", "icon_rip", "icon_rake",
    "icon_bite", "icon_shred", "icon_claw" }
for i = 1, #expected_keys do
    eq(slots[i].key, expected_keys[i], "slot " .. i .. " is " .. expected_keys[i])
end
eq(slots[1].cooldown_key, nil, "maul carries no cooldown key (no swipe source)")
eq(slots[2].cooldown_key, "mangle", "mangle's swipe source is the tracker")
eq(slots[2].swipe_duration, 12, "mangle's swipe fallback is the tracker duration")
eq(slots[3].cooldown_key, "rip", "rip's swipe source is the tracker")
eq(slots[3].swipe_duration, 12, "rip's swipe fallback is the tracker duration")
eq(slots[4].cooldown_key, "rake", "rake's swipe source is the tracker")
eq(slots[4].swipe_duration, 9, "rake's swipe fallback is the tracker duration")
eq(slots[5].cooldown_key, nil, "bite carries no cooldown key")
eq(slots[6].cooldown_key, nil, "shred carries no cooldown key")
eq(slots[1].spell_id, 48480, "post_init resolved Maul to the client's current rank")
eq(slots[2].spell_id, 33987, "post_init resolved Mangle through the module's id table")
eq(slots[3].spell_id, 1079, "rip keeps the spec's id")
eq(slots[4].spell_id, 1822, "rake keeps the spec's id")
eq(slots[5].spell_id, 22568, "bite keeps the spec's id")
eq(slots[6].spell_id, 5221, "shred keeps the spec's id")
eq(slots[7].key, "claw", "the seventh slot is the Forever builder Claw")
eq(slots[7].spell_id, 9850, "claw keeps the sim's Forever id (no rank table)")
eq(ST.DRUID.guide.labels.next_action, "Next action:", "labels.next_action is the default")
eq(ST.DRUID.guide.labels.hold, "HOLD", "labels.hold is the default")
eq(ST.DRUID.guide.labels.ride, "RIDE", "labels.ride is the default")
eq(ST.DRUID.guide.rotation_key, nil, "no rotation text source is declared")
eq(ST.DRUID.guide.rotation_names, nil, "no rotation name map is declared")

-- The frame: one icon per slot, in order.
eq(#ui.icons, 7, "the frame holds one icon per slot")
eq(sandbox.frames, 19, "frame count: group + 7 icons/borders + 3 cooldowns + hold")
for i = 1, #slots do
    eq(ui.icons[i].slot, slots[i], "icon " .. i .. " follows the slot declaration order")
    eq(ui.icons[i].icon.texture.texture, expected_icons[i],
        "icon " .. i .. " shows " .. expected_icons[i])
end
eq(ui.frame.label.text, "Next action:", "the label carries the default caption")
eq(ui.icons[2].remaining_key, "mangle_remaining", "the swipe field names derive from the key")
eq(ui.icons[4].expires_key, "rake_expires", "the expiry field name derives from the key")
eq(ui.icons[1].remaining_key, nil, "the unwiped slots carry no swipe fields")
eq(ui.icons[7].remaining_key, nil, "the Claw slot carries no swipe (no cooldown)")
eq(ui.icons[7].expires_key, nil, "the Claw slot carries no expiry channel")
eq(ui.icons[3].glow_key, nil, "the druid slots carry no glow")

-- Every possible action output names a declared slot (through the real provider).
do
    local provider = ST.DRUID.guide
    local function action_of(overrides)
        local inputs = inp(overrides)
        local out = {}
        provider.evaluate(inputs, out)
        return out.action
    end
    local actions = {
        action_of({}),
        action_of({ form_index = 3, rip_remaining = NONE }),
        action_of({ form_index = 3, rip_remaining = 5, rake_remaining = NONE }),
        action_of({ form_index = 3, rip_remaining = 5, rake_remaining = 5,
            mangle_remaining = NONE }),
        action_of({ form_index = 3, rip_remaining = 5, rake_remaining = 5,
            mangle_remaining = 6, combo_points = 5 }),
        action_of({ form_index = 3, rip_remaining = 5, rake_remaining = 5,
            mangle_remaining = 6, combo_points = 0 }),
        action_of({ form_index = 0 }),
    }
    eq(actions[1], "maul", "the provider delegates to the pure engine (maul)")
    eq(actions[2], "rip", "the provider delegates to the pure engine (rip)")
    eq(actions[3], "rake", "the provider delegates to the pure engine (rake)")
    eq(actions[4], "mangle", "the provider delegates to the pure engine (mangle)")
    eq(actions[5], "bite", "the provider delegates to the pure engine (bite)")
    eq(actions[6], "shred", "the provider delegates to the pure engine (shred)")
    eq(actions[7], nil, "the provider delegates to the pure engine (none)")
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
ST.form_index = 1
ST.maul_queued = true
ST.insufficient_rage = false
sandbox.rage = 40
sandbox.energy = 70
sandbox.combo = 2
sandbox.rage_cost = { { cost = 15 } }
sandbox.cost_queries = 0

local gathered_target = {}
local gathered = ST.DRUID.guide.gather(ST, gathered_target)
eq(gathered, gathered_target, "gather writes into and returns the caller's table")
eq(gathered.speed, 3.0, "gather: speed")
near(gathered.swing_remaining, 2.0, 1e-9, "gather: swing_remaining")
near(gathered.gcd_remaining, 0.5, 1e-9, "gather: gcd_remaining")
eq(gathered.form_index, 1, "gather: the live form")
eq(gathered.rage, 40, "gather: bear rage from the explicit power type")
eq(gathered.energy, nil, "gather: energy stays nil outside cat form")
eq(gathered.combo_points, nil, "gather: combo points stay nil outside cat form")
eq(gathered.maul_queued, true, "gather: maul_queued")
eq(gathered.insufficient_rage, false, "gather: insufficient_rage")
eq(gathered.maul_cost, 15, "gather: the Maul rage cost")
eq(gathered.rip_remaining, nil, "gather: no tracker answer yet -> nil Rip")
eq(gathered.rake_remaining, nil, "gather: no tracker answer yet -> nil Rake")
eq(gathered.mangle_remaining, nil, "gather: no tracker answer yet -> nil Mangle")
eq(gathered.rip_refresh, 4, "gather: the Rip refresh default")
eq(gathered.rake_refresh, 4, "gather: the Rake refresh default")
eq(sandbox.cost_queries, 1, "gather: the Maul cost is queried once")
-- RE-CUT (2026-10-25, operator ruling): the Wrath/Titanforge cost read carries the
-- localized NAME (rank-invariant), never the bare id the old fixture expected.
eq(sandbox.last_cost_id, "Maul", "gather: the cost is read by NAME on Wrath")
eq(sandbox.last_power_type, 1, "gather: the bear read passes the rage power type")

-- Every slot's cooldown key resolves into the gathered inputs.
local cooldowns_resolve = true
for i = 1, #slots do
    if slots[i].cooldown_key and gathered[slots[i].cooldown_key .. "_remaining"] == nil
        and slots[i].cooldown_key ~= "rip" and slots[i].cooldown_key ~= "rake"
        and slots[i].cooldown_key ~= "mangle" then
        cooldowns_resolve = false
    end
end
check(cooldowns_resolve, "every debuff-fed slot cooldown_key resolves into the gathered inputs")

-- Stale fields are overwritten on the reused table (form switch clears the bear reads).
ST.form_index = 3
ST.maul_queued = false
sandbox.rage = nil
sandbox.energy = 55
sandbox.combo = 3
sandbox.last_power_type = nil
local gathered2 = ST.DRUID.guide.gather(ST, gathered_target)
eq(gathered2, gathered_target, "the reused table is the same table")
eq(gathered2.form_index, 3, "the form switch is written through")
eq(gathered2.rage, nil, "the cat gather clears the stale rage")
eq(gathered2.energy, 55, "the cat gather reads energy")
eq(gathered2.combo_points, 3, "the cat gather reads combo points")
eq(sandbox.last_power_type, 4, "the cat gather's last read is the combo power type")
eq(gathered2.maul_queued, false, "the queue flag is overwritten, not stale")
eq(gathered2.maul_cost, 15, "the cost read still happens on the reused table")
eq(class_db.guide_rip_refresh, 4, "the Rip threshold default holds")
class_db.guide_rip_refresh = 6
class_db.guide_rake_refresh = 5
eq(ST.DRUID.guide.gather(ST, gathered_target).rip_refresh, 6,
    "the Rip threshold rides the options")
eq(ST.DRUID.guide.gather(ST, gathered_target).rake_refresh, 5,
    "the Rake threshold rides the options")
class_db.guide_rip_refresh = nil
class_db.guide_rake_refresh = nil
eq(ST.DRUID.guide.gather(ST, gathered_target).rip_refresh, 4,
    "a missing Rip option falls back to the 4 s default")
eq(ST.DRUID.guide.gather(ST, gathered_target).rake_refresh, 4,
    "a missing Rake option falls back to the 4 s default")
class_db.guide_rip_refresh = 4
class_db.guide_rake_refresh = 4

-- RipCP override wiring (filed follow-up built): the gather feeds the future
-- db.guide_rip_min_cp raw (nil until the widget ships); the engine clamps 2-5
-- and defaults to 4 (pinned in §17).
eq(ST.DRUID.guide.gather(ST, gathered_target).rip_min_cp, nil,
    "gather: no RipCP option -> nil (engine defaults to 4)")
class_db.guide_rip_min_cp = 2
eq(ST.DRUID.guide.gather(ST, gathered_target).rip_min_cp, 2,
    "gather: the low-end RipCP override rides the options")
class_db.guide_rip_min_cp = 3
eq(ST.DRUID.guide.gather(ST, gathered_target).rip_min_cp, 3,
    "gather: a mid RipCP override rides the options")
class_db.guide_rip_min_cp = 5
eq(ST.DRUID.guide.gather(ST, gathered_target).rip_min_cp, 5,
    "gather: the high-end RipCP override rides the options")
class_db.guide_rip_min_cp = 1
eq(ST.DRUID.guide.gather(ST, gathered_target).rip_min_cp, 1,
    "gather: a below-range RipCP passes through raw (the engine clamps to 4)")
class_db.guide_rip_min_cp = nil
eq(ST.DRUID.guide.gather(ST, gathered_target).rip_min_cp, nil,
    "a missing RipCP option clears back to nil (engine defaults to 4)")

-- Direct calls without an out table use the module's own reused table.
local own = ST.DRUID.gather_guide_inputs(ST)
eq(own, ST.DRUID.guide_inputs, "gather without an out table uses the module's reused table")

-- The tracker feeds the guide's frozen debuff inputs (and the merged scan keeps
-- running while the guide is enabled even with every debuff bar off).
do
    sandbox.target_auras = {
        { name = "Rip", count = 1, duration = 12, expiration = sandbox.clock + 10,
            source = "player", spell_id = 1079 },
        { name = "Rake", count = 1, duration = 9, expiration = sandbox.clock + 8,
            source = "player", spell_id = 1822 },
        { name = "Mangle", count = 1, duration = 12, expiration = sandbox.clock + 11,
            source = "player", spell_id = 33987 },
    }
    class_db.show_druid_mangle_bar = false
    class_db.show_druid_rip_bar = false
    class_db.show_druid_rake_bar = false
    sandbox.target_aura_calls = 0
    ST.form_index = 3
    local function tick(advance)
        ST.mainhand.ends_at = sandbox.clock + 3.0
        sandbox.advance(advance or 0.1)
        ST.DRUID.on_bar_update(ST, "mainhand")
    end
    tick()
    tick()
    check(sandbox.target_aura_calls > 0,
        "the guide keeps the merged debuff scan alive with every bar off")
    local fed = ST.DRUID.guide.gather(ST, gathered_target)
    near(fed.rip_remaining, 10, 0.2, "the tracker feeds rip_remaining")
    eq(fed.rip_duration, 12, "the tracker feeds the Rip swipe length")
    near(fed.rake_remaining, 8, 0.2, "the tracker feeds rake_remaining")
    near(fed.mangle_remaining, 11, 0.2, "the tracker feeds mangle_remaining")
    -- With the guide off too, the all-off configuration reads no target auras.
    class_db.nextaction_enabled = false
    sandbox.target_aura_calls = 0
    tick()
    eq(sandbox.target_aura_calls, 0,
        "with the guide off too, the all-off configuration reads no target auras")
    class_db.nextaction_enabled = true
    class_db.show_druid_mangle_bar = true
    class_db.show_druid_rip_bar = true
    class_db.show_druid_rake_bar = true
    -- A cleared target clears the frozen debuff inputs on the very next gather.
    sandbox.target_auras = {}
    tick()
    tick()
    local cleared = ST.DRUID.guide.gather(ST, gathered_target)
    eq(cleared.rip_remaining, nil, "a cleared target clears the stale Rip input")
    eq(cleared.rake_remaining, nil, "a cleared target clears the stale Rake input")
    eq(cleared.mangle_remaining, nil, "a cleared target clears the stale Mangle input")
    eq(cleared.rip_duration, nil, "and the stale swipe length")
end

-- The rank-1 fallback when nothing resolves on the client.
do
    local fallback = build()
    fallback.hide_spells = true
    fallback.ST.DRUID.post_init(fallback.ST)
    local fslots = fallback.ST.DRUID.guide.slots
    eq(fslots[1].spell_id, 6807, "an unresolved Maul keeps the rank-1 fallback")
    eq(fslots[2].spell_id, 33878, "an unresolved Mangle keeps the shared 33878 fallback")
    local fui = fallback.st.nextaction_ui
    eq(fui.icons[1].icon.texture.texture, nil,
        "an unresolvable icon simply stays texture-less (no error)")
    fallback.cost_queries = 0
    local fgathered = fallback.ST.DRUID.guide.gather(fallback.ST, {})
    eq(fgathered.maul_cost, nil, "an unresolved Maul rank yields no cost")
    eq(fallback.cost_queries, 0, "an unresolved rank skips the cost query entirely")
end

--=========================================================================================
-- 3) The display mapping through the real frame and the real hooks
--=========================================================================================
sandbox.clock = 200
ST.mainhand = { speed = 3.0, ends_at = 0, start = 0, is_full = false }
ST.gcd = { expires = 0 }
ST.form_index = 1
ST.maul_queued = false
ST.insufficient_rage = false
sandbox.rage = 50
sandbox.rage_cost = { { cost = 15 } }
sandbox.target_auras = {}
sandbox.clock = 201

local function tick(advance)
    ST.mainhand.ends_at = sandbox.clock + 3.0
    sandbox.advance(advance or 0.1)
    ST.DRUID.on_bar_update(ST, "mainhand")
end
local function target(key)
    return ui.icons[ui.slot_index[key]].fade.target
end

-- Bear form: the queued ride, then Maul, then the Mangle fallback.
ST.maul_queued = true
tick()
eq(target("maul"), 0, "a queued Maul is not re-suggested by the frame")
eq(ui.frame.hold.fade.target, 1, "the queued state shows the hold overlay")
eq(ui.frame.hold.text.text, "RIDE", "the queued state reads RIDE")
eq(ui.frame.shown, true, "the in-combat tick shows the frame")
ST.maul_queued = false
tick()
eq(target("maul"), 1, "with nothing queued the guide suggests Maul")
eq(ui.frame.hold.fade.target, 0, "the hold overlay clears")
sandbox.rage = 5
tick()
eq(target("maul"), 0, "insufficient rage withholds the Maul prompt")
eq(target("mangle"), 1, "insufficient rage falls back to Mangle")
eq(ui.frame.hold.fade.target, 0, "the Mangle fallback carries no hold")
sandbox.rage = 50

-- Cat form on Wrath: Savage Roar tracked healthy (the Wrath upkeep rule would
-- otherwise hold SAVAGE ROAR over every builder below), Tiger's Fury and Berserk
-- unknown (dormant), no Clearcasting. Two ticks: the first runs the player scan,
-- the second evaluates off it (the target-aura convention below).
sandbox.player_auras = {
    { name = "Savage Roar", count = 1, duration = 34, expiration = sandbox.clock + 30,
        source = "player", spell_id = 52610 },
}
ST.form_index = 3
sandbox.combo = 5
tick()
tick()
eq(target("rip"), 1, "cat form with 5 CP and no tracked Rip suggests Rip")
eq(target("maul"), 0, "the bear slots stay dark in cat form")
sandbox.target_auras = {
    { name = "Rip", count = 1, duration = 12, expiration = sandbox.clock + 10,
        source = "player", spell_id = 1079 },
}
tick()
tick()
eq(target("rip"), 0, "a healthy Rip clears the Rip prompt")
eq(target("mangle"), 1, "and the guide moves on to an absent Mangle (Mangle above Rake)")
eq(target("rake"), 0, "Rake waits while Mangle is absent")
sandbox.target_auras = {
    { name = "Rip", count = 1, duration = 12, expiration = sandbox.clock + 10,
        source = "player", spell_id = 1079 },
    { name = "Rake", count = 1, duration = 9, expiration = sandbox.clock + 8,
        source = "player", spell_id = 1822 },
}
tick()
tick()
eq(target("rake"), 0, "a healthy Rake clears the Rake prompt")
eq(target("mangle"), 1, "and the guide moves on to an absent Mangle")
sandbox.target_auras = {
    { name = "Rip", count = 1, duration = 12, expiration = sandbox.clock + 10,
        source = "player", spell_id = 1079 },
    { name = "Rake", count = 1, duration = 9, expiration = sandbox.clock + 8,
        source = "player", spell_id = 1822 },
    { name = "Mangle", count = 1, duration = 12, expiration = sandbox.clock + 11,
        source = "player", spell_id = 33987 },
}
sandbox.combo = 4
tick()
tick()
eq(target("mangle"), 0, "a running Mangle clears the Mangle prompt")
eq(target("shred"), 1, "4 combo points build with Shred")
sandbox.combo = 5
tick()
eq(target("bite"), 0, "at 5 combo points with no execute evidence the Bite stays dark (research)")
eq(target("shred"), 1, "and the guide builds with Shred instead of Biting mid-fight")

-- An expired-but-listed Rip lights Rip and drives its swipe from the tracker's
-- own window (5 CP; Wrath never clips: a Rip with time left is healthy, so the
-- swipe case is an overdue listing, remaining floored at 0).
sandbox.combo = 5
sandbox.target_auras = {
    { name = "Rip", count = 1, duration = 12, expiration = sandbox.clock - 0.5,
        source = "player", spell_id = 1079 },
}
tick()
tick()
eq(target("rip"), 1, "an expired Rip at 5 CP lights the Rip slot")
-- The Rip swipe dynamics (tracker-driven length, set-once latch, zero-length
-- clear) live on the legacy matrix: only a refresh WINDOW lights a slot while
-- its remaining is still positive, and Wrath never clips - so the Wrath Rip
-- slot carries no live swipe. A Cata sandbox runs rules 4-8 unchanged and pins
-- the dynamics there instead.
do
    local cata = build({ project = 14 })
    eq(cata.st.family, "CATA", "project 14 reports the CATA family")
    local CST, cui = cata.ST, cata.st.nextaction_ui
    CST.in_combat = true
    CST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
    CST.gcd = { expires = 0 }
    CST.DRUID.post_init(CST)
    check(cui.frame ~= nil, "the Cata sandbox builds the guide frame")
    CST.form_index = 3
    cata.combo = 5
    local function ctick(advance)
        CST.mainhand.ends_at = cata.clock + 3.0
        cata.advance(advance or 0.1)
        CST.DRUID.on_bar_update(CST, "mainhand")
    end
    local function ctarget(key)
        return cui.icons[cui.slot_index[key]].fade.target
    end
    local function cslot_icon(key)
        return cui.icons[cui.slot_index[key]].icon
    end
    cata.target_auras = {
        { name = "Rip", count = 1, duration = 12, expiration = cata.clock + 2,
            source = "player", spell_id = 1079 },
    }
    ctick()
    ctick()
    eq(ctarget("rip"), 1, "legacy: a Rip inside the refresh window lights the Rip slot")
    eq(cslot_icon("rip").cooldown.cooldown_duration, 12,
        "the tracker's debuff length drives the Rip swipe")
    eq(cslot_icon("rip").cooldown.cooldown_sets, 1, "the Rip swipe is set once")
    eq(cslot_icon("rip").cooldown_set, true, "the Rip swipe latch is armed")
    ctick()
    eq(cslot_icon("rip").cooldown.cooldown_sets, 1, "the Rip swipe latch holds across ticks")
    cata.target_auras = {
        { name = "Rip", count = 1, duration = 12, expiration = cata.clock + 10,
            source = "player", spell_id = 1079 },
    }
    ctick()
    ctick()
    eq(cslot_icon("rip").cooldown.cooldown_sets, 2, "a healthy Rip clears the swipe")
    eq(cslot_icon("rip").cooldown.cooldown_duration, 0, "the clear is a zero-length cooldown")
    eq(cslot_icon("rip").cooldown_set, false, "the swipe latch resets on clear")
end

-- Unknown forms: the frame still ticks but nothing is suggested.
ST.form_index = 0
tick()
eq(target("rip"), 0, "an unshifted druid gets no cat action")
eq(target("mangle"), 0, "an unshifted druid gets no bear action")
eq(ui.frame.hold.fade.target, 0, "an unshifted druid gets no hold")
ST.form_index = 5
tick()
eq(target("rip"), 0, "moonkin form gets no feral action")
ST.form_index = 3

-- Option gates: disabled hides the frame and stops the mapping; visibility follows the
-- in-combat key; the size/position/lock diff applies live.
local before_disable = target("shred")
class_db.nextaction_enabled = false
tick()
eq(ui.frame.shown, false, "nextaction_enabled=false hides the frame")
eq(target("shred"), before_disable, "the gated tick leaves the slot targets alone")
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

-- The hand gate: an offhand call never ticks the guide.
local before_offhand = target("mangle")
sandbox.advance(1.0)
ST.DRUID.on_bar_update(ST, "offhand")
eq(target("mangle"), before_offhand, "the offhand call does not tick the guide")

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
    local druid_defaults = presets:match("ST%.DRUID%.defaults%s*=%s*%{(.-)ST%.HUNTER%.defaults") or ""
    local options = read("option_tables.lua")
    local druid_opts = options:match("function ST%.class_opts_funcs%.DRUID%((.-)function ST%.class_opts_funcs%.SHAMAN%(") or ""

    local expected_defaults = {
        nextaction_enabled = "true",
        nextaction_locked = "true",
        nextaction_visibility_key = "\"in_combat\"",
        nextaction_icon_size = "45",
        nextaction_x = "127",
        nextaction_y = "-65",
        guide_rip_refresh = "4",
        guide_rake_refresh = "4",
    }
    for key, value in pairs(expected_defaults) do
        check(druid_defaults:find("%f[%a_]" .. key .. "%s*=%s*" .. value, 1) ~= nil,
            "config_presets.lua: DRUID default " .. key .. " = " .. value)
    end

    local widget_types = {
        nextaction_enabled = "toggle",
        nextaction_locked = "toggle",
        nextaction_visibility_key = "select",
        nextaction_icon_size = "range",
        nextaction_x = "input",
        nextaction_y = "input",
        guide_rip_refresh = "range",
        guide_rake_refresh = "range",
    }
    for key, wtype in pairs(widget_types) do
        local widget = druid_opts:match("%f[%a_]" .. key .. "%s*=%s*{(.-)\n%s*}")
        check(widget ~= nil and widget:find("type%s*=%s*\"" .. wtype .. "\"") ~= nil,
            "option_tables.lua: " .. key .. " has a " .. wtype .. " widget")
    end
    check(druid_opts:find("Next Action Guide") ~= nil,
        "option_tables.lua: the druid options carry a Next Action Guide block")
    local rip_widget = druid_opts:match("guide_rip_refresh%s*=%s*{(.-)\n%s*}") or ""
    check(rip_widget:find("min%s*=%s*0[^%d]") ~= nil and rip_widget:find("max%s*=%s*10") ~= nil,
        "option_tables.lua: guide_rip_refresh is a 0-10 range")
    local rake_widget = druid_opts:match("guide_rake_refresh%s*=%s*{(.-)\n%s*}") or ""
    check(rake_widget:find("min%s*=%s*0[^%d]") ~= nil and rake_widget:find("max%s*=%s*10") ~= nil,
        "option_tables.lua: guide_rake_refresh is a 0-10 range")

    -- druid_guide.lua loads after nextaction.lua in every TOC.
    local tocs = { "SwedgeTimer.toc", "SwedgeTimer_Vanilla.toc", "SwedgeTimer_TBC.toc",
        "SwedgeTimer_Wrath.toc", "SwedgeTimer_Mainline.toc", "SwedgeTimer_Cata.toc",
        "SwedgeTimer_Mists.toc" }
    for i = 1, #tocs do
        local text = read(tocs[i])
        local after = text:find("\nnextaction.lua", 1, true)
        local guide_at = text:find("\ndruid_guide.lua", 1, true)
        check(after ~= nil and guide_at ~= nil and guide_at > after,
            tocs[i] .. ": druid_guide.lua loads after nextaction.lua")
    end

    -- The drive call sites live in classes/druid.lua.
    local druid_src = read("classes/druid.lua")
    check(druid_src:find("st%.nextaction_ui%.init%(self%)") ~= nil,
        "classes/druid.lua: post_init drives st.nextaction_ui.init")
    check(druid_src:find("st%.nextaction_ui%.on_bar_update%(self, hand%)") ~= nil,
        "classes/druid.lua: on_bar_update drives st.nextaction_ui.on_bar_update")
    check(druid_src:find("st%.nextaction_ui%.apply_settings%(self%)") ~= nil,
        "classes/druid.lua: the settings diff applies live")
    check(druid_src:find("self%.DRUID%.resolve_guide_icons%(%)") ~= nil,
        "classes/druid.lua: post_init drives the rank-icons resolver")
    check(druid_src:find("ST%.DRUID%.gather_guide_inputs%(self, out%)") ~= nil,
        "classes/druid.lua: the provider delegates to the gather")
end

--=========================================================================================
-- 5) The TBC cat branch through the pure engine (inputs.family == "TBC")
--=========================================================================================
eq(dg.MANGLE_COST_TBC, 40, "the TBC Mangle cost is 40 energy")
eq(dg.SHRED_COST_TBC, 42, "the TBC Shred cost is 42 energy")
eq(dg.POWERSHIFT_SHORTFALL_TBC, nil, "the TBC powershift shortfall constant is removed (no honest shift probe)")
eq(dg.SHORT_LIVED_TTD_SECONDS, 10, "short-lived means dying inside the sim's 10 s end threshold")

-- A TBC input set: the legacy baseline plus the family flag. NONE clears a key.
local function tin(overrides)
    local o = {}
    for k, v in pairs(overrides or {}) do o[k] = v end
    o.family = "TBC"
    return o
end

local function tevaluate(overrides)
    return evaluate(tin(overrides))
end

-- T1: 4+ CP with Rip expired -> Rip; the CP gate and the expiry gate both bite.
do
    eq(tevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 4,
        rake_remaining = NONE, mangle_remaining = 6 }).action, "rip",
        "T1: 4 CP with no Rip -> Rip (the Rake slot is skipped on TBC)")
    eq(tevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 5,
        rake_remaining = NONE, mangle_remaining = NONE, energy = 100 }).action, "rip",
        "T1 outranks T2/T3: an expired Rip with 5 CP Rips, never Mangles or Bites")
    eq(tevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 5,
        rake_remaining = NONE, mangle_remaining = 6, energy = 100,
        target_short_lived = true }).action, "rip",
        "T1 outranks T3: an expired Rip with 5 CP Rips even on a short-lived target")
    eq(tevaluate({ form_index = 3, rip_remaining = 0, combo_points = 4,
        mangle_remaining = 6 }).action, "rip",
        "T1: a remaining of exactly 0 is expired")
    eq(tevaluate({ form_index = 3, rip_remaining = -1, combo_points = 4,
        mangle_remaining = 6 }).action, "rip",
        "T1: an overdue listing is expired")
    eq(tevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 3,
        rake_remaining = NONE, mangle_remaining = 6, energy = 100 }).action, "shred",
        "T1: 3 CP cannot Rip -> Shred (never Rake on TBC)")
    eq(tevaluate({ form_index = 3, rip_remaining = NONE, combo_points = NONE,
        mangle_remaining = 6, energy = 100 }).action, "shred",
        "T1: an unreadable combo count cannot Rip")
end

-- No refresh window on TBC: a running Rip never refreshes early for builders.
do
    eq(tevaluate({ form_index = 3, rip_remaining = 3, combo_points = 4,
        mangle_remaining = 6, energy = 100 }).action, "shred",
        "TBC: 4 CP with 3 s of Rip left does NOT clip -> Shred")
    eq(tevaluate({ form_index = 3, rip_remaining = 0.0001, combo_points = 4,
        mangle_remaining = 6, energy = 100 }).action, "shred",
        "TBC: even a sliver of Rip left is not expired")
    eq(tevaluate({ form_index = 3, rip_remaining = 0 / 0, combo_points = 4,
        mangle_remaining = 6, energy = 100 }).action, "shred",
        "TBC: a NaN Rip remaining cannot match the expiry rule")
end

-- T2: the 40-energy Mangle gate.
do
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 0,
        rake_remaining = 8, mangle_remaining = NONE, energy = 40 }).action, "mangle",
        "T2: an absent Mangle at exactly 40 energy -> Mangle")
    local out = tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 0,
        rake_remaining = 8, mangle_remaining = NONE, energy = 39.999 })
    eq(out.action, nil, "T2 boundary: 39.999 energy cannot Mangle (or Shred) -> wait")
    eq(out.hold, false, "the wait carries no hold")
    eq(out.hold_text, nil, "the wait carries no hold text")
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 0,
        rake_remaining = 8, mangle_remaining = NONE, energy = NONE }).action, nil,
        "T2: unreadable energy cannot prove a Mangle -> wait, never a guess")
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 0,
        rake_remaining = 8, mangle_remaining = 0.5, energy = 100 }).action, "shred",
        "T2: a running Mangle never refreshes (only nil prompts it)")
end

-- T3/T4: the FB-vs-Rip inversion fix.
do
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 5,
        rake_remaining = 8, mangle_remaining = 6, energy = 100 }).action, "rip",
        "T4: 5 CP on a long fight Rips, never Bites (the inversion fix)")
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 5,
        mangle_remaining = 6, energy = 100, target_short_lived = true }).action, "bite",
        "T3: 5 CP with the short-lived flag -> Bite")
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 5,
        mangle_remaining = 6, energy = 100, time_to_die = 10 }).action, "bite",
        "T3: dying inside one full Rip -> Bite")
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 5,
        mangle_remaining = 6, energy = 100, time_to_die = 10 }).action, "bite",
        "T3: dying inside the 10 s threshold -> Bite")
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 5,
        mangle_remaining = 6, energy = 100, time_to_die = 10.0001 }).action, "rip",
        "T4: just over 10 s to die is a long fight -> Rip")
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 5,
        mangle_remaining = 6, energy = 100, time_to_die = 30 }).action, "rip",
        "T4: a long time-to-die defaults to Rip")
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 4,
        mangle_remaining = 6, energy = 100, target_short_lived = true }).action, "shred",
        "T3: 4 CP cannot Bite even flagged short-lived")
    eq(tevaluate({ form_index = 3, rip_remaining = 3, combo_points = 5,
        mangle_remaining = 6, energy = 100 }).action, "rip",
        "T4: 5 CP Rips even inside the legacy window (no clipping rule on TBC)")
end

-- T5: the 42-energy Shred gate.
do
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 2,
        mangle_remaining = 6, energy = 42 }).action, "shred",
        "T5: exactly 42 energy builds with Shred")
    local out = tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 2,
        mangle_remaining = 6, energy = 41.999 })
    eq(out.action, nil, "T5: 41.999 energy cannot Shred -> wait")
    eq(out.hold, false, "the sub-42 wait pools without a hold")
end

-- T6 (REMOVED - was the powershift call): no SHIFT rule exists, so a short
-- bar with a claimed shift basis simply waits. can_powershift is a reserved
-- input no rule reads; true/false/nil all behave identically here.
do
    local out = tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 2,
        mangle_remaining = 6, energy = 21, can_powershift = true })
    eq(out.action, nil, "removed T6: 21 energy with a claimed shift basis waits, never shifts")
    eq(out.hold, false, "removed T6: the wait carries no hold")
    eq(out.hold_text, nil, "removed T6: the wait carries no hold text")
    eq(out.filler_slot, nil, "removed T6: the wait carries no filler")
    eq(out.judge_slot, nil, "removed T6: the wait carries no judge cue")
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 2,
        mangle_remaining = 6, energy = 22, can_powershift = true }).action, nil,
        "removed T6: 22 energy with a claimed shift basis still waits")
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 2,
        mangle_remaining = 6, energy = 0, can_powershift = true }).hold, false,
        "removed T6: an empty bar with a claimed shift basis still waits")
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 2,
        mangle_remaining = 6, energy = 10 }).hold, false,
        "removed T6: an unknown shift basis waits (nil can_powershift)")
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 2,
        mangle_remaining = 6, energy = 10, can_powershift = false }).hold, false,
        "removed T6: a false shift basis waits")
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 2,
        mangle_remaining = 6, energy = NONE, can_powershift = true }).hold, false,
        "removed T6: unreadable energy waits")
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 2,
        mangle_remaining = 6, energy = 0 / 0, can_powershift = true }).hold, false,
        "removed T6: NaN energy waits")

    -- The wait overwrites stale fields on a reused out table.
    local dirty = { action = "stale", hold = "stale", hold_text = "STALE",
        filler_slot = "stale", judge_slot = "stale", rotation_key = "stale",
        waiting_judgement = true }
    dg.evaluate(tin({ form_index = 3, rip_remaining = 8, combo_points = 2,
        mangle_remaining = 6, energy = 21, can_powershift = true }), dirty)
    eq(dirty.action, nil, "removed T6 overwrites a stale action with nil")
    eq(dirty.hold, false, "removed T6 overwrites a stale hold")
    eq(dirty.hold_text, nil, "removed T6 overwrites stale hold text")
    eq(dirty.waiting_judgement, false, "removed T6 overwrites the judgement carry")
end

-- Rake is never prompted on TBC, whatever the tracker reports.
do
    local rips = { NONE, 0, 0.5, 8 }
    local rakes = { NONE, 0, 4 }
    local mangles = { NONE, 6 }
    local cps = { 0, 3, 4, 5 }
    local energies = { NONE, 0, 21, 22, 41, 42, 100 }
    local shorts = { NONE, true }
    local ttds = { NONE, 5, 30 }
    local shifts = { NONE, true }
    local swept = 0
    for _, rip in ipairs(rips) do
        for _, rake in ipairs(rakes) do
            for _, mangle in ipairs(mangles) do
                for _, cp in ipairs(cps) do
                    for _, energy in ipairs(energies) do
                        for _, short in ipairs(shorts) do
                            for _, ttd in ipairs(ttds) do
                                for _, shift in ipairs(shifts) do
                                    swept = swept + 1
                                    local out = tevaluate({
                                        form_index = 3, rip_remaining = rip,
                                        rake_remaining = rake,
                                        mangle_remaining = mangle,
                                        combo_points = cp, energy = energy,
                                        target_short_lived = short,
                                        time_to_die = ttd,
                                        can_powershift = shift,
                                    })
                                    check(out.action ~= "rake",
                                        "TBC sweep: Rake is never prompted")
                                    -- No SHIFT rule exists anymore (removed T6):
                                    -- the TBC cat chain only acts or waits.
                                    check(out.hold == false,
                                        "TBC sweep: TBC never holds")
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    eq(swept, 4 * 3 * 2 * 4 * 7 * 2 * 3 * 2, "the TBC sweep covered every combination")
end

--=========================================================================================
-- 6) Every other family runs the legacy matrix unchanged (energy ignored, windows kept)
--=========================================================================================
do
    local families = { "CATA", "MISTS", "UNKNOWN" }
    for _, family in ipairs(families) do
        eq(evaluate({ family = family, form_index = 3, rip_remaining = 2,
            combo_points = 0, mangle_remaining = 6, energy = 0 }).action, "rip",
            family .. ": the Rip window still refreshes with no CP gate and no energy")
        eq(evaluate({ family = family, form_index = 3, rip_remaining = 8,
            rake_remaining = NONE, combo_points = 0, energy = 0 }).action, "rake",
            family .. ": the untracked Rake still prompts (the TBC skip is gated)")
        eq(evaluate({ family = family, form_index = 3, rip_remaining = 8,
            rake_remaining = 8, mangle_remaining = NONE, energy = 0 }).action, "mangle",
            family .. ": Mangle stays ungated (the Era gate is an exact match)")
        eq(evaluate({ family = family, form_index = 3, rip_remaining = 8,
            rake_remaining = 8, mangle_remaining = 6, combo_points = 5,
            energy = 0 }).action, "bite",
            family .. ": 5 CP still Bites by default off TBC")
        eq(evaluate({ family = family, form_index = 1 }).action, "maul",
            family .. ": the bear baseline is untouched")
    end
    -- A missing family is the legacy matrix too (every existing caller).
    eq(evaluate({ form_index = 3, rip_remaining = 2, combo_points = 0,
        mangle_remaining = 6, energy = 0 }).action, "rip",
        "a missing family runs the legacy matrix")
    -- The TBC contrast for near-identical inputs: no window, no Rake, gated Mangle.
    eq(tevaluate({ form_index = 3, rip_remaining = 2, combo_points = 0,
        mangle_remaining = 6, energy = 0 }).action, nil,
        "TBC contrast: 2 s of Rip with 0 CP and no energy waits (window gone, CP-gated)")
    eq(evaluate({ family = "tbc", form_index = 3, rip_remaining = NONE }).action, "rip",
        "the TBC branch is an exact family match (lowercase stays legacy)")
    eq(tevaluate({ form_index = 1 }).action, "maul",
        "TBC bear: the bear rules are family-blind")
    eq(tevaluate({ form_index = 1, maul_queued = true }).hold_text, "RIDE",
        "TBC bear: the queued Maul still rides")
    -- The WRATH contrast for near-identical inputs (the WRATH APPENDIX, pinned
    -- rule-by-rule in section 9): no refresh windows, Mangle above Rake, the
    -- cooldown/buff holds off the six slots.
    eq(evaluate({ family = "WRATH", form_index = 3, rip_remaining = 2,
        combo_points = 0, mangle_remaining = 6, energy = 0 }).action, "shred",
        "WRATH contrast: 2 s of Rip with 0 CP builds (window gone, no CP gate)")
    eq(evaluate({ family = "WRATH", form_index = 3, rip_remaining = 8,
        rake_remaining = NONE, combo_points = 0, mangle_remaining = NONE,
        energy = 90 }).action, "mangle",
        "WRATH contrast: an absent Mangle outranks an untracked Rake")
    eq(evaluate({ family = "WRATH", form_index = 1 }).action, "maul",
        "WRATH bear: the bear rules are untouched")
end

--=========================================================================================
-- 6b) The ERA family: no Mangle anywhere, the Shred/FB/powershift cat chain
--=========================================================================================
-- An Era input set: the legacy baseline plus the ERA flag. NONE clears a key.
local function ein(overrides)
    local o = {}
    for k, v in pairs(overrides or {}) do o[k] = v end
    o.family = "ERA"
    return o
end

local function eevaluate(overrides)
    return evaluate(ein(overrides))
end

-- Bear on Era: Maul when proven, RIDE when queued, otherwise wait (never Mangle).
do
    eq(eevaluate({ form_index = 1, rage = 50, maul_cost = 15 }).action, "maul",
        "Era bear: proven rage still Mauls")
    local out = eevaluate({ form_index = 1, rage = 5, maul_cost = 15 })
    eq(out.action, nil, "Era bear: short of rage waits instead of Mangling")
    eq(out.hold, false, "the Era wait carries no hold")
    eq(out.hold_text, nil, "the Era wait carries no hold text")
    eq(eevaluate({ family = "ERA", form_index = 1, rage = NONE,
        maul_cost = NONE }).action, nil,
        "Era bear: unreadable rage waits too (no Mangle guess)")
    eq(eevaluate({ family = "ERA", form_index = 1, maul_queued = true }).hold_text, "RIDE",
        "Era bear: the queued Maul still rides")
    eq(eevaluate({ family = "ERA", form_index = 1, rage = 15, maul_cost = 15,
        insufficient_rage = true }).action, nil,
        "Era bear: the shortfall veto waits instead of Mangling")
end

-- E0/E1: the Omen Shred, then the 5CP expiry-only Rip (never Bite - the sim
-- has no Bite branch at all).
do
    eq(eevaluate({ family = "ERA", form_index = 3, rip_remaining = NONE,
        rake_remaining = NONE, mangle_remaining = NONE, combo_points = 5,
        energy = 0 }).action, "rip",
        "E1: 5 CP with no Rip tracked -> Rip (ungated by energy)")
    eq(eevaluate({ family = "ERA", form_index = 3, rip_remaining = 0,
        rake_remaining = NONE, mangle_remaining = NONE, combo_points = 5,
        energy = 100 }).action, "rip",
        "E1: a remaining of exactly 0 is expired")
    eq(eevaluate({ family = "ERA", form_index = 3, rip_remaining = 8,
        rake_remaining = 8, mangle_remaining = 6, combo_points = 5,
        energy = 100 }).action, "shred",
        "E1 contrast: a healthy Rip at 5 CP is never clipped -> Shred")
    eq(eevaluate({ family = "ERA", form_index = 3, rip_remaining = 8,
        rake_remaining = 8, mangle_remaining = 6, combo_points = 5.5 }).action,
        "shred",
        "E1: above 5 CP still never clips a healthy Rip")
    eq(eevaluate({ family = "ERA", form_index = 3, rip_remaining = NONE,
        rake_remaining = NONE, mangle_remaining = NONE, combo_points = 5,
        energy = 100, clearcast = true }).action, "shred",
        "E0 outranks E1: the Omen proc is a free Shred even at 5 CP")
    eq(eevaluate({ family = "ERA", form_index = 3, rip_remaining = 8,
        rake_remaining = 8, mangle_remaining = 6, combo_points = 2,
        clearcast = true }).action, "shred",
        "E0: the Omen proc builds with Shred")
    eq(eevaluate({ family = "ERA", form_index = 3, rip_remaining = NONE,
        rake_remaining = NONE, mangle_remaining = NONE, combo_points = 4 }).action, "shred",
        "E1 boundary: 4 CP cannot Rip -> Shred")
    eq(eevaluate({ family = "ERA", form_index = 3, rip_remaining = NONE,
        rake_remaining = NONE, mangle_remaining = NONE,
        combo_points = NONE }).action, "shred",
        "E1: an unreadable combo count cannot Bite -> Shred")
    eq(eevaluate({ family = "ERA", form_index = 3, rip_remaining = 8,
        rake_remaining = 8, mangle_remaining = 6, combo_points = 0 / 0 }).action, "shred",
        "E1: a NaN combo count cannot Bite")
end

-- E2 (REMOVED - was the dormant powershift call): no SHIFT rule exists, so a
-- short bar with a claimed shift basis builds with Shred. can_powershift is a
-- reserved input no rule reads.
do
    eq(eevaluate({ form_index = 3, rip_remaining = 8, combo_points = 2,
        mangle_remaining = 6, energy = 21, can_powershift = true }).action, "shred",
        "removed E2: 21 energy with a claimed shift basis builds, never shifts")
    eq(eevaluate({ form_index = 3, rip_remaining = 8, combo_points = 2,
        mangle_remaining = 6, energy = 22, can_powershift = true }).action, "shred",
        "removed E2: 22 energy with a claimed shift basis still builds")
    eq(eevaluate({ family = "ERA", form_index = 3, combo_points = 2,
        energy = 10 }).hold, false,
        "removed E2: an unknown shift basis never holds (nil can_powershift)")
    eq(eevaluate({ family = "ERA", form_index = 3, combo_points = 2,
        energy = 10, can_powershift = false }).hold, false,
        "removed E2: a false shift basis never holds")
    eq(eevaluate({ family = "ERA", form_index = 3, combo_points = 2,
        energy = NONE, can_powershift = true }).hold, false,
        "removed E2: unreadable energy never holds")
    -- E1 outranks everything: a capped bar with a claimed shift still Rips first.
    eq(eevaluate({ family = "ERA", form_index = 3, combo_points = 5, energy = 0,
        rip_remaining = NONE, can_powershift = true }).action, "rip",
        "E1 outranks removed E2: 5 CP Rips even with a claimed shift")
end

-- E2 and the Era absences: Shred is the default, and no input prompts
-- Mangle, Rake or Bite on Era (the sweep below pins the whole input space).
do
    eq(eevaluate({ family = "ERA", form_index = 3, rip_remaining = NONE,
        rake_remaining = NONE, mangle_remaining = NONE, combo_points = 0,
        energy = 100 }).action, "shred",
        "E2: with nothing tracked and no CP the Era default is Shred")
    local rips = { NONE, 0, 0.5, 4, 8 }
    local rakes = { NONE, 0, 4, 8 }
    local mangles = { NONE, 0, 6 }
    local cps = { NONE, 0, 3, 4, 5 }
    local energies = { NONE, 0, 21, 22, 41, 42, 100 }
    local shifts = { NONE, true }
    local procs = { NONE, true }
    local swept = 0
    for _, rip in ipairs(rips) do
        for _, rake in ipairs(rakes) do
            for _, mangle in ipairs(mangles) do
                for _, cp in ipairs(cps) do
                    for _, energy in ipairs(energies) do
                        for _, shift in ipairs(shifts) do
                            for _, proc in ipairs(procs) do
                                swept = swept + 1
                                local out = eevaluate({
                                    form_index = 3, rip_remaining = rip,
                                    rake_remaining = rake,
                                    mangle_remaining = mangle,
                                    combo_points = cp, energy = energy,
                                    can_powershift = shift,
                                    clearcast = proc,
                                })
                                check(out.action ~= "mangle",
                                    "Era sweep: Mangle is never prompted")
                                check(out.action ~= "rake",
                                    "Era sweep: Rake is never prompted")
                                check(out.action ~= "bite",
                                    "Era sweep: Bite is never prompted (no sim branch)")
                                if out.action ~= nil then
                                    check(out.action == "rip" or out.action == "shred",
                                        "Era sweep: only Rip or Shred ever prompt")
                                end
                                -- No SHIFT rule exists anymore (removed E2):
                                -- the Era chain only acts, never holds.
                                check(out.hold == false,
                                    "Era sweep: Era never holds")
                            end
                        end
                    end
                end
            end
        end
    end
    eq(swept, 5 * 4 * 3 * 5 * 7 * 2 * 2, "the Era sweep covered every combination")
end

-- The Era gate is an exact family match, and the provider delegates to it.
do
    eq(evaluate({ family = "era", form_index = 3, rip_remaining = 5,
        rake_remaining = 5, mangle_remaining = NONE }).action, "mangle",
        "the Era gate is exact: lowercase stays legacy")
    eq(evaluate({ family = "ERA", form_index = 3, rip_remaining = 2,
        combo_points = 0, mangle_remaining = 6, energy = 0 }).action, "shred",
        "Era contrast: 2 s of Rip with 0 CP Shreds (no window, no Mangle)")
    local provider = ST.DRUID.guide
    local out = {}
    provider.evaluate(ein({ form_index = 3, rip_remaining = NONE,
        rake_remaining = NONE, mangle_remaining = NONE, combo_points = 5 }), out)
    eq(out.action, "rip", "the provider delegates the Era Rip")
    provider.evaluate(ein({ form_index = 1, rage = 5, maul_cost = 15 }), out)
    eq(out.action, nil, "the provider delegates the Era bear wait")
end

-- The Era display through a real Era sandbox: the Mangle/Rake/Bite icons stay dark.
do
    local era = build({ project = 2 })
    eq(era.st.family, "ERA", "the Era sandbox reports the ERA family")
    local EST, eui = era.ST, era.st.nextaction_ui
    EST.in_combat = true
    EST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
    EST.gcd = { expires = 0 }
    EST.DRUID.post_init(EST)
    check(eui.frame ~= nil, "the Era sandbox builds the guide frame")
    local eslots = EST.DRUID.guide.slots
    eq(#eslots, 7, "the Era slot set stays at seven (Claw declared, dark until its probe lands)")
    EST.form_index = 3
    era.energy = 100
    era.combo = 0
    era.target_auras = {}
    local function etick(advance)
        EST.mainhand.ends_at = era.clock + 3.0
        era.advance(advance or 0.1)
        EST.DRUID.on_bar_update(EST, "mainhand")
    end
    local function etarget(key)
        return eui.icons[eui.slot_index[key]].fade.target
    end
    etick()
    eq(etarget("rip"), 0, "Era display: an untracked Rip never lights")
    eq(etarget("shred"), 1, "Era display: the empty bar builds with Shred")
    eq(etarget("mangle"), 0, "Era display: the Mangle icon stays dark")
    -- Age the fight past the 8 s Rip gate (the first tick latched the fight
    -- clock): a young fight withholds the 5CP Rip and pools instead.
    era.advance(8.1)
    era.combo = 5
    etick()
    eq(etarget("rip"), 1, "Era display: 5 CP with no Rip lights Rip")
    eq(etarget("shred"), 0, "Era display: the finisher replaces the builder")
    eq(etarget("bite"), 0, "Era display: the Bite icon stays dark (no sim branch)")
    era.combo = 0
    era.target_auras = {
        { name = "Rip", count = 1, duration = 12, expiration = era.clock + 10,
            source = "player", spell_id = 1079 },
        { name = "Rake", count = 1, duration = 9, expiration = era.clock + 8,
            source = "player", spell_id = 1822 },
        { name = "Mangle", count = 1, duration = 12, expiration = era.clock + 11,
            source = "player", spell_id = 33987 },
    }
    etick()
    etick()
    eq(etarget("mangle"), 0, "Era display: a tracked Mangle never lights")
    eq(etarget("rake"), 0, "Era display: a tracked Rake never lights")
    eq(etarget("shred"), 1, "Era display: healthy debuffs still build with Shred")
    EST.form_index = 1
    EST.maul_queued = false
    era.rage = 5
    etick()
    eq(etarget("maul"), 0, "Era display: short of rage withholds Maul")
    eq(etarget("mangle"), 0, "Era display: short of rage waits, never Mangles")
    local egathered = EST.DRUID.guide.gather(EST, {})
    eq(egathered.family, "ERA", "the Era gather rides the ERA family")
end

--=========================================================================================
-- 6c) The TBC bear chain: byte-identical to the Wrath bear chain (Mangle is
--     TBC+, so B1-B3 run unchanged; only Era waits). Prior passes pinned just
--     two TBC bear shapes; this block pins the whole leg.
--=========================================================================================
do
    -- Rule-by-rule pins on TBC (mirroring the legacy bear pins above).
    eq(tevaluate({ form_index = 1, rage = 50, maul_cost = 15 }).action, "maul",
        "TBC bear: proven rage Mauls")
    eq(tevaluate({ form_index = 1, rage = 15, maul_cost = 15 }).action, "maul",
        "TBC bear boundary: rage exactly equal to the cost is sufficient")
    eq(tevaluate({ form_index = 1, rage = 14.99, maul_cost = 15 }).action, "mangle",
        "TBC bear: short of rage falls to Mangle (Mangle is TBC+)")
    eq(tevaluate({ form_index = 1, rage = 15, maul_cost = 15,
        insufficient_rage = true }).action, "mangle",
        "TBC bear: the shortfall flag vetoes a numeric proof")
    eq(tevaluate({ form_index = 1, rage = NONE, maul_cost = NONE }).action, "mangle",
        "TBC bear: unreadable rage and cost still land on Mangle")
    local ride = tevaluate({ form_index = 1, maul_queued = true })
    eq(ride.action, nil, "TBC bear: a queued Maul is not re-suggested")
    eq(ride.hold, true, "TBC bear: a queued Maul holds")
    eq(ride.hold_text, "RIDE", "TBC bear: the queued Maul reads RIDE")
    eq(tevaluate({ form_index = 1, maul_queued = true, rage = NONE }).hold_text, "RIDE",
        "TBC bear: the queue outranks the rage rules")

    -- Equivalence sweep: every bear input shape decides identically on TBC and
    -- on every other family that HAS a Mangle, while Era waits wherever the rest
    -- Mangle (RIDE and Maul agree everywhere). The FOREVER client has NO Mangle
    -- spell at all (HU-14, closed 2026-10-20), so it waits like runeless Era.
    local rages = { NONE, 0, 5, 14.999, 15, 50, 0 / 0 }
    local costs = { NONE, 0, 15, 30 }
    local queues = { false, true }
    local shorts = { NONE, false, true }
    local families = { "TBC", "WRATH", "CATA", "MISTS", "FOREVER" }
    local mangle_families = { "TBC", "WRATH", "CATA", "MISTS" }
    local swept = 0
    for _, rage in ipairs(rages) do
        for _, cost in ipairs(costs) do
            for _, queued in ipairs(queues) do
                for _, short in ipairs(shorts) do
                    swept = swept + 1
                    local results = {}
                    for _, family in ipairs(families) do
                        results[family] = evaluate({ family = family, form_index = 1,
                            rage = rage, maul_cost = cost, maul_queued = queued,
                            insufficient_rage = short })
                    end
                    for _, family in ipairs(mangle_families) do
                        eq(results[family].action, results["WRATH"].action,
                            "TBC bear parity: " .. family .. " matches Wrath")
                        eq(results[family].hold, results["WRATH"].hold,
                            "TBC bear hold parity: " .. family .. " matches Wrath")
                        eq(results[family].hold_text, results["WRATH"].hold_text,
                            "TBC bear hold-text parity: " .. family .. " matches Wrath")
                    end
                    local era = evaluate({ family = "ERA", form_index = 1,
                        rage = rage, maul_cost = cost, maul_queued = queued,
                        insufficient_rage = short })
                    if results["WRATH"].action == "mangle" then
                        eq(era.action, nil, "Era bear contrast: waits where Wrath Mangles")
                        eq(era.hold, false, "Era bear contrast: the wait carries no hold")
                        eq(era.hold_text, nil, "Era bear contrast: the wait carries no hold text")
                        -- HU-14 (closed 2026-10-20): the FOREVER client carries no
                        -- Mangle spell at all, so its bear chain waits exactly like
                        -- the runeless Era one - the guide must never name a spell
                        -- the client cannot cast.
                        eq(results["FOREVER"].action, nil,
                            "Forever bear contrast: waits where Wrath Mangles (no Mangle on that client)")
                        eq(results["FOREVER"].hold, false,
                            "Forever bear contrast: the wait carries no hold")
                        eq(results["FOREVER"].hold_text, nil,
                            "Forever bear contrast: the wait carries no hold text")
                    else
                        eq(era.action, results["WRATH"].action,
                            "Era bear parity: shares the Maul/RIDE outcome with Wrath")
                        eq(era.hold, results["WRATH"].hold,
                            "Era bear parity: shares the hold outcome with Wrath")
                        eq(results["FOREVER"].action, results["WRATH"].action,
                            "Forever bear parity: shares the Maul/RIDE outcome with Wrath")
                        eq(results["FOREVER"].hold, results["WRATH"].hold,
                            "Forever bear parity: shares the hold outcome with Wrath")
                    end
                end
            end
        end
    end
    eq(swept, 7 * 4 * 2 * 3, "the TBC bear sweep covered every combination")
end

--=========================================================================================
-- 7) Tiger's Fury is never prompted as an ACTION anywhere (no TF slot exists on
-- any family), and the families without a mid-rotation TF rule never hold for
-- it either. WRATH and ERA-with-runes hold TIGER'S FURY by design (sections 9
-- and 10); this sweep pins every other family.
--=========================================================================================
do
    local banned = { tiger = true, tigers_fury = true, tf = true }
    for i = 1, #slots do
        check(not banned[slots[i].key],
            "slot " .. tostring(slots[i].key) .. " is not a Tiger's Fury slot")
    end
    local families = { NONE, "TBC", "ERA", "FOREVER", "RETAIL" }
    local forms = { NONE, 0, 1, 3, 5 }
    local swept = 0
    for _, family in ipairs(families) do
        for _, form in ipairs(forms) do
            for _, rip in ipairs({ NONE, 0, 3, 8 }) do
                for _, cp in ipairs({ 0, 4, 5 }) do
                    for _, energy in ipairs({ NONE, 0, 40, 42, 100 }) do
                        swept = swept + 1
                        local out = evaluate({ family = family, form_index = form,
                            rip_remaining = rip, rake_remaining = rip,
                            mangle_remaining = rip, combo_points = cp,
                            energy = energy, maul_queued = false,
                            target_short_lived = true, time_to_die = 5,
                            can_powershift = true })
                        check(not banned[out.action],
                            "no input combination prompts Tiger's Fury")
                        if out.action ~= nil then
                            check(ui.slot_index[out.action] ~= nil,
                                "every prompted action still names a declared slot")
                        end
                        -- No SHIFT rule exists anywhere (removed T6/E2/S6) and
                        -- this sweep never feeds a hold input, so nothing holds.
                        check(out.hold == false,
                            "the TF sweep never holds")
                    end
                end
            end
        end
    end
    eq(swept, 5 * 5 * 4 * 3 * 5, "the TF sweep covered every combination")
end

--=========================================================================================
-- 8) The gather writes the family plus the unknown-shaped finisher/shift inputs
--=========================================================================================
do
    local g = ST.DRUID.guide.gather(ST, {})
    eq(g.family, "WRATH", "gather: the sandbox client family rides the inputs")
    eq(g.time_to_die, nil, "gather: no readable target health -> time-to-die nil")
    eq(g.target_short_lived, nil, "gather: the short-lived flag stays nil")
    eq(g.can_powershift, nil, "gather: shift feasibility stays nil (in-game to confirm)")
    -- Stale values on the reused table are overwritten, never kept.
    local reused = { family = "TBC", time_to_die = 5, target_short_lived = true,
        can_powershift = true, energy = 5, combo_points = 5, rage = 99,
        rip_remaining = 1, rake_remaining = 1, mangle_remaining = 1 }
    local g2 = ST.DRUID.guide.gather(ST, reused)
    eq(g2, reused, "the reused table is the same table")
    eq(g2.family, "WRATH", "the family overwrite wins over a stale TBC flag")
    eq(g2.time_to_die, nil, "a stale time-to-die is cleared (no readable target)")
    eq(g2.target_short_lived, nil, "a stale short-lived flag is cleared")
    eq(g2.can_powershift, nil, "a stale shift flag is cleared")
end

--=========================================================================================
-- Retail (12.x) inertness: the stand-in never swings, but rage/energy costs, the
-- queue flag and the absent-debuff defaults answer on Retail - every such shape
-- must stay empty.
--=========================================================================================
do
    local saved_family = pure.family
    pure.family = "RETAIL"
    -- The bear baseline (proven-affordable Maul) stays silent.
    local out = evaluate({})
    eq(out.action, nil, "retail: an affordable Maul never prompts")
    eq(out.hold, false, "retail: an affordable Maul never holds")
    -- A queued Maul never rides.
    local ride = evaluate({ maul_queued = true })
    eq(ride.action, nil, "retail: a queued Maul never prompts")
    eq(ride.hold, false, "retail: a queued Maul never rides")
    eq(ride.hold_text, nil, "retail: a queued Maul carries no RIDE text")
    -- The bear fallback (unaffordable Maul -> Mangle) never prompts.
    eq(evaluate({ rage = 0 }).action, nil,
        "retail: the bear Mangle fallback never prompts")
    -- The cat refresh chain (nil debuffs always refresh) never prompts.
    local cat = evaluate({ form_index = 3, rip_remaining = NONE, rake_remaining = NONE,
        mangle_remaining = NONE })
    eq(cat.action, nil, "retail: the cat refresh chain never prompts")
    eq(cat.hold, false, "retail: the cat chain never holds")
    eq(cat.hold_text, nil, "retail: the cat chain carries no hold text")
    eq(cat.waiting_judgement, false, "retail: the judgement carry stays false")
    -- A stale out table is fully overwritten (no frozen field survives).
    local stale = { action = "maul", hold = true, hold_text = "RIDE",
        filler_slot = "maul", judge_slot = "x", rotation_key = "y",
        waiting_judgement = true }
    local ret = dg.evaluate(inp({}), stale)
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
    eq(evaluate({}).action, "maul",
        "non-retail family: an affordable Maul still prompts")
    pure.family = saved_family
end

--=========================================================================================
-- 9) The WRATH cat branch through the pure engine (inputs.family == "WRATH")
--=========================================================================================
eq(dg.TF_ENERGY_WRATH, 40, "Tiger's Fury base line is 40 energy on Wrath (minus 10 per leeway second)")
eq(dg.BERSERK_ENERGY_WRATH, nil, "the 85-energy Berserk cap is removed (the sim has no energy gate)")
eq(dg.TF_CD_GATE_BERSERK_SECONDS, 15, "Berserk needs Tiger's Fury on cooldown 15 s")
eq(dg.FB_RIP_MIN_SECONDS, 4, "the Bite needs 4 s of Rip left (the sim's BiteTime)")
eq(dg.FB_SR_MIN_SECONDS, 4, "the Bite needs 4 s of Savage Roar left (the sim's BiteTime)")
eq(dg.FB_EXECUTE_TTD_SECONDS, 10, "the Wrath Bite execute window is the last 10 s")
eq(dg.TF_ENERGY_SOD, 40, "Tiger's Fury fires at or under 40 energy on SoD")
eq(dg.SOD_POWERSHIFT_MAX_ENERGY, nil, "the SoD powershift constant is removed with its branch")

-- A Wrath input set: the legacy baseline plus the family flag. NONE clears a key.
local function win(overrides)
    local o = {}
    for k, v in pairs(overrides or {}) do o[k] = v end
    o.family = "WRATH"
    return o
end

local function wevaluate(overrides)
    return evaluate(win(overrides))
end

-- W1: Tiger's Fury under the dynamic 40 - 10 * leeway line rides the hold
-- overlay (no TF slot exists). Baseline gcd_remaining is 0, so the static 40
-- pins below ride the degenerated line; the leeway pins follow.
do
    local out = wevaluate({ form_index = 3, energy = 39.999, tf_ready = true,
        combo_points = 0 })
    eq(out.action, nil, "W1: 39.999 energy with TF ready holds, never an action")
    eq(out.hold, true, "W1: the TF call rides the hold overlay")
    eq(out.hold_text, "TIGER'S FURY", "W1: the TF call reads TIGER'S FURY")
    eq(wevaluate({ form_index = 3, energy = 40, tf_ready = true,
        combo_points = 0 }).action, "shred",
        "W1 boundary: exactly 40 energy is not under 40 -> Shred")
    eq(wevaluate({ form_index = 3, energy = 20, tf_ready = false,
        combo_points = 0 }).hold, false,
        "W1: a TF on cooldown never calls (false is not true)")
    eq(wevaluate({ form_index = 3, energy = 0, combo_points = 0 }).hold, false,
        "W1: an unknown TF state never calls (nil is not true)")
    eq(wevaluate({ form_index = 3, energy = NONE, tf_ready = true,
        combo_points = 0 }).hold, false,
        "W1: unreadable energy cannot prove the line")
    eq(wevaluate({ form_index = 3, energy = 0 / 0, tf_ready = true,
        combo_points = 0 }).hold, false,
        "W1: NaN energy cannot prove the line")
    eq(wevaluate({ form_index = 3, energy = 20, tf_ready = true, combo_points = 5,
        sr_remaining = NONE }).hold_text, "TIGER'S FURY",
        "W1 outranks the SR upkeep")
    -- Leeway: 1.5 s of GCD remainder lowers the line to 25.
    eq(wevaluate({ form_index = 3, energy = 24.999, tf_ready = true,
        combo_points = 0, gcd_remaining = 1.5 }).hold_text, "TIGER'S FURY",
        "W1 leeway: 1.5 s GCD moves the line to 25")
    eq(wevaluate({ form_index = 3, energy = 25, tf_ready = true,
        combo_points = 0, gcd_remaining = 1.5 }).action, "shred",
        "W1 leeway boundary: exactly 25 energy with 1.5 s GCD -> Shred")
    -- Clearcasting adds a second of leeway (the proc keeps filling the bar).
    eq(wevaluate({ form_index = 3, energy = 29.999, tf_ready = true,
        combo_points = 0, clearcast = true }).hold_text, "TIGER'S FURY",
        "W1 leeway: Clearcasting moves the idle line to 30")
    eq(wevaluate({ form_index = 3, energy = 30, tf_ready = true,
        combo_points = 0, clearcast = true }).action, "shred",
        "W1 leeway boundary: exactly 30 energy on a proc -> the free Shred")
    -- An unreadable GCD contributes nothing: the line degrades to the frozen 40.
    eq(wevaluate({ form_index = 3, energy = 39.999, tf_ready = true,
        combo_points = 0, gcd_remaining = NONE }).hold_text, "TIGER'S FURY",
        "W1 leeway: an unknown GCD keeps the 40 line")
    eq(wevaluate({ form_index = 3, energy = 39.999, tf_ready = true,
        combo_points = 0, gcd_remaining = 0 / 0 }).hold_text, "TIGER'S FURY",
        "W1 leeway: a NaN GCD keeps the 40 line")
end

-- W2: Berserk with TF 15 s onto cooldown, Rip up and no proc (no energy gate).
do
    local out = wevaluate({ form_index = 3, energy = 100, berserk_ready = true,
        tf_cd_remaining = 15, combo_points = 0 })
    eq(out.action, nil, "W2: the Berserk call is a hold, never an action")
    eq(out.hold, true, "W2: the Berserk call rides the hold overlay")
    eq(out.hold_text, "BERSERK", "W2: the Berserk call reads BERSERK")
    eq(wevaluate({ form_index = 3, energy = 100, berserk_ready = true,
        tf_cd_remaining = 15, combo_points = 0, rip_remaining = NONE }).hold,
        false,
        "W2: an untracked Rip withholds Berserk (unknown never prompts)")
    eq(wevaluate({ form_index = 3, energy = 100, berserk_ready = true,
        tf_cd_remaining = 15, combo_points = 0, rip_remaining = 0 }).hold,
        false,
        "W2: an expired Rip withholds Berserk")
    eq(wevaluate({ form_index = 3, energy = 100, berserk_ready = true,
        tf_cd_remaining = 15, combo_points = 0, clearcast = true }).hold,
        false,
        "W2: a Clearcasting proc withholds Berserk (the free Shred comes first)")
    eq(wevaluate({ form_index = 3, energy = 20, berserk_ready = true,
        tf_cd_remaining = 14.999, combo_points = 0 }).hold, false,
        "W2 boundary: TF 14.999 s onto cooldown is not 15")
    eq(wevaluate({ form_index = 3, energy = 20, berserk_ready = true,
        tf_cd_remaining = NONE, combo_points = 0 }).hold, false,
        "W2: an unknown TF cooldown never Berserks")
    eq(wevaluate({ form_index = 3, energy = NONE, berserk_ready = true,
        tf_cd_remaining = 30, combo_points = 0 }).hold_text, "BERSERK",
        "W2: unreadable energy never withholds the cooldown call (no energy gate)")
    eq(wevaluate({ form_index = 3, energy = 20, berserk_ready = true,
        tf_cd_remaining = 30, tf_ready = true, combo_points = 0 }).hold_text,
        "TIGER'S FURY",
        "W1 outranks W2: a ready TF is taken before Berserk")
end

-- W3: Savage Roar upkeep (>= 1 CP, expired) rides the hold overlay (no SR slot).
do
    local out = wevaluate({ form_index = 3, energy = 90, combo_points = 1,
        sr_remaining = NONE })
    eq(out.action, nil, "W3: the SR call is a hold, never an action")
    eq(out.hold, true, "W3: the SR call rides the hold overlay")
    eq(out.hold_text, "SAVAGE ROAR", "W3: the SR call reads SAVAGE ROAR")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 1,
        sr_remaining = 0 }).hold_text, "SAVAGE ROAR",
        "W3: a remaining of exactly 0 is expired")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 1,
        sr_remaining = 0.0001 }).action, "shred",
        "W3: even a sliver of Savage Roar left is not expired")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 0,
        sr_remaining = NONE }).hold, false,
        "W3: no combo points cannot Roar")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = NONE,
        sr_remaining = NONE }).hold, false,
        "W3: an unreadable combo count cannot Roar")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 1,
        sr_remaining = 0 / 0 }).hold, false,
        "W3: a NaN Savage Roar cannot prove expiry")
end

-- W4: Clearcasting ahead of the finishers; W5: the 5 CP expiry-only Rip.
do
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 0, sr_remaining = 30,
        rip_remaining = 10, rake_remaining = 8, mangle_remaining = 6,
        clearcast = true }).action, "shred",
        "W4: the Omen proc is a free Shred")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 5, sr_remaining = 30,
        rip_remaining = NONE, clearcast = true }).action, "shred",
        "W4 outranks W5: the free Shred comes before even a missing Rip")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 5, sr_remaining = 30,
        rip_remaining = NONE, mangle_remaining = 6 }).action, "rip",
        "W5: 5 CP with no Rip -> Rip")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 5, sr_remaining = 30,
        rip_remaining = 0, mangle_remaining = 6 }).action, "rip",
        "W5: a remaining of exactly 0 is expired")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 5, sr_remaining = 30,
        rip_remaining = 0.0001, rake_remaining = 8, mangle_remaining = 6 }).action,
        "shred",
        "W5: even a sliver of Rip left is not expired (never clipped)")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 4, sr_remaining = 30,
        rip_remaining = NONE, mangle_remaining = 6, rake_remaining = 8 }).action,
        "shred",
        "W5: 4 CP cannot Rip -> Shred")
end

-- W6/W7: Mangle above Rake (the bleed multiplier outranks the bleed).
do
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 2, sr_remaining = 30,
        rip_remaining = 10, rake_remaining = NONE,
        mangle_remaining = NONE }).action, "mangle",
        "W6: absent Mangle and Rake -> Mangle first")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 2, sr_remaining = 30,
        rip_remaining = 10, rake_remaining = NONE,
        mangle_remaining = 6 }).action, "rake",
        "W7: a running Mangle falls through to an expired Rake")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 2, sr_remaining = 30,
        rip_remaining = 10, rake_remaining = 0.5,
        mangle_remaining = 0.5 }).action, "shred",
        "W6/W7: running debuffs never refresh early (no clipping anywhere)")
end

-- W8: the conditional Bite needs both Rip and Savage Roar healthy AND the
-- last-10-seconds execute window (the research removed it from the mid-fight
-- rotation; an unknown target defaults to the long fight and builds).
do
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 5, sr_remaining = 4,
        rip_remaining = 4, rake_remaining = 8, mangle_remaining = 6,
        target_short_lived = true }).action, "bite",
        "W8 boundary: 4 s of Rip and Roar on an execute-flagged target -> Ferocious Bite")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 5, sr_remaining = 30,
        rip_remaining = 10, rake_remaining = 8, mangle_remaining = 6,
        time_to_die = 10 }).action, "bite",
        "W8 boundary: exactly 10 s to die is execute -> Ferocious Bite")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 5, sr_remaining = 30,
        rip_remaining = 10, rake_remaining = 8, mangle_remaining = 6,
        time_to_die = 10.0001 }).action, "shred",
        "W8: just over 10 s to die is a long fight -> Shred")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 5, sr_remaining = 30,
        rip_remaining = 10, rake_remaining = 8, mangle_remaining = 6 }).action,
        "shred",
        "W8: healthy everything with no execute evidence never Bites mid-fight")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 5, sr_remaining = 30,
        rip_remaining = 10, rake_remaining = 8, mangle_remaining = 6,
        time_to_die = 0 / 0 }).action, "shred",
        "W8: a NaN time-to-die cannot prove execute")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 5, sr_remaining = 30,
        rip_remaining = 3.999, rake_remaining = 8, mangle_remaining = 6,
        target_short_lived = true }).action, "shred",
        "W8: 3.999 s of Rip withholds the Bite even on an execute target")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 5, sr_remaining = 3.999,
        rip_remaining = 10, rake_remaining = 8, mangle_remaining = 6,
        target_short_lived = true }).action, "shred",
        "W8: 3.999 s of Savage Roar withholds the Bite even on an execute target")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 5.5, sr_remaining = 30,
        rip_remaining = 10, rake_remaining = 8, mangle_remaining = 6,
        time_to_die = 5 }).action, "bite",
        "W8: above 5 combo points still Bites on an execute target")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 5, sr_remaining = 30,
        rip_remaining = 0 / 0, rake_remaining = 8, mangle_remaining = 6,
        target_short_lived = true }).action, "shred",
        "W8: a NaN Rip cannot prove the guard even on an execute target")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 5, sr_remaining = NONE,
        rip_remaining = 10, rake_remaining = 8, mangle_remaining = 6 }).hold_text,
        "SAVAGE ROAR",
        "W3 outranks W8: an expired Roar is refreshed before any Bite")
end

-- W9 and the Wrath hold/action vocabulary sweep: no SHIFT on Wrath (Furor no
-- longer refunds), no TF/Berserk/SR actions (no slots exist), every action a
-- declared slot.
do
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 2, sr_remaining = 30,
        rip_remaining = 10, rake_remaining = 8, mangle_remaining = 6 }).action,
        "shred",
        "W9: healthy everything with 2 CP builds with Shred")
    eq(wevaluate({ form_index = 3, energy = 60, combo_points = 0,
        rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6 }).action,
        "shred",
        "W9: the bare Wrath baseline builds (no CP-gated Rip, no windows)")
    local rips = { NONE, 0, 0.5, 8, 12 }
    local srs = { NONE, 0, 0.5, 8, 30 }
    local cps = { NONE, 0, 1, 4, 5 }
    local energies = { NONE, 0, 39.999, 40, 85, 85.0001, 100 }
    local readiness = { NONE, true, false }
    local swept = 0
    for _, rip in ipairs(rips) do
        for _, sr in ipairs(srs) do
            for _, cp in ipairs(cps) do
                for _, energy in ipairs(energies) do
                    for _, ready in ipairs(readiness) do
                        swept = swept + 1
                        local out = wevaluate({
                            form_index = 3, rip_remaining = rip,
                            rake_remaining = rip, mangle_remaining = rip,
                            sr_remaining = sr, combo_points = cp,
                            energy = energy, tf_ready = ready,
                            tf_cd_remaining = 30, berserk_ready = ready,
                            clearcast = ready, can_powershift = true,
                        })
                        check(out.hold_text ~= "SHIFT",
                            "Wrath sweep: powershifting never prompts")
                        if out.hold == true then
                            check(out.hold_text == "TIGER'S FURY"
                                or out.hold_text == "BERSERK"
                                or out.hold_text == "SAVAGE ROAR",
                                "Wrath sweep: the only holds are TF/Berserk/Roar")
                        end
                        if out.action ~= nil then
                            check(ui.slot_index[out.action] ~= nil,
                                "Wrath sweep: every action names a declared slot")
                        end
                    end
                end
            end
        end
    end
    eq(swept, 5 * 5 * 5 * 7 * 3, "the Wrath sweep covered every combination")
    local provider = ST.DRUID.guide
    local out = {}
    provider.evaluate(win({ form_index = 3, energy = 20, tf_ready = true,
        combo_points = 0 }), out)
    eq(out.hold_text, "TIGER'S FURY", "the provider delegates the Wrath TF hold")
end

--=========================================================================================
-- 10) The SOD cat branch (inputs.family == "ERA" with sod_runes)
--=========================================================================================
-- A SoD input set: the Era baseline plus the flag. NONE clears a key.
local function sin(overrides)
    local o = {}
    for k, v in pairs(overrides or {}) do o[k] = v end
    o.family = "ERA"
    o.sod_runes = true
    return o
end

local function sevaluate(overrides)
    return evaluate(sin(overrides))
end

-- S1: Tiger's Fury at or under 40 energy (King of the Jungle +60 cannot overcap).
do
    local out = sevaluate({ form_index = 3, energy = 40, tf_ready = true,
        combo_points = 0 })
    eq(out.action, nil, "S1: 40 energy with TF ready holds, never an action")
    eq(out.hold, true, "S1: the SoD TF call rides the hold overlay")
    eq(out.hold_text, "TIGER'S FURY", "S1: the SoD TF call reads TIGER'S FURY")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 40.0001,
        tf_ready = true, combo_points = 0 }).action, "shred",
        "S1 boundary: 40.0001 energy overcaps -> Shred")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 20,
        tf_ready = NONE, combo_points = 0 }).hold, false,
        "S1: an unknown TF state never calls")
end

-- S2: Berserk immediately after Tiger's Fury (TF burned).
do
    local out = sevaluate({ form_index = 3, energy = 90, berserk_ready = true,
        tf_ready = false, combo_points = 0 })
    eq(out.action, nil, "S2: the SoD Berserk call is a hold, never an action")
    eq(out.hold, true, "S2: the SoD Berserk call rides the hold overlay")
    eq(out.hold_text, "BERSERK", "S2: the SoD Berserk call reads BERSERK")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        berserk_ready = true, tf_ready = true, combo_points = 0 }).hold, false,
        "S2: a ready TF is taken first (S1 outranks on energy, else no call)")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        berserk_ready = true, tf_ready = NONE, combo_points = 0 }).hold, false,
        "S2: an unknown TF state never Berserks")
end

-- S3/S4: the Savage Roar refresh, then the Omen Shred ahead of the finishers.
do
    local out = sevaluate({ form_index = 3, energy = 90, combo_points = 2,
        sr_remaining = NONE })
    eq(out.hold_text, "SAVAGE ROAR", "S3: an absent Roar with CP holds SAVAGE ROAR")
    eq(out.action, nil, "S3: the Roar call carries no action")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 2, sr_remaining = 0 }).hold_text, "SAVAGE ROAR",
        "S3: a remaining of exactly 0 is expired")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 0, sr_remaining = NONE }).hold, false,
        "S3: no combo points cannot Roar")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 0, sr_remaining = 30, rip_remaining = 10, rake_remaining = 8,
        mangle_remaining = 6, clearcast = true }).action, "shred",
        "S4: the Omen proc is a free Shred")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 5, sr_remaining = 30, rip_remaining = NONE,
        clearcast = true }).action, "shred",
        "S4 outranks S5: the free Shred comes before even a missing Rip")
end

-- S5: the 5 CP Rip, expiry-only (the sim has no TF-snapshot term).
do
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 5, sr_remaining = 30, rip_remaining = NONE,
        mangle_remaining = 6 }).action, "rip",
        "S5: 5 CP with no Rip -> Rip")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 5, sr_remaining = 30, rip_remaining = 10,
        mangle_remaining = 6, rake_remaining = 8, tf_active = true }).action, "shred",
        "S5 contrast: a healthy Rip under Tiger's Fury is kept, not clipped")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 5, sr_remaining = 30, rip_remaining = 0.5,
        mangle_remaining = 6, rake_remaining = 8, tf_active = true }).action, "shred",
        "S5 contrast: TF never overrides a non-expired Rip")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 5, sr_remaining = 30, rip_remaining = 0,
        mangle_remaining = 6, rake_remaining = 8, tf_active = true }).action, "rip",
        "S5: an expired Rip still Rips under Tiger's Fury")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 4, sr_remaining = 30, rip_remaining = NONE,
        mangle_remaining = 6, rake_remaining = 8 }).action, "shred",
        "S5: 4 CP cannot Rip")
end

-- S6 (REMOVED - was the dormant powershift at ~0 energy): no SHIFT rule
-- exists, so the same inputs fall through to the builders below.
-- can_powershift is a reserved input no rule reads.
do
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 5,
        combo_points = 2, sr_remaining = 30, rip_remaining = 10,
        mangle_remaining = NONE, rake_remaining = 8,
        can_powershift = true }).action, "mangle",
        "removed S6: at ~0 energy with a claimed shift basis the absent Mangle prompts")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 5.0001,
        combo_points = 2, sr_remaining = 30, rip_remaining = 10, mangle_remaining = 6,
        rake_remaining = 8, can_powershift = true }).action, "shred",
        "removed S6: with everything present the builder is Shred")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 0,
        combo_points = 2, sr_remaining = 30, rip_remaining = 10, mangle_remaining = 6,
        rake_remaining = 8 }).hold, false,
        "removed S6: an unknown shift basis never holds (nil can_powershift)")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 0,
        combo_points = 5, sr_remaining = 30, rip_remaining = NONE,
        can_powershift = true }).action, "rip",
        "S5: the finisher comes first (no shift call exists to outrank)")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 0,
        combo_points = 2, sr_remaining = 30, rip_remaining = 10,
        mangle_remaining = NONE, rake_remaining = 8,
        can_powershift = true }).action, "mangle",
        "removed S6: at ~0 energy the absent Mangle prompts, never a shift")
end

-- S3b: the Roar clip (cover-to-end): the current Roar expires before the fight
-- ends but one fresh Roar covers it - refreshing early saves a full cast.
do
    eq(dg.SOD_SR_DURATION[1], 14, "SoD SR lasts 14 s at 1 CP")
    eq(dg.SOD_SR_DURATION[5], 34, "SoD SR lasts 34 s at 5 CP")
    -- 5 CP, Roar with 10 s left, 20 s to die: the 34 s fresh Roar covers the
    -- end, the current one does not -> clip now.
    local out = sevaluate({ form_index = 3, energy = 90, combo_points = 5,
        sr_remaining = 10, rip_remaining = 10, rake_remaining = 8,
        mangle_remaining = 6, time_to_die = 20 })
    eq(out.action, nil, "S3b: the clip call is a hold, never an action")
    eq(out.hold, true, "S3b: the clip rides the hold overlay")
    eq(out.hold_text, "SAVAGE ROAR", "S3b: the clip reads SAVAGE ROAR")
    -- The current Roar already covers the end: no clip (normal upkeep later).
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 5, sr_remaining = 25, rip_remaining = 10,
        rake_remaining = 8, mangle_remaining = 6, time_to_die = 20 }).action,
        "shred",
        "S3b contrast: a Roar covering the end never clips early")
    -- Even a fresh Roar cannot cover the end: no clip (refresh at expiry).
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 5, sr_remaining = 10, rip_remaining = 10,
        rake_remaining = 8, mangle_remaining = 6, time_to_die = 60 }).action,
        "shred",
        "S3b contrast: a fight outlasting a fresh Roar never clips")
    -- Unknown time-to-die: expiry-only, never a clip.
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 5, sr_remaining = 10, rip_remaining = 10,
        rake_remaining = 8, mangle_remaining = 6 }).action, "shred",
        "S3b: an unknown time-to-die never clips")
    -- No combo points: no fresh length to compare, never clips.
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 0, sr_remaining = 10, rip_remaining = 10,
        rake_remaining = 8, mangle_remaining = 6, time_to_die = 20 }).hold,
        false,
        "S3b: no combo points cannot prove a clip")
    -- An expired Roar belongs to S3, not the clip (same hold either way).
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 2, sr_remaining = 0, time_to_die = 20 }).hold_text,
        "SAVAGE ROAR",
        "S3 outranks S3b: an expired Roar refreshes, never clips")
    -- 1 CP fresh length (14 s): 10 s left with 12 s to die clips; 15 s does not.
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 1, sr_remaining = 10, rip_remaining = 10,
        rake_remaining = 8, mangle_remaining = 6, time_to_die = 12 }).hold_text,
        "SAVAGE ROAR",
        "S3b: the 1 CP fresh length (14 s) covers 12 s -> clip")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 1, sr_remaining = 10, rip_remaining = 10,
        rake_remaining = 8, mangle_remaining = 6, time_to_die = 15 }).hold,
        false,
        "S3b: 15 s to die needs more than a fresh 1 CP Roar -> Shred")
end

-- S6/S7/S8: Mangle, then Rake, then the ungated Shred (no Bite branch at all).
do
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 2, sr_remaining = 30, rip_remaining = 10,
        mangle_remaining = NONE, rake_remaining = NONE }).action, "mangle",
        "S6: absent Mangle and Rake -> Mangle first")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 2, sr_remaining = 30, rip_remaining = 10,
        mangle_remaining = 6, rake_remaining = NONE }).action, "rake",
        "S7: a present Mangle falls through to an expired Rake")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 5, sr_remaining = 30, rip_remaining = 10,
        mangle_remaining = 6, rake_remaining = 8 }).action, "shred",
        "S8: capped CP with a healthy Rip pools with Shred (no Bite branch)")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 4, sr_remaining = 30, rip_remaining = 10,
        mangle_remaining = 6, rake_remaining = 8 }).action, "shred",
        "S8: anything else builds with Shred")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 60,
        combo_points = 0 }).action, "shred",
        "S8: the bare SoD baseline builds (ungated, the E2 convention)")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 0,
        combo_points = 2, sr_remaining = 30, rip_remaining = 10,
        mangle_remaining = NONE, rake_remaining = 8 }).action, "mangle",
        "S6 documents the ungated builder: Mangle prompts even at 0 energy")
end

-- The SoD hold/action vocabulary sweep, the strict-true sod gate, and the SoD
-- bear fallback (Mangle via rune, never the Era wait).
do
    local rips = { NONE, 0, 0.5, 8, 12 }
    local srs = { NONE, 0, 30 }
    local cps = { NONE, 0, 2, 5 }
    local energies = { NONE, 0, 5, 40, 41, 90 }
    local flags = { NONE, true, false }
    local swept = 0
    for _, rip in ipairs(rips) do
        for _, sr in ipairs(srs) do
            for _, cp in ipairs(cps) do
                for _, energy in ipairs(energies) do
                    for _, flag in ipairs(flags) do
                        swept = swept + 1
                        local out = sevaluate({
                            form_index = 3, rip_remaining = rip,
                            rake_remaining = rip, mangle_remaining = rip,
                            sr_remaining = sr, combo_points = cp,
                            energy = energy, tf_ready = flag,
                            berserk_ready = flag, tf_active = flag,
                            clearcast = flag, can_powershift = flag,
                        })
                        if out.hold == true then
                            check(out.hold_text == "TIGER'S FURY"
                                or out.hold_text == "BERSERK"
                                or out.hold_text == "SAVAGE ROAR",
                                "SoD sweep: the only holds are TF/Berserk/Roar (no SHIFT)")
                        end
                        if out.action ~= nil then
                            check(ui.slot_index[out.action] ~= nil,
                                "SoD sweep: every action names a declared slot")
                        end
                    end
                end
            end
        end
    end
    eq(swept, 5 * 3 * 4 * 6 * 3, "the SoD sweep covered every combination")
    eq(evaluate({ family = "ERA", sod_runes = "true", form_index = 3,
        combo_points = 5, energy = 90 }).action, "shred",
        "the sod gate is strict: a non-true flag stays on the Era chain")
    eq(evaluate({ family = "ERA", sod_runes = false, form_index = 3,
        combo_points = 5, energy = 90 }).action, "shred",
        "a false flag stays on the Era chain too")
    eq(sevaluate({ form_index = 1, rage = 50, maul_cost = 15 }).action, "maul",
        "SoD bear: proven rage still Mauls")
    eq(sevaluate({ form_index = 1, rage = 5, maul_cost = 15 }).action, "mangle",
        "SoD bear: short of rage falls back to Mangle (the rune exists)")
    eq(sevaluate({ form_index = 1, maul_queued = true }).hold_text, "RIDE",
        "SoD bear: the queued Maul still rides")
    eq(evaluate({ family = "ERA", form_index = 1, rage = 5,
        maul_cost = 15 }).action, nil,
        "runeless Era bear contrast: waits where SoD Mangles")
    local provider = ST.DRUID.guide
    local out = {}
    provider.evaluate(sin({ form_index = 3, energy = 20, tf_ready = true,
        combo_points = 0 }), out)
    eq(out.hold_text, "TIGER'S FURY", "the provider delegates the SoD TF hold")
end

--=========================================================================================
-- 11) The gather writes the Wrath/SoD buff/cooldown inputs (unknown stays nil),
--     the SoD rune probe, and the ERA-token SoD display through a real sandbox
--=========================================================================================
do
    -- Flush the §3 player buffs first (the merged scan state survives sections).
    sandbox.player_auras = {}
    ST.mainhand.ends_at = sandbox.clock + 3.0
    sandbox.advance(0.1)
    ST.DRUID.on_bar_update(ST, "mainhand")
    ST.mainhand.ends_at = sandbox.clock + 3.0
    sandbox.advance(0.1)
    ST.DRUID.on_bar_update(ST, "mainhand")
    -- Defaults on the WRATH sandbox (no player buffs, no known cooldowns, no
    -- runes): every new input is the unknown shape, and stale values clear.
    -- RE-CUT (2026-10-25, operator ruling): the TF/Berserk read is gated on the client
    -- answering the spell's NAME (the Wrath/Titanforge query form). Pin the UNKNOWN
    -- shape by modelling a client whose spell data does not carry them - BOTH forms
    -- removed, because the id walk would otherwise derive the name itself.
    sandbox.missing_spells = { [5217] = true, [6793] = true, [9845] = true,
        [9846] = true, [50213] = true, [417045] = true, [50334] = true, [417141] = true }
    sandbox.missing_names = { ["Tiger's Fury"] = true, ["Berserk"] = true }
    local g = ST.DRUID.guide.gather(ST, {})
    eq(g.sr_remaining, nil, "gather: no Savage Roar tracked -> nil")
    eq(g.clearcast, nil, "gather: no Omen proc -> nil")
    eq(g.tf_active, nil, "gather: no Tiger's Fury buff -> nil")
    eq(g.tf_ready, nil, "gather: unknown TF cooldown -> nil (never a guess)")
    eq(g.tf_cd_remaining, nil, "gather: unknown TF cooldown -> nil")
    eq(g.berserk_ready, nil, "gather: unknown Berserk -> nil (never a guess)")
    eq(g.sod_runes, nil, "gather: off the ERA token the rune flag stays nil")
    local reused = { sr_remaining = 5, clearcast = true, tf_active = true,
        tf_ready = true, tf_cd_remaining = 0, berserk_ready = true,
        sod_runes = true }
    local g2 = ST.DRUID.guide.gather(ST, reused)
    eq(g2.sr_remaining, nil, "a stale Savage Roar is cleared")
    eq(g2.clearcast, nil, "a stale Clearcasting is cleared")
    eq(g2.tf_active, nil, "a stale Tiger's Fury buff is cleared")
    eq(g2.tf_ready, nil, "a stale TF ready is cleared")
    eq(g2.tf_cd_remaining, nil, "a stale TF cooldown is cleared")
    eq(g2.berserk_ready, nil, "a stale Berserk ready is cleared")
    eq(g2.sod_runes, nil, "a stale rune flag is cleared off-token")
    sandbox.missing_spells = nil
    sandbox.missing_names = nil

    -- The player scan feeds the buff inputs (two ticks: scan, then evaluate).
    sandbox.player_auras = {
        { name = "Savage Roar", count = 1, duration = 34,
            expiration = sandbox.clock + 30, source = "player", spell_id = 52610 },
        { name = "Clearcasting", count = 1, duration = 15,
            expiration = sandbox.clock + 10, source = "player", spell_id = 16870 },
        { name = "Tiger's Fury", count = 1, duration = 6,
            expiration = sandbox.clock + 5, source = "player", spell_id = 5217 },
    }
    ST.mainhand.ends_at = sandbox.clock + 3.0
    sandbox.advance(0.1)
    ST.DRUID.on_bar_update(ST, "mainhand")
    ST.mainhand.ends_at = sandbox.clock + 3.0
    sandbox.advance(0.1)
    ST.DRUID.on_bar_update(ST, "mainhand")
    check(sandbox.player_aura_calls > 0, "the guide runs the player-buff scan")
    local fed = ST.DRUID.guide.gather(ST, {})
    near(fed.sr_remaining, 30, 0.2, "the scan feeds sr_remaining")
    eq(fed.clearcast, true, "the scan feeds the Clearcasting proc")
    eq(fed.tf_active, true, "the scan feeds the Tiger's Fury buff")
    -- A foreign caster's buff does not qualify, and a cleared player clears
    -- the frozen buff inputs on the very next gather.
    sandbox.player_auras = {
        { name = "Savage Roar", count = 1, duration = 34,
            expiration = sandbox.clock + 30, source = "other", spell_id = 52610 },
    }
    ST.mainhand.ends_at = sandbox.clock + 3.0
    sandbox.advance(0.1)
    ST.DRUID.on_bar_update(ST, "mainhand")
    ST.mainhand.ends_at = sandbox.clock + 3.0
    sandbox.advance(0.1)
    ST.DRUID.on_bar_update(ST, "mainhand")
    local cleared = ST.DRUID.guide.gather(ST, {})
    eq(cleared.sr_remaining, nil, "another caster's Roar never feeds sr_remaining")
    eq(cleared.clearcast, nil, "a vanished Omen clears the proc")
    eq(cleared.tf_active, nil, "a vanished Tiger's Fury clears the buff")
    sandbox.player_auras = {}

    -- The cooldown inputs: RE-CUT (2026-10-25, operator ruling) - the gate is the
    -- client answering the spell's NAME (spell data), not known_names. Model no data
    -- for the unknown leg; restore it for the ready leg.
    sandbox.known_names = {}
    sandbox.cooldowns_by_query = {}
    sandbox.missing_spells = { [5217] = true, [6793] = true, [9845] = true,
        [9846] = true, [50213] = true, [417045] = true, [50334] = true, [417141] = true }
    sandbox.missing_names = { ["Tiger's Fury"] = true, ["Berserk"] = true }
    local unknown = ST.DRUID.guide.gather(ST, {})
    eq(unknown.tf_ready, nil, "no TF spell data reads nil (never a guess)")
    eq(unknown.berserk_ready, nil, "an unproven Berserk never reads ready")
    sandbox.missing_spells = nil
    sandbox.missing_names = nil
    sandbox.known_names = { ["Tiger's Fury"] = true, ["Berserk"] = true }
    local ready = ST.DRUID.guide.gather(ST, {})
    eq(ready.tf_ready, true, "a known TF with no cooldown reads ready")
    eq(ready.tf_cd_remaining, 0, "a ready TF reports a zero cooldown")
    eq(ready.berserk_ready, true, "a known Berserk with no cooldown reads ready")
    sandbox.cooldowns_by_query = { ["Tiger's Fury"] = { sandbox.clock, 30 } }
    local burning = ST.DRUID.guide.gather(ST, {})
    near(burning.tf_cd_remaining, 30, 0.2, "a burning TF reports its cooldown")
    eq(burning.tf_ready, false, "a burning TF reads explicitly false (SoD S2)")
    eq(burning.berserk_ready, true, "Berserk stays ready while TF burns")
    sandbox.cooldowns_by_query = { ["Tiger's Fury"] = { sandbox.clock, 1.2 } }
    local gcd_echo = ST.DRUID.guide.gather(ST, {})
    eq(gcd_echo.tf_cd_remaining, 0, "the 1.2 s GCD echo is filtered, not a TF cooldown")
    eq(gcd_echo.tf_ready, true, "the filtered echo reads ready")
    sandbox.known_names = {}
    sandbox.cooldowns_by_query = {}

    -- The APL utility layer's gather reads (the rotation table's utility spine):
    -- every one of them is knowledge-gated or tri-state, and an unreadable read
    -- stays unknown (the engine never prompts off a guess).
    local util = ST.DRUID.guide.gather(ST, {})
    eq(util.lop_known, false, "utility gather: an unproven Leader of the Pack is not known")
    eq(util.lop_active, false,
        "utility gather: a scanned player without the Leader of the Pack reads proven absent")
    eq(util.feral_ff_ready, nil, "utility gather: an unknown Feral Faerie Fire stays unknown")
    eq(util.innervate_ready, nil, "utility gather: an unknown Innervate stays unknown")
    eq(util.elunes_light_ready, nil, "utility gather: the Elune's Light is the Forever row")
    eq(util.ff_debuff_remaining, false,
        "utility gather: the target walk answered - the target carries no Faerie Fire")
    eq(util.mana_percent, nil, "utility gather: an unreadable mana pool stays unknown")
    -- The form upkeep's reads: the Feral-tree spec probe and the Cat Form aura.
    -- The WotLK client has no Cat Form row, so the spec probe stays unknown there.
    eq(util.feral_spec, nil,
        "utility gather: a family with no Cat Form row has no spec probe")
    eq(util.cat_form_active, false,
        "utility gather: a scanned player without the Cat Form aura reads proven absent")
    -- A known Innervate with no cooldown reads ready.
    sandbox.known_names = { ["Innervate"] = true }
    local inn = ST.DRUID.guide.gather(ST, {})
    eq(inn.innervate_ready, true, "utility gather: a known Innervate with no cooldown reads ready")
    sandbox.cooldowns_by_query = { ["Innervate"] = { sandbox.clock, 180 } }
    local inn_burning = ST.DRUID.guide.gather(ST, {})
    eq(inn_burning.innervate_ready, false, "utility gather: a burning Innervate reads false")
    sandbox.known_names = {}
    sandbox.cooldowns_by_query = {}
end

--=========================================================================================
-- 12) The ERA-token SoD display: the rune probe flips an Era sandbox onto the
--     SOD APPENDIX (guide, HUD gate and frame). The probe latches per session
--     like the rank resolvers: each scenario below is a fresh sandbox.
--=========================================================================================
do
    local function new_sod_sandbox(opts)
        opts = opts or {}
        opts.project = 2
        local fresh = build(opts)
        local FST = fresh.ST
        FST.in_combat = true
        FST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
        FST.gcd = { expires = 0 }
        FST.DRUID.post_init(FST)
        return fresh, FST
    end
    local era_only = new_sod_sandbox()
    eq(era_only.st.family, "ERA", "project 2 reports the ERA family")
    local EST0 = era_only.ST
    local sprobe = EST0.DRUID.guide.gather(EST0, {})
    eq(sprobe.sod_runes, nil, "runeless Era: the probe stays nil")
    eq(sprobe.family, "ERA", "runeless Era: the family rides through")
    -- Id knowledge flips with no name answering (the non-enUS client:
    -- GetSpellInfo("Mangle") is nil there, IsSpellKnown(33983) is true).
    local id_sod, IST = new_sod_sandbox({ known_ids = { [33983] = true } })
    eq(IST.DRUID.guide.gather(IST, {}).sod_runes, true,
        "a known Mangle rank flips the ERA token to SoD with no name probe")
    -- The second Mangle rank id probes too.
    local id2_sod = new_sod_sandbox({ known_ids = { [33987] = true } })
    eq(id2_sod.ST.DRUID.guide.gather(id2_sod.ST, {}).sod_runes, true,
        "the second Mangle rank id flips the token too")
    -- Name fallback: a rune the module never tracked by id still flips.
    local name_sod, NST = new_sod_sandbox()
    name_sod.known_names = { ["Savage Roar"] = true }
    eq(NST.DRUID.guide.gather(NST, {}).sod_runes, true,
        "a known Savage Roar flips the token too (name fallback)")
    -- Session latch: forgetting mid-session keeps the flag until /reload.
    name_sod.known_names = {}
    eq(NST.DRUID.guide.gather(NST, {}).sod_runes, true,
        "the probe latches per session: forgetting mid-session needs /reload")

    -- The SoD display: 5 CP with a healthy Rip pools with Shred (no TF clip,
    -- no Bite branch), and the Mangle HUD slot stays live with the rune.
    local sod, SST, sui = id_sod, IST, id_sod.st.nextaction_ui
    SST.form_index = 3
    sod.energy = 90
    sod.combo = 5
    local function stick(advance)
        SST.mainhand.ends_at = sod.clock + 3.0
        sod.advance(advance or 0.1)
        SST.DRUID.on_bar_update(SST, "mainhand")
    end
    local function starget(key)
        return sui.icons[sui.slot_index[key]].fade.target
    end
    sod.player_auras = {
        { name = "Tiger's Fury", count = 1, duration = 6,
            expiration = sod.clock + 30, source = "player", spell_id = 5217 },
        { name = "Savage Roar", count = 1, duration = 34,
            expiration = sod.clock + 30, source = "player", spell_id = 52610 },
    }
    sod.target_auras = {
        { name = "Rip", count = 1, duration = 12, expiration = sod.clock + 30,
            source = "player", spell_id = 1079 },
        { name = "Rake", count = 1, duration = 9, expiration = sod.clock + 30,
            source = "player", spell_id = 1822 },
        { name = "Mangle", count = 1, duration = 12, expiration = sod.clock + 30,
            source = "player", spell_id = 33987 },
    }
    stick()
    stick()
    eq(starget("rip"), 0, "SoD display: a healthy Rip is kept, not clipped for TF")
    eq(starget("shred"), 1, "SoD display: the capped bar pools with Shred")
    local mangle_slot = { key = "mangle", title = "Mangle", kind = "spell", spell = 33878 }
    eq(SST.DRUID.get_hud_state(SST, mangle_slot, sod.clock).hidden, nil,
        "SoD display: the Mangle HUD slot stays live with the rune")
    -- Roar falls off: the hold overlay calls SAVAGE ROAR (no SR slot exists).
    sod.player_auras = {
        { name = "Tiger's Fury", count = 1, duration = 6,
            expiration = sod.clock + 30, source = "player", spell_id = 5217 },
    }
    stick()
    stick()
    eq(sui.frame.hold.fade.target, 1, "SoD display: an expired Roar holds the frame")
    eq(sui.frame.hold.text.text, "SAVAGE ROAR", "SoD display: the hold reads SAVAGE ROAR")
    eq(starget("rip"), 0, "SoD display: the Roar call carries no action")
end

--=========================================================================================
-- 13) TBC 2pc-T6: the live Mangle cost lowers the T2 line (nil keeps the 40)
--=========================================================================================
eq(dg.MANGLE_COST_TBC, 40, "the TBC Mangle default stays 40 energy")
eq(dg.MANGLE_COST_T6_2PC_TBC, 35, "the 2pc-T6 Mangle cost is 35 energy")

do
    -- The bonus input carries the documented constant (the gather proves it
    -- live through GetSpellPowerCost; whether the client reports the set
    -- reduction there is in-game to confirm).
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 0,
        rake_remaining = 8, mangle_remaining = NONE, energy = 35,
        mangle_cost = dg.MANGLE_COST_T6_2PC_TBC }).action, "mangle",
        "T2 with the set bonus: 35 energy Mangles")
    local out = tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 0,
        rake_remaining = 8, mangle_remaining = NONE, energy = 34.999,
        mangle_cost = dg.MANGLE_COST_T6_2PC_TBC })
    eq(out.action, nil, "T2 boundary with the set bonus: 34.999 cannot Mangle -> wait")
    eq(out.hold, false, "the bonus wait carries no hold without a feasible shift")
    -- Without the input the frozen 40 still decides (byte-identical).
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 0,
        rake_remaining = 8, mangle_remaining = NONE, energy = 35 }).action, nil,
        "T2 without the bonus input: 35 energy still waits")
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 0,
        rake_remaining = 8, mangle_remaining = NONE, energy = 35,
        mangle_cost = NONE }).action, nil,
        "T2 with a cleared bonus input falls back to 40")
    -- A non-number cost never lowers the line; NaN energy still cannot spend.
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 0,
        rake_remaining = 8, mangle_remaining = NONE, energy = 35,
        mangle_cost = "35" }).action, nil,
        "T2: a non-number cost falls back to 40")
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 0,
        rake_remaining = 8, mangle_remaining = NONE, energy = 0 / 0,
        mangle_cost = dg.MANGLE_COST_T6_2PC_TBC }).action, nil,
        "T2: NaN energy cannot spend even with the bonus")
    -- Ordering is untouched: T1 still outranks a cheap Mangle, and a cheap
    -- affordable Mangle still outranks the shift call.
    eq(tevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 5,
        mangle_remaining = NONE, energy = 35,
        mangle_cost = dg.MANGLE_COST_T6_2PC_TBC }).action, "rip",
        "T1 outranks the cheap Mangle: an expired Rip with 5 CP still Rips")
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 2,
        mangle_remaining = NONE, energy = 35, can_powershift = true,
        mangle_cost = dg.MANGLE_COST_T6_2PC_TBC }).action, "mangle",
        "T2: a cheap affordable Mangle prompts (no shift call exists to beat)")
end

--=========================================================================================
-- 14) The FOREVER cat branch: F1 Shifting Power, then the Forever chain F2-F7;
--     never Tiger's Fury, never powershift (all UNCONFIRMED - see the
--     FOREVER APPENDIX in druid_guide.lua)
--=========================================================================================
eq(dg.SP_ENERGY_GAIN_FOREVER, 40, "Shifting Power grants 40 energy (UNCONFIRMED)")
eq(dg.SP_ENERGY_FOREVER, 50, "Shifting Power fires with room for 40 (ceiling 50)")
eq(dg.SP_ENERGY_FOREVER_CLEARCAST, 40, "the ceiling drops to 40 on Clearcasting")
eq(dg.SP_ENERGY_FOREVER, 100 - dg.SP_ENERGY_GAIN_FOREVER - 10,
    "the 50 ceiling leaves 10-regen headroom over the GCD (100 - 50 - 40)")
eq(dg.FOREVER_BITE_LOW_TTD_SECONDS, 3, "the Forever bite-low window is 3 s")

-- A Forever input set: the legacy baseline plus the family flag. NONE clears a key.
local function fin(overrides)
    local o = {}
    for k, v in pairs(overrides or {}) do o[k] = v end
    o.family = "FOREVER"
    return o
end

local function fevaluate(overrides)
    return evaluate(fin(overrides))
end

do
    -- F1: proven-ready Shifting Power with room rides the hold overlay (no
    -- slot exists for it). Baseline cp is 0, Rip/Rake/Mangle healthy.
    local out = fevaluate({ form_index = 3, energy = 50, sp_ready = true,
        combo_points = 0 })
    eq(out.action, nil, "F1: the Shifting Power call is a hold, never an action")
    eq(out.hold, true, "F1: the call rides the hold overlay")
    eq(out.hold_text, "SHIFTING POWER", "F1: the call reads SHIFTING POWER")
    eq(out.filler_slot, nil, "F1: the call carries no filler")
    eq(out.judge_slot, nil, "F1: the call carries no judge cue")
    eq(fevaluate({ family = "FOREVER", form_index = 3, energy = 50.0001,
        sp_ready = true, combo_points = 0 }).action, "shred",
        "F1 boundary: 50.0001 energy has no room -> Shred")
    eq(fevaluate({ family = "FOREVER", form_index = 3, energy = 40,
        sp_ready = true, combo_points = 0, clearcast = true }).hold_text,
        "SHIFTING POWER",
        "F1 boundary: exactly 40 energy on a proc still holds")
    eq(fevaluate({ family = "FOREVER", form_index = 3, energy = 40.0001,
        sp_ready = true, combo_points = 0, clearcast = true }).action, "shred",
        "F1 boundary: 40.0001 energy on a proc falls to the free Shred")
    eq(fevaluate({ family = "FOREVER", form_index = 3, energy = 39.999,
        sp_ready = true, combo_points = 0, clearcast = true }).hold_text,
        "SHIFTING POWER",
        "F1: 39.999 energy on a proc still holds SHIFTING POWER")
    eq(fevaluate({ family = "FOREVER", form_index = 3, energy = 20,
        sp_ready = false, combo_points = 0 }).hold, false,
        "F1: a Shifting Power on cooldown never calls (false is not true)")
    eq(fevaluate({ family = "FOREVER", form_index = 3, energy = 20,
        combo_points = 0 }).hold, false,
        "F1: an unknown Shifting Power never calls (nil is not true)")
    eq(fevaluate({ family = "FOREVER", form_index = 3, energy = NONE,
        sp_ready = true, combo_points = 0 }).hold, false,
        "F1: unreadable energy cannot prove the room")
    eq(fevaluate({ family = "FOREVER", form_index = 3, energy = 0 / 0,
        sp_ready = true, combo_points = 0 }).hold, false,
        "F1: NaN energy cannot prove the room")
    -- F1 outranks the maintenance chain (the gain comes first, the W1
    -- precedent) and is Forever-gated.
    eq(fevaluate({ family = "FOREVER", form_index = 3, energy = 20,
        sp_ready = true, combo_points = 5, rip_remaining = NONE }).hold_text,
        "SHIFTING POWER",
        "F1 outranks the Rip refresh")
    eq(evaluate({ form_index = 3, energy = 20, sp_ready = true,
        combo_points = 0 }).hold, false,
        "F1 is Forever-gated: a missing family never holds")
    eq(tevaluate({ form_index = 3, energy = 20, sp_ready = true,
        combo_points = 0 }).hold, false,
        "F1 is Forever-gated: TBC never holds SHIFTING POWER")
    -- Tiger's Fury is absent on Forever: even a "ready" reading never holds.
    eq(fevaluate({ family = "FOREVER", form_index = 3, energy = 20,
        tf_ready = true, combo_points = 0 }).hold, false,
        "Forever: Tiger's Fury is absent - a ready TF never holds")
    eq(fevaluate({ family = "FOREVER", form_index = 3, energy = 20,
        tf_ready = true, combo_points = 0 }).hold_text, nil,
        "Forever: no TF hold text either")
    -- Past F1 the Forever chain F2-F7 runs (expiry-only, Bite end-only).
    eq(fevaluate({ family = "FOREVER", form_index = 3, rip_remaining = NONE,
        combo_points = 5, mangle_remaining = 6, energy = 100 }).action, "rip",
        "F3: 5 CP with no Rip tracked Rips (no window, no CP gate beyond 5)")
    eq(fevaluate({ family = "FOREVER", form_index = 3, rip_remaining = 8,
        combo_points = 5, mangle_remaining = 6, energy = 100 }).action, "shred",
        "F3 contrast: a healthy Rip is never clipped -> Shred")
    eq(fevaluate({ family = "FOREVER", form_index = 3, rip_remaining = 8,
        combo_points = 5, mangle_remaining = 6, energy = 100,
        target_short_lived = true }).action, "bite",
        "F6a: 5 CP on an execute-flagged target Bites")
    eq(fevaluate({ family = "FOREVER", form_index = 3, rip_remaining = 8,
        combo_points = 5, mangle_remaining = 6, energy = 100 }).action, "shred",
        "F6a contrast: no execute evidence never Bites mid-fight")
    eq(fevaluate({ family = "FOREVER", form_index = 3, rip_remaining = 8,
        combo_points = 4, mangle_remaining = 6, rake_remaining = 8,
        energy = 100, time_to_die = 2 }).action, "bite",
        "F6b: 4 CP inside 3 s dumps the Bite")
    eq(fevaluate({ family = "FOREVER", form_index = 3, rip_remaining = 8,
        combo_points = 2, mangle_remaining = 6, rake_remaining = 8,
        energy = 100, time_to_die = 2 }).action, "shred",
        "F6b boundary: 2 CP cannot dump even inside 3 s")
    eq(fevaluate({ family = "FOREVER", form_index = 3, rip_remaining = 8,
        combo_points = 0, mangle_remaining = 6, rake_remaining = 8,
        energy = 100, clearcast = true }).action, "shred",
        "F2: the Omen proc builds with Shred")
    -- HU-14 (closed 2026-10-20): the FOREVER client carries NO Mangle spell, so
    -- the chain must never name one. The slot the Mangle row stood in falls
    -- through to the APL's own order (the Bite, then the builder).
    eq(fevaluate({ family = "FOREVER", form_index = 3, rip_remaining = 8,
        combo_points = 2, mangle_remaining = NONE, rake_remaining = 8,
        energy = 100 }).action, "shred",
        "HU-14: the Forever chain never answers Mangle - it builds with Shred")
    eq(fevaluate({ family = "FOREVER", form_index = 3, rip_remaining = 8,
        combo_points = 5, mangle_remaining = NONE, rake_remaining = 8,
        energy = 100, target_short_lived = true }).action, "bite",
        "HU-14: the F6 Bite branch is reachable again on the Forever client")
    eq(fevaluate({ family = "FOREVER", form_index = 3, rip_remaining = 8,
        combo_points = 2, mangle_remaining = 6, rake_remaining = NONE,
        energy = 100 }).action, "rake",
        "F4: an untracked Rake prompts it")
    eq(fevaluate({ family = "FOREVER", form_index = 3 }).action, "shred",
        "F7: the bare Forever baseline builds")
    eq(fevaluate({ family = "FOREVER", form_index = 1 }).action, "maul",
        "Forever bear: the bear rules are untouched")
end

-- No powershifting on Forever (and no Tiger's Fury anywhere): the hold/action
-- vocabulary sweep over the whole Forever input space.
do
    local rips = { NONE, 0, 8 }
    local energies = { NONE, 0, 20, 50, 50.0001, 100 }
    local cps = { NONE, 0, 5 }
    local flags = { NONE, true, false }
    local swept = 0
    for _, rip in ipairs(rips) do
        for _, energy in ipairs(energies) do
            for _, cp in ipairs(cps) do
                for _, flag in ipairs(flags) do
                    swept = swept + 1
                    local out = fevaluate({
                        form_index = 3, rip_remaining = rip,
                        rake_remaining = rip, mangle_remaining = rip,
                        combo_points = cp, energy = energy,
                        sp_ready = flag, can_powershift = flag,
                        tf_ready = flag, clearcast = flag,
                    })
                    check(out.hold_text ~= "SHIFT",
                        "Forever sweep: powershifting never prompts")
                    check(out.hold_text ~= "TIGER'S FURY",
                        "Forever sweep: Tiger's Fury never prompts")
                    -- HU-14 (closed 2026-10-20): the Forever client has NO Mangle
                    -- spell, so no input combination may ever name one.
                    check(out.action ~= "mangle",
                        "Forever sweep: the chain never answers Mangle (no such spell)")                    if out.hold == true then
                        check(out.hold_text == "SHIFTING POWER",
                            "Forever sweep: the only hold is SHIFTING POWER")
                    end
                    if out.action ~= nil then
                        check(ui.slot_index[out.action] ~= nil,
                            "Forever sweep: every action names a declared slot")
                    end
                end
            end
        end
    end
    eq(swept, 3 * 6 * 3 * 3, "the Forever sweep covered every combination")
    -- HU-14 (closed 2026-10-20): the Mangle debuff is walked on its own here
    -- (the Mangle branch sits BEHIND the Rip and the Rake branches, so the sweep
    -- above - where all three move together - never reaches it). No input
    -- combination may ever answer a Mangle on the Forever client.
    local mangles = { NONE, 0, 8 }
    local mangle_swept = 0
    for _, mangle in ipairs(mangles) do
        for _, rake in ipairs({ NONE, 0, 8 }) do
            for _, rip in ipairs({ NONE, 0, 8 }) do
                for _, cp in ipairs({ 0, 5 }) do
                    for _, clearcast in ipairs({ true, false }) do
                        mangle_swept = mangle_swept + 1
                        local out = fevaluate({
                            form_index = 3, rip_remaining = rip, rake_remaining = rake,
                            mangle_remaining = mangle, combo_points = cp, energy = 60,
                            clearcast = clearcast,
                        })
                        check(out.action ~= "mangle",
                            "Forever Mangle sweep: the chain never answers Mangle (no such spell)")
                    end
                end
            end
        end
    end
    eq(mangle_swept, 3 * 3 * 3 * 2 * 2, "the Forever Mangle sweep covered every combination")
    local provider = ST.DRUID.guide
    local out = {}
    provider.evaluate(fin({ form_index = 3, energy = 20, sp_ready = true,
        combo_points = 0 }), out)
    eq(out.hold_text, "SHIFTING POWER", "the provider delegates the Forever hold")
end

-- The Forever display through a real Forever sandbox: proven-ready Shifting
-- Power holds the frame, and the engine's decision reaches the overlay text.
do
    local forever = build({ project = 18 })
    eq(forever.st.family, "FOREVER", "project 18 reports the FOREVER family")
    local FST, fui = forever.ST, forever.st.nextaction_ui
    FST.in_combat = true
    FST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
    FST.gcd = { expires = 0 }
    FST.DRUID.post_init(FST)
    check(fui.frame ~= nil, "the Forever sandbox builds the guide frame")
    FST.form_index = 3
    forever.energy = 20
    forever.combo = 0
    forever.known_names = { ["Shifting Power"] = true }
    local function ftick(advance)
        FST.mainhand.ends_at = forever.clock + 3.0
        forever.advance(advance or 0.1)
        FST.DRUID.on_bar_update(FST, "mainhand")
    end
    local function ftarget(key)
        return fui.icons[fui.slot_index[key]].fade.target
    end
    ftick()
    ftick()
    eq(fui.frame.hold.fade.target, 1, "Forever display: ready Shifting Power holds the frame")
    eq(fui.frame.hold.text.text, "SHIFTING POWER", "Forever display: the hold reads SHIFTING POWER")
    eq(ftarget("rip"), 0, "Forever display: the hold carries no action")
    eq(ftarget("shred"), 0, "Forever display: the builder stays dark under the hold")
end

--=========================================================================================
-- 15) The gather writes the TBC Mangle cost and the Forever Shifting Power
--     inputs (unknown stays nil), each gated to its family
--=========================================================================================
do
    -- Off-token (the WRATH sandbox): both stay nil, and stale values clear.
    local g = ST.DRUID.guide.gather(ST, {})
    eq(g.mangle_cost, nil, "gather: no live Mangle cost off the TBC token")
    eq(g.sp_ready, nil, "gather: no Shifting Power off the FOREVER token")
    eq(g.sp_cd_remaining, nil, "gather: no Shifting Power cooldown off-token")
    local reused = { mangle_cost = 35, sp_ready = true, sp_cd_remaining = 0 }
    local g2 = ST.DRUID.guide.gather(ST, reused)
    eq(g2, reused, "the reused table is the same table")
    eq(g2.mangle_cost, nil, "a stale Mangle cost is cleared off-token")
    eq(g2.sp_ready, nil, "a stale Shifting Power ready is cleared off-token")
    eq(g2.sp_cd_remaining, nil, "a stale Shifting Power cooldown is cleared off-token")

    -- TBC sandbox: the live cost answers through the current rank (35 here),
    -- while Shifting Power stays nil on the wrong token.
    local tbc = build({ project = 5 })
    eq(tbc.st.family, "TBC", "project 5 reports the TBC family")
    local TST = tbc.ST
    TST.in_combat = true
    TST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
    TST.gcd = { expires = 0 }
    TST.DRUID.post_init(TST)
    tbc.rage_cost = { { cost = 35 } }
    TST.form_index = 3
    local tg = TST.DRUID.guide.gather(TST, {})
    eq(tg.mangle_cost, 35, "gather: the TBC Mangle cost answers live (2pc-T6 35)")
    eq(tg.sp_ready, nil, "gather: no Shifting Power on the TBC token")
    eq(tg.sp_cd_remaining, nil, "gather: no Shifting Power cooldown on the TBC token")

    -- An unresolved Mangle rank yields no cost and skips the query entirely.
    local tbc_bare = build({ project = 5 })
    tbc_bare.hide_spells = true
    tbc_bare.ST.DRUID.post_init(tbc_bare.ST)
    tbc_bare.rage_cost = { { cost = 35 } }
    tbc_bare.cost_queries = 0
    local tbg = tbc_bare.ST.DRUID.guide.gather(tbc_bare.ST, {})
    eq(tbg.mangle_cost, nil, "gather: an unresolved Mangle rank yields no cost")
    eq(tbc_bare.cost_queries, 0, "an unresolved rank skips the cost query entirely")

    -- Forever sandbox: the Shifting Power cooldown is knowledge-gated (the
    -- fixture answers 0,0 for everything unlisted, so knowledge alone decides).
    local sp = build({ project = 18 })
    local SST = sp.ST
    SST.in_combat = true
    SST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
    SST.gcd = { expires = 0 }
    SST.DRUID.post_init(SST)
    local unknown = SST.DRUID.guide.gather(SST, {})
    eq(unknown.sp_ready, nil, "an unknown Shifting Power stays nil (never a guess)")
    eq(unknown.sp_cd_remaining, nil, "an unknown cooldown stays nil")
    eq(unknown.mangle_cost, nil, "no live Mangle cost on the FOREVER token")
    sp.known_names = { ["Shifting Power"] = true }
    local ready = SST.DRUID.guide.gather(SST, {})
    eq(ready.sp_ready, true, "a known Shifting Power with no cooldown reads ready")
    eq(ready.sp_cd_remaining, 0, "a ready Shifting Power reports a zero cooldown")
    sp.cooldowns_by_query = { ["Shifting Power"] = { sp.clock, 16 } }
    local burning = SST.DRUID.guide.gather(SST, {})
    near(burning.sp_cd_remaining, 16, 0.2, "a burning Shifting Power reports its cooldown")
    eq(burning.sp_ready, false, "a burning Shifting Power reads explicitly false")
    sp.cooldowns_by_query = { ["Shifting Power"] = { sp.clock, 1.2 } }
    local echo = SST.DRUID.guide.gather(SST, {})
    eq(echo.sp_cd_remaining, 0, "the 1.2 s GCD echo is filtered, not a cooldown")
    eq(echo.sp_ready, true, "the filtered echo reads ready")
    sp.known_names = {}
    sp.cooldowns_by_query = {}
    local cleared = SST.DRUID.guide.gather(SST, { sp_ready = true, sp_cd_remaining = 0 })
    eq(cleared.sp_ready, nil, "a stale Shifting Power ready is cleared when unknown")
    eq(cleared.sp_cd_remaining, nil, "a stale Shifting Power cooldown is cleared when unknown")
end

--=========================================================================================
-- 16) D4: the EMA-smoothed time-to-die feeds the gather's time_to_die
--     (bench/verify_bank.md §4.1 - the velocity is smoothed, never raw)
--=========================================================================================
do
    local t = build()
    local TST = t.ST
    TST.in_combat = true
    TST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
    TST.gcd = { expires = 0 }
    TST.DRUID.post_init(TST)
    local function gather()
        return TST.DRUID.guide.gather(TST, {})
    end

    -- No target at all.
    eq(gather().time_to_die, nil, "D4: no target -> nil")

    -- A target appears; the first sample seeds the baseline only.
    t.target_guid = "Target-1"
    t.target_hp = 1000
    t.clock = 0
    eq(gather().time_to_die, nil, "D4: the first sample seeds the baseline")
    -- 0.5 s later, 100 hp lost: raw 200 HP/s -> 900 / 200 = 4.5 s.
    t.clock = 0.5
    t.target_hp = 900
    near(gather().time_to_die, 4.5, 0.01, "D4: the second sample yields hp / velocity")
    -- The same clock with fresh hp does not advance the baseline (the throttle).
    t.target_hp = 850
    near(gather().time_to_die, 4.25, 0.01, "D4: the 0.25 s throttle holds the baseline")
    -- Too soon after: the estimate rides the EMA with the live hp.
    t.clock = 0.6
    t.target_hp = 800
    near(gather().time_to_die, 4.0, 0.01, "D4: an early gather reuses the EMA")
    -- A steady rate keeps the EMA at 200: 800 / 200 = 4.0 (the early 0.6 s read
    -- never entered the baseline).
    t.clock = 1.0
    t.target_hp = 800
    near(gather().time_to_die, 4.0, 0.01, "D4: a steady rate keeps the estimate")
    -- A heal contributes zero velocity and decays the EMA to 150.
    t.clock = 1.5
    t.target_hp = 900
    near(gather().time_to_die, 900 / 150, 0.01, "D4: a heal decays the EMA, never flips it")
    -- A target switch resets the baseline.
    t.target_guid = "Target-2"
    t.target_hp = 500
    eq(gather().time_to_die, nil, "D4: a new target re-seeds")
    -- Dead health drops the baseline (a revive cannot diff against pre-death hp).
    t.clock = 2.0
    t.target_hp = 0
    eq(gather().time_to_die, nil, "D4: dead health -> nil")
    t.target_hp = 400
    eq(gather().time_to_die, nil, "D4: the baseline was dropped with the death")
    -- Unreadable health (a secret value degrades to nil in compat) drops it too.
    t.clock = 2.5
    t.target_hp = nil
    eq(gather().time_to_die, nil, "D4: unreadable health -> nil")
    t.target_hp = 350
    eq(gather().time_to_die, nil, "D4: the baseline was dropped with the unreadable read")
    -- Losing the target clears a stale estimate on the reused table.
    local reused = { time_to_die = 5 }
    t.target_guid = nil
    eq(TST.DRUID.guide.gather(TST, reused).time_to_die, nil,
        "D4: losing the target reads nil")
    eq(reused.time_to_die, nil, "D4: the stale estimate is overwritten on the reused table")

    -- End-to-end: the estimate drives the Wrath W8 execute Bite. The scans fill
    -- through the real hooks (the ticks also run the sampler - the throttle keeps
    -- that deterministic), then the engine reads the gathered input.
    t.target_guid = "Target-3"
    t.target_hp = 600
    t.player_auras = {
        { name = "Savage Roar", count = 1, duration = 34,
            expiration = t.clock + 60, source = "player", spell_id = 52610 },
    }
    t.target_auras = {
        { name = "Rip", count = 1, duration = 12, expiration = t.clock + 30,
            source = "player", spell_id = 1079 },
        { name = "Rake", count = 1, duration = 9, expiration = t.clock + 28,
            source = "player", spell_id = 1822 },
        { name = "Mangle", count = 1, duration = 12, expiration = t.clock + 30,
            source = "player", spell_id = 33987 },
    }
    TST.form_index = 3
    t.energy = 90
    t.combo = 5
    local function btick(advance)
        TST.mainhand.ends_at = t.clock + 3.0
        t.advance(advance or 0.1)
        TST.DRUID.on_bar_update(TST, "mainhand")
    end
    btick()          -- scan pass 1 (baseline seeded)
    t.target_hp = 500
    btick(0.3)       -- scan pass 2 + sample 2
    t.target_hp = 400
    btick(0.3)       -- sample 3
    local inputs = gather()
    check(type(inputs.time_to_die) == "number" and inputs.time_to_die <= 10,
        "D4: the gather carries the EMA estimate into the frozen input")
    local out = {}
    TST.DRUID.guide.evaluate(inputs, out)
    eq(out.action, "bite", "D4: the estimate drives the Wrath W8 execute Bite")
    eq(out.hold, false, "D4: the Bite carries no hold")
end

--=========================================================================================
-- 17) Follow-up groundwork: the TBC RipCP override, the fight-elapsed gates,
--     the W1 latency term and the Forever Berserk hold
--=========================================================================================
eq(dg.RIP_MIN_CP_TBC, 4, "the TBC Rip threshold default is 4 CP")
eq(dg.FIGHT_ELAPSED_ERA_SECONDS, 8, "the Era/SoD 5CP Rip gate is 8 s")
eq(dg.FIGHT_ELAPSED_FOREVER_SECONDS, 10, "the Forever 5CP Rip gate is 10 s")

-- T1 rip_min_cp: nil/NaN/junk degrade to 4; 2-5 override; T4 stays 5.
do
    eq(tevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 4,
        mangle_remaining = 6, energy = 100 }).action, "rip",
        "T1 default: 4 CP Rips with a nil override")
    eq(tevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 4,
        mangle_remaining = 6, energy = 100, rip_min_cp = NONE }).action, "rip",
        "T1: a cleared override falls back to 4")
    eq(tevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 4,
        mangle_remaining = 6, energy = 100, rip_min_cp = 0 / 0 }).action, "rip",
        "T1: a NaN override falls back to 4")
    eq(tevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 4,
        mangle_remaining = 6, energy = 100, rip_min_cp = 1 }).action, "rip",
        "T1: a below-range override clamps to 4 (4 CP still Rips)")
    eq(tevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 3,
        mangle_remaining = 6, energy = 100, rip_min_cp = 1 }).action, "shred",
        "T1 clamp: 3 CP cannot Rip on a clamped-4 line")
    eq(tevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 3,
        mangle_remaining = 6, energy = 100, rip_min_cp = 3 }).action, "rip",
        "T1 override: 3 CP Rips with rip_min_cp = 3")
    eq(tevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 2,
        mangle_remaining = 6, energy = 100, rip_min_cp = 3 }).action, "shred",
        "T1 override boundary: 2 CP cannot Rip with rip_min_cp = 3")
    eq(tevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 2,
        mangle_remaining = 6, energy = 100, rip_min_cp = 2 }).action, "rip",
        "T1 override: 2 CP Rips with rip_min_cp = 2")
    eq(tevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 4,
        mangle_remaining = 6, energy = 100, rip_min_cp = 5 }).action, "shred",
        "T1 override: 4 CP cannot Rip with rip_min_cp = 5")
    eq(tevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 5,
        mangle_remaining = 6, energy = 100, rip_min_cp = 5 }).action, "rip",
        "T1 override: 5 CP Rips with rip_min_cp = 5")
    eq(tevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 5,
        mangle_remaining = 6, energy = 100, rip_min_cp = 6 }).action, "rip",
        "T1: an above-range override clamps to 4 (5 CP still Rips)")
    eq(tevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 4,
        mangle_remaining = 6, energy = 100, rip_min_cp = "4" }).action, "rip",
        "T1: a non-number override falls back to 4")
    -- T4 is the 5CP long-fight finisher regardless of the override.
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 5,
        mangle_remaining = 6, energy = 100, rip_min_cp = 2 }).action, "rip",
        "T4: 5 CP Rips on a long fight even with rip_min_cp = 2")
end

-- Fight-elapsed gates (pure): unknown (nil/NaN) defaults to the long fight
-- and Rips; a proven-young fight pools to the builder below.
do
    -- Era E1: 8 s gate.
    eq(eevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 5,
        energy = 100 }).action, "rip",
        "E1: an unknown fight clock Rips (long-fight default)")
    eq(eevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 5,
        energy = 100, fight_elapsed = 0 / 0 }).action, "rip",
        "E1: a NaN fight clock Rips (unknown)")
    eq(eevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 5,
        energy = 100, fight_elapsed = 8 }).action, "rip",
        "E1 boundary: exactly 8 s is a proven-old fight -> Rip")
    eq(eevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 5,
        energy = 100, fight_elapsed = 7.999 }).action, "shred",
        "E1: 7.999 s withholds the Rip -> Shred (E2)")
    eq(eevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 5,
        energy = 100, fight_elapsed = 0 }).action, "shred",
        "E1: a fresh pull pools with Shred")
    -- SoD S5: same 8 s gate (pools to the builder chain, not necessarily
    -- Shred: with an absent Mangle the S6 fallback prompts).
    eq(sevaluate({ form_index = 3, energy = 90, combo_points = 5,
        sr_remaining = 30, rip_remaining = NONE, mangle_remaining = 6,
        rake_remaining = 8 }).action, "rip",
        "S5: an unknown fight clock Rips")
    eq(sevaluate({ form_index = 3, energy = 90, combo_points = 5,
        sr_remaining = 30, rip_remaining = NONE, mangle_remaining = 6,
        rake_remaining = 8, fight_elapsed = 7.999 }).action, "shred",
        "S5: 7.999 s withholds the Rip -> Shred (healthy chain pools)")
    eq(sevaluate({ form_index = 3, energy = 90, combo_points = 5,
        sr_remaining = 30, rip_remaining = NONE, mangle_remaining = NONE,
        rake_remaining = 8, fight_elapsed = 0 }).action, "mangle",
        "S5 young-fight fallthrough: an absent Mangle prompts (S6 order kept)")
    -- Forever F3: 10 s gate.
    eq(fevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 5,
        mangle_remaining = 6, energy = 100 }).action, "rip",
        "F3: an unknown fight clock Rips")
    eq(fevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 5,
        mangle_remaining = 6, energy = 100, fight_elapsed = 10 }).action, "rip",
        "F3 boundary: exactly 10 s Rips")
    eq(fevaluate({ form_index = 3, rip_remaining = NONE, combo_points = 5,
        mangle_remaining = 6, energy = 100, fight_elapsed = 9.999 }).action,
        "shred",
        "F3: 9.999 s withholds the Rip -> Shred")
end

-- W1 latency term: leeway is max(gcd_remaining, latency) + 1 s on Clearcasting.
do
    eq(wevaluate({ form_index = 3, energy = 24.999, tf_ready = true,
        combo_points = 0, gcd_remaining = 0, latency = 1.5 }).hold_text,
        "TIGER'S FURY",
        "W1 latency: 1.5 s latency moves the line to 25")
    eq(wevaluate({ form_index = 3, energy = 25, tf_ready = true,
        combo_points = 0, gcd_remaining = 0, latency = 1.5 }).action, "shred",
        "W1 latency boundary: exactly 25 energy with 1.5 s latency -> Shred")
    eq(wevaluate({ form_index = 3, energy = 24.999, tf_ready = true,
        combo_points = 0, gcd_remaining = 1.5, latency = 0.5 }).hold_text,
        "TIGER'S FURY",
        "W1 max: the GCD wins over a smaller latency (line 25)")
    eq(wevaluate({ form_index = 3, energy = 24.999, tf_ready = true,
        combo_points = 0, gcd_remaining = 0.5, latency = 1.5 }).hold_text,
        "TIGER'S FURY",
        "W1 max: the latency wins over a smaller GCD (line 25)")
    eq(wevaluate({ form_index = 3, energy = 39.999, tf_ready = true,
        combo_points = 0, gcd_remaining = 0, latency = 0 / 0 }).hold_text,
        "TIGER'S FURY",
        "W1 latency: a NaN latency contributes nothing (line 40)")
    eq(wevaluate({ form_index = 3, energy = 14.999, tf_ready = true,
        combo_points = 0, gcd_remaining = 1.5, latency = 1.5,
        clearcast = true }).hold_text, "TIGER'S FURY",
        "W1 latency + proc: max(1.5, 1.5) + 1 moves the line to 15")
end

-- Forever F1b: Berserk with Rip up and no proc (no energy gate, no TF phasing).
do
    local out = fevaluate({ form_index = 3, energy = 100,
        berserk_ready = true, rip_remaining = 8, mangle_remaining = 6,
        rake_remaining = 8 })
    eq(out.action, nil, "F1b: the Forever Berserk call is a hold, never an action")
    eq(out.hold, true, "F1b: the call rides the hold overlay")
    eq(out.hold_text, "BERSERK", "F1b: the call reads BERSERK")
    eq(fevaluate({ family = "FOREVER", form_index = 3, energy = 100,
        berserk_ready = true, rip_remaining = NONE, mangle_remaining = 6,
        rake_remaining = 8 }).action, "shred",
        "F1b: an untracked Rip withholds Berserk")
    eq(fevaluate({ family = "FOREVER", form_index = 3, energy = 100,
        berserk_ready = true, rip_remaining = 0, mangle_remaining = 6,
        rake_remaining = 8 }).action, "shred",
        "F1b: an expired Rip withholds Berserk")
    eq(fevaluate({ family = "FOREVER", form_index = 3, energy = 100,
        berserk_ready = true, rip_remaining = 8, mangle_remaining = 6,
        rake_remaining = 8, clearcast = true }).action, "shred",
        "F1b: a Clearcasting proc withholds Berserk (the free Shred first)")
    eq(fevaluate({ family = "FOREVER", form_index = 3, energy = 100,
        berserk_ready = NONE, rip_remaining = 8, mangle_remaining = 6,
        rake_remaining = 8 }).hold, false,
        "F1b: an unknown Berserk never calls")
    eq(fevaluate({ family = "FOREVER", form_index = 3, energy = 20,
        sp_ready = true, berserk_ready = true, rip_remaining = 8,
        mangle_remaining = 6, rake_remaining = 8 }).hold_text,
        "SHIFTING POWER",
        "F1 outranks F1b: room for the gain comes first")
    eq(fevaluate({ family = "FOREVER", form_index = 3, energy = 100,
        berserk_ready = true, rip_remaining = 8, mangle_remaining = 6,
        rake_remaining = 8, clearcast = NONE }).hold_text, "BERSERK",
        "F1b outranks the maintenance chain")
    eq(evaluate({ form_index = 3, energy = 100, berserk_ready = true,
        rip_remaining = 8 }).hold, false,
        "F1b is Forever-gated: a missing family never holds")
    eq(tevaluate({ form_index = 3, energy = 100, berserk_ready = true,
        rip_remaining = 8 }).hold, false,
        "F1b is Forever-gated: TBC never holds BERSERK")
end

--=========================================================================================
-- 18) The gather writes the follow-up inputs (unknown stays nil, stale clears)
--=========================================================================================
do
    -- The WRATH sandbox is in-combat from §3, so park it out of combat first:
    -- every new input is then the unknown shape, and stale values clear.
    local was_combat = ST.in_combat
    ST.in_combat = false
    local g = ST.DRUID.guide.gather(ST, {})
    eq(g.fight_elapsed, nil, "gather: out of combat the fight clock is nil")
    eq(g.tick_remaining, nil, "gather: no tracker anchor yet -> nil tick phase")
    eq(g.latency, nil, "gather: no latency probe -> nil")
    eq(g.ff_ready, nil, "gather: unknown Faerie Fire -> nil (never a guess)")
    eq(g.ff_cd_remaining, nil, "gather: unknown FF cooldown -> nil")
    eq(g.can_shred, nil, "gather: no position probe -> nil (assume Shred lands)")
    eq(g.rip_min_cp, nil, "gather: no RipCP option -> nil (engine defaults to 4)")
    local reused = { fight_elapsed = 5, tick_remaining = 1, latency = 0.5,
        ff_ready = true, ff_cd_remaining = 0, can_shred = false,
        rip_min_cp = 3 }
    local g2 = ST.DRUID.guide.gather(ST, reused)
    eq(g2.fight_elapsed, nil, "a stale fight clock is cleared out of combat")
    eq(g2.tick_remaining, nil, "a stale tick phase is cleared with no anchor")
    eq(g2.latency, nil, "a stale latency is cleared")
    eq(g2.ff_ready, nil, "a stale FF ready is cleared when unknown")
    eq(g2.ff_cd_remaining, nil, "a stale FF cooldown is cleared when unknown")
    eq(g2.can_shred, nil, "a stale position flag is cleared")
    eq(g2.rip_min_cp, nil, "a stale RipCP override is cleared")
    -- Back in combat the clock latches (0 on its first tick) and ticks on.
    ST.in_combat = true
    local g3 = ST.DRUID.guide.gather(ST, {})
    eq(g3.fight_elapsed, 0, "gather: the first in-combat tick latches the clock at 0")
    sandbox.advance(2.5)
    local g4 = ST.DRUID.guide.gather(ST, {})
    near(g4.fight_elapsed, 2.5, 0.2, "gather: the fight clock ticks with api.get_time()")
    ST.in_combat = was_combat
end

--=========================================================================================
-- 19) The gather proves Faerie Fire and the tick phase when the client answers
--=========================================================================================
do
    -- Faerie Fire: knowledge-gated like TF (the fixture answers 0,0 for
    -- everything unlisted, so knowledge alone decides).
    sandbox.known_names = {}
    sandbox.cooldowns_by_query = {}
    local unknown = ST.DRUID.guide.gather(ST, {})
    eq(unknown.ff_ready, nil, "FF: no spell knowledge stays nil (never a guess)")
    eq(unknown.ff_cd_remaining, nil, "FF: an unknown cooldown stays nil")
    sandbox.known_names = { ["Faerie Fire"] = true }
    local ready = ST.DRUID.guide.gather(ST, {})
    eq(ready.ff_ready, true, "FF: a known FF with no cooldown reads ready")
    eq(ready.ff_cd_remaining, 0, "FF: a ready FF reports a zero cooldown")
    sandbox.cooldowns_by_query = { ["Faerie Fire"] = { sandbox.clock, 6 } }
    local burning = ST.DRUID.guide.gather(ST, {})
    near(burning.ff_cd_remaining, 6, 0.2, "FF: a burning FF reports its cooldown")
    eq(burning.ff_ready, false, "FF: a burning FF reads explicitly false")
    sandbox.cooldowns_by_query = { ["Faerie Fire"] = { sandbox.clock, 1.2 } }
    local echo = ST.DRUID.guide.gather(ST, {})
    eq(echo.ff_cd_remaining, 0, "FF: the 1.2 s GCD echo is filtered, not a cooldown")
    eq(echo.ff_ready, true, "FF: the filtered echo reads ready")
    sandbox.known_names = {}
    sandbox.cooldowns_by_query = {}
    local cleared = ST.DRUID.guide.gather(ST, { ff_ready = true, ff_cd_remaining = 0 })
    eq(cleared.ff_ready, nil, "FF: a stale ready is cleared when unknown")
    eq(cleared.ff_cd_remaining, nil, "FF: a stale cooldown is cleared when unknown")

    -- Tick phase: the tracker's anchor when the sampler runs (cat form, tick
    -- bar on), else nil. The WRATH sandbox seats its anchor on the per-frame
    -- hook, then the gather reads the remaining phase off it.
    ST.form_index = 3
    sandbox.power_type = 3
    sandbox.power = 40
    sandbox.clock = 500
    ST.mainhand.ends_at = sandbox.clock + 3.0
    ST.DRUID.on_bar_update(ST, "mainhand")
    sandbox.clock = 501
    local ticked = ST.DRUID.guide.gather(ST, {})
    near(ticked.tick_remaining, 1.0, 0.2, "gather: the anchor feeds tick_remaining")
end

--=========================================================================================
-- 20) Faerie Fire Omen-fishing (Wrath W1b + waitForFf, Forever F6c) and the
--     Claw slot (sim wowsims/wotlk feral/rotation.go ffNow/waitForFf +
--     wowsims/forever feralcat/apl_sweep_test.go omenFish +
--     TestMonocatClawsWhenShredCannotLand)
--=========================================================================================
eq(dg.FF_ENERGY_WRATH, 87, "the Wrath FF fish line is 87 energy (the sim's ffThresh)")
eq(dg.FF_WAIT_SECONDS, 1, "the FF soon/wait horizon is 1 s")
eq(dg.FF_MAX_DELAY_SECONDS, 0.1, "the FF wait keeps the sim's 0.1 s MaxFfDelay")
eq(dg.FF_SP_LEFT_SECONDS, 1, "the Forever SP-left gate is 1 s (the sim's spellLeft(SP))")
eq(dg.FF_REGEN_ENERGY, 10, "the post-GCD regen is 10 energy")
eq(dg.FF_SHRED_COST, 42, "the FF Shred cost is frozen at 42 (UNCONFIRMED Wrath/Forever)")
eq(dg.FF_RIP_COST, 30, "the FF Rip cost is frozen at 30 (UNCONFIRMED Wrath/Forever)")
eq(dg.FF_RAKE_COST, 40, "the FF Rake cost is frozen at 40 (UNCONFIRMED Forever)")

-- W1b: the FF fish rides the hold overlay (no FF slot exists), ahead of
-- Berserk like the sim. Baseline: healthy SR/Rip/Rake/Mangle, no proc.
do
    local out = wevaluate({ form_index = 3, energy = 80, ff_ready = true,
        combo_points = 0, sr_remaining = 30, rip_remaining = 10,
        rake_remaining = 8, mangle_remaining = 6 })
    eq(out.action, nil, "W1b: the FF call is a hold, never an action")
    eq(out.hold, true, "W1b: the call rides the hold overlay")
    eq(out.hold_text, "FAERIE FIRE", "W1b: the call reads FAERIE FIRE")
    eq(wevaluate({ form_index = 3, energy = 86.999, ff_ready = true,
        combo_points = 0, sr_remaining = 30, rip_remaining = 10,
        rake_remaining = 8, mangle_remaining = 6 }).hold_text, "FAERIE FIRE",
        "W1b boundary: 86.999 energy still fishes")
    eq(wevaluate({ form_index = 3, energy = 87, ff_ready = true,
        combo_points = 0, sr_remaining = 30, rip_remaining = 10,
        rake_remaining = 8, mangle_remaining = 6 }).action, "shred",
        "W1b boundary: exactly 87 energy falls through to the builder")
    eq(wevaluate({ form_index = 3, energy = 20, tf_ready = true,
        ff_ready = true, combo_points = 0 }).hold_text, "TIGER'S FURY",
        "W1 outranks W1b: a ready TF is taken before the fish")
    eq(wevaluate({ form_index = 3, energy = 80, ff_ready = true,
        berserk_ready = true, tf_cd_remaining = 30, combo_points = 0,
        rip_remaining = 8 }).hold_text, "FAERIE FIRE",
        "W1b outranks W2: the fish comes before Berserk")
    eq(wevaluate({ form_index = 3, energy = 80, ff_ready = true,
        combo_points = 0, sr_remaining = 30, rip_remaining = 10,
        rake_remaining = 8, mangle_remaining = 6, clearcast = true }).action,
        "shred",
        "W1b: a Clearcasting proc withholds the fish (the free Shred first)")
    eq(wevaluate({ form_index = 3, energy = 80, ff_ready = false,
        combo_points = 0, sr_remaining = 30, rip_remaining = 10,
        rake_remaining = 8, mangle_remaining = 6 }).hold, false,
        "W1b: an FF on cooldown never calls (false is not true)")
    eq(wevaluate({ form_index = 3, energy = 80, combo_points = 0,
        sr_remaining = 30, rip_remaining = 10, rake_remaining = 8,
        mangle_remaining = 6 }).hold, false,
        "W1b: an unknown FF never calls (nil is not true)")
    eq(wevaluate({ form_index = 3, energy = NONE, ff_ready = true,
        combo_points = 0 }).hold, false,
        "W1b: unreadable energy cannot prove the line")
    eq(wevaluate({ form_index = 3, energy = 0 / 0, ff_ready = true,
        combo_points = 0 }).hold, false,
        "W1b: NaN energy cannot prove the line")
end

-- W1b Rip deferral (sim (!ripNow || energy < ripCost)) and the end-of-fight
-- spend math (an extra FF GCD must buy an extra Shred).
do
    eq(wevaluate({ form_index = 3, energy = 80, ff_ready = true,
        combo_points = 5, sr_remaining = 30, rip_remaining = NONE,
        mangle_remaining = 6 }).action, "rip",
        "W1b deferral: a 5CP Rip due with room outranks the fish")
    eq(wevaluate({ form_index = 3, energy = 20, ff_ready = true,
        combo_points = 5, sr_remaining = 30, rip_remaining = NONE,
        mangle_remaining = 6 }).hold_text, "FAERIE FIRE",
        "W1b deferral boundary: a due Rip the bar cannot cover still fishes")
    eq(wevaluate({ form_index = 3, energy = 80, ff_ready = true,
        combo_points = 0, sr_remaining = 30, rip_remaining = 10,
        rake_remaining = 8, mangle_remaining = 6,
        time_to_die = 2 }).action, "shred",
        "W1b spend math: 80 energy with 2 s left buys no extra Shred -> Shred")
    eq(wevaluate({ form_index = 3, energy = 80, ff_ready = true,
        combo_points = 0, sr_remaining = 30, rip_remaining = 10,
        rake_remaining = 8, mangle_remaining = 6,
        time_to_die = 30 }).hold_text, "FAERIE FIRE",
        "W1b spend math: a long fight still fishes")
    eq(wevaluate({ form_index = 3, energy = 80, ff_ready = true,
        combo_points = 0, sr_remaining = 30, rip_remaining = 10,
        rake_remaining = 8, mangle_remaining = 6,
        target_short_lived = true }).action, "shred",
        "W1b spend math: an explicit short-lived flag with no clock spends nothing")
    eq(wevaluate({ form_index = 3, energy = 80, ff_ready = true,
        combo_points = 0, sr_remaining = 30, rip_remaining = 10,
        rake_remaining = 8, mangle_remaining = 6,
        time_to_die = 0 / 0 }).hold_text, "FAERIE FIRE",
        "W1b spend math: a NaN clock defaults to the long fight and fishes")
    local provider = ST.DRUID.guide
    local out = {}
    provider.evaluate(win({ form_index = 3, energy = 80, ff_ready = true,
        combo_points = 0 }), out)
    eq(out.hold_text, "FAERIE FIRE", "the provider delegates the Wrath FF hold")
end

-- waitForFf (sim wotlk waitForFf): FF imminent pools Mangle/Rake/Shred.
do
    local function waiting(overrides)
        overrides.form_index = 3
        overrides.energy = overrides.energy or 80
        overrides.combo_points = 0
        overrides.sr_remaining = 30
        overrides.rip_remaining = overrides.rip_remaining or 10
        overrides.rake_remaining = 8
        overrides.ff_ready = false
        return wevaluate(overrides)
    end
    local out = waiting({ mangle_remaining = NONE, ff_cd_remaining = 0.5 })
    eq(out.action, nil, "waitForFf: FF inside the second pools the Mangle")
    eq(out.hold, false, "waitForFf: the pool carries no hold")
    eq(waiting({ mangle_remaining = NONE, ff_cd_remaining = 0.9 }).action,
        "mangle",
        "waitForFf boundary: 0.9 s out is not imminent (1 - 0.1)")
    eq(waiting({ mangle_remaining = NONE, ff_cd_remaining = 0.899,
        energy = 70 }).action,
        nil,
        "waitForFf boundary: 0.899 s out pools")
    eq(waiting({ mangle_remaining = NONE, ff_cd_remaining = 0.5,
        rip_remaining = 0.5 }).action, "mangle",
        "waitForFf: a Rip falling inside the second outranks the wait")
    eq(waiting({ mangle_remaining = NONE, ff_cd_remaining = 0.5,
        energy = 82 }).action, "mangle",
        "waitForFf: 82 energy cannot stay under 87 past the GCD")
    eq(waiting({ mangle_remaining = NONE, ff_cd_remaining = 0 / 0 }).action,
        "mangle",
        "waitForFf: a NaN FF cooldown never waits")
    eq(waiting({ mangle_remaining = NONE }).action, "mangle",
        "waitForFf: an unknown FF cooldown never waits")
    eq(waiting({ mangle_remaining = NONE, ff_cd_remaining = 0.5,
        clearcast = true }).action, "shred",
        "waitForFf: a proc never waits (the free Shred first)")
    eq(waiting({ mangle_remaining = 6, ff_cd_remaining = 0.5 }).action,
        nil,
        "waitForFf: the Shred default pools too while FF is imminent")
end

-- F6c: the Forever Omen-fishing call (the APL omenFish). Dormant in game
-- until the Omen-ICD probe lands (nil ICD never fishes); the offline pins
-- prove the spend math.
do
    local function fishing(overrides)
        overrides.family = "FOREVER"
        overrides.form_index = 3
        return evaluate(overrides)
    end
    local out = fishing({ energy = 20, ff_ready = true,
        omen_icd_ready = true, sp_cd_remaining = 5, combo_points = 0,
        rip_remaining = 8, rake_remaining = 8, mangle_remaining = 6 })
    eq(out.action, nil, "F6c: the FF call is a hold, never an action")
    eq(out.hold, true, "F6c: the call rides the hold overlay")
    eq(out.hold_text, "FAERIE FIRE", "F6c: the call reads FAERIE FIRE")
    eq(fishing({ energy = 20, ff_ready = true, combo_points = 0,
        rip_remaining = 8, rake_remaining = 8, mangle_remaining = 6,
        sp_cd_remaining = 5 }).action, "shred",
        "F6c: a nil Omen ICD never fishes (dormant in game)")
    eq(fishing({ energy = 20, ff_ready = true, omen_icd_ready = false,
        sp_cd_remaining = 5, combo_points = 0, rip_remaining = 8,
        rake_remaining = 8, mangle_remaining = 6 }).action, "shred",
        "F6c: a cooling Omen ICD never fishes")
    eq(fishing({ energy = 20, ff_ready = true, omen_icd_ready = true,
        sp_cd_remaining = 0, combo_points = 0, rip_remaining = 8,
        rake_remaining = 8, mangle_remaining = 6 }).action, "shred",
        "F6c: a ready Shifting Power outranks the fish (SP-left 0 < 1)")
    eq(fishing({ energy = 20, ff_ready = true, omen_icd_ready = true,
        combo_points = 0, rip_remaining = 8, rake_remaining = 8,
        mangle_remaining = 6 }).action, "shred",
        "F6c: an unknown Shifting Power never fishes (nil SP-left)")
    eq(fishing({ energy = 40, ff_ready = true, omen_icd_ready = true,
        sp_cd_remaining = 5, combo_points = 0, rip_remaining = 8,
        rake_remaining = 8, mangle_remaining = 6 }).action, "shred",
        "F6c: 40 energy leaves the Shred affordable after regen (50 >= 42)")
    eq(fishing({ energy = 31, ff_ready = true, omen_icd_ready = true,
        sp_cd_remaining = 5, combo_points = 0, rip_remaining = 8,
        rake_remaining = 8, mangle_remaining = 6 }).hold_text, "FAERIE FIRE",
        "F6c boundary: 31 energy regens under the Shred cost (41 < 42)")
    eq(fishing({ energy = 32, ff_ready = true, omen_icd_ready = true,
        sp_cd_remaining = 5, combo_points = 0, rip_remaining = 8,
        rake_remaining = 8, mangle_remaining = 6 }).action, "shred",
        "F6c boundary: 32 energy regens exactly the Shred cost (42 >= 42 blocks)")
    eq(fishing({ energy = 20, ff_ready = true, omen_icd_ready = true,
        sp_cd_remaining = 5, combo_points = 0, rip_remaining = 8,
        rake_remaining = 0.5, mangle_remaining = 6 }).hold_text, "FAERIE FIRE",
        "F6c rakeSoon: a due Rake the regen cannot cover still fishes")
    eq(fishing({ energy = 35, ff_ready = true, omen_icd_ready = true,
        sp_cd_remaining = 5, combo_points = 0, rip_remaining = 8,
        rake_remaining = 0.5, mangle_remaining = 6 }).action, "shred",
        "F6c rakeSoon: a due Rake the regen covers outranks the fish")
    eq(fishing({ energy = 19, ff_ready = true, omen_icd_ready = true,
        sp_cd_remaining = 5, combo_points = 5, rip_remaining = 0.5,
        rake_remaining = 8, mangle_remaining = 6 }).hold_text, "FAERIE FIRE",
        "F6c ripSoon: a due Rip the regen cannot cover still fishes")
    eq(fishing({ energy = 20, ff_ready = true, omen_icd_ready = true,
        sp_cd_remaining = 5, combo_points = 5, rip_remaining = 0.5,
        rake_remaining = 8, mangle_remaining = 6 }).action, "shred",
        "F6c ripSoon: a due Rip the regen covers outranks the fish")
    eq(fishing({ energy = 20, ff_ready = true, omen_icd_ready = true,
        sp_cd_remaining = 5, combo_points = 5, rip_remaining = 0.5,
        rake_remaining = 8, mangle_remaining = 6,
        fight_elapsed = 5 }).hold_text, "FAERIE FIRE",
        "F6c ripSoon: a young fight is not Rip-due, so the fish stands")
    eq(fishing({ energy = 20, ff_ready = true, omen_icd_ready = true,
        sp_cd_remaining = 5, combo_points = 5, rip_remaining = NONE,
        mangle_remaining = 6 }).action, "rip",
        "F3 outranks F6c: an expired Rip on a proven-old fight Rips first")
    eq(fishing({ energy = 20, ff_ready = true, omen_icd_ready = true,
        sp_cd_remaining = 5, combo_points = 0, rip_remaining = 8,
        rake_remaining = 8, mangle_remaining = 6,
        clearcast = true }).action, "shred",
        "F2 outranks F6c: a proc is a free Shred, never a fish")
    eq(fishing({ energy = 80, ff_ready = true, omen_icd_ready = true,
        sp_cd_remaining = 5, combo_points = 0, rip_remaining = 8,
        rake_remaining = 8, mangle_remaining = 6, clearcast = NONE }).action,
        "shred",
        "F6c: a capped bar keeps building (regen far over cost)")
    eq(fishing({ energy = 20, ff_ready = false, omen_icd_ready = true,
        sp_cd_remaining = 5, combo_points = 0 }).hold, false,
        "F6c: an FF on cooldown never calls (false is not true)")
    eq(fishing({ energy = 20, sp_ready = true, omen_icd_ready = true,
        sp_cd_remaining = 0, combo_points = 0, ff_ready = true }).hold_text,
        "SHIFTING POWER",
        "F1 outranks F6c: room for the gain comes first")
    eq(fishing({ energy = 100, ff_ready = true, omen_icd_ready = true,
        sp_cd_remaining = 5, combo_points = 5, rip_remaining = 8,
        rake_remaining = 8, mangle_remaining = 6,
        target_short_lived = true }).action, "bite",
        "F6a outranks F6c: the execute Bite comes before any fish")
    local provider = ST.DRUID.guide
    local fout = {}
    provider.evaluate(fin({ form_index = 3, energy = 20, ff_ready = true,
        omen_icd_ready = true, sp_cd_remaining = 5, combo_points = 0,
        rip_remaining = 8, rake_remaining = 8, mangle_remaining = 6 }), fout)
    eq(fout.hold_text, "FAERIE FIRE", "the provider delegates the Forever FF hold")
end

-- The Wolfshead Helm input (bench/filed_closure_sweep_2026-10-19.md §7 BS-2): the
-- gather publishes the tri-state (classes/druid.lua, pinned by tests/druid_state.lua
-- §38), but it is a RESERVED plug-in point - the Furor half of the powershift basis
-- is still unproven (DU-16), so the SHIFT branch stays removed and NO rule reads it.
do
    -- The engine's answer never moves with the input: same action, same hold, same
    -- hold text, with the Helm worn and with it proven absent.
    local cases = {
        { form_index = 1, rage = 50, maul_cost = 15 },
        { form_index = 3, energy = 90, combo_points = 2, rip_remaining = 10,
            rake_remaining = 8, mangle_remaining = 6 },
        { family = "TBC", form_index = 3, energy = 40, combo_points = 5,
            rip_remaining = 0, rake_remaining = NONE, mangle_remaining = 6 },
        { family = "ERA", form_index = 3, energy = 60, combo_points = 0,
            rip_remaining = NONE, rake_remaining = NONE, mangle_remaining = NONE },
        { family = "WRATH", form_index = 3, energy = 80, combo_points = 5,
            rip_remaining = 0, rake_remaining = 8, mangle_remaining = 6,
            time_to_die = 5 },
        { family = "FOREVER", form_index = 3, energy = 30, combo_points = 0,
            rip_remaining = 8, rake_remaining = 8, mangle_remaining = 6 },
    }
    for index, case in ipairs(cases) do
        local plain = evaluate(case)
        for _, value in ipairs({ true, false }) do
            local variant = {}
            for key, entry in pairs(case) do variant[key] = entry end
            variant.wolfshead_equipped = value
            local out = evaluate(variant)
            eq(out.action, plain.action,
                "no rule reads wolfshead_equipped (case " .. index .. ", action)")
            eq(out.hold, plain.hold,
                "no rule reads wolfshead_equipped (case " .. index .. ", hold)")
            eq(out.hold_text, plain.hold_text,
                "no rule reads wolfshead_equipped (case " .. index .. ", hold text)")
        end
    end
    -- And the source may only NAME the input in a comment: no code reads it.
    local path = ROOT .. "druid_guide.lua"
    local fh = io.open(path, "r")
    local src = fh and fh:read("*a")
    if fh then fh:close() end
    check(src ~= nil, "the reserved-input pin: druid_guide.lua is readable")
    if src then
        local hits = 0
        for line in src:gmatch("[^\r\n]+") do
            local code = line:gsub("%-%-.*$", "")
            if code:find("wolfshead_equipped", 1, true) then
                hits = hits + 1
            end
        end
        eq(hits, 0, "no rule reads wolfshead_equipped (code references: " .. hits .. ")")
    end
end

-- The Claw slot: declared so the contract names it, dark until its position
-- probe lands (no rule reads can_shred yet - filed follow-up).
do
    eq(slots[7].key, "claw", "the seventh slot key is claw")
    eq(slots[7].cooldown_key, nil, "claw carries no cooldown key (a builder)")
    eq(ui.slot_index.claw ~= nil, true, "every declared slot key is frame-addressable (claw)")
    eq(ui.icons[ui.slot_index.claw].glow_key, nil, "the Claw slot carries no glow")
    -- No engine rule reads can_shred: whatever the position probe claims,
    -- the builder chain is unchanged (the sim's CannotShredTarget has no
    -- client counterpart - filed follow-up).
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 2,
        sr_remaining = 30, rip_remaining = 10, rake_remaining = 8,
        mangle_remaining = 6, can_shred = false }).action, "shred",
        "no Claw rule: a claimed front still builds (nil-safe dormancy)")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 2,
        sr_remaining = 30, rip_remaining = 10, rake_remaining = 8,
        mangle_remaining = 6, can_shred = true }).action, "shred",
        "no Claw rule: a claimed behind still builds")
    eq(fevaluate({ form_index = 3, energy = 100, combo_points = 2,
        rip_remaining = 8, rake_remaining = 8, mangle_remaining = 6,
        can_shred = false }).action, "shred",
        "no Claw rule on Forever either: the default still builds")
    -- No action the engine can return is Claw: the slot stays dark.
    local seen_claw = false
    for _, family in ipairs({ "TBC", "ERA", "WRATH", "FOREVER", "CATA" }) do
        local out = evaluate({ family = family, form_index = 3,
            rip_remaining = NONE, rake_remaining = NONE,
            mangle_remaining = NONE, combo_points = 0, energy = 90,
            can_shred = false })
        if out.action == "claw" then
            seen_claw = true
        end
    end
    check(not seen_claw, "no Claw rule: no family ever prompts Claw")
end

-- Name-vs-id classification (bench/lessons.md): the pure engine has NO
-- spell-id uses in scope (no GetSpellInfo / GetSpellCooldown / is_spell_known /
-- spell_id reads) — all TBC-name vs Era-id resolution lives in the gather
-- (classes/druid.lua, pinned by tests/druid_state.lua §31). Pinned here
-- statically so a future id probe cannot slip into the pure module.
do
    local path = ROOT .. "druid_guide.lua"
    local fh = io.open(path, "r")
    local src = fh and fh:read("*a")
    if fh then fh:close() end
    check(src ~= nil, "name-vs-id: druid_guide.lua is readable")
    if src then
        check(not src:find("api.GetSpellInfo(", 1, true), "name-vs-id: pure engine never calls GetSpellInfo")
        check(not src:find("api.GetSpellCooldown(", 1, true), "name-vs-id: pure engine never calls GetSpellCooldown")
        check(not src:find("api.is_spell_known(", 1, true), "name-vs-id: pure engine never probes known spells")
        check(not src:find("api.GetSpellPowerCost(", 1, true), "name-vs-id: pure engine never reads power costs")
    end
end

-- The APL utility layer's arms (the rotation table's utility spine in
-- classes/druid.lua): the Faerie Fire upkeep, the Leader of the Pack, the
-- Innervate and the Elune's Light. Every one of them is a HOLD (no guide slot
-- exists), and every one of them hides on an unreadable input.
do
    -- The Faerie Fire upkeep (the Era APL's i=0/i=8 and the TBC APL's i=2).
    local era_ff = {
        family = "ERA", form_index = 3, combo_points = 0, energy = 60,
        rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        has_target = true, feral_ff_ready = true, ff_debuff_remaining = false,
    }
    local out = evaluate(era_ff)
    eq(out.hold, true, "utility: the Era Faerie Fire upkeep holds")
    eq(out.hold_text, "FAERIE FIRE", "utility: the Era Faerie Fire hold text")
    eq(out.action, nil, "utility: a hold never carries an action")
    -- The debuff still fresh: no prompt (the Era row refreshes at 14 s or less).
    out = evaluate({ family = "ERA", form_index = 3, combo_points = 0, energy = 60,
        rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        has_target = true, feral_ff_ready = true, ff_debuff_remaining = 20 })
    eq(out.hold_text, nil, "utility: a fresh Faerie Fire debuff holds no call")
    -- The debuff about to drop: the Era refresh row fires (14 s or less).
    out = evaluate({ family = "ERA", form_index = 3, combo_points = 0, energy = 60,
        rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        has_target = true, feral_ff_ready = true, ff_debuff_remaining = 10 })
    eq(out.hold_text, "FAERIE FIRE", "utility: the Era Faerie Fire refresh row fires")
    -- Unknown hides: no target, an unreadable cooldown, an unanswered debuff.
    out = evaluate({ family = "ERA", form_index = 3, combo_points = 0, energy = 60,
        rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        has_target = false, feral_ff_ready = true, ff_debuff_remaining = false })
    eq(out.hold_text, nil, "utility: no target, no Faerie Fire call")
    out = evaluate({ family = "ERA", form_index = 3, combo_points = 0, energy = 60,
        rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        has_target = true, feral_ff_ready = NONE, ff_debuff_remaining = false })
    eq(out.hold_text, nil, "utility: an unreadable cooldown, no Faerie Fire call")
    out = evaluate({ family = "ERA", form_index = 3, combo_points = 0, energy = 60,
        rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        has_target = true, feral_ff_ready = true, ff_debuff_remaining = NONE })
    eq(out.hold_text, nil, "utility: an unanswered debuff never prompts")
    -- The TBC row: cast it only when the debuff is inactive.
    out = evaluate({ family = "TBC", form_index = 3, combo_points = 0, energy = 60,
        rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        has_target = true, feral_ff_ready = true, ff_debuff_remaining = false })
    eq(out.hold_text, "FAERIE FIRE", "utility: the TBC Faerie Fire upkeep holds")
    out = evaluate({ family = "TBC", form_index = 3, combo_points = 0, energy = 60,
        rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        has_target = true, feral_ff_ready = true, ff_debuff_remaining = 5 })
    eq(out.hold_text, nil, "utility: the TBC row waits for the debuff to drop")
    -- The SoD shares the Era token but its APL carries no Faerie Fire row.
    out = evaluate({ family = "ERA", sod_runes = true, form_index = 3, combo_points = 0,
        energy = 60, rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        has_target = true, feral_ff_ready = true, ff_debuff_remaining = false })
    eq(out.hold_text, nil, "utility: the SoD carries no Faerie Fire row")
    -- The bear form never runs the cat upkeep.
    out = evaluate({ family = "ERA", form_index = 1, rage = 50, maul_cost = 15,
        has_target = true, feral_ff_ready = true, ff_debuff_remaining = false })
    eq(out.hold_text, nil, "utility: the bear form never runs the cat upkeep")

    -- The Leader of the Pack (the Era APL's i=1 row).
    local lop = {
        family = "ERA", form_index = 3, combo_points = 0, energy = 60,
        rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        lop_known = true, lop_active = false, fight_elapsed = 10,
    }
    out = evaluate(lop)
    eq(out.hold_text, "LEADER OF THE PACK", "utility: the Leader of the Pack holds")
    eq(out.action, nil, "utility: the Leader of the Pack never carries an action")
    out = evaluate({ family = "ERA", form_index = 3, combo_points = 0, energy = 60,
        rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        lop_known = true, lop_active = true, fight_elapsed = 10 })
    eq(out.hold_text, nil, "utility: the Leader of the Pack is up - no call")
    out = evaluate({ family = "ERA", form_index = 3, combo_points = 0, energy = 60,
        rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        lop_known = false, lop_active = false, fight_elapsed = 10 })
    eq(out.hold_text, nil, "utility: an unknown Leader of the Pack - no call")
    out = evaluate({ family = "ERA", form_index = 3, combo_points = 0, energy = 60,
        rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        lop_known = true, lop_active = false, fight_elapsed = 200 })
    eq(out.hold_text, nil, "utility: past the Leader of the Pack's own window - no call")
    out = evaluate({ family = "ERA", sod_runes = true, form_index = 3, combo_points = 0,
        energy = 60, rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        lop_known = true, lop_active = false, fight_elapsed = 10 })
    eq(out.hold_text, nil, "utility: the SoD carries no Leader of the Pack row")

    -- The Innervate (the mana row): the cooldown is ready and the mana is short.
    local inn = {
        family = "ERA", form_index = 0, innervate_ready = true, mana_percent = 0.3,
    }
    out = evaluate(inn)
    eq(out.hold_text, "INNERVATE", "utility: the Innervate holds")
    out = evaluate({ family = "ERA", form_index = 0, innervate_ready = true,
        mana_percent = 0.5 })
    eq(out.hold_text, nil, "utility: a healthy mana pool - no Innervate")
    out = evaluate({ family = "ERA", form_index = 0, innervate_ready = NONE,
        mana_percent = 0.3 })
    eq(out.hold_text, nil, "utility: an unknown Innervate - no call")
    out = evaluate({ family = "ERA", form_index = 0, innervate_ready = true,
        mana_percent = NONE })
    eq(out.hold_text, nil, "utility: an unreadable mana pool - no Innervate")
    out = evaluate({ family = "ERA", form_index = 1, rage = 50, maul_cost = 15,
        innervate_ready = true, mana_percent = 0.3 })
    eq(out.hold_text, nil, "utility: the bear form never calls the Innervate")
    -- The Era row is a caster row (outside the cat form); the SoD row is a cat row.
    out = evaluate({ family = "ERA", form_index = 3, combo_points = 0, energy = 60,
        rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        innervate_ready = true, mana_percent = 0.3 })
    eq(out.hold_text, nil, "utility: the Era Innervate row is a caster row")
    out = evaluate({ family = "ERA", sod_runes = true, form_index = 3, combo_points = 0,
        energy = 60, rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        innervate_ready = true, mana_percent = 0.3 })
    eq(out.hold_text, "INNERVATE", "utility: the SoD Innervate row is a cat row")
    -- The TBC APL carries no Innervate row.
    out = evaluate({ family = "TBC", form_index = 0, innervate_ready = true,
        mana_percent = 0.3 })
    eq(out.hold_text, nil, "utility: the TBC carries no Innervate row")

    -- The Elune's Light (the Forever APL's i=3).
    out = evaluate({ family = "FOREVER", form_index = 3, combo_points = 0, energy = 60,
        rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        elunes_light_ready = true })
    eq(out.hold_text, "ELUNE'S LIGHT", "utility: the Elune's Light holds")
    out = evaluate({ family = "FOREVER", form_index = 3, combo_points = 0, energy = 60,
        rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        elunes_light_ready = NONE })
    eq(out.hold_text, nil, "utility: an unknown Elune's Light - no call")
    out = evaluate({ family = "ERA", form_index = 3, combo_points = 0, energy = 60,
        rip_remaining = 8, rake_remaining = 7, mangle_remaining = 6,
        elunes_light_ready = true })
    eq(out.hold_text, nil, "utility: the Elune's Light is the Forever row")
end

-- The Cat Form upkeep (the rotation table's cat_form row - the APL's form row:
-- the Era APL's i=14, the SoD APL's i=0, the TBC APL's Powershifting group and
-- the Forever APL's i=1). The arm wants THREE proofs: a proven Feral-tree spec
-- (the class's own probe), a proven-absent Cat Form aura (the APL's own
-- condition) and a form the cat rotation uses but the other chains do not own.
do
    local cform = {
        family = "ERA", form_index = 0, feral_spec = true, cat_form_active = false,
    }
    local out = evaluate(cform)
    eq(out.hold, true, "U-CF: the Cat Form upkeep holds")
    eq(out.hold_text, "CAT FORM", "U-CF: the hold text reads CAT FORM")
    eq(out.action, nil, "U-CF: a hold never carries an action")
    -- Unknown hides: an unproven spec, an unanswered aura walk.
    out = evaluate({ family = "ERA", form_index = 0, feral_spec = false,
        cat_form_active = false })
    eq(out.hold_text, nil, "U-CF: a proven non-feral player is never asked to shift")
    out = evaluate({ family = "ERA", form_index = 0, feral_spec = true,
        cat_form_active = NONE })
    eq(out.hold_text, nil, "U-CF: an unanswered Cat Form aura never prompts")
    out = evaluate({ family = "ERA", form_index = 0, feral_spec = NONE,
        cat_form_active = false })
    eq(out.hold_text, nil, "U-CF: an unproven spec never prompts")
    -- The Cat Form aura is up: there is nothing to call.
    out = evaluate({ family = "ERA", form_index = 0, feral_spec = true,
        cat_form_active = true })
    eq(out.hold_text, nil, "U-CF: the Cat Form aura is up - no call")
    -- The forms: the bear and the cat chain own theirs, the tree/moonkin and the
    -- flight forms are not the cat rotation's, and an unreadable form hides.
    out = evaluate({ family = "ERA", form_index = 1, feral_spec = true,
        cat_form_active = false, rage = 50, maul_cost = 15 })
    eq(out.hold_text, nil, "U-CF: the bear form never runs the form upkeep")
    out = evaluate({ family = "ERA", form_index = 3, feral_spec = true,
        cat_form_active = false, combo_points = 0, energy = 60, rip_remaining = 8,
        rake_remaining = 8, mangle_remaining = 6 })
    eq(out.hold_text, nil, "U-CF: the cat form is already there")
    out = evaluate({ family = "ERA", form_index = 4, feral_spec = true,
        cat_form_active = false })
    eq(out.hold_text, "CAT FORM", "U-CF: the travel form asks for the cat form")
    out = evaluate({ family = "ERA", form_index = 5, feral_spec = true,
        cat_form_active = false })
    eq(out.hold_text, nil, "U-CF: a caster form is not the cat rotation's")
    out = evaluate({ family = "ERA", form_index = 6, feral_spec = true,
        cat_form_active = false })
    eq(out.hold_text, nil, "U-CF: the flight form is not the cat rotation's")
    out = evaluate({ family = "ERA", form_index = NONE, feral_spec = true,
        cat_form_active = false })
    eq(out.hold_text, nil, "U-CF: an unreadable form never prompts")
    -- The families: the row belongs to Era (and the SoD), TBC and Forever - never
    -- to WotLK, whose APL carries no Cat Form row.
    out = evaluate({ family = "TBC", form_index = 0, feral_spec = true,
        cat_form_active = false })
    eq(out.hold_text, "CAT FORM", "U-CF: the TBC row fires")
    out = evaluate({ family = "FOREVER", form_index = 0, feral_spec = true,
        cat_form_active = false })
    eq(out.hold_text, "CAT FORM", "U-CF: the Forever row fires")
    out = evaluate({ family = "WRATH", form_index = 0, feral_spec = true,
        cat_form_active = false })
    eq(out.hold_text, nil, "U-CF: the WotLK APL carries no Cat Form row")
    -- The bear form belongs to the bear chain on EVERY family - including the
    -- two whose APL puts the Cat Form row above the Innervate (the arm is
    -- checked before the form dispatch there, so it must exclude the bear form
    -- by itself).
    out = evaluate({ family = "FOREVER", form_index = 1, feral_spec = true,
        cat_form_active = false, rage = 50, maul_cost = 15 })
    eq(out.hold_text, nil, "U-CF: the bear form never runs the form upkeep (Forever)")
    eq(out.action, "maul", "U-CF: the Forever bear chain still owns the bear form")
    out = evaluate({ family = "ERA", sod_runes = true, form_index = 1,
        feral_spec = true, cat_form_active = false, rage = 50, maul_cost = 15 })
    eq(out.hold_text, nil, "U-CF: the bear form never runs the form upkeep (SoD)")
    eq(out.action, "maul", "U-CF: the SoD bear chain still owns the bear form")
    -- The APL order against the Innervate row: the Cat Form row sits above the
    -- Innervate on SoD (i=0 vs i=4) and below it on Era (i=14 vs i=13).
    out = evaluate({ family = "ERA", sod_runes = true, form_index = 0,
        feral_spec = true, cat_form_active = false, innervate_ready = true,
        mana_percent = 0.3 })
    eq(out.hold_text, "CAT FORM", "U-CF: on SoD the Cat Form row outranks the Innervate")
    out = evaluate({ family = "ERA", form_index = 0, feral_spec = true,
        cat_form_active = false, innervate_ready = true, mana_percent = 0.3 })
    eq(out.hold_text, "INNERVATE", "U-CF: on Era the Innervate row outranks the Cat Form")
end

-- The form upkeep's class-side reads: the Feral-tree spec probe (the family's
-- Feral-tree talent) and the Cat Form aura (the player's own aura walk).
do
    local function fresh_gather(opts)
        local fresh = build(opts)
        local FST = fresh.ST
        FST.interfaces_are_initialised = true
        FST.DRUID.post_init(FST)
        return FST.DRUID.guide.gather(FST, {})
    end
    -- The Era client's probe is the Faerie Fire (Feral) (17392), a Feral-tree
    -- talent; the TBC client's is the Faerie Fire (Feral) r5 (27011); the
    -- Forever client's is the Leader of the Pack (17007).
    local era_feral = fresh_gather({ project = 2, known_ids = { [17392] = true } })
    eq(era_feral.feral_spec, true,
        "U-CF gather: a known Faerie Fire (Feral) proves the Feral tree on Era")
    local era_caster = fresh_gather({ project = 2 })
    eq(era_caster.feral_spec, false,
        "U-CF gather: an unknown Faerie Fire (Feral) never proves the Feral tree")
    local tbc_feral = fresh_gather({ project = 5, known_ids = { [27011] = true } })
    eq(tbc_feral.feral_spec, true,
        "U-CF gather: a known Faerie Fire (Feral) proves the Feral tree on TBC")
    local forever_feral = fresh_gather({ project = 18, known_ids = { [17007] = true } })
    eq(forever_feral.feral_spec, true,
        "U-CF gather: a known Leader of the Pack proves the Feral tree on Forever")
    local wrath = fresh_gather({ project = 11, known_ids = { [17007] = true } })
    eq(wrath.feral_spec, nil,
        "U-CF gather: the WotLK client has no Cat Form row, so no spec probe")
end

--=========================================================================================
-- 21) The hold vocabulary is closed, and RIDE is the one press-nothing hold
--=========================================================================================
-- The guide's holds are not one thing: NINE of its ten hold texts name the spell to
-- PRESS (the guide has no slot for the spell, so the hold overlay carries the call),
-- while "RIDE" means PRESS NOTHING (the bear chain's queued Maul - the guide rides
-- the queue the player already placed). The deep-audit's H1 was the class turning
-- that one press-nothing hold into a synthetic action.
--
-- The vocabulary is pinned HERE (the guide owns the texts): every hold text the guide
-- can write is covered by exactly one of the class's two tables, and "RIDE" is the
-- only press-nothing one. A new hold text in the guide fails this pin, so it can
-- never be graded by a guessed slug.
do
    local function read(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text
    end

    -- The guide's own hold texts, read out of the source (every `hold_text = "..."`).
    local source = read("druid_guide.lua")
    local texts = {}
    for text in source:gmatch('hold_text%s*=%s*"([^"]*)"') do
        texts[text] = true
    end
    local known = {
        ["CAT FORM"] = true,
        ["INNERVATE"] = true,
        ["RIDE"] = true,
        ["FAERIE FIRE"] = true,
        ["TIGER'S FURY"] = true,
        ["BERSERK"] = true,
        ["SAVAGE ROAR"] = true,
        ["LEADER OF THE PACK"] = true,
        ["SHIFTING POWER"] = true,
        ["ELUNE'S LIGHT"] = true,
    }
    local count = 0
    for text in pairs(texts) do
        count = count + 1
        check(known[text] == true,
            "hold vocabulary: the guide's hold text is a known one (" .. text .. ")")
    end
    eq(count, 10, "hold vocabulary: the guide writes ten hold texts")

    -- The class's two tables: the spell-naming holds and the press-nothing holds.
    local sb = build()
    local keys = sb.ST.DRUID.PRACTICE_HOLD_KEYS
    local nothing = sb.ST.DRUID.PRACTICE_HOLD_PRESSES_NOTHING
    check(type(keys) == "table" and type(nothing) == "table",
        "hold vocabulary: the class publishes both hold tables")
    for text in pairs(texts) do
        local spell_named = keys[text] ~= nil
        local press_nothing = nothing[text] == true
        check(spell_named ~= press_nothing,
            "hold vocabulary: " .. text .. " is covered by exactly one of the two tables")
    end
    -- RIDE is the press-nothing hold, and never a spell to press.
    eq(nothing["RIDE"], true, "hold vocabulary: RIDE is the press-nothing hold")
    eq(keys["RIDE"], nil, "hold vocabulary: RIDE is never a spell-naming hold")
    local nothing_count = 0
    for _ in pairs(nothing) do nothing_count = nothing_count + 1 end
    eq(nothing_count, 1, "hold vocabulary: the guide has exactly one press-nothing hold")
    -- No hold text maps to the "ride" key: that key would be a button the player can
    -- only press dishonestly (points for idling) and would bank a false mis-pick in
    -- the priority drill for every real pick.
    for text, key in pairs(keys) do
        check(key ~= "ride",
            "hold vocabulary: no hold text maps to the 'ride' key (" .. text .. ")")
    end
end

if failures == 0 then
    print("PASS  druid_guide_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  druid_guide_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end

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
--     short-lived-only Bite, the 40/42 energy gates, the wait terminal and
--     the TBC constants (the old >20-short SHIFT hold was removed with its
--     constant: no honest shift probe exists),
--   * Tiger's Fury is never an ACTION anywhere (no slot exists); the families
--     without a mid-rotation TF rule never hold for it either (WRATH and
--     ERA-with-runes hold TIGER'S FURY by design),
--   * the ERA cat branch (inputs.family == "ERA"): never Mangle/Rip/Rake, the
--     5CP Ferocious Bite (4CP still builds), the ungated Shred, the bear wait
--     terminal, and the exact-match gate (lowercase stays legacy),
--   * every non-TBC, non-Era, non-Wrath family (and a missing family) runs the
--     legacy matrix byte-for-byte: the refresh windows, the untracked Rake, the
--     ungated Mangle/Shred and the default Bite,
--   * the WRATH cat branch (inputs.family == "WRATH"): the <30-energy TF hold,
--     the <=85-energy Berserk hold off a 15 s TF cooldown, the >=1 CP Savage
--     Roar upkeep hold, Clearcasting ahead of the finishers, the 5 CP
--     expiry-only Rip, Mangle above Rake, the Rip+Roar-guarded Bite, the Shred
--     default - and never a SHIFT hold (no powershifting) nor a TF/Berserk/Roar
--     action (no slot exists; the hold overlay carries them),
--   * the SOD cat branch (inputs.family == "ERA" with sod_runes): the <=40
--     TF hold, Berserk-after-TF, the Roar refresh, Omen Shred, the 5 CP Rip
--     with the under-TF snapshot preference, the Mangle/Rake order, the
--     capped-CP Bite, the ungated Shred - and the strict
--     sod_runes == true gate plus the SoD bear Mangle (never the Era wait),
--   * the gather writes the family plus the unknown-shaped finisher inputs
--     (time_to_die, target_short_lived) and the reserved can_powershift nil
--     (no rule reads it) with stale overwrites, plus the Wrath/SoD buff/cooldown inputs (sr_remaining,
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

-- Rule 1: the queued Maul ride.
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
    [5217] = { name = "Tiger's Fury", icon = "icon_tf" },
    [50334] = { name = "Berserk", icon = "icon_berserk" },
    [52610] = { name = "Savage Roar", icon = "icon_sr" },
    [16870] = { name = "Clearcasting", icon = "icon_omen" },
}

local MODULES = { "compat.lua", "utils.lua", "nextaction_ui.lua", "druid_guide.lua",
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
    env.GetSpellInfo = function(spell)
        sb.get_spell_info_calls = sb.get_spell_info_calls + 1
        if sb.hide_spells then
            return nil
        end
        if type(spell) == "string" then
            -- Knowledge-level: a name answers only for a known spell (the SoD
            -- rune probe and the TF/Berserk known gates).
            if sb.known_names[spell] then
                return spell, nil, "icon_" .. spell, 0, 0, 0, 0
            end
            return nil
        end
        local info = SPELL_INFOS[spell]
        if info then
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
    -- through _G, like the warrior fixture): only known_ids answers true.
    env.IsSpellKnown = function(id)
        if sb.known_ids[id] then
            return true
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
eq(#slots, 6, "six slots are declared")
check(#slots <= 6, "the slot set stays at the contract's six or fewer")
local expected_keys = { "maul", "mangle", "rip", "rake", "bite", "shred" }
local expected_icons = { "icon_maul", "icon_mangle_bear", "icon_rip", "icon_rake",
    "icon_bite", "icon_shred" }
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
eq(ST.DRUID.guide.labels.next_action, "Next action:", "labels.next_action is the default")
eq(ST.DRUID.guide.labels.hold, "HOLD", "labels.hold is the default")
eq(ST.DRUID.guide.labels.ride, "RIDE", "labels.ride is the default")
eq(ST.DRUID.guide.rotation_key, nil, "no rotation text source is declared")
eq(ST.DRUID.guide.rotation_names, nil, "no rotation name map is declared")

-- The frame: one icon per slot, in order.
eq(#ui.icons, 6, "the frame holds one icon per slot")
eq(sandbox.frames, 17, "frame count: group + 6 icons/borders + 3 cooldowns + hold")
for i = 1, #slots do
    eq(ui.icons[i].slot, slots[i], "icon " .. i .. " follows the slot declaration order")
    eq(ui.icons[i].icon.texture.texture, expected_icons[i],
        "icon " .. i .. " shows " .. expected_icons[i])
end
eq(ui.frame.label.text, "Next action:", "the label carries the default caption")
eq(ui.icons[2].remaining_key, "mangle_remaining", "the swipe field names derive from the key")
eq(ui.icons[4].expires_key, "rake_expires", "the expiry field name derives from the key")
eq(ui.icons[1].remaining_key, nil, "the unwiped slots carry no swipe fields")
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
eq(sandbox.last_cost_id, 48480, "gather: the cost is read through the current rank")
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
        nextaction_enabled = "false",
        nextaction_locked = "true",
        nextaction_visibility_key = "\"in_combat\"",
        nextaction_icon_size = "45",
        nextaction_x = "0",
        nextaction_y = "-180",
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
eq(dg.SHORT_LIVED_TTD_SECONDS, 12, "short-lived means dying inside one full Rip")

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
        mangle_remaining = 6, energy = 100, time_to_die = 12 }).action, "bite",
        "T3 boundary: exactly 12 s to die is still short-lived")
    eq(tevaluate({ form_index = 3, rip_remaining = 8, combo_points = 5,
        mangle_remaining = 6, energy = 100, time_to_die = 12.0001 }).action, "rip",
        "T4: just over 12 s to die is a long fight -> Rip")
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
    local families = { "CATA", "MISTS", "FOREVER", "UNKNOWN" }
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

-- E1: the 5CP Ferocious Bite, ungated by energy or debuffs.
do
    eq(eevaluate({ family = "ERA", form_index = 3, rip_remaining = NONE,
        rake_remaining = NONE, mangle_remaining = NONE, combo_points = 5,
        energy = 0 }).action, "bite",
        "E1: 5 CP Bites with no debuffs tracked and no energy")
    eq(eevaluate({ family = "ERA", form_index = 3, rip_remaining = 8,
        rake_remaining = 8, mangle_remaining = 6, combo_points = 5,
        energy = 100 }).action, "bite",
        "E1: 5 CP Bites past healthy debuffs (no refresh model on Era)")
    eq(eevaluate({ family = "ERA", form_index = 3, rip_remaining = 8,
        rake_remaining = 8, mangle_remaining = 6, combo_points = 5.5 }).action, "bite",
        "E1: above 5 CP still Bites")
    eq(eevaluate({ family = "ERA", form_index = 3, rip_remaining = NONE,
        rake_remaining = NONE, mangle_remaining = NONE, combo_points = 4 }).action, "shred",
        "E1 boundary: 4 CP cannot Bite -> Shred")
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
    -- E1 outranks everything: a capped bar with a claimed shift still finishes first.
    eq(eevaluate({ family = "ERA", form_index = 3, combo_points = 5, energy = 0,
        can_powershift = true }).action, "bite",
        "E1 outranks removed E2: 5 CP Bites even with a claimed shift")
end

-- E2 and the Era absences: Shred is the default, and no input prompts
-- Mangle, Rip or Rake on Era (the sweep below pins the whole input space).
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
    local swept = 0
    for _, rip in ipairs(rips) do
        for _, rake in ipairs(rakes) do
            for _, mangle in ipairs(mangles) do
                for _, cp in ipairs(cps) do
                    for _, energy in ipairs(energies) do
                        for _, shift in ipairs(shifts) do
                            swept = swept + 1
                            local out = eevaluate({
                                form_index = 3, rip_remaining = rip,
                                rake_remaining = rake,
                                mangle_remaining = mangle,
                                combo_points = cp, energy = energy,
                                can_powershift = shift,
                            })
                            check(out.action ~= "mangle",
                                "Era sweep: Mangle is never prompted")
                            check(out.action ~= "rake",
                                "Era sweep: Rake is never prompted")
                            check(out.action ~= "rip",
                                "Era sweep: Rip is never prompted")
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
    eq(swept, 5 * 4 * 3 * 5 * 7 * 2, "the Era sweep covered every combination")
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
    eq(out.action, "bite", "the provider delegates the Era Bite")
    provider.evaluate(ein({ form_index = 1, rage = 5, maul_cost = 15 }), out)
    eq(out.action, nil, "the provider delegates the Era bear wait")
end

-- The Era display through a real Era sandbox: the Mangle/Rip/Rake icons stay dark.
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
    eq(#eslots, 6, "the Era slot set stays at six (the Mangle slot stays dark)")
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
    era.combo = 5
    etick()
    eq(etarget("bite"), 1, "Era display: 5 CP lights Ferocious Bite")
    eq(etarget("shred"), 0, "Era display: the finisher replaces the builder")
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
    -- on every other non-Era family, while Era waits wherever the rest Mangle
    -- (RIDE and Maul agree everywhere).
    local rages = { NONE, 0, 5, 14.999, 15, 50, 0 / 0 }
    local costs = { NONE, 0, 15, 30 }
    local queues = { false, true }
    local shorts = { NONE, false, true }
    local families = { "TBC", "WRATH", "CATA", "MISTS", "FOREVER" }
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
                    for _, family in ipairs(families) do
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
                    else
                        eq(era.action, results["WRATH"].action,
                            "Era bear parity: shares the Maul/RIDE outcome with Wrath")
                        eq(era.hold, results["WRATH"].hold,
                            "Era bear parity: shares the hold outcome with Wrath")
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
    eq(g.time_to_die, nil, "gather: time-to-die has no client source yet -> nil")
    eq(g.target_short_lived, nil, "gather: the short-lived flag stays nil")
    eq(g.can_powershift, nil, "gather: shift feasibility stays nil (in-game to confirm)")
    -- Stale values on the reused table are overwritten, never kept.
    local reused = { family = "TBC", time_to_die = 5, target_short_lived = true,
        can_powershift = true, energy = 5, combo_points = 5, rage = 99,
        rip_remaining = 1, rake_remaining = 1, mangle_remaining = 1 }
    local g2 = ST.DRUID.guide.gather(ST, reused)
    eq(g2, reused, "the reused table is the same table")
    eq(g2.family, "WRATH", "the family overwrite wins over a stale TBC flag")
    eq(g2.time_to_die, nil, "a stale time-to-die is cleared")
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
eq(dg.TF_ENERGY_WRATH, 40, "Tiger's Fury fires under 40 energy on Wrath (the research tree step 1)")
eq(dg.BERSERK_ENERGY_WRATH, 85, "Berserk fires at or under 85 energy on Wrath")
eq(dg.TF_CD_GATE_BERSERK_SECONDS, 15, "Berserk needs Tiger's Fury on cooldown 15 s")
eq(dg.FB_RIP_MIN_SECONDS, 8, "the Bite needs 8 s of Rip left")
eq(dg.FB_SR_MIN_SECONDS, 8, "the Bite needs 8 s of Savage Roar left")
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

-- W1: Tiger's Fury under 40 energy rides the hold overlay (no TF slot exists).
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
end

-- W2: Berserk at or under 85 energy with TF 15 s onto cooldown.
do
    local out = wevaluate({ form_index = 3, energy = 85, berserk_ready = true,
        tf_cd_remaining = 15, combo_points = 0 })
    eq(out.action, nil, "W2: the Berserk call is a hold, never an action")
    eq(out.hold, true, "W2: the Berserk call rides the hold overlay")
    eq(out.hold_text, "BERSERK", "W2: the Berserk call reads BERSERK")
    eq(wevaluate({ form_index = 3, energy = 85.0001, berserk_ready = true,
        tf_cd_remaining = 30, combo_points = 0 }).hold, false,
        "W2 boundary: just over 85 energy never Berserks")
    eq(wevaluate({ form_index = 3, energy = 20, berserk_ready = true,
        tf_cd_remaining = 14.999, combo_points = 0 }).hold, false,
        "W2 boundary: TF 14.999 s onto cooldown is not 15")
    eq(wevaluate({ form_index = 3, energy = 20, berserk_ready = true,
        tf_cd_remaining = NONE, combo_points = 0 }).hold, false,
        "W2: an unknown TF cooldown never Berserks")
    eq(wevaluate({ form_index = 3, energy = NONE, berserk_ready = true,
        tf_cd_remaining = 30, combo_points = 0 }).hold, false,
        "W2: unreadable energy never Berserks")
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
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 5, sr_remaining = 8,
        rip_remaining = 8, rake_remaining = 8, mangle_remaining = 6,
        target_short_lived = true }).action, "bite",
        "W8 boundary: 8 s of Rip and Roar on an execute-flagged target -> Ferocious Bite")
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
        rip_remaining = 7.999, rake_remaining = 8, mangle_remaining = 6,
        target_short_lived = true }).action, "shred",
        "W8: 7.999 s of Rip withholds the Bite even on an execute target")
    eq(wevaluate({ form_index = 3, energy = 90, combo_points = 5, sr_remaining = 7.999,
        rip_remaining = 10, rake_remaining = 8, mangle_remaining = 6,
        target_short_lived = true }).action, "shred",
        "W8: 7.999 s of Savage Roar withholds the Bite even on an execute target")
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

-- S5: the 5 CP Rip, preferred under Tiger's Fury (the KotJ snapshot).
do
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 5, sr_remaining = 30, rip_remaining = NONE,
        mangle_remaining = 6 }).action, "rip",
        "S5: 5 CP with no Rip -> Rip")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 5, sr_remaining = 30, rip_remaining = 10,
        mangle_remaining = 6, rake_remaining = 8, tf_active = true }).action, "rip",
        "S5 snapshot: 5 CP with a healthy Rip still Rips under Tiger's Fury")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 5, sr_remaining = 30, rip_remaining = 0.5,
        mangle_remaining = 6, rake_remaining = 8, tf_active = true }).action, "rip",
        "S5 snapshot: TF overrides a non-expired Rip")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 5, sr_remaining = 30, rip_remaining = 10,
        mangle_remaining = 6, rake_remaining = 8 }).action, "bite",
        "S5 contrast: a healthy Rip with no TF snapshot to take is not refreshed")
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

-- S6/S7/S8/S9: Mangle, then Rake, then the capped-CP Bite, then Shred.
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
        mangle_remaining = 6, rake_remaining = 8 }).action, "bite",
        "S8: capped CP with a healthy Rip and no TF Bites (the Era-loop dump)")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 90,
        combo_points = 4, sr_remaining = 30, rip_remaining = 10,
        mangle_remaining = 6, rake_remaining = 8 }).action, "shred",
        "S9: anything else builds with Shred")
    eq(sevaluate({ family = "ERA", sod_runes = true, form_index = 3, energy = 60,
        combo_points = 0 }).action, "shred",
        "S9: the bare SoD baseline builds (ungated, the E2 convention)")
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
        combo_points = 5, energy = 90 }).action, "bite",
        "the sod gate is strict: a non-true flag stays on the Era chain")
    eq(evaluate({ family = "ERA", sod_runes = false, form_index = 3,
        combo_points = 5, energy = 90 }).action, "bite",
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

    -- The cooldown inputs: knowledge-gated (GetSpellCooldown alone never proves
    -- ready - the fixture answers 0,0 for everything unlisted).
    sandbox.known_names = {}
    sandbox.cooldowns_by_query = {}
    local unknown = ST.DRUID.guide.gather(ST, {})
    eq(unknown.tf_ready, nil, "a 0,0 cooldown without spell knowledge stays nil")
    eq(unknown.berserk_ready, nil, "an unproven Berserk never reads ready")
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

    -- The SoD display: 5 CP with a healthy Rip under Tiger's Fury refreshes Rip
    -- (the KotJ snapshot), and the Mangle HUD slot stays live.
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
    eq(starget("rip"), 1, "SoD display: 5 CP with TF up refreshes Rip (snapshot)")
    eq(starget("bite"), 0, "SoD display: the snapshot replaces the CP dump")
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
-- 14) The FOREVER cat branch: F1 Shifting Power, then the legacy chain;
--     never Tiger's Fury, never powershift (all UNCONFIRMED - see the
--     FOREVER APPENDIX in druid_guide.lua)
--=========================================================================================
eq(dg.SP_ENERGY_GAIN_FOREVER, 40, "Shifting Power grants 40 energy (UNCONFIRMED)")
eq(dg.SP_ENERGY_FOREVER, 60, "Shifting Power fires with room for 40 (100 - 40)")
eq(dg.SP_ENERGY_FOREVER, 100 - dg.SP_ENERGY_GAIN_FOREVER,
    "the 60 room threshold fits the assumed 40 gain (100 - 40)")

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
    -- slot exists for it).
    local out = fevaluate({ form_index = 3, energy = 60, sp_ready = true,
        combo_points = 0 })
    eq(out.action, nil, "F1: the Shifting Power call is a hold, never an action")
    eq(out.hold, true, "F1: the call rides the hold overlay")
    eq(out.hold_text, "SHIFTING POWER", "F1: the call reads SHIFTING POWER")
    eq(out.filler_slot, nil, "F1: the call carries no filler")
    eq(out.judge_slot, nil, "F1: the call carries no judge cue")
    eq(fevaluate({ family = "FOREVER", form_index = 3, energy = 60.0001,
        sp_ready = true, combo_points = 0 }).action, "shred",
        "F1 boundary: 60.0001 energy has no room -> Shred")
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
    -- Past F1 the legacy chain runs unchanged.
    eq(fevaluate({ family = "FOREVER", form_index = 3, rip_remaining = 2,
        combo_points = 0, mangle_remaining = 6, energy = 0 }).action, "rip",
        "Forever fallthrough: the Rip window still refreshes")
    eq(fevaluate({ family = "FOREVER", form_index = 3, rip_remaining = 8,
        rake_remaining = 8, mangle_remaining = 6, combo_points = 5,
        energy = 0 }).action, "bite",
        "Forever fallthrough: 5 CP still Bites by default")
    eq(fevaluate({ family = "FOREVER", form_index = 1 }).action, "maul",
        "Forever bear: the bear rules are untouched")
end

-- No powershifting on Forever (and no Tiger's Fury anywhere): the hold/action
-- vocabulary sweep over the whole Forever input space.
do
    local rips = { NONE, 0, 8 }
    local energies = { NONE, 0, 20, 60, 60.0001, 100 }
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
                        tf_ready = flag,
                    })
                    check(out.hold_text ~= "SHIFT",
                        "Forever sweep: powershifting never prompts")
                    check(out.hold_text ~= "TIGER'S FURY",
                        "Forever sweep: Tiger's Fury never prompts")
                    if out.hold == true then
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

if failures == 0 then
    print("PASS  druid_guide_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  druid_guide_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end

-- tests/guide_contract.lua: offline tests for the generalised next-action guide frame
-- (nextaction_ui.lua) and the paladin guide provider (classes/paladin.lua).
--
-- Sandbox-loads the real compat.lua + utils.lua (and, for the provider half,
-- nextaction.lua + classes/paladin.lua) with frame/API stubs, and pins:
--   * no provider -> the UI is inert (no frame created, nothing ticks, no errors,
--     should_show false; a guide table missing gather/evaluate is not a provider),
--   * the frozen contract: a fake provider drives the slot graphics by key
--     (action / filler / judge), the db gates, the cooldown-swipe channels
--     (remaining+duration, slot swipe_duration fallback, expires, swipe_always),
--     the glow, the labels and the rotation text,
--   * degenerate providers (gather/evaluate that return their table unchanged,
--     nil-returning gather, unknown slot keys) never error,
--   * the paladin provider: contract shape, the twelve slots with the shipped
--     display fields, gather delegation into the caller's reused table, evaluate
--     parity with the pre-refactor engine mapping over scripted input cases, the
--     Era HoW pass-through onto its slot, and the published
--     twist_sounds map,
--   * the paladin guide through the real frame (structures + one combat tick + idle),
--   * the shaman provider: its twenty-two guide slots through the real frame, the
--     two maintain slots (Lightning Shield S-19, Searing Totem S-17) with their
--     client-resolved icons, the APL utility layer's four slots (bench/
--     rotation_gap_vs_apl_2026-10-20.md §5) and the HUD mirror's nil=off hide.
-- Run from the repo root: lua5.1 tests/guide_contract.lua  (any cwd works).

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
-- Frame stubs (record what the guide draws)
--=========================================================================================
local function make_fontstring()
    local f = { hidden = false }
    function f:SetPoint() end
    function f:SetJustifyH() end
    function f:SetShadowColor() end
    function f:SetShadowOffset() end
    function f:SetFont(path, size, flags) f.font = { path, size, flags }; return true end
    function f:SetText(text)
        -- SoD-faithful: a FontString that was never fonted rejects its text on a
        -- real client ("Font not set"). The sandbox must say so too, or a fontless
        -- site stays invisible to the suite.
        if not f.font then
            error("Font not set", 0)
        end
        f.text = text
        f.set_text_calls = (f.set_text_calls or 0) + 1
    end
    function f:SetTextColor(r, g, b, a) f.color = { r, g, b, a } end
    function f:Hide() f.hidden = true end
    function f:Show() f.hidden = false end
    function f:IsShown() return not f.hidden end
    return f
end

local function make_texture()
    local t = { hidden = true }
    function t:SetAllPoints() end
    function t:SetTexCoord(l, r, top, bottom) t.texcoord = { l, r, top, bottom } end
    function t:SetTexture(tex) t.texture = tex end
    function t:SetColorTexture() end
    function t:SetVertexColor(r, g, b, a) t.color = { r, g, b, a } end
    function t:Hide() t.hidden = true end
    function t:Show() t.hidden = false end
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
    -- Cooldown frame API (also present on plain frames: unreachable there).
    function f:SetCooldown(start, duration)
        f.cooldown_sets = (f.cooldown_sets or 0) + 1
        f.cooldown_start, f.cooldown_duration = start, duration
    end
    function f:SetReverse(reverse) f.reverse = reverse end
    function f:SetHideCountdownNumbers(flag) f.hide_numbers = flag end
    function f:SetAllPoints() end
    return f
end

--=========================================================================================
-- Sandbox builder
--=========================================================================================
local SPELL_INFOS = {
    [35395] = { name = "Crusader Strike", icon = "icon_cs" },
    [20271] = { name = "Judgement", icon = "icon_judge" },
    [26573] = { name = "Consecration", icon = "icon_consec" },
    [879] = { name = "Exorcism", icon = "icon_exo" },
    [24275] = { name = "Hammer of Wrath", icon = "icon_how" },
    [20375] = { name = "Seal of Command", icon = "icon_soc" },
    [31892] = { name = "Seal of Blood", icon = "icon_sob" },
    [1001] = { name = "Fake A", icon = "tex_a" },
    [1002] = { name = "Fake B", icon = "tex_b" },
    [1003] = { name = "Fake C", icon = "tex_c" },
    [1004] = { name = "Fake Mark", icon = "tex_mark" },
    [1005] = { name = "Fake Fill A", icon = "tex_fa" },
    [1006] = { name = "Fake Fill B", icon = "tex_fb" },
    -- Shockadin slots (shipped ids, rank-invariant art like the other fillers).
    [20930] = { name = "Holy Shock", icon = "icon_hs" },
    [407624] = { name = "Aura Mastery", icon = "icon_am" },
    -- Rogue slots (names answer too: the class resolves its ids from the client's own
    -- spell data by name).
    [5101] = { name = "Slice and Dice", icon = "i_snd" },
    [5102] = { name = "Rupture", icon = "i_rp" },
    [5103] = { name = "Eviscerate", icon = "i_ev" },
    [5104] = { name = "Envenom", icon = "i_env" },
    [5105] = { name = "Expose Armor", icon = "i_ea" },
    [5106] = { name = "Shiv", icon = "i_shiv" },
    [5107] = { name = "Thistle Tea", icon = "i_tea" },
    [5108] = { name = "Sinister Strike", icon = "i_ss" },
    [5109] = { name = "Deadly Poison", icon = "i_dp" },
    [5110] = { name = "Adrenaline Rush", icon = "i_ar" },
    [5111] = { name = "Blade Flurry", icon = "i_bf" },
    [5112] = { name = "Kick", icon = "i_kick" },
    -- R3 short-CD fixtures (test-owned ids, never shipped): Kidney resolves the
    -- interrupt row, Vanish the Re-stealth CD (mapping UNCONFIRMED), the
    -- Heavy Netherweave rank the Bandage slot (rank UNCONFIRMED).
    [5113] = { name = "Kidney Shot", icon = "i_kidney" },
    [5114] = { name = "Vanish", icon = "i_vanish" },
    [5115] = { name = "Heavy Netherweave Bandage", icon = "i_bandage" },
    -- Shaman maintain slots (S-19 / S-17): the shipped ids are UNCONFIRMED, so
    -- the client's own spell data answers by NAME and re-points the slot icon.
    -- The fixture ids are test-owned (never shipped) - they stand for "whatever
    -- the client answers".
    [9201] = { name = "Lightning Shield", icon = "icon_ls" },
    [9202] = { name = "Searing Totem", icon = "icon_searing" },
}

local BASE_MODULES = { "compat.lua", "utils.lua", "guard.lua", "nextaction.lua", "nextaction_ui.lua" }
local PALADIN_MODULES = { "compat.lua", "utils.lua", "guard.lua", "nextaction.lua", "nextaction_ui.lua",
    "classes/paladin.lua" }

local function build(opts)
    opts = opts or {}
    local sb = {
        clock = opts.clock or 0,
        frames = 0,
        glow_starts = 0,
        glow_stops = 0,
        glow_key = nil,
        cooldowns = opts.cooldowns or {},
        mana = opts.mana or { 100, 100 },
    }

    local env = {}
    for k, v in pairs(_G) do env[k] = v end
    env._G = env
    env.WOW_PROJECT_ID = 5
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_MAINLINE = 1
    env.GetTimePreciseSec = function() return sb.clock end
    env.GetTime = function() return sb.clock end
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    env.GetLocale = function() return "enUS" end
    env.GetBuildInfo = function() return "0.0.0", "00000", "today", 20506 end
    env.UIParent = make_frame("UIParent")
    env.UIParent.GetCenter = function() return 0, 0 end
    env.CreateFrame = function(...)
        sb.frames = sb.frames + 1
        return make_frame(select(2, ...))
    end
    env.GetSpellInfo = function(spell)
        if type(spell) == "number" then
            local info = SPELL_INFOS[spell]
            if info then
                return info.name, nil, info.icon, 0, 0, 0, spell
            end
            return nil
        end
        -- A name lookup (the rogue resolver's shape): first name match wins.
        for id, info in pairs(SPELL_INFOS) do
            if info.name == spell then
                return info.name, nil, info.icon, 0, 0, 0, id
            end
        end
        return nil
    end
    env.GetSpellCooldown = function(spell)
        local cd = sb.cooldowns[spell]
        if cd then
            return cd[1], cd[2], 1, 1
        end
        return 0, 0, 0, 0
    end
    env.GetSpellBaseCooldown = function() return 0 end
    env.IsSpellKnown = function(spell) return sb.known ~= nil and sb.known[spell] == true end
    sb.known = opts.known
    env.UnitPower = function() return sb.mana[1] end
    env.UnitPowerMax = function() return sb.mana[2] end
    env.UnitExists = function() return false end
    env.UnitCreatureType = function() return nil end
    env.UnitAura = function() return nil end
    env.InCombatLockdown = function() return false end

    local ST = {
        PALADIN = {},
        ROGUE = {},
        SHAMAN = {},
        player_class = opts.player_class or "WARRIOR",
        interfaces_are_initialised = true,
        in_combat = false,
        db = { profile = { enabled = true } },
    }
    local class_db = {
        nextaction_enabled = true,
        nextaction_locked = true,
        nextaction_visibility_key = "always",
        nextaction_x = 0,
        nextaction_y = -180,
        nextaction_icon_size = 45,
        nextaction_show_rotation_text = true,
        nextaction_show_label = true,
        nextaction_show_fillers = true,
        nextaction_show_judgement = true,
        nextaction_hold_enabled = true,
        nextaction_reaction_time_ms = 100,
        nextaction_cs_max_delay_ms = 1700,
        nextaction_filler_mana_consecration = 35,
        nextaction_filler_mana_exorcism = 30,
    }
    function ST.get_class_table() return class_db end
    sb.class_db = class_db

    local LCG = {}
    function LCG.PixelGlow_Start(_, _, _, _, _, _, _, _, _, key)
        sb.glow_starts = sb.glow_starts + 1
        sb.glow_key = key
    end
    function LCG.PixelGlow_Stop(_, key)
        sb.glow_stops = sb.glow_stops + 1
        sb.glow_stop_key = key
    end
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
        return nil
    end

    local st = {}
    local modules = opts.modules or BASE_MODULES
    for i = 1, #modules do
        local chunk = assert(loadfile(ROOT .. modules[i]))
        setfenv(chunk, env)
        chunk("SwedgeTimer", st)
        -- Operator order 2026-10-21: a wrapped class file registers its body as a
        -- loader; the sandbox activates it exactly as main.lua does at init.
        local class = modules[i]:match("classes/(%a+)%.lua")
        if class and type(st.class_loaders) == "table"
            and type(st.class_loaders[class:upper()]) == "function" then
            st.class_loaders[class:upper()]()
        end
    end

    sb.env, sb.st, sb.ST = env, st, ST
    function sb.advance(dt) sb.clock = sb.clock + dt end
    return sb
end

--=========================================================================================
-- 1) No provider -> inert
--=========================================================================================
local main = build()
local ST, st = main.ST, main.st
local ui = st.nextaction_ui
check(type(ui) == "table", "nextaction_ui.lua defines st.nextaction_ui")
check(type(ui.get_provider) == "function", "the provider reader is exported")
eq(ui.get_provider(ST), nil, "a class without a guide table has no provider")
eq(main.frames, 0, "loading the module creates no frames")

local expected_entry_points = { "get_provider", "init", "should_show", "update",
    "on_bar_update", "apply_settings" }
for i = 1, #expected_entry_points do
    check(type(ui[expected_entry_points[i]]) == "function",
        "nextaction_ui.lua exposes " .. expected_entry_points[i])
end

local ok = pcall(ui.init, ST)
check(ok, "init without a provider does not error")
eq(main.frames, 0, "no provider: not a single frame is created")
eq(ui.frame, nil, "no provider: no frame is kept")
eq(ui.inert, true, "no provider: the module goes inert")
eq(ui.should_show(ST), false, "no provider: should_show is false")
ok = pcall(ui.update, ST)
check(ok, "update without a provider does not error")
ok = pcall(ui.on_bar_update, ST, "mainhand")
check(ok, "on_bar_update without a provider does not error")
ok = pcall(ui.apply_settings, ST)
check(ok, "apply_settings without a provider does not error")
eq(main.frames, 0, "no provider: nothing was created by any entry point")

-- A guide table is only a provider with both contract functions.
ST.WARRIOR = { guide = {} }
eq(ui.get_provider(ST), nil, "a guide table without gather/evaluate is not a provider")
ST.WARRIOR = { guide = { gather = function(self, out) return out end } }
eq(ui.get_provider(ST), nil, "gather alone is not a provider")
ST.WARRIOR = { guide = { evaluate = function(inputs, out) return out end } }
eq(ui.get_provider(ST), nil, "evaluate alone is not a provider")
ST.WARRIOR = nil

--=========================================================================================
-- 2) Fake provider: slot graphics, gates, swipes, glow, labels, rotation text
--=========================================================================================
local fake_state = { gather_calls = 0, eval_calls = 0 }
local scenario = {
    action = nil, hold = false, hold_text = nil, riding = false, filler_slot = nil,
    judge_slot = nil, rotation = nil, inputs_unknown = false,
    alpha_remaining = 0, alpha_duration = nil, alpha_expires = nil,
    beta_remaining = 0, gamma_expires = nil,
}
local function fake_provider()
    return {
        slots = {
            { key = "alpha", spell_id = 1001, cooldown_key = "alpha", level = 1,
                swipe_duration = 6 },
            { key = "beta", spell_id = 1002, cooldown_key = "beta", level = 2,
                swipe_always = true, swipe_duration = 10 },
            { key = "gamma", spell_id = 1003, cooldown_key = "gamma", level = 3,
                swipe_always = true, swipe_duration = 30 },
            { key = "mark", spell_id = 1004, level = 4, size = { 22.5, 24.9 },
                offset = { -9, -10 }, glow = true, glow_key = "TestGlow" },
            { key = "fill_a", spell_id = 1005, level = 5, label = "FILL", idle_alpha = 0.25 },
            { key = "fill_b", spell_id = 1006, level = 6 },
        },
        gather = function(self, out)
            fake_state.gather_calls = fake_state.gather_calls + 1
            out.alpha_remaining = scenario.alpha_remaining
            out.alpha_duration = scenario.alpha_duration
            out.alpha_expires = scenario.alpha_expires
            out.beta_remaining = scenario.beta_remaining
            out.gamma_expires = scenario.gamma_expires
            return out
        end,
        evaluate = function(inputs, out)
            fake_state.eval_calls = fake_state.eval_calls + 1
            out.action = scenario.action
            out.hold = scenario.hold
            out.hold_text = scenario.hold_text
            out.riding = scenario.riding
            out.filler_slot = scenario.filler_slot
            out.judge_slot = scenario.judge_slot
            out.rotation_key = scenario.rotation
            out.waiting_judgement = false
            out.inputs_unknown = scenario.inputs_unknown
            return out
        end,
        rotation_key = function(inputs) return scenario.rotation end,
        rotation_names = { rot1 = "Rotation One" },
        labels = { next_action = "NEXT", hold = "STAY", ride = "MOVE" },
    }
end

local fake = build()
local fST, fui = fake.ST, fake.st.nextaction_ui
fST.WARRIOR = { guide = fake_provider() }
fST.in_combat = true
fST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
eq(fui.get_provider(fST), fST.WARRIOR.guide, "a full guide table resolves as the provider")
fui.init(fST)
check(fui.frame ~= nil, "the fake provider builds the frame")
eq(#fui.icons, 6, "one icon per declared slot")
check(fake.frames > 0, "frames were created")
eq(fui.frame.label.text, "NEXT", "labels.next_action drives the label text")

local function idx(key) return fui.slot_index[key] end
local function target(key) return fui.icons[idx(key)].fade.target end
local function icon(key) return fui.icons[idx(key)].icon end
local function update_tick()
    fake.advance(0.1)
    fui.update(fST)
end

-- Every slot in declaration order, keyed.
local order_ok = true
for i = 1, #fST.WARRIOR.guide.slots do
    if fui.icons[i].slot ~= fST.WARRIOR.guide.slots[i] then order_ok = false end
end
check(order_ok, "icons follow the slot declaration order")
eq(icon("alpha").texture.texture, "tex_a", "the slot icon shows its spell's texture")
eq(icon("mark").width, 22.5, "the slot size override applies")
eq(icon("mark").height, 24.9, "the slot height override applies")
eq(icon("mark").points[1][4], -9, "the slot offset override applies (x)")
eq(fui.frame.hold.text.text, "STAY", "labels.hold pre-fills the overlay text")

-- Action mapping: the active key lights its slot, nothing else.
scenario.action = "beta"
update_tick()
eq(fake_state.gather_calls, 1, "one gather per computed tick")
eq(fake_state.eval_calls, 1, "one evaluate per computed tick")
eq(target("beta"), 1, "out.action lights the named slot")
eq(target("alpha"), 0, "a non-active slot stays dark")
eq(target("gamma"), 0, "another non-active slot stays dark")
eq(target("mark"), 0, "the judge slot stays dark without out.judge_slot")
eq(fui.frame.hold.fade.target, 0, "no hold without out.hold")

scenario.action = "alpha"
update_tick()
eq(target("alpha"), 1, "out.action follows the provider's key switch")
eq(target("beta"), 0, "the previous action slot fades out")

-- Active swipe: remaining + duration from the gather inputs.
scenario.alpha_remaining = 3
scenario.alpha_duration = 6
update_tick()
eq(icon("alpha").cooldown.cooldown_sets, 1, "the active slot starts its swipe once")
eq(icon("alpha").cooldown.cooldown_duration, 6, "the swipe uses the gathered duration")
near(icon("alpha").cooldown.cooldown_start, fake.clock - 3, 1e-9,
    "the swipe anchors the remaining time in the api.get_time() domain")
eq(icon("alpha").cooldown_set, true, "the set-once latch is armed")

scenario.alpha_remaining = 2
update_tick()
eq(icon("alpha").cooldown.cooldown_sets, 1, "the latch never re-sets while the swipe runs")

-- Hidden non-always slot: the swipe clears.
scenario.action = "gamma"
scenario.alpha_remaining = 5
update_tick()
eq(target("alpha"), 0, "alpha is no longer the action")
eq(icon("alpha").cooldown.cooldown_sets, 2, "the hidden slot's swipe is cleared")
eq(icon("alpha").cooldown.cooldown_duration, 0, "the clear is a zero-length cooldown")
eq(icon("alpha").cooldown_set, false, "the latch reset on clear")

-- swipe_always: the swipe drives while the icon is faded out.
scenario.beta_remaining = 2
update_tick()
eq(target("beta"), 0, "the swipe_always slot is still faded out")
eq(icon("beta").cooldown.cooldown_sets, 1, "the swipe_always slot swipes while hidden")
eq(icon("beta").cooldown.cooldown_duration, 10, "it uses its slot swipe_duration fallback")

-- Expires channel: the seal-aura shape recomputes remaining against the clock.
local gamma_expiry = fake.clock + 5
scenario.gamma_expires = gamma_expiry
update_tick()
eq(icon("gamma").cooldown.cooldown_sets, 1, "the expiry slot starts its swipe")
eq(icon("gamma").cooldown.cooldown_duration, 30,
    "the expiry slot falls back to its slot swipe_duration")
local gamma_remaining = gamma_expiry - fake.clock
near(icon("gamma").cooldown.cooldown_start, fake.clock - (30 - gamma_remaining), 1e-9,
    "the expiry drives a swipe anchored on the aura's remaining time")
scenario.gamma_expires = nil
update_tick()
eq(icon("gamma").cooldown.cooldown_sets, 2, "a dropped expiry clears the swipe")
eq(icon("gamma").cooldown.cooldown_duration, 0, "the cleared swipe has no length")

-- Filler slot mapping and the judge suppression rule.
scenario.filler_slot = "fill_a"
scenario.judge_slot = "mark"
update_tick()
eq(target("fill_a"), 1, "out.filler_slot lights its slot")
eq(target("mark"), 0, "a shown filler suppresses the judge cue")
eq(fake.glow_starts, 0, "the suppressed judge cue never glows")

scenario.filler_slot = nil
update_tick()
eq(target("mark"), 1, "without a filler the judge cue shows")
eq(fake.glow_starts, 1, "the judge cue starts its glow")
eq(fake.glow_key, "TestGlow", "the glow uses the slot's glow_key")
eq(fui.icons[idx("mark")].glowing, true, "the glow latch is armed")
eq(target("fill_a"), 0, "the previous filler fades out")

scenario.judge_slot = nil
update_tick()
eq(target("mark"), 0, "clearing out.judge_slot hides the cue")
eq(fake.glow_stops, 1, "the glow stops with the cue")
eq(fake.glow_stop_key, "TestGlow", "the stop pairs with the start key")
eq(fui.icons[idx("mark")].glowing, false, "the glow latch is cleared")

-- Option gates.
fST.get_class_table().nextaction_show_fillers = false
scenario.filler_slot = "fill_b"
update_tick()
eq(target("fill_b"), 0, "nextaction_show_fillers=false hides the filler")
fST.get_class_table().nextaction_show_fillers = true
fST.get_class_table().nextaction_show_judgement = false
scenario.judge_slot = "mark"
update_tick()
eq(target("mark"), 0, "nextaction_show_judgement=false hides the judge cue")
fST.get_class_table().nextaction_show_judgement = true

-- Hold overlay: text from out.hold_text, then the label fallbacks.
scenario.hold = true
scenario.hold_text = "CUSTOM"
update_tick()
eq(fui.frame.hold.fade.target, 1, "out.hold shows the overlay")
eq(fui.frame.hold.text.text, "CUSTOM", "out.hold_text wins when present")
scenario.hold_text = nil
update_tick()
eq(fui.frame.hold.text.text, "STAY", "without hold_text the hold label applies")
scenario.riding = true
update_tick()
eq(fui.frame.hold.text.text, "MOVE", "riding selects the ride label")
scenario.riding = false
fST.get_class_table().nextaction_hold_enabled = false
update_tick()
eq(fui.frame.hold.fade.target, 0, "nextaction_hold_enabled=false hides the overlay")
fST.get_class_table().nextaction_hold_enabled = true
scenario.hold = false

-- Rotation text: provider.rotation_key + rotation_names, and the gates.
scenario.rotation = "rot1"
update_tick()
eq(fui.frame.rotation_text.text, "Rotation One", "the rotation key resolves through rotation_names")
eq(fui.frame.rotation_text.hidden, false, "a returned rotation key shows the text")
scenario.rotation = nil
update_tick()
eq(fui.frame.rotation_text.hidden, true, "a nil rotation key hides the text")
scenario.rotation = "rot1"
fST.get_class_table().nextaction_show_rotation_text = false
update_tick()
eq(fui.frame.rotation_text.hidden, true, "nextaction_show_rotation_text=false hides the text")
fST.get_class_table().nextaction_show_rotation_text = true
fST.get_class_table().nextaction_show_label = false
update_tick()
eq(fui.frame.label.hidden, true, "nextaction_show_label=false hides the label")
fST.get_class_table().nextaction_show_label = true
update_tick()
eq(fui.frame.label.hidden, false, "the label returns when the gate reopens")

-- M6: out.inputs_unknown suppresses every advice target and paints "…"; the state
-- is a latch (one SetText) and restores the provider label when it clears.
scenario.action = "alpha"
scenario.rotation = "rot1"
scenario.inputs_unknown = true
update_tick()
eq(target("alpha"), 0, "M6: unknown inputs light no action slot")
eq(fui.frame.label.text, "…", "M6: unknown inputs paint the label as ...")
eq(fui.frame.rotation_text.hidden, true, "M6: unknown inputs hide the rotation text")
local unknown_label_sets = fui.frame.label.set_text_calls
update_tick()
eq(fui.frame.label.set_text_calls, unknown_label_sets, "M6: the ... latch does not re-SetText per tick")
scenario.hold = true
update_tick()
eq(fui.frame.hold.fade.target, 0, "M6: unknown inputs suppress the hold overlay")
scenario.hold = false
scenario.inputs_unknown = false
update_tick()
eq(target("alpha"), 1, "M6: clearing the bit restores the action")
eq(fui.frame.label.text, "NEXT", "M6: clearing the bit restores the provider label")
eq(fui.frame.rotation_text.text, "Rotation One", "M6: the rotation text returns")
scenario.rotation = nil
scenario.action = nil

-- Idle: all slots drop to their idle_alpha, swipes clear, rotation text stays live.
scenario.alpha_remaining = 4
fST.in_combat = false
fST.guide_melee_count = 7
fST.guide_waiting_judgement = true
update_tick()
eq(target("fill_a"), 0.25, "idle shows the slot's idle_alpha")
eq(target("alpha"), 0, "idle hides the ordinary slots")
eq(target("beta"), 0, "idle hides the swipe_always slots too")
eq(fui.frame.hold.fade.target, 0, "idle hides the hold overlay")
eq(icon("alpha").cooldown.cooldown_duration, 0, "idle clears the slot swipes")
eq(icon("beta").cooldown.cooldown_duration, 0, "idle clears the swipe_always swipes")
eq(fui.frame.rotation_text.text, "Rotation One", "idle keeps painting the rotation text")
eq(fST.guide_melee_count, 0, "idle resets the swing carry")
eq(fST.guide_waiting_judgement, false, "idle resets the judgement carry")
fST.in_combat = true

-- should_show gates stay the shipped ones.
fST.get_class_table().nextaction_enabled = false
eq(fui.should_show(fST), false, "nextaction_enabled=false hides the guide")
fST.get_class_table().nextaction_enabled = true
fST.get_class_table().nextaction_locked = false
eq(fui.should_show(fST), true, "unlocked keeps the frame visible for positioning")
fST.get_class_table().nextaction_locked = true
fST.get_class_table().nextaction_visibility_key = "in_combat"
fST.in_combat = false
eq(fui.should_show(fST), false, "the in_combat visibility key hides out of combat")
fST.get_class_table().nextaction_visibility_key = "always"
local saved_mainhand = fST.mainhand
fST.mainhand = nil
eq(fui.should_show(fST), false, "no swing state hides the guide")
-- Ranged-only play (the hunter at range): no mainhand cycle ever starts, so the
-- guide must ride the ranged hand instead of staying dead.
fST.ranged = { speed = 2.9, ends_at = 2.9, start = 0.0, is_full = false }
eq(fui.should_show(fST), true, "a ranged cycle alone keeps the guide visible")
fST.ranged.is_full = true
eq(fui.should_show(fST), false, "a full ranged bar does not count as a live cycle")
fST.ranged = nil
fST.mainhand = saved_mainhand

--=========================================================================================
-- 3) Degenerate providers never error
--=========================================================================================
local bare = build()
local bST, bui = bare.ST, bare.st.nextaction_ui
bST.player_class = "WARRIOR"
bST.in_combat = true
bST.mainhand = { speed = 3.0, ends_at = 5.0, start = 0.0, is_full = false }
bST.WARRIOR = {
    guide = {
        slots = { { key = "only", spell_id = 1001, cooldown_key = "only" } },
        gather = function(self, out) return out end,
        evaluate = function(inputs, out) return out end,
    },
}
bui.init(bST)
check(bui.frame ~= nil, "a minimal provider still builds the frame")
bare.advance(0.1)
ok = pcall(bui.update, bST)
check(ok, "a provider that writes nothing into out does not error (" .. tostring(ok) .. ")")
eq(bui.icons[1].fade.target, 0, "an empty out lights no slot")
eq(bui.frame.hold.fade.target, 0, "an empty out shows no hold")
eq(bui.frame.rotation_text.hidden, true, "no rotation_key function keeps the text hidden")

bST.WARRIOR.guide.evaluate = function(inputs, out)
    out.action = "no_such_slot"
    out.filler_slot = "also_missing"
    out.judge_slot = "missing_judge"
    return out
end
ok = pcall(bui.update, bST)
check(ok, "unknown slot keys do not error")
eq(bui.icons[1].fade.target, 0, "unknown slot keys light nothing")

bST.WARRIOR.guide.gather = function(self, out) return nil end
ok = pcall(bui.update, bST)
check(ok, "a gather that returns nil does not error")
bST.WARRIOR.guide.rotation_key = function(inputs) return nil end
bare.advance(0.1)
ok = pcall(bui.update, bST)
check(ok, "a rotation_key that returns nil does not error")
eq(bui.frame.rotation_text.hidden, true, "a nil rotation key hides the text")

--=========================================================================================
-- 4) The paladin provider: contract shape
--=========================================================================================
local pal = build({ modules = PALADIN_MODULES, player_class = "PALADIN" })
local pST, pst = pal.ST, pal.st
local pui = pst.nextaction_ui
check(type(pST.PALADIN.guide) == "table", "classes/paladin.lua defines ST.PALADIN.guide")
check(type(pST.PALADIN.guide.gather) == "function", "the paladin guide has gather")
check(type(pST.PALADIN.guide.evaluate) == "function", "the paladin guide has evaluate")
check(type(pST.PALADIN.guide.rotation_key) == "function", "the paladin guide has rotation_key")
eq(pST.PALADIN.guide.rotation_names, pst.nextaction.display_names,
    "the paladin rotation names are the engine's own map")
eq(pst.nextaction_ui.get_provider(pST), pST.PALADIN.guide,
    "the paladin guide resolves as the frame's provider")

local slots = pST.PALADIN.guide.slots
eq(#slots, 12, "the paladin declares twelve slots (twist composite + judge + five fillers + the WotLK APL band)")
local expected_keys = { "cs", "soc", "sob", "twist", "judge", "consecration", "exorcism", "how",
    "holy_shock", "aura_mastery", "hor", "how_wrath" }
local keys_ok = true
for i = 1, #expected_keys do
    if slots[i].key ~= expected_keys[i] then keys_ok = false end
end
check(keys_ok, "the slot keys are the engine's action/filler keys, in ship order")
eq(slots[1].spell_id, 35395, "cs keeps the Crusader Strike id")
eq(slots[2].spell_id, 20375, "soc keeps the Seal of Command id")
eq(slots[3].spell_id, 31892, "sob keeps the Seal of Blood id")
eq(slots[4].spell_id, 20375, "twist shows the Command icon")
eq(slots[4].overlay.spell_id, 31892, "twist overlays the Blood icon")
eq(slots[4].overlay.size[1], 22.5, "the twist overlay is half width")
eq(slots[4].overlay.offset[1], 11.25, "the twist overlay sits on the right half")
eq(slots[4].overlay.keep_aspect, true, "the twist overlay is centre-cropped")
eq(slots[4].level, 8, "the twist primary keeps its shipped Z level")
eq(slots[5].spell_id, 20271, "judge keeps the Judgement id")
eq(slots[5].size[1], 22.5, "the judge cue keeps its small size")
eq(slots[5].offset[1], -9, "the judge cue keeps its low-left offset")
eq(slots[5].border_size, 1, "the judge cue keeps its 1px border")
eq(slots[5].glow, true, "the judge cue keeps its glow")
eq(slots[5].glow_key, "NextActionJudge", "the judge glow key is the shipped one")
eq(slots[6].spell_id, 26573, "consecration is the Consecration filler")
eq(slots[6].zoom, 0.2, "consecration keeps the archive zoom")
eq(slots[7].spell_id, 879, "exorcism is the Exorcism filler")
eq(slots[7].zoom, 0.15, "exorcism keeps the archive zoom")
eq(slots[8].key, "how", "the eighth slot is the HoW execute cue")
eq(slots[8].spell_id, 24275, "how carries the Hammer of Wrath rank-1 id")
eq(slots[8].zoom, 0.15, "how matches the single-target filler zoom")
eq(slots[8].label, "FILLER", "how carries the filler caption")
eq(slots[8].cooldown_key, nil, "how carries no swipe, like the other fillers")
eq(slots[8].name_suffix, "FillerH", "how keeps a unique frame-name suffix")
eq(slots[8].level, 15, "how draws above the other fillers")
eq(slots[9].key, "holy_shock", "the ninth slot is the Holy Shock shockadin cue")
eq(slots[9].spell_id, 20930, "holy_shock carries the Holy Shock max-rank id")
eq(slots[9].zoom, 0.15, "holy_shock matches the single-target filler zoom")
eq(slots[9].label, "FILLER", "holy_shock carries the filler caption")
eq(slots[9].cooldown_key, nil, "holy_shock carries no swipe, like the other fillers")
eq(slots[9].name_suffix, "FillerHS", "holy_shock keeps a unique frame-name suffix")
eq(slots[9].level, 16, "holy_shock draws above how")
eq(slots[10].key, "aura_mastery", "the tenth slot is the Aura Mastery shockadin cue")
eq(slots[10].spell_id, 407624, "aura_mastery carries the legs-rune id")
eq(slots[10].zoom, 0.15, "aura_mastery matches the single-target filler zoom")
eq(slots[10].label, "FILLER", "aura_mastery carries the filler caption")
eq(slots[10].cooldown_key, nil, "aura_mastery carries no swipe, like the other fillers")
eq(slots[10].name_suffix, "FillerAM", "aura_mastery keeps a unique frame-name suffix")
eq(slots[10].level, 17, "aura_mastery draws above holy_shock")
eq(slots[6].label, "FILLER", "the filler icons keep their caption")
eq(slots[1].cooldown_key, "cs", "cs swipes from the cs inputs")
eq(slots[2].cooldown_key, "soc", "soc swipes from the soc inputs")
eq(slots[4].cooldown_key, nil, "the twist cue carries no swipe")
eq(slots[6].cooldown_key, nil, "the fillers carry no swipe")
eq(slots[1].swipe_duration, 6, "cs keeps the archive's 6 s swipe fallback")
eq(slots[5].swipe_duration, 8, "judge keeps the archive's 8 s swipe fallback")
eq(slots[2].swipe_duration, 30, "soc keeps the archive's 30 s swipe fallback")
eq(slots[2].swipe_always, true, "the seal swipes drive while hidden")
eq(slots[1].swipe_always, nil, "the cs swipe only drives while shown")
eq(slots[3].idle_alpha, 0.5, "the idle opener is the Blood slot at half alpha")
check(type(pST.PALADIN.twist_sounds) == "table", "ST.PALADIN.twist_sounds is published")
check(pST.PALADIN.twist_sounds["pop"] ~= nil, "the published sound map carries pop")
check(pST.PALADIN.twist_sounds["TadaFanfare"] ~= nil, "the published sound map carries TadaFanfare")

--=========================================================================================
-- 5) The paladin gather: delegation + the display-only seal fields
--=========================================================================================
pST.PALADIN.get_twist_window_time_before_swing = function() return 0.4 end
function pST.get_spell_gcd_duration() return 1.5 end
function pST.get_gcd_time_before_swing_seconds() return 1.5 end
pST.mainhand = { speed = 3.0, ends_at = 4.0, start = 1.0, is_full = false }
pST.gcd = { expires = 0 }
pST.has_soc = true
pST.has_sob = false
pST.soc_expires = 31.0
pST.soc_duration = 30
pST.sob_expires = nil
pST.sob_duration = nil
pST.guide_melee_count = 0
pST.guide_waiting_judgement = false
pal.known = { [35395] = true, ["Crusader Strike"] = true }
pal.cooldowns["Crusader Strike"] = { 1.0, 4.0 }   -- CS: 4 s running, 4 s long
pal.cooldowns["Judgement"] = { 0.0, 8.0 }   -- Judgement: 8 s running, 8 s long

local gathered_target = {}
pal.clock = 1.0
local gathered = pST.PALADIN.guide.gather(pST, gathered_target)
eq(gathered, gathered_target, "gather writes into and returns the caller's table")
eq(gathered.speed, 3.0, "gather: speed")
near(gathered.swing_remaining, 3.0, 1e-9, "gather: swing_remaining")
eq(gathered.G, 1.5, "gather: G")
eq(gathered.seal, "soc", "gather: the active seal")
eq(gathered.cs_remaining, 4.0, "gather: cs_remaining from the client cooldown")
eq(gathered.cs_duration, 4.0, "gather: cs_duration latched from the client cooldown")
eq(gathered.judge_remaining, 7.0, "gather: judge_remaining from the client cooldown")
eq(gathered.judge_duration, 8.0, "gather: judge_duration latched from the client cooldown")
eq(gathered.soc_expires, 31.0, "gather: the Command aura expiry rides the inputs")
eq(gathered.soc_duration, 30, "gather: the Command aura length rides the inputs")
eq(gathered.sob_expires, nil, "gather: a cleared Blood aura clears its expiry")
eq(gathered.sob_duration, nil, "gather: a cleared Blood aura clears its length")
eq(gathered.mana_pct, 100, "gather: mana percentage")
eq(gathered.creature_type, nil, "gather: no target -> no creature type")
eq(gathered.filler_remaining, 0, "gather: the Consecration cooldown remaining")
eq(gathered.waiting_judgement, false, "gather: the judgement carry")
near(gathered.twist_window, 0.4, 1e-9, "gather: the twist window")
eq(gathered.inputs_unknown, false, "M6: a live swing gathers inputs_unknown=false")

-- Without an out table the module's own reused table is used (shipped path).
local own = pST.PALADIN.gather_guide_inputs(pST)
eq(own, pST.PALADIN.guide_inputs, "gather without an out table uses the module's reused table")
eq(own.cs_remaining, gathered.cs_remaining, "both gather paths agree on cs_remaining")
eq(own.seal, gathered.seal, "both gather paths agree on the seal")
eq(own.soc_expires, gathered.soc_expires, "both gather paths agree on the seal expiry")

-- Practice mirror: cleared expiries reach the frame as clears.
pST.soc_expires = nil
pST.soc_duration = nil
pST.has_soc = false
local cleared = pST.PALADIN.guide.gather(pST, {})
eq(cleared.seal, "none", "practice/cleared seals read as no seal")
eq(cleared.soc_expires, nil, "practice/cleared seals clear the expiry")
eq(cleared.soc_duration, nil, "practice/cleared seals clear the duration")

-- M6: without a usable swing record the gather declares the inputs unknown (the
-- frame then renders "…" instead of advice thresholded off speed = 0).
local saved_swing = pST.mainhand
pST.mainhand = {}
local no_swing = pST.PALADIN.guide.gather(pST, {})
eq(no_swing.speed, 0, "M6: no swing record reads speed 0")
eq(no_swing.inputs_unknown, true, "M6: no swing record marks the inputs unknown")
pST.mainhand = { speed = 3.0, ends_at = 3.0, start = 1.0, is_full = true }
eq(pST.PALADIN.guide.gather(pST, {}).inputs_unknown, true, "M6: a full bar marks the inputs unknown")
pST.mainhand = saved_swing

-- The rotation order the running client plays: the gather publishes it next to
-- the FCFS mode it decided, so the practice surface (ST.PALADIN.practice_
-- rotation_for) and the guide can never name different orders.
eq(pST.PALADIN.practice_running_order,
    pST.PALADIN.practice_order_for_mode(gathered.fcfs_mode),
    "gather: the published running order matches the FCFS mode it decided")
eq(pST.PALADIN.practice_running_order, "twist",
    "gather: a client with no FCFS mode plays the twist order")

--=========================================================================================
-- 6) The paladin evaluate: parity with the pre-refactor display mapping
--=========================================================================================
local na = pst.nextaction
local function inp(overrides)
    local t = {
        speed = 3.0, swing_remaining = 3.0, G = 1.5, gcd_remaining = 0,
        twist_window = 0.4, reaction = 0.1, cs_remaining = 6, judge_remaining = 6,
        seal = "none", cs_delay_max = 1.7, waiting_judgement = false,
        melee_count = 0, mana_pct = 50, creature_type = nil, filler_remaining = 0,
    }
    for k, v in pairs(overrides or {}) do t[k] = v end
    return t
end

-- The pre-refactor display mapping: engine flags -> what the frame consumes. The
-- expected side re-derives it from a FRESH engine out table, so a stale provider
-- field or a wrong mapping shows up as a mismatch.
local function engine_map(engine_out)
    return {
        action = engine_out.riding and "sob" or engine_out.action,
        hold = engine_out.hold,
        hold_text = engine_out.riding and "RIDE" or "HOLD",
        filler_slot = engine_out.filler_kind,
        judge_slot = engine_out.judge_call and "judge" or nil,
        waiting_judgement = engine_out.waiting_judgement,
    }
end

local PARITY_CASES = {
    { name = "soc before div", inputs = { seal = "soc" },
        want = { action = "twist", hold = true, hold_text = "HOLD",
            filler_slot = nil, judge_slot = nil, rotation = "1/2" } },
    { name = "CS override", inputs = { cs_remaining = 2.0 },
        want = { action = "cs", hold = true, hold_text = "HOLD",
            filler_slot = nil, judge_slot = nil, rotation = "1/2" } },
    { name = "blood ride", inputs = { seal = "sob", swing_remaining = 1.0,
            gcd_remaining = 0.5, cs_remaining = 6, melee_count = 3 },
        want = { action = "sob", hold = true, hold_text = "RIDE",
            filler_slot = "consecration", judge_slot = nil, rotation = "1/2" } },
    { name = "judgement cue", inputs = { seal = "sob", swing_remaining = 3.0,
            gcd_remaining = 0, cs_remaining = 6, judge_remaining = 0.5 },
        want = { action = "soc", hold = true, hold_text = "HOLD",
            filler_slot = nil, judge_slot = "judge", rotation = "1/2" } },
    { name = "exorcism filler", inputs = { seal = "soc", gcd_remaining = 1.0,
            cs_remaining = 6, melee_count = 3, mana_pct = 40, creature_type = "Undead" },
        want = { action = "twist", hold = true, hold_text = "HOLD",
            filler_slot = "exorcism", judge_slot = nil, rotation = "1/2" } },
    { name = "no-seal twist window", inputs = { swing_remaining = 0.3, cs_remaining = 6 },
        want = { action = "sob", hold = false, hold_text = "HOLD",
            filler_slot = nil, judge_slot = nil, rotation = "1/2" } },
    { name = "filler held back", inputs = { seal = "soc", gcd_remaining = 1.0,
            cs_remaining = 6, melee_count = 3, mana_pct = 40, creature_type = "Undead",
            filler_remaining = 2.0 },
        want = { action = "twist", hold = true, hold_text = "HOLD",
            filler_slot = nil, judge_slot = nil, rotation = "1/2" } },
    { name = "fast weapon rotation", inputs = { speed = 2.3, swing_remaining = 2.3,
            G = 1.15, cs_remaining = 6, seal = "soc" },
        want = { action = "twist", hold = true, hold_text = "HOLD",
            filler_slot = nil, judge_slot = nil, rotation = "2/3" } },
}

for i = 1, #PARITY_CASES do
    local case = PARITY_CASES[i]
    local inputs = inp(case.inputs)
    local engine_out = {}
    na.evaluate(inputs, engine_out)
    local expected = engine_map(engine_out)
    local out = {}
    local ret = pST.PALADIN.guide.evaluate(inputs, out)
    eq(ret, out, case.name .. ": evaluate returns the caller's out table")
    eq(out.action, expected.action, case.name .. ": action mapping")
    eq(out.hold, expected.hold, case.name .. ": hold")
    eq(out.hold_text, expected.hold_text, case.name .. ": hold_text")
    eq(out.filler_slot, expected.filler_slot, case.name .. ": filler_slot")
    eq(out.judge_slot, expected.judge_slot, case.name .. ": judge_slot")
    eq(out.waiting_judgement, expected.waiting_judgement, case.name .. ": judgement carry")
    eq(out.rotation_key, na.calculate_rotation(inputs.speed, inputs.G),
        case.name .. ": rotation_key")
    local want = case.want
    eq(out.action, want.action, case.name .. ": action literal")
    eq(out.hold, want.hold, case.name .. ": hold literal")
    eq(out.hold_text, want.hold_text, case.name .. ": hold_text literal")
    eq(out.filler_slot, want.filler_slot, case.name .. ": filler_slot literal")
    eq(out.judge_slot, want.judge_slot, case.name .. ": judge_slot literal")
    eq(out.rotation_key, want.rotation, case.name .. ": rotation_key literal")
end

-- Reused tables: repeated calls with the same inputs stay identical (the engine's
-- last-action seed never leaks into the result), and nil-able fields are overwritten.
local ride_inputs = inp({ seal = "sob", swing_remaining = 1.0, gcd_remaining = 0.5,
    cs_remaining = 6, melee_count = 3 })
local out_a, out_b = {}, {}
pST.PALADIN.guide.evaluate(ride_inputs, out_a)
pST.PALADIN.guide.evaluate(ride_inputs, out_b)
eq(out_a.action, out_b.action, "a repeated ride tick keeps the same action")
eq(out_a.hold_text, out_b.hold_text, "a repeated ride tick keeps the same hold text")
eq(out_a.filler_slot, out_b.filler_slot, "a repeated ride tick keeps the same filler slot")
check(pST.PALADIN.guide_raw ~= nil and out_a ~= pST.PALADIN.guide_raw,
    "the engine keeps its own reused output table (the caller's out is separate)")

local cue_inputs = inp({ seal = "sob", swing_remaining = 3.0, gcd_remaining = 0,
    cs_remaining = 6, judge_remaining = 0.5 })
pST.PALADIN.guide.evaluate(cue_inputs, out_a)
eq(out_a.judge_slot, "judge", "the cue case sets judge_slot")
pST.PALADIN.guide.evaluate(inp({ seal = "soc" }), out_a)
eq(out_a.judge_slot, nil, "the next case overwrites judge_slot with nil")
eq(out_a.filler_slot, nil, "the next case overwrites filler_slot with nil")

-- Era execute display: the engine's filler_kind "how" reaches the frame's own
-- slot (previously dropped as an unknown key); Era shows no rotation pattern.
local how_inputs = inp({ seal = "soc", swing_remaining = 0.0, cs_remaining = 6,
    melee_count = 3, mana_pct = 50, era = true, cs_known = false,
    target_health_pct = 19, how_remaining = 0 })
local how_engine_out = {}
na.evaluate(how_inputs, how_engine_out)
eq(how_engine_out.filler_kind, "how", "the execute setup yields filler_kind how")
local how_out = {}
pST.PALADIN.guide.evaluate(how_inputs, how_out)
eq(how_out.action, "twist", "how display: the execute keeps the twist action")
eq(how_out.hold, true, "how display: the execute keeps the twist hold")
eq(how_out.hold_text, "HOLD", "how display: the execute is not a ride")
eq(how_out.filler_slot, "how", "how display: filler_kind how maps to the how slot")
eq(how_out.judge_slot, nil, "how display: no judgement cue on the execute tick")
eq(how_out.rotation_key, nil, "how display: Era shows no rotation pattern")
eq(how_out.waiting_judgement, how_engine_out.waiting_judgement,
    "how display: judgement carry matches the engine")

--=========================================================================================
-- 7) The paladin guide through the real frame
--=========================================================================================
pal.frames = 0
pui.init(pST)
check(pui.frame ~= nil, "the paladin provider builds the shipped frame")
eq(#pui.icons, 12, "the paladin frame holds one icon per slot")
eq(pal.frames, 32,
    "frame count: group + hold + 12 icons/borders + twist overlay + 4 cooldown frames")
eq(pui.icons[4].icon.overlay ~= nil, true, "the twist slot carries its overlay icon")
eq(pui.icons[4].icon.overlay.texture.texture, "icon_sob", "the overlay shows the Blood icon")
eq(pui.icons[4].icon.overlay.points[1][4], 11.25, "the overlay anchors on the right half")
eq(pui.icons[5].icon.texture.texture, "icon_judge", "the judge cue shows the Judgement icon")
eq(pui.icons[6].icon.texture.texture, "icon_consec", "the consecration filler shows its icon")
eq(pui.icons[6].icon.points[1][4], 0, "the filler sits centred")
eq(pui.icons[8].icon.texture.texture, "icon_how", "the how filler shows the HoW icon")
eq(pui.icons[8].icon.points[1][4], 0, "the how filler sits centred")
eq(pui.icons[9].icon.texture.texture, "icon_hs", "the holy_shock filler shows the Holy Shock icon")
eq(pui.icons[9].icon.points[1][4], 0, "the holy_shock filler sits centred")
eq(pui.icons[10].icon.texture.texture, "icon_am", "the aura_mastery filler shows the Aura Mastery icon")
eq(pui.icons[10].icon.points[1][4], 0, "the aura_mastery filler sits centred")
eq(pui.icons[6].fade.frame, pui.icons[6].icon, "every slot icon carries its fade element")
eq(pui.icons[2].remaining_key, "soc_remaining", "the swipe field names are derived once")
eq(pui.icons[2].expires_key, "soc_expires", "the expiry field name is derived once")
eq(pui.icons[5].glow_key, "NextActionJudge", "the judge keeps the shipped glow key")

-- One in-combat tick: no seal + full swing -> reseal Command, rotation 1/2.
pST.PALADIN.get_twist_window_time_before_swing = function() return 0.4 end
pST.mainhand = { speed = 3.0, ends_at = 0, start = 0, is_full = false }
pST.gcd = { expires = 0 }
pST.has_soc = false
pST.has_sob = false
pST.soc_expires = nil
pST.sob_expires = nil
pST.guide_melee_count = 0
pST.guide_waiting_judgement = false
pal.cooldowns = {}
pal.cooldowns["Crusader Strike"] = { 2.0, 4.0 }   -- CS on cooldown: no override on the reseal tick
pal.cooldowns["Judgement"] = { 0.0, 8.0 }
pST.in_combat = true
pST.mainhand.ends_at = pal.clock + 3.0
pal.advance(1.0)
pui.update(pST)
local function ptarget(key) return pui.icons[pui.slot_index[key]].fade.target end
eq(ptarget("soc"), 1, "the paladin tick shows the Command slot")
eq(ptarget("cs"), 0, "the CS slot stays dark on the reseal tick")
eq(ptarget("twist"), 0, "the twist slot stays dark on the reseal tick")
eq(ptarget("sob"), 0, "the Blood slot stays dark on the reseal tick")
eq(pui.frame.rotation_text.text, "1/2", "the paladin rotation text paints the engine's display name")

-- Idle tick: the Blood opener dims to half alpha, swipes clear.
pST.in_combat = false
pST.mainhand.ends_at = pal.clock + 3.0
pal.advance(1.0)
pui.update(pST)
eq(ptarget("sob"), 0.5, "the idle tick shows the Blood opener at half alpha")
eq(ptarget("soc"), 0, "the idle tick hides the Command slot")
eq(pui.frame.rotation_text.text, "1/2", "the idle tick keeps the rotation text")

--=========================================================================================
-- 8) Paladin display parity: the real pipeline vs the pre-refactor display mapping
--=========================================================================================
-- The pre-refactor display mapped the engine's flags onto the fixed widgets and drove
-- four swipes (cs / judge always-gated-on-show, the two seals always). This section
-- re-implements that mapping (a copy of the shipped code's arithmetic, latch included)
-- and replays scripted engine states through the REAL paladin provider + frame,
-- comparing every widget's fade target, the hold text, the glow latch and each swipe's
-- remaining / latch / last command. The engine consuming the same inputs feeds the
-- reference, so a wiring drift shows up as a mismatch.
local function new_rec_icon()
    local f = { cooldown_set = false, cooldown = {} }
    function f.cooldown:SetCooldown(start, duration)
        self.sets = (self.sets or 0) + 1
        self.start, self.duration = start, duration
    end
    return f
end
local function rec_set_icon_cooldown(rec, remaining, full_duration, now)
    remaining = remaining or 0
    if remaining > (rec.cooldown_prev or 0) + 0.1 then
        rec.cooldown_set = false
    end
    rec.cooldown_prev = remaining
    if remaining > 0 then
        if not rec.cooldown_set then
            rec.cooldown:SetCooldown(now - (full_duration - remaining), full_duration)
            rec.cooldown_set = true
        end
    else
        if rec.cooldown_set then
            rec.cooldown:SetCooldown(0, 0)
            rec.cooldown_set = false
        end
    end
end
local function rec_set_seal_icon_cooldown(rec, expires, full_duration, now)
    local remaining = 0
    if expires and expires > 0 then
        remaining = expires - now
        if remaining < 0 then
            remaining = 0
        end
    end
    rec_set_icon_cooldown(rec, remaining, full_duration or 30, now)
end

local ref_icons = { cs = new_rec_icon(), command = new_rec_icon(),
    blood = new_rec_icon(), judge = new_rec_icon() }
local ref_targets = {}

local function reference_display(self, out, inputs, db, now)
    local cs_target, command_target, blood_target, twist_target = 0, 0, 0, 0
    local judge_target, hold_target, consec_target, exo_target, how_target = 0, 0, 0, 0, 0
    local hs_target, am_target = 0, 0
    if out.riding then
        blood_target = 1
    elseif out.action == "cs" then
        cs_target = 1
    elseif out.action == "soc" then
        command_target = 1
    elseif out.action == "twist" then
        twist_target = 1
    elseif out.filler_kind == nil then
        -- FCFS filler ticks (action nil, filler set) light the filler alone;
        -- the blood fallthrough is the twist tree's idle reseal shape.
        blood_target = 1
    end
    local hold_text
    if out.hold and db.nextaction_hold_enabled ~= false then
        hold_target = 1
        hold_text = out.riding and "RIDE" or "HOLD"
    end
    if out.filler_kind and db.nextaction_show_fillers ~= false then
        if out.filler_kind == "exorcism" then
            exo_target = 1
        elseif out.filler_kind == "how" then
            how_target = 1
        elseif out.filler_kind == "holy_shock" then
            hs_target = 1
        elseif out.filler_kind == "aura_mastery" then
            am_target = 1
        else
            consec_target = 1
        end
    end
    if out.judge_call and db.nextaction_show_judgement ~= false
        and consec_target == 0 and exo_target == 0 then
        judge_target = 1
    end
    local cs_remaining = inputs.cs_remaining or out.cs_remaining or 0
    local judge_remaining = inputs.judge_remaining or out.judge_remaining or 0
    rec_set_icon_cooldown(ref_icons.cs, cs_target > 0 and cs_remaining or 0,
        inputs.cs_duration or 6, now)
    rec_set_icon_cooldown(ref_icons.judge, judge_target > 0 and judge_remaining or 0,
        inputs.judge_duration or 8, now)
    rec_set_seal_icon_cooldown(ref_icons.command, self.soc_expires, self.soc_duration, now)
    rec_set_seal_icon_cooldown(ref_icons.blood, self.sob_expires, self.sob_duration, now)
    ref_targets.cs = cs_target
    ref_targets.command = command_target
    ref_targets.blood = blood_target
    ref_targets.twist = twist_target
    ref_targets.judge = judge_target
    ref_targets.hold = hold_target
    ref_targets.consec = consec_target
    ref_targets.exo = exo_target
    ref_targets.how = how_target
    ref_targets.hs = hs_target
    ref_targets.am = am_target
    ref_targets.hold_text = hold_text
    return ref_targets
end

-- Scripted tick inputs (the engine's frozen names + the two display durations); the
-- seal expiries/durations ride on self, exactly like the pre-refactor display read them.
local SCRIPT_KEYS = { "speed", "swing_remaining", "G", "gcd_remaining", "twist_window",
    "reaction", "cs_remaining", "judge_remaining", "seal", "cs_delay_max",
    "waiting_judgement", "melee_count", "mana_pct", "creature_type", "filler_remaining",
    "cs_duration", "judge_duration", "soc_expires", "soc_duration", "sob_expires",
    "sob_duration", "era", "cs_known", "target_health_pct", "how_remaining",
    "fcfs_mode", "holy_power_stacks", "holy_power_set_known", "exo_remaining",
    "am_remaining", "hs_remaining", "am_rune_known", "sod_libram_known",
    "sunlight_remaining", "templar_stack_remaining", "templar_wrath_remaining",
    "sod_dual_seal_active", "soc_remaining_seconds", "som_remaining_seconds",
    "sod_t2_known", "sod_naxx_known", "ds_remaining", "cons_remaining",
    "strict_sequence" }
local scripted = {}
local real_gather = pST.PALADIN.guide.gather
pST.PALADIN.guide.gather = function(self, out)
    for i = 1, #SCRIPT_KEYS do
        out[SCRIPT_KEYS[i]] = scripted[SCRIPT_KEYS[i]]
    end
    return out
end

local function script(key, value) scripted[key] = value end

local function parity_tick(label, scenarios, mutate_db)
    for i = 1, #scenarios do
        local case = scenarios[i]
        -- Fresh scripted inputs (every key assigned so nothing leaks between ticks).
        for k = 1, #SCRIPT_KEYS do
            scripted[SCRIPT_KEYS[k]] = nil
        end
        script("speed", 3.0)
        script("swing_remaining", 3.0)
        script("G", 1.5)
        script("gcd_remaining", 0)
        script("twist_window", 0.4)
        script("reaction", 0.1)
        script("cs_remaining", 6)
        script("judge_remaining", 6)
        script("seal", "none")
        script("cs_delay_max", 1.7)
        script("waiting_judgement", false)
        script("melee_count", 0)
        script("mana_pct", 50)
        script("creature_type", nil)
        script("filler_remaining", 0)
        for k, v in pairs(case.inputs) do script(k, v) end
        pST.soc_expires = case.soc_expires
        pST.soc_duration = case.soc_duration
        pST.sob_expires = case.sob_expires
        pST.sob_duration = case.sob_duration
        script("soc_expires", case.soc_expires)
        script("soc_duration", case.soc_duration)
        script("sob_expires", case.sob_expires)
        script("sob_duration", case.sob_duration)
        if mutate_db then mutate_db(pST.get_class_table(), case) end

        -- The reference side: the engine consumes the same inputs. FCFS ticks
        -- (shock/wrath-like/stack) run the priority-winner engine, twist ticks
        -- the archived tree.
        local engine_out = {}
        if case.inputs.fcfs_mode ~= nil then
            na.evaluate_fcfs(inp(case.inputs), engine_out)
        else
            na.evaluate(inp(case.inputs), engine_out)
        end
        pST.mainhand.ends_at = pal.clock + 3.0
        pal.advance(0.1)
        local ref = reference_display(pST, engine_out, inp(case.inputs),
            pST.get_class_table(), pal.clock)
        pui.update(pST)

        local tag = label .. "/" .. case.name
        eq(ptarget("cs"), ref.cs, tag .. ": cs icon")
        eq(ptarget("soc"), ref.command, tag .. ": command icon")
        eq(ptarget("sob"), ref.blood, tag .. ": blood icon")
        eq(ptarget("twist"), ref.twist, tag .. ": twist icon")
        eq(ptarget("judge"), ref.judge, tag .. ": judge icon")
        eq(pui.frame.hold.fade.target, ref.hold, tag .. ": hold overlay")
        eq(ptarget("consecration"), ref.consec, tag .. ": consecration filler")
        eq(ptarget("exorcism"), ref.exo, tag .. ": exorcism filler")
        eq(ptarget("how"), ref.how, tag .. ": how filler")
        eq(ptarget("holy_shock"), ref.hs, tag .. ": holy_shock filler")
        eq(ptarget("aura_mastery"), ref.am, tag .. ": aura_mastery filler")
        if ref.hold_text then
            eq(pui.frame.hold.text.text, ref.hold_text, tag .. ": hold text")
        end
        eq(pui.icons[pui.slot_index.judge].glowing, ref.judge > 0, tag .. ": glow latch")

        local widgets = {
            { ref_icon = ref_icons.cs, slot = "cs" },
            { ref_icon = ref_icons.judge, slot = "judge" },
            { ref_icon = ref_icons.command, slot = "soc" },
            { ref_icon = ref_icons.blood, slot = "sob" },
        }
        for w = 1, #widgets do
            local w_ref = widgets[w].ref_icon
            local w_icon = pui.icons[pui.slot_index[widgets[w].slot]].icon
            eq(w_icon.cooldown_prev, w_ref.cooldown_prev, tag .. ": " .. widgets[w].slot .. " swipe remaining")
            eq(w_icon.cooldown_set, w_ref.cooldown_set, tag .. ": " .. widgets[w].slot .. " swipe latch")
            eq(w_icon.cooldown.cooldown_sets or 0, w_ref.cooldown.sets or 0,
                tag .. ": " .. widgets[w].slot .. " swipe command count")
            eq(w_icon.cooldown.cooldown_duration, w_ref.cooldown.duration,
                tag .. ": " .. widgets[w].slot .. " swipe command length")
            eq(w_icon.cooldown.cooldown_start, w_ref.cooldown.start,
                tag .. ": " .. widgets[w].slot .. " swipe command anchor")
        end
    end
end

pST.in_combat = true
pST.mainhand = { speed = 3.0, ends_at = 0, start = 0, is_full = false }
pST.gcd = { expires = 0 }
pST.has_soc = false
pST.has_sob = false
pal.clock = 100

parity_tick("real", {
    { name = "reseal soc", inputs = { seal = "soc" },
        soc_expires = 130, soc_duration = 30 },
    { name = "cs override", inputs = { cs_remaining = 2.0, cs_duration = 4 } },
    { name = "blood ride", inputs = { seal = "sob", swing_remaining = 1.0,
        gcd_remaining = 0.5, cs_remaining = 6, melee_count = 3 },
        sob_expires = 128, sob_duration = 30 },
    { name = "judgement cue", inputs = { seal = "sob", swing_remaining = 3.0,
        gcd_remaining = 0, cs_remaining = 6, judge_remaining = 0.5, speed = 2.4,
        judge_duration = 5 },
        sob_expires = 126 },
    { name = "exorcism filler", inputs = { seal = "soc", gcd_remaining = 1.0,
        cs_remaining = 6, melee_count = 3, mana_pct = 40, creature_type = "Undead" },
        soc_expires = 129, soc_duration = 30 },
    { name = "consecration filler", inputs = { seal = "soc", gcd_remaining = 1.0,
        cs_remaining = 6, melee_count = 3, mana_pct = 50 },
        soc_expires = 1000 },   -- expired: the swipe clears through the seal path
    { name = "twist + padding", inputs = { seal = "soc", gcd_remaining = 0.7,
        swing_remaining = 1.0, cs_remaining = 0 } },
    { name = "cleared seals", inputs = { seal = "none", swing_remaining = 0.3,
        cs_remaining = 6 } },
    { name = "how execute", inputs = { seal = "soc", swing_remaining = 0.0,
        cs_remaining = 6, melee_count = 3, mana_pct = 50, era = true,
        cs_known = false, target_health_pct = 19, how_remaining = 0 },
        soc_expires = 130, soc_duration = 30 },
    { name = "how withheld at 20 pct", inputs = { seal = "soc", swing_remaining = 0.0,
        cs_remaining = 6, melee_count = 3, mana_pct = 50, era = true,
        cs_known = false, target_health_pct = 20, how_remaining = 0 },
        soc_expires = 130, soc_duration = 30 },
    { name = "shock hs lit", inputs = { fcfs_mode = "sod_shock", holy_power_stacks = 3,
        exo_remaining = 6, am_remaining = 6, hs_remaining = 0, cs_remaining = 6,
        am_rune_known = true, sod_libram_known = true },
        soc_expires = 130, soc_duration = 30 },
    { name = "shock am lit", inputs = { fcfs_mode = "sod_shock", holy_power_stacks = 3,
        exo_remaining = 6, am_remaining = 0, hs_remaining = 6, cs_remaining = 6,
        am_rune_known = true, sod_libram_known = true },
        soc_expires = 130, soc_duration = 30 },
    { name = "shock hs withheld", inputs = { fcfs_mode = "sod_shock",
        holy_power_stacks = 2, exo_remaining = 6, am_remaining = 0,
        hs_remaining = 0, cs_remaining = 0, am_rune_known = true,
        sod_libram_known = true },
        soc_expires = 130, soc_duration = 30 },
    { name = "unknown-state fallthrough", inputs = { seal = "soc", cs_remaining = 6,
        speed = 1.2, swing_remaining = 1.2, G = 1.5, melee_count = 4 } },
}, function(db, case)
    db.nextaction_show_fillers = case.name ~= "cs override"
    db.nextaction_show_judgement = case.name ~= "twist + padding"
    db.nextaction_hold_enabled = case.name ~= "cleared seals"
end)
pST.get_class_table().nextaction_show_fillers = true
pST.get_class_table().nextaction_show_judgement = true
pST.get_class_table().nextaction_hold_enabled = true

-- Idle parity: every widget target and every swipe clear matches the old idle branch.
pST.in_combat = false
pST.soc_expires = pal.clock + 20
pST.soc_duration = 30
pST.sob_expires = nil
pST.mainhand.ends_at = pal.clock + 3.0
pal.advance(0.1)
local idle_now = pal.clock
local idle_ref = {
    cs = 0, command = 0, blood = 0.5, twist = 0, judge = 0, hold = 0, consec = 0, exo = 0,
    how = 0, hs = 0, am = 0,
}
rec_set_icon_cooldown(ref_icons.cs, 0, 6, idle_now)
rec_set_icon_cooldown(ref_icons.judge, 0, 8, idle_now)
rec_set_icon_cooldown(ref_icons.command, 0, 30, idle_now)
rec_set_icon_cooldown(ref_icons.blood, 0, 30, idle_now)
pui.update(pST)
eq(ptarget("cs"), idle_ref.cs, "idle parity: cs icon")
eq(ptarget("soc"), idle_ref.command, "idle parity: command icon")
eq(ptarget("sob"), idle_ref.blood, "idle parity: blood opener at half alpha")
eq(ptarget("twist"), idle_ref.twist, "idle parity: twist icon")
eq(ptarget("judge"), idle_ref.judge, "idle parity: judge icon")
eq(pui.frame.hold.fade.target, idle_ref.hold, "idle parity: hold overlay")
eq(ptarget("consecration"), idle_ref.consec, "idle parity: consecration filler")
eq(ptarget("exorcism"), idle_ref.exo, "idle parity: exorcism filler")
eq(ptarget("how"), idle_ref.how, "idle parity: how filler")
eq(ptarget("holy_shock"), idle_ref.hs, "idle parity: holy_shock filler")
eq(ptarget("aura_mastery"), idle_ref.am, "idle parity: aura_mastery filler")
eq(pui.icons[pui.slot_index.soc].icon.cooldown_set, ref_icons.command.cooldown_set,
    "idle parity: command swipe cleared")
eq(pui.icons[pui.slot_index.soc].icon.cooldown.cooldown_sets or 0,
    ref_icons.command.cooldown.sets or 0, "idle parity: command swipe command count")
eq(pui.icons[pui.slot_index.sob].icon.cooldown_set, ref_icons.blood.cooldown_set,
    "idle parity: blood swipe cleared")
pST.in_combat = true

--=========================================================================================
-- 8b) The SoD strictSequence hard wait: the HOLD/RIDE overlay paints WAIT
--=========================================================================================
-- The engine publishes out.hard_wait (nextaction.lua), the paladin provider
-- feeds it and the frame owns the overlay: a held twist on a strict build
-- waits the swing out instead of filling, and the guide says so. Driven
-- through the REAL provider + frame (the scripted gather feeds the engine).
for k = 1, #SCRIPT_KEYS do
    scripted[SCRIPT_KEYS[k]] = nil
end
script("speed", 3.0)
script("swing_remaining", 0.5)
script("G", 1.5)
script("gcd_remaining", 0)
script("twist_window", 0.4)
script("reaction", 0.1)
script("cs_remaining", 6)
script("judge_remaining", 6)
script("seal", "sob")
script("cs_delay_max", 1.7)
script("waiting_judgement", false)
script("melee_count", 0)
script("mana_pct", 50)
script("creature_type", nil)
script("filler_remaining", 0)
script("strict_sequence", true)
pST.mainhand.ends_at = pal.clock + 3.0
pal.advance(0.1)
pui.update(pST)
eq(pui.frame.hold.fade.target, 1, "hard wait: the HOLD overlay lights")
eq(pui.frame.hold.text.text, "WAIT", "hard wait: the overlay reads WAIT")
-- The same state without the strict build keeps the archived text (the ride).
script("strict_sequence", nil)
pST.mainhand.ends_at = pal.clock + 3.0
pal.advance(0.1)
pui.update(pST)
eq(pui.frame.hold.fade.target, 1, "no hard wait: the overlay still lights")
eq(pui.frame.hold.text.text, "RIDE", "no hard wait: the overlay keeps the archived RIDE")
-- The hard wait adds no slot: the paladin frame still carries exactly ten.
eq(#pui.icons, 12, "hard wait: the paladin slot count stays twelve")

pST.PALADIN.guide.gather = real_gather

--=========================================================================================
-- 6) Rogue provider: gather -> evaluate -> frame parity over the real shared frame
--=========================================================================================
local ROGUE_MODULES = { "compat.lua", "utils.lua", "guard.lua", "druid_energy.lua", "nextaction.lua",
    "nextaction_ui.lua", "rogue_guide.lua", "classes/rogue.lua" }
-- Cold Blood fixture (test-owned id, never shipped): the wired F3/V-G5 slot
-- resolves through the client's own spell data like every other slot.
SPELL_INFOS[5116] = { name = "Cold Blood", icon = "i_cb" }
local rmain = build({ modules = ROGUE_MODULES, player_class = "ROGUE" })
local rST, rst = rmain.ST, rmain.st
local rui = rst.nextaction_ui
check(type(rst.rogue_guide) == "table", "the rogue pure engine loads beside the provider")
check(type(rST.ROGUE) == "table", "the rogue class module loads")
rmain.power = { [3] = 50, [4] = 0 }
rmain.st.api.UnitPower = function(_, power) return rmain.power[power or 0] end
rmain.st.api.UnitPowerMax = function() return 100 end
rmain.st.api.UnitAura = function() return nil end
rmain.st.api.UnitHealth = function() return nil end
rmain.st.api.GetSpellCooldown = function() return 0, 0, 0, 0 end
rmain.st.api.IsSpellUsable = function() return true, false end
rmain.st.api.is_spell_known = function() return true end
rmain.st.api.auras_may_be_secret = function() return false end

rST.ROGUE.post_init(rST)
check(rui.frame ~= nil, "the rogue provider creates the shared frame")
eq(#rui.icons, 11, "the rogue frame builds all eleven action slots")
local rogue_guide_by_key = {}
for i = 1, #rST.ROGUE.guide.slots do
    rogue_guide_by_key[rST.ROGUE.guide.slots[i].key] = rST.ROGUE.guide.slots[i]
end
for _, key in ipairs({ "snd", "ar", "bf", "coldblood" }) do
    check(rogue_guide_by_key[key] ~= nil and rogue_guide_by_key[key].spell_id ~= nil,
        "rogue guide: the " .. key .. " slot resolves from the client's spell data")
    check(rui.slot_index[key] ~= nil, "rogue guide: the frame indexes the " .. key .. " slot")
end
rST.in_combat = true
rST.mainhand = { speed = 2.6, start = 0, ends_at = 0, is_full = false }

-- One parity tick: the reference maps the provider's own frozen output exactly like the
-- frame's display_active does, then the real frame must agree icon-by-icon.
local function rogue_parity(label, energy, cp, clock, secret)
    rmain.power[3], rmain.power[4] = energy, cp
    rmain.clock = clock
    rST.mainhand.start = clock - 0.5
    rST.mainhand.ends_at = clock + 2.1
    rmain.st.api.auras_may_be_secret = function() return secret == true end
    rST.rogue_lust_at = nil

    local rg_gathered = rST.ROGUE.guide.gather(rST, {})
    local out = rST.ROGUE.guide.evaluate(rg_gathered, {})
    out.lust_unknown = rg_gathered.lust_unknown
    local expected = {}
    local expected_hold = 0
    local expected_hold_text
    if not out.inputs_unknown then
        if out.action and rui.slot_index[out.action] then
            expected[rui.slot_index[out.action]] = 1
        end
        if out.hold then
            expected_hold = 1
            expected_hold_text = out.hold_text or (out.riding and "NOW" or "POOL")
        end
    end

    rui.update(rST)
    for i = 1, #rui.icons do
        eq(rui.targets[i] ~= 0 and 1 or 0, expected[i] or 0,
            label .. ": slot " .. rui.icons[i].slot.key .. " target")
    end
    eq(rui.frame.hold.fade.target, expected_hold, label .. ": hold overlay")
    if expected_hold_text then
        eq(rui.frame.hold.text.text, expected_hold_text, label .. ": hold text")
    end
    if out.inputs_unknown then
        eq(rui.frame.label.text, "…", label .. ": unknown renders …")
    else
        check(rui.frame.label.text ~= "…", label .. ": known inputs clear the … label")
    end
    return out
end

local pool_out = rogue_parity("pool", 50, 0, 100)
eq(pool_out.hold, true, "parity case pool: the engine holds")
eq(pool_out.hold_text, "POOL", "parity case pool: the hold text is POOL")
local spend_out = rogue_parity("spend", 90, 0, 110)
eq(spend_out.action, "builder", "parity case spend: the engine spends (builder)")
eq(spend_out.riding, true, "parity case spend: the action rides")
rmain.class_db.rogue_ea_duty = true
local expose_out = rogue_parity("expose", 50, 0, 120)
eq(expose_out.action, "expose", "parity case expose: a due EA refresh prompts")
rmain.class_db.rogue_ea_duty = false
local unknown_out = rogue_parity("unknown", nil, 0, 130)
eq(unknown_out.inputs_unknown, true, "parity case unknown: unreadable energy is unknown")
local snd_out = rogue_parity("snd", 50, 5, 132)
eq(snd_out.action, "snd", "parity case snd: a missing SnD with CP prompts snd")
local ar_out = rogue_parity("ar", 30, 0, 134)
eq(ar_out.action, "ar", "parity case ar: low energy with AR ready prompts ar")
-- BF/Cold Blood need SnD riding: the sandbox aura stub answers nil by default,
-- so these two cases temporarily answer the SnD buff, then restore the stub.
local saved_aura = rmain.st.api.UnitAura
local saved_cd = rmain.st.api.GetSpellCooldown
rmain.st.api.UnitAura = function(unit, index)
    if unit == "player" and index == 1 then
        return "Slice and Dice", "i_snd", 1, nil, 30, rmain.clock + 20,
            nil, nil, nil, 5101
    end
    return nil
end
local bf_out = rogue_parity("bf", 90, 0, 136)
eq(bf_out.action, "bf", "parity case bf: SnD riding with BF ready prompts bf")
rmain.st.api.GetSpellCooldown = function(spell)
    if spell == 5111 or spell == "Blade Flurry" then
        return rmain.clock - 10, 300, 1, 1
    end
    return 0, 0, 0, 0
end
local cb_out = rogue_parity("cb", 90, 0, 138)
eq(cb_out.action, "coldblood", "parity case cb: SnD riding with BF cooling prompts Cold Blood")
rmain.st.api.UnitAura = saved_aura
rmain.st.api.GetSpellCooldown = saved_cd
local latch_out = rogue_parity("latch", 50, 0, 140, true)
eq(latch_out.lust_unknown, true, "parity case latch: the secret regime latches lust unknown")
eq(latch_out.inputs_unknown, true, "parity case latch: the latch owns the unknown bit")

-- R3 short-CD row + Cold Blood through the real provider (rogue parts only):
-- the slots resolve from the client's spell data, hide on a nil toggle (no
-- default-visible change), and the Kidney cooldown answers live.
eq(#rST.ROGUE.HUD_SLOTS, 13, "R3: the HUD declares eleven spell slots + two trinkets")
local r3_by_key = {}
for i = 1, #rST.ROGUE.HUD_SLOTS do
    r3_by_key[rST.ROGUE.HUD_SLOTS[i].key] = rST.ROGUE.HUD_SLOTS[i]
end
check(r3_by_key.kidney ~= nil and r3_by_key.kidney.spell ~= nil,
    "R3: Kidney Shot resolves from the client's spell data")
check(r3_by_key.restealth ~= nil and r3_by_key.restealth.spell ~= nil,
    "R3: Re-stealth resolves from the client's spell data (Vanish mapping UNCONFIRMED)")
check(r3_by_key.bandage ~= nil and r3_by_key.bandage.spell ~= nil,
    "R3: Bandage resolves from the client's spell data (rank UNCONFIRMED)")
eq(rST.ROGUE.get_hud_state(rST, r3_by_key.kidney, 150).hidden, true,
    "R3: a nil Kidney toggle hides (no default-visible change)")
eq(rST.ROGUE.get_hud_state(rST, r3_by_key.restealth, 150).hidden, true,
    "R3: a nil Re-stealth toggle hides")
eq(rST.ROGUE.get_hud_state(rST, r3_by_key.bandage, 150).hidden, true,
    "R3: a nil Bandage toggle hides")
check(r3_by_key.coldblood ~= nil and r3_by_key.coldblood.spell ~= nil,
    "Cold Blood: resolves from the client's spell data")
eq(rST.ROGUE.get_hud_state(rST, r3_by_key.coldblood, 150).hidden, true,
    "Cold Blood: a nil toggle hides (no default-visible change; widget/default filed)")

-- Degenerate inputs never error through the frame (contract robustness).
local degenerate = rST.ROGUE.guide.evaluate({}, {})
eq(degenerate.action, nil, "degenerate inputs produce no action")
eq(degenerate.inputs_unknown, true, "degenerate inputs render unknown")
local degenerate_ok = pcall(rui.update, rST)
check(degenerate_ok, "a degenerate frame tick does not error")

--=========================================================================================
-- 7) Shaman provider: the guide slots through the real frame
--=========================================================================================
-- The guide contract is per class: the shaman's own section pins its slot set.
-- This lane landed the two maintain slots (Lightning Shield S-19, Searing Totem
-- S-17) - the lines the drill/audit lanes filed as "practiced but never taught":
-- they carry a slot, a rule and a live feed, so the frame can show them.
local SHAMAN_MODULES = { "compat.lua", "utils.lua", "guard.lua", "nextaction_ui.lua",
    "shaman_guide.lua", "weave.lua", "classes/shaman.lua" }
local smain = build({ modules = SHAMAN_MODULES, player_class = "SHAMAN" })
local sST, sst = smain.ST, smain.st
check(type(sst.shaman_guide) == "table", "shaman contract: the pure engine loads beside the provider")
check(type(sST.SHAMAN.guide) == "table", "shaman contract: the class module loads")
check(type(sST.SHAMAN.guide.gather) == "function", "shaman contract: the guide has gather")
check(type(sST.SHAMAN.guide.evaluate) == "function", "shaman contract: the guide has evaluate")

sST.in_combat = true
sST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
sST.gcd = { expires = 0 }
-- The weave visuals ride the bars' visuals frame (main.lua owns it); the guide
-- contract needs no widget, so the stub answers nil (the shaman module skips
-- the widget work).
sST.get_visuals_frame = function() return nil end
sST.SHAMAN.post_init(sST)
local sui = sst.nextaction_ui
check(sui.frame ~= nil, "shaman contract: post_init builds the shared guide frame")
check(sui.inert ~= true, "shaman contract: the shaman provider is live")
eq(sui.get_provider(sST), sST.SHAMAN.guide, "shaman contract: the shaman guide is the frame's provider")

local sslots = sST.SHAMAN.guide.slots
eq(#sslots, 22, "shaman contract: twenty-two guide slots are declared")
eq(#sui.icons, 22, "shaman contract: the frame builds one icon per slot")
local sslot_keys = {}
for i = 1, #sslots do sslot_keys[sslots[i].key] = true end
check(sslot_keys.lightningshield == true, "shaman contract: the Lightning Shield slot is declared")
check(sslot_keys.searing == true, "shaman contract: the Searing Totem slot is declared")
check(sslot_keys.coe == true, "shaman contract: the Call of the Elements slot is declared")
-- The APL utility layer's four slots (bench/rotation_gap_vs_apl_2026-10-20.md §5).
check(sslot_keys.bloodlust == true, "shaman contract: the Bloodlust slot is declared")
check(sslot_keys.strength_of_earth == true,
    "shaman contract: the Strength of Earth Totem slot is declared")
check(sslot_keys.mana_spring == true,
    "shaman contract: the Mana Spring Totem slot is declared")
check(sslot_keys.frostshock == true, "shaman contract: the Frost Shock slot is declared")
for i = 1, #sslots do
    eq(sui.icons[i].slot, sslots[i], "shaman contract: icon " .. i .. " follows the slot order")
end
-- The two maintain slots resolve their icon from the client's own spell data
-- (the shipped ids are UNCONFIRMED, so the name is the probe).
local s_by_key = {}
for i = 1, #sslots do s_by_key[sslots[i].key] = sslots[i] end
eq(s_by_key.lightningshield.spell_id, 9201,
    "shaman contract: the Lightning Shield icon resolves from the client's own data")
eq(s_by_key.searing.spell_id, 9202,
    "shaman contract: the Searing Totem icon resolves from the client's own data")
eq(sui.icons[sui.slot_index.lightningshield].icon.texture.texture, "icon_ls",
    "shaman contract: the Lightning Shield icon shows the client's art")
eq(sui.icons[sui.slot_index.searing].icon.texture.texture, "icon_searing",
    "shaman contract: the Searing Totem icon shows the client's art")
-- Every action the engine can return names a declared slot (the contract rule).
local s_actions = {
    sst.shaman_guide.evaluate({ stormstrike_remaining = 0, flameshock_remaining = 10 }, {}).action,
    sst.shaman_guide.evaluate({ stormstrike_remaining = 8, flameshock_remaining = 10,
        firenova_remaining = 5, lightningshield_due = true }, {}).action,
}
local s_actions_ok = true
for i = 1, #s_actions do
    if s_actions[i] ~= nil and not sslot_keys[s_actions[i]] then s_actions_ok = false end
end
check(s_actions_ok, "shaman contract: every action the engine can return names a declared slot")
-- The HUD mirror: the two maintain slots are declared (they have a live read) and
-- hide until their toggle reads exactly true (nil = off - no default-visible
-- change; the options pass owns the default + the widget).
eq(#sST.SHAMAN.HUD_SLOTS, 11, "shaman contract: the HUD declares nine ability slots + two trinkets")
local s_hud_by_key = {}
for i = 1, #sST.SHAMAN.HUD_SLOTS do
    s_hud_by_key[sST.SHAMAN.HUD_SLOTS[i].key] = sST.SHAMAN.HUD_SLOTS[i]
end
check(s_hud_by_key.lightningshield ~= nil, "shaman contract: the HUD declares the Lightning Shield slot")
check(s_hud_by_key.searing ~= nil, "shaman contract: the HUD declares the Searing Totem slot")
check(s_hud_by_key.coe ~= nil, "shaman contract: the HUD declares the Call of the Elements slot")
eq(sST.SHAMAN.get_hud_state(sST, s_hud_by_key.lightningshield, 10).hidden, true,
    "shaman contract: a nil Lightning Shield toggle hides the mirror")
eq(sST.SHAMAN.get_hud_state(sST, s_hud_by_key.searing, 10).hidden, true,
    "shaman contract: a nil Searing toggle hides the mirror")
eq(sST.SHAMAN.get_hud_state(sST, s_hud_by_key.coe, 10).hidden, true,
    "shaman contract: a nil Call of the Elements toggle hides the mirror")

--=========================================================================================
-- F10: the guide's compute isolation is the shared guard (one implementation)
--=========================================================================================
do
    local f = assert(io.open(ROOT .. "nextaction_ui.lua", "r"))
    local src = f:read("*a")
    f:close()
    check(src:find("st.guard.run", 1, true) ~= nil,
        "the guide isolates a throwing provider through the shared guard")
    check(src:find("QUARANTINE_THROWS = ", 1, true) == nil,
        "the guide keeps no second quarantine threshold")
    check(src:find("errors.by_site", 1, true) == nil,
        "the guide keeps no second counter bookkeeping")
    check(src:find('st.guard.label("nextaction", "Next action")', 1, true) ~= nil,
        "the guide wording stays at the call site")
end

--=========================================================================================
-- NILSWEEP (2026-10-22): the guide's per-frame update and settings apply with no class
-- row. No row means no guide settings: the frame hides, never a nil read out of
-- should_show/apply_settings. The unguarded code throws, so each leg is red-first.
--=========================================================================================
do
    local nk = build()
    local nST, nUI = nk.ST, nk.st.nextaction_ui
    nST.WARRIOR = { guide = fake_provider() }
    nST.in_combat = true
    nST.mainhand = { speed = 3.0, ends_at = 3.0, start = 0.0, is_full = false }
    nUI.init(nST)
    check(nUI.frame ~= nil, "fixture: the guide frame built")
    nST.get_class_table = function() return nil end
    nUI.frame:Show()
    -- Pass the throttled compute gate: the visibility check runs on a compute tick.
    nUI.last_compute = -1
    local g1ok, g1err = pcall(nUI.update, nST)
    check(g1ok, "NILSWEEP G1 update tolerates a missing class row (error: " .. tostring(g1err) .. ")")
    eq(nUI.frame:IsShown(), false, "NILSWEEP G1 update hides the guide without a class row")
    nUI.frame:Show()
    local g2ok, g2err = pcall(nUI.apply_settings, nST)
    check(g2ok, "NILSWEEP G2 apply_settings tolerates a missing class row (error: " .. tostring(g2err) .. ")")
    eq(nUI.frame:IsShown(), false, "NILSWEEP G2 apply_settings hides the guide without a class row")
end

if failures == 0 then
    print("PASS  guide_contract.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  guide_contract.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end

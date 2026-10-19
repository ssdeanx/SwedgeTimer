-- tests/rogue_state.lua: offline tests for the rogue class module (classes/rogue.lua)
-- over the real compat.lua + utils.lua + druid_energy.lua + rogue_guide.lua +
-- nextaction_ui.lua + hud.lua in a sandbox.
--
-- Round 2 pins (all behaviour outcomes, not "runs-without-error"):
--   * every shipped TOC lists classes\rogue.lua after classes\warrior.lua and
--     rogue_guide.lua in the guide group before practice.lua/main.lua,
--   * the module exposes the class hooks; the source ships no remembered ids and the
--     slot ids are resolved from the client's own spell data at post_init,
--   * ST.ROGUE.defaults is nil-safe/off-by-default and the shipped HUD/guide keys are
--     documented data (source pins over config_presets.lua),
--   * the proc-aware tick predictor: seed on a +20 gain, re-anchor only in phase,
--     Combat Potency 15 / Relentless 25 never re-anchor, unknown grants and missed
--     ticks read nil/hidden (H4), the cap phase advances without a gain,
--   * the tick spark + 65/85 pooling wash (data-driven bands; hidden on unknown),
--   * the Era-only SS window (Era + sword shows; TBC/Wrath/Forever/Retail, dagger,
--     unknown weapon and option-off hide), the swap tint with the GCD+reset copy,
--     and the MH/OH poison reminder (presence only),
--   * the live HUD provider (SnD/Rupture/EA/AR/BF/Tea/Kick + the secret-regime
--     unknown render), the live guide gather (inputs_unknown ownership + the M5
--     lust-unknown latch + the "…" frame render), and the TTD EMA with the M7
--     provenance refusal,
--   * on_combat_exit preserves the mainhand swing record object/fields (G4 mirror),
--   * the hooks stay throw-safe with both shared consumers absent.
-- Run from the repo root: lua5.1 tests/rogue_state.lua  (any cwd works).

local script_dir = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = script_dir .. "/../"

local checks, failures = 0, 0
local function check(cond, label)
    checks = checks + 1
    if not cond then failures = failures + 1; print("FAIL  " .. label) end
end
local function eq(got, want, label)
    checks = checks + 1
    if got ~= want then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end
local function read_file(path)
    local f = assert(io.open(ROOT .. path, "r"))
    local text = f:read("*a")
    f:close()
    return text:gsub("\r\n", "\n")
end

--=========================================================================================
-- Frame stubs (shared by nextaction_ui.lua and hud.lua)
--=========================================================================================
local function make_fontstring()
    local f = { hidden = false }
    function f:SetPoint() end
    function f:SetJustifyH() end
    function f:SetShadowColor() end
    function f:SetShadowOffset() end
    function f:SetFont(path, size, flags) f.font = { path, size, flags }; return true end
    function f:GetFont() return f.font and f.font[1], f.font and f.font[2], f.font and f.font[3] end
    function f:SetText(text) f.text = text; f.set_text_calls = (f.set_text_calls or 0) + 1 end
    function f:SetTextColor(r, g, b, a) f.color = { r, g, b, a } end
    function f:SetWidth(w) f.width = w end
    function f:SetHeight(h) f.height = h end
    function f:SetAlpha(a) f.alpha = a end
    function f:Hide() f.hidden = true end
    function f:Show() f.hidden = false end
    function f:IsShown() return not f.hidden end
    return f
end

local function make_texture()
    local t = { hidden = true }
    function t:SetAllPoints() end
    function t:SetPoint() end
    function t:SetTexCoord(l, r, top, bottom) t.texcoord = { l, r, top, bottom } end
    function t:SetTexture(tex) t.texture = tex end
    function t:SetColorTexture() end
    function t:SetVertexColor(r, g, b, a) t.color = { r, g, b, a } end
    function t:SetDrawLayer() end
    function t:SetWidth(w) t.width = w end
    function t:SetHeight(h) t.height = h end
    function t:SetAlpha(a) t.alpha = a end
    function t:Hide() t.hidden = true end
    function t:Show() t.hidden = false end
    function t:IsShown() return not t.hidden end
    return t
end

local function make_frame(name)
    local f = { name = name, shown = false }
    function f:SetSize(w, h) f.width, f.height = w, h end
    function f:GetWidth() return f.width or 0 end
    function f:GetHeight() return f.height or 0 end
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
    function f:RegisterEvent(event)
        f.events = f.events or {}
        f.events[event] = true
    end
    function f:UnregisterEvent(event)
        if f.events then f.events[event] = nil end
    end
    function f:Show() f.shown = true end
    function f:Hide() f.shown = false end
    function f:IsShown() return f.shown end
    function f:SetAlpha(a) f.alpha = a end
    function f:GetAlpha() return f.alpha or 1 end
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
    function f:SetDrawEdge(flag) f.draw_edge = flag end
    function f:SetDrawSwipe(flag) f.draw_swipe = flag end
    function f:SetSwipeColor(r, g, b, a) f.swipe_color = { r, g, b, a } end
    function f:SetAllPoints() end
    return f
end

--=========================================================================================
-- Sandbox builder
--=========================================================================================
-- Fixture spell data: ids are test-owned (never shipped by the addon) so the resolver can
-- be pinned in both directions - a name that answers, and one that does not.
local ROGUE_SPELLS_BY_ID = {
    [101] = { name = "Slice and Dice", icon = "i_snd" },
    [102] = { name = "Rupture", icon = "i_rupture" },
    [103] = { name = "Expose Armor", icon = "i_ea" },
    [104] = { name = "Adrenaline Rush", icon = "i_ar" },
    [105] = { name = "Blade Flurry", icon = "i_bf" },
    [106] = { name = "Thistle Tea", icon = "i_tea" },
    [107] = { name = "Kick", icon = "i_kick" },
    [108] = { name = "Sinister Strike", icon = "i_ss" },
    [109] = { name = "Eviscerate", icon = "i_evisc" },
    [110] = { name = "Envenom", icon = "i_env" },
    [111] = { name = "Shiv", icon = "i_shiv" },
    [112] = { name = "Deadly Poison", icon = "i_deadly" },
}
local ROGUE_SPELLS_BY_NAME = {}
for id, entry in pairs(ROGUE_SPELLS_BY_ID) do
    ROGUE_SPELLS_BY_NAME[entry.name] = id
end
local ROGUE_ITEM_INFO = {
    [90001] = { subclass = "Sword" },
    [90002] = { subclass = "Dagger" },
}

-- One throwaway client profile per call: a fresh environment (a metatable over _G), the
-- real modules in TOC order, then classes/rogue.lua on top. The fixture class_db mirrors
-- the shipped ROGUE defaults + the shared class defaults (the behaviour pins rely on the
-- documented OFF values).
local function build(opts)
    opts = opts or {}
    local sb = {
        clock = opts.clock or 0,
        frames = 0,
        power = { [3] = 0, [4] = 0 },
    }

    local env = setmetatable({}, { __index = _G })
    env.WOW_PROJECT_ID = opts.project or 5
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    env.WOW_PROJECT_FOREVER = 18
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    env.GetLocale = function() return "enUS" end
    env.GetBuildInfo = function() return "0.0.0", "00000", "today", 20506 end
    env.GetTime = function() return sb.clock end
    env.GetTimePreciseSec = function() return sb.clock end
    env.UIParent = make_frame("UIParent")
    env.UIParent.GetCenter = function() return 0, 0 end
    env.CreateFrame = function(...)
        sb.frames = sb.frames + 1
        return make_frame(select(2, ...))
    end
    -- Real spell data by name: the module resolves every slot id through the client's
    -- own GetSpellInfo (names, never remembered ids), so the fixture answers both.
    env.GetSpellInfo = function(spell)
        local id
        if type(spell) == "number" then
            id = ROGUE_SPELLS_BY_ID[spell] and spell or nil
        else
            id = ROGUE_SPELLS_BY_NAME[spell]
        end
        local entry = id and ROGUE_SPELLS_BY_ID[id]
        if not entry then
            return nil
        end
        return entry.name, nil, entry.icon, 0, 0, 0, id
    end
    env.GetSpellCooldown = function(spell)
        local cd = sb.spell_cd and sb.spell_cd[spell]
        if cd then
            return cd[1], cd[2], 1, 1
        end
        return 0, 0, 0, 0
    end
    env.GetSpellBaseCooldown = function() return 0 end
    env.IsSpellKnown = function(spell)
        return sb.known == nil or sb.known[spell] ~= false
    end
    env.IsSpellUsable = function(spell)
        if sb.usable and sb.usable[spell] ~= nil then
            return sb.usable[spell], false
        end
        return true, false
    end
    env.IsSpellInRange = function() return nil end
    env.UnitExists = function() return false end
    env.UnitPower = function(_, power)
        return sb.power and sb.power[power or 0] or nil
    end
    env.UnitPowerMax = function(_, power)
        return (sb.power_max and sb.power_max[power or 0]) or 100
    end
    env.UnitAura = function(unit, index)
        local list = sb.auras and sb.auras[unit]
        local a = list and list[index]
        if not a then
            return nil
        end
        return a.name, a.icon or "icon", a.count, nil, a.duration, a.expiration,
            nil, nil, nil, a.spell_id
    end
    env.UnitHealth = function(unit)
        return sb.health and sb.health[unit] or nil
    end
    env.UnitGUID = function(unit)
        return sb.guid and sb.guid[unit] or nil
    end
    env.GetInventoryItemID = function(_, slot)
        return sb.items and sb.items[slot] or nil
    end
    env.GetInventoryItemTexture = function() return nil end
    env.GetInventoryItemCooldown = function() return 0, 0, 1 end
    env.GetItemInfo = function(item)
        local info = ROGUE_ITEM_INFO[item]
        if not info then
            return nil
        end
        return "Item " .. tostring(item), nil, 2, 1, 1, "Weapon", info.subclass
    end
    env.GetWeaponEnchantInfo = function()
        if sb.weapon_enchant_present == false then
            return nil
        end
        return sb.mh_poison ~= false, 3600, nil, sb.oh_poison ~= false, 3600, nil
    end
    env.GetItemCount = function()
        if sb.tea_count == nil then
            return 1
        end
        return sb.tea_count
    end
    env.GetItemCooldown = function(info)
        local cd = sb.tea_cd
        if info ~= "Thistle Tea" or not cd then
            return 0, 0, 1
        end
        return cd[1], cd[2], 1
    end
    env.InCombatLockdown = function() return opts.lockdown == true end
    env.C_EventUtils = { IsEventValid = function() return false end }

    local ST = {
        ROGUE = {},
        player_class = "ROGUE",
        interfaces_are_initialised = true,
        in_combat = false,
        gcd = {},
        db = { profile = { enabled = true } },
    }
    -- Shipped ROGUE defaults (config_presets.lua) + the shared class defaults that the
    -- HUD and the guide read. The source pins in section 2 keep this fixture honest.
    local class_db = {
        show_rogue_energy_tick = false,
        rogue_energy_tick_color = { 255, 209, 64, 0.90 },
        show_rogue_pool_tint = false,
        rogue_pool_tint_color = { 255, 128, 0, 0.85 },
        rogue_pool_band_pre = 65,
        rogue_pool_band_post = 85,
        show_rogue_snd_cue = false,
        rogue_snd_color = { 255, 209, 64, 0.90 },
        show_rogue_rupture_cue = false,
        rogue_rupture_color = { 214, 64, 54, 0.90 },
        show_rogue_ea_cue = false,
        rogue_ea_color = { 140, 89, 38, 0.90 },
        show_rogue_shiv_cue = false,
        rogue_shiv_color = { 89, 140, 191, 0.90 },
        show_rogue_tea_cue = false,
        rogue_tea_color = { 112, 8, 11, 0.90 },
        nextaction_enabled = false,
        nextaction_locked = true,
        nextaction_visibility_key = "in_combat",
        nextaction_icon_size = 45,
        nextaction_x = 0,
        nextaction_y = -180,
        hud_show_snd = true,
        hud_show_rupture = true,
        hud_show_ea = true,
        hud_show_ar = true,
        hud_show_bf = true,
        hud_show_tea = true,
        hud_show_kick = true,
        hud_show_trinket1 = true,
        hud_show_trinket2 = true,
        hud_enabled = false,
        hud_visibility_key = "always",
        hud_locked = true,
        hud_x = 0,
        hud_y = -236,
        hud_scale = 1,
        hud_icon_size = 36,
        hud_match_bar_width = false,
        hud_spacing = 2,
        hud_orientation = "horizontal",
        hud_show_text = true,
        hud_font = "Expressway",
        hud_text_size = 16,
        hud_text_outline = "outline",
        hud_text_color = { 250, 255, 0, 1 },
        hud_text_warn_color = { 255, 102, 107, 1 },
        hud_border_size = 2,
        hud_border_color = { 0, 0, 0, 1 },
        hud_glow_enabled = true,
        hud_desaturate = true,
        hud_mana_tint = true,
        hud_range_tint = true,
    }
    function ST.get_class_table() return class_db end
    function ST.get_hand_table() return { bar_width = 275, border_width = 2 } end
    function ST.convert_color(_, t) return t[1] / 255, t[2] / 255, t[3] / 255, t[4] end
    -- The mainhand visuals frame the rogue widgets are drawn on (bars.lua's frame in the
    -- real client; a plain stub here with recordable textures/fontstrings).
    local visuals = make_frame("RogueVisuals")
    function ST.get_visuals_frame(hand)
        if hand == "mainhand" then
            return visuals
        end
        return nil
    end
    function ST.get_bar_visuals_width_and_height(hand)
        return 200, 18
    end
    sb.class_db = class_db
    sb.visuals = visuals

    local LCG = {}
    function LCG.PixelGlow_Start() end
    function LCG.PixelGlow_Stop() end
    local LSM = {}
    function LSM.Fetch(_, mediatype)
        if mediatype == "font" then return "Fonts\\FRIZQT__.TTF" end
        if mediatype == "border" then return "border_tex" end
        return nil
    end
    function LSM.HashTable() return {} end
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

    -- compat.lua reads several legacy globals through _G; mirror every sandbox stub for
    -- the duration of its load, then restore _G exactly.
    local mirrored = {}
    for name, value in pairs(env) do
        mirrored[name] = rawget(_G, name)
        _G[name] = value
    end

    local st = {}
    local modules = {
        "compat.lua", "utils.lua", "druid_energy.lua", "rogue_guide.lua",
        "nextaction.lua", "nextaction_ui.lua", "hud.lua", "classes/rogue.lua",
    }
    for i = 1, #modules do
        local chunk = assert(loadfile(ROOT .. modules[i]))
        setfenv(chunk, env)
        chunk("SwedgeTimer", st)
    end

    for name, previous in pairs(mirrored) do
        _G[name] = previous
    end

    sb.env, sb.st, sb.ST = env, st, ST
    return sb
end

--=========================================================================================
-- 1) Load order: every shipped TOC lists the class + its pure guide in the right place
--=========================================================================================
local TOCS = {
    "SwedgeTimer.toc", "SwedgeTimer_Vanilla.toc", "SwedgeTimer_TBC.toc",
    "SwedgeTimer_Wrath.toc", "SwedgeTimer_Cata.toc", "SwedgeTimer_Mists.toc",
    "SwedgeTimer_Mainline.toc",
}
for i = 1, #TOCS do
    local toc = TOCS[i]
    local text = read_file(toc)
    local class_at = text:find("classes\\rogue.lua", 1, true)
    local warrior_at = text:find("classes\\warrior.lua", 1, true)
    local guide_at = text:find("rogue_guide.lua", 1, true)
    local hunter_guide_at = text:find("hunter_guide.lua", 1, true)
    local practice_at = text:find("practice.lua", 1, true)
    local main_at = text:find("\nmain.lua", 1, true)
    check(class_at ~= nil, toc .. ": lists classes\\rogue.lua")
    check(warrior_at ~= nil and class_at ~= nil and class_at > warrior_at,
        toc .. ": classes\\rogue.lua loads after classes\\warrior.lua")
    check(guide_at ~= nil, toc .. ": lists rogue_guide.lua")
    check(guide_at ~= nil and hunter_guide_at ~= nil and guide_at > hunter_guide_at,
        toc .. ": rogue_guide.lua sits after hunter_guide.lua")
    check(guide_at ~= nil and practice_at ~= nil and main_at ~= nil
            and guide_at < practice_at and guide_at < main_at,
        toc .. ": rogue_guide.lua loads before practice.lua/main.lua")
end

--=========================================================================================
-- 2) Defaults source pins: nil-safe/off-by-default shape, HUD master still off
--=========================================================================================
do
    local presets = read_file("config_presets.lua")
    local block = presets:match("ST%.ROGUE%.defaults%s*=%s*{(.-)\n%}")
    check(block ~= nil, "config_presets.lua: the ROGUE defaults block is found")
    block = block or ""
    local function ships_true(key)
        return block:find("%f[%a_]" .. key .. "%s*=%s*true") ~= nil
    end
    local function ships_false(key)
        return block:find("%f[%a_]" .. key .. "%s*=%s*false") ~= nil
    end
    for _, key in ipairs({
        "show_rogue_energy_tick", "show_rogue_pool_tint", "show_rogue_snd_cue",
        "show_rogue_rupture_cue", "show_rogue_ea_cue", "show_rogue_shiv_cue",
        "show_rogue_tea_cue", "nextaction_enabled",
    }) do
        check(ships_false(key), "ROGUE defaults: " .. key .. " ships false (nil = off)")
    end
    for _, key in ipairs({
        "hud_show_snd", "hud_show_rupture", "hud_show_ea", "hud_show_ar",
        "hud_show_bf", "hud_show_tea", "hud_show_kick", "hud_show_trinket1",
        "hud_show_trinket2",
    }) do
        check(ships_true(key), "ROGUE defaults: " .. key .. " ships true (master off)")
    end
    check(block:find("nextaction_locked%s*=%s*true") ~= nil,
        "ROGUE defaults: nextaction_locked ships true")
    check(block:find('nextaction_visibility_key%s*=%s*"in_combat"') ~= nil,
        "ROGUE defaults: nextaction_visibility_key ships in_combat")
    check(block:find("nextaction_icon_size%s*=%s*45") ~= nil,
        "ROGUE defaults: nextaction_icon_size ships 45")
    check(block:find("rogue_pool_band_pre%s*=%s*65") ~= nil,
        "ROGUE defaults: the pre-tick pooling band ships 65")
    check(block:find("rogue_pool_band_post%s*=%s*85") ~= nil,
        "ROGUE defaults: the post-tick pooling band ships 85")

    -- Colour tables: 0-255 RGB + 0-1 alpha, the addon's storage convention.
    local function colour_values(key)
        local r, g, b, a = block:match("%f[%a_]" .. key .. "%s*=%s*{%s*(%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*([%d%.]+)%s*}")
        if not r then return nil end
        return { tonumber(r), tonumber(g), tonumber(b), tonumber(a) }
    end
    for _, key in ipairs({
        "rogue_energy_tick_color", "rogue_pool_tint_color", "rogue_snd_color",
        "rogue_rupture_color", "rogue_ea_color", "rogue_shiv_color", "rogue_tea_color",
    }) do
        local c = colour_values(key)
        check(c ~= nil, "ROGUE defaults: " .. key .. " is a colour table")
        if c then
            local in_range = c[1] <= 255 and c[2] <= 255 and c[3] <= 255
                and c[4] >= 0 and c[4] <= 1
            check(in_range, "ROGUE defaults: " .. key .. " uses 0-255 RGB + 0-1 alpha")
        end
    end

    local class_defaults = presets:match("ST%.class_defaults%s*=%s*{(.-)\n%}") or ""
    check(class_defaults:find("hud_enabled%s*=%s*false") ~= nil,
        "shared defaults: the HUD master hud_enabled still ships false")
    check(class_defaults:find("rotation_label_enabled%s*=%s*false") ~= nil,
        "shared defaults: rotation_label_enabled still ships false")
end

--=========================================================================================
-- 2b) Options source pins: the ROGUE class panel exists and exposes the shipped keys
--=========================================================================================
do
    local options = read_file("option_tables.lua")
    check(options:find("function ST%.class_opts_funcs%.ROGUE%(self%)") ~= nil,
        "option_tables.lua: the ROGUE class panel is defined")
    for _, key in ipairs({
        "show_rogue_energy_tick", "rogue_energy_tick_color", "show_rogue_pool_tint",
        "rogue_pool_tint_color", "rogue_pool_band_pre", "rogue_pool_band_post",
        "show_rogue_snd_cue", "rogue_snd_color", "show_rogue_rupture_cue",
        "rogue_rupture_color", "show_rogue_ea_cue", "rogue_ea_color",
        "show_rogue_shiv_cue", "rogue_shiv_color", "show_rogue_tea_cue",
        "rogue_tea_color", "nextaction_enabled", "nextaction_locked",
        "nextaction_visibility_key", "nextaction_icon_size", "nextaction_x",
        "nextaction_y", "hud_show_snd", "hud_show_rupture", "hud_show_ea",
        "hud_show_ar", "hud_show_bf", "hud_show_tea", "hud_show_kick",
        "hud_show_trinket1", "hud_show_trinket2",
    }) do
        check(options:find("%f[%a_]" .. key .. "%s*=%s*{") ~= nil
                or options:find('"' .. key .. '"', 1, true) ~= nil,
            "ROGUE options: " .. key .. " has a widget")
    end
end

--=========================================================================================
-- 3) Module surface + the empty-id / no-hook rules
--=========================================================================================
local base = build()
local ST = base.ST
check(type(ST.ROGUE) == "table", "classes/rogue.lua defines ST.ROGUE")
for _, hook in ipairs({ "post_init", "on_bar_update", "on_combat_exit", "get_hud_state",
    "gather_guide_inputs" }) do
    check(type(ST.ROGUE[hook]) == "function", "ROGUE." .. hook .. " is defined")
end
check(type(ST.ROGUE.guide) == "table", "ST.ROGUE.guide exists")
check(type(ST.ROGUE.guide.gather) == "function", "the guide provider has gather")
check(type(ST.ROGUE.guide.evaluate) == "function", "the guide provider has evaluate")
check(type(ST.ROGUE.guide.slots) == "table", "the guide provider declares slots")
eq(ST.ROGUE.on_spellcast_event, nil, "the module registers no spellcast handler (no casts consumed)")
eq(ST.ROGUE.on_spellcast_succeeded, nil, "the module registers no spellcast success handler")
eq(ST.ROGUE.COMBAT_LOG_EVENT_UNFILTERED, nil, "the module registers no CLEU handler (R1: no ids)")
check(ST.ROGUE.SPELL_IDS ~= nil and next(ST.ROGUE.SPELL_IDS) == nil,
    "the spell id table ships empty (no remembered ids)")
check(ST.ROGUE.POISON_IDS ~= nil and next(ST.ROGUE.POISON_IDS) == nil,
    "the poison id table ships empty (no remembered ids)")

local hud_slots = ST.ROGUE.HUD_SLOTS
check(type(hud_slots) == "table", "ST.ROGUE.HUD_SLOTS exists")
local hud_expected = { "snd", "rupture", "ea", "ar", "bf", "tea", "kick",
    "trinket1", "trinket2" }
eq(#hud_slots, #hud_expected, "the HUD declares the nine teardown slots")
local hud_order_ok = true
local hud_ids_empty = true
local slot_by_key = {}
for i = 1, #hud_slots do
    local slot = hud_slots[i]
    slot_by_key[slot.key] = slot
    if slot.key ~= hud_expected[i] then hud_order_ok = false end
    if slot.kind == "spell" and (slot.spell ~= nil or slot.texture ~= nil) then
        hud_ids_empty = false
    end
end
check(hud_order_ok, "the HUD slot order is the documented teardown order")
check(hud_ids_empty, "spell slots carry no remembered source id (resolved at init)")
eq(slot_by_key.trinket1.inv_slot, 13, "trinket 1 reads inventory slot 13")
eq(slot_by_key.trinket2.inv_slot, 14, "trinket 2 reads inventory slot 14")

local guide_slots = ST.ROGUE.guide.slots
local guide_expected = { "builder", "rupture", "eviscerate", "envenom", "expose",
    "shiv", "tea" }
eq(#guide_slots, #guide_expected, "the guide declares the seven rogue action slots")
local guide_order_ok, guide_ids_empty = true, true
for i = 1, #guide_slots do
    if guide_slots[i].key ~= guide_expected[i] then guide_order_ok = false end
    if guide_slots[i].spell_id ~= nil then guide_ids_empty = false end
end
check(guide_order_ok, "the guide slot keys match the pure engine's action names")
check(guide_ids_empty, "guide slots carry no remembered spell ids (resolved at init)")
eq(ST.ROGUE.guide.labels.hold, "POOL", "the hold label is POOL")
eq(ST.ROGUE.guide.labels.ride, "NOW", "the ride label is NOW")

-- Round 2 surface + data pins.
for _, fn in ipairs({ "update_energy_tick", "sample_energy_tick", "get_time_to_die",
    "update_lust_state", "apply_spell_ids", "setup_rogue_visuals",
    "update_rogue_visuals" }) do
    check(type(ST.ROGUE[fn]) == "function", "ROGUE." .. fn .. " is defined")
end
eq(ST.ROGUE.TICK_PERIOD, 2.0, "the tick period is the classic 2 s")
eq(ST.ROGUE.TICK_ENERGY, 20, "one tick grants 20")
eq(ST.ROGUE.TICK_GAIN_TOLERANCE, 0.4, "the in-phase tolerance is pinned")
eq(ST.ROGUE.PROC_ENERGY_GAINS[15], true, "Combat Potency 15 is a known proc grant")
eq(ST.ROGUE.PROC_ENERGY_GAINS[25], true, "Relentless Strikes 25 is a known proc grant")
eq(ST.ROGUE.PROC_ENERGY_GAINS[20], nil, "a 20-energy gain is never a proc grant")
eq(ST.ROGUE.SS_WINDOW_FAMILY, "ERA", "the SS window is family-gated to ERA")
eq(ST.ROGUE.SS_WINDOW_START, 0.1, "the SS window opens 0.1 s after the swing")
eq(ST.ROGUE.SS_WINDOW_END, 0.2, "the SS window closes 0.2 s after the swing")
eq(ST.ROGUE.SWAP_CUE_FAMILIES.ERA, true, "Era keeps the swap cue")
eq(ST.ROGUE.SWAP_CUE_FAMILIES.TBC, true, "TBC keeps the swap cue")
eq(ST.ROGUE.SWAP_CUE_FAMILIES.WRATH, nil, "Wrath ships no swap cue (recorded conflict)")
eq(ST.ROGUE.SWAP_CUE_FAMILIES.RETAIL, nil, "Retail ships no swap cue")
eq(ST.ROGUE.TTD_PROVENANCE, "own-ema", "the TTD provenance is the module's own EMA")

-- M7 provenance static pins: the TTD path must never consume the enemy-swing fallback.
local rogue_src = read_file("classes/rogue.lua")
check(rogue_src:find("self.enemy", 1, true) == nil,
    "M7: the TTD path never reads an enemy cycle")
check(rogue_src:find("enemy_cycle", 1, true) == nil,
    "M7: the TTD path never names the enemy cycle")
check(rogue_src:find("st.druid_energy", 1, true) ~= nil,
    "the TTD reuses the druid D4 module")

--=========================================================================================
-- 4) HUD: silent until enabled; the provider answers the cleared nil-state
--=========================================================================================
do
    local sb = build()
    local ST2, st2 = sb.ST, sb.st
    local HUD = st2.hud
    check(type(HUD) == "table", "hud.lua defines st.hud")

    ST2.ROGUE.post_init(ST2)
    check(HUD.frame ~= nil, "post_init creates the HUD frame")
    -- The spell slots are skipped by hud.lua's descriptor validation until the in-client
    -- fill supplies ids; only the two self-served trinket slots render.
    eq(#HUD.icons, 2, "only the two trinket slots are renderable before the id fill")
    eq(HUD.should_show(ST2), false, "the HUD stays hidden with the shipped master default")
    eq(HUD.frame:IsShown(), false, "the HUD frame is not shown before it is enabled")
    HUD.on_update(ST2, 1)
    eq(HUD.frame:IsShown(), false, "a HUD tick stays invisible until enabled")

    local state = ST2.ROGUE.hud_state
    local fields = { "remaining", "duration", "start", "reverse", "text_remaining",
        "desaturate", "usable", "in_range", "glow", "count", "texture", "hidden" }
    local stale_cleared = true
    local same_table = true
    for i = 1, #ST2.ROGUE.HUD_SLOTS do
        local slot = ST2.ROGUE.HUD_SLOTS[i]
        for j = 1, #fields do state[fields[j]] = "stale" end
        local s = ST2.ROGUE.get_hud_state(ST2, slot, sb.clock)
        if s ~= state then same_table = false end
        for j = 1, #fields do
            if s[fields[j]] ~= nil then stale_cleared = false end
        end
    end
    check(same_table, "get_hud_state reuses one table (no per-tick allocation)")
    check(stale_cleared, "get_hud_state clears every contract field on every call")
    eq(HUD.validate_slot(ST2.ROGUE.HUD_SLOTS[1], true), false,
        "a spell slot with no id yet is rejected (silent no-op)")
    eq(HUD.validate_slot(ST2.ROGUE.HUD_SLOTS[8], true), true,
        "a trinket slot remains valid without a provider entry")

    -- Enabling the master is still safe: the row becomes visible, but the unfilled spell
    -- slots stay skipped (only the trinkets exist). This is the documented pre-fill shape.
    sb.class_db.hud_enabled = true
    eq(HUD.should_show(ST2), true, "enabling the master makes the HUD eligible")
end

--=========================================================================================
-- 5) Guide provider: unknown inputs, "…" through the real frame, hidden while disabled
--=========================================================================================
do
    local sb = build()
    local ST2, st2 = sb.ST, sb.st
    local ui = st2.nextaction_ui
    ST2.ROGUE.post_init(ST2)
    check(ui.frame ~= nil, "post_init creates the shared guide frame")
    eq(#ui.icons, 7, "the shared frame builds all seven rogue slots")
    eq(ui.should_show(ST2), false, "the guide stays hidden with the shipped OFF default")

    -- Provider-contract pins: caller-owned tables, no allocations, unknown on every tick.
    local gathered = { speed = 2.6, swing_remaining = 1.2 }
    local out = { action = "builder", hold = true, hold_text = "X",
        filler_slot = "rupture", judge_slot = "eviscerate", rotation_key = "old",
        waiting_judgement = true, inputs_unknown = false }
    local got = ST2.ROGUE.gather_guide_inputs(ST2, gathered)
    check(got == gathered, "gather writes into the caller-owned table")
    eq(gathered.inputs_unknown, true, "gather reports inputs_unknown")
    local eval_out = ST2.ROGUE.guide.evaluate(gathered, out)
    check(eval_out == out, "evaluate writes into the caller-owned table")
    eq(out.action, nil, "evaluate clears action")
    eq(out.hold, false, "evaluate clears hold")
    eq(out.hold_text, nil, "evaluate clears hold_text")
    eq(out.filler_slot, nil, "evaluate clears filler_slot")
    eq(out.judge_slot, nil, "evaluate clears judge_slot")
    eq(out.rotation_key, nil, "evaluate clears rotation_key")
    eq(out.waiting_judgement, false, "evaluate clears waiting_judgement")
    eq(out.inputs_unknown, true, "evaluate forwards inputs_unknown")
    local fallback_out = ST2.ROGUE.guide.evaluate(nil, nil)
    check(type(fallback_out) == "table" and fallback_out.inputs_unknown == true,
        "evaluate with no caller table still answers unknown without erroring")
    local module_inputs = ST2.ROGUE.gather_guide_inputs(ST2)
    check(module_inputs == ST2.ROGUE.guide_inputs,
        "gather falls back to the module's reused table")
    check(ST2.ROGUE.gather_guide_inputs(ST2) == module_inputs,
        "repeated gathers reuse the same table")

    -- The real frame's M6 state: enabled + in combat + a live swing -> "…", no advice.
    sb.class_db.nextaction_enabled = true
    sb.class_db.nextaction_visibility_key = "always"
    ST2.in_combat = true
    ST2.mainhand = { speed = 2.6, start = 1.0, ends_at = 3.6, is_full = false }
    sb.clock = 1.0
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(ui.should_show(ST2), true, "an enabled guide with a live swing is eligible")
    eq(ui.frame:IsShown(), true, "the guide frame is shown")
    eq(ui.frame.label.text, "…", "the unknown provider renders the explicit \"…\" label")
    eq(ui.frame.rotation_text.hidden, true, "unknown inputs suppress the rotation text")
    local any_target = false
    for i = 1, #ui.icons do
        if ui.targets[i] ~= 0 then any_target = true end
    end
    eq(any_target, false, "unknown inputs target no advice icon")
    ST2.ROGUE.on_bar_update(ST2, "offhand")
    eq(ui.frame.label.text, "…", "offhand ticks do not disturb the guide")
end

--=========================================================================================
-- 6) on_combat_exit preserves the mainhand record (G4 mirror)
--=========================================================================================
do
    local sb = build()
    local ST2 = sb.ST
    local record = { speed = 2.6, start = 1.0, ends_at = 3.6, is_full = false }
    ST2.mainhand = record
    local ok1, err1 = pcall(ST2.ROGUE.on_combat_exit, ST2)
    check(ok1, "on_combat_exit does not error (" .. tostring(err1) .. ")")
    check(ST2.mainhand == record, "on_combat_exit keeps the mainhand record object")
    eq(record.speed, 2.6, "the mainhand speed is untouched")
    eq(record.start, 1.0, "the mainhand start is untouched")
    eq(record.ends_at, 3.6, "the mainhand ends_at is untouched")
    eq(record.is_full, false, "the mainhand is_full flag is untouched")
    local ok2, err2 = pcall(ST2.ROGUE.on_combat_exit, ST2)
    check(ok2, "a repeated exit hook stays safe (" .. tostring(err2) .. ")")
    check(ST2.mainhand == record and record.ends_at == 3.6,
        "repeated exits still never clear or re-stamp the cycle")
end

--=========================================================================================
-- 7) Throw-safety with both shared consumers absent
--=========================================================================================
do
    local sb = build()
    local ST2, st2 = sb.ST, sb.st
    local nextaction, hud = st2.nextaction_ui, st2.hud
    st2.nextaction_ui = nil
    st2.hud = nil
    local ok1, err1 = pcall(ST2.ROGUE.post_init, ST2)
    check(ok1, "post_init is inert without the shared frames (" .. tostring(err1) .. ")")
    local ok2, err2 = pcall(ST2.ROGUE.on_bar_update, ST2, "mainhand")
    check(ok2, "on_bar_update is inert without the shared frames (" .. tostring(err2) .. ")")
    local ok3, err3 = pcall(ST2.ROGUE.on_bar_update, ST2, "offhand")
    check(ok3, "the non-mainhand hook is a no-op (" .. tostring(err3) .. ")")
    local ok4, err4 = pcall(ST2.ROGUE.get_hud_state, ST2, nil, nil)
    check(ok4, "get_hud_state without a slot/clock does not error (" .. tostring(err4) .. ")")
    st2.nextaction_ui, st2.hud = nextaction, hud
end

--=========================================================================================
-- Done
--=========================================================================================
print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then
    os.exit(1)
end
os.exit(0)

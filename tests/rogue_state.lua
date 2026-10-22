-- tests/rogue_state.lua: offline tests for the rogue class module (classes/rogue.lua)
-- over the real compat.lua + utils.lua + rogue_guide.lua +
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
--   * the Era-only SS window (red band, on by default per owner order 2026-10-19;
--     Era + sword shows; TBC/Wrath/Forever/Retail, dagger, unknown weapon and
--     option-off hide), the swap tint with the GCD+reset copy,
--     and the MH/OH poison reminder (presence only),
--   * the live HUD provider (SnD/Rupture/EA/AR/BF/Tea/Kick + the secret-regime
--     unknown render), the live guide gather (inputs_unknown ownership + the M5
--     lust-unknown latch + the "…" frame render, SnD upkeep + AR/BF readiness),
--     the builder identity chain (Saber > Mutilate > Hemorrhage > dagger Backstab >
--     SS, with the BS-6 family gate: Hemorrhage is a TBC/Forever/Era builder and
--     never a SoD one), the
--     AR-aware tick regime and the slot-less label fallbacks, and the TTD EMA
--     with the M7 provenance refusal, the H6 duty window (TBC wait/release +
--     Forever lockout ride the existing rogue_ea_duty toggle, no new keys)
--     and the SoD Envenom latch (ERA + the SoD-only Envenom rune known,
--     frozen at post_init, feeds inputs.sod_envenom), and the per-CP Rupture
--     DATA (W-M2 sourced rows only — provider passes CP through, no new db
--     key, flat floors still govern),
--   * on_combat_exit preserves the mainhand swing record object/fields (G4 mirror),
--   * the hooks stay throw-safe with both shared consumers absent,
--   * practice: the rogue seam on the shared session (post_init builds the panel
--     frames; the options Practice toggle starts the same session /st practice
--     toggles; pool + SS drills run end-to-end through the registry with
--     unknown-hides, nil-safe without the practice modules),
--   * designer: every rogue element is positionable (bars/HUD/rotation/guide via
--     the shared descriptors; practice panel once the session runs; bar-child
--     visuals move with the bar and take no separate descriptor).
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
local function near(got, want, tol, label)
    checks = checks + 1
    if type(got) ~= "number" or math.abs(got - want) > tol then
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
    function f:ClearAllPoints() f.point_cleared = true end
    function f:SetJustifyH() end
    function f:SetShadowColor() end
    function f:SetShadowOffset() end
    function f:SetFont(path, size, flags)
        -- SoD-faithful: SetFont with a nil path latches nothing (false, like the
        -- client); SetText with no font (neither SetFont nor SetFontObject latched)
        -- throws ("Font not set"). Every FontString must carry a font BEFORE its
        -- first SetText.
        if path == nil then
            return false
        end
        f.font = { path, size, flags }
        return true
    end
    function f:SetFontObject(obj) f.font_object = obj end
    function f:SetWordWrap(wrap) f.word_wrap = wrap end
    function f:GetFont() return f.font and f.font[1], f.font and f.font[2], f.font and f.font[3] end
    function f:SetText(text)
        if f.font == nil and f.font_object == nil then
            error("Font not set", 2)
        end
        f.text = text
        f.set_text_calls = (f.set_text_calls or 0) + 1
    end
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
    function t:ClearAllPoints() t.points = nil end
    function t:SetPoint(point, anchor, rel_point, x, y)
        t.points = t.points or {}
        t.points[#t.points + 1] = { point, anchor, rel_point, x, y }
    end
    function t:SetTexCoord(l, r, top, bottom) t.texcoord = { l, r, top, bottom } end
    function t:SetTexture(tex) t.texture = tex end
    function t:SetColorTexture() end
    function t:SetVertexColor(r, g, b, a) t.color = { r, g, b, a } end
    function t:SetDrawLayer() end
    function t:SetWidth(w) t.width = w end
    function t:SetHeight(h) t.height = h end
    function t:SetSize(w, h) t.width, t.height = w, h end
    function t:SetAlpha(a) t.alpha = a end
    function t:Hide() t.hidden = true end
    function t:Show() t.hidden = false end
    function t:IsShown() return not t.hidden end
    return t
end

local function make_frame(name)
    local f = { name = name, shown = false }
    function f:SetSize(w, h) f.width, f.height = w, h end
    function f:SetWidth(w) f.width = w end
    function f:SetHeight(h) f.height = h end
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
    function f:SetBackdropColor(r, g, b, a) f.backdrop_color = { r, g, b, a } end
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
    -- R3 short-CD fixtures (test-owned ids, never shipped): Kidney resolves the
    -- interrupt row, Vanish the Re-stealth CD (mapping UNCONFIRMED), the
    -- Heavy Netherweave rank the Bandage slot (rank UNCONFIRMED).
    [113] = { name = "Kidney Shot", icon = "i_kidney" },
    [114] = { name = "Vanish", icon = "i_vanish" },
    [115] = { name = "Heavy Netherweave Bandage", icon = "i_bandage" },
    [109] = { name = "Eviscerate", icon = "i_evisc" },
    [110] = { name = "Envenom", icon = "i_env" },
    [111] = { name = "Shiv", icon = "i_shiv" },
    [112] = { name = "Deadly Poison", icon = "i_deadly" },
    -- Cold Blood (test-owned id, never shipped): the slot-less F3/V-G5 prompt
    -- resolves through the client's own spell data like every other slot.
    [119] = { name = "Cold Blood", icon = "i_cb" },
    -- Hunger for Blood (test-owned id, never shipped): the Wrath sin upkeep
    -- (audit W-G1) resolves through the client's own spell data by name too.
    [120] = { name = "Hunger for Blood", icon = "i_hfb" },
    -- The APL utility layer (test-owned ids, never shipped): the rows the sims'
    -- priority lists carry (the utility rows resolve by NAME too).
    [121] = { name = "Ambush", icon = "i_ambush" },
    [122] = { name = "Garrote", icon = "i_garrote" },
    [123] = { name = "Preparation", icon = "i_prep" },
    [124] = { name = "Premeditation", icon = "i_premed" },
    [125] = { name = "Venom", icon = "i_venom" },
    [126] = { name = "Blood Fury", icon = "i_bfury" },
    [127] = { name = "Elune's Light", icon = "i_elune" },
    [128] = { name = "Poisoned Knife", icon = "i_pk" },
    [129] = { name = "Tricks of the Trade", icon = "i_tot" },
    [130] = { name = "Killing Spree", icon = "i_ks" },
    [131] = { name = "Eureka!", icon = "i_eureka" },
    [135] = { name = "Ghostly Strike", icon = "i_gs" },
    [137] = { name = "Hyperspeed Acceleration", icon = "i_hs" },
}
-- R1 name-shape legs: test-side pairings of the shipped utility probe ids
-- with their APL-cited aura names (mechanism legs only - the tests model
-- the client answering its own name for the probed id). Master of
-- Subtlety (the SoD rune aura, classes/rogue.lua APL i=7), Ambush and
-- Venom (the Forever opener rows, wowsims spelldata), Garrote (the
-- spellCurrentCost row) and Adrenaline Rush (the APL buff disjunct).
-- Kept OUT of ROGUE_SPELLS_BY_ID on purpose: those tables drive every
-- name->id resolution in the suite, and duplicate names there would flip
-- unrelated resolutions. The Wrath 58426 aura files NO pairing: its name is
-- UNCONFIRMED in-repo, so only its id shape is pinned.
local UTILITY_AURA_NAMES = {
    [425096] = "Master of Subtlety",
    [462707] = "Ambush",
    [1310703] = "Venom",
    [11290] = "Garrote",
    [13750] = "Adrenaline Rush",
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
    env.GameFontNormal = {}
    env.GameFontHighlightSmall = {}
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
    -- Numeric probes for the shipped utility-aura ids answer the test-side
    -- pairing above (the client's own localized name for the probed id); every
    -- other numeric probe answers only for a listed rank.
    env.GetSpellInfo = function(spell)
        if sb.missing_spells and sb.missing_spells[spell] then
            return nil
        end
        local id
        if type(spell) == "number" then
            if UTILITY_AURA_NAMES[spell] then
                return UTILITY_AURA_NAMES[spell], nil, "i_utility", 0, 0, 0, spell
            end
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
    -- The base cooldown (the APL's spellFullCooldown): the fixture answers 0
    -- ("no value") unless a case sets one - the house's "a non-positive base
    -- cooldown is no value" rule.
    env.GetSpellBaseCooldown = function()
        return sb.base_cd or 0
    end
    -- The spell power cost table (the APL's spellCurrentCost): the client's own
    -- shape - one entry per power type, the flat amount in .cost.
    env.GetSpellPowerCost = function(spell)
        local costs = sb.spell_costs and sb.spell_costs[spell]
        if costs then
            return costs
        end
        return nil
    end
    -- The client's own power types (Enum.PowerType) - the cost read selects the
    -- energy entry through it. A case can drop the energy type
    -- (opts.no_enum) to model a client that does not expose it.
    env.Enum = { PowerType = { Health = 0, Mana = 1, Rage = 2, Energy = 3 } }
    if opts.no_enum then
        env.Enum = { PowerType = {} }
    end
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
    -- Real client shape (SecureGroupHeaders reads hasOffHandEnchant at position 5;
    -- BuffFrame uses four values per weapon slot; the retail Deprecated_12_1_0 shim pads
    -- each slot with four values, the fourth being the enchant id).
    env.GetWeaponEnchantInfo = function()
        if sb.weapon_enchant_present == false then
            return nil
        end
        return sb.mh_poison ~= false, 3600, nil, 12345, sb.oh_poison ~= false, 3600, nil, 12345
    end
    env.GetItemCount = function(item)
        -- R3 Bandage mirrors the Tea shape: an answered count or the default
        -- pouch (Tea defaults to 1 when the test leaves it unset).
        if item == "Heavy Netherweave Bandage" then
            if sb.bandage_count == nil then
                return 1
            end
            return sb.bandage_count
        end
        if sb.tea_count == nil then
            return 1
        end
        return sb.tea_count
    end
    env.GetItemCooldown = function(info)
        if info == "Heavy Netherweave Bandage" then
            local bcd = sb.bandage_cd
            if not bcd then
                return 0, 0, 1
            end
            return bcd[1], bcd[2], 1
        end
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
        -- class-isolation 2026-10-21: the shared layer keys on the ACTIVATED class.
        active_class = "ROGUE",
        interfaces_are_initialised = true,
        in_combat = false,
        gcd = {},
        mainhand = {},
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
        -- Redzone shipped defaults (OWNER ORDER 2026-10-19): the Era SS window
        -- is visible with a red band unless explicitly turned off.
        show_rogue_ss_window = true,
        rogue_ss_color = { 255, 64, 48, 0.85 },
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
    function ST.get_bar_frame() return nil end
    function ST.show_bar() end
    function ST.hide_bar() end
    function ST.handle_bar_visibility() end
    function ST.on_bar_inactive() end
    function ST.on_gcd_length_change() end
    function ST.set_gcd_times_before_swing_seconds() end
    function ST.Print() end
    function ST.convert_color(_, t) return t[1] / 255, t[2] / 255, t[3] / 255, t[4] end
    -- The mainhand visuals frame the rogue widgets are drawn on (bars.lua's frame in the
    -- real client; a plain stub here with recordable textures/fontstrings).
    local visuals = make_frame("RogueVisuals")
    function ST:get_visuals_frame(hand)
        if hand == "mainhand" then
            return visuals
        end
        return nil
    end
    function ST:get_bar_visuals_width_and_height(hand)
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
        "compat.lua", "utils.lua", "guard.lua", "rogue_guide.lua",
        "nextaction.lua", "practice.lua", "nextaction_ui.lua", "hud.lua",
        "classes/rogue.lua", "practice_ui.lua",
    }
    for i = 1, #modules do
        local chunk = assert(loadfile(ROOT .. modules[i]))
        setfenv(chunk, env)
        chunk("SwedgeTimer", st)
        -- classes/rogue.lua registers its body as a loader (operator order 2026-10-21:
        -- only the selected class executes). The suite activates the rogue HERE, right
        -- after its file loads - the same load-time position its body occupied before
        -- the wrapper, so every later module sees the populated ST.ROGUE as it did.
        if modules[i] == "classes/rogue.lua" then
            assert(type(st.class_loaders) == "table"
                and type(st.class_loaders["ROGUE"]) == "function",
                "classes/rogue.lua registers the ROGUE loader")
            st.class_loaders["ROGUE"]()
        end
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
        "show_rogue_energy_tick", "show_rogue_pool_tint",
    }) do
        check(ships_false(key), "ROGUE defaults: " .. key .. " ships false (nil = off)")
    end
    check(ships_true("nextaction_enabled"),
        "ROGUE defaults: nextaction_enabled ships true (on-by-default, owner order)")
    -- Redzone exception (OWNER ORDER 2026-10-19, rogue-redzone): the Era SS
    -- window ships visible with a red band - the explicit gate for this
    -- default-visible exception to the standing off-by-default rule.
    check(block:find("%f[%a_]show_rogue_ss_window%s*=%s*true") ~= nil,
        "ROGUE defaults: show_rogue_ss_window ships true (Era red zone, owner order)")
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
        "rogue_energy_tick_color", "rogue_pool_tint_color", "rogue_ss_color",
    }) do
        local c = colour_values(key)
        check(c ~= nil, "ROGUE defaults: " .. key .. " is a colour table")
        if c then
            local in_range = c[1] <= 255 and c[2] <= 255 and c[3] <= 255
                and c[4] >= 0 and c[4] <= 1
            check(in_range, "ROGUE defaults: " .. key .. " uses 0-255 RGB + 0-1 alpha")
        end
    end
    do
        local c = colour_values("rogue_ss_color")
        check(c ~= nil and c[1] >= 200 and c[2] <= 100 and c[3] <= 100,
            "ROGUE defaults: rogue_ss_color ships red (R dominant, owner order)")
    end

    local class_defaults = presets:match("ST%.class_defaults%s*=%s*{(.-)\n%}") or ""
    check(class_defaults:find("hud_enabled%s*=%s*true") ~= nil,
        "shared defaults: the HUD master hud_enabled ships true (on-by-default, owner order)")
    check(class_defaults:find("rotation_label_enabled%s*=%s*false") ~= nil,
        "shared defaults: rotation_label_enabled still ships false")

    -- Removed cue keys (rogue-parity 2026-10-19): the ten inert upkeep-cue keys
    -- leave no trace in the defaults - a reintroduced key fails here, and the
    -- class-side absence is pinned below. The HUD slots + guide actions already
    -- cover every upkeep state they promised.
    for _, key in ipairs({
        "show_rogue_snd_cue", "rogue_snd_color", "show_rogue_rupture_cue",
        "rogue_rupture_color", "show_rogue_ea_cue", "rogue_ea_color",
        "show_rogue_shiv_cue", "rogue_shiv_color", "show_rogue_tea_cue",
        "rogue_tea_color",
    }) do
        check(block:find("%f[%a_]" .. key .. "%s*=") == nil,
            "ROGUE defaults: the removed cue key " .. key .. " stays gone")
    end
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
        "nextaction_enabled", "nextaction_locked",
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
    "kidney", "restealth", "bandage", "coldblood", "trinket1", "trinket2" }
eq(#hud_slots, #hud_expected, "the HUD declares the nine teardown slots + Cold Blood + the R3 short-CD row")
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
    "shiv", "tea", "snd", "ar", "bf", "coldblood" }
eq(#guide_slots, #guide_expected, "the guide declares the seven rogue action slots + snd/ar/bf/coldblood")
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
check(rogue_src:find("st.druid_energy", 1, true) == nil,
    "F1: no cross-class druid_energy read (rogue-owned EMA)")
check(rogue_src:find("ST.DRUID", 1, true) == nil,
    "F1: no ST.DRUID reference (each class self-contained)")

-- Removed cue keys (rogue-parity 2026-10-19): no consumer may read them back -
-- a reintroduced db read fails here. Zero inert keys: the ten cue toggles are
-- gone and every remaining db key the class reads has a widget (pinned by
-- tests/options_load_state.lua section 9).
for _, key in ipairs({
    "show_rogue_snd_cue", "rogue_snd_color", "show_rogue_rupture_cue",
    "rogue_rupture_color", "show_rogue_ea_cue", "rogue_ea_color",
    "show_rogue_shiv_cue", "rogue_shiv_color", "show_rogue_tea_cue",
    "rogue_tea_color",
}) do
    check(rogue_src:find("db%." .. key, 1, true) == nil,
        "removed cue: classes/rogue.lua never reads db." .. key)
end

--=========================================================================================
-- 4) HUD: ids resolved at init; the provider answers live aura/cooldown state
--=========================================================================================
do
    local sb = build()
    local ST2, st2 = sb.ST, sb.st
    local HUD = st2.hud
    check(type(HUD) == "table", "hud.lua defines st.hud")

    ST2.ROGUE.post_init(ST2)
    check(HUD.frame ~= nil, "post_init creates the HUD frame")
    -- Every spell slot id resolved from the client's own spell data by name; the two
    -- self-served trinket slots render without a provider entry.
    eq(#HUD.icons, 13, "eleven spell slots + two trinkets are renderable after the id fill")
    eq(HUD.should_show(ST2), false, "the HUD stays hidden with the shipped master default")
    eq(HUD.frame:IsShown(), false, "the HUD frame is not shown before it is enabled")
    HUD.on_update(ST2, 1)
    eq(HUD.frame:IsShown(), false, "a HUD tick stays invisible until enabled")
    eq(HUD.validate_slot(ST2.ROGUE.HUD_SLOTS[1], true), true,
        "a resolved spell slot validates")
    eq(HUD.validate_slot(ST2.ROGUE.HUD_SLOTS[12], true), true,
        "a trinket slot remains valid without a provider entry")

    -- The provider reuses one table; an unknown key leaves every contract field cleared.
    local state = ST2.ROGUE.hud_state
    local fields = { "remaining", "duration", "start", "reverse", "text_remaining",
        "desaturate", "usable", "in_range", "glow", "count", "texture", "hidden" }
    local same_table = true
    for i = 1, #ST2.ROGUE.HUD_SLOTS do
        local s = ST2.ROGUE.get_hud_state(ST2, ST2.ROGUE.HUD_SLOTS[i], sb.clock)
        if s ~= state then same_table = false end
    end
    check(same_table, "get_hud_state reuses one table (no per-tick allocation)")
    for j = 1, #fields do state[fields[j]] = "stale" end
    local unknown_slot = ST2.ROGUE.get_hud_state(ST2, { key = "no_such_slot" }, sb.clock)
    check(unknown_slot == state, "an unknown key reuses the state table")
    local stale_cleared = true
    for j = 1, #fields do
        if unknown_slot[fields[j]] ~= nil then stale_cleared = false end
    end
    check(stale_cleared, "an unknown key clears every contract field")

    local snd_slot = ST2.ROGUE.HUD_SLOTS[1]
    local rupture_slot = ST2.ROGUE.HUD_SLOTS[2]
    local ea_slot = ST2.ROGUE.HUD_SLOTS[3]
    local ar_slot = ST2.ROGUE.HUD_SLOTS[4]
    local tea_slot = ST2.ROGUE.HUD_SLOTS[6]
    local kick_slot = ST2.ROGUE.HUD_SLOTS[7]

    -- SnD: an active buff reports its window; inside the final seconds it glows.
    sb.auras = { player = { { name = "Slice and Dice", duration = 30,
        expiration = sb.clock + 20, spell_id = 101 } } }
    local s = ST2.ROGUE.get_hud_state(ST2, snd_slot, sb.clock)
    eq(s.remaining, 20, "SnD reports the live remaining window")
    eq(s.duration, 30, "SnD reports the full window")
    eq(s.desaturate, nil, "an active SnD is not greyed")
    eq(s.hidden, nil, "an active SnD is not hidden")
    sb.auras.player[1].expiration = sb.clock + 2
    s = ST2.ROGUE.get_hud_state(ST2, snd_slot, sb.clock)
    eq(s.glow, true, "SnD glows inside the final seconds")

    -- Rupture: a target debuff; absence (no secret regime) greys the icon.
    sb.auras = { target = { { name = "Rupture", duration = 16,
        expiration = sb.clock + 9, spell_id = 102 } } }
    s = ST2.ROGUE.get_hud_state(ST2, rupture_slot, sb.clock)
    eq(s.remaining, 9, "Rupture reports the live target-debuff window")
    eq(s.duration, 16, "Rupture reports the full debuff window")
    sb.auras = {}
    s = ST2.ROGUE.get_hud_state(ST2, rupture_slot, sb.clock)
    eq(s.remaining, 0, "an absent Rupture reads the greyed zero state")
    eq(s.desaturate, true, "an absent Rupture greys the icon")
    eq(s.hidden, nil, "an absent Rupture is missing, not unknown")

    -- EA absent, AR on cooldown, Kick resource-locked, Tea count/cooldown.
    s = ST2.ROGUE.get_hud_state(ST2, ea_slot, sb.clock)
    eq(s.desaturate, true, "an absent Expose Armor greys the icon")
    -- Name-vs-id rule (operator 2026-10-19): TBC queries by NAME never bare id.
    sb.spell_cd = { ["Adrenaline Rush"] = { sb.clock - 10, 300 } }
    s = ST2.ROGUE.get_hud_state(ST2, ar_slot, sb.clock)
    eq(s.remaining, 290, "Adrenaline Rush reports the live cooldown")
    eq(s.duration, 300, "Adrenaline Rush reports the full cooldown")
    eq(s.desaturate, true, "a running Adrenaline Rush cooldown greys the icon")
    sb.spell_cd = nil
    s = ST2.ROGUE.get_hud_state(ST2, ar_slot, sb.clock)
    eq(s.remaining, 0, "a ready Adrenaline Rush reads zero")
    sb.usable = { ["Kick"] = false }
    s = ST2.ROGUE.get_hud_state(ST2, kick_slot, sb.clock)
    eq(s.usable, false, "Kick reports the live usability")
    sb.usable = nil
    sb.tea_count = 0
    s = ST2.ROGUE.get_hud_state(ST2, tea_slot, sb.clock)
    eq(s.count, 0, "Thistle Tea reports the answered item count")
    eq(s.usable, false, "an empty Tea pouch is unusable")
    sb.tea_count = 2
    sb.tea_cd = { sb.clock - 60, 300 }
    s = ST2.ROGUE.get_hud_state(ST2, tea_slot, sb.clock)
    eq(s.remaining, 240, "Thistle Tea reports the live item cooldown")
    sb.tea_cd = nil
    sb.tea_count = nil

    -- Secret regime (M5): an absent aura under the probe reads unknown (hidden), never
    -- "missing". The probe stub lives on the api table (compat's call site shape).
    local real_probe = st2.api.auras_may_be_secret
    st2.api.auras_may_be_secret = function() return true end
    sb.clock = sb.clock + 0.05
    sb.auras = {}
    s = ST2.ROGUE.get_hud_state(ST2, snd_slot, sb.clock)
    eq(s.hidden, true, "M5: a hidden aura list renders the slot unknown, not missing")
    eq(s.desaturate, nil, "M5: the unknown state is not the greyed missing state")
    st2.api.auras_may_be_secret = real_probe

    -- A client that cannot answer the clock hides the slot.
    local real_time = st2.api.get_time
    st2.api.get_time = function() return nil end
    s = ST2.ROGUE.get_hud_state(ST2, snd_slot, nil)
    eq(s.hidden, true, "a client without a clock hides the slot")
    st2.api.get_time = real_time

    -- Enabling the master is safe and every slot answers through the provider.
    sb.class_db.hud_enabled = true
    eq(HUD.should_show(ST2), true, "enabling the master makes the HUD eligible")
    local state_count = 0
    for i = 1, #ST2.ROGUE.HUD_SLOTS do
        ST2.ROGUE.get_hud_state(ST2, ST2.ROGUE.HUD_SLOTS[i], sb.clock)
        state_count = state_count + 1
    end
    eq(state_count, 13, "every slot answers a state through the provider")

    -- Cold Blood HUD (audit F3/V-G5): resolves from the client's spell data,
    -- hides on a nil toggle (no default-visible change; widget/default filed),
    -- reports the live cooldown once enabled.
    local cb_slot = nil
    for i = 1, #ST2.ROGUE.HUD_SLOTS do
        if ST2.ROGUE.HUD_SLOTS[i].key == "coldblood" then
            cb_slot = ST2.ROGUE.HUD_SLOTS[i]
        end
    end
    check(cb_slot ~= nil, "Cold Blood declares a HUD slot")
    if cb_slot then
        eq(cb_slot.title, "Cold Blood", "Cold Blood keeps its HUD title")
        eq(cb_slot.kind, "spell", "Cold Blood is a spell slot")
        check(cb_slot.spell ~= nil, "Cold Blood resolves from the client's spell data")
        local cb_hidden = ST2.ROGUE.get_hud_state(ST2, cb_slot, sb.clock)
        eq(cb_hidden.hidden, true, "a nil Cold Blood toggle hides (no default-visible change)")
        sb.class_db.hud_show_coldblood = true
        sb.spell_cd = { ["Cold Blood"] = { sb.clock - 10, 120 } }
        local cb_cd = ST2.ROGUE.get_hud_state(ST2, cb_slot, sb.clock)
        eq(cb_cd.remaining, 110, "Cold Blood reports the live cooldown")
        eq(cb_cd.duration, 120, "Cold Blood reports the full cooldown")
        eq(cb_cd.desaturate, true, "a running Cold Blood cooldown greys the icon")
        sb.spell_cd = nil
        local cb_ready = ST2.ROGUE.get_hud_state(ST2, cb_slot, sb.clock)
        eq(cb_ready.remaining, 0, "a ready Cold Blood reads zero")
        eq(cb_ready.hidden, nil, "an enabled Cold Blood is not hidden")
        sb.class_db.hud_show_coldblood = nil
        sb.missing_spells = { ["Cold Blood"] = true }
        ST2.ROGUE.spell_cache["hud:coldblood"] = nil
        ST2.ROGUE.spell_retry_at = 0
        local cb_unresolved = ST2.ROGUE.get_hud_state(ST2, cb_slot, sb.clock)
        eq(cb_unresolved.hidden, true, "an unresolved Cold Blood hides (unknown-hides)")
        sb.missing_spells = nil
        ST2.ROGUE.spell_cache["hud:coldblood"] = nil
        ST2.ROGUE.spell_retry_at = 0
        ST2.ROGUE.apply_spell_ids(ST2)
    end
end

--=========================================================================================
-- 5) Guide provider: live gather, inputs_unknown ownership, POOL/NOW through the frame
--=========================================================================================
do
    local sb = build()
    local ST2, st2 = sb.ST, sb.st
    local ui = st2.nextaction_ui
    ST2.ROGUE.post_init(ST2)
    check(ui.frame ~= nil, "post_init creates the shared guide frame")
    eq(#ui.icons, 11, "the shared frame builds all eleven rogue slots")
    eq(ui.should_show(ST2), false, "the guide stays hidden with the shipped OFF default")
    for _, key in ipairs({ "snd", "ar", "bf", "coldblood" }) do
        check(ui.slot_index[key] ~= nil, "the guide frame indexes the " .. key .. " slot")
    end
    do
        local by_key = {}
        for i = 1, #ST2.ROGUE.guide.slots do
            by_key[ST2.ROGUE.guide.slots[i].key] = ST2.ROGUE.guide.slots[i]
        end
        for _, key in ipairs({ "snd", "ar", "bf", "coldblood" }) do
            check(by_key[key] ~= nil and by_key[key].spell_id ~= nil,
                "the " .. key .. " guide slot resolves from the client's spell data")
        end
    end

    -- Provider-contract pins: caller-owned tables, live reads, no allocation.
    local gathered = { speed = 2.6, swing_remaining = 1.2 }
    sb.power[3] = 50
    sb.power[4] = 0
    local got = ST2.ROGUE.gather_guide_inputs(ST2, gathered)
    check(got == gathered, "gather writes into the caller-owned table")
    eq(gathered.family, "TBC", "gather reports the compat family")
    eq(gathered.energy_now, 50, "gather reads the live energy")
    eq(gathered.cp, 0, "gather reads the live combo points")
    eq(gathered.inputs_unknown, false, "readable core inputs are not unknown")
    eq(gathered.lust_unknown, false, "no secret regime: the lust read is honest")
    local module_inputs = ST2.ROGUE.gather_guide_inputs(ST2)
    check(module_inputs == ST2.ROGUE.guide_inputs,
        "gather falls back to the module's reused table")
    check(ST2.ROGUE.gather_guide_inputs(ST2) == module_inputs,
        "repeated gathers reuse the same table")

    -- Unreadable core reads own the unknown bit (M6); the evaluate mapping forwards it
    -- while clearing every other frozen field.
    local out = { action = "builder", hold = true, hold_text = "X",
        filler_slot = "rupture", judge_slot = "eviscerate", rotation_key = "old",
        waiting_judgement = true, inputs_unknown = false }
    sb.power[3] = nil
    local unknown_gather = ST2.ROGUE.gather_guide_inputs(ST2, {})
    eq(unknown_gather.inputs_unknown, true, "an unreadable energy read is unknown (M6)")
    local eval_out = ST2.ROGUE.guide.evaluate(unknown_gather, out)
    check(eval_out == out, "evaluate writes into the caller-owned table")
    eq(out.action, nil, "evaluate clears action on unknown")
    eq(out.hold, false, "evaluate clears hold on unknown")
    eq(out.hold_text, nil, "evaluate clears hold_text on unknown")
    eq(out.filler_slot, nil, "evaluate clears filler_slot")
    eq(out.judge_slot, nil, "evaluate clears judge_slot")
    eq(out.rotation_key, nil, "evaluate clears rotation_key")
    eq(out.waiting_judgement, false, "evaluate clears waiting_judgement")
    eq(out.inputs_unknown, true, "evaluate forwards inputs_unknown")
    local fallback_out = ST2.ROGUE.guide.evaluate(nil, nil)
    check(type(fallback_out) == "table" and fallback_out.inputs_unknown == true,
        "evaluate with no caller table still answers unknown without erroring")
    sb.power[3] = 50

    -- The real frame, live: enabled + in combat + a live swing.
    sb.class_db.nextaction_enabled = true
    sb.class_db.nextaction_visibility_key = "always"
    ST2.in_combat = true
    ST2.mainhand = { speed = 2.6, start = 0, ends_at = 0, is_full = false }
    local function live_swing(clock)
        sb.clock = clock
        ST2.mainhand.start = clock - 0.5
        ST2.mainhand.ends_at = clock + 2.1
    end

    -- POOL: low energy, no CP -> the hold overlay reads POOL.
    live_swing(10)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(ui.should_show(ST2), true, "an enabled guide with a live swing is eligible")
    eq(ui.frame:IsShown(), true, "the guide frame is shown")
    eq(ui.frame.hold.fade.target, 1, "POOL shows the hold overlay")
    eq(ui.frame.hold.text.text, "POOL", "the hold overlay reads POOL")
    local any_target = false
    for i = 1, #ui.icons do
        if ui.targets[i] ~= 0 then any_target = true end
    end
    eq(any_target, false, "POOL targets no advice icon")

    -- NOW: a capping bar calls the builder; the action icon carries the ride overlay.
    live_swing(20)
    sb.power[3] = 90
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(ui.targets[ui.slot_index.builder], 1, "a capping bar prompts the builder")
    eq(ui.frame.hold.fade.target, 1, "an action shows the ride overlay")
    eq(ui.frame.hold.text.text, "NOW", "the ride overlay reads NOW")

    -- Wired slots (audit F0/H1 + F3/H11 + F3/V-G5): the engine's snd/ar/bf/
    -- coldblood verdicts light their own icons (TBC family, live swing).
    live_swing(21)
    sb.power[3], sb.power[4] = 50, 5
    sb.auras, sb.spell_cd, sb.usable = {}, nil, nil
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(ui.targets[ui.slot_index.snd], 1, "a missing SnD with CP prompts snd")
    eq(ui.frame.hold.text.text, "NOW", "snd rides the NOW overlay")
    live_swing(22)
    sb.power[3], sb.power[4] = 30, 0
    sb.auras = {}
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(ui.targets[ui.slot_index.ar], 1, "low energy with AR ready prompts ar")
    live_swing(23)
    sb.power[3], sb.power[4] = 90, 0
    sb.auras = { player = { { name = "Slice and Dice", duration = 30,
        expiration = sb.clock + 20, spell_id = 101 } } }
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(ui.targets[ui.slot_index.bf], 1, "SnD riding with BF ready prompts bf")
    live_swing(24)
    sb.spell_cd = { ["Blade Flurry"] = { sb.clock - 10, 300 } }
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(ui.targets[ui.slot_index.coldblood], 1, "SnD riding with BF cooling prompts Cold Blood")
    sb.spell_cd = nil
    sb.auras = {}

    -- Unknown through the real frame: unreadable energy -> "…", no advice at all.
    live_swing(30)
    sb.power[3] = nil
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(ui.frame.label.text, "…", "unknown inputs render the explicit \"…\" label")
    eq(ui.frame.rotation_text.hidden, true, "unknown inputs suppress the rotation text")
    any_target = false
    for i = 1, #ui.icons do
        if ui.targets[i] ~= 0 then any_target = true end
    end
    eq(any_target, false, "unknown inputs target no advice icon")
    ST2.ROGUE.on_bar_update(ST2, "offhand")
    eq(ui.frame.label.text, "…", "offhand ticks do not disturb the guide")

    -- M5 latch: the secret regime + an inconclusive lust canary owns the unknown bit.
    live_swing(40)
    sb.power[3] = 50
    local real_probe = st2.api.auras_may_be_secret
    st2.api.auras_may_be_secret = function() return true end
    ST2.rogue_lust_at = nil
    local latched = ST2.ROGUE.gather_guide_inputs(ST2, {})
    eq(latched.lust_unknown, true, "M5: a secret regime marks the lust read unknown")
    eq(latched.inputs_unknown, true, "M5: the secret regime owns the unknown bit")
    st2.api.auras_may_be_secret = function() return false end
    ST2.rogue_lust_at = nil
    local unlatched = ST2.ROGUE.gather_guide_inputs(ST2, {})
    eq(unlatched.lust_unknown, false, "M5: an answering probe restores the honest read")
    eq(unlatched.inputs_unknown, false, "M5: the honest read clears the unknown bit")
    st2.api.auras_may_be_secret = real_probe
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
-- 8) Proc-aware tick predictor (Yam rule + H4)
--=========================================================================================
do
    local sb = build()
    local ST2 = sb.ST
    local TICK = ST2.ROGUE

    -- No anchor yet: the first sample observes, the first +20 gain seeds.
    eq(TICK.update_energy_tick(ST2, 0.0, 40, 100), nil, "no anchor: no prediction")
    near(TICK.update_energy_tick(ST2, 0.5, 60, 100), 2.0, 1e-9,
        "a +20 gain seeds and predicts 2 s")
    near(TICK.update_energy_tick(ST2, 1.5, 60, 100), 1.0, 1e-9, "a zero delta keeps the phase")

    -- Combat Potency 15 and Relentless Strikes 25 NEVER re-anchor (Yam rule, §2.2).
    near(TICK.update_energy_tick(ST2, 1.6, 75, 100), 0.9, 1e-9,
        "CP 15: the tick phase is unchanged")
    near(TICK.update_energy_tick(ST2, 1.7, 100, 100), 0.8, 1e-9,
        "RS 25: the tick phase is unchanged")

    -- A spend never re-anchors; an in-phase +20 does.
    near(TICK.update_energy_tick(ST2, 2.0, 60, 100), 0.5, 1e-9, "a spend keeps the phase")
    near(TICK.update_energy_tick(ST2, 2.5, 80, 100), 2.0, 1e-9, "the in-phase +20 re-anchors")
    near(TICK.update_energy_tick(ST2, 3.0, 80, 100), 1.5, 1e-9,
        "a zero delta follows the re-anchor")

    -- An out-of-phase +20 is ambiguous: hidden until an in-phase tick recovers it.
    eq(TICK.update_energy_tick(ST2, 3.1, 100, 200), nil, "an out-of-phase +20 hides (H4)")
    near(TICK.update_energy_tick(ST2, 4.5, 120, 200), 2.0, 1e-9,
        "the in-phase +20 recovers the phase")

    -- An unrecognised grant latches unknown; a fresh +20 in phase recovers it.
    local sb2 = build()
    local ST3 = sb2.ST
    eq(ST3.ROGUE.update_energy_tick(ST3, 0.0, 40, 100), nil, "fresh: no anchor")
    near(ST3.ROGUE.update_energy_tick(ST3, 0.5, 60, 100), 2.0, 1e-9, "fresh: a +20 seeds")
    eq(ST3.ROGUE.update_energy_tick(ST3, 0.6, 95, 100), nil, "an unrecognised +35 grant hides (H4)")
    eq(ST3.ROGUE.update_energy_tick(ST3, 1.0, 95, 100), nil, "the latch holds while hidden")
    near(ST3.ROGUE.update_energy_tick(ST3, 2.5, 115, 200), 2.0, 1e-9,
        "an in-phase +20 clears the latch")

    -- A missed tick (no gain past the tolerance) drops the phase; the next +20 re-seeds.
    local sb3 = build()
    local ST4 = sb3.ST
    eq(ST4.ROGUE.update_energy_tick(ST4, 0.0, 40, 100), nil, "seeding sample")
    near(ST4.ROGUE.update_energy_tick(ST4, 0.5, 60, 100), 2.0, 1e-9, "seeded")
    near(ST4.ROGUE.update_energy_tick(ST4, 2.5, 60, 100), 0.0, 1e-9,
        "the due-but-unobserved tick reads 0 (pending)")
    eq(ST4.ROGUE.update_energy_tick(ST4, 3.0, 60, 100), nil,
        "past the tolerance the phase drops (H4)")
    near(ST4.ROGUE.update_energy_tick(ST4, 3.5, 80, 100), 2.0, 1e-9,
        "a later +20 re-seeds the phase")

    -- At the cap the phase advances arithmetically (ticks still land, no gain shows).
    local sb4 = build()
    local ST5 = sb4.ST
    ST5.rogue_tick_anchor = 0.5
    ST5.rogue_tick_prev, ST5.rogue_tick_at = 100, 4.9
    near(ST5.ROGUE.update_energy_tick(ST5, 5.0, 100, 100), 1.5, 1e-9,
        "at the cap the phase advances without an observable gain")

    -- NaN/unreadable inputs never ride a stale phase.
    eq(TICK.update_energy_tick(ST2, nil, 50, 100), nil, "an unreadable clock hides")
    eq(TICK.update_energy_tick(ST2, 10.0, 0 / 0, 100), nil, "NaN energy hides")
    eq(TICK.update_energy_tick(ST2, 10.0, nil, 100), nil, "nil energy hides")
end

--=========================================================================================
-- 9) Visuals: tick spark, pooling wash, Era SS window, swap tint, poison reminder
--=========================================================================================
do
    local sb = build({ project = 2 })   -- Classic Era
    local ST2, st2 = sb.ST, sb.st
    local vf = sb.visuals
    local db = sb.class_db
    ST2.ROGUE.post_init(ST2)
    check(vf.rogue_tick_spark ~= nil, "post_init creates the tick spark")
    check(vf.rogue_pool_wash ~= nil, "post_init creates the pooling wash")
    check(vf.rogue_ss_band ~= nil and vf.rogue_ss_text ~= nil,
        "post_init creates the SS window widgets")
    check(vf.rogue_swap_band ~= nil and vf.rogue_swap_text ~= nil,
        "post_init creates the swap widgets")
    check(vf.rogue_poison_text ~= nil, "post_init creates the poison reminder")

    local function set_swing(clock, since, speed)
        local speed_v = speed or 2.6
        sb.clock = clock
        ST2.mainhand = { speed = speed_v, start = clock - since,
            ends_at = clock - since + speed_v, is_full = false }
    end

    -- Tick spark: seeded phase -> positioned, shown spark; unknown -> hidden (H4).
    db.show_rogue_energy_tick = true
    sb.power[3] = 40
    set_swing(0.0, 0.5)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_tick_spark.hidden, true, "no phase yet: the spark is hidden")
    sb.power[3] = 60
    set_swing(0.5, 0.5)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_tick_spark.hidden, false, "a seeded phase shows the spark")
    local points = vf.rogue_tick_spark.points
    eq(points[#points][4], 0, "a freshly anchored tick parks the spark at the left edge")
    sb.power[3] = 60
    set_swing(1.5, 0.5)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    points = vf.rogue_tick_spark.points
    eq(points[#points][4], 100, "mid-cycle the spark sits at half the 200 px bar")
    sb.power[3] = 95
    set_swing(1.6, 0.5)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_tick_spark.hidden, true, "an ambiguous tick hides the spark (H4)")
    db.show_rogue_energy_tick = false

    -- Pooling wash: >= post full alpha, >= pre with a known tick softer, below hidden,
    -- and data-driven (the family table decides when no db override is configured).
    db.show_rogue_pool_tint = true
    ST2.rogue_tick_prev, ST2.rogue_tick_at = nil, nil
    ST2.rogue_tick_anchor, ST2.rogue_tick_unknown = nil, false
    sb.power[3] = 40
    set_swing(10.0, 0.5)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    sb.power[3] = 60
    set_swing(10.5, 0.5)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_pool_wash.hidden, true, "below the pre band the wash stays hidden")
    sb.power[3] = 60
    set_swing(11.0, 0.5)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_pool_wash.hidden, true, "pre band with a healthy bar stays hidden")
    sb.power[3] = 75
    set_swing(11.5, 0.5)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_pool_wash.hidden, false, ">= pre with a known tick shows the softer wash")
    check(math.abs((vf.rogue_pool_wash.color[4] or 0) - 0.85 * 0.55) < 0.001,
        "the pre band uses the softer alpha")
    sb.power[3] = 100
    set_swing(12.0, 0.5)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    check(math.abs((vf.rogue_pool_wash.color[4] or 0) - 0.85) < 0.001,
        "the post band uses the full alpha")
    db.rogue_pool_band_pre, db.rogue_pool_band_post = nil, nil
    st2.family = "RETAIL"
    sb.power[3] = 90
    set_swing(12.5, 0.5)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_pool_wash.hidden, true, "RETAIL has no tick band: the wash never shows")
    st2.family = "ERA"
    db.rogue_pool_band_pre, db.rogue_pool_band_post = 65, 85
    db.show_rogue_pool_tint = false

    -- Era SS window: family ERA + a confirmed sword mainhand, inside 0.1-0.2 s.
    db.show_rogue_ss_window = true
    sb.items = { [16] = 90001, [17] = 90001 }
    set_swing(20.0, 0.15)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_ss_band.hidden, false, "Era + sword: the SS window band shows")
    eq(vf.rogue_ss_text.hidden, false, "Era + sword: the SS caption shows")
    local ss_c = vf.rogue_ss_band.color
    check(ss_c ~= nil and ss_c[1] > 0.9 and ss_c[2] < 0.4 and ss_c[3] < 0.4,
        "Era + sword: the SS band renders the shipped red")
    set_swing(20.5, 0.05)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_ss_band.hidden, true, "before 0.1 s the band hides")
    set_swing(21.0, 0.3)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_ss_band.hidden, true, "after 0.2 s the band hides")
    set_swing(21.5, 0.15)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_ss_band.hidden, false, "back inside the window")
    -- The TBC+ gate is absolute (Sno refuted the technique there).
    st2.family = "TBC"
    set_swing(22.0, 0.15)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_ss_band.hidden, true, "TBC: no SS window, ever")
    st2.family = "WRATH"
    set_swing(22.5, 0.15)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_ss_band.hidden, true, "Wrath: no SS window")
    st2.family = "RETAIL"
    set_swing(23.0, 0.15)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_ss_band.hidden, true, "Retail: no SS window")
    st2.family = "ERA"
    -- Off-loadout Era: dagger / unknown weapon / option off all hide.
    sb.items = { [16] = 90002, [17] = 90002 }
    set_swing(23.5, 0.15)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_ss_band.hidden, true, "Era + dagger: no SS window (H4 loadout)")
    sb.items = nil
    set_swing(24.0, 0.15)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_ss_band.hidden, true, "an unreadable weapon hides the SS window")
    sb.items = { [16] = 90001, [17] = 90001 }
    db.show_rogue_ss_window = false
    set_swing(24.5, 0.15)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_ss_band.hidden, true, "the option off hides the SS window")

    -- Weapon-swap tint: the post-MH window on the swap families, with the cost copy.
    db.show_rogue_swap_cue = true
    st2.family = "TBC"
    set_swing(30.0, 0.15)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_swap_band.hidden, false, "TBC: the swap window shows")
    eq(vf.rogue_swap_text.text, "swap: GCD + swing reset",
        "the swap copy carries the GCD + swing-reset cost")
    st2.family = "WRATH"
    set_swing(30.5, 0.15)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_swap_band.hidden, true, "Wrath ships no swap cue (recorded conflict)")
    st2.family = "RETAIL"
    set_swing(31.0, 0.15)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_swap_band.hidden, true, "Retail ships no swap cue")
    st2.family = "FOREVER"
    set_swing(31.5, 0.15)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_swap_band.hidden, false, "Forever keeps the swap cue")
    set_swing(32.0, 0.05)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_swap_band.hidden, true, "outside the window the swap tint hides")
    db.show_rogue_swap_cue = false
    st2.family = "ERA"

    -- Poison reminder: presence only, both directions, never a claim on unknown.
    db.show_rogue_poison_cue = true
    sb.items = { [16] = 90001, [17] = 90001 }
    sb.mh_poison, sb.oh_poison = false, true
    set_swing(40.0, 0.5)
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_poison_text.text, "no poison: MH", "a bare mainhand reports the missing poison")
    sb.mh_poison, sb.oh_poison = true, false
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_poison_text.text, "no poison: OH", "a bare offhand reports the missing poison")
    sb.mh_poison, sb.oh_poison = false, false
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_poison_text.text, "no poison: MH + OH", "both bare weapons read MH + OH")
    sb.mh_poison, sb.oh_poison = true, true
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_poison_text.hidden, true, "fully poisoned weapons hide the reminder")
    sb.weapon_enchant_present = false
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(vf.rogue_poison_text.hidden, true, "an absent probe never claims a missing poison")
    db.show_rogue_poison_cue = false
end

--=========================================================================================
-- 10) TTD: the rogue-owned EMA, own provenance only (M7)
--=========================================================================================
do
    local sb = build()
    local ST2 = sb.ST
    sb.guid = { target = "G1" }
    sb.health = { target = 100 }
    eq(ST2.ROGUE.get_time_to_die(ST2, 100), nil, "the first sample seeds, no estimate")
    sb.health.target = 80
    local ttd = ST2.ROGUE.get_time_to_die(ST2, 100.3)
    check(type(ttd) == "number" and ttd > 0, "the second sample yields an HP/s estimate")

    -- A fallback-provenance enemy cycle is never consumed (M7): unreadable health stays
    -- nil - the 2.0 s fallback is display fiction and this module has no path to it.
    ST2.enemy = { cycle = 2.0, provenance = "fallback" }
    sb.health.target = nil
    eq(ST2.ROGUE.get_time_to_die(ST2, 101.0), nil, "no health: nil, never the 2.0 fallback")
    check(ST2.ROGUE.TTD_PROVENANCE ~= "fallback",
        "the module's TTD provenance is its own EMA, not the fallback")
    check(ST2.ROGUE.TTD_PROVENANCE ~= "cached", "the module never consumes a cached cycle")

    -- A dropped baseline re-seeds; a new target resets it.
    sb.health.target = 50
    eq(ST2.ROGUE.get_time_to_die(ST2, 101.1), nil, "a dropped baseline re-seeds")
    sb.health.target = 30
    check(ST2.ROGUE.get_time_to_die(ST2, 101.4) ~= nil, "the re-seed estimates again")
    sb.guid.target = "G2"
    eq(ST2.ROGUE.get_time_to_die(ST2, 101.7), nil, "a new target resets the baseline")

    -- No target identity: no estimate (never a guessed TTD).
    sb.guid.target = nil
    sb.health.target = 40
    eq(ST2.ROGUE.get_time_to_die(ST2, 102.0), nil, "no target identity: no estimate")

    -- Equivalence (F1 behavior-preserving move): the rogue-owned EMA answers the
    -- druid D4 vectors verbatim (same smoothing, same inputs/outputs).
    local rg = sb.st.rogue_guide
    eq(rg.TTD_EMA_ALPHA, 0.25, "the rogue EMA weights the newest sample 0.25")
    eq(rg.TTD_SAMPLE_SECONDS, 0.25, "the rogue sampler throttles to 0.25 s")
    near(rg.update_hp_velocity(nil, 900, 1000, 1, 0.25), 100, 1e-9,
        "a first sample seeds the raw velocity")
    near(rg.update_hp_velocity(100, 800, 1000, 1, 0.25), 125, 1e-9,
        "a later sample smooths with weight 0.25")
    near(rg.update_hp_velocity(100, 900, 900, 1, 0.25), 75, 1e-9,
        "zero damage decays the EMA without crossing zero")
    near(rg.update_hp_velocity(50, 1000, 900, 1, 0.25), 37.5, 1e-9,
        "a heal contributes zero velocity")
    near(rg.update_hp_velocity(100, 800, 900, 1, nil), 0.25 * 100 + 0.75 * 100, 1e-9,
        "a missing alpha falls back to the shipped weight")
    eq(rg.update_hp_velocity(100, nil, 900, 1, 0.25), nil, "a missing hp reads nil")
    eq(rg.update_hp_velocity(100, 800, 900, 0, 0.25), nil, "a zero dt reads nil")
    eq(rg.update_hp_velocity(100, 0 / 0, 900, 1, 0.25), nil, "a NaN hp reads nil")
    near(rg.get_time_to_die(1000, 100), 10, 1e-9, "1000 hp at 100 HP/s dies in 10 s")
    near(rg.get_time_to_die(50, 25), 2, 1e-9, "the estimate scales with the hp")
    eq(rg.get_time_to_die(1000, 0), nil, "a zero velocity has no crossing")
    eq(rg.get_time_to_die(0 / 0, 100), nil, "a NaN hp reads nil")
end

--=========================================================================================
-- 11) Cold-spell-book retry: an unresolved slot stays skipped, then fills
--=========================================================================================
do
    local sb = build()
    local ST2, st2 = sb.ST, sb.st
    sb.missing_spells = { Kick = true }
    ST2.ROGUE.post_init(ST2)
    eq(ST2.ROGUE.spell_pending, true, "an unresolved slot marks the retry pending")
    local kick_slot
    for i = 1, #ST2.ROGUE.HUD_SLOTS do
        if ST2.ROGUE.HUD_SLOTS[i].key == "kick" then
            kick_slot = ST2.ROGUE.HUD_SLOTS[i]
        end
    end
    eq(kick_slot.spell, nil, "the unresolved slot ships no id (hud.lua skips it)")
    eq(#st2.hud.icons, 12, "the HUD renders the other twelve slots")
    sb.missing_spells = nil
    sb.clock = sb.clock + 6.0
    ST2.ROGUE.apply_spell_ids(ST2)
    eq(ST2.ROGUE.spell_pending, false, "the throttle retry fills the cold-book slot")
    -- Name-vs-id rule (operator 2026-10-19): TBC slots store the English name.
    eq(kick_slot.spell, "Kick", "the TBC slot resolves to the client name")
end

--=========================================================================================
-- 12) R3 short-CD row + stacked multi-CD glow (competitor_gaps R3; rogue_deep §§2.4/2.7)
--=========================================================================================
-- Sno UI short-CD tracker (Kick/Kidney/Re-stealth/Bandage) + stacked-glow rule:
-- aura + cooldown reads only; tunables UNCONFIRMED beyond Sno's list. New slots
-- hide unless their own hud_show_<key> reads exactly true (nil = off): no
-- default-visible change without an options widget.
do
    local sb = build()
    local ST2, st2 = sb.ST, sb.st
    ST2.ROGUE.post_init(ST2)
    local by_key = {}
    for i = 1, #ST2.ROGUE.HUD_SLOTS do
        by_key[ST2.ROGUE.HUD_SLOTS[i].key] = ST2.ROGUE.HUD_SLOTS[i]
    end
    eq(by_key.kidney ~= nil and by_key.restealth ~= nil and by_key.bandage ~= nil, true,
        "the R3 short-CD slots exist after the teardown order")
    eq(ST2.ROGUE.HUD_SLOTS[8].key, "kidney", "kidney appends at slot 8 (order stable)")
    eq(ST2.ROGUE.HUD_SLOTS[9].key, "restealth", "restealth appends at slot 9")
    eq(ST2.ROGUE.HUD_SLOTS[10].key, "bandage", "bandage appends at slot 10")
    eq(ST2.ROGUE.HUD_SLOTS[11].key, "coldblood", "Cold Blood appends at slot 11 (wired F3/V-G5)")
    eq(ST2.ROGUE.HUD_SLOTS[12].key, "trinket1", "trinkets shift but keep their slots")

    -- No default-visible change: the fixture ships no hud_show_kidney (nil).
    local s = ST2.ROGUE.get_hud_state(ST2, by_key.kidney, sb.clock)
    eq(s.hidden, true, "nil kidney toggle hides (no default-visible change)")
    s = ST2.ROGUE.get_hud_state(ST2, by_key.restealth, sb.clock)
    eq(s.hidden, true, "nil restealth toggle hides")
    s = ST2.ROGUE.get_hud_state(ST2, by_key.bandage, sb.clock)
    eq(s.hidden, true, "nil bandage toggle hides")
    sb.class_db.hud_show_kidney = false
    s = ST2.ROGUE.get_hud_state(ST2, by_key.kidney, sb.clock)
    eq(s.hidden, true, "explicit false kidney toggle hides")
    sb.class_db.hud_show_kidney = nil

    -- Kidney: ability-cooldown swipe while running, zero when ready; range tint.
    -- Name-vs-id rule (operator 2026-10-19): TBC queries by NAME.
    sb.class_db.hud_show_kidney = true
    sb.spell_cd = { ["Kidney Shot"] = { sb.clock - 4, 20 } }
    s = ST2.ROGUE.get_hud_state(ST2, by_key.kidney, sb.clock)
    eq(s.remaining, 16, "Kidney Shot reports the live cooldown")
    eq(s.duration, 20, "Kidney Shot reports the full cooldown")
    eq(s.desaturate, true, "a running Kidney Shot cooldown greys the icon")
    eq(s.hidden, nil, "a wanted Kidney slot is not hidden")
    sb.spell_cd = nil
    s = ST2.ROGUE.get_hud_state(ST2, by_key.kidney, sb.clock)
    eq(s.remaining, 0, "a ready Kidney Shot reads zero")
    sb.class_db.hud_show_kidney = nil

    -- Re-stealth (Vanish mapping UNCONFIRMED): buff wins, else cooldown swipe;
    -- absent under the secret regime hides (unknown, never "ready").
    sb.class_db.hud_show_restealth = true
    sb.auras = { player = { { name = "Vanish", duration = 10,
        expiration = sb.clock + 6, spell_id = 114 } } }
    s = ST2.ROGUE.get_hud_state(ST2, by_key.restealth, sb.clock)
    eq(s.remaining, 6, "an active Vanish buff reports its window")
    eq(s.hidden, nil, "an active Re-stealth is not hidden")
    sb.auras = {}
    sb.spell_cd = { ["Vanish"] = { sb.clock - 30, 300 } }
    s = ST2.ROGUE.get_hud_state(ST2, by_key.restealth, sb.clock)
    eq(s.remaining, 270, "Re-stealth reports the live Vanish cooldown")
    local real_probe = st2.api.auras_may_be_secret
    st2.api.auras_may_be_secret = function() return true end
    sb.clock = sb.clock + 0.05
    sb.auras = {}
    sb.spell_cd = nil
    s = ST2.ROGUE.get_hud_state(ST2, by_key.restealth, sb.clock)
    eq(s.hidden, true, "secret regime: absent Re-stealth hides (unknown)")
    st2.api.auras_may_be_secret = real_probe
    sb.class_db.hud_show_restealth = nil

    -- Bandage (rank UNCONFIRMED): item cooldown outranks the spell; an answered
    -- zero count greys the icon; an absent probe stays silent.
    sb.class_db.hud_show_bandage = true
    sb.bandage_count = 3
    sb.bandage_cd = { sb.clock - 10, 60 }
    s = ST2.ROGUE.get_hud_state(ST2, by_key.bandage, sb.clock)
    eq(s.remaining, 50, "Bandage reports the live item cooldown")
    eq(s.count, 3, "Bandage reports the answered item count")
    sb.bandage_cd = nil
    sb.bandage_count = 0
    s = ST2.ROGUE.get_hud_state(ST2, by_key.bandage, sb.clock)
    eq(s.remaining, 0, "no cooldown reads zero")
    eq(s.usable, false, "an empty bandage pouch is unusable")
    sb.bandage_count = nil
    s = ST2.ROGUE.get_hud_state(ST2, by_key.bandage, sb.clock)
    eq(s.count, 1, "the default pouch answers one (fixture shape)")
    sb.class_db.hud_show_bandage = nil

    -- Stacked multi-CD glow: AR + BF buffs together force the glow on both;
    -- a lone buff never stacks (only the final-seconds rule may glow it).
    sb.auras = { player = {
        { name = "Adrenaline Rush", duration = 15, expiration = sb.clock + 12,
            spell_id = 104 },
        { name = "Blade Flurry", duration = 15, expiration = sb.clock + 12,
            spell_id = 105 },
    } }
    s = ST2.ROGUE.get_hud_state(ST2, by_key.ar, sb.clock)
    eq(s.glow, true, "stacked AR + BF forces the AR yellow glow")
    s = ST2.ROGUE.get_hud_state(ST2, by_key.bf, sb.clock)
    eq(s.glow, true, "stacked AR + BF forces the BF yellow glow")
    sb.auras = { player = { { name = "Adrenaline Rush", duration = 15,
        expiration = sb.clock + 12, spell_id = 104 } } }
    s = ST2.ROGUE.get_hud_state(ST2, by_key.ar, sb.clock)
    eq(s.glow, nil, "a lone AR buff never stacks (12 s left, past the 3 s rule)")
    sb.auras = {}
end

-- R-1 GCD swipe (hud_parity §6): ready slots borrow the running GCD; a running
-- cooldown or live aura short-circuits first; no stamp (or an expired one)
-- means no swipe. Pins one slot per family: aura (snd/rupture/ea), CD
-- (kick/kidney/coldblood), item (tea/bandage).
do
    local sb = build()
    local ST2 = sb.ST
    ST2.ROGUE.post_init(ST2)
    local by_key = {}
    for i = 1, #ST2.ROGUE.HUD_SLOTS do
        by_key[ST2.ROGUE.HUD_SLOTS[i].key] = ST2.ROGUE.HUD_SLOTS[i]
    end
    sb.auras = {}
    sb.spell_cd = nil
    local s = ST2.ROGUE.get_hud_state(ST2, by_key.kick, sb.clock)
    eq(s.remaining, 0, "R-1: no GCD stamp means no swipe on a ready slot")
    ST2.gcd = { expires = sb.clock - 0.5 }
    s = ST2.ROGUE.get_hud_state(ST2, by_key.kick, sb.clock)
    eq(s.remaining, 0, "R-1: an expired GCD means no swipe")
    ST2.gcd = { expires = sb.clock + 1, spell_length = 1.5 }
    -- A running cooldown wins over the GCD.
    sb.spell_cd = { ["Adrenaline Rush"] = { sb.clock - 10, 300 } }
    s = ST2.ROGUE.get_hud_state(ST2, by_key.ar, sb.clock)
    eq(s.remaining, 290, "R-1: a running cooldown wins over the GCD")
    eq(s.text_remaining, 290, "R-1: the cooldown carries its own countdown text")
    sb.spell_cd = nil
    -- A live aura wins over the GCD.
    sb.auras = { player = { { name = "Slice and Dice", duration = 30,
        expiration = sb.clock + 20, spell_id = 101 } } }
    s = ST2.ROGUE.get_hud_state(ST2, by_key.snd, sb.clock)
    eq(s.remaining, 20, "R-1: a live aura wins over the GCD")
    sb.auras = {}
    -- Ready slots borrow per family.
    s = ST2.ROGUE.get_hud_state(ST2, by_key.snd, sb.clock)
    eq(s.remaining, 1, "R-1: a ready SnD borrows the running GCD")
    eq(s.text_remaining, 1, "R-1: the borrowed GCD carries countdown text")
    eq(s.desaturate, true, "R-1: the down-aura grey rides under the GCD swipe")
    s = ST2.ROGUE.get_hud_state(ST2, by_key.rupture, sb.clock)
    eq(s.remaining, 1, "R-1: a ready Rupture borrows the running GCD")
    s = ST2.ROGUE.get_hud_state(ST2, by_key.ea, sb.clock)
    eq(s.remaining, 1, "R-1: a ready Expose Armor borrows the running GCD")
    s = ST2.ROGUE.get_hud_state(ST2, by_key.kick, sb.clock)
    eq(s.remaining, 1, "R-1: a ready Kick borrows the running GCD")
    s = ST2.ROGUE.get_hud_state(ST2, by_key.tea, sb.clock)
    eq(s.remaining, 1, "R-1: a ready Thistle Tea borrows the running GCD")
    sb.class_db.hud_show_kidney = true
    s = ST2.ROGUE.get_hud_state(ST2, by_key.kidney, sb.clock)
    eq(s.remaining, 1, "R-1: a ready Kidney Shot borrows the running GCD")
    sb.class_db.hud_show_kidney = nil
    sb.class_db.hud_show_coldblood = true
    s = ST2.ROGUE.get_hud_state(ST2, by_key.coldblood, sb.clock)
    eq(s.remaining, 1, "R-1: a ready Cold Blood borrows the running GCD")
    eq(s.hidden, nil, "R-1: the borrowed slot is not hidden")
    sb.class_db.hud_show_coldblood = nil
    sb.class_db.hud_show_bandage = true
    s = ST2.ROGUE.get_hud_state(ST2, by_key.bandage, sb.clock)
    eq(s.remaining, 1, "R-1: a ready Bandage borrows the running GCD")
    sb.class_db.hud_show_bandage = nil
end

--=========================================================================================
-- 13) Rotation source: ST.ROGUE.get_rotation_key (the frozen contract)
--=========================================================================================
-- The hunter shape (classes/hunter.lua:1337-1352): the guide's own decision, so
-- the label and the guide can never disagree. The engine names no rotations, so
-- the label is the current action's localized name (from the guide's own slot
-- descriptors), POOL while holding, nil when idle/unknown.
do
    local sb = build()
    local ST2, st2 = sb.ST, sb.st
    check(type(ST2.ROGUE.get_rotation_key) == "function",
        "ROGUE.get_rotation_key is defined (the frozen contract)")
    check(type(ST2.ROGUE.rotation_out) == "table",
        "ST.ROGUE.rotation_out is the reused label table (no per-tick allocation)")

    -- Unknown core reads -> nil (no advice beats wrong advice, M6).
    sb.power[3] = nil
    sb.power[4] = nil
    eq(ST2.ROGUE.get_rotation_key(ST2), nil, "unknown energy/CP -> nil")

    -- Pool: low energy, no CP -> the engine holds and the label reads POOL.
    sb.power[3] = 50
    sb.power[4] = 0
    eq(ST2.ROGUE.get_rotation_key(ST2), "POOL", "pooling -> the POOL hold text")

    -- Spend: a capping bar prompts the builder; the slot descriptor resolves the
    -- localized name through the client's own spell data (post_init fill).
    ST2.ROGUE.post_init(ST2)
    sb.power[3] = 90
    sb.power[4] = 0
    local builder_slot
    for i = 1, #ST2.ROGUE.guide.slots do
        if ST2.ROGUE.guide.slots[i].key == "builder" then
            builder_slot = ST2.ROGUE.guide.slots[i]
        end
    end
    check(builder_slot ~= nil and builder_slot.spell_id == "Sinister Strike",
        "post_init resolves the TBC builder slot to the client name")
    eq(ST2.ROGUE.get_rotation_key(ST2), "Sinister Strike",
        "a spend names the localized builder")

    -- The unresolved fallback: a slot the client has not answered yet labels the
    -- raw action key instead of erroring or guessing.
    builder_slot.spell_id = nil
    builder_slot.spell_name = nil
    eq(ST2.ROGUE.get_rotation_key(ST2), "builder",
        "an unresolved slot falls back to the raw action key")
    builder_slot.spell_id = "Sinister Strike"
    builder_slot.spell_name = "Sinister Strike"

    -- No band, no verdict: RETAIL pools by phase, not by tick, so the guide is
    -- idle and the label is empty (the db bands cleared, as in a profile that
    -- predates the keys - the engine default for RETAIL has no tick line).
    st2.family = "RETAIL"
    sb.class_db.rogue_pool_band_pre, sb.class_db.rogue_pool_band_post = nil, nil
    sb.power[3] = 50
    eq(ST2.ROGUE.get_rotation_key(ST2), nil, "RETAIL (no tick band) -> nil")
    st2.family = "TBC"

    -- Missing engine: silent nil, never an error.
    local saved = st2.rogue_guide
    st2.rogue_guide = nil
    eq(ST2.ROGUE.get_rotation_key(ST2), nil, "missing engine -> nil")
    st2.rogue_guide = saved
end

--=========================================================================================
-- 14) Rotation-audit wiring (bench/rogue_rotation_audit_2026-10-19.md): family
-- builder identity, SnD/AR/BF gather, the AR-aware tick and wired-slot label
-- names. Fixture ids below are test-owned, never shipped (the addon
-- resolves names through the client's own spell data).
--=========================================================================================
do
    ROGUE_SPELLS_BY_ID[116] = { name = "Backstab", icon = "i_backstab" }
    ROGUE_SPELLS_BY_ID[117] = { name = "Mutilate", icon = "i_mutilate" }
    ROGUE_SPELLS_BY_ID[118] = { name = "Saber Slash", icon = "i_saber" }
    -- Hemorrhage (BS-6): the builder the corpus excluded as an uncertain name.
    -- Test-owned id, never shipped - the addon resolves the NAME through the
    -- client's own spell data (the sourced ids are cited in the source, not
    -- used for a lookup).
    ROGUE_SPELLS_BY_ID[121] = { name = "Hemorrhage", icon = "i_hemo" }
    ROGUE_SPELLS_BY_NAME["Backstab"] = 116
    ROGUE_SPELLS_BY_NAME["Mutilate"] = 117
    ROGUE_SPELLS_BY_NAME["Saber Slash"] = 118
    ROGUE_SPELLS_BY_NAME["Hemorrhage"] = 121

    local function builder_id(missing, items, opts)
        opts = opts or {}
        local sb2 = build({ project = opts.project })
        sb2.missing_spells = missing
        sb2.items = items
        sb2.known = opts.known
        local STx = sb2.ST
        STx.ROGUE.post_init(STx)
        for i = 1, #STx.ROGUE.guide.slots do
            if STx.ROGUE.guide.slots[i].key == "builder" then
                return STx.ROGUE.guide.slots[i].spell_id
            end
        end
        return nil
    end

    -- Sim-sourced chain (F1/H12 + BS-6): Saber Slash > Mutilate > Hemorrhage >
    -- dagger Backstab > Sinister Strike. Name-vs-id rule (operator 2026-10-19):
    -- TBC slots store the English name, Era the id.
    eq(builder_id(nil, nil), "Saber Slash", "all known: Saber Slash leads (SoD rune)")
    eq(builder_id({ ["Saber Slash"] = true }, nil), "Mutilate",
        "without Saber: Mutilate leads")
    eq(builder_id({ ["Saber Slash"] = true, ["Mutilate"] = true }, nil),
        "Hemorrhage",
        "without Saber/Mutilate: Hemorrhage leads (the TBC/Forever/Era builder)")
    eq(builder_id({ ["Saber Slash"] = true, ["Mutilate"] = true,
        ["Hemorrhage"] = true }, { [16] = 90002 }), "Backstab",
        "dagger mainhand without Saber/Mutilate/Hemorrhage: Backstab leads")
    eq(builder_id({ ["Saber Slash"] = true, ["Mutilate"] = true,
        ["Hemorrhage"] = true }, { [16] = 90001 }), "Sinister Strike",
        "sword mainhand without Saber/Mutilate/Hemorrhage: Sinister Strike leads")
    eq(builder_id({ ["Saber Slash"] = true, ["Mutilate"] = true,
        ["Hemorrhage"] = true, ["Backstab"] = true }, { [16] = 90002 }),
        "Sinister Strike",
        "unknown Backstab on a dagger falls back to Sinister Strike")
    eq(builder_id({ ["Saber Slash"] = true, ["Mutilate"] = true,
        ["Hemorrhage"] = true }, nil), "Sinister Strike",
        "unreadable mainhand never guesses a dagger (unknown-hides)")

    -- The family gate (BS-6): Hemorrhage is a TBC/Forever/Era builder, never a
    -- SoD one. The SoD client is the ERA token with the SoD-only Envenom rune
    -- known (the provider's frozen latch) - its builder is a rune.
    local sod_opts = { project = 2, known = { [399963] = true } }
    eq(builder_id(nil, nil, sod_opts), 118,
        "SoD: the rune still leads (Saber Slash)")
    eq(builder_id({ ["Saber Slash"] = true, ["Mutilate"] = true }, nil, sod_opts),
        108, "SoD: the gate keeps Hemorrhage off the SoD client (Sinister Strike leads)")
    eq(builder_id({ ["Saber Slash"] = true, ["Mutilate"] = true }, nil,
        { project = 11 }), 108,
        "Wrath: the gate keeps Hemorrhage off a family that has none")

    -- Era-id pinned (the name-vs-id rule): the Era slot stores the numeric id;
    -- the TBC slot above stores the English name. Era-base is the ERA token
    -- WITHOUT the SoD-only Envenom rune known (the fixture's IsSpellKnown
    -- answers true for everything else, so the rune is explicitly unknown).
    eq(builder_id({ ["Saber Slash"] = true, ["Mutilate"] = true }, nil,
        { project = 2, known = { [399963] = false } }), 121,
        "Era: the builder slot stores the id (the Hemorrhage fixture id)")

    -- The guide's builder slot id follows the winner: the rotation label names
    -- the resolved builder, not the chain's first candidate.
    local sbh = build()
    sbh.missing_spells = { ["Saber Slash"] = true, ["Mutilate"] = true }
    local STh = sbh.ST
    STh.ROGUE.post_init(STh)
    sbh.power[3], sbh.power[4] = 90, 0
    eq(STh.ROGUE.get_rotation_key(STh), "Hemorrhage",
        "the rotation label names the Hemorrhage builder (the slot id follows the winner)")

    -- The corpus correction is recorded in the shipped source: the name is
    -- certain, the ids are cited (TBC 26864 / Era-Forever 16511) and the old
    -- uncertain name is gone.
    local bsrc = read_file("classes/rogue.lua")
    check(bsrc:find("Hemo-Ghostly", 1, true) == nil,
        "BS-6: the uncertain 'Hemo-Ghostly' name is gone from the source")
    check(bsrc:find('{ "Saber Slash", "Mutilate", "Hemorrhage" }', 1, true) ~= nil,
        "BS-6: the builder chain carries Hemorrhage behind the rune candidates")
    check(bsrc:find("26864", 1, true) ~= nil and bsrc:find("16511", 1, true) ~= nil,
        "BS-6: the source cites the corrected ids (TBC 26864 / Era-Forever 16511)")

    -- SnD/AR/BF gather: live aura + readiness reads, no new db keys.
    local sb = build()
    local ST2 = sb.ST
    sb.power[3] = 50
    sb.power[4] = 2
    local inputs = ST2.ROGUE.gather_guide_inputs(ST2, {})
    eq(inputs.snd_usable, true, "SnD resolves from the client's spell data")
    eq(inputs.snd_remains, nil, "no SnD aura reads missing (upkeep gap)")
    eq(inputs.ar_ready, true, "AR reads ready (known + usable + off cooldown)")
    eq(inputs.bf_ready, true, "BF reads ready")
    sb.auras = { player = { { name = "Slice and Dice", duration = 30,
        expiration = sb.clock + 20, spell_id = 101 } } }
    inputs = ST2.ROGUE.gather_guide_inputs(ST2, {})
    eq(inputs.snd_remains, 20, "an active SnD reports its window")
    -- Name-vs-id rule: TBC cooldown queries by NAME.
    sb.spell_cd = { ["Adrenaline Rush"] = { sb.clock - 10, 300 } }
    inputs = ST2.ROGUE.gather_guide_inputs(ST2, {})
    eq(inputs.ar_ready, nil, "a running AR cooldown reads unready")
    sb.spell_cd = nil
    sb.auras = {}

    -- AR-aware tick (F2 residual): +40 re-anchors while AR rides, +20 hides.
    local sb3 = build()
    local ST3 = sb3.ST
    eq(ST3.ROGUE.update_energy_tick(ST3, 0.0, 40, 100, 40), nil,
        "AR regime: no anchor yet")
    near(ST3.ROGUE.update_energy_tick(ST3, 0.5, 80, 100, 40), 2.0, 1e-9,
        "AR regime: a +40 gain seeds and predicts 2 s")
    eq(ST3.ROGUE.update_energy_tick(ST3, 1.0, 100, 100, 40), nil,
        "AR regime: a +20 gain hides (H4 — not an AR tick)")
    eq(ST3.ROGUE.update_energy_tick(ST3, 0.0, 40, 100), nil,
        "a missing gain falls back to the classic 20")
    -- Through the live sample: the regime is proven from the AR buff.
    local sb4 = build()
    local ST4 = sb4.ST
    ST4.ROGUE.post_init(ST4)
    sb4.auras = { player = { { name = "Adrenaline Rush", duration = 15,
        expiration = sb4.clock + 12, spell_id = 104 } } }
    sb4.power[3] = 40
    ST4.ROGUE.sample_energy_tick(ST4, 0.0)
    sb4.power[3] = 80
    near(ST4.ROGUE.sample_energy_tick(ST4, 2.0), 2.0, 1e-9,
        "AR riding: a +40 sample re-anchors the phase")

    -- Slot-less audit actions (icons filed): the rotation label names them.
    sb.power[3] = 50
    sb.power[4] = 2
    eq(ST2.ROGUE.get_rotation_key(ST2), "Slice and Dice",
        "missing SnD with 2 CP labels Slice and Dice (wired slot, same name)")
end

--=========================================================================================
-- 15) H6 duty window + SoD Envenom latch (bench/open_rules_2026-10-19.md H6,
-- bench/sod_detect_2026-10-19.md): the TBC wait/release and the Forever
-- lockout ride the existing rogue_ea_duty toggle (no new keys); the SOD table
-- is reached only as ERA + the SoD-only Envenom rune known. Fixture spell ids
-- are test-owned, never shipped.
--=========================================================================================
do
    -- The duty toggle feeds the engine flag, off by default (nil reads false).
    local sb = build()
    local ST2 = sb.ST
    sb.power[3] = 50
    sb.power[4] = 0
    local inputs = ST2.ROGUE.gather_guide_inputs(ST2, {})
    eq(inputs.ea_duty, false, "EA duty ships off (nil reads false)")
    eq(inputs.sod_envenom, nil, "no latch without post_init (nil reads Era-base)")
    sb.class_db.rogue_ea_duty = true
    inputs = ST2.ROGUE.gather_guide_inputs(ST2, {})
    eq(inputs.ea_duty, true, "the duty toggle feeds the engine flag")

    -- SoD latch matrix: ERA + rune-known latches, everything else Era-base.
    local era_base = build({ project = 2 })
    era_base.known = { [399963] = false }
    era_base.ST.ROGUE.post_init(era_base.ST)
    check(era_base.ST.rogue_is_sod ~= true, "Era-base (rune unknown) never latches")
    local era_sod = build({ project = 2 })
    era_sod.known = { [399963] = true }
    era_sod.ST.ROGUE.post_init(era_sod.ST)
    check(era_sod.ST.rogue_is_sod == true, "ERA + Envenom-rune-known latches SoD")
    local tbc_sod = build()
    tbc_sod.known = { [399963] = true }
    tbc_sod.ST.ROGUE.post_init(tbc_sod.ST)
    check(tbc_sod.ST.rogue_is_sod ~= true, "TBC never latches (ERA gate)")
    -- Frozen at post_init (warrior/hunter shape): a rune learned mid-session
    -- needs /reload.
    era_base.known = { [399963] = true }
    local refrozen = era_base.ST.ROGUE.gather_guide_inputs(era_base.ST, {})
    eq(refrozen.sod_envenom, nil, "the latch is frozen (no live re-probe)")

    -- Gather feeds the latch through.
    local latched = era_sod.ST.ROGUE.gather_guide_inputs(era_sod.ST, {})
    eq(latched.sod_envenom, true, "gather reports the frozen SoD latch")
    local unlatched = era_base.ST.ROGUE.gather_guide_inputs(era_base.ST, {})
    eq(unlatched.sod_envenom, nil, "gather stays silent on Era-base")

    -- End to end: ERA + latch Envenoms at 4CP on a living target (SOD primary);
    -- Era-base with the same reads never does.
    local function sod_action(sbx, stacks)
        sbx.power[3] = 50
        sbx.power[4] = 4
        -- SnD healthy (rule 1b passes through) and BF cooling (5c passes
        -- through): the verdict under test is rule 3 alone.
        sbx.spell_cd = { [105] = { sbx.clock - 10, 300 } }
        sbx.auras = {
            target = { { name = "Deadly Poison", duration = 30,
                expiration = sbx.clock + 30, spell_id = 112, count = stacks } },
            player = { { name = "Slice and Dice", duration = 30,
                expiration = sbx.clock + 20, spell_id = 101 } },
        }
        local got = sbx.ST.ROGUE.gather_guide_inputs(sbx.ST, {})
        got.ttd = 30 -- fixture TTD control (the EMA itself is pinned in §10)
        local out = sbx.st.rogue_guide.evaluate(got, {})
        return out.action
    end
    eq(sod_action(era_sod, 1), "envenom", "SoD: 4 CP + stacks primary-dumps")
    eq(sod_action(era_base, 1), nil, "Era-base: the same bar never Envenoms")
end

--=========================================================================================
-- 16) H6 through the real frame: the TBC wait holds POOL, the pool line exposes
--=========================================================================================
do
    local sb = build()
    local ST2, st2 = sb.ST, sb.st
    local ui = st2.nextaction_ui
    ST2.ROGUE.post_init(ST2)
    sb.class_db.nextaction_enabled = true
    sb.class_db.nextaction_visibility_key = "always"
    sb.class_db.rogue_ea_duty = true
    -- The TBC duty line is 71 (the engine default); the fixture mirrors the
    -- stock 65/85 db defaults, so the sim line is tuned in explicitly here.
    sb.class_db.rogue_pool_band_pre = 71
    sb.class_db.rogue_pool_band_post = 71
    ST2.in_combat = true
    ST2.mainhand = { speed = 2.6, start = 0, ends_at = 0, is_full = false }
    local function live_swing(clock)
        sb.clock = clock
        ST2.mainhand.start = clock - 0.5
        ST2.mainhand.ends_at = clock + 2.1
    end

    -- Blade Flurry on cooldown: the wait pins the HOLD, not the BF prompt
    -- (5c stays live through the wait by sim design).
    -- Name-vs-id rule: TBC cooldown queries by NAME.
    sb.power[3] = 50
    sb.power[4] = 5
    live_swing(100)
    sb.spell_cd = { ["Blade Flurry"] = { 90, 300 } }
    sb.auras = {
        target = { { name = "Expose Armor", duration = 30,
            expiration = 110, spell_id = 103 } },
        player = { { name = "Slice and Dice", duration = 30,
            expiration = 120, spell_id = 101 } },
    }
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(ui.frame:IsShown(), true, "the duty guide is eligible on a live swing")
    eq(ui.frame.hold.text.text, "POOL", "the TBC wait holds POOL on the frame")
    local any_target = false
    for i = 1, #ui.icons do
        if ui.targets[i] ~= 0 then any_target = true end
    end
    eq(any_target, false, "the wait targets no advice icon")

    -- The pool line releases into Expose on the frame.
    sb.power[3] = 80
    live_swing(110)
    sb.auras.target[1].expiration = 120
    sb.auras.player[1].expiration = 130
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(ui.targets[ui.slot_index.expose], 1, "the pool line prompts Expose")
    eq(ui.frame.hold.text.text, "NOW", "the release carries the ride overlay")
end

--=========================================================================================
-- 17) Rogue-leftovers gather (T-G4/F3/V-G5): Mutilate-known, Cold Blood
-- readiness, wired-slot label + frame. All live reads, no new db keys.
--=========================================================================================
do
    -- Mutilate-known feeds the TBC Shiv gate (strict true only).
    -- Name-vs-id rule (operator 2026-10-19): TBC knowledge queries by NAME.
    local function mutilate_inputs(mod)
        local sbx = build()
        sbx.power[3] = 50
        sbx.power[4] = 0
        if mod == "missing" then
            sbx.missing_spells = { Mutilate = true }
        elseif mod == "unlearned" then
            sbx.known = { ["Mutilate"] = false }
        end
        return sbx.ST.ROGUE.gather_guide_inputs(sbx.ST, {})
    end
    eq(mutilate_inputs(nil).mutilate_known, true,
        "Mutilate resolved + known reads true")
    eq(mutilate_inputs("missing").mutilate_known, nil,
        "unresolved Mutilate reads nil (upkeep kept)")
    eq(mutilate_inputs("unlearned").mutilate_known, nil,
        "unlearned Mutilate reads nil (never a guessed gate)")

    -- Cold Blood readiness mirrors Shiv/AR (known + usable + off cooldown).
    -- Name-vs-id rule: TBC queries by NAME.
    local function cb_inputs(mod)
        local sbx = build()
        sbx.power[3] = 50
        sbx.power[4] = 4
        if mod == "missing" then
            sbx.missing_spells = { ["Cold Blood"] = true }
        elseif mod == "cd" then
            sbx.spell_cd = { ["Cold Blood"] = { sbx.clock - 10, 300 } }
        elseif mod == "unusable" then
            sbx.usable = { ["Cold Blood"] = false }
        end
        return sbx.ST.ROGUE.gather_guide_inputs(sbx.ST, {})
    end
    eq(cb_inputs(nil).coldblood_ready, true, "a ready Cold Blood reads true")
    eq(cb_inputs("missing").coldblood_ready, nil,
        "an unresolved Cold Blood never prompts")
    eq(cb_inputs("cd").coldblood_ready, nil,
        "a cooling Cold Blood never prompts")
    eq(cb_inputs("unusable").coldblood_ready, nil,
        "an unusable Cold Blood never prompts")

    -- Wired Cold Blood through the rotation label (TBC build, BF cooling
    -- so the 5d line under test owns the verdict) and the real frame.
    -- Name-vs-id rule: TBC cooldown queries by NAME.
    local sb = build()
    local ST2, st2 = sb.ST, sb.st
    local ui = st2.nextaction_ui
    ST2.ROGUE.post_init(ST2)
    sb.power[3] = 50
    sb.power[4] = 4
    sb.spell_cd = { ["Blade Flurry"] = { sb.clock - 10, 300 } }
    sb.auras = { player = { { name = "Slice and Dice", duration = 30,
        expiration = sb.clock + 20, spell_id = 101 } } }
    eq(ST2.ROGUE.get_rotation_key(ST2), "Cold Blood",
        "a ready Cold Blood behind SnD labels Cold Blood (wired slot)")
    check(ui.slot_index.coldblood ~= nil, "the frame indexes the Cold Blood slot")

    -- Through the real frame: the wired action lights its icon with NOW.
    sb.class_db.nextaction_enabled = true
    sb.class_db.nextaction_visibility_key = "always"
    ST2.in_combat = true
    ST2.mainhand = { speed = 2.6, start = 0, ends_at = 0, is_full = false }
    sb.clock = 100
    ST2.mainhand.start = 99.5
    ST2.mainhand.ends_at = 102.1
    sb.auras.player[1].expiration = sb.clock + 20
    sb.spell_cd = { ["Blade Flurry"] = { sb.clock - 10, 300 } }
    ST2.ROGUE.on_bar_update(ST2, "mainhand")
    eq(ui.targets[ui.slot_index.coldblood], 1, "Cold Blood targets its wired icon")
    eq(ui.frame.hold.fade.target, 1, "a wired action shows the ride overlay")
    eq(ui.frame.hold.text.text, "NOW", "the ride overlay reads NOW")
end

--=========================================================================================
-- 18) Per-CP Rupture rows (W-M2): engine-side DATA only, provider passes CP
-- through, no new db key, flat floors still govern (no default-visible change)
--=========================================================================================
do
    -- No provider-side duration key: the durations live engine-side as DATA;
    -- the provider only passes CP through (options own any future widget).
    local percp_src = read_file("classes/rogue.lua")
    check(percp_src:find("rogue_rupture_duration", 1, true) == nil,
        "per-CP: no duration db key (existing refresh/min_ttd keys untouched)")

    local sb = build()
    local ST2 = sb.ST
    local rg = sb.st.rogue_guide
    -- Engine DATA (sourced rows only) is visible through the provider sandbox.
    eq(rg.RUPTURE_DURATION_BY_CP[1], 8, "engine DATA: 1CP Rupture lasts 8 s (W-M2)")
    eq(rg.RUPTURE_DURATION_BY_CP[5], 16, "engine DATA: 5CP Rupture lasts 16 s (W-M2)")
    eq(rg.RUPTURE_DURATION_BY_CP[2], nil, "engine DATA: 2CP stays UNCONFIRMED")
    eq(rg.RUPTURE_DURATION_BY_CP[3], nil, "engine DATA: 3CP stays UNCONFIRMED")
    eq(rg.RUPTURE_DURATION_BY_CP[4], nil, "engine DATA: 4CP stays UNCONFIRMED")
    eq(rg.rupture_duration_for_cp(1), 8, "engine lookup: 1CP answers 8")
    eq(rg.rupture_duration_for_cp(5), 16, "engine lookup: 5CP answers 16")
    eq(rg.rupture_duration_for_cp(3), nil, "engine lookup: 3CP hides")

    -- Gather passes CP through for the engine-side lookup; no tuning key means
    -- the engine default governs (nil = engine default, never invented).
    sb.power[3] = 50
    sb.power[4] = 1
    local one = ST2.ROGUE.gather_guide_inputs(ST2, {})
    eq(one.cp, 1, "gather passes 1CP through for the engine-side lookup")
    eq(one.rupture_min_ttd, nil, "no tuning key: the engine default governs")
    eq(one.rupture_duration_by_cp, nil, "gather invents no duration input")
    sb.power[4] = 5
    local five = ST2.ROGUE.gather_guide_inputs(ST2, {})
    eq(five.cp, 5, "gather passes 5CP through for the engine-side lookup")

    -- End to end (TBC family, pure evaluate): a 5CP TTD-10 target with
    -- Rupture missing still Ruptures on the flat 5 s floor — the 16 s DATA
    -- row does not move the verdict (DATA-only, no default-visible change).
    sb.power[3] = 50
    sb.power[4] = 5
    sb.auras = { player = { { name = "Slice and Dice", duration = 30,
        expiration = sb.clock + 20, spell_id = 101 } } }
    local got = ST2.ROGUE.gather_guide_inputs(ST2, {})
    got.ttd = 10
    eq(sb.st.rogue_guide.evaluate(got, {}).action, "rupture",
        "DATA-only: TBC 5CP TTD 10 Ruptures on the flat floor (not the 16 s row)")
end

--=========================================================================================
-- 19) Name-vs-id rule (operator 2026-10-19): TBC resolves by NAME never bare id;
-- Era by id. Both resolutions pinned here; rogue_guide.lua has zero spell-id uses
-- (pure engine, verified by grep — no conversion). Pickpocket/CttC: zero id uses
-- in classes/rogue.lua (no probes shipped — nothing to convert).
--=========================================================================================
do
    -- Helper live with family branching (compat.lua, shared, one probe max).
    local tbc = build()
    check(type(tbc.st.api.get_spell_query) == "function",
        "compat: the shared name-vs-id helper exists")
    eq(tbc.st.api.get_spell_query("Bloodlust", 2825), "Bloodlust",
        "TBC: the helper returns the NAME")
    eq(tbc.st.api.get_spell_query("Slice and Dice", 101), "Slice and Dice",
        "TBC: slot queries return the name")
    local era = build({ project = 2 })
    eq(era.st.api.get_spell_query("Bloodlust", 2825), 2825,
        "Era: the helper returns the ID")
    eq(era.st.api.get_spell_query("Slice and Dice", 101), 101,
        "Era: slot queries return the id")
    local wrath = build({ project = 11 })
    eq(wrath.st.api.get_spell_query("Bloodlust", 2825), 2825,
        "Wrath (non-TBC): the helper returns the id")

    -- Slots store the family-correct query.
    tbc.ST.ROGUE.post_init(tbc.ST)
    era.ST.ROGUE.post_init(era.ST)
    local tbc_kick, era_kick
    for i = 1, #tbc.ST.ROGUE.HUD_SLOTS do
        if tbc.ST.ROGUE.HUD_SLOTS[i].key == "kick" then
            tbc_kick = tbc.ST.ROGUE.HUD_SLOTS[i]
        end
        if era.ST.ROGUE.HUD_SLOTS[i].key == "kick" then
            era_kick = era.ST.ROGUE.HUD_SLOTS[i]
        end
    end
    eq(tbc_kick.spell, "Kick", "TBC: HUD slots store the NAME (never a bare id)")
    eq(type(era_kick.spell), "number", "Era: HUD slots store the ID")
    local tbc_builder, era_builder
    for i = 1, #tbc.ST.ROGUE.guide.slots do
        if tbc.ST.ROGUE.guide.slots[i].key == "builder" then
            tbc_builder = tbc.ST.ROGUE.guide.slots[i]
        end
        if era.ST.ROGUE.guide.slots[i].key == "builder" then
            era_builder = era.ST.ROGUE.guide.slots[i]
        end
    end
    eq(tbc_builder.spell_id, "Saber Slash",
        "TBC: guide slots store the NAME (all known: Saber leads)")
    eq(era_builder.spell_id, 118,
        "Era: guide slots store the ID (all known: Saber 118 leads)")

    -- Cooldowns: TBC answers the NAME probe, ignores a bare-id probe; Era the reverse.
    tbc.clock = 100
    tbc.spell_cd = { ["Adrenaline Rush"] = { 90, 300 } }
    local tbc_ar = tbc.ST.ROGUE.get_hud_state(tbc.ST,
        tbc.ST.ROGUE.HUD_SLOTS[4], tbc.clock)
    eq(tbc_ar.remaining, 290, "TBC: the NAME cooldown reads live")
    tbc.spell_cd = { [104] = { 90, 300 } }
    tbc_ar = tbc.ST.ROGUE.get_hud_state(tbc.ST,
        tbc.ST.ROGUE.HUD_SLOTS[4], tbc.clock)
    eq(tbc_ar.remaining, 0, "TBC: a bare-id probe never fires (ignored)")
    era.clock = 100
    era.spell_cd = { [104] = { 90, 300 } }
    local era_ar
    for i = 1, #era.ST.ROGUE.HUD_SLOTS do
        if era.ST.ROGUE.HUD_SLOTS[i].key == "ar" then
            era_ar = era.ST.ROGUE.get_hud_state(era.ST,
                era.ST.ROGUE.HUD_SLOTS[i], era.clock)
        end
    end
    eq(era_ar.remaining, 290, "Era: the ID cooldown reads live")
    era.spell_cd = { ["Adrenaline Rush"] = { 90, 300 } }
    for i = 1, #era.ST.ROGUE.HUD_SLOTS do
        if era.ST.ROGUE.HUD_SLOTS[i].key == "ar" then
            era_ar = era.ST.ROGUE.get_hud_state(era.ST,
                era.ST.ROGUE.HUD_SLOTS[i], era.clock)
        end
    end
    eq(era_ar.remaining, 0, "Era: a NAME probe never fires (id-only)")

    -- Auras: id primary, name secondary on every family (the hunter R1
    -- discipline). Either shape lands the read on either client.
    tbc.auras = { player = { { name = "Slice and Dice", duration = 30,
        expiration = tbc.clock + 20, spell_id = 999999 } } }
    local tbc_snd = tbc.ST.ROGUE.get_hud_state(tbc.ST,
        tbc.ST.ROGUE.HUD_SLOTS[1], tbc.clock)
    eq(tbc_snd.remaining, 20, "TBC: the aura matches by NAME (wrong id ignored)")
    tbc.auras = { player = { { name = "WRONG NAME", duration = 30,
        expiration = tbc.clock + 20, spell_id = 101 } } }
    tbc_snd = tbc.ST.ROGUE.get_hud_state(tbc.ST,
        tbc.ST.ROGUE.HUD_SLOTS[1], tbc.clock)
    eq(tbc_snd.remaining, 20, "TBC: the id arm lands a foreign-named aura")
    era.auras = { player = { { name = "WRONG NAME", duration = 30,
        expiration = era.clock + 20, spell_id = 101 } } }
    local era_snd
    for i = 1, #era.ST.ROGUE.HUD_SLOTS do
        if era.ST.ROGUE.HUD_SLOTS[i].key == "snd" then
            era_snd = era.ST.ROGUE.get_hud_state(era.ST,
                era.ST.ROGUE.HUD_SLOTS[i], era.clock)
        end
    end
    eq(era_snd.remaining, 20, "Era: the aura matches by ID (wrong name ignored)")
    era.auras = { player = { { name = "Slice and Dice", duration = 30,
        expiration = era.clock + 20, spell_id = 999999 } } }
    for i = 1, #era.ST.ROGUE.HUD_SLOTS do
        if era.ST.ROGUE.HUD_SLOTS[i].key == "snd" then
            era_snd = era.ST.ROGUE.get_hud_state(era.ST,
                era.ST.ROGUE.HUD_SLOTS[i], era.clock)
        end
    end
    eq(era_snd.remaining, 20, "Era: the name arm lands an id-less aura")

    -- Lust canary: id primary, name secondary on every family. Either shape
    -- lands the read on either client.
    tbc.auras = { player = { { name = "Bloodlust", duration = 40,
        expiration = tbc.clock + 30, spell_id = 999999 } } }
    tbc.ST.rogue_lust_at = nil
    tbc.ST.ROGUE.update_lust_state(tbc.ST, tbc.clock)
    check(tbc.ST.rogue_lust_remaining ~= nil,
        "TBC: lust matches by NAME (wrong id ignored)")
    tbc.auras = { player = { { name = "WRONG", duration = 40,
        expiration = tbc.clock + 30, spell_id = 2825 } } }
    tbc.ST.rogue_lust_at = nil
    tbc.ST.ROGUE.update_lust_state(tbc.ST, tbc.clock)
    check(tbc.ST.rogue_lust_remaining ~= nil,
        "TBC: a bare lust id still lands (Anniversary id shape)")
    tbc.auras = {}
    local wr = build({ project = 11 })
    wr.ST.ROGUE.post_init(wr.ST)
    wr.clock = 100
    wr.auras = { player = { { name = "WRONG", duration = 40,
        expiration = wr.clock + 30, spell_id = 2825 } } }
    wr.ST.ROGUE.update_lust_state(wr.ST, wr.clock)
    check(wr.ST.rogue_lust_remaining ~= nil,
        "Wrath: lust matches by ID (wrong name ignored)")

    -- Rotation label: TBC uses the cached NAME (never a bare-id GetSpellInfo);
    -- Era resolves the localized name through the id.
    local tbc_calls = {}
    local real_tbc_info = tbc.st.api.GetSpellInfo
    tbc.st.api.GetSpellInfo = function(spell)
        tbc_calls[#tbc_calls + 1] = spell
        return real_tbc_info(spell)
    end
    tbc.ST.ROGUE.post_init(tbc.ST)
    tbc.power[3], tbc.power[4] = 90, 0
    eq(tbc.ST.ROGUE.get_rotation_key(tbc.ST), "Saber Slash",
        "TBC: the label names the builder from the cached NAME (all known: Saber leads)")
    local tbc_bare = false
    for i = 1, #tbc_calls do
        if type(tbc_calls[i]) == "number" then
            tbc_bare = true
        end
    end
    check(not tbc_bare, "TBC: no bare-id GetSpellInfo during the label")
    tbc.st.api.GetSpellInfo = real_tbc_info
    -- The shared era build still files the synthetic name-only SnD row above,
    -- which the new name arm reads as up: reset to a row both arms miss so the
    -- engine recommends the builder, exactly the label's precondition.
    era.auras = { player = { { name = "WRONG NAME", duration = 30,
        expiration = era.clock + 20, spell_id = 999999 } } }
    era.power[3], era.power[4] = 90, 0
    eq(era.ST.ROGUE.get_rotation_key(era.ST), "Saber Slash",
        "Era: the label resolves through the ID (all known: Saber leads)")

    -- SoD latch stays Era-by-id (frozen at post_init, TBC never probes).
    local era_sod = build({ project = 2 })
    era_sod.known = { [399963] = true }
    era_sod.ST.ROGUE.post_init(era_sod.ST)
    check(era_sod.ST.rogue_is_sod == true,
        "Era: the SoD latch probes the rune ID (399963 UNCONFIRMED in-client)")
    local tbc_sod = build()
    tbc_sod.known = { [399963] = true }
    tbc_sod.ST.ROGUE.post_init(tbc_sod.ST)
    check(tbc_sod.ST.rogue_is_sod ~= true,
        "TBC: the ERA gate withholds the id probe (never a bare TBC id)")

    -- Static pins: every spell-id use classified. No pickpocket/CttC id probes
    -- shipped (zero uses — nothing to convert); item probes stay name-based
    -- (Thistle Tea / Heavy Netherweave Bandage) on both families.
    local src = read_file("classes/rogue.lua")
    check(src:find("Pickpocket", 1, true) == nil,
        "pickpocket: no id probe shipped (zero uses)")
    check(src:find("ROGUE_SOD_ENVENOM_RUNE_ID", 1, true) ~= nil,
        "sod: the Era-only rune id is the single bare id (gated, pinned above)")
    check(src:find("ROGUE_LUST_NAMES", 1, true) ~= nil,
        "lust: the TBC NAME table ships alongside the Era id table")
    check(src:find("rogue_query", 1, true) ~= nil,
        "query: every live read funnels through the family-correct query")
end

--=========================================================================================
-- 15) Practice seam + options entry + designer coverage
--=========================================================================================
do
    -- Seam surface: every entry point the drill shell (practice_ui rogue
    -- branches) uses to drive the rogue registry drills.
    for _, fn in ipairs({ "practice_sync", "practice_scenario_key",
        "practice_ss_scenario_key", "new_practice_session", "new_ss_session",
        "practice_begin_session", "tick_practice_session", "practice_spend",
        "practice_ss", "practice_cast", "practice_cast_order",
        "practice_cast_label", "practice_cast_spell_id", "practice_status",
        "practice_fight_elapsed", "practice_shift_pause",
        "end_practice_session" }) do
        check(type(ST.ROGUE[fn]) == "function", "ROGUE." .. fn .. " is defined")
    end
    check(type(ST.ROGUE.PRACTICE_CAST_ORDER) == "table",
        "ROGUE.PRACTICE_CAST_ORDER declares the drill order")

    -- Family matrix (wow-ui-source: classic_era / classic_anniversary /
    -- origin/forever): the seam is pure harness math, so the drill keys resolve
    -- and grade identically on Era, TBC Anniversary and Forever; anything the
    -- client cannot read hides (nil) instead of throwing.
    local families = {
        { name = "Era", opts = { project = 2 } },
        { name = "TBC", opts = {} },
        { name = "Forever", opts = { project = 18 } },
    }
    for _, fam in ipairs(families) do
        local fb = build(fam.opts)
        local FST, fst = fb.ST, fb.st
        eq(FST.ROGUE.practice_scenario_key(), "rogue_energy_pool",
            fam.name .. ": the pool drill key resolves")
        eq(FST.ROGUE.practice_ss_scenario_key(), "rogue_ss_window",
            fam.name .. ": the SS drill key resolves")
        eq(FST.ROGUE.practice_sync(FST), 0,
            fam.name .. ": practice_sync reports no seal state")
        -- Drill order + cast labels: Era runs both drills, TBC/Forever pool only
        -- (the SS window is Era sword technique; rogue_deep REFUTED it on TBC+).
        local order = FST.ROGUE.practice_cast_order()
        check(type(order) == "table", fam.name .. ": the cast order is a table")
        if fam.name == "Era" then
            eq(#order, 2, "Era: both drill casts offered")
            eq(order[1], "evisc", "Era: the pool spend leads")
            eq(order[2], "ss", "Era: the SS window follows")
        else
            eq(#order, 1, fam.name .. ": pool only (SS is Era technique)")
            eq(order[1], "evisc", fam.name .. ": the pool spend leads")
        end
        eq(FST.ROGUE.practice_cast_label("evisc"), "Pool Spend",
            fam.name .. ": the spend label reads")
        eq(FST.ROGUE.practice_cast_label("ss"), "SS Window",
            fam.name .. ": the window label reads")
        eq(FST.ROGUE.practice_cast_label("bogus"), nil,
            fam.name .. ": unknown keys have no label")
        eq(FST.ROGUE.practice_cast_spell_id("evisc"), "Eviscerate",
            fam.name .. ": the spend icon resolves by name")
        eq(FST.ROGUE.practice_cast_spell_id("ss"), "Sinister Strike",
            fam.name .. ": the window icon resolves by name")
        -- post_init stays inert without the practice files (guarded, no error);
        -- with them it builds the shared panel frames (the call the paladin and
        -- druid post_inits make).
        fst.practice_ui = nil
        local ok, err = pcall(FST.ROGUE.post_init, FST)
        check(ok, fam.name .. ": post_init is inert without practice_ui ("
            .. tostring(err) .. ")")
        local inited = 0
        fst.practice_ui = { init = function() inited = inited + 1 end }
        FST.ROGUE.post_init(FST)
        eq(inited, 1, fam.name .. ": post_init builds the practice panel frames")
    end

    -- Absent modules: every entry degrades to nil/false/empty, never an error.
    do
        local fb = build()
        local FST, fst = fb.ST, fb.st
        local saved = fst.practice
        fst.practice = nil
        eq(FST.ROGUE.practice_scenario_key(), nil,
            "absent practice: the pool key hides")
        eq(FST.ROGUE.practice_ss_scenario_key(), nil,
            "absent practice: the SS key hides")
        eq(FST.ROGUE.new_practice_session(0), nil,
            "absent practice: no pool session starts")
        eq(FST.ROGUE.new_ss_session(0), nil,
            "absent practice: no SS session starts")
        eq(FST.ROGUE.practice_begin_session({}, 0), false,
            "absent practice: no run begins")
        eq(FST.ROGUE.practice_spend({}, 0, 0.9), nil,
            "absent practice: no spend grades")
        eq(FST.ROGUE.practice_ss({}, 0, 0.1), nil,
            "absent practice: no strike grades")
        eq(FST.ROGUE.practice_cast(nil, 0, "evisc"), nil,
            "absent practice: no cast grades")
        eq(#FST.ROGUE.practice_cast_order(), 0,
            "absent practice: the cast order is empty, never nil")
        eq(FST.ROGUE.practice_status(nil, 0), "Pool: --",
            "absent practice: the status hides")
        eq(FST.ROGUE.practice_fight_elapsed(nil, 0), nil,
            "absent practice: no fight clock reads")
        eq(FST.ROGUE.end_practice_session({}, 0), false,
            "absent practice: no session ends")
        fst.practice = saved
    end

    -- End-to-end pool drill through the shell contract: new creates unbegun,
    -- begin starts the run, casts grade through the tick phase.
    do
        local fb = build()
        local FST, fst = fb.ST, fb.st
        local H = fst.practice.harness
        local session = FST.ROGUE.new_practice_session(0)
        check(session ~= nil, "pool: new_practice_session creates the run")
        check(session.active ~= true, "pool: the run starts unbegun")
        -- Pre-begin casts never score (the harness requires an active session).
        eq(FST.ROGUE.practice_cast(
            { energy = session, tick = { start = 0, interval = 2 } }, 1.9, "evisc"),
            nil, "pool: an unbegun run grades nil")
        check(FST.ROGUE.practice_begin_session(session, 0) == true,
            "pool: practice_begin_session starts the run")
        local drill = { energy = session, tick = { start = 0, interval = 2 } }
        -- Fraction ((1.9-0)%2)/2 = 0.95: on the marker, margin 0 -> S.
        eq(FST.ROGUE.practice_cast(drill, 1.9, "evisc"), "S",
            "pool: a tick-edge spend grades S")
        -- Fraction 0.5: margin 0.45 -> D.
        eq(FST.ROGUE.practice_cast(drill, 1.0, "evisc"), "D",
            "pool: an early spend grades D")
        -- Past the marker -> F; unknown keys never score.
        eq(FST.ROGUE.practice_cast(drill, 1.98, "evisc"), "F",
            "pool: a past-marker spend grades F")
        eq(FST.ROGUE.practice_cast(drill, 1.9, "bogus"), nil,
            "pool: an unknown key grades nil")
        eq(H.session_summary(session).attempts, 3,
            "pool: three graded spends are recorded")
        local out = {}
        eq(FST.ROGUE.tick_practice_session(session, 1.9, 0.05, out), out,
            "pool: the tick passes the out table through")
        eq(FST.ROGUE.practice_fight_elapsed(session, 5), 5,
            "pool: the fight clock reads the run")
        eq(FST.ROGUE.end_practice_session(session, 0.1), true,
            "pool: end_practice_session stops the run")
        eq(FST.ROGUE.end_practice_session(session, 0.2), false,
            "pool: ending an ended run is safe")
        -- Unknown tick reads never guess: unscored and unrecorded.
        local unscored = FST.ROGUE.new_practice_session(0, { tick_known = false })
        FST.ROGUE.practice_begin_session(unscored, 0)
        eq(FST.ROGUE.practice_cast(
            { energy = unscored, tick = { start = 0, interval = 2 } }, 1.9, "evisc"),
            nil, "pool: an unknown tick grades nil")
        eq(H.session_summary(unscored).attempts, 0,
            "pool: the nil spend is unscored")
        -- Status + shift: the tick countdown reads, the pause carries it.
        eq(FST.ROGUE.practice_status({ tick = { start = 0, interval = 2 } }, 1.0),
            "Tick 1.0s", "pool: the status counts the tick down")
        local shiftd = { tick = { start = 10, interval = 2 },
            swing = { swing_start = 20, swing_ends_at = 22 } }
        FST.ROGUE.practice_shift_pause(shiftd, 5)
        eq(shiftd.tick.start, 15, "pool: the pause carries the tick")
        eq(shiftd.swing.swing_start, 25, "pool: the pause carries the swing")
        eq(shiftd.swing.swing_ends_at, 27, "pool: the pause carries the landing")
    end

    -- End-to-end SS drill through the shell contract (window 0.1-0.2, ideal 0.1).
    do
        local fb = build({ project = 2 })
        local FST, fst = fb.ST, fb.st
        local H = fst.practice.harness
        local session = FST.ROGUE.new_ss_session(0)
        check(session ~= nil, "ss: new_ss_session creates the run")
        FST.ROGUE.practice_begin_session(session, 0)
        local drill = { ss = session, swing = { swing_start = 0 } }
        eq(FST.ROGUE.practice_cast(drill, 0.1, "ss"), "S",
            "ss: the 0.1 ideal grades S")
        eq(FST.ROGUE.practice_cast(drill, 0.13, "ss"), "A",
            "ss: a 0.13 offset grades A")
        eq(FST.ROGUE.practice_cast(drill, 0.05, "ss"), "F",
            "ss: an early strike grades F")
        eq(FST.ROGUE.practice_cast(drill, 0.25, "ss"), "F",
            "ss: a late strike grades F")
        eq(H.session_summary(session).attempts, 4,
            "ss: four graded strikes are recorded")
        eq(FST.ROGUE.practice_fight_elapsed(session, 5), 5,
            "ss: the fight clock reads the run")
        FST.ROGUE.end_practice_session(session, 0.1)
        -- Unreadable swing record: nil, never a guessed window.
        local noswing = FST.ROGUE.new_ss_session(0, { swing_known = false })
        FST.ROGUE.practice_begin_session(noswing, 0)
        eq(FST.ROGUE.practice_cast(
            { ss = noswing, swing = { swing_start = 0 } }, 0.1, "ss"), nil,
            "ss: an unknown swing grades nil")
        -- A missing swing clock never throws either.
        eq(FST.ROGUE.practice_cast({ ss = session }, 0.1, "ss"), nil,
            "ss: a missing swing clock grades nil")
    end

    -- Tick/end edge reads (nil-safe, read-only where stated).
    do
        local fb = build()
        local FST = fb.ST
        local out = {}
        eq(FST.ROGUE.tick_practice_session(nil, 0, 0.05, out), out,
            "tick: a nil session returns the out table untouched")
        eq(FST.ROGUE.end_practice_session(nil, 0), false,
            "end: a nil session ends false")
        eq(FST.ROGUE.practice_spend(nil, 0, 0.9), nil,
            "spend: a nil session grades nil")
        eq(FST.ROGUE.practice_ss(nil, 0, 0.1), nil,
            "ss: a nil session grades nil")
        eq(FST.ROGUE.practice_begin_session(nil, 0), false,
            "begin: a nil session begins false")
        eq(FST.ROGUE.practice_cast(nil, 0, "evisc"), nil,
            "cast: a nil drill grades nil")
        eq(FST.ROGUE.practice_cast({}, 0, "evisc"), nil,
            "cast: an empty drill grades nil")
        eq(FST.ROGUE.practice_fight_elapsed(nil, 0), nil,
            "elapsed: a nil session reads nil")
    end

    -- Options entry: the rogue Practice block lives in the ROGUE panel with the
    -- shared page shape, and the toggle calls the shared session toggle (the
    -- same call /st practice makes).
    do
        local options = read_file("option_tables.lua")
        local rstart = options:find("function ST%.class_opts_funcs%.ROGUE%(self%)")
        check(rstart ~= nil, "options: the ROGUE panel source is found")
        local rstop = options:find("function ST:generate_bar_position_options_table",
            rstart or 1)
        check(rstop ~= nil, "options: the ROGUE panel source is bounded")
        local rogue_opts = (rstart and rstop) and options:sub(rstart, rstop) or ""
        for _, key in ipairs({ "practice_header", "practice_desc", "practice_toggle",
            "practice_weapon_speed", "practice_result_duration",
            "practice_result_text_size", "practice_result_color_hit",
            "practice_result_color_miss", "practice_panel_x", "practice_panel_y",
            "practice_reset_position" }) do
            check(rogue_opts:find("%f[%a_]" .. key .. "%s*=%s*{") ~= nil,
                "ROGUE options: " .. key .. " ships in the rogue panel")
        end
        check(rogue_opts:find("st.practice_ui.toggle(ST)", 1, true) ~= nil,
            "ROGUE options: the toggle calls the shared session toggle")
        check(rogue_opts:find("st.practice_ui.is_active()", 1, true) ~= nil,
            "ROGUE options: the toggle label follows the live session")
        check(rogue_opts:find("/st practice toggles the same session", 1, true) ~= nil,
            "ROGUE options: the desc names the both-ways start")
    end

    -- Session bridge (class-isolation 2026-10-21): the shared practice UI routes
    -- the ACTIVE class's drill through ONE provider contract; the rogue's own
    -- module carries its route, panel facts and session seams. The pins below
    -- assert the generic shared surface AND the rogue module's own provider.
    do
        local pui = read_file("practice_ui.lua")
        check(pui:find("function ui.practice_panel()", 1, true) ~= nil,
            "practice_ui: the active class's provider seam is defined")
        check(pui:find("function ui.practice_class_drill()", 1, true) ~= nil,
            "practice_ui: the drill predicate asks the ACTIVE class")
        check(pui:find("ST.ROGUE", 1, true) == nil,
            "practice_ui: the shared module names no class module")
        check(pui:find("function ui.practice_start_drill(self, now)", 1, true) ~= nil,
            "practice_ui: the drill start shell is defined")
        check(pui:find("function ui.practice_drill_running()", 1, true) ~= nil,
            "practice_ui: the running-session predicate is defined")
        check(pui:find("session_api.cast", 1, true) ~= nil,
            "practice_ui: panel casts grade through the class's own cast seam")
        check(pui:find("if ui.practice_class_drill() then", 1, true) ~= nil,
            "practice_ui: options//st start routes to the active class's drill")
        check(pui:find("ui.practice_begin_fight(self, api.get_time())", 1, true) ~= nil,
            "practice_ui: Start Fight re-begins the drill")
        check(pui:find("ui.practice_stop_drill(self)", 1, true) ~= nil,
            "practice_ui: stop ends the drill run")
        check(pui:find("panel.session.pause, self, ui, shift", 1, true) ~= nil,
            "practice_ui: the combat pause shifts the class's own clocks")
        check(pui:find("pcall(panel.session.sync, self, ui)", 1, true) ~= nil,
            "practice_ui: the sync bridge mirrors the class's own drill")
        check(pui:find("local order = ui.practice_order()", 1, true) ~= nil,
            "practice_ui: the panel binds the class's own drill order")
        check(pui:find("ab = ui.practice_class_def(key)", 1, true) ~= nil,
            "practice_ui: the panel icons resolve through the class's own defs")

        local provider_src = read_file("classes/rogue.lua")
        check(provider_src:find("ST.ROGUE.practice_panel = {", 1, true) ~= nil,
            "classes/rogue.lua: the rogue publishes its own practice provider")
        check(provider_src:find('drill_key = "rogue_energy_pool"', 1, true) ~= nil,
            "classes/rogue.lua: the provider names the rogue's own drill key")
        check(provider_src:find('title = "|cFFFF8800Pool Practice|r"', 1, true) ~= nil,
            "classes/rogue.lua: the panel title is the rogue's own")
        check(provider_src:find("ST.ROGUE.practice_cast_order()", 1, true) ~= nil,
            "classes/rogue.lua: the order dispatch is ST.ROGUE-qualified")
        check(provider_src:find("ST.ROGUE.practice_begin_session(ui.rogue_session", 1, true) ~= nil,
            "classes/rogue.lua: Start Fight re-begins the rogue run")
        check(provider_src:find("ST.ROGUE.end_practice_session(ui.rogue_session", 1, true) ~= nil,
            "classes/rogue.lua: stop ends the rogue run")
        check(provider_src:find("ST.ROGUE.practice_shift_pause({", 1, true) ~= nil,
            "classes/rogue.lua: the combat pause carries the rogue clocks")
        check(provider_src:find("local swing = ui.rogue_swing", 1, true) ~= nil,
            "classes/rogue.lua: the sync bridge mirrors the rogue drill swing")
        check(provider_src:find("ST.ROGUE.practice_status({", 1, true) ~= nil,
            "classes/rogue.lua: the info line counts the rogue tick down")
        check(provider_src:find("ST.ROGUE.practice_fight_elapsed(ui.rogue_session", 1, true) ~= nil,
            "classes/rogue.lua: the fight clock reads the rogue run")
        check(provider_src:find("hint_stopped", 1, true) ~= nil,
            "classes/rogue.lua: the stopped hint is the rogue's own wording")
    end

    -- Designer: every frame rogue creates has a shared descriptor. Bars (per hand),
    -- HUD, rotation label, guide and practice panel are generic descriptors over the
    -- frames rogue builds in post_init (pinned above for the panel); the bar-child
    -- visuals (tick spark/pool wash/SS window/swap tint/poison reminder) move with
    -- the bar overlay and take no separate descriptor (the port's documented rule
    -- for bar children, cf. the paladin mini-bar exclusion).
    do
        local dm = read_file("designmode.lua")
        check(dm:find('bar_descriptor("mainhand")', 1, true) ~= nil,
            "designmode: the mainhand bar descriptor covers the rogue bar")
        check(dm:find('bar_descriptor("offhand")', 1, true) ~= nil,
            "designmode: the offhand bar descriptor covers the rogue bar")
        for _, key in ipairs({ "hud", "rottext", "nag", "practice_panel" }) do
            check(dm:find('key = "' .. key .. '"', 1, true) ~= nil,
                "designmode: the " .. key .. " descriptor covers the rogue element")
        end
        for _, key in ipairs({ "practice_rotation", "practice_timeline" }) do
            check(dm:find('practice_descriptor("' .. key .. '"', 1, true) ~= nil,
                "designmode: the " .. key .. " descriptor covers the rogue element")
        end
        check(dm:find("move with the bar overlay", 1, true) ~= nil,
            "designmode: bar children ride the bar overlay (no separate descriptor)")
        local rsrc = read_file("classes/rogue.lua")
        check(rsrc:find("st.hud.init(self)", 1, true) ~= nil,
            "rogue: post_init builds the HUD frame (designer-moved)")
        check(rsrc:find("st.nextaction_ui.init(self)", 1, true) ~= nil,
            "rogue: post_init builds the guide frame (designer-moved)")
        check(rsrc:find("st.practice_ui.init(self)", 1, true) ~= nil,
            "rogue: post_init builds the practice frames (designer-moved)")
        check(type(ST.ROGUE.get_rotation_key) == "function",
            "rogue: the rotation-label provider exists (designer-moved)")
        check(rsrc:find("get_visuals_frame", 1, true) ~= nil,
            "rogue: the bar-child visuals hang off the bar frame (move with it)")
    end

    -- Live shell drive: the rogue drill starts, grades and stops through the
    -- same entry points the options toggle and /st practice invoke
    -- (st.practice_ui.toggle -> ui.start -> rogue_start_session). The sandbox
    -- clock stands in for the client clock.
    do
        -- Era: both drill icons build and grade.
        local fb = build({ project = 2 })
        local FST = fb.ST
        local pui = fb.st.practice_ui
        check(pui ~= nil, "shell: practice_ui loads in the sandbox")
        FST.ROGUE.post_init(FST)
        check(pui.panel ~= nil, "shell: post_init builds the panel")
        check(pui.is_active() == false, "shell: idle before start")
        pui.toggle(FST)
        check(pui.is_active() == true, "shell: the toggle starts the drill run")
        check(pui.panel.ability_icons["evisc"] ~= nil,
            "shell: the pool spend icon builds")
        check(pui.panel.ability_icons["ss"] ~= nil,
            "shell: the Era SS icon builds")
        fb.clock = 1.9
        pui.cast_key(FST, "evisc")
        eq(pui.score.attempts, 1, "shell: the tick-edge spend scores")
        eq(pui.score.last_grade, "S", "shell: the tick-edge spend grades S")
        fb.clock = 0.1
        pui.cast_key(FST, "ss")
        eq(pui.score.attempts, 2, "shell: the window strike scores")
        eq(pui.score.last_grade, "S", "shell: the 0.1 strike grades S")
        local ok, err = pcall(pui.tick, FST, 0.05)
        check(ok, "shell: the driver tick runs (" .. tostring(err) .. ")")
        eq(pui.panel.fight_timer_text.text, "Fight: 0:00",
            "shell: the fight clock reads the run")
        pui.toggle(FST)
        check(pui.is_active() == false, "shell: the toggle stops the run")
        -- TBC: pool only (the SS icon never builds where the technique is
        -- refuted), same flow otherwise.
        local tb = build()
        local TST = tb.ST
        TST.ROGUE.post_init(TST)
        tb.st.practice_ui.toggle(TST)
        check(tb.st.practice_ui.is_active() == true,
            "shell: TBC starts the pool run")
        check(tb.st.practice_ui.panel.ability_icons["evisc"] ~= nil,
            "shell: TBC builds the pool icon")
        check(tb.st.practice_ui.panel.ability_icons["ss"] == nil,
            "shell: TBC builds no SS icon")
        tb.clock = 1.9
        tb.st.practice_ui.cast_key(TST, "evisc")
        eq(tb.st.practice_ui.score.attempts, 1,
            "shell: TBC grades the pool spend")
        tb.st.practice_ui.toggle(TST)
        check(tb.st.practice_ui.is_active() == false,
            "shell: TBC stops the run")
        -- Combat gate: no session starts in combat, no error.
        local cb = build()
        cb.ST.in_combat = true
        cb.ST.ROGUE.post_init(cb.ST)
        local cok = pcall(cb.st.practice_ui.toggle, cb.ST)
        check(cok and cb.st.practice_ui.is_active() == false,
            "shell: combat refuses the start")
    end
end

--=========================================================================================
-- 20) Shared class order: the per-frame hook and the post_init init order (F8 + F9)
--=========================================================================================
-- The six class modules are copy-paste siblings and used to diverge on two orders:
-- the hunter ticked the HUD before the guide, and the paladin built the practice
-- surface before the HUD. The shared contract is now pinned here, per class:
--   * the per-frame class hook ticks the guide BEFORE the HUD;
--   * post_init builds the guide, then the HUD, then the practice surface.
-- Both the runtime order (spies record the calls) and the source order (the call
-- sites) are pinned, so a reordering in either place fails this suite.
do
    local fh = assert(io.open(ROOT .. "classes/rogue.lua", "r"))
    local src = fh:read("*a")
    fh:close()
    -- Comment lines are dropped first: a call quoted inside a comment (the paladin
    -- HUD block quotes st.hud.init(self)) must not be read as the call itself.
    local code = {}
    for line in src:gmatch("[^\r\n]+") do
        if line:match("^%s*%-%-") == nil then
            code[#code + 1] = line
        end
    end
    code = table.concat(code, "\n")
    local at_guide_tick = code:find("st.nextaction_ui.on_bar_update(self, hand)", 1, true)
    local at_hud_tick = code:find("st.hud.on_bar_update(self, hand)", 1, true)
    local at_guide_init = code:find("st.nextaction_ui.init(self)", 1, true)
    local at_hud_init = code:find("st.hud.init(self)", 1, true)
    local at_practice_init = code:find("st.practice_ui.init(self)", 1, true)
    check(at_guide_tick ~= nil and at_hud_tick ~= nil,
        "order: the class hook drives both the guide and the HUD")
    check(at_guide_init ~= nil and at_hud_init ~= nil and at_practice_init ~= nil,
        "order: post_init drives the guide, the HUD and the practice surface")
    check(at_guide_tick < at_hud_tick,
        "order: the guide tick comes before the HUD tick")
    check(at_guide_init < at_hud_init and at_hud_init < at_practice_init,
        "order: post_init builds the guide, then the HUD, then the practice surface")

    -- Runtime order: the spies record the calls the class actually makes.
    local sbox = build()
    local T = sbox.ST
    local init_order = {}
    local saved = {
        nextaction_ui = sbox.st.nextaction_ui,
        hud = sbox.st.hud,
        practice_ui = sbox.st.practice_ui,
    }
    sbox.st.nextaction_ui = { init = function() init_order[#init_order + 1] = "guide" end }
    sbox.st.hud = { init = function() init_order[#init_order + 1] = "hud" end }
    sbox.st.practice_ui = {
        init = function() init_order[#init_order + 1] = "practice" end,
        is_active = function() return false end,
    }
    local ok_init, err_init = pcall(T.ROGUE.post_init, T)
    check(ok_init, "order: post_init runs with the order spies (" .. tostring(err_init) .. ")")
    eq(init_order[1], "guide", "order: post_init builds the guide first")
    eq(init_order[2], "hud", "order: post_init builds the HUD second")
    eq(init_order[3], "practice", "order: post_init builds the practice surface third")
    eq(#init_order, 3, "order: post_init builds exactly the three surfaces")

    local tick_order = {}
    sbox.st.nextaction_ui = {
        apply_settings = function() end,
        on_bar_update = function() tick_order[#tick_order + 1] = "guide" end,
    }
    sbox.st.hud = { on_bar_update = function() tick_order[#tick_order + 1] = "hud" end }
    local ok_tick, err_tick = pcall(T.ROGUE.on_bar_update, T, "mainhand")
    check(ok_tick, "order: the class hook runs with the order spies (" .. tostring(err_tick) .. ")")
    eq(tick_order[1], "guide", "order: the guide ticks before the HUD")
    eq(tick_order[2], "hud", "order: the HUD ticks after the guide")
    eq(#tick_order, 2, "order: the class hook ticks the guide and the HUD once each")

    sbox.st.nextaction_ui = saved.nextaction_ui
    sbox.st.hud = saved.hud
    sbox.st.practice_ui = saved.practice_ui

end

--=========================================================================================
-- 21) The practice contract: the rotation table, the scenario step, the drill set
--=========================================================================================
-- bench/class_features_drills_2026-10-19.md §2.4 (the rogue section): the shared
-- practice engine looks the class side up by player_class, so the rogue exposes
-- three fixed names:
--   ST.ROGUE.practice_rotation        the rotation table in sim priority order
--   ST.ROGUE.practice_scenario_step   one tick of the rotation scenario
--   ST.ROGUE.practice_drills          the target drill set (the audit's C)
-- The energy drill is NOT one of the target drills (the operator's ruling:
-- rogue_energy_pool is baseline resource behaviour).
do
    local sb = build()
    local ST2 = sb.ST

    -- The rotation table: the engine's rule order, every entry citing its source.
    local rotation = ST2.ROGUE.practice_rotation
    check(type(rotation) == "table", "practice: the rotation table ships")
    -- The shipped rule order first, then the APL utility layer (the rows the
    -- sims' own priority lists carry: bench/rotation_gap_vs_apl_2026-10-20.md §3).
    local expected_order = {
        "expose", "snd", "hfb", "shiv", "envenom", "eviscerate", "rupture",
        "ar", "bf", "coldblood", "tea", "builder",
        "vanish", "poisoned_knife", "saber_slash",
        "vanish", "tricks_of_the_trade", "killing_spree", "hypersharp", "mutilate",
        "ambush", "garrote", "vanish", "preparation", "premeditation", "venom",
        "blood_fury", "elunes_light", "gnome_eureka", "mutilate", "hemorrhage",
        "backstab", "ghostly_strike",
        "mutilate", "hemorrhage", "backstab",
    }
    eq(#rotation, #expected_order, "practice: the rotation table carries every step")
    local order_ok = true
    local cited_ok = true
    local label_ok = true
    local note_ok = true
    for i = 1, #expected_order do
        local entry = rotation[i]
        if type(entry) ~= "table" or entry.action ~= expected_order[i] then
            order_ok = false
        end
        if type(entry) ~= "table" or type(entry.source) ~= "string" or entry.source == "" then
            cited_ok = false
        end
        if type(entry) ~= "table" or type(entry.label) ~= "string" or entry.label == "" then
            label_ok = false
        end
        if type(entry) ~= "table" or type(entry.note) ~= "string" or entry.note == "" then
            note_ok = false
        end
    end
    check(order_ok, "practice: the rotation table is in the engine's rule order")
    check(cited_ok, "practice: every rotation step cites its sim source")
    check(label_ok, "practice: every rotation step carries a label (the panel's button)")
    check(note_ok, "practice: every rotation step carries a short note")
    -- The table's actions are the engine's own action names (never a guess), or
    -- one of the BUILDER rows the engine's builder arm already plays (the APL
    -- names the spell; the engine's single builder action resolves it).
    local known = {
        expose = true, snd = true, hfb = true, shiv = true, envenom = true,
        eviscerate = true, rupture = true, ar = true, bf = true,
        coldblood = true, tea = true, builder = true,
        vanish = true, poisoned_knife = true,
        tricks_of_the_trade = true, killing_spree = true, hypersharp = true,
        ambush = true, garrote = true, preparation = true,
        premeditation = true, venom = true, blood_fury = true,
        elunes_light = true, gnome_eureka = true,
    }
    local builder_rows = {
        saber_slash = true, mutilate = true, hemorrhage = true,
        backstab = true, ghostly_strike = true,
    }
    local known_ok = true
    local builder_ok = true
    for i = 1, #rotation do
        local action = rotation[i].action
        if not known[action] then
            if builder_rows[action] then
                -- A builder row: the engine has no arm of its own (the builder
                -- arm plays the spell), so it must say engine = false.
                if rotation[i].engine ~= false then
                    builder_ok = false
                end
            else
                known_ok = false
            end
        end
    end
    check(known_ok, "practice: the rotation steps are the engine's action keys")
    check(builder_ok, "practice: the builder rows ride the builder arm (engine = false)")

    -- The family's slice: the engine asks for it (practice_ui reads
    -- practice_rotation_for / practice_rotation_family).
    check(type(ST2.ROGUE.practice_rotation_for) == "function",
        "practice: the rotation slice ships")
    check(type(ST2.ROGUE.practice_rotation_family) == "function",
        "practice: the rotation family ships")
    local tbc_slice = ST2.ROGUE.practice_rotation_for("TBC")
    local tbc_actions = {}
    for i = 1, #tbc_slice do
        tbc_actions[tbc_slice[i].action] = true
    end
    eq(tbc_actions.snd, true, "practice: the TBC slice keeps the SnD upkeep")
    eq(tbc_actions.rupture, true, "practice: the TBC slice keeps the Rupture finisher")
    eq(tbc_actions.shiv, true, "practice: the TBC slice keeps the Shiv upkeep")
    eq(tbc_actions.hfb, nil, "practice: the TBC slice drops the Wrath sin upkeep")
    eq(tbc_actions.coldblood, true, "practice: the TBC slice keeps Cold Blood")
    local era_slice = ST2.ROGUE.practice_rotation_for("ERA")
    local era_actions = {}
    for i = 1, #era_slice do
        era_actions[era_slice[i].action] = true
    end
    eq(era_actions.rupture, nil,
        "practice: the Era slice drops Rupture (the Era sims are Eviscerate-only)")
    eq(era_actions.eviscerate, true, "practice: the Era slice keeps Eviscerate")
    eq(era_actions.shiv, true, "practice: the Era slice keeps the Shiv upkeep")
    eq(era_actions.coldblood, nil, "practice: the Era slice drops Cold Blood")
    eq(#ST2.ROGUE.practice_rotation_for("RETAIL"), 0,
        "practice: Retail has no rotation slice (no retail sim)")
    eq(#ST2.ROGUE.practice_rotation_for("BOGUS"), 0,
        "practice: an unknown family plays nothing (the engine's fallback stands in)")

    -- The scenario step: the engine's decision for the ctx's state.
    check(type(ST2.ROGUE.practice_scenario_step) == "function",
        "practice: the scenario step ships")
    eq(ST2.ROGUE.practice_scenario_step(ST2, nil), nil,
        "practice: a missing ctx is undecidable (unknown)")
    eq(ST2.ROGUE.practice_scenario_step(ST2, {}), nil,
        "practice: an empty ctx has no state to decide (unknown)")
    eq(ST2.ROGUE.practice_scenario_step(ST2, {
        resources = { energy_now = nil, cp = 5, family = "ERA" },
    }), nil, "practice: an unreadable core read is unknown")

    local era_step = ST2.ROGUE.practice_scenario_step(ST2, {
        now = 10,
        resources = { energy_now = 50, cp = 5, ttd = 30, family = "ERA" },
    })
    check(type(era_step) == "table", "practice: the scenario step answers a known state")
    eq(era_step and era_step.action, "eviscerate",
        "practice: the Era planned finisher is Eviscerate (E-C1)")
    check(type(era_step and era_step.reason) == "string" and era_step.reason ~= "",
        "practice: the scenario step carries a short reason")

    local tbc_step = ST2.ROGUE.practice_scenario_step(ST2, {
        now = 11,
        resources = { energy_now = 50, cp = 5, ttd = 30, family = "TBC" },
    })
    eq(tbc_step and tbc_step.action, "rupture",
        "practice: the TBC planned finisher is Rupture (T-M2)")

    -- A POOL verdict is a HOLD, and a hold is a DECISION (the operator ruling
    -- HU-8): the step states it explicitly, so the engine can punish a cast
    -- during the pool instead of reading the step as an unknown.
    local pool_step = ST2.ROGUE.practice_scenario_step(ST2, {
        now = 12,
        resources = { energy_now = 40, cp = 0, family = "ERA" },
    })
    check(type(pool_step) == "table" and pool_step.hold == true,
        "practice: a POOL verdict states an explicit hold")
    eq(pool_step.action, nil, "practice: the POOL hold names no action")
    check(type(pool_step.reason) == "string" and pool_step.reason ~= "",
        "practice: the POOL hold carries the engine's own reason")

    -- The drill set: the audit's four target drills, one skill each.
    local drills = ST2.ROGUE.practice_drills
    check(type(drills) == "table", "practice: the drill set ships")
    eq(#drills, 4, "practice: the rogue exposes four target drills")
    local keys = {}
    local shape_ok = true
    for i = 1, #drills do
        local drill = drills[i]
        if type(drill) ~= "table" or type(drill.key) ~= "string" or drill.key == ""
            or type(drill.label) ~= "string" or drill.label == ""
            or type(drill.kind) ~= "string" or drill.kind == ""
            or type(drill.description) ~= "string" or drill.description == ""
            or type(drill.grade) ~= "function" then
            shape_ok = false
        else
            keys[drill.key] = drill.label
        end
    end
    check(shape_ok, "practice: every drill carries a key, a label, a kind and a grader")
    check(keys["rogue_finisher_order"] ~= nil, "practice: the finisher-order drill ships")
    check(keys["rogue_cp_finish"] ~= nil, "practice: the combo-point drill ships")
    check(keys["rogue_snd_upkeep"] ~= nil, "practice: the debuff-upkeep drill ships")
    check(keys["rogue_opener"] ~= nil, "practice: the opener drill ships")
    check(keys["rogue_energy_pool"] == nil,
        "practice: the energy drill is baseline, not a target drill (operator ruling)")

    -- The class's own ctx builder: the engine prefers it over its own fallback,
    -- so the drills see the whole gathered state (the upkeep flags included).
    check(type(ST2.ROGUE.practice_context) == "function",
        "practice: the class context builder ships")
    sb.power[3] = 60
    sb.power[4] = 4
    local ctx = ST2.ROGUE.practice_context(ST2, 42, "builder")
    eq(ctx.now, 42, "practice: the ctx builder carries the clock")
    eq(ctx.last_action, "builder", "practice: the ctx builder carries the last action")
    eq(type(ctx.resources), "table", "practice: the ctx builder carries the resource bag")
    eq(ctx.resources.cp, 4, "practice: the resource bag carries the combo points")
    eq(ctx.resources.energy_now, 60, "practice: the resource bag carries the energy")
    eq(ctx.resources.snd_usable, true,
        "practice: the resource bag carries the upkeep state (the drills need it)")
    check(type(ctx.cooldowns) == "table", "practice: the ctx builder carries the cooldown bag")

    -- No namespace mirror any more: the shared engine resolves the class module
    -- from the AceAddon table FIRST (the class tables live there), so no
    -- per-class alias is needed - and none is carried (hands-up.md HU-7).
    eq(sb.st.ROGUE, nil, "practice: the class module carries no namespace alias")

    -- The end-to-end seam: the shared harness finds the rogue's class side by
    -- player_class and drives the step and the drills through it.
    local H = sb.st.practice and sb.st.practice.harness
    check(type(H) == "table" and type(H.practice_drills) == "function",
        "practice: the shared harness exposes the drill lookup")
    if type(H) == "table" and type(H.practice_class_module) == "function" then
        eq(H.practice_class_module("ROGUE"), ST2.ROGUE,
            "practice: the engine finds the class module without an alias")
    end
    if type(H) == "table" and type(H.practice_drills) == "function" then
        local found = H.practice_drills("ROGUE")
        eq(type(found), "table", "practice: the harness finds the rogue's drill list")
        local found_keys = {}
        for i = 1, #found do
            found_keys[found[i].key] = true
        end
        eq(found_keys["rogue_finisher_order"], true,
            "practice: the harness sees the finisher-order drill")
        eq(found_keys["rogue_cp_finish"], true,
            "practice: the harness sees the combo-point drill")
        eq(found_keys["rogue_snd_upkeep"], true,
            "practice: the harness sees the debuff-upkeep drill")
        eq(found_keys["rogue_opener"], true,
            "practice: the harness sees the opener drill")
        eq(H.practice_scenario_available("ROGUE"), true,
            "practice: the harness sees the rogue's scenario step")
        local answer = H.practice_scenario_step("ROGUE", ST2, {
            now = 10,
            resources = { energy_now = 50, cp = 5, ttd = 30, family = "ERA" },
        })
        eq(answer and answer.action, "eviscerate",
            "practice: the harness drives the rogue's step (the Era planned finisher)")
        local grade = H.practice_drill_grade("ROGUE", "rogue_cp_finish", ST2, {
            now = 10,
            last_action = "eviscerate",
            resources = { energy_now = 50, cp = 5, ttd = 30, family = "ERA" },
        })
        eq(grade, "S",
            "practice: the harness drives the rogue's combo-point drill")
    end

    -- D-R1: the finisher order. The engine's action IS the expected order, and
    -- a nearly-right pick (Rupture instead of Eviscerate on Era) is a mis-pick.
    local order_drill = drills[1]
    local function order_ctx(action)
        return {
            now = 20,
            last_action = action,
            resources = { energy_now = 50, cp = 5, ttd = 30, family = "ERA" },
        }
    end
    eq(order_drill.grade(ST2, order_ctx("eviscerate")), "S",
        "practice: the right pick keeps the finisher order at S")
    eq(order_drill.grade(ST2, order_ctx("rupture")), "A",
        "practice: the wrong Era finisher is a mis-pick (the audit's near-miss rule)")
    eq(order_drill.grade(ST2, order_ctx("rupture")), "B",
        "practice: a second mis-pick drops one band")
    eq(order_drill.grade(ST2, order_ctx("eviscerate")), "B",
        "practice: a correct pick does not clear the running mis-pick count")
    eq(order_drill.grade(ST2, { now = 21, resources = { energy_now = 50, cp = 5,
        family = "ERA" } }), nil, "practice: no press grades nothing")
    eq(order_drill.grade(ST2, { now = 21, last_action = "eviscerate",
        resources = { family = "ERA" } }), nil,
        "practice: an unreadable state grades unknown")

    -- D-R2: the combo-point decision (the family's own floor).
    local cp_drill = drills[2]
    local function cp_ctx(action, cp, ttd)
        return {
            now = 30,
            last_action = action,
            resources = { energy_now = 50, cp = cp, ttd = ttd, family = "ERA" },
        }
    end
    eq(cp_drill.grade(ST2, cp_ctx("eviscerate", 5, 30)), "S",
        "practice: the finisher at the Era floor with the right finisher is S")
    eq(cp_drill.grade(ST2, cp_ctx("eviscerate", 4, 30)), "A",
        "practice: one CP short is A")
    eq(cp_drill.grade(ST2, cp_ctx("eviscerate", 3, 30)), "B",
        "practice: two CP short is B")
    eq(cp_drill.grade(ST2, cp_ctx("eviscerate", 2, 30)), "F",
        "practice: below the floor on a healthy target wastes the CP (F)")
    eq(cp_drill.grade(ST2, cp_ctx("rupture", 5, 30)), "C",
        "practice: the right CP with the wrong finisher is C")
    eq(cp_drill.grade(ST2, cp_ctx("eviscerate", 0, 5)), "D",
        "practice: below the floor on a dying target is forgiven (D)")
    eq(cp_drill.grade(ST2, cp_ctx("builder", 5, 30)), nil,
        "practice: a builder press is not a combo-point decision")

    -- D-R3: the debuff upkeep.
    local snd_drill = drills[3]
    eq(snd_drill.grade(ST2, { now = 40, last_action = "snd",
        resources = { cp = 3, snd_remains = 12 } }), "S",
        "practice: a refresh while the debuff is up is S")
    eq(snd_drill.grade(ST2, { now = 40, last_action = "snd",
        resources = { cp = 3, snd_remains = 0 } }), "C",
        "practice: a refresh at the expiry grades the expired debuff (C)")
    eq(snd_drill.grade(ST2, { now = 40, last_action = "snd",
        resources = { cp = 3, snd_late_by = 1.5 } }), "A",
        "practice: a refresh one tick late is A")
    eq(snd_drill.grade(ST2, { now = 40, last_action = "snd",
        resources = { cp = 3, snd_late_by = 3 } }), "B",
        "practice: a refresh two ticks late is B")
    eq(snd_drill.grade(ST2, { now = 40, last_action = "snd",
        resources = { cp = 3, snd_late_by = 30 } }), "F",
        "practice: a refresh after the debuff's own length is never maintained (F)")
    eq(snd_drill.grade(ST2, { now = 40, last_action = "builder",
        resources = { cp = 3, snd_late_by = 1 } }), "D",
        "practice: the builder pressed over the window is D")
    eq(snd_drill.grade(ST2, { now = 40, last_action = "snd",
        resources = { cp = 3 } }), nil,
        "practice: no clock grades the upkeep unknown")

    -- D-R4: the opener (the synthetic pull clock).
    local opener_drill = drills[4]
    local function opener_ctx(action, now)
        return {
            now = now,
            last_action = action,
            resources = { energy_now = 50, cp = 5, ttd = 30, family = "ERA",
                pull_at = 100 },
        }
    end
    eq(opener_drill.grade(ST2, opener_ctx("eviscerate", 101.5)), "S",
        "practice: the opener step on time is S")
    eq(opener_drill.grade(ST2, opener_ctx("eviscerate", 103.0)), "A",
        "practice: one GCD late is A")
    eq(opener_drill.grade(ST2, opener_ctx("eviscerate", 104.5)), "B",
        "practice: two GCDs late is B")
    eq(opener_drill.grade(ST2, opener_ctx("eviscerate", 106.0)), "C",
        "practice: three GCDs late is C")
    eq(opener_drill.grade(ST2, opener_ctx("eviscerate", 110.0)), "D",
        "practice: a badly late opener step is D (the opener was missed)")
    eq(opener_drill.grade(ST2, opener_ctx("builder", 101.5)), "D",
        "practice: skipping the due step is D")
    eq(opener_drill.grade(ST2, opener_ctx("tea", 101.5)), "F",
        "practice: an action outside the opener order is F")
    eq(opener_drill.grade(ST2, { now = 101.5, last_action = "eviscerate",
        resources = { energy_now = 50, cp = 5, ttd = 30, family = "ERA" } }), nil,
        "practice: no pull clock grades the opener unknown")
end

--=========================================================================================
-- 22) Wrath sin upkeep: Hunger for Blood (audit W-G1 / the class-feature audit's
-- R-19): the wowsims wotlk APL refreshes the buff when its aura has <= 1 s left.
-- The spell resolves through the client's OWN data by its English name (the sim's
-- 51662 is sim-side evidence only), the talent gate is a strict true, and only
-- the WRATH family prompts.
--=========================================================================================
do
    local sb = build({ project = 11 })   -- Wrath
    local ST2 = sb.ST
    sb.power[3] = 50
    sb.power[4] = 2
    -- A healthy Slice and Dice keeps the upkeep chain (1b) quiet, so the
    -- Hunger for Blood upkeep (1c) is the step that is due.
    sb.auras = { player = { { name = "Slice and Dice", duration = 30,
        expiration = sb.clock + 20, spell_id = 101 } } }
    local inputs = ST2.ROGUE.gather_guide_inputs(ST2, {})
    eq(inputs.family, "WRATH", "hfb: the Wrath build reports the Wrath family")
    eq(inputs.hfb_usable, true,
        "hfb: the spell resolves through the client's own spell data")
    eq(inputs.hfb_remains, nil,
        "hfb: no Hunger for Blood aura reads missing (upkeep gap)")

    local out = {}
    ST2.ROGUE.guide.evaluate(inputs, out)
    eq(out.action, "hfb",
        "hfb: a missing Hunger for Blood prompts the upkeep (the SnD convention)")

    -- A healthy buff does not prompt.
    sb.auras = { player = {
        { name = "Slice and Dice", duration = 30, expiration = sb.clock + 20, spell_id = 101 },
        { name = "Hunger for Blood", duration = 20, expiration = sb.clock + 15, spell_id = 120 },
    } }
    inputs = ST2.ROGUE.gather_guide_inputs(ST2, {})
    eq(inputs.hfb_remains, 15, "hfb: an active buff reports its window")
    out = {}
    ST2.ROGUE.guide.evaluate(inputs, out)
    check(out.action ~= "hfb", "hfb: a healthy buff does not prompt the upkeep")

    -- The tail (the sim's <= 1 s refresh).
    sb.auras = { player = {
        { name = "Slice and Dice", duration = 30, expiration = sb.clock + 20, spell_id = 101 },
        { name = "Hunger for Blood", duration = 20, expiration = sb.clock + 0.5, spell_id = 120 },
    } }
    inputs = ST2.ROGUE.gather_guide_inputs(ST2, {})
    out = {}
    ST2.ROGUE.guide.evaluate(inputs, out)
    eq(out.action, "hfb", "hfb: the buff's tail (<= 1 s) prompts the refresh")

    -- The talent gate: an unknown spell never prompts.
    sb.known = { [120] = false }
    inputs = ST2.ROGUE.gather_guide_inputs(ST2, {})
    eq(inputs.hfb_usable, nil, "hfb: an unknown spell reads unusable")
    out = {}
    ST2.ROGUE.guide.evaluate(inputs, out)
    check(out.action ~= "hfb", "hfb: an unknown talent never prompts")
    sb.known = nil

    -- The family gate: only Wrath plays the sin upkeep. The Slice and Dice
    -- buff rides, so the upkeep chain (1b) is quiet and the Hunger for Blood
    -- upkeep is the step that would be due.
    local era = build({ project = 2 })
    era.power[3] = 50
    era.power[4] = 2
    era.auras = { player = { { name = "Slice and Dice", duration = 30,
        expiration = era.clock + 20, spell_id = 101 } } }
    local era_inputs = era.ST.ROGUE.gather_guide_inputs(era.ST, {})
    local era_out = {}
    era.ST.ROGUE.guide.evaluate(era_inputs, era_out)
    check(era_out.action ~= "hfb", "hfb: Era never prompts the Wrath sin upkeep")
    local tbc = build()
    tbc.power[3] = 50
    tbc.power[4] = 2
    tbc.auras = { player = { { name = "Slice and Dice", duration = 30,
        expiration = tbc.clock + 20, spell_id = 101 } } }
    local tbc_inputs = tbc.ST.ROGUE.gather_guide_inputs(tbc.ST, {})
    local tbc_out = {}
    tbc.ST.ROGUE.guide.evaluate(tbc_inputs, tbc_out)
    check(tbc_out.action ~= "hfb", "hfb: TBC never prompts the Wrath sin upkeep")

    -- The slot-less action is named by the rotation label (the slot contract is
    -- frozen: no twelfth guide slot).
    local label = ST2.ROGUE.get_rotation_key(ST2)
    eq(label, "Hunger for Blood",
        "hfb: the rotation label names the upkeep (no guide slot)")
end

--=========================================================================================
-- 23) HU-8: the class states its hold, and the pull moment reaches the ctx
--=========================================================================================
-- The operator ruling (hands-up HU-8, resolved 2026-10-19): a HOLD is a DECISION and
-- an unknown is not. The rogue's engine answers a POOL verdict, and the step must
-- SAY so: casting during the pool is an illegal cast, doing nothing is correct,
-- and a state the engine cannot read stays unknown (no attempt at all).
do
    local sb = build()
    local ST2 = sb.ST
    local H = sb.st.practice and sb.st.practice.harness
    check(type(H) == "table", "hold: the shared harness is loaded")

    local pool_ctx = {
        now = 12,
        resources = { energy_now = 40, cp = 0, family = "ERA" },
    }
    local unknown_ctx = {
        now = 13,
        resources = { energy_now = nil, cp = 5, family = "ERA" },
    }

    -- The hold statement: the accessor keeps it (the engine's contract).
    local hold_answer = H.practice_scenario_step("ROGUE", ST2, pool_ctx)
    check(type(hold_answer) == "table" and hold_answer.hold == true,
        "hold: the POOL state states an explicit hold")
    eq(hold_answer.action, nil, "hold: the hold statement names no action")
    check(type(hold_answer.reason) == "string" and hold_answer.reason ~= "",
        "hold: the hold statement carries the engine's reason")

    -- The three states, through the engine's own decision:
    --   hold + a cast  -> the illegal cast (an attempt, an F)
    --   hold + nothing -> a correct hold (no attempt, no points)
    --   unknown        -> unknown (no attempt)
    local run = H.new_rotation_run()
    local cast = H.rotation_run_decide(run, hold_answer.action, "eviscerate", hold_answer.hold)
    eq(cast.outcome, "illegal_cast", "hold: a cast during the pool is an illegal cast")
    eq(H.ROTATION_OUTCOME_GRADES[cast.outcome], "F", "hold: the illegal cast grades F")
    eq(run.mispicks, 1, "hold: the illegal cast counts against the run's band")
    local idle_run = H.new_rotation_run()
    local idle = H.rotation_run_decide(idle_run, hold_answer.action, nil, hold_answer.hold)
    eq(idle.outcome, "hold_ok", "hold: doing nothing during the pool is correct")
    eq(H.ROTATION_OUTCOME_GRADES[idle.outcome], nil,
        "hold: a correct hold records no attempt (no points)")
    eq(idle_run.mispicks, 0, "hold: a correct hold is never a mis-pick")
    -- The unknown: a state the engine cannot read stays unknown.
    local unknown_answer = H.practice_scenario_step("ROGUE", ST2, unknown_ctx)
    eq(unknown_answer, nil, "hold: an unreadable state stays unknown (no hold statement)")
    local unknown_run = H.new_rotation_run()
    local unknown = H.rotation_run_decide(unknown_run, nil, "eviscerate")
    eq(unknown.outcome, "unknown", "hold: an unknown step stays unknown")
    eq(H.ROTATION_OUTCOME_GRADES[unknown.outcome], nil,
        "hold: an unknown decision records no attempt")
    eq(unknown_run.mispicks, 0, "hold: an unknown decision is never a mis-pick")
end

-- The live pull moment in the class's own ctx (BS-8 item 2 / P-17): the opener
-- drill judges the pull window from the SAME moment the live guide reads, so the
-- class's ctx builder carries it.
do
    local sb = build()
    sb.ST.pull_at = 1234
    sb.ST.pull_in_seconds = function(self, now) return self.pull_at - now end
    local ctx = sb.ST.ROGUE.practice_context(sb.ST, 1000, nil)
    eq(ctx.pull_at, 1234, "pull: the ctx carries the absolute pull moment")
    eq(ctx.pull_in_seconds, 234, "pull: the ctx carries the countdown to the pull")
    -- Unknown stays unknown: a client with no armed clock publishes nothing.
    local bare = build()
    local bare_ctx = bare.ST.ROGUE.practice_context(bare.ST, 1000, nil)
    eq(bare_ctx.pull_at, nil, "pull: an unarmed clock publishes no pull moment")
    eq(bare_ctx.pull_in_seconds, nil, "pull: an unarmed clock publishes no countdown")
    -- A non-numeric clock is never a guess.
    local broken = build()
    broken.ST.pull_at = "soon"
    broken.ST.pull_in_seconds = function() return "soon" end
    local broken_ctx = broken.ST.ROGUE.practice_context(broken.ST, 1000, nil)
    eq(broken_ctx.pull_at, nil, "pull: a non-numeric moment is never published")
    eq(broken_ctx.pull_in_seconds, nil, "pull: a non-numeric countdown is never published")
end

--=========================================================================================
-- 22) The APL utility layer: the rotation table's spine rows, the family gates,
--     the two flags, the prepull table and the gather reads
--=========================================================================================
-- bench/rotation_gap_vs_apl_2026-10-20.md §3 (the rogue) is the INPUT; every id
-- below was re-read from the APL files themselves on 2026-10-20 (wowsims/{sod,
-- tbc-new,forever,wotlk}/master) and named against the sims' own spell data.
do
    local sb = build()
    local ST2 = sb.ST
    local rotation = ST2.ROGUE.practice_rotation

    -- The shape: every row after the shipped rule order carries the APL layer's
    -- fields. A live = false row must name the read (or the APL gate) it waits
    -- for; a live = true row must not claim a read it does not need.
    local shape_ok, flags_ok, needs_ok, ids_ok, names_ok = true, true, true, true, true
    for i = 13, #rotation do
        local entry = rotation[i]
        if type(entry.spell_ids) ~= "table" or type(entry.spell_names) ~= "table"
            or type(entry.families) ~= "table" then
            shape_ok = false
        end
        if type(entry.live) ~= "boolean" or type(entry.engine) ~= "boolean" then
            flags_ok = false
        end
        if entry.live == false and (type(entry.needs) ~= "string" or entry.needs == "") then
            needs_ok = false
        end
        -- Every id the row cites must be a number and every family it gates must
        -- carry an id and a name (a family-split id never rides one row).
        for family, id in pairs(entry.spell_ids or {}) do
            if type(id) ~= "number" or entry.families[family] ~= true then
                ids_ok = false
            end
            if type(entry.spell_names[family]) ~= "string" or entry.spell_names[family] == "" then
                names_ok = false
            end
        end
    end
    check(shape_ok, "apl: every utility row carries its ids, names and family gate")
    check(flags_ok, "apl: every utility row carries the live and engine flags")
    check(needs_ok, "apl: every filed row (live = false) names the read it waits for")
    check(ids_ok, "apl: every cited id belongs to a gated family")
    check(names_ok, "apl: every cited family carries the client's English name")
    -- The filed rows: the two whose read (or APL gate) does not exist - the
    -- WotLK Hypersharp row (the belt enchant's availability) and the TBC
    -- Backstab row (the APL's own const-false build gate). The Forever Vanish
    -- (the Garrote energy cost) and the Forever Gnome Eureka (the Adrenaline
    -- Rush split) are WIRED now.
    local filed, filed_actions = 0, {}
    for i = 13, #rotation do
        if rotation[i].live == false then
            filed = filed + 1
            filed_actions[rotation[i].action] = true
        end
    end
    eq(filed, 2, "apl: exactly two utility rows are filed (live = false)")
    eq(filed_actions.vanish, nil, "apl: the Forever Vanish row is wired (not filed)")
    eq(filed_actions.hypersharp, true, "apl: the filed Hypersharp row is one of them")
    eq(filed_actions.gnome_eureka, nil, "apl: the Gnome Eureka row is wired (not filed)")
    eq(filed_actions.backstab, true, "apl: the filed TBC Backstab row is one of them")
    -- A wired row carries no `needs` (nothing is waited for any more).
    local wired_no_needs = true
    for i = 13, #rotation do
        local entry = rotation[i]
        if entry.live == true and entry.needs ~= nil then
            wired_no_needs = false
            print("      (a wired row still claims a read: " .. tostring(entry.action) .. ")")
        end
    end
    check(wired_no_needs, "apl: a wired row claims no read it waits for")
    -- The builder rows say in their own note that engine = false is a
    -- de-duplication (the engine's builder action already plays them), never a
    -- gap - so no reader takes the flag for a missing arm.
    local builder_rows = { "saber_slash", "mutilate", "hemorrhage", "backstab",
        "ghostly_strike" }
    local builder_note_ok = true
    for i = 13, #rotation do
        local entry = rotation[i]
        if entry.engine == false and entry.live == true then
            local is_builder = false
            for _, action in ipairs(builder_rows) do
                if entry.action == action then
                    is_builder = true
                end
            end
            if is_builder and (type(entry.note) ~= "string"
                or not entry.note:find("de-duplication", 1, true)) then
                builder_note_ok = false
                print("      (a builder row does not say why engine = false: "
                    .. tostring(entry.action) .. ")")
            end
        end
    end
    check(builder_note_ok, "apl: every builder row states that engine = false is not a gap")
    -- The rotation label names the slot-less actions (the guide's slot contract
    -- is frozen): the new racial is named, the retired belt row is gone.
    local class_src_text = read_file("classes/rogue.lua")
    check(class_src_text:find('gnome_eureka = "Eureka!"', 1, true) ~= nil,
        "apl: the rotation label names the Eureka! racial")
    check(class_src_text:find('hypersharp = "Hypersharp', 1, true) == nil,
        "apl: the rotation label carries no retired Hypersharp row")

    -- The family-split ids (the traps the gap analysis walked into). These are
    -- the rows' own ids, pinned in both directions: a row that moves an id to
    -- the wrong family's row fails here.
    local function row_for(action, family)
        for i = 13, #rotation do
            local entry = rotation[i]
            if entry.action == action and entry.families[family] == true then
                return entry
            end
        end
        return nil
    end
    local sod_vanish = row_for("vanish", "SOD")
    local wrath_vanish = row_for("vanish", "WRATH")
    local forever_vanish = row_for("vanish", "FOREVER")
    check(sod_vanish ~= nil, "apl: the SoD carries the Vanish row")
    check(wrath_vanish ~= nil, "apl: the WotLK carries the Vanish row")
    check(forever_vanish ~= nil, "apl: the Forever client carries the Vanish row")
    eq(sod_vanish and sod_vanish.spell_ids.SOD, 1856, "apl: the SoD's Vanish is 1856")
    eq(wrath_vanish and wrath_vanish.spell_ids.WRATH, 26889, "apl: the WotLK's Vanish is 26889")
    -- 1857 is VANISH RANK 2 on the Forever client, not Cloak of Shadows.
    eq(forever_vanish and forever_vanish.spell_ids.FOREVER, 1857,
        "apl: the Forever client's Vanish is 1857 (rank 2), never Cloak of Shadows")
    eq(forever_vanish and forever_vanish.spell_names.FOREVER, "Vanish",
        "apl: the Forever client's 1857 is named Vanish")
    -- 14183 is PREMEDITATION on the Forever client, not Shadowstep.
    local forever_premed = row_for("premeditation", "FOREVER")
    check(forever_premed ~= nil, "apl: the Forever client carries the Premeditation row")
    eq(forever_premed and forever_premed.spell_ids.FOREVER, 14183,
        "apl: the Forever client's 14183 is Premeditation")
    -- 1241584 is MUTILATE rank 4 on the Forever client.
    local forever_mutilate = row_for("mutilate", "FOREVER")
    eq(forever_mutilate and forever_mutilate.spell_ids.FOREVER, 1241584,
        "apl: the Forever client's 1241584 is Mutilate rank 4")
    -- The TBC / Forever Hemorrhage and Backstab ids (the bench corpus had the
    -- Hemorrhage pair swapped once already).
    local tbc_hemo = row_for("hemorrhage", "TBC")
    local forever_hemo = row_for("hemorrhage", "FOREVER")
    eq(tbc_hemo and tbc_hemo.spell_ids.TBC, 26864, "apl: the TBC's Hemorrhage is 26864")
    eq(forever_hemo and forever_hemo.spell_ids.FOREVER, 16511, "apl: the Forever client's Hemorrhage is 16511")
    local tbc_back = row_for("backstab", "TBC")
    local forever_back = row_for("backstab", "FOREVER")
    eq(tbc_back and tbc_back.spell_ids.TBC, 26863, "apl: the TBC's Backstab is 26863")
    eq(forever_back and forever_back.spell_ids.FOREVER, 11281, "apl: the Forever client's Backstab is 11281")
    -- The remaining cited ids.
    eq(row_for("mutilate", "TBC").spell_ids.TBC, 34413, "apl: the TBC's Mutilate is 34413")
    eq(row_for("mutilate", "WRATH").spell_ids.WRATH, 48666, "apl: the WotLK's Mutilate is 48666")
    eq(row_for("saber_slash", "SOD").spell_ids.SOD, 424785, "apl: the SoD's Saber Slash is 424785")
    eq(row_for("poisoned_knife", "SOD").spell_ids.SOD, 425012, "apl: the SoD's Poisoned Knife is 425012")
    eq(row_for("tricks_of_the_trade", "WRATH").spell_ids.WRATH, 57934,
        "apl: the WotLK's Tricks of the Trade is 57934")
    eq(row_for("killing_spree", "WRATH").spell_ids.WRATH, 51690, "apl: the WotLK's Killing Spree is 51690")
    eq(row_for("hypersharp", "WRATH").spell_ids.WRATH, 54758, "apl: the WotLK's belt-enchant effect is 54758")
    eq(row_for("hypersharp", "WRATH").spell_names.WRATH, "Hyperspeed Acceleration",
        "apl: the CLIENT's own name for 54758 is Hyperspeed Acceleration (never Hypersharp Weapon)")
    eq(row_for("ambush", "FOREVER").spell_ids.FOREVER, 11269, "apl: the Forever client's Ambush is 11269")
    eq(row_for("garrote", "FOREVER").spell_ids.FOREVER, 11290, "apl: the Forever client's Garrote is 11290")
    eq(row_for("preparation", "FOREVER").spell_ids.FOREVER, 14185, "apl: the Forever client's Preparation is 14185")
    eq(row_for("venom", "FOREVER").spell_ids.FOREVER, 1310703, "apl: the Forever client's Venom is 1310703")
    eq(row_for("blood_fury", "FOREVER").spell_ids.FOREVER, 20572, "apl: the Forever client's Blood Fury is 20572")
    eq(row_for("elunes_light", "FOREVER").spell_ids.FOREVER, 1259799,
        "apl: the Forever client's Elune's Light is 1259799")
    eq(row_for("gnome_eureka", "FOREVER").spell_ids.FOREVER, 1259812,
        "apl: the Forever client's Eureka! racial is 1259812")
    eq(row_for("gnome_eureka", "FOREVER").spell_names.FOREVER, "Eureka!",
        "apl: the CLIENT's own name for 1259812 is Eureka!")
    eq(row_for("ghostly_strike", "FOREVER").spell_ids.FOREVER, 14278,
        "apl: the Forever client's Ghostly Strike is 14278")
    -- The two filed rows name WHAT is missing, exactly: the belt enchant's own
    -- availability and the APL's build constant.
    local tbc_backstab_row = row_for("backstab", "TBC")
    check(tbc_backstab_row ~= nil and type(tbc_backstab_row.needs) == "string"
        and tbc_backstab_row.needs:lower():find("constant", 1, true) ~= nil,
        "apl: the TBC Backstab row names the APL's build constant")
    local wrath_hypersharp_row = row_for("hypersharp", "WRATH")
    check(wrath_hypersharp_row ~= nil and type(wrath_hypersharp_row.needs) == "string"
        and wrath_hypersharp_row.needs:find("ITEM effect", 1, true) ~= nil,
        "apl: the Hypersharp row names the belt enchant's availability")

    -- The family gates: the plain Era client never sees the SoD-only rows, and
    -- the SoD client sees them.
    local era_slice = ST2.ROGUE.practice_rotation_for("ERA")
    local era_actions = {}
    for i = 1, #era_slice do
        era_actions[era_slice[i].action] = true
    end
    eq(era_actions.vanish, nil, "apl: the Era slice carries no Vanish (the Era APL has no row)")
    eq(era_actions.poisoned_knife, nil, "apl: the Era slice carries no Poisoned Knife")
    eq(era_actions.saber_slash, nil, "apl: the Era slice carries no Saber Slash")
    eq(era_actions.ambush, nil, "apl: the Era slice carries no Ambush")
    eq(era_actions.venom, nil, "apl: the Era slice carries no Venom")
    local sod_slice = ST2.ROGUE.practice_rotation_for("SOD")
    local sod_actions = {}
    for i = 1, #sod_slice do
        sod_actions[sod_slice[i].action] = true
    end
    eq(sod_actions.vanish, true, "apl: the SoD slice carries the Vanish row")
    eq(sod_actions.poisoned_knife, true, "apl: the SoD slice carries the Poisoned Knife row")
    eq(sod_actions.saber_slash, nil,
        "apl: the SoD slice leaves the Saber Slash row out (the builder arm plays it)")
    eq(sod_actions.ambush, nil, "apl: the SoD slice carries no Ambush")
    local tbc_apl_slice = ST2.ROGUE.practice_rotation_for("TBC")
    local tbc_apl_actions = {}
    for i = 1, #tbc_apl_slice do
        tbc_apl_actions[tbc_apl_slice[i].action] = true
    end
    eq(tbc_apl_actions.mutilate, nil,
        "apl: the TBC slice leaves the Mutilate row out (the builder arm plays it)")
    eq(tbc_apl_actions.vanish, nil, "apl: the TBC slice carries no Vanish (the TBC APL has no row)")
    local wrath_slice = ST2.ROGUE.practice_rotation_for("WRATH")
    local wrath_actions = {}
    for i = 1, #wrath_slice do
        wrath_actions[wrath_slice[i].action] = true
    end
    eq(wrath_actions.vanish, true, "apl: the WotLK slice carries the Vanish row")
    eq(wrath_actions.tricks_of_the_trade, true, "apl: the WotLK slice carries Tricks of the Trade")
    eq(wrath_actions.killing_spree, true, "apl: the WotLK slice carries Killing Spree")
    eq(wrath_actions.hypersharp, nil,
        "apl: the WotLK slice leaves the filed Hypersharp row out")
    local forever_slice = ST2.ROGUE.practice_rotation_for("FOREVER")
    local forever_actions = {}
    for i = 1, #forever_slice do
        forever_actions[forever_slice[i].action] = true
    end
    eq(forever_actions.ambush, true, "apl: the Forever slice carries the Ambush row")
    eq(forever_actions.garrote, true, "apl: the Forever slice carries the Garrote row")
    eq(forever_actions.preparation, true, "apl: the Forever slice carries the Preparation row")
    eq(forever_actions.premeditation, true, "apl: the Forever slice carries the Premeditation row")
    eq(forever_actions.venom, true, "apl: the Forever slice carries the Venom row")
    eq(forever_actions.blood_fury, true, "apl: the Forever slice carries the Blood Fury row")
    eq(forever_actions.elunes_light, true, "apl: the Forever slice carries the Elune's Light row")
    eq(forever_actions.gnome_eureka, true,
        "apl: the Forever slice carries the wired Gnome Eureka row")
    eq(forever_actions.mutilate, nil,
        "apl: the Forever slice leaves the Mutilate row out (the builder arm plays it)")

    -- The slice is the rows the engine can ACTUALLY ask for: a builder row (the
    -- builder arm plays it) and a filed row (its read does not exist yet) are
    -- both buttons that can never be the right answer.
    local engine_facing_ok = true
    for i = 1, #forever_slice do
        if forever_slice[i].engine == false or forever_slice[i].live == false then
            engine_facing_ok = false
        end
    end
    check(engine_facing_ok, "apl: the slice carries the engine-facing rows only")
    local forever_venom_in_slice = false
    for i = 1, #forever_slice do
        if forever_slice[i].action == "venom" then
            forever_venom_in_slice = true
        end
    end
    check(forever_venom_in_slice, "apl: the Forever slice carries the live Venom row")
    local forever_vanish_in_slice = false
    for i = 1, #forever_slice do
        if forever_slice[i].action == "vanish" then
            forever_vanish_in_slice = true
        end
    end
    check(forever_vanish_in_slice,
        "apl: the wired Forever Vanish row rides in the slice")

    -- The pre-pull table (HU-12): the APLs' prepullActions live here, never in
    -- the combat rotation.
    local prepulls = ST2.ROGUE.practice_prepulls
    check(type(prepulls) == "table", "apl: the pre-pull table ships")
    eq(type(prepulls.TBC), "table", "apl: the TBC carries a pre-pull list")
    eq(prepulls.TBC[1].action, "ar", "apl: the TBC pre-pulls Adrenaline Rush")
    eq(prepulls.TBC[1].spell, 13750, "apl: the TBC pre-pull's Adrenaline Rush is 13750")
    eq(prepulls.TBC[1].at, -1, "apl: the TBC pre-pull lands at -1 s")
    eq(prepulls.SOD[1].action, "blood_fury", "apl: the SoD pre-pulls Blood Fury")
    eq(prepulls.SOD[1].at, -1.5, "apl: the SoD pre-pull lands at -1.5 s")
    eq(prepulls.FOREVER[1].action, "bf", "apl: the Forever client pre-pulls Blade Flurry")
    eq(prepulls.FOREVER[2].action, "premeditation", "apl: the Forever client pre-pulls Premeditation")
    eq(prepulls.FOREVER[3].kind, "aura", "apl: the Forever Stealth pre-pull is an aura activation")
    eq(prepulls.WRATH[1].kind, "aura", "apl: the WotLK pre-pull is an aura activation")
    local prepull_cited = true
    for family, rows in pairs(prepulls) do
        for i = 1, #rows do
            if type(rows[i].source) ~= "string" or rows[i].source == "" then
                prepull_cited = false
                print("      (uncited pre-pull row: " .. tostring(family) .. ")"
                    .. tostring(i))
            end
        end
    end
    check(prepull_cited, "apl: every pre-pull row cites its APL")
    -- The pre-pull rows are NOT combat rotation rows.
    local rotation_actions = {}
    for i = 1, #rotation do
        rotation_actions[rotation[i].action] = true
    end
    local prepull_not_rotation = true
    for family, rows in pairs(prepulls) do
        for i = 1, #rows do
            if rows[i].kind == "aura" and rotation_actions[rows[i].action] then
                prepull_not_rotation = false
                print("      (an aura pre-pull row is also a rotation row: "
                    .. tostring(family) .. " " .. tostring(rows[i].action) .. ")")
            end
        end
    end
    check(prepull_not_rotation, "apl: the aura pre-pull rows are not combat rotation rows")
end

    -- The gather's utility reads: only the RUNNING family's rows are read, and a
    -- row whose spell the client does not know stays nil (the arm hides).
    -- (The builder candidates - Saber Slash, Mutilate, Hemorrhage, Backstab -
    -- stay OUT of the fixture: the builder chain would resolve them and the
    -- builder identity pins would move.)
do
    local sb = build()
    local ST2 = sb.ST
    local gathered = ST2.ROGUE.gather_guide_inputs(ST2, {})
    eq(gathered.vanish_ready, nil,
        "apl: the Era client reads no Vanish row (the Era APL has none)")
    eq(gathered.poisoned_knife_ready, nil, "apl: the Era client reads no Poisoned Knife")
    eq(gathered.ambush_ready, nil, "apl: the Era client reads no Ambush")

    local sod = build()
    sod.st.family = "ERA"
    sod.ST.rogue_is_sod = true
    local sod_gathered = sod.ST.ROGUE.gather_guide_inputs(sod.ST, {})
    eq(sod_gathered.vanish_ready, true, "apl: the SoD reads the Vanish readiness")
    eq(sod_gathered.envenom_ready, true, "apl: the SoD reads the Envenom readiness")
    eq(sod_gathered.poisoned_knife_ready, true, "apl: the SoD reads the Poisoned Knife readiness")
    eq(sod_gathered.master_of_subtlety_active, false,
        "apl: the SoD reads the Master of Subtlety aura (down)")
    eq(sod_gathered.ambush_ready, nil, "apl: the SoD reads no Forever row")

    local wrath = build()
    wrath.st.family = "WRATH"
    local wrath_gathered = wrath.ST.ROGUE.gather_guide_inputs(wrath.ST, {})
    eq(wrath_gathered.vanish_ready, true, "apl: the WotLK reads the Vanish readiness")
    eq(wrath_gathered.tricks_ready, true, "apl: the WotLK reads the Tricks readiness")
    eq(wrath_gathered.killing_spree_ready, true, "apl: the WotLK reads the Killing Spree readiness")
    eq(wrath_gathered.vanished_active, false, "apl: the WotLK reads the 58426 aura (down)")
    eq(wrath_gathered.ambush_ready, nil, "apl: the WotLK reads no Forever row")

    local forever = build()
    forever.st.family = "FOREVER"
    -- The Garrote's CURRENT energy cost (the APL's spellCurrentCost(11290)):
    -- the client's own cost table - one entry per power type, the flat amount
    -- in .cost (the energy entry is the one the client names as its energy
    -- power type).
    forever.spell_costs = { [122] = { { type = 1, cost = 100 }, { type = 3, cost = 45 } } }
    -- The Eureka! racial's FULL cooldown (the APL's spellFullCooldown) in
    -- milliseconds - the client's GetSpellBaseCooldown shape.
    forever.base_cd = 120000
    local forever_gathered = forever.ST.ROGUE.gather_guide_inputs(forever.ST, {})
    eq(forever_gathered.ambush_ready, true, "apl: the Forever client reads the Ambush readiness")
    eq(forever_gathered.garrote_ready, true, "apl: the Forever client reads the Garrote readiness")
    eq(forever_gathered.preparation_ready, true, "apl: the Forever client reads the Preparation readiness")
    eq(forever_gathered.premeditation_ready, true, "apl: the Forever client reads the Premeditation readiness")
    eq(forever_gathered.venom_ready, true, "apl: the Forever client reads the Venom readiness")
    eq(forever_gathered.blood_fury_ready, true, "apl: the Forever client reads the Blood Fury readiness")
    eq(forever_gathered.elunes_light_ready, true, "apl: the Forever client reads the Elune's Light readiness")
    eq(forever_gathered.ambush_cue_active, false, "apl: the Forever client reads the 462707 aura (down)")
    eq(forever_gathered.venom_buff_active, false, "apl: the Forever client reads the Venom buff (down)")
    eq(forever_gathered.garrote_dot_active, false, "apl: the Forever client reads the Garrote dot (down)")
    eq(forever_gathered.garrote_energy_cost, 45,
        "apl: the Forever client reads the Garrote's current energy cost")
    eq(forever_gathered.ar_known, true,
        "apl: the Forever client reads the Adrenaline Rush's known state")
    eq(forever_gathered.ar_buff_active, false,
        "apl: the Forever client reads the Adrenaline Rush's buff (down)")
    eq(forever_gathered.gnome_eureka_ready, true,
        "apl: the Forever client reads the Eureka! racial's readiness")
    eq(forever_gathered.gnome_eureka_full_cd, 120,
        "apl: the Forever client reads the Eureka! racial's full cooldown")
    eq(forever_gathered.tricks_ready, nil, "apl: the Forever client reads no WotLK row")
    -- The energy-cost read is nil-safe: a client that cannot answer the cost
    -- leaves the row's gate unreadable (unknown-hides), never a guessed cost.
    local no_cost = build()
    no_cost.st.family = "FOREVER"
    local no_cost_gathered = no_cost.ST.ROGUE.gather_guide_inputs(no_cost.ST, {})
    eq(no_cost_gathered.garrote_energy_cost, nil,
        "apl: an unreadable Garrote cost stays nil (the Vanish row hides)")
    eq(no_cost_gathered.gnome_eureka_full_cd, nil,
        "apl: an unreadable Eureka! cooldown stays nil (the racial hides)")
    -- A client that does not expose the energy power type cannot answer an
    -- energy cost - the read stays nil (the energy type is never a guessed
    -- constant).
    local no_enum = build({ no_enum = true })
    no_enum.st.family = "FOREVER"
    no_enum.spell_costs = { [122] = { { cost = 45 } } }
    local no_enum_gathered = no_enum.ST.ROGUE.gather_guide_inputs(no_enum.ST, {})
    eq(no_enum_gathered.garrote_energy_cost, nil,
        "apl: a client without the energy power type reads no energy cost")
    -- The cost read picks the ENERGY entry: the client's cost table carries a
    -- mana entry first and the energy entry second.
    eq(forever_gathered.garrote_energy_cost, 45,
        "apl: the Garrote's energy cost is the ENERGY entry, not the first one")
end

--=========================================================================================
-- The NEUTRAL action set (the practice panel's legitimate-but-ungraded presses)
--
-- The class publishes ST.ROGUE.practice_neutral_actions (the contract fixed by
-- the orchestrator, practice.lua's class contract block). The engine treats a
-- press of one of these keys as NEUTRAL: no attempt, no points, no streak change,
-- and NOT a mis-pick. A key that is neither a rotation action nor neutral stays
-- a mis-pick, so the set is a deliberate, CLOSED list - never "everything except
-- the rotation".
--
-- The publish is FAMILY-SCOPED (a family key -> a set of action keys), because the
-- answer is family-dependent:
--   * Cold Blood - the class's own row is a TBC/FOREVER row, so the Era branch
--     and the WotLK client have no rotation row that asks for it while the
--     talent exists on both.
--   * Shiv - the class's own row is an ERA/SoD/TBC row, so the WotLK client and
--     the Forever client have no rotation row that asks for it while the ability
--     exists on both.
--   * Rupture is deliberately NOT published: on the Era client the spell does not
--     exist at all, so an Era press of it is an intentional mis-pick.
--
-- Every bucket ALSO carries the class's common abilities (the practice-panel
-- ability list: a heal, food, a movement ability) - the abilities the panel
-- offers but the rotation never grades.
--=========================================================================================
do
    local sb = build()
    local M = sb.ST.ROGUE
    local published = M.practice_neutral_actions
    eq(type(published), "table", "neutral: the rogue publishes a neutral action set")
    eq(type(published.ERA), "table", "neutral: the Era branch publishes a bucket")
    eq(type(published.TBC), "table", "neutral: the TBC client publishes a bucket")
    eq(type(published.WRATH), "table", "neutral: the WotLK client publishes a bucket")
    eq(type(published.FOREVER), "table", "neutral: the Forever client publishes a bucket")
    eq(published.ERA.coldblood, true, "neutral: Cold Blood is neutral on the Era branch")
    eq(published.WRATH.coldblood, true, "neutral: Cold Blood is neutral on the WotLK client")
    eq(published.WRATH.shiv, true, "neutral: Shiv is neutral on the WotLK client")
    eq(published.FOREVER.shiv, true, "neutral: Shiv is neutral on the Forever client")
    eq(published.ERA.shiv, nil, "neutral: Shiv is not neutral on the Era branch (a rotation row)")
    eq(published.TBC.coldblood, nil,
        "neutral: Cold Blood is not neutral on the TBC client (a rotation row)")
    eq(published.TBC.shiv, nil,
        "neutral: Shiv is not neutral on the TBC client (a rotation row)")
    for family, bucket in pairs(published) do
        for key, value in pairs(bucket) do
            eq(value, true, "neutral: the " .. tostring(family)
                .. " bucket holds key = true entries (" .. tostring(key) .. ")")
        end
    end

    -- The rotation slice of each family (the class's own published slice).
    local function slice_keys(family)
        local out = {}
        local entries = M.practice_rotation_for(family)
        for i = 1, #entries do
            local e = entries[i]
            if type(e) == "table" and type(e.action) == "string" then out[e.action] = true end
        end
        return out
    end

    -- THE GRADING-INTEGRITY PIN: a rotation action can never be neutral. The
    -- engine grades the EXPECTED action first, so a rotation press still hits -
    -- but a rotation action published as neutral would make a WRONG rotation
    -- press free.
    for family, bucket in pairs(published) do
        local keys = slice_keys(family)
        for key in pairs(bucket) do
            check(keys[key] ~= true,
                "neutral: " .. tostring(key) .. " is not a rotation action on " .. tostring(family)
                .. " (a rotation action can never be neutral)")
        end
    end

    -- The family-awareness itself: the same key IS a rotation action on the
    -- families the class did not publish it for.
    check(slice_keys("TBC").coldblood == true,
        "neutral: Cold Blood is a rotation action on the TBC client (never published there)")
    check(slice_keys("FOREVER").coldblood == true,
        "neutral: Cold Blood is a rotation action on the Forever client")
    check(slice_keys("ERA").shiv == true,
        "neutral: Shiv is a rotation action on the Era branch (never published there)")
    check(slice_keys("TBC").shiv == true,
        "neutral: Shiv is a rotation action on the TBC client")
    -- Rupture: not a rotation action on the Era branch, but the ability does not
    -- exist there - so it is an intentional mis-pick, never a neutral action.
    check(slice_keys("ERA").rupture ~= true,
        "neutral: Rupture is no rotation row on the Era branch (the ability does not exist there)")
    check(published.ERA.rupture == nil and published.WRATH.rupture == nil,
        "neutral: Rupture is published for no family (it is an intentional mis-pick)")

    -- THE PRACTICE-PANEL ABILITY LIST: the common abilities the panel offers but
    -- the rotation never grades. Every entry names the client's spell, carries a
    -- label and cites at least one spell id - an ability whose id nobody can
    -- source is not published at all.
    local common = M.practice_common_actions
    eq(type(common), "table", "panel: the rogue publishes a practice-panel ability list")
    check(#common > 0, "panel: the practice-panel ability list is not empty")
    for i = 1, #common do
        local action = common[i]
        eq(type(action), "table", "panel: common action " .. tostring(i) .. " is a table")
        eq(type(action.key), "string", "panel: common action " .. tostring(i) .. " carries a key")
        eq(type(action.label), "string", "panel: common action " .. tostring(action.key)
            .. " carries a label")
        eq(type(action.names), "table", "panel: common action " .. tostring(action.key)
            .. " carries the client's spell name")
        check(#action.names > 0, "panel: common action " .. tostring(action.key)
            .. " names the client's spell")
        eq(type(action.ids), "table", "panel: common action " .. tostring(action.key)
            .. " cites a spell id")
        check(#action.ids > 0, "panel: common action " .. tostring(action.key)
            .. " cites at least one spell id")
        for j = 1, #action.ids do
            eq(type(action.ids[j]), "number", "panel: common action " .. tostring(action.key)
                .. " cites a numeric spell id")
        end
        -- Every common ability is published as neutral on every family (the panel
        -- offers it everywhere) and is never a rotation action.
        for _, family in ipairs({ "ERA", "TBC", "WRATH", "FOREVER" }) do
            eq(published[family][action.key], true, "panel: " .. tostring(action.key)
                .. " is neutral on " .. family .. " (the panel offers it there)")
            check(slice_keys(family)[action.key] ~= true, "panel: the common ability "
                .. tostring(action.key) .. " is not a rotation action on " .. family)
        end
    end
    -- The panel's widening seam: the class publishes the widened slot list and
    -- applies it to the guide slot list (the shaman's apply_family_slots
    -- precedent), so the practice panel offers the common abilities.
    eq(type(M.practice_panel_slots), "function",
        "panel: the class publishes the panel slot list")
    eq(type(M.apply_practice_panel_actions), "function",
        "panel: the class publishes the widening seam")
    local widened = M.practice_panel_slots()
    eq(type(widened), "table", "panel: the panel slot list is a table")
    check(#widened >= #M.guide.slots, "panel: the panel slot list carries the guide slots")
end

-- ---- the shipped comment matches the code (the final-gate claim) -------------
-- The FOR THE RECORD note claimed "the NAME-first resolution finds the client's
-- own rank": the classic-line name leg is UNCONFIRMED in-client (the audit's
-- §6 C1) and the id table is the citation and the fallback - the client's own
-- rank only where that id still exists on it. The pins keep the stale claim OUT
-- and the corrected statement IN (source-shape pins, so a correct rewording
-- still passes).
--
-- THE MATCH IS ON PROSE, NOT ON SOURCE LINES: the claim is wrapped across
-- three source lines here, so the file is flattened (the line-leading comment
-- marker dropped, the lines joined with one space) and the sentence is matched
-- whole.
do
    local function prose(path)
        local fh = io.open(path, "r")
        local src = fh and fh:read("*a") or ""
        if fh then fh:close() end
        local parts = {}
        for line in (src:gsub("\r\n", "\n")):gmatch("[^\n]*") do
            parts[#parts + 1] = (line:gsub("^%s*%-%-%s*", ""))
        end
        return (table.concat(parts, " "):gsub("%s+", " "))
    end
    local p = prose(ROOT .. "classes/rogue.lua")
    check(p:find("every client family answers its own rank art", 1, true) == nil,
        "comment: the stale 'every client family answers its own rank art' claim is gone")
    check(p:find("the NAME-first resolution finds the client's own rank", 1, true) == nil,
        "comment: the stale 'the NAME-first resolution finds the client's own rank' claim is gone")
    check(p:find("answers its own rank id", 1, true) ~= nil,
        "comment: the resolver note says what the code does")
    check(p:find("the NAME-first leg finds the client's own rank only where the client ANSWERS the name", 1, true) ~= nil,
        "comment: the FOR THE RECORD note states the name leg as conditional and UNCONFIRMED")
end

--=========================================================================================
-- The HUD captions carry a font BEFORE their first SetText (the SoD live crash
-- class: "FontString:SetText(): Font not set")
--
-- The sandbox FontString above is SoD-faithful: SetFont(nil) latches nothing and
-- SetText with no font throws. The rogue module's three captions (the Era SS
-- window, the weapon-swap cost line and the poison reminder) are fonted through
-- the shared chain (utils.lua apply_font: the caller's path -> STANDARD_TEXT_FONT
-- -> the classic client font, every step pcall-guarded, never throwing) before
-- their first SetText.
--=========================================================================================
do
    local sb = build({ project = 2 })   -- Classic Era
    local ST2 = sb.ST
    local vf = sb.visuals
    local ok_init, err_init = pcall(ST2.ROGUE.post_init, ST2)
    check(ok_init, "font: post_init never throws (" .. tostring(err_init) .. ")")

    local function caption_fonted(fs, label)
        check(fs ~= nil, "font: the " .. label .. " caption exists")
        if not fs then return end
        check(fs.font ~= nil, "font: the " .. label .. " caption carries a font")
        eq(fs:GetFont(), "Fonts\\FRIZQT__.TTF", "font: the " .. label .. " caption uses the standard font")
    end
    caption_fonted(vf.rogue_ss_text, "SS window")
    caption_fonted(vf.rogue_swap_text, "weapon swap")
    caption_fonted(vf.rogue_poison_text, "poison reminder")

    -- The captions keep their text: the font never costs a line.
    check(vf.rogue_ss_text.text ~= nil, "font: the SS caption keeps its text")
    check(vf.rogue_swap_text.text ~= nil, "font: the swap caption keeps its text")

    -- Source: the three captions go through the shared chain, the chain call
    -- precedes each caption's first SetText, and no direct SetFont call survives.
    local src = read_file("classes/rogue.lua")
    local sites = {
        { name = "SS window", font = "st.utils.apply_font(ss_text", text = "ss_text:SetText(" },
        { name = "weapon swap", font = "st.utils.apply_font(swap_text", text = "swap_text:SetText(" },
        { name = "poison reminder", font = "st.utils.apply_font(poison_text", text = "poison_text:SetText(" },
    }
    for _, site in ipairs(sites) do
        local font_at = src:find(site.font, 1, true)
        local text_at = src:find(site.text, 1, true)
        check(font_at ~= nil and text_at ~= nil and font_at < text_at,
            "font: the " .. site.name .. " caption is fonted before its first SetText")
    end
    check(src:find(":SetFont(", 1, true) == nil,
        "font: no direct SetFont call survives in classes/rogue.lua")
end

--=========================================================================================
-- R1 name-carrying payloads: the aura matchers read id or name on every
-- family (id primary, name secondary). Era rides numeric ids, TBC Anniversary
-- can ride name-carrying/id-less rows (compat.lua); either shape lands the
-- read on either client. A foreign aura changes nothing.
--=========================================================================================
do
    -- Era: the id shape lands the Rupture guide read, and the name shape does too.
    local sb = build({ project = 2 })
    local RST = sb.ST
    sb.auras = { target = { { name = "Rupture", duration = 16,
        expiration = sb.clock + 9, spell_id = 102 } } }
    local out = RST.ROGUE.gather_guide_inputs(RST, {})
    eq(out.rupture_remains, 9, "Era: the Rupture id lands the guide read")

    sb.auras = { target = { { name = "Rupture", duration = 16,
        expiration = sb.clock + 9, spell_id = nil } } }
    out = RST.ROGUE.gather_guide_inputs(RST, {})
    eq(out.rupture_remains, 9, "Era: an id-less Rupture row lands the guide read too")
end

do
    -- TBC Anniversary: the name shape lands the read, and so does the id shape -
    -- including a localized-client-style row whose name differs from the
    -- resolved English one.
    local sb = build({ project = 5 })
    local RST = sb.ST
    sb.auras = { target = { { name = "Rupture", duration = 16,
        expiration = sb.clock + 9, spell_id = nil } } }
    local out = RST.ROGUE.gather_guide_inputs(RST, {})
    eq(out.rupture_remains, 9, "TBC: an id-less Rupture row lands the guide read")

    sb.auras = { target = { { name = "Rupture", duration = 16,
        expiration = sb.clock + 9, spell_id = 102 } } }
    out = RST.ROGUE.gather_guide_inputs(RST, {})
    eq(out.rupture_remains, 9, "TBC: the Rupture id lands the guide read")

    sb.auras = { target = { { name = "Ruptura", duration = 16,
        expiration = sb.clock + 9, spell_id = 102 } } }
    out = RST.ROGUE.gather_guide_inputs(RST, {})
    eq(out.rupture_remains, 9, "TBC: the id arm lands a foreign-named Rupture row")

    -- A foreign aura changes nothing.
    sb.auras = { target = { { name = "Scare Beast", duration = 16,
        expiration = sb.clock + 9, spell_id = nil } } }
    out = RST.ROGUE.gather_guide_inputs(RST, {})
    eq(out.rupture_remains, nil, "TBC: an unrelated aura leaves Rupture missing")
end

do
    -- The utility presence read rides the same matcher on the Forever shapes:
    -- Garrote by id and by name, Ambush by name, and a foreign aura reads down.
    local sb = build()
    sb.st.family = "FOREVER"
    local RST = sb.ST
    sb.auras = { target = { { name = "Garrote", duration = 12,
        expiration = sb.clock + 7, spell_id = 11290 } } }
    local out = RST.ROGUE.gather_guide_inputs(RST, {})
    eq(out.garrote_dot_active, true, "Forever: the Garrote id reads the dot up")

    sb.auras = { target = { { name = "Garrote", duration = 12,
        expiration = sb.clock + 7, spell_id = nil } } }
    out = RST.ROGUE.gather_guide_inputs(RST, {})
    eq(out.garrote_dot_active, true, "Forever: an id-less Garrote row reads the dot up")

    sb.auras = { player = { { name = "Ambush", duration = 10,
        expiration = sb.clock + 5, spell_id = nil } } }
    out = RST.ROGUE.gather_guide_inputs(RST, {})
    eq(out.ambush_cue_active, true, "Forever: an id-less Ambush row reads the cue up")

    sb.auras = { target = { { name = "Scare Beast", duration = 12,
        expiration = sb.clock + 7, spell_id = nil } } }
    out = RST.ROGUE.gather_guide_inputs(RST, {})
    eq(out.garrote_dot_active, false, "Forever: an unrelated aura reads the dot down")
end

do
    -- The SoD Master of Subtlety row reads by id and by name; the Wrath 58426
    -- aura pins its id shape only (its name is UNCONFIRMED in-repo).
    local sb = build()
    sb.st.family = "ERA"
    sb.ST.rogue_is_sod = true
    local RST = sb.ST
    sb.auras = { player = { { name = "Master of Subtlety", duration = 10,
        expiration = sb.clock + 5, spell_id = 425096 } } }
    local out = RST.ROGUE.gather_guide_inputs(RST, {})
    eq(out.master_of_subtlety_active, true, "SoD: the MoS id reads the aura up")

    sb.auras = { player = { { name = "Master of Subtlety", duration = 10,
        expiration = sb.clock + 5, spell_id = nil } } }
    out = RST.ROGUE.gather_guide_inputs(RST, {})
    eq(out.master_of_subtlety_active, true, "SoD: an id-less MoS row reads the aura up")

    local wrath = build()
    wrath.st.family = "WRATH"
    sb.auras = nil
    wrath.auras = { player = { { name = "Vanish", duration = 10,
        expiration = wrath.clock + 5, spell_id = 58426 } } }
    local wout = wrath.ST.ROGUE.gather_guide_inputs(wrath.ST, {})
    eq(wout.vanished_active, true, "Wrath: the 58426 id reads the Vanish aura up")
end

do
    -- Era and Anniversary (TBC) run no utility-aura rows: the presence inputs
    -- stay nil there by construction, so no name-carrying row can misread.
    local era = build({ project = 2 })
    local eout = era.ST.ROGUE.gather_guide_inputs(era.ST, {})
    eq(eout.ambush_cue_active, nil, "Era: no utility aura row is read")
    eq(eout.garrote_dot_active, nil, "Era: no Garrote row is read")

    local tbc = build({ project = 5 })
    local tout = tbc.ST.ROGUE.gather_guide_inputs(tbc.ST, {})
    eq(tout.ambush_cue_active, nil, "TBC: no utility aura row is read")
    eq(tout.vanished_active, nil, "TBC: no Vanish row is read")
end

--=========================================================================================
-- Done
--=========================================================================================
print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then
    os.exit(1)
end
os.exit(0)

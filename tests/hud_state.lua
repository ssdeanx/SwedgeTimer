-- tests/hud_state.lua: offline tests for the cooldown HUD (hud.lua) and its paladin
-- slot provider (classes/paladin.lua) over the real compat.lua + utils.lua +
-- nextaction.lua in a sandbox.
-- Pins the frozen slot/provider contract, the descriptor validation, the state ->
-- visual mapping (set-once swipes, the text rules including the 2 s GCD threshold,
-- the desaturate / mana / range / glow gates), the option gates (an off slot performs
-- no reads and runs no provider), pre-init and combat-lockdown safety, absent-API
-- inertness, the trinket state machine on a fake clock, and the paladin provider's
-- live + practice readers.
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

--=========================================================================================
-- Fixtures (reset per sandbox build; the env stubs read them at call time)
--=========================================================================================
local clock = 0
local aura_list = {}
local cooldowns = {}
local known_spells = {}
-- The spell-book probe declines (returns nil) when this is true: the
-- "unknown" state of compat.lua's api.is_spell_known_state.
local known_declines = false
local item_ids = {}
local item_textures = {}
local item_cooldowns = {}
local cooldown_reads = 0
local usable_reads = 0
local range_reads = 0
local usable_impl = nil
local range_impl = nil
local target_exists = false
local target_creature_type = nil
local target_health, target_health_max = nil, nil
local lockdown = false
local cleu_impl = nil
local lcg_starts, lcg_stops = 0, 0
local created_frames = 0
local class_db = nil

local SPELL_INFOS = {
    [35395] = { name = "Crusader Strike", icon = "icon_cs" },
    [20271] = { name = "Judgement", icon = "icon_judge" },
    [26573] = { name = "Consecration", icon = "icon_consec" },
    [879] = { name = "Exorcism", icon = "icon_exo" },
    [31884] = { name = "Avenging Wrath", icon = "icon_wings" },
    [20375] = { name = "Seal of Command", icon = "icon_soc" },
    [31892] = { name = "Seal of Blood", icon = "icon_sob" },
    [21084] = { name = "Seal of Righteousness", icon = "icon_sor" },
    [24275] = { name = "Hammer of Wrath", icon = "icon_how" },
    [20930] = { name = "Holy Shock", icon = "icon_hs" },
    [407624] = { name = "Aura Mastery", icon = "icon_am" },
    -- The WotLK APL's utility band (the HUD mirrors).
    [67485] = { name = "Hand of Reckoning", icon = "icon_hor" },
    [48806] = { name = "Hammer of Wrath", icon = "icon_howw" },
    -- Hunter HUD slots. The TBC client knows Steady Shot as 34120; 56641 is the
    -- vanilla rank and exists on no client past 2.2 (bench/rotation_gap_vs_apl_
    -- 2026-10-20.md §0.0 H3), so the fixture carries the TBC id.
    [34120] = { name = "Steady Shot", icon = "icon_steady" },
    [2973] = { name = "Raptor Strike", icon = "icon_raptor" },
    [34026] = { name = "Kill Command", icon = "icon_kc" },
    [2643] = { name = "Multi-Shot", icon = "icon_multi" },
    [19574] = { name = "Bestial Wrath", icon = "icon_bw" },
    [3045] = { name = "Rapid Fire", icon = "icon_rf" },
    [19434] = { name = "Aimed Shot", icon = "icon_aimed" },
    [20904] = { name = "Aimed Shot", icon = "icon_aimed" },
    -- Warrior HUD slots.
    [7384] = { name = "Overpower", icon = "icon_op" },
    [5308] = { name = "Execute", icon = "icon_execute" },
    [1464] = { name = "Slam", icon = "icon_slam" },
    [78] = { name = "Heroic Strike", icon = "icon_hs" },
    [845] = { name = "Cleave", icon = "icon_cleave" },
    [23881] = { name = "Bloodthirst", icon = "icon_bt" },
    [1680] = { name = "Whirlwind", icon = "icon_ww" },
    -- Druid HUD slots.
    [6807] = { name = "Maul", icon = "icon_maul" },
    [33878] = { name = "Mangle", icon = "icon_mangle" },
    [1079] = { name = "Rip", icon = "icon_rip" },
    [1822] = { name = "Rake", icon = "icon_rake" },
    [22568] = { name = "Ferocious Bite", icon = "icon_bite" },
    [5221] = { name = "Shred", icon = "icon_shred" },
    -- Shaman HUD slots.
    [17364] = { name = "Stormstrike", icon = "icon_ss" },
    [8050] = { name = "Flame Shock", icon = "icon_fs" },
    [403] = { name = "Lightning Bolt", icon = "icon_lb" },
    [1535] = { name = "Fire Nova Totem", icon = "icon_firenova" },
    [8042] = { name = "Earth Shock", icon = "icon_earthshock" },
    [8512] = { name = "Windfury Totem", icon = "icon_wftotem" },
}

--=========================================================================================
-- Frame stubs (record what the HUD draws)
--=========================================================================================
local function make_fontstring()
    local f = { hidden = false }
    function f:SetPoint() end
    function f:SetJustifyH() end
    function f:SetShadowColor() end
    function f:SetShadowOffset() end
    -- SoD-faithful: SetFont with a nil path latches nothing (false, like the
    -- client); SetText with no font throws ("Font not set"). Every HUD icon
    -- must carry a font before its first SetText.
    function f:SetFont(path, size, flags)
        if path == nil then
            return false
        end
        f.font = { path, size, flags }
        return true
    end
    function f:GetFont() return f.font and f.font[1] or nil end
    function f:SetText(text)
        if f.font == nil then
            error("Font not set", 2)
        end
        f.text = text
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
    function t:SetTexCoord() end
    function t:SetTexture(tex) t.texture = tex end
    function t:SetDesaturated(flag) t.desaturated = flag end
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
        f.point = { point, anchor, rel_point, x, y }
    end
    function f:ClearAllPoints() f.point = nil end
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
    function f:GetCenter() return 50, 60 end
    function f:StartMoving() end
    function f:StopMovingOrSizing() end
    function f:RegisterEvent(event)
        f.events = f.events or {}
        f.events[event] = true
    end
    function f:CreateTexture() return make_texture() end
    function f:CreateFontString() return make_fontstring() end
    function f:SetBackdrop(backdrop) f.backdrop = backdrop end
    function f:SetBackdropColor(r, g, b, a) f.bg_color = { r, g, b, a } end
    function f:SetBackdropBorderColor(r, g, b, a) f.border_color = { r, g, b, a } end
    -- Cooldown frame API (also present on plain frames: unreachable there).
    function f:SetCooldown(start, duration)
        f.cooldown_sets = (f.cooldown_sets or 0) + 1
        f.cooldown_start, f.cooldown_duration = start, duration
    end
    function f:SetReverse(reverse) f.reverse = reverse end
    function f:SetHideCountdownNumbers(flag) f.hide_numbers = flag end
    function f:SetDrawEdge(flag) f.draw_edge = flag end
    function f:SetAllPoints() end
    return f
end

--=========================================================================================
-- Sandbox builder
--=========================================================================================
-- opts.bare_apis: omit the optional inventory / usable / combat-log globals (the
-- absent-API inertness case) and report the CLEU event invalid to the validity probe.
local function build(opts)
    opts = opts or {}
    clock = 0
    aura_list = {}
    cooldowns = {}
    -- The spellbook the knowledge probe reads. opts.known_spells REPLACES the
    -- shared table (the hunter census uses it: the SoD build of the Era client
    -- knows the Chimera Shot rune). The default path is unchanged.
    known_spells = opts.known_spells or { [35395] = true, ["Crusader Strike"] = true }
    item_ids = { [13] = nil, [14] = nil }
    item_textures = {}
    item_cooldowns = {}
    cooldown_reads, usable_reads, range_reads = 0, 0, 0
    usable_impl, range_impl = nil, nil
    target_exists, target_creature_type, lockdown = false, nil, false
    target_health, target_health_max = nil, nil
    cleu_impl = nil
    lcg_starts, lcg_stops = 0, 0
    created_frames = 0

    class_db = {
        class_enabled = true,
        hud_enabled = true,
        hud_locked = true,
        hud_visibility_key = "always",
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
        hud_show_cs = true,
        hud_show_judgement = true,
        hud_show_consecration = true,
        hud_show_exorcism = true,
        hud_show_trinket1 = true,
        hud_show_trinket2 = true,
        hud_show_wings = true,
    }

    local env = {}
    for k, v in pairs(_G) do env[k] = v end
    env._G = env
    env.WOW_PROJECT_ID = opts.project or 5
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
    env.WOW_PROJECT_MISTS_CLASSIC = 19
    env.WOW_PROJECT_MAINLINE = 1
    env.WOW_PROJECT_FOREVER = 18
    env.GetTimePreciseSec = function() return clock end
    env.GetTime = function() return clock end
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    if opts.no_std_font then
        env.STANDARD_TEXT_FONT = nil
    end
    env.GetLocale = function() return "enUS" end
    env.GetBuildInfo = function() return "0.0.0", "00000", "today", 20506 end
    env.UIParent = make_frame("UIParent")
    env.UIParent.GetCenter = function() return 0, 0 end
    env.CreateFrame = function(...)
        created_frames = created_frames + 1
        return make_frame(select(2, ...))
    end
    env.GetSpellInfo = function(spell)
        -- The client's own spell data. opts.spells REPLACES the shared table, so a
        -- per-family census can model exactly the ranks that family carries (the
        -- hunter census uses it: the TBC client knows the r7 Aimed Shot, the
        -- Forever client the r8 Raptor Strike, and so on).
        local info = (opts.spells or SPELL_INFOS)[spell]
        if info then
            return info.name, nil, info.icon, 0, 0, 0, spell
        end
        return nil
    end
    env.GetSpellCooldown = function(spell)
        cooldown_reads = cooldown_reads + 1
        local cd = cooldowns[spell]
        if cd then
            return cd.start or 0, cd.duration or 0, cd.enable or 1, 1
        end
        return 0, 0, 0, 0
    end
    env.IsSpellKnown = function(spell)
        -- The probe may DECLINE (nil): that is the "unknown" state of
        -- compat.lua's api.is_spell_known_state (no probe answered), as
        -- opposed to an answered "not known" (false).
        if known_declines then return nil end
        return known_spells[spell] == true
    end
    env.UnitAura = function(unit, index)
        if unit ~= "player" then return nil end
        local entry = aura_list[index]
        if not entry then return nil end
        return entry.name, entry.icon, entry.count, entry.dispel,
            entry.duration, entry.expiration, entry.source, nil, nil, entry.spell_id
    end
    env.UnitExists = function() return target_exists end
    env.UnitCanAttack = function() return target_exists end
    env.UnitCreatureType = function() return target_creature_type end
    env.UnitHealth = function() return target_health end
    env.UnitHealthMax = function() return target_health_max end
    env.UnitGUID = function() return "Player-1" end
    env.InCombatLockdown = function() return lockdown end
    env.IsSpellInRange = function(name, unit)
        range_reads = range_reads + 1
        if range_impl then return range_impl(name, unit) end
        return 1
    end
    if not opts.bare_apis then
        env.GetInventoryItemID = function(_, slot) return item_ids[slot] end
        env.GetInventoryItemTexture = function(_, slot) return item_textures[slot] end
        env.GetInventoryItemCooldown = function(_, slot)
            local cd = item_cooldowns[slot]
            if not cd then
                return 0, 0, 0
            end
            if cd.table_shape then
                -- Mainline SpellCooldownInfo shape: the compat wrapper must unfold it.
                return { startTime = cd.start or 0, duration = cd.duration or 0,
                    isEnabled = cd.enable == 1 }
            end
            return cd.start or 0, cd.duration or 0, cd.enable or 1
        end
        env.CombatLogGetCurrentEventInfo = function()
            if cleu_impl then
                return cleu_impl()
            end
            return nil
        end
        env.IsSpellUsable = function(name)
            usable_reads = usable_reads + 1
            if usable_impl then return usable_impl(name) end
            return true, false
        end
        env.C_EventUtils = { IsEventValid = function() return true end }
    else
        env.C_EventUtils = { IsEventValid = function() return false end }
    end

    local ST = {
        PALADIN = {},
        HUNTER = {},
        WARRIOR = {},
        DRUID = {},
        SHAMAN = {},
        ROGUE = {},
        player_class = "PALADIN",
        interfaces_are_initialised = true,
        player_guid = "Player-1",
        in_combat = false,
        twist_active_seals_count = 0,
        gcd = {},
        db = { profile = { enabled = true } },
    }
    function ST.get_class_table() return class_db end
    function ST.get_hand_table()
        return { bar_width = 275, border_width = 2, text_font = "Expressway" }
    end
    function ST.convert_color(_, t)
        return t[1] / 255, t[2] / 255, t[3] / 255, t[4]
    end

    local LCG = {}
    function LCG.PixelGlow_Start() lcg_starts = lcg_starts + 1 end
    function LCG.PixelGlow_Stop() lcg_stops = lcg_stops + 1 end
    local LSM = {}
    if opts.lsm_throw then
        function LSM.Fetch() error("LSM probe throw") end
    elseif opts.lsm_font_nil then
        function LSM.Fetch() return nil end
    else
        function LSM.Fetch(_, mediatype)
            if mediatype == "font" then return "Fonts\\FRIZQT__.TTF" end
            return nil
        end
    end
    function LSM.HashTable() return {} end
    env.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { GetAddon = function() return ST end }
        elseif major == "LibCustomGlow-1.0" then
            return LCG
        elseif major == "LibSharedMedia-3.0" then
            if opts.no_lsm then
                return nil
            end
            return LSM
        end
        return nil
    end

    local st = {}
    local modules = { "compat.lua", "utils.lua", "guard.lua", "nextaction.lua", "hud.lua", "classes/paladin.lua" }
    -- opts.class: build the sandbox for another class instead (player_class + its
    -- module). The paladin module always loads first so the shared-provider
    -- sections above keep their fixtures; the class module under test loads last.
    if opts.class and opts.class ~= "PALADIN" then
        ST.player_class = opts.class
        modules[#modules + 1] = "classes/" .. opts.class:lower() .. ".lua"
    end
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
    return { env = env, st = st, ST = ST, LCG = LCG }
end

--=========================================================================================
-- 1) Frozen contract: module surface + slot descriptor validation
--=========================================================================================
local main = build()
local st, ST = main.st, main.ST
local HUD = st.hud
check(type(HUD) == "table", "hud.lua defines st.hud")
check(type(HUD.init) == "function" and type(HUD.ensure_created) == "function"
    and type(HUD.on_update) == "function" and type(HUD.on_bar_update) == "function"
    and type(HUD.validate_slot) == "function" and type(HUD.paint) == "function"
    and type(HUD.trinket_state) == "function" and type(HUD.preview_state) == "function",
    "hud.lua exposes the documented entry points")
check(type(ST.PALADIN.get_hud_state) == "function", "classes/paladin.lua defines the provider")
check(type(ST.PALADIN.HUD_SLOTS) == "table", "classes/paladin.lua defines HUD_SLOTS")

eq(HUD.validate_slot({ key = "a", kind = "spell", spell = 1 }, true), true,
    "spell slot with provider is valid")
eq(HUD.validate_slot({ key = "a", kind = "spell", spell = 1 }, false), false,
    "spell slot without provider is rejected")
eq(HUD.validate_slot({ key = "a", kind = "spell" }, true), false,
    "spell slot without an icon source is rejected")
eq(HUD.validate_slot({ key = "a", texture = "T" }, true), true,
    "texture-only spell slot is valid")
eq(HUD.validate_slot({ key = "a", kind = "trinket", inv_slot = 13 }, false), true,
    "trinket slot needs no provider")
eq(HUD.validate_slot({ key = "a", kind = "trinket", inv_slot = 99 }, false), false,
    "trinket slot with a foreign inventory slot is rejected")
eq(HUD.validate_slot({ key = "", kind = "spell", spell = 1 }, true), false,
    "empty key is rejected")
eq(HUD.validate_slot({ key = "a", kind = "wat" }, true), false,
    "unknown kind is rejected")
eq(HUD.validate_slot(nil, true), false, "nil descriptor is rejected")

local paladin_slots = ST.PALADIN.HUD_SLOTS
eq(#paladin_slots, 14, "the paladin declares fourteen HUD slots (archive 7 + soc/sob/how/HS/AM mirror + the WotLK utility band)")
local expected_keys = { "cs", "judgement", "consecration", "exorcism", "trinket1", "trinket2", "wings",
    "soc", "sob", "how", "holy_shock", "aura_mastery", "hor", "how_wrath" }
local slot_by_key = {}
local order_ok, descriptors_ok = true, true
for i = 1, #paladin_slots do
    local slot = paladin_slots[i]
    slot_by_key[slot.key] = slot
    if slot.key ~= expected_keys[i] then order_ok = false end
    if not HUD.validate_slot(slot, true) then descriptors_ok = false end
end
check(order_ok, "the slot order is the archive's")
check(descriptors_ok, "every paladin descriptor passes the contract")
eq(paladin_slots[1].spell, 35395, "Crusader Strike keeps the archive id")
eq(paladin_slots[2].spell, 20271, "Judgement keeps the archive id")
eq(paladin_slots[3].spell, 26573, "Consecration keeps the archive id")
eq(paladin_slots[4].spell, 879, "Exorcism uses the rank-1 id that resolves on every family")
eq(paladin_slots[5].kind, "trinket", "slot 5 is a trinket slot")
eq(paladin_slots[5].inv_slot, 13, "trinket 1 reads inventory slot 13")
eq(paladin_slots[6].inv_slot, 14, "trinket 2 reads inventory slot 14")
eq(paladin_slots[7].spell, 31884, "Avenging Wrath keeps the archive id")
eq(paladin_slots[8].spell, 20375, "soc mirrors the guide's Seal of Command id")
eq(paladin_slots[9].spell, 31892, "sob mirrors the guide's twist-seal id (TBC Blood)")
eq(paladin_slots[10].spell, 24275, "how mirrors the guide's Hammer of Wrath rank-1 id")
eq(paladin_slots[11].spell, 20930, "holy_shock mirrors the guide's max-rank id")
eq(paladin_slots[12].spell, 407624, "aura_mastery mirrors the guide's legs-rune id")
eq(paladin_slots[13].key, "hor", "slot 13 is the WotLK APL's Hand of Reckoning")
eq(paladin_slots[13].spell, 67485, "hor carries the APL's Hand of Reckoning id")
eq(paladin_slots[14].key, "how_wrath", "slot 14 is the WotLK APL's Hammer of Wrath")
eq(paladin_slots[14].spell, 48806, "how_wrath carries the APL's WotLK Hammer of Wrath id")

-- Twist stays guide-only (deferred like shaman's 13→8): the composite timing cue
-- has no single live spell flag without engine coupling, and the guide frame
-- already covers it.
do
    local pal_keys = {}
    for i = 1, #paladin_slots do pal_keys[paladin_slots[i].key] = true end
    check(pal_keys.twist ~= true, "the HUD ships no twist slot (guide-only, deferred)")
    check(pal_keys.soc == true, "the HUD mirrors soc")
    check(pal_keys.sob == true, "the HUD mirrors sob")
    check(pal_keys.how == true, "the HUD mirrors how")
    check(pal_keys.holy_shock == true, "the HUD mirrors holy_shock")
    check(pal_keys.aura_mastery == true, "the HUD mirrors aura_mastery")
    check(pal_keys.hor == true, "the HUD mirrors the utility band's hor")
    check(pal_keys.how_wrath == true, "the HUD mirrors the utility band's how_wrath")
end

--=========================================================================================
-- 2) Pre-init and combat-lockdown safety
--=========================================================================================
local ok1, err1 = pcall(HUD.on_update, ST, 0.2)
check(ok1, "on_update before creation does not error (" .. tostring(err1) .. ")")
eq(HUD.frame, nil, "nothing is created before init")
local frames_before = created_frames
lockdown = true
local ok2, err2 = pcall(HUD.init, ST)
check(ok2, "init under combat lockdown does not error (" .. tostring(err2) .. ")")
eq(created_frames, frames_before, "no frames are created under lockdown")
eq(HUD.frame, nil, "the HUD stays uncreated under lockdown")
eq(HUD.pending_create, true, "the creation is deferred, not lost")
lockdown = false
HUD.on_bar_update(ST, "mainhand")
check(HUD.frame ~= nil, "the class hook retries the deferred creation")
eq(HUD.pending_create, false, "the deferral latch clears once created")
eq(#HUD.icons, 14, "all fourteen valid slots build an icon")
eq(created_frames, frames_before + 59,
    "exactly the HUD frame, the icon children, the event frame and the driver are created")

--=========================================================================================
-- 3) Construction, layout and the option-driven re-flow
--=========================================================================================
local icon_cs = HUD.icons[1]
eq(icon_cs.slot.key, "cs", "the icons follow the descriptor order")
eq(icon_cs.texture.texture, "icon_cs", "the icon shows the spell's texture")
eq(icon_cs.show_key, "hud_show_cs", "the per-slot toggle key is derived once")
check(HUD.frame.shown, "an enabled HUD shows")
-- the two empty trinkets + how/HS/AM (unknown on TBC) hide, so seven icons form the row
eq(HUD.frame.width, 7 * 36 + 6 * 2, "the row is sized to the shown icons plus spacing")
eq(HUD.frame.height, 36, "the row is one icon tall")
check(icon_cs.shown, "an enabled slot is shown")
eq(icon_cs.point[1], "LEFT", "the first icon anchors to the row's left edge")
near(icon_cs.point[4], 0, 1e-9, "the first icon sits at offset 0")
eq(HUD.icons[2].point[4], 38, "the second icon sits one icon + spacing over")

class_db.hud_show_cs = false
eq(HUD.layout_changed(ST), true, "a slot toggle registers as a layout change")
HUD.on_bar_update(ST, "mainhand")
eq(icon_cs.wanted, false, "the disabled slot is no longer wanted")
check(not icon_cs.shown, "the disabled slot hides")
near(HUD.icons[2].point[4], 0, 1e-9, "the row re-flows without the hidden slot")
class_db.hud_show_cs = true
HUD.apply_settings(ST)

class_db.hud_icon_size = 40
eq(HUD.layout_changed(ST), true, "an icon-size change registers as a layout change")
HUD.apply_settings(ST)
eq(HUD.frame.width, 7 * 40 + 6 * 2, "the new icon size re-flows the row")
class_db.hud_icon_size = 36
HUD.apply_settings(ST)

-- trinket occupancy drives its own re-flow (the archive's layout_key rule)
eq(HUD.icon_should_show(ST, HUD.icons[5], false), false, "an empty trinket slot hides")
item_ids[13] = 28830
item_textures[13] = "tex_dst"
HUD.read_trinkets()
eq(HUD.layout_changed(ST), true, "a filled trinket slot registers as a layout change")
HUD.apply_settings(ST)
eq(HUD.icon_should_show(ST, HUD.icons[5], false), true, "a filled trinket slot shows")
check(HUD.icons[5].shown, "the filled trinket icon is shown")
eq(HUD.icon_should_show(ST, HUD.icons[5], true), true, "design mode shows the slot regardless")

--=========================================================================================
-- 4) paint: swipe set-once, text rules, tints, glow
--=========================================================================================
do
    local icon = HUD.icons[1]
    local cd = icon.cooldown
    clock = 100
    HUD.paint(ST, icon, { remaining = 5, duration = 6, text_remaining = 5, desaturate = true }, clock)
    eq(cd.cooldown_sets, 1, "a cooldown starts its swipe once")
    near(cd.cooldown_start, 99, 1e-9, "the swipe start is derived from remaining/duration")
    eq(cd.cooldown_duration, 6, "the swipe carries the full duration")
    eq(cd.reverse, false, "a plain cooldown is not reversed")
    check(cd.shown, "the swipe is shown")
    eq(icon.text.text, "5", "the countdown text shows the remaining seconds")
    near(icon.text.color[1], 250 / 255, 1e-6, "the normal text colour applies")
    eq(icon.texture.desaturated, true, "the icon desaturates while on cooldown")
    check(icon.texture.color == nil or icon.texture.color[1] == 1,
        "the icon keeps its white tint")

    -- the same cooldown one tick later: no second SetCooldown, same text
    clock = 100.05
    HUD.paint(ST, icon, { remaining = 4.95, duration = 6, text_remaining = 4.95, desaturate = true }, clock)
    eq(cd.cooldown_sets, 1, "the swipe is set once per cooldown, not per tick")
    eq(icon.text.text, "5", "an unchanged displayed value does not rebuild the text")

    -- a restarted cooldown re-sets the swipe
    clock = 106
    HUD.paint(ST, icon, { remaining = 6, duration = 6, text_remaining = 6, desaturate = true }, clock)
    eq(cd.cooldown_sets, 2, "a restarted cooldown re-sets the swipe")
    eq(icon.text.text, "6", "the restarted cooldown shows its full time")

    -- warning window: one decimal and the warn colour
    clock = 108
    HUD.paint(ST, icon, { remaining = 2.6, duration = 6, text_remaining = 2.6, desaturate = true }, clock)
    eq(icon.text.text, "2.6", "under 3 s the text keeps one decimal")
    near(icon.text.color[2], 102 / 255, 1e-6, "under 3 s the warn colour applies")

    -- a GCD-length swipe never carries text
    clock = 110
    HUD.paint(ST, icon, { remaining = 1.2, duration = 1.5, text_remaining = 1.2 }, clock)
    eq(cd.cooldown_duration, 1.5, "the GCD replaces the swipe")
    eq(icon.text.hidden, true, "a GCD-length swipe hides the text")

    -- show_text off hides the text of a real cooldown too
    class_db.hud_show_text = false
    HUD.paint(ST, icon, { remaining = 4, duration = 6, text_remaining = 4, desaturate = true }, clock)
    eq(icon.text.hidden, true, "show_text off: the text hides")
    class_db.hud_show_text = true

    -- expired cooldown clears the swipe
    clock = 111
    HUD.paint(ST, icon, {}, clock)
    eq(cd.cooldown_duration, 0, "an idle state clears the cooldown")
    eq(icon.text.hidden, true, "an idle state hides the text")
    eq(icon.texture.desaturated, false, "an idle state clears the desaturation")

    -- mana / range tints (mana wins)
    HUD.paint(ST, icon, { usable = false }, clock)
    eq(icon.texture.color[1], 0.5, "no mana tints the icon blue")
    HUD.paint(ST, icon, { in_range = false }, clock)
    eq(icon.texture.color[1], 1, "out of range tints the icon red")
    eq(icon.texture.color[2], 0.25, "the red tint uses the archive's component")
    HUD.paint(ST, icon, { usable = false, in_range = false }, clock)
    eq(icon.texture.color[3], 1, "with both cues up the no-mana tint wins")
    class_db.hud_mana_tint = false
    HUD.paint(ST, icon, { usable = false }, clock)
    eq(icon.texture.color[1], 1, "mana tint off: no blue tint")
    class_db.hud_mana_tint = true
    class_db.hud_range_tint = false
    HUD.paint(ST, icon, { in_range = false }, clock)
    eq(icon.texture.color[1], 1, "range tint off: no red tint")
    class_db.hud_range_tint = true
    HUD.paint(ST, icon, {}, clock)

    -- desaturate option gate
    class_db.hud_desaturate = false
    HUD.paint(ST, icon, { desaturate = true }, clock)
    eq(icon.texture.desaturated, false, "desaturate off: a grey state is not painted")
    class_db.hud_desaturate = true

    -- glow gate
    lcg_starts, lcg_stops = 0, 0
    HUD.paint(ST, icon, { glow = true }, clock)
    eq(lcg_starts, 1, "a glow state starts the proc glow")
    HUD.paint(ST, icon, { glow = true }, clock)
    eq(lcg_starts, 1, "the glow is not restarted every tick")
    HUD.paint(ST, icon, {}, clock)
    eq(lcg_stops, 1, "the glow stops when the state clears")
    class_db.hud_glow_enabled = false
    HUD.paint(ST, icon, { glow = true }, clock)
    eq(lcg_starts, 1, "glow option off: no glow starts")
    class_db.hud_glow_enabled = true

    -- hidden states are skipped by paint
    HUD.paint(ST, icon, { remaining = 5, duration = 6, text_remaining = 5 }, clock)
    local text_before = icon.text.text
    HUD.paint(ST, icon, { hidden = true }, clock)
    eq(icon.text.text, text_before, "a hidden state paints nothing")
    eq(cd.cooldown_duration, 6, "a hidden state leaves the swipe alone")

    -- the pure formatter
    eq(HUD.format_time(3.4), "3", "format_time rounds to whole seconds above 3")
    eq(HUD.format_time(2.96), "3.0", "format_time keeps one decimal under 3")
    eq(HUD.format_time(0.04), "0.0", "format_time floors tiny values to 0.0")
end

--=========================================================================================
-- 5) Option gates: off slots read nothing and run no provider
--=========================================================================================
do
    local all_keys = { "hud_show_cs", "hud_show_judgement", "hud_show_consecration",
        "hud_show_exorcism", "hud_show_trinket1", "hud_show_trinket2", "hud_show_wings",
        "hud_show_soc", "hud_show_sob", "hud_show_how", "hud_show_holy_shock",
        "hud_show_aura_mastery", "hud_show_hor", "hud_show_how_wrath" }
    local real_state = ST.PALADIN.get_hud_state
    local provider_calls = 0
    ST.PALADIN.get_hud_state = function(self2, slot2, now2)
        provider_calls = provider_calls + 1
        return real_state(self2, slot2, now2)
    end
    for i = 1, #all_keys do class_db[all_keys[i]] = false end
    HUD.apply_settings(ST)
    cooldown_reads, provider_calls = 0, 0
    HUD.update_display(ST)
    eq(cooldown_reads, 0, "all slots off: no cooldown API reads")
    eq(provider_calls, 0, "all slots off: the provider never runs")
    class_db.hud_show_cs = true
    HUD.apply_settings(ST)
    cooldown_reads, provider_calls = 0, 0
    HUD.update_display(ST)
    eq(provider_calls, 1, "one enabled slot: the provider runs exactly once")
    check(cooldown_reads >= 1, "one enabled slot: its cooldown is read")
    ST.PALADIN.get_hud_state = real_state
    for i = 1, #all_keys do class_db[all_keys[i]] = true end
    HUD.apply_settings(ST)
end

--=========================================================================================
-- 6) Trinket tracker and state machine (fake clock)
--=========================================================================================
do
    local slot13 = slot_by_key.trinket1
    clock = 200
    item_ids[13] = 28830
    item_textures[13] = "tex_dst"
    HUD.read_trinket(13)
    local t13 = HUD.trinkets[13]
    eq(t13.item, 28830, "the tracker reads the equipped item id")
    eq(t13.buff, 34775, "the item's proc buff comes from the local table")
    eq(t13.icd, 20, "the item's internal cooldown comes from the local table")
    eq(t13.texture, "tex_dst", "the tracker latches the item texture")

    -- proc buff up: swipe counts down, no desaturation
    aura_list = { { name = "Lust for Battle", duration = 10, expiration = clock + 8, spell_id = 34775 } }
    local s = HUD.trinket_state(ST, slot13, clock)
    eq(s.duration, 10, "the proc's full duration is carried")
    near(s.remaining, 8, 1e-9, "the proc's remaining time is carried")
    near(s.start, clock + 8 - 10, 1e-9, "the proc swipe start is its application time")
    eq(s.reverse, nil, "a proc swipe counts down")
    eq(s.texture, "tex_dst", "the state carries the item texture")
    eq(s.desaturate, nil, "a proc does not grey the icon")

    -- the proc landing (CLEU) starts the internal cooldown
    HUD.on_aura_applied(ST, "Player-1", 34775, clock)
    near(t13.icd_expires, clock + 20, 1e-9, "the CLEU application starts the ICD")
    aura_list = {}
    s = HUD.trinket_state(ST, slot13, clock)
    eq(s.reverse, true, "the internal cooldown shows as a reversed swipe")
    eq(s.duration, 20, "the ICD swipe carries the ICD length")
    near(s.remaining, 20, 1e-9, "the ICD remaining counts down from the application")
    near(s.start, clock, 1e-9, "the ICD swipe start is the application time")

    -- foreign guid and unrelated spells are ignored
    local icd_before = t13.icd_expires
    HUD.on_aura_applied(ST, "Other-1", 34775, clock + 5)
    near(t13.icd_expires, icd_before, 1e-9, "a foreign destination guid is ignored")
    HUD.on_aura_applied(ST, "Player-1", 99999, clock + 5)
    near(t13.icd_expires, icd_before, 1e-9, "an unrelated spell id is ignored")

    -- on-use cooldown wins over the proc and the ICD
    item_cooldowns[13] = { start = clock - 5, duration = 120, enable = 1 }
    s = HUD.trinket_state(ST, slot13, clock)
    near(s.remaining, 115, 1e-9, "the on-use cooldown is what the icon counts")
    eq(s.duration, 120, "the on-use swipe carries the item's duration")
    eq(s.start, clock - 5, "the on-use swipe keeps the server's start")
    eq(s.desaturate, true, "an on-use cooldown greys the icon")

    -- a GCD-length cooldown is not an on-use cooldown
    item_cooldowns[13] = { start = clock, duration = 1.5, enable = 1 }
    s = HUD.trinket_state(ST, slot13, clock)
    near(s.remaining, 20, 1e-9, "a 1.5 s (GCD-length) cooldown is ignored")
    eq(s.reverse, true, "the ICD still shows behind it")

    -- a disabled cooldown is ignored too
    item_cooldowns[13] = { start = clock - 5, duration = 120, enable = 0 }
    s = HUD.trinket_state(ST, slot13, clock)
    eq(s.duration, 20, "an unenabled cooldown is ignored")
    item_cooldowns[13] = nil

    -- a Mainline SpellCooldownInfo-shaped reading (a table, not the classic
    -- multi-return) is unfolded by compat's wrapper and drives the same paths
    item_cooldowns[13] = { start = clock - 5, duration = 120, enable = 1, table_shape = true }
    local ws, wd, we = st.api.GetInventoryItemCooldown(13)
    near(ws, clock - 5, 1e-9, "a table-shaped item cooldown unwraps its start")
    eq(wd, 120, "a table-shaped item cooldown unwraps its duration")
    eq(we, 1, "a table-shaped item cooldown normalises its enabled flag")
    s = HUD.trinket_state(ST, slot13, clock)
    near(s.remaining, 115, 1e-9, "the unfolded cooldown drives the trinket state machine")
    item_cooldowns[13] = nil

    -- the ICD expires and clears its stamp
    clock = clock + 25
    s = HUD.trinket_state(ST, slot13, clock)
    eq(s.duration, nil, "an expired ICD clears the swipe")
    eq(t13.icd_expires, nil, "the expired ICD stamp is dropped")

    -- an item swap resets the tracker
    item_ids[13] = 29383
    item_textures[13] = "tex_brooch"
    HUD.read_trinket(13)
    eq(t13.item, 29383, "the swap is picked up")
    eq(t13.buff, 35166, "the new item's buff replaces the old one")
    eq(t13.icd, nil, "the new item has no ICD entry")
    eq(t13.icd_expires, nil, "the swap drops the old ICD stamp")
    HUD.on_aura_applied(ST, "Player-1", 35166, clock)
    eq(t13.icd_expires, nil, "no ICD entry: the CLEU application changes nothing")

    -- the CLEU event route unpacks the payload like the archive
    item_ids[13] = 28830
    HUD.read_trinket(13)
    cleu_impl = function()
        return 1, "SPELL_AURA_APPLIED", false, "Player-1", "Player", 0, 0,
            "Player-1", "Player", 0, 0, 34775, "Lust for Battle", 1, "BUFF"
    end
    HUD.on_combat_log_event(ST)
    near(t13.icd_expires, clock + 20, 1e-9, "the CLEU route starts the ICD")
    cleu_impl = nil

    -- an empty slot hides again
    item_ids[13] = nil
    HUD.read_trinket(13)
    eq(HUD.icon_should_show(ST, HUD.icons[5], false), false, "an emptied slot hides again")
    item_ids[13] = 28830
    item_textures[13] = "tex_dst"
    HUD.read_trinket(13)
    HUD.apply_settings(ST)
end

--=========================================================================================
-- 7) Paladin provider: live readers
--=========================================================================================
do
    clock = 300
    ST.gcd = {}
    ST.in_combat = false
    ST.twist_active_seals_count = 0

    cooldowns["Crusader Strike"] = { start = clock - 3, duration = 6 }
    local s = ST.PALADIN.get_hud_state(ST, slot_by_key.cs, clock)
    near(s.remaining, 3, 1e-9, "CS remaining comes from the client cooldown")
    eq(s.duration, 6, "CS carries its full cooldown")
    eq(s.desaturate, true, "an on-cooldown CS greys out")
    near(s.text_remaining, 3, 1e-9, "the cooldown text is the remaining time")

    -- the GCD echo: the real cooldown is remembered (the guide's latch) and the
    -- shorter echo only caps what is still shown
    cooldowns["Crusader Strike"] = { start = clock, duration = 1.3 }
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.cs, clock)
    near(s.remaining, 1.3, 1e-9, "a GCD echo caps the latched CS cooldown")

    -- unknown CS (no talent): nothing to count, and the GCD swipe takes over
    cooldowns["Crusader Strike"] = nil
    known_spells["Crusader Strike"] = false
    ST.gcd = { expires = clock + 1.2, spell_length = 1.5 }
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.cs, clock)
    near(s.remaining, 1.2, 1e-9, "an unknown CS falls through to the GCD swipe")
    eq(s.duration, 1.5, "the GCD swipe carries the GCD length")
    known_spells["Crusader Strike"] = true

    -- Judgement and Avenging Wrath never take the GCD swipe
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.judgement, clock)
    eq(s.remaining, nil, "Judgement never borrows the GCD")
    ST.in_combat = true
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.wings, clock)
    eq(s.remaining, nil, "Wings never borrow the GCD")
    eq(s.glow, true, "ready Wings glow in combat")
    ST.in_combat = false
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.wings, clock)
    eq(s.glow, false, "out of combat Wings do not glow")

    -- Consecration takes the GCD swipe, and its live cooldown is name-based
    ST.gcd = { expires = clock + 1.0, spell_length = 1.5 }
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.consecration, clock)
    near(s.remaining, 1.0, 1e-9, "Consecration takes the GCD swipe")
    cooldowns["Consecration"] = { start = clock - 2, duration = 8 }
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.consecration, clock)
    near(s.remaining, 6, 1e-9, "Consecration's real cooldown is read by name")
    eq(s.duration, 8, "Consecration carries its full cooldown")

    -- Wings' real cooldown ignores the GCD echo entirely
    cooldowns["Avenging Wrath"] = { start = clock, duration = 1.3 }
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.wings, clock)
    eq(s.remaining, nil, "a GCD echo on Wings is ignored")
    cooldowns["Avenging Wrath"] = { start = clock - 10, duration = 180 }
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.wings, clock)
    near(s.remaining, 170, 1e-9, "Wings' real cooldown is counted")
    eq(s.duration, 180, "Wings carries its real duration")

    -- Judgement greys without a seal
    cooldowns[20271] = nil
    ST.twist_active_seals_count = 0
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.judgement, clock)
    eq(s.desaturate, true, "Judgement greys without a seal")
    ST.twist_active_seals_count = 2
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.judgement, clock)
    eq(s.desaturate, nil, "Judgement with a seal is not greyed")

    -- Exorcism: grey unless Undead/Demon, glows then in combat and off cooldown
    target_exists = false
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.exorcism, clock)
    eq(s.desaturate, true, "Exorcism greys without a target")
    eq(s.glow, false, "no target: no glow")
    target_exists = true
    target_creature_type = "Humanoid"
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.exorcism, clock)
    eq(s.desaturate, true, "a Humanoid target does not enable Exorcism")
    target_creature_type = "Undead"
    ST.in_combat = true
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.exorcism, clock)
    eq(s.desaturate, nil, "an Undead target enables Exorcism")
    eq(s.glow, true, "an Undead target in combat makes Exorcism glow")
    cooldowns["Exorcism"] = { start = clock - 5, duration = 15 }
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.exorcism, clock)
    eq(s.glow, false, "on cooldown Exorcism does not glow")
    near(s.remaining, 10, 1e-9, "Exorcism's real cooldown is read by name")
    cooldowns["Exorcism"] = nil
    ST.in_combat = false

    -- Mirror slots (P-1): soc/sob aura swipe, how/HS/AM hidden on TBC (no signal).
    ST.gcd = {}
    ST.has_soc = true
    ST.soc_expires = clock + 20
    ST.soc_duration = 30
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.soc, clock)
    near(s.remaining, 20, 1e-9, "soc active shows the aura remaining")
    eq(s.duration, 30, "soc carries the tracked aura length")
    eq(s.hidden, nil, "soc with a live seal is not hidden")
    ST.has_soc = false
    ST.soc_expires = nil
    ST.soc_duration = nil
    ST.gcd = { expires = clock + 1.0, spell_length = 1.5 }
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.soc, clock)
    near(s.remaining, 1.0, 1e-9, "soc down borrows the GCD swipe (ready to cast)")
    eq(s.hidden, nil, "soc down is not hidden")
    ST.gcd = {}
    ST.has_sob = true
    ST.sob_expires = clock + 15
    ST.sob_duration = 30
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.sob, clock)
    near(s.remaining, 15, 1e-9, "sob active shows the aura remaining (TBC Blood)")
    eq(s.hidden, nil, "sob with a live seal is not hidden")
    ST.has_sob = false
    ST.sob_expires = nil
    ST.sob_duration = nil
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.how, clock)
    eq(s.hidden, true, "how hides on TBC (no execute signal)")
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.holy_shock, clock)
    eq(s.hidden, true, "holy_shock hides on TBC (SoD-only)")
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.aura_mastery, clock)
    eq(s.hidden, true, "aura_mastery hides on TBC (SoD-only)")

    -- The WotLK APL's UTILITY BAND (bench/paladin_apl_utility_build_2026-10-20.md
    -- §2): the two band mirrors hide on TBC. The toggle is ON here AND the book
    -- knows both spells (the TBC family queries by NAME - the class's name-vs-id
    -- rule), so the family gate is the only thing that can hide them - and a
    -- hidden slot performs no read at all.
    class_db.hud_show_hor = true
    class_db.hud_show_how_wrath = true
    known_spells["Hand of Reckoning"] = true
    known_spells["Hammer of Wrath"] = true
    local reads_before = cooldown_reads
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.hor, clock)
    eq(s.hidden, true, "hor hides on TBC even with the toggle on (the band is Wrath-only)")
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.how_wrath, clock)
    eq(s.hidden, true, "how_wrath hides on TBC even with the toggle on (the band is Wrath-only)")
    eq(cooldown_reads, reads_before, "a hidden band slot performs no cooldown read")
    class_db.hud_show_hor = nil
    class_db.hud_show_how_wrath = nil
    known_spells["Hand of Reckoning"] = nil
    known_spells["Hammer of Wrath"] = nil
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.hor, clock)
    eq(s.hidden, true, "hor hides on TBC with the toggle unset (nil = off)")
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.how_wrath, clock)
    eq(s.hidden, true, "how_wrath hides on TBC with the toggle unset (nil = off)")

    -- no-mana probe: gated by the option, degrades when absent
    ST.gcd = {}
    class_db.hud_mana_tint = false
    usable_reads = 0
    ST.PALADIN.get_hud_state(ST, slot_by_key.cs, clock)
    eq(usable_reads, 0, "mana tint off: no IsSpellUsable read")
    class_db.hud_mana_tint = true
    usable_reads = 0
    usable_impl = function() return false, true end
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.cs, clock)
    eq(usable_reads, 1, "mana tint on: the probe is read once")
    eq(s.usable, false, "an insufficient-resource reading is reported")
    usable_impl = nil
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.cs, clock)
    eq(s.usable, nil, "a usable reading reports nothing")

    -- range probe: gated by the option and by a target
    target_exists = false
    range_reads = 0
    ST.PALADIN.get_hud_state(ST, slot_by_key.cs, clock)
    eq(range_reads, 0, "no target: no range read")
    target_exists = true
    range_impl = function() return 0 end
    class_db.hud_range_tint = false
    range_reads = 0
    ST.PALADIN.get_hud_state(ST, slot_by_key.cs, clock)
    eq(range_reads, 0, "range tint off: no range read")
    class_db.hud_range_tint = true
    range_reads = 0
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.cs, clock)
    eq(range_reads, 1, "range tint on: the probe is read once")
    eq(s.in_range, false, "an out-of-range reading is reported")
    range_impl = nil
    target_exists = false
end

--=========================================================================================
-- 7b) Paladin mirror slots on Era: how/HS/AM lit, sob shows Righteousness
--=========================================================================================
do
    local e = build({ project = 2 })
    local est, EST = e.st, e.ST
    eq(est.family, "ERA", "mirror Era: the sandbox runs the ERA family")
    local eslots = EST.PALADIN.HUD_SLOTS
    local eby_key = {}
    for i = 1, #eslots do eby_key[eslots[i].key] = eslots[i] end
    eq(#eslots, 14, "mirror Era: fourteen slots ship on Era too")
    clock = 900
    EST.gcd = {}
    EST.in_combat = false
    EST.has_soc = true
    EST.soc_expires = clock + 20
    EST.soc_duration = 30
    local s = EST.PALADIN.get_hud_state(EST, eby_key.soc, clock)
    near(s.remaining, 20, 1e-9, "mirror Era: soc active shows the aura")
    EST.has_sor = true
    EST.sor_expires = clock + 12
    EST.sor_duration = 30
    s = EST.PALADIN.get_hud_state(EST, eby_key.sob, clock)
    near(s.remaining, 12, 1e-9, "mirror Era: sob shows Righteousness (twist seal)")
    EST.has_sor = false
    EST.sor_expires = nil
    EST.has_soc = false
    EST.soc_expires = nil
    -- how lit: known HoW on cooldown, then ready + glow in combat.
    known_spells[24275] = true
    cooldowns[24275] = { start = clock - 2, duration = 6 }
    s = EST.PALADIN.get_hud_state(EST, eby_key.how, clock)
    near(s.remaining, 4, 1e-9, "mirror Era: how remaining comes from the client cooldown")
    eq(s.desaturate, true, "mirror Era: on-cooldown how greys out")
    eq(s.glow, false, "mirror Era: on-cooldown how does not glow")
    cooldowns[24275] = nil
    EST.gcd = {}
    EST.in_combat = true
    s = EST.PALADIN.get_hud_state(EST, eby_key.how, clock)
    eq(s.remaining, nil, "mirror Era: ready how with no GCD shows no swipe")
    eq(s.glow, true, "mirror Era: ready how glows in combat")
    EST.in_combat = false
    s = EST.PALADIN.get_hud_state(EST, eby_key.how, clock)
    eq(s.glow, false, "mirror Era: out of combat how does not glow")
    -- HS lit: known max rank on cooldown, then ready + glow.
    known_spells[24275] = nil
    known_spells[20930] = true
    cooldowns[20930] = { start = clock - 5, duration = 30 }
    s = EST.PALADIN.get_hud_state(EST, eby_key.holy_shock, clock)
    near(s.remaining, 25, 1e-9, "mirror Era: HS remaining comes from the client cooldown")
    eq(s.desaturate, true, "mirror Era: on-cooldown HS greys out")
    cooldowns[20930] = nil
    EST.in_combat = true
    s = EST.PALADIN.get_hud_state(EST, eby_key.holy_shock, clock)
    eq(s.glow, true, "mirror Era: ready HS glows in combat")
    EST.in_combat = false
    -- AM lit: known rune on cooldown, then ready + glow; unknown hides.
    known_spells[20930] = nil
    known_spells[407624] = true
    cooldowns[407624] = { start = clock - 10, duration = 120 }
    s = EST.PALADIN.get_hud_state(EST, eby_key.aura_mastery, clock)
    near(s.remaining, 110, 1e-9, "mirror Era: AM remaining comes from the client cooldown")
    cooldowns[407624] = nil
    EST.in_combat = true
    s = EST.PALADIN.get_hud_state(EST, eby_key.aura_mastery, clock)
    eq(s.glow, true, "mirror Era: ready AM glows in combat")
    EST.in_combat = false
    known_spells[407624] = nil
    s = EST.PALADIN.get_hud_state(EST, eby_key.aura_mastery, clock)
    eq(s.hidden, true, "mirror Era: unknown AM hides (no signal)")
    cooldowns[24275] = nil
    cooldowns[20930] = nil
    cooldowns[407624] = nil
    known_spells[24275] = nil
    known_spells[20930] = nil
end

--=========================================================================================
-- 7c) Paladin utility-band mirrors on Wrath: hor (67485) + how_wrath (48806)
--=========================================================================================
-- The WotLK APL's UTILITY BAND (bench/paladin_apl_utility_build_2026-10-20.md §2):
-- Hand of Reckoning (the APL's i=1) and the WotLK Hammer of Wrath (i=2). The HUD
-- mirrors are display-only, the druid Claw shape (classes/druid.lua:2685): the
-- slot hides unless hud_show_<key> reads exactly true (nil = off), so a fresh
-- profile's row is unchanged.
do
    local w = build({ project = 11 })
    local W = w.ST
    local wslots = W.PALADIN.HUD_SLOTS
    local wby_key = {}
    for i = 1, #wslots do wby_key[wslots[i].key] = wslots[i] end
    eq(w.st.family, "WRATH", "mirror Wrath: the sandbox runs the WRATH family")
    eq(#wslots, 14, "mirror Wrath: fourteen slots ship on Wrath too")
    eq(wby_key.hor.spell, 67485, "mirror Wrath: hor carries the APL's Hand of Reckoning id")
    eq(wby_key.how_wrath.spell, 48806,
        "mirror Wrath: how_wrath carries the APL's WotLK Hammer of Wrath id")
    clock = 1000
    W.gcd = {}
    W.in_combat = false
    -- The book's answer is set FIRST, so each gate below is the ONLY thing that
    -- can hide the slot: the option gate, then the spell-book gate.
    known_spells[67485] = true
    known_spells[48806] = true

    -- The option gate: the toggle is unset on a fresh profile, so the slot hides
    -- and the row never grows.
    local s = W.PALADIN.get_hud_state(W, wby_key.hor, clock)
    eq(s.hidden, true, "mirror Wrath: hor hides while hud_show_hor is unset (nil = off)")
    s = W.PALADIN.get_hud_state(W, wby_key.how_wrath, clock)
    eq(s.hidden, true, "mirror Wrath: how_wrath hides while hud_show_how_wrath is unset")
    class_db.hud_show_hor = false
    s = W.PALADIN.get_hud_state(W, wby_key.hor, clock)
    eq(s.hidden, true, "mirror Wrath: hor hides while hud_show_hor reads false")
    class_db.hud_show_hor = nil

    -- The spell-book gate: a build without the talent answers "not known" and
    -- the slot hides (unknown-hides, never a wrong icon). The gate reads the
    -- STATE (compat.lua's api.is_spell_known_state), not the binary, so it
    -- tells the two hiding answers apart: "not_known" (the player has no such
    -- spell) and "unknown" (this client could not answer the question).
    class_db.hud_show_hor = true
    class_db.hud_show_how_wrath = true
    known_spells[67485] = nil
    known_spells[48806] = nil
    s = W.PALADIN.get_hud_state(W, wby_key.hor, clock)
    eq(s.hidden, true, "mirror Wrath: an unknown Hand of Reckoning hides (no signal)")
    eq(W.PALADIN.hud_band_spell_state.hor, "not_known",
        "mirror Wrath: the gate reads the state (the build has no talent)")
    s = W.PALADIN.get_hud_state(W, wby_key.how_wrath, clock)
    eq(s.hidden, true, "mirror Wrath: an unknown WotLK Hammer of Wrath hides (no signal)")
    eq(W.PALADIN.hud_band_spell_state.how_wrath, "not_known",
        "mirror Wrath: the gate reads the state for the WotLK Hammer of Wrath")
    -- The client cannot answer: the probe declines (nil), so the state is
    -- "unknown". The slot still hides (unknown-hides - it never shows a spell
    -- the player cannot cast) and the next tick asks again.
    known_declines = true
    s = W.PALADIN.get_hud_state(W, wby_key.hor, clock)
    eq(s.hidden, true, "mirror Wrath: an unanswerable book hides the slot (unknown-hides)")
    eq(W.PALADIN.hud_band_spell_state.hor, "unknown",
        "mirror Wrath: the gate tells 'the client cannot answer' from 'not known'")
    known_declines = false
    known_spells[67485] = true
    known_spells[48806] = true

    -- Known + enabled: the cooldown reads BY NAME (rank-agnostic) and the client's
    -- own duration drives the swipe.
    cooldowns["Hand of Reckoning"] = { start = clock - 4, duration = 8 }
    s = W.PALADIN.get_hud_state(W, wby_key.hor, clock)
    eq(s.hidden, nil, "mirror Wrath: a known, enabled hor is not hidden")
    eq(W.PALADIN.hud_band_spell_state.hor, "known",
        "mirror Wrath: the gate records the known answer")
    near(s.remaining, 4, 1e-9, "mirror Wrath: hor's cooldown reads by name")
    eq(s.duration, 8, "mirror Wrath: hor carries the client's own cooldown length")
    eq(s.desaturate, true, "mirror Wrath: an on-cooldown hor greys out")
    cooldowns["Hand of Reckoning"] = nil
    W.gcd = { expires = clock + 1.0, spell_length = 1.5 }
    s = W.PALADIN.get_hud_state(W, wby_key.hor, clock)
    near(s.remaining, 1.0, 1e-9, "mirror Wrath: a ready hor borrows the GCD swipe")
    W.gcd = {}

    -- The WotLK Hammer of Wrath is an execute-phase cast (the sim's own gate:
    -- IsExecutePhase20), so the mirror greys above 20 % target health. The spell
    -- is READY here: the on-cooldown grey must not mask the execute gate.
    cooldowns["Hammer of Wrath"] = { start = clock - 1, duration = 6 }
    s = W.PALADIN.get_hud_state(W, wby_key.how_wrath, clock)
    eq(s.hidden, nil, "mirror Wrath: a known, enabled how_wrath is not hidden")
    near(s.remaining, 5, 1e-9, "mirror Wrath: how_wrath's cooldown reads by name")
    eq(s.duration, 6, "mirror Wrath: how_wrath carries the client's own cooldown length")
    cooldowns["Hammer of Wrath"] = nil
    target_exists = true
    target_health, target_health_max = 50, 100
    s = W.PALADIN.get_hud_state(W, wby_key.how_wrath, clock)
    eq(s.desaturate, true, "mirror Wrath: how_wrath greys above the 20 % execute gate")
    target_health, target_health_max = 10, 100
    s = W.PALADIN.get_hud_state(W, wby_key.how_wrath, clock)
    eq(s.desaturate, nil, "mirror Wrath: below 20 % target health how_wrath is not greyed")
    -- An unknown health claims nothing (the slot keeps its own state).
    target_health, target_health_max = nil, nil
    s = W.PALADIN.get_hud_state(W, wby_key.how_wrath, clock)
    eq(s.desaturate, nil, "mirror Wrath: an unknown target health claims nothing")
    target_exists = false
    target_health, target_health_max = nil, nil
    cooldowns["Hammer of Wrath"] = nil
    known_spells[67485] = nil
    known_spells[48806] = nil
    class_db.hud_show_hor = nil
    class_db.hud_show_how_wrath = nil
end

--=========================================================================================
-- 8) Paladin provider: practice-mode branches (archive parity)
--=========================================================================================
do
    clock = 400
    ST.gcd = {}
    ST.in_combat = false
    local sim = {
        cs_cooldown_expires = clock + 2,
        judge_cooldown_expires = clock + 5,
        consec_cooldown_expires = 0,
        aw_cooldown_expires = clock + 100,
    }
    st.practice_ui = {
        is_active = function() return true end,
        sim = sim,
    }
    local s = ST.PALADIN.get_hud_state(ST, slot_by_key.cs, clock)
    near(s.remaining, 2, 1e-9, "practice CS comes from the simulated cooldown")
    eq(s.duration, 6, "practice CS keeps the full length")
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.judgement, clock)
    near(s.remaining, 5, 1e-9, "practice Judgement comes from the simulated cooldown")
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.consecration, clock)
    eq(s.remaining, nil, "an expired practice Consecration reads as ready")
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.exorcism, clock)
    eq(s.remaining, nil, "practice Exorcism reads as ready (archive parity)")
    eq(s.desaturate, nil, "practice counts as a valid Exorcism target")
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.wings, clock)
    eq(s.remaining, nil, "practice leaves Wings ready (archive parity)")
    st.practice_ui = nil
    HUD.on_update(ST, 0.06)
end

--=========================================================================================
-- 9) Position drag maths and the scale
--=========================================================================================
do
    class_db.hud_scale = 2
    class_db.hud_x, class_db.hud_y = 0, -236
    HUD.apply_settings(ST)
    eq(HUD.frame.scale, 2, "the row scale is applied")
    near(HUD.frame.point[4], 0, 1e-9, "the scaled anchor divides the stored x")
    near(HUD.frame.point[5], -118, 1e-9, "the scaled anchor divides the stored y")
    HUD.save_position(ST)
    eq(class_db.hud_x, 100, "a drag saves the scaled centre back into hud_x")
    eq(class_db.hud_y, 120, "a drag saves the scaled centre back into hud_y")
    near(HUD.frame.point[4], 50, 1e-9, "the re-anchor round-trips through the scale")
    class_db.hud_scale = 1
    class_db.hud_x, class_db.hud_y = 0, -236
    HUD.apply_settings(ST)

    -- visibility keys
    class_db.hud_locked = true
    class_db.hud_visibility_key = "in_combat"
    ST.in_combat = false
    eq(HUD.should_show(ST), false, "in-combat visibility hides out of combat")
    ST.in_combat = true
    eq(HUD.should_show(ST), true, "in-combat visibility shows in combat")
    class_db.hud_visibility_key = "in_combat_or_target"
    ST.in_combat = false
    target_exists = false
    eq(HUD.should_show(ST), false, "in-combat-or-target hides without either")
    target_exists = true
    eq(HUD.should_show(ST), true, "an attackable target shows the HUD")
    target_exists = false
    class_db.hud_visibility_key = "always"
    class_db.hud_locked = false
    class_db.hud_enabled = false
    eq(HUD.should_show(ST), false, "a disabled HUD is hidden even unlocked")
    class_db.hud_enabled = true
    eq(HUD.should_show(ST), true, "an unlocked HUD stays visible for positioning")
    class_db.class_enabled = false
    eq(HUD.should_show(ST), false, "a disabled class hides the HUD")
    class_db.class_enabled = true
    class_db.hud_locked = true

    -- design mode renders the archive's sample states
    local preview = HUD.preview_state(ST, slot_by_key.cs, 2)
    near(preview.remaining, 4, 1e-9, "the design sample starts CS on a 6 s cooldown")
    eq(preview.desaturate, true, "the design sample greys CS")
    preview = HUD.preview_state(ST, slot_by_key.trinket2, 2)
    eq(preview.desaturate, true, "the design sample shows the second trinket on use")
    preview = HUD.preview_state(ST, { key = "unrelated" }, 2)
    eq(preview, nil, "an unknown slot has no sample state")
end

--=========================================================================================
-- 10) A class without descriptors / without a provider is a silent no-op
--=========================================================================================
do
    local quiet = build()
    quiet.ST.PALADIN.HUD_SLOTS = nil
    quiet.st.hud.init(quiet.ST)
    eq(quiet.st.hud.frame, nil, "no descriptors: no frame is created")
    eq(quiet.st.hud.inert, true, "no descriptors: the module goes inert")
    eq(quiet.st.hud.ensure_created(quiet.ST), false, "an inert module never retries creation")

    local noprov = build()
    noprov.ST.PALADIN.get_hud_state = nil
    noprov.st.hud.init(noprov.ST)
    check(noprov.st.hud.frame ~= nil, "trinket-only classes still build")
    eq(#noprov.st.hud.icons, 2, "without a provider only the trinket slots are created")
end

--=========================================================================================
-- 11) Absent-API inertness (no inventory / usable / combat-log globals)
--=========================================================================================
do
    local bare = build({ bare_apis = true })
    bare.st.hud.init(bare.ST)
    check(bare.st.hud.frame ~= nil, "the HUD still builds without the optional APIs")
    local ok = pcall(bare.ST.PALADIN.get_hud_state, bare.ST, bare.ST.PALADIN.HUD_SLOTS[1], 0)
    check(ok, "the provider runs without the optional APIs")
    local s = bare.ST.PALADIN.get_hud_state(bare.ST, bare.ST.PALADIN.HUD_SLOTS[1], 0)
    eq(s.usable, nil, "no usable probe: the mana tint is skipped")
    local tr = bare.st.hud.trinket_state(bare.ST, bare.ST.PALADIN.HUD_SLOTS[5], 0)
    check(tr ~= nil and tr.remaining == nil, "no inventory APIs: the trinket slot reads as idle")
    local ok_cleu =
        pcall(bare.st.hud.on_combat_log_event, bare.ST)
    check(ok_cleu, "no combat-log getter: the CLEU hook is a silent no-op")
    local events = bare.st.hud.event_frame.events
    check(events == nil or events["COMBAT_LOG_EVENT_UNFILTERED"] == nil,
        "an invalid CLEU event is never registered")
    local ok_tick = pcall(bare.st.hud.on_update, bare.ST, 0.06)
    check(ok_tick, "the driver tick runs without the optional APIs")
end

--=========================================================================================
-- 12) Config, options and TOC wiring
--=========================================================================================
do
    local function read(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text
    end

    local presets = read("config_presets.lua")
    local shared = presets:match("ST%.class_defaults%s*=%s*%{(.-)\n}")
    check(shared ~= nil, "the class_defaults block is found in config_presets.lua")
    shared = shared or ""
    local shared_keys = {
        "hud_enabled", "hud_visibility_key", "hud_locked", "hud_x", "hud_y", "hud_scale",
        "hud_icon_size", "hud_match_bar_width", "hud_spacing", "hud_orientation",
        "hud_show_text", "hud_font", "hud_text_size", "hud_text_outline",
        "hud_text_color", "hud_text_warn_color", "hud_border_size", "hud_border_color",
        "hud_glow_enabled", "hud_desaturate", "hud_mana_tint", "hud_range_tint",
    }
    for i = 1, #shared_keys do
        check(shared:find("%f[%a_]" .. shared_keys[i] .. "%s*=") ~= nil,
            shared_keys[i] .. " ships in the shared class defaults")
    end
    check(shared:find("hud_enabled%s*=%s*true") ~= nil, "the HUD ships on by default (owner order)")
    check(shared:find("hud_locked%s*=%s*true") ~= nil, "the HUD ships locked by default")

    local paladin_defaults = presets:match("ST%.PALADIN%.defaults%s*=%s*%{(.-)ST%.PRIEST%.defaults")
    check(paladin_defaults ~= nil, "the PALADIN defaults block is found")
    paladin_defaults = paladin_defaults or ""
    local slot_keys = { "hud_show_cs", "hud_show_judgement", "hud_show_consecration",
        "hud_show_exorcism", "hud_show_trinket1", "hud_show_trinket2", "hud_show_wings",
        "hud_show_soc", "hud_show_sob", "hud_show_how", "hud_show_holy_shock",
        "hud_show_aura_mastery" }
    for i = 1, #slot_keys do
        check(paladin_defaults:find("%f[%a_]" .. slot_keys[i] .. "%s*=%s*true") ~= nil,
            slot_keys[i] .. " ships true in the PALADIN defaults")
    end
    -- The WotLK APL's UTILITY BAND (hor / how_wrath): display-only mirrors, so
    -- they ship FALSE (the druid Claw shape) - hidden until the player turns
    -- them on in the panel, no default-visible change.
    local band_keys = { "hud_show_hor", "hud_show_how_wrath" }
    for i = 1, #band_keys do
        check(paladin_defaults:find("%f[%a_]" .. band_keys[i] .. "%s*=%s*false") ~= nil,
            band_keys[i] .. " ships false in the PALADIN defaults (hidden, no default-visible change)")
        check(paladin_defaults:find("%f[%a_]" .. band_keys[i] .. "%s*=%s*true") == nil,
            band_keys[i] .. " ships no true default")
    end

    local warrior_defaults = presets:match("ST%.WARRIOR%.defaults%s*=%s*%{(.-)ST%.WARRIOR%.HUD_TEMPLATES")
    check(warrior_defaults ~= nil, "the WARRIOR defaults block is found")
    warrior_defaults = warrior_defaults or ""
    local warrior_slot_keys = { "hud_show_op", "hud_show_execute", "hud_show_slam",
        "hud_show_hs", "hud_show_cleave", "hud_show_bt", "hud_show_ww",
        "hud_show_rend", "hud_show_ms", "hud_show_bladestorm", "hud_show_raging_blow",
        "hud_show_hamstring", "hud_show_trinket1", "hud_show_trinket2" }
    for i = 1, #warrior_slot_keys do
        check(warrior_defaults:find("%f[%a_]" .. warrior_slot_keys[i] .. "%s*=%s*true") ~= nil,
            warrior_slot_keys[i] .. " ships true in the WARRIOR defaults")
    end
    -- The Sunder mirror ships OFF (operator ruling): the provider hides it unless
    -- hud_show_sunder reads exactly true, so false and nil both hide - the mirror
    -- ships (one click to enable) and a fresh profile's HUD row is unchanged.
    check(warrior_defaults:find("%f[%a_]hud_show_sunder%s*=%s*false") ~= nil,
        "hud_show_sunder ships false in the WARRIOR defaults (hidden, no default-visible change)")
    check(warrior_defaults:find("%f[%a_]hud_show_sunder%s*=%s*true") == nil,
        "hud_show_sunder ships no true default")

    local druid_defaults = presets:match("ST%.DRUID%.defaults%s*=%s*%{(.-)ST%.HUNTER%.defaults")
    check(druid_defaults ~= nil, "the DRUID defaults block is found")
    druid_defaults = druid_defaults or ""
    local druid_slot_keys = { "hud_show_maul", "hud_show_mangle", "hud_show_rip",
        "hud_show_rake", "hud_show_bite", "hud_show_shred",
        "hud_show_tf", "hud_show_berserk", "hud_show_trinket1", "hud_show_trinket2" }
    for i = 1, #druid_slot_keys do
        check(druid_defaults:find("%f[%a_]" .. druid_slot_keys[i] .. "%s*=%s*true") ~= nil,
            druid_slot_keys[i] .. " ships true in the DRUID defaults")
    end
    check(druid_defaults:find("%f[%a_]hud_show_claw%s*=%s*false") ~= nil,
        "hud_show_claw ships false in the DRUID defaults (display-only, no default-visible change)")

    local hunter_defaults = presets:match("ST%.HUNTER%.defaults%s*=%s*%{(.-)ST%.MAGE%.defaults")
    check(hunter_defaults ~= nil, "the HUNTER defaults block is found")
    hunter_defaults = hunter_defaults or ""
    local hunter_slot_keys = { "hud_show_steady", "hud_show_raptor", "hud_show_kill_command",
        "hud_show_multi", "hud_show_bestial_wrath", "hud_show_rapid_fire",
        "hud_show_aimed", "hud_show_trinket1", "hud_show_trinket2" }
    for i = 1, #hunter_slot_keys do
        check(hunter_defaults:find("%f[%a_]" .. hunter_slot_keys[i] .. "%s*=%s*true") ~= nil,
            hunter_slot_keys[i] .. " ships true in the HUNTER defaults")
    end

    local shaman_defaults = presets:match("ST%.SHAMAN%.defaults%s*=%s*%{(.-)ST%.WARLOCK%.defaults")
    check(shaman_defaults ~= nil, "the SHAMAN defaults block is found")
    shaman_defaults = shaman_defaults or ""
    local shaman_slot_keys = { "hud_show_stormstrike", "hud_show_flameshock", "hud_show_weave",
        "hud_show_firenova", "hud_show_earthshock", "hud_show_twist",
        "hud_show_trinket1", "hud_show_trinket2" }
    for i = 1, #shaman_slot_keys do
        check(shaman_defaults:find("%f[%a_]" .. shaman_slot_keys[i] .. "%s*=%s*true") ~= nil,
            shaman_slot_keys[i] .. " ships true in the SHAMAN defaults")
    end

    local rogue_defaults = presets:match("ST%.ROGUE%.defaults%s*=%s*%{(.-)ST%.SHAMAN%.defaults")
    check(rogue_defaults ~= nil, "the ROGUE defaults block is found")
    rogue_defaults = rogue_defaults or ""
    local rogue_slot_keys = { "hud_show_snd", "hud_show_rupture", "hud_show_ea",
        "hud_show_ar", "hud_show_bf", "hud_show_tea", "hud_show_kick",
        "hud_show_coldblood", "hud_show_trinket1", "hud_show_trinket2" }
    for i = 1, #rogue_slot_keys do
        check(rogue_defaults:find("%f[%a_]" .. rogue_slot_keys[i] .. "%s*=%s*true") ~= nil,
            rogue_slot_keys[i] .. " ships true in the ROGUE defaults")
    end
    local rogue_off_keys = { "hud_show_kidney", "hud_show_restealth", "hud_show_bandage" }
    for i = 1, #rogue_off_keys do
        check(rogue_defaults:find("%f[%a_]" .. rogue_off_keys[i] .. "%s*=%s*false") ~= nil,
            rogue_off_keys[i] .. " ships false in the ROGUE defaults (no default-visible change)")
    end
    -- The practice feedback / panel keys ship in the defaults AND have widgets below:
    -- together the two directions pin the option <-> default parity.
    local practice_keys = { "practice_result_duration", "practice_result_text_size",
        "practice_result_color_hit", "practice_result_color_miss",
        "practice_panel_x", "practice_panel_y" }
    for i = 1, #practice_keys do
        check(paladin_defaults:find("%f[%a_]" .. practice_keys[i] .. "%s*=") ~= nil,
            practice_keys[i] .. " ships in the PALADIN defaults")
    end

    local options = read("option_tables.lua")
    local paladin_opts = options:match("function ST%.class_opts_funcs%.PALADIN%((.*)$")
    check(paladin_opts ~= nil, "the PALADIN options function is found")
    paladin_opts = paladin_opts or ""
    local widget_types = {
        hud_enabled = "toggle", hud_locked = "toggle", hud_visibility_key = "select",
        hud_icon_size = "range", hud_match_bar_width = "toggle", hud_spacing = "range",
        hud_orientation = "select", hud_scale = "range", hud_x = "input", hud_y = "input",
        hud_show_text = "toggle", hud_font = "select", hud_text_size = "range",
        hud_text_outline = "select", hud_text_color = "color", hud_text_warn_color = "color",
        hud_border_size = "range", hud_border_color = "color", hud_glow_enabled = "toggle",
        hud_desaturate = "toggle", hud_mana_tint = "toggle", hud_range_tint = "toggle",
        hud_show_cs = "toggle", hud_show_judgement = "toggle", hud_show_consecration = "toggle",
        hud_show_exorcism = "toggle", hud_show_trinket1 = "toggle", hud_show_trinket2 = "toggle",
        hud_show_wings = "toggle", hud_show_soc = "toggle", hud_show_sob = "toggle",
        hud_show_how = "toggle", hud_show_holy_shock = "toggle", hud_show_aura_mastery = "toggle",
        hud_show_hor = "toggle", hud_show_how_wrath = "toggle",
        practice_result_duration = "range", practice_result_text_size = "range",
        practice_result_color_hit = "color", practice_result_color_miss = "color",
        practice_panel_x = "input", practice_panel_y = "input",
        practice_reset_position = "execute",
    }
    for key, widget_type in pairs(widget_types) do
        local widget = paladin_opts:match("%f[%a_]" .. key .. "%s*=%s*{(.-)\n%s*}")
        check(widget ~= nil and widget:find("type%s*=%s*\"" .. widget_type .. "\"") ~= nil,
            key .. " has a " .. widget_type .. " widget in the PALADIN options")
    end

    local paladin_src = read("classes/paladin.lua")
    check(paladin_src:find("st.hud.init(self)", 1, true) ~= nil,
        "post_init initialises the HUD")
    check(paladin_src:find("st.hud.on_bar_update(self, hand)", 1, true) ~= nil,
        "the per-frame hook syncs the HUD layout")
    -- The WotLK band's spell-book gate reads the STATE accessor (compat.lua's
    -- api.is_spell_known_state), not the binary: the boolean folds "the player
    -- does not know it" and "this client cannot answer" into one false, so the
    -- gate could not tell the two apart.
    check(paladin_src:find("api.is_spell_known_state(spell_query(", 1, true) ~= nil,
        "the paladin band gate reads the spell-knowledge state")
    check(paladin_src:find("is_spell_known_query(slot.spell)", 1, true) == nil,
        "the paladin band gate does not use the binary spell-knowledge probe")
    -- The gate tells the two hiding answers apart: the "unknown" branch (this
    -- client could not answer) and the answer branch ("not known" - the
    -- player has no such spell). Both hide, so only the shape carries the
    -- distinction.
    local band_at = paladin_src:find('if slot.key == "hor" or slot.key == "how_wrath" then', 1, true)
    check(band_at ~= nil, "the paladin band gate block is found")
    if band_at then
        local band_stop = paladin_src:find("\n    end", band_at, true)
        local band_block = band_stop and paladin_src:sub(band_at, band_stop + 6) or ""
        check(band_block:find('known_state == "unknown"', 1, true) ~= nil,
            "the band gate branches on the 'unknown' state (the client cannot answer)")
        check(band_block:find("known ~= true", 1, true) ~= nil,
            "the band gate branches on the answer ('not known' hides too)")
        check(band_block:find("hud_band_spell_state[slot.key] = known_state", 1, true) ~= nil,
            "the band gate records the state it read")
    end

    -- Cross-client reads live in compat (the AGENTS.md contract): neither the HUD nor
    -- the paladin provider may capture the client globals directly again.
    local hud_src = read("hud.lua")
    local client_globals = { "GetInventoryItemID", "GetInventoryItemTexture",
        "GetInventoryItemCooldown", "CombatLogGetCurrentEventInfo" }
    for i = 1, #client_globals do
        check(hud_src:find('rawget(_G, "' .. client_globals[i] .. '")', 1, true) == nil,
            "hud.lua reaches " .. client_globals[i] .. " through compat, not rawget")
    end
    local usability_globals = { "C_Spell", "IsSpellUsable", "IsUsableSpell" }
    for i = 1, #usability_globals do
        check(paladin_src:find('rawget(_G, "' .. usability_globals[i] .. '")', 1, true) == nil,
            "classes/paladin.lua reaches " .. usability_globals[i] .. " through compat, not rawget")
    end

    local tocs = { "SwedgeTimer.toc", "SwedgeTimer_Vanilla.toc", "SwedgeTimer_TBC.toc",
        "SwedgeTimer_Wrath.toc", "SwedgeTimer_Cata.toc", "SwedgeTimer_Mists.toc",
        "SwedgeTimer_Mainline.toc" }
    for i = 1, #tocs do
        local text = read(tocs[i])
        local hud_at = text:find("\nhud%.lua")
        local class_at = text:find("classes\\paladin%.lua")
        check(hud_at ~= nil and class_at ~= nil and hud_at < class_at,
            tocs[i] .. " lists hud.lua before the class modules")
    end
end

--=========================================================================================
-- 13) Hunter provider: slots, creation and live readers
--=========================================================================================
-- The hunter HUD census runs PER FAMILY: every spell slot carries the FAMILY's own
-- id (the client's own rank - bench/hunter_hud_family_2026-10-20.md §2), so a slot
-- never points at a spell the running client does not have. Each family's fixture
-- answers with ITS OWN ranks (HUNTER_SPELLS below), so the rank a slot points at is
-- always one the family's client can resolve.
local HUNTER_SPELLS = {
    TBC = {
        [34120] = { name = "Steady Shot", icon = "icon_steady" },
        [27014] = { name = "Raptor Strike", icon = "icon_raptor" },
        [34026] = { name = "Kill Command", icon = "icon_kc" },
        [27021] = { name = "Multi-Shot", icon = "icon_multi" },
        [19574] = { name = "Bestial Wrath", icon = "icon_bw" },
        [3045] = { name = "Rapid Fire", icon = "icon_rf" },
        [27065] = { name = "Aimed Shot", icon = "icon_aimed" },
    },
    ERA = {
        [2973] = { name = "Raptor Strike", icon = "icon_raptor" },
        [2643] = { name = "Multi-Shot", icon = "icon_multi" },
        [3045] = { name = "Rapid Fire", icon = "icon_rf" },
        [19434] = { name = "Aimed Shot", icon = "icon_aimed" },
        [20904] = { name = "Aimed Shot", icon = "icon_aimed" },
    },
    FOREVER = {
        [14266] = { name = "Raptor Strike", icon = "icon_raptor" },
        [2643] = { name = "Multi-Shot", icon = "icon_multi" },
        [19574] = { name = "Bestial Wrath", icon = "icon_bw" },
        [3045] = { name = "Rapid Fire", icon = "icon_rf" },
        [20904] = { name = "Aimed Shot", icon = "icon_aimed" },
    },
    WRATH = {
        [49052] = { name = "Steady Shot", icon = "icon_steady" },
        [48996] = { name = "Raptor Strike", icon = "icon_raptor" },
        [34026] = { name = "Kill Command", icon = "icon_kc" },
        [49048] = { name = "Multi-Shot", icon = "icon_multi" },
        [19574] = { name = "Bestial Wrath", icon = "icon_bw" },
        [3045] = { name = "Rapid Fire", icon = "icon_rf" },
        [49050] = { name = "Aimed Shot", icon = "icon_aimed" },
    },
    RETAIL = {
        [56641] = { name = "Steady Shot", icon = "icon_steady" },
        [186270] = { name = "Raptor Strike", icon = "icon_raptor" },
        [34026] = { name = "Kill Command", icon = "icon_kc" },
        [2643] = { name = "Multi-Shot", icon = "icon_multi" },
        [19574] = { name = "Bestial Wrath", icon = "icon_bw" },
        [257044] = { name = "Rapid Fire", icon = "icon_rf" },
        [19434] = { name = "Aimed Shot", icon = "icon_aimed" },
    },
    -- The SoD BUILD of the Era client: the same 1.15.9 client, running the SoD
    -- game. It carries the Chimera Shot rune (409433 - the class's own SoD
    -- detector) and the Bestial Wrath (19574: the client's own spell data maps
    -- it to the Beast Mastery skill line), so the HUD ships the Bestial Wrath
    -- slot there - the slot the Era-BASE pick drops.
    SOD = {
        [14266] = { name = "Raptor Strike", icon = "icon_raptor" },
        [25294] = { name = "Multi-Shot", icon = "icon_multi" },
        [19574] = { name = "Bestial Wrath", icon = "icon_bw" },
        [3045] = { name = "Rapid Fire", icon = "icon_rf" },
        [20904] = { name = "Aimed Shot", icon = "icon_aimed" },
        [409433] = { name = "Chimera Shot", icon = "icon_chimera" },
    },
    -- The Cata and the Mists Classic clients keep the CLASSIC spell ids for the
    -- hunter's classic abilities (wowsims/cata sim/hunter/* - the Cata client's
    -- Steady Shot is 56641, its Raptor Strike 48996 - and wowhead's own Mists
    -- pages: /mop-classic/spell=2643, /mop-classic/spell=19434,
    -- /mop-classic/spell=3045, /mop-classic/spell=56641).
    CATA = {
        [56641] = { name = "Steady Shot", icon = "icon_steady" },
        [48996] = { name = "Raptor Strike", icon = "icon_raptor" },
        [34026] = { name = "Kill Command", icon = "icon_kc" },
        [2643] = { name = "Multi-Shot", icon = "icon_multi" },
        [19574] = { name = "Bestial Wrath", icon = "icon_bw" },
        [3045] = { name = "Rapid Fire", icon = "icon_rf" },
        [19434] = { name = "Aimed Shot", icon = "icon_aimed" },
    },
}
HUNTER_SPELLS.MISTS = HUNTER_SPELLS.CATA
do
    local h = build({ class = "HUNTER", spells = HUNTER_SPELLS.TBC })
    local hst, HST = h.st, h.ST
    local HHUD = hst.hud
    check(type(HST.HUNTER.get_hud_state) == "function", "hunter: the class defines the provider")
    check(type(HST.HUNTER.HUD_SLOTS) == "table", "hunter: the class defines HUD_SLOTS")
    local slots = HST.HUNTER.HUD_SLOTS
    eq(#slots, 9, "hunter: seven ability slots plus the two trinket slots")
    local expected = { "steady", "raptor", "kill_command", "multi", "bestial_wrath",
        "rapid_fire", "aimed", "trinket1", "trinket2" }
    local by_key, keys_ok, desc_ok = {}, true, true
    for i = 1, #slots do
        by_key[slots[i].key] = slots[i]
        if slots[i].key ~= expected[i] then keys_ok = false end
        if not HHUD.validate_slot(slots[i], true) then desc_ok = false end
    end
    check(keys_ok, "hunter: the slot order follows the guide's")
    check(desc_ok, "hunter: every descriptor passes the contract")
    -- Every spell slot carries the TBC client's own rank - the family-correct ids,
    -- never one family-blind id (bench/hunter_hud_family_2026-10-20.md §2).
    eq(by_key.steady.spell, 34120,
        "hunter TBC: the Steady slot carries the TBC rank (not the vanilla 56641)")
    eq(by_key.raptor.spell, 27014,
        "hunter TBC: the Raptor slot carries the TBC client's own rank")
    eq(slots[3].spell, 34026, "hunter TBC: the Kill Command slot carries the TBC id")
    eq(by_key.multi.spell, 27021,
        "hunter TBC: the Multi-Shot slot carries the TBC client's own rank")
    eq(by_key.bestial_wrath.spell, 19574,
        "hunter TBC: the Bestial Wrath slot carries the TBC id")
    eq(by_key.rapid_fire.spell, 3045,
        "hunter TBC: the Rapid Fire slot carries the Rapid Fire id")
    eq(by_key.aimed.spell, 27065,
        "hunter TBC: the Aimed Shot slot carries the TBC client's own rank")
    eq(slots[7].key, "aimed", "hunter: Aimed Shot is the last ability slot")
    eq(slots[8].inv_slot, 13, "hunter: trinket 1 reads inventory slot 13")

    HHUD.init(HST)
    check(HHUD.frame ~= nil, "hunter: the HUD builds")
    eq(#HHUD.icons, 9, "hunter: all nine valid slots build an icon")
    eq(HHUD.icons[1].show_key, "hud_show_steady", "hunter: the per-slot toggle key is derived")
    eq(HHUD.icons[7].show_key, "hud_show_aimed", "hunter: the aimed toggle key is derived")
    eq(HHUD.icons[1].wanted, true, "hunter: a slot without a defaults key still shows")
    eq(HHUD.frame.width, 7 * 36 + 6 * 2, "hunter: the row sizes to the seven shown slots")

    clock = 500
    HST.gcd = {}
    HST.in_combat = false
    cooldowns["Kill Command"] = { start = clock - 10, duration = 60 }
    local s = HST.HUNTER.get_hud_state(HST, by_key.kill_command, clock)
    near(s.remaining, 50, 1e-9, "hunter: KC remaining comes from the client cooldown")
    eq(s.duration, 60, "hunter: KC carries its full cooldown")
    eq(s.desaturate, true, "hunter: an on-cooldown KC greys out")
    near(s.text_remaining, 50, 1e-9, "hunter: the cooldown text is the remaining time")

    -- the GCD echo is filtered: the slot falls through to the GCD swipe
    cooldowns["Kill Command"] = { start = clock, duration = 1.3 }
    HST.gcd = { expires = clock + 1.2, spell_length = 1.5 }
    s = HST.HUNTER.get_hud_state(HST, by_key.kill_command, clock)
    near(s.remaining, 1.2, 1e-9, "hunter: a GCD echo falls through to the GCD swipe")
    s = HST.HUNTER.get_hud_state(HST, by_key.bestial_wrath, clock)
    eq(s.remaining, nil, "hunter: Bestial Wrath never borrows the GCD")
    s = HST.HUNTER.get_hud_state(HST, by_key.rapid_fire, clock)
    eq(s.remaining, nil, "hunter: Rapid Fire never borrows the GCD")

    -- Kill Command glows when ready, in combat (the paladin's wings rule)
    cooldowns["Kill Command"] = nil
    HST.in_combat = true
    s = HST.HUNTER.get_hud_state(HST, by_key.kill_command, clock)
    eq(s.glow, true, "hunter: ready KC glows in combat")
    HST.in_combat = false
    s = HST.HUNTER.get_hud_state(HST, by_key.kill_command, clock)
    eq(s.glow, false, "hunter: out of combat KC does not glow")
    cooldowns["Kill Command"] = { start = clock - 10, duration = 60 }
    HST.in_combat = true
    s = HST.HUNTER.get_hud_state(HST, by_key.kill_command, clock)
    eq(s.glow, false, "hunter: on-cooldown KC does not glow")
    HST.in_combat = false
    cooldowns["Kill Command"] = nil

    -- Aimed Shot: the real Era cooldown is read by localized name (rank-agnostic);
    -- off-Era clients report none and the slot borrows the GCD swipe.
    clock = 500
    cooldowns["Aimed Shot"] = { start = clock - 2, duration = 6 }
    HST.gcd = {}
    s = HST.HUNTER.get_hud_state(HST, by_key.aimed, clock)
    near(s.remaining, 4, 1e-9, "hunter: Aimed remaining comes from the client cooldown")
    eq(s.duration, 6, "hunter: Aimed carries its full cooldown")
    eq(s.desaturate, true, "hunter: an on-cooldown Aimed greys out")
    near(s.text_remaining, 4, 1e-9, "hunter: the Aimed text is the remaining time")

    -- the GCD echo is filtered: the slot falls through to the GCD swipe
    cooldowns["Aimed Shot"] = { start = clock, duration = 1.3 }
    HST.gcd = { expires = clock + 1.2, spell_length = 1.5 }
    s = HST.HUNTER.get_hud_state(HST, by_key.aimed, clock)
    near(s.remaining, 1.2, 1e-9, "hunter: a GCD echo on Aimed falls through to the GCD swipe")

    -- ready with no cooldown anywhere: no swipe at all
    cooldowns["Aimed Shot"] = nil
    HST.gcd = {}
    s = HST.HUNTER.get_hud_state(HST, by_key.aimed, clock)
    eq(s.remaining, nil, "hunter: a ready Aimed with no GCD shows no swipe")
    eq(s.desaturate, nil, "hunter: a ready Aimed is not greyed")

    -- mana / range gates ride the shared options
    HST.gcd = {}
    usable_impl = function() return false, true end
    s = HST.HUNTER.get_hud_state(HST, by_key.steady, clock)
    eq(s.usable, false, "hunter: an insufficient-resource reading is reported")
    usable_impl = nil
    target_exists = true
    range_impl = function() return 0 end
    s = HST.HUNTER.get_hud_state(HST, by_key.steady, clock)
    eq(s.in_range, false, "hunter: an out-of-range reading is reported")
    range_impl = nil
    target_exists = false

    -- the aimed toggle gates its icon like every other per-slot toggle
    local hdb = h.ST.get_class_table()
    hdb.hud_show_aimed = false
    eq(HHUD.icon_should_show(HST, HHUD.icons[7], false), false,
        "hunter: hud_show_aimed off hides the aimed icon")
    hdb.hud_show_aimed = true
    eq(HHUD.icon_should_show(HST, HHUD.icons[7], false), true,
        "hunter: hud_show_aimed on shows the aimed icon")

    -- the HUD aimed icon rank-resolves through the guide's pattern: this client
    -- knows the TBC r7 27065 here, so the descriptor stays on the family's own
    -- rank while the name-based provider keeps counting the same localized spell.
    HST.HUNTER.resolve_guide_icons()
    eq(by_key.aimed.spell, 27065,
        "hunter TBC: the HUD aimed icon resolves to the client's current rank")
    clock = 500
    cooldowns["Aimed Shot"] = { start = clock - 2, duration = 6 }
    HST.gcd = {}
    s = HST.HUNTER.get_hud_state(HST, by_key.aimed, clock)
    near(s.remaining, 4, 1e-9, "hunter: the re-pointed Aimed still reads by name")
    cooldowns["Aimed Shot"] = nil
end

--=========================================================================================
-- 13b) Hunter Era HUD census (H-HUD-1): six live slots, no dead ones.
-- bench/rogue_hunter_eratbc_2026-10-19.md §5. Same descriptors, same order;
-- Steady Shot / Kill Command never prompt on Era, so the HUD filters them
-- instead of shipping them dark, and the Bestial Wrath is dropped on the
-- ERA-BASE build (the game never uses the 2.1 talent). The pick is decided at
-- post_init (the class's own SoD probe), so the census is taken AFTER that
-- decision: the shipped state, not the load-time one.
--=========================================================================================
do
    local e = build({ class = "HUNTER", project = 2, spells = HUNTER_SPELLS.ERA })
    local est, EST = e.st, e.ST
    local EH = est.hud
    local eslots = EST.HUNTER.HUD_SLOTS
    local eby_key = {}
    for i = 1, #eslots do eby_key[eslots[i].key] = eslots[i] end
    -- The DECLARED ids, before the runtime re-point and before the build
    -- decision: the live slots carry the ERA family's own rank (never one
    -- family-blind id).
    eq(eby_key.raptor.spell, 14266,
        "hunter Era: the Raptor slot carries the Era client's own rank")
    eq(eby_key.multi.spell, 25294,
        "hunter Era: the Multi-Shot slot carries the Era client's own rank")
    eq(eby_key.rapid_fire.spell, 3045,
        "hunter Era: the Rapid Fire slot carries the Rapid Fire id")
    eq(eby_key.aimed.spell, 20904,
        "hunter Era: the Aimed Shot slot carries the Era client's own rank")
    -- The build decision: the Era-BASE game never uses the 2.1 Bestial Wrath
    -- talent, so the slot is dropped (the same decision the guide's Era slot
    -- set follows).
    EST.HUNTER.resolve_guide_icons()
    eslots = EST.HUNTER.HUD_SLOTS
    eby_key = {}
    for i = 1, #eslots do eby_key[eslots[i].key] = eslots[i] end
    eq(#eslots, 6, "hunter Era: six live HUD slots (three dead filtered)")
    local eexpected = { "raptor", "multi", "rapid_fire", "aimed", "trinket1", "trinket2" }
    local ekeys_ok, edesc_ok = true, true
    for i = 1, #eslots do
        if eslots[i].key ~= eexpected[i] then ekeys_ok = false end
        if not EH.validate_slot(eslots[i], true) then edesc_ok = false end
    end
    check(ekeys_ok, "hunter Era: the live slots keep guide order")
    check(edesc_ok, "hunter Era: every live descriptor passes the contract")
    eq(eby_key.steady, nil, "hunter Era: no Steady slot ships")
    eq(eby_key.kill_command, nil, "hunter Era: no Kill Command slot ships")
    eq(eby_key.bestial_wrath, nil, "hunter Era: no Bestial Wrath slot ships")
    -- The client's own rank re-points the slot at runtime: this client knows the
    -- raptor r1 2973 and the multi r1 2643, so the slots land on those.
    eq(eby_key.raptor.spell, 2973,
        "hunter Era: the client's own Raptor rank re-points the HUD slot")
    eq(eby_key.multi.spell, 2643,
        "hunter Era: the client's own Multi-Shot rank re-points the HUD slot")

    EH.init(EST)
    check(EH.frame ~= nil, "hunter Era: the HUD builds")
    eq(#EH.icons, 6, "hunter Era: all six live slots build an icon")
    -- The two empty trinket slots hide, so four ability icons form the row.
    eq(EH.frame.width, 4 * 36 + 3 * 2, "hunter Era: the row sizes to the four shown slots")

    -- Live reads ride the same name-based provider as the TBC set.
    clock = 500
    EST.gcd = {}
    cooldowns["Aimed Shot"] = { start = clock - 2, duration = 6 }
    local es = EST.HUNTER.get_hud_state(EST, eby_key.aimed, clock)
    near(es.remaining, 4, 1e-9, "hunter Era: Aimed remaining comes from the client cooldown")
    eq(es.duration, 6, "hunter Era: Aimed carries its full cooldown")
    cooldowns["Aimed Shot"] = nil
end

--=========================================================================================
-- 13g) Hunter SoD HUD census: the BUILD-aware row. The SoD build of the same
-- 1.15.9 client HAS the Bestial Wrath (that client's own spell data maps 19574
-- to the Beast Mastery skill line), so the HUD ships the slot the Era-BASE pick
-- drops - with the SoD id. The build is the class's own SoD probe (the Chimera
-- Shot rune), decided at post_init, so the census is taken after that decision.
--=========================================================================================
do
    local s = build({ class = "HUNTER", project = 2, spells = HUNTER_SPELLS.SOD,
        known_spells = { [409433] = true } })
    local sst, SST = s.st, s.ST
    local SH = sst.hud
    eq(sst.family, "ERA", "hunter SoD: the fixture reads the ERA family token")
    SST.HUNTER.resolve_guide_icons()
    local sslots = SST.HUNTER.HUD_SLOTS
    eq(#sslots, 7, "hunter SoD: seven HUD slots (the Bestial Wrath included)")
    local sby_key, skeys_ok, sdesc_ok = {}, true, true
    local sexpected = { "raptor", "multi", "bestial_wrath", "rapid_fire", "aimed",
        "trinket1", "trinket2" }
    for i = 1, #sslots do
        sby_key[sslots[i].key] = sslots[i]
        if sslots[i].key ~= sexpected[i] then skeys_ok = false end
        if not SH.validate_slot(sslots[i], true) then sdesc_ok = false end
    end
    check(skeys_ok, "hunter SoD: the live slots keep the declaration order")
    check(sdesc_ok, "hunter SoD: every live descriptor passes the contract")
    eq(sby_key.steady, nil,
        "hunter SoD: no Steady slot ships (the 1.15.9 client has no Steady Shot)")
    eq(sby_key.kill_command, nil,
        "hunter SoD: no Kill Command slot ships (the 1.15.9 client has no Kill Command)")
    check(sby_key.bestial_wrath ~= nil, "hunter SoD: the Bestial Wrath slot ships")
    eq(sby_key.bestial_wrath.spell, 19574,
        "hunter SoD: the Bestial Wrath slot carries the SoD client's own rank")
    eq(sby_key.raptor.spell, 14266,
        "hunter SoD: the Raptor slot carries the Era client's own rank")
    eq(sby_key.multi.spell, 25294,
        "hunter SoD: the Multi-Shot slot carries the Era client's own rank")
    eq(sby_key.rapid_fire.spell, 3045,
        "hunter SoD: the Rapid Fire slot carries the Rapid Fire id")
    eq(sby_key.aimed.spell, 20904,
        "hunter SoD: the Aimed Shot slot carries the Era client's own rank")
    -- The guide's SoD slot set declares the same slot with the same id.
    local guide_bw = nil
    for i = 1, #SST.HUNTER.guide.slots do
        if SST.HUNTER.guide.slots[i].key == "bestial_wrath" then
            guide_bw = SST.HUNTER.guide.slots[i]
        end
    end
    check(guide_bw ~= nil, "hunter SoD: the guide declares the Bestial Wrath slot")
    eq(guide_bw and guide_bw.spell_id, sby_key.bestial_wrath.spell,
        "hunter SoD: the guide and the HUD carry the same Bestial Wrath id")
    SH.init(SST)
    check(SH.frame ~= nil, "hunter SoD: the HUD builds")
    eq(#SH.icons, 7, "hunter SoD: all seven live slots build an icon")
end

--=========================================================================================
-- 13c) Hunter Forever HUD census: no Steady slot and no Kill Command slot (the
-- client has neither: bench/rotation_gap_vs_apl_2026-10-20.md §0.0 H4 - no Steady
-- Shot at all - and the Forever client's own hunter spell table carries no Kill
-- Command entry, wowsims/forever sim/hunter/spell_data_auto_gen.go). The HUD
-- filters both slots instead of shipping a dead cell for a spell the client
-- cannot have (the same rule the Era pick follows).
--=========================================================================================
do
    local f = build({ class = "HUNTER", project = 18, spells = HUNTER_SPELLS.FOREVER })
    local fst, FST = f.st, f.ST
    local FH = fst.hud
    eq(fst.family, "FOREVER", "hunter Forever: the project-18 fixture reads the FOREVER token")
    local fslots = FST.HUNTER.HUD_SLOTS
    eq(#fslots, 7, "hunter Forever: seven HUD slots (the dead Steady and Kill Command slots filtered)")
    local fexpected = { "raptor", "multi", "bestial_wrath",
        "rapid_fire", "aimed", "trinket1", "trinket2" }
    local fby_key, fkeys_ok, fdesc_ok = {}, true, true
    for i = 1, #fslots do
        fby_key[fslots[i].key] = fslots[i]
        if fslots[i].key ~= fexpected[i] then fkeys_ok = false end
        if not FH.validate_slot(fslots[i], true) then fdesc_ok = false end
    end
    check(fkeys_ok, "hunter Forever: the live slots keep guide order")
    check(fdesc_ok, "hunter Forever: every live descriptor passes the contract")
    eq(fby_key.steady, nil,
        "hunter Forever: no Steady slot ships (the client has no Steady Shot)")
    eq(fby_key.kill_command, nil,
        "hunter Forever: no Kill Command slot ships (the client has no Kill Command)")
    -- The live slots carry the Forever client's own rank.
    eq(fby_key.raptor.spell, 14266,
        "hunter Forever: the Raptor slot carries the Forever client's own rank")
    eq(fby_key.multi.spell, 2643,
        "hunter Forever: the Multi-Shot slot carries the Forever client's own rank")
    eq(fby_key.bestial_wrath.spell, 19574,
        "hunter Forever: the Bestial Wrath slot carries the Forever client's own rank")
    eq(fby_key.rapid_fire.spell, 3045,
        "hunter Forever: the Rapid Fire slot carries the Rapid Fire id")
    eq(fby_key.aimed.spell, 20904,
        "hunter Forever: the Aimed Shot slot carries the Forever client's own rank")

    FH.init(FST)
    check(FH.frame ~= nil, "hunter Forever: the HUD builds")
    eq(#FH.icons, 7, "hunter Forever: all seven live slots build an icon")
    -- The two empty trinket slots hide, so five ability icons form the row.
    eq(FH.frame.width, 5 * 36 + 4 * 2, "hunter Forever: the row sizes to the five shown slots")
end

--=========================================================================================
-- 13d) Hunter Wrath HUD census: every slot carries the WotLK client's own rank
-- (the vanilla ids the HUD used to ship - 2973 / 2643 / 19434 - are not the
-- WotLK client's Aimed Shot, Multi-Shot and Raptor Strike ranks).
--=========================================================================================
do
    local w = build({ class = "HUNTER", project = 11, spells = HUNTER_SPELLS.WRATH })
    local wst, WST = w.st, w.ST
    local WH = wst.hud
    eq(wst.family, "WRATH", "hunter Wrath: the project-11 fixture reads the WRATH token")
    local wslots = WST.HUNTER.HUD_SLOTS
    eq(#wslots, 9, "hunter Wrath: nine HUD slots (seven ability slots plus the trinkets)")
    local wby_key = {}
    for i = 1, #wslots do wby_key[wslots[i].key] = wslots[i] end
    eq(wby_key.steady.spell, 49052,
        "hunter Wrath: the Steady slot carries the WotLK rank")
    eq(wby_key.raptor.spell, 48996,
        "hunter Wrath: the Raptor slot carries the WotLK client's own rank")
    eq(wby_key.kill_command.spell, 34026,
        "hunter Wrath: the Kill Command slot carries the WotLK id")
    eq(wby_key.multi.spell, 49048,
        "hunter Wrath: the Multi-Shot slot carries the WotLK client's own rank")
    eq(wby_key.bestial_wrath.spell, 19574,
        "hunter Wrath: the Bestial Wrath slot carries the WotLK id")
    eq(wby_key.rapid_fire.spell, 3045,
        "hunter Wrath: the Rapid Fire slot carries the Rapid Fire id")
    eq(wby_key.aimed.spell, 49050,
        "hunter Wrath: the Aimed Shot slot carries the WotLK instant shot")
    check(wby_key.aimed.spell ~= 19434,
        "hunter Wrath: the Aimed Shot slot never carries the vanilla rank 19434")
    WH.init(WST)
    check(WH.frame ~= nil, "hunter Wrath: the HUD builds")
    eq(#WH.icons, 9, "hunter Wrath: all nine live slots build an icon")
end

--=========================================================================================
-- 13f) Hunter Cata / Mists HUD census: the retail-line classic clients keep the
-- CLASSIC spell ids, so every slot carries the client's own rank there too.
--
-- The two rows differ in ONE place: the Raptor Strike. The Cata CLASSIC client
-- (interface 40402) carries the classic rank 2973 - the retail Cata rank 48996
-- is NOT in that client's spell table - while the Mists client has no Raptor
-- Strike id this tree knows at all, so the slot is DROPPED there (a slot for a
-- spell the client cannot have is never offered).
--=========================================================================================
do
    for _, case in ipairs({ { 14, "Cata", "CATA", 9, 2973 }, { 19, "Mists", "MISTS", 8, nil } }) do
        local project, name, key, count, raptor_id = case[1], case[2], case[3], case[4], case[5]
        local c = build({ class = "HUNTER", project = project, spells = HUNTER_SPELLS[key] })
        local cst, CST = c.st, c.ST
        local CH = cst.hud
        eq(cst.family, key, "hunter " .. name .. ": the fixture reads the " .. key .. " token")
        local cslots = CST.HUNTER.HUD_SLOTS
        eq(#cslots, count, "hunter " .. name .. ": " .. count .. " HUD slots")
        local cby_key = {}
        for i = 1, #cslots do cby_key[cslots[i].key] = cslots[i] end
        eq(cby_key.steady.spell, 56641,
            "hunter " .. name .. ": the Steady slot carries the client's own rank")
        if raptor_id then
            eq(cby_key.raptor.spell, raptor_id,
                "hunter " .. name .. ": the Raptor slot carries the client's own rank")
        else
            eq(cby_key.raptor, nil,
                "hunter " .. name .. ": no Raptor slot ships (the client's Raptor Strike id is unknown)")
        end
        eq(cby_key.kill_command.spell, 34026,
            "hunter " .. name .. ": the Kill Command slot carries the client's own rank")
        eq(cby_key.multi.spell, 2643,
            "hunter " .. name .. ": the Multi-Shot slot carries the client's own rank")
        eq(cby_key.bestial_wrath.spell, 19574,
            "hunter " .. name .. ": the Bestial Wrath slot carries the client's own rank")
        eq(cby_key.rapid_fire.spell, 3045,
            "hunter " .. name .. ": the Rapid Fire slot carries the client's own rank")
        eq(cby_key.aimed.spell, 19434,
            "hunter " .. name .. ": the Aimed Shot slot carries the client's own rank")
        CH.init(CST)
        check(CH.frame ~= nil, "hunter " .. name .. ": the HUD builds")
        eq(#CH.icons, count, "hunter " .. name .. ": all " .. count .. " live slots build an icon")
    end
end

--=========================================================================================
-- 13e) Hunter retail HUD census: every slot carries the retail client's own rank
-- (the retail client renamed two of them: the Raptor Strike is 186270 and the
-- Rapid Fire 257044 - wowhead's own retail pages).
--=========================================================================================
do
    local t = build({ class = "HUNTER", project = 1, spells = HUNTER_SPELLS.RETAIL })
    local tst, TST = t.st, t.ST
    local TH = tst.hud
    eq(tst.family, "RETAIL", "hunter retail: the project-1 fixture reads the RETAIL token")
    local tslots = TST.HUNTER.HUD_SLOTS
    eq(#tslots, 9, "hunter retail: nine HUD slots (seven ability slots plus the trinkets)")
    local tby_key = {}
    for i = 1, #tslots do tby_key[tslots[i].key] = tslots[i] end
    eq(tby_key.steady.spell, 56641,
        "hunter retail: the Steady slot carries the client's own rank")
    eq(tby_key.raptor.spell, 186270,
        "hunter retail: the Raptor slot carries the retail client's own rank")
    eq(tby_key.kill_command.spell, 34026,
        "hunter retail: the Kill Command slot carries the retail id")
    eq(tby_key.multi.spell, 2643,
        "hunter retail: the Multi-Shot slot carries the client's own rank")
    eq(tby_key.bestial_wrath.spell, 19574,
        "hunter retail: the Bestial Wrath slot carries the retail id")
    eq(tby_key.rapid_fire.spell, 257044,
        "hunter retail: the Rapid Fire slot carries the retail client's own rank")
    eq(tby_key.aimed.spell, 19434,
        "hunter retail: the Aimed Shot slot carries the client's own rank")
    TH.init(TST)
    check(TH.frame ~= nil, "hunter retail: the HUD builds")
    eq(#TH.icons, 9, "hunter retail: all nine live slots build an icon")
end

--=========================================================================================
-- 14) Warrior provider: TBC slot set, creation and live readers
--=========================================================================================
do
    local w = build({ class = "WARRIOR" })
    local wst, WST = w.st, w.ST
    local WHUD = wst.hud
    check(type(WST.WARRIOR.get_hud_state) == "function", "warrior: the class defines the provider")
    check(type(WST.WARRIOR.HUD_SLOTS) == "table", "warrior: the class defines HUD_SLOTS")
    eq(wst.family, "TBC", "warrior: the sandbox runs the TBC family")
    local slots = WST.WARRIOR.HUD_SLOTS
    eq(#slots, 9, "warrior: the TBC set is seven ability slots plus the two trinkets")
    local expected = { "op", "execute", "slam", "hs", "bt", "ww", "sunder",
        "trinket1", "trinket2" }
    local by_key, keys_ok, desc_ok = {}, true, true
    for i = 1, #slots do
        by_key[slots[i].key] = slots[i]
        if slots[i].key ~= expected[i] then keys_ok = false end
        if not WHUD.validate_slot(slots[i], true) then desc_ok = false end
    end
    check(keys_ok, "warrior: the TBC slot order matches the guide's")
    check(desc_ok, "warrior: every descriptor passes the contract")
    eq(slots[1].spell, 7384, "warrior: Overpower keeps the module's id")
    eq(slots[5].spell, 23881, "warrior: Bloodthirst keeps the module's rank-1 id")
    eq(by_key.sunder.spell, 7386, "warrior: the Sunder mirror keeps the rank-1 id")

    WHUD.init(WST)
    check(WHUD.frame ~= nil, "warrior: the HUD builds")
    eq(#WHUD.icons, 9, "warrior: all nine valid slots build an icon")
    -- The Sunder mirror is provider-hidden by default (no hud_show_sunder key in
    -- the sandbox: nil = off, the druid Claw shape), so the row still sizes to
    -- the six shown slots.
    eq(WHUD.frame.width, 6 * 36 + 5 * 2, "warrior: the row sizes to the six shown slots")

    clock = 600
    WST.gcd = {}
    WST.in_combat = false
    cooldowns["Bloodthirst"] = { start = clock - 2, duration = 6 }
    local s = WST.WARRIOR.get_hud_state(WST, by_key.bt, clock)
    near(s.remaining, 4, 1e-9, "warrior: BT remaining comes from the client cooldown")
    eq(s.duration, 6, "warrior: BT carries its full cooldown")
    eq(s.desaturate, true, "warrior: an on-cooldown BT greys out")

    -- a cooldown-less slot borrows the GCD swipe
    WST.gcd = { expires = clock + 1.0, spell_length = 1.5 }
    s = WST.WARRIOR.get_hud_state(WST, by_key.hs, clock)
    near(s.remaining, 1.0, 1e-9, "warrior: Heroic Strike takes the GCD swipe")

    -- Overpower glows while its dodge window is live (the module's own stamp)
    WST.warrior_overpower_proc_until = clock + 3
    s = WST.WARRIOR.get_hud_state(WST, by_key.op, clock)
    eq(s.glow, true, "warrior: Overpower glows inside the dodge window")
    WST.warrior_overpower_proc_until = clock - 1
    s = WST.WARRIOR.get_hud_state(WST, by_key.op, clock)
    eq(s.glow, false, "warrior: an elapsed window stops the glow")
    WST.warrior_overpower_proc_until = nil

    -- Execute glows when ready, in combat, with the target in Execute range
    target_exists = true
    target_health, target_health_max = 15, 100
    WST.in_combat = true
    s = WST.WARRIOR.get_hud_state(WST, by_key.execute, clock)
    eq(s.glow, true, "warrior: Execute glows at 15% target health in combat")
    target_health = 80
    s = WST.WARRIOR.get_hud_state(WST, by_key.execute, clock)
    eq(s.glow, false, "warrior: Execute does not glow at 80% target health")
    target_health, target_health_max = nil, nil
    s = WST.WARRIOR.get_hud_state(WST, by_key.execute, clock)
    eq(s.glow, false, "warrior: an unreadable target never glows Execute")
    WST.in_combat = false
    target_exists = false

    -- The Sunder mirror (W-21): display-only and hidden unless its
    -- hud_show_sunder toggle reads exactly true (nil = off, the druid Claw
    -- shape). It carries no cooldown of its own to ride, so it reads neither a
    -- cooldown nor the GCD swipe.
    local wdb = WST.get_class_table()
    wdb.hud_show_sunder = nil
    s = WST.WARRIOR.get_hud_state(WST, by_key.sunder, clock)
    eq(s.hidden, true, "warrior: a nil hud_show_sunder hides the Sunder mirror")
    wdb.hud_show_sunder = true
    WST.gcd = { expires = clock + 1.0, spell_length = 1.5 }
    s = WST.WARRIOR.get_hud_state(WST, by_key.sunder, clock)
    eq(s.hidden, nil, "warrior: hud_show_sunder true shows the Sunder mirror")
    eq(s.remaining, nil, "warrior: the Sunder mirror reports no cooldown")
    eq(s.duration, nil, "warrior: the Sunder mirror carries no duration")
    eq(s.glow, nil, "warrior: the Sunder mirror is display-only (no glow)")
    WST.gcd = {}
    wdb.hud_show_sunder = nil
    s = WST.WARRIOR.get_hud_state(WST, by_key.sunder, clock)
    eq(s.hidden, true, "warrior: clearing the toggle hides the Sunder mirror again")
    wdb.hud_show_sunder = nil
end

--=========================================================================================
-- 15) Druid provider: slots, creation and live readers
--=========================================================================================
do
    local d = build({ class = "DRUID" })
    local dst, DST = d.st, d.ST
    local DHUD = dst.hud
    check(type(DST.DRUID.get_hud_state) == "function", "druid: the class defines the provider")
    check(type(DST.DRUID.HUD_SLOTS) == "table", "druid: the class defines HUD_SLOTS")
    local slots = DST.DRUID.HUD_SLOTS
    eq(#slots, 11, "druid: nine ability slots plus the two trinket slots")
    local expected = { "maul", "mangle", "rip", "rake", "bite", "shred", "claw",
        "tf", "berserk", "trinket1", "trinket2" }
    local by_key, keys_ok, desc_ok = {}, true, true
    for i = 1, #slots do
        by_key[slots[i].key] = slots[i]
        if slots[i].key ~= expected[i] then keys_ok = false end
        if not DHUD.validate_slot(slots[i], true) then desc_ok = false end
    end
    check(keys_ok, "druid: the slot order follows the guide's")
    check(desc_ok, "druid: every descriptor passes the contract")
    eq(slots[1].spell, 6807, "druid: Maul keeps the module's rank-1 id")
    eq(by_key.claw.spell, 9850, "druid: Claw ships the sim Forever id")

    DHUD.init(DST)
    check(DHUD.frame ~= nil, "druid: the HUD builds")
    eq(#DHUD.icons, 11, "druid: all eleven valid slots build an icon")
    -- The creation paint (apply_settings' trailing update_display) already observes
    -- the dead Claw toggle + TF/Berserk probes and reflows: six live slots, no gap.
    eq(DHUD.frame.width, 6 * 36 + 5 * 2, "druid: the row sizes to the six live slots")

    clock = 700
    DST.gcd = {}
    DST.in_combat = false
    DST.insufficient_rage = false
    -- no native cooldowns: a ready slot reports nothing without a GCD
    local s = DST.DRUID.get_hud_state(DST, by_key.rip, clock)
    eq(s.remaining, nil, "druid: a ready Rip reports no cooldown")
    eq(s.duration, nil, "druid: a ready Rip reports no duration")
    -- the GCD swipe still shows on every rotational slot
    DST.gcd = { expires = clock + 1.4, spell_length = 1.5 }
    s = DST.DRUID.get_hud_state(DST, by_key.mangle, clock)
    near(s.remaining, 1.4, 1e-9, "druid: Mangle takes the GCD swipe")
    -- a GCD echo on the ability itself is filtered, not counted
    cooldowns["Rip"] = { start = clock, duration = 1.5 }
    DST.gcd = {}
    s = DST.DRUID.get_hud_state(DST, by_key.rip, clock)
    eq(s.remaining, nil, "druid: a GCD-length reading is not a cooldown")
    cooldowns["Rip"] = nil
    -- the Maul slot greys while the queued Maul is unaffordable
    DST.insufficient_rage = true
    s = DST.DRUID.get_hud_state(DST, by_key.maul, clock)
    eq(s.desaturate, true, "druid: Maul greys on insufficient rage")
    DST.insufficient_rage = false
    s = DST.DRUID.get_hud_state(DST, by_key.maul, clock)
    eq(s.desaturate, nil, "druid: an affordable Maul is not greyed")
    -- Claw display mirror: nil toggle hides (no default-visible change), true
    -- takes the rotational GCD path; no probe, no rule.
    s = DST.DRUID.get_hud_state(DST, by_key.claw, clock)
    eq(s.hidden, true, "druid: nil hud_show_claw hides the Claw slot")
    local claw_db = DST.get_class_table()
    claw_db.hud_show_claw = true
    DST.gcd = {}
    s = DST.DRUID.get_hud_state(DST, by_key.claw, clock)
    eq(s.hidden, nil, "druid: hud_show_claw true shows the Claw slot")
    eq(s.remaining, nil, "druid: a ready Claw with no GCD reports no cooldown")
    DST.gcd = { expires = clock + 1.4, spell_length = 1.5 }
    s = DST.DRUID.get_hud_state(DST, by_key.claw, clock)
    near(s.remaining, 1.4, 1e-9, "druid: Claw takes the GCD swipe")
    DST.gcd = {}
    claw_db.hud_show_claw = nil
    s = DST.DRUID.get_hud_state(DST, by_key.claw, clock)
    eq(s.hidden, true, "druid: clearing the toggle hides Claw again")
end

--=========================================================================================
-- 16) Shaman provider: slots, creation and live readers
--=========================================================================================
do
    local m = build({ class = "SHAMAN" })
    local mst, MST = m.st, m.ST
    local MHUD = mst.hud
    check(type(MST.SHAMAN.get_hud_state) == "function", "shaman: the class defines the provider")
    check(type(MST.SHAMAN.HUD_SLOTS) == "table", "shaman: the class defines HUD_SLOTS")
    local slots = MST.SHAMAN.HUD_SLOTS
    eq(#slots, 11, "shaman: nine ability slots plus the two trinket slots")
    local expected = { "stormstrike", "flameshock", "weave", "firenova",
        "earthshock", "twist", "lightningshield", "searing", "coe",
        "trinket1", "trinket2" }
    local by_key, keys_ok, desc_ok = {}, true, true
    for i = 1, #slots do
        by_key[slots[i].key] = slots[i]
        if slots[i].key ~= expected[i] then keys_ok = false end
        if not MHUD.validate_slot(slots[i], true) then desc_ok = false end
    end
    check(keys_ok, "shaman: the slot order follows the guide's")
    check(desc_ok, "shaman: every descriptor passes the contract")
    eq(slots[1].spell, 17364, "shaman: Stormstrike keeps the module's id")
    eq(slots[4].spell, 1535, "shaman: Fire Nova keeps the module's rank-1 id")

    MHUD.init(MST)
    check(MHUD.frame ~= nil, "shaman: the HUD builds")
    eq(#MHUD.icons, 11, "shaman: all eleven valid slots build an icon")
    eq(MHUD.frame.width, 6 * 36 + 5 * 2, "shaman: the row sizes to the six shown slots")

    clock = 800
    MST.gcd = {}
    MST.in_combat = false
    cooldowns["Stormstrike"] = { start = clock - 4, duration = 10 }
    local s = MST.SHAMAN.get_hud_state(MST, by_key.stormstrike, clock)
    near(s.remaining, 6, 1e-9, "shaman: SS remaining comes from the client cooldown")
    eq(s.duration, 10, "shaman: SS carries its full cooldown")
    eq(s.desaturate, true, "shaman: an on-cooldown SS greys out")

    -- Stormstrike glows when ready, in combat (the paladin's wings rule)
    cooldowns["Stormstrike"] = nil
    MST.in_combat = true
    s = MST.SHAMAN.get_hud_state(MST, by_key.stormstrike, clock)
    eq(s.glow, true, "shaman: ready Stormstrike glows in combat")
    MST.in_combat = false
    s = MST.SHAMAN.get_hud_state(MST, by_key.stormstrike, clock)
    eq(s.glow, false, "shaman: out of combat Stormstrike does not glow")

    -- Fire Nova's real cooldown is read by name with its 15 s length
    cooldowns["Fire Nova Totem"] = { start = clock - 5, duration = 15 }
    s = MST.SHAMAN.get_hud_state(MST, by_key.firenova, clock)
    near(s.remaining, 10, 1e-9, "shaman: Fire Nova's real cooldown is read by name")
    eq(s.duration, 15, "shaman: Fire Nova carries its full cooldown")
    cooldowns["Fire Nova Totem"] = nil

    -- The two maintain mirrors (S-19 / S-17): display-only, hidden until their
    -- hud_show_<key> toggle reads exactly true (nil = off - the HUD treats a nil
    -- toggle as wanted, so the provider-level hide is the no-default-visible gate).
    MST.in_combat = true
    s = MST.SHAMAN.get_hud_state(MST, by_key.lightningshield, clock)
    eq(s.hidden, true, "shaman: the Lightning Shield mirror hides without its toggle")
    s = MST.SHAMAN.get_hud_state(MST, by_key.searing, clock)
    eq(s.hidden, true, "shaman: the Searing mirror hides without its toggle")
    s = MST.SHAMAN.get_hud_state(MST, by_key.coe, clock)
    eq(s.hidden, true, "shaman: the Call of the Elements mirror hides without its toggle")
    class_db.hud_show_lightningshield = true
    MST.weave_shield_scanned = false
    s = MST.SHAMAN.get_hud_state(MST, by_key.lightningshield, clock)
    eq(s.hidden, true, "shaman: an unrun aura walk draws nothing (unknown-hides)")
    MST.weave_shield_scanned = true
    MST.weave_shield_type = "lightning"
    s = MST.SHAMAN.get_hud_state(MST, by_key.lightningshield, clock)
    eq(s.hidden, nil, "shaman: an up-to-date shield shows its slot")
    eq(s.glow, false, "shaman: an up-to-date shield never glows")
    MST.weave_shield_type = nil
    s = MST.SHAMAN.get_hud_state(MST, by_key.lightningshield, clock)
    eq(s.glow, true, "shaman: a missing shield glows (the cast is needed)")
    MST.in_combat = false
    s = MST.SHAMAN.get_hud_state(MST, by_key.lightningshield, clock)
    eq(s.glow, false, "shaman: out of combat the shield never glows")
    class_db.hud_show_lightningshield = nil
    class_db.hud_show_searing = true
    s = MST.SHAMAN.get_hud_state(MST, by_key.searing, clock)
    eq(s.hidden, true, "shaman: an unknown Searing Totem draws nothing (the known gate)")
    class_db.hud_show_searing = nil
end

--=========================================================================================
-- 17) Non-paladin wiring: post_init initialises the HUD, the class hook syncs it
--=========================================================================================
do
    local function read(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text
    end

    local wired = { "hunter", "warrior", "druid", "shaman", "rogue" }
    for i = 1, #wired do
        local src = read("classes/" .. wired[i] .. ".lua")
        check(src:find("st.hud.init(self)", 1, true) ~= nil,
            "classes/" .. wired[i] .. ".lua initialises the HUD from post_init")
        check(src:find("st.hud.on_bar_update(self, hand)", 1, true) ~= nil,
            "classes/" .. wired[i] .. ".lua syncs the HUD layout from its class hook")
        check(src:find("get_hud_state", 1, true) ~= nil,
            "classes/" .. wired[i] .. ".lua defines the HUD provider")
        check(src:find("get_rotation_key", 1, true) ~= nil,
            "classes/" .. wired[i] .. ".lua defines the rotation source")
    end
end

--=========================================================================================
-- 18) Hidden-flip reflow: provider-hidden slots reserve no row width
--=========================================================================================
do
    -- Druid end-to-end (no stubbing): the sandbox client carries no TF/Berserk
    -- spell data, so both probes stay negative and both slots hide on the tick;
    -- Claw hides on its nil toggle (no default-visible change).
    local d = build({ class = "DRUID" })
    local dst, DST = d.st, d.ST
    local DHUD = dst.hud
    DHUD.init(DST)
    -- The creation paint (apply_settings' trailing update_display) already observes
    -- the dead Claw toggle + TF/Berserk probes and reflows: six live slots, no gap.
    eq(DHUD.frame.width, 6 * 36 + 5 * 2,
        "reflow: the first paint already closes the dead slots' gap")
    eq(DHUD.icons[7].last_hidden, true, "reflow: the dead Claw slot records its liveness")
    eq(DHUD.icons[8].last_hidden, true, "reflow: the dead TF slot records its liveness")
    eq(DHUD.icons[9].last_hidden, true, "reflow: the dead Berserk slot records its liveness")
    eq(DHUD.icons[2].last_hidden, false, "reflow: the live Mangle slot records its liveness")
    check(not DHUD.icons[7]:IsShown(), "reflow: the dead Claw icon hides")
    check(not DHUD.icons[8]:IsShown(), "reflow: the dead TF icon hides")
    check(not DHUD.icons[9]:IsShown(), "reflow: the dead Berserk icon hides")
    near(DHUD.icons[3].point[4], 2 * (36 + 2), 1e-9,
        "reflow: survivors shift left into the closed gap")

    -- A further identical tick flips nothing: providers still run exactly once
    -- each, and the row stays put.
    clock = 800
    DST.gcd = {}
    DST.in_combat = false
    local provider_calls = 0
    local real_druid = DST.DRUID.get_hud_state
    DST.DRUID.get_hud_state = function(self2, slot2, now2)
        provider_calls = provider_calls + 1
        return real_druid(self2, slot2, now2)
    end
    DHUD.update_display(DST)
    eq(provider_calls, 9, "reflow: a tick still runs each wanted provider exactly once")
    eq(DHUD.frame.width, 6 * 36 + 5 * 2, "reflow: a flip-less tick leaves the row alone")
    DST.DRUID.get_hud_state = real_druid
end

do
    -- Hide / revive / combat-deferral on a fresh paladin row (stubbed provider).
    local r = build()
    local rst, RST = r.st, r.ST
    local RHUD = rst.hud
    RHUD.init(RST)
    eq(RHUD.frame.width, 7 * 36 + 6 * 2, "reflow: the paladin row starts seven wide")
    local real_paladin = RST.PALADIN.get_hud_state
    local hide_cs = false
    RST.PALADIN.get_hud_state = function(self2, slot2, now2)
        if slot2.key == "cs" and hide_cs then
            return { hidden = true }
        end
        return real_paladin(self2, slot2, now2)
    end
    clock = 900
    RST.gcd = {}
    local provider_calls = 0
    local counting = RST.PALADIN.get_hud_state
    RST.PALADIN.get_hud_state = function(self2, slot2, now2)
        provider_calls = provider_calls + 1
        return counting(self2, slot2, now2)
    end
    hide_cs = true
    RHUD.update_display(RST)
    eq(provider_calls, 12, "reflow: the hiding tick runs each wanted provider exactly once")
    check(not RHUD.icons[1]:IsShown(), "reflow: the hidden CS icon hides on the tick")
    eq(RHUD.frame.width, 6 * 36 + 5 * 2, "reflow: the row closes the hidden slot's gap")
    near(RHUD.icons[2].point[4], 0, 1e-9, "reflow: the row re-flows without the hidden slot")

    -- Revive rejoins the row without a settings change.
    hide_cs = false
    provider_calls = 0
    RHUD.update_display(RST)
    eq(provider_calls, 12, "reflow: the revive tick runs each wanted provider exactly once")
    check(RHUD.icons[1]:IsShown(), "reflow: the revived slot re-shows without a settings change")
    eq(RHUD.frame.width, 7 * 36 + 6 * 2, "reflow: the revive restores the row width")
    near(RHUD.icons[2].point[4], 38, 1e-9, "reflow: the revive pushes survivors back over")

    -- Combat: the icon still hides (non-secure frames), but the geometry waits.
    hide_cs = true
    lockdown = true
    RHUD.update_display(RST)
    eq(RHUD.pending_apply, true, "reflow: a combat flip defers through the pending latch")
    eq(RHUD.frame.width, 7 * 36 + 6 * 2,
        "reflow: the row geometry never shifts mid-fight")
    check(not RHUD.icons[1]:IsShown(), "reflow: the icon itself still hides in combat")
    lockdown = false
    RHUD.on_update(RST, 0.06)
    eq(RHUD.pending_apply, false, "reflow: the combat exit clears the pending latch")
    eq(RHUD.frame.width, 6 * 36 + 5 * 2,
        "reflow: the combat exit applies the deferred reflow")
    RST.PALADIN.get_hud_state = real_paladin
end

--=========================================================================================
-- 19) Rogue provider: trinket inputs on the shared ICD row (X1)
--=========================================================================================
-- The rogue is the only class without hud_state coverage: its spell slots resolve
-- their ids from the client's spell data (apply_spell_ids) before the HUD builds,
-- while the two trinket slots are HUD-served like every other class. This section
-- pins the shared-row half: the 13 descriptors, the trinket inputs, the
-- provider's cleared (never invented) trinket state, and the unknown-duration
-- discipline (no icd entry -> no stamp, no swipe) through the rogue row.
do
    local r = build({ class = "ROGUE" })
    local rst, RST = r.st, r.ST
    local RHUD = rst.hud
    check(type(RST.ROGUE.get_hud_state) == "function", "rogue: the class defines the provider")
    check(type(RST.ROGUE.HUD_SLOTS) == "table", "rogue: the class defines HUD_SLOTS")
    local slots = RST.ROGUE.HUD_SLOTS
    eq(#slots, 13, "rogue: eleven ability slots plus the two trinket slots")
    local expected = { "snd", "rupture", "ea", "ar", "bf", "tea", "kick",
        "kidney", "restealth", "bandage", "coldblood", "trinket1", "trinket2" }
    local by_key, keys_ok = {}, true
    for i = 1, #slots do
        by_key[slots[i].key] = slots[i]
        if slots[i].key ~= expected[i] then keys_ok = false end
    end
    check(keys_ok, "rogue: the slot order follows the teardown")
    -- The shared-row inputs validate with and without a provider (the frozen
    -- contract: trinket slots are HUD-served) and read the trinket slots.
    eq(RHUD.validate_slot(by_key.trinket1, true), true,
        "rogue: trinket 1 validates with a provider")
    eq(RHUD.validate_slot(by_key.trinket1, false), true,
        "rogue: trinket 1 validates without a provider")
    eq(RHUD.validate_slot(by_key.trinket2, false), true,
        "rogue: trinket 2 validates without a provider")
    eq(by_key.trinket1.inv_slot, 13, "rogue: trinket 1 reads inventory slot 13")
    eq(by_key.trinket2.inv_slot, 14, "rogue: trinket 2 reads inventory slot 14")
    -- Spell slots ship unresolved: the ids come from apply_spell_ids before the
    -- HUD builds (a slot with no icon source never builds, per the contract).
    for i = 1, 11 do
        eq(slots[i].spell, nil, "rogue: " .. slots[i].key .. " ships without a remembered id")
    end
    eq(RHUD.validate_slot(by_key.snd, true), false,
        "rogue: an unresolved spell slot does not validate")

    -- Resolve the spell slots the way apply_spell_ids does (a known fixture id
    -- stands in for the client's spell data), keep only the trinket inputs
    -- wanted, and build: the X1 row is the two trinket icons.
    for i = 1, 11 do
        slots[i].spell = 35395
    end
    local spell_keys = { "snd", "rupture", "ea", "ar", "bf", "tea", "kick",
        "kidney", "restealth", "bandage", "coldblood" }
    for i = 1, #spell_keys do
        class_db["hud_show_" .. spell_keys[i]] = false
    end
    clock = 900
    item_ids[13] = 28830
    item_textures[13] = "tex_dst"
    item_ids[14] = 29383
    item_textures[14] = "tex_brooch"
    RHUD.init(RST)
    check(RHUD.frame ~= nil, "rogue: the HUD builds")
    eq(#RHUD.icons, 13, "rogue: all thirteen valid slots build an icon")
    eq(RHUD.icons[12].show_key, "hud_show_trinket1",
        "rogue: the trinket toggle key is derived")
    eq(RHUD.frame.width, 2 * 36 + 2, "rogue: the row sizes to the two trinket slots")

    -- The provider reports nothing for the HUD-served slots: the cleared table,
    -- never an invented state (the X1 never-guess rule at the provider level).
    local s = RST.ROGUE.get_hud_state(RST, by_key.trinket1, clock)
    eq(s.remaining, nil, "rogue: the provider reports no trinket remaining")
    eq(s.duration, nil, "rogue: the provider reports no trinket duration")
    eq(s.hidden, nil, "rogue: the provider does not hide the trinket slot")
    eq(s.texture, nil, "rogue: the provider reports no trinket texture")

    -- Unknown-duration discipline through the rogue row: an item with no icd
    -- entry stamps nothing on the proc landing and reads idle (hide, no swipe).
    local t14 = RHUD.trinkets[14]
    eq(t14.icd, nil, "rogue: the unknown item carries no ICD length")
    RHUD.on_aura_applied(RST, "Player-1", 35166, clock)
    eq(t14.icd_expires, nil, "rogue: no icd entry -> the CLEU application stamps nothing")
    s = RHUD.trinket_state(RST, by_key.trinket2, clock)
    eq(s.remaining, nil, "rogue: the unknown ICD reads idle (no countdown)")
    eq(s.duration, nil, "rogue: the unknown ICD carries no swipe")
    item_ids[14] = nil
    RHUD.read_trinket(14)
    eq(RHUD.icon_should_show(RST, RHUD.icons[13], false), false,
        "rogue: an emptied trinket slot hides again")
end

--=========================================================================================
-- H2/M1/M2: hunter-proctor-fixes pins (hud.lua + ldb.lua)
--=========================================================================================
do
    -- H2: secret-hole - a proc buff above a nil row is still detected, and the
    -- walk stays capped at 40 rows.
    local b = build()
    local bHUD, bST = b.st.hud, b.ST
    bHUD.init(bST)
    local tslot = nil
    for i = 1, #bST.PALADIN.HUD_SLOTS do
        if bST.PALADIN.HUD_SLOTS[i].key == "trinket1" then
            tslot = bST.PALADIN.HUD_SLOTS[i]
        end
    end
    check(tslot ~= nil, "H2: the trinket1 descriptor exists")
    item_ids[13] = 28830
    item_textures[13] = "tex_dst"
    bHUD.read_trinket(13)
    clock = 400
    aura_list = {}
    aura_list[3] = { name = "Lust for Battle", duration = 10,
        expiration = clock + 8, spell_id = 34775 }
    local s = bHUD.trinket_state(bST, tslot, clock)
    near(s.remaining, 8, 1e-9, "H2: a proc above a nil row is still detected")
    eq(s.duration, 10, "H2: the proc duration survives the hole")
    -- Cap: an empty list still walks the full 40-row cap (no early break).
    aura_list = {}
    local aura_calls = 0
    local real_unit_aura = b.env.UnitAura
    b.env.UnitAura = function(unit, index, filter)
        aura_calls = aura_calls + 1
        return real_unit_aura(unit, index, filter)
    end
    bHUD.trinket_state(bST, tslot, clock)
    b.env.UnitAura = real_unit_aura
    eq(aura_calls, 40, "H2: the scan walks the full 40-row cap")
end

do
    -- M1: a throwing CLEU registration is counted and chats exactly once.
    local b = build()
    local bHUD, bST = b.st.hud, b.ST
    bHUD.init(bST)
    eq(bHUD.cleu_register_errors, 0, "M1: a clean registration records no error")
    local notices = {}
    b.st.utils.print_msg = function(msg) notices[#notices + 1] = msg end
    bHUD.event_frame = nil
    local real_create = b.env.CreateFrame
    b.env.CreateFrame = function(...)
        local f = real_create(...)
        local real_register = f.RegisterEvent
        f.RegisterEvent = function(self, event)
            if event == "COMBAT_LOG_EVENT_UNFILTERED" then
                error("M1 probe throw")
            end
            return real_register(self, event)
        end
        return f
    end
    bHUD.build_event_frame()
    eq(bHUD.cleu_register_errors, 1, "M1: a failed CLEU registration is counted")
    eq(#notices, 1, "M1: the failure chats once")
    check((notices[1] or ""):find("trinket internal cooldowns", 1, true) ~= nil,
        "M1: the notice names the degraded feed")
    bHUD.event_frame = nil
    bHUD.build_event_frame()
    b.env.CreateFrame = real_create
    eq(bHUD.cleu_register_errors, 2, "M1: every failure counts")
    eq(#notices, 1, "M1: the notice stays one-time")
end

do
    -- M2: no swing state publishes the "--" sentinel (ldb.lua; no ldb_state file
    -- ships, so the pin lives here per the dispatch).
    local broker_obj = nil
    local broker = {
        NewDataObject = function(_, name, obj) broker_obj = obj return obj end,
        GetDataObjectByName = function() return broker_obj end,
    }
    local real_libstub = main.env.LibStub
    main.env.LibStub = function(major, silent)
        if major == "LibDataBroker-1.1" then return broker end
        return real_libstub(major, silent)
    end
    local chunk = assert(loadfile(ROOT .. "ldb.lua"))
    setfenv(chunk, main.env)
    chunk("SwedgeTimer", main.st)
    main.env.LibStub = real_libstub
    local ldb = main.st.ldb
    check(ldb ~= nil and type(ldb.update) == "function", "M2: ldb.lua loads over the hud sandbox")
    clock = 500
    ST.mainhand = { speed = 2.6, ends_at = clock + 2.6 }
    ldb.update(ST, "mainhand")
    check(broker_obj ~= nil, "M2: the first tick creates the data object")
    eq(broker_obj.value, "2.60", "M2: live swing publishes the remaining")
    -- Swing gone: the stale number is replaced, not left up.
    ST.mainhand = nil
    clock = clock + 1
    ldb.update(ST, "mainhand")
    eq(broker_obj.value, "--", "M2: no swing state publishes the sentinel")
    eq(ldb.last_value, "--", "M2: the sentinel updates the write cache")
    -- A second stateless tick republishes nothing new (the sentinel is stable).
    clock = clock + 1
    ldb.update(ST, "mainhand")
    eq(broker_obj.value, "--", "M2: the sentinel is stable across ticks")
    -- Live swing returns: the sentinel is replaced by the new remaining.
    clock = clock + 1
    ST.mainhand = { speed = 2.6, ends_at = clock + 2.6 }
    ldb.update(ST, "mainhand")
    eq(broker_obj.value, "2.60", "M2: live swing replaces the sentinel")
end

--=========================================================================================
-- 20) Trinket usable-only gate (operator order): on-use/proc show, passive/unknown hide
--=========================================================================================
do
    local u = build()
    local uHUD, uST = u.st.hud, u.ST
    uHUD.init(uST)
    local tslot = nil
    for i = 1, #uST.PALADIN.HUD_SLOTS do
        if uST.PALADIN.HUD_SLOTS[i].key == "trinket1" then
            tslot = uST.PALADIN.HUD_SLOTS[i]
        end
    end
    check(tslot ~= nil, "usable gate: the trinket1 descriptor exists")
    check(type(uHUD.trinket_usable) == "function", "usable gate: the helper ships")
    clock = 1000
    -- Known proc shows (TRINKET_DATA buff, no on-use cooldown).
    item_ids[13] = 28830
    item_textures[13] = "tex_dst"
    item_cooldowns[13] = nil
    aura_list = {}
    uHUD.read_trinket(13)
    eq(uHUD.trinket_usable(uHUD.trinkets[13], 13), true, "usable gate: a known proc is usable")
    eq(uHUD.icon_should_show(uST, uHUD.icons[5], false), true, "usable gate: a known proc shows")
    local s = uHUD.trinket_state(uST, tslot, clock)
    eq(s.hidden, nil, "usable gate: a known proc is not hidden")
    -- Live proc shows with its swipe.
    aura_list = { { name = "Lust for Battle", duration = 10, expiration = clock + 8, spell_id = 34775 } }
    s = uHUD.trinket_state(uST, tslot, clock)
    near(s.remaining, 8, 1e-9, "usable gate: a live proc counts down")
    eq(s.hidden, nil, "usable gate: a live proc is not hidden")
    aura_list = {}
    -- On-use shows via the live enable flag (unknown id, never guessed from the table).
    item_ids[13] = 99999
    item_textures[13] = "tex_use"
    item_cooldowns[13] = { start = 0, duration = 0, enable = 1 }
    uHUD.read_trinket(13)
    eq(uHUD.trinket_usable(uHUD.trinkets[13], 13), true, "usable gate: a ready on-use is usable")
    eq(uHUD.icon_should_show(uST, uHUD.icons[5], false), true, "usable gate: a ready on-use shows")
    s = uHUD.trinket_state(uST, tslot, clock)
    eq(s.hidden, nil, "usable gate: a ready on-use is not hidden")
    eq(s.remaining, nil, "usable gate: a ready on-use reads idle (no swipe)")
    -- On-use on cooldown shows with its swipe.
    item_cooldowns[13] = { start = clock - 5, duration = 120, enable = 1 }
    s = uHUD.trinket_state(uST, tslot, clock)
    near(s.remaining, 115, 1e-9, "usable gate: an on-use cooldown is counted")
    eq(s.hidden, nil, "usable gate: an on-use cooldown is not hidden")
    -- Passive stat stick hides (unknown id, disabled cooldown, no buff).
    item_ids[13] = 77777
    item_textures[13] = "tex_stat"
    item_cooldowns[13] = nil
    uHUD.read_trinket(13)
    eq(uHUD.trinket_usable(uHUD.trinkets[13], 13), false, "usable gate: a passive stat stick is not usable")
    eq(uHUD.icon_should_show(uST, uHUD.icons[5], false), false, "usable gate: a passive stat stick hides")
    s = uHUD.trinket_state(uST, tslot, clock)
    eq(s.hidden, true, "usable gate: a passive stat stick reports hidden")
    -- Unknown effect hides too (never guess): a different unknown id, same shape.
    item_ids[13] = 88888
    item_textures[13] = "tex_unknown"
    item_cooldowns[13] = nil
    aura_list = { { name = "Something Else", duration = 10, expiration = clock + 8, spell_id = 99999 } }
    uHUD.read_trinket(13)
    eq(uHUD.trinket_usable(uHUD.trinkets[13], 13), false, "usable gate: an unknown effect is not usable")
    eq(uHUD.icon_should_show(uST, uHUD.icons[5], false), false, "usable gate: an unknown effect hides")
    s = uHUD.trinket_state(uST, tslot, clock)
    eq(s.hidden, true, "usable gate: an unknown effect reports hidden")
    aura_list = {}
    -- Empty hides (nil-safe, no item).
    item_ids[13] = nil
    uHUD.read_trinket(13)
    eq(uHUD.trinket_usable(uHUD.trinkets[13], 13), false, "usable gate: an empty slot is not usable")
    eq(uHUD.icon_should_show(uST, uHUD.icons[5], false), false, "usable gate: an empty slot hides")
end

--=========================================================================================
-- N2: per-icon isolation - a throwing provider costs only its own icon, never the row.
-- First throw prints once, every throw counts in ST.bar_hook_errors (the /st diag
-- counter), the site quarantines after 25. Degrade hides the failed icon.
--=========================================================================================
do
    local b = build()
    local bST, bHUD = b.ST, b.st.hud
    bHUD.init(bST)
    local notices = {}
    bST.Print = function(_, msg) notices[#notices + 1] = tostring(msg) end
    local real = bST.PALADIN.get_hud_state
    bST.PALADIN.get_hud_state = function(self2, slot2, now2)
        if slot2.key == "cs" then error("N2 probe throw") end
        return real(self2, slot2, now2)
    end
    clock = 600
    bST.gcd = {}
    local ok, err = pcall(bHUD.update_display, bST)
    check(ok, "N2: a throwing slot does not break the row (" .. tostring(err) .. ")")
    eq(bST.bar_hook_errors.count, 1, "N2: the throw is counted")
    eq(bST.bar_hook_errors.by_site["hud:cs"], 1, "N2: the counter is attributed per slot")
    eq(#notices, 1, "N2: the first throw prints exactly one chat line")
    check((notices[1] or ""):find("hud:cs", 1, true) ~= nil, "N2: the notice names the failed slot")
    check(not bHUD.icons[1]:IsShown(), "N2: the failed icon hides, never stale")
    check(bHUD.icons[2]:IsShown(), "N2: the rest of the row still paints")
    for _ = 1, 3 do bHUD.update_display(bST) end
    eq(bST.bar_hook_errors.by_site["hud:cs"], 4, "N2: every throw keeps counting")
    eq(#notices, 1, "N2: repeated throws do not spam chat")
    for _ = 5, 25 do bHUD.update_display(bST) end
    eq(bST.bar_hook_errors.by_site["hud:cs"], 25, "N2: the site reaches the quarantine threshold")
    eq(bST.bar_hook_errors.quarantined["hud:cs"], true, "N2: the site is quarantined for the session")
    check((notices[#notices] or ""):find("quarantined for this session", 1, true) ~= nil,
        "N2: the quarantine is announced, never silent")
    local counted = bST.bar_hook_errors.count
    bHUD.update_display(bST)
    eq(bST.bar_hook_errors.count, counted, "N2: a quarantined slot is not called again")
    eq(bST.bar_hook_errors.by_site["hud:cs"], 25, "N2: a quarantined slot does not keep counting")
    bST.PALADIN.get_hud_state = real
end

--=========================================================================================
-- 21) SoD live crash: FontString:SetText(): Font not set (hud.lua create_icon).
-- The SoD client throws when SetText runs before any SetFont; the stub above is
-- SoD-faithful (SetText without a font errors, SetFont(nil) latches nothing).
-- The fix sets a real font BEFORE the first SetText at creation, then
-- apply_settings re-applies the LSM/db font (the single restyle path). The
-- fallback chain is LSM font -> STANDARD_TEXT_FONT -> the classic client font,
-- pcall-guarded so a missing LSM / throwing Fetch / missing STANDARD never
-- throws out of the HUD build.
--=========================================================================================
do
    -- Strict creation: the fixed build carries a font on every icon, so the
    -- SoD-faithful SetText never throws. A font-stripped create_icon mutant
    -- (no apply_font before SetText) dies here on the first icon.
    local s = build()
    local ok_init, err_init = pcall(s.st.hud.init, s.ST)
    check(ok_init, "SoD font: HUD.init never throws (" .. tostring(err_init) .. ")")
    check(s.st.hud.frame ~= nil, "SoD font: the HUD still builds")
    local all_have_font = true
    for i = 1, #s.st.hud.icons do
        if s.st.hud.icons[i].text:GetFont() == nil then
            all_have_font = false
        end
    end
    check(all_have_font, "SoD font: every icon carries a font after creation")
    local ok_tick, err_tick = pcall(s.st.hud.update_display, s.ST)
    check(ok_tick, "SoD font: the first paint never throws (" .. tostring(err_tick) .. ")")

    -- LSM Fetch nil: the STANDARD fallback carries the row, never throws.
    local n = build({ lsm_font_nil = true })
    local ok_n, err_n = pcall(n.st.hud.init, n.ST)
    check(ok_n, "SoD font: a nil LSM font never throws (" .. tostring(err_n) .. ")")
    local got_n = n.st.hud.icons[1] and n.st.hud.icons[1].text
        and n.st.hud.icons[1].text:GetFont() or nil
    eq(got_n, "Fonts\\FRIZQT__.TTF",
        "SoD font: a nil LSM font falls back to STANDARD_TEXT_FONT")

    -- STANDARD missing: the classic literal carries the row, never throws.
    local m = build({ no_std_font = true })
    local ok_m, err_m = pcall(m.st.hud.init, m.ST)
    check(ok_m, "SoD font: a missing STANDARD_TEXT_FONT never throws (" .. tostring(err_m) .. ")")
    local got_m = m.st.hud.icons[1] and m.st.hud.icons[1].text
        and m.st.hud.icons[1].text:GetFont() or nil
    check(got_m ~= nil,
        "SoD font: a missing STANDARD still leaves a font latched")
    eq(got_m, "Fonts\\FRIZQT__.TTF",
        "SoD font: a missing STANDARD falls back to the classic client font")

    -- Both missing: the literal still carries the row, never throws.
    local b2 = build({ lsm_font_nil = true, no_std_font = true })
    local ok_b2, err_b2 = pcall(b2.st.hud.init, b2.ST)
    check(ok_b2, "SoD font: nil LSM + nil STANDARD never throws (" .. tostring(err_b2) .. ")")
    local got_b2 = b2.st.hud.icons[1] and b2.st.hud.icons[1].text
        and b2.st.hud.icons[1].text:GetFont() or nil
    eq(got_b2, "Fonts\\FRIZQT__.TTF",
        "SoD font: nil LSM + nil STANDARD still latches the literal")

    -- Throwing Fetch: pcall-guarded, falls back, never throws.
    local t = build({ lsm_throw = true })
    local ok_t, err_t = pcall(t.st.hud.init, t.ST)
    check(ok_t, "SoD font: a throwing LSM Fetch never throws (" .. tostring(err_t) .. ")")
    local got_t = t.st.hud.icons[1] and t.st.hud.icons[1].text
        and t.st.hud.icons[1].text:GetFont() or nil
    check(got_t ~= nil,
        "SoD font: a throwing Fetch still leaves a font latched")

    -- Missing LSM lib: type-guarded, falls back, never throws.
    local l = build({ no_lsm = true })
    local ok_l, err_l = pcall(l.st.hud.init, l.ST)
    check(ok_l, "SoD font: a missing LSM lib never throws (" .. tostring(err_l) .. ")")
    local got_l = l.st.hud.icons[1] and l.st.hud.icons[1].text
        and l.st.hud.icons[1].text:GetFont() or nil
    check(got_l ~= nil,
        "SoD font: a missing LSM lib still leaves a font latched")

    -- Single restyle path: creation fonts through apply_font before the first
    -- SetText, and apply_settings re-applies through the same helper.
    local function read(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text
    end
    local hud_src = read("hud.lua")
    local apos = hud_src:find("apply_font(f.text", 1, true)
    local tpos = hud_src:find('f.text:SetText("")', 1, true)
    check(apos ~= nil and tpos ~= nil and apos < tpos,
        "SoD font: creation fonts through apply_font before the first SetText")
    check(hud_src:find("apply_font(icon.text, db)", 1, true) ~= nil,
        "SoD font: apply_settings re-applies through the same helper")
    local setfont_uses = 0
    local from = 1
    while true do
        local at = hud_src:find("pcall(text.SetFont", from, true)
        if not at then break end
        setfont_uses = setfont_uses + 1
        from = at + 1
    end
    eq(setfont_uses, 2, "SoD font: exactly two guarded SetFont sites, both inside apply_font")
    check(hud_src:find("text:SetFont", 1, true) == nil,
        "SoD font: no unguarded SetFont call survives outside pcall")
end

--=========================================================================================
-- 22) F10: the HUD's per-icon isolation is the shared guard (one implementation)
--=========================================================================================
do
    local function read_file(path)
        local f = io.open(ROOT .. path, "r")
        local text = f and f:read("*a") or nil
        if f then f:close() end
        return text
    end
    local hud_src = read_file("hud.lua")
    check(hud_src ~= nil, "hud.lua is readable")
    check(hud_src:find("st.guard.run", 1, true) ~= nil,
        "the HUD isolates a throwing provider through the shared guard")
    check(hud_src:find("QUARANTINE_THROWS = ", 1, true) == nil,
        "the HUD keeps no second quarantine threshold")
    check(hud_src:find("errors.by_site", 1, true) == nil,
        "the HUD keeps no second counter bookkeeping")
    check(hud_src:find('st.guard.label("hud", "HUD")', 1, true) ~= nil,
        "the HUD wording stays at the call site")
    check(hud_src:find("HUD error in ", 1, true) == nil,
        "the HUD wording lives in the shared module's parameter, not in a second copy")
end

if failures == 0 then
    print("PASS  hud_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  hud_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end

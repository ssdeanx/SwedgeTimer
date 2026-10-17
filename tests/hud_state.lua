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
    -- Hunter HUD slots.
    [56641] = { name = "Steady Shot", icon = "icon_steady" },
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
    function f:SetFont(path, size, flags) f.font = { path, size, flags }; return true end
    function f:GetFont() return f.font and f.font[1] or nil end
    function f:SetText(text) f.text = text end
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
    known_spells = { [35395] = true }
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
    env.WOW_PROJECT_ID = 5
    env.WOW_PROJECT_CLASSIC = 2
    env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
    env.WOW_PROJECT_WRATH_CLASSIC = 11
    env.WOW_PROJECT_MAINLINE = 1
    env.GetTimePreciseSec = function() return clock end
    env.GetTime = function() return clock end
    env.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"
    env.GetLocale = function() return "enUS" end
    env.GetBuildInfo = function() return "0.0.0", "00000", "today", 20506 end
    env.UIParent = make_frame("UIParent")
    env.UIParent.GetCenter = function() return 0, 0 end
    env.CreateFrame = function(...)
        created_frames = created_frames + 1
        return make_frame(select(2, ...))
    end
    env.GetSpellInfo = function(spell)
        local info = SPELL_INFOS[spell]
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
    env.IsSpellKnown = function(spell) return known_spells[spell] == true end
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
    function LSM.Fetch(_, mediatype)
        if mediatype == "font" then return "Fonts\\FRIZQT__.TTF" end
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

    local st = {}
    local modules = { "compat.lua", "utils.lua", "nextaction.lua", "hud.lua", "classes/paladin.lua" }
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
eq(#paladin_slots, 7, "the paladin declares seven HUD slots (archive set + trinkets + wings)")
local expected_keys = { "cs", "judgement", "consecration", "exorcism", "trinket1", "trinket2", "wings" }
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
eq(#HUD.icons, 7, "all seven valid slots build an icon")
eq(created_frames, frames_before + 31,
    "exactly the HUD frame, the icon children, the event frame and the driver are created")

--=========================================================================================
-- 3) Construction, layout and the option-driven re-flow
--=========================================================================================
local icon_cs = HUD.icons[1]
eq(icon_cs.slot.key, "cs", "the icons follow the descriptor order")
eq(icon_cs.texture.texture, "icon_cs", "the icon shows the spell's texture")
eq(icon_cs.show_key, "hud_show_cs", "the per-slot toggle key is derived once")
check(HUD.frame.shown, "an enabled HUD shows")
-- the two empty trinket slots are hidden, so five icons form the row
eq(HUD.frame.width, 5 * 36 + 4 * 2, "the row is sized to the shown icons plus spacing")
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
eq(HUD.frame.width, 5 * 40 + 4 * 2, "the new icon size re-flows the row")
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
        "hud_show_exorcism", "hud_show_trinket1", "hud_show_trinket2", "hud_show_wings" }
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

    cooldowns[35395] = { start = clock - 3, duration = 6 }
    local s = ST.PALADIN.get_hud_state(ST, slot_by_key.cs, clock)
    near(s.remaining, 3, 1e-9, "CS remaining comes from the client cooldown")
    eq(s.duration, 6, "CS carries its full cooldown")
    eq(s.desaturate, true, "an on-cooldown CS greys out")
    near(s.text_remaining, 3, 1e-9, "the cooldown text is the remaining time")

    -- the GCD echo: the real cooldown is remembered (the guide's latch) and the
    -- shorter echo only caps what is still shown
    cooldowns[35395] = { start = clock, duration = 1.3 }
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.cs, clock)
    near(s.remaining, 1.3, 1e-9, "a GCD echo caps the latched CS cooldown")

    -- unknown CS (no talent): nothing to count, and the GCD swipe takes over
    cooldowns[35395] = nil
    known_spells[35395] = false
    ST.gcd = { expires = clock + 1.2, spell_length = 1.5 }
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.cs, clock)
    near(s.remaining, 1.2, 1e-9, "an unknown CS falls through to the GCD swipe")
    eq(s.duration, 1.5, "the GCD swipe carries the GCD length")
    known_spells[35395] = true

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
    cooldowns[31884] = { start = clock, duration = 1.3 }
    s = ST.PALADIN.get_hud_state(ST, slot_by_key.wings, clock)
    eq(s.remaining, nil, "a GCD echo on Wings is ignored")
    cooldowns[31884] = { start = clock - 10, duration = 180 }
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
    check(shared:find("hud_enabled%s*=%s*false") ~= nil, "the HUD ships off by default")
    check(shared:find("hud_locked%s*=%s*true") ~= nil, "the HUD ships locked by default")

    local paladin_defaults = presets:match("ST%.PALADIN%.defaults%s*=%s*%{(.-)ST%.PRIEST%.defaults")
    check(paladin_defaults ~= nil, "the PALADIN defaults block is found")
    paladin_defaults = paladin_defaults or ""
    local slot_keys = { "hud_show_cs", "hud_show_judgement", "hud_show_consecration",
        "hud_show_exorcism", "hud_show_trinket1", "hud_show_trinket2", "hud_show_wings" }
    for i = 1, #slot_keys do
        check(paladin_defaults:find("%f[%a_]" .. slot_keys[i] .. "%s*=%s*true") ~= nil,
            slot_keys[i] .. " ships true in the PALADIN defaults")
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
        hud_show_wings = "toggle",
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
do
    local h = build({ class = "HUNTER" })
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
    eq(slots[3].spell, 34026, "hunter: Kill Command keeps the module's id")
    eq(by_key.aimed.spell, 19434, "hunter: Aimed Shot ships the rank-1 id")
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

    -- the HUD aimed icon rank-resolves through the guide's pattern: the client
    -- knows the rank-6 20904 here, so the descriptor is re-pointed at it while the
    -- name-based provider keeps counting the same localized spell.
    HST.HUNTER.resolve_guide_icons()
    eq(by_key.aimed.spell, 20904,
        "hunter: the HUD aimed icon resolves to the client's current rank")
    clock = 500
    cooldowns["Aimed Shot"] = { start = clock - 2, duration = 6 }
    HST.gcd = {}
    s = HST.HUNTER.get_hud_state(HST, by_key.aimed, clock)
    near(s.remaining, 4, 1e-9, "hunter: the re-pointed Aimed still reads by name")
    cooldowns["Aimed Shot"] = nil
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
    eq(#slots, 8, "warrior: the TBC set is six ability slots plus the two trinkets")
    local expected = { "op", "execute", "slam", "hs", "bt", "ww", "trinket1", "trinket2" }
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

    WHUD.init(WST)
    check(WHUD.frame ~= nil, "warrior: the HUD builds")
    eq(#WHUD.icons, 8, "warrior: all eight valid slots build an icon")
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
    eq(#slots, 8, "druid: six ability slots plus the two trinket slots")
    local expected = { "maul", "mangle", "rip", "rake", "bite", "shred",
        "trinket1", "trinket2" }
    local by_key, keys_ok, desc_ok = {}, true, true
    for i = 1, #slots do
        by_key[slots[i].key] = slots[i]
        if slots[i].key ~= expected[i] then keys_ok = false end
        if not DHUD.validate_slot(slots[i], true) then desc_ok = false end
    end
    check(keys_ok, "druid: the slot order follows the guide's")
    check(desc_ok, "druid: every descriptor passes the contract")
    eq(slots[1].spell, 6807, "druid: Maul keeps the module's rank-1 id")

    DHUD.init(DST)
    check(DHUD.frame ~= nil, "druid: the HUD builds")
    eq(#DHUD.icons, 8, "druid: all eight valid slots build an icon")
    eq(DHUD.frame.width, 6 * 36 + 5 * 2, "druid: the row sizes to the six shown slots")

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
    eq(#slots, 8, "shaman: six ability slots plus the two trinket slots")
    local expected = { "stormstrike", "flameshock", "weave", "firenova",
        "earthshock", "twist", "trinket1", "trinket2" }
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
    eq(#MHUD.icons, 8, "shaman: all eight valid slots build an icon")
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

    local wired = { "hunter", "warrior", "druid", "shaman" }
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

if failures == 0 then
    print("PASS  hud_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  hud_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end

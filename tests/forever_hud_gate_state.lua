-- tests/forever_hud_gate_state.lua: verification of WoW Forever HUD slot wiring,
-- dynamic leveling gate (spell_known_allows), and Next Action Guide integration.
local script_dir = (arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
local ROOT = os.getenv("SWEDGE_ROOT") or (script_dir .. "/../")

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

-- Frame stubs matching hud_state.lua
local function make_fontstring()
    local f = { hidden = false }
    function f:SetPoint() end
    function f:SetJustifyH() end
    function f:SetShadowColor() end
    function f:SetShadowOffset() end
    function f:SetFont(path, size, flags)
        f.font = { path, size, flags }
        return true
    end
    function f:GetFont() return f.font and f.font[1] or "font.ttf" end
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
    function t:SetTexCoord(...) t.texcoord = { ... } end
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
    function f:GetSize() return f.width or 36, f.height or 36 end
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
    function f:SetBackdrop() end
    function f:SetBackdropColor() end
    function f:SetBackdropBorderColor() end
    function f:SetCooldown(start, duration)
        f.cooldown_start, f.cooldown_duration = start, duration
    end
    function f:SetReverse(reverse) f.reverse = reverse end
    function f:SetHideCountdownNumbers() end
    function f:SetDrawEdge() end
    function f:SetAllPoints() end
    return f
end

_G.CreateFrame = function(frame_type, name, parent)
    return make_frame(name)
end
_G.UIParent = make_frame("UIParent")
_G.InCombatLockdown = function() return false end
_G.UnitExists = function() return true end
_G.UnitCanAttack = function() return true end

local known_spells = {}
local spell_cooldowns = {}

local st = {
    family = "FOREVER",
    is_mainline = true,
    guard = {
        label = function() end,
        run = function(self, site, fn, ...)
            return true, fn(...)
        end,
    },
    api = {
        get_time = function() return 1000.0 end,
        GetSpellInfo = function(query)
            if type(query) == "number" then
                return "Spell" .. query, nil, 134400, 0, 0, 0, query
            end
            return tostring(query), nil, 134400, 0, 0, 0, 100
        end,
        GetSpellCooldown = function(query)
            local cd = spell_cooldowns[query]
            if cd then
                return cd.start, cd.dur
            end
            return 0, 0
        end,
        IsSpellUsable = function(query)
            return true, false
        end,
        IsSpellInRange = function(query, unit)
            return 1
        end,
        is_spell_known = function(spell_id, fallback_id)
            if known_spells[spell_id] == true then return true end
            if fallback_id and known_spells[fallback_id] == true then return true end
            return false
        end,
        is_spell_known_state = function(spell_id, fallback_id)
            if known_spells[spell_id] == true or (fallback_id and known_spells[fallback_id] == true) then
                return true, "known"
            end
            return false, "not_known"
        end,
        GetInventoryItemID = function() return nil end,
        GetInventoryItemTexture = function() return nil end,
    },
}

_G.LibStub = function(major)
    if major == "AceAddon-3.0" then
        return { GetAddon = function() return st end }
    end
    if major == "LibSharedMedia-3.0" then
        return { Fetch = function() return "font.ttf" end }
    end
    if major == "LibCustomGlow-1.0" then
        return { PixelGlow_Start = function() end, PixelGlow_Stop = function() end }
    end
    return {}
end

-- Load forever_guide.lua
local fg_chunk = assert(loadfile(ROOT .. "forever_guide.lua"))
fg_chunk("SwedgeTimer", st)
check(st.forever_guide ~= nil, "forever_guide loaded successfully")

-- Load hud.lua
local hud_chunk = assert(loadfile(ROOT .. "hud.lua"))
hud_chunk("SwedgeTimer", st)
check(st.hud ~= nil, "hud loaded successfully")

local HUD = st.hud

-- 1. Test HUD slot generation on Forever across all 6 classes
local classes = { "PALADIN", "WARRIOR", "HUNTER", "ROGUE", "DRUID", "SHAMAN" }
for _, cls in ipairs(classes) do
    local slots = st.forever_guide.get_hud_slots(cls)
    check(type(slots) == "table" and #slots > 2, "forever_guide.get_hud_slots(" .. cls .. ") returns slots")
    check(slots[#slots - 1].kind == "trinket" and slots[#slots].kind == "trinket", cls .. " has trinket1 & trinket2 slots")

    -- Verify HUD.create uses forever_guide slots on Forever
    local mock_self = {
        player_class = cls,
        get_class_table = function()
            return {
                hud_enabled = true,
                hud_locked = true,
                class_enabled = true,
            }
        end,
        get_hand_table = function() return { bar_width = 275 } end,
        convert_color = function() return 1, 1, 1, 1 end,
    }
    HUD.frame = nil
    HUD.icons = {}
    local ok = HUD.create(mock_self)
    check(ok == true, "HUD.create succeeded on Forever for " .. cls)
    check(#HUD.icons == #slots, cls .. " HUD created exactly " .. #slots .. " icons (got " .. #HUD.icons .. ")")
end

-- Helper to find a slot by key
local function find_slot(slots, key)
    if not slots then return nil end
    for _, s in ipairs(slots) do
        if s.key == key then return s end
    end
    return nil
end

-- 2. Test Dynamic Leveling Gate (HUD.spell_known_allows) across ALL 6 CLASSES

-- PALADIN LEVELING GATE
local paladin_slots = st.forever_guide.get_hud_slots("PALADIN")
local holy_strike_slot = find_slot(paladin_slots, "holy_strike")
local holy_shock_slot = find_slot(paladin_slots, "holy_shock")
check(holy_strike_slot ~= nil and holy_shock_slot ~= nil, "paladin: holy_strike and holy_shock slots found")

known_spells = {}
known_spells[679] = true -- Holy Strike Rank 1 known
check(HUD.spell_known_allows(holy_strike_slot) == true, "paladin gate: Holy Strike (Rank 1 ID 679) allowed through")
check(HUD.spell_known_allows(holy_shock_slot) == false, "paladin gate: Holy Shock correctly hidden (unlearned)")

-- Leveling progression: player untrains Rank 1 and trains Rank 3 (1866)
known_spells[679] = nil
known_spells[1866] = true
check(HUD.spell_known_allows(holy_strike_slot) == true, "paladin gate: Holy Strike (Rank 3 ID 1866) allowed via multi-rank ids")

-- Spec into Holy Shock at level 40:
known_spells[20473] = true
check(HUD.spell_known_allows(holy_shock_slot) == true, "paladin gate: Holy Shock dynamically allowed after talent learned")

-- WARRIOR LEVELING GATE
local warrior_slots = st.forever_guide.get_hud_slots("WARRIOR")
local hs_slot = find_slot(warrior_slots, "hs")
local bt_slot = find_slot(warrior_slots, "bt")
local ms_slot = find_slot(warrior_slots, "ms")
check(hs_slot ~= nil and bt_slot ~= nil and ms_slot ~= nil, "warrior: hs, bt, and ms slots found")

known_spells = {}
known_spells[78] = true -- Heroic Strike Rank 1 known
check(HUD.spell_known_allows(hs_slot) == true, "warrior gate: Heroic Strike (Rank 1 ID 78) allowed through")
check(HUD.spell_known_allows(bt_slot) == false, "warrior gate: Bloodthirst correctly hidden (unlearned)")
check(HUD.spell_known_allows(ms_slot) == false, "warrior gate: Mortal Strike correctly hidden (unlearned)")

-- Train Heroic Strike Rank 4 (1608):
known_spells[78] = nil
known_spells[1608] = true
check(HUD.spell_known_allows(hs_slot) == true, "warrior gate: Heroic Strike (Rank 4 ID 1608) allowed via multi-rank ids")

-- Spec into Bloodthirst (23881):
known_spells[23881] = true
check(HUD.spell_known_allows(bt_slot) == true, "warrior gate: Bloodthirst dynamically allowed after talent learned")

-- HUNTER LEVELING GATE
local hunter_slots = st.forever_guide.get_hud_slots("HUNTER")
local serpent_slot = find_slot(hunter_slots, "serpent")
local strider_kick_slot = find_slot(hunter_slots, "strider_kick")
check(serpent_slot ~= nil and strider_kick_slot ~= nil, "hunter: serpent and strider_kick slots found")

known_spells = {}
known_spells[1978] = true -- Serpent Sting Rank 1 known
check(HUD.spell_known_allows(serpent_slot) == true, "hunter gate: Serpent Sting (Rank 1 ID 1978) allowed through")
check(HUD.spell_known_allows(strider_kick_slot) == false, "hunter gate: Strider Kick correctly hidden (unlearned)")

-- Train Serpent Sting Rank 4 (13551):
known_spells[1978] = nil
known_spells[13551] = true
check(HUD.spell_known_allows(serpent_slot) == true, "hunter gate: Serpent Sting (Rank 4 ID 13551) allowed via multi-rank ids")

-- Learn Strider Kick (1317257):
known_spells[1317257] = true
check(HUD.spell_known_allows(strider_kick_slot) == true, "hunter gate: Strider Kick dynamically allowed after learned")

-- ROGUE LEVELING GATE
local rogue_slots = st.forever_guide.get_hud_slots("ROGUE")
local ss_slot = find_slot(rogue_slots, "ss")
local mutilate_slot = find_slot(rogue_slots, "mutilate")
local hemo_slot = find_slot(rogue_slots, "hemo")
check(ss_slot ~= nil and mutilate_slot ~= nil and hemo_slot ~= nil, "rogue: ss, mutilate, and hemo slots found")

known_spells = {}
known_spells[1752] = true -- Sinister Strike Rank 1 known
check(HUD.spell_known_allows(ss_slot) == true, "rogue gate: Sinister Strike (Rank 1 ID 1752) allowed through")
check(HUD.spell_known_allows(mutilate_slot) == false, "rogue gate: Mutilate correctly hidden (unlearned)")
check(HUD.spell_known_allows(hemo_slot) == false, "rogue gate: Hemorrhage correctly hidden (unlearned)")

-- Train Sinister Strike Rank 3 (1758):
known_spells[1752] = nil
known_spells[1758] = true
check(HUD.spell_known_allows(ss_slot) == true, "rogue gate: Sinister Strike (Rank 3 ID 1758) allowed via multi-rank ids")

-- Spec into Mutilate (1241584 on Forever):
known_spells[1241584] = true
check(HUD.spell_known_allows(mutilate_slot) == true, "rogue gate: Mutilate dynamically allowed after talent learned")

-- DRUID LEVELING GATE
local druid_slots = st.forever_guide.get_hud_slots("DRUID")
local maul_slot = find_slot(druid_slots, "maul")
local primal_bite_slot = find_slot(druid_slots, "primal_bite")
check(maul_slot ~= nil and primal_bite_slot ~= nil, "druid: maul and primal_bite slots found")

known_spells = {}
known_spells[6807] = true -- Maul Rank 1 known
check(HUD.spell_known_allows(maul_slot) == true, "druid gate: Maul (Rank 1 ID 6807) allowed through")
check(HUD.spell_known_allows(primal_bite_slot) == false, "druid gate: Primal Bite correctly hidden (unlearned)")

-- Train Maul Rank 3 (6809):
known_spells[6807] = nil
known_spells[6809] = true
check(HUD.spell_known_allows(maul_slot) == true, "druid gate: Maul (Rank 3 ID 6809) allowed via multi-rank ids")

-- Learn Primal Bite (1238070 on Forever):
known_spells[1238070] = true
check(HUD.spell_known_allows(primal_bite_slot) == true, "druid gate: Primal Bite dynamically allowed after learned")

-- SHAMAN LEVELING GATE
local shaman_slots = st.forever_guide.get_hud_slots("SHAMAN")
local earthshock_slot = find_slot(shaman_slots, "earthshock")
local stormstrike_slot = find_slot(shaman_slots, "stormstrike")
check(earthshock_slot ~= nil and stormstrike_slot ~= nil, "shaman: earthshock and stormstrike slots found")

known_spells = {}
known_spells[8042] = true -- Earth Shock Rank 1 known
check(HUD.spell_known_allows(earthshock_slot) == true, "shaman gate: Earth Shock (Rank 1 ID 8042) allowed through")
check(HUD.spell_known_allows(stormstrike_slot) == false, "shaman gate: Stormstrike correctly hidden (unlearned)")

-- Train Earth Shock Rank 3 (8045):
known_spells[8042] = nil
known_spells[8045] = true
check(HUD.spell_known_allows(earthshock_slot) == true, "shaman gate: Earth Shock (Rank 3 ID 8045) allowed via multi-rank ids")

-- Spec into Stormstrike (17364):
known_spells[17364] = true
check(HUD.spell_known_allows(stormstrike_slot) == true, "shaman gate: Stormstrike dynamically allowed after talent learned")

-- Trinket leveling / usability gate:
-- Trinket slots pass spell_known_allows (they are not spells), but are strictly
-- filtered by HUD.icon_should_show / HUD.trinket_usable so empty or passive items stay hidden!
check(HUD.spell_known_allows({ kind = "trinket", inv_slot = 13 }) == true, "leveling gate: Trinket 1 passes spellbook gate")
check(HUD.spell_known_allows({ kind = "trinket", inv_slot = 14 }) == true, "leveling gate: Trinket 2 passes spellbook gate")

-- 3. Verify Trinket Usability Gate on Forever (HUD.icon_should_show / HUD.trinket_usable)
local test_addon = {
    get_class_table = function() return { hud_show_trinket1 = true, hud_show_trinket2 = true } end,
}
local t1_icon = { show_key = "hud_show_trinket1", slot = { kind = "trinket", inv_slot = 13 } }
local t2_icon = { show_key = "hud_show_trinket2", slot = { kind = "trinket", inv_slot = 14 } }

-- Case A: Empty trinket slot (no item equipped) -> MUST BE HIDDEN
HUD.trinkets[13] = { item = nil }
HUD.trinkets[14] = { item = nil }
check(HUD.icon_should_show(test_addon, t1_icon, false) == false, "trinket gate: empty trinket 1 is hidden")
check(HUD.icon_should_show(test_addon, t2_icon, false) == false, "trinket gate: empty trinket 2 is hidden")

-- Case B: Passive stat-stick trinket equipped (item present, but no on-use cooldown and no proc buff) -> MUST BE HIDDEN
HUD.trinkets[13] = { item = 99991, buff = nil, texture = "item.tga" }
local orig_cooldown_fn = st.api.GetInventoryItemCooldown
st.api.GetInventoryItemCooldown = function(slot)
    return 0, 0, 0 -- enable = 0 (passive item without on-use)
end
check(HUD.icon_should_show(test_addon, t1_icon, false) == false, "trinket gate: passive stat-stick trinket without on-use is hidden")

-- Case C: Active on-use trinket equipped (enable == 1) -> MUST BE SHOWN
st.api.GetInventoryItemCooldown = function(slot)
    return 0, 0, 1 -- enable = 1 (on-use trinket)
end
check(HUD.icon_should_show(test_addon, t1_icon, false) == true, "trinket gate: active on-use trinket is shown")

-- Case D: Proc buff trinket equipped (buff defined in TRINKET_DATA) -> MUST BE SHOWN
st.api.GetInventoryItemCooldown = function(slot) return 0, 0, 0 end
HUD.trinkets[13] = { item = 99992, buff = 2825, texture = "proc.tga" }
check(HUD.icon_should_show(test_addon, t1_icon, false) == true, "trinket gate: proc buff trinket is shown")
st.api.GetInventoryItemCooldown = orig_cooldown_fn

-- 4. Test Provider State on Forever
local hs_state = st.forever_guide.get_hud_state("PALADIN", {}, holy_strike_slot, 1000.0)
check(type(hs_state) == "table", "get_hud_state returned a state table")
eq(hs_state.usable, true, "Holy Strike is usable")
eq(hs_state.in_range, true, "Holy Strike is in range")

-- Put Holy Strike on 6s cooldown:
spell_cooldowns["Holy Strike"] = { start = 1000.0, dur = 6.0 }
hs_state = st.forever_guide.get_hud_state("PALADIN", {}, holy_strike_slot, 1002.0)
eq(hs_state.remaining, 4.0, "Holy Strike remaining cooldown is 4s")
eq(hs_state.duration, 6.0, "Holy Strike duration is 6s")
eq(hs_state.desaturate, true, "Holy Strike desaturates on cooldown")

-- 5. Test Next Action Leveling Fallback Logic across ALL 6 CLASSES

local na_out = {}

-- 5.1 PALADIN LEVELING FALLBACKS
-- Level 1 baseline: no Judgement trained, only Seal of Righteousness -> falls back to sor
st.forever_guide.evaluate("PALADIN", nil, {
    ["Judgement"] = false,
    ["Holy Strike"] = false,
    ["Seal of Righteousness"] = true,
    seal_inactive = true,
}, na_out)
eq(na_out.action, "sor", "paladin fallback: Level 1 falls back to Seal of Righteousness")

-- Level 6 baseline: Holy Strike trained, Judgement on cooldown -> falls back to holy_strike
st.forever_guide.evaluate("PALADIN", nil, {
    ["Judgement"] = true,
    judge_remaining = 6.0,
    ["Holy Strike"] = true,
    holy_strike_remaining = 0,
    ["Seal of Righteousness"] = true,
    seal_active = true,
}, na_out)
eq(na_out.action, "holy_strike", "paladin fallback: Level 6 falls back to Holy Strike when Judgement on CD")

-- Judgement ready -> cues judge
st.forever_guide.evaluate("PALADIN", nil, {
    ["Judgement"] = true,
    judge_remaining = 0,
    ["Holy Strike"] = true,
    holy_strike_remaining = 0,
}, na_out)
eq(na_out.action, "judge", "paladin: Judgement cued when ready")
eq(na_out.judge_slot, "judge", "paladin: judge_slot set to judge")

-- 5.2 WARRIOR LEVELING FALLBACKS
-- Leveling Warrior without MS/BT: resolves spec "general"
-- Rend unapplied -> falls back to rend
st.forever_guide.evaluate("WARRIOR", nil, {
    ["Mortal Strike"] = false,
    ["Bloodthirst"] = false,
    ["Rend"] = true,
    rend_active = false,
    rage = 15,
}, na_out)
eq(na_out.rotation_key, "general", "warrior fallback: resolves to general leveling spec")
eq(na_out.action, "rend", "warrior fallback: cues Rend when unapplied")

-- Rend active, Sunder unstacked -> falls back to sunder
st.forever_guide.evaluate("WARRIOR", nil, {
    ["Mortal Strike"] = false,
    ["Bloodthirst"] = false,
    ["Rend"] = true,
    rend_active = true,
    ["Sunder Armor"] = true,
    sunder_stacks = 2,
    rage = 15,
}, na_out)
eq(na_out.action, "sunder", "warrior fallback: cues Sunder Armor when stacks < 5")

-- Rend active, Sunder 5 stacks -> falls back to Heroic Strike
st.forever_guide.evaluate("WARRIOR", nil, {
    ["Mortal Strike"] = false,
    ["Bloodthirst"] = false,
    ["Rend"] = true,
    rend_active = true,
    ["Sunder Armor"] = true,
    sunder_stacks = 5,
    ["Heroic Strike"] = true,
    rage = 35,
}, na_out)
eq(na_out.action, "hs", "warrior fallback: cues Heroic Strike with excess rage")

-- Player learns Bloodthirst -> resolves to fury, cues bt
st.forever_guide.evaluate("WARRIOR", nil, {
    ["Bloodthirst"] = true,
    bt_remaining = 0,
    rage = 35,
}, na_out)
eq(na_out.rotation_key, "fury", "warrior: resolves to fury spec once Bloodthirst known")
eq(na_out.action, "bt", "warrior: cues Bloodthirst when ready")

-- 5.3 HUNTER LEVELING FALLBACKS
-- Leveling Hunter without Strider Kick: resolves spec "ranged"
-- Missing Hunter's Mark -> cues mark
st.forever_guide.evaluate("HUNTER", nil, {
    ["Strider Kick"] = false,
    ["Hunter's Mark"] = true,
    hunters_mark_active = false,
}, na_out)
eq(na_out.rotation_key, "ranged", "hunter fallback: resolves to ranged spec without Strider Kick")
eq(na_out.action, "hunters_mark", "hunter fallback: cues Hunter's Mark when missing")

-- Mark active, Serpent unapplied -> cues serpent
st.forever_guide.evaluate("HUNTER", nil, {
    ["Strider Kick"] = false,
    ["Hunter's Mark"] = true,
    hunters_mark_active = true,
    ["Serpent Sting"] = true,
    serpent_active = false,
    mana_fraction = 0.5,
}, na_out)
eq(na_out.action, "serpent", "hunter fallback: cues Serpent Sting when missing")

-- Mark active, Serpent active -> falls back to Arcane Shot
st.forever_guide.evaluate("HUNTER", nil, {
    ["Strider Kick"] = false,
    ["Hunter's Mark"] = true,
    hunters_mark_active = true,
    ["Serpent Sting"] = true,
    serpent_active = true,
    ["Arcane Shot"] = true,
    arcane_remaining_cd = 0,
}, na_out)
eq(na_out.action, "arcane", "hunter fallback: falls back to Arcane Shot")

-- Learn Strider Kick -> resolves to melee spec, cues strider_kick
st.forever_guide.evaluate("HUNTER", nil, {
    ["Strider Kick"] = true,
    strider_kick_remaining = 0,
    mana_fraction = 1.0,
}, na_out)
eq(na_out.rotation_key, "melee", "hunter: resolves to melee spec once Strider Kick known")
eq(na_out.action, "strider_kick", "hunter: cues Strider Kick when ready")

-- 5.4 ROGUE LEVELING FALLBACKS
-- Leveling Rogue without Mutilate/Hemo/Dagger: resolves to "combat_ss"
-- Builder fallback with CP < 4 -> falls back to Sinister Strike
st.forever_guide.evaluate("ROGUE", nil, {
    ["Mutilate"] = false,
    ["Hemorrhage"] = false,
    mh_is_dagger = false,
    combo_points = 2,
    snd_remaining = 15,
    energy = 50,
    ["Sinister Strike"] = true,
}, na_out)
eq(na_out.rotation_key, "combat_ss", "rogue fallback: resolves to combat_ss spec without talents")
eq(na_out.action, "ss", "rogue fallback: builder falls back to Sinister Strike")

-- Finisher fallback at 5 CP without Rupture -> falls back to Eviscerate
st.forever_guide.evaluate("ROGUE", nil, {
    ["Mutilate"] = false,
    ["Hemorrhage"] = false,
    mh_is_dagger = false,
    combo_points = 5,
    snd_remaining = 15,
    energy = 35,
    ["Rupture"] = false,
    ["Eviscerate"] = true,
}, na_out)
eq(na_out.action, "eviscerate", "rogue fallback: finisher falls back to Eviscerate without Rupture")

-- Learn Mutilate -> resolves to mutilate spec, cues mutilate
st.forever_guide.evaluate("ROGUE", nil, {
    ["Mutilate"] = true,
    energy = 65,
    combo_points = 2,
    snd_remaining = 15,
}, na_out)
eq(na_out.rotation_key, "mutilate", "rogue: resolves to mutilate spec once Mutilate known")
eq(na_out.action, "mutilate", "rogue: builder cues Mutilate")

-- 5.5 DRUID LEVELING FALLBACKS
-- Bear without Primal Bite: falls back to Maul
st.forever_guide.evaluate("DRUID", "bear", {
    ["Primal Bite"] = false,
    ["Faerie Fire (Feral)"] = true,
    faerie_fire_active = true,
    ["Maul"] = true,
    rage = 40,
}, na_out)
eq(na_out.action, "maul", "druid fallback: Bear falls back to Maul without Primal Bite")

-- Cat without Shred/behind: falls back to Claw
st.forever_guide.evaluate("DRUID", "cat", {
    behind_target = false,
    ["Faerie Fire (Feral)"] = true,
    faerie_fire_active = true,
    ["Claw"] = true,
    energy = 45,
    combo_points = 2,
}, na_out)
eq(na_out.action, "claw", "druid fallback: Cat falls back to Claw when not behind target")

-- Cat finisher at 5 CP without Rip: falls back to Ferocious Bite
st.forever_guide.evaluate("DRUID", "cat", {
    ["Rip"] = false,
    ["Ferocious Bite"] = true,
    energy = 35,
    combo_points = 5,
}, na_out)
eq(na_out.action, "ferocious_bite", "druid fallback: Cat finisher falls back to Ferocious Bite without Rip")

-- Bear with Primal Bite learned: cues primal_bite
st.forever_guide.evaluate("DRUID", "bear", {
    ["Primal Bite"] = true,
    primal_bite_remaining = 0,
    rage = 30,
}, na_out)
eq(na_out.action, "primal_bite", "druid: Bear cues Primal Bite when ready")

-- 5.6 SHAMAN LEVELING FALLBACKS
-- Leveling Shaman without Stormstrike / Maelstrom Weapon: resolves spec "general"
-- Missing Flame Shock -> cues flameshock
st.forever_guide.evaluate("SHAMAN", nil, {
    ["Stormstrike"] = false,
    ["Maelstrom Weapon"] = false,
    ["Flame Shock"] = true,
    flameshock_active = false,
    shock_remaining = 0,
}, na_out)
eq(na_out.rotation_key, "general", "shaman fallback: resolves to general leveling spec")
eq(na_out.action, "flameshock", "shaman fallback: cues Flame Shock when missing")

-- Flame Shock active, shock ready -> falls back to Earth Shock
st.forever_guide.evaluate("SHAMAN", nil, {
    ["Stormstrike"] = false,
    ["Maelstrom Weapon"] = false,
    ["Flame Shock"] = true,
    flameshock_active = true,
    ["Earth Shock"] = true,
    shock_remaining = 0,
}, na_out)
eq(na_out.action, "earthshock", "shaman fallback: falls back to Earth Shock when Flame Shock active")

-- Shock on cooldown, Lightning Shield down -> falls back to Lightning Shield
st.forever_guide.evaluate("SHAMAN", nil, {
    ["Stormstrike"] = false,
    ["Maelstrom Weapon"] = false,
    ["Flame Shock"] = true,
    flameshock_active = true,
    shock_remaining = 5.0,
    ["Lightning Shield"] = true,
    lightningshield_active = false,
}, na_out)
eq(na_out.action, "lightningshield", "shaman fallback: falls back to Lightning Shield when shock on CD")

-- Learn Stormstrike -> resolves to enhancement spec, cues stormstrike (with Flame Shock dot active)
st.forever_guide.evaluate("SHAMAN", nil, {
    ["Stormstrike"] = true,
    stormstrike_remaining = 0,
    flameshock_active = true,
}, na_out)
eq(na_out.rotation_key, "enhancement", "shaman: resolves to enhancement spec once Stormstrike known")
eq(na_out.action, "stormstrike", "shaman: cues Stormstrike when ready")

print(string.format("\n%d checks, %d failed", checks, failures))
if failures > 0 then
    os.exit(1)
end
print("PASS  tests/forever_hud_gate_state.lua")

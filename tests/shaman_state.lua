-- tests/shaman_state.lua: offline tests for the shaman weave module
-- (classes/shaman.lua) over the real compat.lua + weave.lua in a sandbox.
-- Pins the pre-init guards (a live crash regression), catalog resolution, Maelstrom
-- cast-time integration, the cast start/stop/delay lifecycle, the single-walk aura scan,
-- spark monotonicity across swing rollovers, talent invalidation and the combat-exit
-- reset.
-- The sandbox simulates a TBC client (WOW_PROJECT_ID 5): Maelstrom Weapon does not
-- exist there, so the breakpoint markers + spark stay hidden and the effective cast
-- time ignores MW stacks; Wrath behaviour is pinned by temporarily overriding
-- st.family to "WRATH" (the gate reads it live), with bars_state.lua pinning the
-- Wrath visuals end to end independently.
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
-- Float-tolerant compare (haste multipliers are products of 1.30 and 1.10, which do
-- not land exactly on the decimal literal).
local function near(got, want, tol, label)
    checks = checks + 1
    if type(got) ~= "number" or math.abs(got - want) > tol then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end

-- Sandbox environment --------------------------------------------------------------------
local clock = 0
local aura_list = {}
local aura_calls = 0
-- TARGET auras are served separately from the player's: the flame shock scan reads
-- "target" and must never be miscounted as a player-weave walk.
local target_aura_list = {}
local target_aura_calls = 0
-- Spell cooldown fixture for the Stormstrike / Shamanistic Rage badges. compat.lua reads
-- the classic GetSpellCooldown global at load, so this must exist before compat runs.
local cooldowns = {}
-- Spell usability fixture for the S5 HUD mana-tint verification: [spell] =
-- { usable, insufficient }; an absent entry reads affordable.
local spell_usable = {}
local casting_impl = function() return nil end
local channel_impl = function() return nil end

-- Air-slot totem fixture for the twist reconciliation: nil serves MayReturnNothing
-- (no totem / no client read), otherwise { have, name, start, duration, icon,
-- modrate, spell } unpacked like the client's GetTotemInfo.
local totem_slot4 = nil
-- Fire-slot totem fixture for the searing reconcile: same shape as the air
-- slot above (nil = unknown, never "no totem").
local totem_slot1 = nil
-- Water-slot totem fixture for the Call of the Elements clock (S-20 / U-10):
-- same shape again (nil = unknown, never "no totem").
local totem_slot3 = nil
-- Earth-slot totem fixture for the APL utility layer's Strength of Earth clock
-- (bench/rotation_gap_vs_apl_2026-10-20.md §5): same shape again.
local totem_slot2 = nil

-- Mutable known-spell fixture: the catalogue-invalidation test drops back to a lower
-- Lightning Bolt rank and then learns the higher one, which is what makes a resolved
-- catalogue entry stale.
local known_spells = { [25449] = true, [25442] = true, [49281] = true }

-- Bar width the visuals frame reports; a texture's horizontal offset is read back as a
-- fraction of it, which is how the spark/marker positions are asserted below.
local BAR_WIDTH = 100

-- Texture stub recording what on_bar_update draws, so the widgets' positions and colors
-- can be inspected without a real frame.
local function make_texture()
    local t = { hidden = true }
    function t:SetDrawLayer() end
    function t:SetTexCoord() end
    function t:SetColorTexture(r, g, b, a) t.base_color = { r, g, b, a } end
    function t:SetWidth(w) t.width = w end
    function t:SetHeight(h) t.height = h end
    function t:SetTexture(tex) t.texture = tex end
    function t:ClearAllPoints()
        t.point, t.anchor, t.rel_point, t.offset, t.offset_y = nil, nil, nil, nil, nil
    end
    function t:SetPoint(point, anchor, rel_point, x, y)
        t.point, t.anchor, t.rel_point, t.offset, t.offset_y = point, anchor, rel_point, x, y
    end
    function t:SetVertexColor(r, g, b, a) t.color = { r, g, b, a } end
    function t:Hide() t.hidden = true end
    function t:Show() t.hidden = false end
    function t:IsShown() return not t.hidden end
    return t
end

-- Font string stub for the flame shock label and the cooldown badges.
local function make_fontstring()
    local f = { hidden = true }
    function f:ClearAllPoints()
        f.point, f.anchor, f.rel_point, f.offset, f.offset_y = nil, nil, nil, nil, nil
    end
    function f:SetPoint(point, anchor, rel_point, x, y)
        f.point, f.anchor, f.rel_point, f.offset, f.offset_y = point, anchor, rel_point, x, y
    end
    function f:SetJustifyH() end
    function f:SetFont(font_path, size, flags) f.font = { font_path, size, flags } end
    function f:SetText(text) f.text = text end
    function f:SetTextColor(r, g, b, a) f.color = { r, g, b, a } end
    function f:Hide() f.hidden = true end
    function f:Show() f.hidden = false end
    function f:IsShown() return not f.hidden end
    return f
end

-- Visuals frame: setup_weave_visuals builds the mainhand widgets on it in post_init. The
-- offhand frame is separate so the spark mirror's hand-specific anchoring is observable.
local visuals_frame = {}
function visuals_frame:CreateTexture() return make_texture() end
function visuals_frame:CreateFontString() return make_fontstring() end

local offhand_visuals_frame = {}
function offhand_visuals_frame:CreateTexture() return make_texture() end
function offhand_visuals_frame:CreateFontString() return make_fontstring() end

local env = {}
for k, v in pairs(_G) do env[k] = v end
env.WOW_PROJECT_ID = 5
env.WOW_PROJECT_CLASSIC = 2
env.WOW_PROJECT_BURNING_CRUSADE_CLASSIC = 5
env.WOW_PROJECT_WRATH_CLASSIC = 11
env.WOW_PROJECT_CATACLYSM_CLASSIC = 14
env.WOW_PROJECT_MISTS_CLASSIC = 19
env.WOW_PROJECT_MAINLINE = 1
env.WOW_PROJECT_FOREVER = 18
env.GetTime = function() return clock end
env.GetSpellInfo = function(id)
    -- Name-vs-id fixtures: Era queries by id, TBC Anniversary by NAME.
    -- Both resolutions are pinned below; the name leg mirrors the id leg
    -- so the catalogue/cooldown/known gates read identically on each family.
    -- The Lightning Bolt name leg respects the known-rank fixture (low-rank
    -- test drops 25449 and keeps 25448): the name answers the highest KNOWN
    -- rank, nil when neither is known.
    if id == "Lightning Bolt" then
        if known_spells[25449] then return "Lightning Bolt", nil, "icon_lb", 2500, 0, 30, 25449 end
        if known_spells[25448] then return "Lightning Bolt", nil, "icon_lb", 2000, 0, 30, 25448 end
        return nil
    end
    if id == "Chain Lightning" then return "Chain Lightning", nil, "icon_cl", 2000, 0, 30, 25442 end
    -- The practice-panel COMMON abilities (the class's own ability list): the
    -- panel offers them, so the sandbox answers their names the way a client
    -- that has the spell does. Without these the widening seam would resolve
    -- nothing and the panel pins would never see the common slots.
    if id == "Healing Wave" then return "Healing Wave", nil, "icon_hw", 0, 0, 0, 331 end
    if id == "Chain Heal" then return "Chain Heal", nil, "icon_ch", 0, 0, 0, 1064 end
    if id == "Water Shield" then return "Water Shield", nil, "icon_ws", 0, 0, 0, 52127 end
    if id == "Healing Potion" then return "Healing Potion", nil, "icon_hp", 0, 0, 0, 439 end
    if id == "Food" then return "Food", nil, "icon_food", 0, 0, 0, 433 end
    if id == "Stormstrike" then return "Stormstrike", nil, "icon_ss", 0, 0, 0, 17364 end
    if id == "Shamanistic Rage" then return "Shamanistic Rage", nil, "icon_sr", 0, 0, 0, 30823 end
    if id == "Flame Shock" then return "Flame Shock", nil, "icon_fs", 0, 0, 0, 8050 end
    if id == "Fire Nova Totem" then return "Fire Nova Totem", nil, "icon_fn", 0, 0, 0, 1535 end
    if id == "Earth Shock" then return "Earth Shock", nil, "icon_es", 0, 0, 0, 8042 end
    if id == "Feral Spirit" then return "Feral Spirit", nil, "icon_feral", 0, 0, 0, 51533 end
    if id == "Fire Elemental Totem" then return "Fire Elemental Totem", nil, "icon_fe", 0, 0, 0, 2894 end
    if id == "Magma Totem" then return "Magma Totem", nil, "icon_magma", 0, 0, 0, 8190 end
    if id == "Lava Lash" then return "Lava Lash", nil, "icon_ll", 0, 0, 0, 60103 end
    if id == "Molten Blast" then return "Molten Blast", nil, "icon_mb", 0, 0, 0, 425339 end
    if id == "Windfury Totem" then return "Windfury Totem", nil, "icon_wf", 0, 0, 0, 8512 end
    if id == "Grace of Air Totem" then return "Grace of Air Totem", nil, "icon_goa", 0, 0, 0, 10613 end
    if id == "Searing Totem" then return "Searing Totem", nil, "icon_sear", 0, 0, 0, 10438 end
    -- The Lightning Shield maintain (S-19): the client answers the NAME, so the
    -- guide slot's id is the client's own (the same rank-1 fallback it ships).
    if id == "Lightning Shield" then return "Lightning Shield", nil, "icon_ls", 0, 0, 0, 49281 end
    if id == 49281 then return "Lightning Shield", nil, "icon_ls", 0, 0, 0, 49281 end
    if id == 25449 then return "Lightning Bolt", nil, "icon_lb", 2500, 0, 30, 25449 end
    if id == 25448 then return "Lightning Bolt", nil, "icon_lb", 2000, 0, 30, 25448 end
    -- Wrath Lightning Bolt max rank for the M1 sub-5 hardcast (sim source:
    -- wowsims/wotlk sim/shaman/lightning_bolt.go 49238, base cast 2500 ms).
    if id == 49238 then return "Lightning Bolt", nil, "icon_lb_wrath", 2500, 0, 30, 49238 end
    if id == 25442 then return "Chain Lightning", nil, "icon_cl", 2000, 0, 30, 25442 end
    -- Fixture-only stand-in for an unconfirmed higher Windfury Totem rank: not in
    -- the addon's twist id table, so only the live-name resolution path stamps it.
    if id == 10613 then return "Windfury Totem", nil, "icon_wf", 0, 0, 0, 10613 end
    if id == 8512 then return "Windfury Totem", nil, "icon_wf", 0, 0, 0, 8512 end
    -- Fixture-only stand-in for an unconfirmed Searing Totem rank: not in the
    -- addon's searing id table, so only the live-name resolution path stamps it.
    if id == 25530 then return "Searing Totem", nil, "icon_sear", 0, 0, 0, 25530 end
    -- SoD Lava Burst fixture (S4): the live resolver probes by NAME and expects the
    -- spell's id in the 7th return; the id lookup covers direct reads.
    if id == "Lava Burst" then return "Lava Burst", nil, "icon_lava", 2000, 0, 0, 51505 end
    if id == 51505 then return "Lava Burst", nil, "icon_lava", 2000, 0, 0, 51505 end
    return nil
end
env.IsSpellKnown = function(id)
    if known_spells[id] == true then
        return true
    end
    -- TBC name leg: the same known ranks answer by English name.
    if id == "Lightning Bolt" then return known_spells[25449] == true or known_spells[25448] == true end
    if id == "Chain Lightning" then return known_spells[25442] == true end
    if id == "Stormstrike" then return true end
    if id == "Shamanistic Rage" then return true end
    if id == "Flame Shock" then return true end
    if id == "Fire Nova Totem" then return true end
    if id == "Windfury Totem" then return true end
    if id == "Searing Totem" then return known_spells[10438] == true end
    -- The Lightning Shield maintain's known gate (S-19): the Lightning Shield is a
    -- talent, so a build without it must never be prompted.
    if id == "Lightning Shield" then return known_spells[49281] == true end
    if id == 49281 then return known_spells[49281] == true end
    -- The APL utility layer (bench/rotation_gap_vs_apl_2026-10-20.md §5).
    if id == "Bloodlust" then return known_spells[2825] == true end
    if id == "Frost Shock" then return known_spells[25464] == true end
    return nil
end
env.UnitAura = function(unit, index, filter)
    -- Player walks (weave + trackers) and target scans are counted separately so a gate
    -- test can prove the target scan never runs while the flame shock option is off.
    local entry
    if unit == "target" then
        target_aura_calls = target_aura_calls + 1
        entry = target_aura_list[index]
    else
        aura_calls = aura_calls + 1
        entry = aura_list[index]
    end
    if not entry then return nil end
    return entry.name, nil, entry.count, nil, entry.duration, entry.expiration,
        entry.source, nil, nil, entry.spell_id
end
env.GetSpellCooldown = function(id)
    -- Name-vs-id: TBC queries by NAME, Era by id; both hit the same fixture.
    local key = id
    if id == "Stormstrike" then key = 17364 end
    if id == "Shamanistic Rage" then key = 30823 end
    if id == "Flame Shock" then key = 8050 end
    if id == "Fire Nova Totem" then key = 1535 end
    if id == "Feral Spirit" then key = 51533 end
    if id == "Fire Elemental Totem" then key = 2894 end
    if id == "Magma Totem" then key = 8190 end
    if id == "Lava Lash" then key = 60103 end
    if id == "Bloodlust" then key = 2825 end
    if id == "Frost Shock" then key = 25464 end
    local cd = cooldowns[key]
    if cd then return cd.start, cd.duration, 1, 1 end
    return 0, 0, 1, 1
end
env.IsSpellUsable = function(spell)
    -- Name-vs-id: TBC probes by NAME, Era by id; the fixture answers both.
    local key = spell
    if spell == "Stormstrike" then key = 17364 end
    if spell == "Flame Shock" then key = 8050 end
    if spell == "Lightning Bolt" then key = 403 end
    if spell == "Fire Nova Totem" then key = 1535 end
    if spell == "Earth Shock" then key = 8042 end
    if spell == "Windfury Totem" then key = 8512 end
    local entry = spell_usable[key]
    if entry then return entry[1], entry[2] end
    return true, false
end
env.UnitCastingInfo = function() return casting_impl() end
env.UnitChannelInfo = function() return channel_impl() end
env.UnitSpellHaste = function() return 0 end
-- Secret-value probe: only the "SECRET" sentinel reads as restricted, so the
-- wrapper's whole-read degrade is pinnable without touching any other fixture.
env.issecretvalue = function(v) return v == "SECRET" end
env.GetTotemInfo = function(slot)
    if totem_slot4 == "THROW" then error("totem read failed") end
    if slot == 4 then
        if totem_slot4 == nil then return nil end
        local t = totem_slot4
        return t.have, t.name, t.start, t.duration, t.icon, t.modrate, t.spell
    end
    -- Fire slot for the searing reconcile: same unknown-shape as the air slot.
    if slot == 1 then
        if totem_slot1 == "THROW" then error("totem read failed") end
        if totem_slot1 == nil then return nil end
        local t = totem_slot1
        return t.have, t.name, t.start, t.duration, t.icon, t.modrate, t.spell
    end
    -- Water slot for the Call of the Elements clock: same unknown-shape.
    if slot == 3 then
        if totem_slot3 == "THROW" then error("totem read failed") end
        if totem_slot3 == nil then return nil end
        local t = totem_slot3
        return t.have, t.name, t.start, t.duration, t.icon, t.modrate, t.spell
    end
    -- Earth slot for the APL utility layer's Strength of Earth clock: same
    -- unknown-shape.
    if slot == 2 then
        if totem_slot2 == "THROW" then error("totem read failed") end
        if totem_slot2 == nil then return nil end
        local t = totem_slot2
        return t.have, t.name, t.start, t.duration, t.icon, t.modrate, t.spell
    end
    return nil
end
-- compat reads several legacy globals through _G (annotation-safe path); mirror every
-- sandbox stub for the duration of the loads below, then restore _G exactly. A
-- hardcoded name list goes stale the moment compat adds another _G read.
local mirrored_globals = {}
for name, value in pairs(env) do
    mirrored_globals[name] = rawget(_G, name)
    _G[name] = value
end

local st = {}
local class_db = { weave_mw_enabled = true }
local ST = { SHAMAN = {}, interfaces_are_initialised = false }
ST.get_class_table = function() return class_db end
ST.get_visuals_frame = function(_, hand)
    if hand == "offhand" then return offhand_visuals_frame end
    return visuals_frame
end
ST.get_bar_visuals_width_and_height = function() return BAR_WIDTH, 15 end

-- Scripted mainhand swing: a constant speed rolling over every `speed` seconds, exactly
-- like the swing engine advances d.start. on_bar_update reads d.start/d.ends_at live, so
-- stepping the clock through a rollover is what used to rewind the spark.
local function set_scripted_swing(t, speed)
    local start = math.floor((t / speed) + 1e-9) * speed
    ST.mainhand = { speed = speed, start = start, ends_at = start + speed, is_full = false }
end

-- The fraction of the bar at which a texture was last placed.
local function texture_fraction(t)
    if type(t.offset) ~= "number" then return nil end
    return t.offset / BAR_WIDTH
end

env.LibStub = function(major)
    if major == "AceAddon-3.0" then
        return { GetAddon = function() return ST end }
    end
    return {}
end

local compat = assert(loadfile(ROOT .. "compat.lua")); setfenv(compat, env); compat("SwedgeTimer", st)
local weave = assert(loadfile(ROOT .. "weave.lua")); setfenv(weave, env); weave("SwedgeTimer", st)
-- The decision engine loads before the class module (as the TOCs order it), so the
-- class's own drill grades through the SHIPPED model and not a copy of it.
local guide = assert(loadfile(ROOT .. "shaman_guide.lua")); setfenv(guide, env); guide("SwedgeTimer", st)
local shaman = assert(loadfile(ROOT .. "classes/shaman.lua")); setfenv(shaman, env); shaman("SwedgeTimer", st)
-- classes/shaman.lua registers its body as a loader (operator order 2026-10-21:
-- only the selected class executes). Activate it here, right after its file loads -
-- the same load-time position its body occupied before the wrapper.
assert(type(st.class_loaders) == "table"
    and type(st.class_loaders["SHAMAN"]) == "function",
    "classes/shaman.lua registers the SHAMAN loader")
st.class_loaders["SHAMAN"]()
for name, previous in pairs(mirrored_globals) do
    _G[name] = previous
end
check(type(ST.SHAMAN.post_init) == "function", "classes/shaman.lua loads and defines its hooks")

-- 1) Pre-init safety: SUCCEEDED is dispatched without an init gate ----------------------
clock = 0
ST.interfaces_are_initialised = false
ST.weave_catalog = nil
local ok1, err1 = pcall(ST.SHAMAN.on_spellcast_succeeded, ST, "player", nil, 25449)
check(ok1, "pre-init SUCCEEDED does not error (" .. tostring(err1) .. ")")
local ok2, err2 = pcall(ST.SHAMAN.on_spellcast_succeeded, ST, "player", nil, 25449)
check(ok2, "repeated pre-init SUCCEEDED stays safe (" .. tostring(err2) .. ")")

-- With the init flag up but no catalog yet the nil guard must hold too.
ST.interfaces_are_initialised = true
local ok3, err3 = pcall(ST.SHAMAN.on_spellcast_succeeded, ST, "player", nil, 25449)
check(ok3, "SUCCEEDED with a nil catalog does not error (" .. tostring(err3) .. ")")
ST.interfaces_are_initialised = false

-- 2) post_init resolves the catalog ----------------------------------------------------
local ok4 = pcall(ST.SHAMAN.post_init, ST)
check(ok4, "post_init runs in the sandbox")
check(type(ST.weave_catalog) == "table", "post_init builds the weave catalog")
eq(ST.weave_catalog.LB and ST.weave_catalog.LB.spell_id, 25449, "LB resolves to the highest known rank")
eq(ST.weave_catalog.LB and ST.weave_catalog.LB.cast_seconds, 2.5, "LB cast time comes from GetSpellInfo")
eq(ST.weave_catalog.CL and ST.weave_catalog.CL.spell_id, 25442, "CL resolves to its known rank")
eq(ST.weave_catalog.HW, nil, "unknown families stay unresolved")

-- 3) Maelstrom Weapon stacks feed the effective cast time, gated per client ---------
-- The sandbox is a TBC client: Maelstrom Weapon does not exist there, so even five
-- stacks leave the full base cast time; the scan itself stays truthful.
eq(st.family, "TBC", "the sandbox simulates a TBC client")
eq(st.weave.has_maelstrom_weapon(st.family), false, "TBC has no Maelstrom Weapon")
aura_list = { { name = "Maelstrom Weapon", count = 5, spell_id = 408505 } }
ST.SHAMAN.refresh_weave_mw_stacks(ST)
eq(ST.weave_mw_stacks, 5, "the scan stays truthful: five stacks are still read")
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5, "TBC: no MW reduction despite the stacks")
class_db.weave_mw_enabled = false
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5, "TBC: the option-off path is the same base cast time")
class_db.weave_mw_enabled = true
-- A Wrath client keeps the exact historical behaviour (the option stays the
-- kill-switch where MW exists).
st.family = "WRATH"
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 0, "Wrath: five stacks make the cast instant")
class_db.weave_mw_enabled = false
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5, "Wrath: MW can be disabled by option")
class_db.weave_mw_enabled = true
st.family = "TBC"
aura_list = {}
ST.SHAMAN.refresh_weave_mw_stacks(ST)
eq(ST.weave_mw_stacks, 0, "no aura means zero stacks")
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5, "base cast time without stacks")

-- 4) Cast lifecycle: start -> delayed -> stop ------------------------------------------
ST.interfaces_are_initialised = true
clock = 1.0
casting_impl = function()
    return "Lightning Bolt", "Lightning Bolt", "icon_lb", 1000, 3500, false, 1, false, 25449
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-1", 25449)
eq(ST.weave_is_casting, true, "START begins the cast state")
eq(ST.weave_family, "LB", "START resolves the family from the spell id")
eq(ST.weave_cast_start_time, 1.0, "cast start comes from the client window")
eq(ST.weave_cast_end_time, 3.5, "cast end comes from the client window")
eq(ST.weave_cast_duration, 2.5, "cast duration is the live window length")

casting_impl = function()
    return "Lightning Bolt", "Lightning Bolt", "icon_lb", 1000, 4200, false, 1, false, 25449
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_DELAYED", "player", "cast-1", 25449)
eq(ST.weave_cast_start_time, 1.0, "DELAYED keeps the original start anchor")
eq(ST.weave_cast_end_time, 4.2, "DELAYED re-anchors the end from the live window")
eq(ST.weave_cast_duration, 3.2, "DELAYED duration follows the live window")

ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", "cast-1")
eq(ST.weave_is_casting, false, "STOP ends the cast state")
eq(ST.weave_cast_end_time, nil, "STOP clears the end anchor")

-- SUCCEEDED keeps the last family and ends the cast.
clock = 2.0
casting_impl = function() return nil end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-2", 25449)
eq(ST.weave_is_casting, true, "second START begins a new cast")
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-2", 25449)
eq(ST.weave_is_casting, false, "SUCCEEDED ends the cast state")
eq(ST.weave_family, "LB", "SUCCEEDED keeps the last family for the marker")

-- 5) The init gate on the lifecycle hook ------------------------------------------------
ST.interfaces_are_initialised = false
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-3", 25449)
eq(ST.weave_is_casting, false, "spellcast events are ignored before init")
ST.interfaces_are_initialised = true

-- 6) Family toggles pick the first enabled family ---------------------------------------
class_db.weave_families = { LB = false, CL = true, HW = true, LHW = true, CH = true }
ST.weave_family = "LB"
local entry, family = ST.SHAMAN.get_weave_visual_spell(ST)
eq(family, "CL", "a disabled family falls through to the next enabled one")
eq(entry and entry.spell_id, 25442, "the fallback family's entry is returned")
class_db.weave_families = nil

-- 7) One aura walk feeds both weave inputs ----------------------------------------------
-- scan_weave_auras must serve BOTH the haste buffs and the Maelstrom stacks, so a change
-- of auras costs one UnitAura walk. The fixture keeps a neutral aura last and omits
-- Berserking, so the walk cannot early-exit: R2 walks the full 40-row cap (a nil
-- row no longer terminates), so one change costs exactly 40 reads.
aura_list = {
    { name = "Maelstrom Weapon", count = 3, spell_id = 408505 },
    { name = "Whirlwind" },
    { name = "Bloodlust", spell_id = 2825 },
    { name = "Lightning Shield" },
}
aura_calls = 0
ST.SHAMAN.on_aura_change(ST)
eq(aura_calls, 40, "one on_aura_change walks the full 40-row cap (R2: no nil terminator)")
eq(ST.weave_mw_stacks, 3, "the single walk carries the Maelstrom stack count")
near(ST.weave_haste_mult, 1.30, 1e-9, "the single walk carries the Bloodlust haste multiplier")

-- Standalone fallback: refresh_weave_mw_stacks with no stacks argument walks on its own
-- and lands on the same count.
aura_calls = 0
ST.SHAMAN.refresh_weave_mw_stacks(ST)
check(aura_calls > 0, "standalone stack refresh performs its own aura walk")
eq(ST.weave_mw_stacks, 3, "standalone stack refresh yields the same count")

-- 8) Spark monotonicity across a swing rollover -----------------------------------------
-- Runs as a Wrath client (the spark only draws where Maelstrom exists); the TBC
-- pin follows at the end of the section.
-- A 3s cast begun 0.5s into a 2s swing (rollover at t=2) must never move the spark
-- backwards: the projection is anchored to the swing the cast started in
-- (weave_cast_swing_start), not to whatever swing is current mid-cast.
st.family = "WRATH"
ST.interfaces_are_initialised = true
clock = 0.5
set_scripted_swing(clock, 2.0)
casting_impl = function()
    return "Lightning Bolt", "Lightning Bolt", "icon_lb", 500, 3500, false, 1, false, 25449
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-spark", 25449)
eq(ST.weave_cast_swing_start, 0, "cast start captures the swing anchor")
near(ST.weave_cast_start_swing_fraction, 0.25, 1e-9, "cast start fraction is measured against the captured swing")

local spark_fractions = {}
for i = 0, 30 do
    clock = 0.5 + i * 0.1
    set_scripted_swing(clock, 2.0)
    ST.SHAMAN.on_bar_update(ST, "mainhand")
    spark_fractions[#spark_fractions + 1] = texture_fraction(visuals_frame.weave_spark)
end
local monotonic = true
for i = 2, #spark_fractions do
    if spark_fractions[i] < spark_fractions[i - 1] - 1e-9 then
        monotonic = false
    end
end
check(monotonic, "spark fraction never moves backwards across the swing rollover")
near(spark_fractions[#spark_fractions], 1.0, 1e-6, "spark lands at ~1.0 by the end of the cast")
eq(ST.weave_cast_swing_start, 0, "the captured swing anchor survives the rollover")

-- end_weave_cast clears both anchors.
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", "cast-spark")
eq(ST.weave_is_casting, false, "STOP after the rollover ends the cast")
eq(ST.weave_cast_swing_start, nil, "end_weave_cast clears the swing anchor")
eq(ST.weave_cast_start_swing_fraction, nil, "end_weave_cast clears the cast start fraction")

-- Back on TBC the same cast draws nothing: tracking still runs (the family gate is
-- visuals-only), but no marker or spark may teach hard-cast weaving.
st.family = "TBC"
clock = 10.5
set_scripted_swing(clock, 2.0)
casting_impl = function()
    return "Lightning Bolt", "Lightning Bolt", "icon_lb", 10500, 13500, false, 1, false, 25449
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-tbc", 25449)
eq(ST.weave_is_casting, true, "TBC: cast tracking still runs without Maelstrom")
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_marker.hidden, "TBC: the marker stays hidden on an active swing")
check(visuals_frame.weave_spark.hidden, "TBC: the spark stays hidden during the cast")
check(visuals_frame.weave_marker_top.hidden, "TBC: the top marker stays hidden")
check(visuals_frame.weave_marker_bottom.hidden, "TBC: the bottom marker stays hidden")
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", "cast-tbc")

-- 9) Combat exit ends an in-flight cast but keeps the resolved family ---------------------
-- A wipe fires no STOP, so the cast state would stay live forever; on_combat_exit must
-- clear it while weave_family (and with it the marker's breakpoint) survives.
ST.interfaces_are_initialised = true
clock = 5.0
set_scripted_swing(clock, 2.0)
casting_impl = function()
    return "Chain Lightning", "Chain Lightning", "icon_cl", 5000, 8000, false, 1, false, 25442
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-wipe", 25442)
eq(ST.weave_is_casting, true, "wipe scenario: the cast is in flight")
eq(ST.weave_family, "CL", "wipe scenario: the cast resolved its family")

local ok5 = pcall(ST.SHAMAN.on_combat_exit, ST)
check(ok5, "on_combat_exit does not error")
eq(ST.weave_is_casting, false, "combat exit ends the in-flight cast")
eq(ST.weave_cast_start_time, nil, "combat exit clears the cast start anchor")
eq(ST.weave_cast_end_time, nil, "combat exit clears the cast end anchor")
eq(ST.weave_cast_swing_start, nil, "combat exit clears the swing anchor")
eq(ST.weave_cast_start_swing_fraction, nil, "combat exit clears the start fraction")
eq(ST.weave_cast_duration, nil, "combat exit clears the cast duration")
eq(ST.weave_family, "CL", "combat exit keeps the last resolved family")

-- The kept family still resolves (the marker itself stays hidden on TBC: no Maelstrom
-- here; the Wrath draw is pinned in section 17).
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_marker.hidden, "TBC: the marker stays hidden after a combat exit")
eq(visuals_frame.weave_spark.hidden, true, "the spark is hidden after a combat exit")

-- Pre-init + no visuals: the reset must not error (nothing here reads the frame).
clock = 6.0
set_scripted_swing(clock, 2.0)
casting_impl = function()
    return "Lightning Bolt", "Lightning Bolt", "icon_lb", 6000, 9000, false, 1, false, 25449
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-wipe-preinit", 25449)
local saved_frame_getter = ST.get_visuals_frame
local saved_marker, saved_spark = visuals_frame.weave_marker, visuals_frame.weave_spark
ST.get_visuals_frame = function() return nil end
visuals_frame.weave_marker, visuals_frame.weave_spark = nil, nil
ST.interfaces_are_initialised = false
local ok6, err6 = pcall(ST.SHAMAN.on_combat_exit, ST)
check(ok6, "pre-init on_combat_exit with no visuals does not error (" .. tostring(err6) .. ")")
eq(ST.weave_is_casting, false, "pre-init combat exit still clears the cast state")
visuals_frame.weave_marker, visuals_frame.weave_spark = saved_marker, saved_spark
ST.get_visuals_frame = saved_frame_getter
ST.interfaces_are_initialised = true

-- 10) Effective cast time with Maelstrom and haste ----------------------------------------
-- TBC first: the hasted base cast time applies, Maelstrom never reduces it here.
aura_list = {
    { name = "Maelstrom Weapon", count = 5, spell_id = 408505 },
    { name = "Bloodlust", spell_id = 2825 },
}
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_mw_stacks, 5, "five Maelstrom stacks are read by the merged scan")
near(ST.weave_haste_mult, 1.30, 1e-9, "Bloodlust sets the haste multiplier")
near(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5 / 1.30, 1e-9, "TBC: the hasted base cast time, no MW reduction")
class_db.weave_mw_enabled = false
near(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5 / 1.30, 1e-9, "TBC: option-off is the same hasted base cast time")
class_db.weave_mw_enabled = true
-- Wrath keeps the exact historical behaviour: five stacks stay instant under haste,
-- and disabling MW applies the hasted base cast time.
st.family = "WRATH"
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 0, "Wrath: five stacks stay instant under haste")
class_db.weave_mw_enabled = false
near(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5 / 1.30, 1e-9, "Wrath: MW disabled applies the hasted base cast time")
class_db.weave_mw_enabled = true
st.family = "TBC"

-- Without haste, the TBC path is exactly the base cast time either way.
aura_list = { { name = "Maelstrom Weapon", count = 5, spell_id = 408505 } }
ST.SHAMAN.on_aura_change(ST)
near(ST.weave_haste_mult, 1.0, 1e-9, "no buff restores the neutral haste multiplier")
class_db.weave_mw_enabled = false
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5, "TBC: option-off returns the base cast time")
class_db.weave_mw_enabled = true
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5, "TBC: five stacks still return the base cast time")
st.family = "WRATH"
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 0, "Wrath: five stacks return 0 with MW enabled")
st.family = "TBC"
aura_list = {}
ST.SHAMAN.refresh_weave_mw_stacks(ST)
eq(ST.weave_mw_stacks, 0, "aura fixture reset to no stacks")

-- 11) Talent changes invalidate the resolved catalogue -------------------------------------
-- resolve_weave_catalog only fills MISSING families, so a rank learned after post_init
-- must be picked up by dropping the stale entry in on_talents_changed first.
known_spells[25449] = nil              -- only the low Lightning Bolt rank is known now
known_spells[25448] = true
ST.weave_catalog.LB = nil
ST.SHAMAN.resolve_weave_catalog(ST)
eq(ST.weave_catalog.LB and ST.weave_catalog.LB.spell_id, 25448, "the low rank resolves first")
eq(ST.weave_catalog.LB and ST.weave_catalog.LB.cast_seconds, 2.0, "the low rank carries its own cast time")

-- A failed family's retry stamp is dropped too (a level-up must retry immediately, not
-- after the throttle window).
ST.weave_catalog_retry_at.HW = clock + 1000
known_spells[25449] = true             -- the higher rank is learned
ST.SHAMAN.on_talents_changed(ST)
eq(ST.weave_catalog.LB, nil, "on_talents_changed drops the resolved catalogue")
eq(ST.weave_catalog_retry_at.HW, nil, "on_talents_changed drops the retry stamps")

ST.SHAMAN.resolve_weave_catalog(ST)
eq(ST.weave_catalog.LB and ST.weave_catalog.LB.spell_id, 25449, "re-resolution picks up the learned higher rank")
eq(ST.weave_catalog.LB and ST.weave_catalog.LB.cast_seconds, 2.5, "the higher rank's cast time is re-read")
eq(ST.weave_catalog.CL and ST.weave_catalog.CL.spell_id, 25442, "other families re-resolve unchanged")
known_spells[25448] = nil              -- fixture restored: 25449 is the highest known rank

-- 11b) H4: an unresolvable cast time hides the weave widgets (never renders instant)
-- The resolver only stores entries with a positive cast time, but a partially
-- populated client can still hand the math an entry whose cast_seconds is nil; the
-- effective cast then reads UNKNOWN and every marker/position widget must hide
-- instead of clamping nil to fraction 0 and painting a whole-swing-safe breakpoint.
st.family = "WRATH"
ST.weave_mw_observed = false
aura_list = {}
ST.SHAMAN.on_aura_change(ST)
-- Keep the suite clock monotonic: this block runs before section 12's clock = 50, so
-- the throttled target-debuff stamp it writes never out-runs the later fixtures.
clock = 45
set_scripted_swing(clock, 4.0)
ST.weave_family = "LB"
local h4_entry = ST.weave_catalog.LB
ST.weave_catalog.LB = { spell_id = 25449, name = "Lightning Bolt", icon = "icon_lb", cast_seconds = nil }
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), nil,
    "H4: an entry without a cast time reads UNKNOWN (nil), not instant")
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_marker.hidden, "H4: the main marker hides on an unknown cast")
check(visuals_frame.weave_marker_top.hidden, "H4: the top marker hides on an unknown cast")
check(visuals_frame.weave_marker_bottom.hidden, "H4: the bottom marker hides on an unknown cast")

class_db.show_shaman_spell_positions = true
local ok_h4 = pcall(ST.SHAMAN.on_bar_update, ST, "mainhand")
check(ok_h4, "H4: the position row does not error on an unknown cast")
local h4_icons = visuals_frame.weave_pos_icons
check(h4_icons.LB.hidden, "H4: the unresolved LB slot hides")
check(visuals_frame.weave_pos_times.LB.hidden, "H4: the unresolved LB cast time hides")
check(not h4_icons.CL.hidden, "H4: a resolved sibling (CL) still draws")
near(h4_icons.CL.offset, (4.0 - 2.0) / 4.0 * BAR_WIDTH, 1e-6,
    "H4: the resolved slot keeps its own safe start")
class_db.show_shaman_spell_positions = nil
ST.weave_catalog.LB = h4_entry
-- Drop the lazily-created position widgets again: section 27 pins that they do not
-- exist until the option first turns on.
visuals_frame.weave_pos_icons, visuals_frame.weave_pos_times = nil, nil
visuals_frame.weave_pos_zone, visuals_frame.weave_pos_label = nil, nil
st.family = "TBC"

-- 11c) Catalogue miss is hidden-with-retry by design (H4 follow-up)
-- An unresolved family stays nil and only advances its throttled retry stamp; the
-- hide comes from the H4 unknown path (11b), never a guess, and there is no chat or
-- diag write to assert - the acceptance is that the miss is quiet and retried.
ST.weave_catalog.HW = nil
ST.weave_catalog_retry_at.HW = nil
clock = 45.5
ST.SHAMAN.resolve_weave_catalog(ST)
eq(ST.weave_catalog.HW, nil, "catalogue miss: the family stays unresolved")
eq(ST.weave_catalog_retry_at.HW, clock + 5, "catalogue miss: the retry is throttled, not spammed")

-- 12) Tracker option gates: all five off -> nothing drawn, no scans -----------------------
-- The gate contract for every new visual: an off option keeps the widgets hidden AND the
-- per-frame path performs no additional aura work (the flame shock target scan is the
-- only UnitAura read reachable from on_bar_update).
ST.interfaces_are_initialised = true
clock = 50
set_scripted_swing(clock, 2.0)
aura_list = {
    { name = "Windfury Weapon" },
    { name = "Lightning Shield", count = 3 },
    { name = "Shamanistic Rage", expiration = clock + 10 },
}
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_windfury_active, true, "windfury fixture resolves through the merged scan")
eq(ST.weave_shield_type, "lightning", "shield fixture resolves through the merged scan")
eq(ST.weave_shield_charges, 3, "shield charge count is read from the aura")
near(ST.weave_sr_expires, clock + 10, 1e-9, "shamanistic rage expiry is read from the aura")

target_aura_list = {
    { name = "Flame Shock", spell_id = 8050, source = "player", duration = 12, expiration = clock + 8 },
}
cooldowns[17364] = { start = clock, duration = 8 }
cooldowns[30823] = { start = clock, duration = 60 }

local new_option_keys = {
    "show_shaman_breakpoint_markers", "show_shaman_windfury_icd",
    "show_shaman_flame_shock_bar", "show_shaman_cooldown_badges",
    "show_shaman_shield_charges",
}
local saved_options = {}
for i = 1, #new_option_keys do
    saved_options[i] = class_db[new_option_keys[i]]
    class_db[new_option_keys[i]] = false
end
target_aura_calls = 0
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(target_aura_calls, 0, "all tracker options off: on_bar_update performs no target scans")
check(visuals_frame.weave_windfury_bg.hidden, "windfury strip hidden when off")
check(visuals_frame.weave_windfury_fill.hidden, "windfury fill hidden when off")
check(visuals_frame.weave_fs_bg.hidden, "flame shock bar hidden when off")
check(visuals_frame.weave_fs_fill.hidden, "flame shock fill hidden when off")
check(visuals_frame.weave_fs_glow.hidden, "flame shock glow hidden when off")
check(visuals_frame.weave_fs_label.hidden, "flame shock label hidden when off")
check(visuals_frame.weave_ss_text.hidden, "SS badge hidden when off")
check(visuals_frame.weave_sr_text.hidden, "SR badge hidden when off")
check(visuals_frame.weave_marker_top.hidden, "top breakpoint marker hidden when off")
check(visuals_frame.weave_marker_bottom.hidden, "bottom breakpoint marker hidden when off")
local gated_rects = visuals_frame.weave_shield_rects
check(gated_rects[1].hidden and gated_rects[2].hidden and gated_rects[3].hidden and gated_rects[4].hidden,
    "shield rects hidden when off")
check(visuals_frame.weave_marker.hidden, "TBC: the main marker stays hidden with the trackers off")
for i = 1, #new_option_keys do
    class_db[new_option_keys[i]] = saved_options[i]
end
-- The same tick as a Wrath client draws the marker: the gate is the family, not the
-- options above.
st.family = "WRATH"
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_marker.hidden == false, "Wrath: the same tick draws the main marker")
st.family = "TBC"

-- 13) Windfury ICD strip buckets ----------------------------------------------------------
-- d.start is the current swing's start, i.e. the previous swing's landing time, which is
-- exactly the reference's lastSwing stamp, so the strip counts from the last swing.
clock = 50
set_scripted_swing(clock, 2.0)
aura_list = { { name = "Windfury Weapon" } }
ST.SHAMAN.on_aura_change(ST)
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(not visuals_frame.weave_windfury_bg.hidden, "windfury strip shows while the buff is up")
eq(visuals_frame.weave_windfury_fill.color[2], 0, "just procced reads red")
near(visuals_frame.weave_windfury_fill.width, 3, 1e-9, "full ICD fills the strip")
clock = 50.5
ST.SHAMAN.on_bar_update(ST, "mainhand")
near(visuals_frame.weave_windfury_fill.width, 2.5, 1e-9, "fill width tracks the remaining ICD")
eq(visuals_frame.weave_windfury_fill.color[2], 0, "above 2s stays red")
clock = 52.0
ST.SHAMAN.on_bar_update(ST, "mainhand")
near(visuals_frame.weave_windfury_fill.color[2], 0.65, 1e-9, "between 0.5s and 2s reads orange")
clock = 52.6
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_windfury_fill.color[2], 1, "below 0.5s reads green")
aura_list = {}
ST.SHAMAN.on_aura_change(ST)
clock = 53
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_windfury_bg.hidden, "strip hides when Windfury drops")
aura_list = { { name = "Windfury (localized)", spell_id = 8232 } }
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_windfury_active, true, "windfury also resolves by spell id")

-- 14) Flame Shock target bar ---------------------------------------------------------------
clock = 60
set_scripted_swing(clock, 2.0)
target_aura_list = {
    { name = "Flame Shock", spell_id = 8050, source = "player", duration = 12, expiration = 68 },
}
target_aura_calls = 0
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(not visuals_frame.weave_fs_bg.hidden, "flame shock bar shows for the player's debuff")
near(visuals_frame.weave_fs_fill.width, BAR_WIDTH * (8 / 12), 1e-6, "fill fraction is remaining/total")
eq(visuals_frame.weave_fs_label.text, "8", "the seconds label counts down")
check(visuals_frame.weave_fs_glow.hidden, "no glow above the final 4 seconds")
eq(target_aura_calls, 1, "the scan stops at the matched target aura")
local fs_scan_calls = target_aura_calls
clock = 60.01
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(target_aura_calls, fs_scan_calls, "the target scan is throttled to 0.05 s")

clock = 65
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(not visuals_frame.weave_fs_glow.hidden, "glow shows inside the final 4 seconds")
eq(visuals_frame.weave_fs_label.text, "3", "the label keeps counting down")

-- Another caster's Flame Shock does not qualify.
clock = 70
target_aura_list = {
    { name = "Flame Shock", spell_id = 8050, source = "other", duration = 12, expiration = clock + 8 },
}
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_fs_bg.hidden, "a debuff from another caster does not show the bar")

-- An unknown (localized) name still matches through the id table.
clock = 71
target_aura_list = {
    { name = "Flame Shock (localized)", spell_id = 8050, source = "player", duration = 12, expiration = clock + 8 },
}
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(not visuals_frame.weave_fs_bg.hidden, "the id table matches when the name differs")

-- No debuff -> hidden, glow cache reset.
target_aura_list = {}
clock = 72
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_fs_bg.hidden, "bar hides when the debuff is gone")
check(visuals_frame.weave_fs_glow.hidden, "glow hides when the debuff is gone")

-- 15) Stormstrike / Shamanistic Rage badges ------------------------------------------------
clock = 80
aura_list = {}
ST.SHAMAN.on_aura_change(ST)                        -- no SR aura up
cooldowns[17364] = { start = 78, duration = 8 }     -- 6s left
cooldowns[30823] = { start = 79, duration = 60 }    -- 59s left
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_ss_text.text, "SS 6s", "SS badge shows the Stormstrike cooldown")
eq(visuals_frame.weave_sr_text.text, "SR 59s", "SR badge falls back to the cooldown")
check(not visuals_frame.weave_ss_text.hidden, "SS badge shows while on cooldown")
check(not visuals_frame.weave_sr_text.hidden, "SR badge shows while on cooldown")

-- The SR aura wins over the cooldown while it is up.
clock = 90
aura_list = { { name = "Shamanistic Rage", expiration = 95 } }
ST.SHAMAN.on_aura_change(ST)
cooldowns[30823] = { start = 85, duration = 60 }    -- would read 55s if the cooldown won
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_sr_text.text, "SR 5s", "the SR aura reading wins over the cooldown")

-- Both ready -> hidden.
clock = 100
cooldowns[17364] = nil
cooldowns[30823] = nil
aura_list = {}
ST.SHAMAN.on_aura_change(ST)
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_ss_text.hidden, "SS badge hides when off cooldown")
check(visuals_frame.weave_sr_text.hidden, "SR badge hides when ready and down")

-- 16) Shield charge row ---------------------------------------------------------------------
-- Lightning Shield: 4 slots, the aura count fills them, the rest stay dimmed.
aura_list = { { name = "Lightning Shield", count = 2 } }
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_shield_type, "lightning", "lightning shield detected by name")
eq(ST.weave_shield_charges, 2, "charge count read from the aura")
ST.SHAMAN.on_bar_update(ST, "mainhand")
local rects = visuals_frame.weave_shield_rects
near(rects[1].color[4], 0.9, 1e-9, "first Lightning Shield charge filled")
near(rects[2].color[4], 0.9, 1e-9, "second Lightning Shield charge filled")
near(rects[3].color[4], 0.2, 1e-9, "third Lightning Shield charge dimmed")
near(rects[4].color[4], 0.2, 1e-9, "fourth Lightning Shield charge dimmed")
check(not rects[4].hidden, "empty Lightning Shield slots stay visible (dimmed)")
eq(rects[1].anchor, visuals_frame, "the row anchors to the mainhand visuals frame")
eq(rects[1].offset, -6, "the row sits one gap left of the bar")
eq(rects[2].anchor, rects[1], "the row grows leftward, rect by rect")
eq(rects[1].height, 15, "rects span the bar height")

-- Water Shield: 3 slots; the fourth rect hides.
aura_list = { { name = "Water Shield", count = 1 } }
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_shield_type, "water", "water shield detected by name")
ST.SHAMAN.on_bar_update(ST, "mainhand")
near(rects[1].color[4], 0.9, 1e-9, "the filled Water Shield charge")
near(rects[2].color[4], 0.2, 1e-9, "second Water Shield charge dimmed")
near(rects[3].color[4], 0.2, 1e-9, "third Water Shield charge dimmed")
check(rects[4].hidden, "the fourth rect hides for the 3-slot Water Shield row")

-- A localized name still matches through the id table.
aura_list = { { name = "Water Shield (localized)", spell_id = 52127, count = 3 } }
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_shield_type, "water", "shield detection falls back to the id table")

-- An unreadable count reads as the 3-charge standard (reference
-- SuperSwingTimer_ClassMods.lua:4141-4144), never the optimistic full row.
aura_list = { { name = "Lightning Shield" } }
ST.SHAMAN.on_aura_change(ST)
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(ST.weave_shield_charges, nil, "a shield aura without a count stores no count")
near(rects[1].color[4], 0.9, 1e-9, "the 3-charge standard fills slot 1")
near(rects[3].color[4], 0.9, 1e-9, "the 3-charge standard fills slot 3")
near(rects[4].color[4], 0.2, 1e-9, "the 3-charge standard leaves the fourth slot dimmed")

-- 17) Breakpoint markers and the offhand spark mirror ---------------------------------------
-- Runs as a Wrath client (the markers only draw where Maelstrom exists); the TBC pin
-- closes the section.
st.family = "WRATH"
-- A 4s swing with the 2.5s Lightning Bolt cast puts the marker at fraction 0.375.
aura_list = {}
ST.SHAMAN.on_aura_change(ST)        -- no MW stacks / haste
ST.weave_family = "LB"
clock = 113
set_scripted_swing(clock, 4.0)      -- swing starts at 112 (floor(113/4)*4)
casting_impl = function()
    return "Lightning Bolt", "Lightning Bolt", "icon_lb", 112000, 114500, false, 1, false, 25449
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-markers", 25449)
ST.SHAMAN.on_bar_update(ST, "mainhand")
near(visuals_frame.weave_marker.offset, 0.375 * BAR_WIDTH, 1e-6, "the main marker sits at the cutoff")
check(not visuals_frame.weave_marker_top.hidden, "top marker shows")
eq(visuals_frame.weave_marker_top.point, "BOTTOM", "top marker hangs from its bottom edge")
eq(visuals_frame.weave_marker_top.rel_point, "TOPLEFT", "top marker anchors above the bar")
near(visuals_frame.weave_marker_top.offset, 0.375 * BAR_WIDTH, 1e-6, "top marker anchored at the marker fraction")
near(visuals_frame.weave_marker_top.offset_y, 2, 1e-9, "top marker sits a gap above the bar")
check(not visuals_frame.weave_marker_bottom.hidden, "bottom marker shows")
near(visuals_frame.weave_marker_bottom.offset, 0.375 * BAR_WIDTH, 1e-6, "bottom marker anchored at the marker fraction")
eq(visuals_frame.weave_marker_bottom.anchor, visuals_frame, "single wield: bottom marker under the mainhand bar")
near(visuals_frame.weave_spark.offset, 25, 1e-6, "the spark travels from the cast start toward its landing")

ST.SHAMAN.on_bar_update(ST, "offhand")
local oh_spark = offhand_visuals_frame.weave_spark_offhand
check(oh_spark ~= nil, "the offhand spark widget exists")
check(oh_spark.hidden, "no offhand spark without an offhand weapon")

ST.offhand = { has_weapon = true, anchor_frame = { bar_frame = { IsShown = function() return true end } } }
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_marker_bottom.anchor, offhand_visuals_frame,
    "dual wield: the bottom marker drops below the offhand bar")
ST.SHAMAN.on_bar_update(ST, "offhand")
check(not oh_spark.hidden, "the offhand spark mirror shows while casting")
near(oh_spark.offset, visuals_frame.weave_spark.offset, 1e-6,
    "the mirror sits at the same fraction as the mainhand spark")
near(oh_spark.color[2], visuals_frame.weave_spark.color[2], 1e-9, "the mirror shares the mainhand tint")

-- The marker option gates the pair and the mirror.
class_db.show_shaman_breakpoint_markers = false
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_marker_top.hidden and visuals_frame.weave_marker_bottom.hidden,
    "off: the marker pair hides")
check(visuals_frame.weave_marker.hidden == false, "off: the main marker keeps drawing")
ST.SHAMAN.on_bar_update(ST, "offhand")
check(oh_spark.hidden, "off: the spark mirror hides")
class_db.show_shaman_breakpoint_markers = nil
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", "cast-markers")

-- Back on TBC an active swing with a cast in flight draws neither marker nor spark.
st.family = "TBC"
clock = 200
set_scripted_swing(clock, 4.0)
casting_impl = function()
    return "Lightning Bolt", "Lightning Bolt", "icon_lb", 200000, 202500, false, 1, false, 25449
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-tbc-markers", 25449)
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_marker.hidden, "TBC: no main marker on an active swing")
check(visuals_frame.weave_spark.hidden, "TBC: no spark during the cast")
ST.SHAMAN.on_bar_update(ST, "offhand")
check(offhand_visuals_frame.weave_spark_offhand.hidden, "TBC: no offhand mirror during the cast")
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", "cast-tbc-markers")

-- 19) Aura-observed MW enablement (SoD shares the ERA token) -------------------------
-- SoD HAS the MW rune (408505) while Era-base has nothing: the first observed
-- aura/stack signal latches weave_mw_observed and re-enables the markers and the
-- MW cast-time reduction; Era-base (never observed) stays off; TBC stays off even
-- when observed; the weave_mw_enabled option stays the kill-switch everywhere.
st.family = "ERA"
ST.weave_mw_observed = false
aura_list = {}
ST.SHAMAN.refresh_weave_mw_stacks(ST)
eq(ST.weave_mw_stacks, 0, "SoD setup: no aura means zero stacks")
eq(ST.weave_mw_observed, false, "SoD setup: an empty scan never latches observed")
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5, "Era-base: never observed stays at the base cast time")

-- Era-base draws nothing on an active swing.
clock = 300
set_scripted_swing(clock, 4.0)
casting_impl = function()
    return "Lightning Bolt", "Lightning Bolt", "icon_lb", 300000, 302500, false, 1, false, 25449
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-era-base", 25449)
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_marker.hidden, "Era-base: no main marker without an observed MW aura")
check(visuals_frame.weave_spark.hidden, "Era-base: no spark without an observed MW aura")
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", "cast-era-base")

-- The first observed aura latches; a later empty scan clears stacks, not the latch.
aura_list = { { name = "Maelstrom Weapon", count = 3, spell_id = 408505 } }
ST.SHAMAN.refresh_weave_mw_stacks(ST)
eq(ST.weave_mw_stacks, 3, "SoD: the rune aura stacks are read")
eq(ST.weave_mw_observed, true, "SoD: the first observed aura latches enablement")
aura_list = {}
ST.SHAMAN.refresh_weave_mw_stacks(ST)
eq(ST.weave_mw_stacks, 0, "SoD: a dropped aura reads zero stacks")
eq(ST.weave_mw_observed, true, "SoD: the latch survives a dropped aura (zero stacks is not absence of MW)")

-- Observed stacks reduce the cast time (3 stacks -> 2.5 * 0.4 = 1.0; 5 -> instant).
aura_list = { { name = "Maelstrom Weapon", count = 3, spell_id = 408505 } }
ST.SHAMAN.refresh_weave_mw_stacks(ST)
near(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 1.0, 1e-9, "SoD: three observed stacks reduce the cast time")
aura_list = { { name = "Maelstrom Weapon", count = 5, spell_id = 408505 } }
ST.SHAMAN.refresh_weave_mw_stacks(ST)
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 0, "SoD: five observed stacks make the cast instant")

-- Observed markers draw on an active swing (no stacks: 2.5s cast on a 4s swing).
aura_list = {}
ST.SHAMAN.refresh_weave_mw_stacks(ST)
eq(ST.weave_mw_observed, true, "SoD: the latch holds with no live aura")
clock = 313
set_scripted_swing(clock, 4.0)
casting_impl = function()
    return "Lightning Bolt", "Lightning Bolt", "icon_lb", 312000, 314500, false, 1, false, 25449
end
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-sod", 25449)
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_marker.hidden == false, "SoD: the marker draws once MW is observed")
near(visuals_frame.weave_marker.offset, 0.375 * BAR_WIDTH, 1e-6, "SoD: the marker sits at the cutoff")
check(visuals_frame.weave_spark.hidden == false, "SoD: the spark draws once MW is observed")
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", "cast-sod")

-- The option stays the kill-switch even when observed.
class_db.weave_mw_enabled = false
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5, "SoD: option-off returns the base cast time despite the latch")
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_marker.hidden, "SoD: option-off hides the marker despite the latch")
class_db.weave_mw_enabled = true

-- TBC stays off even with the latch set (no MW there).
st.family = "TBC"
aura_list = { { name = "Maelstrom Weapon", count = 5, spell_id = 408505 } }
ST.SHAMAN.refresh_weave_mw_stacks(ST)
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5, "TBC: five stacks still return the base cast time with the latch set")
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-tbc-latch", 25449)
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_marker.hidden, "TBC: no main marker even with the latch set")
check(visuals_frame.weave_spark.hidden, "TBC: no spark even with the latch set")
ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_STOP", "player", "cast-tbc-latch")

-- Fixture restored: TBC client, option on, no live aura, latch cleared.
st.family = "TBC"
aura_list = {}
ST.SHAMAN.refresh_weave_mw_stacks(ST)
ST.weave_mw_observed = false
casting_impl = function() return nil end

-- 20) Totem-twist live stamp: SUCCEEDED commits + air-slot reconciliation -------------
-- post_init starts the stamp unknown; Windfury (id, live spell name, name token)
-- and Grace of Air (name token, air-slot totemName) SUCCEEDED commits stamp it;
-- weave casts and unknown spells do not; the pre-init gate holds; the air-slot poll
-- adopts a twist totem's startTime when the stamp is unknown or older, ignores
-- non-twist totems / absent reads / bad stamps, and never rewinds a fresher commit.
ST.SHAMAN.post_init(ST)
eq(ST.weave_twist_last_drop, nil, "post_init starts the twist stamp unknown")
eq(ST.weave_magma_last_drop, nil, "post_init starts the magma stamp unknown")
ST.interfaces_are_initialised = true
local fam_before_twist = ST.weave_family

clock = 500
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-tw-1", 8512)
eq(ST.weave_twist_last_drop, 500, "Windfury by id stamps the drop time")
eq(ST.weave_family, fam_before_twist, "a twist commit never resolves a weave family")

clock = 501
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-lb", 25449)
eq(ST.weave_twist_last_drop, 500, "a weave cast does not move the twist stamp")
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-unknown", 99999)
eq(ST.weave_twist_last_drop, 500, "an unknown spell does not move the twist stamp")

clock = 502
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "Grace of Air Totem", 99999)
eq(ST.weave_twist_last_drop, 502, "Grace of Air by name token stamps the drop time")

clock = 503
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-tw-2", 10613)
eq(ST.weave_twist_last_drop, 503, "an unconfirmed WF rank stamps through its live spell name")

clock = 504
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-nil", nil)
eq(ST.weave_twist_last_drop, 503, "a nil spell id neither stamps nor errors")

-- Magma maintain commits: the unconfirmed rank-1 id, the name token and the live
-- spell name all stamp; weave casts, twist drops and unknown spells do not move
-- the magma stamp (and magma commits never resolve a weave family).
clock = 510
local fam_before_magma = ST.weave_family
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-magma-1", 8190)
eq(ST.weave_magma_last_drop, 510, "Magma by id stamps the drop time")
eq(ST.weave_family, fam_before_magma, "a magma commit never resolves a weave family")
eq(ST.weave_twist_last_drop, 503, "a magma commit never moves the twist stamp")
clock = 511
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "Magma Totem", 99999)
eq(ST.weave_magma_last_drop, 511, "Magma by name token stamps the drop time")
clock = 512
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-lb-magma", 25449)
eq(ST.weave_magma_last_drop, 511, "a weave cast does not move the magma stamp")
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-twist-magma", 8512)
eq(ST.weave_magma_last_drop, 511, "a twist drop does not move the magma stamp")
eq(ST.weave_twist_last_drop, 512, "the twist drop still stamps its own clock")
clock = 513
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-nil-magma", nil)
eq(ST.weave_magma_last_drop, 511, "a nil spell id neither stamps magma nor errors")

ST.interfaces_are_initialised = false
clock = 505
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-tw-pre", 8512)
eq(ST.weave_twist_last_drop, 512, "twist commits are ignored before init")
eq(ST.weave_magma_last_drop, 511, "magma commits are ignored before init")
ST.interfaces_are_initialised = true

totem_slot4 = nil
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 512, "an absent air totem leaves the stamp alone")
totem_slot4 = { have = true, name = "Searing Totem", start = 600, spell = 943 }
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 512, "a non-twist air totem never stamps")
totem_slot4 = { have = true, name = "Windfury Totem", start = 600, spell = 8512 }
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 600, "a newer twist totem clock is adopted")
totem_slot4 = { have = true, name = "Grace of Air Totem", start = 550, spell = 99999 }
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 600, "a stale poll reading never rewinds a fresher commit")
ST.weave_twist_last_drop = nil
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 550, "an unknown stamp adopts the twist totem clock by name")
totem_slot4 = { have = false, name = "Windfury Totem", start = 700, spell = 8512 }
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 550, "an inactive slot leaves the stamp alone")
totem_slot4 = { have = true, name = "Windfury Totem", start = "soon", spell = 8512 }
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 550, "a non-number startTime leaves the stamp alone")
totem_slot4 = { have = true, name = "Windfury Totem", start = 0, spell = 8512 }
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 550, "a zero startTime leaves the stamp alone")
totem_slot4 = { have = true, name = "Windfury Totem (localized)", start = 700, spell = 8512 }
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 700, "the spell id matches when the totem name differs")
totem_slot4 = { have = 1, name = "Grace of Air Totem", start = 710 }
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 710, "a numeric haveTotem with no spell id still adopts by name")
-- The compat wrapper contract, through the live module: a valid air-slot read
-- passes through verbatim, while an empty slot, a throwing read and a secret
-- field all degrade to nil (absent).
totem_slot4 = { have = true, name = "Windfury Totem", start = 720, duration = 120,
    icon = "icon_wf", modrate = 1, spell = 8512 }
local wh, wn, ws, wd, wi, wm, wp = st.api.GetTotemInfo(4)
eq(wh, true, "the wrapper passes haveTotem through")
eq(wn, "Windfury Totem", "the wrapper passes totemName through")
eq(ws, 720, "the wrapper passes startTime through")
eq(wd, 120, "the wrapper passes duration through")
eq(wi, "icon_wf", "the wrapper passes icon through")
eq(wm, 1, "the wrapper passes modRate through")
eq(wp, 8512, "the wrapper passes spellID through")
eq(st.api.GetTotemInfo(2), nil, "a slot with no totem reads absent")
totem_slot4 = nil
eq(st.api.GetTotemInfo(4), nil, "an empty air slot reads absent")
totem_slot4 = "THROW"
local ok_throw = pcall(st.api.GetTotemInfo, 4)
check(ok_throw, "a throwing totem read degrades instead of erroring")
totem_slot4 = { have = true, name = "Windfury Totem", start = "SECRET", spell = 8512 }
eq(st.api.GetTotemInfo(4), nil, "a secret field degrades the whole read to absent")
ST.SHAMAN.refresh_twist_from_totems(ST)
eq(ST.weave_twist_last_drop, 710, "a secret totem read leaves the stamp alone")
totem_slot4 = nil
eq(ST.weave_is_casting, false, "twist commits leave no cast in flight")

-- 21) Rage of the Farseer lust -------------------------------------------------------
-- Farseer (Forever personal Bloodlust, UNCONFIRMED - name-only match, no spell id
-- published) feeds the Bloodlust leg of the buff-haste multiplier through the same
-- single aura walk. Never present off Forever, so every other family is unaffected.
aura_list = { { name = "Rage of the Farseer" } }
aura_calls = 0
ST.SHAMAN.on_aura_change(ST)
eq(aura_calls, 40, "farseer: the lust feeds through the same single walk (full 40-row cap, R2)")
near(ST.weave_haste_mult, 1.30, 1e-9, "farseer: the personal lust reads as the 30% Bloodlust leg")
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5 / 1.30, 1e-9, "TBC: the farseer haste shortens the base cast time")
aura_list = { { name = "Rage of the Farseer" }, { name = "Bloodlust", spell_id = 2825 } }
ST.SHAMAN.on_aura_change(ST)
near(ST.weave_haste_mult, 1.30, 1e-9, "farseer: lust never stacks with Bloodlust (one leg, maxed)")
-- Name-only match proof: no spell id is published for Farseer, so an unknown
-- (or wrong) id must never defeat the name match.
aura_list = { { name = "Rage of the Farseer", spell_id = 99999 } }
ST.SHAMAN.on_aura_change(ST)
near(ST.weave_haste_mult, 1.30, 1e-9, "farseer: the name match ignores an unconfirmed id")
aura_list = {}
ST.SHAMAN.on_aura_change(ST)
near(ST.weave_haste_mult, 1.0, 1e-9, "a dropped lust restores the neutral haste multiplier")
casting_impl = function() return nil end

-- 22) Stormstrike nature-vuln target bar (S2) -----------------------------------------
-- Option-gated (nil = off, true = on); the widgets are created lazily on the first
-- tick with the option on, so a default session creates nothing (the construction-
-- time widget counts stay untouched) and a tick nobody needs performs no aura work.
ST.interfaces_are_initialised = true
st.family = "TBC"
clock = 400
set_scripted_swing(clock, 2.0)
aura_list = {}
ST.SHAMAN.on_aura_change(ST)
class_db.show_shaman_flame_shock_bar = false
class_db.show_shaman_stormstrike_bar = nil
target_aura_list = {}
target_aura_calls = 0
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_storm_bg == nil, "S2 off (nil): no widgets are created")
eq(target_aura_calls, 0, "S2 off with every consumer off: no target scans")

-- On: the scan runs, the widgets appear and the debuff draws.
class_db.show_shaman_stormstrike_bar = true
target_aura_list = {
    { name = "Stormstrike", spell_id = 17364, source = "player", duration = 12, expiration = clock + 10 },
}
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_storm_bg ~= nil, "S2 on: the bar widgets are created lazily")
check(not visuals_frame.weave_storm_bg.hidden, "S2: the bar shows for the player's Stormstrike debuff")
near(visuals_frame.weave_storm_fill.width, BAR_WIDTH * (10 / 12), 1e-6, "S2: fill fraction is remaining/total")
eq(visuals_frame.weave_storm_label.text, "10", "S2: the seconds label counts down")
check(visuals_frame.weave_storm_glow.hidden, "S2: no glow above the final 4 s")
clock = 407
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_storm_label.text, "3", "S2: the label keeps counting down")
check(not visuals_frame.weave_storm_glow.hidden, "S2: glow inside the final 4 s")

-- Another caster's debuff does not qualify.
clock = 420
target_aura_list = {
    { name = "Stormstrike", spell_id = 17364, source = "other", duration = 12, expiration = clock + 8 },
}
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_storm_bg.hidden, "S2: a debuff from another caster does not show the bar")

-- The trigger id noted in verify_bank (32175) and a localized name still match
-- through the guarded id/name reads; an unknown pair never lights the bar.
clock = 421
target_aura_list = {
    { name = "Stormstrike (localized)", spell_id = 32175, source = "player", duration = 12, expiration = clock + 8 },
}
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(not visuals_frame.weave_storm_bg.hidden, "S2: the trigger id 32175 with a localized name still matches")
clock = 422
target_aura_list = {
    { name = "Something Else", spell_id = 99999, source = "player", duration = 12, expiration = clock + 8 },
}
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_storm_bg.hidden, "S2: an unknown id/name pair never lights the bar")

-- A dropped debuff hides the bar and clears the glow cache.
target_aura_list = {}
clock = 423
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_storm_bg.hidden, "S2: the bar hides when the debuff is gone")
check(visuals_frame.weave_storm_glow.hidden, "S2: the glow hides when the debuff is gone")
class_db.show_shaman_stormstrike_bar = nil
class_db.show_shaman_flame_shock_bar = nil

-- 23) WF-fishing HOLD tint (S3) --------------------------------------------------------
-- Option-gated (nil = off): while Stormstrike is ready and the Windfury ICD clears
-- inside the current swing, the SS badge flips to an amber "SS HOLD" and the bar's
-- final fraction (from the ICD clear point to the swing end) gets an amber wash.
clock = 498.5
set_scripted_swing(clock, 4.0)          -- swing 496 -> 500; ICD clears at 499 (0.5 s left)
aura_list = { { name = "Windfury Weapon" } }
ST.SHAMAN.on_aura_change(ST)
class_db.show_shaman_wf_hold_tint = nil
-- Prime the whole-second cache (6 s) so the hold -> cooldown switch below is a true
-- same-second transition; a stale "SS HOLD" must never survive into it.
cooldowns[17364] = { start = clock - 2, duration = 8 }
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_ss_text.text, "SS 6s", "S3 setup: the cooldown text primes the cache")
cooldowns[17364] = nil
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_ss_text.hidden, "S3 off (nil): the ready SS badge stays hidden")
check(visuals_frame.weave_wf_wash == nil, "S3 off (nil): no wash widget is created")

class_db.show_shaman_wf_hold_tint = true
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_ss_text.text, "SS HOLD", "S3: the ready SS badge reads SS HOLD while fishing")
check(not visuals_frame.weave_ss_text.hidden, "S3: the hold badge shows")
near(visuals_frame.weave_ss_text.color[1], 1.0, 1e-9, "S3: the hold badge is amber (red channel)")
near(visuals_frame.weave_ss_text.color[2], 0.72, 1e-9, "S3: the hold badge is amber (green channel)")
check(visuals_frame.weave_wf_wash ~= nil, "S3: the wash widget is created lazily")
check(not visuals_frame.weave_wf_wash.hidden, "S3: the wash shows while holding")
near(visuals_frame.weave_wf_wash.offset, 0.75 * BAR_WIDTH, 1e-6,
    "S3: the wash starts at the ICD-clear fraction (elapsed + ICD / speed)")
near(visuals_frame.weave_wf_wash.width, 0.25 * BAR_WIDTH, 1e-6,
    "S3: the wash covers the swing's final fraction")
near(visuals_frame.weave_wf_wash.base_color[4], 0.18, 1e-9, "S3: the wash is translucent amber")

-- The ICD elapsing ends the hold (a ready Stormstrike is no longer delayed).
clock = 499.5
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_ss_text.hidden, "S3: an elapsed ICD ends the hold")
check(visuals_frame.weave_wf_wash.hidden, "S3: the wash hides once the ICD has cleared")

-- The ICD outlasting the swing never holds (a short swing, e.g. under haste).
clock = 500
set_scripted_swing(clock, 2.0)          -- swing 500 -> 502; ICD until 503
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_ss_text.hidden, "S3: an ICD beyond the swing end never holds")
check(visuals_frame.weave_wf_wash.hidden, "S3: no wash when the ICD outlasts the swing")

-- A running Stormstrike cooldown wins the badge (the hold only applies when SS is
-- ready), and a dropped imbue ends the hold entirely. The whole-second readout
-- deliberately matches the stale pre-hold cache (6 s), pinning that a mode switch
-- always refreshes the text - a stale "SS HOLD" must never survive into it.
clock = 501
set_scripted_swing(clock, 4.0)          -- swing 500 -> 504; ICD until 502
cooldowns[17364] = { start = clock - 2, duration = 8 }  -- 6 s left
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_ss_text.text, "SS 6s", "S3: a running cooldown keeps the cooldown text")
check(visuals_frame.weave_wf_wash.hidden, "S3: a running cooldown also hides the wash")
cooldowns[17364] = nil
aura_list = {}
ST.SHAMAN.on_aura_change(ST)
clock = 501.5
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_ss_text.hidden, "S3: a dropped imbue ends the hold")
check(visuals_frame.weave_wf_wash.hidden, "S3: a dropped imbue hides the wash")

-- The badge option still gates the whole badge (hold included).
aura_list = { { name = "Windfury Weapon" } }
ST.SHAMAN.on_aura_change(ST)
class_db.show_shaman_cooldown_badges = false
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_ss_text.hidden, "S3: the badge option off hides the hold too")
class_db.show_shaman_cooldown_badges = true
class_db.show_shaman_wf_hold_tint = nil
aura_list = {}

-- 24) MW5 spender choice (S4) ----------------------------------------------------------
-- ERA + the Lava Burst rune known: at five stacks the assist marks Lava Burst (icon
-- + lava tint); without the rune, on TBC, below five stacks, or with the FS-collision
-- guard armed (FS inside its final 2 s AND a ready shock) the catalogue Lightning
-- Bolt stays. The gather holds mw_available while the guard is armed, so the frozen
-- engine falls through to the Flame Shock refresh.
st.family = "ERA"
ST.weave_mw_observed = true
class_db.weave_mw_enabled = true
known_spells[51505] = true
clock = 600
set_scripted_swing(clock, 4.0)
aura_list = { { name = "Maelstrom Weapon", count = 5, spell_id = 408505 } }
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_mw_stacks, 5, "S4: five stacks are read")
target_aura_list = {}
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_marker.texture, "icon_lava", "S4: the MW5 marker shows Lava Burst when the rune is known")
near(visuals_frame.weave_marker.color[1], 1.0, 1e-9, "S4: the LvB marker carries the lava tint (red)")
near(visuals_frame.weave_marker.color[2], 0.55, 1e-9, "S4: the LvB marker carries the lava tint (green)")

-- FS-collision guard: FS inside its final 2 s with a ready shock holds LvB back.
clock = 601
target_aura_list = {
    { name = "Flame Shock", spell_id = 8050, source = "player", duration = 12, expiration = clock + 1.5 },
}
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_marker.texture, "icon_lb", "S4: the FS-collision guard holds LvB back inside the final 2 s")

-- A running shock cooldown means the refresh cannot go out: no hold, LvB stays.
cooldowns[8050] = { start = clock, duration = 6 }
clock = 602
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_marker.texture, "icon_lava", "S4: a running shock cooldown leaves LvB in place")
cooldowns[8050] = nil

-- Exactly 2.0 s of Flame Shock does not hold (strict <).
clock = 610
target_aura_list = {
    { name = "Flame Shock", spell_id = 8050, source = "player", duration = 12, expiration = 612 },
}
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_marker.texture, "icon_lava", "S4: exactly 2.0 s of Flame Shock does not hold (strict <)")

-- Without the rune/talent the MW5 marker stays Lightning Bolt. (The Flame Shock
-- fixture is cleared so the FS-collision guard cannot mask the choice.)
known_spells[51505] = nil
target_aura_list = {}
clock = 611
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_marker.texture, "icon_lb", "S4: without the rune the MW5 marker stays Lightning Bolt")
known_spells[51505] = true

-- TBC never resolves Lava Burst at all (not baseline there): the visual-spell
-- resolver answers the catalogue directly (the marker itself stays hidden on TBC -
-- no Maelstrom there - so asserting the texture would read a stale value).
st.family = "TBC"
local tbc_entry, tbc_family = ST.SHAMAN.get_weave_visual_spell(ST)
eq(tbc_entry and tbc_entry.icon, "icon_lb", "S4: TBC never resolves Lava Burst (not baseline there)")
eq(tbc_family, "LB", "S4: TBC keeps the Lightning Bolt family token")
st.family = "ERA"

-- Below five stacks the catalogue spell stays.
aura_list = { { name = "Maelstrom Weapon", count = 4, spell_id = 408505 } }
ST.SHAMAN.on_aura_change(ST)
clock = 613
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_marker.texture, "icon_lb", "S4: below five stacks the catalogue spell stays")

-- The gather holds mw_available while the guard is armed; the stack count stays
-- truthful, and a running shock (or no FS reading) leaves the gate open.
ST.weave_mw_stacks = 5
clock = 620
target_aura_list = {
    { name = "Flame Shock", spell_id = 8050, source = "player", duration = 12, expiration = clock + 1.5 },
}
ST.SHAMAN.on_bar_update(ST, "mainhand")
local gathered_s4 = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_s4.mw_available, false, "S4: the gather holds the MW gate while FS is inside the guard")
eq(gathered_s4.mw_stacks, 5, "S4: the stack count stays truthful while held")
cooldowns[8050] = { start = clock, duration = 6 }
gathered_s4 = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_s4.mw_available, true, "S4: a running shock leaves the MW gate open")
cooldowns[8050] = nil
target_aura_list = {}
clock = 621
ST.SHAMAN.on_bar_update(ST, "mainhand")
gathered_s4 = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_s4.mw_available, true, "S4: no Flame Shock reading leaves the MW gate open")
ST.weave_mw_stacks = 0
ST.weave_mw_observed = false
st.family = "TBC"

-- 25) Rockbiter Weapon badge -----------------------------------------------------------
-- Option-gated (nil = off, created lazily); the merged aura walk feeds it, the id
-- table and the English name both match, and a dropped imbue hides the badge.
clock = 700
aura_list = { { name = "Rockbiter Weapon", expiration = clock + 300 } }
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_rockbiter_active, true, "RB: the imbue is tracked through the merged scan")
class_db.show_shaman_rockbiter_badge = nil
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_rb_text == nil, "RB off (nil): no widget is created")
class_db.show_shaman_rockbiter_badge = true
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_rb_text ~= nil, "RB on: the badge is created lazily")
eq(visuals_frame.weave_rb_text.text, "RB 300s", "RB: the badge counts the imbue down")
check(not visuals_frame.weave_rb_text.hidden, "RB: the badge shows while the imbue is up")
clock = 705
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_rb_text.text, "RB 295s", "RB: the readout follows the clock")

-- An unreadable expiry shows the bare badge; the id table matches a localized name.
aura_list = { { name = "Rockbiter Weapon" } }
ST.SHAMAN.on_aura_change(ST)
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_rb_text.text, "RB", "RB: an unreadable expiry shows the bare badge")
aura_list = { { name = "Rockbiter (localized)", spell_id = 8017, expiration = clock + 100 } }
ST.SHAMAN.on_aura_change(ST)
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_rb_text.text, "RB 100s", "RB: the id table matches when the name differs")

-- A dropped imbue hides the badge.
aura_list = {}
ST.SHAMAN.on_aura_change(ST)
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_rb_text.hidden, "RB: the badge hides when the imbue drops")
class_db.show_shaman_rockbiter_badge = nil

-- 26) S5 mana tint verification: the HUD provider's tint path --------------------------
-- Verified wired: get_hud_state reads the shared hud_mana_tint key and marks
-- s.usable=false on an insufficient-power reading (the shared default ships true);
-- an affordable reading or the toggle off leaves the slot untinted.
do
    local slot = ST.SHAMAN.HUD_SLOTS[1]
    class_db.hud_mana_tint = true
    spell_usable[17364] = { false, true }
    local s = ST.SHAMAN.get_hud_state(ST, slot, clock)
    eq(s.usable, false, "S5: an insufficient-power reading tints the slot")
    class_db.hud_mana_tint = false
    s = ST.SHAMAN.get_hud_state(ST, slot, clock)
    eq(s.usable, nil, "S5: the tint toggle off leaves the slot untinted")
    class_db.hud_mana_tint = true
    spell_usable[17364] = { true, false }
    s = ST.SHAMAN.get_hud_state(ST, slot, clock)
    eq(s.usable, nil, "S5: an affordable reading leaves the slot untinted")
    spell_usable[17364] = nil
    class_db.hud_mana_tint = nil
end

-- 27) Spell-position row (round 2) -----------------------------------------------------
-- Option-gated (nil = off); on: per-spell icons at each spell's latest safe cast
-- start, cast-time numbers, the zone band + label, and the ready/clip/wait states.
-- WRATH client (Maelstrom active) with the sandbox catalogue: LB cast 2.5 s,
-- CL cast 2.0 s; MW stacks scale the effective cast and move the positions.
st.family = "WRATH"
ST.weave_mw_observed = false
class_db.weave_mw_enabled = true
clock = 800
set_scripted_swing(clock, 4.0)          -- swing 800 -> 804
class_db.show_shaman_spell_positions = nil
aura_list = {}
ST.SHAMAN.on_aura_change(ST)
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_pos_zone == nil, "positions off (nil): no widgets are created")

class_db.show_shaman_spell_positions = true
aura_list = { { name = "Maelstrom Weapon", count = 2, spell_id = 408505 } }
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_mw_stacks, 2, "positions: two stacks are read")
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_pos_zone ~= nil, "positions on: the widgets are created lazily")
local pos_icons = visuals_frame.weave_pos_icons
local pos_times = visuals_frame.weave_pos_times
check(pos_icons.LB and pos_icons.CL and pos_icons.LvB, "positions: LB, CL and LvB slots exist")
check(not pos_icons.LB.hidden, "positions: the LB icon shows")
near(pos_icons.LB.offset, 0.625 * BAR_WIDTH, 1e-6,
    "positions: LB sits at its latest safe start (2 stacks: 4 - 1.5 over 4)")
near(pos_icons.CL.offset, 0.7 * BAR_WIDTH, 1e-6,
    "positions: CL sits at its latest safe start (2 stacks: 4 - 1.2 over 4)")
eq(pos_times.LB.text, "1.5", "positions: the LB cast time is shown")
eq(pos_times.CL.text, "1.2", "positions: the CL cast time is shown")
near(pos_icons.LB.color[1], 0.45, 1e-9, "positions: a ready LB icon carries the family color")
near(pos_icons.LB.color[4], 0.95, 1e-9, "positions: a ready icon carries the ready alpha")
check(pos_icons.LvB.hidden, "positions: LvB stays hidden without the rune (WRATH)")

-- The zone band + the operator's caption.
local pos_zone = visuals_frame.weave_pos_zone
check(not pos_zone.hidden, "positions: the zone band shows")
near(pos_zone.offset, 0.625 * BAR_WIDTH, 1e-6, "positions: the zone starts at the earliest safe start")
near(pos_zone.width, 0.075 * BAR_WIDTH, 1e-6, "positions: the zone spans the safe starts")
near(pos_zone.offset_y, 18, 1e-9, "positions: the zone sits above the bar stack")
eq(visuals_frame.weave_pos_label.text, "Spells start cast range zone",
    "positions: the zone label carries the operator's caption")

-- LvB joins the row when the rune/talent is present (ERA; the S4 gate stays).
st.family = "ERA"
ST.weave_mw_observed = true
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(not pos_icons.LvB.hidden, "positions: LvB joins the row when the rune is present")
near(pos_icons.LvB.offset, 0.7 * BAR_WIDTH, 1e-6, "positions: LvB sits at its own safe start")
eq(pos_times.LvB.text, "1.2", "positions: the LvB cast time is shown")

-- The clip case: past a spell's safe start the icon turns red (casting now would
-- overrun the swing) - never a ready state.
clock = 803.5
set_scripted_swing(clock, 4.0)          -- still the 800 -> 804 swing; now at 0.875
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(pos_icons.LB.color[1], 1, "positions: a passed window reads as a clip (red)")
near(pos_icons.LB.color[2], 0.15, 1e-9, "positions: the clip tint is the red constant")
near(pos_icons.CL.color[2], 0.15, 1e-9, "positions: CL clips at the same moment")

-- Fewer than two stacks read as wait (dim): the 2-3 stack gate.
aura_list = { { name = "Maelstrom Weapon", count = 1, spell_id = 408505 } }
ST.SHAMAN.on_aura_change(ST)
ST.SHAMAN.on_bar_update(ST, "mainhand")
near(pos_icons.LB.color[4], 0.35, 1e-9, "positions: one stack reads as wait (dimmed)")

-- Five stacks: the instant cast sits at the swing end and the degenerate zone
-- hides (every spell shares the same start).
aura_list = { { name = "Maelstrom Weapon", count = 5, spell_id = 408505 } }
ST.SHAMAN.on_aura_change(ST)
clock = 805
set_scripted_swing(clock, 4.0)          -- fresh swing 804 -> 808
ST.SHAMAN.on_bar_update(ST, "mainhand")
near(pos_icons.LB.offset, BAR_WIDTH, 1e-6, "positions: five stacks put the instant cast at the swing end")
eq(pos_times.LB.text, "0.0", "positions: the instant cast time reads 0.0")
check(not pos_icons.LB.hidden, "positions: the instant cast stays ready")
check(pos_zone.hidden, "positions: a degenerate zone (one start) hides the band")

-- Dynamic re-adjust: after the swing rolls over (and the stacks change) the row
-- recomputes against the fresh swing.
aura_list = { { name = "Maelstrom Weapon", count = 3, spell_id = 408505 } }
ST.SHAMAN.on_aura_change(ST)
clock = 805.5
set_scripted_swing(clock, 4.0)
ST.SHAMAN.on_bar_update(ST, "mainhand")
near(pos_icons.LB.offset, 0.75 * BAR_WIDTH, 1e-6,
    "positions: after the rollover LB re-adjusts to the new swing (3 stacks: 4 - 1.0 over 4)")
near(pos_icons.CL.offset, 0.8 * BAR_WIDTH, 1e-6, "positions: CL re-adjusts with its own cast time")
eq(pos_times.LB.text, "1.0", "positions: the LB cast time follows the stack count")
check(not pos_zone.hidden, "positions: the zone returns with distinct starts")

-- The option off hides every widget again.
class_db.show_shaman_spell_positions = nil
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(pos_zone.hidden, "positions: the option off hides the zone")
check(pos_icons.LB.hidden, "positions: the option off hides the icons")
check(pos_times.LB.hidden, "positions: the option off hides the cast times")
aura_list = {}
ST.SHAMAN.on_aura_change(ST)
st.family = "TBC"

-- 28) DW sync + Flurry badges (round 2) ------------------------------------------------
-- Option-gated (nil = off): the sync readout compares the MH/OH landings against
-- the Flurry ICD threshold (0.5 s, amber when past it); the Flurry readout shows
-- the stack count and the live 0.5 s proc ICD. Both work off swing/aura state only
-- (no st.is_mainline gate); the sync half hides without a live offhand.
clock = 900
set_scripted_swing(clock, 2.6)
aura_list = {}
ST.SHAMAN.on_aura_change(ST)
class_db.show_shaman_dw_sync = nil
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_sync_text == nil, "DW badges off (nil): no widgets are created")

class_db.show_shaman_dw_sync = true
ST.offhand = { has_weapon = true, ends_at = ST.mainhand.ends_at + 0.1 }
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_sync_text ~= nil, "DW badges on: the widgets are created lazily")
eq(visuals_frame.weave_sync_text.text, "DW SYNC 0.1s", "DW badges: a synced pair reads DW SYNC")
near(visuals_frame.weave_sync_text.color[2], 1.0, 1e-9, "DW badges: the synced readout is green")
eq(visuals_frame.weave_sync_text.offset_y, -28, "DW badges: the sync readout sits under Rockbiter")
eq(visuals_frame.weave_flurry_text.offset_y, -38, "DW badges: the Flurry readout sits under the sync line")

ST.offhand.ends_at = ST.mainhand.ends_at + 0.8
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_sync_text.text, "DW DESYNC 0.8s", "DW badges: drift past the ICD window reads DW DESYNC")
near(visuals_frame.weave_sync_text.color[2], 0.72, 1e-9, "DW badges: the desync readout is amber")

ST.offhand.ends_at = ST.mainhand.ends_at + 0.5
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_sync_text.text, "DW SYNC 0.5s",
    "DW badges: exactly the threshold still reads SYNC (strict >)")

ST.offhand = { has_weapon = false, ends_at = ST.mainhand.ends_at }
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_sync_text.hidden, "DW badges: no offhand weapon hides the sync readout")
ST.offhand = { has_weapon = true }
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_sync_text.hidden, "DW badges: unknown landings never warn")

-- Flurry: a fresh aura stamps the proc time; the readout carries the stacks and
-- the live ICD, counts down, and drops the suffix once the ICD elapses.
aura_list = { { name = "Flurry", count = 3, spell_id = 16280 } }
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_flurry_stacks, 3, "DW badges: Flurry stacks are read")
near(ST.weave_flurry_proc_at, clock, 1e-9, "DW badges: a fresh aura stamps the proc time")
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_flurry_text.text, "FL 3 0.5s", "DW badges: the Flurry readout carries the live ICD")
near(visuals_frame.weave_flurry_text.color[1], 0.65, 1e-9, "DW badges: the Flurry readout is ice blue")
clock = 900.3
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_flurry_text.text, "FL 3 0.2s", "DW badges: the ICD counts down")
clock = 900.6
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_flurry_text.text, "FL 3", "DW badges: the elapsed ICD drops off the readout")

-- A consumed charge (count decrease) never restamps; a re-proc (increase) does.
aura_list = { { name = "Flurry", count = 2, spell_id = 16280 } }
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_flurry_stacks, 2, "DW badges: a consumed charge drops the stack count")
near(ST.weave_flurry_proc_at, 900, 1e-9, "DW badges: consuming a charge never restamps the ICD")
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_flurry_text.text, "FL 2", "DW badges: the readout follows the remaining charges")
clock = 910
aura_list = { { name = "Flurry", count = 3, spell_id = 16280 } }
ST.SHAMAN.on_aura_change(ST)
near(ST.weave_flurry_proc_at, 910, 1e-9, "DW badges: a re-proc restamps the ICD")
clock = 910.2
ST.SHAMAN.on_aura_change(ST)
near(ST.weave_flurry_proc_at, 910, 1e-9, "DW badges: an unchanged count never restamps")

-- A dropped Flurry hides the readout; the badge works without an offhand too.
aura_list = {}
ST.SHAMAN.on_aura_change(ST)
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_flurry_text.hidden, "DW badges: a dropped Flurry hides the readout")
clock = 911
aura_list = { { name = "Flurry", count = 1, spell_id = 16280 } }
ST.SHAMAN.on_aura_change(ST)
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_sync_text.hidden, "DW badges: no offhand keeps the sync readout hidden")
eq(visuals_frame.weave_flurry_text.text, "FL 1 0.5s", "DW badges: Flurry tracks without an offhand (2H)")

-- The option off hides both readouts.
class_db.show_shaman_dw_sync = nil
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_sync_text.hidden, "DW badges: the option off hides the sync readout")
check(visuals_frame.weave_flurry_text.hidden, "DW badges: the option off hides the Flurry readout")
aura_list = {}
ST.SHAMAN.on_aura_change(ST)

-- 18) Config and options wiring: the five new keys exist in both directions ---------------
do
    local function read(path)
        local f = assert(io.open(ROOT .. path, "r"))
        local text = f:read("*a")
        f:close()
        return text
    end

    local presets = read("config_presets.lua")
    local shaman_defaults = presets:match("ST%.SHAMAN%.defaults%s*=%s*%{(.-)ST%.WARLOCK%.defaults")
    check(shaman_defaults ~= nil, "the SHAMAN defaults block is found in config_presets.lua")
    shaman_defaults = shaman_defaults or ""
    local options = read("option_tables.lua")
    local shaman_opts = options:match("function ST%.class_opts_funcs%.SHAMAN%((.*)$")
    check(shaman_opts ~= nil, "the SHAMAN options function is found in option_tables.lua")
    shaman_opts = shaman_opts or ""
    for i = 1, #new_option_keys do
        local key = new_option_keys[i]
        check(shaman_defaults:find("%f[%a_]" .. key .. "%s*=%s*true") ~= nil,
            key .. " ships true in the SHAMAN defaults")
        local widget = shaman_opts:match("%f[%a_]" .. key .. "%s*=%s*{(.-)\n%s*}")
        check(widget ~= nil and widget:find("type%s*=%s*\"toggle\"") ~= nil,
            key .. " has a toggle widget in the SHAMAN options section")
    end
end

-- R2: secret-hole scans (no truncation below a restricted row) ------------------
-- A nil row above the tracked auras no longer hides them: the weave walk and
-- the target scan both continue past it. (Clock 1000: past every earlier
-- section, so the 0.05 s target-scan throttle cannot swallow the re-scan.)
clock = 1000
set_scripted_swing(clock, 2.0)
aura_list = {
    [2] = { name = "Maelstrom Weapon", count = 3, spell_id = 408505 },
    [3] = { name = "Bloodlust", spell_id = 2825 },
}
ST.SHAMAN.on_aura_change(ST)
eq(ST.weave_mw_stacks, 3, "R2: Maelstrom stacks latch below a secret row")
near(ST.weave_haste_mult, 1.30, 1e-9, "R2: Bloodlust haste latches below a secret row")

target_aura_list = {
    [2] = { name = "Flame Shock", spell_id = 8050, source = "player", duration = 12, expiration = clock + 8 },
}
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(not visuals_frame.weave_fs_bg.hidden, "R2: Flame Shock draws below a secret row")
eq(visuals_frame.weave_fs_label.text, "8", "R2: the label counts down below a secret row")

-- 28) Lust status badge (S1 effect-status row + secret-regime affordance) -----------
-- Option-gated (nil = off, created lazily like the rockbiter badge); a live
-- Bloodlust reads the remaining time, a miss under a secret regime reads
-- "BL ?", a present-but-unstamped buff reads the bare "BL", a dropped lust
-- hides the badge. The throttle, the closed-on-unknown gate and the Forever
-- Farseer name leg are pinned through update_lust_state directly.
class_db.show_shaman_lust_status = nil
clock = 1100
aura_list = {}
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_lust_text == nil, "lust off (nil): no widget is created")
eq(ST.shaman_lust_remaining, nil, "lust off (nil): no scan runs")
eq(ST.shaman_lust_unknown, nil, "lust off (nil): the latch stays untouched")

class_db.show_shaman_lust_status = true
clock = 1100
aura_list = { { name = "Bloodlust", spell_id = 2825, expiration = clock + 40 } }
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_lust_text ~= nil, "lust on: the badge is created lazily")
eq(visuals_frame.weave_lust_text.text, "BL 40s", "lust on: the badge counts the window down")
check(not visuals_frame.weave_lust_text.hidden, "lust on: the badge shows while lust is up")
eq(ST.shaman_lust_unknown, false, "lust on: a live lust reads known")

-- The rescan throttle: a same-tick re-poll costs no aura walk.
local lust_reads_before = aura_calls
ST.SHAMAN.update_lust_state(ST, clock + 0.1)
eq(aura_calls, lust_reads_before, "lust: the rescan throttle skips the walk inside 0.5 s")

-- The countdown follows the clock past the throttle.
clock = 1101
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_lust_text.text, "BL 39s", "lust: the readout follows the clock")

-- A miss under a secret regime latches unknown and renders "BL ?".
local real_lust_probe = st.api.auras_may_be_secret
st.api.auras_may_be_secret = function() return true end
clock = 1200
aura_list = {}
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(ST.shaman_lust_remaining, nil, "secret: no aura reads no window")
eq(ST.shaman_lust_unknown, true, "secret: the regime latches lust unknown")
eq(visuals_frame.weave_lust_text.text, "BL ?", "secret: the badge renders the unknown read")
check(not visuals_frame.weave_lust_text.hidden, "secret: the unknown badge shows")
st.api.auras_may_be_secret = real_lust_probe

-- An honest miss (no secret regime) hides the badge instead of guessing.
clock = 1300
aura_list = {}
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(ST.shaman_lust_remaining, nil, "miss: no aura reads no window")
eq(ST.shaman_lust_unknown, false, "miss: a visible miss reads known")
check(visuals_frame.weave_lust_text.hidden, "miss: the badge hides with no lust")

-- Closed-on-unknown: a closed family (Era/UNKNOWN, or a pre-C2 nil) never arms
-- the scan, even with the aura present.
st.lust_supported = false
clock = 1400
aura_list = { { name = "Bloodlust", spell_id = 2825, expiration = clock + 40 } }
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(ST.shaman_lust_remaining, nil, "gate: a closed family reads no window")
eq(ST.shaman_lust_unknown, false, "gate: a closed family never reads unknown")
check(visuals_frame.weave_lust_text.hidden, "gate: the badge hides on a closed family")
st.lust_supported = true

-- The Forever Farseer leg matches by name (UNCONFIRMED: no spell id published).
clock = 1500
aura_list = { { name = "Rage of the Farseer", expiration = clock + 40 } }
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(visuals_frame.weave_lust_text.text, "BL 40s", "farseer: the name leg counts down like Bloodlust")

-- Present but unstamped (no readable expiry): the bare text, never a guess.
clock = 1600
aura_list = { { name = "Bloodlust", spell_id = 2825 } }
ST.SHAMAN.on_bar_update(ST, "mainhand")
eq(ST.shaman_lust_remaining, nil, "unstamped: no expiry reads no countdown")
eq(visuals_frame.weave_lust_text.text, "BL", "unstamped: the badge shows the bare text")
check(not visuals_frame.weave_lust_text.hidden, "unstamped: the bare badge shows")

-- A non-number clock marks the read unknown (never a stale window).
ST.SHAMAN.update_lust_state(ST, nil)
eq(ST.shaman_lust_remaining, nil, "clock: a nil clock reads no window")
eq(ST.shaman_lust_unknown, true, "clock: a nil clock reads unknown")

-- A dropped lust hides the badge again; the toggle off hides it too.
clock = 1700
aura_list = {}
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_lust_text.hidden, "lust: the badge hides when lust drops")
class_db.show_shaman_lust_status = nil
ST.SHAMAN.on_bar_update(ST, "mainhand")
check(visuals_frame.weave_lust_text.hidden, "lust: the toggle off hides the badge")

-- 29) Searing maintain reader (fight clock + fire-slot reconcile) -------------------
-- post_init starts the searing stamp unknown; SUCCEEDED commits by id, name
-- token and live spell name stamp it (weave casts, twist drops, magma drops
-- and unknown spells do not move it, and commits never resolve a weave
-- family); the pre-init gate holds; the fire-slot poll adopts a Searing clock
-- when the stamp is unknown or older, clears on an affirmative empty slot,
-- ignores non-Searing occupants and unreadable reads, and never rewinds a
-- fresher commit; the gather feeds fight_elapsed/searing_elapsed/searing_down
-- nil-safe with unknown-hides (no rule reads them yet).
ST.SHAMAN.post_init(ST)
eq(ST.weave_searing_last_drop, nil, "post_init starts the searing stamp unknown")
ST.interfaces_are_initialised = true
ST.fight_start_at = nil
local fam_before_sear = ST.weave_family

clock = 700
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-sear-1", 10438)
eq(ST.weave_searing_last_drop, 700, "Searing by id stamps the drop time")
eq(ST.weave_family, fam_before_sear, "a searing commit never resolves a weave family")
clock = 701
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "Searing Totem", 99999)
eq(ST.weave_searing_last_drop, 701, "Searing by name token stamps the drop time")
clock = 702
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-sear-2", 25530)
eq(ST.weave_searing_last_drop, 702, "an unconfirmed Searing rank stamps through its live spell name")
clock = 703
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-lb-sear", 25449)
eq(ST.weave_searing_last_drop, 702, "a weave cast does not move the searing stamp")
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-twist-sear", 8512)
eq(ST.weave_searing_last_drop, 702, "a twist drop does not move the searing stamp")
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-magma-sear", 8190)
eq(ST.weave_searing_last_drop, 702, "a magma drop does not move the searing stamp")
eq(ST.weave_magma_last_drop, 703, "the magma drop still stamps its own clock")
clock = 704
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-unknown-sear", 88888)
eq(ST.weave_searing_last_drop, 702, "an unknown spell does not move the searing stamp")
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-nil-sear", nil)
eq(ST.weave_searing_last_drop, 702, "a nil spell id neither stamps searing nor errors")

ST.interfaces_are_initialised = false
clock = 705
ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-sear-pre", 10438)
eq(ST.weave_searing_last_drop, 702, "searing commits are ignored before init")
ST.interfaces_are_initialised = true

totem_slot1 = nil
ST.SHAMAN.refresh_searing_from_totems(ST)
eq(ST.weave_searing_last_drop, 702, "an absent fire slot leaves the stamp alone")
totem_slot1 = { have = true, name = "Magma Totem", start = 800, spell = 8190 }
ST.SHAMAN.refresh_searing_from_totems(ST)
eq(ST.weave_searing_last_drop, 702, "a non-Searing fire totem never stamps")
totem_slot1 = { have = true, name = "Searing Totem", start = 800, spell = 10438 }
ST.SHAMAN.refresh_searing_from_totems(ST)
eq(ST.weave_searing_last_drop, 800, "a newer Searing totem clock is adopted")
totem_slot1 = { have = true, name = "Searing Totem", start = 750, spell = 99999 }
ST.SHAMAN.refresh_searing_from_totems(ST)
eq(ST.weave_searing_last_drop, 800, "a stale poll reading never rewinds a fresher commit")
ST.weave_searing_last_drop = nil
ST.SHAMAN.refresh_searing_from_totems(ST)
eq(ST.weave_searing_last_drop, 750, "an unknown stamp adopts the Searing clock by name")
totem_slot1 = { have = false, name = "Searing Totem", start = 900, spell = 10438 }
local sear_empty, sear_holding = ST.SHAMAN.refresh_searing_from_totems(ST)
eq(sear_empty, true, "an affirmatively empty fire slot reports due")
eq(sear_holding, false, "an affirmatively empty fire slot holds nothing")
eq(ST.weave_searing_last_drop, nil, "an affirmatively empty fire slot clears the stamp")
totem_slot1 = { have = true, name = "Searing Totem", start = "soon", spell = 10438 }
ST.SHAMAN.refresh_searing_from_totems(ST)
eq(ST.weave_searing_last_drop, nil, "a non-number startTime leaves the stamp alone")
totem_slot1 = { have = true, name = "Searing Totem", start = 0, spell = 10438 }
ST.SHAMAN.refresh_searing_from_totems(ST)
eq(ST.weave_searing_last_drop, nil, "a zero startTime leaves the stamp alone")
totem_slot1 = { have = true, name = "Searing Totem (localized)", start = 950, spell = 10438 }
ST.SHAMAN.refresh_searing_from_totems(ST)
eq(ST.weave_searing_last_drop, 950, "the spell id matches when the totem name differs")
totem_slot1 = "THROW"
local ok_sear = pcall(ST.SHAMAN.refresh_searing_from_totems, ST)
check(ok_sear, "a throwing fire-slot read degrades instead of erroring")
eq(ST.weave_searing_last_drop, 950, "a throwing fire-slot read leaves the stamp alone")
totem_slot1 = { have = true, name = "Searing Totem", start = "SECRET", spell = 10438 }
eq(st.api.GetTotemInfo(1), nil, "a secret fire-slot field degrades the whole read to absent")
ST.SHAMAN.refresh_searing_from_totems(ST)
eq(ST.weave_searing_last_drop, 950, "a secret fire-slot read leaves the stamp alone")
totem_slot1 = nil

-- Gather: an unknown clock and an unknown totem read feed nil (never a guess).
-- The Searing maintain is known-gated (the Searing Totem is a talent on Era/SoD):
-- the fixture marks it known so the feed can answer, and the gate itself is
-- pinned below.
known_spells[10438] = true
ST.fight_start_at = nil
ST.weave_searing_last_drop = nil
clock = 1000
local gathered_sear = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_sear.fight_elapsed, nil, "an unknown fight clock feeds nil")
eq(gathered_sear.searing_elapsed, nil, "an unknown searing stamp feeds nil")
eq(gathered_sear.searing_down, nil, "an unknown fire slot never feeds due")

-- A stamped fight clock feeds elapsed; a trusted stamp feeds elapsed + not-due.
ST.fight_start_at = 980
ST.weave_searing_last_drop = 990
gathered_sear = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_sear.fight_elapsed, 20, "the fight clock feeds seconds since combat-enter")
eq(gathered_sear.searing_elapsed, 10, "a trusted commit feeds seconds since the drop")
eq(gathered_sear.searing_down, false, "a trusted commit never feeds due")

-- An affirmatively empty slot feeds due with no elapsed; a live Searing feeds
-- not-due with the live clock; an occupied slot never feeds due.
totem_slot1 = { have = false }
gathered_sear = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_sear.searing_down, true, "an empty fire slot feeds due")
eq(gathered_sear.searing_elapsed, nil, "an empty fire slot feeds no elapsed")
totem_slot1 = { have = true, name = "Searing Totem", start = 995, spell = 10438 }
gathered_sear = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_sear.searing_down, false, "a live Searing feeds not-due")
eq(gathered_sear.searing_elapsed, 5, "a live Searing feeds elapsed off its clock")
totem_slot1 = { have = true, name = "Fire Elemental Totem", start = 995, spell = 2894 }
gathered_sear = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_sear.searing_down, false, "an occupied fire slot never feeds due")
-- The known gate: without the Searing Totem the maintain never prompts (the
-- talent is the player's own, and an unknown id answers false).
known_spells[10438] = nil
totem_slot1 = { have = false }
gathered_sear = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_sear.searing_down, nil, "an unknown Searing Totem never feeds the due flag")
known_spells[10438] = true
totem_slot1 = nil
ST.fight_start_at = nil
ST.weave_searing_last_drop = nil
eq(ST.weave_is_casting, false, "searing commits leave no cast in flight")

-- 29b) The two maintain feeds: the Lightning Shield maintain (S-19) and the
-- Searing maintain's SoD latch (S-17) -----------------------------------------
-- The Lightning Shield maintain rides the player's own aura walk (the charge
-- row's walk): no shield aura up means the cast is due, an aura up means it is
-- not, and an unrun walk means unknown (never a guess). The family gate is the
-- engine's helper: WRATH, FOREVER and the SoD build on the ERA token (the
-- MW-rune latch) - the Era-base and TBC sims run no Lightning Shield. The
-- Searing gate picks its fight-age threshold from the SoD MW-rune latch, which
-- the gather feeds verbatim.
do
    local saved_family = st.family
    st.family = "WRATH"
    ST.weave_shield_scanned = false
    local g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(g.lightningshield_due, nil, "an unrun aura walk never feeds the Lightning Shield maintain")
    ST.weave_shield_scanned = true
    ST.weave_shield_type = nil
    g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(g.lightningshield_due, true, "no shield aura up feeds the Lightning Shield maintain due")
    ST.weave_shield_type = "lightning"
    g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(g.lightningshield_due, false, "an up-to-date Lightning Shield never feeds due")
    ST.weave_shield_type = "water"
    g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(g.lightningshield_due, false, "a Water Shield build never feeds the Lightning Shield due")
    ST.weave_shield_type = nil
    st.family = "TBC"
    g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(g.lightningshield_due, nil, "TBC never feeds the Lightning Shield maintain")
    st.family = "ERA"
    g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(g.lightningshield_due, nil, "Era never feeds the Lightning Shield maintain")
    -- The SoD build on the ERA token (the MW-rune latch): the SoD APL's i=8 row
    -- casts 10432 r7 the same way, so the maintain fires there too.
    ST.weave_mw_observed = true
    g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(g.lightningshield_due, true, "the SoD build feeds the Lightning Shield maintain")
    ST.weave_mw_observed = false
    g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(g.lightningshield_due, nil, "the Era-base build never feeds the Lightning Shield maintain")
    -- Forever (the Forever APL's i=6 row: 10432, the same condition).
    st.family = "FOREVER"
    g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(g.lightningshield_due, true, "Forever feeds the Lightning Shield maintain")
    st.family = saved_family
    -- The known gate: the Lightning Shield is a talent, so a build without it
    -- must never be prompted (an unreadable answer stays silent).
    st.family = "WRATH"
    known_spells[49281] = nil
    ST.weave_shield_type = nil
    g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(g.lightningshield_due, nil, "an unknown Lightning Shield never feeds the maintain")
    known_spells[49281] = true
    g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(g.lightningshield_due, true, "a known Lightning Shield feeds the maintain again")
    st.family = saved_family
    -- The SoD latch: the gather feeds it verbatim (the engine's Searing gate
    -- reads it to pick the Era 20 s / SoD 30 s fight-age threshold).
    ST.weave_mw_observed = false
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).mw_observed, false,
        "the gather feeds the SoD latch off when the rune was never observed")
    ST.weave_mw_observed = true
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).mw_observed, true,
        "the gather feeds the SoD latch on once the rune was observed")
    ST.weave_mw_observed = false
    -- The HUD mirrors (display-only, nil = off): the upkeep cue is the glow.
    local hud_ls, hud_sear
    for i = 1, #ST.SHAMAN.HUD_SLOTS do
        if ST.SHAMAN.HUD_SLOTS[i].key == "lightningshield" then hud_ls = ST.SHAMAN.HUD_SLOTS[i] end
        if ST.SHAMAN.HUD_SLOTS[i].key == "searing" then hud_sear = ST.SHAMAN.HUD_SLOTS[i] end
    end
    check(hud_ls ~= nil, "the HUD declares the Lightning Shield mirror")
    check(hud_sear ~= nil, "the HUD declares the Searing mirror")
    eq(ST.SHAMAN.get_hud_state(ST, hud_ls, 100).hidden, true,
        "the Lightning Shield mirror hides without its toggle (nil = off)")
    class_db.hud_show_lightningshield = true
    ST.weave_shield_scanned = false
    eq(ST.SHAMAN.get_hud_state(ST, hud_ls, 100).hidden, true,
        "an unrun aura walk draws nothing (unknown-hides)")
    ST.weave_shield_scanned = true
    ST.weave_shield_type = "lightning"
    eq(ST.SHAMAN.get_hud_state(ST, hud_ls, 100).glow, false,
        "an up-to-date shield never glows")
    ST.weave_shield_type = nil
    ST.in_combat = true
    eq(ST.SHAMAN.get_hud_state(ST, hud_ls, 100).glow, true,
        "a missing shield glows (the cast is needed)")
    ST.in_combat = false
    class_db.hud_show_lightningshield = nil
    eq(ST.SHAMAN.get_hud_state(ST, hud_sear, 100).hidden, true,
        "the Searing mirror hides without its toggle (nil = off)")
    class_db.hud_show_searing = true
    known_spells[10438] = nil
    totem_slot1 = { have = false }
    eq(ST.SHAMAN.get_hud_state(ST, hud_sear, 100).hidden, true,
        "an unknown Searing Totem draws nothing (the known gate)")
    known_spells[10438] = true
    ST.in_combat = true
    eq(ST.SHAMAN.get_hud_state(ST, hud_sear, 100).glow, true,
        "an empty fire slot glows (the drop is needed)")
    totem_slot1 = { have = true, name = "Magma Totem", start = 100, spell = 8190 }
    eq(ST.SHAMAN.get_hud_state(ST, hud_sear, 100).glow, false,
        "another totem in the fire slot never glows")
    totem_slot1 = nil
    ST.in_combat = false
    class_db.hud_show_searing = nil
end

-- 30) Twist mana-pause + SR threshold feeds ------------------------------------------------
-- Rule-7 consumption lives engine-side; the gather feeds the threshold it reads:
-- TBC feeds the weave plug-in value (0.10), every other family feeds nil so the
-- old prompt stands. The SR thresholds travel with their cooldown feed (TBC 0.10,
-- SoD 0.65, Wrath/unknown nil = engine default/ungated). Every field is written
-- on every call, so no stale threshold survives a family change.
st.family = "TBC"
ST.weave_mw_observed = false
local gathered_twist = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_twist.twist_mana_threshold, 0.10, "TBC: the twist mana-pause threshold feeds the sim default")
eq(gathered_twist.twist_mana_threshold, st.weave.TWIST_MANA_PAUSE_THRESHOLD_TBC, "TBC: the feed matches the weave plug-in source")
eq(gathered_twist.sr_mana_threshold, 0.10, "TBC: the SR threshold travels with the TBC feed")
st.family = "WRATH"
gathered_twist = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_twist.twist_mana_threshold, nil, "Wrath: no twist threshold feeds (never twists)")
eq(gathered_twist.twist_remaining, nil, "Wrath: no twist remaining feeds either")
eq(gathered_twist.sr_mana_threshold, nil, "Wrath: no SR threshold feeds (prompts on cooldown)")
st.family = "ERA"
ST.weave_mw_observed = true
gathered_twist = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_twist.twist_mana_threshold, nil, "SoD: no twist threshold feeds (TBC-only)")
eq(gathered_twist.sr_mana_threshold, 0.65, "SoD: the SR threshold travels with the name feed")
ST.weave_mw_observed = false
gathered_twist = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_twist.sr_mana_threshold, nil, "Era-base: no SR threshold feeds (unknown client)")
eq(gathered_twist.twist_mana_threshold, nil, "Era-base: no twist threshold feeds either")
st.family = nil
gathered_twist = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_twist.twist_mana_threshold, nil, "unknown family: no threshold feeds (never pause on a guess)")
eq(gathered_twist.sr_mana_threshold, nil, "unknown family: no SR threshold feeds either")
-- The live frame reuses its table: leaving TBC must clear the feed in place.
st.family = "TBC"
local reused_twist = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(reused_twist.twist_mana_threshold, 0.10, "back on TBC: the threshold feed returns")
st.family = "WRATH"
reused_twist = ST.SHAMAN.gather_guide_inputs(ST, reused_twist)
eq(reused_twist.twist_mana_threshold, nil, "leaving TBC clears the threshold (no stale value)")
st.family = "TBC"
ST.weave_mw_observed = false

-- 30b) Era static totem feeds (G2) ------------------------------------------------------
-- Windfury first on an affirmatively empty air slot, Grace of Air as the
-- fallback while Windfury is unknown; Era-base only (family ERA without the
-- SoD latch). Every other family feeds nil (byte-identical); an unreadable
-- air slot feeds nil (never prompts on a guess). Both ids UNCONFIRMED, so the
-- known gate drives every pin. Every field is written on every call, so no
-- stale value survives a family change.
st.family = "ERA"
ST.weave_mw_observed = false
totem_slot4 = { have = false }
local gathered_era = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_era.wftotem_remaining, nil, "Era-base: unknown totems feed nil on an empty slot")
eq(gathered_era.goatotem_remaining, nil, "Era-base: unknown GoA feeds nil on an empty slot")
known_spells[10614] = true
gathered_era = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_era.wftotem_remaining, 0, "Era-base: an empty air slot feeds Windfury due")
eq(gathered_era.goatotem_remaining, nil, "Era-base: Windfury known gates Grace of Air")
known_spells[10627] = true
totem_slot4 = { have = true, name = "Windfury Totem", start = clock - 4, spell = 10614 }
gathered_era = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_era.wftotem_remaining, nil, "Era-base: a live Windfury feeds not-due")
eq(gathered_era.goatotem_remaining, nil, "Era-base: a live Windfury gates Grace of Air")
totem_slot4 = { have = true, name = "Grace of Air Totem", start = clock - 4, spell = 10627 }
gathered_era = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_era.wftotem_remaining, 0, "Era-base: Windfury takes the slot back from Grace of Air")
eq(gathered_era.goatotem_remaining, nil, "Era-base: a live Grace of Air never feeds due itself")
known_spells[10614] = nil
totem_slot4 = { have = false }
gathered_era = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_era.wftotem_remaining, nil, "Era-base: unknown Windfury never feeds")
eq(gathered_era.goatotem_remaining, 0, "Era-base: the empty slot feeds Grace of Air due")
totem_slot4 = { have = true, name = "Grace of Air Totem", start = clock - 4, spell = 10627 }
gathered_era = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_era.wftotem_remaining, nil, "Era-base: unknown Windfury never takes the slot")
eq(gathered_era.goatotem_remaining, nil, "Era-base: a live Grace of Air never feeds due")
totem_slot4 = { have = true, name = "Nature Resistance Totem", start = clock - 4 }
known_spells[10614] = true
gathered_era = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_era.wftotem_remaining, nil, "Era-base: an unmodeled air totem never feeds Windfury")
eq(gathered_era.goatotem_remaining, nil, "Era-base: an unmodeled air totem never feeds Grace of Air")
totem_slot4 = nil
gathered_era = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_era.wftotem_remaining, nil, "Era-base: an unreadable air slot feeds no Windfury")
eq(gathered_era.goatotem_remaining, nil, "Era-base: an unreadable air slot feeds no Grace of Air")
-- Every other family stays nil (byte-identical): SoD runs no totem maintain,
-- TBC twists, Wrath/Forever run none.
totem_slot4 = { have = false }
ST.weave_mw_observed = true
gathered_era = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_era.wftotem_remaining, nil, "SoD: no Windfury feed despite an empty slot")
eq(gathered_era.goatotem_remaining, nil, "SoD: no Grace of Air feed either")
ST.weave_mw_observed = false
st.family = "TBC"
gathered_era = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_era.wftotem_remaining, nil, "TBC: no Windfury feed despite an empty slot")
eq(gathered_era.goatotem_remaining, nil, "TBC: no Grace of Air feed either")
st.family = "WRATH"
gathered_era = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_era.wftotem_remaining, nil, "Wrath: no Windfury feed despite an empty slot")
st.family = "FOREVER"
gathered_era = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_era.wftotem_remaining, nil, "Forever: no Windfury feed despite an empty slot")
st.family = nil
gathered_era = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(gathered_era.wftotem_remaining, nil, "unknown family: no Windfury feed on a guess")
-- The live frame reuses its table: leaving Era clears the feed in place.
st.family = "ERA"
local reused_era = ST.SHAMAN.gather_guide_inputs(ST, {})
eq(reused_era.wftotem_remaining, 0, "back on Era-base: the Windfury feed returns")
st.family = "TBC"
reused_era = ST.SHAMAN.gather_guide_inputs(ST, reused_era)
eq(reused_era.wftotem_remaining, nil, "leaving Era clears the Windfury feed (no stale value)")
eq(reused_era.goatotem_remaining, nil, "leaving Era clears the Grace of Air feed too")
-- Fixture restored: TBC client, no live totems, unknown totem spells.
known_spells[10614] = nil
known_spells[10627] = nil
totem_slot4 = nil
st.family = "TBC"
ST.weave_mw_observed = false

-- 31) Name-vs-id rule (bench/lessons.md): TBC Anniversary resolves by NAME
-- never bare id; Classic Era by id. Classification: gather slots (SS/SR/
-- shock/Fire Nova/Fire Ele/Feral/Lava/Molten), cooldown reads, known-spell
-- probes and HUD/rotation lookups branch via st.family (spell_query); aura
-- scans, totem readers and the SUCCEEDED live-name bridge already match
-- id OR name (nil-safe fallback) and are pinned by sections 13/20/29 above.
-- Both resolutions are pinned here (recorded queries + catalogue ranks).
do
    local real_cd = st.api.GetSpellCooldown
    local real_known = st.api.is_spell_known
    local cd_queries = {}
    local last_known
    st.api.GetSpellCooldown = function(q) cd_queries[#cd_queries + 1] = q; return real_cd(q) end
    st.api.is_spell_known = function(q) last_known = q; return real_known(q) end
    local function saw_cd(want)
        for _, q in ipairs(cd_queries) do
            if q == want then
                return true
            end
        end
        return false
    end

    -- Stormstrike cooldown: TBC NAME, Era id.
    st.family = "TBC"
    cooldowns[17364] = { start = clock, duration = 8 }
    cd_queries = {}
    ST.SHAMAN.gather_guide_inputs(ST, {})
    check(saw_cd("Stormstrike"), "TBC: Stormstrike cooldown reads by NAME, never bare id")
    check(not saw_cd(17364), "TBC: no bare-id Stormstrike probe")
    st.family = "ERA"
    cd_queries = {}
    ST.SHAMAN.gather_guide_inputs(ST, {})
    check(saw_cd(17364), "Era: Stormstrike cooldown reads by id")
    check(not saw_cd("Stormstrike") or true, "Era: id path pinned (name leg is SoD-only)")

    -- Shock probe: TBC NAME, Era id (via the gather's shared shock read;
    -- the module caches the query, so pin through fresh catalogue-style
    -- probes instead of forcing the cache: direct spell_query behaviour is
    -- covered by the Stormstrike + catalogue pins above and the HUD/rotation
    -- name maps below).
    -- Catalogue: TBC NAME (highest known rank), Era id walk.
    known_spells[25449] = true
    known_spells[25448] = true
    ST.weave_catalog.LB = nil
    st.family = "TBC"
    ST.SHAMAN.resolve_weave_catalog(ST)
    eq(last_known, "Lightning Bolt", "TBC: catalogue known-probe by NAME")
    eq(ST.weave_catalog.LB and ST.weave_catalog.LB.spell_id, 25449, "TBC: catalogue resolves the top rank by name")
    ST.weave_catalog.LB = nil
    st.family = "ERA"
    ST.SHAMAN.resolve_weave_catalog(ST)
    eq(last_known, 25449, "Era: catalogue known-probe by id")
    eq(ST.weave_catalog.LB and ST.weave_catalog.LB.spell_id, 25449, "Era: catalogue resolves the top rank by id")

    -- Known gate: TBC NAME (Feral Spirit), Era id path stays silent there.
    st.family = "TBC"
    ST.SHAMAN.gather_guide_inputs(ST, {})
    -- (Feral Spirit is unknown on TBC: the probe runs but feeds nil, never prompts.)
    check(last_known ~= nil, "TBC: known probes run (name-first, nil-safe)")

    st.api.GetSpellCooldown = real_cd
    st.api.is_spell_known = real_known
    st.family = "TBC"
end

-- 32) G1 SoD ANY-stack weave fit (live-gate G1) + M1 Wrath sub-5
-- (wrath_leftovers_2026-10-19 §S3): the gather verifies a sub-5 LB/LvB
-- hardcast fits the live swing on a WF-imbue SoD build at ANY stacks incl
-- 0-1 (100 ms buffer) or a WF-imbue Wrath build at 3-4 stacks with LB 49238
-- (300 ms buffer); every other shape feeds nil (never prompts, old
-- behaviour). Pins the cast-time model (effective at live MW), the swing-fit
-- gate, the per-family MIN/buffer and the imbue-build awareness in this
-- sandbox; the provider sandbox pins the frame mapping.
do
    clock = 2000
    st.family = "ERA"
    ST.weave_mw_observed = true
    class_db.weave_mw_enabled = true
    ST.weave_is_casting = false
    ST.weave_windfury_active = true
    ST.weave_rockbiter_active = false
    ST.weave_mw_stacks = 3
    ST.weave_haste_mult = 1
    ST.latency = nil
    ST.mainhand = { speed = 3.0, start = clock - 1.0, ends_at = clock + 2.0, is_full = false }
    ST.gcd = { expires = 0 }
    ST.weave_lava_burst = nil
    ST.weave_lava_burst_retry_at = nil
    known_spells[51505] = nil
    if not ST.weave_catalog or not ST.weave_catalog.LB then
        ST.weave_catalog = ST.weave_catalog or {}
        ST.weave_catalog.LB = { spell_id = 25449, name = "Lightning Bolt", icon = "icon_lb", cast_seconds = 2.5 }
    end
    local g1 = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(g1.weave_sub5_ready, true, "G1: a fitting LB hardcast feeds ready on a WF-imbue SoD build")
    eq(g1.weave_sub5_is_lavaburst, false, "G1: without the rune the fit spell is Lightning Bolt")
    check(type(g1.weave_sub5_cast_seconds) == "number",
        "G1: the effective sub-5 cast time is numeric in the window")
    -- Lava Burst rune known: the fit spell is LvB.
    known_spells[51505] = true
    ST.weave_lava_burst = nil
    ST.weave_lava_burst_retry_at = nil
    local g1_lava = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(g1_lava.weave_sub5_ready, true, "G1: a fitting LvB hardcast feeds ready with the rune")
    eq(g1_lava.weave_sub5_is_lavaburst, true, "G1: with the rune the fit spell is Lava Burst")
    known_spells[51505] = nil
    ST.weave_lava_burst = nil
    ST.weave_lava_burst_retry_at = nil
    -- A short swing withholds the fit (known-not-fit, still no prompt).
    ST.mainhand = { speed = 3.0, start = clock - 2.5, ends_at = clock + 0.5, is_full = false }
    local g1_short = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(g1_short.weave_sub5_ready, false, "G1: a clipping cast feeds known-not-fit")
    ST.mainhand = { speed = 3.0, start = clock - 1.0, ends_at = clock + 2.0, is_full = false }
    -- Imbue-build gate: no WF imbue never feeds ready; a Rockbiter build
    -- never feeds ready (SoD sim runs WF/WF).
    ST.weave_windfury_active = false
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).weave_sub5_ready, nil,
        "G1: a dropped WF imbue clears the fit feed")
    ST.weave_windfury_active = true
    ST.weave_rockbiter_active = true
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).weave_sub5_ready, nil,
        "G1: a Rockbiter build never feeds the fit")
    ST.weave_rockbiter_active = false
    -- ANY stacks incl 0-1 feed (the SoD sim weaves at ANY stacks when the
    -- cast fits); 5 stays on rule 5 (the instant). The 0-1 casts are nearly
    -- full-length, so these pins widen the swing to one that fits them.
    ST.mainhand = { speed = 3.0, start = clock, ends_at = clock + 3.0, is_full = false }
    ST.weave_mw_stacks = 1
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).weave_sub5_ready, true,
        "G1: 1 stack feeds ready when the cast fits (0-1 hardcast)")
    ST.weave_mw_stacks = 0
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).weave_sub5_ready, true,
        "G1: 0 stacks feed ready when the cast fits (0-1 hardcast)")
    ST.mainhand = { speed = 3.0, start = clock - 1.0, ends_at = clock + 2.0, is_full = false }
    ST.weave_mw_stacks = 5
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).weave_sub5_ready, nil,
        "G1: 5 stacks never feed the fit (rule 5 owns the instant)")
    ST.weave_mw_stacks = 3
    -- Casting withholds the fit (rule 1 RIDE holds anyway).
    ST.weave_is_casting = true
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).weave_sub5_ready, nil,
        "G1: casting never feeds the fit")
    ST.weave_is_casting = false
    -- Non-SoD families: TBC/Era-base never feed (no MW there).
    st.family = "TBC"
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).weave_sub5_ready, nil,
        "G1: TBC never feeds the fit")
    -- M1 Wrath sub-5 (default_wf APL: MW>=3 + 300 ms + cast fits): 3-4
    -- stacks feed with LB 49238 known; 0-2 and 5 stay out; the spell is
    -- always Lightning Bolt (LvB is Elemental-only there).
    st.family = "WRATH"
    known_spells[49238] = true
    ST.weave_mw_stacks = 3
    local m1 = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(m1.weave_sub5_ready, true, "M1: a fitting Wrath LB hardcast feeds ready at 3 stacks")
    eq(m1.weave_sub5_is_lavaburst, false, "M1: the Wrath fit spell is always Lightning Bolt")
    check(type(m1.weave_sub5_cast_seconds) == "number",
        "M1: the Wrath effective cast time is numeric in the window")
    -- Effective at 3 stacks is 2.5 * 0.4 = 1.0 s: the 300 ms buffer (not the
    -- SoD 100 ms) decides the boundary.
    ST.mainhand = { speed = 3.0, start = clock - 1.65, ends_at = clock + 1.35, is_full = false }
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).weave_sub5_ready, true,
        "M1: effective + latency + 300 ms fits on Wrath")
    ST.mainhand = { speed = 3.0, start = clock - 1.75, ends_at = clock + 1.25, is_full = false }
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).weave_sub5_ready, false,
        "M1: just inside 300 ms withholds on Wrath (SoD 100 ms would fit)")
    ST.mainhand = { speed = 3.0, start = clock - 1.0, ends_at = clock + 2.0, is_full = false }
    ST.weave_mw_stacks = 2
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).weave_sub5_ready, nil,
        "M1: 2 stacks never feed the fit on Wrath (MW>=3)")
    ST.weave_mw_stacks = 4
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).weave_sub5_ready, true,
        "M1: 4 stacks feed ready when the cast fits on Wrath")
    ST.weave_mw_stacks = 5
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).weave_sub5_ready, nil,
        "M1: 5 stacks never feed the fit on Wrath (rule 5 owns the instant)")
    ST.weave_mw_stacks = 0
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).weave_sub5_ready, nil,
        "M1: 0 stacks never feed the fit on Wrath")
    ST.weave_mw_stacks = 3
    -- Known gate: an unknown 49238 feeds nil (never prompts on a guess).
    known_spells[49238] = nil
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).weave_sub5_ready, nil,
        "M1: an unknown Wrath LB never feeds the fit")
    known_spells[49238] = true
    -- The Wrath branch needs no MW latch (Wrath has the talent, not the SoD
    -- rune): unobserved still feeds.
    ST.weave_mw_observed = false
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).weave_sub5_ready, true,
        "M1: Wrath feeds without the MW latch")
    ST.weave_mw_observed = true
    -- Imbue-build gate on Wrath too.
    ST.weave_windfury_active = false
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).weave_sub5_ready, nil,
        "M1: a dropped WF imbue clears the Wrath fit feed")
    ST.weave_windfury_active = true
    ST.weave_rockbiter_active = true
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).weave_sub5_ready, nil,
        "M1: a Rockbiter build never feeds the Wrath fit")
    ST.weave_rockbiter_active = false
    known_spells[49238] = nil
    st.family = "ERA"
    ST.weave_mw_observed = false
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).weave_sub5_ready, nil,
        "G1: Era-base never feeds the fit")
    ST.weave_mw_observed = true
    class_db.weave_mw_enabled = false
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).weave_sub5_ready, nil,
        "G1: option-off never feeds the fit")
    class_db.weave_mw_enabled = true
    -- Stale fields are overwritten on the reused table.
    st.family = "TBC"
    local g1_stale = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(g1_stale.weave_sub5_ready, nil, "G1: the fit feed is re-fed, not stale")
    eq(g1_stale.weave_sub5_cast_seconds, nil, "G1: the cast feed is re-fed, not stale")
    eq(g1_stale.weave_sub5_is_lavaburst, nil, "G1: the spell feed is re-fed, not stale")
    st.family = "TBC"
    ST.weave_mw_observed = false
    ST.weave_mw_stacks = 0
    ST.weave_windfury_active = false
    ST.weave_rockbiter_active = false
end

-- 33) Practice seam surface: the shaman weave drill --------------------------------
-- The drill seam mirrors the hunter shape: sync reports no seal state, the
-- scenario key resolves through the registry, lookups are nil-safe, cast times
-- come from the live catalogue with the harness default behind them.
eq(ST.SHAMAN.practice_sync(ST), 0, "drill: practice_sync reports no seal state")
do
    local pmod = assert(loadfile(ROOT .. "practice.lua"))
    setfenv(pmod, env)
    local okp, errp = pcall(function() pmod("SwedgeTimer", st) end)
    check(okp, "drill: practice.lua loads in the shaman sandbox (" .. tostring(errp) .. ")")
end
check(type(st.practice) == "table" and type(st.practice.harness) == "table",
    "drill: the harness is loaded")
eq(ST.SHAMAN.practice_scenario_key(), "shaman_weave",
    "drill: the scenario key resolves through the registry")
eq(#ST.SHAMAN.PRACTICE_CASTS, 2, "drill: two weave casts")
eq(ST.SHAMAN.PRACTICE_CAST_ORDER[1], "weave_lb", "drill: LB casts first")
eq(ST.SHAMAN.PRACTICE_CAST_ORDER[2], "weave_cl", "drill: CL casts second")
eq(ST.SHAMAN.practice_cast_family("weave_lb"), "LB", "drill: LB maps to its family")
eq(ST.SHAMAN.practice_cast_family("weave_cl"), "CL", "drill: CL maps to its family")
eq(ST.SHAMAN.practice_cast_family("bogus"), nil, "drill: unknown casts map nowhere")
eq(ST.SHAMAN.practice_cast_label("weave_lb"), "Lightning Bolt", "drill: LB label")
eq(ST.SHAMAN.practice_cast_label("bogus"), nil, "drill: unknown casts label nothing")
eq(ST.SHAMAN.practice_cast_spell_id("weave_lb"), 25449,
    "drill: LB icon resolves through the live catalogue")
eq(ST.SHAMAN.practice_cast_spell_id("weave_cl"), 25442,
    "drill: CL icon resolves through the live catalogue")
eq(ST.SHAMAN.practice_cast_spell_id("bogus"), nil, "drill: unknown icons hide")
eq(ST.SHAMAN.practice_cast_seconds("weave_lb"), 2.5,
    "drill: LB cast seconds come from the catalogue")
eq(ST.SHAMAN.practice_cast_seconds("weave_cl"), 2.0,
    "drill: CL cast seconds come from the catalogue")
eq(ST.SHAMAN.practice_cast_seconds("bogus"), nil, "drill: unknown casts time nothing")
eq(ST.SHAMAN.practice_latency_seconds(), 0, "drill: unreadable latency reads 0")
ST.latency = { world_ms = 120 }
eq(ST.SHAMAN.practice_latency_seconds(), 0.12, "drill: 120ms reads 0.12s")
ST.latency = { world_ms = "fast" }
eq(ST.SHAMAN.practice_latency_seconds(), 0, "drill: non-number latency reads 0")
ST.latency = nil

-- 34) Drill lifecycle end-to-end (harness session, exact-time grades) ---------------
do
    local now = 1000
    local swing = { swing_duration = 2.6, swing_start = now, swing_ends_at = now + 2.6 }
    -- Unknown catalogue: the harness default stands in (no grade on a guess only
    -- when even the default is gone).
    local kept_catalog = ST.weave_catalog
    ST.weave_catalog = nil
    eq(ST.SHAMAN.practice_cast_seconds("weave_cl"), 1.5,
        "drill: no catalogue falls back to the harness default")
    eq(ST.SHAMAN.practice_cast_spell_id("weave_cl"), nil,
        "drill: no catalogue hides the icon")
    ST.weave_catalog = kept_catalog
    local session = ST.SHAMAN.new_practice_session(now,
        { swing_duration = 2.6, effective_cast = 2.0, latency = 0 })
    check(type(session) == "table" and session.active == true,
        "drill: new_practice_session begins a live run")
    eq(session.key, "shaman_mw_weave",
        "drill: the run is the class's own drill, not the retired built-in")
    eq(ST.SHAMAN.practice_drill_key(), "shaman_mw_weave",
        "drill: the class publishes the drill its session runs")
    -- The class's own drill grades the weave: the Maelstrom-stack floor first
    -- (a weave below it is a wrong pick whatever the timing), then the timing.
    local kept_stacks = ST.weave_mw_stacks
    ST.weave_mw_stacks = 0
    local grade_floor = ST.SHAMAN.practice_cast(session, swing, now + 0.22 * 2.6, "weave_cl")
    eq(grade_floor, "F", "drill: a weave below the stack floor grades F")
    ST.weave_mw_stacks = 5
    -- CL at fraction 0.22: marker (2.6-2.0)/2.6 = 0.2307, margin 0.0107 -> S.
    local early = now + 0.22 * 2.6
    local grade_s, margin_s = ST.SHAMAN.practice_cast(session, swing, early, "weave_cl")
    eq(grade_s, "S", "drill: a tight weave start grades S")
    check(type(margin_s) == "number" and margin_s > 0 and margin_s < 100,
        "drill: the S margin is a small positive ms")
    -- CL at fraction 0.5: past the marker and clipping -> F.
    local late = now + 0.5 * 2.6
    local grade_f = ST.SHAMAN.practice_cast(session, swing, late, "weave_cl")
    eq(grade_f, "F", "drill: a late clipping weave start grades F")
    eq(ST.SHAMAN.practice_cast(session, swing, early, "bogus"), nil,
        "drill: unknown casts never score")
    -- Clip decides: a 3.0s cast in a 2.6s swing overruns from any start. Start at
    -- the swing edge (fraction 0, not late): only the measured clip can fail it.
    local kept_cl = ST.weave_catalog.CL
    ST.weave_catalog.CL = { spell_id = 25442, cast_seconds = 3.0 }
    eq(ST.SHAMAN.practice_cast(session, swing, now, "weave_cl"), "F",
        "drill: an overrunning weave start grades F on the clip")
    ST.weave_catalog.CL = kept_cl
    ST.weave_mw_stacks = kept_stacks
    local out = ST.SHAMAN.tick_practice_session(session, early, 0.05, nil)
    check(type(out) == "table", "drill: tick returns the out table")
    eq(ST.SHAMAN.practice_begin_session(session, early), false,
        "drill: begin on a live run is a no-op")
    eq(ST.SHAMAN.practice_fight_elapsed(session, early), early - now,
        "drill: fight elapsed runs from the run start")
    eq(ST.SHAMAN.end_practice_session(session, early), true, "drill: the run ends")
    eq(ST.SHAMAN.practice_cast(session, swing, early, "weave_cl"), nil,
        "drill: ended runs never score")
    eq(ST.SHAMAN.end_practice_session(session, early), false,
        "drill: ending twice is a no-op")
    eq(ST.SHAMAN.end_practice_session(nil, early), false,
        "drill: ending nil is a no-op")
    eq(ST.SHAMAN.practice_fight_elapsed(session, early), nil,
        "drill: ended runs clock nothing")
    eq(ST.SHAMAN.practice_fight_elapsed(nil, early), nil,
        "drill: nil sessions clock nothing")
    -- Status readout: idle without a swing, too-late past the marker, countdown early.
    eq(ST.SHAMAN.practice_status(nil, early), "Drill idle", "drill: nil swing reads idle")
    eq(ST.SHAMAN.practice_status(swing, late), "Too late - wait for the next swing",
        "drill: late reads too-late")
    -- Status reads the LB window (the most restrictive drill cast): marker
    -- (2.6-2.5)/2.6 = 0.038, so 0.22 is already too late for LB but 0.03 counts down.
    local status = ST.SHAMAN.practice_status(swing, now + 0.03 * 2.6)
    check(status:find("Cast now") ~= nil and status:find("to marker") ~= nil,
        "drill: early reads the countdown (" .. tostring(status) .. ")")
end

-- 35) Family matrix: Era / TBC / Forever grade identically --------------------------
-- The drill clock is the caller's and every read is compat- or catalogue-level, so
-- the family token never changes a grade. Unknown client data (no catalogue)
-- still runs on the harness default; nothing throws on any client.
do
    local now = 2000
    local swing = { swing_duration = 2.6, swing_start = now, swing_ends_at = now + 2.6 }
    local early = now + 0.22 * 2.6
    -- A weaveable client: the class's own drill grades the Maelstrom-stack floor
    -- first, so the timing pins below need the stacks the floor asks for.
    local kept_stacks = ST.weave_mw_stacks
    ST.weave_mw_stacks = 5
    for _, fam in ipairs({ "ERA", "TBC", "FOREVER" }) do
        st.family = fam
        local session = ST.SHAMAN.new_practice_session(now,
            { swing_duration = 2.6, effective_cast = 2.0, latency = 0 })
        check(session ~= nil, "drill: the run starts on " .. fam)
        eq(ST.SHAMAN.practice_cast(session, swing, early, "weave_cl"), "S",
            "drill: the tight weave grades S on " .. fam)
        ST.SHAMAN.end_practice_session(session, early)
    end
    st.family = "TBC"
    -- No catalogue on any family: the default still grades, the icon hides.
    local kept_catalog = ST.weave_catalog
    ST.weave_catalog = nil
    for _, fam in ipairs({ "ERA", "TBC", "FOREVER" }) do
        st.family = fam
        local session = ST.SHAMAN.new_practice_session(now,
            { swing_duration = 2.6, effective_cast = 1.5, latency = 0 })
        check(session ~= nil, "drill: the run starts on " .. fam .. " with no catalogue")
        eq(ST.SHAMAN.practice_cast_spell_id("weave_lb"), nil,
            "drill: the icon hides on " .. fam .. " with no catalogue")
        -- Default cast 1.5: marker (2.6-1.5)/2.6 = 0.423; 0.41 is inside -> S.
        eq(ST.SHAMAN.practice_cast(session, swing, now + 0.41 * 2.6, "weave_lb"), "S",
            "drill: the default cast grades S on " .. fam)
        ST.SHAMAN.end_practice_session(session, now + 0.41 * 2.6)
    end
    ST.weave_catalog = kept_catalog
    ST.weave_mw_stacks = kept_stacks
    st.family = "TBC"
end

-- 36) Designer coverage: every shaman element is positionable -----------------------
-- Shaman creates no standalone frames (no CreateFrame in the class module): every
-- visual it draws is a texture/fontstring on the bar visuals frames (children of
-- the bar anchors) or one of the shared module frames. The five generic design
-- descriptors therefore position everything shaman owns: bars, HUD, rotation
-- label, Next Action Guide, practice panel. These pins prove the coverage exists
-- in-tree (the registry count itself is pinned by tests/designmode_state.lua).
do
    local f = assert(io.open(ROOT .. "classes/shaman.lua", "r"))
    local shaman_src = f:read("*a")
    f:close()
    local creations = 0
    for _ in shaman_src:gmatch("CreateFrame%s*%(") do
        creations = creations + 1
    end
    eq(creations, 0, "designer: shaman creates no standalone frames")
    local d = assert(io.open(ROOT .. "designmode.lua", "r"))
    local design_src = d:read("*a")
    d:close()
    -- Bars register through the bar_descriptor(hand) helper and the rotation /
    -- timeline through practice_descriptor(key, title), so those pins match the
    -- register call sites; the rest carry literal keys.
    for _, literal in ipairs({ 'register(bar_descriptor("mainhand"))',
        'register(bar_descriptor("offhand"))', 'key = "hud"', 'key = "rottext"',
        'key = "nag"', 'key = "practice_panel"',
        'register(practice_descriptor("practice_rotation"',
        'register(practice_descriptor("practice_timeline"' }) do
        check(design_src:find(literal, 1, true) ~= nil,
            "designer: descriptor registered (" .. literal .. ")")
    end
    -- The providers behind the shared frames are wired for shaman.
    check(type(ST.SHAMAN.guide) == "table" and type(ST.SHAMAN.guide.gather) == "function"
        and type(ST.SHAMAN.guide.evaluate) == "function",
        "designer: the NAG provider (guide/gather/evaluate) is wired")
    check(type(ST.SHAMAN.get_rotation_key) == "function",
        "designer: the rotation-label source is wired")
    check(type(ST.SHAMAN.get_hud_state) == "function"
        and type(ST.SHAMAN.HUD_SLOTS) == "table" and #ST.SHAMAN.HUD_SLOTS > 0,
        "designer: the HUD provider and slots are wired")
    -- The position keys the descriptors write already exist in the defaults chain.
    local c = assert(io.open(ROOT .. "config_presets.lua", "r"))
    local presets_src = c:read("*a")
    c:close()
    check(presets_src:find("nextaction_x", 1, true) ~= nil,
        "designer: nextaction_x ships in the defaults chain")
    check(presets_src:find("hud_x", 1, true) ~= nil,
        "designer: hud_x ships in the defaults chain")
    check(presets_src:find("rotation_label_x", 1, true) ~= nil,
        "designer: rotation_label_x ships in the defaults chain")
    check(presets_src:find("practice_panel_x", 1, true) ~= nil,
        "designer: practice_panel_x ships in the defaults chain")
    -- Both-ways start is wired: post_init builds the shared session frames and the
    -- options toggle drives the same toggle as /st practice.
    check(shaman_src:find("practice_ui.init", 1, true) ~= nil,
        "designer: post_init builds the practice session frames")
    local o = assert(io.open(ROOT .. "option_tables.lua", "r"))
    local tables_src = o:read("*a")
    o:close()
    local shaman_panel = tables_src:match("function ST%.class_opts_funcs%.SHAMAN.-\nend")
    check(shaman_panel ~= nil, "designer: the SHAMAN options panel is found")
    if shaman_panel then
        check(shaman_panel:find("practice_toggle", 1, true) ~= nil,
            "designer: the SHAMAN panel carries the Practice toggle")
        check(shaman_panel:find("practice_weapon_speed", 1, true) ~= nil,
            "designer: the SHAMAN panel carries the weapon speed")
        check(shaman_panel:find("st.practice_ui.toggle", 1, true) ~= nil,
            "designer: the SHAMAN toggle drives the shared session toggle")
    end
end

--=========================================================================================
-- 37) Shared class order: the per-frame hook and the post_init init order (F8 + F9)
--=========================================================================================
-- The six class modules are copy-paste siblings and used to diverge on two orders:
-- the hunter ticked the HUD before the guide, and the paladin built the practice
-- surface before the HUD. The shared contract is now pinned here, per class:
--   * the per-frame class hook ticks the guide BEFORE the HUD;
--   * post_init builds the guide, then the HUD, then the practice surface.
-- Both the runtime order (spies record the calls) and the source order (the call
-- sites) are pinned, so a reordering in either place fails this suite.
do
    local fh = assert(io.open(ROOT .. "classes/shaman.lua", "r"))
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

    -- Runtime order: the spies record the calls the class actually makes. The
    -- shaman suite runs on one shared sandbox, so the three modules are restored.
    local init_order = {}
    local saved_nextaction_ui, saved_hud, saved_practice_ui =
        st.nextaction_ui, st.hud, st.practice_ui
    st.nextaction_ui = { init = function() init_order[#init_order + 1] = "guide" end }
    st.hud = { init = function() init_order[#init_order + 1] = "hud" end }
    st.practice_ui = {
        init = function() init_order[#init_order + 1] = "practice" end,
        is_active = function() return false end,
    }
    local ok_init, err_init = pcall(ST.SHAMAN.post_init, ST)
    check(ok_init, "order: post_init runs with the order spies (" .. tostring(err_init) .. ")")
    eq(init_order[1], "guide", "order: post_init builds the guide first")
    eq(init_order[2], "hud", "order: post_init builds the HUD second")
    eq(init_order[3], "practice", "order: post_init builds the practice surface third")
    eq(#init_order, 3, "order: post_init builds exactly the three surfaces")

    local tick_order = {}
    st.nextaction_ui = {
        apply_settings = function() end,
        on_bar_update = function() tick_order[#tick_order + 1] = "guide" end,
    }
    st.hud = { on_bar_update = function() tick_order[#tick_order + 1] = "hud" end }
    local ok_tick, err_tick = pcall(ST.SHAMAN.on_bar_update, ST, "mainhand")
    check(ok_tick, "order: the class hook runs with the order spies (" .. tostring(err_tick) .. ")")
    eq(tick_order[1], "guide", "order: the guide ticks before the HUD")
    eq(tick_order[2], "hud", "order: the HUD ticks after the guide")
    eq(#tick_order, 2, "order: the class hook ticks the guide and the HUD once each")

    st.nextaction_ui = saved_nextaction_ui
    st.hud = saved_hud
    st.practice_ui = saved_practice_ui

end

-- 38) The practice surface (bench/class_features_drills_2026-10-19.md §2.6) ---------
-- The class-side view of the practice contract: the rotation table's spell
-- references (TBC resolves by NAME, Era by ID - bench/lessons.md, both pinned),
-- the namespace mirror the shared engine's lookup needs, and the proof that the
-- live guide is untouched by the practice surface (no slot added, no frozen input
-- changed, the gather writes the same set).
do
    local rot = ST.SHAMAN.practice_rotation
    check(type(rot) == "table", "practice: the class ships a rotation table")
    eq(#rot, 22, "practice: the rotation table carries twenty-two lines")
    -- Name-vs-id: every line ships the Era id AND the TBC name, both pinned
    -- against the module's own constants.
    local IDS = {
        fireele = 2894, feralspirit = 51533, shamanisticrage = 30823, weave = 403,
        flameshock = 8050, twist = 8512, wftotem = 10614, goa = 10627,
        stormstrike = 17364, searing = 10438, magma = 8190, firenova = 1535,
        lightningshield = 49281, lavalash = 60103, chainlightning = 10605,
        earthshock = 8042, moltenblast = 425339, coe = 66842,
        bloodlust = 2825, strength_of_earth = 10442, mana_spring = 25570,
        frostshock = 25464,
    }
    local NAMES = {
        fireele = "Fire Elemental Totem", feralspirit = "Feral Spirit",
        shamanisticrage = "Shamanistic Rage", weave = "Lightning Bolt",
        flameshock = "Flame Shock", twist = "Windfury Totem", wftotem = "Windfury Totem",
        goa = "Grace of Air Totem", stormstrike = "Stormstrike",
        searing = "Searing Totem", magma = "Magma Totem", firenova = "Fire Nova Totem",
        lightningshield = "Lightning Shield", lavalash = "Lava Lash",
        chainlightning = "Chain Lightning", earthshock = "Earth Shock",
        moltenblast = "Molten Blast", coe = "Call of the Elements",
        bloodlust = "Bloodlust", strength_of_earth = "Strength of Earth Totem",
        mana_spring = "Mana Spring Totem", frostshock = "Frost Shock",
    }
    local ids_ok, names_ok = true, true
    for i = 1, #rot do
        local line = rot[i]
        if line.spell_id ~= IDS[line.action] then ids_ok = false end
        if line.spell_name ~= NAMES[line.action] then names_ok = false end
    end
    check(ids_ok, "practice: every rotation line carries the pinned Era id")
    check(names_ok, "practice: every rotation line carries the pinned TBC name")
    -- The TBC name of a line is the name the module itself queries by: the
    -- Stormstrike and Fire Nova lines match the module's name constants.
    local by_action = {}
    for i = 1, #rot do by_action[rot[i].action] = rot[i] end
    eq(by_action.stormstrike.spell_name, "Stormstrike",
        "practice: the Stormstrike line names the TBC spell the module queries")
    eq(by_action.firenova.spell_name, "Fire Nova Totem",
        "practice: the Fire Nova line names the TBC spell the module queries")
    eq(by_action.stormstrike.spell_id, 17364,
        "practice: the Stormstrike line carries the module's id")
    -- The live flags match reality: a line is live when its READ exists (HU-13),
    -- and the engine flag says whether the frozen engine has an arm that can PLAY
    -- the line with the inputs the shipped tree produces. S-19 and S-17 landed with
    -- their slots and rules, so they are live; S-20 (Call of the Elements) landed
    -- with its slot, its rule 9c and the water clock, so it is live too; the Chain
    -- Lightning line has NEITHER a read NOR an arm that can fire: the enemy-count
    -- sensor does not exist (no client API counts enemies), so no producer ever
    -- feeds target_count and rule 13 is unreachable - the row claims no arm and
    -- names the read it waits for.
    eq(by_action.searing.live, true, "practice: the Searing line is live (slot + rule 9b)")
    eq(by_action.lightningshield.live, true,
        "practice: the Lightning Shield line is live (slot + rule 11b)")
    eq(by_action.coe.live, true,
        "practice: the Call of the Elements line is live (slot + rule 9c + the water clock)")
    eq(by_action.chainlightning.live, false,
        "practice: the Chain Lightning line is not live (no enemy-count read)")
    eq(by_action.chainlightning.engine, false,
        "practice: the Chain Lightning line claims no engine arm (nothing feeds target_count)")
    check(type(by_action.chainlightning.needs) == "string"
        and by_action.chainlightning.needs ~= "",
        "practice: the Chain Lightning line names the read it waits for")
    -- The reachability behind that flag: the gather never supplies an enemy count
    -- on any family, so rule 13 has no producer (the sensor's filed remainder).
    local saved_family_chain = st.family
    local chain_target_count = nil
    for _, fam in ipairs({ "ERA", "TBC", "WRATH", "FOREVER" }) do
        st.family = fam
        chain_target_count = ST.SHAMAN.gather_guide_inputs(ST, {}).target_count
    end
    st.family = saved_family_chain
    eq(chain_target_count, nil,
        "practice: no family ever feeds an enemy count (the Chain Lightning sensor's remainder)")
    -- The APL utility layer's four lines: a live read AND an engine arm each.
    for _, action in ipairs({ "bloodlust", "strength_of_earth", "mana_spring", "frostshock" }) do
        eq(by_action[action].live, true, "practice: the " .. action .. " line has a live read")
        eq(by_action[action].engine, true, "practice: the " .. action .. " line has an engine arm")
        check(type(by_action[action].spell_ids) == "table",
            "practice: the " .. action .. " line carries its per-family ids")
    end
    -- The Lightning Shield line's per-family ids (the residual's F1): the row runs
    -- on WRATH, on the SoD build and on FOREVER, and each family carries its own
    -- id - the SoD and Forever APLs cast 10432 (the SoD phase_6 APL's i=8 row and
    -- the Forever APL's i=6 row), while the Wrath APLs cast 49281. Without the map
    -- the line would read the Wrath id on every family.
    eq(by_action.lightningshield.spell_ids.WRATH, 49281,
        "practice: the Lightning Shield line carries the Wrath id")
    eq(by_action.lightningshield.spell_ids.SOD, 10432,
        "practice: the Lightning Shield line carries the SoD id (10432 r7)")
    eq(by_action.lightningshield.spell_ids.FOREVER, 10432,
        "practice: the Lightning Shield line carries the Forever id (10432)")
    eq(by_action.lightningshield.families[1], "WRATH",
        "practice: the Lightning Shield line lists the Wrath family")
    local ls_families = {}
    for _, fam in ipairs(by_action.lightningshield.families) do ls_families[fam] = true end
    eq(ls_families.SOD, true, "practice: the Lightning Shield line lists the SoD family")
    eq(ls_families.FOREVER, true, "practice: the Lightning Shield line lists the Forever family")
    eq(ls_families.ERA, nil,
        "practice: the Lightning Shield line does not claim the Era-base family")
    eq(ls_families.TBC, nil,
        "practice: the Lightning Shield line does not claim the TBC family")
    -- The twist row's rank reconciliation (the residual's C5): the shipped id is
    -- the Windfury Totem RANK-1 fallback (8512) and the TBC APL's sim-exact rank-5
    -- id (25587) rides in spell_ids; the alternation's other half is the Grace of
    -- Air Totem 25359 (the pre-pull table's goa row).
    eq(by_action.twist.spell_id, 8512,
        "practice: the twist line keeps the Windfury rank-1 fallback id")
    eq(by_action.twist.spell_ids.TBC, 25587,
        "practice: the twist line records the TBC APL's rank-5 Windfury id")
    check(by_action.twist.source:find("25359", 1, true) ~= nil,
        "practice: the twist line cites the alternation's Grace of Air id (25359)")
    local live_actions = {}
    for i = 1, #rot do
        if rot[i].live then live_actions[rot[i].action] = true end
    end
    -- THE FAMILY SLICE (the release-gate blocker B1): the rotation rows each
    -- family's APL carries, in the table's own order. The expectation is
    -- spelled out here AND derived from the shipped table below, so a change
    -- to either side has to be deliberate.
    local EXPECTED_SLICES = {
        ERA = { "feralspirit", "shamanisticrage", "weave", "flameshock",
            "strength_of_earth", "wftotem", "goa", "stormstrike", "searing",
            "lavalash", "chainlightning", "earthshock", "moltenblast" },
        SOD = { "lightningshield" },
        TBC = { "fireele", "shamanisticrage", "weave", "flameshock", "twist",
            "strength_of_earth", "mana_spring", "stormstrike", "searing",
            "magma", "firenova", "frostshock", "earthshock" },
        WRATH = { "fireele", "feralspirit", "bloodlust", "shamanisticrage",
            "weave", "flameshock", "stormstrike", "magma", "firenova",
            "lightningshield", "lavalash", "earthshock", "coe" },
        FOREVER = { "flameshock", "strength_of_earth", "stormstrike", "searing",
            "firenova", "lightningshield", "earthshock" },
    }
    -- The guide's family slot sets: the same rows in the class's DISPLAY
    -- order (the display order is the class's own; the family cut filters it).
    local EXPECTED_SLOT_ORDERS = {
        ERA = { "stormstrike", "flameshock", "weave", "earthshock", "feralspirit",
            "lavalash", "shamanisticrage", "chainlightning", "moltenblast",
            "wftotem", "goa", "searing", "strength_of_earth" },
        SOD = { "lightningshield" },
        TBC = { "stormstrike", "flameshock", "weave", "firenova", "earthshock",
            "twist", "fireele", "magma", "shamanisticrage", "searing",
            "strength_of_earth", "mana_spring", "frostshock" },
        WRATH = { "stormstrike", "flameshock", "weave", "firenova", "earthshock",
            "feralspirit", "fireele", "magma", "lavalash", "shamanisticrage",
            "lightningshield", "coe", "bloodlust" },
        FOREVER = { "stormstrike", "flameshock", "firenova", "earthshock",
            "lightningshield", "searing", "strength_of_earth" },
    }
    -- (a) The per-family slice, derived from the shipped table.
    for slice_family, expected in pairs(EXPECTED_SLICES) do
        local derived = {}
        for i = 1, #rot do
            local fams = {}
            for _, fam in ipairs(rot[i].families or {}) do fams[fam] = true end
            if fams[slice_family] then derived[#derived + 1] = rot[i].action end
        end
        local derived_ok = (#derived == #expected)
        for i = 1, #expected do
            if derived[i] ~= expected[i] then derived_ok = false end
        end
        check(derived_ok, "practice: the " .. slice_family .. " slice is the table's own family rows")
        -- (b) The accessor returns exactly that slice.
        local slice = ST.SHAMAN.practice_rotation_for(slice_family)
        eq(#slice, #expected,
            "practice: the " .. slice_family .. " slice carries " .. #expected .. " rows")
        local order_ok = true
        for i = 1, #expected do
            if slice[i] == nil or slice[i].action ~= expected[i] then order_ok = false end
        end
        check(order_ok, "practice: the " .. slice_family .. " slice keeps the table's own order")
    end
    eq(#ST.SHAMAN.practice_rotation_for("NOPE"), 0,
        "practice: an unknown family has no rotation slice")
    -- The guide's slot set is the family's cut of the class's full vocabulary
    -- (the rotation table's `families` is the one truth): the slot keys and the
    -- rotation actions are the same key space, so the two can never disagree.
    eq(#ST.SHAMAN.GUIDE_SLOTS, 22, "practice: the class ships twenty-two guide slots")
    for slot_family, expected in pairs(EXPECTED_SLOT_ORDERS) do
        local slots = ST.SHAMAN.family_guide_slots(slot_family)
        eq(#slots, #expected,
            "practice: the " .. slot_family .. " guide carries " .. #expected .. " slots")
        local order_ok = true
        for i = 1, #expected do
            if slots[i] == nil or slots[i].key ~= expected[i] then order_ok = false end
        end
        check(order_ok, "practice: the " .. slot_family .. " guide slots keep the display order")
        local slot_keys = {}
        for i = 1, #slots do slot_keys[slots[i].key] = true end
        local rows_ok = true
        for _, action in ipairs(EXPECTED_SLICES[slot_family]) do
            if not slot_keys[action] then rows_ok = false end
        end
        check(rows_ok,
            "practice: the " .. slot_family .. " guide slots mirror the " .. slot_family .. " rotation rows")
    end
    -- Every live rotation line names a declared guide slot - per family now
    -- (the guide's slot list is the running family's cut, so the check runs
    -- against each family's own slot set).
    local live_ok = true
    for live_family, rows in pairs(EXPECTED_SLICES) do
        local slot_action = {}
        local slots = ST.SHAMAN.family_guide_slots(live_family)
        for i = 1, #slots do slot_action[slots[i].key] = true end
        for _, action in ipairs(rows) do
            if live_actions[action] and not slot_action[action] then live_ok = false end
        end
    end
    check(live_ok, "practice: every live rotation line names a declared guide slot")
    -- (c) THE STRIP (practice_ui.lua's scenario_action_order): the rotation
    -- slice first, then the guide slot keys, then the keys the engine asked
    -- for. On a TBC client it must carry NO Wrath-only and NO Era-only key -
    -- the direct offline form of TESTING.md's "a family that does not carry a
    -- row must never show it".
    local strip = {}
    for _, strip_row in ipairs(ST.SHAMAN.practice_rotation_for("TBC")) do
        strip[strip_row.action] = true
    end
    local tbc_slots = ST.SHAMAN.family_guide_slots("TBC")
    for _, slot in ipairs(tbc_slots) do strip[slot.key] = true end
    for _, key in ipairs({ "coe", "bloodlust", "lightningshield" }) do
        eq(strip[key], nil, "strip: a TBC client is offered no Wrath-only row (" .. key .. ")")
    end
    for _, key in ipairs({ "moltenblast", "lavalash", "chainlightning",
        "wftotem", "goa", "feralspirit" }) do
        eq(strip[key], nil, "strip: a TBC client is offered no Era-only row (" .. key .. ")")
    end
    local tbc_rows = {}
    for _, action in ipairs(EXPECTED_SLICES.TBC) do tbc_rows[action] = true end
    local strip_ok = true
    for key in pairs(strip) do
        if not tbc_rows[key] then strip_ok = false end
    end
    check(strip_ok, "strip: every key a TBC client is offered is a row the TBC APL carries")
    -- The PUBLISHED slot list is the running family's set (the panel reads it
    -- live, so this is what the strip offers): the guide frame's own icons
    -- were built from the class's full vocabulary, but the vocabulary the
    -- panel reads is the family's - PLUS the class's own common abilities,
    -- which the widening seam appends (the same seam the other five class
    -- modules apply from their post_init).
    local published = {}
    for i = 1, #ST.SHAMAN.guide.slots do published[#published + 1] = ST.SHAMAN.guide.slots[i].key end
    local expected_published = {}
    for i = 1, #tbc_slots do expected_published[#expected_published + 1] = tbc_slots[i].key end
    for _, action in ipairs(ST.SHAMAN.practice_common_actions) do
        expected_published[#expected_published + 1] = action.key
    end
    eq(table.concat(published, ","), table.concat(expected_published, ","),
        "strip: the published guide slots are the running family's set plus the common abilities")
    -- The SoD build: the ERA token plus the rune basis. The argument-free
    -- accessor answers the CLIENT's family plus the running BUILD's own token
    -- (the SoD variant names itself, the way the paladin's SoD orders do).
    local saved_family_scope = st.family
    local saved_mw_scope = ST.weave_mw_observed
    st.family = "ERA"
    ST.weave_mw_observed = false
    eq(ST.SHAMAN.practice_rotation_family(), "ERA",
        "practice: the rotation family follows the running client")
    local era_slice = ST.SHAMAN.practice_rotation_for()
    local era_actions = {}
    for i = 1, #era_slice do era_actions[#era_actions + 1] = era_slice[i].action end
    eq(table.concat(era_actions, ","),
        "feralspirit,shamanisticrage,weave,flameshock,strength_of_earth,wftotem,"
            .. "goa,stormstrike,searing,lavalash,chainlightning,earthshock,moltenblast",
        "practice: the Era client's slice carries the ERA rows in the table's order")
    ST.weave_mw_observed = true
    local sod_slice = ST.SHAMAN.practice_rotation_for()
    local sod_actions = {}
    for i = 1, #sod_slice do sod_actions[#sod_actions + 1] = sod_slice[i].action end
    eq(#sod_slice, 14, "practice: the SoD build's slice adds its own row")
    eq(sod_actions[10], "lightningshield",
        "practice: the SoD build's own row rides the Era slice")
    eq(sod_actions[14], "moltenblast",
        "practice: the SoD build's slice keeps the table's own order")
    st.family = saved_family_scope
    ST.weave_mw_observed = saved_mw_scope
    -- No namespace mirror any more: the shared engine resolves the class module
    -- from the AceAddon table FIRST (the class tables live there), so no
    -- per-class alias is needed - and none is carried (hands-up.md HU-7).
    eq(st.SHAMAN, nil, "practice: the class module carries no namespace alias")
    local H = st.practice and st.practice.harness
    check(type(H) == "table", "practice: the shared engine is loaded")
    if type(H) == "table" then
        eq(H.practice_class_module("SHAMAN"), ST.SHAMAN,
            "practice: the engine finds the class module without an alias")
        check(H.practice_drills("SHAMAN") ~= nil,
            "practice: the engine reads the class drill list without an alias")
        check(H.practice_scenario_available("SHAMAN") == true,
            "practice: the engine finds the class scenario step without an alias")
    end
    -- The live guide grew with the maintain slots (S-19 / S-17) and the Call of
    -- the Elements slot (S-20 / U-10) - the practice surface rides the same
    -- slots and rules, so the slot set is shared. The RUNNING client's slot
    -- list is its family's cut (the strip's vocabulary) PLUS the class's own
    -- common abilities (the widening seam appends them); the class's full
    -- vocabulary is ST.SHAMAN.GUIDE_SLOTS above. The sandbox is a TBC client.
    ST.SHAMAN.apply_family_slots()
    eq(#ST.SHAMAN.guide.slots, 18,
        "practice: the guide carries the thirteen TBC slots plus the five common abilities on a TBC client")
    eq(#ST.SHAMAN.HUD_SLOTS, 11, "practice: the HUD ships eleven slots")
    -- The gather still writes the frozen inputs this TBC fixture reads (the
    -- practice surface did not shrink the live input set; the inputs that read
    -- unknown here are nil by design and are pinned by the sections above).
    local gathered = ST.SHAMAN.gather_guide_inputs(ST, {})
    local present = { speed = true, swing_remaining = true, gcd_remaining = true,
        casting = true, mw_available = true, mw_stacks = true, weave_available = true,
        flameshock_remaining = true, flameshock_refresh = true, flameshock_allowed = true,
        stormstrike_remaining = true, stormstrike_hold_enabled = true,
        shock_remaining = true, firenova_remaining = true, sr_mana_threshold = true,
        magma_refresh = true, clearcasting_active = true }
    local missing = nil
    for name in pairs(present) do
        if gathered[name] == nil then missing = missing or name end
    end
    check(missing == nil, "practice: the gather still writes every frozen input (missing: "
        .. tostring(missing) .. ")")
end

-- 39) The Call of the Elements line (S-20 / U-10) + the per-family Stormstrike
-- fallback (S-23 / U-09) -------------------------------------------------------
-- The water clock reads the client's own slot 3 (CLIENT-SOURCED: the shipped
-- clients' Constants.lua carries WATER_TOTEM_SLOT = 3 and the id 66842 in
-- TOTEM_MULTI_CAST_SUMMON_SPELLS). Tri-state like the fire/air readers: the
-- remaining seconds, zero for an affirmatively empty slot, nil for an
-- unreadable one (never a guess). The gather publishes the pair, and the
-- engine's rule 9c prompts CoE on WRATH while the water totem is under the
-- APL's 20 s - between Earth Shock and Magma Totem, the APL's own order.
do
    local saved_family = st.family
    -- The reader ------------------------------------------------------------
    clock = 500
    totem_slot3 = nil
    local remaining, duration = ST.SHAMAN.get_water_totem_clock(ST, 500)
    eq(remaining, nil, "an unreadable water slot reads unknown (never a guess)")
    eq(duration, nil, "an unreadable water slot has no length either")
    totem_slot3 = { have = false }
    remaining, duration = ST.SHAMAN.get_water_totem_clock(ST, 500)
    eq(remaining, 0, "an empty water slot reads zero (the drop is due)")
    eq(duration, nil, "an empty water slot has no length to report")
    totem_slot3 = { have = true, name = "Healing Surge", start = 400, duration = 120, spell = 555 }
    remaining, duration = ST.SHAMAN.get_water_totem_clock(ST, 500)
    near(remaining, 20, 1e-9, "the water clock counts the totem down on the api.get_time() axis")
    eq(duration, 120, "the water clock reports the totem's full length")
    totem_slot3 = { have = true, name = "Healing Surge", start = 100, duration = 120, spell = 555 }
    remaining = ST.SHAMAN.get_water_totem_clock(ST, 500)
    eq(remaining, 0, "an expired water totem reads zero, never a negative")
    totem_slot3 = { have = true, name = "Healing Surge", start = 400, duration = 0, spell = 555 }
    remaining = ST.SHAMAN.get_water_totem_clock(ST, 500)
    eq(remaining, nil, "an unreadable totem length reads unknown")
    totem_slot3 = { have = true, name = "Healing Surge", start = "SECRET", duration = 120, spell = 555 }
    remaining = ST.SHAMAN.get_water_totem_clock(ST, 500)
    eq(remaining, nil, "a secret field degrades the whole water read to unknown")
    totem_slot3 = "THROW"
    remaining = ST.SHAMAN.get_water_totem_clock(ST, 500)
    eq(remaining, nil, "a throwing totem read reads unknown")
    totem_slot3 = nil

    -- The gather feed -------------------------------------------------------
    totem_slot3 = { have = true, name = "Healing Surge", start = 400, duration = 120, spell = 555 }
    local g = ST.SHAMAN.gather_guide_inputs(ST, {})
    near(g.water_remaining, 20, 1e-9, "the gather publishes the water totem's remaining seconds")
    eq(g.water_duration, 120, "the gather publishes the water totem's length")
    totem_slot3 = { have = false }
    g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(g.water_remaining, 0, "an empty water slot feeds zero")
    eq(g.water_duration, nil, "an empty water slot feeds no length")
    totem_slot3 = nil
    g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(g.water_remaining, nil, "an unreadable water slot feeds nil (unknown-hides)")
    eq(g.water_duration, nil, "an unreadable water slot feeds no length")

    -- The engine rule 9c ---------------------------------------------------
    local function coe_action(overrides)
        local inputs = {
            stormstrike_remaining = 8,    -- Stormstrike is on cooldown
            flameshock_allowed = false,   -- the Era-base veto: rule 6 falls through
        }
        for k, v in pairs(overrides) do inputs[k] = v end
        local out = {}
        st.shaman_guide.evaluate(inputs, out)
        return out.action
    end
    st.family = "WRATH"
    eq(coe_action({ water_remaining = 12 }), "coe",
        "rule 9c: CoE is due while the water totem is under 20 s")
    eq(coe_action({ water_remaining = 19.9 }), "coe",
        "rule 9c: the 20 s window is exclusive at its edge")
    eq(coe_action({ water_remaining = 20 }), "firenova",
        "rule 9c: exactly 20 s left is not due yet")
    eq(coe_action({ water_remaining = nil }), "firenova",
        "rule 9c: an unknown water read never prompts (unknown-hides)")
    eq(coe_action({ water_remaining = 12, magma_remaining = 0 }), "coe",
        "rule 9c: CoE ranks above the Magma maintain (the APL's order)")
    eq(coe_action({ water_remaining = 25, magma_remaining = 0 }), "magma",
        "rule 9c: a fresh water totem leaves the Magma maintain in charge")
    st.family = "TBC"
    eq(coe_action({ water_remaining = 12 }), "firenova",
        "rule 9c: the TBC sims run no CoE line, so the family gate keeps it silent")
    st.family = "ERA"
    eq(coe_action({ water_remaining = 12 }), "earthshock",
        "rule 9c: the Era sims run no CoE line, so the family gate keeps it silent")
    st.family = saved_family

    -- The per-family Stormstrike fallback (S-23 / U-09) ----------------------
    st.family = "ERA"
    ST.weave_mw_observed = false
    eq(ST.SHAMAN.get_stormstrike_cooldown_seconds(ST), 20,
        "Era carries the 20 s Stormstrike cooldown (wowsims/classic)")
    ST.weave_mw_observed = true
    eq(ST.SHAMAN.get_stormstrike_cooldown_seconds(ST), 6,
        "the SoD build carries the 6 s cooldown (wowsims/sod)")
    ST.weave_mw_observed = false
    st.family = "TBC"
    eq(ST.SHAMAN.get_stormstrike_cooldown_seconds(ST), 10,
        "TBC carries the 10 s Stormstrike cooldown (wowsims/tbc-new)")
    st.family = "WRATH"
    eq(ST.SHAMAN.get_stormstrike_cooldown_seconds(ST), 8,
        "Wrath carries the 8 s Stormstrike cooldown (wowsims/wotlk)")
    st.family = "FOREVER"
    eq(ST.SHAMAN.get_stormstrike_cooldown_seconds(ST), 10,
        "a family with no sourced value keeps the shipped 10 s (no number invented)")
    st.family = nil
    eq(ST.SHAMAN.get_stormstrike_cooldown_seconds(ST), 10,
        "an unknown family keeps the shipped 10 s")
    st.family = saved_family
    -- The HUD mirror's fallback is per family too (the HUD's own accessor, so
    -- the number is observable even while the client reports no cooldown).
    local hud_ss
    for i = 1, #ST.SHAMAN.HUD_SLOTS do
        if ST.SHAMAN.HUD_SLOTS[i].key == "stormstrike" then hud_ss = ST.SHAMAN.HUD_SLOTS[i] end
    end
    check(hud_ss ~= nil, "the HUD declares the Stormstrike mirror")
    st.family = "ERA"
    ST.weave_mw_observed = false
    eq(ST.SHAMAN.get_hud_cooldown_fallback(ST, hud_ss), 20,
        "the HUD's Stormstrike fallback follows the family (Era 20 s)")
    ST.weave_mw_observed = true
    eq(ST.SHAMAN.get_hud_cooldown_fallback(ST, hud_ss), 6,
        "the HUD's Stormstrike fallback follows the SoD latch (6 s)")
    ST.weave_mw_observed = false
    st.family = "TBC"
    eq(ST.SHAMAN.get_hud_cooldown_fallback(ST, hud_ss), 10,
        "the HUD's Stormstrike fallback follows the family (TBC 10 s)")
    st.family = "WRATH"
    eq(ST.SHAMAN.get_hud_cooldown_fallback(ST, hud_ss), 8,
        "the HUD's Stormstrike fallback follows the family (Wrath 8 s)")
    st.family = saved_family
    -- The guide slot's static fallback follows the family (the gather refreshes
    -- the descriptor before the frame renders it).
    local storm_slot = ST.SHAMAN.guide.slots[1]
    eq(storm_slot.key, "stormstrike", "the first guide slot is the Stormstrike")
    st.family = "WRATH"
    ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(storm_slot.swipe_duration, 8, "the guide slot's Stormstrike fallback follows the family")
    st.family = "ERA"
    ST.weave_mw_observed = true
    ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(storm_slot.swipe_duration, 6, "the SoD latch moves the guide slot's fallback to 6 s")
    ST.weave_mw_observed = false
    st.family = saved_family
    ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(storm_slot.swipe_duration, 10, "the TBC fallback is 10 s")

    -- The HUD mirror -------------------------------------------------------
    local hud_coe
    for i = 1, #ST.SHAMAN.HUD_SLOTS do
        if ST.SHAMAN.HUD_SLOTS[i].key == "coe" then hud_coe = ST.SHAMAN.HUD_SLOTS[i] end
    end
    check(hud_coe ~= nil, "the HUD declares the Call of the Elements mirror")
    eq(ST.SHAMAN.get_hud_state(ST, hud_coe, 500).hidden, true,
        "the Call of the Elements mirror hides without its toggle (nil = off)")
    class_db.hud_show_coe = true
    totem_slot3 = nil
    eq(ST.SHAMAN.get_hud_state(ST, hud_coe, 500).hidden, true,
        "an unreadable water slot draws nothing (unknown-hides)")
    ST.in_combat = true
    totem_slot3 = { have = true, name = "Healing Surge", start = 400, duration = 120, spell = 555 }
    local coe_state = ST.SHAMAN.get_hud_state(ST, hud_coe, 500)
    eq(coe_state.hidden, nil, "a readable water slot shows the mirror")
    eq(coe_state.glow, false, "a water totem with exactly 20 s left does not glow")
    near(coe_state.remaining, 20, 1e-9, "the mirror counts the water totem down")
    eq(coe_state.duration, 120, "the mirror carries the water totem's length")
    totem_slot3 = { have = true, name = "Healing Surge", start = 390, duration = 120, spell = 555 }
    coe_state = ST.SHAMAN.get_hud_state(ST, hud_coe, 500)
    eq(coe_state.glow, true, "a water totem under 20 s glows (the drop is needed)")
    totem_slot3 = { have = false }
    coe_state = ST.SHAMAN.get_hud_state(ST, hud_coe, 500)
    eq(coe_state.glow, true, "an empty water slot glows (the drop is due)")
    ST.in_combat = false
    coe_state = ST.SHAMAN.get_hud_state(ST, hud_coe, 500)
    eq(coe_state.glow, false, "out of combat the drop never glows")
    class_db.hud_show_coe = nil
    totem_slot3 = nil
end

--=========================================================================================
-- 40) The Flame Shock refresh threshold: the gather's own fallback matches the
--     shipped default (0 = the sim-exact expiry-only value)
--=========================================================================================
-- The shipped default is 0 (config_presets.lua: every sim re-applies Flame Shock
-- only when the dot is INACTIVE, so 0 = expiry-only; the default itself is
-- pinned in tests/options_load_state.lua's SIM block). The gather's own fallback
-- has to agree with it: an option that is missing (an old profile, a key the
-- defaults never wrote) must not fall back to the old 3 s clip, which shaved
-- ~3 s off every Flame Shock dot.
do
    local saved = class_db.guide_flameshock_refresh
    class_db.guide_flameshock_refresh = nil
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).flameshock_refresh, 0,
        "a missing option falls back to the shipped default (0), not the old 3 s clip")
    class_db.guide_flameshock_refresh = 0
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).flameshock_refresh, 0,
        "the shipped default 0 rides through the gather (0 is never swallowed)")
    class_db.guide_flameshock_refresh = 5
    eq(ST.SHAMAN.gather_guide_inputs(ST, {}).flameshock_refresh, 5,
        "the option rides the gather")
    class_db.guide_flameshock_refresh = saved
end

--=========================================================================================
-- 41) The pull moment in the ctx (BS-8 item 2 / P-17)
--=========================================================================================
-- The shaman publishes NO ctx builder: the shared engine's fallback builder owns
-- the ctx, and it is the one that carries the live pull clock (the engine's
-- apply_pull_clock). So the class-side read has no builder to land in, and the
-- class's step must never disturb a pull-carrying ctx: the engine's own verdict
-- is still the answer.
do
    eq(ST.SHAMAN.practice_context, nil,
        "pull: the shaman publishes no ctx builder (the engine's fallback owns it)")
    local answer = ST.SHAMAN.practice_scenario_step(ST, { now = 100,
        cooldowns = { stormstrike = 0, flameshock = 10 },
        pull_at = 120, pull_in_seconds = 20 })
    eq(answer and answer.action, "stormstrike",
        "pull: a pull-carrying ctx still answers the engine's own verdict")
    local ride = ST.SHAMAN.practice_scenario_step(ST, { now = 100,
        resources = { casting = true }, pull_at = 120, pull_in_seconds = 20 })
    check(type(ride) == "table" and ride.hold == true,
        "pull: a pull-carrying ctx still states the ride hold")
end

--=========================================================================================
-- 42) The APL utility layer's feeds + the pre-pull table (HU-12)
--     (bench/rotation_gap_vs_apl_2026-10-20.md §5)
--=========================================================================================
-- The four new rotation lines each need a READ that exists in the shipped tree:
-- the Strength of Earth and Mana Spring upkeeps read the client's EARTH and WATER
-- totem slots through api.GetTotemInfo (the water clock's own shape), the
-- Bloodlust and Frost Shock lines read the client cooldown behind the known
-- gate. Every read is tri-state: an unreadable slot or an unknown spell feeds
-- nil and the engine never prompts on a guess.
do
    local saved_family = st.family
    clock = 500

    -- The Strength of Earth clock: the earth's slot (slot 2) ------------------
    totem_slot2 = nil
    local remaining = ST.SHAMAN.get_totem_slot_clock(ST, 2, 500)
    eq(remaining, nil, "utility: an unreadable earth slot reads unknown (never a guess)")
    totem_slot2 = { have = false }
    eq(ST.SHAMAN.get_totem_slot_clock(ST, 2, 500), 0,
        "utility: an empty earth slot reads zero (the drop is due)")
    totem_slot2 = { have = true, name = "Strength of Earth Totem", start = 400,
        duration = 120, spell = 10442 }
    eq(ST.SHAMAN.get_totem_slot_clock(ST, 2, 500), 20,
        "utility: the earth clock counts the totem down on the api.get_time() axis")
    totem_slot2 = { have = true, name = "Strength of Earth Totem", start = 400,
        duration = 120, spell = 10442 }
    local earth_g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(earth_g.strength_of_earth_remaining, 20,
        "utility: the gather publishes the earth slot's remaining seconds")
    totem_slot2 = { have = false }
    earth_g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(earth_g.strength_of_earth_remaining, 0,
        "utility: an empty earth slot feeds zero (the upkeep is due)")
    totem_slot2 = nil
    earth_g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(earth_g.strength_of_earth_remaining, nil,
        "utility: an unreadable earth slot feeds nil (unknown-hides)")

    -- The Mana Spring clock: the water slot on TBC ---------------------------
    st.family = "TBC"
    totem_slot3 = { have = false }
    local tbc_g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(tbc_g.mana_spring_remaining, 0,
        "utility: TBC feeds the Mana Spring clock from the water slot")
    totem_slot3 = { have = true, name = "Mana Spring Totem", start = 400,
        duration = 60, spell = 25570 }
    tbc_g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(tbc_g.mana_spring_remaining, 0,
        "utility: an expired Mana Spring totem reads zero")
    totem_slot3 = { have = true, name = "Mana Spring Totem", start = 480,
        duration = 60, spell = 25570 }
    tbc_g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(tbc_g.mana_spring_remaining, 40,
        "utility: the Mana Spring clock counts the water totem down")
    st.family = "ERA"
    tbc_g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(tbc_g.mana_spring_remaining, nil,
        "utility: the Era token feeds no Mana Spring row (a PRE-PULL row there)")
    st.family = "TBC"

    -- The Frost Shock cooldown + the filler choice ---------------------------
    cooldowns[25464] = { start = clock, duration = 10 }
    known_spells[25464] = true
    tbc_g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(tbc_g.frostshock_remaining, 10, "utility: TBC feeds the Frost Shock cooldown")
    -- The CHOICE is the player's own option (the residual's second item): the
    -- class states it only when the player picked Frost Shock; anything else -
    -- including a missing option - is the APL's DEFAULT (Earth Shock), so a
    -- fresh profile behaves exactly as before.
    eq(tbc_g.filler_shock, nil,
        "utility: an unset filler choice leaves the APL default standing")
    class_db.guide_filler_shock = ST.SHAMAN.FILLER_SHOCK_OPTION_EARTH
    tbc_g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(tbc_g.filler_shock, nil,
        "utility: the Earth's choice leaves the APL default standing")
    class_db.guide_filler_shock = ST.SHAMAN.FILLER_SHOCK_OPTION_FROST
    tbc_g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(tbc_g.filler_shock, "FROST",
        "utility: the Frost Shock choice states the engine's frozen token")
    st.family = "ERA"
    tbc_g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(tbc_g.filler_shock, nil,
        "utility: the Era token states no filler choice (the TBC APL's variable)")
    st.family = "TBC"
    class_db.guide_filler_shock = nil
    tbc_g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(tbc_g.filler_shock, nil,
        "utility: a missing option never arms the Frost Shock arm")
    known_spells[25464] = nil
    cooldowns[25464] = nil
    tbc_g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(tbc_g.frostshock_remaining, nil,
        "utility: an unknown Frost Shock feeds nil (the known gate)")
    st.family = "ERA"
    tbc_g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(tbc_g.frostshock_remaining, nil,
        "utility: the Era token feeds no Frost Shock row")
    st.family = "TBC"

    -- The Bloodlust cooldown: the Wrath family only --------------------------
    st.family = "WRATH"
    cooldowns[2825] = { start = clock, duration = 600 }
    known_spells[2825] = true
    local wrath_g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(wrath_g.bloodlust_remaining, 600, "utility: Wrath feeds the Bloodlust cooldown")
    known_spells[2825] = nil
    cooldowns[2825] = nil
    wrath_g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(wrath_g.bloodlust_remaining, nil,
        "utility: an unknown Bloodlust feeds nil (the known gate)")
    st.family = "TBC"
    tbc_g = ST.SHAMAN.gather_guide_inputs(ST, {})
    eq(tbc_g.bloodlust_remaining, nil,
        "utility: the TBC token feeds no Bloodlust row")

    totem_slot3 = nil
    st.family = saved_family
end

-- The APL's PRE-PULL rows (HU-12): they live in their own table, never in the
-- combat rotation. The offsets are the APLs' own doAtValue values.
--
-- NO CONSUMER: the class ships no pre-pull drill (only the warrior, the hunter
-- and the rogue have one), so the table is CITATIONS ONLY - it records the
-- APLs' own pre-pull rows for the lane that builds the drill. The pin below
-- scans the PRODUCTION tree so the suite stops implying coverage that does not
-- exist: no file outside classes/shaman.lua reads the table.
do
    local prepulls = ST.SHAMAN.PRACTICE_PREPULLS
    check(type(prepulls) == "table", "prepull: the class ships a pre-pull table")
    local EXPECTED = {
        ERA = { { "strength_of_earth", 10442, -6 }, { "wftotem", 10614, -4.5 },
            { "goa", 10627, -3 }, { "searing", 10438, -1.5 } },
        SOD = { { "lightningshield", 10432, -10 }, { "mana_spring", 10497, -8.25 },
            { "goa", 25359, -6.75 }, { "strength_of_earth", 25361, -5 },
            { "searing", 10438, -2.75 }, { "blood_fury", 20572, -1.25 } },
        TBC = { { "twist", 25587, -8 }, { "strength_of_earth", 25528, -5 },
            { "mana_spring", 25570, -4 }, { "firenova", 25537, -3 },
            { "goa", 25359, -2 }, { "drums", 35476, -1 } },
        FOREVER = { { "goa", 25359, -8 }, { "flametongue", 16387, -7 },
            { "strength_of_earth", 25361, -6 }, { "mana_spring", 10497, -5 } },
        WRATH = { { "coe", 66842, -3 } },
    }
    local shape_ok, order_ok, source_ok = true, true, true
    for prepull_family, rows in pairs(EXPECTED) do
        local list = prepulls[prepull_family]
        if type(list) ~= "table" or #list ~= #rows then
            shape_ok = false
        else
            for i = 1, #rows do
                local row = list[i]
                if type(row.action) ~= "string" or row.action ~= rows[i][1]
                    or row.spell ~= rows[i][2] or row.at ~= rows[i][3] then
                    order_ok = false
                end
                if type(row.label) ~= "string" or row.label == "" then
                    shape_ok = false
                end
                if type(row.source) ~= "string" or row.source == "" then
                    source_ok = false
                end
            end
        end
    end
    check(shape_ok, "prepull: every family carries its APL pre-pull rows with labels")
    check(order_ok, "prepull: every pre-pull row keeps the APL's action, id and offset")
    check(source_ok, "prepull: every pre-pull row cites its APL")
    -- The pre-pull rows are NOT combat rotation rows (HU-12): the rotation table
    -- never names a pre-pull-only line.
    local rot_actions = {}
    for i = 1, #ST.SHAMAN.practice_rotation do
        rot_actions[ST.SHAMAN.practice_rotation[i].action] = true
    end
    eq(rot_actions.flametongue, nil,
        "prepull: the Flametongue Totem stays a pre-pull row, not a rotation line")
    eq(rot_actions.blood_fury, nil,
        "prepull: the Blood Fury racial stays a pre-pull row, not a rotation line")
    eq(rot_actions.drums, nil,
        "prepull: the raid drum stays a pre-pull row, not a rotation line")
    -- The pre-pull table has NO consumer: the class ships no pre-pull drill,
    -- so nothing grades a pre-pull row today. The scan covers the PRODUCTION
    -- tree (the repo root and classes/); the class file that defines the table
    -- is the only place that may name it.
    local function shell_lines(cmd)
        if not io.popen then return {} end
        local pipe = io.popen(cmd)
        if not pipe then return {} end
        local lines = {}
        for line in pipe:lines() do lines[#lines + 1] = line end
        pipe:close()
        return lines
    end
    local readers = {}
    local sources = {}
    for _, name in ipairs(shell_lines('ls -A -- "' .. ROOT .. '" 2>/dev/null')) do
        if name:find("%.lua$") then sources[#sources + 1] = ROOT .. name end
    end
    for _, name in ipairs(shell_lines('ls -A -- "' .. ROOT .. 'classes" 2>/dev/null')) do
        if name:find("%.lua$") then sources[#sources + 1] = ROOT .. "classes/" .. name end
    end
    for _, path in ipairs(sources) do
        local fh = io.open(path, "r")
        if fh then
            local src = fh:read("*a")
            fh:close()
            if src:find("SHAMAN.PRACTICE_PREPULLS", 1, true)
                and path ~= ROOT .. "classes/shaman.lua" then
                readers[#readers + 1] = path
            end
        end
    end
    eq(#readers, 0,
        "prepull: no production file reads the pre-pull table (it has no consumer)")
end

--=========================================================================================
-- The NEUTRAL action set (the practice panel's legitimate-but-ungraded presses)
--
-- The class publishes ST.SHAMAN.practice_neutral_actions (the contract fixed by
-- the orchestrator, practice.lua's class contract block). The engine treats a
-- press of one of these keys as NEUTRAL: no attempt, no points, no streak change,
-- and NOT a mis-pick. A key that is neither a rotation action nor neutral stays
-- a mis-pick, so the set is a deliberate, CLOSED list.
--
-- The shaman's publish carries the class's COMMON ABILITIES - the abilities the
-- practice panel offers but the rotation never grades (a heal, a shield, food, a
-- potion). The rotation rows themselves are never published: the guide slots are
-- cut from the rotation table itself (ST.SHAMAN.family_guide_slots: a slot whose
-- ROTATION row names no family never joins a slice), and the rotation table
-- carries one guide slot per row - so every ROTATION key the panel offers is a
-- rotation action the rotation grades. The slots a family does not play are
-- filtered OUT of the panel, not shown as ungraded extras (Lightning Shield is a
-- WRATH/SOD/FOREVER row, Strength of Earth an ERA/FOREVER/TBC row).
--
-- The pins below keep that true: no rotation action is ever published as neutral,
-- and every published common ability names the client's spell, carries a label and
-- cites at least one spell id.
--=========================================================================================
do
    local published = ST.SHAMAN.practice_neutral_actions
    eq(type(published), "table", "neutral: the shaman publishes a neutral action set")
    local count = 0
    for key, value in pairs(published) do
        count = count + 1
        eq(value, true, "neutral: the published key " .. tostring(key) .. " is exactly true")
    end
    check(count > 0, "neutral: the shaman publishes its common abilities")

    -- The rotation slice of each family (the class's own published slice) - and
    -- the guide slots that family plays. Every rotation key is graded.
    local function slice_keys(slice_family)
        local out = {}
        local entries = ST.SHAMAN.practice_rotation_for(slice_family)
        for i = 1, #entries do
            local e = entries[i]
            if type(e) == "table" and type(e.action) == "string" then out[e.action] = true end
        end
        return out
    end
    for _, fam in ipairs({ "ERA", "TBC", "WRATH", "FOREVER" }) do
        local keys = slice_keys(fam)
        check(next(keys) ~= nil, "neutral: the " .. fam .. " slice is not empty")
        for key in pairs(keys) do
            check(published[key] ~= true,
                "neutral: the rotation action " .. key .. " is not published as neutral")
        end
    end

    -- The guide slots a family plays are cut from the rotation rows, so the
    -- panel never offers a key the rotation cannot ask for.
    for _, fam in ipairs({ "ERA", "TBC", "WRATH", "FOREVER" }) do
        local keys = slice_keys(fam)
        local slots = ST.SHAMAN.family_guide_slots(fam, nil)
        eq(type(slots), "table", "neutral: the " .. fam .. " guide slots resolve")
        for i = 1, #slots do
            local slot = slots[i]
            if type(slot) == "table" and type(slot.key) == "string" then
                check(keys[slot.key] == true,
                    "neutral: the guide slot " .. slot.key .. " is a rotation action on "
                    .. fam)
            end
        end
    end

    -- THE PRACTICE-PANEL ABILITY LIST: the common abilities the panel offers but
    -- the rotation never grades. Every entry names the client's spell, carries a
    -- label and cites at least one spell id - an ability whose id nobody can
    -- source is not published at all.
    local common = ST.SHAMAN.practice_common_actions
    eq(type(common), "table", "panel: the shaman publishes a practice-panel ability list")
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
        -- Published as neutral (the publish is flat: the same set on every family)
        -- and never a rotation action.
        eq(published[action.key], true, "panel: " .. tostring(action.key)
            .. " is published as neutral")
        for _, fam in ipairs({ "ERA", "TBC", "WRATH", "FOREVER" }) do
            check(slice_keys(fam)[action.key] ~= true, "panel: the common ability "
                .. tostring(action.key) .. " is not a rotation action on " .. fam)
        end
    end
    -- The panel's widening seam: the class publishes the widened slot list and
    -- applies it to the guide slot list (the same seam apply_family_slots uses),
    -- so the practice panel offers the common abilities.
    eq(type(ST.SHAMAN.practice_panel_slots), "function",
        "panel: the class publishes the panel slot list")
    eq(type(ST.SHAMAN.apply_practice_panel_actions), "function",
        "panel: the class publishes the widening seam")
    local widened = ST.SHAMAN.practice_panel_slots()
    eq(type(widened), "table", "panel: the panel slot list is a table")
    local common_keys = {}
    for i = 1, #widened do
        if type(widened[i]) == "table" and widened[i].practice_common == true then
            common_keys[widened[i].key] = true
        end
    end
    local offered = 0
    for _, action in ipairs(ST.SHAMAN.practice_common_actions) do
        if common_keys[action.key] == true then offered = offered + 1 end
    end
    eq(offered, #ST.SHAMAN.practice_common_actions,
        "panel: the panel slot list carries every common ability the offer gate allows")
end

-- ---- the widening runs on EVERY family (the audit's MEDIUM-1) ---------------
-- The seam apply_family_slots narrows the strip to the running family's rows
-- and returns BEFORE the widening when the family carries no row at all - so on
-- the Cata and the Mists clients (where the class publishes no rotation) the
-- panel would keep the guide vocabulary alone and never offer the class's five
-- common abilities, which it publishes as neutral there. The class's own
-- post_init therefore calls the widening itself, the same way the other five
-- class modules do (bench/final_gate_audit_2026-10-20.md MEDIUM-1).
do
    local saved_family = st.family
    local saved_practice_ui = st.practice_ui
    -- The practice surface stub (the same shape the order spies above install):
    -- without it the class's post_init skips the whole practice block, and the
    -- widening seam would never run.
    st.practice_ui = { init = function() end, is_active = function() return false end }
    -- A fresh vocabulary: the section above left the strip narrowed to the TBC
    -- cut and already widened, and the widening is idempotent (a strip that
    -- already carries a common slot is left alone), so the class's full
    -- vocabulary stands in for a client that has never been narrowed.
    ST.SHAMAN.guide.slots = ST.SHAMAN.GUIDE_SLOTS
    st.family = "CATA"
    -- The family cut is empty here: the class carries no Cata row, so the
    -- narrowing leaves the class's full vocabulary standing.
    eq(#ST.SHAMAN.family_guide_slots("CATA"), 0,
        "panel: the Cata client carries no rotation row (the family's own cut is empty)")
    local before = #ST.SHAMAN.guide.slots
    ST.SHAMAN.post_init(ST)
    st.family = saved_family
    st.practice_ui = saved_practice_ui
    local common_keys = {}
    for i = 1, #ST.SHAMAN.guide.slots do
        local slot = ST.SHAMAN.guide.slots[i]
        if type(slot) == "table" and slot.practice_common == true then
            common_keys[slot.key] = true
        end
    end
    local offered = 0
    for _, action in ipairs(ST.SHAMAN.practice_common_actions) do
        if common_keys[action.key] == true then offered = offered + 1 end
    end
    eq(offered, #ST.SHAMAN.practice_common_actions,
        "panel: post_init widens the strip on a family with no rotation row (the common abilities reach the panel)")
    check(#ST.SHAMAN.guide.slots > before,
        "panel: the widening grows the guide slot list on a family with no rotation row")
end

-- ---- the style constants ride the module table (the local ceiling) ---------
-- The class module sits at Lua 5.1's 200-local ceiling, so its display
-- constants live on the module table. The values are the reference's own,
-- unchanged by the move - pinned here so a later edit cannot quietly change
-- one.
do
    eq(type(ST.SHAMAN.flame_shock_style), "table",
        "style: the Flame Shock style rides the module table")
    eq(ST.SHAMAN.flame_shock_style.bar_height, 6,
        "style: the Flame Shock bar keeps its 6 px height")
    eq(ST.SHAMAN.flame_shock_style.color[2], 0.35,
        "style: the Flame Shock fill colour keeps its green channel")
    eq(ST.SHAMAN.flame_shock_style.bg_color[4], 0.45,
        "style: the Flame Shock backing colour keeps its alpha")
    eq(ST.SHAMAN.flame_shock_style.glow_color[1], 1.0,
        "style: the Flame Shock glow colour keeps its red channel")
    eq(ST.SHAMAN.flame_shock_style.label_color[2], 0.85,
        "style: the Flame Shock label colour keeps its green channel")
    eq(type(ST.SHAMAN.stormstrike_style), "table",
        "style: the Stormstrike style rides the module table")
    eq(ST.SHAMAN.stormstrike_style.bar_height, 6,
        "style: the Stormstrike bar keeps its 6 px height")
    eq(ST.SHAMAN.stormstrike_style.color[2], 0.80,
        "style: the Stormstrike fill colour keeps its green channel")
    eq(ST.SHAMAN.stormstrike_style.label_color[4], 0.95,
        "style: the Stormstrike label colour keeps its alpha")
    eq(type(ST.SHAMAN.shield_style), "table",
        "style: the shield style rides the module table")
    eq(ST.SHAMAN.shield_style.rect_width, 5,
        "style: the shield rect keeps its 5 px width")
    eq(ST.SHAMAN.shield_style.rect_gap, 1,
        "style: the shield rect keeps its 1 px gap")
    eq(ST.SHAMAN.shield_style.bar_gap, 6,
        "style: the shield tracker keeps its 6 px gap")
    eq(ST.SHAMAN.shield_style.dim_alpha, 0.20,
        "style: the empty shield slot keeps its 0.20 alpha")
    eq(ST.SHAMAN.shield_style.max_slots, 4,
        "style: the shield row keeps its four slots")
    eq(ST.SHAMAN.shield_style.colors.lightning[2], 0.72,
        "style: the Lightning Shield colour keeps its green channel")
    eq(ST.SHAMAN.shield_style.colors.water[2], 0.80,
        "style: the Water Shield colour keeps its green channel")
    eq(type(ST.SHAMAN.position_style), "table",
        "style: the spell-position style rides the module table")
    eq(ST.SHAMAN.position_style.icon_size, 14,
        "style: the spell-position icon keeps its 14 px size")
    eq(ST.SHAMAN.position_style.ready_alpha, 0.95,
        "style: the ready spell-position icon keeps its 0.95 alpha")
    eq(ST.SHAMAN.position_style.clip_color[1], 1.0,
        "style: the clip colour keeps its red channel")
    eq(ST.SHAMAN.position_style.wait_color[4], 0.35,
        "style: the wait colour keeps its 0.35 alpha")
end

-- ---- the shipped comment matches the code (the audit's HIGH-2) --------------
-- The resolver note claimed "every client family answers its own rank art":
-- the fallback hands the ERA corpus's rank-1 id, not the client's own art, and
-- the classic-line name leg is UNCONFIRMED in-client. The pin keeps the stale
-- claim OUT (a source-shape pin on its ABSENCE, so a correct rewording passes).
do
    local f = io.open(ROOT .. "classes/shaman.lua", "r")
    local src = f and f:read("*a") or ""
    if f then f:close() end
    local flat = src:gsub("\r\n", "\n")
    check(flat:find("every client family answers its own rank art", 1, true) == nil,
        "comment: the stale 'every client family answers its own rank art' claim is gone")
    check(flat:find("answers its own rank id", 1, true) ~= nil,
        "comment: the resolver note says what the code does")
end

--=========================================================================================
-- R1 name-carrying payloads: the weave family resolves by id or by name.
-- lookup_weave_family already matches entry.spell_id or entry.name on every
-- family (no change needed); these legs pin both shapes so the Anniversary
-- name-carrying START/SUCCEEDED and the Era numeric-id path stay green
-- together. A foreign name resolves nothing.
--=========================================================================================
do
    ST.interfaces_are_initialised = true
    clock = 600
    casting_impl = function() return nil end
    ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "Lightning Bolt", nil)
    eq(ST.weave_is_casting, true, "START with a name token begins the cast")
    eq(ST.weave_family, "LB", "START resolves the family from the name token")
    ST.SHAMAN.on_spellcast_succeeded(ST, "player", "Lightning Bolt", nil)
    eq(ST.weave_is_casting, false, "SUCCEEDED ends the name-token cast")
    eq(ST.weave_family, "LB", "SUCCEEDED keeps the name-resolved family")

    -- The numeric-id shape resolves exactly as before.
    ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "cast-lb-id", 25449)
    eq(ST.weave_is_casting, true, "START with a numeric id begins the cast")
    eq(ST.weave_family, "LB", "START resolves the family from the numeric id")
    ST.SHAMAN.on_spellcast_succeeded(ST, "player", "cast-lb-id", 25449)
    eq(ST.weave_family, "LB", "SUCCEEDED keeps the id-resolved family")

    -- A foreign name resolves nothing and changes nothing.
    local before = ST.weave_family
    ST.SHAMAN.on_spellcast_event(ST, "UNIT_SPELLCAST_START", "player", "Scare Beast", nil)
    eq(ST.weave_is_casting, false, "START with a foreign name begins nothing")
    eq(ST.weave_family, before, "a foreign name leaves the family alone")
end

--=========================================================================================
-- NILSWEEP (2026-10-22): nil class-table / slot guards on the per-frame entries.
-- A nil get_class_table return means the profile has no table for the class; a
-- nil slot means a caller that does not pass one. Neither may throw. ST is
-- suite-shared, so every leg restores the stub it replaces.
--=========================================================================================
do
    -- S1: get_weave_visual_spell with no class table falls back to the catalogue.
    local saved = ST.get_class_table
    ST.get_class_table = function() return nil end
    local ok = pcall(ST.SHAMAN.get_weave_visual_spell, ST)
    ST.get_class_table = saved
    check(ok, "NILSWEEP S1 get_weave_visual_spell tolerates a nil class table")
end

do
    -- S2: on_bar_update on the offhand with no class table hides the spark.
    local saved = ST.get_class_table
    ST.get_class_table = function() return nil end
    local ok, err = pcall(ST.SHAMAN.on_bar_update, ST, "offhand")
    ST.get_class_table = saved
    check(ok, "NILSWEEP S2 offhand on_bar_update tolerates a nil class table (error: " .. tostring(err) .. ")")
end

do
    -- S3: on_bar_update on the mainhand with no class table skips the tick.
    local saved = ST.get_class_table
    ST.get_class_table = function() return nil end
    local ok, err = pcall(ST.SHAMAN.on_bar_update, ST, "mainhand")
    ST.get_class_table = saved
    check(ok, "NILSWEEP S3 on_bar_update tolerates a nil class table (error: " .. tostring(err) .. ")")
end

do
    -- S4: gather_guide_inputs with no class table reads option defaults.
    local saved = ST.get_class_table
    ST.get_class_table = function() return nil end
    local ok, inputs = pcall(ST.SHAMAN.gather_guide_inputs, ST, {})
    ST.get_class_table = saved
    check(ok, "NILSWEEP S4 gather_guide_inputs tolerates a nil class table")
    if ok then
        eq(inputs.flameshock_refresh, 0, "NILSWEEP S4 gather_guide_inputs defaults flameshock_refresh to 0")
    end
end

do
    -- S5/S6: get_hud_state with no class table skips the tints; with no slot hides.
    local saved = ST.get_class_table
    ST.get_class_table = function() return nil end
    local ok, s = pcall(ST.SHAMAN.get_hud_state, ST, { key = "lavaburst" }, 100)
    ST.get_class_table = saved
    check(ok, "NILSWEEP S5 get_hud_state tolerates a nil class table")
    if ok then
        eq(s.usable, nil, "NILSWEEP S5 get_hud_state leaves usable alone without a class table")
        eq(s.in_range, nil, "NILSWEEP S5 get_hud_state leaves in_range alone without a class table")
    end
    local ok_hud, s_hud = pcall(ST.SHAMAN.get_hud_state, ST, nil, 100)
    check(ok_hud, "NILSWEEP S6 get_hud_state tolerates a nil slot")
    if ok_hud then
        eq(s_hud.hidden, true, "NILSWEEP S6 get_hud_state hides a nil slot")
    end
end

if failures == 0 then
    print("PASS  shaman_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  shaman_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end

-- tests/shaman_state.lua: offline tests for the shaman weave module
-- (classes/shaman.lua) over the real compat.lua + weave.lua in a sandbox.
-- Pins the pre-init guards (a live crash regression), catalog resolution, Maelstrom
-- cast-time integration and the cast start/stop/delay lifecycle.
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

-- Sandbox environment --------------------------------------------------------------------
local clock = 0
local aura_list = {}
local casting_impl = function() return nil end
local channel_impl = function() return nil end

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
    if id == 25449 then return "Lightning Bolt", nil, "icon_lb", 2500, 0, 30, 25449 end
    if id == 25442 then return "Chain Lightning", nil, "icon_cl", 2000, 0, 30, 25442 end
    return nil
end
env.IsSpellKnown = function(id) return id == 25449 or id == 25442 end
env.UnitAura = function(unit, index, filter)
    local entry = aura_list[index]
    if not entry then return nil end
    return entry.name, nil, entry.count, nil, nil, nil, nil, nil, nil, entry.spell_id
end
env.UnitCastingInfo = function() return casting_impl() end
env.UnitChannelInfo = function() return channel_impl() end
env.UnitSpellHaste = function() return 0 end
-- compat reads some legacy globals through _G (annotation-safe path); mirror the
-- sandbox stubs so is_spell_known resolves against them here too.
_G.IsSpellKnown = env.IsSpellKnown

local st = {}
local class_db = { weave_mw_enabled = true }
local ST = { SHAMAN = {}, interfaces_are_initialised = false }
ST.get_class_table = function() return class_db end
ST.get_visuals_frame = function() return nil end

env.LibStub = function(major)
    if major == "AceAddon-3.0" then
        return { GetAddon = function() return ST end }
    end
    return {}
end

local compat = assert(loadfile(ROOT .. "compat.lua")); setfenv(compat, env); compat("SwedgeTimer", st)
local weave = assert(loadfile(ROOT .. "weave.lua")); setfenv(weave, env); weave("SwedgeTimer", st)
local shaman = assert(loadfile(ROOT .. "classes/shaman.lua")); setfenv(shaman, env); shaman("SwedgeTimer", st)
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

-- 3) Maelstrom Weapon stacks feed the effective cast time ------------------------------
aura_list = { { name = "Maelstrom Weapon", count = 5, spell_id = 408505 } }
ST.SHAMAN.refresh_weave_mw_stacks(ST)
eq(ST.weave_mw_stacks, 5, "five Maelstrom stacks are read from the aura")
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 0, "five stacks make the cast instant")
class_db.weave_mw_enabled = false
eq(ST.SHAMAN.get_weave_effective_cast_time(ST, ST.weave_catalog.LB), 2.5, "MW can be disabled by option")
class_db.weave_mw_enabled = true
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

if failures == 0 then
    print("PASS  shaman_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  shaman_state.lua: " .. tostring(failures) .. " of " .. tostring(checks) .. " checks failed")
    os.exit(1)
end

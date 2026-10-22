-- tests/class_activation_state.lua: proves the operator's class-activation order across
-- ALL SIX real class modules (operator order 2026-10-21: "you only load the fucking class
-- that is playing. that should be determined in options. rogue should only load for rogue
-- the rest should not load.").
--
-- Unlike tests/main_init_state.lua (which pins main.lua's init order with a synthetic
-- loader) this suite loads classes/druid.lua, classes/hunter.lua, classes/paladin.lua,
-- classes/rogue.lua, classes/shaman.lua and classes/warrior.lua into ONE sandbox, then
-- runs the SHIPPED activation function (extracted from main.lua and executed here) and
-- checks the operator's contract on the real tables:
--
--   1. At load every class file only REGISTERS its loader: all six ST.<CLASS> tables are
--      empty (no functions, tables or hooks) before activation.
--   2. Activate ONE class -> that class has its hooks and practice contract; the other
--      five tables stay EMPTY. Any registration in a non-selected table fails loudly
--      with the offending keys listed.
--   3. The selection follows the option: "Auto" activates the PLAYING class; an explicit
--      class (including lower case) activates that class instead.
--   4. A loader that throws fails closed: no crash, no half-state (the class table is
--      reset), exactly one clear notice naming the class and the error.
--   5. A class with no loader is reported, not crashed: one notice naming it, every
--      class table still empty. "Auto" on an unsupported class stays silent (the A1
--      decision: an unsupported class must not print at every login).
--
-- Run from the repo root: lua5.1 tests/class_activation_state.lua  (any cwd works).

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
local function contains(text, needle, label)
    check(type(text) == "string" and text:find(needle, 1, true) ~= nil,
        label .. "  (expected '" .. tostring(needle) .. "' in '" .. tostring(text) .. "')")
end

local CLASSES = { "DRUID", "HUNTER", "PALADIN", "ROGUE", "SHAMAN", "WARRIOR" }
-- The TOC order of the class modules (all six are listed by every flavor TOC).
local CLASS_MODULES = {
    "classes/druid.lua", "classes/hunter.lua", "classes/paladin.lua",
    "classes/rogue.lua", "classes/shaman.lua", "classes/warrior.lua",
}

--=========================================================================================
-- The SHIPPED activation function
--=========================================================================================
-- main.lua's ST:activate_class() is self-contained: self.player_class,
-- self.get_class_table(), st.class_loaders and self:Print. Extracting that one function
-- (its signature line to the next column-0 `end`) lets this suite execute the REAL
-- selection/fail-closed code against the real class registry without booting the whole
-- addon; main.lua's order and notice text are already pinned by tests/main_init_state.lua
-- and tests/wiring_check.lua.
local function shipped_activation_source()
    local lines = {}
    local f = assert(io.open(ROOT .. "main.lua", "r"))
    for line in f:lines() do
        lines[#lines + 1] = line
    end
    f:close()
    local start_line
    for i = 1, #lines do
        if lines[i]:match("^function ST:activate_class%(%)%s*$") then
            start_line = i
            break
        end
    end
    assert(start_line, "main.lua defines ST:activate_class")
    local end_line
    for i = start_line + 1, #lines do
        if lines[i]:match("^end%s*$") then
            end_line = i
            break
        end
    end
    assert(end_line, "ST:activate_class is closed by a column-0 end")
    local src = table.concat(lines, "\n", start_line, end_line)
    src = src:gsub("^function ST:activate_class%(%)",
        "local function activate_class(self)", 1)
    return src .. "\nreturn activate_class"
end

local ACTIVATION_SOURCE = shipped_activation_source()

--=========================================================================================
-- The sandbox: the real compat.lua + utils.lua + all six real class modules
--=========================================================================================
local function make_frame()
    return setmetatable({}, { __index = function() return function() end end })
end

local function build()
    local sb = { notices = {} }
    local env = setmetatable({}, { __index = _G })
    env.WOW_PROJECT_ID = 2
    env.WOW_PROJECT_CLASSIC = 2
    env.GetLocale = function() return "enUS" end
    env.GetTime = function() return 0 end
    env.GetTimePreciseSec = function() return 0 end
    env.CreateFrame = function() return make_frame() end
    env.UIParent = make_frame()
    env.C_EventUtils = { IsEventValid = function() return true end }
    env.GetSpellInfo = function() return nil end
    env.GetSpellCooldown = function() return 0, 0, 0 end
    env.GetSpellPowerCost = function() return nil end
    env.GetSpellTexture = function() return nil end
    env.IsSpellKnown = function() return false end
    env.GetTalentInfo = function() return nil end
    env.GetActiveTalentGroup = function() return 1 end
    env.GetNumSpellTabs = function() return 0 end
    env.GetSpellTabInfo = function() return nil end
    env.GetItemInfo = function() return nil end
    env.GetItemCount = function() return 0 end
    env.GetItemCooldown = function() return 0, 0 end
    env.UnitGUID = function() return nil end
    env.UnitExists = function() return false end
    env.UnitCanAttack = function() return false end
    env.InCombatLockdown = function() return false end
    env.IsInInstance = function() return false end
    env.GetInstanceInfo = function() return nil end

    local ST = { notices = {} }
    for i = 1, #CLASSES do
        ST[CLASSES[i]] = {}
    end
    function ST:Print(msg)
        self.notices[#self.notices + 1] = tostring(msg)
    end
    function ST:get_class_table()
        return { class_activation = self.selection }
    end
    sb.ST = ST

    local LCG = { PixelGlow_Start = function() end, PixelGlow_Stop = function() end }
    local LSM = { Fetch = function() return nil end, HashTable = function() return {} end }
    local LBCD = { RegisterDebuff = function() end, RegisterBuff = function() end }
    env.LibStub = function(major)
        if major == "AceAddon-3.0" then
            return { GetAddon = function() return ST end }
        elseif major == "LibCustomGlow-1.0" then
            return LCG
        elseif major == "LibSharedMedia-3.0" then
            return LSM
        elseif major == "LibClassicDurations" then
            return LBCD
        end
        error("class_activation_state: unexpected LibStub major " .. tostring(major), 2)
    end

    -- compat.lua reads several legacy globals through rawget(_G); mirror every sandbox
    -- stub for the duration of the load, then restore _G exactly.
    local mirrored = {}
    for name, value in pairs(env) do
        mirrored[name] = { value = rawget(_G, name), present = rawget(_G, name) ~= nil }
        _G[name] = value
    end

    local st = {}
    local modules = { "compat.lua", "utils.lua" }
    for i = 1, #CLASS_MODULES do
        modules[#modules + 1] = CLASS_MODULES[i]
    end
    for i = 1, #modules do
        local chunk = assert(loadfile(ROOT .. modules[i]))
        setfenv(chunk, env)
        local ok, err = pcall(chunk, "SwedgeTimer", st)
        if not ok then
            print("FAIL  " .. modules[i] .. " does not load under the sandbox: " .. tostring(err))
            os.exit(1)
        end
    end

    for name, previous in pairs(mirrored) do
        _G[name] = previous.value
        if not previous.present then _G[name] = nil end
    end

    sb.env, sb.st = env, st
    return sb
end

-- Runs the SHIPPED activation against this sandbox's real class registry.
local function activate(sb, selection, player_class)
    local chunk = assert(loadstring(ACTIVATION_SOURCE, "activate_class"))
    setfenv(chunk, setmetatable({ st = sb.st }, { __index = _G }))
    local activate_class = chunk()
    sb.ST.player_class = player_class
    sb.ST.selection = selection
    local ok, result, reason = pcall(activate_class, sb.ST)
    return ok, result, reason
end

-- Fails loudly, listing exactly what a non-selected (or pre-activation) class table has
-- registered - no functions, tables or hooks are allowed there.
local function class_is_empty(sb, class, label)
    local registered = {}
    for key, value in pairs(sb.ST[class] or {}) do
        registered[#registered + 1] = tostring(key) .. " (" .. type(value) .. ")"
    end
    local detail = ""
    if #registered > 0 then
        local shown = {}
        for i = 1, math.min(#registered, 8) do
            shown[i] = registered[i]
        end
        detail = ": " .. table.concat(shown, ", ")
        if #registered > 8 then
            detail = detail .. ", and " .. tostring(#registered - 8) .. " more"
        end
    end
    check(#registered == 0, label .. " - no functions, tables or hooks" .. detail)
end

local function all_empty_except(sb, activated, label)
    for i = 1, #CLASSES do
        local class = CLASSES[i]
        if class ~= activated then
            class_is_empty(sb, class, label .. ": " .. class .. " stays inert")
        end
    end
end

--=========================================================================================
-- 0) Load-time shape: every file registers a loader and runs NO body
--=========================================================================================
local base = build()
for i = 1, #CLASS_MODULES do
    local class = CLASSES[i]
    eq(type(base.st.class_loaders and base.st.class_loaders[class]), "function",
        CLASS_MODULES[i] .. " registers the " .. class .. " loader")
end
for i = 1, #CLASSES do
    local class = CLASSES[i]
    class_is_empty(base, class,
        "at load " .. class .. " has not executed its body")
end

--=========================================================================================
-- 1) Auto activates the PLAYING class; the other five stay empty
--=========================================================================================
do
    local sb = build()
    local druid_table = sb.ST.DRUID
    local ok, result = activate(sb, "Auto", "DRUID")
    check(ok, "Auto activation does not crash")
    eq(result, true, "Auto activation reports success")
    check(sb.ST.DRUID == druid_table,
        "activation populates the class table main.lua created (no replacement)")
    eq(type(sb.ST.DRUID.post_init), "function", "the activated class has its post_init hook")
    eq(type(sb.ST.DRUID.on_bar_update), "function", "the activated class has its bar hook")
    eq(type(sb.ST.DRUID.practice_scenario_step), "function",
        "the activated class keeps its practice contract")
    all_empty_except(sb, "DRUID", "Auto")
    eq(#sb.ST.notices, 0, "Auto activation prints no notice")
end

--=========================================================================================
-- 2) An explicit pick activates THAT class (and resolves lower case)
--=========================================================================================
do
    local sb = build()
    local paladin_table = sb.ST.PALADIN
    local ok, result = activate(sb, "paladin", "WARRIOR")
    check(ok, "an explicit activation does not crash")
    eq(result, true, "an explicit activation reports success")
    check(sb.ST.PALADIN == paladin_table,
        "activation populates the selected class table (no replacement)")
    eq(type(sb.ST.PALADIN.post_init), "function",
        "the selected class has its post_init hook")
    eq(type(sb.ST.PALADIN.on_bar_update), "function",
        "the selected class has its bar hook")
    eq(type(sb.ST.PALADIN.practice_scenario_step), "function",
        "the selected class keeps its practice contract")
    class_is_empty(sb, "WARRIOR",
        "the playing class did NOT activate when another is selected")
    all_empty_except(sb, "PALADIN", "explicit")
    eq(#sb.ST.notices, 0, "a resolvable explicit selection prints no notice")
end

--=========================================================================================
-- 3) A loader that throws fails closed: no crash, no half-state, one clear notice
--=========================================================================================
do
    local sb = build()
    sb.st.class_loaders["SHAMAN"] = function()
        sb.ST.SHAMAN.partial = true
        error("unit-test loader exploded")
    end
    local ok, result = activate(sb, "SHAMAN", "PALADIN")
    check(ok, "a throwing loader does not escape activation")
    eq(result, false, "a throwing loader reports failure")
    class_is_empty(sb, "SHAMAN", "the throwing loader's half-state is rolled back")
    eq(#sb.ST.notices, 1, "the throwing loader prints exactly one notice")
    contains(sb.ST.notices[1], "SHAMAN class module failed to load",
        "the notice names the failing class")
    contains(sb.ST.notices[1], "unit-test loader exploded", "the notice carries the error")
    class_is_empty(sb, "PALADIN", "a failed explicit pick does not fall back to the playing class")
    all_empty_except(sb, "SHAMAN", "throwing loader")
end

--=========================================================================================
-- 4) A class with no loader is reported, not crashed
--=========================================================================================
do
    local sb = build()
    sb.st.class_loaders["MONK"] = nil
    local ok, result, reason = activate(sb, "MONK", "PALADIN")
    check(ok, "a missing loader does not crash activation")
    eq(result, false, "a missing loader reports failure")
    eq(reason, "no-loader", "a missing loader reports the no-loader reason")
    eq(#sb.ST.notices, 1, "a missing explicit module prints exactly one notice")
    contains(sb.ST.notices[1], "no class module is available for MONK",
        "the notice names the missing class")
    for i = 1, #CLASSES do
        local class = CLASSES[i]
        class_is_empty(sb, class, "a missing module leaves " .. class .. " empty")
    end
end

--=========================================================================================
-- 5) Auto on a class with no module stays silent (the A1 decision)
--=========================================================================================
do
    local sb = build()
    local ok, result, reason = activate(sb, "Auto", "MAGE")
    check(ok, "Auto on an unsupported class does not crash")
    eq(result, false, "Auto on an unsupported class reports no loader")
    eq(reason, "no-loader", "Auto on an unsupported class reports the no-loader reason")
    eq(#sb.ST.notices, 0, "Auto on an unsupported class prints no notice")
    for i = 1, #CLASSES do
        local class = CLASSES[i]
        class_is_empty(sb, class, "Auto on an unsupported class leaves " .. class .. " empty")
    end
end

if failures == 0 then
    print("PASS  class_activation_state.lua (" .. tostring(checks) .. " checks)")
else
    print("FAIL  class_activation_state.lua: " .. tostring(failures) .. " of "
        .. tostring(checks) .. " checks failed")
    os.exit(1)
end

-- tests/weave_range_state.lua: offline tests for the PURE half of weave_range.lua - the
-- ranged distance bar's maths and its nil-safe enable rule.
--
-- Two sandboxes, each loading the real module file:
--   1. WoW-free: asserts weave_range.lua loads with no CreateFrame/UIParent/LibStub at
--      all, then pins every pure helper (fill fraction, state word, yards label, class
--      far bound, the enable rule).
--   2. Inert: no UIParent/CreateFrame - init() must stay a safe no-op and update()/
--      poll() must not throw.
-- A static scan pins the contract that the module has ONE distance source
-- (st.api.UnitDistance), no range library, no band fallback and no clock/API call of
-- its own.
--
-- The frame driver (creation, anchoring, screen clamp, paint latching, driver cadence,
-- guard) lives in tests/weave_bar_state.lua.
--
-- Plain Lua 5.1, no WoW client needed. Run from the repo root:
-- lua5.1 tests/weave_range_state.lua  (any cwd works; ROOT follows arg[0]).

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
local function near(got, want, label)
    checks = checks + 1
    if type(got) ~= "number" or math.abs(got - want) > 1e-9 then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end

--=========================================================================================
-- 0. Static contract: one distance source, no library, no band fallback, no clock
--=========================================================================================
-- HU-23: `st.api.UnitDistance("target")` is the ONLY distance read. These tokens are the
-- call shapes a second source, the old band fallback, a library or a direct client call
-- would use; the module's prose may NAME them, never call them.
local src_file = assert(io.open(ROOT .. "weave_range.lua", "r"))
local src = src_file:read("*a")
src_file:close()
for _, token in ipairs({
    "LibStub(", "GetRange(", "IsSpellInRange(", "CheckInteractDistance(",
    "UnitDistanceSquared(", "C_Timer", "GetTime(",
}) do
    check(src:find(token, 1, true) == nil, "source has no " .. token .. " call")
end
check(src:find("st.api.UnitDistance(", 1, true) ~= nil, "source reads st.api.UnitDistance")
check(src:find("target_min_range", 1, true) == nil, "source has no LibRangeCheck band read")
check(src:find("target_max_range", 1, true) == nil, "source has no LibRangeCheck band read")
check(src:find("proximity_fraction(", 1, true) == nil, "the band-proxy helper is gone")
check(src:find("distance_proxy(", 1, true) == nil, "the band-proxy helper is gone")
check(src:find("format_yards(5", 1, true) == nil, "no band label formatter remains")

--=========================================================================================
-- 1. WoW-free sandbox: load + pure helpers
--=========================================================================================
local st = {}
local env = setmetatable({}, { __index = _G })
local mod = assert(loadfile(ROOT .. "weave_range.lua"))
setfenv(mod, env)
local ok, err = pcall(function() mod("SwedgeTimer", st) end)
check(ok, "weave_range.lua loads under a WoW-free sandbox (" .. tostring(err) .. ")")
local wr = st.weave_range
check(type(wr) == "table", "st.weave_range table exists")

-- constants ----------------------------------------------------------------
eq(wr.NEAR_YARDS, 5, "NEAR_YARDS == 5")
eq(wr.FAR_YARDS, 30, "FAR_YARDS == 30 (non-hunter)")
eq(wr.HUNTER_FAR_YARDS, 35, "HUNTER_FAR_YARDS == 35")
eq(wr.UPDATE_INTERVAL, 0.05, "UPDATE_INTERVAL == 0.05")
eq(wr.DISABLED_INTERVAL, 0.5, "DISABLED_INTERVAL == 0.5")
eq(wr.BAR_HEIGHT, 10, "BAR_HEIGHT == 10 (horizontal bar)")
eq(wr.BG_COLOR[4], 0.85, "the backdrop ships near-opaque (operator report: not see-through)")

-- far_yards_for ------------------------------------------------------------
eq(wr.far_yards_for("HUNTER"), 35, "far: HUNTER gets the Auto Shot band")
eq(wr.far_yards_for("PALADIN"), 30, "far: another class gets the shared band")
eq(wr.far_yards_for(nil), 30, "far: an unknown class token gets the shared band")
eq(wr.far_yards_for("hunter"), 30, "far: only the uppercase UnitClass token is a hunter")

-- class_default_on ---------------------------------------------------------
-- The nil answer is DELEGATED to config_presets.lua's ST.weave_range_default_enabled
-- (the same reader the options getter uses). The module must not hardcode a class: a
-- helper that says off wins even for a hunter token.
local hunter_default_st = {
    player_class = "HUNTER",
    weave_range_default_enabled = function(token) return token == "HUNTER" end,
}
eq(wr.class_default_on(hunter_default_st), true, "default: the helper's hunter answer")
eq(wr.class_default_on({ player_class = "PALADIN",
    weave_range_default_enabled = function() return false end }), false,
    "default: the helper's non-hunter answer")
eq(wr.class_default_on({ player_class = "HUNTER",
    weave_range_default_enabled = function() return false end }), false,
    "default: a helper that says off beats the hunter token (no hardcoded class)")
eq(wr.class_default_on({ player_class = "HUNTER" }), false,
    "default: no helper at all reads off, never an invented class default")
eq(wr.class_default_on(nil), false, "default: a nil addon object reads off")
eq(wr.class_default_on({ player_class = "HUNTER",
    weave_range_default_enabled = function() return "yes" end }), false,
    "default: only an explicit true counts")

-- enabled_for --------------------------------------------------------------
-- Explicit saved values win both ways; nil takes the resolved class default.
eq(wr.enabled_for({ class_enabled = true, weave_range_enabled = true }, nil, false), true,
    "gate: explicit true is on even when the default is off")
eq(wr.enabled_for({ class_enabled = true, weave_range_enabled = false }, nil, true), false,
    "gate: explicit false beats an on default")
eq(wr.enabled_for({ class_enabled = true }, nil, true),
    true, "gate: nil takes the on default")
eq(wr.enabled_for({ class_enabled = true }, nil, false),
    false, "gate: nil takes the off default")
eq(wr.enabled_for({ class_enabled = true, weave_range_enabled = nil }, nil, true), true,
    "gate: an explicit nil key takes the default")
eq(wr.enabled_for({ class_enabled = false, weave_range_enabled = true }, nil, true), false,
    "gate: the class master switch wins")
eq(wr.enabled_for({ class_enabled = true, weave_range_enabled = true },
    { enabled = false }, true), false, "gate: the profile master switch wins")
eq(wr.enabled_for({ class_enabled = true, weave_range_enabled = true },
    { enabled = true }, true), true, "gate: an enabled profile passes")
eq(wr.enabled_for(nil, nil, true), false, "gate: no class row is off, never a guess")
eq(wr.enabled_for("x", nil, true), false, "gate: a non-table class row is off")

-- fill_fraction ------------------------------------------------------------
near(wr.fill_fraction(5), 1, "fill: at NEAR_YARDS -> 1")
near(wr.fill_fraction(3), 1, "fill: closer than NEAR_YARDS -> 1")
near(wr.fill_fraction(20), 0.4, "fill: 20 yd on the 5-30 band -> 0.4")
near(wr.fill_fraction(12, 5, 35), 0.7666666667, "fill: 12 yd on the hunter 5-35 band")
near(wr.fill_fraction(20, 5, 35), 0.5, "fill: 20 yd on the hunter band -> 0.5")
near(wr.fill_fraction(35, 5, 35), 0, "fill: at the hunter far bound -> 0")
near(wr.fill_fraction(30), 0, "fill: at the shared far bound -> 0")
near(wr.fill_fraction(40), 0, "fill: beyond the far bound -> 0")
eq(wr.fill_fraction(nil), nil, "fill: an unknown distance is nil, NOT zero")
eq(wr.fill_fraction("x"), nil, "fill: a non-number distance is nil")
eq(wr.fill_fraction(20, 30, 5), nil, "fill: a degenerate span (far <= near) is nil")
near(wr.fill_fraction(10, nil, nil), 0.8, "fill: nil near/far use the shared defaults")
near(wr.fill_fraction(10, 0, 40), 0.75, "fill: explicit near/far override")

-- range_state --------------------------------------------------------------
eq(wr.range_state(3), "melee", "state: inside melee -> melee")
eq(wr.range_state(5), "melee", "state: at the melee edge is still melee")
eq(wr.range_state(6), "in_range", "state: just outside melee -> in_range")
eq(wr.range_state(30), "out", "state: at the shared far bound -> out")
eq(wr.range_state(34, 5, 35), "in_range", "state: inside the hunter band -> in_range")
eq(wr.range_state(35, 5, 35), "out", "state: at the hunter far bound -> out")
eq(wr.range_state(nil), nil, "state: unknown distance -> nil")

-- state_label / state_color ------------------------------------------------
eq(wr.state_label("melee"), "MELEE", "word: melee")
eq(wr.state_label("in_range"), "IN RANGE", "word: in range")
eq(wr.state_label("out"), "OUT", "word: out")
eq(wr.state_label(nil), nil, "word: unknown -> nil")
eq(wr.state_color("melee"), wr.MELEE_COLOR, "colour: melee")
eq(wr.state_color("out"), wr.OUT_COLOR, "colour: out")
eq(wr.state_color("in_range"), wr.IN_RANGE_COLOR, "colour: in range")
eq(wr.state_color(nil), wr.IN_RANGE_COLOR, "colour: an unknown state falls back to in-range")

-- format_yards / label -----------------------------------------------------
eq(wr.format_yards(12), "12 yd", "label: whole yards -> 12 yd")
eq(wr.format_yards(12.4), "12 yd", "label: below .5 rounds down")
eq(wr.format_yards(12.5), "13 yd", "label: at .5 rounds up")
eq(wr.format_yards(0), "0 yd", "label: zero -> 0 yd")
eq(wr.format_yards(nil), nil, "label: nil distance -> nil")
eq(wr.format_yards("x"), nil, "label: non-number distance -> nil")
eq(wr.label(12, 5, 35), "12 yd  IN RANGE", "label: yards + the state word")
eq(wr.label(3, 5, 35), "3 yd  MELEE", "label: melee word at 3 yd")
eq(wr.label(40, 5, 35), "40 yd  OUT", "label: out word past the far bound")
eq(wr.label(nil, 5, 35), nil, "label: unknown distance -> nil (the caller hides)")

--=========================================================================================
-- 2. Inert sandbox: no UIParent / CreateFrame
--=========================================================================================
local st3 = {}
local env3 = setmetatable({}, { __index = _G })
local mod3 = assert(loadfile(ROOT .. "weave_range.lua"))
setfenv(mod3, env3)
local ok3, err3 = pcall(function() mod3("SwedgeTimer", st3) end)
check(ok3, "weave_range.lua loads without WoW frame APIs (" .. tostring(err3) .. ")")
local wr3 = st3.weave_range
local ST3 = {
    player_class = "HUNTER",
    get_class_table = function() return { class_enabled = true } end,
    get_profile_table = function() return { enabled = true } end,
}
eq(wr3.init(ST3), false, "init without UIParent/CreateFrame returns false")
eq(wr3.inert, true, "init without WoW frame APIs marks the module inert")
local ok4 = pcall(function() wr3.update(ST3) end)
check(ok4, "update without a frame is a safe no-op")
local ok5 = pcall(function() wr3.poll(ST3) end)
check(ok5, "poll without a frame is a safe no-op")

--=========================================================================================
-- NILSWEEP (2026-10-22 style): every absence shape the pure rule can see. No row, no
-- profile accessor, no class token - all read off, never a throw and never a guess.
--=========================================================================================
do
    eq(wr3.enabled_for(nil, nil, nil), false, "NILSWEEP: no row, no default -> off")
    eq(wr3.enabled_for({ class_enabled = true }, nil, nil), false,
        "NILSWEEP: a nil default reads off (never a guessed class)")
    eq(wr3.class_default_on(nil), false, "NILSWEEP: no addon object reads no default")
    local ok6, err6 = pcall(function() wr3.update({}) end)
    check(ok6, "NILSWEEP: update with no accessors never throws (" .. tostring(err6) .. ")")
    local ok7, err7 = pcall(function() wr3.poll({}) end)
    check(ok7, "NILSWEEP: poll with no accessors never throws (" .. tostring(err7) .. ")")
end

--=========================================================================================
print("")
print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then os.exit(1) end
os.exit(0)

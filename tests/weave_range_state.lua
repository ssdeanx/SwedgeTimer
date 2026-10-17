-- tests/weave_range_state.lua: offline tests for weave_range.lua - the pure proximity
-- maths and the frame driver (fill height, yards label, show/hide gates, driver throttle)
-- - plus the compat.UnitDistance wrapper the exact-distance path depends on.
--
-- Four sandboxes, each loading the real module files:
--   1. WoW-free: asserts weave_range.lua loads with no CreateFrame/UIParent/LibStub at
--      all, then pins the pure helpers.
--   2. Frame stubs: instrumented fake frames record every draw call, so the driver's
--      show/hide gates, the exact-first preference and the fill/label mapping are
--      checked against real code.
--   3. Inert: no UIParent/CreateFrame - init() must stay a safe no-op.
--   4. Compat wrapper: the real compat.lua over a stubbed UnitDistanceSquared, pinning
--      sqrt/normalisation and every nil degrade (absent, unchecked, non-finite, secret,
--      throwing).
-- A static scan also pins the contract that the module adds no range/clock/library reads
-- of its own: it consumes ST.target_min_range / ST.target_max_range plus the single
-- compat UnitDistance call, and never the range library or a clock directly.
--
-- Plain Lua 5.1, no WoW client needed. Run from the repo root:
-- lua5.1 tests/weave_range_state.lua  (any cwd works).

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
-- 0. Static contract: no new range reads, no library, no clock
--=========================================================================================
-- The bar must be fed by main.lua's existing range poll plus the single compat
-- UnitDistance read. These tokens are the call shapes a second range source or a
-- library/clock dependency would use; the module's own comments may name the library and
-- the API in prose, but never call them directly.
local src_file = assert(io.open(ROOT .. "weave_range.lua", "r"))
local src = src_file:read("*a")
src_file:close()
for _, token in ipairs({
    "LibStub(", "GetRange(", "IsSpellInRange(", "CheckInteractDistance(", "GetTime(",
    "C_Timer", "UnitDistanceSquared(",
}) do
    check(src:find(token, 1, true) == nil, "source has no " .. token .. " call")
end
check(src:find("ST.target_min_range", 1, true) ~= nil, "source reads ST.target_min_range")
check(src:find("ST.target_max_range", 1, true) ~= nil, "source reads ST.target_max_range")
check(src:find("st.api.UnitDistance(", 1, true) ~= nil, "source reads st.api.UnitDistance")

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
eq(wr.FAR_YARDS, 30, "FAR_YARDS == 30")
eq(wr.UPDATE_INTERVAL, 0.05, "UPDATE_INTERVAL == 0.05")
eq(wr.BAR_WIDTH, 16, "BAR_WIDTH == 16")
eq(wr.BAR_HEIGHT, 120, "BAR_HEIGHT == 120")

-- is_known ------------------------------------------------------------------
eq(wr.is_known(nil, nil), false, "is_known: nil/nil -> false")
eq(wr.is_known(5, nil), true, "is_known: min only -> true")
eq(wr.is_known(nil, 8), true, "is_known: max only -> true")
eq(wr.is_known(0, 0), true, "is_known: zero band -> true")
eq(wr.is_known("5", nil), false, "is_known: string min -> false")
eq(wr.is_known(nil, true), false, "is_known: boolean max -> false")

-- distance_proxy ------------------------------------------------------------
eq(wr.distance_proxy(5, 8), 8, "proxy: upper bound wins")
eq(wr.distance_proxy(5, nil), 5, "proxy: lower bound when max unknown")
eq(wr.distance_proxy(nil, 8), 8, "proxy: max when min unknown")
eq(wr.distance_proxy(nil, nil), nil, "proxy: unknown -> nil")
eq(wr.distance_proxy("5", nil), nil, "proxy: non-number -> nil")

-- proximity_fraction --------------------------------------------------------
near(wr.proximity_fraction(0, 2), 1, "frac: in melee band -> 1")
near(wr.proximity_fraction(5, 8), 0.88, "frac: 5-8 band -> 0.88")
near(wr.proximity_fraction(2, 10), 0.8, "frac: 2-10 band -> 0.8")
near(wr.proximity_fraction(10, 20), 0.4, "frac: 10-20 band -> 0.4")
near(wr.proximity_fraction(20, 30), 0, "frac: 20-30 band -> 0")
near(wr.proximity_fraction(30, nil), 0, "frac: beyond the far bound -> 0")
near(wr.proximity_fraction(40, nil), 0, "frac: far-only band -> 0")
near(wr.proximity_fraction(nil, 8), 0.88, "frac: max-only band uses max")
near(wr.proximity_fraction(nil, nil), 0, "frac: unknown band -> 0")
near(wr.proximity_fraction("x", "y"), 0, "frac: non-number band -> 0")
near(wr.proximity_fraction(10, 20, nil, nil), 0.4, "frac: nil near/far use the defaults")
near(wr.proximity_fraction(10, 20, 0, 40), 0.5, "frac: explicit near/far override")
near(wr.proximity_fraction(10, 20, 30, 5), 0, "frac: degenerate span (far <= near) -> 0")
near(wr.proximity_fraction(5, 8), wr.proximity_fraction_from_distance(8),
    "frac: band proxy and exact path agree on the same yards (shared clamp)")

-- proximity_fraction_from_distance (the exact path) --------------------------
near(wr.proximity_fraction_from_distance(5), 1, "exact frac: at NEAR_YARDS -> 1")
near(wr.proximity_fraction_from_distance(3), 1, "exact frac: closer than NEAR_YARDS -> 1")
near(wr.proximity_fraction_from_distance(12), 0.72, "exact frac: 12 yd -> 0.72")
near(wr.proximity_fraction_from_distance(17.5), 0.5, "exact frac: midpoint -> 0.5")
near(wr.proximity_fraction_from_distance(30), 0, "exact frac: at FAR_YARDS -> 0")
near(wr.proximity_fraction_from_distance(40), 0, "exact frac: beyond FAR_YARDS -> 0")
near(wr.proximity_fraction_from_distance(12, 0, 40), 0.7, "exact frac: explicit near/far override")
near(wr.proximity_fraction_from_distance(12, 30, 5), 0, "exact frac: degenerate span -> 0")
near(wr.proximity_fraction_from_distance(nil), 0, "exact frac: nil distance -> 0")
near(wr.proximity_fraction_from_distance("x"), 0, "exact frac: non-number distance -> 0")

-- format_yards --------------------------------------------------------------
eq(wr.format_yards(5, 8), "5-8 yd", "label: band -> 5-8 yd")
eq(wr.format_yards(8, 5), "5-8 yd", "label: inverted band is normalised")
eq(wr.format_yards(0, 2), "<2 yd", "label: zero lower bound -> <2 yd")
eq(wr.format_yards(nil, 8), "<8 yd", "label: max only -> <8 yd")
eq(wr.format_yards(40, nil), "40+ yd", "label: min only -> 40+ yd")
eq(wr.format_yards(nil, nil), nil, "label: unknown band -> nil")
eq(wr.format_yards("5", 8), "<8 yd", "label: non-number min is treated as absent")
eq(wr.format_yards(5.9, 8.1), "5-8 yd", "label: values floor to whole yards")

-- format_distance_yards (the exact path) --------------------------------------
eq(wr.format_distance_yards(12), "12 yd", "exact label: whole yards -> 12 yd")
eq(wr.format_distance_yards(12.4), "12 yd", "exact label: below .5 rounds down")
eq(wr.format_distance_yards(12.5), "13 yd", "exact label: at .5 rounds up")
eq(wr.format_distance_yards(0), "0 yd", "exact label: zero -> 0 yd")
eq(wr.format_distance_yards(29.51), "30 yd", "exact label: sub-yard near FAR_YARDS")
eq(wr.format_distance_yards(nil), nil, "exact label: nil distance -> nil")
eq(wr.format_distance_yards("x"), nil, "exact label: non-number distance -> nil")

--=========================================================================================
-- 2. Frame sandbox: instrumented stubs record every driver draw call
--=========================================================================================
local created_frames = {}

local function make_texture()
    local t = { height_sets = 0 }
    function t:SetPoint(...) t.point = { ... } end
    function t:SetAllPoints(target) t.all_points = target end
    function t:SetWidth(w) t.width = w end
    function t:SetHeight(h) t.height = h; t.height_sets = t.height_sets + 1 end
    function t:SetColorTexture(r, g, b, a) t.color = { r, g, b, a } end
    return t
end

local function make_fontstring()
    local fs = { text_sets = 0 }
    function fs:SetPoint(...) fs.point = { ... } end
    function fs:SetJustifyH(justify) fs.justify = justify end
    function fs:SetText(text) fs.text = text; fs.text_sets = fs.text_sets + 1 end
    return fs
end

local function make_frame(kind, name, parent, template)
    local f = {
        kind = kind, name = name, parent = parent, template = template,
        shown = true, show_calls = 0, hide_calls = 0,
        textures = {}, fontstrings = {}, points = {},
    }
    function f:SetSize(w, h) f.width, f.height = w, h end
    function f:SetPoint(...) table.insert(f.points, { ... }) end
    function f:SetFrameStrata(strata) f.strata = strata end
    function f:CreateTexture() local t = make_texture(); table.insert(f.textures, t); return t end
    function f:CreateFontString() local fs = make_fontstring(); table.insert(f.fontstrings, fs); return fs end
    function f:Show() f.shown = true; f.show_calls = f.show_calls + 1 end
    function f:Hide() f.shown = false; f.hide_calls = f.hide_calls + 1 end
    function f:IsShown() return f.shown end
    function f:SetScript(event, fn) f.scripts = f.scripts or {}; f.scripts[event] = fn end
    function f:GetScript(event) return f.scripts and f.scripts[event] end
    created_frames[#created_frames + 1] = f
    return f
end

local target_exists = false
local target_attackable = true
local env2 = setmetatable({}, { __index = _G })
env2.CreateFrame = make_frame
env2.UIParent = make_frame("Frame", "UIParent", nil)
env2.PlayerFrame = make_frame("Frame", "PlayerFrame", nil)
env2.UnitExists = function(unit) return unit == "target" and target_exists or false end
env2.UnitCanAttack = function() return target_attackable end

local st2 = {}
local mod2 = assert(loadfile(ROOT .. "weave_range.lua"))
setfenv(mod2, env2)
local ok2, err2 = pcall(function() mod2("SwedgeTimer", st2) end)
check(ok2, "weave_range.lua loads in the frame sandbox (" .. tostring(err2) .. ")")
local wr2 = st2.weave_range

-- Exact-distance stub: the driver reaches the wrapper through st.api (the real compat
-- surface); nil means "wrapper answered unknown" and must keep the band path identical.
local exact_calls = 0
local exact_unit = nil
local exact_value = nil
st2.api = {
    UnitDistance = function(unit)
        exact_calls = exact_calls + 1
        exact_unit = unit
        return exact_value
    end,
}

local function make_st()
    local ST = {
        target_min_range = nil,
        target_max_range = nil,
        class_db = { class_enabled = true, weave_range_enabled = false },
        profile_db = { enabled = true },
    }
    function ST:get_class_table() return self.class_db end
    function ST:get_profile_table() return self.profile_db end
    return ST
end

local function frame_named(name)
    for _, f in ipairs(created_frames) do
        if f.name == name then return f end
    end
    return nil
end

local ST = make_st()

-- init ---------------------------------------------------------------------
local before = #created_frames
eq(wr2.init(ST), true, "init returns true with a frame environment")
eq(#created_frames - before, 2, "init creates the bar and driver frames")
local bar = frame_named("SwedgeTimerWeaveRangeBar")
local driver = frame_named("SwedgeTimerWeaveRangeDriver")
check(bar ~= nil, "bar frame exists by name")
check(driver ~= nil, "driver frame exists by name")
eq(bar.parent, env2.UIParent, "bar is parented to UIParent")
eq(bar.shown, false, "bar starts hidden")
eq(bar.width, 16, "bar width is BAR_WIDTH")
eq(bar.height, 120, "bar height is BAR_HEIGHT")
eq(bar.strata, "MEDIUM", "bar uses MEDIUM strata")
eq(#bar.textures, 2, "bar has background and fill textures")
eq(#bar.fontstrings, 1, "bar has one label")
eq(bar.fill.height, 1, "fill starts at the 1 px sliver")
eq(driver:GetScript("OnUpdate") ~= nil, true, "driver owns the OnUpdate poll")
eq(wr2.init(ST), true, "second init is a no-op returning true")
eq(#created_frames - before, 2, "second init creates no extra frames")

-- driver throttle + disabled gate ------------------------------------------
local real_update = wr2.update
local update_calls = 0
wr2.update = function(self)
    update_calls = update_calls + 1
    return real_update(self)
end
local on_update = driver:GetScript("OnUpdate")
local height_sets_after_init = bar.fill.height_sets
on_update(driver, 0.05) -- first interval elapses: update runs, toggle is off
eq(update_calls, 1, "driver calls update after one interval")
eq(bar.shown, false, "off by default: the bar stays hidden")
eq(bar.fill.height_sets, height_sets_after_init, "off by default: the fill is never repainted")
on_update(driver, 0.02)
on_update(driver, 0.02)
eq(update_calls, 1, "driver throttles inside UPDATE_INTERVAL")
on_update(driver, 0.02)
eq(update_calls, 2, "driver updates again once the interval elapses")
on_update(driver, 0)
eq(update_calls, 2, "a zero-elapsed tick adds nothing")
on_update(driver, 0.05)
eq(update_calls, 3, "the next full interval updates again")
wr2.update = real_update

-- enabled gates --------------------------------------------------------------
ST.class_db.weave_range_enabled = true
target_exists = true
target_attackable = true

ST.target_min_range, ST.target_max_range = 5, 8
wr2.update(ST)
eq(bar.shown, true, "enabled + attackable target + known band: bar shows")
near(bar.fill.height, 0.88 * 116, "fill height follows the 5-8 band (0.88)")
eq(bar.text.text, "5-8 yd", "label prints the exact band")

-- drains as the target moves away -------------------------------------------
ST.target_min_range, ST.target_max_range = 10, 20
wr2.update(ST)
near(bar.fill.height, 0.4 * 116, "10-20 band drains the fill to 0.4")
ST.target_min_range, ST.target_max_range = 20, 30
wr2.update(ST)
near(bar.fill.height, 1, "20-30 band drains the fill to the 1 px sliver")
eq(bar.text.text, "20-30 yd", "label follows the drained band")
ST.target_min_range, ST.target_max_range = 40, nil
wr2.update(ST)
near(bar.fill.height, 1, "beyond the furthest check: empty fill")
eq(bar.text.text, "40+ yd", "far-only band labels 40+ yd")
ST.target_min_range, ST.target_max_range = 0, 2
wr2.update(ST)
near(bar.fill.height, 116, "in the melee band the fill is full")
eq(bar.text.text, "<2 yd", "melee band labels <2 yd")

-- exact distance (compat UnitDistance) takes precedence over the band ---------
exact_value = 12
ST.target_min_range, ST.target_max_range = 5, 8
wr2.update(ST)
eq(exact_unit, "target", "exact read queries the target unit")
near(bar.fill.height, 0.72 * 116, "exact 12 yd drives the fill, not the 5-8 band")
eq(bar.text.text, "12 yd", "label prints exact yards, not the band")

-- exact present with no band at all: still shows (the band gate is a fallback gate)
ST.target_min_range, ST.target_max_range = nil, nil
wr2.update(ST)
eq(bar.shown, true, "exact distance shows even with no LibRangeCheck band")
near(bar.fill.height, 0.72 * 116, "fill follows exact yards without a band")
eq(bar.text.text, "12 yd", "label follows exact yards without a band")

-- exact clamps at the bar's ends ---------------------------------------------
exact_value = 3
wr2.update(ST)
near(bar.fill.height, 116, "exact 3 yd: full fill")
eq(bar.text.text, "3 yd", "exact label at melee range")
exact_value = 40
wr2.update(ST)
near(bar.fill.height, 1, "exact 40 yd: 1 px sliver")
eq(bar.text.text, "40 yd", "exact label beyond FAR_YARDS")

-- exact unknown: band fallback, byte-identical to before the exact branch ------
exact_value = nil
ST.target_min_range, ST.target_max_range = 5, 8
wr2.update(ST)
near(bar.fill.height, 0.88 * 116, "exact nil: band fill unchanged")
eq(bar.text.text, "5-8 yd", "exact nil: band label unchanged")

-- a non-number exact result is treated as unknown ------------------------------
exact_value = "12"
wr2.update(ST)
near(bar.fill.height, 0.88 * 116, "non-number exact result: band fill")
eq(bar.text.text, "5-8 yd", "non-number exact result: band label")
exact_value = nil

-- st.api absent or without the wrapper: band path, zero behavior change --------
local api_keep = st2.api
st2.api = nil
wr2.update(ST)
near(bar.fill.height, 0.88 * 116, "no st.api: band fill unchanged")
eq(bar.text.text, "5-8 yd", "no st.api: band label unchanged")
st2.api = {}
wr2.update(ST)
near(bar.fill.height, 0.88 * 116, "st.api without UnitDistance: band fill unchanged")
eq(bar.text.text, "5-8 yd", "st.api without UnitDistance: band label unchanged")
st2.api = api_keep

-- hide gates ----------------------------------------------------------------
ST.target_min_range, ST.target_max_range = nil, nil
wr2.update(ST)
eq(bar.shown, false, "unknown band hides the bar")
ST.target_min_range, ST.target_max_range = 5, 8
wr2.update(ST)
eq(bar.shown, true, "known band re-shows the bar")

-- gate order: the exact wrapper is only queried behind the enable/target gates
local calls_before_gates = exact_calls
target_exists = false
wr2.update(ST)
eq(bar.shown, false, "no target hides the bar")
eq(exact_calls, calls_before_gates, "no target: the exact wrapper is not queried")
target_exists = true
target_attackable = false
wr2.update(ST)
eq(bar.shown, false, "non-attackable target hides the bar")
eq(exact_calls, calls_before_gates, "non-attackable: the exact wrapper is not queried")
target_attackable = true

exact_value = 12
ST.class_db.weave_range_enabled = false
wr2.update(ST)
eq(bar.shown, false, "toggle off hides the bar")
eq(exact_calls, calls_before_gates, "toggle off: the exact wrapper is not queried")
ST.class_db.weave_range_enabled = true
exact_value = nil
ST.class_db.class_enabled = false
wr2.update(ST)
eq(bar.shown, false, "class disabled hides the bar")
ST.class_db.class_enabled = true
ST.profile_db.enabled = false
wr2.update(ST)
eq(bar.shown, false, "profile disabled hides the bar")
ST.profile_db.enabled = true
wr2.update(ST)
eq(bar.shown, true, "all gates back on re-shows the bar")

--=========================================================================================
-- 3. Inert sandbox: no UIParent / CreateFrame
--=========================================================================================
local st3 = {}
local env3 = setmetatable({}, { __index = _G })
local mod3 = assert(loadfile(ROOT .. "weave_range.lua"))
setfenv(mod3, env3)
local ok3, err3 = pcall(function() mod3("SwedgeTimer", st3) end)
check(ok3, "weave_range.lua loads without WoW frame APIs (" .. tostring(err3) .. ")")
local wr3 = st3.weave_range
local ST3 = make_st()
eq(wr3.init(ST3), false, "init without UIParent/CreateFrame returns false")
eq(wr3.inert, true, "init without WoW frame APIs marks the module inert")
local ok4 = pcall(function() wr3.update(ST3) end)
check(ok4, "update without a frame is a safe no-op")

--=========================================================================================
-- 4. Compat wrapper: st.api.UnitDistance over a stubbed UnitDistanceSquared
--=========================================================================================
-- The exact path's contract: sqrt of the squared reading, and nil for every shape the
-- driver must treat as unknown (absent global, unchecked, non-number, negative,
-- non-finite, secret, throwing call). A secret value keeps its underlying type, so the
-- sentinel is a number: the is_secret guards have bite only against a value the plain
-- type/range guards would otherwise let through.
local SECRET = 12345
local dist = { squared = nil, checked = nil, unit = nil, throw = false }

local envC = setmetatable({}, { __index = _G })
envC.issecretvalue = function(value) return value == SECRET end
envC.UnitDistanceSquared = function(unit)
    dist.unit = unit
    if dist.throw then error("distance stub threw") end
    return dist.squared, dist.checked
end

local stC = {}
local modC = assert(loadfile(ROOT .. "compat.lua"))
setfenv(modC, envC)
local okC, errC = pcall(function() modC("SwedgeTimer", stC) end)
check(okC, "compat.lua loads in the wrapper sandbox (" .. tostring(errC) .. ")")
local apiC = stC.api
check(type(apiC.UnitDistance) == "function", "compat assigns api.UnitDistance")

dist.squared, dist.checked = 144, true
near(apiC.UnitDistance("target"), 12, "wrapper: sqrt(144) -> 12 yd")
eq(dist.unit, "target", "wrapper: forwards the unit token")
dist.squared, dist.checked = 0, true
eq(apiC.UnitDistance("target"), 0, "wrapper: zero distance stays 0")
dist.squared, dist.checked = 210.25, true
near(apiC.UnitDistance("target"), 14.5, "wrapper: sub-yard precision survives")
dist.squared, dist.checked = 100, false
eq(apiC.UnitDistance("target"), nil, "wrapper: unchecked reading -> nil")
dist.squared, dist.checked = nil, true
eq(apiC.UnitDistance("target"), nil, "wrapper: nil distance -> nil")
dist.squared, dist.checked = -4, true
eq(apiC.UnitDistance("target"), nil, "wrapper: negative squared -> nil")
dist.squared, dist.checked = 0 / 0, true
eq(apiC.UnitDistance("target"), nil, "wrapper: NaN squared -> nil")
dist.squared, dist.checked = 1 / 0, true
eq(apiC.UnitDistance("target"), nil, "wrapper: infinite squared -> nil")
dist.squared, dist.checked = SECRET, true
eq(apiC.UnitDistance("target"), nil, "wrapper: secret distance -> nil")
dist.squared, dist.checked = 144, SECRET
eq(apiC.UnitDistance("target"), nil, "wrapper: secret checked flag -> nil")
dist.squared, dist.checked = nil, nil
dist.throw = true
eq(apiC.UnitDistance("target"), nil, "wrapper: throwing API -> nil")
dist.throw = false

-- absent global: a client without UnitDistanceSquared (standard WotLK) ---------
local envC2 = setmetatable({}, { __index = _G })
local stC2 = {}
local modC2 = assert(loadfile(ROOT .. "compat.lua"))
setfenv(modC2, envC2)
local okC2, errC2 = pcall(function() modC2("SwedgeTimer", stC2) end)
check(okC2, "compat.lua loads without UnitDistanceSquared (" .. tostring(errC2) .. ")")
eq(stC2.api.UnitDistance("target"), nil, "wrapper: absent API -> nil (band fallback)")

--=========================================================================================
print("")
print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then os.exit(1) end
os.exit(0)

-- tests/weave_bar_state.lua: offline tests for the FRAME half of weave_range.lua - the
-- standalone horizontal ranged-distance bar.
--
-- One instrumented frame sandbox (fake CreateFrame/UIParent/UnitExists/UnitCanAttack and
-- a stubbed st.api.UnitDistance) records every draw call, so the driver's creation,
-- anchoring, screen clamp, gate order, paint maths, paint latching and cadence are all
-- checked against the REAL module code.
--
-- The pure maths and the enable rule live in tests/weave_range_state.lua.
--
-- Plain Lua 5.1, no WoW client needed. Run from the repo root:
-- lua5.1 tests/weave_bar_state.lua  (any cwd works; ROOT follows arg[0]).

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
-- Frame sandbox
--=========================================================================================
local created = {}
local function new_region(kind, name, parent)
    local r = {
        kind = kind, name = name, parent = parent,
        shown = true, width = nil, height = nil, top = nil,
        width_sets = 0, height_sets = 0, color_sets = 0, text_sets = 0,
        points = {}, strata = nil,
    }
    function r:SetSize(w, h) self.width, self.height = w, h end
    function r:SetWidth(w) self.width = w; self.width_sets = self.width_sets + 1 end
    function r:SetHeight(h) self.height = h; self.height_sets = self.height_sets + 1 end
    function r:GetWidth() return self.width end
    function r:GetHeight() return self.height end
    function r:GetTop() return self.top end
    function r:SetPoint(...)
        local point, relative, relative_point, x, y = ...
        self.points = { { point = point, relative = relative, relative_point = relative_point,
            x = x, y = y } }
    end
    function r:GetPoint(index)
        local p = self.points[index or 1]
        if not p then return nil end
        return p.point, p.relative, p.relative_point, p.x, p.y
    end
    function r:ClearAllPoints() self.points = {} end
    function r:SetFrameStrata(strata) self.strata = strata end
    function r:EnableMouse() end
    function r:CreateTexture()
        local t = new_region("Texture", nil, self)
        self.textures = self.textures or {}
        self.textures[#self.textures + 1] = t
        return t
    end
    function r:CreateFontString()
        local f = new_region("FontString", nil, self)
        self.fontstrings = self.fontstrings or {}
        self.fontstrings[#self.fontstrings + 1] = f
        return f
    end
    function r:SetAllPoints() end
    function r:SetColorTexture(rr, gg, bb, aa)
        self.color = { rr, gg, bb, aa }
        self.color_sets = self.color_sets + 1
    end
    function r:SetTextColor(rr, gg, bb, aa) self.text_color = { rr, gg, bb, aa } end
    function r:SetJustifyH(justify) self.justify = justify end
    function r:SetText(text)
        self.text = text
        self.text_sets = self.text_sets + 1
    end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:IsShown() return self.shown end
    function r:SetScript(event, fn) self.scripts = self.scripts or {}; self.scripts[event] = fn end
    function r:GetScript(event) return self.scripts and self.scripts[event] end
    -- Only real frames join the census (textures/fontstrings are regions, not frames).
    if kind == "Frame" then
        created[#created + 1] = r
    end
    return r
end

-- Scripted client state ----------------------------------------------------
local target_exists = false
local target_attackable = true
local yards = nil
local dist_calls = 0

local env = setmetatable({}, { __index = _G })
env.UIParent = new_region("Frame", "UIParent", nil)
env.UIParent.top = 768
env.CreateFrame = function(kind, name, parent, template)
    return new_region(kind or "Frame", name, parent)
end
env.UnitExists = function(unit) return unit == "target" and target_exists or false end
env.UnitCanAttack = function(_, unit) return target_attackable end

-- The real module under test.
local st = {}
local mod = assert(loadfile(ROOT .. "weave_range.lua"))
setfenv(mod, env)
local ok, err = pcall(function() mod("SwedgeTimer", st) end)
check(ok, "weave_range.lua loads in the frame sandbox (" .. tostring(err) .. ")")
local wr = st.weave_range

-- The ONE distance source, spied.
local now_clock = 100
st.api = {
    UnitDistance = function(unit)
        dist_calls = dist_calls + 1
        check(unit == "target", "the distance read always asks for the target unit")
        return yards
    end,
    get_time = function() return now_clock end,
}

-- The addon object: the settings accessors, the class token and the per-class default
-- reader (config_presets.lua's ST.weave_range_default_enabled, the SAME reader the
-- options getter falls back to) are all the module reads.
local ST = {
    player_class = "HUNTER",
    class_db = { class_enabled = true, weave_range_enabled = nil },
    profile_db = { enabled = true },
    ranged = nil,
    -- The shipped default table's answer for the bar: ON for a hunter, off elsewhere.
    default_enabled = true,
}
function ST:get_class_table() return self.class_db end
function ST:get_profile_table() return self.profile_db end
-- Dot-style, exactly like config_presets.lua's reader (called as
-- ST.weave_range_default_enabled(ST.player_class): no self argument).
function ST.weave_range_default_enabled(class_token)
    if class_token ~= "HUNTER" then
        return false
    end
    return ST.default_enabled == true
end

local function frame_named(name)
    for _, f in ipairs(created) do
        if f.name == name then return f end
    end
    return nil
end

--=========================================================================================
-- 1. init: two top-level frames, horizontal geometry, hidden
--=========================================================================================
local before = #created
eq(wr.init(ST), true, "init returns true with a frame environment")
eq(#created - before, 2, "init creates the bar and the driver")
local bar = frame_named("SwedgeTimerWeaveRangeBar")
local driver = frame_named("SwedgeTimerWeaveRangeDriver")
check(bar ~= nil, "the bar frame exists by name")
check(driver ~= nil, "the driver frame exists by name")
eq(bar.parent, env.UIParent, "the bar is a TOP-LEVEL frame (parent UIParent, not the ranged bar)")
eq(bar.height, 10, "bar height is BAR_HEIGHT (horizontal)")
eq(bar.width, wr.BAR_WIDTH, "bar width starts at BAR_WIDTH")
eq(bar.shown, false, "the bar starts hidden")
eq(bar.strata, "MEDIUM", "bar strata is MEDIUM")
eq(#bar.textures, 2, "bar has the backdrop and the fill")
-- CreateTexture order: bg first, fill second.
local bg, fill = bar.textures[1], bar.textures[2]
eq(bg.color[4], 0.85, "the backdrop ships near-opaque")
eq(fill.height, 8, "the fill height is the inner height (10 - 2 * padding)")
eq(fill.width, 1, "the fill starts at the 1 px sliver")
eq(fill.points[1].point, "LEFT", "the fill is LEFT-anchored (grows horizontally)")
eq(#bar.fontstrings, 1, "one label")
eq(driver:GetScript("OnUpdate") ~= nil, true, "the driver owns the OnUpdate poll")
eq(wr.init(ST), true, "a second init is a no-op returning true")
eq(#created - before, 2, "a second init creates no frames")

--=========================================================================================
-- 2. Gates: disabled shapes hide and read NOTHING
--=========================================================================================
local function tick()
    wr.poll(ST)
end

-- Disabled: nil on a non-hunter, explicit false, class off, profile off.
ST.player_class = "PALADIN"
yards = 12
target_exists = true
target_attackable = true
dist_calls = 0
tick()
eq(bar.shown, false, "gate: nil on another class is OFF")
eq(dist_calls, 0, "gate: the disabled path never reads the distance")

ST.player_class = "HUNTER"
ST.class_db.weave_range_enabled = false
tick()
eq(bar.shown, false, "gate: explicit false on a hunter is OFF")
eq(dist_calls, 0, "gate: explicit false never reads the distance")

ST.class_db.weave_range_enabled = nil
ST.class_db.class_enabled = false
tick()
eq(bar.shown, false, "gate: the class master switch hides the bar")
eq(dist_calls, 0, "gate: the class master switch never reads the distance")
ST.class_db.class_enabled = true

ST.profile_db.enabled = false
tick()
eq(bar.shown, false, "gate: the profile master switch hides the bar")
eq(dist_calls, 0, "gate: the profile master switch never reads the distance")
ST.profile_db.enabled = true

-- The driver cadence follows the gate: 0.5 s while off, 0.05 s while on.
eq(wr.gate_interval, 0.5, "cadence: the disabled feature polls at DISABLED_INTERVAL")

--=========================================================================================
-- 3. Hunter nil = ON: target + exact yards paint the fill and the label
--=========================================================================================
yards = 20
dist_calls = 0
tick()
eq(bar.shown, true, "hunter nil: the bar shows (nil = ON for hunters)")
eq(dist_calls, 1, "hunter nil: exactly one distance read per update")
eq(wr.gate_interval, 0.05, "cadence: the enabled feature polls at UPDATE_INTERVAL")

-- Layout: no ranged bar -> screen centre fallback.
eq(bar.points[1].point, "CENTER", "layout: no ranged bar centres the bar on UIParent")
eq(bar.points[1].relative, env.UIParent, "layout: the fallback parent is UIParent")
eq(bar.width, wr.BAR_WIDTH, "layout: no ranged bar keeps the default width")
-- 20 yd on the hunter 5-35 band = 0.5; inner width = 200 - 2.
near(fill.width, 0.5 * 198, "paint: 20 yd on the hunter band fills half")
eq(bar.fontstrings[1].text, "20 yd  IN RANGE", "paint: the label is yards + state word")
eq(fill.color[1], wr.IN_RANGE_COLOR[1], "paint: the in-range colour")

-- 3 yd: full fill, MELEE word + green.
yards = 3
tick()
near(fill.width, 198, "paint: inside melee the fill is full")
eq(bar.fontstrings[1].text, "3 yd  MELEE", "paint: the melee word")
eq(fill.color[1], wr.MELEE_COLOR[1], "paint: the melee colour")

-- 40 yd: a 1 px sliver, OUT word + grey (hunter far bound is 35).
yards = 40
tick()
near(fill.width, 1, "paint: past the far bound the fill is the 1 px sliver")
eq(bar.fontstrings[1].text, "40 yd  OUT", "paint: the out word")
eq(fill.color[1], wr.OUT_COLOR[1], "paint: the out colour")

-- The nil answer is DELEGATED to ST.weave_range_default_enabled (config_presets), the
-- same reader the options getter falls back to: a helper that says off turns a hunter's
-- nil OFF. A hardcoded class rule would ignore this flip.
ST.default_enabled = false
dist_calls = 0
tick()
eq(bar.shown, false, "delegation: the shipped default reader says off -> the bar hides")
eq(dist_calls, 0, "delegation: the off answer reads no distance")
ST.default_enabled = true
tick()
eq(bar.shown, true, "delegation: the shipped default reader says on -> the bar shows")

-- An explicit saved value still beats the default reader in both directions.
ST.class_db.weave_range_enabled = true
ST.default_enabled = false
tick()
eq(bar.shown, true, "delegation: explicit saved true beats an off default")
ST.class_db.weave_range_enabled = false
ST.default_enabled = true
tick()
eq(bar.shown, false, "delegation: explicit saved false beats an on default")
ST.class_db.weave_range_enabled = nil
ST.default_enabled = true
tick()
eq(bar.shown, true, "delegation: back to nil + on default shows the bar")

--=========================================================================================
-- 4. Per-class far bound: the same 12 yd fills differently
--=========================================================================================
yards = 12
tick()
local hunter_fill = fill.width
ST.player_class = "PALADIN"
ST.class_db.weave_range_enabled = true -- opt-in for a non-hunter
tick()
local paladin_fill = fill.width
check(hunter_fill > paladin_fill,
    "class band: 12 yd fills higher on the hunter 35 yd band than on the shared 30 yd band")
near(paladin_fill, ((30 - 12) / 25) * 198, "class band: the shared band maths")
ST.player_class = "HUNTER"
ST.class_db.weave_range_enabled = nil

--=========================================================================================
-- 5. Unknown / no-target shapes hide and repaint nothing
--=========================================================================================
yards = nil
local width_sets = fill.width_sets
local text_sets = bar.fontstrings[1].text_sets
tick()
eq(bar.shown, false, "unknown: an answerless distance hides the bar (never a painted 0)")
eq(fill.width_sets, width_sets, "unknown: the fill is not repainted")
eq(bar.fontstrings[1].text_sets, text_sets, "unknown: the label is not repainted")

yards = 12
tick()
eq(bar.shown, true, "unknown: a known reading brings the bar back")

target_exists = false
dist_calls = 0
tick()
eq(bar.shown, false, "no target: the bar hides")
eq(dist_calls, 0, "no target: the distance is never read")

target_exists = true
target_attackable = false
tick()
eq(bar.shown, false, "non-attackable target: the bar hides")
eq(dist_calls, 0, "non-attackable: the distance is never read")
target_attackable = true

--=========================================================================================
-- 6. Paint latching: an unchanged value costs a compare, not a texture call
--=========================================================================================
yards = 12
tick()
local latched_width = fill.width_sets
local latched_text = bar.fontstrings[1].text_sets
local latched_color = fill.color_sets
tick()
eq(fill.width_sets, latched_width, "latch: the same distance issues no SetWidth")
eq(bar.fontstrings[1].text_sets, latched_text, "latch: the same label issues no SetText")
eq(fill.color_sets, latched_color, "latch: the same state issues no SetColorTexture")
yards = 13
tick()
eq(fill.width_sets, latched_width + 1, "latch: a moved target repaints the fill")
eq(bar.fontstrings[1].text_sets, latched_text + 1, "latch: a moved target repaints the label")

--=========================================================================================
-- 7. Layout: above the ranged bar, reserving the hunter stack; width follows the bar
--=========================================================================================
-- A ranged bar frame with a hunter cast bar (15 px) and Rapid Fire bar (4 px) built: the
-- distance bar must clear BOTH (the stack is reserved, never visibility-driven).
local ranged_anchor = new_region("Frame", "RangedAnchor", env.UIParent)
local ranged_bar = new_region("Frame", "RangedBar", ranged_anchor)
ranged_bar.width = 275
ranged_anchor.bar_frame = ranged_bar
ST.ranged = { anchor_frame = ranged_anchor }

local hunter_ui = { cast_frame = new_region("Frame", "HunterCastBar", ranged_bar),
    rapid_fire_bar = new_region("Frame", "HunterRapidFireBar", ranged_bar) }
hunter_ui.cast_frame.height = 15
hunter_ui.rapid_fire_bar.height = 4
st.hunter_ui = hunter_ui

yards = 12
tick()
eq(bar.points[1].point, "BOTTOMLEFT", "anchor: the bar hangs off the ranged bar's top-left")
eq(bar.points[1].relative, ranged_bar, "anchor: the relative frame is the ranged bar")
eq(bar.points[1].y, 2 + (15 + 2) + (4 + 2),
    "anchor: the offset reserves the cast bar and Rapid Fire stack")
eq(bar.width, 275, "anchor: the bar takes the ranged bar's width")
near(fill.width, ((35 - 12) / 30) * 273, "anchor: the fill maths follows the new inner width")

-- A 1 px-wide target can never produce a negative inner width.
ranged_bar.width = 2
tick()
eq(wr.width, 2, "anchor: the layout accepts a tiny bar width")
near(fill.width, 1, "anchor: inner width floors at 1 px (and the fill with it)")

--=========================================================================================
-- 8. Screen clamp: a bar anchored above a top-of-screen ranged bar is shifted down
--=========================================================================================
ranged_bar.width = 275
tick()
bar.top = 800 -- 36 px past the clamped limit (768 - 4)
now_clock = now_clock + 2 -- the clamp re-checks at most once a second
tick()
eq(bar.points[1].y, (2 + 15 + 2 + 4 + 2) - (800 - (768 - 4)),
    "clamp: the bar is shifted down by the overflow past the screen edge")

--=========================================================================================
-- 9. Driver cadence: 0.05 s while enabled, 0.5 s while disabled
--=========================================================================================
local on_update = driver:GetScript("OnUpdate")
local polls = 0
local real_poll = wr.poll
wr.poll = function(addon)
    polls = polls + 1
    return real_poll(addon)
end

wr.gate_interval = wr.UPDATE_INTERVAL
on_update(driver, 0.02)
eq(polls, 0, "cadence: a 0.02 s tick is inside the enabled interval")
on_update(driver, 0.03)
eq(polls, 1, "cadence: 0.05 s of elapsed time runs one poll")
on_update(driver, 0.05)
eq(polls, 2, "cadence: the next 0.05 s runs another")

wr.gate_interval = wr.DISABLED_INTERVAL
on_update(driver, 0.05)
on_update(driver, 0.05)
eq(polls, 2, "cadence: with the disabled interval two 0.05 s ticks run nothing")
on_update(driver, 0.4)
eq(polls, 3, "cadence: 0.5 s of elapsed time runs the disabled-path gate")

wr.poll = real_poll

-- The disabled path costs two settings reads per 0.5 s and no unit API call.
ST.class_db.weave_range_enabled = false
dist_calls = 0
target_exists = true
yards = 12
wr.gate_interval = wr.DISABLED_INTERVAL
wr.poll(ST)
eq(dist_calls, 0, "cost: a disabled poll reads no distance")
ST.class_db.weave_range_enabled = nil

--=========================================================================================
-- 10. Guard: a throwing update is isolated, announced once, then quarantined
--=========================================================================================
do
    local prints = {}
    local saved_print = st.utils
    st.utils = { print_msg = function(msg) prints[#prints + 1] = msg end }
    local saved_update = wr.update
    wr.update = function() error("boom") end
    wr.failures = nil
    local okp = pcall(wr.poll, ST)
    check(okp, "guard: a throwing update never escapes the driver")
    eq(wr.failures, 1, "guard: the first throw is counted")
    eq(#prints, 1, "guard: the first throw is announced once")
    wr.poll(ST)
    wr.poll(ST)
    eq(#prints, 1, "guard: later throws stay quiet")
    eq(wr.failures, 3, "guard: every throw is counted")
    for _ = 1, wr.QUARANTINE_ROWS do
        wr.poll(ST)
    end
    eq(driver:GetScript("OnUpdate"), nil, "guard: quarantine stops the driver")
    eq(bar.shown, false, "guard: quarantine hides the bar")
    wr.update = saved_update
    wr.failures = nil
    st.utils = saved_print
end

--=========================================================================================
print("")
print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then os.exit(1) end
os.exit(0)

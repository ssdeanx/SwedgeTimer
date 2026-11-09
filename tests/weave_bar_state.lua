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
    function r:GetBottom() return self.bottom end
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
-- Native swing-range fallback (tier 2, 2026-11-07): the client's own exact check.
local swing = { melee = nil, ranged = nil }
-- Tier 3: the same spell probes the left hunter range helper uses.
local spell_melee, spell_ranged = nil, nil
st.api = {
    UnitDistance = function(unit)
        dist_calls = dist_calls + 1
        check(unit == "target", "the distance read always asks for the target unit")
        return yards
    end,
    is_target_in_swing_range = function(hand)
        if hand == "mainhand" then
            return swing.melee
        end
        if hand == "ranged" then
            return swing.ranged
        end
        return nil
    end,
    IsSpellInRange = function(spell, unit)
        if unit ~= "target" then
            return nil
        end
        if spell == "Auto Shot" then
            return spell_ranged
        end
        if spell == "Wing Clip" or spell == "Raptor Strike" then
            return spell_melee
        end
        return nil
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
-- 5. Unknown face / no-target: the bar stays visible when the distance is unknown (B-5),
--    hides for a missing or non-attackable target, and never paints a false 0.
--=========================================================================================
yards = nil
tick()
eq(bar.shown, true, "B-5: an unknown distance keeps the bar VISIBLE (explicit unknown face)")
eq(bar.fontstrings[1].text, wr.UNKNOWN_LABEL, "B-5: the unknown face prints the '--' label")
eq(fill.color[1], wr.UNKNOWN_COLOR[1], "B-5: the unknown face uses the neutral dim colour")
eq(fill.color[4], wr.UNKNOWN_COLOR[4], "B-5: the unknown fill is the documented dim alpha")
near(fill.width, 198, "B-5: the unknown face fills the track (never a 0-looking empty bar)")
eq(wr.last_reason, "unknown-distance", "B-5: the diag reason records the unknown distance")
eq(wr.last_distance, nil, "B-5: no invented distance is stored")

-- The face is latched: a second unknown tick costs no texture call.
local unknown_width_sets = fill.width_sets
local unknown_text_sets = bar.fontstrings[1].text_sets
local unknown_color_sets = fill.color_sets
tick()
eq(fill.width_sets, unknown_width_sets, "B-5: the unknown fill is not repainted per tick")
eq(bar.fontstrings[1].text_sets, unknown_text_sets, "B-5: the unknown label is not repainted")
eq(fill.color_sets, unknown_color_sets, "B-5: the unknown colour is not repainted")

yards = 12
tick()
eq(bar.shown, true, "B-5: a known reading takes over from the unknown face")
eq(bar.fontstrings[1].text, "12 yd  IN RANGE", "B-5: the known reading paints the real label")

target_exists = false
dist_calls = 0
tick()
eq(bar.shown, false, "no target: the bar hides")
eq(dist_calls, 0, "no target: the distance is never read")
eq(wr.last_reason, "no-target", "no target: the diag reason is recorded")

target_exists = true
target_attackable = false
tick()
eq(bar.shown, false, "non-attackable target: the bar hides")
eq(dist_calls, 0, "non-attackable: the distance is never read")
eq(wr.last_reason, "not-attackable", "non-attackable: the diag reason is recorded")
target_attackable = true

--=========================================================================================
-- 5b. Native swing-range fallback (2026-11-07): UnitDistanceSquared is group-only and
--     #noinstance, so the client's own C_SwingTimer check paints the exact BAND - never
--     an invented yard count between the two bounds.
--=========================================================================================
yards = nil
swing.melee, swing.ranged = true, true
tick()
eq(bar.shown, true, "band: the bar stays visible")
eq(bar.fontstrings[1].text, "<=5 yd  MELEE", "band: melee paints the exact near band")
near(fill.width, 198, "band: melee fills the track")
eq(fill.color[1], wr.MELEE_COLOR[1], "band: melee colour")
eq(wr.last_reason, "band", "band: the diag reason is band")
eq(wr.last_source, "swing", "band: the diag source is swing")
eq(wr.last_distance, nil, "band: no yard count is invented")

swing.melee, swing.ranged = false, true
tick()
eq(bar.fontstrings[1].text, "5-35 yd  IN RANGE", "band: ranged paints the exact far band")
near(fill.width, wr.BAND_IN_RANGE_FRACTION * 198, "band: in-range marks the band midpoint")
eq(fill.color[1], wr.IN_RANGE_COLOR[1], "band: in-range colour")

swing.melee, swing.ranged = false, false
tick()
eq(bar.fontstrings[1].text, ">35 yd  OUT", "band: beyond ranged paints the out band")
near(fill.width, 1, "band: out is the 1 px sliver")
eq(fill.color[1], wr.OUT_COLOR[1], "band: out colour")

swing.melee, swing.ranged = false, nil
tick()
eq(bar.fontstrings[1].text, ">5 yd  OUT",
    "band: outside melee without a ranged check claims only the near bound")
eq(fill.color[1], wr.OUT_COLOR[1], "band: out_melee uses the out colour")

-- Tier 3: the C_SwingTimer check is silent in the instance; the bottom bar first uses
-- the LEFT indicator's computed helper_state verbatim (the operator-visible working
-- source), then the helper's probe bridge.
yards = nil
swing.melee, swing.ranged = nil, nil
local helper_calls = 0
st.hunter_ui = {
    range_band = function()
        helper_calls = helper_calls + 1
        return "in_range"
    end,
}
tick()
eq(helper_calls, 1, "spell band: the left indicator's computed state is used first")
eq(bar.fontstrings[1].text, "5-35 yd  IN RANGE",
    "spell band: the left indicator's state paints the in-range band")
eq(wr.last_source, "spell", "spell band: the left-indicator source is spell")

local bridge_calls = 0
st.hunter_ui = {
    spell_range_band = function()
        bridge_calls = bridge_calls + 1
        return "in_range"
    end,
}
spell_melee, spell_ranged = false, true
tick()
eq(bridge_calls, 1, "spell band: the left helper's bridge is called")
eq(bar.fontstrings[1].text, "5-35 yd  IN RANGE",
    "spell band: the left helper's bridge paints the in-range band")
eq(wr.last_source, "spell", "spell band: the bridge source is spell")

-- The bridge is absent on an older load: the name/id fallback probes still answer.
st.hunter_ui = { auto_shot_token = "Auto Shot", wing_clip_token = "Wing Clip",
    raptor_token = "Raptor Strike" }
spell_melee, spell_ranged = false, true
tick()
eq(bar.fontstrings[1].text, "5-35 yd  IN RANGE",
    "spell band: the left helper's Auto Shot probe paints the in-range band")
eq(wr.last_reason, "band", "spell band: the diag reason is band")
eq(wr.last_source, "spell", "spell band: the diag source is spell")
near(fill.width, wr.BAND_IN_RANGE_FRACTION * 198, "spell band: the band marker fill")
eq(fill.color[1], wr.IN_RANGE_COLOR[1], "spell band: the in-range colour")

spell_melee, spell_ranged = true, false
tick()
eq(bar.fontstrings[1].text, "<=5 yd  MELEE", "spell band: the melee probe wins")

spell_melee, spell_ranged = false, false
tick()
eq(bar.fontstrings[1].text, ">35 yd  OUT", "spell band: both probes false is out")

spell_melee, spell_ranged = false, nil
tick()
eq(bar.fontstrings[1].text, ">5 yd  OUT",
    "spell band: a nil ranged answer claims only the melee-free band")

st.hunter_ui = nil
spell_melee, spell_ranged = nil, nil

-- Tier 1 wins when it answers: an exact yard count is never replaced by a band.
yards = 20
swing.melee, swing.ranged = true, true
tick()
eq(bar.fontstrings[1].text, "20 yd  IN RANGE", "band: the exact reading wins over the band")
eq(wr.last_source, "exact", "band: the exact source is recorded")

-- Both tiers silent -> the unknown face.
yards = nil
swing.melee, swing.ranged = nil, nil
tick()
eq(bar.fontstrings[1].text, wr.UNKNOWN_LABEL,
    "band: both tiers silent falls back to the unknown face")
eq(wr.last_source, "none", "band: the unknown source is recorded")

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
-- 7. Layout: BELOW the power bar (or the bottom-most visible melee bar when it is
--    hidden); width follows the anchor. This is the 2026-11-09 operator placement.
--=========================================================================================
local power_bar = new_region("Frame", "PowerBar", env.UIParent)
power_bar.width = 275
st.power_bar = { frame = power_bar }

local ranged_anchor = new_region("Frame", "RangedAnchor", env.UIParent)
local ranged_bar = new_region("Frame", "RangedBar", ranged_anchor)
ranged_bar.width = 275
ranged_anchor.bar_frame = ranged_bar
ST.ranged = { anchor_frame = ranged_anchor }

-- The fallback path uses the same public hand/frame surface as bars.lua.
local bottom_bar = new_region("Frame", "BottomMeleeBar", env.UIParent)
bottom_bar.width = 250
bottom_bar.bottom = 120
function ST:iter_hands()
    local done = false
    return function()
        if done then return nil end
        done = true
        return "mainhand"
    end
end
function ST:get_bar_frame(hand)
    if hand == "mainhand" then return bottom_bar end
    return nil
end

yards = 12
tick()
eq(bar.points[1].point, "TOPLEFT", "anchor: the bar hangs below the power bar")
eq(bar.points[1].relative, power_bar, "anchor: the relative frame is the power bar")
eq(bar.points[1].relative_point, "BOTTOMLEFT",
    "anchor: the power bar's bottom edge owns the placement")
eq(bar.points[1].y, -wr.BAR_GAP, "anchor: the gap is the shared BAR_GAP")
eq(bar.width, 275, "anchor: the bar takes the power bar's width")
near(fill.width, ((35 - 12) / 30) * 273, "anchor: the fill maths follows the new inner width")

-- Power bar hidden -> the bottom-most visible melee bar is the anchor.
st.power_bar.frame.shown = false
tick()
eq(bar.points[1].relative, bottom_bar, "anchor: a hidden power bar falls back to the melee bar")
eq(bar.width, 250, "anchor: the fallback width follows the melee bar")
st.power_bar.frame.shown = true

-- A 1 px-wide target can never produce a negative inner width.
power_bar.width = 2
tick()
eq(wr.width, 2, "anchor: the layout accepts a tiny bar width")
near(fill.width, 1, "anchor: inner width floors at 1 px (and the fill with it)")

--=========================================================================================
-- 8. Screen clamp: a bar below a bottom-of-screen power bar is shifted up
--=========================================================================================
power_bar.width = 275
tick()
bar.top = 800 -- 36 px past the top limit (768 - 4)
now_clock = now_clock + 2 -- the clamp re-checks at most once a second
tick()
eq(bar.points[1].y, -wr.BAR_GAP - (800 - (768 - 4)),
    "clamp: the bar is shifted down by the top overflow past the screen edge")

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
-- 10. Guard: a throwing update is isolated, announced once per burst, quarantined after
--     25 CONSECUTIVE throws, and the quarantine RECOVERS (B-6, 2026-11-06)
--=========================================================================================
do
    local prints = {}
    local saved_print = st.utils
    st.utils = { print_msg = function(msg) prints[#prints + 1] = msg end }
    -- Put a real paint on screen first: the quarantine must KEEP it, not blank it.
    ST.class_db.weave_range_enabled = nil
    target_exists = true
    target_attackable = true
    yards = 12
    wr.failures = nil
    wr.quarantined = nil
    wr.quarantine_until = nil
    wr.quarantine_streak = 0
    wr.poll(ST)
    eq(bar.shown, true, "B-6: fixture: the bar is painted before the throw burst")

    local saved_update = wr.update
    wr.update = function() error("boom") end
    local okp = pcall(wr.poll, ST)
    check(okp, "guard: a throwing update never escapes the driver")
    eq(wr.failures, 1, "guard: the first throw is counted")
    eq(#prints, 1, "guard: the first throw is announced once")
    wr.poll(ST)
    wr.poll(ST)
    eq(#prints, 1, "guard: later throws in the same burst stay quiet")
    eq(wr.failures, 3, "guard: every throw is counted")

    -- Consecutive-only: from a fresh burst, 24 throws + success + 24 throws must NOT
    -- quarantine (the counter resets on success; the new pin makes the contract explicit).
    wr.failures = nil
    for _ = 1, wr.QUARANTINE_ROWS - 1 do
        wr.poll(ST)
    end
    eq(wr.quarantined, nil, "B-6: 24 consecutive throws do not quarantine")
    wr.update = saved_update
    wr.poll(ST)
    eq(wr.failures, nil, "B-6: a success resets the consecutive counter")
    wr.update = function() error("boom again") end
    for _ = 1, wr.QUARANTINE_ROWS - 1 do
        wr.poll(ST)
    end
    eq(wr.quarantined, nil, "B-6: a success between bursts means the next 24 are not enough")

    -- The 25th consecutive throw quarantines - but the driver stays ARMED and the last
    -- paint stays on screen (no permanent hide, no dead OnUpdate).
    wr.poll(ST)
    eq(wr.quarantined, true, "B-6: the 25th consecutive throw quarantines the update")
    check(driver:GetScript("OnUpdate") ~= nil,
        "B-6: quarantine keeps the driver armed (recoverable, never permanent)")
    eq(bar.shown, true, "B-6: quarantine keeps the last paint instead of hiding the bar")
    eq(wr.gate_interval, wr.DISABLED_INTERVAL, "B-6: the quarantined driver polls at the slow cadence")
    local prints_after_quarantine = #prints
    check(prints_after_quarantine >= 2, "B-6: the quarantine prints its retry line")

    -- The quarantine window skips the body: no additional throws / prints.
    local failures_at_quarantine = wr.failures
    wr.poll(ST)
    eq(wr.failures, failures_at_quarantine, "B-6: the quarantine window skips the body")
    eq(#prints, prints_after_quarantine, "B-6: the quarantine window prints nothing")

    -- Past the window, the driver retries; a recovered update clears the quarantine and
    -- paints again (proves the bar is not dead for the session).
    wr.update = saved_update
    now_clock = now_clock + wr.RECOVERY_SECONDS + 1
    wr.poll(ST)
    eq(wr.quarantined, false, "B-6: the retry after the quarantine window runs the update")
    eq(wr.failures, nil, "B-6: a recovered update clears the failure count")
    eq(bar.shown, true, "B-6: the recovered bar is painted again")
    eq(wr.quarantine_streak, 0, "B-6: a recovery resets the backoff streak")

    wr.update = saved_update
    wr.failures = nil
    wr.quarantined = nil
    wr.quarantine_until = nil
    wr.quarantine_streak = 0
    st.utils = saved_print
end

--=========================================================================================
-- 11. B-7: the /st diag receipt (weave= token) reports shown/why/distance/state
--=========================================================================================
do
    ST.class_db.weave_range_enabled = nil
    ST.player_class = "HUNTER"
    target_exists = true
    target_attackable = true
    yards = 12
    tick()
    local text = wr.diagnostic_text(ST)
    check(type(text) == "string" and text:find("weave=", 1, true) == 1,
        "B-7: the diag text starts with the weave= token")
    check(text:find("on", 1, true) ~= nil and text:find("yes", 1, true) ~= nil,
        "B-7: the diag text reports enabled + shown")
    check(text:find("shown", 1, true) ~= nil and text:find("12yd", 1, true) ~= nil
        and text:find("in_range", 1, true) ~= nil,
        "B-7: the diag text reports why/distance/state")
    check(text:find("src=exact", 1, true) ~= nil,
        "B-7: the diag text reports the exact source")

    ST.class_db.weave_range_enabled = false
    tick()
    text = wr.diagnostic_text(ST)
    check(text:find("off", 1, true) ~= nil and text:find("settings-off", 1, true) ~= nil,
        "B-7: a disabled bar reports off + its gate reason")
    ST.class_db.weave_range_enabled = nil

    yards = nil
    tick()
    text = wr.diagnostic_text(ST)
    check(text:find("unknown-distance", 1, true) ~= nil and text:find("unknown", 1, true) ~= nil,
        "B-7: the unknown face is attributable from the diag line")
    yards = 12
    tick()
end

--=========================================================================================
print("")
print(string.format("%d checks, %d failures", checks, failures))
if failures > 0 then os.exit(1) end
os.exit(0)

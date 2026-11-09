-- tests/power_bar_state.lua: offline tests for power_bar.lua - the primary-resource
-- bar under the bottom-most visible melee swing bar.
--
-- One instrumented frame sandbox (fake CreateFrame/UIParent and a stubbed st.api)
-- records every draw call, so the module's pure rules, frame creation, anchor choice,
-- layout, power-type colours, text, hide paths, event filter and the restricted
-- (secret) paint path are checked against the REAL module code.
--
-- THE SECRET CONTRACT (WoW Forever / Mainline-code clients): UnitPower and UnitPowerMax
-- are SecretWhenUnitPowerRestricted / SecretWhenUnitPowerMaxRestricted
-- (origin/forever Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua
-- ~2732-2747 / ~2801-2824). A StatusBar accepts those opaque values directly:
-- SetMinMaxValues and SetValue are SecretArguments = "AllowedWhenTainted" with
-- SecretArgumentsAddAspect = { Enum.SecretAspect.BarValue }
-- (SimpleStatusBarAPIDocumentation.lua ~229-236 / ~354-361), which is exactly what
-- Blizzard's own mana bar does (Blizzard_UnitFrame/Mainline/UnitFrame.lua:948-970 on
-- origin/forever). So the bar must hand the RAW readings to the StatusBar, never compare,
-- fraction or format them, and must stay visible while the client hides the number.
--
-- Plain Lua 5.1, no WoW client needed. Run from the repo root:
-- lua5.1 tests/power_bar_state.lua  (any cwd works; ROOT follows arg[0]).

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
    if type(got) ~= "number" or math.abs(got - want) > (tol or 1e-9) then
        failures = failures + 1
        print("FAIL  " .. label .. "  (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
    end
end

--=========================================================================================
-- Frame sandbox
--=========================================================================================
local created = {}
local by_name = {}
local function record_statusbar(region, method, entry)
    entry.method = method
    region.statusbar_log = region.statusbar_log or {}
    local log = region.statusbar_log
    log[#log + 1] = entry
end
local function new_region(kind, name, parent)
    local r = {
        kind = kind, name = name, parent = parent,
        shown = true, width = 200, height = 14, frame_level = 10,
        points = {}, scripts = {}, events = {},
        -- Screen rect: the client answers GetLeft/GetBottom for a laid-out frame, and the
        -- power bar compares that rect (a moved owning bar re-points it).
        left = 0, bottom = 0, setpoint_count = 0,
    }
    function r:SetSize(w, h) self.width, self.height = w, h end
    function r:SetWidth(w) self.width = w end
    function r:SetHeight(h) self.height = h end
    function r:GetWidth() return self.width end
    function r:GetHeight() return self.height end
    function r:GetLeft() return self.left end
    function r:GetBottom() return self.bottom end
    function r:SetPoint(point, relative, relative_point, x, y)
        self.setpoint_count = self.setpoint_count + 1
        self.points = { { point = point, relative = relative, relative_point = relative_point,
            x = x, y = y } }
    end
    function r:GetPoint(index)
        local p = self.points[index or 1]
        if not p then return nil end
        return p.point, p.relative, p.relative_point, p.x, p.y
    end
    function r:ClearAllPoints() self.points = {} end
    function r:Show() self.shown = true end
    function r:Hide() self.shown = false end
    function r:IsShown() return self.shown end
    function r:IsVisible() return self.shown end
    function r:SetFrameStrata(strata) self.strata = strata end
    function r:SetFrameLevel(level) self.frame_level = level end
    function r:GetFrameLevel() return self.frame_level end
    function r:SetScript(event, fn) self.scripts[event] = fn end
    function r:GetScript(event) return self.scripts[event] end
    function r:RegisterEvent(event) self.events[event] = true end
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
    function r:SetColorTexture(rr, gg, bb, aa) self.color = { rr, gg, bb, aa } end
    function r:SetTextColor(rr, gg, bb, aa) self.text_color = { rr, gg, bb, aa } end
    function r:SetJustifyH(justify) self.justify = justify end
    function r:SetText(text) self.text = text; self.text_sets = (self.text_sets or 0) + 1 end
    -- StatusBar surface: the fill is a REAL StatusBar, and one instrumented log proves
    -- what a paint hands it (the restricted case hands the raw secret values through).
    function r:SetStatusBarTexture(asset) self.statusbar_texture = asset end
    function r:SetStatusBarColor(rr, gg, bb, aa)
        self.statusbar_color = { rr, gg, bb, aa }
        record_statusbar(self, "SetStatusBarColor", { r = rr, g = gg, b = bb, a = aa })
    end
    function r:SetMinMaxValues(min_value, max_value)
        self.min_value, self.max_value = min_value, max_value
        record_statusbar(self, "SetMinMaxValues", { min = min_value, max = max_value })
    end
    function r:SetValue(value)
        self.value = value
        record_statusbar(self, "SetValue", { value = value })
    end
    function r:GetValue() return self.value end
    function r:GetMinMaxValues() return self.min_value, self.max_value end
    if kind == "Frame" then
        created[#created + 1] = r
    end
    if name ~= nil then
        by_name[name] = r
    end
    return r
end

local env = setmetatable({}, { __index = _G })
env.UIParent = new_region("Frame", "UIParent", nil)
env.CreateFrame = function(kind, name, parent) return new_region(kind or "Frame", name, parent) end
env.InCombatLockdown = function() return false end

-- The real module under test.
local st = {}
local mod = assert(loadfile(ROOT .. "power_bar.lua"))
setfenv(mod, env)
local ok, err = pcall(function() mod("SwedgeTimer", st) end)
check(ok, "power_bar.lua loads in the frame sandbox (" .. tostring(err) .. ")")
local pb = st.power_bar

local function frame_named(name)
    local found = by_name[name]
    if found ~= nil then return found end
    for _, f in ipairs(created) do
        if f.name == name then return f end
    end
    return nil
end

-- The most recent call of one StatusBar method on a region (nil if never called).
local function statusbar_last(region, method)
    local log = region and region.statusbar_log
    if type(log) ~= "table" then return nil end
    for i = #log, 1, -1 do
        if log[i].method == method then return log[i] end
    end
    return nil
end

-- The width a StatusBar actually paints: (value - min) / (max - min) * track width,
-- clamped the way the widget clamps. This is the pixel contract the old hand-computed
-- texture width had to satisfy (fraction * padded inner width).
-- The StatusBar colour a paint most recently set (an empty table when the fill is not a
-- real StatusBar, so a regression reports FAILs instead of aborting the run).
local function track_colour(region)
    return (region and region.statusbar_color) or {}
end

local function painted_width(region)
    local min_value, max_value = region:GetMinMaxValues()
    local value = region:GetValue()
    if type(min_value) ~= "number" or type(max_value) ~= "number" then return nil end
    if type(value) ~= "number" or max_value <= min_value then return nil end
    local fraction = (value - min_value) / (max_value - min_value)
    if fraction < 0 then fraction = 0 end
    if fraction > 1 then fraction = 1 end
    return fraction * (region:GetWidth() or 0)
end

-- The primary power the stub client answers. Counts every call so the disabled and
-- unknown paths can assert ZERO reads. `restricted=true` models the Mainline-code
-- secret regime: the raw reader hands an opaque value back with the flag set.
local power = { type = 0, token = "MANA", value = 3000, max = 3000, restricted = false }
local reads = { type = 0, raw = 0, legacy = 0, legacy_max = 0 }
st.api = {
    get_time = function() return 100 end,
    UnitPowerType = function(unit)
        reads.type = reads.type + 1
        check(unit == "player", "power type is read for the player")
        return power.type, power.token
    end,
    -- The secret-safe reader compat gains: (value, max_value, restricted) with the raw
    -- client readings, never nil'd.
    GetPlayerPower = function(power_type)
        reads.raw = reads.raw + 1
        check(power_type == power.type, "the raw power read uses the resolved power type")
        return power.value, power.max, power.restricted
    end,
    -- The old nil-on-secret pair stays on st.api for arithmetic consumers; the bar must
    -- NOT use it (a nil would hide the bar, which is the defect this suite pins).
    UnitPower = function(unit, power_type)
        reads.legacy = reads.legacy + 1
        return power.value
    end,
    UnitPowerMax = function(unit, power_type)
        reads.legacy_max = reads.legacy_max + 1
        return power.max
    end,
}
local function read_total()
    return reads.type + reads.raw + reads.legacy + reads.legacy_max
end
local function reset_reads()
    reads = { type = 0, raw = 0, legacy = 0, legacy_max = 0 }
end

-- The addon object: one visible melee bar by default.
local mh_bar = new_region("Frame", "MHBar", env.UIParent)
mh_bar.width, mh_bar.height = 275, 14
mh_bar:Hide()
local oh_bar = new_region("Frame", "OHBar", env.UIParent)
oh_bar.width, oh_bar.height = 275, 14
oh_bar:Hide()
local ST = {
    player_class = "HUNTER",
    class_db = { class_enabled = true, power_bar_enabled = nil, power_bar_height = nil,
        power_bar_text_enabled = nil },
    profile_db = { enabled = true, frame_strata = "MEDIUM" },
    mainhand = { anchor_frame = { bar_frame = mh_bar } },
    offhand = { anchor_frame = { bar_frame = oh_bar } },
}
function ST:get_class_table() return self.class_db end
function ST:get_profile_table() return self.profile_db end
-- Enablement is NOT visibility: a real class enables a hand (built + on + weapon) and
-- the hand's own activity rule decides whether it is on screen. The power bar picks its
-- owning ROW from enablement, so the two are separate here (2026-10-28 contract). The
-- fixture starts as a single melee row (no offhand bar); section 5 enables the offhand
-- row to pin the bottom-slot ownership, and turns it back off for the later sections.
local hand_enabled = { mainhand = true, offhand = false }
function ST:bar_is_enabled(hand)
    return hand_enabled[hand] == true
end

--=========================================================================================
-- 1. Pure helpers
--=========================================================================================
eq(pb.fraction(0, 100), 0, "fraction: empty is 0")
eq(pb.fraction(50, 100), 0.5, "fraction: half is 0.5")
eq(pb.fraction(100, 100), 1, "fraction: full is 1")
eq(pb.fraction(150, 100), 1, "fraction: over max clamps to 1")
eq(pb.fraction(nil, 100), nil, "fraction: nil value is unknown")
eq(pb.fraction(50, 0), nil, "fraction: zero max is unknown")
eq(pb.fraction(50, nil), nil, "fraction: nil max is unknown")
eq(pb.color_for(pb.POWER_MANA), pb.COLOR_MANA, "colour: mana blue")
eq(pb.color_for(pb.POWER_RAGE), pb.COLOR_RAGE, "colour: rage red")
eq(pb.color_for(pb.POWER_ENERGY), pb.COLOR_ENERGY, "colour: energy yellow")
eq(pb.color_for(99), pb.COLOR_OTHER, "colour: unknown is neutral")
eq(pb.format_value(56.6), "57", "format: rounds to a whole number")
eq(pb.format_value(-3), "0", "format: negatives clamp to 0")
eq(pb.format_value(nil), nil, "format: nil is unknown")
eq(pb.height_for(nil), 14, "height: default 14")
eq(pb.height_for({ power_bar_height = 99 }), 30, "height: clamps to 30")
eq(pb.height_for({ power_bar_height = 1 }), 10, "height: clamps to 10")
eq(pb.height_for({ power_bar_height = 20 }), 20, "height: accepts 20")
eq(pb.anchor_choice(false, false), nil, "anchor: no available hand is nil")
eq(pb.anchor_choice(true, false), "mainhand", "anchor: mainhand only")
eq(pb.anchor_choice(true, true), "offhand", "anchor: the offhand row wins when available")
eq(pb.anchor_choice(false, true), "offhand", "anchor: offhand alone")
check(type(pb.fill_dimensions) == "function",
    "the fill-dimensions helper exists (the StatusBar track keeps the old padded geometry)")
if type(pb.fill_dimensions) == "function" then
    local inner_width, inner_height = pb.fill_dimensions(275, 14)
    eq(inner_width, 273, "fill dimensions: the old 1 px inset each side")
    eq(inner_height, 12, "fill dimensions: the old 1 px inset top/bottom")
    inner_width, inner_height = pb.fill_dimensions(nil, nil)
    eq(inner_width, 198, "fill dimensions: a missing width falls back to 200")
    eq(inner_height, 12, "fill dimensions: a missing height falls back to 14")
    inner_width, inner_height = pb.fill_dimensions(2, 2)
    eq(inner_width, 1, "fill dimensions: never a zero/negative track")
    eq(inner_height, 1, "fill dimensions: never a zero/negative track (height)")
end

check(pb.enabled_for(nil, nil) == false, "enable: missing class table is off")
check(pb.enabled_for({ class_enabled = false }, { enabled = true }) == false,
    "enable: class master switch")
check(pb.enabled_for({ class_enabled = true, power_bar_enabled = false }, { enabled = true }) == false,
    "enable: explicit false hides")
check(pb.enabled_for({ class_enabled = true, power_bar_enabled = nil }, { enabled = true }) == true,
    "enable: nil reads ON")
check(pb.enabled_for({ class_enabled = true, power_bar_enabled = true }, { enabled = false }) == false,
    "enable: profile master switch")

--=========================================================================================
-- 2. Init: three frames + a real StatusBar track, default geometry, hidden off-anchor
--=========================================================================================
local before = #created
eq(pb.init(ST), true, "init returns true with a frame environment")
eq(#created - before, 3, "init creates the bar, driver and event frame")
eq(pb.init(ST), true, "init is idempotent")
eq(#created - before, 3, "a second init creates nothing")
local bar = frame_named("SwedgeTimerPowerBar")
local driver = frame_named("SwedgeTimerPowerBarDriver")
local events = frame_named("SwedgeTimerPowerBarEvents")
local fill = bar and bar.fill
check(bar ~= nil and driver ~= nil and events ~= nil, "the three frames exist by name")
check(fill ~= nil and fill.kind == "StatusBar",
    "the fill is a real StatusBar (the only secret-safe paint surface)")
eq(fill and fill.statusbar_texture, pb.STATUS_BAR_TEXTURE,
    "the track uses the flat white StatusBar texture")
eq(bar.shown, false, "no visible melee bar starts hidden")
check(events.events.UNIT_POWER_FREQUENT == true, "the event frame registers power events")
check(events.events.UNIT_DISPLAYPOWER == true, "the event frame registers form changes")
check(events.events.PLAYER_EQUIPMENT_CHANGED == true, "the event frame registers weapon changes")

--=========================================================================================
-- 3. Paint: hunter mana under the mainhand
--=========================================================================================
mh_bar:Show()
reset_reads()
pb.update(ST)
eq(bar.shown, true, "a visible mainhand shows the power bar")
eq(reads.type, 1, "one power-type read")
eq(reads.raw, 1, "one raw power read")
eq(reads.legacy + reads.legacy_max, 0,
    "the bar does not fall back to the nil-on-secret UnitPower pair")
near(bar.width, 275, 1e-9, "width follows the owning melee bar")
near(bar.height, 14, 1e-9, "default height is 14")
near(fill.width, 273, 1e-9, "the StatusBar track keeps the padded width")
near(fill.height, 12, 1e-9, "the StatusBar track keeps the padded height")
local point, relative, relative_point, x, y = bar:GetPoint(1)
eq(point, "TOPLEFT", "the bar anchors at its top-left")
eq(relative, mh_bar, "the bar anchors to the mainhand bar frame")
eq(relative_point, "BOTTOMLEFT", "the bar hangs off the mainhand's bottom")
near(x, 0, 1e-9, "the bar keeps the owning bar's left edge")
near(y, -2, 1e-9, "the bar gap is 2 px")
local min_value, max_value = fill:GetMinMaxValues()
eq(min_value, 0, "the track minimum is 0")
eq(max_value, 3000, "the track max is the power max")
eq(fill:GetValue(), 3000, "the track value is the current power")
near(painted_width(fill), 273, 1e-9, "full mana paints the full padded width")
eq(track_colour(fill)[1], pb.COLOR_MANA[1], "mana uses the blue fill")
eq(track_colour(fill)[2], pb.COLOR_MANA[2], "mana uses the blue fill (green)")
eq(bar.text.text, "3000", "the value text is the current power")
eq(bar.text.shown, true, "the value text is shown")

-- Half mana.
power.value = 1500
pb.update(ST)
near(painted_width(fill), 136.5, 1e-9, "half mana paints half the padded width")
eq(bar.text.text, "1500", "the value text follows the reading")

--=========================================================================================
-- 4. Power types: rage red, energy yellow, focus orange
--=========================================================================================
power.type, power.token, power.value, power.max = pb.POWER_RAGE, "RAGE", 55, 100
pb.update(ST)
eq(track_colour(fill)[1], pb.COLOR_RAGE[1], "rage uses the red fill")
eq(bar.text.text, "55", "rage text is the current rage")
power.type, power.token, power.value, power.max = pb.POWER_ENERGY, "ENERGY", 70, 100
pb.update(ST)
eq(track_colour(fill)[1], pb.COLOR_ENERGY[1], "energy uses the yellow fill")
power.type, power.token, power.value, power.max = pb.POWER_FOCUS, "FOCUS", 100, 100
pb.update(ST)
eq(track_colour(fill)[1], pb.COLOR_FOCUS[1], "focus uses the orange fill")

--=========================================================================================
-- 5. Offhand slot ownership; no melee row on screen hides; displaced hands
--=========================================================================================
-- Operator order 2026-10-28: the slot directly below the bottom-most melee ROW belongs
-- to the power bar, and the offhand row owns it when the class uses an offhand. The
-- offhand hand's own bar is activity-driven and hides while idle, so the power bar must
-- NOT hop up to the mainhand every time that happens (it follows the ROW, not the
-- current visibility).
power.type, power.token, power.value, power.max = pb.POWER_MANA, "MANA", 100, 100
hand_enabled.offhand = true
oh_bar:Show()
pb.update(ST)
local op, orel, orelp = bar:GetPoint(1)
eq(op, "TOPLEFT", "the offhand anchor keeps the top-left point")
eq(orel, oh_bar, "a visible offhand owns the bar (bottom-most)")
eq(orelp, "BOTTOMLEFT", "the offhand anchor uses the offhand bottom-left")
near(bar.width, 275, 1e-9, "the width follows the offhand")
oh_bar:Hide()
pb.update(ST)
local mp, mrel = bar:GetPoint(1)
eq(mp, "TOPLEFT", "the hidden-offhand anchor keeps the top-left point")
eq(mrel, oh_bar, "an idle (hidden) offhand keeps its row: the bar does not hop to the mainhand")
-- A class that does not use an offhand: the mainhand row owns the slot.
hand_enabled.offhand = false
pb.update(ST)
local dp, drel = bar:GetPoint(1)
eq(dp, "TOPLEFT", "the mainhand fallback keeps the top-left point")
eq(drel, mh_bar, "with no offhand row the mainhand owns the bar")
hand_enabled.offhand = true
-- A hand whose bar is disabled is not a row either.
mh_bar:Hide()
hand_enabled.mainhand = false
reset_reads()
pb.update(ST)
eq(bar.shown, false, "no melee row defined hides the power bar")
eq(read_total(), 0, "no anchor performs no power reads")
hand_enabled.mainhand = true
mh_bar:Show()
-- The offhand row visible while the mainhand is hidden still owns the bar.
oh_bar:Show()
pb.update(ST)
local sp, srel = bar:GetPoint(1)
eq(sp, "TOPLEFT", "the offhand-only case keeps the top-left point")
eq(srel, oh_bar, "an offhand row owns the bar even when only it is on screen")
mh_bar:Hide()
reset_reads()
pb.update(ST)
eq(bar.shown, true, "an offhand-only melee group keeps the power bar up")
eq(reads.type, 1, "the offhand anchor reads the power once")
oh_bar:Hide()
mh_bar:Hide()
reset_reads()
pb.update(ST)
eq(bar.shown, false, "no visible melee bar hides the power bar")
eq(read_total(), 0, "hidden anchor performs no power reads")
mh_bar:Show()

--=========================================================================================
-- 5b. The bar follows its owning bar when that bar MOVES (a rect change, not identity)
--=========================================================================================
-- The hunter melee stack and a drag both re-anchor the SAME owning frame, so a
-- frame-identity latch alone would leave the bar behind. A screen-rect change re-points
-- it; an unchanged rect does not (no per-tick re-pointing).
oh_bar:Show()
mh_bar:Show()
pb.update(ST)
local points_before = bar.setpoint_count
pb.update(ST)
eq(bar.setpoint_count, points_before, "a still owning bar does not re-point the power bar")
oh_bar.left, oh_bar.bottom = 40, -120
pb.update(ST)
check(bar.setpoint_count > points_before, "a moved owning bar re-points the power bar")
local moved_p, moved_rel, _, _, moved_y = bar:GetPoint(1)
eq(moved_p, "TOPLEFT", "the moved anchor keeps the top-left point")
eq(moved_rel, oh_bar, "the moved anchor still owns the bar")
near(moved_y, -2, 1e-9, "the moved anchor keeps the 2 px gap")
local settled = bar.setpoint_count
pb.update(ST)
eq(bar.setpoint_count, settled, "a settled anchor stops re-pointing (latched)")
-- A height change moves the owning bar's bottom edge: same detection.
oh_bar.bottom = -160
pb.update(ST)
check(bar.setpoint_count > settled, "a re-anchored owning bar (new bottom edge) re-points the bar")
oh_bar:Hide()
mh_bar:Hide()
hand_enabled.offhand = false
oh_bar.left, oh_bar.bottom = 0, 0

--=========================================================================================
-- 6. Disabled path: zero reads
--=========================================================================================
mh_bar:Show()
ST.class_db.power_bar_enabled = false
reset_reads()
pb.update(ST)
eq(bar.shown, false, "explicit false hides the bar")
eq(read_total(), 0, "disabled performs zero power reads")
ST.class_db.power_bar_enabled = nil
ST.profile_db.enabled = false
reset_reads()
pb.update(ST)
eq(bar.shown, false, "profile off hides the bar")
eq(read_total(), 0, "profile off performs zero power reads")
ST.profile_db.enabled = true

--=========================================================================================
-- 7. Unknown power shapes hide, never paint 0
--=========================================================================================
power.type, power.token, power.value, power.max = nil, nil, 100, 100
pb.update(ST)
eq(bar.shown, false, "a nil power type hides even with numeric power values")
power.type, power.token, power.value, power.max = 0, "MANA", nil, 100
pb.update(ST)
eq(bar.shown, false, "a nil value hides")
power.value, power.max = 100, 0
pb.update(ST)
eq(bar.shown, false, "a zero max hides")
power.value, power.max = 100, 100
power.type = 0
pb.update(ST)
eq(bar.shown, true, "a complete read shows again")
-- The raw reader absent (a client/API shape without it) is still a hard hide, never a
-- throw: compat always defines it, so this is the defensive no-api path.
local reader = st.api.GetPlayerPower
st.api.GetPlayerPower = nil
pb.update(ST)
eq(bar.shown, false, "no raw reader hides (no-api)")
st.api.GetPlayerPower = reader

--=========================================================================================
-- 8. Text toggle, height option and width re-layout
--=========================================================================================
ST.class_db.power_bar_text_enabled = false
pb.update(ST)
eq(bar.text.shown, false, "text off hides the value label")
ST.class_db.power_bar_text_enabled = nil
pb.update(ST)
eq(bar.text.shown, true, "text nil reads on")
ST.class_db.power_bar_height = 20
pb.update(ST)
near(bar.height, 20, 1e-9, "the height option applies")
near(fill.height, 18, 1e-9, "the track height follows the bar height")
ST.class_db.power_bar_height = nil
pb.update(ST)
near(bar.height, 14, 1e-9, "nil height reads 14")
near(fill.height, 12, 1e-9, "the track height returns to the 14 px default minus padding")
mh_bar.width = 300
pb.update(ST)
near(bar.width, 300, 1e-9, "a resized owning bar re-layouts the power bar")
near(fill.width, 298, 1e-9, "the track follows the owning bar width")

--=========================================================================================
-- 9. Event filter: player only
--=========================================================================================
local handler = events.scripts.OnEvent
check(type(handler) == "function", "the event frame has an OnEvent handler")
reset_reads()
handler(events, "UNIT_POWER_FREQUENT", "target")
eq(reads.type, 0, "another unit's power event performs no read")
handler(events, "UNIT_POWER_FREQUENT", "player")
eq(reads.type, 1, "the player's power event repaints")
reset_reads()
handler(events, "UPDATE_SHAPESHIFT_FORM")
eq(reads.type, 1, "a unit-less event (shapeshift) repaints")
reset_reads()
handler(events, "PLAYER_EQUIPMENT_CHANGED", "Player-1", 16)
eq(reads.type, 1, "equipment changes are not filtered as another unit")
reset_reads()
handler(events, "PLAYER_ENTERING_WORLD", false, false)
eq(reads.type, 1, "world entry is not filtered as another unit")

--=========================================================================================
-- 10. refresh
--=========================================================================================
check(pb.refresh(ST) == true, "refresh repaints an existing bar")
near(painted_width(fill), 298, 1e-9, "refresh repaints the fill at the new width")

--=========================================================================================
-- 11. Wiring pin: main.lua's post_init calls the module
--=========================================================================================
local main_file = io.open(ROOT .. "main.lua", "r")
local main_src = main_file and main_file:read("*a") or ""
if main_file then main_file:close() end
check(main_src:find("st.power_bar.init(self)", 1, true) ~= nil,
    "main.lua post_init initialises st.power_bar (the bar is not dead wiring)")

--=========================================================================================
-- 12. Restricted (secret) readings on the Mainline-code clients: raw pass-through
--=========================================================================================
-- On WoW Forever UnitPower/UnitPowerMax are SecretWhenUnitPowerRestricted /
-- SecretWhenUnitPowerMaxRestricted (origin/forever UnitDocumentation.lua ~2732-2747,
-- ~2801-2824). Blizzard's own mana bar passes the RAW UnitPower/UnitPowerMax into
-- SetMinMaxValues/SetValue (Blizzard_UnitFrame/Mainline/UnitFrame.lua:948-970), and those
-- two are SecretArguments = "AllowedWhenTainted" with the BarValue aspect
-- (SimpleStatusBarAPIDocumentation.lua ~229-236 / ~354-361). The bar must therefore hand
-- the values straight to the StatusBar: no nil (that hides the bar), no comparison, no
-- fraction, no formatting.
mh_bar:Show()
mh_bar.width = 275
hand_enabled.offhand = false
local SECRET_VALUE = 777001
local SECRET_MAX = 777002
-- The formatting/fraction helpers are the only places a readable reading is consumed for
-- text or a value; spying on them proves the restricted path never reaches them (a real
-- secret would raise on arithmetic/formatting, a Lua fixture cannot).
local fraction_calls, format_calls = 0, 0
local real_fraction, real_format = pb.fraction, pb.format_value
pb.fraction = function(value, maximum)
    fraction_calls = fraction_calls + 1
    return real_fraction(value, maximum)
end
pb.format_value = function(value)
    format_calls = format_calls + 1
    return real_format(value)
end

power.type, power.token, power.value, power.max, power.restricted =
    pb.POWER_MANA, "MANA", SECRET_VALUE, SECRET_MAX, true
fill.statusbar_log = nil
reset_reads()
local restricted_ok, restricted_err = pcall(pb.update, ST)
check(restricted_ok, "a restricted reading never throws (" .. tostring(restricted_err) .. ")")
eq(bar.shown, true, "a restricted (secret) reading STILL SHOWS the bar")
local minmax_call = statusbar_last(fill, "SetMinMaxValues")
check(minmax_call ~= nil, "the restricted read reaches StatusBar:SetMinMaxValues")
eq(minmax_call and minmax_call.min, 0, "SetMinMaxValues keeps the fixed 0 minimum")
eq(minmax_call and minmax_call.max, SECRET_MAX,
    "SetMinMaxValues receives the RAW secret max, never a computed value")
local value_call = statusbar_last(fill, "SetValue")
check(value_call ~= nil, "the restricted read reaches StatusBar:SetValue")
eq(value_call and value_call.value, SECRET_VALUE,
    "SetValue receives the RAW secret value, never a fraction")
eq(pb.last_state.restricted, true, "last_state carries restricted=true")
eq(pb.last_state.value, SECRET_VALUE, "last_state carries the raw value")
eq(pb.last_state.max_value, SECRET_MAX, "last_state carries the raw max")
eq(pb.last_state.why, nil, "a restricted read is PAINTED (why=nil), not hidden")
-- SEC-11 (2026-11-07): FontString:SetText is AllowedWhenTainted with the Text aspect on
-- Forever, so the RAW number is handed to the widget and the client renders it. The
-- fixture value is a plain number; a real secret would be rendered by the client.
eq(bar.text.text, SECRET_VALUE,
    "the RAW restricted number is handed to FontString:SetText (the client renders it)")
eq(bar.text.shown, true, "the raw value label is shown when the text option is on")
eq(format_calls, 0, "nothing formats a restricted value")
eq(fraction_calls, 0, "nothing computes a fraction from a restricted value")
eq(reads.raw, 1, "one raw power read")
eq(reads.legacy + reads.legacy_max, 0, "the restricted path never touches the nil-on-secret pair")

-- A restricted max that LOOKS unusable (0) must still be painted: comparing a secret is
-- exactly what the client forbids, so no value test may gate the restricted path.
power.value, power.max = SECRET_VALUE, 0
fill.statusbar_log = nil
pcall(pb.update, ST)
eq(bar.shown, true, "a restricted read is shown even when the opaque max would look empty")
eq(pb.last_state.restricted, true, "the opaque-max read is still flagged restricted")
minmax_call = statusbar_last(fill, "SetMinMaxValues")
eq(minmax_call and minmax_call.max, 0, "the raw opaque max still reaches SetMinMaxValues")
eq(format_calls, 0, "the opaque-max case still formats nothing")
eq(fraction_calls, 0, "the opaque-max case still computes no fraction")

-- The text option still governs the restricted label (the constant is not forced on).
ST.class_db.power_bar_text_enabled = false
pcall(pb.update, ST)
eq(bar.text.shown, false, "text off hides the raw value label while restricted")
ST.class_db.power_bar_text_enabled = nil

-- Non-restricted contract: the same StatusBar path keeps the old text and fraction.
power.type, power.token, power.value, power.max, power.restricted =
    pb.POWER_MANA, "MANA", 1500, 3000, false
fraction_calls, format_calls = 0, 0
fill.statusbar_log = nil
pb.update(ST)
eq(pb.last_state.restricted, false, "a readable read is marked not restricted")
near(pb.last_state.fraction, 0.5, 1e-9, "the readable fraction is resolved as before")
eq(bar.text.text, "1500", "the readable value text is unchanged")
eq(bar.text.shown, true, "the readable value text is shown")
minmax_call = statusbar_last(fill, "SetMinMaxValues")
eq(minmax_call and minmax_call.min, 0, "readable min is 0")
eq(minmax_call and minmax_call.max, 3000, "readable max is the power max")
value_call = statusbar_last(fill, "SetValue")
eq(value_call and value_call.value, 1500, "readable value is the power value")
near(painted_width(fill), 136.5, 1e-9, "readable half fills exactly the old padded width")
eq(format_calls, 1, "the readable path still formats the label")
eq(fraction_calls, 1, "the readable path still resolves the fraction")

-- Restore the real helpers so nothing later can observe the spies.
pb.fraction, pb.format_value = real_fraction, real_format

print(string.format("PASS  power_bar_state.lua (%d checks)", checks))
if failures > 0 then
    print(string.format("FAIL  power_bar_state.lua: %d of %d checks failed", failures, checks))
    os.exit(1)
end

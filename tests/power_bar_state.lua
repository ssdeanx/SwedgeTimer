-- tests/power_bar_state.lua: offline tests for power_bar.lua - the primary-resource
-- bar under the bottom-most visible melee swing bar.
--
-- One instrumented frame sandbox (fake CreateFrame/UIParent and a stubbed st.api)
-- records every draw call, so the module's pure rules, frame creation, anchor choice,
-- layout, power-type colours, text, hide paths and event filter are checked against
-- the REAL module code.
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
    if kind == "Frame" then
        created[#created + 1] = r
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
    for _, f in ipairs(created) do
        if f.name == name then return f end
    end
    return nil
end

-- The primary power the stub client answers. Counts every call so the disabled and
-- unknown paths can assert ZERO reads.
local power = { type = 0, token = "MANA", value = 3000, max = 3000 }
local reads = { type = 0, value = 0, max = 0 }
st.api = {
    get_time = function() return 100 end,
    UnitPowerType = function(unit)
        reads.type = reads.type + 1
        check(unit == "player", "power type is read for the player")
        return power.type, power.token
    end,
    UnitPower = function(unit, ptype)
        reads.value = reads.value + 1
        check(unit == "player", "power value is read for the player")
        return power.value
    end,
    UnitPowerMax = function(unit, ptype)
        reads.max = reads.max + 1
        check(unit == "player", "power max is read for the player")
        return power.max
    end,
}

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
-- 2. Init: three frames, default geometry, hidden with no visible melee bar
--=========================================================================================
local before = #created
eq(pb.init(ST), true, "init returns true with a frame environment")
eq(#created - before, 3, "init creates the bar, driver and event frame")
eq(pb.init(ST), true, "init is idempotent")
eq(#created - before, 3, "a second init creates nothing")
local bar = frame_named("SwedgeTimerPowerBar")
local driver = frame_named("SwedgeTimerPowerBarDriver")
local events = frame_named("SwedgeTimerPowerBarEvents")
check(bar ~= nil and driver ~= nil and events ~= nil, "the three frames exist by name")
eq(bar.shown, false, "no visible melee bar starts hidden")
check(events.events.UNIT_POWER_FREQUENT == true, "the event frame registers power events")
check(events.events.UNIT_DISPLAYPOWER == true, "the event frame registers form changes")
check(events.events.PLAYER_EQUIPMENT_CHANGED == true, "the event frame registers weapon changes")

--=========================================================================================
-- 3. Paint: hunter mana under the mainhand
--=========================================================================================
mh_bar:Show()
reads = { type = 0, value = 0, max = 0 }
pb.update(ST)
eq(bar.shown, true, "a visible mainhand shows the power bar")
eq(reads.type, 1, "one power-type read")
eq(reads.value, 1, "one power-value read")
eq(reads.max, 1, "one power-max read")
near(bar.width, 275, 1e-9, "width follows the owning melee bar")
near(bar.height, 14, 1e-9, "default height is 14")
local point, relative, relative_point, x, y = bar:GetPoint(1)
eq(point, "TOPLEFT", "the bar anchors at its top-left")
eq(relative, mh_bar, "the bar anchors to the mainhand bar frame")
eq(relative_point, "BOTTOMLEFT", "the bar hangs off the mainhand's bottom")
near(x, 0, 1e-9, "the bar keeps the owning bar's left edge")
near(y, -2, 1e-9, "the bar gap is 2 px")
near(bar.fill.width, 273, 1e-9, "full mana fills the padded width")
eq(bar.fill.color[1], pb.COLOR_MANA[1], "mana uses the blue fill")
eq(bar.fill.color[2], pb.COLOR_MANA[2], "mana uses the blue fill (green)")
eq(bar.text.text, "3000", "the value text is the current power")
eq(bar.text.shown, true, "the value text is shown")

-- Half mana.
power.value = 1500
pb.update(ST)
near(bar.fill.width, 136.5, 1e-9, "half mana fills half the padded width")
eq(bar.text.text, "1500", "the value text follows the reading")

--=========================================================================================
-- 4. Power types: rage red, energy yellow, focus orange
--=========================================================================================
power.type, power.token, power.value, power.max = pb.POWER_RAGE, "RAGE", 55, 100
pb.update(ST)
eq(bar.fill.color[1], pb.COLOR_RAGE[1], "rage uses the red fill")
eq(bar.text.text, "55", "rage text is the current rage")
power.type, power.token, power.value, power.max = pb.POWER_ENERGY, "ENERGY", 70, 100
pb.update(ST)
eq(bar.fill.color[1], pb.COLOR_ENERGY[1], "energy uses the yellow fill")
power.type, power.token, power.value, power.max = pb.POWER_FOCUS, "FOCUS", 100, 100
pb.update(ST)
eq(bar.fill.color[1], pb.COLOR_FOCUS[1], "focus uses the orange fill")

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
reads = { type = 0, value = 0, max = 0 }
pb.update(ST)
eq(bar.shown, false, "no melee row defined hides the power bar")
eq(reads.type, 0, "no anchor performs no power reads")
hand_enabled.mainhand = true
mh_bar:Show()
-- The offhand row visible while the mainhand is hidden still owns the bar.
oh_bar:Show()
pb.update(ST)
local sp, srel = bar:GetPoint(1)
eq(sp, "TOPLEFT", "the offhand-only case keeps the top-left point")
eq(srel, oh_bar, "an offhand row owns the bar even when only it is on screen")
mh_bar:Hide()
reads = { type = 0, value = 0, max = 0 }
pb.update(ST)
eq(bar.shown, true, "an offhand-only melee group keeps the power bar up")
eq(reads.type, 1, "the offhand anchor reads the power once")
oh_bar:Hide()
mh_bar:Hide()
reads = { type = 0, value = 0, max = 0 }
pb.update(ST)
eq(bar.shown, false, "no visible melee bar hides the power bar")
eq(reads.type, 0, "hidden anchor performs no power reads")
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
reads = { type = 0, value = 0, max = 0 }
pb.update(ST)
eq(bar.shown, false, "explicit false hides the bar")
eq(reads.type + reads.value + reads.max, 0, "disabled performs zero power reads")
ST.class_db.power_bar_enabled = nil
ST.profile_db.enabled = false
reads = { type = 0, value = 0, max = 0 }
pb.update(ST)
eq(bar.shown, false, "profile off hides the bar")
eq(reads.type + reads.value + reads.max, 0, "profile off performs zero power reads")
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
near(bar.fill.height, 18, 1e-9, "the fill height follows the bar height")
ST.class_db.power_bar_height = nil
pb.update(ST)
near(bar.height, 14, 1e-9, "nil height reads 14")
mh_bar.width = 300
pb.update(ST)
near(bar.width, 300, 1e-9, "a resized owning bar re-layouts the power bar")

--=========================================================================================
-- 9. Event filter: player only
--=========================================================================================
local handler = events.scripts.OnEvent
check(type(handler) == "function", "the event frame has an OnEvent handler")
reads = { type = 0, value = 0, max = 0 }
handler(events, "UNIT_POWER_FREQUENT", "target")
eq(reads.type, 0, "another unit's power event performs no read")
handler(events, "UNIT_POWER_FREQUENT", "player")
eq(reads.type, 1, "the player's power event repaints")
reads = { type = 0, value = 0, max = 0 }
handler(events, "UPDATE_SHAPESHIFT_FORM")
eq(reads.type, 1, "a unit-less event (shapeshift) repaints")
reads = { type = 0, value = 0, max = 0 }
handler(events, "PLAYER_EQUIPMENT_CHANGED", "Player-1", 16)
eq(reads.type, 1, "equipment changes are not filtered as another unit")
reads = { type = 0, value = 0, max = 0 }
handler(events, "PLAYER_ENTERING_WORLD", false, false)
eq(reads.type, 1, "world entry is not filtered as another unit")

--=========================================================================================
-- 10. refresh
--=========================================================================================
check(pb.refresh(ST) == true, "refresh repaints an existing bar")
near(bar.fill.width, 298, 1e-9, "refresh repaints the fill at the new width")

--=========================================================================================
-- 11. Wiring pin: main.lua's post_init calls the module
--=========================================================================================
local main_file = io.open(ROOT .. "main.lua", "r")
local main_src = main_file and main_file:read("*a") or ""
if main_file then main_file:close() end
check(main_src:find("st.power_bar.init(self)", 1, true) ~= nil,
    "main.lua post_init initialises st.power_bar (the bar is not dead wiring)")

print(string.format("PASS  power_bar_state.lua (%d checks)", checks))
if failures > 0 then
    print(string.format("FAIL  power_bar_state.lua: %d of %d checks failed", failures, checks))
    os.exit(1)
end

--=========================================================================================
-- Power bar: the player's primary resource, under the bottom-most melee swing bar.
--
-- WHAT IT IS: a thin horizontal bar showing the CURRENT primary power (mana, rage,
-- energy, focus, runic power, ...) with the numeric value centred. Operator request
-- 2026-10-27: "can we implement a power bar, for mana for hunter, also check and make
-- sure warrior have rage bar, rogue energy, etc. That should be underneath the mh/oh
-- bar depending on if its being used" and "power bar should be like 14-15".
--
-- WHY IT IS GENERIC: the type comes from UnitPowerType("player") and the values from
-- st.api.GetPlayerPower (compat.lua). No class switch and no id table, so the same code
-- paints mana for hunter/paladin/shaman, rage for warrior/bear, energy for rogue/cat and
-- focus wherever that is the primary power. Druid forms repaint through
-- UNIT_DISPLAYPOWER / UPDATE_SHAPESHIFT_FORM; nothing caches the type.
--
-- WHY THE FILL IS A REAL StatusBar (WoW Forever / Mainline-code secret fix): on the
-- Mainline clients UnitPower/UnitPowerMax are SecretWhenUnitPowerRestricted /
-- SecretWhenUnitPowerMaxRestricted (origin/forever
-- Blizzard_APIDocumentationGenerated/UnitDocumentation.lua:2732-2747, :2801-2824), so a
-- restricted combat read is an opaque value that raises on comparison/arithmetic. The old
-- fill was a plain texture whose width this module computed with Lua arithmetic, and
-- compat's nil-on-secret wrappers turned the read into nil, so the bar hid (the operator's
-- "being blocked becuz its secret"). A StatusBar may RECEIVE a restricted value:
-- SetMinMaxValues (SimpleStatusBarAPIDocumentation.lua:229-236) and SetValue (:354-361)
-- are SecretArguments = "AllowedWhenTainted" with SecretArgumentsAddAspect =
-- { Enum.SecretAspect.BarValue }, and Blizzard's own mana bar feeds the raw UnitPower /
-- UnitPowerMax straight into them without arithmetic
-- (Blizzard_UnitFrame/Mainline/UnitFrame.lua:948-970, origin/forever). So the fill is
-- CreateFrame("StatusBar", ...) and the raw pair goes to SetMinMaxValues/SetValue; while
-- the read is restricted nothing compares, divides or formats it - the value text passes
-- the same raw number straight to FontString:SetText (AllowedWhenTainted, Text aspect:
-- Blizzard's own unit frames do statusText:SetText(UnitHealth(unit))), or hides with the
-- text option, and the bar is still painted. On classic clients there are no secret
-- values, so the same path is a plain render.
--
-- PLACEMENT: in the slot directly below the bottom-most melee bar ROW - the offhand row
-- when the class uses an offhand, else the mainhand row (operator order 2026-10-28:
-- "ranged bar shouldnt be below mh/oh bar because thats where power bar should be for
-- each class"). The owning ROW is picked from the hand being enabled, not from whether it
-- is on screen at this instant: the offhand bar itself is activity-driven and hides while
-- idle, and the power bar must not hop up and down between the hands every time it does.
-- With no melee bar on screen the power bar hides. Width equals the owning bar's width;
-- height defaults to 14 px (operator range 10-30). Anchored to the bar frame itself, so
-- it follows the hunter melee stack (which pins MH/OH under the ranged bar) and any drag
-- (a rect change re-points it; frame identity alone is not the trigger).
-- If no melee bar is visible, or the power read is unknown (no API/type/value), the bar
-- hides instead of painting a guess. A restricted read is NOT unknown: it is painted.
--
-- DEFAULT: ON. The operator request is the explicit gate for a default-visible
-- change; an explicit false hides it (class table key power_bar_enabled), and the
-- profile/class master switches also gate it.
--
-- EVENTS: UNIT_POWER_FREQUENT / UNIT_POWER_UPDATE / UNIT_DISPLAYPOWER /
-- UPDATE_SHAPESHIFT_FORM / PLAYER_ENTERING_WORLD / PLAYER_EQUIPMENT_CHANGED. The
-- 0.25 s driver is the layout/failsafe paint (it also catches a melee bar being
-- shown/hidden between power events). Every read goes through st.api (compat.lua):
-- GetPlayerPower returns the raw values + the restricted flag, and only a genuinely
-- unknown read degrades to nil (then the bar hides).
--
-- CROSS-CLIENT: UnitPower / UnitPowerMax / UnitPowerType are documented on
-- classic_era, classic_anniversary, classic_titan, origin/forever and live (see
-- compat.lua's wrappers); the six events are documented on all five branches. No
-- protected call, no taint risk: the frame is insecure and only SetPoint/SetSize/
-- SetHeight/SetFrameLevel on the container plus the StatusBar widget methods
-- (SetStatusBarTexture/SetMinMaxValues/SetValue/SetStatusBarColor) are used.
--
-- DIAGNOSTICS: every refresh resolves through pb.resolve (read-only) and stores the
-- result in pb.last_state - why the bar hides this tick (or nil when painted), the
-- owning hand, the power reading, the fraction (readable reads only) and the restricted
-- flag. The verbose /st diag power line reads that receipt instead of re-deriving the
-- decision, so the report and the bar cannot disagree. Nothing on that path writes a
-- frame or a profile key.
--=========================================================================================
local addon_name, st = ...

st.power_bar = st.power_bar or {}
local pb = st.power_bar

pb.DEFAULT_HEIGHT = 14
pb.MIN_HEIGHT = 10
pb.MAX_HEIGHT = 30
pb.GAP = 2
pb.BAR_PADDING = 1
pb.PAINT_INTERVAL = 0.25
pb.QUARANTINE_ROWS = 25

-- The flat white texture the StatusBar track tints with the power colour (the old fill
-- was a flat-coloured texture). LibSharedMedia lists it as the "Solid" statusbar texture
-- on every client family, so it is the client-canonical flat asset.
pb.STATUS_BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8"

-- PowerType constants (Enum.PowerType values; the raw numbers are the stable API,
-- Enum is not present on every classic client).
pb.POWER_MANA = 0
pb.POWER_RAGE = 1
pb.POWER_FOCUS = 2
pb.POWER_ENERGY = 3
pb.POWER_RUNIC_POWER = 6

-- 0-1 texture colours. Mana blue, rage red, energy yellow, focus orange; the rest
-- get the neutral grey (never a class guess).
pb.COLOR_MANA = { 0.10, 0.40, 1.00, 0.90 }
pb.COLOR_RAGE = { 0.90, 0.10, 0.10, 0.90 }
pb.COLOR_FOCUS = { 1.00, 0.50, 0.20, 0.90 }
pb.COLOR_ENERGY = { 1.00, 0.85, 0.10, 0.90 }
pb.COLOR_RUNIC = { 0.20, 0.80, 1.00, 0.90 }
pb.COLOR_OTHER = { 0.60, 0.60, 0.60, 0.90 }
pb.BG_COLOR = { 0.0, 0.0, 0.0, 1.0 }
pb.TEXT_COLOR = { 1.0, 1.0, 1.0, 1.0 }

--=========================================================================================
-- Pure helpers (WoW-free; unit-tested by tests/power_bar_state.lua)
--=========================================================================================

-- Fill fraction in [0, 1], or nil when either value is not a usable number or the
-- maximum is not positive (unknown is not "empty").
function pb.fraction(value, max_value)
    local current = tonumber(value)
    local maximum = tonumber(max_value)
    if current == nil or maximum == nil or maximum <= 0 then
        return nil
    end
    if current <= 0 then
        return 0
    end
    if current >= maximum then
        return 1
    end
    return current / maximum
end

function pb.color_for(power_type)
    if power_type == pb.POWER_MANA then return pb.COLOR_MANA end
    if power_type == pb.POWER_RAGE then return pb.COLOR_RAGE end
    if power_type == pb.POWER_FOCUS then return pb.COLOR_FOCUS end
    if power_type == pb.POWER_ENERGY then return pb.COLOR_ENERGY end
    if power_type == pb.POWER_RUNIC_POWER then return pb.COLOR_RUNIC end
    return pb.COLOR_OTHER
end

-- Whole-number label: power is reported as an integer, but a float reading is
-- rounded rather than truncated (the same rule the swing bar texts use).
function pb.format_value(value)
    local number = tonumber(value)
    if number == nil then
        return nil
    end
    if number < 0 then
        number = 0
    end
    return tostring(math.floor(number + 0.5))
end

-- Nil-safe enable rule: only an explicit false turns the bar off; the profile and
-- class master switches also gate it. A sandbox without either table is off.
function pb.enabled_for(class_db, profile_db)
    if type(class_db) ~= "table" then
        return false
    end
    if class_db.class_enabled == false then
        return false
    end
    if profile_db ~= nil and profile_db.enabled == false then
        return false
    end
    return class_db.power_bar_enabled ~= false
end

-- Which melee bar row owns the bar: the offhand when the class uses one (the bottom-most
-- row), else the mainhand. nil when neither is available - the caller hides.
function pb.anchor_choice(mainhand_available, offhand_available)
    if offhand_available == true then
        return "offhand"
    end
    if mainhand_available == true then
        return "mainhand"
    end
    return nil
end

-- Clamp the configured height into the shipped range; a nil/garbage value reads the
-- 14 px default.
function pb.height_for(class_db)
    local height = class_db and tonumber(class_db.power_bar_height)
    if height == nil then
        height = pb.DEFAULT_HEIGHT
    end
    if height < pb.MIN_HEIGHT then
        height = pb.MIN_HEIGHT
    elseif height > pb.MAX_HEIGHT then
        height = pb.MAX_HEIGHT
    end
    return height
end

-- Size of the StatusBar track inside the bar frame: the old hand-painted fill's 1 px
-- inset on every side, clamped so a tiny configured height still yields a paintable
-- track. Keeping the inset means the fraction the StatusBar paints is
-- fraction * (width - 2 * BAR_PADDING) - exactly the pixel width the old SetWidth path
-- computed - so the visible geometry does not change with the secret-safe widget.
function pb.fill_dimensions(width, height)
    local track_width = tonumber(width) or 200
    local track_height = tonumber(height) or pb.DEFAULT_HEIGHT
    track_width = track_width - (pb.BAR_PADDING * 2)
    track_height = track_height - (pb.BAR_PADDING * 2)
    if track_width < 1 then
        track_width = 1
    end
    if track_height < 1 then
        track_height = 1
    end
    return track_width, track_height
end

--=========================================================================================
-- Frame driver
--=========================================================================================

local function frame_visible(frame)
    if frame == nil then
        return false
    end
    if type(frame.IsVisible) == "function" then
        return frame:IsVisible() == true
    end
    if type(frame.IsShown) == "function" then
        return frame:IsShown() == true
    end
    return false
end

-- The hand's bar frame when the hand is ENABLED (built, bar on, weapon present); nil
-- otherwise. Visibility is deliberately not part of this test: the offhand's row owns
-- the bottom slot for as long as the class can use an offhand, so an idle (hidden)
-- offhand keeps the power bar where the offhand appears instead of letting the bar hop
-- between the hands every time the offhand idles out.
local function usable_hand_frame(ST, hand)
    local state = ST and ST[hand]
    local anchor = state and state.anchor_frame
    local frame = anchor and anchor.bar_frame
    if frame == nil then
        return nil
    end
    if ST ~= nil and type(ST.bar_is_enabled) == "function" and ST:bar_is_enabled(hand) ~= true then
        return nil
    end
    return frame
end

-- The hand's bar frame when the hand is enabled AND on screen; nil otherwise.
local function visible_hand_frame(ST, hand)
    local frame = usable_hand_frame(ST, hand)
    if not frame_visible(frame) then
        return nil
    end
    return frame
end

local function choose_anchor(ST)
    local mainhand_visible = visible_hand_frame(ST, "mainhand")
    local offhand_visible = visible_hand_frame(ST, "offhand")
    -- The bar hangs off the melee group: with no melee bar on screen it has nothing to
    -- belong to and hides (the same rule as before).
    if mainhand_visible == nil and offhand_visible == nil then
        return nil, nil
    end
    -- The slot directly below the bottom-most melee bar ROW belongs to the power bar
    -- (operator order 2026-10-28: "ranged bar shouldnt be below mh/oh bar because thats
    -- where power bar should be"). The offhand row owns it when the class uses an
    -- offhand (whether or not that hand is on screen at this instant), else the
    -- mainhand row.
    local mainhand_row = usable_hand_frame(ST, "mainhand")
    local offhand_row = usable_hand_frame(ST, "offhand")
    local choice = pb.anchor_choice(mainhand_row ~= nil, offhand_row ~= nil)
    if choice == "offhand" then
        return offhand_row, "offhand"
    end
    if choice == "mainhand" then
        return mainhand_row, "mainhand"
    end
    -- No row is enabled (an unbuilt/disabled melee pair while one is still on screen):
    -- fall back to a visible frame, and name the hand it belongs to.
    if mainhand_visible ~= nil then
        return mainhand_visible, "mainhand"
    end
    return offhand_visible, "offhand"
end

local function hide()
    local frame = pb.frame
    if frame ~= nil and frame:IsShown() then
        frame:Hide()
    end
    pb.last_anchor = nil
    pb.last_left = nil
    pb.last_bottom = nil
    pb.last_width = nil
    pb.last_height = nil
    pb.last_fill_width = nil
    pb.last_fill_height = nil
    pb.last_value = nil
    pb.last_max_value = nil
    pb.last_text = nil
    pb.last_color = nil
end

-- Screen coordinates rounded to 1/10 px: float noise must not re-point the bar on every
-- tick, while a real drag / re-anchor (the layout policies move the melee bars) still
-- does. nil when the client cannot answer (a sandbox without GetLeft/GetBottom).
local function round_tenth(value)
    if type(value) ~= "number" then
        return nil
    end
    return math.floor(value * 10 + 0.5) / 10
end

local function anchor_rect(anchor)
    local left = round_tenth(type(anchor.GetLeft) == "function" and anchor:GetLeft() or nil)
    local bottom = round_tenth(type(anchor.GetBottom) == "function" and anchor:GetBottom() or nil)
    return left, bottom
end

-- Layout only when an input changed: width follows the owning melee bar, height the
-- option, and the point is the bar's bottom-left. Frame identity alone is not enough:
-- the same owning bar is moved by the hunter melee stack and by a drag, so the bar's
-- rect is compared too. Strata/level are changed out of combat (a non-secure frame, but
-- the profile pass owns those fields).
local function layout(ST, anchor, now)
    local frame = pb.frame
    local class_db = type(ST.get_class_table) == "function" and ST:get_class_table() or nil
    local profile_db = type(ST.get_profile_table) == "function" and ST:get_profile_table() or nil
    local width = type(anchor.GetWidth) == "function" and anchor:GetWidth() or nil
    if type(width) ~= "number" or width <= 0 then
        width = 200
    end
    local height = pb.height_for(class_db)
    if pb.last_width ~= width then
        pb.last_width = width
        frame:SetWidth(width)
    end
    if pb.last_height ~= height then
        pb.last_height = height
        frame:SetHeight(height)
    end
    -- The StatusBar track keeps the old fill's 1 px inset, so the widget paints exactly
    -- the pixel width the previous SetWidth path computed. Resizing the track does not
    -- touch the value: the bar repaints itself.
    local fill_width, fill_height = pb.fill_dimensions(width, height)
    if pb.last_fill_width ~= fill_width or pb.last_fill_height ~= fill_height then
        pb.last_fill_width, pb.last_fill_height = fill_width, fill_height
        if frame.fill and type(frame.fill.SetSize) == "function" then
            frame.fill:SetSize(fill_width, fill_height)
        end
    end
    local left, bottom = anchor_rect(anchor)
    local moved = pb.last_anchor ~= anchor
        or (left ~= nil and pb.last_left ~= nil and pb.last_left ~= left)
        or (bottom ~= nil and pb.last_bottom ~= nil and pb.last_bottom ~= bottom)
    if moved then
        pb.last_anchor = anchor
        pb.last_left = left
        pb.last_bottom = bottom
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -pb.GAP)
    end
    local in_combat = type(InCombatLockdown) == "function" and InCombatLockdown()
    if not in_combat then
        local strata = profile_db and profile_db.frame_strata or "MEDIUM"
        if type(strata) == "string" and (pb.last_strata ~= strata)
            and type(frame.SetFrameStrata) == "function" then
            pb.last_strata = strata
            frame:SetFrameStrata(strata)
        end
        local level = type(anchor.GetFrameLevel) == "function"
            and (anchor:GetFrameLevel() or 0) + 1 or nil
        if type(level) == "number" and pb.last_level ~= level
            and type(frame.SetFrameLevel) == "function" then
            pb.last_level = level
            frame:SetFrameLevel(level)
        end
    end
end

-- Paint one resolved state (pb.resolve) through the StatusBar track. A readable state is
-- handed to the widget as value/max (it clamps exactly like pb.fraction did); a
-- RESTRICTED state hands the raw secret reading straight through and never compares,
-- divides or formats it - that is what the sanctioned sinks accept (SetMinMaxValues/
-- SetValue: AllowedWhenTainted, BarValue aspect; SetText: AllowedWhenTainted, Text
-- aspect). The colour is a constant palette entry keyed by the (non-secret) power type.
local function paint(state)
    local frame = pb.frame
    if frame == nil then
        return false
    end
    local color = pb.color_for(state.power_type)
    if pb.last_color ~= color then
        pb.last_color = color
        frame.fill:SetStatusBarColor(color[1], color[2], color[3], color[4])
    end
    if state.restricted then
        -- Raw pass-through. Both calls are repeated every restricted tick on purpose: the
        -- values are opaque, so there is nothing safe to compare them with.
        frame.fill:SetMinMaxValues(0, state.max_value)
        frame.fill:SetValue(state.value)
        pb.last_value, pb.last_max_value = nil, nil
    else
        if pb.last_max_value ~= state.max_value then
            frame.fill:SetMinMaxValues(0, state.max_value)
        end
        if pb.last_value ~= state.value then
            frame.fill:SetValue(state.value)
        end
        pb.last_value, pb.last_max_value = state.value, state.max_value
    end
    local text_on = state.class_db == nil or state.class_db.power_bar_text_enabled ~= false
    if state.restricted then
        -- SEC-11 (2026-11-07, operator in-client): pass the RAW restricted reading to
        -- the font string. FontString:SetText is `SecretArguments = AllowedWhenTainted`
        -- with the Text aspect on WoW Forever (wow-ui-source origin/forever,
        -- SimpleFontStringAPIDocumentation.lua, Name = "SetText"), and Blizzard's own
        -- unit frames hand it a raw number
        -- (CompactUnitFrame_UpdateStatusText: statusText:SetText(UnitHealth(unit))).
        -- The client renders the number; this code never reads, formats, compares or
        -- divides it. There is deliberately no latch: a secret cannot be compared, so
        -- the write repeats every restricted tick (the same shape as the StatusBar
        -- pass-through above).
        if text_on then
            frame.text:SetText(state.value)
            if not frame.text:IsShown() then
                frame.text:Show()
            end
        elseif frame.text:IsShown() then
            frame.text:Hide()
        end
        pb.last_text = nil
    else
        local label = text_on and pb.format_value(state.value) or nil
        if label ~= nil then
            if pb.last_text ~= label then
                pb.last_text = label
                frame.text:SetText(label)
            end
            if not frame.text:IsShown() then
                frame.text:Show()
            end
        else
            pb.last_text = nil
            if frame.text:IsShown() then
                frame.text:Hide()
            end
        end
    end
    if not frame:IsShown() then
        frame:Show()
    end
    return true
end

-- Resolve what one refresh would render from. READ-ONLY: it reads frames and the power
-- API but never shows, hides or creates a frame and never writes a profile key. pb.update
-- renders from this result and stores it in pb.last_state, so the verbose /st diag power
-- line (diag.lua) reports the SAME decision the driver just made instead of re-deriving
-- it. `why` is the reason this tick hides the bar; nil means "painted".
--   no-frame / no-addon / off / no-anchor / no-api / no-type / no-value / no-fraction
-- A restricted (secret) reading is a PAINTED state: restricted=true, the raw values, and
-- why=nil. It is never compared, divided or formatted - only handed to the StatusBar and
-- the font string, whose bindings do the rendering.
function pb.resolve(ST)
    local state = { why = nil }
    if pb.frame == nil then
        state.why = "no-frame"
        return state
    end
    if type(ST) ~= "table" then
        state.why = "no-addon"
        return state
    end
    local class_db = type(ST.get_class_table) == "function" and ST:get_class_table() or nil
    local profile_db = type(ST.get_profile_table) == "function" and ST:get_profile_table() or nil
    state.class_db = class_db
    if not pb.enabled_for(class_db, profile_db) then
        state.why = "off"
        return state
    end
    local anchor, anchor_hand = choose_anchor(ST)
    if anchor == nil then
        state.why = "no-anchor"
        return state
    end
    state.anchor = anchor
    state.anchor_hand = anchor_hand
    local api = st.api
    if type(api) ~= "table" or type(api.UnitPowerType) ~= "function"
        or type(api.GetPlayerPower) ~= "function" then
        state.why = "no-api"
        return state
    end
    local power_type = api.UnitPowerType("player")
    if type(power_type) ~= "number" then
        state.why = "no-type"
        return state
    end
    state.power_type = power_type
    local value, max_value, restricted = api.GetPlayerPower(power_type)
    -- The restricted branch may only use type(): type() is safe on a secret and rejects an
    -- unreadable shape, while a comparison, arithmetic or format would raise on the real
    -- client. Anything else about the two values is left to the StatusBar.
    if restricted == true then
        if type(value) ~= "number" or type(max_value) ~= "number" then
            state.why = "no-value"
            return state
        end
        state.restricted = true
        state.value = value
        state.max_value = max_value
        return state
    end
    state.restricted = false
    if type(value) ~= "number" or type(max_value) ~= "number" or max_value <= 0 then
        state.why = "no-value"
        return state
    end
    state.value = value
    state.max_value = max_value
    local fraction = pb.fraction(value, max_value)
    if fraction == nil then
        state.why = "no-fraction"
        return state
    end
    state.fraction = fraction
    return state
end

-- One refresh: gate settings, pick the owning bar, read the primary power through
-- compat, then lay out and paint. Every genuinely unknown path hides; a restricted read
-- is painted.
function pb.update(ST, now)
    if pb.frame == nil then
        return
    end
    local state = pb.resolve(ST)
    -- The diag receipt: the last resolution (read-only for diag.lua, written only here).
    pb.last_state = state
    if state.why ~= nil then
        hide()
        return
    end
    layout(ST, state.anchor, now)
    if not paint(state) then
        hide()
        return
    end
end

-- Options call this after an appearance change so the fill/height repaint now
-- rather than at the next driver tick.
function pb.refresh(ST)
    if pb.frame == nil then
        return false
    end
    pb.last_value = nil
    pb.last_max_value = nil
    pb.last_height = nil
    pb.update(ST)
    return true
end

-- Guarded driver entry (H3 discipline): one throwing tick must not break OnUpdate.
function pb.poll(ST)
    local now = st.api and type(st.api.get_time) == "function" and st.api.get_time() or nil
    local ok, err = pcall(pb.update, ST, now)
    if ok then
        pb.failures = nil
        return
    end
    local failures = (pb.failures or 0) + 1
    pb.failures = failures
    pb.last_error = tostring(err)
    if failures == 1 and st.utils and type(st.utils.print_msg) == "function" then
        st.utils.print_msg("Power bar update failed and was isolated: " .. tostring(err))
    end
    if failures >= pb.QUARANTINE_ROWS then
        if pb.driver and type(pb.driver.SetScript) == "function" then
            pb.driver:SetScript("OnUpdate", nil)
        end
        hide()
    end
end

local POWER_EVENTS = {
    "UNIT_POWER_FREQUENT",
    "UNIT_POWER_UPDATE",
    "UNIT_DISPLAYPOWER",
    "UPDATE_SHAPESHIFT_FORM",
    "PLAYER_ENTERING_WORLD",
    "PLAYER_EQUIPMENT_CHANGED",
}

local function register_events(frame, ST)
    for i = 1, #POWER_EVENTS do
        local event = POWER_EVENTS[i]
        local valid = true
        if type(C_EventUtils) == "table" and type(C_EventUtils.IsEventValid) == "function" then
            valid = C_EventUtils.IsEventValid(event) and true or false
        end
        if valid then
            frame:RegisterEvent(event)
        end
    end
    frame:SetScript("OnEvent", function(_, event, unit)
        -- Only the unit events carry a unit token in argument 2. PLAYER_ENTERING_WORLD
        -- passes isInitialLogin and PLAYER_EQUIPMENT_CHANGED passes a GUID there, so a
        -- generic "unit ~= player" filter would silently drop those refreshes.
        if event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE"
            or event == "UNIT_DISPLAYPOWER" then
            if unit ~= "player" then
                return
            end
        end
        pb.update(ST)
    end)
end

-- Build the bar, the driver and the event frame once. Called from main.lua's
-- post_init after the swing bars are built and shown.
function pb.init(ST)
    if pb.ready then
        return true
    end
    if type(CreateFrame) ~= "function" or UIParent == nil then
        pb.inert = true
        return false
    end
    local frame = CreateFrame("Frame", addon_name .. "PowerBar", UIParent)
    frame:SetSize(200, pb.DEFAULT_HEIGHT)
    frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, -200)
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(false)
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints(frame)
    frame.bg:SetColorTexture(pb.BG_COLOR[1], pb.BG_COLOR[2], pb.BG_COLOR[3], pb.BG_COLOR[4])
    -- The track is a REAL StatusBar: a restricted power reading may only be rendered
    -- through the widget's SetMinMaxValues/SetValue (AllowedWhenTainted, BarValue aspect),
    -- and the widget paints the fraction itself - no Lua arithmetic, no texture width.
    -- The 1 px inset is the old hand-computed fill geometry, kept so the pixels match.
    local fill_width, fill_height = pb.fill_dimensions(200, pb.DEFAULT_HEIGHT)
    frame.fill = CreateFrame("StatusBar", addon_name .. "PowerBarFill", frame)
    frame.fill:SetPoint("LEFT", frame, "LEFT", pb.BAR_PADDING, 0)
    frame.fill:SetSize(fill_width, fill_height)
    frame.fill:SetStatusBarTexture(pb.STATUS_BAR_TEXTURE)
    frame.fill:SetStatusBarColor(pb.COLOR_MANA[1], pb.COLOR_MANA[2], pb.COLOR_MANA[3],
        pb.COLOR_MANA[4])
    -- A sane range before the first paint: a restricted reading replaces both raw, and a
    -- readable one overwrites them on the same tick.
    frame.fill:SetMinMaxValues(0, 1)
    frame.fill:SetValue(0)
    frame.fill:EnableMouse(false)
    -- The text is parented to the StatusBar: a child FRAME always draws above its
    -- parent's own regions, so a font string on the container would sit behind the track.
    frame.text = frame.fill:CreateFontString(nil, "OVERLAY")
    if frame.text.SetFontObject then
        pcall(frame.text.SetFontObject, frame.text, nil)
    end
    -- A FontString with no font throws on the first SetText. The shared chain is a
    -- no-op on a template that already carries one and repairs a client that does not.
    if st.utils and type(st.utils.apply_font) == "function" then
        st.utils.apply_font(frame.text, nil, 12, "")
    end
    frame.text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    frame.text:SetJustifyH("CENTER")
    frame.text:SetTextColor(pb.TEXT_COLOR[1], pb.TEXT_COLOR[2], pb.TEXT_COLOR[3], pb.TEXT_COLOR[4])
    frame:Hide()
    pb.frame = frame

    local driver = CreateFrame("Frame", addon_name .. "PowerBarDriver", UIParent)
    pb.driver = driver
    pb.gate_interval = pb.PAINT_INTERVAL
    local accumulator = 0
    driver:SetScript("OnUpdate", function(_, elapsed)
        accumulator = accumulator + (elapsed or 0)
        if accumulator < pb.gate_interval then
            return
        end
        accumulator = 0
        pb.poll(ST)
    end)

    local events = CreateFrame("Frame", addon_name .. "PowerBarEvents", UIParent)
    pb.events = events
    register_events(events, ST)

    pb.ready = true
    pb.update(ST)
    return true
end

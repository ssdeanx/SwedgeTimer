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
-- UnitPower/UnitPowerMax. No class switch and no id table, so the same code paints
-- mana for hunter/paladin/shaman, rage for warrior/bear, energy for rogue/cat and
-- focus wherever that is the primary power. Druid forms repaint through
-- UNIT_DISPLAYPOWER / UPDATE_SHAPESHIFT_FORM; nothing caches the type.
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
-- If no melee bar is visible, or the power read is unknown/secret/zero-max, the bar
-- hides instead of painting a guess.
--
-- DEFAULT: ON. The operator request is the explicit gate for a default-visible
-- change; an explicit false hides it (class table key power_bar_enabled), and the
-- profile/class master switches also gate it.
--
-- EVENTS: UNIT_POWER_FREQUENT / UNIT_POWER_UPDATE / UNIT_DISPLAYPOWER /
-- UPDATE_SHAPESHIFT_FORM / PLAYER_ENTERING_WORLD / PLAYER_EQUIPMENT_CHANGED. The
-- 0.25 s driver is the layout/failsafe paint (it also catches a melee bar being
-- shown/hidden between power events). Every read goes through st.api (compat.lua),
-- so a secret Mainline value degrades to nil and the bar hides.
--
-- CROSS-CLIENT: UnitPower / UnitPowerMax / UnitPowerType are documented on
-- classic_era, classic_anniversary, classic_titan, origin/forever and live (see
-- compat.lua's wrappers); the six events are documented on all five branches. No
-- protected call, no taint risk: the frame is insecure and only SetPoint/SetWidth/
-- SetHeight/SetFrameLevel are used.
--
-- DIAGNOSTICS: every refresh resolves through pb.resolve (read-only) and stores the
-- result in pb.last_state - why the bar hides this tick (or nil when painted), the
-- owning hand, the power reading and the fraction. The verbose /st diag power line
-- reads that receipt instead of re-deriving the decision, so the report and the bar
-- cannot disagree. Nothing on that path writes a frame or a profile key.
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
    if type(ST.bar_is_enabled) == "function" and ST:bar_is_enabled(hand) ~= true then
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
    pb.last_fraction = nil
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
        pb.last_fraction = nil
    end
    if pb.last_height ~= height then
        pb.last_height = height
        frame:SetHeight(height)
        local fill_height = height - (pb.BAR_PADDING * 2)
        if fill_height < 1 then
            fill_height = 1
        end
        if frame.fill and type(frame.fill.SetHeight) == "function" then
            frame.fill:SetHeight(fill_height)
        end
        pb.last_fraction = nil
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

local function paint(class_db, power_type, value, max_value)
    local frame = pb.frame
    local fraction = pb.fraction(value, max_value)
    if fraction == nil then
        return false
    end
    local width = frame:GetWidth() or pb.last_width or 200
    local inner = width - (pb.BAR_PADDING * 2)
    if inner < 1 then
        inner = 1
    end
    local fill_width = fraction * inner
    if fill_width < 1 then
        fill_width = 1
    end
    if pb.last_fraction ~= fraction then
        pb.last_fraction = fraction
        frame.fill:SetWidth(fill_width)
    end
    local color = pb.color_for(power_type)
    if pb.last_color ~= color then
        pb.last_color = color
        frame.fill:SetColorTexture(color[1], color[2], color[3], color[4])
    end
    local text_on = class_db == nil or class_db.power_bar_text_enabled ~= false
    local label = pb.format_value(value)
    if text_on and label ~= nil then
        if pb.last_text ~= label then
            pb.last_text = label
            frame.text:SetText(label)
        end
        if not frame.text:IsShown() then
            frame.text:Show()
        end
    elseif frame.text:IsShown() then
        frame.text:Hide()
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
        or type(api.UnitPower) ~= "function" or type(api.UnitPowerMax) ~= "function" then
        state.why = "no-api"
        return state
    end
    local power_type = api.UnitPowerType("player")
    if type(power_type) ~= "number" then
        state.why = "no-type"
        return state
    end
    state.power_type = power_type
    local value = api.UnitPower("player", power_type)
    local max_value = api.UnitPowerMax("player", power_type)
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
-- compat, then lay out and paint. Every unknown path hides.
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
    if not paint(state.class_db, state.power_type, state.value, state.max_value) then
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
    pb.last_fraction = nil
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
    frame.fill = frame:CreateTexture(nil, "ARTWORK")
    frame.fill:SetPoint("LEFT", frame, "LEFT", pb.BAR_PADDING, 0)
    frame.fill:SetHeight(pb.DEFAULT_HEIGHT - (pb.BAR_PADDING * 2))
    frame.fill:SetWidth(1)
    frame.fill:SetColorTexture(pb.COLOR_MANA[1], pb.COLOR_MANA[2], pb.COLOR_MANA[3], pb.COLOR_MANA[4])
    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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

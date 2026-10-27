--=========================================================================================
-- Ranged distance bar: standalone horizontal melee-weave proximity bar.
--
-- WHAT IT IS: one horizontal bar in its own top-level frame that fills as the distance to
-- the current attackable target closes to melee range, and drains as the target moves
-- away - full at MELEE_RANGE yards or closer, empty at the class's far bound. The label
-- prints the exact distance in yards plus a short state word (MELEE / IN RANGE / OUT).
-- Anchored above the hunter's ranged bar (clear of the cast bar and Rapid Fire bar that
-- stack there), screen-clamped, and centred on UIParent only when no ranged bar frame
-- exists at all.
--
-- DISTANCE SOURCE: `st.api.UnitDistance("target")` ONLY (compat.lua's exact-yards wrapper
-- over UnitDistanceSquared, pcall-wrapped, nil when the client cannot answer). Operator
-- ruling HU-23: no LibRangeCheck read, no band fallback, no protected client call. The
-- bar never reads main.lua's range-poll band fields either (it has one distance source).
-- A nil reading is UNKNOWN: the bar hides rather than painting an empty bar that would
-- read as a real 0.
--
-- ENABLE RULE (nil-safe, and the one place it lives):
--   class_db.weave_range_enabled == true   -> on
--   class_db.weave_range_enabled == false  -> off (explicit off always wins)
--   class_db.weave_range_enabled == nil    -> ST.weave_range_default_enabled(ST.player_class)
--   plus the shared gates: class_db.class_enabled ~= false and profile.enabled ~= false.
-- The nil answer is DELEGATED, not hardcoded: `config_presets.lua`'s
-- `ST.weave_range_default_enabled(class_token)` resolves the class's own defaults table
-- (`ST.HUNTER.defaults.weave_range_enabled = true`, the shared
-- `ST.class_defaults.weave_range_enabled = false`), and the options getter for the same
-- key (option_tables.lua, `weave_range_enabled`) falls back to that identical helper -
-- so a fresh-profile answer, a pre-key profile's nil answer, the settings UI and the
-- runtime gate can never disagree. A sandbox/flavor without the helper reads no default
-- (off) rather than inventing a class.
--
-- COST: one driver frame. Its OnUpdate does an add and one compare per frame; the gate
-- pass runs at UPDATE_INTERVAL (0.05 s) while the feature is enabled and at
-- DISABLED_INTERVAL (0.5 s) while it is off - so the disabled feature costs two table
-- reads twice a second and never touches a unit API. When hidden by a missing target or
-- an unknown distance the bar repaints nothing (all paint values are latched).
--
-- CROSS-CLIENT: UnitDistanceSquared is documented on classic_era, classic_anniversary,
-- classic_titan, origin/forever and live
-- (Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua, Name =
-- "UnitDistanceSquared", Returns distance + checkedDistance), and compat.lua already
-- normalises it. A family without the global hides the bar (unknown), never guesses.
--
-- IN-GAME CONFIRMATION NEEDED (new UI; offline tests pin the maths, the gate order and
-- the frame calls): the anchor stack above the ranged bar, the 200 x 10 px default size,
-- the colours, and the scan-clamp on a top-of-screen bar.
--
-- Pure helpers first (no WoW API; unit-tested by tests/weave_range_state.lua), then the
-- frame driver (create/refresh/update; unit-tested by tests/weave_bar_state.lua). The
-- driver is reached only through init()/poll(), never at file scope, so the pure sandbox
-- load stays WoW-free.
--=========================================================================================
local addon_name, st = ...

st.weave_range = st.weave_range or {}
local wr = st.weave_range

-- Distance band the bar spans, in yards: full at melee, empty at (or beyond) the class's
-- far bound. HUNTER uses 35 yd because that is Auto Shot's range - the melee-weave
-- window this bar exists to show; every other class drains at the 30 yd band the old
-- bar used.
wr.NEAR_YARDS = 5
wr.FAR_YARDS = 30
wr.HUNTER_FAR_YARDS = 35

-- Driver cadence (seconds). UPDATE_INTERVAL matches main.lua's 0.05 s range poll so a
-- faster read could not see new data; DISABLED_INTERVAL is the off-path gate cadence.
wr.UPDATE_INTERVAL = 0.05
wr.DISABLED_INTERVAL = 0.5

-- Frame geometry (px) and colours (the addon's 0-1 texture convention). The backdrop is
-- deliberately near-opaque: the operator's 2026-10-25 report is that the old surfaces
-- read as fully see-through (the appearance lane owns the swing-bar backdrop default;
-- this widget ships its own opaque one).
wr.BAR_WIDTH = 200
wr.BAR_HEIGHT = 10
wr.BAR_PADDING = 1
wr.BAR_GAP = 2
wr.SCREEN_MARGIN = 4
wr.BAR_COLOR = { 0.25, 0.85, 0.40, 0.90 }
wr.MELEE_COLOR = { 0.20, 0.85, 0.25, 1.00 }
wr.IN_RANGE_COLOR = { 0.98, 0.82, 0.18, 1.00 }
wr.OUT_COLOR = { 0.55, 0.55, 0.55, 1.00 }
wr.BG_COLOR = { 0.0, 0.0, 0.0, 0.85 }
wr.LABEL_COLOR = { 1.0, 1.0, 1.0, 1.0 }

--=========================================================================================
-- Pure helpers (WoW-free; the frame driver below is the only WoW-facing half)
--=========================================================================================

-- The far bound for a class token. HUNTER (UnitClass's second return) gets the Auto Shot
-- band; an unknown or lowercase token falls back to the shared 30 yd band (never a
-- player-visible guess: it is the documented non-hunter default).
function wr.far_yards_for(class_token)
    if class_token == "HUNTER" then
        return wr.HUNTER_FAR_YARDS
    end
    return wr.FAR_YARDS
end

-- The class's shipped default for the bar, delegated to the ONE reader the options copy
-- uses (config_presets.lua's ST.weave_range_default_enabled, which resolves the class's
-- own defaults table). The options getter (option_tables.lua, the `weave_range_enabled`
-- widget) reads: explicit saved true/false wins, nil falls back to that same helper - so
-- the runtime gate and the settings UI can never disagree. A flavor/sandbox without the
-- helper reads "no default": the bar stays off rather than inventing a class.
function wr.class_default_on(ST)
    if ST ~= nil and type(ST.weave_range_default_enabled) == "function" then
        return ST.weave_range_default_enabled(ST.player_class) == true
    end
    return false
end

-- The one nil-safe enable rule (see the header). Pure: takes the two settings tables and
-- the class's resolved default, so the frame driver and the tests share one decision.
function wr.enabled_for(class_db, profile_db, default_on)
    if type(class_db) ~= "table" then
        return false
    end
    if class_db.class_enabled == false then
        return false
    end
    if profile_db ~= nil and profile_db.enabled == false then
        return false
    end
    local toggle = class_db.weave_range_enabled
    if toggle == true then
        return true
    end
    if toggle == false then
        return false
    end
    return default_on == true
end

-- Fill fraction in [0, 1] from a point distance, or nil when the distance is unknown.
-- 1 at near_yards or closer, 0 at far_yards or farther, linear in between. nil (never 0)
-- for an unknown distance: the caller hides instead of painting a real-looking empty bar.
function wr.fill_fraction(distance, near_yards, far_yards)
    local yards = tonumber(distance)
    if yards == nil then
        return nil
    end
    local near = tonumber(near_yards) or wr.NEAR_YARDS
    local far = tonumber(far_yards)
    if far == nil then
        far = wr.FAR_YARDS
    end
    if far <= near then
        return nil
    end
    if yards <= near then
        return 1
    end
    if yards >= far then
        return 0
    end
    return (far - yards) / (far - near)
end

-- The state word's key: "melee", "in_range" or "out"; nil for an unknown distance.
function wr.range_state(distance, near_yards, far_yards)
    local frac = wr.fill_fraction(distance, near_yards, far_yards)
    if frac == nil then
        return nil
    end
    local yards = tonumber(distance)
    local near = tonumber(near_yards) or wr.NEAR_YARDS
    local far = tonumber(far_yards) or wr.FAR_YARDS
    if yards <= near then
        return "melee"
    end
    if yards >= far then
        return "out"
    end
    return "in_range"
end

-- The state word shown beside the yards. Unknown keys read nil (the caller hides).
function wr.state_label(state)
    if state == "melee" then
        return "MELEE"
    end
    if state == "in_range" then
        return "IN RANGE"
    end
    if state == "out" then
        return "OUT"
    end
    return nil
end

-- The fill colour for a state key, as the 0-1 tuple the texture calls take.
function wr.state_color(state)
    if state == "melee" then
        return wr.MELEE_COLOR
    end
    if state == "out" then
        return wr.OUT_COLOR
    end
    return wr.IN_RANGE_COLOR
end

-- The yards label ("12 yd"), rounded to the nearest whole yard: a continuous reading has
-- sub-yard precision, and nearest is the most faithful whole-yard claim. nil when the
-- distance is not a number (unknown).
function wr.format_yards(distance)
    local yards = tonumber(distance)
    if yards == nil then
        return nil
    end
    return string.format("%d yd", math.floor(yards + 0.5))
end

-- The full label: "12 yd  IN RANGE" (two spaces, ASCII only). nil when unknown.
function wr.label(distance, near_yards, far_yards)
    local yards = wr.format_yards(distance)
    if yards == nil then
        return nil
    end
    local word = wr.state_label(wr.range_state(distance, near_yards, far_yards))
    if word == nil then
        return yards
    end
    return yards .. "  " .. word
end

--=========================================================================================
-- Frame driver (WoW-facing; reached only through init()/poll())
--=========================================================================================

-- The hunter widgets that stack above the ranged bar (cast bar, Rapid Fire bar). Their
-- RESERVED height is used, never their visibility: a bar that moved every time the Auto
-- Shot cast window opened would repeat the very defect this wave fixes on the melee bars.
-- Nil-safe: a flavor without hunter_ui, or a widget not built yet, contributes 0.
local function reserved_above()
    local total = 0
    local cast = st.hunter_ui and st.hunter_ui.cast_frame
    if cast and type(cast.GetHeight) == "function" then
        local height = cast:GetHeight()
        if type(height) == "number" and height > 0 then
            total = total + height + 2
        end
    end
    local rapid = st.hunter_ui and st.hunter_ui.rapid_fire_bar
    if rapid and type(rapid.GetHeight) == "function" then
        local height = rapid:GetHeight()
        if type(height) == "number" and height > 0 then
            total = total + height + 2
        end
    end
    return total
end

-- The frame to hang the bar above: the ranged bar frame when it exists, else nil (the
-- driver then centres on UIParent). Reads every ref once per layout pass.
local function anchor_bar(ST)
    local ranged = ST and ST.ranged
    local anchor = ranged and ranged.anchor_frame
    return anchor and anchor.bar_frame or nil
end

-- Builds the hidden bar frame and the never-hidden driver frame. Called once from
-- main.lua's post_init. A no-op in a sandbox with no UIParent/CreateFrame.
function wr.init(ST)
    if wr.frame or wr.inert then
        return wr.frame ~= nil
    end
    if type(CreateFrame) ~= "function" or UIParent == nil then
        wr.inert = true
        return false
    end

    local frame = CreateFrame("Frame", addon_name .. "WeaveRangeBar", UIParent)
    wr.frame = frame
    frame:SetSize(wr.BAR_WIDTH, wr.BAR_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
    frame:SetFrameStrata("MEDIUM")
    frame:EnableMouse(false)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(unpack(wr.BG_COLOR))

    -- Horizontal fill: left-anchored, width drives the fill (empty = 1 px sliver).
    local fill = frame:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", frame, "LEFT", wr.BAR_PADDING, 0)
    fill:SetHeight(wr.BAR_HEIGHT - (wr.BAR_PADDING * 2))
    fill:SetWidth(1)
    fill:SetColorTexture(unpack(wr.BAR_COLOR))
    frame.fill = fill

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER", frame, "CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    text:SetTextColor(unpack(wr.LABEL_COLOR))
    frame.text = text

    frame:Hide()

    -- The driver is a separate, never-hidden frame: OnUpdate does not run on a hidden
    -- frame, so the bar frame itself cannot own the poll that decides to show it.
    local driver = CreateFrame("Frame", addon_name .. "WeaveRangeDriver", UIParent)
    wr.driver = driver
    wr.gate_interval = wr.DISABLED_INTERVAL
    local counter = 0
    driver:SetScript("OnUpdate", function(_, elapsed)
        counter = counter + (elapsed or 0)
        if counter < wr.gate_interval then
            return
        end
        counter = 0
        wr.poll(ST)
    end)
    return true
end

-- Repaint gates: hide the bar and drop the paint latches so the next show repaints.
local function hide_bar()
    local frame = wr.frame
    if frame and frame:IsShown() then
        frame:Hide()
    end
    wr.last_fraction = nil
    wr.last_text = nil
    wr.last_state = nil
end

-- One layout pass: pick the anchor, size to the ranged bar, reserve the hunter stack
-- above it, then clamp to the screen. Runs only when one of those inputs reports a
-- change (plus a 1 s re-clamp), never per frame.
local function layout(ST, now)
    local frame = wr.frame
    local bar = anchor_bar(ST)
    local stack = reserved_above()
    local width = wr.BAR_WIDTH
    if bar and type(bar.GetWidth) == "function" then
        local bar_width = bar:GetWidth()
        if type(bar_width) == "number" and bar_width > 0 then
            width = bar_width
        end
    end
    local clamp_due = type(now) == "number"
        and (type(wr.clamp_at) ~= "number" or now >= wr.clamp_at)
    local changed = bar ~= wr.anchor or stack ~= wr.stack or width ~= wr.width
    if not changed and not clamp_due then
        return
    end
    wr.anchor, wr.stack, wr.width = bar, stack, width
    wr.clamp_at = (type(now) == "number") and (now + 1) or nil
    if width ~= frame:GetWidth() then
        frame:SetWidth(width)
        -- The fill width is derived from the inner width: a resized bar must repaint even
        -- when the distance (and therefore the fraction) has not moved.
        wr.last_fraction = nil
    end

    local base_gap = wr.BAR_GAP + stack
    frame:ClearAllPoints()
    if bar then
        frame:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, base_gap)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
    end

    -- Screen clamp: a bar anchored above a ranged bar parked at the top of the screen
    -- would leave the screen. Measure once, then shift the vertical offset (never the
    -- stored position - this frame owns its own anchor).
    local top = type(frame.GetTop) == "function" and frame:GetTop() or nil
    local limit = type(UIParent.GetTop) == "function" and UIParent:GetTop() or nil
    if type(top) == "number" and type(limit) == "number" then
        local overflow = top - (limit - wr.SCREEN_MARGIN)
        if overflow > 0 then
            local point, relative, relative_point, x, y = frame:GetPoint(1)
            if point then
                frame:SetPoint(point, relative, relative_point, x or 0,
                    (y or 0) - overflow)
            end
        end
    end
end

-- One refresh: gate on the settings, read the one distance source, paint the fill, the
-- colour and the label. Hides whenever anything is missing instead of drawing a guess.
function wr.update(ST, now)
    local frame = wr.frame
    if not frame then
        return
    end

    -- Enable gates FIRST: the disabled path must not cost a single unit read. The nil
    -- (no saved value) answer is the class's shipped default, read through the same
    -- helper the options getter uses (see class_default_on above).
    local class_db
    if type(ST.get_class_table) == "function" then
        class_db = ST:get_class_table()
    end
    local profile_db
    if type(ST.get_profile_table) == "function" then
        profile_db = ST:get_profile_table()
    end
    if not wr.enabled_for(class_db, profile_db, wr.class_default_on(ST)) then
        wr.gate_interval = wr.DISABLED_INTERVAL
        hide_bar()
        return
    end
    wr.gate_interval = wr.UPDATE_INTERVAL

    local has_target = type(UnitExists) == "function" and UnitExists("target") and true or false
    if not has_target then
        hide_bar()
        return
    end
    if type(UnitCanAttack) == "function" and not UnitCanAttack("player", "target") then
        hide_bar()
        return
    end

    local yards
    if st.api and type(st.api.UnitDistance) == "function" then
        yards = st.api.UnitDistance("target")
    end
    if type(yards) ~= "number" then
        -- Unknown distance: hide. Never paint 0 as if the target were at the far bound.
        hide_bar()
        return
    end

    local near = wr.NEAR_YARDS
    local far = wr.far_yards_for(ST.player_class)
    local fraction = wr.fill_fraction(yards, near, far)
    local text = wr.label(yards, near, far)
    if fraction == nil or text == nil then
        hide_bar()
        return
    end

    layout(ST, now)

    -- Latch every paint: an unchanged value costs a compare, not a texture call.
    local inner_width = (wr.width or wr.BAR_WIDTH) - (wr.BAR_PADDING * 2)
    if inner_width < 1 then
        inner_width = 1
    end
    local fill_width = fraction * inner_width
    if fill_width < 1 then
        fill_width = 1
    end
    if wr.last_fraction ~= fraction then
        wr.last_fraction = fraction
        frame.fill:SetWidth(fill_width)
    end
    local state = wr.range_state(yards, near, far)
    if wr.last_state ~= state then
        wr.last_state = state
        local color = wr.state_color(state)
        frame.fill:SetColorTexture(color[1], color[2], color[3], color[4])
    end
    if wr.last_text ~= text then
        wr.last_text = text
        frame.text:SetText(text)
    end
    if not frame:IsShown() then
        frame:Show()
    end
end

-- Guarded driver entry (H3 discipline): a throwing update must not break the OnUpdate
-- chain every 0.05 s. Counts, announces once, and gives up after QUARANTINE_ROWS throws.
wr.QUARANTINE_ROWS = 25

function wr.poll(ST)
    local now
    if st.api and type(st.api.get_time) == "function" then
        now = st.api.get_time()
    end
    local ok, err = pcall(wr.update, ST, now)
    if ok then
        wr.failures = nil
        return
    end
    local failures = (wr.failures or 0) + 1
    wr.failures = failures
    wr.last_error = tostring(err)
    if failures == 1 and st.utils and type(st.utils.print_msg) == "function" then
        st.utils.print_msg("Ranged distance bar update failed and was isolated: "
            .. tostring(err))
    end
    if failures >= wr.QUARANTINE_ROWS then
        wr.gate_interval = wr.DISABLED_INTERVAL
        if wr.driver and type(wr.driver.SetScript) == "function" then
            wr.driver:SetScript("OnUpdate", nil)
        end
        hide_bar()
    end
end

if st.debug then st.utils.print_msg('-- Parsed weave_range.lua correctly') end

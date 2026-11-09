--=========================================================================================
-- Ranged distance bar: standalone horizontal melee-weave proximity bar.
--
-- WHAT IT IS: one horizontal bar in its own top-level frame that fills as the distance to
-- the current attackable target closes to melee range, and drains as the target moves
-- away - full at MELEE_RANGE yards or closer, empty at the class's far bound. The label
-- prints the exact distance in yards plus a short state word (MELEE / IN RANGE / OUT).
-- The bar hangs below the POWER bar (the row directly under the bottom-most melee bar),
-- or below the bottom-most visible melee bar when the power bar is hidden/disabled. It is
-- deliberately NOT above the ranged bar any more: the aura icon row already occupies that
-- space, and the 2026-11-09 operator screenshot showed the two overlapping. The frame is
-- screen-clamped and centred on UIParent only when no bar exists at all.
--
-- DISTANCE SOURCE (exact yards first, native band fallback, no guessing):
--   1. `st.api.UnitDistance("target")` - compat.lua's exact-yards wrapper. It uses
--      UnitDistanceSquared when the client actually checked the reading, and on WoW
--      Forever falls back to UnitPosition("player")/UnitPosition("target") coordinates
--      (2D yard metric, the same source Blizzard's TutorialTutorials.lua uses for a
--      target). That fallback is what makes an attackable enemy answer with real yards
--      instead of the old grey unknown.
--   2. `st.api.is_target_in_swing_range(hand)` - the client's OWN exact range check
--      (C_SwingTimer.IsTargetWithinSwingRange, documented on wow-ui-source
--      origin/forever, SwingTimerDocumentation.lua). MainHand = within melee auto-attack
--      range; Ranged = within the ranged swing range. It answers true/false/nil for the
--      current target and is already used by the ranged swing bar. This tier is only
--      reached when no exact yard reading is available.
--   3. The hunter UI's own working left indicator: `ui.range_band()` first returns its
--      computed helper_state verbatim (melee / sweet spot / ranged / out of range), then
--      `ui.spell_range_band()` re-probes the same Auto Shot / Wing Clip / Raptor Strike
--      tokens and numeric IDs. This is the in-instance source when both native checks
--      above are silent; it paints the band instead of the grey unknown face. A name-only
--      duplicate remains for older loads. Never used on non-hunters.
-- Tier 2/3 render the exact BAND (label "<=5 yd  MELEE", "5-35 yd  IN RANGE",
-- ">35 yd  OUT") and a band marker fill; it never invents a yard count between the two
-- bounds. Tier 1 renders the exact yards. No tier reads LibRangeCheck, a protected
-- client call, or main.lua's range-poll band fields.
-- When every tier is silent the reading is UNKNOWN, not zero: the bar renders an
-- explicit neutral "unknown" face (dim fill + "--") and STAYS VISIBLE (B-5, 2026-11-06
-- operator requirement: the range aid must not disappear). It never paints an empty bar
-- that would read as a real far-bound 0, and it never falls back to a guess.
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
-- reads twice a second and never touches a unit API. When hidden by a missing target the
-- bar repaints nothing (all paint values are latched); the unknown-distance face repaints
-- once per transition, not per tick.
--
-- CROSS-CLIENT: UnitDistanceSquared is documented on classic_era, classic_anniversary,
-- classic_titan, origin/forever and live
-- (Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua, Name =
-- "UnitDistanceSquared", Returns distance + checkedDistance), and compat.lua normalises
-- it. The Warcraft Wiki page (API:UnitDistanceSquared, Forever 1.60.1 row) documents the
-- limits that made the bar read grey for an enemy: it answers "a unit in your group" and
-- is #noinstance (outdoors only). The native band tier (C_SwingTimer) is documented on
-- origin/forever, SwingTimerDocumentation.lua, with the exact "nil when no range check
-- could be made" contract compat preserves. A family without either global shows the
-- unknown face (never a guess).
--
-- IN-GAME CONFIRMATION NEEDED (new UI; offline tests pin the maths, the gate order and
-- the frame calls): the anchor below the power bar (bottom-most melee bar when the power
-- bar is hidden), the 200 x 10 px default size, the colours, the screen-clamp at the
-- bottom, and whether the live Forever client answers IsTargetWithinSwingRange for an
-- enemy target in and out of an instance (the band labels are only as good as that
-- answer; the diag `src=` token says which tier answered).
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
-- B-5 (2026-11-06): the target exists and is attackable but the client cannot answer
-- the distance (UnitDistanceSquared checkedDistance=false, restricted, or no global).
-- The operator wants the range aid STAY ON SCREEN, so the bar renders this explicit
-- neutral face instead of disappearing - and never paints an empty bar that would read
-- as a real 0-yard/far-bound reading.
wr.UNKNOWN_COLOR = { 0.55, 0.55, 0.55, 0.55 }
wr.UNKNOWN_LABEL = "--"
-- Band-marker fill for the native swing-range tier: the exact distance between the two
-- bounds is unknowable there, so the fill marks the BAND (never a yard position). MELEE
-- fills the track, IN RANGE marks its midpoint, OUT is the 1 px sliver.
wr.BAND_IN_RANGE_FRACTION = 0.5
wr.BG_COLOR = { 0.0, 0.0, 0.0, 0.85 }
wr.LABEL_COLOR = { 1.0, 1.0, 1.0, 1.0 }

-- Driver-quarantine recovery (B-6, 2026-11-06). A quarantine used to remove the
-- driver's OnUpdate permanently and hide the bar. Now it keeps the driver armed, skips
-- the body for a backoff window, keeps the last paint, and retries: only a repeated
-- full burst of consecutive throws backs the next retry off (10 s, 20 s, ... 60 s).
wr.RECOVERY_SECONDS = 10
wr.RECOVERY_MAX_SECONDS = 60

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
    if state == "out" or state == "out_melee" then
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

-- The native-band label. "<=5 yd  MELEE" / "5-35 yd  IN RANGE" / ">35 yd  OUT" /
-- ">5 yd  OUT" (outside melee, no ranged check available: the far bound is unknown, so
-- only the near bound is claimed). nil for an unknown band key.
function wr.band_label(state, near_yards, far_yards)
    local near = tonumber(near_yards) or wr.NEAR_YARDS
    local far = tonumber(far_yards) or wr.FAR_YARDS
    if state == "melee" then
        return string.format("<=%d yd  MELEE", near)
    end
    if state == "in_range" then
        return string.format("%d-%d yd  IN RANGE", near, far)
    end
    if state == "out" then
        return string.format(">%d yd  OUT", far)
    end
    if state == "out_melee" then
        return string.format(">%d yd  OUT", near)
    end
    return nil
end

-- The band-marker fill fraction (see BAND_IN_RANGE_FRACTION): 1 melee, 0.5 in range,
-- 0 out. nil for an unknown band key.
function wr.band_fraction(state)
    if state == "melee" then
        return 1
    end
    if state == "in_range" then
        return wr.BAND_IN_RANGE_FRACTION
    end
    if state == "out" or state == "out_melee" then
        return 0
    end
    return nil
end

--=========================================================================================
-- Frame driver (WoW-facing; reached only through init()/poll())
--=========================================================================================

-- The frame to hang the bar below: the power bar when it is shown (the row directly
-- under the bottom-most melee bar), else the lowest visible melee bar, else nil (the
-- driver centres on UIParent). Reads every ref once per layout pass.
local function bottom_anchor(ST)
    local pb = st.power_bar
    local power = pb and pb.frame
    if power and type(power.IsShown) == "function" and power:IsShown() then
        return power
    end
    local best, best_bottom
    if type(ST) == "table" and type(ST.iter_hands) == "function" then
        for hand in ST:iter_hands() do
            local frame = ST.get_bar_frame and ST:get_bar_frame(hand) or nil
            if frame and type(frame.IsShown) == "function" and frame:IsShown() then
                local bottom = type(frame.GetBottom) == "function" and frame:GetBottom() or nil
                if type(bottom) == "number" and (best_bottom == nil or bottom < best_bottom) then
                    best, best_bottom = frame, bottom
                end
            end
        end
    end
    return best
end

-- The client's OWN exact swing-range check for the current target, or nil when the
-- client has no native check (every family except WoW Forever). This is tier 2 of the
-- distance source: melee true wins; otherwise ranged true = inside the ranged band;
-- ranged false = beyond it; melee false with no ranged answer = outside melee only
-- ("out_melee": the far bound is unknowable, so only the near bound is claimed).
function wr.swing_band()
    local api = st.api
    if type(api) ~= "table" or type(api.is_target_in_swing_range) ~= "function" then
        return nil
    end
    local melee = api.is_target_in_swing_range("mainhand")
    if melee == true then
        return "melee"
    end
    local ranged = api.is_target_in_swing_range("ranged")
    if ranged == true then
        return "in_range"
    end
    if ranged == false then
        return "out"
    end
    if melee == false then
        return "out_melee"
    end
    return nil
end

-- The same spell-range probes the left hunter range helper uses (Auto Shot for the
-- ranged band, Wing Clip / Raptor Strike for the melee band). This is the working
-- in-instance source when UnitDistance and C_SwingTimer are both silent: the native spell
-- check answers true/false and the bar paints the band instead of the grey unknown face.
function wr.spell_band()
    local api = st.api
    if type(api) ~= "table" or type(api.IsSpellInRange) ~= "function" then
        return nil
    end
    local ui = st.hunter_ui
    -- Prefer the LEFT indicator's computed state verbatim: it is the proven working
    -- indicator the operator sees. Only if it has no state do we re-probe the APIs.
    if ui ~= nil and type(ui.range_band) == "function" then
        local ok, band = pcall(ui.range_band)
        if ok and band ~= nil then
            return band
        end
    end
    -- Next, the working left helper's own probe (including its numeric-ID fallbacks).
    if ui ~= nil and type(ui.spell_range_band) == "function" then
        local ok, band = pcall(ui.spell_range_band)
        if ok and band ~= nil then
            return band
        end
    end
    local function probe(token, fallback)
        local answer
        if token ~= nil then
            local ok, value = pcall(api.IsSpellInRange, token, "target")
            if ok then
                answer = value
            end
        end
        if answer == nil and fallback ~= nil then
            local ok, value = pcall(api.IsSpellInRange, fallback, "target")
            if ok then
                answer = value
            end
        end
        return answer
    end
    local melee = probe(ui and ui.wing_clip_token, "Wing Clip")
    if melee == nil then
        melee = probe(ui and ui.raptor_token, "Raptor Strike")
    end
    local ranged = probe(ui and ui.auto_shot_token, "Auto Shot")
    if melee == true then
        return "melee"
    end
    if ranged == true then
        return "in_range"
    end
    if melee == false and ranged == false then
        return "out"
    end
    if melee == false or ranged == false then
        return "out_melee"
    end
    return nil
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
    wr.last_source = nil
end

-- The bar's inner width (the padding-inset track the fill is laid out in), floored at
-- 1 px so a tiny ranged bar can never produce a negative fill.
local function bar_inner_width()
    local inner = (wr.width or wr.BAR_WIDTH) - (wr.BAR_PADDING * 2)
    if inner < 1 then
        inner = 1
    end
    return inner
end

-- One layout pass: pick the bottom anchor, size to it, clamp to the screen. Runs only
-- when one of those inputs reports a change (plus a 1 s re-clamp), never per frame.
local function layout(ST, now)
    local frame = wr.frame
    local bar = bottom_anchor(ST)
    local width = wr.BAR_WIDTH
    if bar and type(bar.GetWidth) == "function" then
        local bar_width = bar:GetWidth()
        if type(bar_width) == "number" and bar_width > 0 then
            width = bar_width
        end
    end
    local clamp_due = type(now) == "number"
        and (type(wr.clamp_at) ~= "number" or now >= wr.clamp_at)
    local changed = bar ~= wr.anchor or width ~= wr.width
    if not changed and not clamp_due then
        return
    end
    wr.anchor, wr.width = bar, width
    wr.clamp_at = (type(now) == "number") and (now + 1) or nil
    if width ~= frame:GetWidth() then
        frame:SetWidth(width)
        -- The fill width is derived from the inner width: a resized bar must repaint even
        -- when the distance (and therefore the fraction) has not moved.
        wr.last_fraction = nil
    end

    frame:ClearAllPoints()
    if bar then
        frame:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -wr.BAR_GAP)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -100)
    end

    -- Screen clamp: a bar below a bottom-of-screen power bar must stay on screen. Measure
    -- once, then shift the vertical offset (never the stored position - this frame owns
    -- its own anchor).
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
    local bottom = type(frame.GetBottom) == "function" and frame:GetBottom() or nil
    local limit_bottom = type(UIParent.GetBottom) == "function" and UIParent:GetBottom() or nil
    if type(bottom) == "number" and type(limit_bottom) == "number" then
        local under = (limit_bottom + wr.SCREEN_MARGIN) - bottom
        if under > 0 then
            local point, relative, relative_point, x, y = frame:GetPoint(1)
            if point then
                frame:SetPoint(point, relative, relative_point, x or 0,
                    (y or 0) + under)
            end
        end
    end
end

-- One refresh: gate on the settings, read the one distance source, paint the fill, the
-- colour and the label. Hides whenever anything is missing instead of drawing a guess -
-- EXCEPT the explicit unknown-distance face (B-5), which stays visible by design.
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
        -- Why= token for /st diag (B-7): the decision comes from enabled_for; this only
        -- attributes it, so the two can never disagree.
        local reason = "settings-off"
        if type(class_db) ~= "table" then
            reason = "no-class"
        elseif class_db.class_enabled == false then
            reason = "class-off"
        elseif type(profile_db) == "table" and profile_db.enabled == false then
            reason = "profile-off"
        end
        wr.last_reason = reason
        hide_bar()
        return
    end
    wr.gate_interval = wr.UPDATE_INTERVAL

    local has_target = type(UnitExists) == "function" and UnitExists("target") and true or false
    if not has_target then
        wr.last_reason = "no-target"
        hide_bar()
        return
    end
    if type(UnitCanAttack) == "function" and not UnitCanAttack("player", "target") then
        wr.last_reason = "not-attackable"
        hide_bar()
        return
    end

    local near = wr.NEAR_YARDS
    local far = wr.far_yards_for(ST.player_class)
    local yards
    if st.api and type(st.api.UnitDistance) == "function" then
        yards = st.api.UnitDistance("target")
    end
    if type(yards) ~= "number" then
        -- Tier 2 (2026-11-07): the exact API is silent (UnitDistanceSquared is
        -- group-only and #noinstance), so ask the client's native swing-range check.
        -- It is exact for the current target and covers the two bounds this bar spans.
        local band = wr.swing_band()
        local band_source = "swing"
        if band == nil then
            band = wr.spell_band()
            band_source = "spell"
        end
        if band ~= nil then
            wr.last_reason = "band"
            wr.last_distance = nil
            wr.last_source = band_source
            layout(ST, now)
            local inner = bar_inner_width()
            local band_fraction = wr.band_fraction(band)
            local fill_width = band_fraction * inner
            if fill_width < 1 then
                fill_width = 1
            end
            if wr.last_fraction ~= band_fraction then
                wr.last_fraction = band_fraction
                frame.fill:SetWidth(fill_width)
            end
            if wr.last_state ~= band then
                wr.last_state = band
                local color = wr.state_color(band)
                frame.fill:SetColorTexture(color[1], color[2], color[3], color[4])
            end
            local band_text = wr.band_label(band, near, far)
            if wr.last_text ~= band_text then
                wr.last_text = band_text
                frame.text:SetText(band_text)
            end
            if not frame:IsShown() then
                frame:Show()
            end
            return
        end
        -- B-5 (2026-11-06): target present and attackable, distance unknown. The
        -- operator wants the range aid on screen, so render the explicit unknown face:
        -- a dim neutral full-width fill and "--". Never paint 0 as if the target were at
        -- the far bound, and never disappear (that was the "worked then stopped" shape).
        wr.last_reason = "unknown-distance"
        wr.last_distance = nil
        wr.last_source = "none"
        layout(ST, now)
        local inner = bar_inner_width()
        if wr.last_fraction ~= "unknown" then
            wr.last_fraction = "unknown"
            frame.fill:SetWidth(inner)
        end
        if wr.last_state ~= "unknown" then
            wr.last_state = "unknown"
            frame.fill:SetColorTexture(unpack(wr.UNKNOWN_COLOR))
        end
        if wr.last_text ~= wr.UNKNOWN_LABEL then
            wr.last_text = wr.UNKNOWN_LABEL
            frame.text:SetText(wr.UNKNOWN_LABEL)
        end
        if not frame:IsShown() then
            frame:Show()
        end
        return
    end

    local fraction = wr.fill_fraction(yards, near, far)
    local text = wr.label(yards, near, far)
    if fraction == nil or text == nil then
        wr.last_reason = "bad-reading"
        hide_bar()
        return
    end

    layout(ST, now)

    -- Latch every paint: an unchanged value costs a compare, not a texture call.
    local inner_width = bar_inner_width()
    local fill_width = fraction * inner_width
    if fill_width < 1 then
        fill_width = 1
    end
    wr.last_reason = "shown"
    wr.last_distance = yards
    wr.last_source = "exact"
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
-- chain. Counts consecutive throws, announces the first of each burst once, and
-- quarantines after QUARANTINE_ROWS CONSECUTIVE throws (a success resets the streak).
-- B-6 (2026-11-06): the quarantine is RECOVERABLE - the driver stays armed, keeps the
-- last paint, skips the body for a backoff window (10 s doubling to 60 s) and retries.
-- The old shape removed the OnUpdate and hid the bar for the rest of the session.
wr.QUARANTINE_ROWS = 25

function wr.poll(ST)
    local now
    if st.api and type(st.api.get_time) == "function" then
        now = st.api.get_time()
    end
    -- Quarantine window: the driver keeps ticking (cheap) and retries when the window
    -- closes. The last paint stays on screen - a transient must not blank the session.
    if wr.quarantined then
        if type(now) ~= "number"
            or (type(wr.quarantine_until) == "number" and now < wr.quarantine_until) then
            return
        end
        wr.quarantined = false
        wr.quarantine_until = nil
        wr.failures = nil
    end
    local ok, err = pcall(wr.update, ST, now)
    if ok then
        wr.failures = nil
        wr.quarantine_streak = 0
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
        wr.quarantined = true
        wr.quarantine_streak = (wr.quarantine_streak or 0) + 1
        local backoff = wr.RECOVERY_SECONDS * (2 ^ (wr.quarantine_streak - 1))
        if backoff > wr.RECOVERY_MAX_SECONDS then
            backoff = wr.RECOVERY_MAX_SECONDS
        end
        wr.quarantine_until = (type(now) == "number") and (now + backoff) or nil
        wr.gate_interval = wr.DISABLED_INTERVAL
        if st.utils and type(st.utils.print_msg) == "function" then
            st.utils.print_msg(string.format(
                "Ranged distance bar update kept failing (%d in a row); it will retry in %d s.",
                failures, backoff))
        end
    end
end

-- B-7 (2026-11-06): the one /st diag receipt for this bar. Shape:
--   weave=<on|off|?>:<yes|no>:<why>:<distance>:<state>:src=<exact|swing|none|?>:fail=<n>:q=<yes|no>
-- where why is shown / band / no-target / not-attackable / unknown-distance /
-- bad-reading / class-off / profile-off / settings-off / no-class, and src is the tier
-- that answered (exact = UnitDistance, swing = C_SwingTimer band, none = unknown face).
-- Read-only and nil-safe: the diag path must never be the thing that throws.
function wr.diagnostic_text(ST)
    local enabled = "?"
    if type(ST) == "table" and type(ST.get_class_table) == "function" then
        local class_db, profile_db
        local ok_class, db = pcall(ST.get_class_table, ST)
        if ok_class then
            class_db = db
        end
        if type(ST.get_profile_table) == "function" then
            local ok_profile, pdb = pcall(ST.get_profile_table, ST)
            if ok_profile then
                profile_db = pdb
            end
        end
        local ok_default, default_on = pcall(wr.class_default_on, ST)
        if not ok_default then
            default_on = false
        end
        enabled = wr.enabled_for(class_db, profile_db, default_on) and "on" or "off"
    end
    local shown = "no"
    if wr.frame and type(wr.frame.IsShown) == "function" then
        shown = wr.frame:IsShown() and "yes" or "no"
    end
    local distance = "?"
    if type(wr.last_distance) == "number" then
        distance = string.format("%dyd", math.floor(wr.last_distance + 0.5))
    end
    return string.format("weave=%s:%s:%s:%s:%s:src=%s:fail=%d:q=%s",
        enabled,
        shown,
        tostring(wr.last_reason or "?"),
        distance,
        tostring(wr.last_state or "?"),
        tostring(wr.last_source or "?"),
        wr.failures or 0,
        wr.quarantined and "yes" or "no")
end

if st.debug then st.utils.print_msg('-- Parsed weave_range.lua correctly') end

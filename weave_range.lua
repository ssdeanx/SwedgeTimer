--=========================================================================================
-- Weave range: vertical melee-weave proximity bar.
--
-- WHAT IT IS: one small vertical bar plus a yards label that fills as the distance
-- between the player and the current attackable target closes from FAR_YARDS down to
-- NEAR_YARDS, and drains as the target moves away. Two distance sources, exact first:
-- on clients where compat's UnitDistance wrapper answers (UnitDistanceSquared - Era,
-- TBC, Titanforge, Retail, WoW Forever) the fill and the label use exact yards and move
-- per yard; everywhere else they fall back to the range state main.lua's LibRangeCheck
-- poll already publishes (ST.target_min_range / ST.target_max_range, updated by
-- ST:rf_update). Either way this module makes no LibRangeCheck call of its own and adds
-- no per-frame library traffic.
--
-- WHY THE BAND FALLBACK: LibRangeCheck reports distance as a band
-- (minRange, maxRange), not a point value (see the vendored lib's getRange, which
-- returns the boundary of the largest range check the unit is still inside). The
-- fallback fill therefore uses the band's UPPER bound as the distance proxy - the bar
-- never claims to be closer than the target can actually be - and the fallback label
-- prints the band ("5-8 yd", "40+ yd", "<2 yd"). That fill visibly steps at band
-- changes; the exact path removes the stepping on the clients that expose
-- UnitDistanceSquared, and an absent or unchecked reading keeps the band path unchanged.
--
-- LAYOUT: pure helpers first (no WoW API; unit-tested by tests/weave_range_state.lua),
-- then the frame driver (create/refresh). The driver is reached only through
-- init()/update() and never runs at file scope, so the pure sandbox load stays WoW-free.
--
-- OFF BY DEFAULT: the shared class default weave_range_enabled is false (config_presets.lua)
-- and the top-level options toggle (option_tables.lua) flips it. The driver hides the
-- frame whenever that toggle, the class enable or the profile enable is off, and shows it
-- only with an attackable target and either an exact distance reading or a known band.
--
-- IN-GAME CONFIRMATION NEEDED (this is new UI, offline tests can only pin the maths and
-- the frame calls): the anchor (left of PlayerFrame, fallback screen centre), the
-- 16 x 120 px size, the colours, NEAR_YARDS/FAR_YARDS (5/30 yd - the TBC melee ->
-- Lightning Bolt band), and the fill behaviour on both paths (per-yard smoothness where
-- the exact API answers - notably WoW Forever - and the band steps where it does not).
--=========================================================================================
local addon_name, st = ...

st.weave_range = st.weave_range or {}

-- Distance band the bar spans, in yards: full at melee, empty at (or beyond) the TBC
-- Lightning Bolt range. Named constants so retargeting is one edit.
st.weave_range.NEAR_YARDS = 5
st.weave_range.FAR_YARDS = 30

-- Driver refresh cadence in seconds. main.lua's range poll runs at 0.05 s
-- (ST.rangefinder_interval), so reading faster cannot see new data.
st.weave_range.UPDATE_INTERVAL = 0.05

-- Frame geometry (px) and colours (the addon's 0-1 texture convention).
st.weave_range.BAR_WIDTH = 16
st.weave_range.BAR_HEIGHT = 120
st.weave_range.BAR_PADDING = 2
st.weave_range.BAR_COLOR = { 0.25, 0.85, 0.40, 0.90 }
st.weave_range.BG_COLOR = { 0.0, 0.0, 0.0, 0.55 }

--=========================================================================================
-- Pure helpers
--=========================================================================================

-- Pure: is a range reading usable? LibRangeCheck gives (min, max) with either end
-- possibly nil (max nil = beyond the furthest available check, min nil = no lower bound
-- known); only both-nil is "unknown".
function st.weave_range.is_known(min_range, max_range)
    return type(min_range) == "number" or type(max_range) == "number"
end

-- Pure: the single distance proxy the fill uses: the band's upper bound when known
-- (never overstates closeness), else the lower bound. nil when the band is unknown.
function st.weave_range.distance_proxy(min_range, max_range)
    if type(max_range) == "number" then return max_range end
    if type(min_range) == "number" then return min_range end
    return nil
end

-- Pure: proximity fraction in [0, 1]: 1 at NEAR_YARDS or closer, 0 at FAR_YARDS or
-- farther, linear in between. A degenerate span (far <= near) reads 0, and an unknown
-- band reads 0 (the caller hides the frame instead of drawing a guess). The band's
-- proxy value is fed through the exact-path maths below so both paths share one clamp.
function st.weave_range.proximity_fraction(min_range, max_range, near_yards, far_yards)
    local distance = st.weave_range.distance_proxy(min_range, max_range)
    if distance == nil then return 0 end
    return st.weave_range.proximity_fraction_from_distance(distance, near_yards, far_yards)
end

-- Pure: proximity fraction in [0, 1] from a point distance in yards (the exact path):
-- same shape as proximity_fraction - 1 at NEAR_YARDS or closer, 0 at FAR_YARDS or
-- farther, linear in between. A degenerate span (far <= near) or a non-number distance
-- reads 0.
function st.weave_range.proximity_fraction_from_distance(distance, near_yards, far_yards)
    local near = tonumber(near_yards) or st.weave_range.NEAR_YARDS
    local far = tonumber(far_yards) or st.weave_range.FAR_YARDS
    if far <= near then return 0 end
    local yards = tonumber(distance)
    if yards == nil then return 0 end
    local frac = (far - yards) / (far - near)
    if frac < 0 then return 0 end
    if frac > 1 then return 1 end
    return frac
end

-- Pure: the exact yards label for a band, or nil when the band is unknown.
--   both bounds known -> "5-8 yd" (bounds normalised low..high)
--   max nil, min known -> "40+ yd" (at least the lower bound)
--   min nil or 0, max  -> "<8 yd"  (closer than the upper bound)
-- Values are floored to whole yards: LibRangeCheck already floors every boundary it
-- builds from spell ranges, and no client API exposes sub-yard precision here.
function st.weave_range.format_yards(min_range, max_range)
    local min = type(min_range) == "number" and min_range or nil
    local max = type(max_range) == "number" and max_range or nil
    if min ~= nil and max ~= nil then
        local lo = math.min(min, max)
        local hi = math.max(min, max)
        if lo <= 0 then
            return string.format("<%d yd", math.floor(hi))
        end
        return string.format("%d-%d yd", math.floor(lo), math.floor(hi))
    elseif max ~= nil then
        return string.format("<%d yd", math.floor(max))
    elseif min ~= nil then
        return string.format("%d+ yd", math.floor(min))
    end
    return nil
end

-- Pure: the exact-yards label for a point distance ("12 yd"), or nil when the distance
-- is not a number. Rounded to the nearest whole yard: the band labels floor their bounds
-- because LibRangeCheck's bounds are already whole yards, while a continuous reading has
-- sub-yard precision, so nearest is the most faithful whole-yard claim.
function st.weave_range.format_distance_yards(distance)
    local yards = tonumber(distance)
    if yards == nil then return nil end
    return string.format("%d yd", math.floor(yards + 0.5))
end

--=========================================================================================
-- Frame driver (WoW-facing; reached only through init()/update()).
--=========================================================================================

-- Builds the hidden bar frame and the always-shown driver frame. Called once from
-- main.lua's post_init. A no-op in a sandbox with no UIParent/CreateFrame.
function st.weave_range.init(ST)
    local wr = st.weave_range
    if wr.frame or wr.inert then return wr.frame ~= nil end
    if type(CreateFrame) ~= "function" or UIParent == nil then
        wr.inert = true
        return false
    end

    local frame = CreateFrame("Frame", addon_name .. "WeaveRangeBar", UIParent)
    wr.frame = frame
    frame:SetSize(wr.BAR_WIDTH, wr.BAR_HEIGHT)
    if PlayerFrame ~= nil then
        frame:SetPoint("RIGHT", PlayerFrame, "LEFT", -12, 0)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
    end
    frame:SetFrameStrata("MEDIUM")

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(unpack(wr.BG_COLOR))

    local fill = frame:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("BOTTOM", frame, "BOTTOM", 0, wr.BAR_PADDING)
    fill:SetWidth(wr.BAR_WIDTH - (wr.BAR_PADDING * 2))
    fill:SetHeight(1)
    fill:SetColorTexture(unpack(wr.BAR_COLOR))
    frame.fill = fill

    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("BOTTOM", frame, "TOP", 0, 2)
    text:SetJustifyH("CENTER")
    frame.text = text

    frame:Hide()

    -- The driver is a separate, never-hidden frame: OnUpdate does not run on a hidden
    -- frame, so the bar frame itself cannot own the poll that decides to show it.
    local driver = CreateFrame("Frame", addon_name .. "WeaveRangeDriver", UIParent)
    wr.driver = driver
    local counter = 0
    driver:SetScript("OnUpdate", function(_, elapsed)
        counter = counter + (elapsed or 0)
        if counter < wr.UPDATE_INTERVAL then return end
        counter = 0
        wr.update(ST)
    end)
    return true
end

-- One refresh: gate on the settings, read the range state main.lua already publishes,
-- paint the fill height and the yards label. Hides the frame whenever anything is
-- missing instead of drawing a guess.
function st.weave_range.update(ST)
    local wr = st.weave_range
    local frame = wr.frame
    if not frame then return end

    local class_db = ST:get_class_table()
    local profile_db = ST:get_profile_table()
    -- No class row means no weave range toggle: the bar cannot be enabled without
    -- settings, so it hides (the same fail-closed state an off toggle paints).
    -- This runs from the driver's 0.2 s poll, so it must never throw on absence.
    if type(class_db) ~= "table" then
        if frame:IsShown() then frame:Hide() end
        return
    end
    local enabled = class_db.weave_range_enabled == true
        and class_db.class_enabled ~= false
        and (profile_db == nil or profile_db.enabled ~= false)
    if not enabled then
        if frame:IsShown() then frame:Hide() end
        return
    end

    local min_range, max_range = ST.target_min_range, ST.target_max_range
    local has_target = type(UnitExists) == "function" and UnitExists("target") and true or false
    local attackable = true
    if type(UnitCanAttack) == "function" then
        attackable = UnitCanAttack("player", "target") and true or false
    end
    if not has_target or not attackable then
        if frame:IsShown() then frame:Hide() end
        return
    end

    -- Exact yards first: on clients where compat's UnitDistance wrapper answers
    -- (UnitDistanceSquared on the clients that have it), it supersedes the LibRangeCheck
    -- band for both the fill and the label, so the bar moves per yard instead of stepping
    -- per band. An absent wrapper, an unknown reading or a non-number result keeps
    -- exact_yards nil and the band path below behaves exactly as before this branch
    -- existed. Queried only once the target gates passed, never while disabled.
    local exact_yards
    if st.api and type(st.api.UnitDistance) == "function" then
        exact_yards = st.api.UnitDistance("target")
        if type(exact_yards) ~= "number" then
            exact_yards = nil
        end
    end

    -- The LibRangeCheck band is the fallback source: when no exact reading is available,
    -- an unknown band still hides the frame instead of drawing a guess.
    if exact_yards == nil and not wr.is_known(min_range, max_range) then
        if frame:IsShown() then frame:Hide() end
        return
    end

    local label, frac
    if exact_yards ~= nil then
        label = wr.format_distance_yards(exact_yards)
        frac = wr.proximity_fraction_from_distance(exact_yards)
    else
        label = wr.format_yards(min_range, max_range)
        frac = wr.proximity_fraction(min_range, max_range)
    end
    if label == nil then
        if frame:IsShown() then frame:Hide() end
        return
    end

    local inner_height = wr.BAR_HEIGHT - (wr.BAR_PADDING * 2)
    frame.fill:SetHeight(math.max(1, frac * inner_height))
    frame.text:SetText(label)
    if not frame:IsShown() then frame:Show() end
end

if st.debug then st.utils.print_msg('-- Parsed weave_range.lua correctly') end

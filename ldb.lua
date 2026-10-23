--=========================================================================================
-- LibDataBroker feed: publishes the live mainhand swing state as a broker data object so
-- any LibDataBroker display (Titan Panel, Baggage, a LibDBIcon minimap button, ...) can
-- show it. The object is created exactly once per session; bars.lua drives it from the
-- existing per-frame bar update, mainhand only, next to the generic class hook.
--
-- Data object field set (LibDataBroker-1.1 semantics):
--   type / text / label      broker identity: "data source", "SwedgeTimer", "Swing"
--   value                    mainhand swing time remaining as a PLAIN STRING ("%.2f"),
--                            so no number and no secret value is ever published
--   firstText / firstValue   "Speed" + the numeric mainhand swing speed, bounded by the
--                            MinValue/MaxValue pair below for bar-style displays
--   MinValue / MaxValue      speed bounds, 0.1 .. 6.0
--   secondText / secondValue "Combat" + "In combat" / "Out of combat"
--   OnTooltipShow            live multi-line tooltip (read on hover, never throttled)
--   OnClick                  left-click toggles the swing bars; other buttons ignored
--
-- Cadence: the bar OnUpdate runs every frame, which is far more often than a swing
-- readout needs. update() throttles to at most 4 publishes a second and then writes a
-- field only when its formatted value actually changed - LDB fires four callbacks per
-- changed field, so an unchanged publish must never reach the object. Nothing on this
-- path allocates a table, and the value string is not even built outside the throttle.
--
-- Degradation: LibDataBroker-1.1 is fetched with the silent LibStub form, so a client
-- without a broker library (or one where it never registered) simply has no data object
-- and update() is a no-op forever after one init attempt. Nothing here gates on
-- st.is_mainline: the Retail stand-in swing engine never reports a swing, so there is
-- no state to publish there anyway, while WoW Forever publishes like every other client.
--
-- The clock is compat's aligned st.api.get_time(), never raw GetTime(), and no
-- cross-client API is called outside compat.
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
-- Cross-client API wrappers (see compat.lua).
local api = st.api

st.ldb = st.ldb or {}
local ldb = st.ldb

-- Silent form: an absent broker library must degrade to "nothing", never to an error.
local broker = LibStub("LibDataBroker-1.1", true)

-- Broker name of our data object. The client takes the first registered object with a
-- given name, and NewDataObject refuses to make a second one.
local OBJECT_NAME = "SwedgeTimer"
-- Publishing cadence. Four updates a second is enough for a swing readout and keeps the
-- per-frame bar OnUpdate effectively free when no broker display is even installed.
local UPDATE_INTERVAL = 0.25
-- Swing speed bounds, for displays that render firstValue as a bar.
local MIN_SPEED = 0.1
local MAX_SPEED = 6.0
local IN_COMBAT = "In combat"
local OUT_OF_COMBAT = "Out of combat"

-- Session state. obj/owner come from init; the last_* values are the write cache.
ldb.obj = nil
ldb.owner = nil
ldb.init_attempted = false
ldb.last_update = nil
ldb.last_value = nil
ldb.last_speed = nil
ldb.last_combat = nil

-- Formats a number for publication. string.format raises on values the client protects
-- (secret values), so it is wrapped: a protected reading simply is not published.
local function format_number(value)
    local ok, text = pcall(string.format, "%.2f", value)
    if ok and type(text) == "string" then
        return text
    end
    return nil
end

-- Live read of the tracked (mainhand) swing state. Returns remaining, speed, or nil
-- when there is no swing state to describe at all.
local function swing_state(owner)
    local d = owner and owner.mainhand
    if type(d) ~= "table" then return nil end
    local speed = d.speed
    local ends_at = d.ends_at
    if type(speed) ~= "number" or type(ends_at) ~= "number" then return nil end
    if speed <= 0 then return nil end
    local remaining = ends_at - api.get_time()
    if remaining < 0 then remaining = 0 end
    return remaining, speed
end

-- Hover path: read live rather than the throttled publish, since a tooltip is a
-- user-initiated event where freshness is worth one extra format.
local function tooltip_show(tooltip)
    local remaining, speed = swing_state(ldb.owner or ST)
    tooltip:SetText("SwedgeTimer")
    if remaining then
        local remaining_text = format_number(remaining)
        local speed_text = format_number(speed)
        if remaining_text then
            tooltip:AddLine("Swing remaining: " .. remaining_text, 1, 1, 1)
        else
            tooltip:AddLine("Swing remaining: --", 1, 1, 1)
        end
        if speed_text then
            tooltip:AddLine("Swing speed: " .. speed_text, 1, 1, 1)
        else
            tooltip:AddLine("Swing speed: --", 1, 1, 1)
        end
        tooltip:AddLine("Hand: Mainhand", 1, 1, 1)
    else
        tooltip:AddLine("No swing state yet", 1, 1, 1)
    end
    tooltip:AddLine("|cffeda55fLeft-Click:|r Toggle swing timer bars", 1, 1, 1)
    tooltip:Show()
end

-- Click path: mirrors the archived build's minimap button
-- (docs/swedge/SwedgeTimer_TBC/minimap.lua), which flipped a global enable and let the
-- addon's own visibility pass re-apply the per-hand show conditions. Nothing here calls
-- show_bar/hide_bar directly: set_bar_visibilities is the function that owns them, and
-- it keeps practice-mode and class gating intact.
--
-- Displays disagree on the callback shape - LibDBIcon passes (frame, buttonName) while
-- Titan Panel passes (buttonName) - so the first string argument is treated as the button.
local function toggle_bars(first, second)
    local button = first
    if type(button) ~= "string" then button = second end
    if button and button ~= "LeftButton" then return end
    local owner = ldb.owner or ST
    -- Nothing to toggle before the bar frames exist (init_libs has not run).
    if not owner.db or not owner.interfaces_are_initialised then return end
    local db_class = owner:get_class_table()
    if type(db_class) ~= "table" then return end
    db_class.class_enabled = not db_class.class_enabled
    owner:set_bar_visibilities()
    -- Keep the options UI showing the setting we just flipped.
    local acr = LibStub("AceConfigRegistry-3.0", true)
    if acr and owner.options_table_name then
        acr:NotifyChange(owner.options_table_name)
    end
end

--=========================================================================================
-- Data object creation
--=========================================================================================
-- Idempotent, and safe to call before the addon is initialised: self is the addon object
-- (bars.lua passes it), with ST - the same object, looked up once here - as the fallback.
function ldb.init(self)
    if ldb.obj then
        return ldb.obj
    end
    -- One attempt per session: a broker library that is not there on the first tick is
    -- not going to appear mid-session, and the hot path must not keep retrying.
    if ldb.init_attempted then
        return nil
    end
    ldb.init_attempted = true
    if not broker then
        return nil
    end
    ldb.owner = self or ST
    local obj = broker:NewDataObject(OBJECT_NAME, {
        type = "data source",
        text = "SwedgeTimer",
        label = "Swing",
        value = "0.00",
        firstText = "Speed",
        firstValue = MIN_SPEED,
        MinValue = MIN_SPEED,
        MaxValue = MAX_SPEED,
        secondText = "Combat",
        secondValue = OUT_OF_COMBAT,
        OnTooltipShow = tooltip_show,
        OnClick = toggle_bars,
    })
    -- NewDataObject returns nil when the name is taken (an object left behind by an
    -- earlier copy or reload): adopt that one rather than publishing a second.
    if not obj then
        obj = broker:GetDataObjectByName(OBJECT_NAME)
    end
    ldb.obj = obj
    return obj
end

--=========================================================================================
-- Broker object class
--=========================================================================================
-- NewDataObject's result is typed as a union of display kinds, so the fields the feed
-- writes are declared once here; the live object is cast to this class wherever it is
-- handed out, keeping every write type-checked against our own declarations.
---@class SwedgeTimerLDBObject
---@field value string
---@field firstValue number
---@field secondValue string

--=========================================================================================
-- Per-frame feed (called from bars.lua)
--=========================================================================================
function ldb.update(self, hand)
    -- Mainhand only: the offhand and ranged bars never feed the broker.
    if hand ~= "mainhand" then return end
    local obj = ldb.obj --[[@as SwedgeTimerLDBObject?]]
    if not obj then
        -- Lazy init. The bars only start ticking once the swing engine is up, which is
        -- exactly the first moment there is swing state worth publishing; init is
        -- idempotent, so this runs NewDataObject at most once per session.
        obj = ldb.init(self) --[[@as SwedgeTimerLDBObject?]]
        if not obj then return end
    end
    local now = api.get_time()
    -- since < 0 can only happen if the clock ever steps backwards; publish rather than
    -- stall the feed for as long as the step takes to wear off.
    local since = now - (ldb.last_update or -UPDATE_INTERVAL)
    if since >= 0 and since < UPDATE_INTERVAL then return end
    ldb.last_update = now

    local d = self and self.mainhand
    local speed = type(d) == "table" and d.speed or nil
    local ends_at = type(d) == "table" and d.ends_at or nil
    -- No swing state yet (pre-init, or a client with no mainhand speed): publish
    -- the "--" sentinel (the tooltip's "Swing remaining: --" shape) instead of
    -- leaving a stale number up. J2 (hunter-proctor-fixes): "--" is the unknown
    -- contract - never 0.00, which would read as a landed swing; last_value
    -- tracks it so the sentinel publishes exactly once per stateless run.
    if type(speed) ~= "number" or type(ends_at) ~= "number" or speed <= 0 then
        if ldb.last_value ~= "--" then
            obj.value = "--"
            ldb.last_value = "--"
        end
        return
    end
    local remaining = ends_at - now
    if remaining < 0 then remaining = 0 end

    -- Only build the value string once the throttle has let us through, and only hand it
    -- to the object when it differs from what the object already shows.
    local remaining_text = format_number(remaining)
    if remaining_text and remaining_text ~= ldb.last_value then
        obj.value = remaining_text
        ldb.last_value = remaining_text
    end
    if speed ~= ldb.last_speed then
        obj.firstValue = speed
        ldb.last_speed = speed
    end
    local combat = self.in_combat and IN_COMBAT or OUT_OF_COMBAT
    if combat ~= ldb.last_combat then
        obj.secondValue = combat
        ldb.last_combat = combat
    end
end

if st.debug then st.utils.print_msg('-- Parsed ldb.lua module correctly') end

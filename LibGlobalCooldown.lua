local MAJOR_VERSION = "LibGlobalCooldown"
local MINOR_VERSION = 1

local lib = LibStub:NewLibrary(MAJOR_VERSION, MINOR_VERSION)
if not lib then
    return
end

-- Cross-client API wrappers (see compat.lua).
local _, st = ...
local api = st.api

-- See compat.lua: a restricted (secret) stat/cooldown reading must degrade to "skip this
-- update", never to an error. Exact no-op where the probe is absent (classic clients).
local is_secret = issecretvalue or function()
    return false
end

local CreateFrame = CreateFrame
local C_Timer = C_Timer
local GetCombatRating = api.GetCombatRating
local GetCombatRatingBonus = api.GetCombatRatingBonus
-- 20 is CR_HASTE_SPELL, spelled as the bare index on purpose: the global constant is
-- NOT portable. Classic Era defines it only in the TBC/Cata PaperDollFrame variants, so
-- the vanilla client reads nil and GetCombatRating(nil) raises
-- "Usage: GetCombatRating(ratingIndex)" on every COMBAT_RATING_UPDATE (2026-10-28
-- in-client report, ERA). calculate_expected_spell_gcd has always used the bare 20 for
-- the same read, which is why that path never raised.
local HASTE_SPELL_RATING = 20

-- Rating reads are advisory: a client that cannot answer (a nil/out-of-range index on a
-- vanilla client, a restricted secret value, an absent API) keeps the previous estimate
-- instead of throwing out of an event handler. nil = "unknown", never zero.
local function read_combat_rating(index)
    local ok, value = pcall(GetCombatRating, index)
    if not ok or type(value) ~= "number" or is_secret(value) then
        return nil
    end
    return value
end

local function read_combat_rating_bonus(index)
    local ok, value = pcall(GetCombatRatingBonus, index)
    if not ok or type(value) ~= "number" or is_secret(value) then
        return nil
    end
    return value
end

-- A plain finite number, or nil. is_secret is asked BEFORE any comparison or type() use:
-- a secret value keeps its underlying type and raises on comparison, so the probe is the
-- only legal question. A restricted read therefore never reaches the arithmetic below.
local function plain_number(value)
    if is_secret(value) then
        return nil
    end
    if type(value) ~= "number" then
        return nil
    end
    if value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

-- Secret-safe for the reads below: compat's GetSpellCooldown reports a restricted
-- (secret) reading as 0/0/0/0 plus a fifth `restricted` return. A readable zero is still
-- the cleared-cooldown shape the == 0 early-outs handle; a restricted read is UNKNOWN and
-- now clears the timing state instead of being stored as a number.
local GetSpellCooldown = api.GetSpellCooldown
local GetSpellInfo = api.GetSpellInfo
local GetTime = GetTime
local GetShapeshiftForm = api.GetShapeshiftForm
-- Spell id whose cooldown reading mirrors the global cooldown (family-specific).
local gcd_probe_spell_id = st.gcd_probe_spell_id
local math = math
local select = select
local UnitClass = UnitClass

-- Callbacks and event names
lib.callbacks = lib.callbacks or LibStub("CallbackHandler-1.0"):New(lib)
lib.GCD_OVER = "GCD_OVER"
lib.GCD_STARTED = "GCD_STARTED"
lib.GCD_DURATIONS_UPDATED = "GCD_DURATIONS_UPDATED"
lib.GCD_PHYS_UPDATED = "GCD_PHYS_UPDATED"
lib.GCD_SPELL_UPDATED = "GCD_SPELL_UPDATED"
-- Forever object channel (bench/forever_hud_api_2026-11-08.md §6): while the client hides
-- cooldown timing the numeric read is the degraded zero shape, so the GCD is carried by the
-- client's opaque LuaDurationObject. The handle is NOT a secret value and no number is
-- derived from it; the event is additive, so existing consumers are untouched.
lib.GCD_OBJECT_STARTED = "GCD_OBJECT_STARTED"
lib.GCD_OBJECT_OVER = "GCD_OBJECT_OVER"

-- Containers for state tracking
lib.in_combat = false
lib.current_form = nil

-- Containers for active GCD info
lib.gcd_duration = nil
lib.gcd_started = nil
lib.gcd_expires = nil

-- Forever object channel state. Both fields are plain by construction: the object is a
-- non-secret opaque handle and gcd_on_gcd is the NeverSecret SpellCooldownInfo field.
-- nil = no object-reported GCD.
lib.gcd_object = nil
lib.gcd_on_gcd = nil

-- Containers for predicted GCD info
lib.phys_gcd = 1.5 -- will be modified for feral cats
lib.base_spell_gcd = 1.5
lib.current_spell_gcd = nil
lib.has_bloodlust = false
lib.has_breath_haste = false
lib.current_spell_haste = nil

-- A cast time that will be guaranteed to not benefit from a class's
-- instant cast procs. Defaults to Flash of Light, but if the player is a
-- Paladin we'll change this to rank 1 Frostbolt to avoid AoW instant casts.
lib.cast_time_1500ms_spell_id = 19750

function lib:Fire(event, ...)
    self.callbacks:Fire(event, ...)
end

-----------------------------------------------------------
-- Funcs to manipulate state and fire events
-----------------------------------------------------------
function lib:calculate_expected_spell_gcd()
    -- First try to calc the expected GCD from first principles
    -- 20 = CR_HASTE_SPELL (HASTE_SPELL_RATING). An unknown/restricted read keeps the
    -- previous estimate instead of folding in a value we cannot see.
    local rating_percent_reduction = read_combat_rating_bonus(HASTE_SPELL_RATING)
    if rating_percent_reduction == nil then
        return
    end
    local spell_gcd = self.base_spell_gcd
    local reduction_from_haste_rating = 100 / (100 + rating_percent_reduction)
    local current = spell_gcd * reduction_from_haste_rating
    if lib.has_bloodlust then
        current = current * (1 / 1.3)
    end
    if lib.has_breath_haste then
        current = current * (1 / 1.25)
    end

    -- Flash of Light has a 1.5s cast time so can be used to check
    -- for the spell GCD duration, in case we miss any multiplicative buffs.
    -- If there are any debuffs decreasing cast speed, this will be wrong,
    -- and we'll fallback on the first principles calc.
    local cast_time_test = select(4, GetSpellInfo(self.cast_time_1500ms_spell_id))
    cast_time_test = cast_time_test or 1500
    cast_time_test = cast_time_test / 1000 -- change from ms to s

    -- Get the minimum of the 2 methods, which should be the more accurate.
    -- print(current, cast_time_test)
    current = math.min(current, cast_time_test)

    -- The minimum GCD for all classes is 1 second.
    if current < 1 then
        current = 1.0
    end
    -- print(string.format("current: %f, old: %f", current, self.current_spell_gcd))
    -- print(current, self.current_spell_gcd)

    -- If has changed, fire relevant triggers.
    if current ~= self.current_spell_gcd then
        self.current_spell_gcd = current
        self:Fire(self.GCD_SPELL_UPDATED, self.current_spell_gcd)
        self:Fire(self.GCD_DURATIONS_UPDATED, self.phys_gcd, self.current_spell_gcd)
    end
    -- print(string.format('spell GCD: %f, phys GCD: %f', current, self.phys_gcd))
end

function lib:release_gcd_lock()
    self.gcd_duration = nil
    self.gcd_started = nil
    self:clear_gcd_object()
    self:Fire(self.GCD_OVER)
end

-- Drop the Forever object channel. The over event fires only when it was carrying, so a
-- callback consumer sees one start and one over per object-reported GCD.
function lib:clear_gcd_object()
    if self.gcd_object == nil and self.gcd_on_gcd == nil then
        return
    end
    self.gcd_object = nil
    self.gcd_on_gcd = nil
    self:Fire(self.GCD_OBJECT_OVER)
end

function lib:poll_gcd()
    -- Function to be called when we have reason to believe a new GCD may
    -- have triggered. Locks out new updates when we're on a GCD.
    if self.gcd_duration then
        return
    end
    -- Forever only + exact API probe: while cooldown timing is restricted the numeric read
    -- below is the degraded zero shape and would never arm a GCD. The plain NeverSecret
    -- SpellCooldownInfo fields (isOnGCD/isActive) say a GCD is running, and the opaque
    -- duration object carries it; NO number is derived from either. Never keyed on
    -- st.is_mainline alone (Retail keeps the numeric path).
    if st.family == "FOREVER" and type(api.get_spell_cooldown_duration) == "function" then
        local on_gcd, active
        if type(api.get_spell_cooldown_state) == "function" then
            local state_ok
            state_ok, on_gcd, active = pcall(api.get_spell_cooldown_state, gcd_probe_spell_id)
            if not state_ok then
                on_gcd, active = nil, nil
            end
        end
        if on_gcd == true or active == true then
            local object_ok, object = pcall(api.get_spell_cooldown_duration,
                gcd_probe_spell_id, false)
            if object_ok and object ~= nil then
                local was_carrying = self.gcd_object ~= nil
                self.gcd_object = object
                self.gcd_on_gcd = on_gcd == true
                if not was_carrying then
                    self:Fire(self.GCD_OBJECT_STARTED, object, on_gcd == true)
                end
            end
            return
        end
        -- The client says no GCD is running: release the object channel so the next GCD
        -- reports its own start.
        self:clear_gcd_object()
    end
    local time_started, duration_reported, _, _, restricted = GetSpellCooldown(gcd_probe_spell_id)
    if restricted == true then
        -- The client hid the timing and no object answered: clear the timing state rather
        -- than storing a partial number derived from the degraded idle shape.
        self:clear_gcd_object()
        return
    end
    local duration = plain_number(duration_reported)
    local started = plain_number(time_started)
    if duration == nil or started == nil or duration <= 0 then
        -- A readable idle read: no GCD is running (a restricted read took the branch above),
        -- so a stale object channel is released here as well.
        self:clear_gcd_object()
        return
    end
    local t = GetTime()
    local duration_actual = duration - (t - started)
    local expires = t + duration_actual
    self.gcd_duration = duration
    self.gcd_started = started
    self.gcd_expires = expires
    -- print(duration_reported)
    self:Fire(self.GCD_STARTED, duration_actual, expires)
    C_Timer.After(duration_actual, function() self:release_gcd_lock() end)
end

-----------------------------------------------------------
-- Event handlers
-----------------------------------------------------------
function lib:COMBAT_RATING_UPDATE()
    -- 20 = CR_HASTE_SPELL (HASTE_SPELL_RATING), never the global constant: Classic Era
    -- leaves CR_HASTE_SPELL nil on the vanilla client, so GetCombatRating(nil) raises
    -- "Usage: GetCombatRating(ratingIndex)" for every fired event.
    -- An unknown/restricted read keeps the previous estimate, never compares or stores it.
    local new_spell_haste = read_combat_rating(HASTE_SPELL_RATING)
    if new_spell_haste == nil then
        return
    end
    -- print(new_spell_haste)
    if new_spell_haste ~= self.current_spell_haste then
        -- print('spell haste changed')
        self.current_spell_haste = new_spell_haste
        self:calculate_expected_spell_gcd()
    end
end

function lib:PLAYER_LOGIN()
    -- Populate info on class here.
    local class = select(2, UnitClass("player"))
    -- print("class says: "..tostring(class))
    self.class = class

    if self.class == "PALADIN" then
        self.cast_time_1500ms_spell_id = 116
    end
    lib.phys_gcd = 1.5
    lib.base_spell_gcd = 1.5
    -- Set the phys gcds for special cases i.e. rogue/cat.
    if class == "ROGUE" then
        lib.phys_gcd = 1
    elseif self.class == "DRUID" then
        local i = GetShapeshiftForm()
        if i == 3 then
            lib.phys_gcd = 1
        end
        self.current_form = i
    end

    self:calculate_expected_spell_gcd()
    self:Fire("GCD_DURATIONS_UPDATED", lib.phys_gcd, lib.current_spell_gcd)
end

-- function lib:PLAYER_REGEN_DISABLED()
--     self.in_combat = true
-- end

-- function lib:PLAYER_REGEN_ENABLED()
--     self.in_combat = false
-- end

function lib:SPELL_UPDATE_COOLDOWN()
    self:poll_gcd()
end

function lib:UNIT_AURA()
    self:calculate_expected_spell_gcd()
end

function lib:UNIT_SPELLCAST_INTERRUPTED()
    if self.gcd_duration then
        -- The numeric lock is only ever armed from a READABLE read, so this release keeps
        -- its historical shape: compat reports a restricted read as the cleared 0 shape,
        -- and releasing then is harmless (the object channel never uses this lock). T1's
        -- warning - that this must not become the only release path once the GCD works -
        -- is honoured by the object channel, which releases from the plain GCD state.
        local duration_reported = select(2, GetSpellCooldown(gcd_probe_spell_id))
        if duration_reported == 0 then
            self:release_gcd_lock()
        end
    end
end

function lib:UPDATE_SHAPESHIFT_FORM()
    -- Only druids have their physical gcd change.
    if self.class ~= "DRUID" then
        return
    end
    local i = GetShapeshiftForm()
    if i == 3 then
        self.phys_gcd = 1.0
    else
        self.phys_gcd = 1.5
    end
    self.current_form = i
    self:Fire(self.GCD_PHYS_UPDATED, lib.phys_gcd)
    self:Fire(self.GCD_DURATIONS_UPDATED, lib.phys_gcd, lib.current_spell_gcd)
end

function lib:activate()
    if not self.frame then
        local frame = CreateFrame("Frame")
        self.frame = frame
        frame:RegisterEvent("PLAYER_LOGIN")
        -- frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        -- frame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frame:RegisterEvent("COMBAT_RATING_UPDATE")
        frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        frame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        frame:RegisterUnitEvent("UNIT_AURA", "player")
        frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
    end
    self.frame:SetScript("OnEvent", function(_, event, ...)
        lib[event](lib, event, ...)
    end
    )
end

lib:activate()

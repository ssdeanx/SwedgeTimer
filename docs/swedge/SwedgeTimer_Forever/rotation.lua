-- rotation.lua =============================================================================
-- Rotation Helper Module for SwedgeTimer
-- Calculates optimal seal twist rotation based on attack speed and haste
-- Inspired by the "Rotation Twister" WeakAura by Surveillant
local addon_name, st = ...
local print = st.utils.print_msg
local ST = LibStub("AceAddon-3.0"):GetAddon("SwedgeTimer")

--=========================================================================================
-- ROTATION MODULE
--=========================================================================================
st.rotation = {}

-- Current rotation state
st.rotation.current_rotation = nil      -- Current rotation type (e.g., "1/2", "2/3")
st.rotation.current_step = 1            -- Current position in rotation sequence (1-indexed)
st.rotation.sequence = {}               -- Current rotation sequence (array of action strings)
st.rotation.last_rotation = nil         -- Previous rotation (for detecting changes)

-- Crusader Strike tracking
st.rotation.cs_on_cooldown = false
st.rotation.cs_cooldown_remaining = 0
st.rotation.cs_cooldown_start = 0
st.rotation.cs_cooldown_duration = 6    -- CS has a 6 second cooldown

-- Cache for rotation calculation (avoid recalculating every frame)
st.rotation.cache_time = 0
st.rotation.cache_rotation = nil
st.rotation.cache_interval = 0.05       -- Recalculate every 50ms at most

--=========================================================================================
-- ROTATION DEFINITIONS
-- Each rotation defines the sequence of actions in one "cycle"
-- Actions: "cs", "twist", "blood_auto", "cmd_auto", "cs_late"
--=========================================================================================

st.rotation.sequences = {
    ["1/2"] = {"cs", "twist"},
    ["2/3"] = {"cs", "twist", "twist"},
    ["2/2/5"] = {"cs", "twist", "cs_late", "blood_auto", "twist"},
    ["2/4"] = {"cs", "twist", "blood_auto", "twist"},
    ["1/3"] = {"cs", "blood_auto", "twist"},
    ["2/5_blood"] = {"cs", "blood_auto", "twist", "blood_auto", "twist"},
    ["2/5_command"] = {"cs", "cmd_auto", "twist", "cmd_auto", "twist"},
    ["2007"] = {"blood_auto", "cs"},
}

-- Human-readable descriptions for training mode
st.rotation.descriptions = {
    ["1/2"] = "CS, Twist",
    ["2/3"] = "CS, Twist, Twist",
    ["2/2/5"] = "CS, Twist, CS (late), Auto, Twist",
    ["2/4"] = "CS, Twist, Auto, Twist",
    ["1/3"] = "CS, Auto, Twist",
    ["2/5_blood"] = "CS, Auto, Twist, Auto, Twist",
    ["2/5_command"] = "CS, Cmd Auto, Twist, Cmd Auto, Twist",
    ["2007"] = "Ride Blood & CS",
}

-- Display names for rotation types
st.rotation.display_names = {
    ["1/2"] = "1/2",
    ["2/3"] = "2/3",
    ["2/2/5"] = "2/2/5",
    ["2/4"] = "2/4",
    ["1/3"] = "1/3",
    ["2/5_blood"] = "2/5 Blood",
    ["2/5_command"] = "2/5 Command",
    ["2007"] = "2007",
}

--=========================================================================================
-- SPELL TEXTURE IDS
-- Used to display ability icons in the rotation helper
--=========================================================================================

st.rotation.spell_textures = {
    cs = 35395,          -- Crusader Strike
    cs_late = 35395,     -- Crusader Strike (same icon, different timing)
    twist = nil,         -- Special: uses split icon (Command + Blood)
    blood_auto = 31892,  -- Seal of Blood (represents auto with Blood)
    cmd_auto = 20375,    -- Seal of Command (represents auto with Command)
}

--=========================================================================================
-- GCD AND HASTE CALCULATIONS
--=========================================================================================

-- Get the current GCD duration accounting for spell haste
-- This mirrors the WeakAura logic using Flash of Light's cast time
st.rotation.get_gcd_duration = function()
    -- Use Flash of Light (spell 19750) to determine GCD
    -- GetSpellInfo returns: name, rank, icon, castTime, minRange, maxRange, spellID
    local _, _, _, castTime, _, _, _ = GetSpellInfo(19750)

    local gcd = 1.5  -- Default base GCD

    if castTime then
        -- castTime is in milliseconds
        gcd = castTime / 1000
    end

    -- Clamp GCD between 1.0 and 1.5 seconds
    if gcd >= 1.5 then
        gcd = 1.5
    elseif gcd < 1.0 then
        gcd = 1.0
    end

    return gcd
end

-- Calculate haste percentage (how much GCD is reduced from base)
st.rotation.get_haste_amount = function()
    local gcd = st.rotation.get_gcd_duration()
    -- Haste amount = base GCD (1.5) minus current GCD
    -- e.g., if GCD is 1.3s, haste amount is 0.2
    return 1.5 - gcd
end

--=========================================================================================
-- ROTATION CALCULATION
-- Determines the optimal rotation based on attack speed and haste
-- Logic ported directly from the Rotation Twister WeakAura
--=========================================================================================

st.rotation.calculate_rotation = function()
    -- Check cache to avoid recalculating every frame
    local current_time = GetTime()
    if st.rotation.cache_rotation and (current_time - st.rotation.cache_time) < st.rotation.cache_interval then
        return st.rotation.cache_rotation
    end

    local attackSpeed = UnitAttackSpeed("player") or 3.0
    local gcd = st.rotation.get_gcd_duration()
    local haste = st.rotation.get_haste_amount()

    local rotation = nil

    -- Rotation selection logic from WeakAura (in priority order)
    if attackSpeed > 2.6 then
        -- Slowest weapons: simple 1 twist per CS cycle
        rotation = "1/2"

    elseif attackSpeed >= math.max(1.9, 2 * gcd - 0.35) and haste > 0.1 then
        -- Fast enough with high haste: 2 twists per CS cycle
        rotation = "2/3"

    elseif attackSpeed >= 2.4 or (attackSpeed >= 2.3 and haste > 0.05) then
        -- Medium speed: complex pattern with late CS
        rotation = "2/2/5"

    elseif attackSpeed >= math.max(1.5, 1.5 * gcd + 0.05) and haste > 0.1 then
        -- Fast with high haste: 2 twists in 4 actions
        rotation = "2/4"

    elseif attackSpeed >= 1.9 then
        -- Standard rotation: 1 twist per 3 actions
        rotation = "1/3"

    elseif attackSpeed >= (gcd + 0.07) then
        -- Very fast: ride Blood between twists
        rotation = "2/5_blood"

    elseif attackSpeed > 1.0 then
        -- Extremely fast: ride Command for procs
        rotation = "2/5_command"

    elseif attackSpeed >= 0.01 then
        -- Ludicrous speed (full Bloodlust + haste): just ride Blood and CS
        rotation = "2007"
    end

    -- Update cache
    st.rotation.cache_time = current_time
    st.rotation.cache_rotation = rotation

    return rotation
end

--=========================================================================================
-- ROTATION STATE MANAGEMENT
--=========================================================================================

-- Update the current rotation and sequence
st.rotation.update_rotation = function()
    local new_rotation = st.rotation.calculate_rotation()

    if new_rotation ~= st.rotation.current_rotation then
        -- Rotation changed (haste buff, new weapon, etc.)
        st.rotation.last_rotation = st.rotation.current_rotation
        st.rotation.current_rotation = new_rotation
        st.rotation.sequence = st.rotation.sequences[new_rotation] or {}

        -- Reset to step 1 when rotation changes
        st.rotation.current_step = 1

        if st.debug then
            print("Rotation changed to: " .. tostring(new_rotation))
        end

        -- Trigger UI update
        if st.bar and st.bar.update_rotation_display then
            st.bar.update_rotation_display()
        end
    end
end

-- Get the current action (what player should do now)
st.rotation.get_current_action = function()
    if not st.rotation.sequence or #st.rotation.sequence == 0 then
        return nil
    end

    local step = st.rotation.current_step
    if step < 1 then step = 1 end
    if step > #st.rotation.sequence then step = 1 end

    return st.rotation.sequence[step]
end

-- Get the next action after current
st.rotation.get_next_action = function()
    if not st.rotation.sequence or #st.rotation.sequence == 0 then
        return nil
    end

    local next_step = st.rotation.current_step + 1
    if next_step > #st.rotation.sequence then
        next_step = 1
    end

    return st.rotation.sequence[next_step]
end

-- Advance to the next step in the rotation
st.rotation.advance_step = function()
    if not st.rotation.sequence or #st.rotation.sequence == 0 then
        return
    end

    st.rotation.current_step = st.rotation.current_step + 1

    -- Loop back to start if sequence complete
    if st.rotation.current_step > #st.rotation.sequence then
        st.rotation.current_step = 1
    end

    if st.debug then
        print("Rotation step: " .. st.rotation.current_step .. " (" .. tostring(st.rotation.get_current_action()) .. ")")
    end

    -- Trigger UI update
    if st.bar and st.bar.update_rotation_display then
        st.bar.update_rotation_display()
    end
end

-- Reset rotation to step 1 (typically called after CS)
st.rotation.reset_to_start = function()
    st.rotation.current_step = 1

    if st.debug then
        print("Rotation reset to step 1")
    end

    -- Trigger UI update
    if st.bar and st.bar.update_rotation_display then
        st.bar.update_rotation_display()
    end
end

-- Called when Crusader Strike is cast
st.rotation.on_cs_cast = function()
    -- CS always means we go to step 2 (after CS in sequence)
    -- Unless this IS the first step (CS), then we advance normally
    local current_action = st.rotation.get_current_action()

    if current_action == "cs" or current_action == "cs_late" then
        st.rotation.advance_step()
    else
        -- CS cast out of expected order - reset to after CS
        -- Find the first non-CS step
        st.rotation.current_step = 2
        if st.rotation.current_step > #st.rotation.sequence then
            st.rotation.current_step = 1
        end
    end

    -- Start tracking CS cooldown
    st.rotation.cs_on_cooldown = true
    st.rotation.cs_cooldown_start = GetTime()
    st.rotation.cs_cooldown_remaining = st.rotation.cs_cooldown_duration
end

-- Called when a swing completes (auto-attack)
st.rotation.on_swing_complete = function()
    local current_action = st.rotation.get_current_action()

    -- Check if current expected action is an auto-attack
    if current_action == "blood_auto" or current_action == "cmd_auto" then
        st.rotation.advance_step()
    end
end

-- Called when a twist is detected (seal changed near swing)
st.rotation.on_twist = function()
    local current_action = st.rotation.get_current_action()

    if current_action == "twist" then
        st.rotation.advance_step()
    end
end

--=========================================================================================
-- CRUSADER STRIKE COOLDOWN TRACKING
--=========================================================================================

st.rotation.track_cs_cooldown = function()
    -- Check CS cooldown using GetSpellCooldown
    local start, duration = GetSpellCooldown(35395)  -- Crusader Strike

    if start and start > 0 and duration and duration > 0 then
        st.rotation.cs_on_cooldown = true
        st.rotation.cs_cooldown_remaining = (start + duration) - GetTime()
        st.rotation.cs_cooldown_start = start
        st.rotation.cs_cooldown_duration = duration

        if st.rotation.cs_cooldown_remaining < 0 then
            st.rotation.cs_cooldown_remaining = 0
            st.rotation.cs_on_cooldown = false
        end
    else
        st.rotation.cs_on_cooldown = false
        st.rotation.cs_cooldown_remaining = 0
    end
end

-- Check if CS is ready to use
st.rotation.is_cs_ready = function()
    st.rotation.track_cs_cooldown()
    return not st.rotation.cs_on_cooldown
end

--=========================================================================================
-- FRAME UPDATE (called each frame)
--=========================================================================================

st.rotation.on_update = function(elapsed)
    -- Update rotation calculation (will use cache if recent)
    st.rotation.update_rotation()

    -- Update CS cooldown tracking
    if st.rotation.cs_on_cooldown then
        st.rotation.cs_cooldown_remaining = st.rotation.cs_cooldown_remaining - elapsed
        if st.rotation.cs_cooldown_remaining <= 0 then
            st.rotation.cs_on_cooldown = false
            st.rotation.cs_cooldown_remaining = 0
        end
    end
end

--=========================================================================================
-- UTILITY FUNCTIONS
--=========================================================================================

-- Get the icon texture for an action type
st.rotation.get_action_texture = function(action)
    if not action then return nil end

    local spell_id = st.rotation.spell_textures[action]
    if spell_id then
        return GetSpellTexture(spell_id)
    end

    return nil
end

-- Get display text for current rotation
st.rotation.get_rotation_text = function()
    if st.rotation.current_rotation then
        return st.rotation.display_names[st.rotation.current_rotation] or st.rotation.current_rotation
    end
    return ""
end

-- Get description text for current rotation
st.rotation.get_rotation_description = function()
    if st.rotation.current_rotation then
        return st.rotation.descriptions[st.rotation.current_rotation] or ""
    end
    return ""
end

-- Check if rotation helper should be active
st.rotation.should_show = function()
    local db = ST.db.profile

    -- Check if feature is enabled
    if not db.rotation_helper_enabled then
        return false
    end

    -- Only show when bar would be visible
    if st.bar and st.bar.should_show_bar and not st.bar.should_show_bar() then
        return false
    end

    -- Only show if we have a valid rotation
    if not st.rotation.current_rotation then
        return false
    end

    return true
end

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then print('-- Parsed rotation.lua module correctly') end

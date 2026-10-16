--=========================================================================================
-- Module for Paladin-specific behaviours
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
local LCG = LibStub("LibCustomGlow-1.0")
local LSM = LibStub("LibSharedMedia-3.0")
-- Cross-client API wrappers (see compat.lua).
local api = st.api
local get_tab = st.utils.convert_lookup_table

--=========================================================================================
-- LibClassicDurations (next-action guide swipe durations)
--=========================================================================================
-- The library is Classic Era / TBC Anniversary ONLY: LibClassicDurations/core.lua line 20
-- returns before it creates the library unless WOW_PROJECT_ID is WOW_PROJECT_CLASSIC or
-- WOW_PROJECT_BURNING_CRUSADE_CLASSIC, so on WotLK, Titanforge, Cata, Mists, Retail and
-- WoW Forever the silent LibStub form below yields nil. That is why it is always fetched
-- silently and why no behaviour may depend on it existing: every duration it supplies has
-- a hardcoded fallback (SEAL_FALLBACK_DURATION below, the display constants in
-- nextaction_ui.lua for the spell cooldowns).
-- It is also combat-log driven, so it has its own failure modes even where it loads: it
-- only knows an aura once it has seen the application (nothing is tracked before the first
-- combat-log event after Register, and a seal that is up at login stays unknown until it
-- is re-cast), it returns nil for any aura missing from its spell table (Seal of Blood /
-- Seal of the Martyr are not in it), and the durations it reports are 30 s for the seals
-- it does know. Untracked -> nil -> the fallback, on every family.
local LCD = LibStub("LibClassicDurations", true)
local lcd_aura_duration = LCD and LCD.GetAuraDurationByUnit

-- Vanilla/TBC seal duration: the archived build's own fallback
-- (docs/swedge/SwedgeTimer_TBC/player.lua seal_1_duration / seal_2_duration).
local SEAL_FALLBACK_DURATION = 30

-- Length of a tracked aura in seconds, or nil when the library is absent, has not tracked
-- the aura, or reports something unusable. Method cached at load; no per-call allocation
-- and no string work (the aura name comes from the aura loop, not from a lookup).
local function get_tracked_aura_duration(unit, spell_id, spell_name)
    if not lcd_aura_duration then
        return nil
    end
    -- pcall because the library is vendored code on a client family this addon only
    -- supports indirectly: a failure here must degrade to the fallback, never error.
    local ok, duration = pcall(lcd_aura_duration, LCD, unit, spell_id, nil, spell_name)
    if not ok or type(duration) ~= "number" or duration <= 0
        or duration > SEAL_FALLBACK_DURATION * 2 then
        -- The upper bound rejects a nonsense length (no seal is longer than an hour);
        -- the caller then falls back to SEAL_FALLBACK_DURATION.
        return nil
    end
    return duration
end

--=========================================================================================
-- Spell data
--=========================================================================================
-- Seals: every rank id per classic family, because the active aura keeps the id of the
-- rank that was cast. On Wrath the seals were consolidated to a single rank which is
-- contained in each list, so Wrath behaviour is unchanged. Rank data per the archived
-- TBC/Forever builds.
local soc_ids = get_tab({
    20375, 20915, 20918, 20919, 20920, 27170
})
local sov_ids = get_tab({
    31801, 348704
})
local sol_ids = get_tab({
    20165, 20347, 20348, 20349, 27160
})
local sow_ids = get_tab({
    20166, 20356, 20357, 27166
})
local sor_ids = get_tab({
    21084, 20154, 20287, 20288, 20289, 20290, 20291, 20292, 20293, 27155
})
local soj_ids = get_tab({
    20164, 31895
})
-- Seal of Blood / Seal of the Martyr
local sob_ids = get_tab({
    31892, 348700
})
-- Seal of the Crusader
local sotc_ids = get_tab({
    21082, 20162, 20305, 20306, 20307, 20308, 27158
})

-- Art of War (WotLK proc)
local aow_id = 59578

-- Exorcism, all ranks.
local exorcism_ids = get_tab({
    879, 5614, 5615, 10312, 10313, 10314, 27138, 48800, 48801
})

function ST.PALADIN.post_init(self)
    self.exo_on_cooldown = false
    self.exo_cooldown_time = api.GetSpellBaseCooldown(879) / 1000
    -- Twist state (port of the archived build's player.lua state fields).
    self.twist_attempt_pending = false
    self.twist_impossible = false
    self.twist_sound_played = false
    self.twist_extra_attacks_pending = 0
    self.twist_active_seals_count = 0

    -- Parse auras after the state above so the seal count sticks.
    self.PALADIN.on_aura_change(self)

    -- Twist window band and success text (the visuals frames exist by now).
    self.PALADIN.setup_twist_visuals(self)

    -- Next Action Guide (rotation prompt): builds its own UIParent frame and needs
    -- the pure st.nextaction engine module; guarded so a flavor without the guide
    -- files stays inert.
    if st.nextaction_ui then
        st.nextaction_ui.init(self)
    end

    -- LibClassicDurations: registering is what makes it track auras (it hooks
    -- COMBAT_LOG_EVENT_UNFILTERED on its own frame), and without it every
    -- GetAuraDurationByUnit read returns nil. Done here rather than at file load so it
    -- runs after login with the library's playerClass-dependent branches valid, and so
    -- a paladin-only addon never turns it on for other classes' clients. No-op off
    -- Classic Era / TBC Anniversary, where the library never registered itself (see the
    -- header block). pcall keeps a library-side failure from breaking post_init: the
    -- guide then simply keeps using its hardcoded seal duration.
    if lcd_aura_duration and type(LCD.Register) == "function" then
        pcall(LCD.Register, LCD, addon_name)
    end

    -- Twist Practice: builds its own UIParent frames and the pure-engine bridge;
    -- guarded so a flavor without the practice files stays inert.
    if st.practice_ui then
        st.practice_ui.init(self)
    end
end

function ST.PALADIN.on_spellcast_succeeded(self, unit_target, cast_guid, spell_id)
    -- Track exo casts
    if exorcism_ids[spell_id] ~= nil then
        self.exo_on_cooldown = true
        self.PALADIN.process_aow(self)
        C_Timer.After(self.exo_cooldown_time, function()
            self.exo_on_cooldown = false
            self.PALADIN.process_aow(self)
        end)
    end
end


--=========================================================================================
-- Twist Practice: seal-state mirror for the simulation
--=========================================================================================
function ST.PALADIN.practice_sync(self)
    -- Replaces the aura-derived seal state with the practice simulation's state while a
    -- session runs (practice_ui's bridge calls this; parse_seals branches into it too).
    -- The sim seals never expire on their own as far as the guide is concerned, so no
    -- expiry input is provided; every other seal flag belongs to the real auras and is
    -- cleared so stale state cannot leak into the practice display.
    local sim = st.practice_ui and st.practice_ui.sim
    if not sim then
        return self.twist_active_seals_count or 0
    end
    self.has_soc = sim.active_seals["command"] == true
    self.has_sob = sim.active_seals["blood"] == true
    self.has_sor = sim.active_seals["crusader"] == true
    self.has_sov = false
    self.has_sol = false
    self.has_sow = false
    self.has_soj = false
    self.has_sotc = false
    self.has_aow = false
    self.soc_expires = nil
    self.sob_expires = nil
    self.twist_active_seals_count = sim.n_active_seals or 0
    return self.twist_active_seals_count
end

function ST.PALADIN.parse_seals(self)
    -- Refresh seal and Art of War flags from the player's auras; returns the
    -- active-seal count. Shared by on_aura_change and the twist swing path
    -- (which must not restart the AoW glow on every swing).
    -- While a Twist Practice session runs the simulation owns the seal state, so the
    -- real auras must not clobber it.
    if st.practice_ui and st.practice_ui.is_active() then
        return self.PALADIN.practice_sync(self)
    end
    self.has_aow = false
    self.has_soc = false
    self.has_sov = false
    self.has_sol = false
    self.has_sow = false
    self.has_sor = false
    self.has_soj = false
    self.has_sob = false
    self.has_sotc = false
    -- Seal expiry timestamps in seconds (next-action guide seal input). Reset so a
    -- dropped seal cannot leave a stale value behind.
    self.soc_expires = nil
    self.sob_expires = nil
    -- Swipe lengths for the guide's seal icons, from LibClassicDurations where that
    -- library exists and tracks the aura (Classic Era / TBC Anniversary only), else nil
    -- so the guide falls back to its own constant. Reset with the expiries for the same
    -- reason: they describe the same aura, so neither may outlive it.
    self.soc_duration = nil
    self.sob_duration = nil

    -- Iterate all player auras
    local i = 1
    while true do
        local name, _, _, _, _, expiration_time, _, _, _, spell_id = api.UnitAura("player", i)
        if name == nil then
            break
        end
        -- Seals
        if soc_ids[spell_id] ~= nil then
            self.has_soc = true
            self.soc_expires = expiration_time
            -- The library keys its records by the rank that was cast, which is the aura
            -- id right here (the same reason soc_ids carries every rank).
            self.soc_duration = get_tracked_aura_duration("player", spell_id, name)
        end
        if sov_ids[spell_id] ~= nil then
            self.has_sov = true
        end
        if sol_ids[spell_id] ~= nil then
            self.has_sol = true
        end
        if sow_ids[spell_id] ~= nil then
            self.has_sow = true
        end
        if sor_ids[spell_id] ~= nil then
            self.has_sor = true
        end
        if soj_ids[spell_id] ~= nil then
            self.has_soj = true
        end
        if sob_ids[spell_id] ~= nil then
            self.has_sob = true
            self.sob_expires = expiration_time
            self.sob_duration = get_tracked_aura_duration("player", spell_id, name)
        end
        if sotc_ids[spell_id] ~= nil then
            self.has_sotc = true
        end

        -- Art of War
        if spell_id == aow_id then
            self.has_aow = true
        end

        i = i + 1
    end

    -- Count active seals (twist attempts need 2 simultaneously active).
    local count = 0
    if self.has_soc then count = count + 1 end
    if self.has_sov then count = count + 1 end
    if self.has_sol then count = count + 1 end
    if self.has_sow then count = count + 1 end
    if self.has_sor then count = count + 1 end
    if self.has_soj then count = count + 1 end
    if self.has_sob then count = count + 1 end
    if self.has_sotc then count = count + 1 end
    self.twist_active_seals_count = count
    return count
end

function ST.PALADIN.on_aura_change(self)
    self.PALADIN.parse_seals(self)
    -- Finally set the bar color
    self:set_bar_color("mainhand")
end

function ST.PALADIN.glow_start(self)
    local db_class = self:get_class_table()
    local frame = self:get_bar_frame("mainhand")
    local db_hand = self:get_hand_table("mainhand")
    local thickness = db_hand.border_width
    if thickness == 0 then
        thickness = 1
    end
    LCG.PixelGlow_Start(frame,
        {self:convert_color(db_class.aow_glow_color)},
        db_class.aow_glow_nlines,
        db_class.aow_glow_freq,
        db_class.aow_glow_line_length,
        thickness,
        0,
        0,
        -- db_class.aow_glow_offset,
        -- db_class.aow_glow_offset,
        false
    )
end

function ST.PALADIN.glow_stop(self)
    local frame = self:get_bar_frame("mainhand")
    LCG.PixelGlow_Stop(frame)
end

function ST.PALADIN.process_aow(self)
    local db = self:get_class_table()
    if not self.has_aow then
        self.PALADIN.glow_stop(self)
        return
    end
    if not db.use_aow_glow then
        self.PALADIN.glow_stop(self)
        return
    end
    if db.require_exo_ready then
        if self.exo_on_cooldown then
            self.PALADIN.glow_stop(self)
            return
        end
    end
    self.PALADIN.glow_start(self)
end

function ST.PALADIN.set_bar_color(self, hand)
    -- Returns true if any special setting was applied to let the parent func know 
    -- to revert to default behaviour.
    -- Will set appropriate colors for seals and AoW procs if requested.
    local db_class = self:get_class_table()
    local frame = self:get_visuals_frame(hand)

    -- Art of War glow
    self.PALADIN.process_aow(self)

    -- Seal colors    
    if db_class.use_seal_colors then
        if self.has_soc then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.soc_color)
            )
            return true
        end
        if self.has_sov then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.sov_color)
            )
            return true
        end
        if self.has_sol then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.sol_color)
            )
            return true
        end
        if self.has_sow then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.sow_color)
            )
            return true
        end
        if self.has_sor then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.sor_color)
            )
            return true
        end
        if self.has_soj then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.soj_color)
            )
            return true
        end
        if self.has_sob then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.sob_color)
            )
            return true
        end
        if self.has_sotc then
            frame.bar:SetVertexColor(
                self:convert_color(db_class.sotc_color)
            )
            return true
        end
    end

    return false
end

function ST.PALADIN.on_combat_log_unfiltered(self, _, timestamp, event, hide_caster, source_guid, source_name, source_flags, source_raid_flags, dest_guid, dest_name, dest_flags, dest_raid_flags, ...)
    -- Twist Practice: the simulation owns the twist state while a session runs, so real
    -- combat-log events must not arm attempts or consume procs (they would also fight
    -- the 0.05 s seal mirror for control of the same flags).
    if st.practice_ui and st.practice_ui.is_active() then
        return
    end
    -- Only our own actions matter for twisting.
    if source_guid ~= UnitGUID("player") then
        return
    end

    if event == "SPELL_EXTRA_ATTACKS" then
        -- The amount field is the 4th payload argument after the destination
        -- fields (spellId, spellName, spellSchool, amount).
        local amount = tonumber(select(4, ...)) or 1
        self.twist_extra_attacks_pending = (self.twist_extra_attacks_pending or 0) + amount
        return
    end

    if event == "SWING_DAMAGE" or event == "SWING_MISSED" then
        if (self.twist_extra_attacks_pending or 0) > 0 then
            self.twist_extra_attacks_pending = self.twist_extra_attacks_pending - 1
            return
        end
        -- Refresh seals without the full aura-change side effects (the AoW glow
        -- must not restart on every swing).
        local n = self.PALADIN.parse_seals(self)
        local twist_seal_active = st.twist.is_twist_seal_active(self.has_soc, self.has_sor)
        local attempt = st.twist.detect_twist_attempt(false, twist_seal_active, n)
        if attempt then
            self.twist_attempt_pending = true
            self.twist_sound_played = false
            self.PALADIN.on_twist_attempt(self)
        else
            self.twist_attempt_pending = false
            self.twist_sound_played = false
        end
        return
    end

    if event == "SPELL_DAMAGE" then
        local sid = select(1, ...)
        if type(sid) == "number" then
            if st.twist.detect_twist_success(self.twist_attempt_pending == true, sid) then
                self.twist_attempt_pending = false
                self.PALADIN.on_successful_twist(self)
            end
        end
        return
    end
end

--=========================================================================================
-- Seal twisting: window band and success feedback visuals
--=========================================================================================
-- Twist feedback sounds: key -> file map ported from the archived build's bar.lua
-- (69 entries; the archive's map carries the same key set). The keys are saved option
-- values (never rename them). DEVIATION from the archive: the archived build shipped
-- these files under Sounds\ while the live addon ships them under Media\Sounds\
-- (same file names), so every path below points at the live layout.
local twist_sounds = {
    -- Original sounds
    ["pop"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\pop.ogg",
    ["bubble-pop"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\bubble-pop.ogg",
    ["swoosh"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\swoosh.ogg",
    ["whoopee"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\whoopee.ogg",
    -- Instruments
    ["AcousticGuitar"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\AcousticGuitar.ogg",
    ["Brass"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Brass.mp3",
    ["Drums"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Drums.ogg",
    ["Glass"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Glass.mp3",
    ["SynthChord"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\SynthChord.ogg",
    ["TempleBellHuge"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\TempleBellHuge.ogg",
    ["Xylophone"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Xylophone.ogg",
    -- Alerts & UI
    ["AirHorn"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\AirHorn.ogg",
    ["BikeHorn"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\BikeHorn.ogg",
    ["ErrorBeep"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\ErrorBeep.ogg",
    ["RingingPhone"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\RingingPhone.ogg",
    ["RobotBlip"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\RobotBlip.ogg",
    ["WarningSiren"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\WarningSiren.ogg",
    ["WaterDrop"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\WaterDrop.ogg",
    -- Animals
    ["Bleat"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Bleat.ogg",
    ["CatMeow2"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\CatMeow2.ogg",
    ["ChickenAlarm"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\ChickenAlarm.ogg",
    ["CowMooing"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\CowMooing.ogg",
    ["GoatBleating"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\GoatBleating.ogg",
    ["KittenMeow"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\KittenMeow.ogg",
    ["RoaringLion"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\RoaringLion.ogg",
    ["RoosterChickenCalls"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\RoosterChickenCalls.ogg",
    ["SheepBleat"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\SheepBleat.ogg",
    -- Combat & Action
    ["Bloodlust"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Bloodlust.ogg",
    ["BatmanPunch"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\BatmanPunch.ogg",
    ["Blast"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Blast.ogg",
    ["BoxingArenaSound"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\BoxingArenaSound.ogg",
    ["DoubleWhoosh"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\DoubleWhoosh.ogg",
    ["SharpPunch"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\SharpPunch.ogg",
    ["Shotgun"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Shotgun.ogg",
    -- Cartoon & Fun
    ["Applause"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Applause.ogg",
    ["BananaPeelSlip"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\BananaPeelSlip.ogg",
    ["CartoonVoiceBaritone"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\CartoonVoiceBaritone.ogg",
    ["CartoonWalking"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\CartoonWalking.ogg",
    ["HeartbeatSingle"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\HeartbeatSingle.ogg",
    ["SqueakyToyShort"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\SqueakyToyShort.ogg",
    ["SquishFart"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\SquishFart.ogg",
    ["TadaFanfare"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\TadaFanfare.ogg",
    -- Voice Callouts
    ["Adds"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Adds.ogg",
    ["Boss"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Boss.ogg",
    ["DontRelease"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\DontRelease.ogg",
    ["Empowered"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Empowered.ogg",
    ["Focus"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Focus.ogg",
    ["Idiot"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Idiot.ogg",
    ["OhNo"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\OhNo.ogg",
    ["Protected"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Protected.ogg",
    ["Release"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Release.ogg",
    ["RunAway"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\RunAway.ogg",
    ["Spread"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Spread.ogg",
    ["Stack"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Stack.ogg",
    ["Taunt"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Taunt.ogg",
    -- Shapes (Markers)
    ["Circle"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Circle.ogg",
    ["Cross"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Cross.ogg",
    ["Diamond"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Diamond.ogg",
    ["Left"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Left.ogg",
    ["Moon"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Moon.ogg",
    ["Right"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Right.ogg",
    ["Skull"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Skull.ogg",
    ["Square"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Square.ogg",
    ["Star"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Star.ogg",
    ["Triangle"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Triangle.ogg",
    -- Misc
    ["Next"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Next.ogg",
    ["Portal"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Portal.ogg",
    ["Switch"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Switch.ogg",
    ["Torch"] = "Interface\\AddOns\\SwedgeTimer\\Media\\Sounds\\Torch.ogg",
}

-- Plays a twist feedback sound by option key (fallback_key covers a nil choice);
-- no-op when the key has no entry (unknown/renamed key) or the client offers no
-- PlaySoundFile, so a mismatched setting can never error.
local function play_twist_sound(db, key, fallback_key)
    local path = twist_sounds[key or fallback_key]
    if path == nil or PlaySoundFile == nil then
        return
    end
    PlaySoundFile(path, db.sound_channel or "Master")
end

-- Fallback colours used whenever a db key is missing (or malformed), so the visuals
-- are safe to run even before the options lane lands the matching keys.
local TWIST_MARKER_COLOR = {255, 255, 255, 0.35}
local TWIST_TWISTING_COLOR = {179, 26, 153, 1.0}
local TWIST_CANT_COLOR = {212, 212, 3, 1.0}
local TWIST_SUCCESS_COLOR = {90, 255, 90, 1.0}

-- Returns db[key] when it looks like a colour table, otherwise the fallback.
local function twist_color(db, key, fallback)
    local c = db[key]
    if type(c) == "table" and #c >= 4 then
        return c
    end
    return fallback
end

function ST.PALADIN.get_twist_window_time_before_swing(self)
    -- Twist window duration (seconds before the swing lands): the 400 ms baseline
    -- plus the configured padding, per the archived build's helper. The lag used
    -- here is calibrated from the player's raw world latency with the twist lag
    -- settings (the archived build's lag_calibrated_ms), not the deadzone
    -- calibration, so the two features stay independent.
    local db = self:get_class_table()
    local raw_ms = (self.latency and self.latency.world_ms) or 0
    local lag_ms = raw_ms * (db.lag_multiplier or 1.4) + (db.lag_offset or 15)
    return st.twist.get_window_seconds(
        db.twist_padding_mode, lag_ms, db.twist_window_padding_ms)
end

function ST.PALADIN.setup_twist_visuals(self)
    -- Creates the twist widgets on the mainhand visuals frame. Called once from
    -- post_init, when the frames exist.
    local vf = self:get_visuals_frame("mainhand")
    if not vf or vf.twist_band then
        return
    end

    -- Window band: overlays the final (rightmost) part of the swing.
    local band = vf:CreateTexture(nil, "OVERLAY")
    band:SetDrawLayer("OVERLAY", -2)
    band:SetPoint("TOPRIGHT", vf, "TOPRIGHT", 0, 0)
    -- White base texture; the per-frame updater tints via SetVertexColor.
    band:SetColorTexture(1, 1, 1, 1)
    band:Hide()
    vf.twist_band = band

    -- Success text, centred above the bar.
    local text = vf:CreateFontString(nil, "OVERLAY")
    text:SetPoint("BOTTOM", vf, "TOP", 0, 6)
    text:SetJustifyH("CENTER")
    local db = self:get_class_table()
    local db_hand = self:get_hand_table("mainhand")
    local font_path = LSM:Fetch("font", db_hand.text_font) or STANDARD_TEXT_FONT
    text:SetFont(font_path, db.twist_success_text_size or 24, "OUTLINE")
    text:Hide()
    vf.twist_text = text
end

function ST.PALADIN.on_bar_update(self, hand)
    -- Per-frame twist visuals, called from ST:onupdate_common via the generic class
    -- hook. Deliberately cheap and nil-safe: gates on the mainhand bar, the twist
    -- widgets and the configured options.
    if hand ~= "mainhand" then
        return
    end
    local hand_state = self[hand]
    if not (hand_state and hand_state.anchor_frame) then
        return
    end
    -- Next Action Guide (mainhand only): driven before the twist-only gates below so
    -- it also runs on Mainline-code clients (WoW Forever shows the guide but not the
    -- twist band). It never gates on st.is_mainline itself; swing activity decides.
    -- Settings that rebuild the frame (scale/position/lock) are applied when the class
    -- options change; the display toggles are read live by the UI.
    local gdb = self:get_class_table()
    if gdb.nextaction_icon_size ~= self.guide_ui_icon_size
        or gdb.nextaction_x ~= self.guide_ui_x
        or gdb.nextaction_y ~= self.guide_ui_y
        or gdb.nextaction_locked ~= self.guide_ui_locked then
        self.guide_ui_icon_size = gdb.nextaction_icon_size
        self.guide_ui_x = gdb.nextaction_x
        self.guide_ui_y = gdb.nextaction_y
        self.guide_ui_locked = gdb.nextaction_locked
        if st.nextaction_ui then
            st.nextaction_ui.apply_settings(self)
        end
    end
    if st.nextaction_ui then
        st.nextaction_ui.on_bar_update(self, hand)
    end
    local vf = self:get_visuals_frame(hand)
    if not vf or not vf.twist_band then
        return
    end
    if st.is_mainline then
        -- The swing engine never runs here, so the twist visuals stay hidden.
        vf.twist_band:Hide()
        if vf.twist_text then
            vf.twist_text:Hide()
            vf.twist_text:SetText("")
        end
        return
    end

    local db = self:get_class_table()
    local now = GetTime()

    -- Success text: fade out over its final 0.3 s, then clear it.
    local text = vf.twist_text
    if text then
        local success_until = self.twist_success_until or 0
        if db.twist_enabled ~= false
            and db.twist_feedback_enabled ~= false
            and db.twist_success_text_enabled ~= false
            and now < success_until then
            text:SetAlpha(math.min(1, (success_until - now) / 0.3))
            text:Show()
        elseif text:IsShown() then
            text:Hide()
            text:SetText("")
        end
    end

    local band = vf.twist_band
    local d = self[hand]
    if db.twist_enabled == false
        or db.twist_marker_enabled == false
        or not st.twist.is_twist_seal_active(self.has_soc, self.has_sor)
        or not (d and d.speed and d.speed > 0 and d.ends_at and d.start)
        or d.is_full then
        self.twist_impossible = false
        band:Hide()
        return
    end

    -- Geometry: the band covers the swing's final twist-window fraction.
    local w, h = self:get_bar_visuals_width_and_height(hand)
    local window = self.PALADIN.get_twist_window_time_before_swing(self)
    local frac = math.min(1, window / d.speed)
    band:SetWidth(max(1, w * frac))
    band:SetHeight(h)

    -- Tint priority: success flash, impossible, attempt flash, armed (pulsing),
    -- inside the window, idle.
    local color, alpha
    local remaining = math.max(0, d.ends_at - now)
    -- Twist window sound cue (archive parity, off by default): fires once the bar is
    -- inside the window, latched so the per-frame tick cannot repeat it; the
    -- swing-landing handler clears the latch for the next swing.
    if db.twist_sound_enabled and remaining <= window and self.twist_sound_played ~= true then
        play_twist_sound(db, db.twist_sound_choice, "pop")
        self.twist_sound_played = true
    end
    local gcd_remaining = (self.gcd and self.gcd.expires
        and math.max(0, self.gcd.expires - now)) or 0
    -- Pass raw world latency: the twist lag settings calibrate it inside the
    -- helper (the archived build's lag_calibrated_ms), so the deadzone
    -- calibration is not applied twice.
    local lag_ms = (self.latency and self.latency.world_ms) or 0
    local impossible = st.twist.is_twist_impossible(
        db.lag_detection_enabled, remaining, gcd_remaining, lag_ms,
        db.lag_multiplier, db.lag_offset, window)
    self.twist_impossible = impossible

    if db.twist_feedback_enabled ~= false
        and db.twist_success_text_enabled ~= false
        and (self.twist_success_until or 0) > now then
        color = twist_color(db, "twist_success_text_color", TWIST_SUCCESS_COLOR)
        alpha = 0.55
    elseif impossible then
        color = twist_color(db, "twist_color_cant", TWIST_CANT_COLOR)
        alpha = 0.5
    elseif db.twist_feedback_enabled ~= false
        and (self.twist_attempt_until or 0) > now then
        color = twist_color(db, "twist_color_twisting", TWIST_TWISTING_COLOR)
        alpha = 0.55
    elseif (self.twist_active_seals_count or 0) >= 2 then
        color = twist_color(db, "twist_color_twisting", TWIST_TWISTING_COLOR)
        alpha = 0.35 + 0.15 * math.sin(now * 8)
    elseif remaining <= window then
        color = twist_color(db, "twist_marker_color", TWIST_MARKER_COLOR)
        alpha = 0.30
    else
        color = twist_color(db, "twist_marker_color", TWIST_MARKER_COLOR)
        alpha = 0.15
    end
    band:SetVertexColor(self:convert_color(color, alpha))
    band:Show()
end

function ST.PALADIN.on_twist_attempt(self)
    -- Called when a twist attempt registers (two seals active on the swing).
    local db = self:get_class_table()
    -- Attempt sound is its own toggle and stays independent of the visual feedback
    -- gates below (archive parity: the archived build played it at the top of its
    -- attempt handler, ahead of the glow effect).
    if db.twist_success_sound_enabled then
        play_twist_sound(db, db.twist_success_sound_choice, "TadaFanfare")
    end
    if db.twist_enabled == false or db.twist_feedback_enabled == false then
        return
    end
    self.twist_attempt_until = GetTime() + 0.25
end

function ST.PALADIN.on_successful_twist(self)
    -- Called when a Command proc confirms a successful twist.
    local db = self:get_class_table()
    if db.twist_enabled == false
        or db.twist_feedback_enabled == false
        or db.twist_success_text_enabled == false then
        return
    end
    self.twist_success_until = GetTime() + (db.twist_success_text_duration or 1.5)
    local vf = self.mainhand.anchor_frame and self:get_visuals_frame("mainhand")
    local text = vf and vf.twist_text
    if text then
        text:SetText("Successful TWIST!")
        text:SetTextColor(
            self:convert_color(twist_color(db, "twist_success_text_color", TWIST_SUCCESS_COLOR))
        )
        text:SetAlpha(1)
        text:Show()
    end
end

function ST.PALADIN.on_combat_exit(self)
    -- Combat-scoped twist state: orphaned extra attacks must not carry into the
    -- next fight (they would suppress its first twist attempts).
    self.twist_extra_attacks_pending = 0
    self.twist_attempt_pending = false
    -- Combat-scoped next-action guide state: the guide may already be hidden when
    -- the fight ends, so it cannot rely on its own display tick to reset these.
    self.guide_melee_count = 0
    self.guide_waiting_judgement = false
end

--=========================================================================================
-- Next Action Guide: live inputs for the pure st.nextaction engine
--=========================================================================================
-- The engine (nextaction.lua) is pure and reads these frozen input names:
--   speed, swing_remaining, G, gcd_remaining, twist_window, reaction, cs_remaining,
--   judge_remaining, seal, cs_delay_max, waiting_judgement, melee_count, mana_pct,
--   creature_type, filler_remaining
-- filler_remaining is one number (the chosen filler's own cooldown remaining) or nil
-- (unknown on this client). The engine also accepts the optional inputs
-- gcd_before_swing and both mana thresholds; this gather fills them.
-- cs_duration / judge_duration are display-only and are ignored by the engine: the full
-- length (seconds) of the last real CS / Judgement cooldown the client reported, or nil
-- when none has been seen. nextaction_ui.lua uses them for its cooldown swipes, falling
-- back to its hardcoded constants. The seal icons' equivalent lengths are not engine
-- inputs at all: they ride on self.soc_duration / self.sob_duration (the seal mirror).

-- One reused input table: no per-frame allocations on the guide tick.
ST.PALADIN.guide_inputs = {}

-- Localized filler spell names, resolved lazily (name-based cooldown lookups see
-- whatever rank the player knows, unlike a fixed rank id).
local filler_name_consecration
local filler_name_exorcism

-- Live cooldown remaining (seconds) for a spell id or name, handling the client's GCD
-- echo: GetSpellCooldown reports whichever cooldown ends later, so a real ability
-- cooldown shows its full duration while a shorter ability cooldown inside a running
-- GCD reports the GCD's ~1.5 s instead. With latch_key the last real cooldown end is
-- remembered on the addon (the archive's rule), so the true remaining time survives
-- the echo window.
-- With duration_key the client-reported LENGTH of that real cooldown is latched next to
-- the expiry (duration_key holds seconds, never an end time). The guide's cooldown
-- swipes need the length, not just the end: hardcoding it breaks on any client whose
-- Crusader Strike / Judgement cooldown differs from the archived build's. Latching it
-- here (rather than in the UI) keeps it paired with the expiry it belongs to, so both
-- always describe the same cooldown. LibClassicDurations cannot help here: it is
-- aura-based and knows nothing about spell cooldowns.
local function get_guide_cooldown_remaining(self, spell, latch_key, duration_key)
    local now = api.get_time()
    local start_time, duration = api.GetSpellCooldown(spell)
    if not start_time or not duration or duration == 0 then
        return 0
    end
    if duration > 1.51 then
        if latch_key then
            self[latch_key] = start_time + duration
        end
        if duration_key then
            -- A real cooldown: api.GetSpellCooldown has already normalised both shapes
            -- (classic start/duration, Mainline the SpellCooldownInfo table) and the
            -- >1.51 branch means this is not the GCD echo.
            self[duration_key] = duration
        end
        local remaining = start_time + duration - now
        if remaining < 0 then
            remaining = 0
        end
        return remaining
    end
    -- GCD echo: the real cooldown (if any) ends before this GCD does.
    if not latch_key then
        return 0
    end
    local remaining = (self[latch_key] or 0) - now
    if remaining <= 0 then
        return 0
    end
    local echo_end = start_time + duration - now
    if remaining > echo_end then
        remaining = echo_end
    end
    return remaining
end

-- Player mana percentage and the target's (localized) creature type for the filler
-- kind choice; the engine owns the Undead/Demon name table.
local function get_guide_mana_pct()
    local power_max = UnitPowerMax and UnitPowerMax("player") or 0
    if type(power_max) == "number" and power_max > 0 then
        local power = (UnitPower and UnitPower("player")) or 0
        if type(power) == "number" then
            return power / power_max * 100
        end
    end
    return 0
end

local function get_guide_creature_type()
    if UnitExists and UnitExists("target") then
        return UnitCreatureType and UnitCreatureType("target")
    end
    return nil
end

function ST.PALADIN.gather_guide_inputs(self)
    local na = st.nextaction
    local now = api.get_time()
    local d = self.mainhand
    local gcd = self.gcd
    local db = self:get_class_table()
    local inputs = self.PALADIN.guide_inputs

    -- Swing state and clock (seconds). ends_at and the GCD/aura stamps all live in
    -- the GetTime() domain, which api.get_time() shares, so the comparisons hold.
    inputs.speed = (d and d.speed) or 0
    inputs.swing_remaining = math.max(0, ((d and d.ends_at) or now) - now)
    inputs.G = self:get_spell_gcd_duration()
    inputs.gcd_remaining = (gcd and gcd.expires and math.max(0, gcd.expires - now)) or 0
    inputs.twist_window = self.PALADIN.get_twist_window_time_before_swing(self)
    inputs.reaction = (db.nextaction_reaction_time_ms or 100) / 1000
    inputs.cs_delay_max = (db.nextaction_cs_max_delay_ms or 1700) / 1000

    -- Active seal for the decision tree ("soc" | "sob" | "none"; Command's
    -- remaining time guards the engine's reseal branch).
    if na then
        inputs.seal = na.get_seal_state(self.has_soc, self.has_sob,
            self.soc_expires and (self.soc_expires - now))
    else
        inputs.seal = "none"
    end

    -- Crusader Strike / Judgement cooldowns. The archive's rules: an unknown CS
    -- talent means the engine must never see CS available (999 s), and Judgement
    -- needs no latch of its own. The swipe LENGTHs ride along in cs_duration /
    -- judge_duration (display-only; see the input-contract comment above) and are read
    -- after the calls, so they describe the cooldown this same tick reported.
    if na and na.CS_SPELL_ID then
        if api.is_spell_known(na.CS_SPELL_ID) then
            inputs.cs_remaining = get_guide_cooldown_remaining(self, na.CS_SPELL_ID,
                "guide_cs_expires", "guide_cs_duration")
        else
            inputs.cs_remaining = 999
        end
        inputs.judge_remaining = na.JUDGEMENT_SPELL_ID
            and get_guide_cooldown_remaining(self, na.JUDGEMENT_SPELL_ID, nil,
                "guide_judge_duration") or 0
    else
        inputs.cs_remaining = 999
        inputs.judge_remaining = 0
    end
    -- Read after both lookups so a length latched on this very tick is the one the
    -- guide draws. nil simply means "nothing observed yet": the display falls back to
    -- its own constant.
    inputs.cs_duration = self.guide_cs_duration
    inputs.judge_duration = self.guide_judge_duration

    -- Filler availability. The engine consumes one cooldown value: the remaining
    -- time of the filler it would pick. That pick is mirrored here from the data the
    -- engine itself uses (its own target-type table; the mana thresholds passed
    -- below), so the two sides always agree. A nil value means the spell is unknown
    -- on this client, i.e. the archive's known=false.
    inputs.melee_count = self.guide_melee_count or 0
    inputs.mana_pct = get_guide_mana_pct()
    inputs.creature_type = get_guide_creature_type()
    inputs.gcd_before_swing = self:get_gcd_time_before_swing_seconds("mainhand")
    inputs.mana_consecration_threshold = db.nextaction_filler_mana_consecration or 35
    inputs.mana_exorcism_threshold = db.nextaction_filler_mana_exorcism or 30
    local consecration_remaining
    local exorcism_remaining
    if na then
        if filler_name_consecration == nil and na.CONSECRATION_SPELL_ID then
            filler_name_consecration = api.GetSpellInfo(na.CONSECRATION_SPELL_ID)
        end
        if filler_name_consecration then
            consecration_remaining = get_guide_cooldown_remaining(self, filler_name_consecration)
        end
        if filler_name_exorcism == nil and na.EXORCISM_SPELL_ID then
            filler_name_exorcism = api.GetSpellInfo(na.EXORCISM_SPELL_ID)
        end
        if filler_name_exorcism then
            exorcism_remaining = get_guide_cooldown_remaining(self, filler_name_exorcism)
        end
    end
    inputs.filler_remaining = nil
    if na and inputs.creature_type and na.exorcism_target_types
        and na.exorcism_target_types[inputs.creature_type] then
        if inputs.mana_pct > inputs.mana_exorcism_threshold then
            inputs.filler_remaining = exorcism_remaining
        end
    elseif na and inputs.mana_pct > inputs.mana_consecration_threshold then
        inputs.filler_remaining = consecration_remaining
    end

    -- Judgement-wait carry from the engine's previous output (kept by the display).
    inputs.waiting_judgement = self.guide_waiting_judgement and true or false
    return inputs
end

if st.debug then st.utils.print_msg('-- Parsed classes/paladin.lua module correctly (twist)') end

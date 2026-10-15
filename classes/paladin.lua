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


function ST.PALADIN.parse_seals(self)
    -- Refresh seal and Art of War flags from the player's auras; returns the
    -- active-seal count. Shared by on_aura_change and the twist swing path
    -- (which must not restart the AoW glow on every swing).
    self.has_aow = false
    self.has_soc = false
    self.has_sov = false
    self.has_sol = false
    self.has_sow = false
    self.has_sor = false
    self.has_soj = false
    self.has_sob = false
    self.has_sotc = false

    -- Iterate all player auras
    local i = 1
    while true do
        local name, _, _, _, _, _, _, _, _, spell_id = api.UnitAura("player", i)
        if name == nil then
            break
        end
        -- Seals
        if soc_ids[spell_id] ~= nil then
            self.has_soc = true
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
end

if st.debug then st.utils.print_msg('-- Parsed classes/paladin.lua module correctly (twist)') end

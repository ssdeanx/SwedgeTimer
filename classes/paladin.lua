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

-- See compat.lua: restricted (secret) reads must degrade, never error. Exact no-op
-- where the probe is absent (classic clients).
local is_secret = issecretvalue or function()
    return false
end

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
-- Seal of Righteousness on Forever (Twist of Light twist seal): UNCONFIRMED.
-- The beta guides name the seal but publish no spell id, so this table is
-- deliberately EMPTY until GetSpellInfo confirms an id in-client (the hunter
-- Summon Hawk / Sniper Shot discipline: an empty table resolves nothing, so
-- the latch below stays inert rather than guessing). The classic sor_ids
-- above still latch 21084 on Forever; if Forever's Righteousness carries a
-- new id, has_sor stays down until that id is confirmed into this table.
-- Plug-in point: add the confirmed Forever rank id(s) here.
local sor_forever_ids = get_tab({
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

-- Era twist seal: on the Era family the engine's twist-seal ("sob") position is
-- Seal of Righteousness — Seal of Blood does not exist on Era. 21084 is its
-- rank-1 id (archived docs/swedge/SwedgeTimer_TBC/st_data.lua:74). Every other
-- family keeps the Blood id, so nothing changes outside the Era family.
-- Computed once at load (compat.lua runs before the class modules, and every
-- offline harness loads it first too).
local ERA_TWIST_SEAL_ID = 21084
local is_era_family = st.family == "ERA"
local twist_seal_icon_id = is_era_family and ERA_TWIST_SEAL_ID or 31892

-- Forever family flag + guide twist-seal id (WoW Forever / Camelot 1.60.x):
-- Twist of Light alternates Seal of Command / Seal of Righteousness after
-- auto attacks and Judgement no longer consumes seals
-- (docs/research/forever_beta.md — all UNCONFIRMED beta information with no
-- confirmed spell ids, so Twist of Light and Holy Strike are NOT probed and
-- can never prompt). The guide's twist-seal slot and twist overlay show
-- Righteousness on Forever (same slot, same key, Era texture); the standalone
-- seal icons above stay Era-only (their Forever mapping is unverified).
local is_forever_family = st.family == "FOREVER"
local guide_twist_seal_id = (is_era_family or is_forever_family) and ERA_TWIST_SEAL_ID or 31892

-- Wrath FCFS display (family WRATH only): no seal twisting exists there, so the
-- twist-seal guide slot ("sob") carries Divine Storm and the execute slot ("how")
-- carries Holy Wrath instead. Slot KEYS, order, count and display fields are
-- frozen (the contract pins eight); only the texture-source ids move, and only on
-- Wrath. The rank-1 fallbacks below paint the icons until post_init repoints them
-- at the resolved ranks (confirm both ids in-client).
local is_wrath_family = st.family == "WRATH"
local WRATH_DS_ICON_FALLBACK = 53385
local WRATH_HW_ICON_FALLBACK = 48817
local guide_sob_spell_id = is_wrath_family and WRATH_DS_ICON_FALLBACK or guide_twist_seal_id
local guide_how_spell_id = is_wrath_family and WRATH_HW_ICON_FALLBACK or 24275

-- Art of War (WotLK proc)
local aow_id = 59578

-- Exorcism, all ranks.
local exorcism_ids = get_tab({
    879, 5614, 5615, 10312, 10313, 10314, 27138, 48800, 48801
})

function ST.PALADIN.post_init(self)
    self.exo_on_cooldown = false
    local exo_base = api.GetSpellBaseCooldown(879) / 1000
    -- Mainline-code clients have no GetSpellBaseCooldown (compat degrades to 0); without
    -- the fallback require_exo_ready would report Exorcism always ready on Forever.
    self.exo_cooldown_time = (type(exo_base) == "number" and exo_base > 0) and exo_base or 15
    -- Twist state (port of the archived build's player.lua state fields).
    self.twist_attempt_pending = false
    self.twist_impossible = false
    self.twist_sound_played = false
    self.twist_glow_until = 0
    self.twist_extra_attacks_pending = 0
    self.twist_active_seals_count = 0

    -- Parse auras after the state above so the seal count sticks.
    self.PALADIN.on_aura_change(self)

    -- Twist window band and success text (the visuals frames exist by now).
    self.PALADIN.setup_twist_visuals(self)

    -- Next Action Guide (rotation prompt): builds its own UIParent frame and needs
    -- the pure st.nextaction engine module; guarded so a flavor without the guide
    -- files stays inert. The FCFS slot textures resolve first (above), so the
    -- frame builds its icons from the final ids.
    ST.PALADIN.resolve_guide_icons()
    if st.nextaction_ui then
        st.nextaction_ui.init(self)
    end

    -- LibClassicDurations: registering is what makes it track auras (it hooks
    -- COMBAT_LOG_EVENT_UNFILTERED on its own frame), and without it every
    -- GetAuraDurationByUnit read returns nil. Done here rather than at file load so it
    -- runs after login (post_init waits for the swing-engine / range libraries, so a seal
    -- applied before that simply is not tracked yet and the guide uses its constant until
    -- the first tracked application) and so a paladin-only addon never turns it on for
    -- other classes' clients. No-op off Classic Era / TBC Anniversary, where the library
    -- never registered itself (see the header block). pcall keeps a library-side failure
    -- from breaking post_init: the guide then keeps using its hardcoded seal duration.
    if lcd_aura_duration and type(LCD.Register) == "function" then
        pcall(LCD.Register, LCD, addon_name)
    end

    -- Twist Practice: builds its own UIParent frames and the pure-engine bridge;
    -- guarded so a flavor without the practice files stays inert.
    if st.practice_ui then
        st.practice_ui.init(self)
    end

    -- Cooldown HUD: builds its own UIParent frames (out of combat, deferred and
    -- retried via the per-frame hook under lockdown) from this class's HUD_SLOTS and
    -- the provider below; guarded so a flavor without hud.lua stays inert. Other
    -- classes would call st.hud.init(self) from their own post_init the same way.
    if st.hud then
        st.hud.init(self)
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
    self.sor_expires = nil
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
    -- dropped seal cannot leave a stale value behind. sor_* backs the
    -- twist-seal swipe on Era (Righteousness there; see is_era_family above).
    self.soc_expires = nil
    self.sob_expires = nil
    self.sor_expires = nil
    -- Swipe lengths for the guide's seal icons, from LibClassicDurations where that
    -- library exists and tracks the aura (Classic Era / TBC Anniversary only), else nil
    -- so the guide falls back to its own constant. Reset with the expiries for the same
    -- reason: they describe the same aura, so neither may outlive it.
    self.soc_duration = nil
    self.sob_duration = nil
    self.sor_duration = nil

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
        -- Forever's own Righteousness ranks (empty until confirmed, see above)
        -- latch the same flag, so a new Forever id degrades to silent rather
        -- than latching the wrong seal. Gated on the family so every other
        -- family ignores the table entirely.
        if sor_ids[spell_id] ~= nil
            or (is_forever_family and sor_forever_ids[spell_id] ~= nil) then
            self.has_sor = true
            self.sor_expires = expiration_time
            -- Same rank-keyed lookup as Command above (sor_ids carries every rank).
            self.sor_duration = get_tracked_aura_duration("player", spell_id, name)
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
        -- Archive parity: the attempt arms on n_active_seals == 2 alone. The extra
        -- seal-discipline gate wrongly disarmed Blood+Crusader windows.
        local attempt = st.twist.detect_twist_attempt(false, true, n)
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

-- Published for the rotation-text sound widgets (widgets.lua prefers the class
-- module's published map over its debug-upvalue bridge; same keys, same paths).
ST.PALADIN.twist_sounds = twist_sounds

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

-- Fallback glow colour (the archive's {0.0, 1.0, 0.0, 0.8} converted up), used
-- whenever the db key is missing or malformed.
local TWIST_GLOW_COLOR = {0, 255, 0, 0.8}

--=========================================================================================
-- Judgement marker line, seal icons, twist-success glow (archived TBC bar visuals)
--=========================================================================================
-- Judgement (the rotation timing cue, archive bar.lua:1750-1786): the spell id the
-- guide already uses, the marker colour (the archive's {0.9, 0.9, 0.01, 1.0}
-- converted up to the codebase's 0-255 storage) and the line thickness. Only the
-- enable is an option (judgement_marker_enabled); colour/width are constants.
local JUDGEMENT_SPELL_ID = 20271
local JUDGEMENT_MARKER_COLOR = {230, 230, 3, 1.0}
local JUDGEMENT_MARKER_WIDTH = 2

-- Standalone seal icons (archive bar.lua:826-910): the two twist seals get one slot
-- each, Command first. The swipe length falls back to the archived 30 s seal
-- duration where LibClassicDurations tracks nothing. Only the enable is an option
-- (seal_icons_enabled); the attached position, the gap and the timer size are
-- constants. The icons sit right of the mainhand bar at bar height.
local SEAL_ICON_SLOTS = {
    { spell_id = 20375 },
    -- The second slot tracks the twist seal: Blood everywhere but Era, where it
    -- is Righteousness (twist_seal_icon_id above).
    { spell_id = twist_seal_icon_id },
}
local SEAL_ICON_GAP = 4
local SEAL_ICON_TEXCROP = {0.07, 0.93, 0.07, 0.93}
local SEAL_TIMER_TEXT_SIZE = 16

-- One reused seal-state pair: update_seal_icons runs every frame, so no table
-- work happens on the tick (the HUD provider contract's no-allocation rule).
local SEAL_LIVE = {
    { active = false, expires = nil, full = nil },
    { active = false, expires = nil, full = nil },
}

-- Twist-success glow (archive bar.lua:551-616, Pixel at minimum): the key lets the
-- attempt glow coexist with the Art of War glow on the same bar frame; the line
-- count, frequency and thickness are the archive's Pixel parameters. Only the
-- enable, colour and duration are options.
local TWIST_GLOW_KEY = "TwistSuccess"
local TWIST_GLOW_LINES = 8
local TWIST_GLOW_FREQUENCY = 0.25
local TWIST_GLOW_THICKNESS = 2

function ST.PALADIN.update_judgement_marker(self, hand)
    -- Judgement timing line (archive bar.lua:1750-1786): drawn at the swing
    -- position where Judgement comes off cooldown, i.e. remaining_cd into the
    -- elapsed swing, exactly like the archive's (remaining + elapsed) / speed
    -- offset. Shown only while Judgement is on a real cooldown that ends inside
    -- this swing (durations at or below 1.5 s are the GCD echo, not a cooldown)
    -- and a seal worth judging is up.
    local vf = self:get_visuals_frame(hand)
    local marker = vf and vf.judgement_marker
    if not marker then
        return
    end
    local now = api.get_time()
    local db = self:get_class_table()
    local d = self[hand]
    local offset
    if db.judgement_marker_enabled ~= false
        and not st.is_retail
        and d and d.speed and d.speed > 0 and d.ends_at and d.start
        and not d.is_full
        and (self.has_sob or self.has_sor or self.has_sov or self.has_soj) then
        local swing_remaining = math.max(0, d.ends_at - now)
        local start_time, duration = api.GetSpellCooldown(JUDGEMENT_SPELL_ID)
        if duration and duration > 1.51 then
            local cd_remaining = start_time + duration - now
            if cd_remaining > 0 and cd_remaining < swing_remaining then
                local elapsed = d.speed - swing_remaining
                local w = self:get_bar_visuals_width_and_height(hand)
                offset = ((cd_remaining + elapsed) / d.speed) * w
            end
        end
    end
    if offset == nil then
        if marker:IsShown() then
            marker:Hide()
        end
        return
    end
    local _, h = self:get_bar_visuals_width_and_height(hand)
    marker:SetStartPoint("TOPLEFT", offset, 0)
    marker:SetEndPoint("TOPLEFT", offset, h * -1)
    marker:Show()
end

function ST.PALADIN.update_seal_icons(self, hand)
    -- Standalone seal icons (archive bar.lua:919-1119, condensed): one slot per
    -- twist seal with a reversed cooldown swipe and a remaining-time text. The
    -- swipe runs from the aura expiry over the tracked (or fallback) full
    -- length; a seal without a usable expiry still shows its icon, exactly like
    -- the archive's texture-before-cooldown order.
    local vf = self:get_visuals_frame(hand)
    local set = vf and vf.seal_icons
    if not set then
        return
    end
    local now = api.get_time()
    local db = self:get_class_table()
    local enabled = db.seal_icons_enabled ~= false and not st.is_retail
    -- The icon size tracks the bar height; re-layout once when it changes.
    local _, h = self:get_bar_visuals_width_and_height(hand)
    if h and h ~= set.size then
        set.size = h
        set.frame:SetSize(h * 2 + 2, h)
        for i = 1, #set.slots do
            local slot = set.slots[i]
            slot.icon:SetSize(h, h)
            slot.icon:SetPoint("TOPLEFT", (i - 1) * (h + 2), 0)
            slot.cooldown:SetSize(h, h)
            slot.cooldown:SetPoint("TOPLEFT", slot.icon, "TOPLEFT", 0, 0)
        end
    end
    local live = SEAL_LIVE
    live[1].active, live[1].expires, live[1].full = self.has_soc, self.soc_expires, self.soc_duration
    -- Era tracks the twist seal (Righteousness) in the second slot; every other
    -- family keeps Blood there.
    if is_era_family then
        live[2].active, live[2].expires, live[2].full = self.has_sor, self.sor_expires, self.sor_duration
    else
        live[2].active, live[2].expires, live[2].full = self.has_sob, self.sob_expires, self.sob_duration
    end
    local any_shown = false
    for i = 1, #set.slots do
        local slot = set.slots[i]
        local state = live[i]
        local icon_texture
        if enabled and state.active then
            icon_texture = select(3, api.GetSpellInfo(slot.spell_id))
        end
        if icon_texture == nil then
            if slot.icon:IsShown() then
                slot.icon:Hide()
            end
            slot.icon_key = nil
            if slot.cd_start ~= nil then
                slot.cd_start, slot.cd_full = nil, nil
                slot.cooldown:SetCooldown(0, 0)
                slot.cooldown:Hide()
            end
            if slot.timer:IsShown() then
                slot.timer:Hide()
            end
            slot.text_value = nil
        else
            any_shown = true
            if slot.icon_key ~= icon_texture then
                slot.icon_key = icon_texture
                slot.icon:SetTexture(icon_texture)
            end
            if not slot.icon:IsShown() then
                slot.icon:Show()
            end
            local full = state.full or SEAL_FALLBACK_DURATION
            local start = (type(state.expires) == "number") and (state.expires - full) or nil
            if start ~= nil and state.expires > now then
                if slot.cd_start ~= start or slot.cd_full ~= full then
                    slot.cd_start, slot.cd_full = start, full
                    slot.cooldown:SetCooldown(start, full)
                end
                if not slot.cooldown:IsShown() then
                    slot.cooldown:Show()
                end
                local quantised = math.floor(state.expires - now)
                if slot.text_value ~= quantised then
                    slot.text_value = quantised
                    slot.timer:SetText(string.format("%d", state.expires - now))
                end
                if not slot.timer:IsShown() then
                    slot.timer:Show()
                end
            else
                if slot.cd_start ~= nil then
                    slot.cd_start, slot.cd_full = nil, nil
                    slot.cooldown:SetCooldown(0, 0)
                end
                if slot.cooldown:IsShown() then
                    slot.cooldown:Hide()
                end
                if slot.timer:IsShown() then
                    slot.timer:Hide()
                end
                slot.text_value = nil
            end
        end
    end
    if any_shown then
        if not set.frame:IsShown() then
            set.frame:Show()
        end
    elseif set.frame:IsShown() then
        set.frame:Hide()
    end
end

function ST.PALADIN.twist_glow_start(self)
    -- Starts the twist-success Pixel glow on the mainhand bar (archive
    -- bar.lua:573-584, via the HUD's LibCustomGlow call shape). Nil-safe
    -- pre-construction: without the bar frame there is nothing to glow.
    local frame = self.mainhand.anchor_frame and self:get_bar_frame("mainhand")
    if not frame then
        return
    end
    local db = self:get_class_table()
    LCG.PixelGlow_Start(frame,
        {self:convert_color(twist_color(db, "twist_success_glow_color", TWIST_GLOW_COLOR))},
        TWIST_GLOW_LINES,
        TWIST_GLOW_FREQUENCY,
        nil,
        TWIST_GLOW_THICKNESS,
        0,
        0,
        false,
        TWIST_GLOW_KEY
    )
end

function ST.PALADIN.twist_glow_stop(self)
    local frame = self.mainhand.anchor_frame and self:get_bar_frame("mainhand")
    if not frame then
        return
    end
    LCG.PixelGlow_Stop(frame, TWIST_GLOW_KEY)
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

    -- Judgement marker line (archive bar.lua:270-272): a full-height line drawn at
    -- the swing position where Judgement comes off cooldown, like the GCD markers.
    -- Positioned per frame by update_judgement_marker below.
    local judge = vf:CreateLine()
    judge:SetDrawLayer("OVERLAY", -1)
    judge:SetThickness(JUDGEMENT_MARKER_WIDTH)
    judge:SetColorTexture(self:convert_color(JUDGEMENT_MARKER_COLOR))
    judge:Hide()
    vf.judgement_marker = judge

    -- Standalone seal icons (archive bar.lua:826-910): one slot per twist seal with
    -- a cooldown swipe and a timer text, attached right of the mainhand bar.
    -- Positioned per frame by update_seal_icons below.
    self.PALADIN.setup_seal_icons(self)
end

function ST.PALADIN.setup_seal_icons(self)
    -- Builds the seal-icon container on the mainhand bar frame. Called once from
    -- setup_twist_visuals. Nil-safe pre-construction: without the bar frame there
    -- is nothing to attach to.
    local vf = self:get_visuals_frame("mainhand")
    local bar_frame = self.mainhand.anchor_frame and self:get_bar_frame("mainhand")
    if not vf or not bar_frame or vf.seal_icons then
        return
    end
    local _, h = self:get_bar_visuals_width_and_height("mainhand")
    local size = h or 16
    local container = CreateFrame("Frame", addon_name .. "SealIcons", bar_frame)
    container:SetSize(size * 2 + 2, size)
    container:SetPoint("LEFT", bar_frame, "RIGHT", SEAL_ICON_GAP, 0)
    container:Hide()
    local set = { frame = container, size = size, slots = {} }
    for i = 1, #SEAL_ICON_SLOTS do
        local slot = { spell_id = SEAL_ICON_SLOTS[i].spell_id }
        local icon = container:CreateTexture(nil, "ARTWORK")
        icon:SetSize(size, size)
        icon:SetPoint("TOPLEFT", (i - 1) * (size + 2), 0)
        icon:SetTexCoord(SEAL_ICON_TEXCROP[1], SEAL_ICON_TEXCROP[2],
            SEAL_ICON_TEXCROP[3], SEAL_ICON_TEXCROP[4])
        icon:Hide()
        slot.icon = icon
        local cooldown = CreateFrame("Cooldown", nil, container, "CooldownFrameTemplate")
        cooldown:SetSize(size, size)
        cooldown:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        cooldown:SetReverse(true)
        if cooldown.SetHideCountdownNumbers then
            cooldown:SetHideCountdownNumbers(true)
        end
        cooldown:Hide()
        cooldown:Hide()
        slot.cooldown = cooldown
        -- The timer text needs its own frame above the cooldown swipe, exactly
        -- like the archive (bar.lua:863-871): a plain frame cannot out-draw a
        -- Cooldown otherwise.
        local timer_frame = CreateFrame("Frame", nil, container)
        timer_frame:SetSize(size, size)
        timer_frame:SetPoint("TOPLEFT", icon, "TOPLEFT", 0, 0)
        timer_frame:SetFrameLevel(cooldown:GetFrameLevel() + 1)
        local timer = timer_frame:CreateFontString(nil, "OVERLAY")
        timer:SetPoint("CENTER", 0, 0)
        timer:SetJustifyH("CENTER")
        timer:SetShadowColor(0, 0, 0, 1)
        timer:SetShadowOffset(2, -2)
        timer:SetFont(STANDARD_TEXT_FONT, SEAL_TIMER_TEXT_SIZE, "THICKOUTLINE")
        timer:Hide()
        slot.timer = timer
        slot.cd_start, slot.cd_full, slot.text_value = nil, nil, nil
        set.slots[i] = slot
    end
    vf.seal_icons = set
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
    -- Cooldown HUD: retries a lockdown-deferred creation and picks layout option
    -- changes up between the HUD driver's ticks (the row itself ticks on its own
    -- driver frame, so this is cheap). Deliberately not gated on st.is_mainline: the
    -- Forever client must show the HUD, and the Retail stand-in simply never swings.
    if st.hud then
        st.hud.on_bar_update(self, hand)
    end
    local vf = self:get_visuals_frame(hand)
    if not vf or not vf.twist_band then
        return
    end
    if st.is_retail then
        -- Retail has no swing engine (the stand-in never reports a swing), so the twist
        -- visuals stay hidden there. WoW Forever is Mainline-code but DOES run the Forever
        -- swing engine, so it must keep the band and its text.
        vf.twist_band:Hide()
        if vf.twist_text then
            vf.twist_text:Hide()
            vf.twist_text:SetText("")
        end
        -- The judgement line and seal icons share the band's Retail gate (their
        -- updaters hide them through the same st.is_retail rule).
        self.PALADIN.update_judgement_marker(self, hand)
        self.PALADIN.update_seal_icons(self, hand)
        return
    end

    local db = self:get_class_table()
    local now = api.get_time()

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
    -- Judgement marker, seal icons and glow expiry run on every mainhand tick,
    -- independent of the twist-band gates below: a Blood-only swing still times
    -- Judgement and still shows its seals.
    self.PALADIN.update_judgement_marker(self, hand)
    self.PALADIN.update_seal_icons(self, hand)
    if (self.twist_glow_until or 0) > 0
        and (db.twist_success_glow_enabled == false or now >= self.twist_glow_until) then
        self.twist_glow_until = 0
        self.PALADIN.twist_glow_stop(self)
    end
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
    -- The archive cued the sound 0.20 s BEFORE the window (audio lead-in), not at it.
    if db.twist_sound_enabled and remaining <= window + 0.20 and self.twist_sound_played ~= true then
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
    -- Twist-success glow (archive bar.lua:568-615): fires on the attempt, ahead of
    -- the visual feedback gates below, like the sound above. The per-frame hook
    -- stops it after twist_success_glow_duration.
    if db.twist_success_glow_enabled ~= false then
        self.PALADIN.twist_glow_start(self)
        self.twist_glow_until = api.get_time() + (db.twist_success_glow_duration or 0.4)
    end
    if db.twist_enabled == false or db.twist_feedback_enabled == false then
        return
    end
    self.twist_attempt_until = api.get_time() + 0.25
end

function ST.PALADIN.on_successful_twist(self)
    -- Called when a Command proc confirms a successful twist.
    local db = self:get_class_table()
    if db.twist_enabled == false
        or db.twist_feedback_enabled == false
        or db.twist_success_text_enabled == false then
        return
    end
    self.twist_success_until = api.get_time() + (db.twist_success_text_duration or 1.5)
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
    -- Combat-scoped twist-glow state: a glow started on the killing swing must not
    -- leak its stop into the next fight's first attempt. The stop touches bar
    -- visuals, so it carries the init guard (wiring_check check 3); the state
    -- reset is safe anywhere.
    self.twist_glow_until = 0
    if self.interfaces_are_initialised then
        self.PALADIN.twist_glow_stop(self)
    end
    -- Combat-scoped next-action guide state: the guide may already be hidden when
    -- the fight ends, so it cannot rely on its own display tick to reset these.
    self.guide_melee_count = 0
    self.guide_waiting_judgement = false
    -- Combat-scoped JotC scan cache: a new fight re-scans the new target.
    self.guide_jotc_at = nil
    self.guide_jotc_value = nil
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
-- gcd_before_swing and both mana thresholds, plus the TBC opt-ins
-- judge_require_fit (always true here), jotc_remaining (the target JotC scan
-- below, nil when untracked) and target_count (1 when a target is known, nil
-- otherwise — no WoW API counts enemies; that presence rule is the plug-in
-- point a future target counter upgrades), plus the Era opt-ins era (true on
-- the Era family), forever (true on the Forever family; Twist of Light
-- alternates Command/Righteousness there, UNCONFIRMED), cs_known (the
-- client's Crusader Strike spell-book answer), target_health_pct (target hp
-- percent, nil when unknown) and how_remaining (Hammer of Wrath cooldown
-- remaining, nil when unknown); this gather fills them (the Era/Forever ones
-- only on their family, nil elsewhere).
-- FCFS inputs (Wrath FCFS + SoD Exodin; nil on every other family, which the
-- archived tree ignores as unknown names): fcfs_mode ("wrath" | "sod"),
-- ds_remaining (Divine Storm cooldown, nil while unresolved/unknown),
-- cons_remaining / exo_remaining (the filler mirror's agreed cooldowns),
-- hw_remaining (Wrath Holy Wrath cooldown, nil elsewhere) and has_aow (live Art
-- of War flag, gating the Wrath Exorcism). The FCFS engine (evaluate_fcfs)
-- consumes them; the provider dispatch selects the engine by fcfs_mode.
-- cs_duration / judge_duration are display-only and are ignored by the engine: the full
-- length (seconds) of the last real CS / Judgement cooldown the client reported, or nil
-- when none has been seen. nextaction_ui.lua uses them for its cooldown swipes, falling
-- back to the slot's swipe_duration (the archive's constants). The seal slots' swipe
-- fields (soc_expires / soc_duration / sob_expires / sob_duration below) are the same
-- kind of display-only inputs: they carry the seal mirror's aura expiry and the length
-- LibClassicDurations reported (nil where it does not track the aura).

-- One reused input table: no per-frame allocations on the guide tick.
ST.PALADIN.guide_inputs = {}

-- Localized filler spell names, resolved lazily (name-based cooldown lookups see
-- whatever rank the player knows, unlike a fixed rank id).
local filler_name_consecration
local filler_name_exorcism

-- Judgement of the Crusader ranks, all TBC ranks (the debuff lasts 10 s per
-- LibClassicDurations/classAbilities.lua line 837). The guide's
-- Crusader-priority cue refreshes it ahead of expiry (the engine owns the lead
-- time); a nil reading means untracked and keeps the archived Blood-only cue.
local jotc_ids = get_tab({
    21183, 20188, 20300, 20301, 20302, 20303
})

-- Target-debuff re-scan throttle (seconds): the JotC scan below stays off the
-- hot path. Stale by at most this long across target swaps; the engine's
-- refresh lead absorbs it.
local JOTC_RESCAN_INTERVAL = 0.5

-- Target JotC time left (seconds) for the guide's Crusader-priority cue, or nil
-- when the target carries no JotC (or there is no target / no reading).
-- Best-effort like every other aura loop here: a secret entry truncates the
-- scan at the first unreadable row. The 40-row cap is the TBC debuff-slot
-- count and only bounds a misbehaving client.
local function get_guide_jotc_remaining(self, now)
    if self.guide_jotc_at and (now - self.guide_jotc_at) < JOTC_RESCAN_INTERVAL then
        return self.guide_jotc_value
    end
    self.guide_jotc_at = now
    self.guide_jotc_value = nil
    if UnitExists and UnitExists("target") then
        local best = nil
        local i = 1
        while i <= 40 do
            local name, _, _, _, _, expiration, _, _, _, spell_id =
                api.UnitAura("target", i, "HARMFUL")
            if name == nil then
                break
            end
            if spell_id and jotc_ids[spell_id] and expiration and expiration > 0 then
                local remaining = expiration - now
                if best == nil or remaining < best then
                    best = remaining
                end
            end
            i = i + 1
        end
        self.guide_jotc_value = best
    end
    return self.guide_jotc_value
end

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
    -- Through compat, never bare: the modern clients can strip these globals.
    local power_max = api.UnitPowerMax("player")
    if type(power_max) == "number" and power_max > 0 then
        local power = api.UnitPower("player")
        if type(power) == "number" then
            return power / power_max * 100
        end
    end
    return 0
end

-- UnitCreatureType returns a localized string on every family; a restricted (secret)
-- reading cannot be indexed into the target-type table, so it degrades to unknown (nil)
-- - the engine then falls back to the Consecration suggestion, exactly like a locale
-- whose name is missing from the table.
local function read_creature_type()
    if not UnitCreatureType then
        return nil
    end
    local ctype = UnitCreatureType("target")
    if is_secret(ctype) then
        return nil
    end
    return ctype
end

local function get_guide_creature_type()
    if UnitExists and UnitExists("target") then
        return read_creature_type()
    end
    return nil
end

-- Hammer of Wrath ranks (archived docs/swedge/SwedgeTimer_TBC/st_data.lua:95-96;
-- Era knows the pre-TBC ranks). The gather resolves whichever rank this client
-- knows and reads its cooldown — the same IsSpellKnown-gate pattern as the
-- Crusader Strike talent check above. Resolved once and cached (ranks are never
-- unlearned); a miss retries at most every few seconds so level-ups resolve.
local how_ids = { 24275, 24274, 24239, 27180 }
local how_spell_id = nil
local how_retry_at = 0
local HOW_RESOLVE_RETRY_S = 5

local function resolve_how_spell_id(now)
    if how_spell_id then
        return how_spell_id
    end
    if now < how_retry_at then
        return nil
    end
    how_retry_at = now + HOW_RESOLVE_RETRY_S
    for i = 1, #how_ids do
        if api.is_spell_known(how_ids[i]) then
            how_spell_id = how_ids[i]
            return how_spell_id
        end
    end
    return nil
end

-- Hammer of Wrath cooldown remaining for the Era execute cue, or nil when the
-- spell is unknown on this client. No latch: without one the GCD echo reads as
-- ready (0), which is exactly the cue's question (HoW itself off cooldown?).
local function get_guide_how_remaining(self, now)
    local known_id = resolve_how_spell_id(now)
    if not known_id then
        return nil
    end
    return get_guide_cooldown_remaining(self, known_id)
end

-- Divine Storm ranks for the FCFS branches (Wrath FCFS #3, SoD Exodin #3):
-- 53385 is the Wrath rank-1 id; the SoD rune reuses it when the book says so
-- (confirm both in-client). Same resolve-once/retry discipline as HoW above; nil
-- while unresolved, which withholds DS in the engine (never a wrong prompt).
local ds_ids = { 53385 }
local ds_spell_id = nil
local ds_retry_at = 0
local DS_RESOLVE_RETRY_S = 5

local function resolve_ds_spell_id(now)
    if ds_spell_id then
        return ds_spell_id
    end
    if now < ds_retry_at then
        return nil
    end
    ds_retry_at = now + DS_RESOLVE_RETRY_S
    for i = 1, #ds_ids do
        if api.is_spell_known(ds_ids[i]) then
            ds_spell_id = ds_ids[i]
            return ds_spell_id
        end
    end
    return nil
end

-- Holy Wrath ranks for the Wrath FCFS "if eligible" cue (Era HoW keeps how_ids
-- above): Wrath ranks first, then the classic/TBC ranks every family knows. Same
-- discipline; nil while unresolved, which withholds Holy Wrath.
local hw_ids = { 48817, 48816, 27139, 10318, 2812 }
local hw_spell_id = nil
local hw_retry_at = 0

local function resolve_hw_spell_id(now)
    if hw_spell_id then
        return hw_spell_id
    end
    if now < hw_retry_at then
        return nil
    end
    hw_retry_at = now + DS_RESOLVE_RETRY_S
    for i = 1, #hw_ids do
        if api.is_spell_known(hw_ids[i]) then
            hw_spell_id = hw_ids[i]
            return hw_spell_id
        end
    end
    return nil
end

-- Target health percent for the Era execute cue, or nil when there is no
-- target or the client cannot answer (secret reads degrade to nil in compat,
-- like every other gather reading here).
local function get_guide_target_health_pct()
    if not (UnitExists and UnitExists("target")) then
        return nil
    end
    local health = api.UnitHealth("target")
    local health_max = api.UnitHealthMax("target")
    if type(health) ~= "number" or type(health_max) ~= "number"
        or health_max <= 0 then
        return nil
    end
    return health / health_max * 100
end

-- Repoint the FCFS slot textures at the resolved ranks once the book answers
-- (hunter resolve_guide_icons pattern): the sob slot at Divine Storm, the how
-- slot at Holy Wrath. Unknown keeps the fallback, never a blank swap; families
-- whose book lacks both keep the shipped ids bit-identically. Runs once from
-- post_init, before the guide frame builds its icons. Defined after the DS/HW
-- resolvers above (lexical locals) and before the guide table below.
function ST.PALADIN.resolve_guide_icons()
    local now = api.get_time()
    local ds_id = (is_wrath_family or is_era_family) and resolve_ds_spell_id(now) or nil
    local hw_id = is_wrath_family and resolve_hw_spell_id(now) or nil
    if not ds_id and not hw_id then
        return
    end
    local slots = ST.PALADIN.guide.slots
    for i = 1, #slots do
        local slot = slots[i]
        if ds_id and slot.key == "sob" then
            slot.spell_id = ds_id
        end
        if hw_id and slot.key == "how" then
            slot.spell_id = hw_id
        end
    end
end

function ST.PALADIN.gather_guide_inputs(self, out)
    local na = st.nextaction
    local now = api.get_time()
    local d = self.mainhand
    local gcd = self.gcd
    local db = self:get_class_table()
    local inputs = out or self.PALADIN.guide_inputs

    -- Swing state and clock (seconds). ends_at and the GCD/aura stamps all live in
    -- the GetTime() domain, which api.get_time() shares, so the comparisons hold.
    inputs.speed = (d and d.speed) or 0
    inputs.swing_remaining = math.max(0, ((d and d.ends_at) or now) - now)
    inputs.G = self:get_spell_gcd_duration()
    inputs.gcd_remaining = (gcd and gcd.expires and math.max(0, gcd.expires - now)) or 0
    inputs.twist_window = self.PALADIN.get_twist_window_time_before_swing(self)
    inputs.reaction = (db.nextaction_reaction_time_ms or 100) / 1000
    -- Era family flag for the engine's Era branch (false everywhere else, so
    -- all other families keep the archived behaviour bit-identically).
    inputs.era = is_era_family
    -- Forever family flag for the engine's Forever branch (false everywhere
    -- else, so all other families keep the archived behaviour bit-identically).
    inputs.forever = is_forever_family
    -- TBC: researched CS delay is under 1 s; the archived 1.7 s default
    -- over-delays CS. CONFLICT: Wrath wants ~0 (no twist to protect) — one
    -- default cannot serve both; the option range is unchanged. See the same
    -- note on the engine fallback in nextaction.lua.
    inputs.cs_delay_max = (db.nextaction_cs_max_delay_ms or 900) / 1000

    -- Active seal for the decision tree ("soc" | "sob" | "none"; Command's
    -- remaining time guards the engine's reseal branch). Era feeds the twist
    -- seal (Righteousness; Blood does not exist there) into the engine's
    -- twist-seal position, reusing its landmarks unchanged.
    if na then
        local twist_seal_up = self.has_sob
        -- Forever feeds Righteousness into the twist-seal position (Twist of
        -- Light alternates Command/Righteousness, UNCONFIRMED): same engine
        -- landmarks, Era texture on the guide slot.
        if (inputs.era or inputs.forever) and self.has_sor then
            twist_seal_up = true
        end
        inputs.seal = na.get_seal_state(self.has_soc, twist_seal_up,
            self.soc_expires and (self.soc_expires - now))
    else
        inputs.seal = "none"
    end

    -- Display-only seal swipe fields for the guide frame (its cooldown_key slot
    -- swipes read <key>_expires / <key>_duration from these inputs; the engine
    -- ignores them). Assigning nil is the clear: exactly what a dropped seal, the
    -- practice mirror and the pre-tracking window want. Era drives the
    -- twist-seal swipe from the Righteousness aura (that slot's icon is
    -- Righteousness there); every other family keeps Blood.
    inputs.soc_expires = self.soc_expires
    inputs.soc_duration = self.soc_duration
    inputs.sob_expires = self.sob_expires
    inputs.sob_duration = self.sob_duration
    if inputs.era or inputs.forever then
        inputs.sob_expires = self.sor_expires
        inputs.sob_duration = self.sor_duration
    end

    -- Crusader Strike / Judgement cooldowns. The archive's rules: an unknown CS
    -- talent means the engine must never see CS available (999 s), and Judgement
    -- needs no latch of its own. cs_known rides the inputs too: the engine's
    -- Era branch keys its no-CS guarantee off it (the client's spell book, not
    -- the 999 sentinel). The swipe LENGTHs ride along in cs_duration /
    -- judge_duration (display-only; see the input-contract comment above) and are read
    -- after the calls, so they describe the cooldown this same tick reported.
    local cs_known = na and na.CS_SPELL_ID and api.is_spell_known(na.CS_SPELL_ID) or false
    inputs.cs_known = cs_known
    if na and na.CS_SPELL_ID then
        if cs_known then
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
    -- TBC opt-ins (engine defaults preserve the archive; constants, no options):
    -- the judge-feasibility gate is always on. Single-target is reported from
    -- target presence: no WoW API counts enemies, so a known target reads as
    -- single-target (Consecration withheld as AoE-only) while no target reading
    -- leaves the archived suggestion; a future target counter upgrades this to
    -- the real count (> 1 re-enables Consecration). Reporting nil (not 1) with
    -- no target also keeps provider-unaware callers bit-identical. Exorcism vs
    -- Undead/Demon is unaffected either way.
    inputs.judge_require_fit = true
    inputs.target_count = inputs.creature_type ~= nil and 1 or nil
    inputs.jotc_remaining = get_guide_jotc_remaining(self, now)
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

    -- FCFS inputs (Wrath FCFS + SoD Exodin; nil on every other family, which the
    -- archived tree ignores as unknown names, so it runs bit-identically there).
    -- cons/exo reuse the filler mirror's agreed cooldowns above (no second client
    -- query); DS/Holy Wrath resolve here (nil while the book is cold or the spell
    -- unknown, which withholds them); has_aow is the live Art of War flag that
    -- gates the Wrath Exorcism. SoD detection is rune spells only, never version
    -- strings: the ERA family client with a book entry Era-base cannot have
    -- (CS rune via cs_known, DS rune via the resolve, 348700 Seal of the Martyr
    -- via the probe). Candidate ids are best-knowledge (confirm in-client); a
    -- miss reads unknown and the Era branch stands, never a wrong prompt.
    local ds_id = (is_wrath_family or is_era_family) and resolve_ds_spell_id(now) or nil
    inputs.ds_remaining = ds_id and get_guide_cooldown_remaining(self, ds_id) or nil
    local hw_id = is_wrath_family and resolve_hw_spell_id(now) or nil
    inputs.hw_remaining = hw_id and get_guide_cooldown_remaining(self, hw_id) or nil
    local fcfs_family = is_wrath_family or is_era_family
    inputs.cons_remaining = fcfs_family and consecration_remaining or nil
    inputs.exo_remaining = fcfs_family and exorcism_remaining or nil
    inputs.has_aow = self.has_aow == true
    local is_sod = is_era_family
        and (cs_known or ds_id ~= nil or api.is_spell_known(348700))
    inputs.fcfs_mode = is_wrath_family and "wrath" or (is_sod and "sod") or nil

    -- Judgement-wait carry from the engine's previous output (kept by the display).
    inputs.waiting_judgement = self.guide_waiting_judgement and true or false
    -- Era/Forever execute inputs (nil everywhere else: the engine only reads
    -- them on Era/Forever, so all other families keep the archived behaviour
    -- bit-identically). Forever reuses the window: the beta Ret ST lists
    -- Hammer of Wrath below 20% (UNCONFIRMED).
    -- how_remaining is nil while the spell is unknown on this client.
    if is_era_family or is_forever_family then
        inputs.target_health_pct = get_guide_target_health_pct()
        inputs.how_remaining = get_guide_how_remaining(self, now)
    else
        inputs.target_health_pct = nil
        inputs.how_remaining = nil
    end
    return inputs
end

--=========================================================================================
-- Next Action Guide: the paladin provider for the generic guide frame
--=========================================================================================
-- Implements the frozen ST.<CLASS>.guide contract documented in nextaction_ui.lua's
-- header. The decision engine stays pure (st.nextaction) and the live reads stay in
-- gather_guide_inputs above; this table is the glue: it names the display slots, maps
-- the engine's flags onto slot keys (the frame only knows keys) and publishes the
-- rotation source the frame paints below the icons.
--
-- SEVEN slots (cs, soc, sob, twist, judge, consecration, exorcism) plus the
-- Era execute cue below: EIGHT in total. The contract expects six or fewer
-- per class; the composite twist cue and the execute cue are the paladin's
-- extra two, kept because they are the shipped visuals (the twist is one
-- icon: Command full width with the half-width, centre-cropped Blood icon
-- over its right half - the WA's 'twist 1/2' + 'twist 2/2' pair).
--
-- Display specifics are exactly the shipped frame's: the 45x45 stacked action icons
-- (levels 1/3/5), the composite twist at 8/9, the 22.5x24.9 judgement cue at
-- (-9,-10) with its Pixel glow, the three 45x45 filler icons (zoom 0.2 / 0.15 /
-- 0.15) with their FILLER captions, and the Blood opener dimmed to 0.5 while idle. Swipe
-- fallbacks keep the archive's constants (CS 6 s, Judgement 8 s, seals 30 s); the
-- seal swipes drive always (from the aura expiries) while the CS / Judgement swipes
-- only drive while their icon shows - the shipped display's split.
ST.PALADIN.guide = {
    slots = {
        -- Crusader Strike (archive icon_cs).
        { key = "cs", spell_id = 35395, cooldown_key = "cs",
            name_suffix = "IconCS", level = 1, swipe_duration = 6 },
        -- Seal of Command (archive icon_command): reseal icon + the aura swipe.
        { key = "soc", spell_id = 20375, cooldown_key = "soc",
            name_suffix = "IconCommand", level = 3, swipe_duration = 30,
            swipe_always = true },
        -- Seal of Blood (archive icon_blood): the ride icon + the aura swipe; the
        -- idle opener shows this icon at half alpha. On Era and Forever the
        -- icon is the twist seal (Righteousness): same slot, same key, Era
        -- texture. On Wrath
        -- the slot carries Divine Storm instead (same slot, same key, DS texture;
        -- no twisting there and the FCFS engine prompts DS on this channel).
        { key = "sob", spell_id = guide_sob_spell_id, cooldown_key = "sob",
            name_suffix = "IconBlood", level = 5, swipe_duration = 30,
            swipe_always = true, idle_alpha = 0.5 },
        -- The twist cue (archive icon_twist): Command full width with the
        -- half-width Blood overlay on its right half (Righteousness on Era
        -- and Forever: same slot, same key, Era texture).
        { key = "twist", spell_id = 20375, name_suffix = "TwistLeft", level = 8,
            overlay = { spell_id = guide_twist_seal_id, name_suffix = "TwistRight",
                size = { 22.5, 45 }, offset = { 11.25, 0 }, keep_aspect = true } },
        -- Judgement cue (archive icon_judge): small, low-left, Pixel glow while shown.
        { key = "judge", spell_id = 20271, cooldown_key = "judge",
            name_suffix = "JudgeTime", level = 9, size = { 22.5, 24.9 },
            offset = { -9, -10 }, keep_aspect = true, border_size = 1,
            glow = true, glow_key = "NextActionJudge", swipe_duration = 8 },
        -- Fillers (archive filler_consec / filler_exo) pop over everything, captioned.
        { key = "consecration", spell_id = 26573, name_suffix = "FillerC",
            level = 13, zoom = 0.2, label = "FILLER" },
        { key = "exorcism", spell_id = 879, name_suffix = "FillerE",
            level = 14, zoom = 0.15, label = "FILLER" },
        -- Execute (Era Hammer of Wrath): the engine's filler_kind "how" needs a
        -- slot of its own or the frame drops it as an unknown key. Same filler
        -- shape (no swipe, captioned, above everything); the rank-1 id carries
        -- the icon every rank shares. On Wrath the slot carries Holy Wrath (the
        -- FCFS engine's "how" channel there); same slot, same key, HW texture.
        { key = "how", spell_id = guide_how_spell_id, name_suffix = "FillerH",
            level = 15, zoom = 0.15, label = "FILLER" },
    },

    -- Live inputs: the existing gather, verbatim, into the caller's reused table.
    gather = function(self, out)
        return ST.PALADIN.gather_guide_inputs(self, out)
    end,

    -- Pure: one engine tick, then the display mapping the frame consumes. The engine
    -- writes into its own reused table, so its `out.action` seed (the archive's last
    -- action) keeps the exact value it always had; the frozen display fields are then
    -- derived into the caller's table. riding shows the Blood slot with the RIDE
    -- overlay, the engine's judge/filler flags become slot keys.
    evaluate = function(inputs, out)
        if type(out) ~= "table" then
            out = {}
        end
        local raw = ST.PALADIN.guide_raw
        if not raw then
            raw = {}
            ST.PALADIN.guide_raw = raw
        end
        local na = st.nextaction
        -- FCFS families (Wrath, SoD runes) run the priority-winner engine; every
        -- other family keeps the archived twist tree bit-identically (scripted and
        -- old callers pass no fcfs_mode, which reads as nil here).
        if na and na.evaluate_fcfs and inputs.fcfs_mode ~= nil then
            na.evaluate_fcfs(inputs, raw)
        elseif na and na.evaluate then
            na.evaluate(inputs, raw)
        end
        out.action = raw.riding and "sob" or raw.action
        out.hold = raw.hold
        out.hold_text = raw.riding and "RIDE" or "HOLD"
        out.filler_slot = raw.filler_kind
        out.judge_slot = raw.judge_call and "judge" or nil
        -- Era and Forever show no rotation pattern: the keys name CS-cycle
        -- cadences that do not exist without Crusader Strike. (The filler_kind
        -- "how" passes through untouched to the HoW slot above.)
        out.rotation_key = nil
        -- FCFS has no rotation pattern (nothing to paint); the twist cadences
        -- stay TBC-only, Era and Forever stay patternless as before.
        if not inputs.era and not inputs.forever and inputs.fcfs_mode == nil
            and na and na.calculate_rotation then
            out.rotation_key = na.calculate_rotation(inputs.speed, inputs.G)
        end
        out.waiting_judgement = raw.waiting_judgement
        return out
    end,

    -- Live rotation-pattern source for the guide's rotation text (identical to the
    -- shipped update_texts call; the engine owns the thresholds). Nil on Era
    -- and Forever (see evaluate above).
    rotation_key = function(inputs)
        if inputs.era or inputs.forever or inputs.fcfs_mode ~= nil then
            return nil
        end
        local na = st.nextaction
        if not (na and na.calculate_rotation) then
            return nil
        end
        return na.calculate_rotation(inputs.speed, inputs.G)
    end,

    -- Key -> display text: the engine's own map, never duplicated here.
    rotation_names = st.nextaction and st.nextaction.display_names or nil,

    labels = { next_action = "Next action:", hold = "HOLD", ride = "RIDE" },
}

--=========================================================================================
-- Cooldown HUD: paladin slots and the live state provider
--=========================================================================================
-- The slot set is the archived HUD's (archive hud.lua:28-49): Crusader Strike,
-- Judgement, Consecration, Exorcism, the two trinket slots and Avenging Wrath. The
-- descriptor and provider contracts are frozen in hud.lua's header comment; the
-- "trinket" slots are served by the HUD's own tracker, every "spell" slot by
-- ST.PALADIN.get_hud_state below.
--
-- Exorcism: the archive carried the TBC rank id (27138) for the icon; the rank-1 id
-- (879, the id the guide already uses) is the one that resolves on every family, so
-- the icon is never blank on Classic Era. cooldown_spell stays unused: the provider
-- reads cooldowns by the client's own rank (name-based), not by a fixed id.
ST.PALADIN.HUD_SLOTS = {
    { key = "cs", title = "Crusader Strike", kind = "spell", spell = 35395 },
    { key = "judgement", title = "Judgement", kind = "spell", spell = 20271 },
    { key = "consecration", title = "Consecration", kind = "spell", spell = 26573 },
    { key = "exorcism", title = "Exorcism", kind = "spell", spell = 879 },
    { key = "trinket1", title = "Trinket 1", kind = "trinket", inv_slot = 13 },
    { key = "trinket2", title = "Trinket 2", kind = "trinket", inv_slot = 14 },
    { key = "wings", title = "Avenging Wrath", kind = "spell", spell = 31884 },
}

-- One reused state table: the HUD reads it immediately and never keeps a reference
-- (see the frozen contract in hud.lua), so there is no per-tick allocation here.
ST.PALADIN.hud_state = {}

-- Localized HUD slot spell names, resolved lazily (name-based cooldown and probe
-- lookups are rank-agnostic). Resolved values are cached; a failed resolution (spell
-- data not ready yet) is retried on the next call, like the guide's filler names.
local hud_slot_names = {}

local function hud_slot_name(slot)
    local name = hud_slot_names[slot.key]
    if not name then
        name = slot.spell and api.GetSpellInfo(slot.spell) or nil
        if name then
            hud_slot_names[slot.key] = name
        end
    end
    return name
end

-- Practice-mode cooldown remaining (the archive's readers checked st.practice.active;
-- this codebase's practice session is practice_ui).
local function hud_practice_active()
    return st.practice_ui ~= nil and st.practice_ui.is_active() == true
end

local function hud_sim_remaining(field, now)
    local sim = st.practice_ui and st.practice_ui.sim
    local expires = sim and sim[field]
    if type(expires) ~= "number" then
        return 0
    end
    local remaining = expires - now
    if remaining < 0 then
        remaining = 0
    end
    return remaining
end

-- The running GCD (archive hud.lua:101-107, re-pointed at the addon's own tracking).
local function hud_gcd_remaining(self, now)
    local g = self.gcd
    local expires = g and g.expires
    if type(expires) ~= "number" then
        return 0, 0
    end
    local remaining = expires - now
    if remaining <= 0 then
        return 0, 0
    end
    return remaining, g.spell_length or g.duration or 1.5
end

-- Remaining time and full duration of one paladin ability cooldown, practice-aware:
-- the archive's ability_cooldown (hud.lua:74-99) re-expressed on the readers the guide
-- already uses (get_guide_cooldown_remaining: client cooldown with latch and GCD-echo
-- handling) plus the practice sim fields for a session.
local function hud_ability_cooldown(self, slot, now)
    local key = slot.key
    local practice = hud_practice_active()
    if key == "cs" then
        local remaining
        if practice then
            remaining = hud_sim_remaining("cs_cooldown_expires", now)
        elseif st.nextaction and st.nextaction.CS_SPELL_ID
            and api.is_spell_known(st.nextaction.CS_SPELL_ID) then
            remaining = get_guide_cooldown_remaining(self, st.nextaction.CS_SPELL_ID,
                "guide_cs_expires", "guide_cs_duration")
        else
            remaining = 999   -- without the talent there is nothing to count
        end
        if remaining >= 999 then
            remaining = 0
        end
        return remaining, 6
    elseif key == "judgement" then
        if practice then
            return hud_sim_remaining("judge_cooldown_expires", now), 8
        end
        local judge_id = st.nextaction and st.nextaction.JUDGEMENT_SPELL_ID or 20271
        return get_guide_cooldown_remaining(self, judge_id), 8
    elseif key == "consecration" then
        if practice then
            return hud_sim_remaining("consec_cooldown_expires", now), 8
        end
        local name = hud_slot_name(slot)
        if not name then
            return 0, 8
        end
        return get_guide_cooldown_remaining(self, name) or 0, 8
    elseif key == "exorcism" then
        -- Archive parity: the filler reader behind Exorcism never simulated a
        -- cooldown, so during practice it reads as ready.
        if practice then
            return 0, 15
        end
        local name = hud_slot_name(slot)
        if not name then
            return 0, 15
        end
        return get_guide_cooldown_remaining(self, name) or 0, 15
    elseif key == "wings" then
        -- Straight from the API, ignoring the GCD echo (a real cooldown is minutes
        -- long). Archive parity: practice leaves it ready.
        if practice then
            return 0, 180
        end
        local start_time, duration = api.GetSpellCooldown(31884)
        if start_time and duration and duration > 1.51 then
            local remaining = start_time + duration - now
            if remaining > 0 then
                return remaining, duration
            end
        end
        return 0, 180
    end
    return 0, 0
end

-- IsUsableSpell's second return (the WA's "insufficientResources"; archive
-- hud.lua:114-121), through compat's cross-client IsSpellUsable wrapper: the
-- C_Spell / classic-global probes and their fallback live there. A client with no probe
-- reports unknown, rendered as "no tint" exactly like the archive's
-- `if not IsUsableSpell` guard; the pcall absorbs a probe that rejects the argument form.
local function hud_no_mana(slot)
    local name = hud_slot_name(slot)
    local ok, _, insufficient = pcall(api.IsSpellUsable, name or slot.spell)
    return ok and insufficient == true
end

-- WA "spellInRange == 0" (archive hud.lua:123-130): api.IsSpellInRange returns 0 out
-- of range, 1/true in range, nil unknown (treated as "not out of range").
local function hud_out_of_range(slot)
    if not (UnitExists and UnitExists("target")) then
        return false
    end
    local name = hud_slot_name(slot)
    if not name then
        return false
    end
    return api.IsSpellInRange(name, "target") == 0
end

local function hud_exorcisable()
    if hud_practice_active() then
        return true   -- archive: practice counts as a valid target
    end
    if not (UnitExists and UnitExists("target")) then
        return false
    end
    local ctype = read_creature_type()
    local types = st.nextaction and st.nextaction.exorcism_target_types
    return ctype ~= nil and types ~= nil and types[ctype] == true
end

-- The class provider (frozen contract, hud.lua header): maps the archive's
-- ability_state (hud.lua:418-453) onto the semantic state fields the HUD paints.
function ST.PALADIN.get_hud_state(self, slot, now)
    local s = ST.PALADIN.hud_state
    s.remaining, s.duration, s.start, s.reverse = nil, nil, nil, nil
    s.text_remaining, s.desaturate, s.usable, s.in_range = nil, nil, nil, nil
    s.glow, s.count, s.texture, s.hidden = nil, nil, nil, nil
    now = now or api.get_time()
    local remaining, full = hud_ability_cooldown(self, slot, now)
    local on_cd = remaining > 0
    if on_cd then
        s.remaining = remaining
        s.duration = full
        s.text_remaining = remaining
        s.desaturate = true
    elseif slot.key ~= "judgement" and slot.key ~= "wings" then
        -- The GCD shows as a swipe (WA "show GCD"); the HUD's 2 s rule keeps its
        -- text hidden. Judgement and Avenging Wrath never carry it (archive 426-428).
        local g, gd = hud_gcd_remaining(self, now)
        if g > 0 then
            s.remaining, s.duration = g, gd
            s.text_remaining = g
        end
    end

    local db = self:get_class_table()
    if db.hud_mana_tint and hud_no_mana(slot) then
        s.usable = false
    end
    if db.hud_range_tint and hud_out_of_range(slot) then
        s.in_range = false
    end

    if slot.key == "judgement" then
        -- Grey without an active seal (archive 441-443).
        if (self.twist_active_seals_count or 0) <= 0 then
            s.desaturate = true
        end
    elseif slot.key == "exorcism" then
        -- Grey unless the target is Undead or Demon; glows then, in combat and ready.
        local ok_target = hud_exorcisable()
        if not ok_target then
            s.desaturate = true
        end
        s.glow = (ok_target and remaining <= 0 and self.in_combat == true) or false
    elseif slot.key == "wings" then
        -- Glows the moment it is ready, in combat (archive 448-451).
        s.glow = (remaining <= 0 and self.in_combat == true) or false
    end
    return s
end

if st.debug then st.utils.print_msg('-- Parsed classes/paladin.lua module correctly (twist)') end

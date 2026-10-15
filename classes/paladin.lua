--=========================================================================================
-- Module for Paladin-specific behaviours
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
local LCG = LibStub("LibCustomGlow-1.0")
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
    self.PALADIN.on_aura_change(self)
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


function ST.PALADIN.on_aura_change(self)
    -- Parse seals and art of war
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

if st.debug then st.utils.print_msg('-- Parsed classes/paladin.lua module correctly') end

--=========================================================================================
-- Module for Warrior-specific behaviours
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
-- Heroic Strike, all ranks across the classic families (vanilla -> BCC -> WotLK).
-- The lookup table keeps every rank id; get_family_spell_id picks the highest id
-- that exists on the running client (the current rank).
local hs_ids = get_tab({
    47450, 47449, 30324, 29707, 25286, 11567, 11566,
    11565, 11564, 1608, 285, 284, 78
})

-- Cleave, all ranks.
local cleave_ids = get_tab({
    47520, 47519, 25231, 20569, 11609, 11608, 7369, 845
})

-- Cached current-rank ids, resolved once on first use.
local hs_current_id
local cleave_current_id

-- Bloodsurge (WotLK proc)
local bloodsurge_id = 46916


function ST.WARRIOR.on_rage_update(self)
    if (not self.hs_queued) and (not self.cleave_queued) then
        self.insufficient_rage = false
        return
    end
    
    if self.hs_queued then
        hs_current_id = hs_current_id or api.get_family_spell_id(hs_ids)
        local costs = hs_current_id and api.GetSpellPowerCost(hs_current_id)
        local rage_cost = costs and costs[1] and costs[1].cost
        local power = UnitPower("player")
        if rage_cost and power < rage_cost then
            self.insufficient_rage = true
            self:set_bar_color("mainhand")
        else
            self.insufficient_rage = false
        end
        return
    end

    if self.cleave_queued then
        cleave_current_id = cleave_current_id or api.get_family_spell_id(cleave_ids)
        local costs = cleave_current_id and api.GetSpellPowerCost(cleave_current_id)
        local rage_cost = costs and costs[1] and costs[1].cost
        local power = UnitPower("player")
        if rage_cost and power < rage_cost then
            self.insufficient_rage = true
            self:set_bar_color("mainhand")
        else
            self.insufficient_rage = false
        end
        return
    end
end

function ST.WARRIOR.on_spellcast_failed_quiet(self, unit_id, cast_guid, spell_id)
    if hs_ids[spell_id] ~= nil then
        self.hs_queued = false
        self:set_bar_color("mainhand")
        return
    end
    if cleave_ids[spell_id] ~= nil then
        self.cleave_queued = false
        self:set_bar_color("mainhand")
        return
    end
end

function ST.WARRIOR.on_spellcast_succeeded(self, unit_target, cast_guid, spell_id)
    -- print(unit_target)
    -- print(spell_id)
    if hs_ids[spell_id] ~= nil then
        self.hs_queued = false
        self:set_bar_color("mainhand")
        return
    end
    if cleave_ids[spell_id] ~= nil then
        self.cleave_queued = false
        self:set_bar_color("mainhand")
        return
    end
end

function ST.WARRIOR.on_current_spell_cast_changed(self, is_cancelled)
    -- This function detects when the player queues up a heroic strike or cleave
    -- and sets relevant flags for the func to set bar colors.
    local db = self:get_class_table()

    -- Only run this logic if special on-next-attack colors are enabled in the warrior settings.
    if (not db.enable_hs_color) and not (db.enable_cleave_color) then
        return
    end

    if db.enable_hs_color then
        for spell_id in pairs(hs_ids) do
            local result = api.IsCurrentSpell(spell_id)
            if result then
                -- print('matched HS id: '..tostring(spell_id))
                self.hs_queued = true
                self.cleave_queued = false
                self:set_bar_color("mainhand")
                return
            end
        end
        self.hs_queued = false
    end

    -- If we get here, cleave color is enabled and no HS queued so check that always.
    for spell_id in pairs(cleave_ids) do
        local result = api.IsCurrentSpell(spell_id)
        if result then
            -- print('matched cleave id: '..tostring(spell_id))
            self.cleave_queued = true
            self:set_bar_color("mainhand")
            return
        end
    end
    self.cleave_queued = false
end

function ST.WARRIOR.on_aura_change(self)
    self.has_bloodsurge = false
    -- Iterate all player auras
    local i = 1
    while true do
        local name, _, _, _, _, _, _, _, _, spell_id = api.UnitAura("player", i)
        if name == nil then
            break
        end
        if spell_id == bloodsurge_id then
            self.has_bloodsurge = true
        end
        i = i + 1
    end
    self.WARRIOR.process_bloodsurge(self)
end

function ST.WARRIOR.glow_start(self)
    local db_class = self:get_class_table()
    local frame = self:get_bar_frame("mainhand")
    local db_hand = self:get_hand_table("mainhand")
    local thickness = db_hand.border_width or 1
    -- if thickness == 0 then
    --     thickness = 1
    -- end
    LCG.PixelGlow_Start(frame,
        {self:convert_color(db_class.bloodsurge_glow_color)},
        db_class.bloodsurge_glow_nlines,
        db_class.bloodsurge_glow_freq,
        db_class.bloodsurge_glow_line_length,
        thickness,
        0,
        0,
        false
    )
end

function ST.WARRIOR.process_bloodsurge(self)
    local db = self:get_class_table()
    if not self.has_bloodsurge then
        self.WARRIOR.glow_stop(self)
        return
    end
    if not db.use_bloodsurge_glow then
        self.WARRIOR.glow_stop(self)
        return
    end
    self.WARRIOR.glow_start(self)
end

function ST.WARRIOR.glow_stop(self)
    local frame = self:get_bar_frame("mainhand")
    LCG.PixelGlow_Stop(frame)
end

function ST.WARRIOR.set_bar_color(self, hand)
    -- Returns true if any special setting was applied to let the parent func know 
    -- to revert to default behaviour.
    -- Will set appropriate colors for HS/Cleave queued if requested in the settings,
    -- and will set a special color when the player has one of those queued up but has
    -- insufficient rage to cast them.
    local db_class = self:get_class_table()
    local frame = self:get_visuals_frame(hand)

    self.WARRIOR.process_bloodsurge(self)

    if hand ~= "mainhand" then
        return false
    end

    -- On-next-attack behaviours
    if db_class.enable_hs_color and self.hs_queued and not (self.insufficient_rage) then
        frame.bar:SetVertexColor(
            self:convert_color(db_class.hs_color)
        )
        return true
    end
    if db_class.enable_cleave_color and self.cleave_queued and not (self.insufficient_rage) then
        frame.bar:SetVertexColor(
            self:convert_color(db_class.cleave_color)
        )
        return true
    end
    
    -- Insufficient rage for queue.
    if (self.cleave_queued or self.hs_queued) and self.insufficient_rage then
        frame.bar:SetVertexColor(
            self:convert_color(db_class.insufficient_rage_color)
        )
        return true
    end

    return false

end

if st.debug then st.utils.print_msg('-- Parsed classes/warrior.lua module correctly') end

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
-- Mortal Strike (29707 / 30324) is deliberately NOT in this table: it outranks the TBC
-- Heroic Strike id, so get_family_spell_id would pick it there and query the wrong rage
-- cost.
local hs_ids = get_tab({
    47450, 47449, 25286, 11567, 11566,
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


-- Resolves the highest rank that exists on the running client exactly once. A negative
-- result is latched as false too, so a client without the spell stops re-walking the
-- whole table on every power tick.
local function resolve_rank(ids, cached)
    if cached == nil then
        return api.get_family_spell_id(ids) or false
    end
    return cached
end

-- Compares the current rage against the queued ability cost and recolours only when the
-- state actually changes: UNIT_POWER_FREQUENT fires several times a second.
local function update_rage_state(self, spell_id)
    local costs = spell_id and api.GetSpellPowerCost(spell_id)
    local rage_cost = costs and costs[1] and costs[1].cost
    local power = api.UnitPower("player")
    -- No cost data (unlearned spell, client we cannot read) means we cannot claim the
    -- player is short of rage; a non-numeric reading (or a secret value on a modern
    -- client) degrades the same way instead of erroring on the comparison.
    local insufficient = false
    if type(rage_cost) == "number" and type(power) == "number" then
        insufficient = power < rage_cost
    end
    if self.insufficient_rage ~= insufficient then
        self.insufficient_rage = insufficient
        self:set_bar_color("mainhand")
    end
end

function ST.WARRIOR.on_rage_update(self)
    if self.hs_queued then
        hs_current_id = resolve_rank(hs_ids, hs_current_id)
        return update_rage_state(self, hs_current_id or nil)
    end
    if self.cleave_queued then
        cleave_current_id = resolve_rank(cleave_ids, cleave_current_id)
        return update_rage_state(self, cleave_current_id or nil)
    end
    -- Nothing queued: clear a stale "insufficient rage" colour left by the last fight.
    if self.insufficient_rage then
        self.insufficient_rage = false
        self:set_bar_color("mainhand")
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

    -- No HS queued. Only probe Cleave when its colour is enabled, so the flag can never
    -- stay stale while the option is off.
    if not db.enable_cleave_color then
        self.cleave_queued = false
        return
    end
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
        -- "HELPFUL" explicitly: the Retail wrapper forwards the filter into
        -- C_UnitAuras.GetAuraDataByIndex, where it is a typed enum argument.
        local name, _, _, _, _, _, _, _, _, spell_id = api.UnitAura("player", i, "HELPFUL")
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
    local should_glow = (self.has_bloodsurge and db.use_bloodsurge_glow) and true or false
    -- LibCustomGlow pools its glow frames: re-starting (or stopping twice) on every aura
    -- event churns the pool and can double-release the frame, so only transition when
    -- the state actually changes.
    if should_glow == self.bloodsurge_glow_active then
        return
    end
    self.bloodsurge_glow_active = should_glow
    if should_glow then
        self.WARRIOR.glow_start(self)
    else
        self.WARRIOR.glow_stop(self)
    end
end

function ST.WARRIOR.glow_stop(self)
    local frame = self:get_bar_frame("mainhand")
    LCG.PixelGlow_Stop(frame)
end

function ST.WARRIOR.post_init(self)
    -- Starts settled so the first process_bloodsurge does not emit a spurious stop on
    -- an already-idle frame.
    self.bloodsurge_glow_active = false
    self.hs_queued = false
    self.cleave_queued = false
    self.insufficient_rage = false
end

function ST.WARRIOR.on_combat_exit(self)
    -- A queued ability dies with the fight; without this the bar can keep the HS /
    -- Cleave / insufficient-rage colour into the next pull.
    self.hs_queued = false
    self.cleave_queued = false
    self.insufficient_rage = false
    self.WARRIOR.process_bloodsurge(self)
    if self.interfaces_are_initialised then
        self:set_bar_color("mainhand")
    end
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

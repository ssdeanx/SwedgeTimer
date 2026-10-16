--=========================================================================================
-- Module for Hunter-specific behaviours
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
-- Cross-client API wrappers (see compat.lua).
local api = st.api
local get_tab = st.utils.convert_lookup_table

--=========================================================================================
-- Spell data
--=========================================================================================
-- Raptor Strike, all ranks across the classic families (vanilla -> BCC -> WotLK).
-- The lookup table keeps every rank id; get_family_spell_id picks the highest id
-- that exists on the running client (the current rank).
local raptor_strike_ids = get_tab({
    2973, 14260, 14261, 14262, 14263, 14264, 14265, 27014, 48995, 48996
})

function ST.HUNTER.on_spellcast_failed_quiet(self, unit_id, cast_guid, spell_id)
    if raptor_strike_ids[spell_id] ~= nil then
        self.raptor_strike_queued = false
        self:set_bar_color("mainhand")
    end
end

function ST.HUNTER.on_spellcast_succeeded(self, unit_target, cast_guid, spell_id)
    if raptor_strike_ids[spell_id] ~= nil then
        self.raptor_strike_queued = false
        self:set_bar_color("mainhand")
    end
end

function ST.HUNTER.on_current_spell_cast_changed(self, is_cancelled)
    -- This function detects when the player queues up a raptor strike
    -- and sets relevant flags for the func to set bar colors.
    local db = self:get_class_table()
    -- Only run this logic if special on-next-attack colors are enabled in the hunter settings.
    if not db.enable_raptor_strike_color then
        return
    end
    for spell_id in pairs(raptor_strike_ids) do
        local result = api.IsCurrentSpell(spell_id)
        if result then
            self.raptor_strike_queued = true
            self:set_bar_color("mainhand")
            return
        end
    end
    self.raptor_strike_queued = false
end

function ST.HUNTER.post_init(self)
    -- Flags must exist before the first spellcast/current-cast event reaches this
    -- module, otherwise a stale nil would decide the bar colour.
    self.raptor_strike_queued = false
end

function ST.HUNTER.on_combat_exit(self)
    -- A queued Raptor Strike dies with the fight.
    self.raptor_strike_queued = false
end

function ST.HUNTER.set_bar_color(self, hand)
    local db_class = self:get_class_table()
    local frame = self:get_visuals_frame(hand)
    if hand ~= "mainhand" then
        return false
    end

    -- On-next-attack behaviours
    if db_class.enable_raptor_strike_color and self.raptor_strike_queued then
        frame.bar:SetVertexColor(
            self:convert_color(db_class.raptor_strike_color)
        )
        return true
    end
    return false
end

if st.debug then st.utils.print_msg('-- Parsed classes/hunter.lua module correctly') end

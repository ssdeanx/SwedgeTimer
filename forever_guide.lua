--=========================================================================================
-- WoW Forever (Camelot 1.60.1 / Interface 16001) Rotation Engine & Spec Guides
-- Pure decision model: maps class + spec + inputs -> action, spell_name, hold, hold_text
-- Completely isolated from Era / TBC / Wrath legacy logic.
-- Name-first resolution with fallback rank IDs; smooth leveling progression before talents.
--=========================================================================================
local addon_name, st = ...
st = st or {}
st.addon_name = st.addon_name or addon_name
st.forever_guide = st.forever_guide or {}
local FG = st.forever_guide

-- Helper: check if a cooldown is ready (<= 0 or nil)
local function is_ready(cd, spell_name)
    if type(cd) == "number" then
        return cd <= 0
    end
    if spell_name then
        local api = st and st.api
        if api and api.GetSpellCooldown then
            local sp_def = FG.SPELLS_BY_NAME and FG.SPELLS_BY_NAME[spell_name]
            local query = (sp_def and sp_def.id) or spell_name
            local ok, start, duration = pcall(api.GetSpellCooldown, query)
            if canaccessallvalues(duration, start) then
                local dur_n = tonumber(duration)
                local start_n = tonumber(start)
                if ok and start_n and dur_n and dur_n > 1.51 and start_n > 0 then
                    local now = api.get_time and api.get_time() or 0
                    return (start_n + dur_n - now) <= 0
                end
            end
            return true
        end
    end
    return cd == nil or (type(cd) == "number" and cd <= 0)
end

-- Helper: check if a spell is known (strictly boolean true from exact name or legacy flag)
local function is_known(inputs, name, flag)
    if type(inputs) == "table" then
        if name and inputs[name] == true then return true end
        if flag and inputs[flag] == true then return true end
        if name and inputs[name] == false then return false end
        if flag and inputs[flag] == false then return false end
    end
    local api = st and st.api
    if api and type(api.is_spell_known) == "function" and name then
        local sp_def = FG.SPELLS_BY_NAME and FG.SPELLS_BY_NAME[name]
        if sp_def then
            if sp_def.id and api.is_spell_known(sp_def.id) == true then
                return true
            end
            if sp_def.ids then
                for i = 1, #sp_def.ids do
                    if api.is_spell_known(sp_def.ids[i]) == true then
                        return true
                    end
                end
            end
        end
        local ok, known = pcall(api.is_spell_known, name)
        if ok and known == true then
            return true
        end
    end
    return false
end

--=========================================================================================
-- Tracked Spell Metadata Dictionary (Name-First with Multi-Rank ID Tables)
--=========================================================================================
FG.SPELLS = {
    -- Hunter
    SERPENT_STING   = { name = "Serpent Sting",    id = 1978,    ids = { 1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295, 425728, 425729, 425730, 425732, 425733, 425734, 425735, 425736, 425737 } },
    RAPTOR_STRIKE   = { name = "Raptor Strike",    id = 2973,    ids = { 2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266 } },
    STRIDER_KICK    = { name = "Strider Kick",     id = 1317257, ids = { 1317257 } },
    MONGOOSE_BITE   = { name = "Mongoose Bite",    id = 1495,    ids = { 1495, 14269, 14270, 14271 } },
    HUNTERS_MARK    = { name = "Hunter's Mark",    id = 1130,    ids = { 1130, 14323, 14324, 14325 } },
    ARCANE_SHOT     = { name = "Arcane Shot",      id = 3044,    ids = { 3044, 14281, 14282, 14283, 14284, 14285, 14286, 14287 } },
    MULTI_SHOT      = { name = "Multi-Shot",       id = 2643,    ids = { 2643 } },
    WING_CLIP       = { name = "Wing Clip",        id = 2974,    ids = { 2974, 14267, 14268 } },
    IMMOLATION_TRAP = { name = "Immolation Trap",  id = 13795,   ids = { 13795, 14302, 14303, 14304, 14305 } },
    AIMED_SHOT      = { name = "Aimed Shot",       id = 19434,   ids = { 19434, 20900, 20901, 20902, 20903, 20904 } },
    SNIPER_SHOT     = { name = "Sniper Shot",      id = 1310687, ids = { 1310687, 1310786 } },
    SUMMON_HAWK     = { name = "Summon Hawk",      id = 1293241, ids = { 1293241 } },
    ASPECT_HAWK     = { name = "Aspect of the Hawk", id = 13165, ids = { 13165, 14318, 14319, 14320, 14321, 14322, 25296 } },

    -- Warrior
    HEROIC_STRIKE   = { name = "Heroic Strike",    id = 78,      ids = { 78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286 } },
    REND            = { name = "Rend",             id = 772,     ids = { 772, 6546, 6547, 6548, 11572, 11573, 11574 } },
    OVERPOWER       = { name = "Overpower",        id = 7384,    ids = { 7384, 7887, 11584, 11585 } },
    BLOODTHRILL     = { name = "Bloodthrill",      id = 1289682, ids = { 1289681, 1289682 } },
    MORTAL_STRIKE   = { name = "Mortal Strike",    id = 12294,   ids = { 12294, 21551, 21552, 21553 } },
    BLOODTHIRST     = { name = "Bloodthirst",      id = 23881,   ids = { 23881, 23892, 23893, 23894 } },
    WHIRLWIND       = { name = "Whirlwind",        id = 1680,    ids = { 1680 } },
    EXECUTE         = { name = "Execute",          id = 5308,    ids = { 5308, 20658, 20660, 20661, 20662 } },
    SLAM            = { name = "Slam",             id = 1240193, ids = { 1240193, 1464, 8820, 11604, 11605 } },
    SUNDER_ARMOR    = { name = "Sunder Armor",     id = 7386,    ids = { 7386, 7405, 8380, 11596, 11597 } },
    THUNDER_CLAP    = { name = "Thunder Clap",     id = 6343,    ids = { 6343, 8198, 8204, 8205, 11580, 11581 } },
    DEMO_SHOUT      = { name = "Demoralizing Shout", id = 1160,  ids = { 1160, 6190, 11554, 11555, 11556 } },
    REVENGE         = { name = "Revenge",          id = 6572,    ids = { 6572, 6574, 7379, 11600, 11601, 25288 } },
    SHIELD_SLAM     = { name = "Shield Slam",      id = 23922,   ids = { 23922, 23923, 23924, 23925 } },
    SHIELD_BLOCK    = { name = "Shield Block",     id = 2565,    ids = { 2565 } },
    SHIELD_WALL     = { name = "Shield Wall",      id = 871,     ids = { 871 } },
    LAST_STAND      = { name = "Last Stand",       id = 12975,   ids = { 12975 } },
    HAMSTRING       = { name = "Hamstring",        id = 1715,    ids = { 1715, 7372, 7373 } },
    CLEAVE          = { name = "Cleave",           id = 845,     ids = { 845, 7369, 11608, 11609, 20569 } },
    BATTLE_SHOUT    = { name = "Battle Shout",     id = 6673,    ids = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 } },

    -- Paladin
    HOLY_STRIKE     = { name = "Holy Strike",      id = 679,     ids = { 679, 678, 1866, 680, 2495, 5569, 10332, 10333 } },
    JUDGEMENT       = { name = "Judgement",        id = 20271,   ids = { 20271 } },
    SEAL_RIGHTEOUSNESS = { name = "Seal of Righteousness", id = 21084, ids = { 21084, 20154, 20287, 20288, 20289, 20290, 20291, 20292, 20293 } },
    SEAL_COMMAND    = { name = "Seal of Command",  id = 20375,   ids = { 20375, 20915, 20918, 20919, 20920 } },
    SEAL_CRUSADER   = { name = "Seal of the Crusader", id = 21082, ids = { 21082, 20162, 20305, 20306, 20307, 20308 } },
    CONSECRATION    = { name = "Consecration",     id = 26573,   ids = { 26573, 20116, 20922, 20923, 20924 } },
    EXORCISM        = { name = "Exorcism",         id = 879,     ids = { 879, 5614, 5615, 10312, 10313, 10314, 415068, 415069, 415070, 415071, 415072, 415073 } },
    HAMMER_OF_WRATH = { name = "Hammer of Wrath",  id = 24275,   ids = { 24275, 24274, 24239 } },
    HOLY_SHOCK      = { name = "Holy Shock",       id = 20473,   ids = { 20473, 20929, 20930 } },
    DIVINE_FAVOR    = { name = "Divine Favor",     id = 20216,   ids = { 20216 } },
    HOLY_SHIELD     = { name = "Holy Shield",      id = 20925,   ids = { 20925 } },
    RIGHTEOUS_FURY  = { name = "Righteous Fury",   id = 25780,   ids = { 25780, 407627 } },
    SEAL_FURY       = { name = "Seal of Fury",      id = 20423,   ids = { 1311649, 1311656, 20163, 20419, 20421, 20422, 20423 } },

    -- Rogue
    SINISTER_STRIKE = { name = "Sinister Strike",  id = 1752,    ids = { 1752, 1757, 1758, 1759, 1760, 8621, 11293, 11294 } },
    EVISCERATE      = { name = "Eviscerate",       id = 2098,    ids = { 2098, 6760, 6761, 6762, 8623, 8624, 11299, 11300, 31016 } },
    SLICE_AND_DICE  = { name = "Slice and Dice",   id = 5171,    ids = { 5171, 6774 } },
    RUPTURE         = { name = "Rupture",          id = 1943,    ids = { 1943, 8639, 8640, 11273, 11274, 11275 } },
    MUTILATE        = { name = "Mutilate",         id = 1241584, ids = { 399960, 399961, 1241582, 1241584, 1241585, 1241586, 1241588, 1241590 } },
    HEMORRHAGE      = { name = "Hemorrhage",       id = 16511,   ids = { 16511 } },
    BACKSTAB        = { name = "Backstab",         id = 53,      ids = { 53, 2589, 2590, 2591, 8721, 11279, 11280, 11281, 25300 } },
    RIPOSTE         = { name = "Riposte",          id = 14251,   ids = { 14251 } },
    ENVENOM         = { name = "Venom",            id = 1310703, ids = { 1310703 } },
    EXPOSE_ARMOR    = { name = "Expose Armor",     id = 8647,    ids = { 8647, 8649, 8650, 11197, 11198 } },

    -- Druid
    MAUL            = { name = "Maul",             id = 6807,    ids = { 6807, 6808, 6809, 8972, 9745, 9880, 9881 } },
    SWIPE           = { name = "Swipe",            id = 779,     ids = { 779, 780, 769, 9754, 9908, 1264494, 1264497, 1264498, 1264501, 1264502 } },
    DEMO_ROAR       = { name = "Demoralizing Roar", id = 99,     ids = { 99, 1735, 9490, 9747, 9898 } },
    ENRAGE          = { name = "Enrage",           id = 5229,    ids = { 5229 } },
    -- UNVERIFIED: not present in the Wowhead Forever DB. 16857/17390-17392 are the
    -- classic fallback ladder; 784/1070/13424/13752 are the unverified Forever
    -- candidate variants (operator order: "use all the ids for now").
    FAERIE_FIRE_FERAL = { name = "Faerie Fire (Feral)", id = 16857, ids = { 16857, 17390, 17391, 17392, 784, 1070, 13424, 13752 } },
    CLAW            = { name = "Claw",             id = 1082,    ids = { 1082, 3029, 5201, 9849, 9850 } },
    SHRED           = { name = "Shred",            id = 5221,    ids = { 5221, 6800, 8992, 9829, 9830 } },
    RIP             = { name = "Rip",              id = 1079,    ids = { 1079, 9492, 9493, 9752, 9894, 9896 } },
    FEROCIOUS_BITE  = { name = "Ferocious Bite",   id = 22568,   ids = { 1328618, 22568, 22827, 22828, 22829, 31018 } },
    LACERATE        = { name = "Lacerate",         id = 1235827, ids = { 1328617, 1328616, 414644, 1235826, 1235827, 1299332 } },
    PRIMAL_BITE     = { name = "Primal Bite",      id = 1238070, ids = { 407995, 1238069, 1238070, 1238073 } },
    BARKSKIN        = { name = "Barkskin",         id = 22812,   ids = { 22812 } },
    FRENZIED_REGEN  = { name = "Frenzied Regeneration", id = 22842, ids = { 22842 } },
    RAKE            = { name = "Rake",             id = 1822,    ids = { 1822, 1823, 1824, 9904 } },
    RAVAGE          = { name = "Ravage",           id = 6785,    ids = { 6785, 6787, 9866, 9867 } },
    TIGERS_FURY     = { name = "Tiger's Fury",     id = 5217,    ids = { 5217 } },

    -- Shaman
    FLAME_SHOCK     = { name = "Flame Shock",      id = 8050,    ids = { 8050, 8052, 8053, 10447, 10448, 29228 } },
    STORMSTRIKE     = { name = "Stormstrike",      id = 17364,   ids = { 17364 } },
    EARTH_SHOCK     = { name = "Earth Shock",      id = 8042,    ids = { 8042, 8044, 8045, 8046, 10412, 10413, 10414 } },
    FIRE_NOVA       = { name = "Fire Nova",        id = 408345,  ids = { 408341, 408342, 408343, 408344, 408345 } },
    LIGHTNING_BOLT  = { name = "Lightning Bolt",   id = 403,     ids = { 403, 529, 548, 915, 943, 6041, 10391, 10392, 15207, 15208, 408439, 408440, 408441, 408442, 408443, 408472, 408473, 408474, 408475, 408477 } },
    LIGHTNING_SHIELD = { name = "Lightning Shield", id = 324,    ids = { 324, 325, 905, 945, 8134, 10431, 10432 } },
    WATER_SHIELD    = { name = "Water Shield",     id = 408510,  ids = { 408510 } },
    SEARING_TOTEM   = { name = "Searing Totem",    id = 3599,    ids = { 3599, 6363, 6364, 6365, 10437, 10438 } },
    STRENGTH_OF_EARTH = { name = "Strength of Earth Totem", id = 8075, ids = { 8075, 8160, 8161, 10442, 25361 } },
}

-- Registry by Class for /st diag in-game auditing
FG.SPELLS_BY_CLASS = {
    HUNTER = {
        FG.SPELLS.SERPENT_STING, FG.SPELLS.RAPTOR_STRIKE, FG.SPELLS.STRIDER_KICK,
        FG.SPELLS.MONGOOSE_BITE, FG.SPELLS.HUNTERS_MARK, FG.SPELLS.ARCANE_SHOT,
        FG.SPELLS.MULTI_SHOT, FG.SPELLS.WING_CLIP, FG.SPELLS.IMMOLATION_TRAP,
        FG.SPELLS.AIMED_SHOT, FG.SPELLS.SNIPER_SHOT, FG.SPELLS.SUMMON_HAWK,
        FG.SPELLS.ASPECT_HAWK,
    },
    WARRIOR = {
        FG.SPELLS.HEROIC_STRIKE, FG.SPELLS.REND, FG.SPELLS.OVERPOWER,
        FG.SPELLS.BLOODTHRILL, FG.SPELLS.MORTAL_STRIKE, FG.SPELLS.BLOODTHIRST,
        FG.SPELLS.WHIRLWIND, FG.SPELLS.EXECUTE, FG.SPELLS.SLAM,
        FG.SPELLS.SUNDER_ARMOR, FG.SPELLS.THUNDER_CLAP, FG.SPELLS.DEMO_SHOUT,
        FG.SPELLS.REVENGE, FG.SPELLS.SHIELD_SLAM, FG.SPELLS.SHIELD_BLOCK,
        FG.SPELLS.SHIELD_WALL, FG.SPELLS.LAST_STAND, FG.SPELLS.HAMSTRING, FG.SPELLS.CLEAVE,
        FG.SPELLS.BATTLE_SHOUT,
    },
    PALADIN = {
        FG.SPELLS.HOLY_STRIKE, FG.SPELLS.JUDGEMENT, FG.SPELLS.SEAL_RIGHTEOUSNESS,
        FG.SPELLS.SEAL_COMMAND, FG.SPELLS.SEAL_CRUSADER, FG.SPELLS.SEAL_FURY,
        FG.SPELLS.CONSECRATION, FG.SPELLS.EXORCISM, FG.SPELLS.HAMMER_OF_WRATH,
        FG.SPELLS.HOLY_SHOCK, FG.SPELLS.DIVINE_FAVOR, FG.SPELLS.HOLY_SHIELD,
        FG.SPELLS.RIGHTEOUS_FURY,
    },
    ROGUE = {
        FG.SPELLS.SINISTER_STRIKE, FG.SPELLS.EVISCERATE, FG.SPELLS.SLICE_AND_DICE,
        FG.SPELLS.RUPTURE, FG.SPELLS.MUTILATE, FG.SPELLS.HEMORRHAGE,
        FG.SPELLS.BACKSTAB, FG.SPELLS.RIPOSTE, FG.SPELLS.ENVENOM, FG.SPELLS.EXPOSE_ARMOR,
    },
    DRUID = {
        FG.SPELLS.MAUL, FG.SPELLS.SWIPE, FG.SPELLS.DEMO_ROAR, FG.SPELLS.ENRAGE,
        FG.SPELLS.FAERIE_FIRE_FERAL, FG.SPELLS.CLAW, FG.SPELLS.SHRED,
        FG.SPELLS.RIP, FG.SPELLS.FEROCIOUS_BITE, FG.SPELLS.LACERATE,
        FG.SPELLS.PRIMAL_BITE, FG.SPELLS.BARKSKIN, FG.SPELLS.FRENZIED_REGEN,
        FG.SPELLS.RAKE, FG.SPELLS.RAVAGE, FG.SPELLS.TIGERS_FURY,
    },
    SHAMAN = {
        FG.SPELLS.FLAME_SHOCK, FG.SPELLS.STORMSTRIKE, FG.SPELLS.EARTH_SHOCK,
        FG.SPELLS.FIRE_NOVA, FG.SPELLS.LIGHTNING_BOLT, FG.SPELLS.LIGHTNING_SHIELD,
        FG.SPELLS.WATER_SHIELD, FG.SPELLS.SEARING_TOTEM, FG.SPELLS.STRENGTH_OF_EARTH,
    },
}

local SPELL_KEY_BY_NAME = {
    -- Paladin
    ["Holy Strike"] = "holy_strike",
    ["Judgement"] = "judge",
    ["Seal of Righteousness"] = "sor",
    ["Seal of Command"] = "soc",
    ["Seal of the Crusader"] = "sotc",
    ["Seal of Fury"] = "sof",
    ["Consecration"] = "consecration",
    ["Exorcism"] = "exorcism",
    ["Hammer of Wrath"] = "how",
    ["Holy Shock"] = "holy_shock",
    ["Divine Favor"] = "divine_favor",
    ["Holy Shield"] = "holy_shield",
    ["Righteous Fury"] = "rf",
    ["Crusader Strike"] = "cs",

    -- Warrior
    ["Heroic Strike"] = "hs",
    ["Rend"] = "rend",
    ["Overpower"] = "op",
    ["Bloodthrill"] = "bloodthrill",
    ["Mortal Strike"] = "ms",
    ["Bloodthirst"] = "bt",
    ["Whirlwind"] = "ww",
    ["Execute"] = "execute",
    ["Slam"] = "slam",
    ["Sunder Armor"] = "sunder",
    ["Thunder Clap"] = "thunder_clap",
    ["Demoralizing Shout"] = "demo_shout",
    ["Revenge"] = "revenge",
    ["Shield Slam"] = "shield_slam",
    ["Shield Block"] = "shield_block",
    ["Shield Wall"] = "shield_wall",
    ["Last Stand"] = "last_stand",
    ["Hamstring"] = "hamstring",
    ["Cleave"] = "cleave",
    ["Battle Shout"] = "battle_shout",

    -- Hunter
    ["Serpent Sting"] = "serpent",
    ["Raptor Strike"] = "raptor",
    ["Strider Kick"] = "strider_kick",
    ["Mongoose Bite"] = "mongoose_bite",
    ["Hunter's Mark"] = "hunters_mark",
    ["Arcane Shot"] = "arcane",
    ["Multi-Shot"] = "multi",
    ["Wing Clip"] = "wing_clip",
    ["Immolation Trap"] = "immolation_trap",
    ["Aimed Shot"] = "aimed",
    ["Sniper Shot"] = "sniper",
    ["Summon Hawk"] = "hawk",
    ["Aspect of the Hawk"] = "aspect_hawk",

    -- Rogue
    ["Sinister Strike"] = "ss",
    ["Eviscerate"] = "eviscerate",
    ["Slice and Dice"] = "snd",
    ["Rupture"] = "rupture",
    ["Mutilate"] = "mutilate",
    ["Hemorrhage"] = "hemo",
    ["Backstab"] = "backstab",
    ["Riposte"] = "riposte",
    ["Venom"] = "envenom",
    ["Expose Armor"] = "expose",

    -- Druid
    ["Maul"] = "maul",
    ["Swipe"] = "swipe",
    ["Demoralizing Roar"] = "demo_roar",
    ["Enrage"] = "enrage",
    ["Faerie Fire (Feral)"] = "faerie_fire",
    ["Claw"] = "claw",
    ["Shred"] = "shred",
    ["Rip"] = "rip",
    ["Ferocious Bite"] = "bite",
    ["Lacerate"] = "lacerate",
    ["Primal Bite"] = "primal_bite",
    ["Barkskin"] = "barkskin",
    ["Frenzied Regeneration"] = "frenzied_regen",
    ["Rake"] = "rake",
    ["Ravage"] = "ravage",
    ["Tiger's Fury"] = "tigers_fury",

    -- Shaman
    ["Flame Shock"] = "flameshock",
    ["Stormstrike"] = "stormstrike",
    ["Earth Shock"] = "earthshock",
    ["Fire Nova"] = "firenova",
    ["Lightning Bolt"] = "weave",
    ["Lightning Shield"] = "lightningshield",
    ["Water Shield"] = "watershield",
    ["Searing Totem"] = "searing",
    ["Strength of Earth Totem"] = "strength_of_earth",
}

FG.SPELLS_BY_NAME = {}
for _, sp in pairs(FG.SPELLS) do
    if type(sp) == "table" and sp.name then
        FG.SPELLS_BY_NAME[sp.name] = sp
    end
end

function FG.get_hud_slots(class)
    class = class or "WARRIOR"
    local list = FG.SPELLS_BY_CLASS[class]
    if not list then return nil end
    local slots = {}
    for i = 1, #list do
        local sp = list[i]
        local key = SPELL_KEY_BY_NAME[sp.name] or string.lower(sp.name:gsub("%s+", "_"))
        slots[#slots + 1] = {
            key = key,
            title = sp.name,
            kind = "spell",
            spell = sp.id,
            spell_name = sp.name,
            ids = sp.ids,
        }
    end
    slots[#slots + 1] = { key = "trinket1", title = "Trinket 1", kind = "trinket", inv_slot = 13 }
    slots[#slots + 1] = { key = "trinket2", title = "Trinket 2", kind = "trinket", inv_slot = 14 }
    return slots
end

-- The guide's slot keys are the evaluator's action names; a few differ from the
-- HUD slot keys (SPELL_KEY_BY_NAME), which stay untouched (hud_show_<key> toggles).
local GUIDE_KEY_OVERRIDE = {
    ["Raptor Strike"] = "raptor_strike",
    ["Expose Armor"] = "ea",
    ["Demoralizing Roar"] = "demoralizing_roar",
    ["Ferocious Bite"] = "ferocious_bite",
}

-- D5 (audit 2026-11-05): cooldown swipe keys for the guide frame. nextaction_ui
-- derives the per-frame field names as cooldown_key .. "_remaining" / "_duration" /
-- "_expires" (nextaction_ui.lua:383-387) and only arms set_icon_cooldown for slots
-- that name one (nextaction_ui.lua:727-740), so a slot without cooldown_key never
-- swipes. Keys are keyed by the guide slot key (post-GUIDE_KEY_OVERRIDE) and name
-- the input the class gather feeds on Forever: the CD_SPELL_BY_FIELD entry minus
-- the "_remaining" suffix. Spells with no cooldown input (dots, seals, rage dumps,
-- procs, maintains that ride a due flag, rogue energy spenders - the class side
-- carries no cooldown_key for those either) stay keyless. swipe_duration is the
-- display fallback only (classes/warrior.lua:913-914: a real cooldown always
-- carries the client-reported length); values are the class slots' own stated
-- fallbacks, otherwise the 1.5 s frame-safe generic (marked FALLBACK below - an
-- unwritten remaining read is a proven no-op in set_icon_cooldown, never a wrong
-- swipe). Hunter gathers feed <base>_remaining_cd, which the frame's
-- cooldown_key .. "_remaining" shape cannot address, so hunter keys are structural
-- until the gather names align (filed follow-up); the sniper and multi keys do
-- resolve today through the gather's live-cast <base>_remaining feeds.
local FG_GUIDE_SWIPE = {
    -- Warrior (classes/warrior.lua:3674-3699: 1.5 s display fallback convention;
    -- thunder_clap slot ibid.:964-965; the gather feeds <key>_remaining pairs).
    op = { "op", 1.5 },
    ms = { "ms", 1.5 }, -- FALLBACK (no class-stated value; client length wins)
    bt = { "bt", 1.5 }, -- FALLBACK (no class-stated value; client length wins)
    ww = { "ww", 1.5 }, -- FALLBACK (no class-stated value; client length wins)
    execute = { "execute", 1.5 },
    slam = { "slam", 1.5 },
    thunder_clap = { "tc", 1.5 },
    demo_shout = { "demo", 1.5 }, -- FALLBACK (no class-stated value)
    revenge = { "revenge", 1.5 }, -- FALLBACK (no class-stated value)
    shield_slam = { "shield_slam", 1.5 }, -- FALLBACK (no class-stated value)
    shield_block = { "shield_block", 1.5 }, -- FALLBACK (no class-stated value)
    shield_wall = { "shield_wall", 1.5 }, -- FALLBACK (no class-stated value)
    last_stand = { "last_stand", 1.5 }, -- FALLBACK (no class-stated value)
    -- Paladin (classes/paladin.lua:3842-3867 ret set, 4025-4044 prot set).
    holy_strike = { "holy_strike", 1.5 }, -- FALLBACK (Forever sim: no cooldown; dark)
    judge = { "judge", 8 },
    consecration = { "consecration", 8 },
    exorcism = { "exorcism", 15 },
    how = { "how", 6 },
    holy_shock = { "holy_shock", 1.5 }, -- FALLBACK (no class-stated value; dark on Forever)
    divine_favor = { "divine_favor", 1.5 }, -- FALLBACK (no class-stated value)
    holy_shield = { "holy_shield", 10 },
    -- Hunter (structural until the gather names align - see note above; aimed and
    -- sniper durations are the class slots' own: classes/hunter.lua:2686,2704-2705;
    -- multi rides the live-cast feed at the classic 0.5 s cast - FALLBACK,
    -- unverified for Forever).
    raptor_strike = { "raptor_strike", 1.5 },
    mongoose_bite = { "mongoose_bite", 1.5 },
    strider_kick = { "strider_kick", 1.5 },
    immolation_trap = { "immolation_trap", 1.5 },
    hawk = { "summon_hawk", 1.5 },
    wing_clip = { "wing_clip", 1.5 },
    aspect_hawk = { "hawk", 1.5 },
    arcane = { "arcane", 1.5 },
    multi = { "multi", 0.5 },
    aimed = { "aimed", 3.0 },
    sniper = { "sniper", 4.0 },
    -- Druid (frenzied_regen duration is the class slot's own:
    -- classes/druid.lua:2341-2342; the rest are FALLBACK/display-only).
    enrage = { "enrage", 1.5 },
    primal_bite = { "primal_bite", 1.5 },
    barkskin = { "barkskin", 1.5 },
    frenzied_regen = { "frenzied_regen", 180 },
    -- Shaman (stormstrike 10 s: classes/shaman.lua:118-124, families with no
    -- sourced value keep the shipped 10 s; flameshock 12 s and firenova 15 s are
    -- the class slots' own: classes/shaman.lua:2948-2949,2952. flameshock follows
    -- the class's debuff-window convention (flameshock_remaining), not the map's
    -- shared shock global (shock_remaining).)
    stormstrike = { "stormstrike", 10 },
    flameshock = { "flameshock", 12 },
    firenova = { "firenova", 15 },
}

function FG.get_guide_slots(class)
    class = class or "WARRIOR"
    local list = FG.SPELLS_BY_CLASS[class]
    if not list then return nil end
    local slots = {}
    for i = 1, #list do
        local sp = list[i]
        local key = GUIDE_KEY_OVERRIDE[sp.name] or SPELL_KEY_BY_NAME[sp.name] or string.lower(sp.name:gsub("%s+", "_"))
        local swipe = FG_GUIDE_SWIPE[key]
        slots[#slots + 1] = {
            key = key,
            spell_id = sp.id,
            spell_name = sp.name,
            name_suffix = "Icon" .. key,
            ids = sp.ids,
            cooldown_key = swipe and swipe[1] or nil,
            swipe_duration = swipe and swipe[2] or nil,
        }
    end
    if class == "PALADIN" then
        slots[#slots + 1] = {
            key = "twist",
            spell_id = 20375,
            name_suffix = "TwistLeft",
            level = 8,
            overlay = {
                spell_id = 20293,
                name_suffix = "TwistRight",
                size = { 22.5, 45 },
                offset = { 11.25, 0 },
                keep_aspect = true,
            },
        }
        slots[#slots + 1] = { key = "sob", spell_id = 20293, name_suffix = "IconBlood", level = 5 }
        slots[#slots + 1] = { key = "cs", spell_id = 35395, name_suffix = "IconCS", level = 1 }
    elseif class == "ROGUE" then
        slots[#slots + 1] = { key = "builder", name_suffix = "IconBuilder" }
    end
    return slots
end

local fg_hud_state_reused = {}
function FG.get_hud_state(class, self, slot, now)
    if type(class) == "table" then
        now = slot
        slot = self
        self = class
    end
    if not slot or slot.kind == "trinket" then return nil end
    local api = st and st.api
    if not api then return nil end
    now = now or (api.get_time and api.get_time() or 0)
    local spell_query = slot.spell_name or slot.spell
    if not spell_query then return nil end

    local rem, dur = 0, 0
    local start, duration
    -- The fifth return is compat's restriction flag: true only when the client handed
    -- back secret timing and no readable fallback answered. It is nil on every
    -- classic-line family, so the classic read below is untouched by it.
    local restricted, _
    if api.GetSpellCooldown then
        start, duration, _, _, restricted = api.GetSpellCooldown(spell_query)
        if canaccessvalue(duration) then
            if (not start or duration == 0) and slot.spell then
                local fb_restricted
                start, duration, _, _, fb_restricted = api.GetSpellCooldown(slot.spell)
                -- This slot's own spell id is the final answer for the slot: a readable
                -- fallback (zeros included) means the timing IS known, so its verdict
                -- replaces the name query's flag instead of only ever setting it.
                if restricted then
                    restricted = fb_restricted == true
                end
            end
        end
        if canaccessallvalues(duration, start) then
            if start and duration and duration > 0 and start > 0 then
                rem = (start + duration) - now
                if rem < 0 then rem = 0 end
                dur = duration
            end
        end
    end
    -- A restricted read with no readable duration is unknown, not ready: rem/dur stay
    -- 0 (no swipe invented from the secret value) and the state carries the flag so a
    -- consumer can render unknown instead of an idle slot. The GCD echo below is
    -- skipped as well - a swipe that expires still reads as "ready". Classic-line
    -- families always pass restricted == nil, so nothing there changes.
    local restricted_state = restricted == true and dur <= 0

    -- If ability is not on cooldown, show the running GCD swipe. The addon already
    -- tracks the GCD (self.gcd, as every class hud_gcd_remaining does), so read that
    -- instead of re-asking the client once per slot per tick; the probe query is only
    -- the fallback when no tracked GCD exists.
    local gcd_object, gcd_on_gcd
    if rem <= 0 and not restricted_state then
        local g = self and self.gcd
        if type(g) == "table" and type(g.expires) == "number" then
            local g_rem = g.expires - now
            if g_rem > 0 then
                rem = g_rem
                dur = g.spell_length or g.duration or 1.5
            end
        elseif type(g) == "table" and g.gcd_object ~= nil then
            -- Forever object channel (2026-11-09): while cooldown timing is restricted the
            -- numeric expiry is absent, but LibGlobalCooldown carries the opaque GCD handle.
            -- Hand it to paint; it feeds the native sink and never reads a number.
            gcd_object = g.gcd_object
            gcd_on_gcd = g.gcd_on_gcd == true
        elseif api.GetSpellCooldown then
            local g_probe = (st and st.gcd_probe_spell_id) or 61304
            local g_start, g_dur = api.GetSpellCooldown(g_probe)
            if canaccessallvalues(g_dur, g_start) then
                if g_start and g_dur and g_dur > 0 and g_dur <= 1.51 and g_start > 0 then
                    local g_rem = (g_start + g_dur) - now
                    if g_rem > 0 then
                        rem = g_rem
                        dur = g_dur
                    end
                end
            end
        end
    end

    local usable = true
    if api.IsSpellUsable then
        local ok, is_usable, no_mana = pcall(api.IsSpellUsable, spell_query)
        if (not ok or is_usable == nil) and slot.spell then
            ok, is_usable, no_mana = pcall(api.IsSpellUsable, slot.spell)
        end
        if ok and (is_usable == false or no_mana == true) then
            usable = false
        end
    end

    local in_range = true
    if api.IsSpellInRange and UnitExists and UnitExists("target") then
        local ok, r = pcall(api.IsSpellInRange, spell_query, "target")
        if (not ok or r == nil) and slot.spell then
            ok, r = pcall(api.IsSpellInRange, slot.spell, "target")
        end
        if ok and r == 0 then
            in_range = false
        end
    end

    -- Dynamic proc / condition glow
    local glow = false
    local k = slot.key
    if k == "exorcism" then
        if rem <= 0 and UnitExists and UnitExists("target") then
            -- SEC-3/M6 (2026-11-06): the creature type is an identity read and is
            -- restricted on Mainline-code clients. api.UnitCreatureType answers nil when
            -- it cannot be read; nil is UNKNOWN, not "not undead", so no undead/demon
            -- specific cue is emitted from a fact we do not have.
            local creature_type = api.UnitCreatureType and api.UnitCreatureType("target")
            if creature_type == "Undead" or creature_type == "Demon" then
                glow = true
            end
        end
    elseif k == "how" then
        if rem <= 0 and UnitExists and UnitExists("target") then
            local hp_fn = api.UnitHealth or UnitHealth
            local max_fn = api.UnitHealthMax or UnitHealthMax
            local max_hp = max_fn and max_fn("target")
            local hp = hp_fn and hp_fn("target")
            if type(max_hp) == "number" and max_hp > 0 and type(hp) == "number" and (hp / max_hp) < 0.2 then
                glow = true
            end
        end
    elseif k == "execute" then
        if rem <= 0 and UnitExists and UnitExists("target") then
            local hp_fn = api.UnitHealth or UnitHealth
            local max_fn = api.UnitHealthMax or UnitHealthMax
            local max_hp = max_fn and max_fn("target")
            local hp = hp_fn and hp_fn("target")
            if type(max_hp) == "number" and max_hp > 0 and type(hp) == "number" and (hp / max_hp) < 0.2 then
                glow = true
            end
        end
    elseif k == "op" or k == "revenge" or k == "riposte" or k == "mongoose_bite" then
        if rem <= 0 and usable then
            glow = true
        end
    end

    fg_hud_state_reused.remaining = rem
    fg_hud_state_reused.duration = dur
    fg_hud_state_reused.text_remaining = (rem > 0 and dur > 2) and rem or nil
    fg_hud_state_reused.desaturate = (rem > 0 and dur > 1.51) and true or false
    fg_hud_state_reused.usable = usable
    fg_hud_state_reused.in_range = in_range
    fg_hud_state_reused.glow = glow
    fg_hud_state_reused.hidden = nil
    fg_hud_state_reused.restricted = nil
    -- Forever GCD object channel (plain handle + plain NeverSecret bool); the HUD uses it
    -- only when it is present, and the object path never reads a number out of it.
    fg_hud_state_reused.cooldown_object = gcd_object
    fg_hud_state_reused.on_gcd = gcd_object ~= nil and gcd_on_gcd or nil
    if restricted_state then
        fg_hud_state_reused.restricted = true
    end

    return fg_hud_state_reused
end

--=========================================================================================
-- Spec Resolvers (detects active spec for each class on WoW Forever)
-- Leveling characters without talents smoothly resolve to "general" baseline
--=========================================================================================
function FG.resolve_warrior_spec(inputs)
    inputs = inputs or {}
    if inputs.is_shield_equipped == true or inputs.has_shield == true or is_known(inputs, "Shield Slam", "shield_slam_known") or inputs.prot == true then
        return "prot"
    elseif is_known(inputs, "Mortal Strike", "ms_known") then
        return "arms"
    elseif is_known(inputs, "Bloodthirst", "bt_known") then
        return "fury"
    else
        return "general"
    end
end

function FG.resolve_paladin_spec(inputs)
    inputs = inputs or {}
    if inputs.is_shield_equipped == true or inputs.has_shield == true
        or inputs.fcfs_mode == "prot_forever" or inputs.fcfs_mode == "prot"
        or is_known(inputs, "Holy Shield", "holy_shield_known") then
        return "prot"
    elseif is_known(inputs, "Holy Shock", "holy_shock_known") then
        return "shockadin"
    elseif is_known(inputs, "Seal of Command", "soc_known") then
        return "ret"
    else
        return "general"
    end
end

function FG.resolve_hunter_spec(inputs)
    if is_known(inputs, "Strider Kick", "strider_kick_known") or inputs.melee_spec == true then
        return "melee"
    else
        return "ranged"
    end
end

function FG.resolve_rogue_spec(inputs)
    if is_known(inputs, "Mutilate", "mutilate_known") then
        return "mutilate"
    elseif is_known(inputs, "Hemorrhage", "hemo_known") then
        return "hemo"
    elseif inputs.mh_is_dagger == true then
        return "combat_bs"
    else
        return "combat_ss"
    end
end

function FG.resolve_druid_spec(inputs)
    inputs = inputs or {}
    if inputs.form == "bear" or inputs.shapeshift_form == 1 or inputs.form_index == 1 then
        return "bear"
    elseif inputs.form == "cat" or inputs.shapeshift_form == 3 or inputs.form_index == 3 then
        return "cat"
    else
        return "caster"
    end
end

function FG.resolve_shaman_spec(inputs)
    if is_known(inputs, "Stormstrike", "stormstrike_known") or is_known(inputs, "Maelstrom Weapon", "mw_known") then
        return "enhancement"
    else
        return "general"
    end
end

--=========================================================================================
-- 1. WARRIOR (Protection, Arms, Fury, General Leveling)
-- Based on wowsims/forever warrior APLs: arms.apl.json, fury.apl.json, protection/default.apl.json
--=========================================================================================
function FG.evaluate_warrior(spec, inputs, out)
    inputs = inputs or {}
    out = out or {}
    spec = spec or FG.resolve_warrior_spec(inputs)
    local rage = type(inputs.rage) == "number" and inputs.rage or 0
    local hp_pct = type(inputs.target_health_pct) == "number" and inputs.target_health_pct or 100
    local is_execute = hp_pct < (inputs.execute_pct or 20) or inputs.victory_rush == true

    out.rotation_key = spec

    -- D4 (audit 2026-11-05, filed skeleton): the target_count arms below (prot
    -- Thunder Clap, the three Cleave arms) have no Forever producer - the enemy-
    -- count sensor does not exist (classes/warrior.lua:437-445; the gather never
    -- feeds target_count on any family), so they are unreachable in-game. They
    -- stay pinned for direct callers (tests/forever_guide_state.lua:84-85) until
    -- the sensor lands; removal would widen the fallthrough arms at evaluator
    -- level, so this lane keeps them and documents the gap instead.

    if spec == "prot" then
        -- PROTECTION WARRIOR (Tank) - wowsims/forever warrior protection/default.apl.json
        local player_hp = type(inputs.player_health_pct) == "number" and inputs.player_health_pct or 100
        if is_known(inputs, "Shield Wall", "shield_wall_known") and player_hp <= 35 and is_ready(inputs.shield_wall_remaining) then
            out.action = "shield_wall"
            out.spell_name = "Shield Wall"
        elseif is_known(inputs, "Last Stand", "last_stand_known") and player_hp <= 40 and is_ready(inputs.last_stand_remaining) then
            out.action = "last_stand"
            out.spell_name = "Last Stand"
        elseif is_known(inputs, "Shield Block", "shield_block_known") and (inputs.shield_block_active ~= true) and is_ready(inputs.shield_block_remaining) and rage >= 10 then
            out.action = "shield_block"
            out.spell_name = "Shield Block"
        elseif is_known(inputs, "Shield Slam", "shield_slam_known") and is_ready(inputs.shield_slam_remaining) and rage >= 20 then
            out.action = "shield_slam"
            out.spell_name = "Shield Slam"
        elseif is_known(inputs, "Bloodthirst", "bt_known") and is_ready(inputs.bt_remaining) and rage >= 30 then
            out.action = "bt"
            out.spell_name = "Bloodthirst"
        elseif is_known(inputs, "Mortal Strike", "ms_known") and is_ready(inputs.ms_remaining) and rage >= 30 then
            out.action = "ms"
            out.spell_name = "Mortal Strike"
        elseif is_known(inputs, "Revenge", "revenge_known") and inputs.revenge_usable == true and is_ready(inputs.revenge_remaining) and rage >= 5 then
            out.action = "revenge"
            out.spell_name = "Revenge"
        elseif is_known(inputs, "Sunder Armor", "sunder_known") and (type(inputs.sunder_stacks) ~= "number" or inputs.sunder_stacks < 5 or (type(inputs.sunder_remaining) == "number" and inputs.sunder_remaining <= 10)) and rage >= 15 then
            out.action = "sunder"
            out.spell_name = "Sunder Armor"
        -- D4 (filed): no Forever target_count producer - unreachable in-game.
        elseif is_known(inputs, "Thunder Clap", "tc_known") and (inputs.tc_active ~= true) and is_ready(inputs.tc_remaining) and (inputs.target_count and inputs.target_count > 1) and rage >= 20 then
            out.action = "thunder_clap"
            out.spell_name = "Thunder Clap"
        elseif is_known(inputs, "Demoralizing Shout", "demo_known") and (inputs.demo_active ~= true) and is_ready(inputs.demo_remaining) and rage >= 10 then
            out.action = "demo_shout"
            out.spell_name = "Demoralizing Shout"
        elseif is_known(inputs, "Rend", "rend_known") and inputs.rend_active ~= true and rage >= 10 then
            out.action = "rend"
            out.spell_name = "Rend"
        elseif inputs.hs_queued == true or inputs.cleave_queued == true then
            out.hold = true
            out.hold_text = "RIDE"
        -- D4 (filed): no Forever target_count producer - the cleave leg is
        -- unreachable in-game; without it this arm is the hs dump.
        elseif rage >= (inputs.hs_rage_floor or 40) or (inputs.shield_slam_known ~= true and inputs.sunder_known ~= true and rage >= (inputs.hs_cost or 15)) then
            out.action = (inputs.target_count and inputs.target_count > 1 and is_known(inputs, "Cleave", "cleave_known")) and "cleave" or "hs"
            out.spell_name = out.action == "cleave" and "Cleave" or "Heroic Strike"
        else
            out.hold = true
            out.hold_text = "HOLD"
        end
        return out
    end

    if spec == "arms" then
        -- ARMS WARRIOR
        local op_proc = (type(inputs.overpower_remaining) == "number" and inputs.overpower_remaining > 0) or inputs.bloodthrill_active == true
        if is_known(inputs, "Overpower", "op_known") and op_proc and is_ready(inputs.op_remaining) and rage >= 5 then
            out.action = "op"
            out.spell_name = "Overpower"
        elseif is_known(inputs, "Mortal Strike", "ms_known") and is_ready(inputs.ms_remaining) and rage >= 30 then
            out.action = "ms"
            out.spell_name = "Mortal Strike"
        elseif is_known(inputs, "Whirlwind", "ww_known") and is_ready(inputs.ww_remaining) and rage >= 25 then
            out.action = "ww"
            out.spell_name = "Whirlwind"
        elseif is_known(inputs, "Slam", "slam_known") and is_ready(inputs.slam_remaining) and rage >= 15 then
            out.action = "slam"
            out.spell_name = "Slam"
        elseif is_known(inputs, "Rend", "rend_known") and inputs.rend_active ~= true and not is_execute and rage >= 10 then
            out.action = "rend"
            out.spell_name = "Rend"
        elseif is_known(inputs, "Execute", "execute_known") and is_execute and is_ready(inputs.execute_remaining) and rage >= 15 then
            out.action = "execute"
            out.spell_name = "Execute"
        elseif inputs.hs_queued == true or inputs.cleave_queued == true then
            out.hold = true
            out.hold_text = "RIDE"
        -- D4 (filed): no Forever target_count producer - unreachable in-game.
        elseif is_known(inputs, "Cleave", "cleave_known") and inputs.target_count and inputs.target_count > 1 and rage >= 40 then
            out.action = "cleave"
            out.spell_name = "Cleave"
        elseif is_known(inputs, "Heroic Strike", "hs_known") and not is_execute and rage >= (inputs.hs_rage_floor or 90) then
            out.action = "hs"
            out.spell_name = "Heroic Strike"
        elseif is_known(inputs, "Hamstring", "hamstring_known") and rage >= 80 then
            out.action = "hamstring"
            out.spell_name = "Hamstring"
        elseif is_known(inputs, "Sunder Armor", "sunder_known") and (type(inputs.sunder_stacks) ~= "number" or inputs.sunder_stacks < 5) and rage >= 15 then
            out.action = "sunder"
            out.spell_name = "Sunder Armor"
        elseif rage < 15 then
            out.hold = true
            out.hold_text = "HOLD"
        end
        return out
    end

    if spec == "fury" then
        -- FURY WARRIOR
        local op_proc = (type(inputs.overpower_remaining) == "number" and inputs.overpower_remaining > 0) or inputs.bloodthrill_active == true
        if is_known(inputs, "Overpower", "op_known") and op_proc and is_ready(inputs.op_remaining) and rage >= 5 then
            out.action = "op"
            out.spell_name = "Overpower"
        elseif is_known(inputs, "Execute", "execute_known") and is_execute and is_ready(inputs.execute_remaining) and rage >= 15 then
            out.action = "execute"
            out.spell_name = "Execute"
        elseif is_known(inputs, "Bloodthirst", "bt_known") and is_ready(inputs.bt_remaining) and rage >= 30 then
            out.action = "bt"
            out.spell_name = "Bloodthirst"
        elseif is_known(inputs, "Whirlwind", "ww_known") and is_ready(inputs.ww_remaining) and rage >= 25 then
            out.action = "ww"
            out.spell_name = "Whirlwind"
        elseif inputs.hs_queued == true or inputs.cleave_queued == true then
            out.hold = true
            out.hold_text = "RIDE"
        -- D4 (filed): no Forever target_count producer - unreachable in-game.
        elseif is_known(inputs, "Cleave", "cleave_known") and inputs.target_count and inputs.target_count > 1 and rage >= 25 then
            out.action = "cleave"
            out.spell_name = "Cleave"
        elseif is_known(inputs, "Heroic Strike", "hs_known") and ((not is_execute and rage >= (inputs.hs_rage_floor or 40)) or rage >= 60) then
            out.action = "hs"
            out.spell_name = "Heroic Strike"
        elseif is_known(inputs, "Rend", "rend_known") and inputs.rend_active ~= true and not is_execute and rage >= 10 and inputs.rend_upkeep_enabled == true then
            out.action = "rend"
            out.spell_name = "Rend"
        elseif is_known(inputs, "Hamstring", "hamstring_known") and rage >= 80 then
            out.action = "hamstring"
            out.spell_name = "Hamstring"
        elseif is_known(inputs, "Sunder Armor", "sunder_known") and (type(inputs.sunder_stacks) ~= "number" or inputs.sunder_stacks < 5) and rage >= 15 then
            out.action = "sunder"
            out.spell_name = "Sunder Armor"
        elseif rage < 15 then
            out.hold = true
            out.hold_text = "HOLD"
        end
        return out
    end

    -- GENERAL LEVELING WARRIOR (Levels 1 - 39 without MS / BT)
    local op_proc = (type(inputs.overpower_remaining) == "number" and inputs.overpower_remaining > 0) or inputs.bloodthrill_active == true
    if is_known(inputs, "Overpower", "op_known") and op_proc and is_ready(inputs.op_remaining) and rage >= 5 then
        out.action = "op"
        out.spell_name = "Overpower"
    elseif is_known(inputs, "Execute", "execute_known") and is_execute and is_ready(inputs.execute_remaining) and rage >= 15 then
        out.action = "execute"
        out.spell_name = "Execute"
    elseif is_known(inputs, "Rend", "rend_known") and inputs.rend_active ~= true and not is_execute and rage >= 10 then
        out.action = "rend"
        out.spell_name = "Rend"
    elseif is_known(inputs, "Sunder Armor", "sunder_known") and (type(inputs.sunder_stacks) ~= "number" or inputs.sunder_stacks < 5) and rage >= 15 then
        out.action = "sunder"
        out.spell_name = "Sunder Armor"
    elseif inputs.hs_queued == true or inputs.cleave_queued == true then
        out.hold = true
        out.hold_text = "RIDE"
    elseif is_known(inputs, "Heroic Strike", "hs_known") and rage >= (inputs.hs_rage_floor or 30) then
        out.action = "hs"
        out.spell_name = "Heroic Strike"
    else
        out.hold = true
        out.hold_text = "HOLD"
    end
    return out
end

--=========================================================================================
-- 2. PALADIN (Protection, Retribution, Holy Shock, General Leveling)
-- Based on wowsims/forever paladin APLs: retribution/default.apl.siml, holy_shock.apl.siml, protection/default.apl.siml
--=========================================================================================
function FG.evaluate_paladin(spec, inputs, out)
    inputs = inputs or {}
    out = out or {}
    spec = spec or FG.resolve_paladin_spec(inputs)
    local mana_pct = type(inputs.mana_pct) == "number" and inputs.mana_pct or 100
    local target_hp = type(inputs.target_health_pct) == "number" and inputs.target_health_pct or 100

    out.rotation_key = spec

    if spec == "prot" then
        -- PROTECTION PALADIN (Tank) - wowsims/forever protection/default.apl.siml
        -- 1. Righteous Fury upkeep
        -- 2. Judgement
        -- 3. Seal of Fury (or SoR fallback) upkeep
        -- 4. Consecration
        -- 5. Holy Shock (if known)
        -- 6. Holy Shield
        -- 7. Holy Strike
        -- 8. Hammer of Wrath (execute)
        -- 9. Exorcism
        if inputs.has_rf ~= true and inputs.has_righteous_fury ~= true and is_known(inputs, "Righteous Fury", "rf_known") then
            out.action = "rf"
            out.spell_name = "Righteous Fury"
        elseif is_known(inputs, "Judgement", "judge_known") and is_ready(inputs.judge_remaining) then
            out.action = "judge"
            out.spell_name = "Judgement"
            out.judge_call = true
        elseif (inputs.seal_inactive == true or inputs.seal_active ~= true) and (is_known(inputs, "Seal of Fury", "sof_known") or is_known(inputs, "Seal of Righteousness", "seal_known") or inputs.seal_fury_known) then
            out.action = (is_known(inputs, "Seal of Fury", "sof_known") or inputs.seal_fury_known) and "sof" or "sor"
            out.spell_name = out.action == "sof" and "Seal of Fury" or "Seal of Righteousness"
        elseif is_known(inputs, "Consecration", "cons_known") and is_ready(inputs.cons_remaining) and mana_pct >= 10 then
            out.action = "consecration"
            out.spell_name = "Consecration"
        elseif is_known(inputs, "Holy Shock", "holy_shock_known") and is_ready(inputs.holy_shock_remaining) and mana_pct >= 10 then
            out.action = "holy_shock"
            out.spell_name = "Holy Shock"
        elseif is_known(inputs, "Holy Shield", "holy_shield_known") and is_ready(inputs.holy_shield_remaining) and mana_pct >= 10 then
            out.action = "holy_shield"
            out.spell_name = "Holy Shield"
        elseif is_known(inputs, "Holy Strike", "holy_strike_known") and is_ready(inputs.holy_strike_remaining) then
            out.action = "holy_strike"
            out.spell_name = "Holy Strike"
        elseif is_known(inputs, "Hammer of Wrath", "how_known") and target_hp < 20 and is_ready(inputs.how_remaining) then
            out.action = "how"
            out.spell_name = "Hammer of Wrath"
        elseif is_known(inputs, "Exorcism", "exo_known") and is_ready(inputs.exo_remaining) and mana_pct >= 20 then
            out.action = "exorcism"
            out.spell_name = "Exorcism"
        else
            out.hold = true
            out.hold_text = "WAIT"
        end
        return out
    end

    if spec == "shockadin" then
        -- HOLY SHOCK (Shockadin DPS) - wowsims/forever retribution/holy_shock.apl.siml
        -- 1. Judgement
        -- 2. Consecration
        -- 3. Seal of Righteousness / Command refresh
        -- 4. Holy Strike
        -- 5. Divine Favor (when Holy Shock ready)
        -- 6. Holy Shock
        -- 7. Hammer of Wrath (execute)
        -- 8. Exorcism
        if is_known(inputs, "Judgement", "judge_known") and is_ready(inputs.judge_remaining) then
            out.action = "judge"
            out.spell_name = "Judgement"
            out.judge_call = true
        elseif is_known(inputs, "Consecration", "cons_known") and is_ready(inputs.cons_remaining) and mana_pct >= 15 then
            out.action = "consecration"
            out.spell_name = "Consecration"
        elseif (inputs.seal_inactive == true or inputs.seal_active ~= true) and is_known(inputs, "Seal of Righteousness", "seal_known") then
            out.action = is_known(inputs, "Seal of Command", "soc_known") and "soc" or "sor"
            out.spell_name = out.action == "soc" and "Seal of Command" or "Seal of Righteousness"
        elseif is_known(inputs, "Holy Strike", "holy_strike_known") and is_ready(inputs.holy_strike_remaining) then
            out.action = "holy_strike"
            out.spell_name = "Holy Strike"
        elseif is_known(inputs, "Divine Favor", "divine_favor_known") and is_ready(inputs.divine_favor_remaining) and is_ready(inputs.holy_shock_remaining) then
            out.action = "divine_favor"
            out.spell_name = "Divine Favor"
        elseif is_known(inputs, "Holy Shock", "holy_shock_known") and is_ready(inputs.holy_shock_remaining) and mana_pct >= 10 then
            out.action = "holy_shock"
            out.spell_name = "Holy Shock"
        elseif is_known(inputs, "Hammer of Wrath", "how_known") and target_hp < 20 and is_ready(inputs.how_remaining) then
            out.action = "how"
            out.spell_name = "Hammer of Wrath"
        elseif is_known(inputs, "Exorcism", "exo_known") and is_ready(inputs.exo_remaining) and mana_pct >= 15 then
            out.action = "exorcism"
            out.spell_name = "Exorcism"
        else
            out.hold = true
            out.hold_text = "WAIT"
        end
        return out
    end

    if spec == "ret" then
        -- RETRIBUTION PALADIN - wowsims/forever retribution/default.apl.siml
        -- 1. Judgement (cast judgement if $wf_guard)
        -- 2. Hammer of Wrath (instant or execute < 20%)
        -- 3. Holy Strike (weaves when Judgement is on CD)
        -- 4. Seal of Command / Righteousness refresh
        -- 5. Consecration (mana >= 10%, Judgement & Holy Strike on CD)
        -- 6. Exorcism (mana >= 10%, Judgement & Holy Strike on CD)
        -- 7. Holy Strike fallback
        local how_instant = inputs.how_cast_seconds == 0 or (inputs.auto_age_seconds and inputs.auto_age_seconds < 0.2)
        if is_known(inputs, "Judgement", "judge_known") and is_ready(inputs.judge_remaining) then
            out.action = "judge"
            out.spell_name = "Judgement"
            out.judge_call = true
        elseif is_known(inputs, "Hammer of Wrath", "how_known") and (how_instant or target_hp < 20) and is_ready(inputs.how_remaining) then
            out.action = "how"
            out.spell_name = "Hammer of Wrath"
        elseif is_known(inputs, "Holy Strike", "holy_strike_known") and is_ready(inputs.holy_strike_remaining) and not is_ready(inputs.judge_remaining) then
            out.action = "holy_strike"
            out.spell_name = "Holy Strike"
        elseif (inputs.seal_inactive == true or inputs.seal_active ~= true) and (is_known(inputs, "Seal of Command", "soc_known") or is_known(inputs, "Seal of Righteousness", "seal_known")) then
            out.action = is_known(inputs, "Seal of Command", "soc_known") and "soc" or "sor"
            out.spell_name = out.action == "soc" and "Seal of Command" or "Seal of Righteousness"
        elseif is_known(inputs, "Consecration", "cons_known") and is_ready(inputs.cons_remaining) and mana_pct >= (inputs.mana_consecration_threshold or 10) and not is_ready(inputs.judge_remaining) and not is_ready(inputs.holy_strike_remaining) then
            out.action = "consecration"
            out.spell_name = "Consecration"
        elseif is_known(inputs, "Exorcism", "exo_known") and is_ready(inputs.exo_remaining) and mana_pct >= (inputs.mana_exorcism_threshold or 10) and not is_ready(inputs.judge_remaining) and not is_ready(inputs.holy_strike_remaining) then
            out.action = "exorcism"
            out.spell_name = "Exorcism"
        elseif is_known(inputs, "Holy Strike", "holy_strike_known") and is_ready(inputs.holy_strike_remaining) then
            out.action = "holy_strike"
            out.spell_name = "Holy Strike"
        elseif is_known(inputs, "Seal of Command", "soc_known") or is_known(inputs, "Seal of Righteousness", "seal_known") then
            out.action = is_known(inputs, "Seal of Command", "soc_known") and "soc" or "sor"
            out.spell_name = out.action == "soc" and "Seal of Command" or "Seal of Righteousness"
        else
            -- D1 (audit 2026-11-05): neither seal learned yet (levels 1-3) - hold,
            -- never prompt an unlearned Seal.
            out.hold = true
            out.hold_text = "WAIT"
        end
        return out
    end

    -- GENERAL LEVELING PALADIN (Baseline progression before Command / Shock)
    -- Levels 1-39: Seal upkeep -> Judgement -> Holy Strike -> HoW -> Consecration -> Exorcism
    if (inputs.seal_inactive == true or inputs.seal_active ~= true) and is_known(inputs, "Seal of Righteousness", "seal_known") then
        out.action = "sor"
        out.spell_name = "Seal of Righteousness"
    elseif is_known(inputs, "Judgement", "judge_known") and is_ready(inputs.judge_remaining) then
        out.action = "judge"
        out.spell_name = "Judgement"
        out.judge_call = true
    elseif is_known(inputs, "Holy Strike", "holy_strike_known") and is_ready(inputs.holy_strike_remaining) then
        out.action = "holy_strike"
        out.spell_name = "Holy Strike"
    elseif is_known(inputs, "Hammer of Wrath", "how_known") and target_hp < 20 and is_ready(inputs.how_remaining) then
        out.action = "how"
        out.spell_name = "Hammer of Wrath"
    elseif is_known(inputs, "Consecration", "cons_known") and is_ready(inputs.cons_remaining) and mana_pct >= 25 then
        out.action = "consecration"
        out.spell_name = "Consecration"
    elseif is_known(inputs, "Exorcism", "exo_known") and is_ready(inputs.exo_remaining) and mana_pct >= 20 then
        out.action = "exorcism"
        out.spell_name = "Exorcism"
    elseif is_known(inputs, "Seal of Righteousness", "seal_known") then
        out.action = "sor"
        out.spell_name = "Seal of Righteousness"
    else
        -- D1 (audit 2026-11-05): Seal of Righteousness not yet learned (levels
        -- 1-3) - hold, never prompt an unlearned Seal.
        out.hold = true
        out.hold_text = "WAIT"
    end
    return out
end

--=========================================================================================
-- 3. HUNTER (Melee Hunter, Ranged Hunter / Weave)
-- Based on wowsims/forever hunter APLs: melee.apl.siml, default.apl.siml, clean_weave.apl.siml
--=========================================================================================
function FG.evaluate_hunter(spec, inputs, out)
    inputs = inputs or {}
    out = out or {}
    spec = spec or FG.resolve_hunter_spec(inputs)
    local mana_pct = type(inputs.mana_fraction) == "number" and (inputs.mana_fraction * 100) or 100

    out.rotation_key = spec

    if spec == "melee" then
        -- MELEE HUNTER SPEC (Survival talent Strider Kick 1317257 or melee toggle)
        -- Based on wowsims/forever hunter/dps/melee.apl.siml
        if is_known(inputs, "Raptor Strike", "raptor_strike_known") and is_ready(inputs.raptor_strike_remaining_cd) then
            out.action = "raptor_strike"
            out.spell_name = "Raptor Strike"
        elseif is_known(inputs, "Hunter's Mark", "hunters_mark_known") and inputs.hunters_mark_active ~= true then
            out.action = "hunters_mark"
            out.spell_name = "Hunter's Mark"
        elseif is_known(inputs, "Mongoose Bite", "mongoose_bite_known") and inputs.mongoose_bite_usable == true and is_ready(inputs.mongoose_bite_remaining_cd) then
            out.action = "mongoose_bite"
            out.spell_name = "Mongoose Bite"
        elseif is_known(inputs, "Strider Kick", "strider_kick_known") and is_ready(inputs.strider_kick_remaining_cd) then
            out.action = "strider_kick"
            out.spell_name = "Strider Kick"
        elseif is_known(inputs, "Immolation Trap", "immolation_trap_known") and is_ready(inputs.immolation_trap_remaining_cd) then
            out.action = "immolation_trap"
            out.spell_name = "Immolation Trap"
        elseif is_known(inputs, "Summon Hawk", "summon_hawk_known") and is_ready(inputs.summon_hawk_remaining_cd) and (type(inputs.hawk_active_count) ~= "number" or inputs.hawk_active_count < 2) then
            out.action = "hawk"
            out.spell_name = "Summon Hawk"
        elseif is_known(inputs, "Wing Clip", "wing_clip_known") and (inputs.strider_kick_known ~= true or (type(inputs.strider_kick_remaining_cd) == "number" and inputs.strider_kick_remaining_cd > 1.5)) and is_ready(inputs.wing_clip_remaining_cd) then
            out.action = "wing_clip"
            out.spell_name = "Wing Clip"
        elseif is_known(inputs, "Aspect of the Hawk", "hawk_known") and is_ready(inputs.hawk_remaining_cd) and (type(inputs.hawk_active_count) ~= "number" or inputs.hawk_active_count < 3) then
            out.action = "aspect_hawk"
            out.spell_name = "Aspect of the Hawk"
        end
        return out
    end

    -- RANGED / WEAVE HUNTER (Default Leveling & Ranged)
    -- Based on wowsims/forever hunter/dps/clean_weave.apl.siml, default.apl.siml, turret.apl.siml
    local in_melee = inputs.weave_band == "melee" or (inputs.unit_distance and inputs.unit_distance <= 5)
    if in_melee then
        if is_known(inputs, "Raptor Strike", "raptor_strike_known") and is_ready(inputs.raptor_strike_remaining_cd) then
            out.action = "raptor_strike"
            out.spell_name = "Raptor Strike"
        elseif is_known(inputs, "Strider Kick", "strider_kick_known") and is_ready(inputs.strider_kick_remaining_cd) then
            out.action = "strider_kick"
            out.spell_name = "Strider Kick"
        elseif is_known(inputs, "Mongoose Bite", "mongoose_bite_known") and inputs.mongoose_bite_usable == true and is_ready(inputs.mongoose_bite_remaining_cd) then
            out.action = "mongoose_bite"
            out.spell_name = "Mongoose Bite"
        elseif is_known(inputs, "Immolation Trap", "immolation_trap_known") and is_ready(inputs.immolation_trap_remaining_cd) then
            out.action = "immolation_trap"
            out.spell_name = "Immolation Trap"
        elseif is_known(inputs, "Wing Clip", "wing_clip_known") and is_ready(inputs.wing_clip_remaining_cd) then
            out.action = "wing_clip"
            out.spell_name = "Wing Clip"
        end
        if out.action then return out end
    end

    -- Ranged Priority
    if is_known(inputs, "Hunter's Mark", "hunters_mark_known") and inputs.hunters_mark_active ~= true then
        out.action = "hunters_mark"
        out.spell_name = "Hunter's Mark"
    elseif is_known(inputs, "Serpent Sting", "serpent_known") and inputs.serpent_active ~= true and mana_pct >= 20 then
        out.action = "serpent"
        out.spell_name = "Serpent Sting"
    elseif is_known(inputs, "Arcane Shot", "arcane_known") and is_ready(inputs.arcane_remaining_cd) then
        out.action = "arcane"
        out.spell_name = "Arcane Shot"
    elseif is_known(inputs, "Multi-Shot", "multi_known") and is_ready(inputs.multi_remaining_cd) then
        out.action = "multi"
        out.spell_name = "Multi-Shot"
    elseif is_known(inputs, "Aimed Shot", "aimed_known") and is_ready(inputs.aimed_remaining_cd) then
        out.action = "aimed"
        out.spell_name = "Aimed Shot"
    elseif is_known(inputs, "Sniper Shot", "sniper_known") and is_ready(inputs.sniper_remaining_cd) then
        out.action = "sniper"
        out.spell_name = "Sniper Shot"
    elseif is_known(inputs, "Summon Hawk", "summon_hawk_known") and is_ready(inputs.summon_hawk_remaining_cd) and (type(inputs.hawk_active_count) ~= "number" or inputs.hawk_active_count < 2) then
        out.action = "hawk"
        out.spell_name = "Summon Hawk"
    elseif is_known(inputs, "Aspect of the Hawk", "hawk_known") and is_ready(inputs.hawk_remaining_cd) and (type(inputs.hawk_active_count) ~= "number" or inputs.hawk_active_count < 3) then
        out.action = "aspect_hawk"
        out.spell_name = "Aspect of the Hawk"
    else
        -- D2 (audit 2026-11-05): nothing known yet (early leveling) - hold
        -- instead of returning an empty out (blank guide).
        out.hold = true
        out.hold_text = "WAIT"
    end
    return out
end

--=========================================================================================
-- 4. ROGUE (Combat SS, Combat BS, Mutilate, Subtlety Hemo)
-- Based on wowsims/forever rogue APL: default.apl.json, presets.ts
--=========================================================================================
function FG.evaluate_rogue(spec, inputs, out)
    inputs = inputs or {}
    out = out or {}
    spec = spec or FG.resolve_rogue_spec(inputs)
    local cp = type(inputs.combo_points) == "number" and inputs.combo_points or 0
    local energy = type(inputs.energy) == "number" and inputs.energy or 0
    local snd_rem = type(inputs.snd_remaining) == "number" and inputs.snd_remaining or 0

    out.rotation_key = spec

    -- Defensive Riposte proc on parry/defensive state
    if is_known(inputs, "Riposte", "riposte_known") and inputs.riposte_usable == true and energy >= 10 then
        out.action = "riposte"
        out.spell_name = "Riposte"
        out.hold = true
        out.hold_text = "RIPOSTE"
        return out
    end

    -- Finishers at 4-5 CP, or 1-2 CP if SnD is missing entirely
    if snd_rem <= 0 and cp >= 1 and is_known(inputs, "Slice and Dice", "snd_known") then
        out.action = "snd"
        out.spell_name = "Slice and Dice"
        return out
    end

    if cp >= 4 or (cp >= 3 and snd_rem <= 2) then
        if is_known(inputs, "Expose Armor", "ea_known") and inputs.use_ea == true and inputs.ea_active ~= true then
            out.action = "ea"
            out.spell_name = "Expose Armor"
        elseif is_known(inputs, "Slice and Dice", "snd_known") and snd_rem <= 3 then
            out.action = "snd"
            out.spell_name = "Slice and Dice"
        elseif is_known(inputs, "Venom", "envenom_known") and inputs.envenom_usable == true then
            out.action = "envenom"
            out.spell_name = "Venom"
        elseif is_known(inputs, "Rupture", "rupture_known") and inputs.rupture_active ~= true and (inputs.ttd == nil or inputs.ttd >= 8) then
            out.action = "rupture"
            out.spell_name = "Rupture"
        elseif is_known(inputs, "Eviscerate", "eviscerate_known") then
            out.action = "eviscerate"
            out.spell_name = "Eviscerate"
        end
        if out.action then return out end
    end

    -- Builders
    if spec == "mutilate" and is_known(inputs, "Mutilate", "mutilate_known") then
        if energy >= (inputs.mutilate_cost or 60) then
            out.action = "mutilate"
            out.spell_name = "Mutilate"
        else
            out.hold = true
            out.hold_text = "POOL"
        end
    elseif (spec == "combat_bs" or spec == "sub_bs") and is_known(inputs, "Backstab", "backstab_known") then
        if energy >= (inputs.backstab_cost or 60) then
            out.action = "backstab"
            out.spell_name = "Backstab"
        else
            out.hold = true
            out.hold_text = "POOL"
        end
    elseif spec == "hemo" and is_known(inputs, "Hemorrhage", "hemo_known") then
        if energy >= (inputs.hemo_cost or 35) then
            out.action = "hemo"
            out.spell_name = "Hemorrhage"
        else
            out.hold = true
            out.hold_text = "POOL"
        end
    else
        -- Default: Sinister Strike (General Leveling builder)
        if is_known(inputs, "Sinister Strike", "ss_known") then
            if energy >= (inputs.ss_cost or 45) then
                out.action = "ss"
                out.spell_name = "Sinister Strike"
            else
                out.hold = true
                out.hold_text = "POOL"
            end
        end
    end
    return out
end

--=========================================================================================
-- 5. DRUID (Feral Bear, Feral Cat, Caster Baseline)
-- Based on wowsims/forever druid APLs: feralcat/adaptive.apl.json, feralbear/adaptive.apl.json
--=========================================================================================
function FG.evaluate_druid(spec, inputs, out)
    inputs = inputs or {}
    out = out or {}
    spec = spec or FG.resolve_druid_spec(inputs)

    out.rotation_key = spec

    if spec == "bear" then
        -- FERAL BEAR TANK - wowsims/forever feralbear/adaptive.apl.json
        local rage = type(inputs.rage) == "number" and inputs.rage or 0
        local hp_pct = type(inputs.player_health_pct) == "number" and inputs.player_health_pct or 100

        if is_known(inputs, "Barkskin", "barkskin_known") and hp_pct <= 40 and is_ready(inputs.barkskin_remaining) then
            out.action = "barkskin"
            out.spell_name = "Barkskin"
        elseif is_known(inputs, "Frenzied Regeneration", "frenzied_regen_known") and hp_pct <= 35 and is_ready(inputs.frenzied_regen_remaining) and rage >= 10 then
            out.action = "frenzied_regen"
            out.spell_name = "Frenzied Regeneration"
        elseif is_known(inputs, "Enrage", "enrage_known") and is_ready(inputs.enrage_remaining) and rage < 20 then
            out.action = "enrage"
            out.spell_name = "Enrage"
        elseif is_known(inputs, "Faerie Fire (Feral)", "faerie_fire_known") and inputs.faerie_fire_active ~= true then
            out.action = "faerie_fire"
            out.spell_name = "Faerie Fire (Feral)"
        elseif is_known(inputs, "Demoralizing Roar", "demo_roar_known") and inputs.demo_roar_active ~= true and rage >= 10 then
            out.action = "demoralizing_roar"
            out.spell_name = "Demoralizing Roar"
        elseif is_known(inputs, "Primal Bite", "primal_bite_known") and is_ready(inputs.primal_bite_remaining) and rage >= 25 then
            out.action = "primal_bite"
            out.spell_name = "Primal Bite"
        elseif is_known(inputs, "Lacerate", "lacerate_known") and (type(inputs.lacerate_stacks) ~= "number" or inputs.lacerate_stacks < 5 or (type(inputs.lacerate_remaining) == "number" and inputs.lacerate_remaining <= 4)) and rage >= 15 then
            out.action = "lacerate"
            out.spell_name = "Lacerate"
        elseif is_known(inputs, "Swipe", "swipe_known") and inputs.target_count and inputs.target_count > 1 and rage >= 20 then
            out.action = "swipe"
            out.spell_name = "Swipe"
        elseif is_known(inputs, "Maul", "maul_known") and (rage >= (inputs.maul_cost or 15) or rage >= 40) then
            out.action = "maul"
            out.spell_name = "Maul"
        else
            out.hold = true
            out.hold_text = "POOL"
        end
        return out
    end

    if spec == "cat" then
        -- FERAL CAT DPS - wowsims/forever feralcat/adaptive.apl.json
        local energy = type(inputs.energy) == "number" and inputs.energy or 0
        local cp = type(inputs.combo_points) == "number" and inputs.combo_points or 0

        if inputs.prowl_active == true and is_known(inputs, "Ravage", "ravage_known") and energy >= 60 then
            out.action = "ravage"
            out.spell_name = "Ravage"
            return out
        end

        if is_known(inputs, "Faerie Fire (Feral)", "faerie_fire_known") and inputs.faerie_fire_active ~= true then
            out.action = "faerie_fire"
            out.spell_name = "Faerie Fire (Feral)"
            return out
        end

        -- Clearcasting proc: Shred immediately
        -- D8 (audit 2026-11-05, allow-but-note): nil passes ~= false, so Shred is
        -- legal when the facing read is unknown - no facing probe exists on any
        -- client, so the guide allows the cast and notes the gap instead of
        -- guessing. No behavior change.
        if inputs.clearcasting_active == true and is_known(inputs, "Shred", "shred_known") and inputs.behind_target ~= false then
            out.action = "shred"
            out.spell_name = "Shred"
            return out
        end

        -- Finishers at 5 Combo Points
        if cp >= 5 then
            if is_known(inputs, "Rip", "rip_known") and inputs.rip_active ~= true and (inputs.ttd == nil or inputs.ttd >= 8) and energy >= 30 then
                out.action = "rip"
                out.spell_name = "Rip"
            elseif is_known(inputs, "Ferocious Bite", "fb_known") and energy >= 35 then
                out.action = "ferocious_bite"
                out.spell_name = "Ferocious Bite"
            else
                out.hold = true
                out.hold_text = "POOL"
            end
            return out
        end

        -- Bleed Upkeep: Rake
        if is_known(inputs, "Rake", "rake_known") and inputs.rake_active ~= true and (inputs.ttd == nil or inputs.ttd >= 6) and energy >= 35 then
            out.action = "rake"
            out.spell_name = "Rake"
            return out
        end

        -- Builders
        -- D8 (audit 2026-11-05, allow-but-note): see the Clearcasting note above -
        -- nil ~= false keeps Shred legal with no facing probe. No behavior change.
        if is_known(inputs, "Shred", "shred_known") and inputs.behind_target ~= false then
            if energy >= (inputs.shred_cost or 60) then
                out.action = "shred"
                out.spell_name = "Shred"
            else
                out.hold = true
                out.hold_text = "POOL"
            end
        elseif is_known(inputs, "Claw", "claw_known") then
            if energy >= (inputs.claw_cost or 45) then
                out.action = "claw"
                out.spell_name = "Claw"
            else
                out.hold = true
                out.hold_text = "POOL"
            end
        end
        return out
    end

    -- CASTER / BASELINE DRUID
    -- D3 (audit 2026-11-05): caster DPS is unmodeled - hold instead of returning
    -- an empty out (blank guide).
    out.hold = true
    out.hold_text = "WAIT"
    return out
end

--=========================================================================================
-- 6. SHAMAN (Enhancement, General Leveling)
-- Based on wowsims/forever shaman APL: enhancement/testing.build.json
--=========================================================================================
function FG.evaluate_shaman(spec, inputs, out)
    inputs = inputs or {}
    out = out or {}
    spec = spec or FG.resolve_shaman_spec(inputs)
    local mw_stacks = type(inputs.mw_stacks) == "number" and inputs.mw_stacks or 0
    local mana_pct = type(inputs.mana_fraction) == "number" and (inputs.mana_fraction * 100) or 100

    out.rotation_key = spec

    -- Enhancement Priority (from wowsims/forever testing.build.json)
    -- Flame Shock -> Stormstrike -> Lightning Bolt (MW5) -> Earth Shock -> Fire Nova
    if is_known(inputs, "Flame Shock", "flameshock_known") and inputs.flameshock_active ~= true and is_ready(inputs.shock_remaining) then
        out.action = "flameshock"
        out.spell_name = "Flame Shock"
    elseif is_known(inputs, "Stormstrike", "stormstrike_known") and is_ready(inputs.stormstrike_remaining) then
        out.action = "stormstrike"
        out.spell_name = "Stormstrike"
    elseif is_known(inputs, "Lightning Bolt", "mw_known") and mw_stacks >= 5 then
        out.action = "weave"
        out.spell_name = "Lightning Bolt"
    elseif is_known(inputs, "Earth Shock", "earthshock_known") and is_ready(inputs.shock_remaining) then
        out.action = "earthshock"
        out.spell_name = "Earth Shock"
    elseif is_known(inputs, "Fire Nova", "firenova_known") and is_ready(inputs.firenova_remaining) and (inputs.clearcasting_active == true or mana_pct > 10) then
        out.action = "firenova"
        out.spell_name = "Fire Nova"
    elseif is_known(inputs, "Strength of Earth Totem", "soe_known") and inputs.soe_active ~= true then
        out.action = "strength_of_earth"
        out.spell_name = "Strength of Earth Totem"
    elseif is_known(inputs, "Searing Totem", "searing_known") and inputs.searing_active ~= true then
        out.action = "searing"
        out.spell_name = "Searing Totem"
    elseif is_known(inputs, "Water Shield", "watershield_known") and inputs.watershield_active ~= true then
        out.action = "watershield"
        out.spell_name = "Water Shield"
    elseif is_known(inputs, "Lightning Shield", "lightningshield_known") and inputs.lightningshield_active ~= true then
        out.action = "lightningshield"
        out.spell_name = "Lightning Shield"
    else
        out.hold = true
        out.hold_text = "WAIT"
    end
    return out
end

--=========================================================================================
-- Live-gather bridge
-- The class modules' gather_guide_inputs publish cooldowns as <x>_remaining, aura
-- state as <x>_remaining / tri-states and a few differently named fields. The
-- evaluators above read the keys below; FG.evaluate hands them a read-through view
-- of the raw inputs: a key the caller set always wins (so direct callers and the
-- offline tests are unchanged), otherwise a live alias or a lazy client cooldown
-- read (by spell name, GCD echo filtered) fills it in. Reads are lazy, so only the
-- fields a rule actually reaches cost a client query, and nothing is stored on the
-- caller's table (no stale value can survive between ticks).
--=========================================================================================
local CD_SPELL_BY_FIELD = {
    -- Warrior
    bt_remaining = "Bloodthirst", ms_remaining = "Mortal Strike", ww_remaining = "Whirlwind",
    shield_slam_remaining = "Shield Slam", revenge_remaining = "Revenge",
    shield_wall_remaining = "Shield Wall", last_stand_remaining = "Last Stand",
    shield_block_remaining = "Shield Block", tc_remaining = "Thunder Clap",
    demo_remaining = "Demoralizing Shout", op_remaining = "Overpower",
    slam_remaining = "Slam", execute_remaining = "Execute",
    -- Paladin
    judge_remaining = "Judgement", cons_remaining = "Consecration", exo_remaining = "Exorcism",
    holy_strike_remaining = "Holy Strike", holy_shock_remaining = "Holy Shock",
    holy_shield_remaining = "Holy Shield", how_remaining = "Hammer of Wrath",
    divine_favor_remaining = "Divine Favor",
    -- Hunter
    raptor_strike_remaining_cd = "Raptor Strike", mongoose_bite_remaining_cd = "Mongoose Bite",
    strider_kick_remaining_cd = "Strider Kick", immolation_trap_remaining_cd = "Immolation Trap",
    summon_hawk_remaining_cd = "Summon Hawk", wing_clip_remaining_cd = "Wing Clip",
    hawk_remaining_cd = "Aspect of the Hawk", arcane_remaining_cd = "Arcane Shot",
    multi_remaining_cd = "Multi-Shot", aimed_remaining_cd = "Aimed Shot",
    sniper_remaining_cd = "Sniper Shot",
    -- Druid
    barkskin_remaining = "Barkskin", frenzied_regen_remaining = "Frenzied Regeneration",
    enrage_remaining = "Enrage", primal_bite_remaining = "Primal Bite",
    -- Shaman
    stormstrike_remaining = "Stormstrike", firenova_remaining = "Fire Nova",
    shock_remaining = "Flame Shock",
}

-- Seconds left on a spell's own cooldown (0 = ready). The GCD echo (<= 1.51 s) is
-- never a cooldown. nil when the client cannot answer, which the rules read as ready.
--
-- restricted_seen: this tick read at least one cooldown the client reported as
-- restricted (secret timing, no readable fallback). FG.evaluate clears it before the
-- decision model runs and ORs it into out.inputs_unknown afterwards, so a restricted
-- read never turns into a "ready" claim (M6: unknown suppresses the advice).
local restricted_seen = false
local function live_cooldown(spell_name)
    local api = st and st.api
    if not (api and api.GetSpellCooldown) then
        return nil
    end
    local sp_def = FG.SPELLS_BY_NAME and FG.SPELLS_BY_NAME[spell_name]
    local ok, start, duration, _, _, restricted = pcall(api.GetSpellCooldown, spell_name, sp_def and sp_def.id)
    -- Unknown, never 0 ("ready"): the flag makes this tick's advice unknown instead.
    if restricted == true then
        restricted_seen = true
        return nil
    end
    if not ok or type(start) ~= "number" or type(duration) ~= "number" then
        return nil
    end
    if canaccessallvalues(duration, start) then
        if duration > 1.51 and start > 0 then
            local now = api.get_time and api.get_time() or 0
            local remaining = start + duration - now
            if remaining > 0 then
                return remaining
            end
        end
    end
    return 0
end

local function positive(v)
    if type(v) ~= "number" then
        return nil
    end
    return v > 0
end

-- Any seal up: Righteousness/Fury rides seal_inactive == false, Command/the twist
-- seal ride the engine's seal state string.
local function live_seal_active(raw)
    if raw.seal_inactive == false then
        return true
    end
    if raw.seal ~= nil then
        return raw.seal ~= "none"
    end
    return nil
end

-- The Hunter's Mark debuff on the target (memoised per evaluate call: it walks the
-- target's auras).
local function live_hunters_mark(memo)
    if memo.hunters_mark ~= nil then
        return memo.hunters_mark
    end
    local result = nil
    local api = st and st.api
    if api and api.scan_unit_aura then
        local remaining = api.scan_unit_aura("target", function(_, name)
            return name == "Hunter's Mark"
        end, "HARMFUL")
        if remaining ~= nil then
            result = true
        else
            -- H3 (2026-11-06): nil is UNKNOWN, never "absent". scan_unit_aura returns
            -- nil both when the mark is not there and when the target-aura list could
            -- not be read (a restricted row/list); the old `remaining ~= nil` made the
            -- unknown branch unreachable, so a restricted list re-cued Hunter's Mark
            -- forever. Only the client's own secrecy predicate may turn that nil into
            -- "unknown"; without one (classic clients have no C_Secrets) nil keeps its
            -- historical meaning of absent.
            local may_be_secret = false
            local may = api.spell_aura_may_be_secret
            if type(may) == "function" and may(FG.SPELLS.HUNTERS_MARK.id) == true then
                may_be_secret = true
            elseif type(api.auras_may_be_secret) == "function"
                and api.auras_may_be_secret() == true then
                may_be_secret = true
            end
            result = may_be_secret and "unknown" or false
        end
    end
    memo.hunters_mark = result == nil and "unknown" or result
    return memo.hunters_mark
end

local ALIAS = {
    -- Warrior
    shield_block_active = function(r) return r.has_shield_block_buff end,
    tc_active = function(r) return positive(r.thunder_clap_debuff_remaining) end,
    demo_active = function(r) return positive(r.demo_shout_debuff_remaining) end,
    rend_active = function(r)
        if r.rend_remaining == nil and r.rend_known == nil then return nil end
        return positive(r.rend_remaining) == true
    end,
    -- Paladin
    seal_active = live_seal_active,
    -- Hunter
    mana_fraction = function(r) return r.mana_frac end,
    -- Druid
    faerie_fire_active = function(r)
        local v = r.ff_debuff_remaining
        if type(v) == "number" then return true end
        return v
    end,
    rip_active = function(r) if r.rip_known ~= nil then return positive(r.rip_remaining) == true end end,
    rake_active = function(r) if r.rake_known ~= nil then return positive(r.rake_remaining) == true end end,
    clearcasting_active = function(r) return r.clearcast end,
    ttd = function(r) return r.time_to_die end,
    -- Rogue
    energy = function(r) return r.energy_now end,
    combo_points = function(r) return r.cp end,
    snd_remaining = function(r) return r.snd_remains end,
    rupture_active = function(r)
        if r.rupture_known == nil then return nil end
        return r.rupture_remains ~= nil
    end,
    ea_active = function(r) return r.ea_remains ~= nil end,
    use_ea = function(r) return r.ea_duty end,
    -- The Forever Venom finisher's usability. The class gather NEVER writes
    -- envenom_usable; it supplies venom_ready (known + usable + off cooldown,
    -- classes/rogue.lua:1241) and venom_buff_active (classes/rogue.lua:1245). The APL
    -- row the engine cites (classes/rogue.lua:2754) is "the buff is down AND cp >= 3".
    -- Tri-state, so an unreadable producer can never invent a missing buff:
    --   true  = ready AND the buff is CONFIRMED down AND cp >= 3
    --   false = ready and buff-down but cp < 3 (a real "not yet")
    --   nil   = unknown (not ready / no buff reading / no cp reading) - never fires.
    -- nil is NOT "down": venom_buff_active is nil when the client has no aura scan at
    -- all (classes/rogue.lua:434-437), and this addon's unknown-hides rule keeps the
    -- row quiet rather than claiming a buff state it did not read.
    envenom_usable = function(r)
        if r.venom_ready ~= true or r.venom_buff_active ~= false then
            return nil
        end
        if type(r.cp) ~= "number" then
            return nil
        end
        return r.cp >= 3
    end,
    -- Shaman
    flameshock_active = function(r)
        if r.flameshock_allowed == nil then return nil end
        return positive(r.flameshock_remaining) == true
    end,
    soe_active = function(r) return positive(r.strength_of_earth_remaining) end,
    searing_active = function(r)
        if r.searing_down == nil then return nil end
        return r.searing_down == false
    end,
    lightningshield_active = function(r)
        if r.lightningshield_due == nil then return nil end
        return r.lightningshield_due == false
    end,
    -- D7 (audit 2026-11-05): reads the dedicated watershield_due producer
    -- (classes/shaman.lua gather, Forever-only) - never the Lightning Shield leg.
    watershield_active = function(r)
        if r.watershield_due == nil then return nil end
        return r.watershield_due == false
    end,
}

local bridge_raw
local bridge_memo = {}
local bridge_view = setmetatable({}, {
    __index = function(_, key)
        local raw = bridge_raw
        local v = raw[key]
        if v ~= nil then
            -- The seal state is the one raw field whose live meaning differs
            -- (seal_inactive only tracks Righteousness/Fury): trust the engine's
            -- own seal state whenever it is present.
            if key == "seal_inactive" and raw.seal ~= nil then
                local active = live_seal_active(raw)
                if active ~= nil then return not active end
            end
            return v
        end
        if key == "hunters_mark_active" then
            local mark = live_hunters_mark(bridge_memo)
            if mark == "unknown" then
                -- H3 (2026-11-06): unknown is not "absent". The cue rule tests
                -- `hunters_mark_active ~= true`, so returning nil would re-cue a mark
                -- that may already be up. Report it as active for the rule (no cue) AND
                -- flag the tick unknown via restricted_seen so the display takes its
                -- HOLD/unknown face instead of a confident action.
                restricted_seen = true
                return true
            end
            return mark
        end
        if key == "mongoose_bite_usable" and raw.now ~= nil then
            local api = st and st.api
            if api and api.IsSpellUsable then
                local ok, usable = pcall(api.IsSpellUsable, "Mongoose Bite")
                if ok then return usable == true end
            end
            return nil
        end
        local alias = ALIAS[key]
        if alias then
            return alias(raw)
        end
        local spell_name = CD_SPELL_BY_FIELD[key]
        if spell_name then
            return live_cooldown(spell_name)
        end
        return nil
    end,
})

local function bridge_inputs(inputs)
    bridge_raw = inputs
    for k in pairs(bridge_memo) do
        bridge_memo[k] = nil
    end
    return bridge_view
end

--=========================================================================================
-- Master Evaluator
--=========================================================================================
function FG.evaluate(class, spec, inputs, out)
    inputs = inputs or {}
    out = out or {}
    local raw_inputs = inputs
    inputs = bridge_inputs(raw_inputs)
    out.hold = false
    out.hold_text = nil
    out.riding = nil
    out.filler_slot = nil
    out.judge_slot = nil
    out.waiting_judgement = false
    -- Every field a branch can write is cleared first: the output table is reused
    -- across ticks and fights (nextaction_ui and the class providers pass the same
    -- one back in), so a HOLD / POOL / WAIT branch that sets no action must not
    -- re-display the previous tick's action, and judge_call must not latch the
    -- Judgement icon on later ticks.
    out.action = nil
    out.spell_name = nil
    out.judge_call = nil
    out.rotation_key = nil
    out.inputs_unknown = raw_inputs.inputs_unknown == true
    restricted_seen = false

    local res
    if class == "WARRIOR" then
        res = FG.evaluate_warrior(spec, inputs, out)
    elseif class == "PALADIN" then
        res = FG.evaluate_paladin(spec, inputs, out)
    elseif class == "HUNTER" then
        res = FG.evaluate_hunter(spec, inputs, out)
    elseif class == "ROGUE" then
        res = FG.evaluate_rogue(spec, inputs, out)
    elseif class == "DRUID" then
        res = FG.evaluate_druid(spec, inputs, out)
    elseif class == "SHAMAN" then
        res = FG.evaluate_shaman(spec, inputs, out)
    else
        res = out
    end

    if restricted_seen then
        out.inputs_unknown = true
    end
    if out.judge_call or out.action == "judge" then
        out.judge_slot = "judge"
    end
    return res
end

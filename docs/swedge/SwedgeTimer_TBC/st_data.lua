local _, st = ...
local print = st.utils.print_msg
local get_tab = st.utils.convert_lookup_table
st.data = {}

--=========================================================================================
-- Seal IDs
--=========================================================================================
-- blood/the Martyr
local sob_ids = {
    31892, 348700
}
st.data.sob_ids = get_tab(sob_ids)

-- command
local soc_ids = {
    20375, 20915, 20918, 20919, 20920, 27170
}
st.data.soc_ids = get_tab(soc_ids)

-- righteousness
local sor_ids = {
    21084, 20154, 20287, 20288, 20289, 20290, 20291, 20292, 20293, 27155
}
st.data.sor_ids = get_tab(sor_ids)

-- crusader
local sotc_ids = {
    21082, 20162, 20305, 20306, 20307, 20308, 27158
}
st.data.sotc_ids = get_tab(sotc_ids)

-- justice
local soj_ids = {
    20164, 31895
}
st.data.soj_ids = get_tab(soj_ids)

-- wisdom
local sow_ids = {
    20166, 20356, 20357, 27166
}
st.data.sow_ids = get_tab(sow_ids)

-- light
local sol_ids = {
    20165, 20347, 20348, 20349, 27160
}
st.data.sol_ids = get_tab(sol_ids)

-- vengeance/corruption
local sov_ids = {
    31801, 348704
}
st.data.sov_ids = get_tab(sov_ids)

-- Seal of Command proc (damage dealt on swing)
-- These are the actual damage spells that fire when Command procs
local soc_proc_ids = {
    20424,  -- Rank 1
    20944,  -- Rank 2
    20945,  -- Rank 3
    20946,  -- Rank 4
    20947,  -- Rank 5
    29385,  -- Rank 6 (TBC)
}
st.data.soc_proc_ids = get_tab(soc_proc_ids)

--=========================================================================================
-- Seal spell IDs for icon display (uses GetSpellTexture)
--=========================================================================================
st.data.seal_texture_ids = {
    command = 20375,        -- Seal of Command (Rank 1)
    righteousness = 21084,  -- Seal of Righteousness (Rank 1)
    blood = 31892,          -- Seal of Blood
    vengeance = 31801,      -- Seal of Vengeance
    wisdom = 20166,         -- Seal of Wisdom (Rank 1)
    light = 20165,          -- Seal of Light (Rank 1)
    justice = 20164,        -- Seal of Justice
    crusader = 21082,       -- Seal of the Crusader (Rank 1)
}

--=========================================================================================
-- Finite cast time spell IDs that reset the swing timer.
--=========================================================================================
local cast_time_spells = {
    -- Flash of Light
    19750, 19939, 19940, 19941, 19942, 19943, 27137,
    -- Holy Light
    635, 639, 647, 1026, 1042, 3472, 10328, 10329, 25292, 27135, 27136,
    -- Avenger's Shield
    31935, 32699, 32700,
    -- Holy Wrath
    2812, 10318, 27139,
    -- Hammer of Wrath
    24275, 24274, 24239, 27180,
    -- Turn Evil
    10326,
    -- Turn Undead
    2878, 5627,
    -- Redemption
    7328, 10322, 10324, 20772, 20773
}
st.data.reset_on_completion_spell_ids = get_tab(cast_time_spells)

--=========================================================================================
-- Instant cast spell IDs that reset the swing timer.
--=========================================================================================
local instant_cast_spells = {
    -- Repentence
    20066,
}
st.data.reset_on_cast_spell_ids = get_tab(instant_cast_spells)

--=========================================================================================
-- Rotation Helper Spell IDs
--=========================================================================================
-- Crusader Strike (all ranks)
st.data.cs_spell_ids = get_tab({
    35395,  -- Crusader Strike (Rank 1)
})

-- Spell IDs for rotation helper icon textures
--=========================================================================================
-- Trinkets (from Nullgodx's Paladin WeakAura): item id -> proc buff spell id, and
-- item id -> internal cooldown in seconds for the ones that have one.
--=========================================================================================
st.data.trinket_buffs = {
    [28830] = 34775, -- Dragonspine Trophy
    [29383] = 35166, -- Bloodlust Brooch
    [19343] = 23733, -- Scrolls of Blinding Light
    [23570] = 29602, -- Jom Gabbar
    [38290] = 51953, -- Dark Iron Smoking Pipe
    [38289] = 51952, -- Coren's Lucky Coin
    [38288] = 51954, -- Direbrew Hops
    [38287] = 51955, -- Empty Mug of Direbrew
    [29387] = 35169, -- Gnomeregan Auto-Blocker 600
    [29376] = 35165, -- Essence of the Martyr
    [28789] = 34747, -- Eye of Magtheridon
    [29370] = 35163, -- Icon of the Silver Crescent
    [28034] = 33649, -- Hourglass of the Unraveller
    [27891] = 33479, -- Adamantine Figurine
    [34473] = 45058, -- Commendation of Kael'thas
    [34472] = 45053, -- Shard of Contempt
    [32534] = 40538, -- Brooch of the Immortal King
    [30841] = 37879, -- Lower City Prayerbook
    [28727] = 29601, -- Pendant of the Violet Eye
    [28288] = 33807, -- Abacus of Violent Odds
    [28590] = 38332, -- Ribbon of Sacrifice
    [28528] = 34519, -- Moroes' Lucky Pocket Watch
    [28418] = 34321, -- Shiffar's Nexus-Horn
    [28370] = 34210, -- Bangle of Endless Blessings
    [28190] = 33370, -- Scarab of the Infinite Cycle
    [27683] = 33370, -- Quagmirran's Eye
    [35702] = 46784, -- Figurine - Shadowsong Panther
    [35700] = 46783, -- Figurine - Crimson Serpent
    [35693] = 46780, -- Figurine - Empyrean Tortoise
    [30627] = 42084, -- Tsunami Talisman
    [30626] = 38348, -- Sextant of Unstable Currents
    [33831] = 43716, -- Berserker's Call
    [33829] = 43712, -- Hex Shrunken Head
    [33828] = 43710, -- Tome of Diabolic Remedy
    [32505] = 40477, -- Madness of the Betrayer
    [32501] = 40464, -- Shadowmoon Insignia
    [32496] = 37656, -- Memento of Tyrande
    [32483] = 40396, -- The Skull of Gul'dan
    [34427] = 45040, -- Blackened Naaru Sliver
    [32486] = 40452, -- Ashtongue Talisman of Equilibrium
    [30450] = 37174, -- Warp-Spring Coil
    [30447] = 37198, -- Tome of Fiery Redemption
    [30663] = 37243, -- Fathom-Brooch of the Tidewalker
    [30619] = 38324, -- Fel Reaver's Piston
    [34470] = 45055, -- Timbal's Focusing Crystal (proc)
    [32770] = 41261, -- Skyguard Silver Cross
    [32771] = 41263, -- Airman's Ribbon of Gallantry
}

st.data.trinket_icd = {
    [28830] = 20, -- Dragonspine Trophy
    [34473] = 30, -- Commendation of Kael'thas
    [34472] = 45, -- Shard of Contempt
    [28418] = 45, -- Shiffar's Nexus-Horn
    [28190] = 45, -- Scarab of the Infinite Cycle
    [27683] = 45, -- Quagmirran's Eye
    [30627] = 45, -- Tsunami Talisman
    [30626] = 45, -- Sextant of Unstable Currents
    [34427] = 45, -- Blackened Naaru Sliver
    [32496] = 50, -- Memento of Tyrande
    [28034] = 50, -- Hourglass of the Unraveller
    [32486] = 10, -- Ashtongue Talisman of Equilibrium
    [30450] = 30, -- Warp-Spring Coil
    [30447] = 45, -- Tome of Fiery Redemption
    [30663] = 40, -- Fathom-Brooch of the Tidewalker
    [30619] = 15, -- Fel Reaver's Piston
    [28370] = 50, -- Bangle of Endless Blessings
    [34470] = 15, -- Timbal's Focusing Crystal
    [32770] = 10, -- Skyguard Silver Cross
    [32771] = 10, -- Airman's Ribbon of Gallantry
}

st.data.rotation_textures = {
    cs = 35395,           -- Crusader Strike
    blood = 31892,        -- Seal of Blood (for blood auto icon)
    command = 20375,      -- Seal of Command (for command auto icon)
    judgement = 20271,    -- Judgement (for filler priority)
}

--=========================================================================================
-- End, if debug verify module was read.
--=========================================================================================
if st.debug then print('-- Parsed st_data.lua module correctly') end

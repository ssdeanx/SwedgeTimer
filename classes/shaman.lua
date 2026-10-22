--=========================================================================================
-- Module for Shaman-specific behaviours: the Enhancement spell-weaving assist ("LB
-- weaving"), ported from the read-only reference SuperSwingTimer-WoW/
-- SuperSwingTimer_Weaving.lua (spell-catalog resolution, cast tracking, marker/spark
-- display), plus the reference's Enhancement trackers
-- (SuperSwingTimer_ClassMods.lua shaman block 3334-4513): the above/below-bar breakpoint
-- markers and offhand spark mirror, the Windfury Weapon ICD strip, the Flame Shock target
-- bar, the Stormstrike / Shamanistic Rage badges and the shield charge row. All
-- swing-relative math is frozen in weave.lua; this module only gathers the live inputs
-- (haste, Maelstrom Weapon, auras, cooldowns, cast events) and drives the visuals.
--
-- The assist draws on the mainhand visuals frame:
--   vf.weave_marker        : the resolved spell's icon at the latest safe cast start.
--   vf.weave_marker_top    : the same icon above the bar (reference 3491-3497).
--   vf.weave_marker_bottom : the same icon below the bar stack (reference 3499-3506).
--   vf.weave_spark         : the active cast, tinted red when the cast will clip.
--   vf.weave_spark_offhand : the offhand mirror of the spark (dual wield; reference
--                            3481-3489), created on the offhand visuals frame.
-- plus the tracker widgets: windfury strip, flame shock bar, cooldown badges and the
-- shield charge rects.
--=========================================================================================
local addon_name, st = ...
local ST = LibStub("AceAddon-3.0"):GetAddon(addon_name)
st.class_loaders = st.class_loaders or {}
st.class_loaders["SHAMAN"] = function()
-- Cross-client API wrappers (see compat.lua).
local api = st.api
local LSM = LibStub("LibSharedMedia-3.0")

--=========================================================================================
-- Data
--=========================================================================================
-- Maelstrom Weapon: 20% cast-time reduction per stack, instant at 5. 408505 is the SoD
-- aura, 53817 the Wrath-era one; the name fallback covers everything else.
local WEAVE_MW_SPELL_IDS = { [408505] = true, [53817] = true }
local WEAVE_MW_NAME = "Maelstrom Weapon"

-- Buff haste sources, checked when the spell-haste API reports nothing (Classic). The
-- reference maxes these against the API value, never multiplies it.
local WEAVE_BLOODLUST_IDS = { [2825] = true, [32182] = true }  -- Bloodlust / Heroism
local WEAVE_BERSERKING_IDS = { [20554] = true, [26285] = true, [26284] = true }

-- Rage of the Farseer (Forever Enhancement personal Bloodlust - UNCONFIRMED,
-- docs/research/forever_beta.md; no spell id published, so name-only match): feeds
-- the Bloodlust leg of the buff-haste multiplier (personal lust reads as 30%,
-- mirroring Bloodlust - the VALUE is assumed, see the multiplier site below).
-- Confirm in-game (spell id, haste value, aura name). Never
-- present off Forever, so every other family reads byte-identical.
local WEAVE_FARSEER_NAME = "Rage of the Farseer"

-- Unresolved families are retried at most this often: a level-up can teach a family after
-- the first attempt, and the throttled retry keeps the per-frame path cheap.
local WEAVE_CATALOG_RETRY_S = 5

-- Marker alpha multiplier while the cast would overrun the swing (0.65, like the
-- reference's unsafe color).
local WEAVE_UNSAFE_ALPHA = 0.65

-- Visual fallbacks for malformed or pre-options profiles.
local WEAVE_FALLBACK_MARKER_SIZE = 6
local WEAVE_FALLBACK_MARKER_ALPHA = 1
local WEAVE_FALLBACK_SPARK_WIDTH = 3
local WEAVE_FALLBACK_SPARK_HEIGHT = 15
local WEAVE_FALLBACK_SPARK_ALPHA = 0.95

-- Spark colors: red while the cast clips the swing, otherwise the shaman class blue.
local WEAVE_RED_COLOR = { 1, 0.15, 0.15 }
local weave_shaman_blue = nil
local function get_shaman_spark_color()
	if weave_shaman_blue == nil then
		local c = RAID_CLASS_COLORS and RAID_CLASS_COLORS["SHAMAN"]
		if c and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
			weave_shaman_blue = { c.r, c.g, c.b }
		else
			-- Fallback: the shaman class color on every family that has defined it.
			weave_shaman_blue = { 0, 0.44, 0.87 }
		end
	end
	return weave_shaman_blue
end

--=========================================================================================
-- Tracker data (reference SuperSwingTimer_ClassMods.lua shaman block 3334-4513)
--=========================================================================================
-- Windfury Weapon buff (ICD strip: 3766-3848). The proc buff is accepted too, mirroring
-- the reference's WINDFURY_BUFF_NAMES / WINDFURY_BUFF_SPELL_IDS pair (3751-3765).
-- TBC MICRO (docs/research/tbc_minmax.md): the 3 s ICD caps output at 20 procs/min
-- (st.weave.WINDFURY_MAX_PROCS_PER_MINUTE) and is shared across hands; double WF
-- wants the slowest weapons in BOTH hands. DOWNRANK NOTE: twist with WF rank 1 for
-- mana sustain (max rank ooms in 1-2 min of twisting); ranks resolve by id table
-- plus the name fallback below, so unconfirmed ranks still light the strip.
local WEAVE_WINDFURY_IDS = {
	[8232] = true, [8233] = true, [8234] = true, [8235] = true,
	[16316] = true, [16317] = true, [25585] = true, [33757] = true,
}
local WEAVE_WINDFURY_NAMES = { ["Windfury Weapon"] = true, ["Windfury"] = true }

-- Stormstrike / Shamanistic Rage cooldown badges (3695-3748; ids from
-- SuperSwingTimer_Constants.lua:193-196).
local WEAVE_STORMSTRIKE_SPELL_ID = 17364
local WEAVE_STORMSTRIKE_NAME = "Stormstrike"
-- The Stormstrike cooldown LENGTH per family (S-23 / U-09). SIM-CONFIRMED - the
-- value is read from each family's own stormstrike.go (fetched live 2026-10-19):
--   Era   20 s - wowsims/classic sim/shaman/stormstrike.go -> Duration: time.Second * 20
--   SoD    6 s - wowsims/sod    sim/shaman/stormstrike.go -> Duration: time.Second * 6
--                   (also operator-confirmed in-client 2026-10-19, central journal)
--   TBC   10 s - wowsims/tbc-new sim/shaman/stormstrike.go -> Duration: time.Second * 10
--   Wrath  8 s - wowsims/wotlk  sim/shaman/stormstrike.go ->
--                   cooldownTime := TernaryFloat64(HasSetBonus(ItemSetGladiatorsEarthshaker, 4), 6, 8)
--                   (8 s without the 4pc set bonus; the set probe does not exist in
--                   this addon, so the base length is the fallback - never a guess)
-- The ERA token carries both builds, so the SoD MW-rune latch picks the SoD
-- length over the Era-base one (bench/lessons.md: SoD is Era + a rune, not a
-- different client). The families with no sourced value (Forever, Retail, an
-- unknown token) keep the shipped 10 s - no number is invented for them.
-- (One table, not four constants: this chunk is at Lua 5.1's 200-local limit,
-- so the per-family table is published on the class namespace.)
ST.SHAMAN.STORMSTRIKE_COOLDOWN_SECONDS = {
	ERA = 20,
	TBC = 10,
	WRATH = 8,
	SOD = 6,
	DEFAULT = 10,
}
local WEAVE_SR_SPELL_ID = 30823
local WEAVE_SR_NAME = "Shamanistic Rage"

-- Call of the Elements 66842 (S-20 / U-10). CLIENT-SOURCED: the shipped
-- clients carry the spell in their own totem-summon list - classic_titan
-- (3.80.2.69815) Interface/AddOns/Blizzard_FrameXMLBase/Classic/Constants.lua:
-- 300-304 -> TOTEM_MULTI_CAST_SUMMON_SPELLS = { 66842, 66843, 66844 }; (the same
-- block on classic_era 1.15.9 and classic_anniversary 2.5.6, and on
-- origin/forever 1.60.1 at Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua:
-- 240-244). The client's own list is the totem-multi-cast family: 66842 is the
-- Call of the Elements the Wrath enhancement APLs rank below Earth Shock and
-- above Magma Totem.
local WEAVE_COE_SPELL_ID = 66842

-- Wrath Lightning Bolt max rank for the M1 sub-5 hardcast (sim source:
-- wowsims/wotlk sim/shaman/lightning_bolt.go 49238, base cast 2500 ms; APL
-- default_wf.apl.json ranks MW >= 3 + 300 ms + cast < swing; id UNCONFIRMED
-- in-game, known-gated so an unknown spell feeds nil and never prompts).
local WEAVE_WRATH_LB_SPELL_ID = 49238
local WEAVE_LB_NAME = "Lightning Bolt"

-- Name-vs-id rule (bench/lessons.md): TBC Anniversary resolves by NAME never
-- bare id; Classic Era by id. spell_query branches every direct spell read
-- (GetSpellInfo / GetSpellCooldown / is_spell_known / IsSpellUsable /
-- IsSpellInRange / IsCurrentSpell / GetSpellPowerCost) via st.family.
-- Nil-safe: a nil id/name stays nil so unknown-hides is preserved.
local function spell_query(id, name)
	if st.family == "TBC" then
		return name
	end
	return id
end

-- Rockbiter Weapon imbue badge (discover #6; reference
-- SuperSwingTimer_ClassMods.lua:4217 tracks it as a buff icon with rank-1 id
-- 8017). Ranks above 1 match by the English name only: their ids are UNCONFIRMED
-- and never guessed (the WF-rank convention above). Guarded reads only - a nil
-- or unconfirmed id can never light the badge.
local WEAVE_ROCKBITER_IDS = {
	[8017] = true,
}
local WEAVE_ROCKBITER_NAME = "Rockbiter Weapon"

-- Flurry (16280; reference SuperSwingTimer_ClassMods.lua:4221) - the melee proc
-- buff whose 0.5 s ICD drives the DW sync warning (round 2). The aura count is
-- the remaining charges; a count INCREASE is a fresh proc (stamped in
-- on_aura_change). Ids above the reference's are matched by name only.
local WEAVE_FLURRY_IDS = {
	[16280] = true,
}
local WEAVE_FLURRY_NAME = "Flurry"

-- Clearcasting (Elemental Focus proc, 16246): the Forever sim casts Fire Nova free
-- on the proc (audit 2026-10-19 Forever §). Ids above the reference's are matched
-- by name only. Guarded reads only - a nil or unconfirmed id never lights the feed.
local WEAVE_CLEARCASTING_IDS = {
	[16246] = true,
}
local WEAVE_CLEARCASTING_NAME = "Clearcasting"

-- Next Action Guide shock/totem slots (TBC Enhancement): Fire Nova Totem rank 1 is
-- 1535 (classicdb-confirmed rank 1; TBC top rank 25547) with a 15 s cooldown; Earth
-- Shock rank 1 is 8042 (instant, no cooldown); the twist slot shows Windfury Totem
-- 8512 - the Windfury Totem RANK-1 id (wowsims/forever sim/shaman/spell_data_auto_gen.go:
-- WindfuryTotem Ranked(8512, 10613, 10614)), which the module drops ON PURPOSE (the
-- DOWNRANK NOTE above: rank 1 for mana sustain). The TBC APL's own air-slot rows cast
-- the sim-exact rank-5 id 25587 and the alternation's other half the Grace of Air Totem
-- 25359 (wowsims/tbc-new ui/specs/shaman/enhancement/apls/default.apl.json i=3 group
-- Totems rows 1-2) - the rank choice is the operator's O-1 decision
-- (bench/filed_closure_sweep_2026-10-19.md §10), so the shipped fallback stays 8512 and
-- the icon/label resolve by NAME (the rotation row records the APL's id in spell_ids).
-- 8512 itself is UNCONFIRMED on 2.5.6 and needs in-game confirmation (the twist
-- rule is a skeleton until a compat totem read lands - see weave.lua).
local WEAVE_FIRE_NOVA_SPELL_ID = 1535
local WEAVE_FIRE_NOVA_NAME = "Fire Nova Totem"
local WEAVE_FIRE_NOVA_COOLDOWN_SECONDS = 15
local WEAVE_EARTH_SHOCK_SPELL_ID = 8042
local WEAVE_EARTH_SHOCK_NAME = "Earth Shock"
local WEAVE_WINDFURY_TOTEM_SPELL_ID = 8512
local WEAVE_WINDFURY_TOTEM_NAME = "Windfury Totem"

-- Totem-twist drops (TBC Enhancement): the air slot alternates Windfury Totem <->
-- Grace of Air Totem roughly every st.weave.TOTEM_TWIST_PERIOD_SECONDS seconds. The
-- air slot is 4 (FrameXML: FIRE 1, EARTH 2, WATER 3, AIR 4). The id table ships only
-- the pre-existing Windfury rank-1 id above (still UNCONFIRMED on 2.5.6); every
-- other rank of either totem matches by English name (the SUCCEEDED hook also
-- resolves the cast's spell id through GetSpellInfo, so unconfirmed ranks stamp by
-- name) until the GoA + higher-WF rank ids are confirmed in-game - plug-in point:
-- add the confirmed rank ids to WEAVE_TWIST_TOTEM_IDS.
-- FOREVER: no twisting there (party-buff totem model - totems dropped 4-at-once via
-- Call of the Elements coexist with the Windfury Weapon imbue; docs/research/
-- forever_beta.md). The gather feeds the stamp through st.weave.
-- is_totem_twist_family, which reads false on FOREVER, so no weapon-enchant twist
-- prompt can ever fire there.
-- The client's own totem-slot map. CLIENT-SOURCED, not an analogy: the shipped
-- clients carry it in their own FrameXMLBase Constants.lua - classic_titan
-- (3.80.2.69815) Interface/AddOns/Blizzard_FrameXMLBase/Classic/Constants.lua:
-- 286-289 -> FIRE_TOTEM_SLOT = 1; EARTH_TOTEM_SLOT = 2; WATER_TOTEM_SLOT = 3;
-- AIR_TOTEM_SLOT = 4; (the same block on classic_era 1.15.9 and
-- classic_anniversary 2.5.6, and on origin/forever 1.60.1 at
-- Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua:226-229). The tree's old
-- "UNCONFIRMED against FrameXML" note on the water slot was stale. (One table,
-- not four locals: this chunk is at Lua 5.1's 200-local limit.)
local WEAVE_TOTEM_SLOTS = {
	FIRE = 1,
	EARTH = 2,
	WATER = 3,
	AIR = 4,
}
local WEAVE_TWIST_TOTEM_IDS = {
	[WEAVE_WINDFURY_TOTEM_SPELL_ID] = true,
}
local WEAVE_TWIST_TOTEM_NAMES = { ["Windfury Totem"] = true, ["Grace of Air Totem"] = true }

-- Era static totem maintain (G2, audit 2026-10-19 Era §: the sim prepulls
-- Windfury Totem 10614 > Grace of Air 10627, then ranks WF refresh first and
-- GoA when inactive, both above Stormstrike). Both share the air slot, so one
-- shaman holds one: first-drop wins and a re-drop is only due on an
-- affirmatively emptied slot (a third air totem such as Nature Resistance is
-- unmodeled and left alone - the twist reconciler's precedent above). The
-- sim's buff-keyed WF refresh (imbue buff 10611 <= 1.5 s) needs an imbue-buff
-- expiry read the aura scan does not capture (active-only, no expiry), so the
-- feed is slot-presence only - that precision is filed remainder (F2 class).
-- Rank-1 ids UNCONFIRMED (bench/verify_bank.md UNCONFIRMED list); higher ranks
-- match by English name only, so unconfirmed ranks still read by name; a wrong
-- id stays silent through the gather's known gate below.
local WEAVE_WF_TOTEM_SPELL_ID = 10614
local WEAVE_WF_TOTEM_NAME = "Windfury Totem"
local WEAVE_WF_TOTEM_IDS = {
	[WEAVE_WF_TOTEM_SPELL_ID] = true,
}
local WEAVE_WF_TOTEM_NAMES = { [WEAVE_WF_TOTEM_NAME] = true }
local WEAVE_GOA_TOTEM_SPELL_ID = 10627
local WEAVE_GOA_TOTEM_NAME = "Grace of Air Totem"
local WEAVE_GOA_TOTEM_IDS = {
	[WEAVE_GOA_TOTEM_SPELL_ID] = true,
}
local WEAVE_GOA_TOTEM_NAMES = { [WEAVE_GOA_TOTEM_NAME] = true }

-- Wrath Enhancement top-parse slots (docs/research/rotations_wrath.md): Feral Spirit
-- 51533 (repo-verified via LibClassicSwingTimerAPI); Fire Elemental Totem rank 1
-- 2894 UNCONFIRMED; Magma Totem matched by English name (rank-1 id 8190
-- UNCONFIRMED lives in the id table below); Lava Lash 60103 UNCONFIRMED. The
-- cooldown slots are known-gated (IsSpellKnown false -> the gather feeds nil ->
-- the engine never prompts), so a wrong id stays silent rather than prompting
-- wrong. Cooldown fallbacks are best-recall WotLK values, also UNCONFIRMED; the
-- client-reported length rides whenever a real cooldown runs. Lava Lash carries
-- no fallback (its cooldown is unconfirmed): the swipe falls back to the
-- remaining time itself. Confirm all four in-game (ids, Feral/Fire-Ele/Lava-Lash
-- cooldowns, Magma duration + the empty-fire-slot shape).
local WEAVE_FERAL_SPIRIT_SPELL_ID = 51533
local WEAVE_FERAL_SPIRIT_COOLDOWN_SECONDS = 180
local WEAVE_FIRE_ELEMENTAL_SPELL_ID = 2894
local WEAVE_FIRE_ELEMENTAL_COOLDOWN_SECONDS = 600
-- Fire Elemental Totem identity for the uptime guard (audit 2026-10-19 TBC §: the
-- sim suppresses Fire Nova while it holds the fire slot). The rank-1 id ships
-- UNCONFIRMED; ranks above 1 match by the English name only (the twist-rank
-- convention above), so unconfirmed ranks still stamp the guard by name.
local WEAVE_FIRE_ELEMENTAL_IDS = {
	[WEAVE_FIRE_ELEMENTAL_SPELL_ID] = true,
}
local WEAVE_FIRE_ELEMENTAL_NAME = "Fire Elemental Totem"
local WEAVE_FIRE_ELEMENTAL_NAMES = { [WEAVE_FIRE_ELEMENTAL_NAME] = true }
local WEAVE_MAGMA_TOTEM_SPELL_ID = 8190
local WEAVE_MAGMA_TOTEM_NAME = "Magma Totem"
local WEAVE_MAGMA_SWIPE_SECONDS = 20
local WEAVE_LAVA_LASH_SPELL_ID = 60103
local WEAVE_MAGMA_TOTEM_IDS = {
	[WEAVE_MAGMA_TOTEM_SPELL_ID] = true,
}
local WEAVE_MAGMA_TOTEM_NAMES = { [WEAVE_MAGMA_TOTEM_NAME] = true }

-- Searing Totem maintain (audit 2026-10-19 Era/SoD/Forever: the sims keep
-- Searing down past a fight-age gate - Era > 20 s, SoD P6 > 30 s - and the
-- Forever sim drops it when the fire slot is empty). READER groundwork only:
-- the matcher + stamp + fire-slot reconcile + gather feed; no guide rule
-- reads the feed yet, so there is no default-visible change. Rank-1 id 10438
-- UNCONFIRMED (Forever sim rotation; needs in-game confirmation); ranks above
-- it match by the English name only, so unconfirmed ranks still stamp by
-- name. A wrong id stays silent (the feed is nil until a commit answers).
local WEAVE_SEARING_TOTEM_SPELL_ID = 10438
local WEAVE_SEARING_TOTEM_NAME = "Searing Totem"
local WEAVE_SEARING_TOTEM_IDS = {
	[WEAVE_SEARING_TOTEM_SPELL_ID] = true,
}
local WEAVE_SEARING_TOTEM_NAMES = { [WEAVE_SEARING_TOTEM_NAME] = true }

-- The APL UTILITY layer (bench/rotation_gap_vs_apl_2026-10-20.md §5): the per-family
-- spell ids and names of the lines the shipped rotation table did not carry - the
-- Strength of Earth and Mana Spring totem upkeeps, the TBC Frost Shock filler and
-- the Wrath Bloodlust party cooldown. ONE table, not four locals: this chunk is at
-- Lua 5.1's 200-local limit (the same reason the totem-slot map above is one
-- table).
--   strength_of_earth  10442 (Era r4) / 25528 (TBC) / 25361 (Forever r5)
--     wowsims/classic sim/shaman/earth_totems.go: StrengthOfEarthTotemSpellId =
--     {0, 8075, 8160, 8161, 10442, 25361}; wowsims/tbc-new sim/shaman/totems.go:
--     strengthOfEarthTotemRank = spellData.StrengthOfEarthTotem.BySpellID(25528);
--     wowsims/forever sim/shaman/spell_data_auto_gen.go: StrengthOfEarthTotem:
--     Ranked(8075, 8160, 8161, 10442, 25361).
--   mana_spring  25570 (TBC r5) / 10497 (r4 - the SoD and Forever PRE-PULL row)
--     wowsims/tbc-new sim/shaman/totems.go: manaSpringTotemRank =
--     spellData.ManaSpringTotem.BySpellID(25570); wowsims/classic
--     sim/shaman/water_totems.go: ManaSpringTotemSpellId = {0, 5675, 10495, 10496,
--     10497}.
--   frostshock  25464 (TBC r5)
--     wowsims/tbc-new sim/shaman/shocks.go: frostShockRank =
--     spellData.FrostShock.BySpellID(25464). (The WotLK Frost Shock is 49236 -
--     wowsims/wotlk sim/shaman/shocks.go - and no WotLK APL carries it.)
--   bloodlust  2825
--     wowsims/wotlk sim/shaman/bloodlust.go: BloodlustActionID = SpellID 2825.
ST.SHAMAN.APL_UTILITY = {
	strength_of_earth = {
		ids = { ERA = 10442, TBC = 25528, FOREVER = 25361 },
		name = "Strength of Earth Totem",
	},
	mana_spring = {
		ids = { SOD = 10497, TBC = 25570, FOREVER = 10497 },
		name = "Mana Spring Totem",
	},
	frostshock = {
		ids = { TBC = 25464 },
		name = "Frost Shock",
	},
	bloodlust = {
		ids = { WRATH = 2825 },
		name = "Bloodlust",
	},
}

-- The player's own "Filler Shock" choice (the TBC APL's valueVariable): the
-- option's own value keys - "earth" (the APL's DEFAULT, the valueVariables
-- entry) and "frost" (the ALTERNATIVE, the Shocks group's row 2: 25464 r5).
-- The gather maps "frost" to the engine's frozen token
-- (st.shaman_guide.FILLER_SHOCK_FROST); every other value - and a missing one -
-- reads as the APL's default, so the live prompt never changes unless the
-- player asks for it (the widget: option_tables.lua's guide_filler_shock; the
-- default: config_presets.lua).
ST.SHAMAN.FILLER_SHOCK_OPTION_EARTH = "earth"
ST.SHAMAN.FILLER_SHOCK_OPTION_FROST = "frost"

-- SoD rune/name feeds (audit 2026-10-19 SoD §): Feral Spirit, Lava Lash and Molten
-- Blast ship Wrath-era ids that never resolve on SoD, so ERA clients resolve them
-- by English name (never guessed - a client without the spell data leaves the feed
-- dead) with the same throttled-retry cache shape as the Lava Burst resolver below.
-- Feral Spirit 51533 / Lava Lash 60103 keep their id gates everywhere else;
-- Molten Blast 425339 is UNCONFIRMED (rune-enum role, audit UNCONFIRMED list) and
-- needs in-game confirmation. Shamanistic Rage resolves by name on SoD (425336,
-- not the TBC 30823); every other family keeps the 30823 id gate.
local WEAVE_MOLTEN_BLAST_SPELL_ID = 425339
local WEAVE_MOLTEN_BLAST_NAME = "Molten Blast"
local WEAVE_FERAL_SPIRIT_NAME = "Feral Spirit"
local WEAVE_LAVA_LASH_NAME = "Lava Lash"
local WEAVE_NAMED_SPELLS = {
	feralspirit = { name = WEAVE_FERAL_SPIRIT_NAME },
	lavalash = { name = WEAVE_LAVA_LASH_NAME },
	moltenblast = { name = WEAVE_MOLTEN_BLAST_NAME },
	shamanisticrage = { name = WEAVE_SR_NAME },
}

-- Flame Shock rank ids (target bar: 3850-4056; SuperSwingTimer_Constants.lua:197-206).
-- The name fallback covers ranks the id table does not list.
local WEAVE_FLAME_SHOCK_IDS = {
	[8050] = true, [8052] = true, [8053] = true, [10447] = true,
	[10448] = true, [29228] = true, [25457] = true,
}
local WEAVE_FLAME_SHOCK_NAME = "Flame Shock"
-- Target-aura scan cadence: the reference throttles at 0.05 s (3993-3996).
local WEAVE_FLAME_SHOCK_SCAN_INTERVAL = 0.05
-- Rank-1 Flame Shock id, for rank-agnostic cooldown reads (the shock cooldown is
-- shared with Earth Shock; the S4 FS-collision guard reads it by localized name).
local WEAVE_FLAME_SHOCK_BASE_SPELL_ID = 8050

-- Stormstrike nature-vulnerability debuff (S2 target bar): 17364 CONFIRMED
-- (12 s, +20% nature damage taken - bench/verify_bank.md §2, Wowhead TBC
-- spell=17364); the ability trigger id 32175 noted there is accepted defensively
-- (its aura-id role is UNCONFIRMED). The name fallback covers ranks the id table
-- does not list; reads stay guarded (id lookups and name compares are nil-safe).
local WEAVE_STORMSTRIKE_DEBUFF_IDS = {
	[17364] = true,
	[32175] = true,
}
local WEAVE_STORMSTRIKE_DEBUFF_NAME = "Stormstrike"

-- Lightning / Water Shield (charge row: 4058-4209; SuperSwingTimer_Constants.lua:208-258).
local WEAVE_LIGHTNING_SHIELD_IDS = {
	[324] = true, [325] = true, [905] = true, [945] = true, [8134] = true,
	[10431] = true, [10432] = true, [25469] = true, [25472] = true,
}
local WEAVE_LIGHTNING_SHIELD_NAMES = { ["Lightning Shield"] = true }
local WEAVE_WATER_SHIELD_IDS = {
	[52127] = true, [52129] = true, [52131] = true, [24398] = true,
	[33736] = true, [33737] = true, [34827] = true, [57960] = true,
}
local WEAVE_WATER_SHIELD_NAMES = { ["Water Shield"] = true, ["Mana Shield"] = true }

-- Tracker visual constants (parenthesised line references are the reference's).
local WEAVE_MARKER_GAP = 2                              -- triangleGap default (3439)
local WEAVE_WINDFURY_STRIP_WIDTH = 3                    -- wfIcdBar width (3811)
local WEAVE_WINDFURY_COLORS = {                         -- statusbar buckets (3840-3846)
	red = { 1, 0, 0, 0.85 },
	orange = { 1, 0.65, 0, 0.85 },
	green = { 0, 1, 0, 0.85 },
}
local WEAVE_WINDFURY_BG_COLOR = { 0, 0, 0, 0.5 }        -- ICD background (3819)
-- The weave visuals' own style constants ride the MODULE TABLE, not file-scope
-- locals: this module sits at the Lua 5.1 ceiling for file-scope locals (200),
-- so one more `local` here would be a LOAD FAILURE on every client. Nothing
-- below is mutated - every entry is read-only, exactly as the constants were.
ST.SHAMAN.flame_shock_style = {
	bar_height = 6,                  -- FLAME_SHOCK_BAR_HEIGHT (3850)
	color = { 1.0, 0.35, 0.10, 0.90 },      -- fill (3895)
	bg_color = { 0, 0, 0, 0.45 },           -- backing (3905)
	glow_color = { 1.0, 0.45, 0.08, 0.85 }, -- glow edge (3915)
	label_color = { 1.0, 0.85, 0.25, 0.95 }, -- label (3957)
}
local WEAVE_SS_BADGE_COLOR = { 0.25, 0.85, 1.0, 0.95 }  -- Stormstrike badge (3706)
local WEAVE_SR_BADGE_COLOR = { 0.15, 0.85, 1.0, 0.95 }  -- Shamanistic Rage badge (3730)
-- WF-fishing hold (S3): the SS badge flips amber and the bar's final fraction gets
-- an amber wash while Stormstrike is held for the Windfury proc.
local WEAVE_SS_HOLD_COLOR = { 1.0, 0.72, 0.15, 0.95 }
local WEAVE_WF_HOLD_WASH_COLOR = { 1.0, 0.72, 0.15, 0.18 }
-- Rockbiter Weapon badge (discover #6): stone-brown so it reads apart from the
-- SS/SR blues and the amber hold tint.
local WEAVE_RB_BADGE_COLOR = { 0.85, 0.62, 0.30, 0.95 }
-- Lust status badge (S1 effect-status row, Shaman leg): hot red so it reads apart
-- from the SS/SR blues; the "BL ?" unknown text reuses the same badge.
local WEAVE_LUST_BADGE_COLOR = { 1.0, 0.30, 0.25, 0.95 }
-- Lust status rescan cadence: the paladin twist override and the rogue lust canary
-- both re-poll at 0.5 s; this lane matches them so the three scans stay comparable.
local WEAVE_LUST_RESCAN_INTERVAL = 0.5
-- Stormstrike debuff target bar (S2): FS-bar clone styling, nature-teal.
ST.SHAMAN.stormstrike_style = {
	bar_height = 6,
	color = { 0.30, 0.80, 0.95, 0.90 },
	bg_color = { 0, 0, 0, 0.45 },
	glow_color = { 0.40, 0.88, 1.0, 0.85 },
	label_color = { 0.75, 0.95, 1.0, 0.95 },
}
ST.SHAMAN.shield_style = {
	rect_width = 5,                       -- LIGHTNING_SHIELD_RECT_WIDTH (3512)
	rect_gap = 1,                         -- LIGHTNING_SHIELD_RECT_GAP (3513)
	bar_gap = 6,                          -- tracker gap default (3515)
	dim_alpha = 0.20,                     -- empty-slot alpha (4177)
	colors = {                            -- (4058, 4151-4155)
		lightning = { 0.25, 0.72, 1.0, 0.90 },
		water = { 0.50, 0.80, 1.0, 0.90 },
	},
	-- One rect per possible shield charge slot: Lightning Shield can reach 4, Water Shield 3
	-- (mirrors weave.SHIELD_MAX_CHARGES; created once, the row shows `slots` of them).
	max_slots = 4,
}

-- Spell-position row (round 2, operator spec): the zone band + per-spell icons live
-- in a strip above the bar, clear of the Flame Shock (+2..8) and Stormstrike
-- (+10..16) bars; each icon sits at its spell's latest safe cast start and the
-- zone spans the min..max of those starts. All geometry is constant here so the
-- follow-up pass can refine the layout without touching the logic.
local WEAVE_POSITION_SLOTS = { "LB", "CL" }
local WEAVE_POSITION_LAVA_KEY = "LvB"
local WEAVE_ZONE_LABEL = "Spells start cast range zone"
local WEAVE_ZONE_BOTTOM = 18
local WEAVE_ZONE_HEIGHT = 14
local WEAVE_ZONE_LABEL_GAP = 2
local WEAVE_ZONE_COLOR = { 0.45, 0.75, 1.0, 0.12 }
local WEAVE_ZONE_LABEL_COLOR = { 0.75, 0.90, 1.0, 0.90 }
ST.SHAMAN.position_style = {
	icon_size = 14,
	ready_alpha = 0.95,
	clip_color = { 1.0, 0.15, 0.15, 0.95 },
	wait_color = { 0.6, 0.6, 0.6, 0.35 },
}

-- DW / Flurry badges (round 2): sync + Flurry stacks/ICD, stacked under the
-- Rockbiter badge on the mainhand column.
local WEAVE_SYNC_COLOR = { 0.30, 1.0, 0.40, 0.95 }
local WEAVE_DESYNC_COLOR = { 1.0, 0.72, 0.15, 0.95 }
local WEAVE_FLURRY_COLOR = { 0.65, 0.85, 1.0, 0.95 }

-- Badge/label font: the bar's configured font, with the client standard font as the
-- fallback for sandboxes and stripped clients.
local function get_tracker_font_path(self)
	local db_hand = self.get_hand_table and self:get_hand_table("mainhand")
	if LSM and LSM.Fetch and db_hand and db_hand.text_font then
		local path = LSM:Fetch("font", db_hand.text_font)
		if path then return path end
	end
	return STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
end

--=========================================================================================
-- Spell catalogue
--=========================================================================================
-- Resolve a family's highest known rank (ids run low -> high; walk backwards) that has a
-- positive cast time. Returns {spell_id, name, icon, cast_seconds} or nil. compat's
-- GetSpellInfo normalizes castTime to milliseconds on every family (classic global and
-- C_Spell.SpellInfo.castTime agree), so the 4th return is used directly.
-- Name-vs-id: TBC resolves by NAME (group.label) never bare id; every other
-- family resolves by id. Nil-safe: an unanswered name/id returns nil.
local function resolve_family_spell(group)
	if st.family == "TBC" then
		local label = group.label
		if label and api.is_spell_known(label) then
			local name, _, icon, cast_ms, _, _, answered_id = api.GetSpellInfo(label)
			if name and type(cast_ms) == "number" and cast_ms > 0 then
				return {
					spell_id = answered_id or label,
					name = name,
					icon = icon,
					cast_seconds = cast_ms / 1000,
				}
			end
		end
		return nil
	end
	for i = #group.ids, 1, -1 do
		local spell_id = group.ids[i]
		if api.is_spell_known(spell_id) then
			local name, _, icon, cast_ms = api.GetSpellInfo(spell_id)
			if name and type(cast_ms) == "number" and cast_ms > 0 then
				return {
					spell_id = spell_id,
					name = name,
					icon = icon,
					cast_seconds = cast_ms / 1000,
				}
			end
		end
	end
	return nil
end

-- Resolve every family still missing a spell. Families that resolve to nothing are
-- retried at most once per WEAVE_CATALOG_RETRY_S. CATALOGUE-RETRY OBSERVABILITY
-- (H4 follow-up): a sustained miss stays hidden-with-retry by design - after the
-- H4 split, an unresolved cast time is UNKNOWN and every weave widget hides/dims
-- instead of rendering an instant-0 marker, so the safe direction is silence plus
-- the throttled retry below. No chat/diag notice is added: a low-level character
-- whose spell book cannot answer yet would trip it on every login.
function ST.SHAMAN.resolve_weave_catalog(self)
	local now = api.get_time()
	for i = 1, #st.weave.SPELL_GROUPS do
		local group = st.weave.SPELL_GROUPS[i]
		local family = group.abbrev
		if not self.weave_catalog[family] and now >= (self.weave_catalog_retry_at[family] or 0) then
			local entry = resolve_family_spell(group)
			if entry then
				self.weave_catalog[family] = entry
			else
				self.weave_catalog_retry_at[family] = now + WEAVE_CATALOG_RETRY_S
			end
		end
	end
end

-- Drop every resolved entry so the next resolution pass re-reads the spellbook.
-- resolve_weave_catalog only fills MISSING families, so a rank learned after post_init
-- (level-up, respec, retrain) would otherwise keep the old rank's cast time and icon
-- for the rest of the session. The throttled retry stamps go too: a family that failed
-- to resolve must be retried immediately rather than after the throttle window.
function ST.SHAMAN.on_talents_changed(self)
	if not self.weave_catalog then
		return
	end
	for family in pairs(self.weave_catalog) do
		self.weave_catalog[family] = nil
	end
	if self.weave_catalog_retry_at then
		for family in pairs(self.weave_catalog_retry_at) do
			self.weave_catalog_retry_at[family] = nil
		end
	end
	-- The Lava Burst spender cache (S4) is talent/rune state too: drop it so the
	-- next resolution pass re-reads the spellbook (a rune engraved mid-session
	-- flips the MW5 choice without a reload).
	self.weave_lava_burst = nil
	self.weave_lava_burst_retry_at = nil
	-- The SoD name feeds (resolve_named_spell) are rune state the same way: drop
	-- every answered id and retry stamp so a rune engraved mid-session re-resolves
	-- without a reload.
	for key in pairs(WEAVE_NAMED_SPELLS) do
		self["weave_named_" .. key] = nil
		self["weave_named_" .. key .. "_retry_at"] = nil
	end
end

-- Resolve the Lava Burst (SoD rune) catalogue entry for the MW5 spender choice:
-- name query -> id -> icon and cast time, cached like the weave catalogue (the id
-- is never guessed - a client without the spell data leaves the cache empty and
-- retries are throttled). The player-level rune/talent gate is applied by the
-- caller through st.weave.get_mw5_spender (the SoD rune teaches the spell; an
-- Era-base character without the rune fails it even though the client's spell
-- data can resolve the name), so the choice follows the rune live.
function ST.SHAMAN.resolve_lava_burst(self)
	if st.family ~= "ERA" then
		return nil
	end
	local entry = self.weave_lava_burst
	if entry == nil then
		local now = api.get_time()
		if now < (self.weave_lava_burst_retry_at or 0) then
			return nil
		end
		local name, _, icon, cast_ms, _, _, lava_id = api.GetSpellInfo("Lava Burst")
		if type(lava_id) == "number" and name then
			entry = {
				spell_id = lava_id,
				name = name,
				icon = icon,
				cast_seconds = (type(cast_ms) == "number" and cast_ms or 0) / 1000,
			}
			self.weave_lava_burst = entry
		else
			self.weave_lava_burst_retry_at = now + WEAVE_CATALOG_RETRY_S
			return nil
		end
	end
	return entry
end

-- Resolve a SoD rune / rank-variant slot by English name (Feral Spirit, Lava Lash,
-- Molten Blast, Shamanistic Rage): the Wrath-era ids never resolve on SoD, so ERA
-- clients probe the client's own spell data by name and cache the answered id
-- (never guessed - an unanswered probe leaves the feed dead and retries throttled,
-- the resolve_lava_burst convention). ERA-only: every other family keeps its id
-- gate byte-identical. The player-level rune/talent gate is applied by the caller
-- (IsSpellKnown on the answered id, or the SoD MW latch), so the choice follows
-- the rune live. Returns the { spell_id, name, icon, cast_seconds } entry or nil.
function ST.SHAMAN.resolve_named_spell(self, key)
	if st.family ~= "ERA" then
		return nil
	end
	local spec = WEAVE_NAMED_SPELLS[key]
	if not spec then
		return nil
	end
	local cache_key = "weave_named_" .. key
	local retry_key = cache_key .. "_retry_at"
	local entry = self[cache_key]
	if entry == nil then
		local now = api.get_time()
		if now < (self[retry_key] or 0) then
			return nil
		end
		local name, _, icon, cast_ms, _, _, spell_id = api.GetSpellInfo(spec.name)
		if type(spell_id) == "number" and name then
			entry = {
				spell_id = spell_id,
				name = name,
				icon = icon,
				cast_seconds = (type(cast_ms) == "number" and cast_ms or 0) / 1000,
			}
			self[cache_key] = entry
		else
			self[retry_key] = now + WEAVE_CATALOG_RETRY_S
			return nil
		end
	end
	return entry
end

-- Look up a family by a numeric spell id or a localized spell-name token.
local function lookup_weave_family(self, token)
	if token == nil or not self.weave_catalog then
		return nil
	end
	for i = 1, #st.weave.FAMILIES do
		local family = st.weave.FAMILIES[i]
		local entry = self.weave_catalog[family]
		if entry and (entry.spell_id == token or entry.name == token) then
			return family
		end
	end
	return nil
end

--=========================================================================================
-- Live inputs: haste and Maelstrom Weapon
--=========================================================================================
-- Spell-haste percentage: UnitSpellHaste where present, then the older GetSpellHaste,
-- then 0. The compat wrappers return nil on clients that lack the function.
local function get_spell_haste_percent()
	local haste = api.UnitSpellHaste("player")
	if type(haste) == "number" then
		return haste
	end
	haste = api.GetSpellHaste()
	if type(haste) == "number" then
		return haste
	end
	return 0
end

-- One walk of the player's auras for the weave inputs AND the tracker state: the
-- Maelstrom Weapon stack count, the buff haste multiplier, whether Windfury Weapon is
-- active (ICD strip), Shamanistic Rage's expiry (SR badge), whether Rockbiter Weapon is
-- active and its expiry (RB badge), the Flurry stack count (DW/Flurry badge) and the
-- active shield's type and charge count (charge row). An aura without a count still
-- means one Maelstrom stack (the reference's max(1, count) handling). The walk stops
-- once every lookup is resolved, so the early exits survive while costing at most one
-- walk per aura change. The result is handed back in a reused module-local table (no
-- per-frame allocation); read it before the next call.
local weave_aura_scan = {
	stacks = 0, buff_multiplier = 1, windfury = false,
	sr_expires = nil, rockbiter = false, rockbiter_expires = nil,
	flurry = nil, shield_type = nil, shield_charges = nil,
	clearcasting = false, scanned = false,
}
local function scan_weave_auras()
	local stacks, mw_found = 0, false
	local bloodlust, berserking = false, false
	local windfury, sr_found, sr_expires = false, false, nil
	local rockbiter, rockbiter_expires = false, nil
	local flurry_count = nil
	local shield_type, shield_charges = nil, nil
	local clearcasting = false
	local i = 1
	while i <= 40 do
		local name, _, count, _, _, expiration, _, _, _, spell_id = api.UnitAura("player", i, "HELPFUL")
		-- No early break (R2): nil is simply no match at this index.
		if name ~= nil then
			if not mw_found
				and ((spell_id and WEAVE_MW_SPELL_IDS[spell_id]) or name == WEAVE_MW_NAME) then
				local n = tonumber(count) or 1
				if n > st.weave.MW_MAX_STACKS then
					n = st.weave.MW_MAX_STACKS
				elseif n < 1 then
					n = 1
				end
				stacks = n
				mw_found = true
			end
			if not bloodlust and ((spell_id and WEAVE_BLOODLUST_IDS[spell_id]) or name == "Bloodlust" or name == "Heroism"
				-- Rage of the Farseer (UNCONFIRMED, name-only: no spell id published,
				-- so the literal name IS the probe - the only one Forever exposes).
				or name == WEAVE_FARSEER_NAME) then
				bloodlust = true
			end
			if not berserking and ((spell_id and WEAVE_BERSERKING_IDS[spell_id]) or name == "Berserking") then
				berserking = true
			end
			if not windfury
				and ((spell_id and WEAVE_WINDFURY_IDS[spell_id]) or WEAVE_WINDFURY_NAMES[name]) then
				windfury = true
			end
			if not sr_found and ((spell_id and spell_id == WEAVE_SR_SPELL_ID) or name == WEAVE_SR_NAME) then
				sr_found = true
				if type(expiration) == "number" and expiration > 0 then
					sr_expires = expiration
				end
			end
			if not rockbiter
				and ((spell_id and WEAVE_ROCKBITER_IDS[spell_id]) or name == WEAVE_ROCKBITER_NAME) then
				rockbiter = true
				if type(expiration) == "number" and expiration > 0 then
					rockbiter_expires = expiration
				end
			end
			if flurry_count == nil
				and ((spell_id and WEAVE_FLURRY_IDS[spell_id]) or name == WEAVE_FLURRY_NAME) then
				local n = tonumber(count) or 1
				if n < 1 then n = 1 end
				flurry_count = n
			end
			if not shield_type then
				if (spell_id and WEAVE_LIGHTNING_SHIELD_IDS[spell_id])
					or WEAVE_LIGHTNING_SHIELD_NAMES[name] then
					shield_type = "lightning"
					shield_charges = tonumber(count)
				elseif (spell_id and WEAVE_WATER_SHIELD_IDS[spell_id])
					or WEAVE_WATER_SHIELD_NAMES[name] then
					shield_type = "water"
					shield_charges = tonumber(count)
				end
			end
			if not clearcasting
				and ((spell_id and WEAVE_CLEARCASTING_IDS[spell_id]) or name == WEAVE_CLEARCASTING_NAME) then
				clearcasting = true
			end
			if mw_found and bloodlust and berserking and windfury and sr_found
				and rockbiter and flurry_count and shield_type then
				break
			end
		end
		i = i + 1
	end
	local mult = 1
	-- UNCONFIRMED on Forever: the Farseer leg above borrows Bloodlust's 30%
	-- (no haste value published for Rage of the Farseer - the beta guides name
	-- the spell only). The leg itself is never guessed (the aura must actually
	-- be present), but the 1.30 factor is assumed from Bloodlust parity until
	-- the value is confirmed in-game.
	if bloodlust then mult = mult * 1.30 end
	if berserking then mult = mult * 1.10 end
	weave_aura_scan.stacks = stacks
	weave_aura_scan.buff_multiplier = mult
	weave_aura_scan.windfury = windfury
	weave_aura_scan.sr_expires = sr_expires
	weave_aura_scan.rockbiter = rockbiter
	weave_aura_scan.rockbiter_expires = rockbiter_expires
	weave_aura_scan.flurry = flurry_count
	weave_aura_scan.shield_type = shield_type
	weave_aura_scan.shield_charges = shield_charges
	weave_aura_scan.clearcasting = clearcasting
	-- The walk ran: the shield leg below reads "no shield aura" only after a walk
	-- has actually answered (an unrun walk is unknown, never "no shield").
	weave_aura_scan.scanned = true
	return weave_aura_scan
end

-- Buff haste multiplier: Bloodlust/Heroism (x1.30) and Berserking (x1.10) compound; the
-- caller then maxes the result against the spell-haste value (never multiplies it).
-- buff_multiplier is a value a merged scan already collected; nil walks the auras on
-- its own, so the refresh hooks stay usable standalone.
local function get_buff_haste_multiplier(buff_multiplier)
	if buff_multiplier == nil then
		buff_multiplier = scan_weave_auras().buff_multiplier
	end
	return buff_multiplier
end

-- Refresh the spell-haste multiplier (cast starts and aura changes). The optional
-- buff_multiplier is the value a merged scan already collected.
function ST.SHAMAN.refresh_weave_haste(self, buff_multiplier)
	self.weave_haste_mult = st.weave.get_max_haste_multiplier(
		get_spell_haste_percent(), get_buff_haste_multiplier(buff_multiplier))
end

-- Refresh the Maelstrom Weapon stack count (aura changes). The optional stacks value
-- comes from a merged scan; nil performs its own walk, so the hook stays usable
-- standalone with identical results. Any positive count latches weave_mw_observed
-- for the session (SoD shares the ERA token but HAS the MW rune: the first actually
-- observed aura/stack signal is what re-enables the markers and the MW guide rules
-- there; Era-base never observes it and stays off). The latch never clears: a
-- dropped aura means zero stacks, not a client without Maelstrom.
function ST.SHAMAN.refresh_weave_mw_stacks(self, stacks)
	if stacks == nil then
		stacks = scan_weave_auras().stacks
	end
	self.weave_mw_stacks = stacks
	if type(stacks) == "number" and stacks > 0 then
		self.weave_mw_observed = true
		-- The SoD build is the ERA token's own build: the practice vocabulary
		-- follows it (the Lightning Shield row rides the SoD slice). The call
		-- is a no-op until the practice surface cut the list once, so the
		-- guide frame's own icon set never changes under it.
		if ST.SHAMAN.applied_family_token ~= nil then
			ST.SHAMAN.apply_family_slots()
		end
	end
end

-- Effective Maelstrom gate: the shipped weave_mw_enabled default is unconditionally
-- true (nothing sets it per client), so the family token supplies the per-client
-- default via st.weave.has_maelstrom_weapon - TBC never has Maelstrom Weapon, ERA
-- needs the aura-observed latch (SoD HAS the 408505 rune; Era-base never observes
-- it and stays off; Forever keeps the unconditional read - bars_state pins its
-- marker, MW at 60 UNCONFIRMED) - while the option remains the user kill-switch
-- everywhere.
-- RESIDUAL SoD specifics: the Lava Burst vs Lightning Bolt 5-stack choice is
-- surfaced by re-pointing the weave slot at Lava Burst when the rune is known
-- (resolve_guide_icons); the engine keeps prompting the generic weave slot at 5
-- stacks only (MW5-only, like Wrath). Rolling Thunder stack-gen is not modelled -
-- FS/ES already alternate (guide rules 5 and 12). The Stormstrike-debuff read for
-- the spender choice needs a target-debuff tracker plus in-game confirmation.
local function is_weave_mw_active(db, mw_observed)
	if db and db.weave_mw_enabled == false then
		return false
	end
	return st.weave.has_maelstrom_weapon(st.family, mw_observed)
end

-- Effective cast time (seconds) for a resolved spell entry, with the current haste and
-- (unless disabled in the options, or absent on this client family) the Maelstrom
-- Weapon reduction.
function ST.SHAMAN.get_weave_effective_cast_time(self, entry)
	local mw_mult = 1
	if is_weave_mw_active(self:get_class_table(), self.weave_mw_observed) then
		mw_mult = st.weave.get_maelstrom_multiplier(self.weave_mw_stacks)
	end
	return st.weave.get_effective_cast_time(entry.cast_seconds, self.weave_haste_mult, mw_mult, false)
end

--=========================================================================================
-- Cast tracking
--=========================================================================================
-- The player's live cast/channel window. UnitCastingInfo and UnitChannelInfo do NOT share
-- a return shape: casting returns castID before notInterruptible and the spell id 9th,
-- channeling has no castID and the spell id 8th (verified against the generated client
-- documentation on every family branch). Returns name, spell_id, start-time and
-- end-time seconds (ms/1000 keeps the GetTime() domain for DELAYED re-anchoring).
local function get_live_player_cast()
	local name, _, _, start_ms, end_ms, _, _, _, spell_id = api.UnitCastingInfo("player")
	if type(start_ms) ~= "number" or type(end_ms) ~= "number" or end_ms <= start_ms then
		name, _, _, start_ms, end_ms, _, _, spell_id = api.UnitChannelInfo("player")
	end
	if type(start_ms) ~= "number" or type(end_ms) ~= "number" or end_ms <= start_ms then
		return nil, nil, nil, nil
	end
	return name, spell_id, start_ms / 1000, end_ms / 1000
end

-- Record the start (or delay) of a tracked cast. The client's live start/end window wins
-- over the computed effective cast time; a DELAYED event refreshes the end without moving
-- our start stamp, so the spark keeps travelling smoothly. keep_swing_anchor re-anchors
-- the timing of a cast already in flight (DELAYED) without re-measuring the swing the
-- cast began in - see the swing-anchor note below.
local function begin_weave_cast(self, family, live_start, live_end, keep_swing_anchor)
	local entry = self.weave_catalog[family]
	if not entry then
		return
	end
	self.SHAMAN.refresh_weave_haste(self)
	local now = api.get_time()
	local start_time = now
	local end_time
	if type(live_start) == "number" and type(live_end) == "number" and live_end > live_start then
		start_time = live_start
		end_time = live_end
	end
	self.weave_is_casting = true
	self.weave_spell_id = entry.spell_id
	self.weave_family = family
	self.weave_cast_start_time = start_time
	self.weave_cast_end_time = end_time
	self.weave_cast_duration = end_time and (end_time - start_time)
		or self.SHAMAN.get_weave_effective_cast_time(self, entry)
	local d = self.mainhand
	if d and d.speed and d.ends_at and d.start and not d.is_full then
		-- Swing-anchor note: BOTH swing anchors are measured against the swing that was
		-- current when the cast began and are then held for the whole cast. Rolling them
		-- forward with the live swing would move the cast's start AND its projected
		-- landing by one swing duration every rollover, which made the spark jump back
		-- toward its origin and re-travel. A DELAYED event keeps the anchors it was
		-- given (same cast); everything else re-measures, because a new cast really did
		-- begin in whatever swing is current now.
		if not (keep_swing_anchor and self.weave_cast_swing_start ~= nil) then
			self.weave_cast_swing_start = d.start
			-- Anchored on the cast's own start stamp, not on the tick's now: a START
			-- payload that arrives after the cast began must still report where in the
			-- swing the cast started.
			self.weave_cast_start_swing_fraction = st.weave.get_cast_start_fraction(start_time, d.start, d.speed)
		end
	else
		self.weave_cast_swing_start = nil
		self.weave_cast_start_swing_fraction = nil
	end
end

-- End the active-cast state (the last-known family is kept for the marker).
local function end_weave_cast(self)
	self.weave_is_casting = false
	self.weave_cast_start_time = nil
	self.weave_cast_end_time = nil
	self.weave_cast_start_swing_fraction = nil
	self.weave_cast_swing_start = nil
	self.weave_cast_duration = nil
end

-- Is this token one of the totem-twist drops? A numeric spell id matches the id
-- table; a name token (older-style payloads, the live GetSpellInfo resolution in
-- on_spellcast_succeeded and the air-slot totemName) matches the name set, so
-- ranks whose ids are still unconfirmed stamp by name. Anything else is not a
-- twist drop.
local function is_twist_totem(token)
	if token == nil then
		return false
	end
	if WEAVE_TWIST_TOTEM_IDS[token] then
		return true
	end
	if type(token) == "string" and WEAVE_TWIST_TOTEM_NAMES[token] then
		return true
	end
	return false
end

-- Is this token the Era Windfury Totem (G2)? Same shape as the twist matcher
-- above, but WF-only: the numeric rank-1 id matches the id table (10614
-- UNCONFIRMED), a name token matches the name set, so unconfirmed ranks read
-- by name. Grace of Air is NOT a match here - the two rank separately.
local function is_wf_totem(token)
	if token == nil then
		return false
	end
	if WEAVE_WF_TOTEM_IDS[token] then
		return true
	end
	if type(token) == "string" and WEAVE_WF_TOTEM_NAMES[token] then
		return true
	end
	return false
end

-- Is this token the Era Grace of Air Totem (G2)? Same shape, GoA-only.
local function is_goa_totem(token)
	if token == nil then
		return false
	end
	if WEAVE_GOA_TOTEM_IDS[token] then
		return true
	end
	if type(token) == "string" and WEAVE_GOA_TOTEM_NAMES[token] then
		return true
	end
	return false
end

-- Reconcile the last-drop stamp with the live air-slot totem clock: an active
-- twist-named totem (name or spell id) with a positive startTime adopts it when
-- the stamp is unknown or older. This covers loads/reloads mid-twist and missed
-- SUCCEEDED events; an absent totem, a non-twist air totem (Nature Resistance and
-- friends share the slot) and an unreadable startTime leave the stamp alone, so no
-- prompt is ever built on a guess. Newer wins: a stale poll reading never rewinds
-- a fresher cast commit.
function ST.SHAMAN.refresh_twist_from_totems(self)
	local have_totem, totem_name, start_time, _, _, _, spell_id =
		api.GetTotemInfo(WEAVE_TOTEM_SLOTS.AIR)
	if not have_totem then
		return
	end
	if not is_twist_totem(totem_name) and not is_twist_totem(spell_id) then
		return
	end
	if type(start_time) ~= "number" or start_time <= 0 then
		return
	end
	local known = self.weave_twist_last_drop
	if type(known) ~= "number" or known <= 0 or start_time > known then
		self.weave_twist_last_drop = start_time
	end
end

-- Is this token a Magma Totem drop? Same shape as the twist matcher above: a numeric
-- spell id matches the id table (8190 UNCONFIRMED), a name token matches the name
-- set, so unconfirmed ranks stamp by name. Anything else is not a Magma drop.
local function is_magma_totem(token)
	if token == nil then
		return false
	end
	if WEAVE_MAGMA_TOTEM_IDS[token] then
		return true
	end
	if type(token) == "string" and WEAVE_MAGMA_TOTEM_NAMES[token] then
		return true
	end
	return false
end

-- Is this token a Searing Totem drop? Same shape as the magma matcher above:
-- the rank-1 id matches the id table (10438 UNCONFIRMED), a name token
-- matches the name set, so unconfirmed ranks stamp by name. Anything else is
-- not a Searing drop.
local function is_searing_totem(token)
	if token == nil then
		return false
	end
	if WEAVE_SEARING_TOTEM_IDS[token] then
		return true
	end
	if type(token) == "string" and WEAVE_SEARING_TOTEM_NAMES[token] then
		return true
	end
	return false
end

-- Is this token a Fire Elemental Totem drop? Same shape as the magma matcher above:
-- the rank-1 id matches the id table (2894 UNCONFIRMED), a name token matches the
-- name set, so unconfirmed ranks stamp by name. Anything else is not a Fire Ele.
local function is_fireele_totem(token)
	if token == nil then
		return false
	end
	if WEAVE_FIRE_ELEMENTAL_IDS[token] then
		return true
	end
	if type(token) == "string" and WEAVE_FIRE_ELEMENTAL_NAMES[token] then
		return true
	end
	return false
end
-- Reconcile the last-drop stamp with the live fire-slot totem clock (Magma
-- maintain): an active Magma Totem (name or spell id) with a positive startTime
-- adopts it when the stamp is unknown or older. This covers loads/reloads with
-- Magma up and missed SUCCEEDED events; an absent totem, a non-Magma fire totem
-- (Searing, Totem of Wrath, Fire Elemental and friends share the slot) and an
-- unreadable startTime leave the stamp alone, so no prompt is ever built on a
-- guess. Newer wins: a stale poll reading never rewinds a fresher cast commit.
-- Returns true when the client affirmatively reports an empty fire slot
-- (haveTotem == false): the totem is due. A nil read (MayReturnNothing empty,
-- throwing read, secret field, no API) is unknown, never "no totem" - the
-- compat contract - so the gather leaves the feed dead on it.
function ST.SHAMAN.refresh_magma_from_totems(self)
	local have_totem, totem_name, start_time, _, _, _, spell_id =
		api.GetTotemInfo(WEAVE_TOTEM_SLOTS.FIRE)
	if have_totem == nil then
		return false
	end
	if have_totem == false then
		self.weave_magma_last_drop = nil
		return true
	end
	if not is_magma_totem(totem_name) and not is_magma_totem(spell_id) then
		return false
	end
	if type(start_time) ~= "number" or start_time <= 0 then
		return false
	end
	local known = self.weave_magma_last_drop
	if type(known) ~= "number" or known <= 0 or start_time > known then
		self.weave_magma_last_drop = start_time
	end
	return false
end
-- Reconcile the last-drop stamp with the live fire-slot totem clock (Searing
-- maintain): same contract as the magma reconcile above. An active Searing
-- Totem (name or spell id) with a positive startTime adopts it when the stamp
-- is unknown or older; an affirmatively empty fire slot clears the stamp (the
-- totem is down); a nil read (MayReturnNothing empty, throwing read, secret
-- field, no API) is unknown, never "no totem" - the compat contract - so the
-- gather feeds dead on it. Newer wins: a stale poll reading never rewinds a
-- fresher cast commit. Returns the slot state for the gather: (empty, holding)
-- where empty is true only on an affirmative empty slot and holding is true
-- only while the slot affirmatively holds Searing (nil occupancy reads
-- unknown, never a guess).
function ST.SHAMAN.refresh_searing_from_totems(self)
	local have_totem, totem_name, start_time, _, _, _, spell_id =
		api.GetTotemInfo(WEAVE_TOTEM_SLOTS.FIRE)
	if have_totem == nil then
		return false, nil
	end
	if have_totem == false then
		self.weave_searing_last_drop = nil
		return true, false
	end
	if not is_searing_totem(totem_name) and not is_searing_totem(spell_id) then
		return false, false
	end
	if type(start_time) ~= "number" or start_time <= 0 then
		return false, nil
	end
	local known = self.weave_searing_last_drop
	if type(known) ~= "number" or known <= 0 or start_time > known then
		self.weave_searing_last_drop = start_time
	end
	return false, true
end

-- The totem-slot clock (the shared reader behind the water clock and the earth
-- clock): how long the totem in `slot` has left, and how long it lasts.
-- api.GetTotemInfo answers haveTotem, name, startTime, duration, icon, modRate,
-- spellID (compat.lua's wrapper) and the startTime is on the api.get_time() axis,
-- so the remaining time is duration - (now - startTime).
-- CONTRACT (the same tri-state the fire/air readers follow - unknown is never
-- "empty"):
--   * remaining = the seconds left on the slot's totem (0 when the slot is
--     affirmatively EMPTY - the drop is due then), and duration = the totu's
--     full length when the client reports one.
--   * nil = UNKNOWN (no GetTotemInfo on this client, a MayReturnNothing read, a
--     throwing read, a secret field, an unreadable start/duration) - the caller
--     never prompts on a guess.
function ST.SHAMAN.get_totem_slot_clock(self, slot, now)
	local have_totem, _, start_time, duration = api.GetTotemInfo(slot)
	if have_totem == nil then
		return nil, nil
	end
	if have_totem == false then
		-- Affirmatively empty: no totem is up, so the drop is due and
		-- there is no length to report.
		return 0, nil
	end
	if type(start_time) ~= "number" or type(duration) ~= "number" or duration <= 0 then
		return nil, nil
	end
	local elapsed = (now or api.get_time()) - start_time
	local remaining = duration - elapsed
	if remaining < 0 then
		remaining = 0
	end
	return remaining, duration
end

-- The water-totem clock (S-20 / U-10): how long the water totem has left, and
-- how long it lasts. api.GetTotemInfo(WEAVE_TOTEM_SLOTS.WATER) answers
-- haveTotem, name, startTime, duration, icon, modRate, spellID (compat.lua's
-- wrapper) and the startTime is on the api.get_time() axis, so the remaining
-- time is duration - (now - startTime).
-- CONTRACT (the same tri-state the fire/air readers follow - unknown is never
-- "empty"):
--   * remaining = the seconds left on the water totem (0 when the slot is
--     affirmatively EMPTY - the Call of the Elements drop is due then), and
--     duration = the totu's full length when the client reports one.
--   * nil = UNKNOWN (no GetTotemInfo on this client, a MayReturnNothing read, a
--     throwing read, a secret field, an unreadable start/duration) - the caller
--     never prompts on a guess.
function ST.SHAMAN.get_water_totem_clock(self, now)
	return ST.SHAMAN.get_totem_slot_clock(self, WEAVE_TOTEM_SLOTS.WATER, now)
end

function ST.SHAMAN.on_spellcast_event(self, event, unit, cast_guid, spell_id)
	if unit ~= "player" or not self.interfaces_are_initialised then
		return
	end

	if event == "UNIT_SPELLCAST_START"
		or event == "UNIT_SPELLCAST_DELAYED"
		or event == "UNIT_SPELLCAST_CHANNEL_START" then
		-- The live window is fetched either way: it carries the family for payloads
		-- without a spell token, and the live duration when a cast is running.
		local live_name, live_spell_id, live_start, live_end = get_live_player_cast()

		-- Numeric id first, then a name token (older-style payloads).
		local family = lookup_weave_family(self, spell_id) or lookup_weave_family(self, cast_guid)
		if not family then
			family = lookup_weave_family(self, live_spell_id) or lookup_weave_family(self, live_name)
		end
		if not family then
			-- A family may have been learned since the last resolution: retry (throttled)
			-- before giving up on the cast.
			self.SHAMAN.resolve_weave_catalog(self)
			family = lookup_weave_family(self, spell_id) or lookup_weave_family(self, cast_guid)
				or lookup_weave_family(self, live_spell_id) or lookup_weave_family(self, live_name)
		end

		if family then
			begin_weave_cast(self, family, live_start, live_end, event == "UNIT_SPELLCAST_DELAYED")
		elseif event == "UNIT_SPELLCAST_DELAYED" and self.weave_is_casting and self.weave_family then
			-- Keep tracking the running cast and re-anchor its timing.
			begin_weave_cast(self, self.weave_family, live_start, live_end, true)
		end
		return
	end

	if event == "UNIT_SPELLCAST_STOP"
		or event == "UNIT_SPELLCAST_INTERRUPTED"
		or event == "UNIT_SPELLCAST_FAILED"
		or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		end_weave_cast(self)
	end
end

function ST.SHAMAN.on_spellcast_succeeded(self, unit_id, cast_guid, spell_id)
	if unit_id ~= "player" or not self.interfaces_are_initialised then
		return
	end
	-- Keep the finished cast as the last-known family (the marker keeps showing its
	-- breakpoint) and end the active-cast state. Instants (5 Maelstrom Weapon stacks)
	-- only fire SUCCEEDED, so the token is also how they become the last cast.
	local family = lookup_weave_family(self, spell_id) or lookup_weave_family(self, cast_guid)
	if family then
		self.weave_family = family
		self.weave_spell_id = self.weave_catalog[family].spell_id
	end
	-- Totem-twist drops commit here (totem casts are instants: SUCCEEDED is the only
	-- event they fire). Numeric id first, then the name token (older-style payloads),
	-- then the cast's live spell name so ranks whose ids are still unconfirmed stamp
	-- by name. The stamp is the api.get_time() commit time, the same domain the
	-- air-slot startTime and the guide's now share.
	local live_name
	if spell_id ~= nil then
		-- Event-id to name bridge (nil-safe): unconfirmed totem ranks stamp
		-- by their live spell name (the id tables only carry confirmed ranks).
		-- The MATCH itself is name-based on every family (is_*_totem checks
		-- the name set), so TBC still resolves by NAME here; the id read only
		-- translates the event token and never probes the spellbook.
		live_name = api.GetSpellInfo(spell_id)
	end
	if is_twist_totem(spell_id) or is_twist_totem(cast_guid)
		or is_twist_totem(live_name) then
		self.weave_twist_last_drop = api.get_time()
	end
	-- Magma maintain drops commit here too (totem drops are instants: SUCCEEDED is
	-- the only event they fire). Same token shapes as the twist commit above, so
	-- unconfirmed Magma ranks stamp by name. The stamp is the api.get_time()
	-- commit time, the same domain the fire-slot startTime and the guide share.
	if is_magma_totem(spell_id) or is_magma_totem(cast_guid)
		or is_magma_totem(live_name) then
		self.weave_magma_last_drop = api.get_time()
	end
	-- Searing maintain drops commit here too (same instant shape as magma:
	-- totem drops are instants, so SUCCEEDED is the only event they fire).
	-- Same token shapes, so unconfirmed Searing ranks stamp by name. The
	-- stamp is the api.get_time() commit time, the same domain the fire-slot
	-- startTime and the guide's now share.
	if is_searing_totem(spell_id) or is_searing_totem(cast_guid)
		or is_searing_totem(live_name) then
		self.weave_searing_last_drop = api.get_time()
	end
	-- Fire Elemental drops commit here too (same instant shape): the uptime guard
	-- (rule 11 Nova suppression) counts from the commit. Same token shapes, so
	-- unconfirmed ranks stamp by name; the stamp is cleared when the fire slot
	-- affirmatively empties or swaps (see the gather).
	if is_fireele_totem(spell_id) or is_fireele_totem(cast_guid)
		or is_fireele_totem(live_name) then
		self.weave_fireele_last_drop = api.get_time()
	end
	end_weave_cast(self)
end

function ST.SHAMAN.on_aura_change(self)
	-- Haste buffs, Maelstrom Weapon stacks and the tracker state (windfury, Shamanistic
	-- Rage, Rockbiter, Flurry, shield charges) all change here and are read by the SAME
	-- auras, so one walk feeds every refresh below. No widgets are touched: this hook
	-- runs from UNIT_AURA.
	local scan = scan_weave_auras()
	self.SHAMAN.refresh_weave_haste(self, scan.buff_multiplier)
	self.SHAMAN.refresh_weave_mw_stacks(self, scan.stacks)
	self.weave_windfury_active = scan.windfury
	self.weave_sr_expires = scan.sr_expires
	self.weave_rockbiter_active = scan.rockbiter
	self.weave_rockbiter_expires = scan.rockbiter_expires
	-- Flurry (round 2): the stack count feeds the DW/Flurry badge; a count INCREASE
	-- (a fresh aura or a new proc while one is active) stamps the proc time the
	-- 0.5 s ICD counts from. A decrease is a charge consumed - never a stamp.
	local flurry_count = scan.flurry
	if type(flurry_count) == "number" and flurry_count > (self.weave_flurry_stacks or 0) then
		self.weave_flurry_proc_at = api.get_time()
	end
	self.weave_flurry_stacks = flurry_count
	self.weave_shield_type = scan.shield_type
	self.weave_shield_charges = scan.shield_charges
	-- The walk ran (the Lightning Shield maintain reads "no shield aura" only
	-- after a walk has answered; see the guide's rule 11b).
	self.weave_shield_scanned = scan.scanned == true
	-- Clearcasting (Forever free-Nova proc): the aura's presence is the feed; the
	-- gather reads it verbatim, so an absent aura reads as down (never a guess).
	self.weave_clearcasting = scan.clearcasting == true
end

function ST.SHAMAN.on_combat_exit(self)
	-- A wipe interrupts the cast without ever firing STOP/SUCCEEDED, so the cast state
	-- would stay "live" and leave a frozen spark and a stale clip tint for the rest of
	-- the session. Clear the in-flight cast (end_weave_cast keeps the last resolved
	-- family, so the marker still shows that spell's breakpoint).
	end_weave_cast(self)
end

function ST.SHAMAN.post_init(self)
	-- Weave state: the cast tracker, the per-family resolved spell catalog, and the live
	-- inputs the frozen weave.lua math consumes.
	self.weave_is_casting = false
	self.weave_spell_id = nil
	self.weave_family = nil
	self.weave_cast_start_time = nil
	self.weave_cast_end_time = nil
	self.weave_cast_start_swing_fraction = nil
	self.weave_cast_swing_start = nil
	self.weave_cast_duration = nil
	self.weave_marker_icon = nil
	self.weave_mw_stacks = 0
	self.weave_mw_observed = false
	self.weave_haste_mult = 1
	self.weave_catalog = {}
	self.weave_catalog_retry_at = {}

	-- Tracker state (windfury ICD, Shamanistic Rage, flame shock, Stormstrike debuff,
	-- Rockbiter, shields). The flame shock / Stormstrike caches are refreshed lazily
	-- by the throttled target scan in on_bar_update.
	self.weave_windfury_active = false
	self.weave_windfury_bucket = nil
	-- Totem-twist last-drop stamp (TBC): api.get_time() of the last Windfury/Grace
	-- of Air commit (SUCCEEDED) or the air-slot totem clock, reconciled in
	-- refresh_twist_from_totems. Nil means unknown - the guide never prompts on a
	-- guess (see gather_guide_inputs).
	self.weave_twist_last_drop = nil
	-- Magma maintain last-drop stamp (Wrath): api.get_time() of the last Magma
	-- Totem commit (SUCCEEDED) or the fire-slot totem clock, reconciled in
	-- refresh_magma_from_totems. Nil means unknown - the guide never prompts on a
	-- guess (see gather_guide_inputs).
	self.weave_magma_last_drop = nil
	-- Searing maintain last-drop stamp: api.get_time() of the last Searing
	-- Totem commit (SUCCEEDED) or the fire-slot totem clock, reconciled in
	-- refresh_searing_from_totems. Nil means unknown - no rule reads the feed
	-- yet, so it never prompts on a guess (see gather_guide_inputs).
	self.weave_searing_last_drop = nil
	-- Fire Elemental uptime-guard stamp: api.get_time() of the last Fire Elemental
	-- Totem commit (SUCCEEDED). Nil means unknown - the Nova suppression never
	-- fires on a guess; an affirmatively emptied/swapped fire slot clears it.
	self.weave_fireele_last_drop = nil
	self.weave_sr_expires = nil
	self.weave_rockbiter_active = false
	self.weave_rockbiter_expires = nil
	self.weave_flurry_stacks = nil
	self.weave_flurry_proc_at = nil
	self.weave_shield_type = nil
	self.weave_shield_charges = nil
	self.weave_shield_scanned = false
	self.weave_clearcasting = false
	self.weave_shield_layout_slots = nil
	self.weave_fs_duration = nil
	self.weave_fs_expires = nil
	self.weave_fs_scan_at = nil
	self.weave_fs_glow_on = false
	self.weave_fs_label_seconds = nil
	self.weave_storm_duration = nil
	self.weave_storm_expires = nil
	self.weave_storm_glow_on = false
	self.weave_storm_label_seconds = nil
	self.weave_ss_seconds = nil
	self.weave_ss_badge_mode = nil
	self.weave_sr_seconds = nil
	self.weave_rb_seconds = nil
	self.weave_sync_readout = nil
	self.weave_flurry_readout = nil
	-- Lava Burst spender cache (S4; resolved lazily on ERA clients) and its retry stamp.
	self.weave_lava_burst = nil
	self.weave_lava_burst_retry_at = nil

	-- Haste/Maelstrom/tracker snapshot and the initial catalogue (also parses auras,
	-- like the paladin does for seals).
	self.SHAMAN.on_aura_change(self)
	self.SHAMAN.resolve_weave_catalog(self)

	-- Next Action Guide: resolve the weave slot's icon from the catalogue just resolved,
	-- then hand the provider (ST.SHAMAN.guide at the end of this file) to the shared
	-- frame. Guarded so a flavor without nextaction_ui stays inert; the guide itself
	-- stays hidden until nextaction_enabled is turned on.
	self.SHAMAN.resolve_guide_icons(self)
	-- The HUD row's two maintain mirrors re-point their icons from the same
	-- resolution (the guide slots' ids are the answer), before the HUD builds.
	self.SHAMAN.resolve_hud_slot_icons(self)
	if st.nextaction_ui then
		st.nextaction_ui.init(self)
	end

	-- Cooldown HUD: builds its own UIParent frames (out of combat, deferred and
	-- retried via the per-frame hook under lockdown) from this class's HUD_SLOTS
	-- and the provider below; guarded so a flavor without hud.lua stays inert
	-- (the paladin wires it the same way in classes/paladin.lua).
	-- Runs before the practice init below: the shared post_init order is guide,
	-- HUD, practice in all six class modules (deep-audit F9).
	if st.hud then
		st.hud.init(self)
	end

	-- Twist Practice: builds the shared session panel/frames and the pure-engine
	-- bridge; guarded so a flavor without the practice files stays inert (the
	-- paladin wires it the same way in classes/paladin.lua, the druid in
	-- classes/druid.lua). The session itself is class-agnostic - the options
	-- Practice toggle or /st practice starts it, the panel icons cast the
	-- simulated spells - and the practice seam below keeps that flow shaman-safe.
	if st.practice_ui and type(st.practice_ui.init) == "function" then
		-- The practice strip's action vocabulary is the RUNNING FAMILY's: the
		-- panel reads the guide's slot list live, and a family that does not
		-- carry a row must never show it (TESTING.md's utility-row rule). The
		-- guide frame above already built its icons from the class's full
		-- display vocabulary, so this narrows the strip, not the frame.
		ST.SHAMAN.apply_family_slots()
		-- The panel's COMMON abilities (a heal, a shield, food, a potion) widen
		-- the strip on EVERY family - the same call the other five class modules
		-- make from their own post_init. apply_family_slots widens the strip only
		-- for a family it carries a rotation row for: it returns BEFORE the
		-- widening when the family has no row, so without this call the Cata and
		-- the Mists clients (where the class publishes no rotation at all) would
		-- keep the guide vocabulary alone and never offer the five common
		-- abilities the class publishes as neutral there. The call is idempotent:
		-- a strip that already carries a common slot is left alone.
		ST.SHAMAN.apply_practice_panel_actions()
		st.practice_ui.init(self)
	end

	-- The mainhand visuals frame exists by now.
	self.SHAMAN.setup_weave_visuals(self)
end

--=========================================================================================
-- Visuals
--=========================================================================================
function ST.SHAMAN.setup_weave_visuals(self)
	-- Creates the weave widgets on the mainhand visuals frame and the offhand spark
	-- mirror (called from post_init; on_bar_update retries if the frame was not ready yet).
	local vf = self:get_visuals_frame("mainhand")
	if vf and not vf.weave_marker then
		-- Breakpoint marker: the resolved spell's icon, cropped like the reference.
		local marker = vf:CreateTexture(nil, "OVERLAY")
		marker:SetDrawLayer("OVERLAY", -3)
		marker:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		marker:Hide()
		vf.weave_marker = marker

		-- Reference top/bottom breakpoint icons (SuperSwingTimer_ClassMods.lua:3491-3506):
		-- the same icon above the bar and below the bar stack.
		local marker_top = vf:CreateTexture(nil, "OVERLAY")
		marker_top:SetDrawLayer("OVERLAY", -3)
		marker_top:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		marker_top:Hide()
		vf.weave_marker_top = marker_top

		local marker_bottom = vf:CreateTexture(nil, "OVERLAY")
		marker_bottom:SetDrawLayer("OVERLAY", -3)
		marker_bottom:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		marker_bottom:Hide()
		vf.weave_marker_bottom = marker_bottom

		-- Cast spark: white base texture, tinted per frame.
		local spark = vf:CreateTexture(nil, "OVERLAY")
		spark:SetDrawLayer("OVERLAY", -2)
		spark:SetColorTexture(1, 1, 1, 1)
		spark:Hide()
		vf.weave_spark = spark

		-- Windfury ICD strip: dark backing plus a fill that shrinks as the internal
		-- cooldown elapses, left-anchored at the bar's right edge (reference wfIcdBar,
		-- SuperSwingTimer_ClassMods.lua:3809-3821).
		local windfury_bg = vf:CreateTexture(nil, "OVERLAY")
		windfury_bg:SetDrawLayer("OVERLAY", -1)
		windfury_bg:SetColorTexture(WEAVE_WINDFURY_BG_COLOR[1], WEAVE_WINDFURY_BG_COLOR[2],
			WEAVE_WINDFURY_BG_COLOR[3], WEAVE_WINDFURY_BG_COLOR[4])
		windfury_bg:SetPoint("LEFT", vf, "RIGHT", 0, 0)
		windfury_bg:Hide()
		vf.weave_windfury_bg = windfury_bg

		local windfury_fill = vf:CreateTexture(nil, "OVERLAY")
		windfury_fill:SetDrawLayer("OVERLAY", -1)
		windfury_fill:SetColorTexture(1, 1, 1, 1)
		windfury_fill:SetPoint("LEFT", vf, "RIGHT", 0, 0)
		windfury_fill:Hide()
		vf.weave_windfury_fill = windfury_fill

		-- Flame Shock target bar: orange fill over a dark backing, a 1 px glow outline
		-- shown in the final seconds and a seconds label placed above the bar (reference
		-- SuperSwingTimer_ClassMods.lua:3885-3963). All static setup happens once here;
		-- the per-frame path only resizes the fill and flips label/glow visibility.
		local fs_bg = vf:CreateTexture(nil, "OVERLAY")
		fs_bg:SetDrawLayer("OVERLAY", -2)
		fs_bg:SetColorTexture(ST.SHAMAN.flame_shock_style.bg_color[1], ST.SHAMAN.flame_shock_style.bg_color[2],
			ST.SHAMAN.flame_shock_style.bg_color[3], ST.SHAMAN.flame_shock_style.bg_color[4])
		fs_bg:SetHeight(ST.SHAMAN.flame_shock_style.bar_height)
		fs_bg:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", 0, 2)
		fs_bg:SetPoint("BOTTOMRIGHT", vf, "TOPRIGHT", 0, 2)
		fs_bg:Hide()
		vf.weave_fs_bg = fs_bg

		local fs_fill = vf:CreateTexture(nil, "OVERLAY")
		fs_fill:SetDrawLayer("OVERLAY", -2)
		fs_fill:SetColorTexture(ST.SHAMAN.flame_shock_style.color[1], ST.SHAMAN.flame_shock_style.color[2],
			ST.SHAMAN.flame_shock_style.color[3], ST.SHAMAN.flame_shock_style.color[4])
		fs_fill:SetHeight(ST.SHAMAN.flame_shock_style.bar_height)
		fs_fill:SetPoint("LEFT", fs_bg, "LEFT", 0, 0)
		fs_fill:Hide()
		vf.weave_fs_fill = fs_fill

		local fs_glow = vf:CreateTexture(nil, "OVERLAY")
		fs_glow:SetDrawLayer("OVERLAY", -1)
		fs_glow:SetColorTexture(ST.SHAMAN.flame_shock_style.glow_color[1], ST.SHAMAN.flame_shock_style.glow_color[2],
			ST.SHAMAN.flame_shock_style.glow_color[3], ST.SHAMAN.flame_shock_style.glow_color[4])
		fs_glow:SetPoint("BOTTOMLEFT", fs_bg, "BOTTOMLEFT", -1, -1)
		fs_glow:SetPoint("TOPRIGHT", fs_bg, "TOPRIGHT", 1, 1)
		fs_glow:Hide()
		vf.weave_fs_glow = fs_glow

		local fs_label = vf:CreateFontString(nil, "OVERLAY")
		fs_label:SetPoint("CENTER", fs_bg, "CENTER", 0, 0)
		fs_label:SetJustifyH("CENTER")
		fs_label:SetFont(get_tracker_font_path(self), 8, "OUTLINE")
		fs_label:SetTextColor(ST.SHAMAN.flame_shock_style.label_color[1], ST.SHAMAN.flame_shock_style.label_color[2],
			ST.SHAMAN.flame_shock_style.label_color[3], ST.SHAMAN.flame_shock_style.label_color[4])
		fs_label:Hide()
		vf.weave_fs_label = fs_label

		-- Cooldown badges, stacked beside the bar's right edge (reference
		-- SuperSwingTimer_ClassMods.lua:3700-3748).
		local ss_text = vf:CreateFontString(nil, "OVERLAY")
		ss_text:SetPoint("TOPLEFT", vf, "TOPRIGHT", 3, 2)
		ss_text:SetJustifyH("LEFT")
		ss_text:SetFont(get_tracker_font_path(self), 9, "OUTLINE")
		ss_text:SetTextColor(WEAVE_SS_BADGE_COLOR[1], WEAVE_SS_BADGE_COLOR[2],
			WEAVE_SS_BADGE_COLOR[3], WEAVE_SS_BADGE_COLOR[4])
		ss_text:Hide()
		vf.weave_ss_text = ss_text

		local sr_text = vf:CreateFontString(nil, "OVERLAY")
		sr_text:SetPoint("TOPLEFT", vf, "TOPRIGHT", 3, -8)
		sr_text:SetJustifyH("LEFT")
		sr_text:SetFont(get_tracker_font_path(self), 9, "OUTLINE")
		sr_text:SetTextColor(WEAVE_SR_BADGE_COLOR[1], WEAVE_SR_BADGE_COLOR[2],
			WEAVE_SR_BADGE_COLOR[3], WEAVE_SR_BADGE_COLOR[4])
		sr_text:Hide()
		vf.weave_sr_text = sr_text

		-- Shield charge row: one rect per possible charge slot, right-anchored beside
		-- the bar and growing leftward, empty slots dimmed (reference
		-- SuperSwingTimer_ClassMods.lua:3632-3660, 4171-4206). Colors are applied per
		-- frame via SetVertexColor so a shield swap never re-allocates a texture.
		local rects = {}
		for i = 1, ST.SHAMAN.shield_style.max_slots do
			local rect = vf:CreateTexture(nil, "OVERLAY")
			rect:SetDrawLayer("OVERLAY", -1)
			rect:SetWidth(ST.SHAMAN.shield_style.rect_width)
			rect:SetColorTexture(1, 1, 1, 1)
			rect:Hide()
			rects[i] = rect
		end
		vf.weave_shield_rects = rects
	end

	-- Offhand spark mirror: same lookup as the mainhand spark, drawn on the offhand
	-- visuals frame while the player dual-wields (reference 3481-3489).
	local oh_vf = self:get_visuals_frame("offhand")
	if oh_vf and not oh_vf.weave_spark_offhand then
		local oh_spark = oh_vf:CreateTexture(nil, "OVERLAY")
		oh_spark:SetDrawLayer("OVERLAY", -2)
		oh_spark:SetColorTexture(1, 1, 1, 1)
		oh_spark:Hide()
		oh_vf.weave_spark_offhand = oh_spark
	end
end

-- The family the assist should draw right now: at five Maelstrom Weapon stacks the
-- chosen spender (S4 - Lava Burst only when the rune/talent is present and the
-- FS-collision guard allows; see st.weave.get_mw5_spender / should_hold_mw5),
-- otherwise the cast in progress, else the last resolved cast, else the first enabled
-- family with a resolved spell. Returns the catalog entry and its family ("LvB" for
-- the Lava Burst spender), or nil when nothing is drawable.
function ST.SHAMAN.get_weave_visual_spell(self)
	local db = self:get_class_table()
	local families = db.weave_families
	-- MW5 spender choice (S4). A held-back guard (FS inside its final 2 s with a
	-- ready shock) or a disabled LB family falls through to the catalogue read
	-- below, so the pre-S4 behaviour is the fallback everywhere.
	if (not families or families.LB ~= false)
		and is_weave_mw_active(db, self.weave_mw_observed)
		and type(self.weave_mw_stacks) == "number"
		and self.weave_mw_stacks >= st.weave.MW_MAX_STACKS then
		local lava = self.SHAMAN.resolve_lava_burst(self)
		if lava and st.weave.get_mw5_spender(api.is_spell_known(spell_query(lava.spell_id, lava.name))) == "lavaburst" then
			local fs_remaining
			if self.weave_fs_duration or self.weave_fs_expires then
				fs_remaining = st.weave.get_flame_shock_remaining(
					self.weave_fs_duration, self.weave_fs_expires, api.get_time())
			end
			if not st.weave.should_hold_mw5(fs_remaining, self.SHAMAN.is_shock_ready()) then
				return lava, "LvB"
			end
		end
	end
	local last = self.weave_family
	if last and self.weave_catalog[last] and (not families or families[last] ~= false) then
		return self.weave_catalog[last], last
	end
	for i = 1, #st.weave.FAMILIES do
		local family = st.weave.FAMILIES[i]
		if not families or families[family] ~= false then
			local entry = self.weave_catalog[family]
			if entry then
				return entry, family
			end
		end
	end
	return nil, nil
end

--=========================================================================================
-- Tracker visuals
--=========================================================================================
-- The tracked cast's display state on the MAINHAND swing axis, shared by the mainhand
-- spark and its offhand mirror: the spark fraction (nil while no cast window is running),
-- whether the cast clips the swing, and the marker fraction (reference
-- SuperSwingTimer_ClassMods.lua:454-464, 3458-3464). While no cast is live the clip
-- estimate assumes a fresh cast, which is also what dims the marker.
local function get_weave_spark_display(self, d, entry, now, latency)
	local duration = d.speed
	local effective = self.SHAMAN.get_weave_effective_cast_time(self, entry)
	local marker_fraction = st.weave.get_marker_fraction(duration, effective, latency)
	local cast_start_fraction = self.weave_cast_start_swing_fraction
	local cast_remaining = effective
	local cast_total = self.weave_cast_duration
	local cast_live = self.weave_is_casting and self.weave_cast_start_time
		and self.weave_cast_duration and self.weave_cast_duration > 0
	if cast_live then
		if type(self.weave_cast_end_time) == "number" then
			cast_remaining = math.max(0, self.weave_cast_end_time - now)
		else
			cast_remaining = math.max(0, self.weave_cast_duration - (now - self.weave_cast_start_time))
		end
		if type(self.weave_cast_end_time) == "number"
			and self.weave_cast_end_time > self.weave_cast_start_time then
			cast_total = self.weave_cast_end_time - self.weave_cast_start_time
		end
	end
	local clip_amount = st.weave.get_clip_amount(now, latency, cast_remaining, d.ends_at)
	local clipped = st.weave.is_clipped(clip_amount, cast_start_fraction, marker_fraction)
	local spark_fraction
	if cast_live and cast_total > 0 then
		local progress = st.weave.clamp_fraction((now - self.weave_cast_start_time) / cast_total)
		if cast_start_fraction ~= nil and duration > 0 then
			-- Travel from where the cast started toward where it is projected to land.
			-- The landing is projected against the swing the CAST started in
			-- (weave_cast_swing_start), not the swing that is current now: the cast's
			-- impact time is fixed, so re-anchoring the projection on every rollover
			-- rewound the destination by a full swing and made the spark re-travel.
			local projected = st.weave.get_projected_impact_fraction(now, cast_remaining, latency,
				self.weave_cast_swing_start or d.start, duration)
			spark_fraction = st.weave.get_spark_fraction(cast_start_fraction, projected, progress)
		else
			spark_fraction = progress
		end
	end
	return spark_fraction, clipped, marker_fraction
end

-- Hide the marker trio (main icon plus the reference top/bottom pair).
local function hide_weave_markers(vf)
	if vf.weave_marker then vf.weave_marker:Hide() end
	if vf.weave_marker_top then vf.weave_marker_top:Hide() end
	if vf.weave_marker_bottom then vf.weave_marker_bottom:Hide() end
end

-- The frame the reference drops the bottom breakpoint icon under: the offhand bar's
-- visuals frame while the player dual-wields with that bar visible, else the mainhand
-- frame (SuperSwingTimer_ClassMods.lua:3499-3502).
local function get_weave_bottom_anchor(self, mainhand_vf, mainhand_width)
	local oh = self.offhand
	local oh_bar = oh and oh.anchor_frame and oh.anchor_frame.bar_frame
	if oh and oh.has_weapon and oh_bar and oh_bar.IsShown and oh_bar:IsShown() then
		local oh_vf = self:get_visuals_frame("offhand")
		local oh_width = self:get_bar_visuals_width_and_height("offhand")
		if oh_vf and type(oh_width) == "number" then
			return oh_vf, oh_width
		end
	end
	return mainhand_vf, mainhand_width
end

-- The Windfury ICD window for this client (Era/SoD 1.5 s, everywhere else 3 s -
-- audit 2026-10-19 §5): every strip/badge/wash/hold read shares it, so the visuals
-- and the guide rule can never disagree about when the ICD clears.
local function windfury_window()
	return st.weave.get_windfury_icd_seconds(st.family)
end

-- Windfury ICD strip: a thin strip at the bar's right edge whose fill shrinks as the 3 s
-- internal cooldown elapses, tinted by bucket (reference
-- SuperSwingTimer_ClassMods.lua:3802-3848). Only drawn while Windfury Weapon is up.
local function update_windfury_icd(self, vf, d, db, now, h)
	local bg, fill = vf.weave_windfury_bg, vf.weave_windfury_fill
	if not (bg and fill) then return end
	if type(h) ~= "number" or h <= 0
		or db.show_shaman_windfury_icd == false
		or not self.weave_windfury_active
		or not (d and type(d.start) == "number" and d.start > 0) then
		bg:Hide()
		fill:Hide()
		return
	end
	local remaining = st.weave.get_windfury_icd_remaining(d.start, now, windfury_window())
	if not remaining then
		bg:Hide()
		fill:Hide()
		return
	end
	local fraction = st.weave.clamp_fraction(remaining / windfury_window())
	bg:SetWidth(WEAVE_WINDFURY_STRIP_WIDTH)
	bg:SetHeight(h)
	fill:SetWidth(WEAVE_WINDFURY_STRIP_WIDTH * fraction)
	fill:SetHeight(h)
	local bucket = st.weave.get_windfury_tint_bucket(remaining)
	if self.weave_windfury_bucket ~= bucket then
		self.weave_windfury_bucket = bucket
		local color = WEAVE_WINDFURY_COLORS[bucket]
		fill:SetVertexColor(color[1], color[2], color[3], color[4])
	end
	bg:Show()
	fill:Show()
end

-- Scan the TARGET's harmful auras for the tracked debuffs: Flame Shock (always) and
-- the Stormstrike nature-vulnerability debuff (only while its bar is enabled). Id
-- table + name fallback, caster must be the player (reference
-- SuperSwingTimer_ClassMods.lua:3966-3989; the Stormstrike leg mirrors the
-- reference's caster == "player" rule with the port's nil-source allowance).
-- Returns the Flame Shock duration/expiration then the Stormstrike
-- duration/expiration; the walk stops once everything it was asked for is found.
local function scan_target_debuffs(want_stormstrike)
	local fs_found, fs_duration, fs_expiration = false, nil, nil
	local ss_found, ss_duration, ss_expiration = false, nil, nil
	local i = 1
	while i <= 40 do
		local name, _, _, _, duration, expiration, source, _, _, spell_id = api.UnitAura("target", i, "HARMFUL")
		-- No early break (R2): nil is simply no match at this index.
		if name ~= nil then
			local mine = source == "player" or source == nil
			if mine and not fs_found
				and ((spell_id and WEAVE_FLAME_SHOCK_IDS[spell_id]) or name == WEAVE_FLAME_SHOCK_NAME) then
				fs_found = true
				fs_duration, fs_expiration = duration, expiration
			end
			if want_stormstrike and mine and not ss_found
				and ((spell_id and WEAVE_STORMSTRIKE_DEBUFF_IDS[spell_id]) or name == WEAVE_STORMSTRIKE_DEBUFF_NAME) then
				ss_found = true
				ss_duration, ss_expiration = duration, expiration
			end
			if fs_found and (not want_stormstrike or ss_found) then
				break
			end
		end
		i = i + 1
	end
	return fs_duration, fs_expiration, ss_duration, ss_expiration
end

-- Lust status for the S1 effect-status row (competitor_gaps S1, Shaman leg):
-- Bloodlust / Heroism (2825 / 32182, the verify_bank CONFIRMED pair) plus the
-- Forever-only Rage of the Farseer name leg (UNCONFIRMED, same shape as the haste
-- walk above - the name IS the probe there). Throttled player-aura scan through
-- compat's frozen scan_player_aura, closed-on-unknown: only an explicit
-- st.lust_supported == true arms it (Era/UNKNOWN stay off, nil stays off - the
-- R4 rule), and a miss under a secret-aura regime latches unknown (the paladin
-- M5 / rogue M5 shape: api.auras_may_be_secret answers true) instead of an
-- honest "no lust". Provider-side state for the lust badge below; the frozen
-- guide engine is untouched (no engine input carries lust).
function ST.SHAMAN.update_lust_state(self, now)
	if type(now) ~= "number" then
		self.shaman_lust_at = nil
		self.shaman_lust_remaining = nil
		self.shaman_lust_unstamped = nil
		self.shaman_lust_unknown = true
		return nil
	end
	if type(self.shaman_lust_at) == "number"
		and now - self.shaman_lust_at < WEAVE_LUST_RESCAN_INTERVAL then
		return self.shaman_lust_remaining
	end
	self.shaman_lust_at = now
	self.shaman_lust_remaining = nil
	self.shaman_lust_unstamped = nil
	if st.lust_supported == true then
		local seen = false
		local remaining = api.scan_player_aura(function(spell_id, name)
			local hit = (spell_id and WEAVE_BLOODLUST_IDS[spell_id])
				or name == "Bloodlust" or name == "Heroism"
				or name == WEAVE_FARSEER_NAME
			if hit then
				seen = true
			end
			return hit
		end)
		if type(remaining) == "number" and remaining > 0 then
			self.shaman_lust_remaining = remaining
		elseif seen then
			-- Present but unstamped (no readable expiry): the buff is up but
			-- cannot be counted down - the badge renders the bare text, never
			-- a guessed length (the rockbiter bare-"RB" rule).
			self.shaman_lust_unstamped = true
		end
	end
	local probe = api.auras_may_be_secret
	self.shaman_lust_unknown = st.lust_supported == true
		and self.shaman_lust_remaining == nil
		and self.shaman_lust_unstamped == nil
		and type(probe) == "function" and probe() == true
	return self.shaman_lust_remaining
end

-- Throttled target-debuff scan shared by the Flame Shock bar, the Stormstrike bar
-- and the guide's frozen Flame Shock input (scan cadence: the reference's 0.05 s,
-- SuperSwingTimer_ClassMods.lua:3991-3996). Only the debuffs someone will read are
-- scanned; a tick nobody needs performs no aura work at all.
local function refresh_target_debuffs(self, db, now)
	local want_fs = db.show_shaman_flame_shock_bar ~= false or db.nextaction_enabled == true
	local want_ss = db.show_shaman_stormstrike_bar == true
	if not (want_fs or want_ss) then
		return
	end
	if now < (self.weave_fs_scan_at or 0) then
		return
	end
	self.weave_fs_scan_at = now + WEAVE_FLAME_SHOCK_SCAN_INTERVAL
	local fs_duration, fs_expiration, ss_duration, ss_expiration = scan_target_debuffs(want_ss)
	if want_fs then
		self.weave_fs_duration = fs_duration
		self.weave_fs_expires = fs_expiration
	end
	if want_ss then
		self.weave_storm_duration = ss_duration
		self.weave_storm_expires = ss_expiration
	end
end

-- Flame Shock target bar: duration fill, seconds label and a glow outline in the final
-- seconds. The throttled target scan runs in refresh_target_debuffs (shared with the
-- Stormstrike bar and the guide); between scans the bar just counts down.
local function update_flame_shock_bar(self, vf, db, now, w)
	local glow, bg, fill, label = vf.weave_fs_glow, vf.weave_fs_bg, vf.weave_fs_fill, vf.weave_fs_label
	if not (glow and bg and fill and label) then return end
	local show_bar = db.show_shaman_flame_shock_bar ~= false
	if not show_bar and db.nextaction_enabled ~= true then
		self.weave_fs_glow_on = false
		glow:Hide()
		bg:Hide()
		fill:Hide()
		label:Hide()
		return
	end
	local duration, expires = self.weave_fs_duration, self.weave_fs_expires
	if not show_bar or (not duration and not expires) then
		self.weave_fs_glow_on = false
		glow:Hide()
		bg:Hide()
		fill:Hide()
		label:Hide()
		return
	end
	local remaining, total = st.weave.get_flame_shock_remaining(duration, expires, now)
	if type(w) == "number" and w > 0 then
		fill:SetWidth(w * st.weave.clamp_fraction(remaining / total))
	end
	local seconds = math.floor(remaining + 0.5)
	if self.weave_fs_label_seconds ~= seconds then
		self.weave_fs_label_seconds = seconds
		label:SetText(tostring(seconds))
	end
	local glow_on = st.weave.should_flame_shock_glow(remaining)
	if glow_on ~= self.weave_fs_glow_on then
		self.weave_fs_glow_on = glow_on
		if glow_on then glow:Show() else glow:Hide() end
	end
	bg:Show()
	fill:Show()
	label:Show()
end

-- Stormstrike nature-vulnerability target bar (S2): an FS-bar clone stacked above
-- the Flame Shock bar - duration fill, seconds label and a final-seconds glow -
-- fed by the same throttled target scan (refresh_target_debuffs). The widgets are
-- created lazily on the first tick with the option ON, so a default session (nil =
-- off) creates nothing and the construction-time widget counts stay untouched.
local function update_stormstrike_bar(self, vf, db, now, w)
	local show_bar = db.show_shaman_stormstrike_bar == true
	if not show_bar then
		if vf.weave_storm_bg then
			self.weave_storm_glow_on = false
			vf.weave_storm_glow:Hide()
			vf.weave_storm_bg:Hide()
			vf.weave_storm_fill:Hide()
			vf.weave_storm_label:Hide()
		end
		return
	end
	local bg = vf.weave_storm_bg
	if not bg then
		local fs_bg = vf.weave_fs_bg
		bg = vf:CreateTexture(nil, "OVERLAY")
		bg:SetDrawLayer("OVERLAY", -2)
		bg:SetColorTexture(ST.SHAMAN.stormstrike_style.bg_color[1], ST.SHAMAN.stormstrike_style.bg_color[2],
			ST.SHAMAN.stormstrike_style.bg_color[3], ST.SHAMAN.stormstrike_style.bg_color[4])
		bg:SetHeight(ST.SHAMAN.stormstrike_style.bar_height)
		if fs_bg then
			bg:SetPoint("BOTTOMLEFT", fs_bg, "TOPLEFT", 0, 2)
			bg:SetPoint("BOTTOMRIGHT", fs_bg, "TOPRIGHT", 0, 2)
		else
			bg:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", 0, 2)
			bg:SetPoint("BOTTOMRIGHT", vf, "TOPRIGHT", 0, 2)
		end
		bg:Hide()
		vf.weave_storm_bg = bg

		local fill = vf:CreateTexture(nil, "OVERLAY")
		fill:SetDrawLayer("OVERLAY", -2)
		fill:SetColorTexture(ST.SHAMAN.stormstrike_style.color[1], ST.SHAMAN.stormstrike_style.color[2],
			ST.SHAMAN.stormstrike_style.color[3], ST.SHAMAN.stormstrike_style.color[4])
		fill:SetHeight(ST.SHAMAN.stormstrike_style.bar_height)
		fill:SetPoint("LEFT", bg, "LEFT", 0, 0)
		fill:Hide()
		vf.weave_storm_fill = fill

		local glow = vf:CreateTexture(nil, "OVERLAY")
		glow:SetDrawLayer("OVERLAY", -1)
		glow:SetColorTexture(ST.SHAMAN.stormstrike_style.glow_color[1], ST.SHAMAN.stormstrike_style.glow_color[2],
			ST.SHAMAN.stormstrike_style.glow_color[3], ST.SHAMAN.stormstrike_style.glow_color[4])
		glow:SetPoint("BOTTOMLEFT", bg, "BOTTOMLEFT", -1, -1)
		glow:SetPoint("TOPRIGHT", bg, "TOPRIGHT", 1, 1)
		glow:Hide()
		vf.weave_storm_glow = glow

		local label = vf:CreateFontString(nil, "OVERLAY")
		label:SetPoint("CENTER", bg, "CENTER", 0, 0)
		label:SetJustifyH("CENTER")
		label:SetFont(get_tracker_font_path(self), 8, "OUTLINE")
		label:SetTextColor(ST.SHAMAN.stormstrike_style.label_color[1], ST.SHAMAN.stormstrike_style.label_color[2],
			ST.SHAMAN.stormstrike_style.label_color[3], ST.SHAMAN.stormstrike_style.label_color[4])
		label:Hide()
		vf.weave_storm_label = label
	end
	local duration, expires = self.weave_storm_duration, self.weave_storm_expires
	if not duration and not expires then
		self.weave_storm_glow_on = false
		vf.weave_storm_glow:Hide()
		bg:Hide()
		vf.weave_storm_fill:Hide()
		vf.weave_storm_label:Hide()
		return
	end
	local remaining, total = st.weave.get_stormstrike_remaining(duration, expires, now)
	if type(w) == "number" and w > 0 then
		vf.weave_storm_fill:SetWidth(w * st.weave.clamp_fraction(remaining / total))
	end
	local seconds = math.floor(remaining + 0.5)
	if self.weave_storm_label_seconds ~= seconds then
		self.weave_storm_label_seconds = seconds
		vf.weave_storm_label:SetText(tostring(seconds))
	end
	local glow_on = st.weave.should_stormstrike_glow(remaining)
	if glow_on ~= self.weave_storm_glow_on then
		self.weave_storm_glow_on = glow_on
		if glow_on then vf.weave_storm_glow:Show() else vf.weave_storm_glow:Hide() end
	end
	bg:Show()
	vf.weave_storm_fill:Show()
	vf.weave_storm_label:Show()
end

-- Stormstrike / Shamanistic Rage badges, stacked beside the bar's right edge. SS shows
-- the cooldown; SR prefers the aura's remaining time and falls back to its cooldown
-- (reference SuperSwingTimer_ClassMods.lua:3695-3748). Text is only re-set when the
-- whole-second readout changes, so the per-frame path allocates nothing. S3: while the
-- WF-fishing hold is armed (option-gated) the SS badge flips to an amber "SS HOLD"
-- instead of the cooldown text.
local function update_cooldown_badges(self, vf, db, now, d)
	local ss_text, sr_text = vf.weave_ss_text, vf.weave_sr_text
	if not (ss_text and sr_text) then return end
	if db.show_shaman_cooldown_badges == false then
		ss_text:Hide()
		sr_text:Hide()
		return
	end

	local start_time, duration = api.GetSpellCooldown(spell_query(WEAVE_STORMSTRIKE_SPELL_ID, WEAVE_STORMSTRIKE_NAME))
	local ss_remaining = st.weave.get_cooldown_remaining(start_time, duration, now)
	-- WF-fishing hold (S3): Stormstrike ready + the Windfury ICD clearing inside this
	-- swing -> hold it (delay-if-fishing-WF). Gated on the swing's own activity (no
	-- family/mainline gate); the pure predicate lives in weave.lua.
	local ss_hold = false
	if db.show_shaman_wf_hold_tint == true and not ss_remaining
		and self.weave_windfury_active and d
		and type(d.start) == "number" and type(d.ends_at) == "number" then
		ss_hold = st.weave.should_hold_stormstrike(
			st.weave.get_windfury_icd_remaining(d.start, now, windfury_window()), d.ends_at - now)
	end
	if ss_hold then
		if self.weave_ss_badge_mode ~= "hold" then
			self.weave_ss_badge_mode = "hold"
			ss_text:SetText("SS HOLD")
			ss_text:SetTextColor(WEAVE_SS_HOLD_COLOR[1], WEAVE_SS_HOLD_COLOR[2],
				WEAVE_SS_HOLD_COLOR[3], WEAVE_SS_HOLD_COLOR[4])
		end
		ss_text:Show()
	elseif ss_remaining then
		if self.weave_ss_badge_mode ~= "cooldown" then
			self.weave_ss_badge_mode = "cooldown"
			-- Force the text refresh too: the cached whole-second readout can
			-- survive a hold period, and the badge must never keep "SS HOLD".
			self.weave_ss_seconds = nil
			ss_text:SetTextColor(WEAVE_SS_BADGE_COLOR[1], WEAVE_SS_BADGE_COLOR[2],
				WEAVE_SS_BADGE_COLOR[3], WEAVE_SS_BADGE_COLOR[4])
		end
		local seconds = math.floor(ss_remaining + 0.5)
		if self.weave_ss_seconds ~= seconds then
			self.weave_ss_seconds = seconds
			ss_text:SetText(string.format("SS %.0fs", ss_remaining))
		end
		ss_text:Show()
	else
		self.weave_ss_badge_mode = nil
		ss_text:Hide()
	end

	local sr_remaining
	if type(self.weave_sr_expires) == "number" then
		local aura_remaining = self.weave_sr_expires - now
		if aura_remaining > 0 then
			sr_remaining = aura_remaining
		end
	end
	if not sr_remaining then
		local sr_start, sr_duration = api.GetSpellCooldown(spell_query(WEAVE_SR_SPELL_ID, WEAVE_SR_NAME))
		sr_remaining = st.weave.get_cooldown_remaining(sr_start, sr_duration, now)
	end
	if sr_remaining then
		local seconds = math.floor(sr_remaining + 0.5)
		if self.weave_sr_seconds ~= seconds then
			self.weave_sr_seconds = seconds
			sr_text:SetText(string.format("SR %.0fs", sr_remaining))
		end
		sr_text:Show()
	else
		sr_text:Hide()
	end
end

-- WF-fishing hold wash (S3): while the hold is armed, an amber translucent overlay
-- covers the swing's final fraction - from the point the Windfury ICD clears to the
-- swing's end (the window where the held Stormstrike is safe to press). The widget
-- is created lazily on the first armed tick with the option ON, so a default
-- session (nil = off) creates nothing; the wash is drawn on the mainhand visuals
-- frame under the marker/spark layers.
local function update_wf_hold_wash(self, vf, db, now, d, w, h)
	local wash = vf.weave_wf_wash
	local armed = false
	local wash_fraction
	-- The hold only exists while Stormstrike is ready to be held (the engine's rule
	-- 8 sits behind its off-cooldown check); the cooldown read runs only with the
	-- option on, so the default path stays read-free.
	if db.show_shaman_wf_hold_tint == true then
		local ss_start, ss_duration = api.GetSpellCooldown(spell_query(WEAVE_STORMSTRIKE_SPELL_ID, WEAVE_STORMSTRIKE_NAME))
		local ss_remaining = st.weave.get_cooldown_remaining(ss_start, ss_duration, now)
		if not ss_remaining and self.weave_windfury_active and d
			and type(d.start) == "number" and type(d.ends_at) == "number"
			and type(d.speed) == "number" and d.speed > 0 then
			local icd_remaining = st.weave.get_windfury_icd_remaining(d.start, now, windfury_window())
			if st.weave.should_hold_stormstrike(icd_remaining, d.ends_at - now) then
				armed = true
				wash_fraction = st.weave.get_wf_hold_wash_fraction(now - d.start, d.speed, icd_remaining)
			end
		end
	end
	if not wash then
		if not armed then return end
		wash = vf:CreateTexture(nil, "OVERLAY")
		wash:SetDrawLayer("OVERLAY", -4)
		wash:SetColorTexture(WEAVE_WF_HOLD_WASH_COLOR[1], WEAVE_WF_HOLD_WASH_COLOR[2],
			WEAVE_WF_HOLD_WASH_COLOR[3], WEAVE_WF_HOLD_WASH_COLOR[4])
		wash:Hide()
		vf.weave_wf_wash = wash
	end
	if not armed or wash_fraction == nil or type(w) ~= "number" or w <= 0
		or type(h) ~= "number" or h <= 0 then
		wash:Hide()
		return
	end
	local start = st.weave.clamp_fraction(wash_fraction)
	wash:SetHeight(h)
	wash:ClearAllPoints()
	wash:SetPoint("BOTTOMLEFT", vf, "BOTTOMLEFT", start * w, 0)
	wash:SetWidth((1 - start) * w)
	wash:Show()
end

-- Rockbiter Weapon badge (discover #6): an "RB" readout with the imbue's remaining
-- time while the buff is up, hidden otherwise. Option-gated (nil = off) and created
-- lazily; a buff without a readable expiry still shows the bare "RB". Reads stay
-- guarded (the aura scan owns id/name matching; this only renders its result).
local function update_rockbiter_badge(self, vf, db, now)
	local text = vf.weave_rb_text
	if db.show_shaman_rockbiter_badge ~= true then
		if text then text:Hide() end
		return
	end
	if not text then
		text = vf:CreateFontString(nil, "OVERLAY")
		text:SetPoint("TOPLEFT", vf, "TOPRIGHT", 3, -18)
		text:SetJustifyH("LEFT")
		text:SetFont(get_tracker_font_path(self), 9, "OUTLINE")
		text:SetTextColor(WEAVE_RB_BADGE_COLOR[1], WEAVE_RB_BADGE_COLOR[2],
			WEAVE_RB_BADGE_COLOR[3], WEAVE_RB_BADGE_COLOR[4])
		text:Hide()
		vf.weave_rb_text = text
	end
	if not self.weave_rockbiter_active then
		self.weave_rb_seconds = nil
		text:Hide()
		return
	end
	local expires = self.weave_rockbiter_expires
	if type(expires) ~= "number" then
		if self.weave_rb_seconds ~= -1 then
			self.weave_rb_seconds = -1
			text:SetText("RB")
		end
		text:Show()
		return
	end
	local remaining = expires - now
	if remaining < 0 then remaining = 0 end
	local seconds = math.floor(remaining + 0.5)
	if self.weave_rb_seconds ~= seconds then
		self.weave_rb_seconds = seconds
		text:SetText(string.format("RB %.0fs", remaining))
	end
	text:Show()
end

-- Lust status badge (S1 effect-status row, Shaman leg): a "BL %.0fs" countdown
-- beside the bar while Bloodlust / Heroism (or the Forever Farseer leg) is up,
-- "BL ?" while the aura list may be restricted and the read is inconclusive,
-- the bare "BL" while the buff is present but unstamped (the rockbiter
-- bare-"RB" rule - never a guessed length), hidden otherwise. Option-gated
-- (nil = off) and created lazily like the rockbiter badge, so a default
-- session creates nothing and the construction-time widget counts stay
-- untouched. The trinket half of S1 stays on the HUD's own trinket row
-- (hud.lua TRINKET_DATA; every `icd` there is UNCONFIRMED until an in-client
-- combat-log read confirms it) - this badge covers the haste-effect side only.
local function update_lust_badge(self, vf, db, now)
	local text = vf.weave_lust_text
	if db.show_shaman_lust_status ~= true then
		if text then text:Hide() end
		return
	end
	if not text then
		text = vf:CreateFontString(nil, "OVERLAY")
		text:SetPoint("TOPLEFT", vf, "TOPRIGHT", 3, -28)
		text:SetJustifyH("LEFT")
		text:SetFont(get_tracker_font_path(self), 9, "OUTLINE")
		text:SetTextColor(WEAVE_LUST_BADGE_COLOR[1], WEAVE_LUST_BADGE_COLOR[2],
			WEAVE_LUST_BADGE_COLOR[3], WEAVE_LUST_BADGE_COLOR[4])
		text:Hide()
		vf.weave_lust_text = text
	end
	ST.SHAMAN.update_lust_state(self, now)
	if type(self.shaman_lust_remaining) == "number" then
		local seconds = math.floor(self.shaman_lust_remaining + 0.5)
		if self.shaman_lust_seconds ~= seconds then
			self.shaman_lust_seconds = seconds
			text:SetText(string.format("BL %.0fs", self.shaman_lust_remaining))
		end
		text:Show()
		return
	end
	if self.shaman_lust_unknown == true then
		if self.shaman_lust_seconds ~= -1 then
			self.shaman_lust_seconds = -1
			text:SetText("BL ?")
		end
		text:Show()
		return
	end
	if self.shaman_lust_unstamped == true then
		if self.shaman_lust_seconds ~= -2 then
			self.shaman_lust_seconds = -2
			text:SetText("BL")
		end
		text:Show()
		return
	end
	self.shaman_lust_seconds = nil
	text:Hide()
end

-- Shield charge row: one rect per charge slot, filled slots in the shield color and the
-- empty ones dimmed, anchored left of the bar (reference
-- SuperSwingTimer_ClassMods.lua:4058-4209).
local function update_shield_charges(self, vf, db, h)
	local rects = vf.weave_shield_rects
	if not rects then return end
	local shield_type = self.weave_shield_type
	local slots, filled = st.weave.get_shield_tracker_state(shield_type, self.weave_shield_charges)
	if db.show_shaman_shield_charges == false or slots <= 0 or type(h) ~= "number" or h <= 0 then
		for i = 1, #rects do
			rects[i]:Hide()
		end
		self.weave_shield_layout_slots = nil
		return
	end
	if self.weave_shield_layout_slots ~= slots then
		-- (Re)anchor the row on a slot-count change: rightmost rect beside the bar, the
		-- rest growing leftward. Anchor changes are rare (Lightning <-> Water Shield),
		-- so the per-frame path never touches the anchors.
		local previous
		for i = 1, slots do
			local rect = rects[i]
			rect:ClearAllPoints()
			if previous then
				rect:SetPoint("TOPRIGHT", previous, "TOPLEFT", -ST.SHAMAN.shield_style.rect_gap, 0)
			else
				rect:SetPoint("TOPRIGHT", vf, "TOPLEFT", -ST.SHAMAN.shield_style.bar_gap, 0)
			end
			previous = rect
		end
		self.weave_shield_layout_slots = slots
	end
	local color = ST.SHAMAN.shield_style.colors[shield_type]
	for i = 1, slots do
		local rect = rects[i]
		rect:SetWidth(ST.SHAMAN.shield_style.rect_width)
		rect:SetHeight(h)
		if i <= filled then
			rect:SetVertexColor(color[1], color[2], color[3], color[4])
		else
			rect:SetVertexColor(color[1], color[2], color[3], ST.SHAMAN.shield_style.dim_alpha)
		end
		rect:Show()
	end
	for i = slots + 1, #rects do
		rects[i]:Hide()
	end
end

-- Spell-position row (round 2, operator spec): for each shown weave spell (LB, CL;
-- LvB when the rune/talent is present) the icon sits at the swing fraction where its
-- cast must START to land just before the MH swing - the "spells start cast range
-- zone". The zone band spans the min..max of those starts; icons, cast-time numbers
-- and the zone update every tick (stacks/haste/swing changes move them, so every
-- swing / LB / CL / weave event re-adjusts them). A spell whose safe start has
-- passed reads as a clip (red) - casting now would overrun the swing; fewer than
-- MW_MIN_WEAVE_STACKS stacks read as "wait" (dim). Option-gated (nil = off), all
-- widgets created lazily on the first live tick with the option on.
local weave_position_starts = {}
-- Per-slot caches for the per-tick path: the icon texture and the cast-time value
-- are re-set only when they change (no string/SetTexture churn on a stable swing).
local weave_position_icon_texture = {}
local weave_position_time_value = {}

-- Hide every spell-position widget (created lazily; absent widgets are skipped).
local function hide_spell_positions(vf)
	if vf.weave_pos_zone then vf.weave_pos_zone:Hide() end
	if vf.weave_pos_label then vf.weave_pos_label:Hide() end
	local icons, times = vf.weave_pos_icons, vf.weave_pos_times
	if icons then
		for _, icon in pairs(icons) do icon:Hide() end
	end
	if times then
		for _, time in pairs(times) do time:Hide() end
	end
end

-- One state color for a position slot: family color when ready, red for a clip,
-- dimmed grey while waiting for stacks.
local function get_position_color(state, family)
	if state == "clip" then
		return ST.SHAMAN.position_style.clip_color
	elseif state == "wait" then
		return ST.SHAMAN.position_style.wait_color
	end
	if family == WEAVE_POSITION_LAVA_KEY then
		return st.weave.LAVA_BURST_COLOR
	end
	return st.weave.FAMILY_COLORS[family]
end

local function update_spell_positions(self, vf, db, now, d, w)
	if not (db.show_shaman_spell_positions == true and db.weave_enabled ~= false
		and is_weave_mw_active(db, self.weave_mw_observed)
		and d and type(d.speed) == "number" and d.speed > 0
		and type(d.start) == "number" and type(d.ends_at) == "number" and not d.is_full) then
		hide_spell_positions(vf)
		return
	end
	if not vf.weave_pos_zone then
		local zone = vf:CreateTexture(nil, "OVERLAY")
		zone:SetDrawLayer("OVERLAY", -5)
		zone:SetColorTexture(WEAVE_ZONE_COLOR[1], WEAVE_ZONE_COLOR[2],
			WEAVE_ZONE_COLOR[3], WEAVE_ZONE_COLOR[4])
		zone:SetHeight(WEAVE_ZONE_HEIGHT)
		zone:Hide()
		vf.weave_pos_zone = zone
		local label = vf:CreateFontString(nil, "OVERLAY")
		label:SetJustifyH("CENTER")
		label:SetFont(get_tracker_font_path(self), 8, "OUTLINE")
		label:SetTextColor(WEAVE_ZONE_LABEL_COLOR[1], WEAVE_ZONE_LABEL_COLOR[2],
			WEAVE_ZONE_LABEL_COLOR[3], WEAVE_ZONE_LABEL_COLOR[4])
		label:SetText(WEAVE_ZONE_LABEL)
		label:Hide()
		vf.weave_pos_label = label
		local icons, times = {}, {}
		local keys = {}
		for i = 1, #WEAVE_POSITION_SLOTS do
			keys[i] = WEAVE_POSITION_SLOTS[i]
		end
		keys[#keys + 1] = WEAVE_POSITION_LAVA_KEY
		for i = 1, #keys do
			local icon = vf:CreateTexture(nil, "OVERLAY")
			icon:SetDrawLayer("OVERLAY", -3)
			icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
			icon:SetWidth(ST.SHAMAN.position_style.icon_size)
			icon:SetHeight(ST.SHAMAN.position_style.icon_size)
			icon:Hide()
			icons[keys[i]] = icon
			local time = vf:CreateFontString(nil, "OVERLAY")
			time:SetJustifyH("LEFT")
			time:SetFont(get_tracker_font_path(self), 8, "OUTLINE")
			time:SetPoint("LEFT", icon, "RIGHT", 1, 0)
			time:Hide()
			times[keys[i]] = time
		end
		vf.weave_pos_icons = icons
		vf.weave_pos_times = times
	end
	local icons, times = vf.weave_pos_icons, vf.weave_pos_times
	local duration = d.speed
	local latency = ((self.latency and self.latency.world_ms) or 0) / 1000
	local now_fraction = st.weave.clamp_fraction((now - d.start) / duration)
	local stacks = self.weave_mw_stacks
	if type(stacks) ~= "number" then
		stacks = 0
	end
	local families = db.weave_families
	local lava = self.SHAMAN.resolve_lava_burst(self)
	local starts = weave_position_starts
	local count = 0
	local center_y = WEAVE_ZONE_BOTTOM + (WEAVE_ZONE_HEIGHT / 2)
	for i = 1, #WEAVE_POSITION_SLOTS + 1 do
		local key = (i <= #WEAVE_POSITION_SLOTS) and WEAVE_POSITION_SLOTS[i]
			or WEAVE_POSITION_LAVA_KEY
		local icon, time = icons[key], times[key]
		local entry
		if key == WEAVE_POSITION_LAVA_KEY then
			if lava and st.weave.get_mw5_spender(api.is_spell_known(spell_query(lava.spell_id, lava.name))) == "lavaburst" then
				entry = lava
			end
		elseif not families or families[key] ~= false then
			entry = self.weave_catalog[key]
		end
		if entry and entry.icon then
			local effective = self.SHAMAN.get_weave_effective_cast_time(self, entry)
			local safe_start = effective ~= nil and st.weave.get_marker_fraction(duration, effective, latency) or nil
			-- H4: an unresolvable cast time (nil effective) leaves the safe start
			-- unknown; hide the slot instead of anchoring it at nil*width or printing
			-- a fake 0.0 s cast. get_spell_position_state would read "wait" regardless.
			if safe_start == nil then
				icon:Hide()
				time:Hide()
			else
				local state = st.weave.get_spell_position_state(stacks, now_fraction, safe_start)
				count = count + 1
				starts[count] = safe_start
				local color = get_position_color(state, key)
				icon:ClearAllPoints()
				icon:SetPoint("CENTER", vf, "TOPLEFT", safe_start * w, center_y)
				-- Cached per slot: the per-tick path re-sets only what changed, so a
				-- stable swing allocates nothing (the codebase's marker discipline).
				if weave_position_icon_texture[key] ~= entry.icon then
					weave_position_icon_texture[key] = entry.icon
					icon:SetTexture(entry.icon)
				end
				icon:SetVertexColor(color[1], color[2], color[3],
					state == "ready" and ST.SHAMAN.position_style.ready_alpha or color[4])
				icon:Show()
				if weave_position_time_value[key] ~= effective then
					weave_position_time_value[key] = effective
					time:SetText(string.format("%.1f", effective))
				end
				time:SetTextColor(color[1], color[2], color[3], 0.95)
				time:Show()
			end
		else
			icon:Hide()
			time:Hide()
		end
	end
	for i = count + 1, #starts do
		starts[i] = nil
	end
	local min_start, max_start = st.weave.get_cast_zone_bounds(starts)
	if min_start and max_start and max_start > min_start then
		local zone = vf.weave_pos_zone
		zone:ClearAllPoints()
		zone:SetPoint("BOTTOMLEFT", vf, "TOPLEFT", min_start * w, WEAVE_ZONE_BOTTOM)
		zone:SetWidth((max_start - min_start) * w)
		zone:Show()
		local label = vf.weave_pos_label
		label:ClearAllPoints()
		label:SetPoint("BOTTOM", vf, "TOPLEFT", ((min_start + max_start) / 2) * w,
			WEAVE_ZONE_BOTTOM + WEAVE_ZONE_HEIGHT + WEAVE_ZONE_LABEL_GAP)
		label:Show()
	else
		vf.weave_pos_zone:Hide()
		vf.weave_pos_label:Hide()
	end
end

-- DW sync + Flurry badges (round 2): the sync badge compares the MH/OH next
-- landings against the Flurry ICD threshold and warns amber when they drift apart
-- (desync burns extra Flurry charges); the Flurry badge shows the stack count and
-- the live 0.5 s proc ICD. Option-gated (nil = off), created lazily, stacked in the
-- mainhand badge column under Rockbiter. The sync half shows only while
-- dual-wielding with both landings known; the Flurry half works for any setup.
local function update_dw_badges(self, vf, db, now)
	if db.show_shaman_dw_sync ~= true then
		if vf.weave_sync_text then vf.weave_sync_text:Hide() end
		if vf.weave_flurry_text then vf.weave_flurry_text:Hide() end
		return
	end
	if not vf.weave_sync_text then
		local sync_text = vf:CreateFontString(nil, "OVERLAY")
		sync_text:SetPoint("TOPLEFT", vf, "TOPRIGHT", 3, -28)
		sync_text:SetJustifyH("LEFT")
		sync_text:SetFont(get_tracker_font_path(self), 9, "OUTLINE")
		sync_text:Hide()
		vf.weave_sync_text = sync_text
		local flurry_text = vf:CreateFontString(nil, "OVERLAY")
		flurry_text:SetPoint("TOPLEFT", vf, "TOPRIGHT", 3, -38)
		flurry_text:SetJustifyH("LEFT")
		flurry_text:SetFont(get_tracker_font_path(self), 9, "OUTLINE")
		flurry_text:Hide()
		vf.weave_flurry_text = flurry_text
	end
	local sync_text, flurry_text = vf.weave_sync_text, vf.weave_flurry_text
	local oh = self.offhand
	local mh = self.mainhand
	local offset = st.weave.get_dw_sync_offset(mh and mh.ends_at, oh and oh.ends_at)
	if oh and oh.has_weapon and offset then
		local desynced = st.weave.is_dw_desynced(offset)
		local color = desynced and WEAVE_DESYNC_COLOR or WEAVE_SYNC_COLOR
		local readout = desynced and string.format("DW DESYNC %.1fs", offset)
			or string.format("DW SYNC %.1fs", offset)
		if self.weave_sync_readout ~= readout then
			self.weave_sync_readout = readout
			sync_text:SetText(readout)
			sync_text:SetTextColor(color[1], color[2], color[3], color[4])
		end
		sync_text:Show()
	else
		self.weave_sync_readout = nil
		sync_text:Hide()
	end
	local stacks = self.weave_flurry_stacks
	if type(stacks) == "number" and stacks >= 1 then
		local icd = st.weave.get_flurry_icd_remaining(self.weave_flurry_proc_at, now)
		local readout
		if icd and icd > 0 then
			readout = string.format("FL %d %.1fs", stacks, icd)
		else
			readout = string.format("FL %d", stacks)
		end
		if self.weave_flurry_readout ~= readout then
			self.weave_flurry_readout = readout
			flurry_text:SetText(readout)
			flurry_text:SetTextColor(WEAVE_FLURRY_COLOR[1], WEAVE_FLURRY_COLOR[2],
				WEAVE_FLURRY_COLOR[3], WEAVE_FLURRY_COLOR[4])
		end
		flurry_text:Show()
	else
		self.weave_flurry_readout = nil
		flurry_text:Hide()
	end
end

-- Offhand spark mirror: the mainhand spark's own state drawn on the offhand visuals
-- frame while the player dual-wields (reference SuperSwingTimer_ClassMods.lua:3481-3489).
-- The widget is created lazily so nothing exists before an offhand is used.
local function update_offhand_spark(self, hand)
	local vf = self:get_visuals_frame(hand)
	if not vf then return end
	local spark = vf.weave_spark_offhand
	if not spark then
		if not (self.offhand and self.offhand.has_weapon) then return end
		spark = vf:CreateTexture(nil, "OVERLAY")
		spark:SetDrawLayer("OVERLAY", -2)
		spark:SetColorTexture(1, 1, 1, 1)
		spark:Hide()
		vf.weave_spark_offhand = spark
	end
	local db = self:get_class_table()
	local d = self.mainhand
	if db.weave_enabled == false
		or db.show_shaman_breakpoint_markers == false
		or not is_weave_mw_active(db, self.weave_mw_observed)
		or not (self.offhand and self.offhand.has_weapon)
		or not (d and d.speed and d.ends_at and d.start and not d.is_full) then
		spark:Hide()
		return
	end
	local entry = self.SHAMAN.get_weave_visual_spell(self)
	if not entry then
		spark:Hide()
		return
	end
	local now = api.get_time()
	local latency = ((self.latency and self.latency.world_ms) or 0) / 1000
	local spark_fraction, clipped = get_weave_spark_display(self, d, entry, now, latency)
	if spark_fraction == nil then
		spark:Hide()
		return
	end
	local w, h = self:get_bar_visuals_width_and_height(hand)
	local spark_h = db.weave_spark_height or WEAVE_FALLBACK_SPARK_HEIGHT
	if type(h) == "number" and h > 0 and spark_h > h then
		spark_h = h
	end
	spark:SetWidth(db.weave_spark_width or WEAVE_FALLBACK_SPARK_WIDTH)
	spark:SetHeight(spark_h)
	spark:ClearAllPoints()
	spark:SetPoint("CENTER", vf, "LEFT", st.weave.clamp_fraction(spark_fraction) * w, 0)
	local color = WEAVE_RED_COLOR
	if not clipped then
		color = get_shaman_spark_color()
	end
	spark:SetVertexColor(color[1], color[2], color[3], db.weave_spark_alpha or WEAVE_FALLBACK_SPARK_ALPHA)
	spark:Show()
end

function ST.SHAMAN.on_bar_update(self, hand)
	-- Per-frame weave visuals, called from ST:onupdate_common via the generic class hook.
	-- Deliberately cheap and nil-safe. NOTE: this must NOT gate on st.is_mainline - the
	-- Forever client is Mainline-code but shows weaving - only on swing activity.
	if hand == "offhand" then
		update_offhand_spark(self, hand)
		return
	end
	if hand ~= "mainhand" then
		return
	end
	-- Next Action Guide (mainhand only): driven before the swing gates below so it also
	-- runs off-swing. Deliberately not gated on st.is_mainline - the Forever client is
	-- Mainline-code but shows the guide; swing activity decides instead (the Retail
	-- stand-in never reports a swing). Settings that rebuild the frame
	-- (scale/position/lock) are applied when the class options change; the display
	-- toggles are read live by the UI.
	local db = self:get_class_table()
	if db.nextaction_icon_size ~= self.guide_ui_icon_size
		or db.nextaction_x ~= self.guide_ui_x
		or db.nextaction_y ~= self.guide_ui_y
		or db.nextaction_locked ~= self.guide_ui_locked then
		self.guide_ui_icon_size = db.nextaction_icon_size
		self.guide_ui_x = db.nextaction_x
		self.guide_ui_y = db.nextaction_y
		self.guide_ui_locked = db.nextaction_locked
		if st.nextaction_ui then
			st.nextaction_ui.apply_settings(self)
		end
	end
	if st.nextaction_ui then
		st.nextaction_ui.on_bar_update(self, hand)
	end
	-- Cooldown HUD: retries a lockdown-deferred creation and picks layout option
	-- changes up between the HUD driver's ticks (the row itself ticks on its own
	-- driver frame, so this is cheap). Deliberately not gated on st.is_mainline:
	-- the Forever client must show the HUD, and the Retail stand-in simply never
	-- swings (the paladin hooks it the same way in classes/paladin.lua).
	-- Runs after the guide tick above: the shared per-frame order is guide then
	-- HUD in all six class modules (deep-audit F8).
	if st.hud then
		st.hud.on_bar_update(self, hand)
	end
	local vf = self:get_visuals_frame(hand)
	if not vf then
		return
	end
	if not vf.weave_marker then
		self.SHAMAN.setup_weave_visuals(self)
	end
	local marker = vf.weave_marker
	if not marker then
		return
	end

	local d = self[hand]
	local now = api.get_time()
	local w, h = self:get_bar_visuals_width_and_height(hand)

	-- Trackers: each one gates on its own option and degrades when the spell/aura/API is
	-- missing, independently of the swing-activity gate below, so a shield swap, badge
	-- countdown or flame shock tick keeps updating while the swing bar is idle. The
	-- shared target-debuff scan runs first (Flame Shock + Stormstrike, throttled); the
	-- round-2 spell-position row and the DW/Flurry badges gate themselves.
	refresh_target_debuffs(self, db, now)
	update_windfury_icd(self, vf, d, db, now, h)
	update_flame_shock_bar(self, vf, db, now, w)
	update_stormstrike_bar(self, vf, db, now, w)
	update_cooldown_badges(self, vf, db, now, d)
	update_shield_charges(self, vf, db, h)
	update_wf_hold_wash(self, vf, db, now, d, w, h)
	update_rockbiter_badge(self, vf, db, now)
	update_lust_badge(self, vf, db, now)
	update_spell_positions(self, vf, db, now, d, w)
	update_dw_badges(self, vf, db, now)

	if db.weave_enabled == false
		or not is_weave_mw_active(db, self.weave_mw_observed)
		or not (d and d.speed and d.ends_at and d.start and not d.is_full) then
		hide_weave_markers(vf)
		if vf.weave_spark then vf.weave_spark:Hide() end
		return
	end

	local entry, family = self.SHAMAN.get_weave_visual_spell(self)
	if not entry then
		hide_weave_markers(vf)
		if vf.weave_spark then vf.weave_spark:Hide() end
		return
	end

	local latency = ((self.latency and self.latency.world_ms) or 0) / 1000
	local spark_fraction, clipped, marker_fraction = get_weave_spark_display(self, d, entry, now, latency)

	-- Marker: the spell icon sits at the latest safe cast start, in the family color.
	-- H4: an unresolvable cast time makes get_marker_fraction return nil; hide the
	-- whole marker trio instead of clamping nil to 0 and drawing a false breakpoint.
	local marker_alpha = db.weave_marker_alpha or WEAVE_FALLBACK_MARKER_ALPHA
	if clipped then
		marker_alpha = marker_alpha * WEAVE_UNSAFE_ALPHA
	end
	local marker_size = db.weave_marker_size or WEAVE_FALLBACK_MARKER_SIZE
	local marker_top, marker_bottom = vf.weave_marker_top, vf.weave_marker_bottom
	if marker_fraction == nil then
		hide_weave_markers(vf)
	else
		local marker_x = st.weave.clamp_fraction(marker_fraction) * w
		marker:SetWidth(marker_size)
		marker:SetHeight(marker_size)
		if entry.icon ~= self.weave_marker_icon then
			self.weave_marker_icon = entry.icon
			if entry.icon then
				marker:SetTexture(entry.icon)
				if marker_top then marker_top:SetTexture(entry.icon) end
				if marker_bottom then marker_bottom:SetTexture(entry.icon) end
			end
		end
		marker:ClearAllPoints()
		marker:SetPoint("CENTER", vf, "LEFT", marker_x, 0)
		local family_color = st.weave.FAMILY_COLORS[family]
			or (family == "LvB" and st.weave.LAVA_BURST_COLOR)
		local r, g, b = 1, 1, 1
		if family_color then
			r, g, b = family_color[1], family_color[2], family_color[3]
		end
		marker:SetVertexColor(r, g, b, marker_alpha)
		marker:Show()

		-- Reference top/bottom breakpoint icons (SuperSwingTimer_ClassMods.lua:3491-3506):
		-- the same icon above the bar and below the bar stack, anchored at the marker
		-- fraction. The pair hides with the option or without an icon texture.
		if marker_top and marker_bottom and entry.icon and db.show_shaman_breakpoint_markers ~= false then
			local bottom_anchor, bottom_width = get_weave_bottom_anchor(self, vf, w)
			marker_top:SetWidth(marker_size)
			marker_top:SetHeight(marker_size)
			marker_top:ClearAllPoints()
			marker_top:SetPoint("BOTTOM", vf, "TOPLEFT", marker_x, WEAVE_MARKER_GAP)
			marker_top:SetVertexColor(r, g, b, marker_alpha)
			marker_top:Show()
			marker_bottom:SetWidth(marker_size)
			marker_bottom:SetHeight(marker_size)
			marker_bottom:ClearAllPoints()
			marker_bottom:SetPoint("TOP", bottom_anchor, "BOTTOMLEFT",
				st.weave.clamp_fraction(marker_fraction) * bottom_width, -WEAVE_MARKER_GAP)
			marker_bottom:SetVertexColor(r, g, b, marker_alpha)
			marker_bottom:Show()
		else
			if marker_top then marker_top:Hide() end
			if marker_bottom then marker_bottom:Hide() end
		end
	end

	-- Spark: only while a tracked cast is active.
	local spark = vf.weave_spark
	if spark and spark_fraction ~= nil then
		local spark_h = db.weave_spark_height or WEAVE_FALLBACK_SPARK_HEIGHT
		if type(h) == "number" and h > 0 and spark_h > h then
			-- Reference behaviour: the spark never outgrows the bar.
			spark_h = h
		end
		spark:SetWidth(db.weave_spark_width or WEAVE_FALLBACK_SPARK_WIDTH)
		spark:SetHeight(spark_h)
		spark:ClearAllPoints()
		spark:SetPoint("CENTER", vf, "LEFT", st.weave.clamp_fraction(spark_fraction) * w, 0)
		local color = WEAVE_RED_COLOR
		if not clipped then
			color = get_shaman_spark_color()
		end
		spark:SetVertexColor(color[1], color[2], color[3], db.weave_spark_alpha or WEAVE_FALLBACK_SPARK_ALPHA)
		spark:Show()
	elseif spark then
		spark:Hide()
	end
end

--=========================================================================================
-- Next Action Guide: the shaman provider for the generic guide frame
--=========================================================================================
-- Implements the frozen ST.<CLASS>.guide contract documented in nextaction_ui.lua's
-- header. The decision model is the pure st.shaman_guide module (shaman_guide.lua; its
-- docblock is the frozen spec), the live reads live in gather_guide_inputs, and this
-- table is the last piece of glue: the slot set, the gather/evaluate pair and the static
-- captions. Default OFF (nextaction_enabled=false in config_presets.lua): a wrong prompt
-- is worse than none, so the owner enables it after in-client verification.
--
-- SIX slots (stormstrike, flameshock, weave, firenova, earthshock, twist - the
-- contract's original six) plus the four Wrath slots (feralspirit, fireele, magma,
-- lavalash) plus the audit-2026-10-19 three (shamanisticrage, chainlightning,
-- moltenblast) plus the Era static totems (wftotem, goa) plus the three maintain
-- mirrors (lightningshield, searing - S-19 / S-17, the slotless lines the drill
-- lane filed - and coe - S-20 / U-10, the Call of the Elements line, whose water
-- -totem clock landed with it). The frame builds one icon per slot in provider
-- order (the paladin ships eight), so eighteen needs no contract change.
-- Stormstrike, Flame Shock and
-- Fire Nova carry a cooldown_key:
-- the SS swipe follows the client-reported cooldown (the gather's GCD-echo rule
-- keeps a running GCD out of it), the Flame Shock swipe follows the target debuff
-- window the tracker already measures, and the Fire Nova swipe follows its 15 s
-- client cooldown. Feral Spirit and Fire Elemental carry a cooldown_key the same
-- way (known-gated: nil while the spell is unknown); Magma's swipe follows the
-- fire-slot totem window; Lava Lash and Shamanistic Rage carry a cooldown_key with
-- no fallback (unknown cooldown length - the client length rides while one runs).
-- The weave slot's icon comes from the resolved spell catalogue at
-- post_init (re-pointed at Lava Burst on SoD; Feral Spirit / Lava Lash re-point by
-- name the same way); Earth Shock, Chain Lightning, Molten Blast and the twist
-- skeleton carry no swipe. Lightning Shield, Searing and Call of the Elements
-- carry no swipe either: a shield buff, a persistent totem and a totem-multi-
-- cast drop have no window to ride - their slots light on the due flag alone.
-- The Stormstrike swipe's FALLBACK length is per family (S-23 / U-09: Era 20 /
-- SoD 6 / TBC 10 / Wrath 8); the gather refreshes the descriptor before the
-- frame renders it, and the client-reported length wins whenever a real
-- cooldown runs.

-- One reused input table: no per-frame allocations on the guide tick (the frame passes
-- its own reused table through gather; this one serves direct calls).
ST.SHAMAN.guide_inputs = {}

-- Live cooldown for the guide, with the client's GCD echo filtered: GetSpellCooldown
-- reports whichever cooldown ends later, so a reading of 1.51 s or less is a GCD echo
-- and never Stormstrike's own cooldown. Returns remaining seconds (>= 0) and the
-- client-reported duration, or (0, nil) when there is no real cooldown to show.
local function get_guide_cooldown(spell)
	if not spell then
		return 0, nil
	end
	local start_time, duration = api.GetSpellCooldown(spell)
	if not start_time or not duration or duration <= 1.51 then
		return 0, nil
	end
	local remaining = start_time + duration - api.get_time()
	if remaining <= 0 then
		return 0, nil
	end
	return remaining, duration
end

-- Wrath cooldown-slot feed with the known gate: remaining seconds (>= 0) and the
-- client-reported duration when the spell is known, (nil, nil) otherwise. An
-- unconfirmed id (Fire Elemental, Lava Lash) reads unknown on every client until
-- its id is confirmed in-game, so the engine rule - numeric only - never prompts
-- on a guess. Unknown families keep the same shape (nil feeds are dead).
-- Name-vs-id: TBC probes the NAME, every other family probes the id.
local function get_guide_cooldown_known(spell_id, spell_name)
	local query = spell_query(spell_id, spell_name)
	if not api.is_spell_known(query) then
		return nil, nil
	end
	return get_guide_cooldown(query)
end

-- Is the shock cooldown ready? (S4 FS-collision guard; the shock global is shared
-- by Flame Shock and Earth Shock, so the Flame Shock read answers for the refresh
-- the guard defers to.) Rank-agnostic localized-name read with the same GCD-echo
-- filter as the guide cooldowns; the name is resolved lazily and retried until the
-- spell data answers, mirroring hud_slot_name's convention. A client that cannot
-- answer reports no cooldown - the guard's shock leg then reads ready.
local weave_flameshock_query
function ST.SHAMAN.is_shock_ready()
	if weave_flameshock_query == nil then
		weave_flameshock_query = api.GetSpellInfo(spell_query(WEAVE_FLAME_SHOCK_BASE_SPELL_ID, WEAVE_FLAME_SHOCK_NAME)) or false
	end
	local remaining = get_guide_cooldown(weave_flameshock_query or spell_query(WEAVE_FLAME_SHOCK_BASE_SPELL_ID, WEAVE_FLAME_SHOCK_NAME))
	return remaining <= 0
end

-- Slot descriptors: the rank-1 id ships as the fallback; resolve_guide_icons re-points
-- the weave slot at the resolved catalogue entry once the spell data is live. The
-- shock/totem slots keep their static rank-1 ids (icons are rank-invariant); the
-- twist slot is the skeleton's sixth (never lit live outside TBC - see the gather
-- stub). The four Wrath slots follow the same pattern: Feral Spirit ships its
-- verified id, the other three ship best-recall ids marked UNCONFIRMED above (a
-- wrong id stays silent through the gather's known gate).
local guide_slot_stormstrike = { key = "stormstrike", spell_id = WEAVE_STORMSTRIKE_SPELL_ID,
	cooldown_key = "stormstrike", swipe_duration = ST.SHAMAN.STORMSTRIKE_COOLDOWN_SECONDS.DEFAULT }
local guide_slot_flameshock = { key = "flameshock", spell_id = 8050,
	cooldown_key = "flameshock", swipe_duration = 12 }
local guide_slot_weave = { key = "weave", spell_id = 403 }
local guide_slot_firenova = { key = "firenova", spell_id = WEAVE_FIRE_NOVA_SPELL_ID,
	cooldown_key = "firenova", swipe_duration = WEAVE_FIRE_NOVA_COOLDOWN_SECONDS }
local guide_slot_earthshock = { key = "earthshock", spell_id = WEAVE_EARTH_SHOCK_SPELL_ID }
local guide_slot_twist = { key = "twist", spell_id = WEAVE_WINDFURY_TOTEM_SPELL_ID }
local guide_slot_feralspirit = { key = "feralspirit", spell_id = WEAVE_FERAL_SPIRIT_SPELL_ID,
	cooldown_key = "feralspirit", swipe_duration = WEAVE_FERAL_SPIRIT_COOLDOWN_SECONDS }
local guide_slot_fireele = { key = "fireele", spell_id = WEAVE_FIRE_ELEMENTAL_SPELL_ID,
	cooldown_key = "fireele", swipe_duration = WEAVE_FIRE_ELEMENTAL_COOLDOWN_SECONDS }
local guide_slot_magma = { key = "magma", spell_id = WEAVE_MAGMA_TOTEM_SPELL_ID,
	cooldown_key = "magma", swipe_duration = WEAVE_MAGMA_SWIPE_SECONDS }
local guide_slot_lavalash = { key = "lavalash", spell_id = WEAVE_LAVA_LASH_SPELL_ID,
	cooldown_key = "lavalash" }
-- Shamanistic Rage (audit 2026-10-19: SoD/TBC/Wrath): known-gated like Lava Lash
-- (no confirmed fallback - the client length rides while one runs).
local guide_slot_shamanisticrage = { key = "shamanisticrage", spell_id = WEAVE_SR_SPELL_ID,
	cooldown_key = "shamanisticrage" }
-- Chain Lightning multi-target (audit 2026-10-19 §4: SoD MW >= 4 with 2+ targets):
-- SKELETON, no swipe (no sensor yet, so the feed is always nil).
local guide_slot_chainlightning = { key = "chainlightning", spell_id = 10605 }
-- Molten Blast (audit 2026-10-19 SoD §2: sim filler below Earth Shock): no swipe
-- (the rune has no cooldown to ride); id UNCONFIRMED, SoD feeds by name.
local guide_slot_moltenblast = { key = "moltenblast", spell_id = WEAVE_MOLTEN_BLAST_SPELL_ID }
-- Era static totems (G2, audit 2026-10-19 Era §): no swipe (persistent totems
-- have no window to ride - the due-or-nil feed lights the slot, the drop
-- clears it); ids UNCONFIRMED, Era-base feeds by known gate, SoD keeps the
-- id gate byte-identical (nil - no SoD totem maintain in its sim).
local guide_slot_wftotem = { key = "wftotem", spell_id = WEAVE_WF_TOTEM_SPELL_ID }
local guide_slot_goa = { key = "goa", spell_id = WEAVE_GOA_TOTEM_SPELL_ID }
-- Lightning Shield (audit 2026-10-19 §2.6 S-19: all three wowsims/wotlk enhancement
-- APLs maintain it iff inactive, above Lava Lash). NO swipe: the shield is a buff
-- with charges, not a cooldown - the maintain rides the player's own aura (the
-- charge row's walk), not a timer. The id is the Wrath Lightning Shield
-- (UNCONFIRMED - in-client confirmation owed; a wrong id shows a wrong icon, the
-- rule itself reads the aura by name and stays correct).
local guide_slot_lightningshield = { key = "lightningshield", spell_id = 49281 }
-- Searing Totem (audit 2026-10-19 §2.6 S-17/S-25: the classic default APL keeps
-- Searing down past 20 s, the SoD APL past 30 s). NO swipe: a persistent totem has
-- no window to ride - the due-or-nil feed lights the slot. The id is UNCONFIRMED
-- (the same id the reader already gates on).
local guide_slot_searing = { key = "searing", spell_id = WEAVE_SEARING_TOTEM_SPELL_ID }
-- Call of the Elements (S-20 / U-10): the three wowsims/wotlk enhancement APLs
-- rank it between Earth Shock and Magma Totem, gated on the water totem being
-- under 20 s (default_wf.apl.json [9], default_ft.apl.json [9], phase_3.apl.json
-- [8] - each between the Earth Shock 49231 line and the Magma Totem 58734 line;
-- the condition is {"cmp":{"op":"OpLt","lhs":{"totemRemainingTime":
-- {"totemType":"Water"}},"rhs":{"const":{"val":"20s"}}}}). NO swipe: the CoE drop
-- is a maintain, not a cooldown to ride - the due flag lights the slot, exactly
-- like the Lightning Shield / Searing mirrors. The id 66842 is CLIENT-SOURCED
-- (the clients' own Constants.lua TOTEM_MULTI_CAST_SUMMON_SPELLS, cited above).
-- (The descriptor is inlined in the slots list below: this chunk is at Lua 5.1's
-- 200-local limit.)

-- The APL utility layer's guide slots (bench/rotation_gap_vs_apl_2026-10-20.md §5):
-- the two totem upkeeps, the TBC shock filler and the Wrath party cooldown.
-- Declared as table fields, not locals (this chunk is at Lua 5.1's 200-local
-- limit), and inlined in the slots list below like the Call of the Elements slot.
-- NO swipe on any of them: a persistent totem has no window to ride, and the two
-- cooldowns carry no confirmed fallback (the client-reported length rides while
-- one runs). The ids are the sims' ids; the icon resolves by NAME on the client
-- (resolve_guide_icons), because the TBC ids are the TBC client's own.
ST.SHAMAN.APL_SLOTS = {
	strength_of_earth = { key = "strength_of_earth", spell_id = 10442 },
	mana_spring = { key = "mana_spring", spell_id = 25570 },
	frostshock = { key = "frostshock", spell_id = 25464 },
	bloodlust = { key = "bloodlust", spell_id = 2825 },
}

-- The Stormstrike swipe fallback for the running family (S-23 / U-09): the
-- per-family sim length (the table above). The ERA token carries both builds,
-- so the SoD MW-rune latch picks the SoD length (6 s) over the Era-base one
-- (20 s); every other family reads its own entry, and a family with no sourced
-- value keeps the shipped 10 s. Pure: no API, no clock.
function ST.SHAMAN.get_stormstrike_cooldown_seconds(self)
	if st.family == "ERA" then
		if self and self.weave_mw_observed == true then
			return ST.SHAMAN.STORMSTRIKE_COOLDOWN_SECONDS.SOD
		end
		return ST.SHAMAN.STORMSTRIKE_COOLDOWN_SECONDS.ERA
	end
	local value = ST.SHAMAN.STORMSTRIKE_COOLDOWN_SECONDS[st.family]
	if type(value) == "number" then
		return value
	end
	return ST.SHAMAN.STORMSTRIKE_COOLDOWN_SECONDS.DEFAULT
end

-- Resolve the weave slot's icon from the catalogue the caller just resolved; called
-- once from post_init, before the shared frame builds its icons. With no resolved
-- family the slot keeps the Lightning Bolt rank-1 fallback above.
-- SoD 5-stack spender choice (docs/research/rotations_sod.md): on ERA clients the
-- Lava Burst rune, when the client's spell data resolves it, re-points the weave
-- slot, so the MW5 prompt shows the Lava Burst icon and label instead of Lightning
-- Bolt. ERA-only: Wrath enhancement never casts Lava Burst (Elemental-only there),
-- so Wrath keeps the catalogue icon. The id comes from the shared Lava Burst cache
-- (resolve_lava_burst; the classic GetSpellInfo answers a name query with the
-- spell's id in its 7th return, so no rune spell id is guessed here); unknown reads
-- nil and keeps the catalogue (Era-base byte-identical). Callers apply the SoD
-- latch (weave_mw_observed) on top: the probe answers client data, the feed
-- decides SoD. The player-level
-- rune/talent gate rides the assist's MW5 spender choice (get_weave_visual_spell);
-- this post_init slot shape keeps its client-data gate, pinned by its own suite.
function ST.SHAMAN.resolve_guide_icons(self)
	local entry = self.SHAMAN.get_weave_visual_spell(self)
	if entry and entry.spell_id then
		guide_slot_weave.spell_id = entry.spell_id
	end
	if st.family == "ERA" then
		local lava = self.SHAMAN.resolve_lava_burst(self)
		if lava and type(lava.spell_id) == "number" then
			guide_slot_weave.spell_id = lava.spell_id
		end
		-- SoD rune slots (audit 2026-10-19 SoD §2): the Wrath Feral Spirit / Lava
		-- Lash ids never resolve on SoD, so the answered name re-points the slot
		-- (icon + rotation label) the same way; unknown reads keep the Wrath ids
		-- (Era-base byte-identical - the known gate feeds nil there anyway).
		local feral = self.SHAMAN.resolve_named_spell(self, "feralspirit")
		if feral and type(feral.spell_id) == "number" then
			guide_slot_feralspirit.spell_id = feral.spell_id
		end
		local lash = self.SHAMAN.resolve_named_spell(self, "lavalash")
		if lash and type(lash.spell_id) == "number" then
			guide_slot_lavalash.spell_id = lash.spell_id
		end
	end
	-- The two maintain slots (S-19 / S-17): their ids are UNCONFIRMED (the Searing
	-- id is the Forever sim's, so it does not resolve on the classic-line clients
	-- at all), so the client's own spell data re-points the icon (and the rotation
	-- label) by NAME - the name is certain where the id is not (the classic
	-- GetSpellInfo answers a name query with the spell's id in its 7th return, the
	-- resolve_named_spell convention). An unanswered probe keeps the shipped id: a
	-- wrong icon is filed for in-client confirmation, never a wrong prompt - the
	-- rules read the player's own aura and the fire slot, not the id.
	local ls_answered, _, _, _, _, _, ls_id = api.GetSpellInfo("Lightning Shield")
	if ls_answered and type(ls_id) == "number" then
		guide_slot_lightningshield.spell_id = ls_id
	end
	local sr_answered, _, _, _, _, _, sr_id = api.GetSpellInfo(WEAVE_SEARING_TOTEM_NAME)
	if sr_answered and type(sr_id) == "number" then
		guide_slot_searing.spell_id = sr_id
	end
	-- The APL utility slots (bench/rotation_gap_vs_apl_2026-10-20.md §5): the
	-- Strength of Earth and Mana Spring ids are the SIMS' ids, and the TBC
	-- client's own ids differ (25528 / 25570), so the client's spell data
	-- re-points the icons by NAME - the name is certain where the id is not (the
	-- classic GetSpellInfo answers a name query with the spell's id in its 7th
	-- return). An unanswered probe keeps the shipped id: a wrong icon is filed
	-- for in-client confirmation, never a wrong prompt - the rules read the
	-- client's own slots, not the id.
	local soe_answered, _, _, _, _, _, soe_id = api.GetSpellInfo(
		ST.SHAMAN.APL_UTILITY.strength_of_earth.name)
	if soe_answered and type(soe_id) == "number" then
		ST.SHAMAN.APL_SLOTS.strength_of_earth.spell_id = soe_id
	end
	local ms_answered, _, _, _, _, _, ms_id = api.GetSpellInfo(
		ST.SHAMAN.APL_UTILITY.mana_spring.name)
	if ms_answered and type(ms_id) == "number" then
		ST.SHAMAN.APL_SLOTS.mana_spring.spell_id = ms_id
	end
	local fs_answered, _, _, _, _, _, fs_id = api.GetSpellInfo(
		ST.SHAMAN.APL_UTILITY.frostshock.name)
	if fs_answered and type(fs_id) == "number" then
		ST.SHAMAN.APL_SLOTS.frostshock.spell_id = fs_id
	end
end

-- Live inputs for the pure engine, written into the caller-owned reused table. Every
-- field of the frozen input set is written on every call, so no stale value can survive
-- between ticks; nil means "the client did not answer".
function ST.SHAMAN.gather_guide_inputs(self, out)
	local inputs = out or ST.SHAMAN.guide_inputs
	local now = api.get_time()
	local d = self.mainhand
	local gcd = self.gcd
	local db = self:get_class_table()

	-- Swing and GCD, in the api.get_time() domain (ends_at and the GCD stamp share it).
	inputs.speed = (d and d.speed) or 0
	inputs.swing_remaining = math.max(0, ((d and d.ends_at) or now) - now)
	inputs.gcd_remaining = (gcd and gcd.expires and math.max(0, gcd.expires - now)) or 0

	-- The cast state, the Maelstrom stacks and the catalogue readiness the rules read.
	-- (A gather before post_init finds no catalogue and simply answers unavailable.)
	-- The stack count stays truthful (the aura scan owns it); mw_available carries the
	-- family-plus-observed gate, the option kill-switch AND the S4 FS-collision guard
	-- (see the Flame Shock block below), so the engine - never the gather - decides
	-- whether MW rules may fire, from what the gather feeds. On ERA the latch is the
	-- SoD signal (observed MW aura => SoD rune client); Era-base never observes it.
	inputs.casting = self.weave_is_casting == true
	local mw_active = is_weave_mw_active(db, self.weave_mw_observed)
	inputs.mw_available = mw_active
	local stacks = self.weave_mw_stacks
	if type(stacks) ~= "number" then
		stacks = 0
	end
	inputs.mw_stacks = stacks
	local entry
	if self.weave_catalog then
		entry = self.SHAMAN.get_weave_visual_spell(self)
	end
	inputs.weave_available = (entry ~= nil) and self.weave_is_casting ~= true

	-- G1 SoD ANY-stack weave fit (audit 2026-10-19 SoD §: the sim weaves LB/LvB
	-- at ANY stacks when the cast fits, including the 0-1 hardcast filler;
	-- live-gate G1) + M1 Wrath sub-5 (bench/wrath_leftovers_2026-10-19.md §S3:
	-- the default_wf APL hardcasts LB 49238 at MW >= 3 when 300 ms + cast
	-- fits the swing): the sub-5 hardcast the guide rules 5b (LvB, high) +
	-- 5c (Wrath LB, high) + 12b (SoD LB, low) consume. SoD-only vs
	-- Wrath-only branches below (ERA + observed MW rune vs WRATH; Era-base
	-- never observes, TBC has no MW, Forever/unknown stay nil), WF-imbue
	-- build only (windfury up, rockbiter down - imbue-build awareness: both
	-- sims run WF builds; a Rockbiter build stays silent), catalogue (SoD)
	-- / known-gate (Wrath 49238, live cast time, never hardcoded) resolves,
	-- swing known, not casting. The fit is swing_remaining >= effective +
	-- latency + buffer (SoD 0.10 s, Wrath 0.30 s - the sims' cast + 100/300
	-- ms, engine constants with fallbacks). Every field is written on every
	-- call: nil = unknown/not-in-window (never prompts, old behaviour),
	-- true/false = the fit verdict in the window. api.get_time() domain
	-- throughout.
	inputs.weave_sub5_ready = nil
	inputs.weave_sub5_cast_seconds = nil
	inputs.weave_sub5_is_lavaburst = nil
	do
		local guide = st.shaman_guide
		local is_wrath = st.family == "WRATH"
		local min_stacks, buffer
		if is_wrath then
			min_stacks = (guide and guide.WEAVE_SUB5_MIN_STACKS_WRATH) or 3
			buffer = (guide and guide.WEAVE_SUB5_FIT_BUFFER_WRATH_SECONDS) or 0.30
		else
			min_stacks = (guide and guide.WEAVE_SUB5_MIN_STACKS) or 0
			buffer = (guide and guide.WEAVE_SUB5_FIT_BUFFER_SECONDS) or 0.10
		end
		local family_ok = (st.family == "ERA" and self.weave_mw_observed == true and mw_active)
			or (is_wrath and mw_active)
		if family_ok
			and type(stacks) == "number" and stacks >= min_stacks and stacks < 5
			and self.weave_is_casting ~= true
			and self.weave_windfury_active == true
			and self.weave_rockbiter_active ~= true
			and d and type(d.speed) == "number" and d.speed > 0
			and type(d.ends_at) == "number" and type(d.start) == "number"
			and not d.is_full then
			local sub5_entry, sub5_is_lava = nil, false
			if is_wrath then
				-- Wrath LB 49238 (sim max rank): known-gated, live cast time
				-- from the client's spell data (never hardcoded); LvB is
				-- Elemental-only on Wrath, so is_lavaburst stays false and the
				-- engine answers rule 5c.
				if api.is_spell_known(spell_query(WEAVE_WRATH_LB_SPELL_ID, WEAVE_LB_NAME)) then
					local name, _, icon, cast_ms =
						api.GetSpellInfo(spell_query(WEAVE_WRATH_LB_SPELL_ID, WEAVE_LB_NAME))
					if name and type(cast_ms) == "number" and cast_ms > 0 then
						sub5_entry = {
							spell_id = WEAVE_WRATH_LB_SPELL_ID,
							name = name,
							icon = icon,
							cast_seconds = cast_ms / 1000,
						}
					end
				end
			else
				if self.weave_catalog and self.weave_catalog.LB then
					sub5_entry = self.weave_catalog.LB
				end
				local lava = self.SHAMAN.resolve_lava_burst(self)
				if lava and api.is_spell_known(spell_query(lava.spell_id, lava.name)) then
					sub5_entry = lava
					sub5_is_lava = true
				end
			end
			if sub5_entry then
				local effective = self.SHAMAN.get_weave_effective_cast_time(self, sub5_entry)
				if type(effective) == "number" and effective == effective then
					local latency_ms = self.latency and self.latency.world_ms
					if type(latency_ms) ~= "number" then latency_ms = 0 end
					local latency = latency_ms / 1000
					local swing_remaining = math.max(0, d.ends_at - now)
					inputs.weave_sub5_cast_seconds = effective
					inputs.weave_sub5_is_lavaburst = sub5_is_lava
					inputs.weave_sub5_ready = swing_remaining >= effective + latency + buffer
				end
			end
		end
	end

	-- Flame Shock: the tracker's target-debuff window, plus the slot's swipe length.
	inputs.flameshock_remaining = nil
	inputs.flameshock_duration = nil
	if self.weave_fs_duration or self.weave_fs_expires then
		inputs.flameshock_remaining, inputs.flameshock_duration =
			st.weave.get_flame_shock_remaining(self.weave_fs_duration, self.weave_fs_expires, now)
	end

	-- Era-base veto (audit 2026-10-19 Era §: the Era sim never casts Flame Shock):
	-- ERA without the observed SoD rune suppresses the maintain; SoD (observed)
	-- and every other family keep it. Older callers that predate the input read
	-- allowed (nil), so the old behaviour survives off-client.
	inputs.flameshock_allowed = st.family ~= "ERA" or self.weave_mw_observed == true

	-- S4 FS-collision guard: while the target's Flame Shock is inside its final
	-- MW5_FS_GUARD_SECONDS and the shock cooldown is ready, the five-stack weave is
	-- held back so the FS refresh goes first (bank S4: "hold weave if FS < 2s and
	-- shock ready"). The engine is frozen, so the gather - the only lever - narrows
	-- the availability it feeds; the stack count stays truthful above.
	if mw_active and st.weave.should_hold_mw5(inputs.flameshock_remaining,
		self.SHAMAN.is_shock_ready()) then
		inputs.mw_available = false
	end

	-- Stormstrike cooldown, GCD echo filtered (the rule matrix reads the remaining).
	-- Name-vs-id: TBC reads the NAME, Era reads the id.
	inputs.stormstrike_remaining, inputs.stormstrike_duration =
		get_guide_cooldown(spell_query(WEAVE_STORMSTRIKE_SPELL_ID, WEAVE_STORMSTRIKE_NAME))
	-- The swipe's FALLBACK length is per family (S-23 / U-09): the static slot
	-- descriptor cannot know the family at load time and the SoD build only
	-- becomes known when the MW rune is observed, so the gather refreshes the
	-- descriptor before the frame renders it (the frame reads
	-- slot.swipe_duration after the gather, on the same tick). The gathered
	-- duration above still wins when the client reports a real cooldown.
	guide_slot_stormstrike.swipe_duration = ST.SHAMAN.get_stormstrike_cooldown_seconds(self)
	-- Windfury-fishing opt-in (audit 2026-10-19 §1: every sim casts Stormstrike on
	-- cooldown): the hold only arms behind the wf-hold-tint display opt-in. Nil
	-- reads as off (nil-safe, no default-visible change without the explicit
	-- opt-in); a dedicated guide option waits on the options pass (follow-up).
	inputs.stormstrike_hold_enabled = db.show_shaman_wf_hold_tint == true

	-- Windfury ICD for the delay-if-fishing rule: seconds from the last swing, only
	-- while the imbue is up, in the family window (Era/SoD 1.5 s, elsewhere 3 s).
	-- Nil when unknown (no swing stamp, imbue down) so the engine never holds
	-- Stormstrike on a guess.
	inputs.windfury_icd_remaining = nil
	if self.weave_windfury_active and d and type(d.start) == "number" and d.start > 0 then
		inputs.windfury_icd_remaining =
			st.weave.get_windfury_icd_remaining(d.start, now, windfury_window())
	end

	-- Player mana fraction (audit 2026-10-19: SoD Shamanistic Rage <= 65%, TBC
	-- < 10%, Era Earth Shock >= 50%, Forever Nova dump > 10%). Unknown (nil) when
	-- the client cannot answer (secret regime, no UnitPower) - gated rules never
	-- prompt on a guess; ungated paths read old behaviour.
	inputs.mana_fraction = nil
	do
		local cur = api.UnitPower("player")
		local max = api.UnitPowerMax("player")
		if type(cur) == "number" and type(max) == "number" and max > 0 and cur >= 0 then
			local frac = cur / max
			if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
			inputs.mana_fraction = frac
		end
	end

	-- Shared shock cooldown (audit 2026-10-19: the SoD sim alternates Earth Shock
	-- and Molten Blast on the shock global). Rank-agnostic name read with the same
	-- GCD-echo filter; unknown reads ready (is_off_cooldown(nil) is true), so old
	-- callers keep the ungated filler.
	if weave_flameshock_query == nil then
		weave_flameshock_query = api.GetSpellInfo(spell_query(WEAVE_FLAME_SHOCK_BASE_SPELL_ID, WEAVE_FLAME_SHOCK_NAME)) or false
	end
	inputs.shock_remaining =
		get_guide_cooldown(weave_flameshock_query or spell_query(WEAVE_FLAME_SHOCK_BASE_SPELL_ID, WEAVE_FLAME_SHOCK_NAME))

	-- Fire Nova cooldown, GCD echo filtered (the rule matrix reads the remaining).
	inputs.firenova_remaining, inputs.firenova_duration =
		get_guide_cooldown(spell_query(WEAVE_FIRE_NOVA_SPELL_ID, WEAVE_FIRE_NOVA_NAME))

	-- Wrath top-parse cooldowns (research docs/research/rotations_wrath.md #1-2 and
	-- #12): known-gated, so an unconfirmed id feeds nil (never prompts) on every
	-- family. TBC/Era-base never know these spells, so their feeds stay nil and the
	-- old chain runs byte-identical - except where the SoD name feeds below
	-- re-enable them. Every field is still written on every call.
	inputs.fireele_remaining, inputs.fireele_duration =
		get_guide_cooldown_known(WEAVE_FIRE_ELEMENTAL_SPELL_ID, WEAVE_FIRE_ELEMENTAL_NAME)
	inputs.feralspirit_remaining, inputs.feralspirit_duration =
		get_guide_cooldown_known(WEAVE_FERAL_SPIRIT_SPELL_ID, WEAVE_FERAL_SPIRIT_NAME)
	inputs.lavalash_remaining, inputs.lavalash_duration =
		get_guide_cooldown_known(WEAVE_LAVA_LASH_SPELL_ID, WEAVE_LAVA_LASH_NAME)

	-- SoD name feeds (audit 2026-10-19 SoD §2: Feral Spirit / Lava Lash never
	-- prompted - the Wrath ids never resolve on SoD). ERA clients that have
	-- observed the MW rune aura (the SoD signal - Era-base never observes it)
	-- resolve by English name; every other family keeps the id gate above
	-- byte-identical. The answered name feeds the rank-agnostic cooldown read
	-- (the HUD's hud_slot_name convention), so whatever rank the rune teaches is
	-- counted.
	do
		if inputs.feralspirit_remaining == nil and st.family == "ERA"
			and self.weave_mw_observed == true then
			local named = self.SHAMAN.resolve_named_spell(self, "feralspirit")
			if named then
				inputs.feralspirit_remaining, inputs.feralspirit_duration =
					get_guide_cooldown(named.name)
			end
		end
		if inputs.lavalash_remaining == nil and st.family == "ERA"
			and self.weave_mw_observed == true then
			local named = self.SHAMAN.resolve_named_spell(self, "lavalash")
			if named then
				inputs.lavalash_remaining, inputs.lavalash_duration =
					get_guide_cooldown(named.name)
			end
		end
	end

	-- Shamanistic Rage (audit 2026-10-19: SoD #3 at mana <= 65%, TBC top-group at
	-- mana < 10%, Wrath #5 on cooldown/line-up with no mana gate). Wrath and TBC
	-- feed the id gate; SoD (ERA + observed MW rune) feeds by name (its rune id
	-- 425336 is not the TBC 30823). Every other shape feeds nil (never prompts on
	-- a guess); the threshold travels with the feed, so a nil feed is inert.
	inputs.sr_remaining, inputs.sr_duration, inputs.sr_mana_threshold = nil, nil, nil
	do
		local guide = st.shaman_guide
		if st.family == "WRATH" then
			inputs.sr_remaining, inputs.sr_duration =
				get_guide_cooldown_known(WEAVE_SR_SPELL_ID, WEAVE_SR_NAME)
		elseif st.family == "TBC" then
			inputs.sr_remaining, inputs.sr_duration =
				get_guide_cooldown_known(WEAVE_SR_SPELL_ID, WEAVE_SR_NAME)
			inputs.sr_mana_threshold = guide and guide.SR_MANA_THRESHOLD_TBC or 0.10
		elseif st.family == "ERA" and self.weave_mw_observed == true then
			local named = self.SHAMAN.resolve_named_spell(self, "shamanisticrage")
			if named then
				inputs.sr_remaining, inputs.sr_duration = get_guide_cooldown(named.name)
			end
			inputs.sr_mana_threshold = guide and guide.SR_MANA_THRESHOLD_SOD or 0.65
		end
	end

	-- Molten Blast (audit 2026-10-19 SoD §2: no slot at all - sim unconditional
	-- filler below Earth Shock). The rune has no cooldown to ride: the feed is 0
	-- (ready) while the spell is known, nil while unknown. Wrath+ id gate, SoD
	-- (ERA) name fallback; nil everywhere else (never prompts on a guess).
	inputs.moltenblast_remaining, inputs.moltenblast_duration = nil, nil
	do
		local known = api.is_spell_known(spell_query(WEAVE_MOLTEN_BLAST_SPELL_ID, WEAVE_MOLTEN_BLAST_NAME))
		if not known and st.family == "ERA" and self.weave_mw_observed == true then
			known = self.SHAMAN.resolve_named_spell(self, "moltenblast") ~= nil
		end
		if known then
			inputs.moltenblast_remaining = 0
		end
	end

	-- Multi-target Chain Lightning (audit 2026-10-19 §4: SoD MW >= 4 with 2+
	-- targets). SKELETON: the enemy-count sensor does not exist yet, so the feed
	-- stays nil and the rule stays dead (pinned). The wiring waits on a lane that
	-- can add the compat target-count probe (follow-up).
	inputs.target_count = nil

	-- Clearcasting proc (audit 2026-10-19 Forever §: free Fire Nova on Elemental
	-- Focus). The aura scan owns the flag; the gather reads it verbatim.
	inputs.clearcasting_active = self.weave_clearcasting == true

	-- Fire Elemental uptime guard (audit 2026-10-19 TBC §: the sim suppresses Fire
	-- Nova while the Elemental holds the fire slot). The SUCCEEDED stamp counts
	-- the uptime window; the live fire-slot clock confirms it: an affirmatively
	-- emptied slot clears the stale stamp, a swapped (non-FE) slot clears it too,
	-- an unreadable slot trusts the stamp (the commit is real, not a guess). Nil
	-- when no drop is known (never suppresses on a guess).
	inputs.fireele_active = nil
	do
		if type(self.weave_fireele_last_drop) == "number" and self.weave_fireele_last_drop > 0 then
			local fe_left = st.weave.get_fireele_remaining(self.weave_fireele_last_drop, now)
			if type(fe_left) == "number" and fe_left > 0 then
				local have, totem_name, _, _, _, _, spell_id =
					api.GetTotemInfo(WEAVE_TOTEM_SLOTS.FIRE)
				if have == nil then
					inputs.fireele_active = true
				elseif have == false then
					self.weave_fireele_last_drop = nil
					inputs.fireele_active = false
				elseif is_fireele_totem(totem_name) or is_fireele_totem(spell_id) then
					inputs.fireele_active = true
				else
					self.weave_fireele_last_drop = nil
					inputs.fireele_active = false
				end
			elseif fe_left == 0 then
				self.weave_fireele_last_drop = nil
				inputs.fireele_active = false
			end
		end
	end

	-- The water-totem clock (S-20 / U-10): the Call of the Elements line's feed.
	-- The reader answers the seconds left on the water totem (0 when the slot
	-- is affirmatively empty - the drop is due then) and the totu's full length;
	-- an unreadable slot feeds nil on both (unknown-hides - the engine's rule
	-- never prompts on a guess). The feed is live on every classic family (the
	-- client owns slot 3 everywhere); the RULE is WRATH-only, because only the
	-- Wrath enhancement APLs rank the line.
	inputs.water_remaining = nil
	inputs.water_duration = nil
	local water_remaining, water_duration = self.SHAMAN.get_water_totem_clock(self, now)
	inputs.water_remaining = water_remaining
	inputs.water_duration = water_duration

	-- The APL UTILITY layer's feeds (bench/rotation_gap_vs_apl_2026-10-20.md §5):
	-- the EARTH totem slot clock (the Strength of Earth Totem upkeep), the WATER
	-- slot clock on TBC (where the water slot carries Mana Spring), the Bloodlust
	-- cooldown on Wrath and the Frost Shock cooldown on TBC. Every field is
	-- written on every call, so no stale value survives. An unknown read stays
	-- nil: the engine never prompts on a guess (unknown-hides).
	--
	-- The Strength of Earth read: the client's EARTH totem slot (the client's own
	-- slot map - Constants.lua EARTH_TOTEM_SLOT = 2). 0 = the slot is
	-- affirmatively empty (the drop is due), the seconds left while a totem is
	-- up, nil = unknown. The engine's rule 8a decides which family reads it (and
	-- the SoD MW latch keeps the ERA token's SoD build silent - the SoD build
	-- runs no Strength of Earth rotation row).
	inputs.strength_of_earth_remaining = nil
	local earth_remaining = ST.SHAMAN.get_totem_slot_clock(self, WEAVE_TOTEM_SLOTS.EARTH, now)
	inputs.strength_of_earth_remaining = earth_remaining
	-- The Mana Spring read (TBC only): the water slot clock. On TBC the water
	-- slot carries Mana Spring (the TBC APL's Totems group row 4); the SoD and
	-- Forever Mana Spring rows are PRE-PULL rows (HU-12), so no other family
	-- reads this input.
	inputs.mana_spring_remaining = nil
	if st.family == "TBC" then
		inputs.mana_spring_remaining = inputs.water_remaining
	end
	-- The Bloodlust cooldown (Wrath only): the client cooldown behind the known
	-- gate, so a client without the spell never sees the prompt.
	inputs.bloodlust_remaining = nil
	if st.family == "WRATH" then
		local bloodlust_remaining = get_guide_cooldown_known(
			ST.SHAMAN.APL_UTILITY.bloodlust.ids.WRATH,
			ST.SHAMAN.APL_UTILITY.bloodlust.name)
		inputs.bloodlust_remaining = bloodlust_remaining
	end
	-- The Frost Shock cooldown (TBC only): the TBC APL's ALTERNATIVE shock
	-- filler. The CHOICE itself is a policy input (the APL's "Filler Shock"
	-- variable): the class reads the player's own option (db.guide_filler_shock,
	-- the widget in option_tables.lua, the default in config_presets.lua) and
	-- states the choice ONLY when the player picked Frost Shock - a nil choice
	-- is the APL's DEFAULT (Earth Shock), so a fresh profile behaves exactly as
	-- before and no family but TBC ever sees the token.
	inputs.frostshock_remaining = nil
	inputs.filler_shock = nil
	if st.family == "TBC" then
		inputs.frostshock_remaining = get_guide_cooldown_known(
			ST.SHAMAN.APL_UTILITY.frostshock.ids.TBC,
			ST.SHAMAN.APL_UTILITY.frostshock.name)
		-- The engine owns the token; without the engine module there is nothing
		-- to consume the choice (the guard keeps a flavor without it inert).
		local filler_guide = st.shaman_guide
		if filler_guide and db.guide_filler_shock == ST.SHAMAN.FILLER_SHOCK_OPTION_FROST then
			inputs.filler_shock = filler_guide.FILLER_SHOCK_FROST
		end
	end

	-- Magma maintain (Wrath #10, TBC default filler): WRATH + TBC fed. The stamp
	-- commits on Magma SUCCEEDED and reconciles with the fire-slot clock; an
	-- affirmatively empty fire slot feeds due (0), an unknown read feeds nil
	-- (never prompts). Every other family stays nil (byte-identical to the old
	-- stub). Every field is still written on every call, so no stale value
	-- survives.
	inputs.magma_remaining = nil
	inputs.magma_duration = nil
	if st.family == "WRATH" or st.family == "TBC" then
		local slot_empty = self.SHAMAN.refresh_magma_from_totems(self)
		if slot_empty then
			inputs.magma_remaining = 0
			inputs.magma_duration = WEAVE_MAGMA_SWIPE_SECONDS
		else
			inputs.magma_remaining =
				st.weave.get_magma_remaining(self.weave_magma_last_drop, now)
			if inputs.magma_remaining ~= nil then
				inputs.magma_duration = WEAVE_MAGMA_SWIPE_SECONDS
			end
		end
	end
	inputs.magma_refresh = st.shaman_guide and st.shaman_guide.MAGMA_REFRESH_DEFAULT or 3

	-- Fight clock (main.lua PLAYER_REGEN_DISABLED stamp, api.get_time()
	-- domain): seconds since combat-enter for the Searing fight-age gate
	-- (Era > 20 s, SoD P6 > 30 s per the audit). Nil when the stamp is
	-- unknown (out of combat, or a clock that never answered) - the future
	-- rule never prompts on a guess. Unknown-hides: no rule reads this yet.
	inputs.fight_elapsed = nil
	do
		local start = self.fight_start_at
		if type(start) == "number" and start > 0 and type(now) == "number" then
			local elapsed = now - start
			if elapsed < 0 then elapsed = 0 end
			inputs.fight_elapsed = elapsed
		end
	end

	-- Searing maintain (audit 2026-10-19 Era/SoD/Forever: the sims keep
	-- Searing down past the fight-age gate above). READER feed: the stamp
	-- commits on Searing SUCCEEDED and reconciles with the fire-slot clock;
	-- an affirmatively empty fire slot feeds down (the totem is due), an
	-- unknown read feeds nil (never prompts). No duration is shipped (no
	-- confirmed value in scope), so the feed is elapsed-since-drop plus the
	-- down flag. The engine's rule 9b reads the down flag (with the fight
	-- clock and the SoD latch below) - the maintain is live on the ERA token
	-- (Era-base 20 s, SoD 30 s).
	-- Every field is still written on every call, so no stale value survives.
	inputs.searing_elapsed = nil
	inputs.searing_down = nil
	do
		local slot_empty, holding = self.SHAMAN.refresh_searing_from_totems(self)
		if slot_empty == true then
			inputs.searing_down = true
		elseif holding == true then
			-- The slot affirmatively holds Searing: not due, elapsed counts
			-- the live drop.
			inputs.searing_down = false
			local stamp = self.weave_searing_last_drop
			if type(stamp) == "number" and stamp > 0 and type(now) == "number" then
				inputs.searing_elapsed = math.max(0, now - stamp)
			end
		elseif holding == false then
			-- The slot affirmatively holds something else: a re-drop would
			-- overwrite it, so never due.
			inputs.searing_down = false
		else
			-- Unreadable slot (FE-guard shape): trust a known commit, guess
			-- nothing otherwise.
			local stamp = self.weave_searing_last_drop
			if type(stamp) == "number" and stamp > 0 and type(now) == "number" then
				inputs.searing_elapsed = math.max(0, now - stamp)
				inputs.searing_down = false
			end
		end
	end
	-- The Searing maintain is known-gated like every other maintain in this
	-- module (the Fire Elemental, Magma, Lava Lash and Molten Blast feeds all
	-- carry the gate): the Searing Totem is a talent on Era/SoD, so a player
	-- without it must never be prompted. The probe asks for the CLIENT'S OWN
	-- resolved id (the shipped id is the Forever sim's and never resolves on the
	-- classic-line clients); an unknown id answers false, so the feed stays
	-- silent rather than prompting on a guess.
	if not api.is_spell_known(spell_query(guide_slot_searing.spell_id, WEAVE_SEARING_TOTEM_NAME)) then
		inputs.searing_down = nil
	end

	-- The SoD MW-rune latch (the ERA token carries both the Era-base build and the
	-- SoD build): the engine's Searing gate reads it to pick the fight-age gate
	-- (Era 20 s, SoD 30 s). Written on every call, so a stale latch never
	-- survives. Unknown (nil) reads as Era-base.
	inputs.mw_observed = self.weave_mw_observed == true

	-- Lightning Shield maintain (audit 2026-10-19 §2.6 S-19: the three wowsims/wotlk
	-- enhancement APLs maintain it iff inactive, above Lava Lash; the SoD
	-- phase_6.apl.json i=8 row and the Forever default.apl.json i=6 row cast
	-- 10432 the same way). The family gate is the engine's helper: WRATH,
	-- FOREVER and the SoD build on the ERA token (the MW-rune latch separates
	-- SoD from Era-base; the Era-base APL and the TBC APL run no Lightning
	-- Shield row at all).
	-- The read is free: the player's aura walk already looks for the Lightning /
	-- Water Shield auras (the charge row), so the maintain rides that answer.
	-- Tri-state: true = due (the walk ran and NO shield aura is up - a Water
	-- Shield build never sees the prompt, because its own aura is up), false = a
	-- shield aura is up (nothing to do), nil = unknown (the walk has not run yet,
	-- or the client may hide auras) - unknown never prompts.
	-- KNOWN GATE: the Lightning Shield is a TALENT, so a build without it must
	-- never be prompted (the Searing maintain's gate shape). The probe asks the
	-- CLIENT'S OWN resolved id - the guide slot's id, re-pointed by NAME at
	-- post_init - so a wrong id stays silent instead of prompting wrong, and an
	-- unreadable answer keeps the maintain silent (unknown-hides).
	inputs.lightningshield_due = nil
	local ls_guide = st.shaman_guide
	if ls_guide and ls_guide.get_lightningshield_family_gate
		and ls_guide.get_lightningshield_family_gate(st.family, self.weave_mw_observed == true)
		and self.weave_shield_scanned == true
		and api.is_spell_known(spell_query(guide_slot_lightningshield.spell_id, "Lightning Shield")) then
		local secret_probe = api.auras_may_be_secret
		if type(secret_probe) ~= "function" or secret_probe() ~= true then
			inputs.lightningshield_due = (self.weave_shield_type == nil)
		end
	end

	-- Era static totem maintain (G2, audit 2026-10-19 Era §: WF 10614 refresh
	-- first, GoA 10627 when inactive, both above Stormstrike). Era-base only:
	-- family ERA without the SoD MW-rune latch (SoD runs no totem maintain per
	-- its sim; TBC twists through rule 7 instead; Wrath/Forever run none).
	-- Both share the air slot, so one shaman holds one: Windfury is due on an
	-- affirmatively emptied slot or when it must take the slot back from Grace
	-- of Air (the sim's priority); Grace of Air is the fallback air totem,
	-- due only on an affirmatively emptied slot while Windfury is unknown (so
	-- it can never overwrite a known Windfury and thrash). A third air totem
	-- (Nature Resistance and friends) is unmodeled and left alone; an
	-- unreadable slot feeds nil (never prompts on a guess). The buff-keyed
	-- WF refresh (imbue 10611 <= 1.5 s) needs a buff-expiry read that does not
	-- exist - filed remainder (F2 class) - so presence is the whole feed.
	-- Every field is still written on every call, so no stale value survives.
	inputs.wftotem_remaining = nil
	inputs.goatotem_remaining = nil
	if st.family == "ERA" and self.weave_mw_observed ~= true then
		local wf_known =
			api.is_spell_known(spell_query(WEAVE_WF_TOTEM_SPELL_ID, WEAVE_WF_TOTEM_NAME))
		local goa_known =
			api.is_spell_known(spell_query(WEAVE_GOA_TOTEM_SPELL_ID, WEAVE_GOA_TOTEM_NAME))
		local have, totem_name, _, _, _, _, spell_id =
			api.GetTotemInfo(WEAVE_TOTEM_SLOTS.AIR)
		if have ~= nil then
			local wf_up = is_wf_totem(totem_name) or is_wf_totem(spell_id)
			local goa_up = is_goa_totem(totem_name) or is_goa_totem(spell_id)
			if have == false then
				-- Affirmatively empty: WF first (the sim's priority), GoA
				-- only as the fallback while Windfury is unknown.
				if wf_known then
					inputs.wftotem_remaining = 0
				elseif goa_known then
					inputs.goatotem_remaining = 0
				end
			elseif goa_up and wf_known and not wf_up then
				-- Sim priority: Windfury takes the slot back from Grace of
				-- Air. Every other held state reads not-due: the sim's own
				-- pair holding the slot, or a third air totem (Nature
				-- Resistance and friends) the sim never models - the guide
				-- leaves those alone and never fights the player's drop.
				inputs.wftotem_remaining = 0
			end
			-- Otherwise the sim's pair holds the slot (WF up, or GoA up
			-- while Windfury is unknown): not due.
		end
	end

	-- Totem twist (TBC Enhancement only): the live last-drop stamp - SUCCEEDED
	-- commits plus the air-slot totem-clock reconciliation - fed through the
	-- weave.lua timing model into the engine's rule 7. Every other family stays nil
	-- (byte-identical to the old stub); nil means unknown and the engine never
	-- prompts on a guess. Every field is still written on every call, so no stale
	-- value survives. FOREVER is excluded by the family gate (party-buff totem
	-- model: totems coexist with imbues, nothing to alternate).
	inputs.twist_remaining = nil
	inputs.twist_mana_threshold = nil
	if st.weave.is_totem_twist_family(st.family) then
		self.SHAMAN.refresh_twist_from_totems(self)
		inputs.twist_remaining =
			st.weave.get_totem_twist_remaining(self.weave_twist_last_drop, now)
		if st.weave.get_twist_mana_threshold then
			inputs.twist_mana_threshold = st.weave.get_twist_mana_threshold(st.family)
		end
	end

	-- The refresh threshold from the options (0-10 s). The shipped default is 0
	-- (config_presets.lua: every sim re-applies Flame Shock only when the dot is
	-- INACTIVE, so 0 = expiry-only) and the gather's own fallback now matches it:
	-- a missing option falls back to the shipped default, never to the old 3 s
	-- clip (the sim-exact value is 0 - the 3 clipped ~3 s of dot every cycle).
	inputs.flameshock_refresh = db.guide_flameshock_refresh or 0
	return inputs
end

-- The class's FULL guide slot vocabulary (the display order the frame builds
-- its icons in). The FAMILY sets are cut from this very list (see
-- ST.SHAMAN.family_guide_slots below), so the display order and the family's
-- order can never drift apart, and the class's full vocabulary stays readable
-- on its own (the frame's own icon set).
--
-- The list lives on the class table instead of inline in the guide
-- constructor: this chunk is at Lua 5.1's 200-local limit (199 locals), so a
-- new file-scope local would not load - the family cut needs the list as data.
ST.SHAMAN.GUIDE_SLOTS = {
	guide_slot_stormstrike, guide_slot_flameshock, guide_slot_weave,
	guide_slot_firenova, guide_slot_earthshock, guide_slot_twist,
	guide_slot_feralspirit, guide_slot_fireele, guide_slot_magma,
	guide_slot_lavalash, guide_slot_shamanisticrage,
	guide_slot_chainlightning, guide_slot_moltenblast,
	guide_slot_wftotem, guide_slot_goa,
	guide_slot_lightningshield, guide_slot_searing,
	{ key = "coe", spell_id = WEAVE_COE_SPELL_ID },
	ST.SHAMAN.APL_SLOTS.bloodlust,
	ST.SHAMAN.APL_SLOTS.strength_of_earth,
	ST.SHAMAN.APL_SLOTS.mana_spring,
	ST.SHAMAN.APL_SLOTS.frostshock,
}

ST.SHAMAN.guide = {
	slots = ST.SHAMAN.GUIDE_SLOTS,

	-- Live inputs: the gather above, verbatim, into the caller's reused table.
	gather = function(self, out)
		return ST.SHAMAN.gather_guide_inputs(self, out)
	end,

	-- Pure: the frozen shaman rule matrix (st.shaman_guide in shaman_guide.lua);
	-- guarded so a flavor without that module stays inert rather than erroring.
	evaluate = function(inputs, out)
		if st.shaman_guide and st.shaman_guide.evaluate then
			return st.shaman_guide.evaluate(inputs, out)
		end
		return out
	end,

	-- Static captions (defaults; the RIDE/HOLD text rides out.hold_text).
	labels = { next_action = "Next action:", hold = "HOLD", ride = "RIDE" },
}

--=========================================================================================
-- Cooldown HUD: shaman slots and the live state provider
--=========================================================================================
-- The slot set mirrors the Next Action Guide's ORIGINAL six slots (the Wrath
-- additions above have no HUD mirror yet: hud_state.lua pins the eight-slot row,
-- so the mirror waits on a lane that can update that suite - deferred; the Era
-- static totems wftotem/goa are likewise guide-only: their ids are UNCONFIRMED
-- and the HUD suite is owned by another lane - deferred, same precedent), plus
-- the three maintain mirrors this lane landed (lightningshield, searing - the
-- guide slots 16 and 17 - and coe - S-20 / U-10, the guide slot 18) and the two
-- trinket slots the HUD serves itself. The
-- descriptor and provider contracts are frozen in hud.lua's header
-- comment; the "trinket" slots need no provider entry.
--
-- The three maintain mirrors are DISPLAY-ONLY: none has a cooldown to ride (a
-- shield buff, a persistent totem and a totem-multi-cast drop), so their state
-- is the upkeep cue - the icon glows while the cast / drop is needed. They hide
-- unless their hud_show_<key> toggle reads exactly true (nil = off: the HUD
-- treats a nil toggle as wanted, so the provider-level hide is the
-- no-default-visible gate; the options pass owns the default + the widget -
-- filed). The Call of the Elements mirror also counts the water totem down
-- (the S-20 / U-10 water clock).
--
-- Rank notes: the rank-1 ids ship as the icon fallback (the spell art is
-- rank-invariant), while the provider reads cooldowns by the client's own localized
-- name (hud_slot_name), so whatever rank the player knows is what is counted - the
-- paladin's cooldown_spell-free convention from classes/paladin.lua. Stormstrike
-- (17364), Flame Shock (8050), Fire Nova Totem (1535) and Earth Shock (8042) are the
-- ids the rest of this module already reads; Lightning Bolt (403) is the weave
-- catalogue's rank-1 fallback. Windfury Totem (8512) mirrors the guide's twist slot
-- and is UNCONFIRMED on 2.5.6 (see the WEAVE_WINDFURY_TOTEM_SPELL_ID note at the top
-- of this file) - confirm with GetSpellInfo in-game before release.
-- The two maintain mirrors (audit 2026-10-19 §2.6 S-19 / S-17), declared inline
-- so the post_init resolver can re-point their icon (the ids are UNCONFIRMED -
-- the client's own spell data answers by name).
ST.SHAMAN.HUD_SLOTS = {
	{ key = "stormstrike", title = "Stormstrike", kind = "spell", spell = 17364 },
	{ key = "flameshock", title = "Flame Shock", kind = "spell", spell = 8050 },
	{ key = "weave", title = "Lightning Bolt", kind = "spell", spell = 403 },
	{ key = "firenova", title = "Fire Nova Totem", kind = "spell", spell = 1535 },
	{ key = "earthshock", title = "Earth Shock", kind = "spell", spell = 8042 },
	{ key = "twist", title = "Windfury Totem", kind = "spell", spell = 8512 },
	-- The maintain mirrors (audit 2026-10-19 §2.6 S-19 / S-17, plus S-20 / U-10).
	-- Appended before the self-served trinkets so they stay last. All hide
	-- unless their hud_show_<key> toggle reads exactly true (nil = off; the HUD
	-- treats a nil toggle as wanted, so the provider-level hide is the
	-- no-default-visible gate; options own the widget + the default - filed
	-- follow-up).
	{ key = "lightningshield", title = "Lightning Shield", kind = "spell", spell = 49281 },
	{ key = "searing", title = "Searing Totem", kind = "spell", spell = WEAVE_SEARING_TOTEM_SPELL_ID },
	-- The Call of the Elements mirror (S-20 / U-10): the water-totem clock. It
	-- hides like the other two maintain mirrors (its hud_show_coe toggle reads
	-- exactly true - nil = off, so the provider-level hide is the
	-- no-default-visible gate; the options pass owns the default + the widget -
	-- filed) and it counts the water totem down.
	{ key = "coe", title = "Call of the Elements", kind = "spell", spell = WEAVE_COE_SPELL_ID },
	{ key = "trinket1", title = "Trinket 1", kind = "trinket", inv_slot = 13 },
	{ key = "trinket2", title = "Trinket 2", kind = "trinket", inv_slot = 14 },
}

-- One reused state table: the HUD reads it immediately and never keeps a reference
-- (see the frozen contract in hud.lua), so there is no per-tick allocation here.
ST.SHAMAN.hud_state = {}

-- Localized HUD slot spell names, resolved lazily (name-based cooldown and probe
-- lookups are rank-agnostic). Resolved values are cached; a failed resolution (spell
-- data not ready yet) is retried on the next call, like the guide's filler names in
-- classes/paladin.lua.
-- Name-vs-id: TBC answers the literal English name (never a bare id); Era
-- resolves the slot id. Nil-safe: an unanswered spell stays nil (unknown-hides).
local hud_slot_names = {}
local HUD_SLOT_TBC_NAMES = {
	stormstrike = WEAVE_STORMSTRIKE_NAME,
	flameshock = WEAVE_FLAME_SHOCK_NAME,
	weave = "Lightning Bolt",
	firenova = WEAVE_FIRE_NOVA_NAME,
	earthshock = WEAVE_EARTH_SHOCK_NAME,
	twist = WEAVE_WINDFURY_TOTEM_NAME,
	lightningshield = "Lightning Shield",
	searing = WEAVE_SEARING_TOTEM_NAME,
}

local function hud_slot_name(slot)
	local name = hud_slot_names[slot.key]
	if not name then
		if st.family == "TBC" then
			name = HUD_SLOT_TBC_NAMES[slot.key]
				or (slot.spell and api.GetSpellInfo(slot.spell))
				or nil
		else
			name = slot.spell and api.GetSpellInfo(slot.spell) or nil
		end
		if name then
			hud_slot_names[slot.key] = name
		end
	end
	return name
end

-- Full cooldown lengths (seconds) for the swipe when the client reports no real
-- cooldown of its own (TBC values; NEEDS IN-CLIENT CONFIRMATION on 2.5.6 - the swipe
-- length only matters while a real cooldown is running, which always carries the
-- client-reported length instead). The shocks share their 6 s shock cooldown; the
-- weave cast and the twist skeleton carry 0. Stormstrike is NOT here: its length
-- is per family (S-23 / U-09), so it is read live from
-- ST.SHAMAN.get_stormstrike_cooldown_seconds (the same table the guide slot's
-- fallback uses).
local HUD_COOLDOWN_FALLBACK = {
	flameshock = 6,
	weave = 0,
	firenova = 15,
	earthshock = 6,
	twist = 0,
}

-- Slots that never borrow the GCD swipe (the paladin's judgement/wings rule in
-- classes/paladin.lua). Every shaman ROTATIONAL slot is rotational, so the set
-- only holds the maintain mirrors (a shield buff, a persistent totem and the
-- totem-multi-cast drop have no cast window to show - the GCD swipe would read
-- as a cooldown they do not have).
local HUD_SKIP_GCD = {
	lightningshield = true,
	searing = true,
	coe = true,
}

-- The two maintain mirrors' HUD icons: the ids ship UNCONFIRMED, so the client's
-- own spell data answers by name (the classic GetSpellInfo answers a name query
-- with the spell's id in its 7th return). On TBC the ICON resolves by NAME (a bare
-- id leaves it blank there - the name-vs-id rule, bench/lessons.md), on every
-- other family by the resolved id. Called once from post_init, before the HUD
-- builds its icons.
function ST.SHAMAN.resolve_hud_slot_icons(self)
	local slots = ST.SHAMAN.HUD_SLOTS
	for i = 1, #slots do
		local slot = slots[i]
		if slot.key == "lightningshield" then
			slot.spell = (st.family == "TBC") and HUD_SLOT_TBC_NAMES.lightningshield
				or guide_slot_lightningshield.spell_id
		elseif slot.key == "searing" then
			slot.spell = (st.family == "TBC") and HUD_SLOT_TBC_NAMES.searing
				or guide_slot_searing.spell_id
		end
	end
end

-- The running GCD (classes/paladin.lua hud_gcd_remaining, verbatim).
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

-- Remaining time and full duration of one shaman ability cooldown: the client's own
-- reading by localized name (rank-agnostic), with the GCD echo filtered (a reading
-- of 1.51 s or less is the running GCD, never one of these abilities' cooldowns -
-- the class's own get_guide_cooldown rule). A missing reading means ready.
-- The swipe's full length when the client reports no real cooldown of its own.
-- Stormstrike reads the PER-FAMILY sim length (S-23 / U-09: Era 20 / SoD 6 /
-- TBC 10 / Wrath 8) instead of one static number, so the mirror can never show
-- another family's length; every other slot keeps the static table.
function ST.SHAMAN.get_hud_cooldown_fallback(self, slot)
	if slot.key == "stormstrike" then
		return ST.SHAMAN.get_stormstrike_cooldown_seconds(self)
	end
	return HUD_COOLDOWN_FALLBACK[slot.key] or 0
end

local function hud_ability_cooldown(self, slot, now)
	local query = hud_slot_name(slot) or slot.spell
	local start_time, duration = api.GetSpellCooldown(query)
	if start_time and duration and duration > 1.51 then
		local remaining = start_time + duration - now
		if remaining > 0 then
			return remaining, duration
		end
	end
	return 0, ST.SHAMAN.get_hud_cooldown_fallback(self, slot)
end

-- IsUsableSpell's second return (classes/paladin.lua hud_no_mana, verbatim):
-- through compat's cross-client IsSpellUsable wrapper. A client with no probe
-- reports unknown, rendered as "no tint".
local function hud_no_mana(slot)
	local name = hud_slot_name(slot)
	local ok, _, insufficient = pcall(api.IsSpellUsable, name or slot.spell)
	return ok and insufficient == true
end

-- WA "spellInRange == 0" (classes/paladin.lua hud_out_of_range, verbatim):
-- api.IsSpellInRange returns 0 out of range, 1/true in range, nil unknown (treated
-- as "not out of range").
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

-- The class provider (frozen contract, hud.lua header): the paladin's ability_state
-- mapping (hud.lua:418-453) re-expressed for the shaman slots. Stormstrike glows
-- the moment it is ready, in combat (the paladin's Avenging Wrath rule).
function ST.SHAMAN.get_hud_state(self, slot, now)
	local s = ST.SHAMAN.hud_state
	s.remaining, s.duration, s.start, s.reverse = nil, nil, nil, nil
	s.text_remaining, s.desaturate, s.usable, s.in_range = nil, nil, nil, nil
	s.glow, s.count, s.texture, s.hidden = nil, nil, nil, nil
	now = now or api.get_time()
	-- The maintain mirrors (audit 2026-10-19 §2.6 S-19 / S-17 and S-20): display-
	-- only, no cooldown to ride (they are in HUD_SKIP_GCD). Each hides unless its
	-- hud_show_<key> toggle reads exactly true - the HUD treats a nil toggle as
	-- wanted, so this provider-level hide is the no-default-visible gate (the
	-- druid Claw shape; the options pass owns the default + the widget - filed).
	-- The upkeep cue is the glow: it lights while the cast / drop is needed, in
	-- combat (the Stormstrike "ready" rule). An unknown read draws nothing.
	if slot.key == "lightningshield" or slot.key == "searing" or slot.key == "coe" then
		local hud_db = self:get_class_table()
		if type(hud_db) ~= "table" or hud_db["hud_show_" .. slot.key] ~= true then
			s.hidden = true
			return s
		end
		if slot.key == "lightningshield" then
			-- The player's own shield aura (the charge row's walk): the cast is
			-- needed while NO shield aura is up. A Water Shield build never sees
			-- the cue - its own aura is up.
			if self.weave_shield_scanned ~= true then
				s.hidden = true
				return s
			end
			s.glow = (self.weave_shield_type == nil and self.in_combat == true) or false
		elseif slot.key == "coe" then
			-- The water-totem clock (S-20 / U-10): the drop is needed while the
			-- water totem is under the APL's 20 s threshold (empty slot = due).
			-- An unreadable slot draws nothing (never a guess). The countdown
			-- rides the water totem's own remaining time.
			local remaining, duration = self.SHAMAN.get_water_totem_clock(self, now)
			if remaining == nil then
				s.hidden = true
				return s
			end
			s.remaining = remaining
			s.duration = duration
			s.text_remaining = remaining
			local gate = st.shaman_guide and st.shaman_guide.COE_WATER_REFRESH_SECONDS or 20
			s.glow = (remaining < gate and self.in_combat == true) or false
		else
			-- The fire slot's occupancy: the drop is needed while the slot is
			-- affirmatively empty. An unreadable slot draws nothing (never a
			-- guess); another totem in the slot means the Searing is not due.
			-- The known gate matches the guide's (the Searing Totem is a talent
			-- on Era/SoD): a player without it is never cued. Fail-visible:
			-- only a confirmed "not_known" hides; "unknown" (the client could
			-- not answer) shows, and the next tick asks again.
			local sear_known, sear_state = api.is_spell_known_state(spell_query(guide_slot_searing.spell_id, WEAVE_SEARING_TOTEM_NAME))
			if sear_known ~= true and sear_state ~= "unknown" then
				s.hidden = true
				return s
			end
			local have_totem = api.GetTotemInfo(WEAVE_TOTEM_SLOTS.FIRE)
			if have_totem == nil then
				s.hidden = true
				return s
			end
			s.glow = (have_totem == false and self.in_combat == true) or false
		end
		return s
	end
	local remaining, full = hud_ability_cooldown(self, slot, now)
	local on_cd = remaining > 0
	if on_cd then
		s.remaining = remaining
		s.duration = full
		s.text_remaining = remaining
		s.desaturate = true
	elseif not HUD_SKIP_GCD[slot.key] then
		-- The GCD shows as a swipe (WA "show GCD"); the HUD's 2 s rule keeps its
		-- text hidden.
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

	if slot.key == "stormstrike" then
		s.glow = (remaining <= 0 and self.in_combat == true) or false
	end
	return s
end

--=========================================================================================
--=========================================================================================
-- Practice: the shaman weave drill (options Practice toggle + /st practice)
--=========================================================================================
-- The session runs how it always has: the options Practice toggle or /st practice
-- starts it and the panel icons cast the simulated spells (practice_ui.lua,
-- class-agnostic; the hunter drill rides the same flow in classes/hunter.lua).
-- This seam only keeps that flow shaman-safe and routes the shaman drill:
--   * practice_sync reports no seal state (the shaman has none to mirror), so the
--     shared bridge never stamps paladin seal fields onto a shaman session;
--     practice_ui.sync_to_addon calls it through the SHAMAN branch there, then
--     mirrors the drill swing onto the mainhand bar so the live weave marker and
--     spark render against the simulated swing.
--   * the wrappers below drive the shaman_weave drill (practice.lua harness
--     registry); the grade returns to the caller and the session scores through
--     the shared ui.score pipeline, the same entry points any caller (the
--     toggle-started session, an options tab) uses. new/begin/end mirror the
--     hunter seam (unbegun session, explicit run); the drill clock is
--     caller-owned (practice_ui carries it, tests pass synthetic swings).
-- Every entry degrades to nil/0 when the practice modules are absent (a flavor
-- without them), never an error; nothing here shows without the explicit toggle
-- (opt-in, no default-visible change). Family-independent by construction: the
-- swing clock is the caller's, cast times come from the live catalogue with the
-- harness WEAVE_DEFAULTS fallback, latency falls back to 0 - unknown reads grade
-- nil through the shell, never a guess.
function ST.SHAMAN.practice_sync(self)
	return 0
end

-- The harness drill this class practices (practice.lua registry): the key when the
-- module is loaded and carries the spec, nil otherwise (unknown-hides, the same
-- shape as the druid seam).
--
-- The key stays the RETIRED built-in ("shaman_weave") on purpose: it is the
-- routing key the shared engine reads (the panel's drill route and the engine's
-- supersession rule H.SUPERSEDED_DRILLS), and the built-in stays registered for
-- backward compatibility. The class's own session never starts it - the drill it
-- runs is the class's own (practice_drill_key below).
function ST.SHAMAN.practice_scenario_key()
	local pr = st.practice
	if pr and pr.harness and pr.harness.get_scenario
		and pr.harness.get_scenario("shaman_weave") then
		return "shaman_weave"
	end
	return nil
end

-- The drill this class's session runs: the class's OWN drill - the weave
-- decision (the same weave.lua maths, re-sourced with the Maelstrom-stack
-- condition). The retired built-in ("shaman_weave") stays registered for backward
-- compatibility and the engine delegates its grading to this drill (practice.lua
-- H.SUPERSEDED_DRILLS), so the old truth never grades a player attempt.
ST.SHAMAN.PRACTICE_DRILL_KEY = "shaman_mw_weave"

-- The class's own drill key, or nil when the class publishes no such drill
-- (unknown-hides: the session refuses rather than falling back to the retired
-- built-in).
function ST.SHAMAN.practice_drill_key()
	local key = ST.SHAMAN.PRACTICE_DRILL_KEY
	if type(key) ~= "string" or key == "" then
		return nil
	end
	local drills = ST.SHAMAN.practice_drills
	if type(drills) ~= "table" then
		return nil
	end
	for i = 1, #drills do
		local entry = drills[i]
		if type(entry) == "table" and entry.key == key
			and type(entry.grade) == "function" then
			return key
		end
	end
	return nil
end

-- The drill casts (panel icon order): Lightning Bolt and Chain Lightning weave
-- starts, graded by margin before the weave marker through the harness. Spell ids
-- ride the live weave catalogue (icon resolution only); ranks follow the client.
ST.SHAMAN.PRACTICE_CASTS = {
	{ key = "weave_lb", family = "LB", label = "Lightning Bolt" },
	{ key = "weave_cl", family = "CL", label = "Chain Lightning" },
}
ST.SHAMAN.PRACTICE_CAST_ORDER = { "weave_lb", "weave_cl" }

-- Drill cast lookup helpers (all nil-safe; unknown keys answer nil, never a guess).
function ST.SHAMAN.practice_cast_family(key)
	for i = 1, #ST.SHAMAN.PRACTICE_CASTS do
		local cast = ST.SHAMAN.PRACTICE_CASTS[i]
		if cast.key == key then
			return cast.family
		end
	end
	return nil
end

function ST.SHAMAN.practice_cast_label(key)
	for i = 1, #ST.SHAMAN.PRACTICE_CASTS do
		local cast = ST.SHAMAN.PRACTICE_CASTS[i]
		if cast.key == key then
			return cast.label
		end
	end
	return nil
end

-- Icon spell id for a drill cast, resolved through the live weave catalogue
-- (family rank, like the guide icons). Nil when the client's spell data has not
-- answered (unknown hides, the icon stays blank) - never a guessed id. Era, TBC
-- and Forever resolve through the same catalogue path the live marker uses.
function ST.SHAMAN.practice_cast_spell_id(key)
	local family = ST.SHAMAN.practice_cast_family(key)
	if family == nil then
		return nil
	end
	if ST.weave_catalog == nil then
		return nil
	end
	local entry = ST.weave_catalog[family]
	if type(entry) ~= "table" or type(entry.spell_id) ~= "number" then
		return nil
	end
	return entry.spell_id
end

-- Effective cast seconds for a drill cast: the live catalogue entry first, the
-- harness WEAVE_DEFAULTS fallback second (the scenario's own documented default),
-- nil when neither answers (the shell then grades nil, never a guess).
function ST.SHAMAN.practice_cast_seconds(key)
	local family = ST.SHAMAN.practice_cast_family(key)
	if family == nil then
		return nil
	end
	if ST.weave_catalog ~= nil then
		local entry = ST.weave_catalog[family]
		if type(entry) == "table" and type(entry.cast_seconds) == "number" then
			return entry.cast_seconds
		end
	end
	local pr = st.practice
	local defaults = pr and pr.harness and pr.harness.WEAVE_DEFAULTS
	if type(defaults) == "table" and type(defaults.effective_cast) == "number" then
		return defaults.effective_cast
	end
	return nil
end

-- Drill latency in seconds (the same world-latency read the live weave spark
-- uses); 0 when unreadable, never a throw.
function ST.SHAMAN.practice_latency_seconds()
	local world_ms = ST.latency and ST.latency.world_ms
	if type(world_ms) ~= "number" then
		return 0
	end
	return world_ms / 1000
end

-- Start a drill run: the class's OWN drill session, begun at `now`.
-- Returns the session, or nil when the drill is unavailable.
--
-- The session is the harness's own shape - the score accumulator, the lifecycle and
-- the drill's state - and the drill's TRUTH is the class's own grade function: the
-- retired built-in's model never grades a player attempt.
function ST.SHAMAN.new_practice_session(now, opts)
	local pr = st.practice
	local H = pr and pr.harness
	if not (H and H.begin_session and H.new_score and H.WEAVE_DEFAULTS) then
		return nil
	end
	local key = ST.SHAMAN.practice_drill_key()
	if key == nil then
		return nil
	end
	opts = opts or {}
	local defaults = H.WEAVE_DEFAULTS
	local state = {
		swing_duration = opts.swing_duration or defaults.swing_duration,
		effective_cast = opts.effective_cast or defaults.effective_cast,
		latency = opts.latency or defaults.latency,
		swing_remaining = nil,
	}
	local session = {
		key = key,
		spec = {
			key = key,
			class = "SHAMAN",
			event = function(sess, event_now, event_key)
				-- Grade through the class's own drill function, with the ctx the
				-- shared engine hands the drills (the session's state, the clock
				-- and the pick). Nil when the drill cannot judge the attempt.
				local drill_key = sess and sess.key or nil
				if type(drill_key) ~= "string" or drill_key == "" then
					return nil
				end
				local ctx = H.drill_context(sess.state, event_now, event_key)
				return H.practice_drill_grade(ST.SHAMAN, drill_key, ST, ctx)
			end,
			-- The weave drill keeps no tick of its own (the swing clock is
			-- caller-owned), so the tick leaves the out table untouched.
			tick = function(sess, tick_now, tick_elapsed, out)
			end,
		},
		state = state,
		score = H.new_score(),
		windows = {},
		started_at = now or 0,
		active = false,
	}
	H.begin_session(session, now, opts)
	return session
end

-- Run one drill tick through the harness (the weave_timing scenario keeps no
-- tick of its own; the swing clock is caller-owned). Returns out.
function ST.SHAMAN.tick_practice_session(session, now, elapsed, out)
	local pr = st.practice
	if not (session and pr and pr.harness and pr.harness.tick_session) then
		return out
	end
	return pr.harness.tick_session(session, now, elapsed, out)
end

-- Grade one simulated weave start at `now` against the caller-owned drill swing
-- ({ swing_duration, swing_start, swing_ends_at } in the caller's clock domain,
-- the same GetTime domain the live bar compares). The start fraction is the swing
-- position at click time; the clip is the simulated overrun past the swing end
-- through the weave model, floored at 0. Returns the S/A/B/C/D/F grade plus the
-- margin in milliseconds, or nil when the cast cannot be scored (unknown family,
-- idle session, absent shell, unresolvable cast - never a grade on a guess).
-- The caller records the grade on the session score (practice_ui feeds the
-- shared ui.score pipeline, the hunter shape).
function ST.SHAMAN.practice_cast(session, swing, now, key)
	local pr = st.practice
	if not (session and swing and pr and pr.harness and pr.harness.scenario_event
		and pr.harness.weave_marker_fraction) then
		return nil
	end
	local duration = swing.swing_duration
	if type(duration) ~= "number" or duration <= 0 then
		return nil
	end
	local start = swing.swing_start
	if type(start) ~= "number" or type(now) ~= "number" then
		return nil
	end
	local cast = ST.SHAMAN.practice_cast_seconds(key)
	if type(cast) ~= "number" then
		return nil
	end
	local latency = ST.SHAMAN.practice_latency_seconds()
	local fraction = (now - start) / duration
	-- The class's own drill grades the weave decision: the session's state carries
	-- the swing the drill reads (the drill measures the clip itself), and the pick
	-- under test is the weave. The retired built-in's model never grades here.
	local state = session.state
	if type(state) == "table" then
		state.swing_duration = duration
		state.swing_remaining = nil
		if type(swing.swing_ends_at) == "number" then
			state.swing_remaining = swing.swing_ends_at - now
		end
		state.latency = latency
		state.effective_cast = cast
		state.weave_cast_seconds = cast
		state.mw_stacks = ST.weave_mw_stacks
		state.mw_observed = ST.weave_mw_observed
	end
	local grade = pr.harness.scenario_event(session, "weave", now)
	if grade == nil then
		return nil
	end
	local marker = pr.harness.weave_marker_fraction(duration, cast, latency)
	local margin_ms = nil
	if type(marker) == "number" then
		margin_ms = (marker - fraction) * duration * 1000
		if margin_ms < 0 then
			margin_ms = 0
		end
	end
	return grade, margin_ms
end

-- End a drill run (stops the harness session). Safe on an ended or nil session.
function ST.SHAMAN.end_practice_session(session, now)
	local pr = st.practice
	if not (session and pr and pr.harness and pr.harness.end_session) then
		return false
	end
	return pr.harness.end_session(session, now)
end

-- Begin a begun-again drill run on an ended session (mirrors the paladin
-- start_fight; the score accumulator rides along). False when there is nothing
-- to begin (absent shell, malformed or already-active session).
function ST.SHAMAN.practice_begin_session(session, now, opts)
	local pr = st.practice
	if not (session and pr and pr.harness and pr.harness.begin_session) then
		return false
	end
	return pr.harness.begin_session(session, now, opts) == true
end

-- Seconds since the current run began (the harness re-stamps started_at on every
-- begin). Nil when the run never began - never a clock on a guess.
function ST.SHAMAN.practice_fight_elapsed(session, now)
	if type(session) ~= "table" or type(now) ~= "number" then
		return nil
	end
	if not session.active or type(session.started_at) ~= "number" then
		return nil
	end
	local elapsed = now - session.started_at
	if elapsed < 0 then
		return 0
	end
	return elapsed
end

-- Info-line status for the panel (marker countdown / clip verdict / idle). Pure
-- readout, never a rule input: unknown reads idle, never a guess.
function ST.SHAMAN.practice_status(swing, now)
	if type(swing) ~= "table" or type(swing.swing_duration) ~= "number"
		or swing.swing_duration <= 0 or type(swing.swing_start) ~= "number"
		or type(now) ~= "number" then
		return "Drill idle"
	end
	local fraction = (now - swing.swing_start) / swing.swing_duration
	local cast = ST.SHAMAN.practice_cast_seconds("weave_lb")
	if type(cast) ~= "number" then
		return "Drill idle"
	end
	local marker = st.weave and st.weave.get_marker_fraction
		and st.weave.get_marker_fraction(swing.swing_duration, cast,
			ST.SHAMAN.practice_latency_seconds())
	if type(marker) ~= "number" then
		return "Drill idle"
	end
	if fraction > marker then
		return "Too late - wait for the next swing"
	end
	local left = (marker - fraction) * swing.swing_duration
	return string.format("Cast now - %.2fs to marker", left)
end

--=========================================================================================
-- Practice surface: the rotation table, the scenario step and the class drills
-- (bench/class_features_drills_2026-10-19.md §2.6)
--=========================================================================================
-- The shared engine (practice.lua:3223-3477) drives three class hooks; this module
-- implements them for the shaman and the pure half lives in shaman_guide.lua (the
-- practice surface at the end of that file). The engine registers the drills itself
-- - nothing here registers anything.
--
-- ROTATION TABLE. The class's sim priority order - the compiled form of the rule
-- matrix in shaman_guide.lua (its header lists the order the engine runs), with each
-- line's sim citation. The lines the live guide cannot play yet (no slot) stay in
-- the table with live = false, so the practice surface shows the whole spine:
--   S-20 Call of the Elements landed with its slot, its rule (9c) and the
--   water-totem clock (the client's own slot 3 - CLIENT-SOURCED, the tree's old
--   "UNCONFIRMED against FrameXML" note was stale); its id 66842 is in the
--   shipped clients' own Constants.lua totem-multi-cast list, and the Wrath
--   enhancement APLs rank it between Earth Shock and Magma Totem.
--   S-19 Lightning Shield and S-17 Searing Totem landed with their slots and rules
--   (guide slots 16 and 17, rules 11b and 9b), so their lines are live now.
-- Name-vs-id (bench/lessons.md): TBC Anniversary resolves by NAME and Classic Era by
-- ID, so every line ships both - the id is the Era id, the name the TBC English
-- name. The ids marked UNCONFIRMED below are the ones the module already gates on:
-- a wrong id stays silent through the known gate, it never prompts wrong.
-- families names the client family tokens whose SIM plays the line; on the ERA
-- token the SoD build is the one that plays the SoD-only lines (the MW-rune latch
-- separates SoD from Era-base at runtime), and a line no client plays today still
-- lists the family whose sim does.
-- FLAGS (HU-13's two axes, read the way this table reads them):
--   live   = the line's READ exists in the shipped tree today (the gather can
--            supply the input the rule needs). A line without a read is live =
--            false and names the read it waits for in `needs`.
--   engine = the frozen engine has an arm that can PLAY the line with the inputs
--            the shipped tree actually produces (the live gather's feeds and the
--            shared practice engine's stated resources). A rule whose input no
--            producer ever supplies claims NO arm: engine = false - a row that
--            claims an arm it cannot have is the failure mode this project hunts
--            (the Chain Lightning row: rule 13 exists, but no client API counts
--            enemies, so nothing ever feeds target_count).

ST.SHAMAN.practice_rotation = {
	{ action = "fireele", label = "Fire Elemental Totem",
		spell_id = WEAVE_FIRE_ELEMENTAL_SPELL_ID, spell_name = WEAVE_FIRE_ELEMENTAL_NAME,
		families = { "WRATH", "TBC" }, live = true, engine = true,
		source = "the guide's rule 2 (Wrath #1); tbc-new enhancement APL (the Fire Ele group) - audit 2026-10-19 §2.6 S-12/S-18; id 2894 UNCONFIRMED" },
	{ action = "feralspirit", label = "Feral Spirit",
		spell_id = WEAVE_FERAL_SPIRIT_SPELL_ID, spell_name = WEAVE_FERAL_SPIRIT_NAME,
		families = { "ERA", "WRATH" }, live = true, engine = true,
		source = "sod phase_6.apl.json (#1); wowsims/wotlk feral_spirit.go (51533, 3 min, 45 s) - audit 2026-10-19 §2.6 S-08" },
	{ action = "bloodlust", label = "Bloodlust",
		spell_id = ST.SHAMAN.APL_UTILITY.bloodlust.ids.WRATH,
		spell_name = ST.SHAMAN.APL_UTILITY.bloodlust.name,
		spell_ids = ST.SHAMAN.APL_UTILITY.bloodlust.ids,
		families = { "WRATH" }, live = true, engine = true,
		source = "the APL UTILITY layer (bench/rotation_gap_vs_apl_2026-10-20.md §5): wowsims/wotlk ui/enhancement_shaman/apls/default_wf.apl.json i=1 and i=2 (2825: the party haste cooldown, cast on cooldown - the row sits between Feral Spirit and the autocast row) - wowsims/wotlk sim/shaman/bloodlust.go:7-9 (BloodlustActionID = SpellID 2825); the read is api.GetSpellCooldown on 2825 behind the known gate, so a client without the spell never sees the prompt (engine rule 3b)" },
	{ action = "shamanisticrage", label = "Shamanistic Rage",
		spell_id = WEAVE_SR_SPELL_ID, spell_name = WEAVE_SR_NAME,
		families = { "ERA", "TBC", "WRATH" }, live = true, engine = true,
		source = "sod phase_6.apl.json (#3, mana <= 65%); tbc-new SR group (mana < 10%); wowsims/wotlk (the generic MCD) - audit 2026-10-19 §2.6 S-07" },
	{ action = "weave", label = "Lightning Bolt",
		spell_id = 403, spell_name = WEAVE_LB_NAME,
		families = { "ERA", "TBC", "WRATH" }, live = true, engine = true,
		source = "the MW5 instant (every sim); sod phase_4/6.apl.json (autoTimeToNext >= cast + 100 ms, ANY stacks); wowsims/wotlk default_wf.apl.json (MW >= 3 and 300 ms + cast < autoTimeToNext) - audit 2026-10-19 §2.6 S-02/S-03/S-04" },
	{ action = "flameshock", label = "Flame Shock",
		spell_id = WEAVE_FLAME_SHOCK_BASE_SPELL_ID, spell_name = WEAVE_FLAME_SHOCK_NAME,
		families = { "ERA", "TBC", "WRATH", "FOREVER" }, live = true, engine = true,
		source = "the sims refresh it on expiry (not dotIsActive); sod phase_6.apl.json + tbc-new default APL (only after 12 s of fight); the classic default APL (the Era-base veto) never casts it, but the SoD build on the same ERA token does - audit 2026-10-19 §2.6 S-05/S-06" },
	{ action = "twist", label = "Windfury Totem",
		spell_id = WEAVE_WINDFURY_TOTEM_SPELL_ID, spell_name = WEAVE_WINDFURY_TOTEM_NAME,
		spell_ids = { TBC = 25587 },
		families = { "TBC" }, live = true, engine = true,
		source = "tbc-new weapon_imbues.go (the Windfury/Grace of Air alternation, the mana pause at 10%) - audit 2026-10-19 §2.6 S-14; id 8512 UNCONFIRMED. RANK RECONCILIATION (bench/shaman_apl_utility_build_2026-10-20.md §2 C5): the shipped id 8512 is the Windfury Totem RANK-1 id (wowsims/forever sim/shaman/spell_data_auto_gen.go: WindfuryTotem Ranked(8512, 10613, 10614)), and the module twists rank 1 ON PURPOSE (the DOWNRANK NOTE above: rank 1 for mana sustain - max rank ooms in 1-2 min of twisting); the TBC APL's own air-slot rows cast the sim-exact rank-5 id 25587 (ui/specs/shaman/enhancement/apls/default.apl.json i=3 group Totems row 1, and its prepullActions row @-8s) and the alternation's other half is the Grace of Air Totem 25359 r3 (the same group's row 2, and the prepull's goa row @-2s) - the sim-exact Windfury id is recorded in spell_ids, while the shipped fallback stays 8512 because the rank choice is the operator's O-1 decision (bench/filed_closure_sweep_2026-10-19.md §10) and the guide's name-based icon/label resolution covers the real rank" },
	{ action = "strength_of_earth", label = "Strength of Earth Totem",
		spell_id = ST.SHAMAN.APL_UTILITY.strength_of_earth.ids.ERA,
		spell_name = ST.SHAMAN.APL_UTILITY.strength_of_earth.name,
		spell_ids = ST.SHAMAN.APL_UTILITY.strength_of_earth.ids,
		families = { "ERA", "TBC", "FOREVER" }, live = true, engine = true,
		source = "the APL UTILITY layer (bench/rotation_gap_vs_apl_2026-10-20.md §5): wowsims/classic ui/enhancement_shaman/apls/default.apl.json i=0 (10442 r4: cast when the aura is NOT active); wowsims/tbc-new ui/specs/shaman/enhancement/apls/default.apl.json i=3 group Totems row 3 (25528: auraRemainingTime <= 5s); wowsims/forever ui/specs/shaman/enhancement/apls/default.apl.json i=4 (25361: totemRemainingTime(Earth) <= 0s) - the per-family ids come from the sims' own ladders (classic sim/shaman/earth_totems.go StrengthOfEarthTotemSpellId = {8075, 8160, 8161, 10442, 25361}; tbc-new sim/shaman/totems.go BySpellID(25528); forever sim/shaman/spell_data_auto_gen.go Ranked(8075, 8160, 8161, 10442, 25361)); the read is the client's EARTH totem slot clock through api.GetTotemInfo (the water clock's shape), so an unreadable slot never prompts (engine rule 8a); the SoD build runs no SoE rotation row (its SoE is a PRE-PULL row), so the MW latch keeps the ERA token's SoD build silent" },
	{ action = "wftotem", label = "Windfury Totem",
		spell_id = WEAVE_WF_TOTEM_SPELL_ID, spell_name = WEAVE_WF_TOTEM_NAME,
		families = { "ERA" }, live = true, engine = true,
		source = "the classic default APL (the Windfury Totem refresh) - audit 2026-10-19 §2.6 S-16; id 10614 UNCONFIRMED" },
	{ action = "goa", label = "Grace of Air Totem",
		spell_id = WEAVE_GOA_TOTEM_SPELL_ID, spell_name = WEAVE_GOA_TOTEM_NAME,
		families = { "ERA" }, live = true, engine = true,
		source = "the classic default APL (Grace of Air when the slot is inactive) - audit 2026-10-19 §2.6 S-16; id 10627 UNCONFIRMED" },
	{ action = "mana_spring", label = "Mana Spring Totem",
		spell_id = ST.SHAMAN.APL_UTILITY.mana_spring.ids.TBC,
		spell_name = ST.SHAMAN.APL_UTILITY.mana_spring.name,
		spell_ids = ST.SHAMAN.APL_UTILITY.mana_spring.ids,
		families = { "TBC" }, live = true, engine = true,
		source = "the APL UTILITY layer (bench/rotation_gap_vs_apl_2026-10-20.md §5): wowsims/tbc-new ui/specs/shaman/enhancement/apls/default.apl.json i=3 group Totems row 4 (25570: auraRemainingTime <= 5s - the mana totem's refresh) - the id is the TBC client's own (tbc-new sim/shaman/totems.go: manaSpringTotemRank = spellData.ManaSpringTotem.BySpellID(25570)); the read is the client's WATER totem slot clock through api.GetTotemInfo (on TBC the water slot carries Mana Spring), so an unreadable slot never prompts (engine rule 8d); the SoD and Forever Mana Spring rows are PRE-PULL rows (HU-12), not rotation rows" },
	{ action = "stormstrike", label = "Stormstrike",
		spell_id = WEAVE_STORMSTRIKE_SPELL_ID, spell_name = WEAVE_STORMSTRIKE_NAME,
		families = { "ERA", "TBC", "WRATH", "FOREVER" }, live = true, engine = true,
		source = "every fetched sim casts Stormstrike unconditionally at its priority slot - audit 2026-10-19 §2.6 S-01" },
	{ action = "searing", label = "Searing Totem",
		spell_id = WEAVE_SEARING_TOTEM_SPELL_ID, spell_name = WEAVE_SEARING_TOTEM_NAME,
		families = { "ERA", "TBC", "FOREVER" }, live = true, engine = true,
		source = "the classic default APL (Searing iff inactive, fight > 20 s); sod phase_6.apl.json (fight > 30 s); tbc-new (the Searing fallback when mana is low) - audit 2026-10-19 §2.6 S-17/S-25; id 10438 UNCONFIRMED; the guide slot (17) and rule 9b are live on the ERA token (the TBC low-mana fallback quotes no threshold and the Forever static maintain is filed, so no other family fires it)" },
	{ action = "magma", label = "Magma Totem",
		spell_id = WEAVE_MAGMA_TOTEM_SPELL_ID, spell_name = WEAVE_MAGMA_TOTEM_NAME,
		families = { "WRATH", "TBC" }, live = true, engine = true,
		source = "tbc-new fire_totems.go (the Magma filler); wowsims/wotlk fire_totems.go (Magma iff the dot is within 100 ms and no Fire Elemental 2894 is out) - audit 2026-10-19 §2.6 S-13; id 8190 UNCONFIRMED" },
	{ action = "firenova", label = "Fire Nova Totem",
		spell_id = WEAVE_FIRE_NOVA_SPELL_ID, spell_name = WEAVE_FIRE_NOVA_NAME,
		families = { "TBC", "WRATH", "FOREVER" }, live = true, engine = true,
		source = "tbc-new fire_totems.go (25537, 15 s); forever default.apl.json (Clearcasting, else mana > 10%, below Earth Shock) - audit 2026-10-19 §2.6 S-12/S-28" },
	{ action = "lightningshield", label = "Lightning Shield",
		spell_id = 49281, spell_name = "Lightning Shield",
		spell_ids = { WRATH = 49281, SOD = 10432, FOREVER = 10432 },
		families = { "WRATH", "SOD", "FOREVER" }, live = true, engine = true,
		source = "the three wowsims/wotlk enhancement APLs + lightning_shield.go (maintain iff inactive, above Lava Lash) - audit 2026-10-19 §2.6 S-19; id 49281 UNCONFIRMED; the guide slot (16) and rule 11b are live on WRATH, FOREVER and the SoD build (the maintain reads the player's own shield aura by name, so a wrong id only shows a wrong icon; the spell is known-gated, so a build without the Lightning Shield talent is never prompted). PER-FAMILY EXTENSION (bench/shaman_apl_utility_build_2026-10-20.md §5 F1): the SoD and Forever sims run the same maintain, so the row's families are WRATH, SOD and FOREVER and spell_ids carries each family's own id - wowsims/sod ui/enhancement_shaman/apls/phase_6.apl.json i=8 and phase_4.apl.json i=0 (10432 r7: 'not auraIsActive(10432)' -> cast 10432) and wowsims/forever ui/specs/shaman/enhancement/apls/default.apl.json i=6 (10432: the same condition); the Era-base and TBC APLs carry no Lightning Shield row, so the Era-base build and TBC never fire the maintain (the engine's get_lightningshield_family_gate)" },
	{ action = "lavalash", label = "Lava Lash",
		spell_id = WEAVE_LAVA_LASH_SPELL_ID, spell_name = WEAVE_LAVA_LASH_NAME,
		families = { "ERA", "WRATH" }, live = true, engine = true,
		source = "sod phase_6.apl.json (#6); wowsims/wotlk lavalash.go (60103, 6 s, off hand only) - audit 2026-10-19 §2.6 S-09; id 60103 UNCONFIRMED" },
	{ action = "chainlightning", label = "Chain Lightning",
		spell_id = 10605, spell_name = "Chain Lightning",
		families = { "ERA" }, live = false, engine = false,
		needs = "the enemy-count sensor (the target_count input rule 13 reads) - it does NOT exist: no client API counts enemies, and the shipped clients' FrameXML carries no Chain Lightning reference on any branch (re-verified 2026-10-20: git grep over classic_era, classic_anniversary, classic_titan, origin/forever and origin/live returns 0 hits each - bench/filed_closure_sweep_2026-10-19.md §4.1 S-11). Nothing in the tree feeds it either: the live gather writes target_count = nil and the shared practice engine never states the frozen input, so rule 13 has no producer and the row claims NO engine arm (engine = false - a row that claims an arm it cannot have is the failure mode this project hunts). What would close it: a third-party / combat-log unit-appear count plus a decision to accept a 0.5 s-lagged count - that is the operator's O-4 decision (bench/filed_closure_sweep_2026-10-19.md §10), so the rule stays as a filed skeleton until the operator rules",
		source = "sod phase_6.apl.json i=7 (10605 r4: MW >= 4 with numberTargets >= 2 - the APL's own enemy count, a SIM-side read with no client counterpart) and phase_4.apl.json i=6 (the same row): MW >= 4 with two or more targets - audit 2026-10-19 §2.6 S-11; the enemy-count sensor does not exist, so the line stays dark live and the row claims no arm" },
	{ action = "frostshock", label = "Frost Shock",
		spell_id = ST.SHAMAN.APL_UTILITY.frostshock.ids.TBC,
		spell_name = ST.SHAMAN.APL_UTILITY.frostshock.name,
		spell_ids = ST.SHAMAN.APL_UTILITY.frostshock.ids,
		families = { "TBC" }, live = true, engine = true,
		source = "the APL UTILITY layer (bench/rotation_gap_vs_apl_2026-10-20.md §5): wowsims/tbc-new ui/specs/shaman/enhancement/apls/default.apl.json i=6 group Shocks row 2 (25464 r5: the ALTERNATIVE 'Filler Shock' choice - the group's row 3, 25454 r8 Earth Shock, is the valueVariables default the group's own variable 'Filler Shock' carries) - the id is the TBC client's own (tbc-new sim/shaman/shocks.go: frostShockRank = spellData.FrostShock.BySpellID(25464); the WotLK Frost Shock is 49236 and no WotLK APL carries it); the read is api.GetSpellCooldown on 25464 behind the known gate; the arm fires only when the player states the Frost Shock choice - the class reads it from the player's own guide_filler_shock option (option_tables.lua's widget, config_presets.lua's default), so the APL's Earth Shock default stands until the player picks Frost Shock (engine rule 13b)" },
	{ action = "earthshock", label = "Earth Shock",
		spell_id = WEAVE_EARTH_SHOCK_SPELL_ID, spell_name = WEAVE_EARTH_SHOCK_NAME,
		families = { "ERA", "TBC", "WRATH", "FOREVER" }, live = true, engine = true,
		source = "the classic / tbc-new / wowsims/wotlk APLs (Earth Shock unconditional below Flame Shock; the Era sim only at mana >= 50%) - audit 2026-10-19 §2.6 S-21" },
	{ action = "moltenblast", label = "Molten Blast",
		spell_id = WEAVE_MOLTEN_BLAST_SPELL_ID, spell_name = WEAVE_MOLTEN_BLAST_NAME,
		families = { "ERA" }, live = true, engine = true,
		source = "sod phase_6.apl.json (the unconditional filler); proto/shaman.proto:113 - audit 2026-10-19 §2.6 S-10; id 425339 UNCONFIRMED" },
	{ action = "coe", label = "Call of the Elements",
		spell_id = WEAVE_COE_SPELL_ID, spell_name = "Call of the Elements",
		families = { "WRATH" }, live = true, engine = true,
		source = "the three wowsims/wotlk enhancement APLs + totems.go: CoE 66842 iff the water totem is under 20 s, ranked BETWEEN Earth Shock 49231 and Magma Totem 58734 (default_wf.apl.json [9], default_ft.apl.json [9], phase_3.apl.json [8]) - audit 2026-10-19 §2.6 S-20; id 66842 CLIENT-SOURCED (the shipped clients' own Constants.lua TOTEM_MULTI_CAST_SUMMON_SPELLS: classic_titan 3.80.2 :300-304, classic_era / classic_anniversary the same block, origin/forever :240-244); the water slot 3 is CLIENT-SOURCED the same way (Constants.lua:288 WATER_TOTEM_SLOT = 3 - the tree's old 'UNCONFIRMED against FrameXML' note was stale); the guide slot (18) and rule 9c are live on WRATH, and the water clock reads the client's own slot 3 through api.GetTotemInfo (the reader is the fire/air reader's shape, so an unreadable slot never prompts)" },
}

--=========================================================================================
-- The FAMILY SLICE: the rotation rows and the guide slots a client may be offered
--=========================================================================================
-- The rotation table above is FLAT: every row carries the family tokens whose
-- APL plays it (`families`), but nothing read that field at runtime - the
-- per-row list was token-validated by the suite and nothing else. The practice
-- panel therefore offered EVERY row on EVERY client: a TBC client was offered
-- the Wrath-only Call of the Elements and Bloodlust rows and the Era-only
-- Molten Blast, Lava Lash, Chain Lightning, Windfury Totem and Grace of Air
-- rows - rows its own APL never plays, so pressing one of them could only
-- ever grade wrong. TESTING.md's rule is explicit: "A family that does not
-- carry a row must never show it."
--
-- THE ONE SOURCE OF TRUTH: the rotation table's per-row `families` list. The
-- guide's slot set is cut from the SAME list, so the rotation rows and the
-- guide slots can never disagree about which rows a family carries.

-- The family set of one rotation row: the row's own `families` list. The table
-- lists the tokens (the cross-class convention the hunter, the rogue and the
-- druid use is a set), so the lookup walks the list.
function ST.SHAMAN.rotation_row_families(entry)
	local out = {}
	if type(entry) ~= "table" then
		return out
	end
	local families = entry.families
	if type(families) ~= "table" then
		return out
	end
	for i = 1, #families do
		local family = families[i]
		if type(family) == "string" and family ~= "" then
			out[family] = true
		end
	end
	return out
end

-- The rotation family the running client plays: the client's own family token
-- (compat.lua's). It is the panel's readout ("which rotation is the scenario
-- grading against") and the default slice.
function ST.SHAMAN.practice_rotation_family()
	return st.family
end

-- The running BUILD's own family token: "SOD" on the ERA token once the
-- Season of Discovery rune basis is observed (the MW-rune latch - the same
-- latch the guide's SoD gates read), nil on every other client.
--
-- The SoD game runs on the ERA client, so the client's own family token cannot
-- name it: the BUILD names itself, exactly like the paladin's SoD orders name
-- their own family (classes/paladin.lua's practice_rotation_for).
function ST.SHAMAN.practice_build_family()
	if st.family ~= "ERA" then
		return nil
	end
	if ST.weave_mw_observed == true then
		return "SOD"
	end
	return nil
end

-- The family's rotation slice: the rows whose `families` names the family, in
-- the table's own order (the sim priority order).
--
-- THE ORDER TOKEN: the argument-free call answers the client's family PLUS the
-- running build's token, so the SoD build's own rows ride the ERA slice - the
-- same shape as the paladin's SoD orders (the twist order is shared by the
-- classic line, the SoD variants are their own orders). An explicit family
-- answers that family ALONE (the pins walk the families one by one), and an
-- unknown family answers an empty slice - never a guess, never another
-- family's rows.
--
-- The ERA token carries two games (the runeless Era build and the SoD build),
-- and the table's ERA rows are the token's truth: the SoD-only lines (the
-- Molten Blast filler, the Lava Lash, the Chain Lightning, the Feral Spirit)
-- are listed under ERA with the note that the MW-rune latch separates the two
-- builds at runtime. The slice therefore names the CLIENT's family, so the
-- Era-base client is offered the SoD-only rows as well - that is the shipped
-- table's truth, and the engine's own gates (the same latch) keep those
-- prompts dark. Splitting the two builds' rows apart would need a per-row
-- build marker the table does not carry (a filed refinement of the table, not
-- a change made here).
function ST.SHAMAN.practice_rotation_for(family)
	local want = family
	local extra = nil
	if type(want) ~= "string" or want == "" then
		want = ST.SHAMAN.practice_rotation_family()
		extra = ST.SHAMAN.practice_build_family()
	end
	local out = {}
	for i = 1, #ST.SHAMAN.practice_rotation do
		local entry = ST.SHAMAN.practice_rotation[i]
		local families = ST.SHAMAN.rotation_row_families(entry)
		if families[want] or (extra ~= nil and families[extra]) then
			out[#out + 1] = entry
		end
	end
	return out
end

--=========================================================================================
-- The NEUTRAL action set (the panel's legitimate-but-ungraded presses)
--
-- The shared engine grades a press against the rotation: the action the rotation
-- asks for is a HIT, any other action is a MIS-PICK (F) - and a NEUTRAL action is
-- neither (no attempt, no points, no streak change). The class publishes the keys
-- that are legitimate but that the rotation never asks for; the engine reads
-- ST.<CLASS>.practice_neutral_actions (the contract fixed by the orchestrator,
-- practice.lua's class contract block). A class that publishes nothing leaves
-- every non-rotation press a mis-pick, exactly as before.
--
-- THE PUBLISH IS EMPTY, and that is the class's own truth, not a gap:
--
--   * the shaman's PANEL ACTION VOCABULARY is the rotation. The guide slots are
--     cut from the rotation table itself (ST.SHAMAN.family_guide_slots: "a slot
--     whose ROTATION row names no family never joins a slice"), and the rotation
--     table carries ONE guide slot per row - so on every client the panel offers
--     exactly that family's rotation rows, and every key it offers is a rotation
--     action the rotation grades;
--   * the slots a family does NOT play are filtered OUT of the panel, not shown
--     as ungraded extras: Lightning Shield is a WRATH/SOD/FOREVER row (the
--     Era-base and TBC APLs carry no Lightning Shield row), and Strength of
--     Earth is an ERA/FOREVER/TBC row (the WotLK APLs carry none). So "the
--     rotation does not ask for it" never reaches the panel on that family;
--   * the class's own drills grade rotation rows (shaman_enh_priority and the
--     weave drill's own casts), and the drill's cast keys (PRACTICE_CAST_ORDER:
--     weave_lb, weave_cl) are the DRILL's graded casts, not rotation picks - the
--     neutral set must never touch a drill's own truth.
--
-- THE KEYS THE ORCHESTRATOR NAMED FOR THIS CLASS (Healing Wave, Chain Heal, the
-- water shield, food and drink, potions, Lightning Shield, Strength of Earth,
-- Bloodlust) are all accounted for above: the shields and the totems are
-- rotation rows (or filtered out of the panel on the families that do not play
-- them), Bloodlust is a WRATH rotation row, and the heals, the food and drink
-- and the potions have NO key in the shaman's own ability list - the class's
-- guide slots carry no key for them (the APL's consumable rows are ITEMS, not
-- spells), so publishing them would invent keys the class does not have.
--
-- The closed list still holds: the class's own suite pins that every panel key
-- on every family is classified (a rotation action, a neutral action, or an
-- intentional mis-pick), so the next ability someone adds cannot silently become
-- a free press - and so a family that grows a NON-rotation guide slot fails the
-- suite until the class classifies it here.
--=========================================================================================
ST.SHAMAN.practice_neutral_actions = {
	healing_wave = true,
	chain_heal = true,
	water_shield = true,
	healing_potion = true,
	food = true,
}

--=========================================================================================
-- The neutral set THIS class publishes for the RUNNING family
--
-- The engine reads the publish through its own accessor (practice.lua's
-- H.practice_neutral_actions) and resolves it for the running client family
-- (st.family): a FLAT publish answers itself, a family-scoped publish answers the
-- bucket for that family, and a family the class published no bucket for answers
-- nil (the engine then grades every non-rotation press exactly as it did before).
--
-- This accessor is that SAME rule, re-implemented here so the class never has to
-- ask the engine - and so the OFFER GATE below reads the class's OWN truth.
--
-- THE OFFER GATE READS IT (the orchestrator's ruling, 2026-10-20): an ability may
-- only be OFFERED on a family where it is either a rotation action or a neutral
-- action. An offer that can only ever be a mis-pick is a trap - the player is
-- invited to press something the grader will always punish. So the panel's
-- common-ability offer list and this set are ONE truth per family: an ability
-- with no neutral bucket on that family is NOT offered there (it stays available
-- on the families where it IS neutral).
--
-- THE CATA AND MISTS CLIENTS: the shaman's publish is FLAT, so it already answers
-- every family - the Cata (4.4.3) and the Mists (5.5.0) clients included. The class
-- publishes no rotation for those two clients (the rotation table carries no CATA /
-- MISTS row, so practice_rotation_for answers an empty slice there), so none of the
-- published common abilities is rotation-ranked there: a Healing Wave, a Chain Heal,
-- a Water Shield, a Healing Potion or a Food press on those clients is a legitimate,
-- ungraded press - never a mis-pick. Every one of those spells is present on both
-- clients (cited per ability in the common list below).
--=========================================================================================
function ST.SHAMAN.practice_neutral_set()
	local published = ST.SHAMAN.practice_neutral_actions
	if type(published) ~= "table" then
		return nil
	end
	local source = published
	for _, value in pairs(published) do
		if type(value) == "table" then
			-- a family-scoped publish: the running family's own bucket
			source = published[st.family]
			break
		end
	end
	if type(source) ~= "table" then
		return nil
	end
	return source
end

-- The running family's ROTATION actions (the set the offer gate reads): the class's
-- own published slice for the running client, read the way the panel reads it (the
-- argument-free call - practice_ui.lua's scenario_action_order).
function ST.SHAMAN.practice_rotation_action_set()
	local out = {}
	local ok, entries = pcall(function() return ST.SHAMAN.practice_rotation_for() end)
	if not ok or type(entries) ~= "table" then
		return out
	end
	for i = 1, #entries do
		local entry = entries[i]
		if type(entry) == "table" and type(entry.action) == "string" and entry.action ~= "" then
			out[entry.action] = true
		end
	end
	return out
end

-- The class's own alias table (the spellings the engine or the sim may report, mapped
-- onto the canonical key). The shaman has none - its key space is one - so the
-- normaliser is the identity.
function ST.SHAMAN.practice_canonical_key(key)
	local aliases = ST.SHAMAN.practice_action_aliases
	if type(aliases) == "table" and type(key) == "string" then
		return aliases[key] or key
	end
	return key
end

-- THE OFFER GATE (the orchestrator's ruling, 2026-10-20): may this common ability be
-- OFFERED on the running family?
--
--   (1) the class's own per-ability family gate (the entry's `families` field) names
--       the running family - the class's own statement about the ability;
--   (2) the running family's published neutral set carries the key - the offer list
--       and the neutral set are ONE truth per family;
--   (3) the running family's rotation does not rank the key - a rotation action is
--       graded by the rotation, never an offered common ability.
--
-- A family the class published no neutral bucket for offers NO common ability: the
-- ability would be a mis-pick the moment it is pressed.
function ST.SHAMAN.practice_common_offer_allowed(action, neutral, rotation)
	if type(action) ~= "table" or type(action.key) ~= "string" or action.key == "" then
		return false
	end
	local families = action.families
	if type(families) == "table" then
		local named = false
		for i = 1, #families do
			if families[i] == st.family then
				named = true
				break
			end
		end
		if not named then
			return false
		end
	end
	if type(neutral) ~= "table" or neutral[action.key] ~= true then
		return false
	end
	if type(rotation) == "table"
		and rotation[ST.SHAMAN.practice_canonical_key(action.key)] == true then
		return false
	end
	return true
end

--=========================================================================================
-- The PRACTICE-PANEL ability list: the common abilities the panel offers
--
-- WHY THIS EXISTS: the practice panel's action row offers the class's whole ability
-- list, and a player legitimately presses a heal, a shield, food or a potion while
-- practicing. The engine grades such a press NEUTRAL - no attempt, no points, no
-- streak change, never a mis-pick (bench/practice_neutral_actions_2026-10-20.md). For
-- that the class needs a KEY for each of them: the panel's vocabulary is the rotation
-- slice plus the class's own guide slot list, and the common abilities had no key at
-- all (bench/class_neutral_actions_2026-10-20.md §2).
--
-- HOW IT REACHES THE PANEL: the list below is APPENDED to the class's own guide slot
-- list AFTER the guide frame has built its icons - the same seam this file's
-- apply_family_slots already uses (the guide frame above built its icons from the
-- class's full display vocabulary, so the narrower list changes nothing the player
-- sees there). The practice panel reads the slot list LIVE, so the panel's action row
-- offers the common abilities with their own icons.
--
-- THE IDS (cited, never invented):
--   * the resolution asks the client's own spell data for the ENGLISH spell NAME
--     (the rogue's resolve_named_spell rule, classes/rogue.lua), and the id the
--     client answers WITH that name is its own rank's id - so a client that
--     indexes the English name shows its own rank art. Whether the classic-line
--     global GetSpellInfo takes a name at all is UNCONFIRMED in-client
--     (bench/final_gate_audit_2026-10-20.md §6 C1: the Blizzard UI calls the
--     classic global with an id and the Cata/Mists UI code with a name), so the
--     name leg is a claim the operator's in-client pass still owes;
--   * the id table is the CITATION and the fallback - it is NOT a guarantee of the
--     client's own art: a client that does not answer the name, or answers it
--     without an id, falls back to the ERA corpus's rank-1 ids, which is the
--     client's own rank only where that id still exists on it (the Healthstone:
--     the Era id 5720 answers "Not Found" on the Cata and the Mists clients,
--     whose own rank is 6262 - the ladder is deliberately not extended with it,
--     bench/class_neutral_family_coverage_2026-10-20.md §1.2);
--   * the query is family-correct (the operator's name-vs-id rule, bench/lessons.md):
--     the NAME on TBC (that client answers names, never bare ids), the numeric id on
--     every other family;
--   * the id sources: the Classic 1.15 client corpus (/home/sam/wow.export/Spell.csv
--     - the id plus the client's own description) and the client's spell names from
--     the Classic spell pages (the /data/spell/<id> page on the warcraftdb site - its
--     title carries the client's own spell name). The in-tree citations are named
--     per row.
--
-- UNKNOWN-HIDES: an ability the running client does not have is never offered - the
-- resolution drops it - so the panel never shows a button the client cannot cast.
--
-- NO ROTATION ACTION HERE: none of these keys is a rotation row on any family the
-- shaman plays (the class's own rotation rows: stormstrike, flameshock, firenova,
-- earthshock, weave, twist, lightningshield, searing, coe, bloodlust,
-- strength_of_earth, mana_spring, frostshock, the totem rows and the SoD rows), so
-- none of them may be a rotation action; the neutral set above publishes exactly
-- these keys.
--
-- THE SHIELD ROW: Water Shield is NOT a rotation row on any family (the class's
-- rotation table carries no water shield row - the shield row is Lightning Shield,
-- and that one IS a rotation row on WRATH/SOD/FOREVER). Lightning Shield is
-- deliberately NOT in this list: it is a rotation action on three of the five
-- families, and the SoD build shares the Era family token with the Era build, so a
-- family-scoped neutral publish could not separate them - publishing it would make a
-- WRONG Lightning Shield press free on the Era build. The Water Shield is the
-- classic-era shield the class's own shield row already reads.
--=========================================================================================
ST.SHAMAN.practice_common_actions = {
	{
		key = "healing_wave",
		label = "Healing Wave",
		names = { "Healing Wave" },
		-- 331 (r1) / 332 / 547 / 913 / 939 / 959 / 25357 (r7) - the client's Healing
		-- Wave ladder (the corpus description: "Heals a friendly target for $s1."; the
		-- rank-1 id 331 and the top rank 25357 are also in
		-- Libs/LibClassicDurations/classAbilities.lua: "[GetSpellInfo(25357)] --
		-- Healing Wave"). No shaman rotation row asks for it.
		ids = { 331, 332, 547, 913, 939, 959, 25357 },
	},
	{
		key = "chain_heal",
		label = "Chain Heal",
		names = { "Chain Heal" },
		-- 1064 (r1) / 10622 / 10623 - the client's Chain Heal ladder (the corpus
		-- description: "Heals the friendly target for $s1, then jumps to heal
		-- additional nearby targets."). No shaman rotation row asks for it.
		ids = { 1064, 10622, 10623 },
	},
	{
		key = "water_shield",
		label = "Water Shield",
		-- The Season of Discovery client RENAMED the shield, so both names are
		-- offered: the client answers whichever one it knows.
		names = { "Water Shield", "Mana Shield" },
		-- 52127 / 52129 / 52131 / 24398 / 33736 / 33737 / 34827 / 57960 - the class's
		-- OWN water-shield aura id table (classes/shaman.lua's
		-- WEAVE_WATER_SHIELD_IDS, the same rows the shield charge row reads; the
		-- names table beside it carries "Water Shield" and "Mana Shield"). No
		-- shaman rotation row asks for it.
		ids = { 52127, 52129, 52131, 24398, 33736, 33737, 34827, 57960 },
	},
	{
		key = "healing_potion",
		label = "Healing Potion",
		names = { "Healing Potion" },
		-- 439 / 440 / 441 / 2024 / 4042 / 17534 - the client's Healing Potion use
		-- effects (the corpus description: "Restores $s1 health."; the name
		-- confirmed at the Classic spell page (439)). No shaman rotation
		-- row asks for it.
		ids = { 439, 440, 441, 2024, 4042, 17534 },
	},
	{
		key = "food",
		label = "Food",
		names = { "Food" },
		-- 433 / 2639 / 5004 / 10256 / 10257 - the client's Food use effects (the
		-- corpus description: "Restores $o1 health over $d. Must remain seated
		-- while eating."; the name confirmed at the Classic spell page (433)).
		ids = { 433, 2639, 5004, 10256, 10257 },
	},
}

-- Resolve one common ability against the client's own spell data: the English name
-- first (a client that indexes it answers its own rank id - the client's own rank
-- art), then the cited id ladder (the ERA corpus's rank-1 ids - the fallback for a
-- client that does not index the English name, or answers it without an id). Returns
-- the panel slot - { key, label, spell_id } - or nil when this client does not have
-- the spell (unknown-hides: the panel never offers a button the client cannot cast).
--
-- Nil-safe throughout: a malformed entry, a missing api or a throwing client read
-- answers nil, never an error.
function ST.SHAMAN.resolve_practice_common_action(action)
	if type(action) ~= "table" or type(action.key) ~= "string" or action.key == "" then
		return nil
	end
	if type(api.GetSpellInfo) ~= "function" then
		return nil
	end
	local names = action.names
	if type(names) == "table" then
		for i = 1, #names do
			local name = names[i]
			local ok, spell_name, _, _, _, _, _, spell_id = pcall(api.GetSpellInfo, name)
			if ok and type(spell_name) == "string" then
				local query
				if st.family == "TBC" then
					query = name
				elseif type(spell_id) == "number" then
					query = spell_id
				else
					query = action.ids and action.ids[1] or nil
				end
				if query ~= nil then
					return { key = action.key, label = action.label, spell_id = query,
						practice_common = true }
				end
			end
		end
	end
	-- The cited id ladder: the fallback for a client that does not index the English
	-- name. On TBC the query must be a NAME, so the ladder cannot stand in there.
	local ids = action.ids
	if st.family ~= "TBC" and type(ids) == "table" and type(api.get_family_spell_id_state) == "function" then
		local id = api.get_family_spell_id_state(ids)
		if type(id) == "number" then
			return { key = action.key, label = action.label, spell_id = id,
				practice_common = true }
		end
	end
	return nil
end

-- The panel's ability list: the class's own guide slots plus the common abilities
-- the running client actually has. The practice panel reads the guide slot list LIVE
-- (practice_ui.lua's scenario_guide_slots), so this is the list the panel offers.
function ST.SHAMAN.practice_panel_slots()
	local guide = ST.SHAMAN.guide
	local slots = type(guide) == "table" and guide.slots or nil
	local out = {}
	if type(slots) == "table" then
		for i = 1, #slots do
			out[i] = slots[i]
		end
	end
	local common = ST.SHAMAN.practice_common_actions
	if type(common) == "table" then
		-- THE OFFER GATE: a common ability is offered on the running family only if
		-- that family publishes it (as neutral) or the rotation ranks it there - the
		-- offer list and the neutral set are one truth per family.
		local neutral = ST.SHAMAN.practice_neutral_set()
		local rotation = ST.SHAMAN.practice_rotation_action_set()
		for i = 1, #common do
			local action = common[i]
			if ST.SHAMAN.practice_common_offer_allowed(action, neutral, rotation) then
				local slot = ST.SHAMAN.resolve_practice_common_action(action)
				if slot then
					out[#out + 1] = slot
				end
			end
		end
	end
	return out
end

-- Widen the class's guide slot list with the common abilities. Called AFTER the guide
-- frame has built its icons and AFTER apply_family_slots narrowed the list to the
-- running family, so the live guide keeps its own icon set while the practice panel's
-- action row offers the common abilities. Idempotent: a list that already carries a
-- common slot is left alone (apply_family_slots re-narrows the list, and this
-- re-widens it).
function ST.SHAMAN.apply_practice_panel_actions()
	local guide = ST.SHAMAN.guide
	if type(guide) ~= "table" or type(guide.slots) ~= "table" then
		return false
	end
	local current = guide.slots
	for i = 1, #current do
		local slot = current[i]
		if type(slot) == "table" and slot.practice_common == true then
			return false
		end
	end
	local widened = ST.SHAMAN.practice_panel_slots()
	if type(widened) ~= "table" or #widened <= #current then
		return false
	end
	guide.slots = widened
	return true
end

-- The family's guide slot set: the slots whose ROTATION row names the family,
-- in the class's display order (the rotation table is the family truth, so the
-- two vocabularies can never drift apart).
--
-- The slot keys and the rotation actions are the same key space (one slot per
-- rotation row), so the cut is a filter over the full vocabulary: a slot whose
-- row names no family (a slot the table does not carry) never joins a slice.
function ST.SHAMAN.family_guide_slots(family, extra)
	local out = {}
	if type(family) ~= "string" or family == "" then
		return out
	end
	local all_slots = ST.SHAMAN.GUIDE_SLOTS
	if type(all_slots) ~= "table" then
		return out
	end
	local by_action = {}
	for i = 1, #ST.SHAMAN.practice_rotation do
		local entry = ST.SHAMAN.practice_rotation[i]
		by_action[entry.action] = ST.SHAMAN.rotation_row_families(entry)
	end
	for i = 1, #all_slots do
		local slot = all_slots[i]
		local families = by_action[slot.key]
		if families ~= nil
			and (families[family] or (extra ~= nil and families[extra])) then
			out[#out + 1] = slot
		end
	end
	return out
end

-- Narrow the guide's slot list to the running family's set: the practice
-- panel's action strip reads this list LIVE (the strip is the rotation slice
-- + the guide slot keys + the keys the engine asked for), so the family's
-- vocabulary is exactly what the strip offers.
--
-- The guide FRAME built its icons from the class's full display vocabulary
-- above (the frame stacks one icon per slot and fades in only the current
-- action's, so the narrower list changes nothing the player sees there) and
-- keeps them: the frame's icons are built once and never rebuilt.
--
-- The applied token makes the call idempotent: the SoD build is only known
-- once the MW rune is observed (a runtime latch), so the list is cut again
-- when the running build changes - and never before the practice surface is
-- wired (the frame's own icon set must not change under it).
function ST.SHAMAN.apply_family_slots()
	local family = ST.SHAMAN.practice_rotation_family()
	local extra = ST.SHAMAN.practice_build_family()
	local token = (type(family) == "string" and family or "") .. "/" .. (extra or "")
	if ST.SHAMAN.applied_family_token == token then
		return false
	end
	local slots = ST.SHAMAN.family_guide_slots(family, extra)
	if #slots == 0 then
		-- A family the class carries no row for (a client that plays no
		-- shaman rotation at all) leaves the class's vocabulary standing:
		-- unknown-hides, never another family's rows.
		return false
	end
	local guide = ST.SHAMAN.guide
	if type(guide) ~= "table" then
		return false
	end
	guide.slots = slots
	ST.SHAMAN.applied_family_token = token
	-- The family's slice narrowed the PANEL's strip; the common abilities (a heal, a
	-- shield, food, a potion) ride on top of it, so the strip is re-widened here.
	-- The guide frame keeps its own icon set - it built its icons from the class's
	-- full display vocabulary above, and the frame's icons are never rebuilt.
	ST.SHAMAN.apply_practice_panel_actions()
	return true
end

-- The APL's PRE-PULL rows (HU-12, the orchestrator's ruling of 2026-10-20): the
-- rotation table above carries the APL's SPELL ROWS; the pre-pull rows live here,
-- in the hunter's shape (ST.HUNTER.PRACTICE_PREPULLS). `at` is the offset
-- relative to the pull in seconds (negative = before the pull), taken from the
-- APL's own doAtValue; `spell` is the id the APL casts. The consumable rows
-- (the potions, the drum items and the SoD item/activateAura rows) are NOT
-- rotation decisions and are not listed here.
--
-- NO CONSUMER (stated here so nothing implies coverage that does not exist):
-- this table is CITATIONS ONLY. The class ships no pre-pull drill - only the
-- warrior, the hunter and the rogue have one - and no other module reads this
-- table, so nothing grades a pre-pull row today. It records the APLs' own
-- pre-pull rows (the ids and the offsets) for the lane that builds the drill,
-- and it must never join the combat rotation: the rotation table above is the
-- rotation, and the family's slice (practice_rotation_for) never names a
-- pre-pull row.
--
--   ERA     wowsims/classic ui/enhancement_shaman/apls/default.apl.json
--           (prepullActions: 10442 r4 @-6s, 10614 r3 @-4.5s, 10627 r2 @-3s,
--           10438 r6 @-1.5s)
--   SOD     wowsims/sod ui/enhancement_shaman/apls/phase_6.apl.json
--           (prepullActions: 10432 r7 @-10s, 415140 @-10s (an aura activation,
--           not a cast), 10497 r4 @-8.25s, 25359 r3 @-6.75s, 25361 r5 @-5.00s,
--           10438 r6 @-2.75s, 20572 @-1.25s, 26297 @-1.0s (an item), item 215162
--           @-1s)
--   TBC     wowsims/tbc-new ui/specs/shaman/enhancement/apls/default.apl.json
--           (prepullActions: 25587 r5 @-8s, 25528 r6 @-5s, 25570 r5 @-4s,
--           25537 r7 @-3s, 25359 r3 @-2s, 35476 @-1s)
--   FOREVER wowsims/forever ui/specs/shaman/enhancement/apls/default.apl.json
--           (prepullActions: 25359 @-8s, 16387 @-7s, 25361 @-6s, 10497 @-5s)
--   WRATH   wowsims/wotlk ui/enhancement_shaman/apls/default_wf.apl.json
--           (prepullActions: 66842 @-3s, OtherActionPotion @-1s)
ST.SHAMAN.PRACTICE_PREPULLS = {
	ERA = {
		{ action = "strength_of_earth", label = "Strength of Earth Totem", spell = 10442, at = -6,
			source = "wowsims/classic ui/enhancement_shaman/apls/default.apl.json (prepullActions: Strength of Earth Totem 10442 r4 at -6s)" },
		{ action = "wftotem", label = "Windfury Totem", spell = 10614, at = -4.5,
			source = "wowsims/classic ui/enhancement_shaman/apls/default.apl.json (prepullActions: Windfury Totem 10614 r3 at -4.5s)" },
		{ action = "goa", label = "Grace of Air Totem", spell = 10627, at = -3,
			source = "wowsims/classic ui/enhancement_shaman/apls/default.apl.json (prepullActions: Grace of Air Totem 10627 r2 at -3s)" },
		{ action = "searing", label = "Searing Totem", spell = 10438, at = -1.5,
			source = "wowsims/classic ui/enhancement_shaman/apls/default.apl.json (prepullActions: Searing Totem 10438 r6 at -1.5s)" },
	},
	SOD = {
		{ action = "lightningshield", label = "Lightning Shield", spell = 10432, at = -10,
			source = "wowsims/sod ui/enhancement_shaman/apls/phase_6.apl.json (prepullActions: Lightning Shield 10432 r7 at -10s)" },
		{ action = "mana_spring", label = "Mana Spring Totem", spell = 10497, at = -8.25,
			source = "wowsims/sod ui/enhancement_shaman/apls/phase_6.apl.json (prepullActions: Mana Spring Totem 10497 r4 at -8.25s)" },
		{ action = "goa", label = "Grace of Air Totem", spell = 25359, at = -6.75,
			source = "wowsims/sod ui/enhancement_shaman/apls/phase_6.apl.json (prepullActions: Grace of Air Totem 25359 r3 at -6.75s)" },
		{ action = "strength_of_earth", label = "Strength of Earth Totem", spell = 25361, at = -5,
			source = "wowsims/sod ui/enhancement_shaman/apls/phase_6.apl.json (prepullActions: Strength of Earth Totem 25361 r5 at -5.00s)" },
		{ action = "searing", label = "Searing Totem", spell = 10438, at = -2.75,
			source = "wowsims/sod ui/enhancement_shaman/apls/phase_6.apl.json (prepullActions: Searing Totem 10438 r6 at -2.75s)" },
		{ action = "blood_fury", label = "Blood Fury", spell = 20572, at = -1.25,
			source = "wowsims/sod ui/enhancement_shaman/apls/phase_6.apl.json (prepullActions: Blood Fury 20572 at -1.25s)" },
	},
	TBC = {
		{ action = "twist", label = "Windfury Totem", spell = 25587, at = -8,
			source = "wowsims/tbc-new ui/specs/shaman/enhancement/apls/default.apl.json (prepullActions: Windfury Totem 25587 r5 at -8s)" },
		{ action = "strength_of_earth", label = "Strength of Earth Totem", spell = 25528, at = -5,
			source = "wowsims/tbc-new ui/specs/shaman/enhancement/apls/default.apl.json (prepullActions: Strength of Earth Totem 25528 r6 at -5s)" },
		{ action = "mana_spring", label = "Mana Spring Totem", spell = 25570, at = -4,
			source = "wowsims/tbc-new ui/specs/shaman/enhancement/apls/default.apl.json (prepullActions: Mana Spring Totem 25570 r5 at -4s)" },
		{ action = "firenova", label = "Fire Nova Totem", spell = 25537, at = -3,
			source = "wowsims/tbc-new ui/specs/shaman/enhancement/apls/default.apl.json (prepullActions: Fire Nova Totem 25537 r7 at -3s)" },
		{ action = "goa", label = "Grace of Air Totem", spell = 25359, at = -2,
			source = "wowsims/tbc-new ui/specs/shaman/enhancement/apls/default.apl.json (prepullActions: Grace of Air Totem 25359 r3 at -2s)" },
		{ action = "drums", label = "Drums of War", spell = 35476, at = -1,
			source = "wowsims/tbc-new ui/specs/shaman/enhancement/apls/default.apl.json (prepullActions: Drums of War 35476 at -1s)" },
	},
	FOREVER = {
		{ action = "goa", label = "Grace of Air Totem", spell = 25359, at = -8,
			source = "wowsims/forever ui/specs/shaman/enhancement/apls/default.apl.json (prepullActions: Grace of Air Totem 25359 at -8s)" },
		{ action = "flametongue", label = "Flametongue Totem", spell = 16387, at = -7,
			source = "wowsims/forever ui/specs/shaman/enhancement/apls/default.apl.json (prepullActions: Flametongue Totem 16387 at -7s)" },
		{ action = "strength_of_earth", label = "Strength of Earth Totem", spell = 25361, at = -6,
			source = "wowsims/forever ui/specs/shaman/enhancement/apls/default.apl.json (prepullActions: Strength of Earth Totem 25361 at -6s)" },
		{ action = "mana_spring", label = "Mana Spring Totem", spell = 10497, at = -5,
			source = "wowsims/forever ui/specs/shaman/enhancement/apls/default.apl.json (prepullActions: Mana Spring Totem 10497 at -5s)" },
	},
	WRATH = {
		{ action = "coe", label = "Call of the Elements", spell = 66842, at = -3,
			source = "wowsims/wotlk ui/enhancement_shaman/apls/default_wf.apl.json (prepullActions: Call of the Elements 66842 at -3s)" },
	},
}
-- frozen display fields) is reused, so the step itself allocates nothing. The
-- returned step table is fresh - the caller may keep it.
ST.SHAMAN.practice_scenario_out = {}

-- The practice scenario step: what the rotation wants cast next.
--   -> { action = "<slot key>", reason = "<text>" } | nil
--   -> { action = nil, hold = true, reason = "<text>" }   -- an explicit HOLD
-- ctx = { now, last_action, resources, cooldowns } (the contract's shape, see
-- practice.lua:3235-3240). nil means "cannot decide": the engine grades that step
-- UNKNOWN, never a wrong action. The verdict is the guide engine's own - the audit's
-- expected-sequence comparison (§2.6 D: st.shaman_guide.evaluate at every tick) -
-- so the scenario teaches the same priority the live guide shows.
--
-- A guide HOLD is a DECISION, not an unknown (the operator ruling HU-8, hands-up
-- 2026-10-19: HOLD-IS-A-DECISION): the RIDE window (a cast is in flight) and the
-- WAIT window (the Stormstrike is fished) state the hold explicitly, so the
-- engine can tell a hold (casting then is an illegal cast) from an unknown (no
-- attempt at all). The hold text is the guide's own caption - never a guess.
--
-- The family gates inside the engine read st.family (the live client's family). A ctx
-- family (the simulator's) is applied for the call and restored afterwards, so an
-- offline run grades its own family's rules. The restore is why the call is guarded:
-- a throwing step would otherwise leave st.family changed. A throw grades UNKNOWN
-- here, the same rule the shared engine applies around this call
-- (practice.lua:3284-3286): a step that cannot answer is never a wrong action.
function ST.SHAMAN.practice_scenario_step(self, ctx)
	local guide = st.shaman_guide
	if not (guide and guide.practice_step) then
		return nil
	end
	local family = nil
	if type(ctx) == "table" and type(ctx.resources) == "table" then
		family = ctx.resources.family
	end
	local saved = nil
	if type(family) == "string" and family ~= "" and family ~= st.family then
		saved = st.family
		st.family = family
	end
	local ok, step = pcall(guide.practice_step, ctx, ST.SHAMAN.practice_scenario_out)
	-- The step is nil: the engine either held (a decision) or could not decide
	-- (unknown). Its own verdict says which - the class never re-decides. The
	-- family swap still applies, so the verdict runs under the ctx's family.
	local is_hold = false
	local hold_text = nil
	if ok and type(step) ~= "table" and type(guide.practice_expected) == "function" then
		local ok2, res = pcall(guide.practice_expected, ctx, ST.SHAMAN.practice_scenario_out)
		if ok2 and type(res) == "table" and res.hold == true then
			is_hold = true
			if type(res.hold_text) == "string" and res.hold_text ~= "" then
				hold_text = res.hold_text
			end
		end
	end
	if saved ~= nil then
		st.family = saved
	end
	if not ok or type(step) ~= "table" then
		if is_hold then
			return { action = nil, hold = true, reason = hold_text or "the rotation is holding" }
		end
		return nil
	end
	return step
end

-- The class drills (bench/class_features_drills_2026-10-19.md §2.6 C, D-S1..D-S4).
-- The keys are the registry keys the shared engine registers; the grade functions
-- are thin wrappers over the pure graders in shaman_guide.lua. Every grader returns
-- nil when the attempt is not judgeable (the engine shows UNKNOWN and records no
-- attempt - a grade is never guessed).
ST.SHAMAN.practice_drills = {
	{
		key = "shaman_enh_priority",
		label = "The enhancement priority",
		kind = "rotation_order",
		description = "Pick the rotation's next action: Feral Spirit, Shamanistic Rage, the weave, Stormstrike, Flame Shock, Earth Shock.",
		grade = function(self, ctx)
			local guide = st.shaman_guide
			if not (guide and guide.grade_enh_priority) then
				return nil
			end
			return guide.grade_enh_priority(ctx)
		end,
	},
	{
		key = "shaman_mw_weave",
		label = "The stack decision",
		kind = "rotation_window",
		description = "Weave at the right Maelstrom stack and inside the swing: the marker fraction and the clip, on weave.lua's maths.",
		grade = function(self, ctx)
			local guide = st.shaman_guide
			if not (guide and guide.grade_mw_weave) then
				return nil
			end
			return guide.grade_mw_weave(ctx)
		end,
	},
	{
		key = "shaman_stormstrike_hold",
		label = "The Stormstrike decision",
		kind = "situational",
		description = "Press Stormstrike the moment it comes off cooldown - every sim does - or hold it for the Windfury proc behind the opt-in.",
		grade = function(self, ctx)
			local guide = st.shaman_guide
			if not (guide and guide.grade_stormstrike_hold) then
				return nil
			end
			return guide.grade_stormstrike_hold(ctx)
		end,
	},
	{
		key = "shaman_totem_upkeep",
		label = "The totem upkeep",
		kind = "rotation_window",
		description = "Keep the air and fire slots occupied - Windfury, Grace of Air, Magma, Searing - and never replace a live Fire Elemental.",
		grade = function(self, ctx)
			local guide = st.shaman_guide
			if not (guide and guide.grade_totem_upkeep) then
				return nil
			end
			return guide.grade_totem_upkeep(ctx)
		end,
	},
}

-- The namespace mirror this file used to carry (st.SHAMAN = ST.SHAMAN) is GONE:
-- the shared engine resolves the class module from the AceAddon table FIRST (the
-- class tables live there - main.lua creates ST.SHAMAN and every class module
-- reaches it through LibStub), and the namespace is only the fallback. The
-- central fix landed in practice.lua (H.practice_class_module reads the addon
-- object first), so the engine finds this class's practice hooks without any
-- per-class alias - see hands-up.md HU-7 and
-- bench/practice_scenario_engine_2026-10-19.md section 6.

--=========================================================================================
-- Rotation text: the shaman rotation source
--=========================================================================================
-- Implements the frozen ST.<CLASS>.get_rotation_key contract documented in
-- rotationtext.lua's header, following the paladin's shape (ST.PALADIN.
-- get_rotation_key in rotationtext.lua): the guide's own decision, so the label and
-- the guide can never disagree. The shaman engine names no rotations (its
-- out.rotation_key is always nil), so the label is the current action: the
-- recommended ability's localized name (resolved from the guide's own slot
-- descriptors, cached per spell id), HOLD while the engine holds, RIDE while it
-- rides (a cast in flight), nil when the guide is idle (renders as the empty
-- text). No practice branch: Twist Practice is paladin-only (no simulation exists
-- for this class). One reused output table: no per-tick allocation on the label
-- tick. The weave math module must be present (the gather reads it); without it
-- there is no source and the label stays empty.
ST.SHAMAN.rotation_out = {}

-- The guide slot's localized spell name for an action key (the slot's current-rank
-- spell id, so a re-pointed icon re-points the label with it). Falls back to the
-- raw action key when the client's spell data has not answered yet.
-- Name-vs-id: TBC queries the slot's English name; Era queries the id.
local rotation_name_cache = {}
local ROTATION_TBC_NAMES = {
	stormstrike = WEAVE_STORMSTRIKE_NAME,
	flameshock = WEAVE_FLAME_SHOCK_NAME,
	weave = "Lightning Bolt",
	firenova = WEAVE_FIRE_NOVA_NAME,
	earthshock = WEAVE_EARTH_SHOCK_NAME,
	twist = WEAVE_WINDFURY_TOTEM_NAME,
	feralspirit = WEAVE_FERAL_SPIRIT_NAME,
	fireele = WEAVE_FIRE_ELEMENTAL_NAME,
	magma = WEAVE_MAGMA_TOTEM_NAME,
	lavalash = WEAVE_LAVA_LASH_NAME,
	shamanisticrage = WEAVE_SR_NAME,
	chainlightning = "Chain Lightning",
	moltenblast = WEAVE_MOLTEN_BLAST_NAME,
	lightningshield = "Lightning Shield",
	searing = WEAVE_SEARING_TOTEM_NAME,
	bloodlust = "Bloodlust",
	strength_of_earth = "Strength of Earth Totem",
	mana_spring = "Mana Spring Totem",
	frostshock = "Frost Shock",
}

local function rotation_ability_name(action)
	local spell_id
	-- The class's FULL slot vocabulary, not the family's cut: the label must
	-- resolve for every action the engine can name, including one the family's
	-- rotation slice does not carry (the guide's own gate decides whether the
	-- action fires, not the practice vocabulary).
	local slots = ST.SHAMAN.GUIDE_SLOTS
	for i = 1, #slots do
		if slots[i].key == action then
			spell_id = slots[i].spell_id
			break
		end
	end
	if spell_id then
		if st.family == "TBC" then
			local tbc_name = ROTATION_TBC_NAMES[action]
			if tbc_name then
				local answered = api.GetSpellInfo(tbc_name)
				if answered then
					return answered
				end
				return tbc_name
			end
		end
		local name = rotation_name_cache[spell_id]
		if not name then
			name = api.GetSpellInfo(spell_id)
			if name then
				rotation_name_cache[spell_id] = name
			end
		end
		if name then
			return name
		end
	end
	return action
end

function ST.SHAMAN.get_rotation_key(self)
	local guide = ST.SHAMAN.guide
	local engine = st.shaman_guide
	if not (guide and guide.gather and guide.evaluate and engine and engine.evaluate) then
		return nil
	end
	if st.weave == nil then
		return nil
	end
	local out = guide.evaluate(guide.gather(self, ST.SHAMAN.guide_inputs),
		ST.SHAMAN.rotation_out)
	if out.action ~= nil then
		return rotation_ability_name(out.action)
	end
	if out.hold then
		return out.hold_text
	end
	return nil
end

--=========================================================================================
-- Shared practice-panel provider (class-isolation 2026-10-21 C2)
--=========================================================================================
-- The shaman's OWN practice route, panel order, ability defs and drill session.
-- The shared practice UI asks the ACTIVE class for this table and renders the
-- answers; it never names the shaman. The session seams are the class's own
-- functions (the weave maths stays in weave.lua).
ST.SHAMAN.practice_panel = {
    drill_key = "shaman_weave",
    title = "|cFFFF8800Weave Practice|r",
    def_type = "ability",
    -- The drill's name-art rule: a client that answers the name shows its own
    -- rank art - whether the classic-line global GetSpellInfo takes a name at
    -- all is UNCONFIRMED in-client (bench/final_gate_audit_2026-10-20.md §6 C1)
    -- - and an unanswered name leaves the icon blank rather than guessed (the
    -- drill still runs and grades).
    icon = "name",
    drift_message = "Practice mode is not available (shaman drill key drifted).",
    idle_status = "Drill idle - press Start Fight",
    hint_active = "Click a cast to weave. /st practice or the X button stops.",
    hint_stopped = "Press Start Fight, or cast weaves with the icon grid.",
    progress = {
        mode = "shaman_mw_weave",
        scenario = "shaman_rotation",
        drills = { "shaman_enh_priority" },
    },
    scenario_key = function() return ST.SHAMAN.practice_scenario_key() end,
    order = function() return ST.SHAMAN.PRACTICE_CAST_ORDER end,
    label = function(key) return ST.SHAMAN.practice_cast_label(key) end,
    spell_id = function(key) return ST.SHAMAN.practice_cast_spell_id(key) end,
    status = function(ui, now)
        if type(ST.SHAMAN.practice_status) ~= "function" then
            return nil
        end
        return ST.SHAMAN.practice_status(ui.shaman_swing, now)
    end,
    fight_elapsed = function(ui, now)
        if type(ST.SHAMAN.practice_fight_elapsed) ~= "function" then
            return nil
        end
        return ST.SHAMAN.practice_fight_elapsed(ui.shaman_session, now)
    end,
    session = {
        running = function(ui) return ui.shaman_session ~= nil end,
        active = function(ui)
            return ui.shaman_session and ui.shaman_session.active
        end,
        start = function(self, now, ui, ctx)
            if type(ST.SHAMAN.practice_latency_seconds) ~= "function"
                or type(ST.SHAMAN.practice_cast_seconds) ~= "function"
                or type(ST.SHAMAN.new_practice_session) ~= "function"
                or type(ST.SHAMAN.tick_practice_session) ~= "function"
                or type(ST.SHAMAN.practice_cast) ~= "function" then
                return false
            end
            local duration = ctx and ctx.base_speed
            if type(duration) ~= "number" or duration <= 0 then
                duration = 3.5
            end
            if type(self.mainhand) == "table" then
                ui.saved_hand_speed = self.mainhand.speed
            else
                ui.saved_hand_speed = nil
            end
            local ok_lat, latency = pcall(ST.SHAMAN.practice_latency_seconds)
            if not ok_lat or type(latency) ~= "number" then
                latency = 0
            end
            local ok_cast, cast = pcall(ST.SHAMAN.practice_cast_seconds, "weave_lb")
            if not ok_cast or type(cast) ~= "number" then
                local pr = st.practice
                local defaults = pr and pr.harness and pr.harness.WEAVE_DEFAULTS
                cast = (defaults and defaults.effective_cast) or 1.5
            end
            -- Grade-path resolvability: the drill grades through the weave marker;
            -- if the marker cannot resolve (weave model absent), in-fight casts
            -- would never score. Fail closed here instead of a scoreless session.
            local pr = st.practice
            local harness = pr and pr.harness
            local ok_marker, marker = false, nil
            if type(harness) == "table"
                and type(harness.weave_marker_fraction) == "function" then
                ok_marker, marker = pcall(harness.weave_marker_fraction,
                    duration, cast, latency)
            end
            if not ok_marker or type(marker) ~= "number" then
                return false
            end
            local ok_new, session = pcall(function()
                return ST.SHAMAN.new_practice_session(now, {
                    swing_duration = duration,
                    effective_cast = cast,
                    latency = latency,
                })
            end)
            if not ok_new or session == nil then
                return false
            end
            ui.shaman_session = session
            ui.shaman_swing = {
                swing_duration = duration,
                swing_start = now,
                swing_ends_at = now + duration,
            }
            ui.shaman_out = {}
            ui.base_speed = duration
            return true
        end,
        tick = function(self, now, elapsed, ui)
            local session = ui.shaman_session
            local swing = ui.shaman_swing
            if session == nil or swing == nil then
                return
            end
            local duration = swing.swing_duration
            if type(duration) ~= "number" or duration <= 0 then
                return
            end
            if session.active then
                -- Roll the drill swing (cap catch-up after a hitch so one frame
                -- never fast-forwards the whole drill).
                local guard = 0
                while now >= swing.swing_ends_at and guard < 8 do
                    swing.swing_start = swing.swing_ends_at
                    swing.swing_ends_at = swing.swing_ends_at + duration
                    guard = guard + 1
                end
            end
            local out = ST.SHAMAN.tick_practice_session(session, now, elapsed,
                ui.shaman_out)
            ui.shaman_out = out
            ui.update_fight_timer(self, now)
            ui.sync_to_addon(self)
        end,
        cast = function(self, key, ui)
            local session = ui.shaman_session
            local swing = ui.shaman_swing
            if session == nil or swing == nil then
                return nil
            end
            return ST.SHAMAN.practice_cast(session, swing, api.get_time(), key)
        end,
        stop = function(self, ui)
            local session = ui.shaman_session
            if session == nil then
                return
            end
            if type(ST.SHAMAN.end_practice_session) == "function" then
                ST.SHAMAN.end_practice_session(session, api.get_time())
            end
            ui.shaman_session = nil
            ui.shaman_swing = nil
        end,
        begin = function(self, now, ui)
            if ui.shaman_session and type(ST.SHAMAN.practice_begin_session) == "function" then
                ST.SHAMAN.practice_begin_session(ui.shaman_session, now)
            end
        end,
        end_session = function(self, ui)
            if ui.shaman_session and type(ST.SHAMAN.end_practice_session) == "function" then
                ST.SHAMAN.end_practice_session(ui.shaman_session, api.get_time())
            end
        end,
        pause = function(self, ui, shift)
            local swing = ui.shaman_swing
            if swing then
                swing.swing_start = swing.swing_start + shift
                swing.swing_ends_at = swing.swing_ends_at + shift
            end
        end,
        sync = function(self, ui)
            local swing = ui.shaman_swing
            local session = ui.shaman_session
            local now = api.get_time()
            local d = self.mainhand
            if swing and type(swing.swing_duration) == "number" and swing.swing_duration > 0
                and type(swing.swing_start) == "number"
                and type(swing.swing_ends_at) == "number" then
                d.speed = swing.swing_duration
                d.start = swing.swing_start
                d.ends_at = swing.swing_ends_at
                d.is_paused = not (session and session.active)
            else
                d.speed = ui.base_speed or d.speed or 3.5
                d.start = now
                d.ends_at = now + (d.speed or 3.5)
                d.is_paused = true
            end
            d.is_full = false
            if ui.combat_paused then
                d.is_paused = true
            end
            if type(ST.SHAMAN.practice_sync) == "function" then
                ST.SHAMAN.practice_sync(self)
            end
            self:show_bar("mainhand")
        end,
        clear = function(self, ui)
            local now = api.get_time()
            local d = self.mainhand
            d.speed = ui.saved_hand_speed or d.speed
            local speed = d.speed or 3.5
            d.start = now - speed
            d.ends_at = now
            d.current_progress = 1
            d.is_full = true
            d.is_paused = false
            self:on_bar_inactive("mainhand")
            self:handle_bar_visibility("mainhand")
        end,
    },
}

if st.debug then st.utils.print_msg('-- Parsed classes/shaman.lua module correctly (weaving)') end

end

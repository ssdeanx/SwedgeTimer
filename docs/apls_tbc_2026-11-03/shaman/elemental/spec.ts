import * as OtherInputs from '@features/settings/model/other_inputs';
import { APLRotation } from '@generated/proto/apl';
import { ItemSlot, PseudoStat, Spec, Stat } from '@generated/proto/common';
import { PlayerClasses } from '@sim/player/classes';
import { Player } from '@sim/player/player';
import { DEFAULT_HYBRID_CASTER_GEM_STATS, Stats, UnitStat } from '@sim/proto/stats';
import { defineSpec } from '@sim/spec_config';

import * as ShamanInputs from '../shared/inputs';
import * as Presets from './presets';

export default defineSpec<Spec.SpecElementalShaman>({
	spec: Spec.SpecElementalShaman,

	className: 'elemental-shaman-sim-ui',
	cssScheme: PlayerClasses.getCssScheme(PlayerClasses.Shaman),
	// List any known bugs / issues here and they'll be shown on the site.
	knownIssues: [],
	warnings: [],

	// All stats for which EP should be calculated.
	epStats: [
		Stat.StatIntellect,
		Stat.StatSpellDamage,
		Stat.StatNatureDamage,
		Stat.StatSpellHitRating,
		Stat.StatSpellCritRating,
		Stat.StatSpellHasteRating,
		Stat.StatMP5,
	],
	epPseudoStats: [PseudoStat.PseudoStatSchoolHitPercentNature],
	// Reference stat against which to calculate EP.
	epReferenceStat: Stat.StatSpellDamage,
	// Which stats to display in the Character Stats section, at the bottom of the left-hand sidebar.
	displayStats: UnitStat.createDisplayStatArray(
		[
			Stat.StatHealth,
			Stat.StatMana,
			Stat.StatStamina,
			Stat.StatIntellect,
			Stat.StatSpellDamage,
			Stat.StatNatureDamage,
			Stat.StatMP5,
			Stat.StatArcaneResistance,
			Stat.StatFireResistance,
			Stat.StatFrostResistance,
			Stat.StatNatureResistance,
			Stat.StatShadowResistance,
		],
		[
			PseudoStat.PseudoStatSpellCritPercent,
			PseudoStat.PseudoStatSpellHastePercent,
			PseudoStat.PseudoStatSpellHitPercent,
			PseudoStat.PseudoStatSchoolHitPercentNature,
		],
	),
	gemStats: DEFAULT_HYBRID_CASTER_GEM_STATS,
	defaults: {
		// Default equipped gear.
		gear: Presets.P3_PRESET.gear,
		// Default EP weights for sorting gear in the gear picker.
		epWeights: Presets.EP_PRESET_DEFAULT.epWeights,
		statCaps: (() => {
			return new Stats().withPseudoStat(PseudoStat.PseudoStatSchoolHitPercentNature, 16);
		})(),
		// Default consumes settings.
		consumables: Presets.DefaultConsumables,
		// Default talents.
		talents: Presets.StandardTalents.data,
		// Default spec-specific settings.
		specOptions: Presets.DefaultOptions,
		other: Presets.OtherDefaults,
		// Default raid/party buffs settings.
		raidBuffs: Presets.DefaultRaidBuffs,
		partyBuffs: Presets.DefaultPartyBuffs,
		individualBuffs: Presets.DefaultIndividualBuffs,
		debuffs: Presets.DefaultDebuffs,
	},
	// IconInputs to include in the 'Player' section on the settings tab.
	playerIconInputs: [],
	// Buff and Debuff inputs to include/exclude, overriding the EP-based defaults.
	includeBuffDebuffInputs: [Stat.StatAttackPower, Stat.StatFireDamage],
	excludeBuffDebuffInputs: [],
	// Inputs to include in the 'Other' section on the settings tab.
	otherInputs: {
		inputs: [ShamanInputs.ShamanShieldProcrate(), OtherInputs.InputDelay, OtherInputs.TankAssignment, OtherInputs.DistanceFromTarget],
	},
	itemSwapSlots: [ItemSlot.ItemSlotTrinket1, ItemSlot.ItemSlotTrinket2, ItemSlot.ItemSlotMainHand, ItemSlot.ItemSlotOffHand],
	encounterPicker: {
		// Whether to include 'Execute Duration (%)' in the 'Encounter' section of the settings tab.
		showExecuteProportion: false,
	},

	presets: {
		epWeights: [Presets.EP_PRESET_DEFAULT],
		// Preset talents that the user can quickly select.
		talents: [Presets.StandardTalents],
		// Preset rotations that the user can quickly select.
		rotations: [Presets.ROTATION_PRESET_DEFAULT],
		// Preset gear configurations that the user can quickly select.
		gear: [Presets.PRERAID_PRESET, Presets.P1_PRESET_A, Presets.P1_PRESET_H, Presets.P2_PRESET, Presets.P3_PRESET, Presets.P4_PRESET, Presets.P5_PRESET],
		// Preset build combinations that the user can quickly select.
		builds: [Presets.P1_PRESET_BUILD_DEFAULT],
	},

	autoRotation: (_player: Player<Spec.SpecElementalShaman>): APLRotation => {
		return Presets.ROTATION_PRESET_DEFAULT.rotation.rotation!;
	},

	reforge: {},
});

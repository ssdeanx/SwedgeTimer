import * as OtherInputs from '@features/settings/model/other_inputs';
import { StatCapType } from '@generated/proto/api';
import { APLRotation } from '@generated/proto/apl';
import { ItemSlot, PseudoStat, Spec, Stat } from '@generated/proto/common';
import * as Mechanics from '@sim/constants/mechanics';
import { PlayerClasses } from '@sim/player/classes';
import { Player } from '@sim/player/player';
import { StatCap, Stats, UnitStat } from '@sim/proto/stats';
import { defineSpec } from '@sim/spec_config';

import * as ShamanInputs from '../shared/inputs';
import * as EnhancementInputs from './inputs';
import * as Presets from './presets';

export default defineSpec<Spec.SpecEnhancementShaman>({
	spec: Spec.SpecEnhancementShaman,

	className: 'enhancement-shaman-sim-ui',
	cssScheme: PlayerClasses.getCssScheme(PlayerClasses.Shaman),
	// List any known bugs / issues here and they'll be shown on the site.
	knownIssues: [],
	warnings: [],

	// All stats for which EP should be calculated.
	epStats: [
		Stat.StatStrength,
		Stat.StatAgility,
		Stat.StatIntellect,
		Stat.StatAttackPower,
		Stat.StatMeleeHitRating,
		Stat.StatMeleeCritRating,
		Stat.StatMeleeHasteRating,
		Stat.StatExpertiseRating,
		Stat.StatArmorPenetration,
		Stat.StatSpellDamage,
		Stat.StatNatureDamage,
		Stat.StatSpellHitRating,
		Stat.StatSpellCritRating,
	],
	epPseudoStats: [PseudoStat.PseudoStatMainHandDps, PseudoStat.PseudoStatOffHandDps],
	// Reference stat against which to calculate EP.
	epReferenceStat: Stat.StatAttackPower,
	consumableStats: [Stat.StatMana, Stat.StatMP5],
	// Which stats to display in the Character Stats section, at the bottom of the left-hand sidebar.
	displayStats: UnitStat.createDisplayStatArray(
		[
			Stat.StatHealth,
			Stat.StatStamina,
			Stat.StatStrength,
			Stat.StatAgility,
			Stat.StatIntellect,
			Stat.StatMana,
			Stat.StatAttackPower,
			Stat.StatExpertiseRating,
			Stat.StatArmorPenetration,
			Stat.StatSpellDamage,
			Stat.StatNatureDamage,
			Stat.StatArcaneResistance,
			Stat.StatFireResistance,
			Stat.StatFrostResistance,
			Stat.StatNatureResistance,
			Stat.StatShadowResistance,
		],
		[
			PseudoStat.PseudoStatMeleeHitPercent,
			PseudoStat.PseudoStatMeleeCritPercent,
			PseudoStat.PseudoStatMeleeHastePercent,
			PseudoStat.PseudoStatSpellHitPercent,
			PseudoStat.PseudoStatSpellCritPercent,
			PseudoStat.PseudoStatSpellHastePercent,
		],
	),

	defaults: {
		// Default equipped gear.
		gear: Presets.P3_PRESET.gear,
		// Default EP weights for sorting gear in the gear picker.
		epWeights: Presets.P3_EP_PRESET.epWeights,
		statCaps: (() => {
			const expCap = new Stats().withStat(Stat.StatExpertiseRating, 6.5 * 4 * Mechanics.EXPERTISE_PER_QUARTER_PERCENT_REDUCTION);
			return expCap;
		})(),
		softCapBreakpoints: (() => {
			const meleeHitSoftCapConfig = StatCap.fromPseudoStat(PseudoStat.PseudoStatMeleeHitPercent, {
				breakpoints: [9, 20, 28],
				capType: StatCapType.TypeSoftCap,
				postCapEPs: [1.9 * Mechanics.PHYSICAL_HIT_RATING_PER_HIT_PERCENT, 1.73 * Mechanics.PHYSICAL_HIT_RATING_PER_HIT_PERCENT, 0],
			});

			return [meleeHitSoftCapConfig];
		})(),
		other: Presets.OtherDefaults,
		// Default consumes settings.
		consumables: Presets.DefaultConsumables,
		// Default talents.
		talents: Presets.SubRestoIWT.data,
		itemSwap: Presets.P1_TRUNCHEON_ITEMSWAP_PRESET.itemSwap,
		// Default spec-specific settings.
		specOptions: Presets.DefaultOptions,
		// Default raid/party buffs settings.
		raidBuffs: Presets.DefaultRaidBuffs,
		partyBuffs: Presets.DefaultPartyBuffs,
		individualBuffs: Presets.DefaultIndividualBuffs,
		debuffs: Presets.DefaultDebuffs,
	},

	// IconInputs to include in the 'Player' section on the settings tab.
	playerIconInputs: [ShamanInputs.ShamanImbueMH(), EnhancementInputs.ShamanImbueOH, ShamanInputs.ShamanImbueMHSwap(), EnhancementInputs.ShamanImbueOHSwap],
	// Buff and Debuff inputs to include/exclude, overriding the EP-based defaults.
	includeBuffDebuffInputs: [Stat.StatMP5, Stat.StatFireDamage],
	excludeBuffDebuffInputs: [],
	// Inputs to include in the 'Other' section on the settings tab.
	otherInputs: {
		inputs: [
			EnhancementInputs.SyncTypeInput,
			ShamanInputs.ShamanShieldProcrate(),
			OtherInputs.InputDelay,
			OtherInputs.TankAssignment,
			OtherInputs.InFrontOfTarget,
		],
	},
	itemSwapSlots: [ItemSlot.ItemSlotTrinket1, ItemSlot.ItemSlotTrinket2, ItemSlot.ItemSlotMainHand, ItemSlot.ItemSlotOffHand],
	encounterPicker: {
		// Whether to include 'Execute Duration (%)' in the 'Encounter' section of the settings tab.
		showExecuteProportion: false,
	},

	presets: {
		epWeights: [Presets.P1_EP_PRESET, Presets.P3_EP_PRESET],
		// Preset talents that the user can quickly select.
		talents: [Presets.SubRestoIWT, Presets.SubRestoILS, Presets.SubEle],
		// Preset rotations that the user can quickly select.
		rotations: [Presets.ROTATION_PRESET_DEFAULT],
		// Preset gear configurations that the user can quickly select.
		gear: [Presets.PRERAID_PRESET, Presets.P1_PRESET, Presets.P2_PRESET, Presets.P3_PRESET, Presets.P4_PRESET, Presets.P5_PRESET],

		itemSwaps: [Presets.P1_BADGEOH_ITEMSWAP_PRESET, Presets.P1_TRUNCHEON_ITEMSWAP_PRESET, Presets.P1_BIS_ITEMSWAP_PRESET],
	},

	autoRotation: (_: Player<Spec.SpecEnhancementShaman>): APLRotation => {
		return Presets.ROTATION_PRESET_DEFAULT.rotation.rotation!;
	},

	reforge: {},
});

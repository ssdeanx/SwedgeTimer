import * as OtherInputs from '@features/settings/model/other_inputs';
import { StatCapType } from '@generated/proto/api';
import { APLRotation } from '@generated/proto/apl';
import { Debuffs, Drums, IndividualBuffs, ItemSlot, PartyBuffs, PseudoStat, RaidBuffs, Spec, Stat, TristateEffect } from '@generated/proto/common';
import * as Mechanics from '@sim/constants/mechanics';
import { PlayerClasses } from '@sim/player/classes';
import { Player } from '@sim/player/player';
import { StatCap, Stats, UnitStat } from '@sim/proto/stats';
import { defaultExposeWeaknessSettings, defaultRaidBuffMajorDamageCooldowns } from '@sim/proto/utils';
import { defineSpec } from '@sim/spec_config';

import * as Presets from './presets';

export default defineSpec<Spec.SpecRogue>({
	spec: Spec.SpecRogue,

	className: 'rogue-sim-ui',
	cssScheme: PlayerClasses.getCssScheme(PlayerClasses.Rogue),
	// List any known bugs / issues here and they'll be shown on the site.
	knownIssues: [
		'The APL is in constant flux due to bug fixes and new findings; if your DPS drops dramatically, reset it back to "Auto" in the Rotation tab!',
		'Mutilate does not have a default APL currently. It will not be automatically used when talented.',
	],

	// All stats for which EP should be calculated.
	epStats: [
		Stat.StatStamina,
		Stat.StatAgility,
		Stat.StatStrength,
		Stat.StatMeleeCritRating,
		Stat.StatMeleeHasteRating,
		Stat.StatMeleeHitRating,
		Stat.StatArmorPenetration,
		Stat.StatExpertiseRating,
		Stat.StatAttackPower,
		Stat.StatPhysicalDamage,
	],
	epPseudoStats: [PseudoStat.PseudoStatMainHandDps, PseudoStat.PseudoStatOffHandDps],
	// Reference stat against which to calculate EP.
	epReferenceStat: Stat.StatAttackPower,
	// Which stats to display in the Character Stats section, at the bottom of the left-hand sidebar.
	displayStats: UnitStat.createDisplayStatArray(
		[
			Stat.StatHealth,
			Stat.StatStamina,
			Stat.StatAgility,
			Stat.StatStrength,
			Stat.StatAttackPower,
			Stat.StatArmorPenetration,
			Stat.StatExpertiseRating,
			Stat.StatArcaneResistance,
			Stat.StatFireResistance,
			Stat.StatFrostResistance,
			Stat.StatNatureResistance,
			Stat.StatShadowResistance,
		],
		[PseudoStat.PseudoStatMeleeHitPercent, PseudoStat.PseudoStatMeleeCritPercent, PseudoStat.PseudoStatMeleeHastePercent],
	),

	defaults: {
		// Default equipped gear.
		gear: Presets.P3_SWORDS_GEAR.gear,
		// Default EP weights for sorting gear in the gear picker.
		epWeights: Presets.P1_EP_PRESET.epWeights,
		statCaps: (() => {
			const expCap = new Stats().withStat(Stat.StatExpertiseRating, 6.5 * 4 * Mechanics.EXPERTISE_PER_QUARTER_PERCENT_REDUCTION);
			return expCap;
		})(),
		softCapBreakpoints: (() => {
			const meleeHitSoftCapConfig = StatCap.fromPseudoStat(PseudoStat.PseudoStatMeleeHitPercent, {
				breakpoints: [9, 28],
				capType: StatCapType.TypeSoftCap,
				postCapEPs: [3.06 * Mechanics.PHYSICAL_HIT_RATING_PER_HIT_PERCENT, 0],
			});

			return [meleeHitSoftCapConfig];
		})(),
		other: Presets.OtherDefaults,
		// Default consumes settings.
		consumables: Presets.DefaultConsumables,
		// Default talents.
		talents: Presets.Talents.data,
		// Default spec-specific settings.
		specOptions: Presets.DefaultOptions,
		// Default raid/party buffs settings.
		raidBuffs: RaidBuffs.create({
			...defaultRaidBuffMajorDamageCooldowns(),
			giftOfTheWild: TristateEffect.TristateEffectImproved,
		}),
		partyBuffs: PartyBuffs.create({
			battleShout: TristateEffect.TristateEffectImproved,
			ferociousInspiration: 1,
			strengthOfEarthTotem: TristateEffect.TristateEffectImproved,
			graceOfAirTotem: TristateEffect.TristateEffectImproved,
			windfuryTotem: TristateEffect.TristateEffectImproved,
			leaderOfThePack: TristateEffect.TristateEffectRegular,
			totemTwisting: true,
			drums: Drums.LesserDrumsOfBattle,
		}),
		individualBuffs: IndividualBuffs.create({
			blessingOfKings: true,
			blessingOfMight: TristateEffect.TristateEffectImproved,
			unleashedRage: true,
		}),
		debuffs: Debuffs.create({
			...defaultExposeWeaknessSettings(),
			bloodFrenzy: true,
			huntersMark: TristateEffect.TristateEffectImproved,
			improvedSealOfTheCrusader: TristateEffect.TristateEffectImproved,
			mangle: true,
			misery: true,
			curseOfRecklessness: true,
			faerieFire: TristateEffect.TristateEffectImproved,
			giftOfArthas: true,
			sunderArmor: true,
		}),
	},

	playerInputs: {
		inputs: [],
	},
	// IconInputs to include in the 'Player' section on the settings tab.
	playerIconInputs: [],
	// Buff and Debuff inputs to include/exclude, overriding the EP-based defaults.
	includeBuffDebuffInputs: [Stat.StatSpellHitRating],
	excludeBuffDebuffInputs: [],
	// Inputs to include in the 'Other' section on the settings tab.
	otherInputs: {
		inputs: [OtherInputs.TotemTwisting, OtherInputs.InFrontOfTarget, OtherInputs.InputDelay],
	},
	itemSwapSlots: [ItemSlot.ItemSlotTrinket1, ItemSlot.ItemSlotTrinket2, ItemSlot.ItemSlotMainHand, ItemSlot.ItemSlotOffHand],
	encounterPicker: {
		// Whether to include 'Execute Duration (%)' in the 'Encounter' section of the settings tab.
		showExecuteProportion: false,
	},

	presets: {
		epWeights: [Presets.P1_EP_PRESET],
		// Preset talents that the user can quickly select.
		talents: [Presets.Talents],
		// Preset rotations that the user can quickly select.
		rotations: [Presets.SINSITER_APL],
		// Preset gear configurations that the user can quickly select.
		gear: [Presets.PREARAID_SWORDS_GEAR, Presets.P1_SWORDS_GEAR, Presets.P2_SWORDS_GEAR, Presets.P3_SWORDS_GEAR],
	},

	autoRotation: (_player: Player<Spec.SpecRogue>): APLRotation => {
		return Presets.SINSITER_APL.rotation.rotation!;
	},

	reforge: {},
});

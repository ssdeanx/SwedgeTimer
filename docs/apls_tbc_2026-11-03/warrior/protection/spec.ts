import * as OtherInputs from '@features/settings/model/other_inputs';
import { APLRotation } from '@generated/proto/apl';
import { Debuffs, IndividualBuffs, ItemSlot, PartyBuffs, PseudoStat, RaidBuffs, Spec, Stat, TristateEffect } from '@generated/proto/common';
import * as Mechanics from '@sim/constants/mechanics';
import { PlayerClasses } from '@sim/player/classes';
import { Player } from '@sim/player/player';
import { Stats, UnitStat } from '@sim/proto/stats';
import { defineSpec } from '@sim/spec_config';

import * as WarriorInputs from '../shared/inputs';
import * as WarriorPresets from '../shared/presets';
import * as Presets from './presets';

export default defineSpec<Spec.SpecProtectionWarrior>({
	spec: Spec.SpecProtectionWarrior,
	enableHealing: true,

	className: 'protection-warrior-sim-ui',
	cssScheme: PlayerClasses.getCssScheme(PlayerClasses.Warrior),
	// List any known bugs / issues here and they'll be shown on the site.
	knownIssues: [],

	epRatios: [0, 0, 0.6, 0, 1.15, 0],
	// All stats for which EP should be calculated.
	epStats: [
		Stat.StatStamina,
		Stat.StatStrength,
		Stat.StatAgility,
		Stat.StatAttackPower,
		Stat.StatMeleeHitRating,
		Stat.StatMeleeHasteRating,
		Stat.StatMeleeCritRating,
		Stat.StatArmorPenetration,
		Stat.StatExpertiseRating,
		Stat.StatResilienceRating,
		Stat.StatDefenseRating,
		Stat.StatBlockRating,
		Stat.StatBlockValue,
		Stat.StatDodgeRating,
		Stat.StatParryRating,
		Stat.StatArmor,
		Stat.StatBonusArmor,
	],
	epPseudoStats: [PseudoStat.PseudoStatMainHandDps],
	// Reference stat against which to calculate EP. I think all classes use either spell power or attack power.
	epReferenceStat: Stat.StatStrength,
	tankRefStat: Stat.StatStamina,
	// Which stats to display in the Character Stats section, at the bottom of the left-hand sidebar.
	displayStats: UnitStat.createDisplayStatArray(
		[
			Stat.StatHealth,
			Stat.StatArmor,
			Stat.StatBonusArmor,
			Stat.StatStamina,
			Stat.StatStrength,
			Stat.StatAgility,
			Stat.StatAttackPower,
			Stat.StatBlockValue,
			Stat.StatDefenseRating,
			Stat.StatExpertiseRating,
			Stat.StatResilienceRating,
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
			PseudoStat.PseudoStatBlockPercent,
			PseudoStat.PseudoStatDodgePercent,
			PseudoStat.PseudoStatParryPercent,
		],
	),

	defaults: {
		// Default equipped gear.
		gear: Presets.P3_PRESET.gear,
		// Default EP weights for sorting gear in the gear picker.
		epWeights: Presets.P1_EP_PRESET.epWeights,
		statCaps: (() => {
			const hitCap = new Stats().withPseudoStat(PseudoStat.PseudoStatMeleeHitPercent, 9);
			const expCap = new Stats().withStat(Stat.StatExpertiseRating, 6.5 * 4 * Mechanics.EXPERTISE_PER_QUARTER_PERCENT_REDUCTION);
			const critImmunityCap = new Stats().withPseudoStat(PseudoStat.PseudoStatReducedCritTakenPercent, 5.6);

			return hitCap.add(expCap).add(critImmunityCap);
		})(),
		other: Presets.OtherDefaults,
		// Default consumes settings.
		consumables: Presets.DefaultConsumables,
		// Default talents.
		talents: Presets.DefaultTalents.data,
		// Default spec-specific settings.
		specOptions: Presets.DefaultOptions,
		// Default raid/party buffs settings.
		raidBuffs: RaidBuffs.create({
			...WarriorPresets.DefaultRaidBuffs,
			thorns: TristateEffect.TristateEffectRegular,
			shadowProtection: true,
		}),
		partyBuffs: PartyBuffs.create({
			sanctityAura: TristateEffect.TristateEffectImproved,
			braidedEterniumChain: true,
			graceOfAirTotem: TristateEffect.TristateEffectImproved,
			strengthOfEarthTotem: TristateEffect.TristateEffectImproved,
			windfuryTotem: TristateEffect.TristateEffectImproved,
			totemTwisting: true,
			battleShout: TristateEffect.TristateEffectImproved,
		}),
		individualBuffs: IndividualBuffs.create({
			...WarriorPresets.DefaultIndividualBuffs,
			blessingOfSanctuary: true,
		}),
		debuffs: Debuffs.create({
			...WarriorPresets.DefaultDebuffs,
			giftOfArthas: false,
			insectSwarm: true,
			shadowEmbrace: true,
			screech: true,
		}),
	},

	// IconInputs to include in the 'Player' section on the settings tab.
	// The two Battle Shout icon toggles used to sit in `otherInputs`; icon pickers are not part
	// of the `InputConfig` union any more, so they join the player icon row.
	playerIconInputs: [WarriorInputs.ShoutPicker(), WarriorInputs.StancePicker(), WarriorInputs.BattleShoutSolarianSapphire(), WarriorInputs.BattleShoutT2()],
	// Buff and Debuff inputs to include/exclude, overriding the EP-based defaults.
	includeBuffDebuffInputs: [],
	excludeBuffDebuffInputs: [],
	// Inputs to include in the 'Other' section on the settings tab.
	otherInputs: {
		inputs: [
			OtherInputs.TotemTwisting,
			WarriorInputs.StartingRage(),
			WarriorInputs.StanceSnapshot(),
			WarriorInputs.QueueDelay(),
			OtherInputs.InputDelay,
			OtherInputs.TankAssignment,
			OtherInputs.InspirationUptime,
			OtherInputs.IncomingHps,
			OtherInputs.HealingCadence,
			OtherInputs.HealingCadenceVariation,
			OtherInputs.AbsorbFrac,
			OtherInputs.BurstWindow,
			OtherInputs.HpPercentForDefensives,
			OtherInputs.InFrontOfTarget,
		],
	},
	itemSwapSlots: [ItemSlot.ItemSlotTrinket1, ItemSlot.ItemSlotTrinket2, ItemSlot.ItemSlotMainHand, ItemSlot.ItemSlotOffHand],
	defaultBuild: Presets.MAGTHERIDON_PRESET_BUILD,

	encounterPicker: {
		// Whether to include 'Execute DuratFion (%)' in the 'Encounter' section of the settings tab.
		showExecuteProportion: false,
	},

	presets: {
		epWeights: [Presets.P1_EP_PRESET],
		// Preset talents that the user can quickly select.
		talents: [Presets.DefaultTalents],
		// Preset rotations that the user can quickly select.
		rotations: [Presets.ROTATION_DEFAULT],
		// Preset gear configurations that the user can quickly select.
		gear: [
			Presets.PRERAID_BALANCED_PRESET,
			Presets.P1_PRESET,
			Presets.P2_PRESET,
			Presets.P2_HYDROSS_PRESET,
			Presets.P3_PRESET,
			Presets.P4_PRESET,
			Presets.P5_PRESET,
		],
		builds: [
			Presets.DEFAULT_PRESET_BUILD,
			Presets.KARAZHAN_PRESET_BUILD,
			Presets.MAGTHERIDON_PRESET_BUILD,
			Presets.MOROGRIM_PRESET_BUILD,
			Presets.HYDROSS_PRESET_BUILD,
			Presets.GOREFIEND_PRESET_BUILD,
			Presets.ARCHIMONDE_PRESET_BUILD,
			Presets.P1_PRESET_BUILD,
		],
	},

	autoRotation: (_player: Player<Spec.SpecProtectionWarrior>): APLRotation => {
		return Presets.ROTATION_DEFAULT.rotation.rotation!;
	},

	reforge: {},
});

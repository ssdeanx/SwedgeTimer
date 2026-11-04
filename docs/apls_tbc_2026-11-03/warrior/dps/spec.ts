import * as OtherInputs from '@features/settings/model/other_inputs';
import { StatCapType } from '@generated/proto/api';
import { APLRotation, APLRotation_Type, SimpleRotation } from '@generated/proto/apl';
import { Cooldowns, HandType, ItemSlot, PseudoStat, Spec, Stat } from '@generated/proto/common';
import { DpsWarriorSpec, WarriorSunder } from '@generated/proto/warrior';
import * as Mechanics from '@sim/constants/mechanics';
import { PlayerClasses } from '@sim/player/classes';
import { Player } from '@sim/player/player';
import { SpecRotation } from '@sim/proto/spec_types';
import { DEFAULT_MELEE_GEM_STATS, StatCap, Stats, UnitStat } from '@sim/proto/stats';
import { defineSpec } from '@sim/spec_config';

import * as WarriorInputs from '../shared/inputs';
import * as WarriorPresets from '../shared/presets';
import * as DpsWarriorInputs from './inputs';
import * as Presets from './presets';

export default defineSpec<Spec.SpecDpsWarrior>({
	spec: Spec.SpecDpsWarrior,

	className: 'dps-warrior-sim-ui',
	cssScheme: PlayerClasses.getCssScheme(PlayerClasses.Warrior),
	// List any known bugs / issues here and they'll be shown on the site.
	knownIssues: [],

	// All stats for which EP should be calculated.
	epStats: [
		Stat.StatStrength,
		Stat.StatAgility,
		Stat.StatAttackPower,
		Stat.StatArmorPenetration,
		Stat.StatMeleeHitRating,
		Stat.StatMeleeHasteRating,
		Stat.StatMeleeCritRating,
		Stat.StatExpertiseRating,
	],
	epPseudoStats: [PseudoStat.PseudoStatMainHandDps, PseudoStat.PseudoStatOffHandDps],
	// Reference stat against which to calculate EP. I think all classes use either spell power or attack power.
	epReferenceStat: Stat.StatStrength,
	gemStats: DEFAULT_MELEE_GEM_STATS,
	// Which stats to display in the Character Stats section, at the bottom of the left-hand sidebar.
	displayStats: UnitStat.createDisplayStatArray(
		[
			Stat.StatHealth,
			Stat.StatStamina,
			Stat.StatStrength,
			Stat.StatAgility,
			Stat.StatAttackPower,
			Stat.StatExpertiseRating,
			Stat.StatArmorPenetration,
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
		gear: Presets.P3_BIS_FURY_PRESET.gear,
		// Default EP weights for sorting gear in the gear picker.
		epWeights: Presets.P2_FURY_EP_PRESET.epWeights,
		statCaps: (() => {
			const expCap = new Stats().withStat(Stat.StatExpertiseRating, 6.5 * 4 * Mechanics.EXPERTISE_PER_QUARTER_PERCENT_REDUCTION);
			return expCap;
		})(),
		softCapBreakpoints: (() => {
			const meleeHitSoftCapConfig = StatCap.fromPseudoStat(PseudoStat.PseudoStatMeleeHitPercent, {
				breakpoints: [9, 28],
				capType: StatCapType.TypeSoftCap,
				postCapEPs: [0.57 * Mechanics.PHYSICAL_HIT_RATING_PER_HIT_PERCENT, 0],
			});

			return [meleeHitSoftCapConfig];
		})(),
		rotationType: APLRotation_Type.TypeSimple,
		simpleRotation: Presets.SIMPLE_ROTATION,
		other: Presets.OtherDefaults,
		// Default consumes settings.
		consumables: Presets.DefaultConsumables,
		// Default talents.
		talents: Presets.FuryTalents.data,
		// Default spec-specific settings.
		specOptions: Presets.DefaultOptions,
		// Default raid/party buffs settings.
		raidBuffs: WarriorPresets.DefaultRaidBuffs,
		partyBuffs: WarriorPresets.DefaultPartyBuffs,
		individualBuffs: WarriorPresets.DefaultIndividualBuffs,
		debuffs: WarriorPresets.DefaultDebuffs,
	},

	// IconInputs to include in the 'Player' section on the settings tab.
	// The two Battle Shout icon toggles used to sit in `otherInputs`; icon pickers are not part
	// of the `InputConfig` union any more, so they join the player icon row.
	playerIconInputs: [WarriorInputs.ShoutPicker(), WarriorInputs.StancePicker(), WarriorInputs.BattleShoutSolarianSapphire(), WarriorInputs.BattleShoutT2()],
	// Buff and Debuff inputs to include/exclude, overriding the EP-based defaults.
	includeBuffDebuffInputs: [],
	excludeBuffDebuffInputs: [],
	rotationInputs: DpsWarriorInputs.RotationInputs,
	// `simpleRotation` below never reads its Cooldowns argument.
	hideSimpleCooldowns: true,
	// Inputs to include in the 'Other' section on the settings tab.
	otherInputs: {
		inputs: [
			OtherInputs.TotemTwisting,
			WarriorInputs.StartingRage(),
			WarriorInputs.StanceSnapshot(),
			OtherInputs.DistanceFromTarget,
			WarriorInputs.QueueDelay(),
			OtherInputs.InputDelay,
			OtherInputs.TankAssignment,
			OtherInputs.InFrontOfTarget,
		],
	},
	itemSwapSlots: [ItemSlot.ItemSlotTrinket1, ItemSlot.ItemSlotTrinket2, ItemSlot.ItemSlotMainHand, ItemSlot.ItemSlotOffHand],
	encounterPicker: {
		// Whether to include 'Execute Duration (%)' in the 'Encounter' section of the settings tab.
		showExecuteProportion: true,
	},

	presets: {
		epWeights: [Presets.P1_FURY_EP_PRESET, Presets.P2_FURY_EP_PRESET, Presets.P1_ARMS_EP_PRESET, Presets.P3_ARMS_EP_PRESET],
		// Preset talents that the user can quickly select.
		talents: [Presets.FuryTalents, Presets.ArmsTalents, Presets.ArmsKebabTalents],
		// Preset rotations that the user can quickly select.
		rotations: [Presets.SIMPLE_DEFAULT_ROTATION, Presets.FURY_DEFAULT_ROTATION, Presets.ARMS_DEFAULT_ROTATION],
		// Preset gear configurations that the user can quickly select.
		gear: [
			Presets.P1_PRERAID_FURY_PRESET,
			Presets.P1_BIS_FURY_PRESET,
			Presets.P2_BIS_FURY_PRESET,
			Presets.P3_BIS_FURY_PRESET,
			Presets.P4_BIS_FURY_PRESET,
			Presets.P5_BIS_FURY_PRESET,
			Presets.P1_PRERAID_ARMS_PRESET,
			Presets.P1_BIS_ARMS_PRESET,
			Presets.P2_BIS_ARMS_PRESET,
			Presets.P3_BIS_ARMS_PRESET,
			Presets.P4_BIS_ARMS_PRESET,
			Presets.P5_BIS_ARMS_PRESET,
		],
		builds: [
			Presets.PRESET_BUILD_FURY,
			Presets.PRESET_BUILD_ARMS,
			Presets.PRESET_BUILD_ARMS_KEBAB,
			Presets.P1_PRESET_BUILD_FURY,
			Presets.P2_PRESET_BUILD_FURY,
			Presets.P3_PRESET_BUILD_FURY,
			Presets.P4_PRESET_BUILD_FURY,
			Presets.P5_PRESET_BUILD_FURY,
			Presets.P1_PRESET_BUILD_ARMS,
			Presets.P2_PRESET_BUILD_ARMS,
			Presets.P3_PRESET_BUILD_ARMS,
			Presets.P4_PRESET_BUILD_ARMS,
			Presets.P5_PRESET_BUILD_ARMS,
		],
	},

	autoRotation: (player: Player<Spec.SpecDpsWarrior>): APLRotation => {
		if (Presets.isArmsSpec(player) || Presets.isArmsKebabSpec(player)) {
			return Presets.ARMS_DEFAULT_ROTATION.rotation.rotation!;
		}

		return Presets.FURY_DEFAULT_ROTATION.rotation.rotation!;
	},

	simpleRotation: (player: Player<Spec.SpecDpsWarrior>, simple: SpecRotation<Spec.SpecDpsWarrior>, _: Cooldowns): APLRotation => {
		let { spec, sunderArmor = WarriorSunder.WarriorSunderHelp, useOverpower = true, useRecklessness = false, bloodlustTiming = 5 } = simple;

		if (!spec) {
			if (Presets.isArmsSpec(player) || Presets.isArmsKebabSpec(player)) {
				spec = DpsWarriorSpec.DpsWarriorSpecArms;
			} else {
				spec = DpsWarriorSpec.DpsWarriorSpecFury;
			}
		}

		const rotation = APLRotation.clone(
			spec == DpsWarriorSpec.DpsWarriorSpecFury ? Presets.FURY_DEFAULT_ROTATION.rotation.rotation! : Presets.ARMS_DEFAULT_ROTATION.rotation.rotation!,
		);

		const bloodlustTimingVariable = rotation.valueVariables.find(variable => variable.name === 'Bloodlust time');
		if (bloodlustTimingVariable && bloodlustTimingVariable.value?.value.oneofKind === 'const')
			bloodlustTimingVariable.value.value.const.val = String(bloodlustTiming);

		const recklessnessAction = rotation.priorityList.find(
			action => action.action?.action.oneofKind === 'groupReference' && action.action.action.groupReference.groupName === 'Recklessness ON/OFF',
		);
		if (recklessnessAction) recklessnessAction.hide = !useRecklessness;

		const sunderArmorAction = rotation.priorityList.find(
			action => action.action?.action.oneofKind === 'groupReference' && action.action?.action.groupReference.groupName === 'Sunder Armor',
		);
		if (sunderArmorAction) sunderArmorAction.hide = sunderArmor == WarriorSunder.WarriorSunderNone;

		const opWeaveAction = rotation.priorityList.find(
			action => action.action?.action.oneofKind === 'groupReference' && action.action?.action.groupReference.groupName === 'Overpower Weaving',
		);
		if (opWeaveAction) opWeaveAction.hide = !useOverpower;

		return APLRotation.create({
			simple: SimpleRotation.create({}),
			...rotation,
		});
	},

	reforge: {
		updateSoftCaps: (softCaps, player, ctx) => {
			const gear = player.getGear();
			const mainHandType = gear.getEquippedItem(ItemSlot.ItemSlotMainHand)?.item.handType;
			const offHandType = gear.getEquippedItem(ItemSlot.ItemSlotOffHand)?.item.handType;
			const isFury =
				mainHandType &&
				[HandType.HandTypeOneHand, HandType.HandTypeMainHand].includes(mainHandType) &&
				offHandType &&
				[HandType.HandTypeOneHand, HandType.HandTypeOffHand].includes(offHandType);

			const softCapToModify = softCaps.find(sc => sc.unitStat.equalsPseudoStat(PseudoStat.PseudoStatMeleeHitPercent));
			if (softCapToModify) {
				if (isFury) {
					softCapToModify.breakpoints = ctx.defaults.softCapBreakpoints?.[0].breakpoints || [];
					softCapToModify.postCapEPs = ctx.defaults.softCapBreakpoints?.[0].postCapEPs || [];
				} else {
					softCapToModify.breakpoints = [9];
					softCapToModify.postCapEPs = [0];
				}
			}

			return softCaps;
		},
	},
});

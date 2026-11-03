import * as PresetUtils from '@app/preset_utils';
import * as Consumables from '@features/settings/model/consumables_auto_gen';
import { ConsumesSpec, PseudoStat, Spec, Stat } from '@generated/proto/common';
import { Rogue_Options as RogueOptions, Rogue_Rotation as RogueRotation } from '@generated/proto/rogue';
import { SavedTalents } from '@generated/proto/ui';
import { Stats } from '@sim/proto/stats';

import DefaultAPL from './apls/default.apl.json';
import P1BsCombatGear from './gear_sets/p1_bscombat.gear.json';
import P1BsSubGear from './gear_sets/p1_bssub.gear.json';
import P1MutiGear from './gear_sets/p1_muti.gear.json';
import P1SlowMhGear from './gear_sets/p1_slowmh.gear.json';

// Preset options for this spec.
// Eventually we will import these values for the raid sim too, so its good to
// keep them in a separate file.

export const TALENTS_MUTILATE_ASN = {
	name: 'Asn Muti',
	data: SavedTalents.create({
		talentsString: '00532310151501031-302303202014',
	}),
};
export const TALENTS_MUTILATE_COM = {
	name: 'Combat Muti',
	data: SavedTalents.create({
		talentsString: '00532310101401-302303202015152-001',
	}),
};
export const TALENTS_COMBAT_SS = {
	name: 'Combat SS',
	data: SavedTalents.create({
		talentsString: '005323101012-32030320201515231',
	}),
};
export const TALENTS_COMBAT_BS = {
	name: 'Combat BS',
	data: SavedTalents.create({
		talentsString: '00532310101-32030320201515231-002',
	}),
};
export const TALENTS_SUB_HEMO = {
	name: 'Subtlety Hemo',
	data: SavedTalents.create({
		talentsString: '005323101014--4323200300013211501',
	}),
};
export const TALENTS_SUB_BS = {
	name: 'Subtlety BS',
	data: SavedTalents.create({
		talentsString: '0053031-3203-4320203300013211051',
	}),
};

export const DEFAULT_APL = PresetUtils.makePresetAPLRotation('Direct APL', DefaultAPL);

export const DEFAULT_SIMPLE_ROTATION = RogueRotation.create({ useBackstab: false, useExposeArmor: false });
export const SIMPLE_ROTATION = PresetUtils.makePresetSimpleRotation('Configurable', Spec.SpecRogue, DEFAULT_SIMPLE_ROTATION);
const SIMPLE_BACKSTAB_BUILD_ROTATION = PresetUtils.makePresetSimpleRotation(
	'Configurable',
	Spec.SpecRogue,
	RogueRotation.create({ useBackstab: true, useExposeArmor: false }),
);

export const P1_BS_COMBAT_GEAR = PresetUtils.makePresetGear('Backstab Combat', P1BsCombatGear, { devOnly: true });
export const P1_MUTI_GEAR = PresetUtils.makePresetGear('Mutilate', P1MutiGear, { devOnly: true });
export const P1_SLOW_MH_GEAR = PresetUtils.makePresetGear('Slow Main Hand', P1SlowMhGear, { devOnly: true });
export const P1_BS_SUB_GEAR = PresetUtils.makePresetGear('Backstab Subtlety', P1BsSubGear, { devOnly: true });

// Preset options for EP weights
export const EP_PRESET_COMBAT_SINISTER = PresetUtils.makePresetEpWeights(
	'Combat Sinister',
	Stats.fromMap(
		{
			[Stat.StatStamina]: 0.01,
			[Stat.StatAgility]: 1.96,
			[Stat.StatStrength]: 1.1,
			[Stat.StatCritRating]: 1.7,
			[Stat.StatHasteRating]: 1.72,
			[Stat.StatHitRating]: 2.42,
			[Stat.StatExpertiseRating]: 2.55,
			[Stat.StatArmorPenetration]: 0.41,
			[Stat.StatSpellPiercing]: 0.19,
			[Stat.StatAttackPower]: 1.0,
			[Stat.StatPhysicalDamage]: 7.97,
		},
		{
			[PseudoStat.PseudoStatMainHandDps]: 10.57,
			[PseudoStat.PseudoStatOffHandDps]: 2.93,
		},
	),
);

export const EP_PRESET_COMBAT_DAGS = PresetUtils.makePresetEpWeights(
	'Combat Daggers',
	Stats.fromMap(
		{
			[Stat.StatStamina]: 0.01,
			[Stat.StatAgility]: 1.95,
			[Stat.StatStrength]: 1.1,
			[Stat.StatCritRating]: 1.68,
			[Stat.StatHasteRating]: 1.7,
			[Stat.StatHitRating]: 2.35,
			[Stat.StatExpertiseRating]: 2.21,
			[Stat.StatArmorPenetration]: 0.43,
			[Stat.StatSpellPiercing]: 0.21,
			[Stat.StatAttackPower]: 1.0,
			[Stat.StatPhysicalDamage]: 9.9,
		},
		{
			[PseudoStat.PseudoStatMainHandDps]: 10.18,
			[PseudoStat.PseudoStatOffHandDps]: 2.97,
		},
	),
);

export const EP_PRESET_SUBTLETY = PresetUtils.makePresetEpWeights(
	'Subtlety',
	Stats.fromMap(
		{
			[Stat.StatStamina]: 0.01,
			[Stat.StatAgility]: 1.93,
			[Stat.StatStrength]: 1.1,
			[Stat.StatCritRating]: 1.63,
			[Stat.StatHasteRating]: 1.43,
			[Stat.StatHitRating]: 2.12,
			[Stat.StatExpertiseRating]: 2.42,
			[Stat.StatArmorPenetration]: 0.33,
			[Stat.StatSpellPiercing]: 0.16,
			[Stat.StatAttackPower]: 1.0,
			[Stat.StatPhysicalDamage]: 6.83,
		},
		{
			[PseudoStat.PseudoStatMainHandDps]: 10.47,
			[PseudoStat.PseudoStatOffHandDps]: 2.27,
		},
	),
);

export const EP_PRESET_ASSASSINATION = PresetUtils.makePresetEpWeights(
	'Assassination',
	Stats.fromMap(
		{
			[Stat.StatStamina]: 0.01,
			[Stat.StatAgility]: 2.06,
			[Stat.StatStrength]: 1.1,
			[Stat.StatCritRating]: 2.02,
			[Stat.StatHasteRating]: 1.93,
			[Stat.StatHitRating]: 2.8,
			[Stat.StatExpertiseRating]: 2.77,
			[Stat.StatArmorPenetration]: 0.4,
			[Stat.StatSpellPiercing]: 0.65,
			[Stat.StatAttackPower]: 1.0,
			[Stat.StatPhysicalDamage]: 10.55,
		},
		{
			[PseudoStat.PseudoStatMainHandDps]: 8.44,
			[PseudoStat.PseudoStatOffHandDps]: 4.16,
		},
	),
);

export const DefaultOptions = RogueOptions.create({
	classOptions: {},
});

export const DefaultConsumables = ConsumesSpec.create({
	elixirIds: [Consumables.ElixirOfTheMongoose.id, Consumables.ElixirOfGreaterFortitude.id, Consumables.ElixirOfFerocity.id, Consumables.JujuMight.id],
	foodId: Consumables.SwiftstrikeSteak.id,
	offensivePotId: Consumables.MajorFrenzyPotion.id,
	conjuredId: Consumables.ThistleTea.id,
	mhImbueId: Consumables.DenseWeightstone.id,
	ohImbueId: Consumables.DenseSharpeningStone.id,
	mhWeaponImbueId: Consumables.InstantPoisonVI.id,
	ohWeaponImbueId: Consumables.DeadlyPoisonIV.id,
});

const FlippedPoisons = ConsumesSpec.create({
	...DefaultConsumables,
	mhWeaponImbueId: Consumables.DeadlyPoisonIV.id,
	ohWeaponImbueId: Consumables.InstantPoisonVI.id,
});

const IP_MH_Settings = {
	name: 'Default',
	consumables: DefaultConsumables,
};
const _DP_MH_Settings = {
	name: 'Flipped Poisons',
	consumables: FlippedPoisons,
};

export const PRESET_BUILD_MUTILATE_ASN = PresetUtils.makePresetBuild('Asn Muti', {
	talents: TALENTS_MUTILATE_ASN,
	rotation: SIMPLE_ROTATION,
	gear: P1_MUTI_GEAR,
	settings: IP_MH_Settings,
	epWeights: EP_PRESET_ASSASSINATION,
});

export const PRESET_BUILD_MUTILATE_COM = PresetUtils.makePresetBuild('Combat Muti', {
	talents: TALENTS_MUTILATE_COM,
	rotation: SIMPLE_ROTATION,
	gear: P1_MUTI_GEAR,
	settings: IP_MH_Settings,
	epWeights: EP_PRESET_COMBAT_DAGS,
});

export const PRESET_BUILD_COMBAT_SS = PresetUtils.makePresetBuild('Combat SS', {
	talents: TALENTS_COMBAT_SS,
	rotation: SIMPLE_ROTATION,
	gear: P1_SLOW_MH_GEAR,
	settings: IP_MH_Settings,
	epWeights: EP_PRESET_COMBAT_SINISTER,
});

export const PRESET_BUILD_COMBAT_BS = PresetUtils.makePresetBuild('Combat BS', {
	talents: TALENTS_COMBAT_BS,
	rotation: SIMPLE_BACKSTAB_BUILD_ROTATION,
	gear: P1_BS_COMBAT_GEAR,
	settings: IP_MH_Settings,
	epWeights: EP_PRESET_COMBAT_DAGS,
});

export const PRESET_BUILD_SUB_HEMO = PresetUtils.makePresetBuild('Subtlety Hemo', {
	talents: TALENTS_SUB_HEMO,
	rotation: SIMPLE_ROTATION,
	gear: P1_SLOW_MH_GEAR,
	settings: IP_MH_Settings,
	epWeights: EP_PRESET_SUBTLETY,
});

export const PRESET_BUILD_SUB_BS = PresetUtils.makePresetBuild('Subtlety BS', {
	talents: TALENTS_SUB_BS,
	rotation: SIMPLE_BACKSTAB_BUILD_ROTATION,
	gear: P1_BS_SUB_GEAR,
	settings: IP_MH_Settings,
	epWeights: EP_PRESET_SUBTLETY,
});

export const OtherDefaults = {
	distanceFromTarget: 5,
};

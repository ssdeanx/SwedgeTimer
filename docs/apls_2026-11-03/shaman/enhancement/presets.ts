import * as PresetUtils from '@app/preset_utils';
import * as Consumables from '@features/settings/model/consumables_auto_gen';
import { Debuffs, IndividualBuffs, PartyBuffs, RaidBuffs } from '@generated/proto/buffs';
import { ConsumesSpec, Profession, PseudoStat, Race, Spec, Stat } from '@generated/proto/common';
import { EnhancementShaman_Options as EnhancementShamanOptions, ShamanImbue } from '@generated/proto/shaman';
import { SavedTalents } from '@generated/proto/ui';
import { Stats } from '@sim/proto/stats';

import TestingBuildJson from './builds/testing.build.json';

export const ROTATION_PRESET_DEFAULT = PresetUtils.makePresetAPLRotation('Default', TestingBuildJson.player.rotation);

export const DefaultGear = PresetUtils.makePresetGear('Testing', TestingBuildJson.player.equipment, { devOnly: true });

export const TestingBuild = PresetUtils.makePresetBuildFromJSON('Testing', Spec.SpecEnhancementShaman, TestingBuildJson, { gear: DefaultGear });

export const StandardTalents = {
	name: 'Standard',
	data: SavedTalents.create({
		talentsString: TestingBuildJson.player.talentsString,
	}),
};

// Measured on the Testing gear with the Standard talents over a three minute fight. The gear has 8.2% hit, so hit
// is measured with 40 hit rating taken off, for its value below the 8% cap.
export const PreBiSEpWeights = PresetUtils.makePresetEpWeights(
	'Pre-BiS',
	Stats.fromMap(
		{
			[Stat.StatStrength]: 2.2,
			[Stat.StatAgility]: 1.32,
			[Stat.StatIntellect]: 1.99,
			[Stat.StatAttackPower]: 1,
			[Stat.StatHitRating]: 5.2,
			[Stat.StatCritRating]: 2.42,
			[Stat.StatHasteRating]: 2.81,
			[Stat.StatExpertiseRating]: 3.5,
			[Stat.StatArmorPenetration]: 0.37,
			[Stat.StatSpellDamage]: 1.27,
			[Stat.StatNatureDamage]: 0.72,
			[Stat.StatSpellPiercing]: 2.52,
		},
		{
			[PseudoStat.PseudoStatMainHandDps]: 14.18,
		},
	),
);

export const DefaultIndividualBuffs = IndividualBuffs.create({
	greaterBlessingOfKings: true,
	greaterBlessingOfMight: 1,
});

// Windfury Weapon on the main hand outbids the party's Windfury Totem, so the default is Rockbiter Weapon.
export const DefaultOptions = EnhancementShamanOptions.create({
	classOptions: {
		shieldProcrate: 0,
		imbueMh: ShamanImbue.RockbiterWeapon,
	},
});

export const OtherDefaults = {
	distanceFromTarget: 5,
	profession1: Profession.Engineering,
	profession2: Profession.Leatherworking,
	race: Race.RaceOrc,
};

export const DefaultConsumables = ConsumesSpec.create({
	resourcePotId: Consumables.MajorManaPotion.id,
	flaskId: Consumables.FlaskOfSupremePower.id,
	foodId: Consumables.SmokedDesertDumplings.id,
	conjuredId: Consumables.DemonicRune.id,
	elixirIds: [
		Consumables.ElixirOfTheOwl.id,
		Consumables.ElixirOfSages.id,
		Consumables.GreaterMagebloodElixir.id,
		Consumables.ElixirOfNaturePower.id,
		Consumables.GreaterArcaneElixir.id,
		Consumables.WinterfallFirewater.id,
		Consumables.ElixirOfCunning.id,
		Consumables.ElixirOfFerocity.id,
	],
	explosiveId: Consumables.EZThroDarkBomb.id,
	mhImbueId: Consumables.ElementalSharpeningStone.id,
	extraIds: [Consumables.GoblinSapperCharge.id],
});

export const DefaultPartyBuffs = PartyBuffs.create({});

export const DefaultRaidBuffs = RaidBuffs.create({
	powerWordFortitude: true,
	markOfTheWild: true,
	arcaneIntellect: true,
	strengthOfEarthTotem: 1,
	windfuryTotem: true,
	battleShout: 1, // Rank 6
	leaderOfThePack: true,
});

export const DefaultDebuffs = Debuffs.create({
	huntersMark: true,
	judgementOfWisdom: true,
	giftOfArthas: true,
	exposeArmor: true,
	faerieFire: true,
	sunderArmor: true,
	curseOfElements: true,
	curseOfRecklessness: true,
});

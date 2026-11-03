import * as PresetUtils from '@app/preset_utils';
import * as Consumables from '@features/settings/model/consumables_auto_gen';
import { Debuffs, IndividualBuffs, PartyBuffs, RaidBuffs } from '@generated/proto/buffs';
import { ConsumesSpec, Profession, Race, Spec, Stat } from '@generated/proto/common';
import { ElementalShaman_Options as ElementalShamanOptions } from '@generated/proto/shaman';
import { SavedTalents } from '@generated/proto/ui';
import { Stats } from '@sim/proto/stats';

import TestingBuildJson from './builds/testing.build.json';

export const ROTATION_PRESET_DEFAULT = PresetUtils.makePresetAPLRotation('Default', TestingBuildJson.player.rotation);

export const DefaultGear = PresetUtils.makePresetGear('Testing', TestingBuildJson.player.equipment, { devOnly: true });

export const TestingBuild = PresetUtils.makePresetBuildFromJSON('Testing', Spec.SpecElementalShaman, TestingBuildJson, { gear: DefaultGear });

// Measured on the Testing gear with the Standard talents over a three minute fight. Hit is its value below the
// 17% cap.
export const DefaultEpWeights = PresetUtils.makePresetEpWeights(
	'Testing',
	Stats.fromMap({
		[Stat.StatIntellect]: 0.19,
		[Stat.StatSpirit]: 0.02,
		[Stat.StatSpellDamage]: 1,
		[Stat.StatFireDamage]: 0.31,
		[Stat.StatNatureDamage]: 0.69,
		[Stat.StatSpellPiercing]: 1.81,
		[Stat.StatHitRating]: 1.18,
		[Stat.StatCritRating]: 0.61,
		[Stat.StatHasteRating]: 1.23,
		[Stat.StatMP5]: 0.04,
	}),
);

export const StandardTalents = {
	name: 'Standard',
	data: SavedTalents.create({
		talentsString: TestingBuildJson.player.talentsString,
	}),
};

export const DefaultOptions = ElementalShamanOptions.create({
	classOptions: {
		shieldProcrate: 0,
	},
});

export const OtherDefaults = {
	distanceFromTarget: 20,
	profession1: Profession.Leatherworking,
	profession2: Profession.Enchanting,
	race: Race.RaceTroll,
};

export const DefaultRaidBuffs = RaidBuffs.create({
	arcaneIntellect: true,
	markOfTheWild: true,
	powerWordFortitude: true,
	prayerOfSpirit: true,
	moonkinAura: true,
});

export const DefaultPartyBuffs = PartyBuffs.create({});

export const DefaultIndividualBuffs = IndividualBuffs.create({
	greaterBlessingOfKings: true,
	greaterBlessingOfWisdom: 1,
});

export const DefaultDebuffs = Debuffs.create({
	curseOfElements: true,
	curseOfRecklessness: true,
	exposeArmor: true,
	faerieFire: true,
	giftOfArthas: true,
	judgementOfWisdom: true,
	sunderArmor: true,
});

export const DefaultConsumables = ConsumesSpec.create({
	conjuredId: Consumables.DemonicRune.id,
	flaskId: Consumables.FlaskOfSupremePower.id,
	foodId: Consumables.NightfinSoup.id,
	mhImbueId: Consumables.BrilliantWizardOil.id,
	offensivePotId: Consumables.MajorSpellblastingPotion.id,
});

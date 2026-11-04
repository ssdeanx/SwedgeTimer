import * as PresetUtils from '@app/preset_utils';
import { ConsumesSpec, Profession, UnitReference } from '@generated/proto/common';
import { RestorationDruid_Options as RestorationDruidOptions } from '@generated/proto/druid';

import P3Gear from './gear_sets/p3.gear.json';
import PreraidGear from './gear_sets/preraid.gear.json';
import DefaultEpJson from './presets/ep/default.ep.json';
import DreamstateTalentsJson from './presets/talents/dreamstate.talents.json';
import TreeOfLifeTalentsJson from './presets/talents/tree_of_life.talents.json';

export const P3_PRESET = PresetUtils.makePresetGear('P3 BiS', P3Gear);
export const PRERAID_PRESET = PresetUtils.makePresetGear('Pre-raid', PreraidGear);

// Stat weights with healing power = 1, ordered after wowhead's TBC stat priority for the spec
// (healing > Spirit and MP5 > Intellect > haste > crit). Not sim-derived: there is no healing sim, so these only sort the gear picker
// and drive the gem optimizer.
export const DEFAULT_EP_PRESET = PresetUtils.makePresetEpWeightsFromJSON(DefaultEpJson);

// Talent builds from wowhead's TBC guide. Uses the wowhead calculator format, make the talents on
// https://www.wowhead.com/tbc/talent-calc and copy the numbers in the url.
export const TreeOfLifeTalents = PresetUtils.makePresetTalentsFromJSON(TreeOfLifeTalentsJson);
export const DreamstateTalents = PresetUtils.makePresetTalentsFromJSON(DreamstateTalentsJson);

export const DefaultOptions = RestorationDruidOptions.create({
	classOptions: {
		innervateTarget: UnitReference.create(),
	},
});

export const DefaultConsumables = ConsumesSpec.create({
	flaskId: 22853, // Flask of Mighty Restoration
	foodId: 27666, // Golden Fish Sticks
	potId: 22832, // Super Mana Potion
});

export const OtherDefaults = {
	distanceFromTarget: 20,
	profession1: Profession.Tailoring,
	profession2: Profession.Enchanting,
};

import * as PresetUtils from '@app/preset_utils';
import { ConsumesSpec, Profession } from '@generated/proto/common';
import { RestorationShaman_Options as RestorationShamanOptions } from '@generated/proto/shaman';

import P3Gear from './gear_sets/p3.gear.json';
import PreraidGear from './gear_sets/preraid.gear.json';
import DefaultEpJson from './presets/ep/default.ep.json';
import ElementalWardingTalentsJson from './presets/talents/elemental_warding.talents.json';
import EnhancingTotemsTalentsJson from './presets/talents/enhancing_totems.talents.json';

export const P3_PRESET = PresetUtils.makePresetGear('P3 BiS', P3Gear);
export const PRERAID_PRESET = PresetUtils.makePresetGear('Pre-raid', PreraidGear);

// Stat weights with healing power = 1, ordered after wowhead's TBC stat priority for the spec
// (healing > MP5 > Intellect > haste > crit > Stamina > Spirit). Not sim-derived: there is no healing sim, so these only sort the gear picker
// and drive the gem optimizer.
export const DEFAULT_EP_PRESET = PresetUtils.makePresetEpWeightsFromJSON(DefaultEpJson);

// Talent builds from wowhead's TBC guide. Uses the wowhead calculator format, make the talents on
// https://www.wowhead.com/tbc/talent-calc and copy the numbers in the url.
export const ElementalWardingTalents = PresetUtils.makePresetTalentsFromJSON(ElementalWardingTalentsJson);
export const EnhancingTotemsTalents = PresetUtils.makePresetTalentsFromJSON(EnhancingTotemsTalentsJson);

export const DefaultOptions = RestorationShamanOptions.create({
	classOptions: {},
});

export const DefaultConsumables = ConsumesSpec.create({
	flaskId: 22853, // Flask of Mighty Restoration
	foodId: 27666, // Golden Fish Sticks
	potId: 22832, // Super Mana Potion
});

export const OtherDefaults = {
	distanceFromTarget: 20,
	profession1: Profession.Leatherworking,
	profession2: Profession.Enchanting,
};

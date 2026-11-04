// Configuration for spec-specific UI elements on the settings tab.
// These don't need to be in a separate file but it keeps things cleaner.
import { Spec } from '@generated/proto/common';
import * as InputHelpers from '@ui-kit/input_helpers';

import * as SharedPaladinInputs from '../shared/inputs';

export const PaladinRotationConfig = {
	inputs: [
		InputHelpers.makeRotationBooleanInput<Spec.SpecRetributionPaladin>({
			fieldName: 'useExorcism',
			label: 'Use Exorcism',
			labelTooltip: 'If <b>true</b>, will use Excorism in rotation if target is undead or demon.',
			getValue: player => player.getSimpleRotation().useExorcism,
		}),
		SharedPaladinInputs.ConsecrationRankInput<Spec.SpecRetributionPaladin>(
			'Which rank of Consecration to use in the rotation. Exorcism takes priority. Select <b>Do not use</b> to disable.',
		),
		InputHelpers.makeRotationNumberInput<Spec.SpecRetributionPaladin>({
			fieldName: 'delayMajorCDs',
			label: 'Delay Major CDs',
			labelTooltip: 'Delays the first automatic use of major cooldowns (e.g. Bloodlust, Drums) by the specified number of seconds.',
			getValue: player => player.getSimpleRotation().delayMajorCDs,
			positive: true,
		}),
		InputHelpers.makeRotationBooleanInput<Spec.SpecRetributionPaladin>({
			fieldName: 'prepullSotC',
			label: 'Prepull Seal of the Crusader',
			labelTooltip:
				'If <b>true</b>, will use Seal of the Crusader on prepull for the target Debuff. Set this to true if you are the only paladin applying SotC. <br/><br/> If <b>false</b>, make sure to enable SotC in settings under debuffs.',
			getValue: player => player.getSimpleRotation().prepullSotC,
		}),
	],
};

// Icon-enum pickers cannot sit in an `inputs` array any more; they go in the spec's
// `rotationIconInputs`, which the simple-rotation pane renders as an icon row.
export const PaladinRotationIconInputs = [
	SharedPaladinInputs.AuraInput<Spec.SpecRetributionPaladin>(
		'Which paladin aura to activate in the prepull. <b>Sanctity Aura</b> requires the talent. Pick <b>None</b> to skip casting an aura.',
	),
];

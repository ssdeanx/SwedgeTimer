// Configuration for spec-specific UI elements on the settings tab.
// These don't need to be in a separate file but it keeps things cleaner.
import { Spec } from '@generated/proto/common';
import { PaladinJudgement } from '@generated/proto/paladin';
import { ActionId } from '@sim/proto/action_id';
import * as InputHelpers from '@ui-kit/input_helpers';

import * as SharedPaladinInputs from '../shared/inputs';

export const PaladinRotationConfig = {
	inputs: [
		InputHelpers.makeRotationBooleanInput<Spec.SpecProtectionPaladin>({
			fieldName: 'prioritizeHolyShield',
			label: 'Prioritize Holy Shield',
			labelTooltip: 'If <b>true</b>, Holy Shield is cast at highest priority. If <b>false</b>, Holy Shield is cast after Consecration and Judgement.',
			storeField: ['rotation', 'talentsString'] as const,
			getValue: player => player.getSimpleRotation().prioritizeHolyShield,
			showWhen: player => player.getTalents().holyShield,
		}),
		SharedPaladinInputs.ConsecrationRankInput<Spec.SpecProtectionPaladin>(
			'Which rank of Consecration to use in the rotation. Select <b>Do not use</b> to disable.',
		),
		InputHelpers.makeRotationBooleanInput<Spec.SpecProtectionPaladin>({
			fieldName: 'useExorcism',
			label: 'Use Exorcism',
			labelTooltip: 'If <b>true</b>, will use Exorcism in the rotation (only effective against Undead and Demons).',
			getValue: player => player.getSimpleRotation().useExorcism,
		}),
		InputHelpers.makeRotationBooleanInput<Spec.SpecProtectionPaladin>({
			fieldName: 'useHammerOfWrath',
			label: 'Use Hammer of Wrath',
			labelTooltip: 'If <b>true</b>, will use Hammer of Wrath in the rotation when the target is in execute range.',
			getValue: player => player.getSimpleRotation().useHammerOfWrath,
		}),
		InputHelpers.makeRotationBooleanInput<Spec.SpecProtectionPaladin>({
			fieldName: 'useAvengersShield',
			label: "Use Avenger's Shield",
			labelTooltip: "If <b>true</b>, will use Avenger's Shield in the rotation.",
			storeField: ['rotation', 'talentsString'] as const,
			getValue: player => player.getSimpleRotation().useAvengersShield,
			showWhen: player => player.getTalents().avengersShield,
		}),
		InputHelpers.makeRotationBooleanInput<Spec.SpecProtectionPaladin>({
			fieldName: 'precastAvengersShield',
			label: "Precast Avenger's Shield",
			labelTooltip:
				"If <b>true</b>, opens combat with a prepull Avenger's Shield cast that lands at pull. Adjusts the prepull Holy Shield and seal cast timings to fit.",
			storeField: ['rotation', 'talentsString'] as const,
			getValue: player => player.getSimpleRotation().precastAvengersShield,
			showWhen: player => player.getTalents().avengersShield,
		}),
	],
};

// Icon-enum pickers cannot sit in an `inputs` array any more; they go in the spec's
// `rotationIconInputs`, which the simple-rotation pane renders as an icon row.
export const PaladinRotationIconInputs = [
	InputHelpers.makeRotationEnumIconInput<Spec.SpecProtectionPaladin, PaladinJudgement>({
		fieldName: 'maintainJudgement',
		label: 'Maintain Judgement',
		labelTooltip:
			'Which Judgement debuff to keep active on the target. The matching Seal will be used before each Judgement. Pick <b>None</b> to keep Seal of Righteousness up and skip Judgement maintenance.',
		values: [
			{ color: 'grey', value: PaladinJudgement.JudgementNone, tooltip: 'None' },
			{ actionId: ActionId.fromSpellId(27162), value: PaladinJudgement.JudgementOfLight, tooltip: 'Judgement of Light' },
			{ actionId: ActionId.fromSpellId(27164), value: PaladinJudgement.JudgementOfWisdom, tooltip: 'Judgement of Wisdom' },
		],
		getValue: player => player.getSimpleRotation().maintainJudgement,
	}),
	SharedPaladinInputs.AuraInput<Spec.SpecProtectionPaladin>(
		'Which paladin aura to activate in the prepull. <b>Sanctity Aura</b> requires the talent. Pick <b>None</b> to skip casting an aura.',
	),
];

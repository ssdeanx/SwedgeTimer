// Shared rotation inputs used by both protection and retribution paladin.
// Holy has no simple rotation fields so it's not covered here.
import { Spec } from '@generated/proto/common';
import { PaladinAura } from '@generated/proto/paladin';
import { ActionId } from '@sim/proto/action_id';
import * as InputHelpers from '@ui-kit/input_helpers';

type PaladinSimpleSpec = Spec.SpecProtectionPaladin | Spec.SpecRetributionPaladin;

const CONSECRATION_RANK_VALUES = [
	{ name: 'Do not use', value: 0 },
	{ name: 'Rank 1', value: 1 },
	{ name: 'Rank 2', value: 2 },
	{ name: 'Rank 3', value: 3 },
	{ name: 'Rank 4', value: 4 },
	{ name: 'Rank 5', value: 5 },
	{ name: 'Rank 6', value: 6 },
];

export const ConsecrationRankInput = <SpecType extends PaladinSimpleSpec>(labelTooltip: string) =>
	InputHelpers.makeRotationEnumInput<SpecType, number>({
		fieldName: 'consecrationRank',
		label: 'Consecration Rank',
		labelTooltip,
		values: CONSECRATION_RANK_VALUES,
	});

// The aura picker is an icon-enum input, so it lands in `rotationIconInputs`.
export const AuraInput = <SpecType extends PaladinSimpleSpec>(labelTooltip: string) =>
	InputHelpers.makeRotationEnumIconInput<SpecType, PaladinAura>({
		fieldName: 'aura',
		label: 'Aura',
		labelTooltip,
		values: [
			{ color: 'grey', value: PaladinAura.AuraNone, tooltip: 'None' },
			{ actionId: ActionId.fromSpellId(27149), value: PaladinAura.DevotionAura, tooltip: 'Devotion Aura' },
			{ actionId: ActionId.fromSpellId(27150), value: PaladinAura.RetributionAura, tooltip: 'Retribution Aura' },
			{ actionId: ActionId.fromSpellId(19746), value: PaladinAura.ConcentrationAura, tooltip: 'Concentration Aura' },
			{ actionId: ActionId.fromSpellId(27153, 0, 1), value: PaladinAura.FireResistanceAura, tooltip: 'Fire Resistance Aura' },
			{ actionId: ActionId.fromSpellId(27152, 0, 1), value: PaladinAura.FrostResistanceAura, tooltip: 'Frost Resistance Aura' },
			{ actionId: ActionId.fromSpellId(27151, 0, 1), value: PaladinAura.ShadowResistanceAura, tooltip: 'Shadow Resistance Aura' },
			{
				actionId: ActionId.fromSpellId(20218),
				value: PaladinAura.SanctityAura,
				tooltip: 'Sanctity Aura',
				showWhen: player => player.getTalents().sanctityAura,
			},
		],
		storeField: ['rotation', 'talentsString'] as const,
	});

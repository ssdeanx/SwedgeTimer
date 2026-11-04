import { ShamanImbue } from '@generated/proto/shaman';
import i18n from '@i18n/config';
import { Player } from '@sim/player/player';
import { ActionId } from '@sim/proto/action_id';
import { ShamanSpecs } from '@sim/proto/spec_types';
import * as InputHelpers from '@ui-kit/input_helpers';

// Configuration for class-specific UI elements on the settings tab.
// These don't need to be in a separate file but it keeps things cleaner.

export const ShamanImbueMH = <SpecType extends ShamanSpecs>() =>
	InputHelpers.makeClassOptionsEnumIconInput<SpecType, ShamanImbue>({
		fieldName: 'imbueMh',
		values: [
			{ value: ShamanImbue.NoImbue, tooltip: 'No Main Hand Enchant' },
			{ actionId: ActionId.fromSpellId(8232), value: ShamanImbue.WindfuryWeapon },
			{ actionId: ActionId.fromSpellId(8024), value: ShamanImbue.FlametongueWeapon },
			{ actionId: ActionId.fromSpellId(8033), value: ShamanImbue.FrostbrandWeapon },
		],
	});

export const ShamanImbueMHSwap = <SpecType extends ShamanSpecs>() =>
	InputHelpers.makeClassOptionsEnumIconInput<SpecType, ShamanImbue>({
		fieldName: 'imbueMhSwap',
		values: [
			{ value: ShamanImbue.NoImbue, tooltip: 'No Main Hand Swap Enchant' },
			{ actionId: ActionId.fromSpellId(8232), value: ShamanImbue.WindfuryWeapon },
			{ actionId: ActionId.fromSpellId(8024), value: ShamanImbue.FlametongueWeapon },
		],
		showWhen: (player: Player<SpecType>) => player.itemSwapSettings.getEnableItemSwap(),
		storeField: ['specOptions', 'itemSwap'] as const,
	});

export const ShamanShieldProcrate = <SpecType extends ShamanSpecs>() =>
	InputHelpers.makeClassOptionsNumberInput<SpecType>({
		fieldName: 'shieldProcrate',
		label: i18n.t('settings_tab.other.shaman_shield_procrate.label'),
		labelTooltip: i18n.t('settings_tab.other.shaman_shield_procrate.tooltip'),
		positive: true,
		float: true,
	});

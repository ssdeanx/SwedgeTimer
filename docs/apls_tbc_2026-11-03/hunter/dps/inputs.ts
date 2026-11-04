import { HandType, ItemSlot, Spec } from '@generated/proto/common';
import { HunterOptions_Ammo, HunterOptions_PetType, HunterOptions_QuiverBonus } from '@generated/proto/hunter';
import i18n from '@i18n/config';
import { Player } from '@sim/player/player';
import { ActionId } from '@sim/proto/action_id';
import { HunterSpecs } from '@sim/proto/spec_types';
import * as InputHelpers from '@ui-kit/input_helpers';

export const AmmoInput = <SpecType extends HunterSpecs>() =>
	InputHelpers.makeClassOptionsEnumIconInput<SpecType, HunterOptions_Ammo>({
		fieldName: 'ammo',
		label: i18n.t('settings_tab.other.ammo.label'),
		labelTooltip: i18n.t('settings_tab.other.ammo.tooltip'),
		numColumns: 4,
		values: [
			{ value: HunterOptions_Ammo.AmmoNone, tooltip: i18n.t('settings_tab.other.ammo.no_ammo') },
			{ actionId: ActionId.fromItemId(31737), value: HunterOptions_Ammo.TimelessArrow, tooltip: i18n.t('settings_tab.other.ammo.timeless_arrow') },
			{ actionId: ActionId.fromItemId(34581), value: HunterOptions_Ammo.MysteriousArrow, tooltip: i18n.t('settings_tab.other.ammo.mysterious_arrow') },
			{
				actionId: ActionId.fromItemId(33803),
				value: HunterOptions_Ammo.AdamantiteStinger,
				tooltip: i18n.t('settings_tab.other.ammo.adamantite_stinger'),
			},
			{
				actionId: ActionId.fromItemId(30611),
				value: HunterOptions_Ammo.HalaaniRazorshaft,
				tooltip: i18n.t('settings_tab.other.ammo.halaani_razorshaft'),
			},
			{ actionId: ActionId.fromItemId(28056), value: HunterOptions_Ammo.BlackflightArrow, tooltip: i18n.t('settings_tab.other.ammo.blackflight_arrow') },
			{ actionId: ActionId.fromItemId(31949), value: HunterOptions_Ammo.WardensArrow, tooltip: i18n.t('settings_tab.other.ammo.wardens_arrow') },
		],
	});

export const QuiverInput = <SpecType extends HunterSpecs>() =>
	InputHelpers.makeClassOptionsEnumIconInput<SpecType, HunterOptions_QuiverBonus>({
		extraClassNames: ['quiver-picker'],
		fieldName: 'quiverBonus',
		label: i18n.t('settings_tab.other.quiver.label'),
		labelTooltip: i18n.t('settings_tab.other.quiver.tooltip'),
		numColumns: 4,
		values: [
			{ color: '82e89d', value: HunterOptions_QuiverBonus.QuiverNone, tooltip: i18n.t('settings_tab.other.quiver.no_quiver') },
			{ actionId: ActionId.fromItemId(18714), value: HunterOptions_QuiverBonus.Speed15, tooltip: i18n.t('settings_tab.other.quiver.speed_15') },
			{ actionId: ActionId.fromItemId(2662), value: HunterOptions_QuiverBonus.Speed14, tooltip: i18n.t('settings_tab.other.quiver.speed_14') },
			{ actionId: ActionId.fromItemId(8217), value: HunterOptions_QuiverBonus.Speed13, tooltip: i18n.t('settings_tab.other.quiver.speed_13') },
			{ actionId: ActionId.fromItemId(7371), value: HunterOptions_QuiverBonus.Speed12, tooltip: i18n.t('settings_tab.other.quiver.speed_12') },
			{ actionId: ActionId.fromItemId(3605), value: HunterOptions_QuiverBonus.Speed11, tooltip: i18n.t('settings_tab.other.quiver.speed_11') },
			{ actionId: ActionId.fromItemId(3573), value: HunterOptions_QuiverBonus.Speed10, tooltip: i18n.t('settings_tab.other.quiver.speed_10') },
		],
	});

export const PetTypeInput = <SpecType extends HunterSpecs>() =>
	InputHelpers.makeClassOptionsEnumIconInput<SpecType, HunterOptions_PetType>({
		extraClassNames: ['pet-type-picker'],
		fieldName: 'petType',
		label: i18n.t('settings_tab.other.pet_type.label'),
		labelTooltip: i18n.t('settings_tab.other.pet_type.tooltip'),
		numColumns: 4,
		values: [
			{ value: HunterOptions_PetType.PetNone, actionId: ActionId.fromPetName(''), tooltip: i18n.t('settings_tab.other.pet_type.no_pet') },
			{ value: HunterOptions_PetType.Bat, actionId: ActionId.fromPetName('Bat'), tooltip: i18n.t('settings_tab.other.pet_type.bat') },
			{ value: HunterOptions_PetType.Bear, actionId: ActionId.fromPetName('Bear'), tooltip: i18n.t('settings_tab.other.pet_type.bear') },
			{ value: HunterOptions_PetType.Cat, actionId: ActionId.fromPetName('Cat'), tooltip: i18n.t('settings_tab.other.pet_type.cat') },
			{ value: HunterOptions_PetType.Crab, actionId: ActionId.fromPetName('Crab'), tooltip: i18n.t('settings_tab.other.pet_type.crab') },
			{ value: HunterOptions_PetType.Owl, actionId: ActionId.fromPetName('Owl'), tooltip: i18n.t('settings_tab.other.pet_type.owl') },
			{ value: HunterOptions_PetType.Raptor, actionId: ActionId.fromPetName('Raptor'), tooltip: i18n.t('settings_tab.other.pet_type.raptor') },
			{ value: HunterOptions_PetType.Ravager, actionId: ActionId.fromPetName('Ravager'), tooltip: i18n.t('settings_tab.other.pet_type.ravager') },
			{
				value: HunterOptions_PetType.WindSerpent,
				actionId: ActionId.fromPetName('Wind Serpent'),
				tooltip: i18n.t('settings_tab.other.pet_type.wind_serpent'),
			},
			{
				value: HunterOptions_PetType.Dragonhawk,
				actionId: ActionId.fromPetName('Dragonhawk'),
				tooltip: i18n.t('settings_tab.other.pet_type.dragonhawk'),
			},
		],
	});

export const PetSingleAbility = () =>
	InputHelpers.makeClassOptionsBooleanInput<Spec.SpecHunter>({
		fieldName: 'petSingleAbility',
		label: i18n.t('settings_tab.other.pet_single_ability.label'),
		labelTooltip: i18n.t('settings_tab.other.pet_single_ability.tooltip'),
	});

export const PetUptime = () =>
	InputHelpers.makeClassOptionsNumberInput<Spec.SpecHunter>({
		fieldName: 'petUptime',
		label: i18n.t('settings_tab.other.pet_uptime.label'),
		labelTooltip: i18n.t('settings_tab.other.pet_uptime.tooltip'),
		percent: true,
	});

export const RotationInputs = {
	inputs: [
		InputHelpers.makeRotationNumberInput<Spec.SpecHunter>({
			fieldName: 'viperStartManaPercent',
			label: i18n.t('rotation_tab.options.hunter.viper_start_mana_percent.label'),
			labelTooltip: i18n.t('rotation_tab.options.hunter.viper_start_mana_percent.tooltip'),
			percent: true,
			positive: true,
			max: 100,
		}),
		InputHelpers.makeRotationNumberInput<Spec.SpecHunter>({
			fieldName: 'viperStopManaPercent',
			label: i18n.t('rotation_tab.options.hunter.viper_stop_mana_percent.label'),
			labelTooltip: i18n.t('rotation_tab.options.hunter.viper_stop_mana_percent.tooltip'),
			percent: true,
			positive: true,
			max: 100,
		}),
		InputHelpers.makeRotationBooleanInput<Spec.SpecHunter>({
			fieldName: 'meleeWeave',
			label: i18n.t('rotation_tab.options.hunter.melee_weave.label'),
			labelTooltip: i18n.t('rotation_tab.options.hunter.melee_weave.tooltip'),
			showWhen: (player: Player<Spec.SpecHunter>) => player.getEquippedItem(ItemSlot.ItemSlotMainHand)?.item?.handType === HandType.HandTypeTwoHand,
		}),
		InputHelpers.makeRotationNumberInput<Spec.SpecHunter>({
			fieldName: 'timeToWeave',
			label: i18n.t('rotation_tab.options.hunter.time_to_weave.label'),
			labelTooltip: i18n.t('rotation_tab.options.hunter.time_to_weave.tooltip'),
			positive: true,
			showWhen: (player: Player<Spec.SpecHunter>) =>
				player.getEquippedItem(ItemSlot.ItemSlotMainHand)?.item?.handType === HandType.HandTypeTwoHand && player.getSimpleRotation().meleeWeave,
			storeField: ['rotation', 'gear'] as const,
		}),
		InputHelpers.makeRotationBooleanInput<Spec.SpecHunter>({
			fieldName: 'useMulti',
			label: i18n.t('rotation_tab.options.hunter.use_multi.label'),
			labelTooltip: i18n.t('rotation_tab.options.hunter.use_multi.tooltip'),
		}),
		InputHelpers.makeRotationBooleanInput<Spec.SpecHunter>({
			fieldName: 'useArcane',
			label: i18n.t('rotation_tab.options.hunter.use_arcane.label'),
			labelTooltip: i18n.t('rotation_tab.options.hunter.use_arcane.tooltip'),
		}),
	],
};

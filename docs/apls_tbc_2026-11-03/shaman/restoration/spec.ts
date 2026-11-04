import * as BuffDebuffInputs from '@features/settings/model/buffs_debuffs';
import { APLRotation } from '@generated/proto/apl';
import { Debuffs, PseudoStat, Spec, Stat } from '@generated/proto/common';
import { PlayerClasses } from '@sim/player/classes';
import { Player } from '@sim/player/player';
import { DEFAULT_HEALER_GEM_STATS, UnitStat } from '@sim/proto/stats';
import { defaultHealerIndividualBuffs, defaultHealerPartyBuffs, defaultHealerRaidBuffs } from '@sim/proto/utils';
import { defineSpec } from '@sim/spec_config';

import * as Presets from './presets';

// Gear planner only: no healing spells are implemented, so there is no simulation for this spec.
export default defineSpec<Spec.SpecRestorationShaman>({
	spec: Spec.SpecRestorationShaman,
	// Nothing is simulated, so the incoming-healing model stays off.
	enableHealing: false,

	className: 'restoration-shaman-sim-ui',
	cssScheme: PlayerClasses.getCssScheme(PlayerClasses.Shaman),
	// List any known bugs / issues here and they'll be shown on the site.
	knownIssues: [],

	// All stats for which EP should be calculated.
	epStats: [Stat.StatIntellect, Stat.StatSpirit, Stat.StatHealingPower, Stat.StatSpellCritRating, Stat.StatSpellHasteRating, Stat.StatMP5],
	// Reference stat against which to calculate EP.
	epReferenceStat: Stat.StatHealingPower,
	// Which stats to display in the Character Stats section, at the bottom of the left-hand sidebar.
	// The resistances are there for planning resistance sets, the way the hunter sim shows them.
	displayStats: UnitStat.createDisplayStatArray(
		[
			Stat.StatHealth,
			Stat.StatMana,
			Stat.StatStamina,
			Stat.StatIntellect,
			Stat.StatSpirit,
			Stat.StatHealingPower,
			Stat.StatSpellDamage,
			Stat.StatMP5,
			Stat.StatArcaneResistance,
			Stat.StatFireResistance,
			Stat.StatFrostResistance,
			Stat.StatNatureResistance,
			Stat.StatShadowResistance,
		],
		[PseudoStat.PseudoStatSpellCritPercent, PseudoStat.PseudoStatSpellHastePercent],
	),
	gemStats: DEFAULT_HEALER_GEM_STATS,

	defaults: {
		// Default equipped gear.
		gear: Presets.P3_PRESET.gear,
		// Default EP weights for sorting gear in the gear picker.
		epWeights: Presets.DEFAULT_EP_PRESET.epWeights,
		// Default consumes settings.
		consumables: Presets.DefaultConsumables,
		// Default talents.
		talents: Presets.ElementalWardingTalents.data,
		// Default spec-specific settings.
		specOptions: Presets.DefaultOptions,
		other: Presets.OtherDefaults,
		// Default raid/party buffs settings.
		raidBuffs: defaultHealerRaidBuffs(),
		partyBuffs: defaultHealerPartyBuffs(),
		individualBuffs: defaultHealerIndividualBuffs(),
		debuffs: Debuffs.create({}),
	},

	// IconInputs to include in the 'Player' section on the settings tab.
	playerIconInputs: [],
	// Buff and Debuff inputs to include/exclude, overriding the EP-based defaults.
	// Stamina is not an EP stat for healers, but the buff still belongs in the stats panel.
	includeBuffDebuffInputs: [BuffDebuffInputs.PowerWordFortitude],
	// Nothing is simulated, so buffs that only matter inside an encounter (damage, cooldowns,
	// mana returns over a fight) would only mislead.
	excludeBuffDebuffInputs: [
		BuffDebuffInputs.Bloodlust,
		BuffDebuffInputs.Thorns,
		BuffDebuffInputs.BlessingOfSanctuary,
		BuffDebuffInputs.Innervate,
		BuffDebuffInputs.PowerInfusion,
		BuffDebuffInputs.FerociousInspiration,
		BuffDebuffInputs.ManaTideTotem,
		BuffDebuffInputs.ShadowPriestDPS,
		BuffDebuffInputs.SanctityAura,
		BuffDebuffInputs.DrumsBuff,
	],
	// Inputs to include in the 'Other' section on the settings tab.
	otherInputs: {
		inputs: [],
	},
	encounterPicker: {
		// Whether to include 'Execute Duration (%)' in the 'Encounter' section of the settings tab.
		showExecuteProportion: false,
	},

	presets: {
		epWeights: [Presets.DEFAULT_EP_PRESET],
		// Preset talents that the user can quickly select.
		talents: [Presets.ElementalWardingTalents, Presets.EnhancingTotemsTalents],
		// Preset rotations that the user can quickly select.
		rotations: [],
		// Preset gear configurations that the user can quickly select.
		gear: [Presets.PRERAID_PRESET, Presets.P3_PRESET],
	},

	autoRotation: (_: Player<Spec.SpecRestorationShaman>): APLRotation => {
		return APLRotation.create();
	},

	// The gem optimizer.
	reforge: {},
});

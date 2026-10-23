# Release audit: hunter + shaman + paladin (desk audit-hsp, 2026-10-22)

Write scope held: classes/hunter.lua, tests/hunter_state.lua only.
Read-only everywhere else. No Libs/TOCs/versions/run.sh/main/bars/compat/hud/options/practice touches.

## Verdict

No crash found. One wrong-behavior fixed (F1). One wrong-behavior confirmed but
left open behind an operator visibility gate (C3). Everything else verified
clean and pinned by the existing suites (all green, see §5).

## F1 (wrong-behavior) — FIXED: hunter SUCCEEDED/channel sites id-only vs the R1 rule

The module's own pinned rule (tests/hunter_state.lua §10 R1 legs) says TBC
payloads can ride the name with no id (`token = spell_id or cast_guid`), and
the queue-tint clears already match names. Four sites on the same event shapes
matched ids only, so a name-carrying payload missed them:

- `on_spellcast_succeeded`: Feign Death (5384) ranged-display clear and
  Readiness (23989) stamp + Rapid Fire refresh — classes/hunter.lua:875,894.
- `note_trap_cast` (`TRAP_SPELLS[spell_id]` raw lookup) — :911 + :1631. Its
  comment ("event payloads stay numeric on every family") contradicted R1;
  corrected.
- `on_current_spellcast_cast_changed`: UnitChannelInfo 8th-value id-only check
  — :950.

Fix (behavior-neutral when ids are present): `is_feign_death_token` /
`is_readiness_token` (id, then live localized name, then English fallback),
`trap_key_for_name` (id, then live name, then English fallback; Wrath takes
49067 / others 13813 on the shared "Explosive Trap" name), channel name through
the existing `is_hunter_live_cast` matcher. Table/nil/boolean tokens all read
false (no throw paths).

## C3 (wrong-behavior) — CONFIRMED, NOT FIXED (operator visibility gate owed)

The hunter guide cannot show at range (where hunters fight): hunter drives
`nextaction_ui.on_bar_update(self, hand)` for ranged and mainhand
(classes/hunter.lua:1048), but the UI ignores non-mainhand
(nextaction_ui.lua:828-833 `if hand ~= "mainhand" then return end`), and
`ui.should_show` requires mainhand swing state (:449-467). At range there are
no melee swings (and lazy-bars leaves MH unbuilt), so the guide stays hidden.
Fix shape (gated lane): a provider hook for the guide anchor hand (hunter
overrides with ranged state) without touching mainhand state. NOT implemented:
showing the guide at range is a default-visible change and there is no
operator gate for it (inherited residual from the hunter_bars lane, noted by
the orchestrator for the handoff, not a ruling question).

## Verified clean (sampled + suite-pinned, no change)

- Shaman: SUCCEEDED/START token shapes name-tolerant (`lookup_weave_family`
  id-or-name; twist/magma/searing/fireele commits spell_id/cast_guid/live_name,
  :1291-1317); aura scan id-or-name throughout (MW, Bloodlust, Berserking,
  Windfury, SR, Rockbiter); totem readers match totemName and id; Searing/LS/
  WF/GoA slots spell-known-gated; MW5 spender known-gated; rule-7 opt-in, WF
  family ICD, CoE 66842 client-sourced all present.
- Paladin: Exorcism SUCCEEDED token name-tolerant; CLEU SPELL_DAMAGE matches
  id/name/table shapes; lust scan TBC-name / else-id; twist ICD/PPM, SoD 200ms
  narrowing, is_sod_client rune gating present; SoD aura ids ERA-gated on the
  UnitAura path (numeric ids always present there — id-only is correct);
  JotC via `aura_matches`; band slots fail-visible via `is_spell_known_state`
  (HU-15).
- hunter_ui: Auto Shot exclusion, RF/BW/Frenzy readers all id-or-name.
- nextaction.lua: pure (no spell queries). nextaction_ui.lua: GetSpellInfo for
  icons only. weave.lua: pure math (no spell queries).
- Rotation tables: HU-12 shape holds (APL spell rows with citations + family
  gates; harness/prepull rows separated); rotfix items present (LnL arms,
  Sniper bypass, Explosive ranks, rule-7 opt-in, SoD Magma/FN, WF ICD,
  paladin ICD/SoD-window/TBC pull-hold).
- Spell-known gating + leveling: fail-visible discipline per class, pinned
  (hunter unlearned-never-prompts, shaman unknown-hides, paladin cold-hides).

## Validation (focused — full run.sh is the orchestrator's)

- hunter_state 1776, hunter_guide_state 1976, hunter_window_state 213,
  shaman_state 1073, shaman_guide_state 1570, weave_state 493,
  weave_range_state 149/0, paladin_state 1241, nextaction_state 631 — all PASS.
- luacheck 0/0 on classes/hunter.lua + tests/hunter_state.lua.
- Mutations (fresh /tmp/opencode copies, removed after): M1' name-legs neutered
  (FD/Readiness) -> 6 name legs red, all id legs green; M2 trap name resolution
  neutered -> 6 trap name legs red, suite completes (hardened `or {}` legs, no
  abort); M3 channel fallback reverted -> id-less channel leg red. Fixed tree
  re-ran green after.

## UNVERIFIED (in-client evidence that closes each)

- U1: name-carrying SUCCEEDED payloads occur on the operator's TBC client (F1
  is behavior-neutral if they never do).
- U2: FD at range clears cleanly + Readiness double-RF window in-client.
- U3: trap badge arms on a TBC trap cast.
- U4 (C3): hunter guide shows at range — needs the gated fix first.

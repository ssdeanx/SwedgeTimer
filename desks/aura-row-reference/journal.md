# Desk: aura-row-reference

## 2026-11-08 — Reference extraction + SwedgeTimer port map (task t2, attempt 5243edcf)

- **Worked on:** read `bench/briefs/brief_aura_row_reference_2026-11-08.md`; read the reference
  aura module in full (`/home/sam/SuperSwingTimer-WoW/SuperSwingTimer_Forever.lua`, 2156 lines:
  support/secrecy gates, the six per-class lists + candidate merge, `CreateAuraContainerFrame`,
  `CreateAuraGroupContainer`, `StyleAuraButton`, `GetAnchorBar`/`ComputeIconYOffset`/
  `ApplyContainerAnchors`, `IsForeverDebuffRowPopulated`, the 0.15 s `UpdateForeverAuraIcons`, the
  PLAYER_LOGIN/PLAYER_ENTERING_WORLD init retry), its `WIRING.md` §7, `SuperSwingTimer_UI.lua:2824`,
  `SuperSwingTimer_Constants.lua` (`ns.UnitAura`, `IsSecretValue`, `SafeNumber`, `HasNativeSwingTimer`),
  and the reference's own tests (`SuperSwingTimer_Tests.lua:3039-3140`). Confirmed the API side against
  `/home/sam/wow-ui-source` `origin/forever` (tip `eac30af5`, `1.60.1.70790`): Blueprint templates,
  `AuraContainerSortMethod/Direction`, `C_AuraContainerUtil`, `C_Secrets` predicates +
  `Enum.SecrecyLevel`, `C_UnitAuras` annotations (`RequiresNonSecretAura`,
  `SecretWhenUnitAuraRestricted`), `includeSpellIDs` privilege gating, `maxDuration` semantics,
  `AddAuraGroup` vs `AddAuraSlot`, flow-layout `secretwrap` sizing. Extracted the six class lists
  mechanically (bare `lua5.1` load of the reference file with an empty namespace table) and checked
  every id against the 1.15.9 `Spell.csv` as corroboration only. Read the target side: `bars.lua`
  helpers (939-966, 88-129, 592-700), `main.lua` `iter_hands`/`init_libs`/`post_init`/lazy bars,
  `hud.lua` init/creation/lockdown patterns, `config_presets.lua` class defaults, `option_tables.lua`
  HUD section + hidden-gate pattern, `SwedgeTimer.toc`, `tests/run.sh`, `tests/toc_check.lua`.
- **Current state:** `bench/aura_row_reference_2026-11-08.md` is on the bench (869 lines, 84 KB):
  reference code map with file:line, per-class id tables with provenance markers, the API
  confirmation table, the proposed `aura_icons.lua` port (gate expression, init seam, container
  config, fixed-band anchoring, options/defaults, TOC, 18 test cases + 8 mutation proofs, risks),
  the do-not-copy list, and a 13-row UNCONFIRMED in-client checklist. Four stale claims in the
  reference's own `WIRING.md`/comments are documented so the impl lane does not inherit them.
- **Findings that change downstream work:** (1) the client sizes aura containers through `secretwrap`
  (`Blizzard_CustomAuraContainer.lua:800`), so the debuff row must never be measured — the port uses a
  fixed reserved band; (2) `includeSpellIDs` only applies identity matching on helpful auras for
  player-controlled units and harmful auras on non-assistable units, so the debuff row is empty on
  friendly targets by design; (3) `UnitAura` does not exist on Forever ⇒ no classic fallback;
  (4) `27019` is reference-marked TBC-only ⇒ excluded (44 hunter debuff ids, not 45); (5) the
  reference's double merge of `FOREVER_NEW_ABILITY_CANDIDATES` into both rows is recommended to keep
  (18 ids, i.e. every candidate, in both sets; pinned by test); (6) `WIRING.md`'s 0.25 s throttle and its
  "classic updaters are NOT wrapped"/"native row shown only while secret" claims are contradicted by
  the code.
- **Next step:** the impl lane (T3) builds `aura_icons.lua` from §6; the operator closes the U1-U13
  in-client items (container creation, secret-safe combat behaviour, own-caster filtering, topmost-bar
  anchoring per class). No product file was touched by this lane (read-only); the desk's only outputs
  are this journal, the bench report and the done signal.
